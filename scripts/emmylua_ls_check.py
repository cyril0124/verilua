#!/usr/bin/env python3
"""Check Lua file(s) via emmylua_ls (stdio LSP, one-shot, no daemon).

Usage:
  ./scripts/emmylua_ls_check.py path/to/file.lua
  ./scripts/emmylua_ls_check.py path/to/dir
  ./scripts/emmylua_ls_check.py file1.lua file2.lua path/to/dir
  ./scripts/emmylua_ls_check.py path1 path2 --root /path/to/workspace
  ./scripts/emmylua_ls_check.py path --warnings-as-errors --no-color
  ./scripts/emmylua_ls_check.py --version

Exit: 0 no failing diagnostics, 1 has errors (or warnings with
--warnings-as-errors), 2 usage/runtime error.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import queue
import shutil
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import urllib.request
import zipfile
from pathlib import Path

SEVERITY = {1: "Error", 2: "Warning", 3: "Info", 4: "Hint"}
ROOT_MARKERS = (".emmyrc.json", ".emmyrc.lua", ".luarc.json", ".git")
RELEASE_BASE_URL = (
    "https://github.com/EmmyLuaLs/emmylua-analyzer-rust/releases/latest/download"
)
SCRIPT_VERSION = "1.0.1"

_USE_COLOR = False


class C:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RED = "\033[31m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    CYAN = "\033[36m"
    GREEN = "\033[32m"
    GRAY = "\033[90m"


def color(text: str, *codes: str) -> str:
    if not _USE_COLOR or not codes:
        return text
    return f"{''.join(codes)}{text}{C.RESET}"


def severity_style(sev_num) -> tuple[str, str]:
    name = SEVERITY.get(sev_num, str(sev_num))
    if sev_num == 1:
        return name, C.RED + C.BOLD
    if sev_num == 2:
        return name, C.YELLOW + C.BOLD
    if sev_num == 3:
        return name, C.BLUE
    if sev_num == 4:
        return name, C.GRAY
    return name, C.DIM


def encode(msg: dict) -> bytes:
    body = json.dumps(msg, ensure_ascii=False, separators=(",", ":")).encode()
    return f"Content-Length: {len(body)}\r\n\r\n".encode() + body


def find_root(start: Path, explicit: Path | None) -> tuple[Path, str]:
    if explicit is not None:
        root = explicit.resolve()
        hit = [m for m in ROOT_MARKERS if (root / m).exists()]
        if hit:
            return root, f"--root {root} (marker: {root / hit[0]})"
        return root, f"--root {root} (no marker file in root)"

    cur = (start if start.is_dir() else start.parent).resolve()
    for d in (cur, *cur.parents):
        for m in ROOT_MARKERS:
            marker = d / m
            if marker.exists():
                return d, str(marker)
    return cur, f"fallback parent (no marker found): {cur}"


def collect_lua_files(target: Path) -> list[Path]:
    target = target.resolve()
    if target.is_file():
        if target.suffix != ".lua":
            raise ValueError(f"not a .lua file: {target}")
        return [target]
    if target.is_dir():
        files = sorted(p for p in target.rglob("*.lua") if p.is_file())
        if not files:
            raise ValueError(f"no .lua files under: {target}")
        return files
    raise ValueError(f"path not found: {target}")


def collect_targets(targets: list[Path]) -> list[Path]:
    files = {path.resolve() for target in targets for path in collect_lua_files(target)}
    return sorted(files)


def user_install_path() -> Path:
    binary = "emmylua_ls.exe" if os.name == "nt" else "emmylua_ls"
    if os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
        return base / "emmylua_ls-check" / "bin" / binary
    return Path.home() / ".local" / "bin" / binary


def release_asset() -> str:
    system = platform.system().lower()
    machine = platform.machine().lower()

    if system == "linux":
        if machine in ("x86_64", "amd64"):
            libc = platform.libc_ver()[0].lower()
            if libc == "musl" or any(Path("/lib").glob("ld-musl-*.so.1")):
                return "emmylua_ls-linux-musl.tar.gz"
            return "emmylua_ls-linux-x64-glibc.2.17.tar.gz"
        if machine in ("aarch64", "arm64"):
            if platform.libc_ver()[0].lower() == "musl":
                raise RuntimeError("unsupported platform: Linux arm64 musl")
            return "emmylua_ls-linux-aarch64-glibc.2.17.tar.gz"
        if machine in ("riscv64", "riscv64gc"):
            return "emmylua_ls-linux-riscv64.tar.gz"

    if system == "darwin":
        if machine in ("x86_64", "amd64"):
            return "emmylua_ls-darwin-x64.tar.gz"
        if machine in ("aarch64", "arm64"):
            return "emmylua_ls-darwin-arm64.tar.gz"

    if system == "windows":
        if machine in ("x86_64", "amd64"):
            return "emmylua_ls-win32-x64.zip"
        if machine in ("x86", "i386", "i686"):
            return "emmylua_ls-win32-ia32.zip"
        if machine in ("aarch64", "arm64"):
            return "emmylua_ls-win32-arm64.zip"

    raise RuntimeError(f"unsupported platform: {platform.system()} {platform.machine()}")


def download(url: str, destination: Path) -> None:
    request = urllib.request.Request(
        url, headers={"User-Agent": f"emmylua-ls-check/{SCRIPT_VERSION}"}
    )
    with urllib.request.urlopen(request, timeout=60) as response, destination.open("wb") as out:
        total = int(response.headers.get("Content-Length", 0))
        downloaded = 0
        while chunk := response.read(1024 * 1024):
            out.write(chunk)
            downloaded += len(chunk)
            if total:
                print(
                    f"\rdownload: {downloaded / 1024 / 1024:.1f}/"
                    f"{total / 1024 / 1024:.1f} MiB",
                    end="",
                    file=sys.stderr,
                    flush=True,
                )
        if total:
            print(file=sys.stderr)


def extract_binary(archive: Path, destination: Path) -> None:
    binary_name = "emmylua_ls.exe" if os.name == "nt" else "emmylua_ls"
    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as package:
            matches = [name for name in package.namelist() if Path(name).name == binary_name]
            if len(matches) != 1:
                raise RuntimeError(f"release archive does not contain exactly one {binary_name}")
            with package.open(matches[0]) as src, destination.open("wb") as out:
                shutil.copyfileobj(src, out)
    else:
        with tarfile.open(archive, "r:gz") as package:
            matches = [member for member in package.getmembers() if Path(member.name).name == binary_name]
            if len(matches) != 1 or not matches[0].isfile():
                raise RuntimeError(f"release archive does not contain exactly one {binary_name}")
            src = package.extractfile(matches[0])
            if src is None:
                raise RuntimeError(f"cannot extract {binary_name}")
            with src, destination.open("wb") as out:
                shutil.copyfileobj(src, out)

    if destination.stat().st_size == 0:
        raise RuntimeError("downloaded emmylua_ls binary is empty")
    if os.name != "nt":
        destination.chmod(0o755)


def verify_binary(binary: Path) -> str:
    result = subprocess.run(
        [binary, "--version"],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    version = (result.stdout or result.stderr).strip()
    if result.returncode != 0 or not version.startswith("emmylua_ls "):
        raise RuntimeError(f"downloaded binary failed verification: {version or result.returncode}")
    return version


def install_emmylua_ls(target: Path) -> Path:
    asset = release_asset()
    url = f"{RELEASE_BASE_URL}/{asset}"
    print("emmylua_ls not found; installing official release", file=sys.stderr)
    print(f"download: {url}", file=sys.stderr)
    print(f"install: {target}", file=sys.stderr)

    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="emmylua-ls-install-") as tmp:
        archive = Path(tmp) / asset
        candidate = target.parent / f".{target.name}.{os.getpid()}.tmp"
        try:
            download(url, archive)
            extract_binary(archive, candidate)
            version = verify_binary(candidate)
            os.replace(candidate, target)
        finally:
            candidate.unlink(missing_ok=True)

    print(f"installed: {version}", file=sys.stderr)
    return target


def resolve_emmylua_ls() -> Path:
    found = shutil.which("emmylua_ls")
    if found:
        return Path(found)
    installed = user_install_path()
    if installed.is_file():
        return installed
    return install_emmylua_ls(installed)


class LspClient:
    """LSP over a pair of binary streams (stdio pipes)."""

    def __init__(self, reader, writer) -> None:
        self.reader = reader
        self.writer = writer
        self._id = 0
        self._pending: dict[int, dict] = {}
        self._notifs: queue.Queue = queue.Queue()
        self._buf = b""
        self._alive = True
        self._closed = threading.Event()
        self._reader_error: Exception | None = None
        threading.Thread(target=self._reader_loop, daemon=True).start()

    def _reader_loop(self) -> None:
        try:
            while self._alive:
                chunk = self.reader.read(65536)
                if not chunk:
                    break
                self._buf += chunk
                while True:
                    msg = self._try_parse()
                    if msg is None:
                        break
                    if "id" in msg and ("result" in msg or "error" in msg):
                        pending = self._pending.get(msg["id"])
                        if pending is not None:
                            pending["msg"] = msg
                            pending["event"].set()
                        else:
                            self._notifs.put(msg)
                    else:
                        self._notifs.put(msg)
        except Exception as error:
            self._reader_error = error
        finally:
            self._closed.set()
            for pending in list(self._pending.values()):
                pending["event"].set()

    def raise_if_closed(self) -> None:
        if self._closed.is_set():
            detail = f": {self._reader_error}" if self._reader_error else ""
            raise RuntimeError(f"emmylua_ls closed the LSP connection{detail}")

    def _try_parse(self) -> dict | None:
        if b"\r\n\r\n" not in self._buf:
            return None
        header, rest = self._buf.split(b"\r\n\r\n", 1)
        length = None
        for line in header.split(b"\r\n"):
            if line.lower().startswith(b"content-length:"):
                length = int(line.split(b":", 1)[1].strip())
        if length is None:
            raise RuntimeError(f"malformed LSP header: {header!r}")
        if len(rest) < length:
            return None
        body, self._buf = rest[:length], rest[length:]
        return json.loads(body.decode())

    def request(self, method: str, params, timeout: float = 60.0):
        self._id += 1
        rid = self._id
        pending = {"event": threading.Event(), "msg": None}
        self._pending[rid] = pending
        self.writer.write(
            encode({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        )
        self.writer.flush()
        deadline = time.monotonic() + timeout
        while not pending["event"].wait(0.05):
            handle_server_requests(self, self.drain(), show_progress=False)
            self.raise_if_closed()
            if time.monotonic() >= deadline:
                self._pending.pop(rid, None)
                raise TimeoutError(f"{method} timed out after {timeout}s")
        self._pending.pop(rid, None)
        msg = pending["msg"]
        if msg is None:
            self.raise_if_closed()
            raise RuntimeError(f"{method} ended without a response")
        if "error" in msg:
            raise RuntimeError(f"{method}: {msg['error']}")
        return msg["result"]

    def notify(self, method: str, params=None) -> None:
        msg: dict = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            msg["params"] = params
        self.writer.write(encode(msg))
        self.writer.flush()

    def reply(self, req_id, result=None) -> None:
        self.writer.write(encode({"jsonrpc": "2.0", "id": req_id, "result": result}))
        self.writer.flush()

    def drain(self, wait: float = 0.0) -> list[dict]:
        end = time.time() + wait
        out: list[dict] = []
        while True:
            timeout = max(0.0, end - time.time()) if wait else 0.0
            try:
                out.append(self._notifs.get(timeout=timeout))
            except queue.Empty:
                break
        return out

    def close(self) -> None:
        self._alive = False


def handle_server_requests(
    client: LspClient, msgs: list[dict], show_progress: bool = True
) -> bool:
    progress_end = False
    for msg in msgs:
        method = msg.get("method")
        if method in ("window/workDoneProgress/create", "client/registerCapability"):
            client.reply(msg["id"], None)
        elif method == "workspace/configuration":
            items = msg.get("params", {}).get("items", [{}])
            client.reply(msg["id"], [{}] * len(items))
        elif method == "$/progress":
            value = msg.get("params", {}).get("value", {})
            kind = value.get("kind")
            text = value.get("message") or value.get("title") or ""
            if show_progress and (kind or text):
                print(f"[index {kind}] {text}", file=sys.stderr, flush=True)
            if kind == "end":
                progress_end = True
    return progress_end


def rel_display(path: Path, root: Path) -> str:
    try:
        return str(path.resolve().relative_to(root.resolve()))
    except ValueError:
        return str(path.resolve())


def filter_items(items: list[dict]) -> list[dict]:
    return [d for d in items if d.get("severity") != 4]


def count_by_severity(items: list[dict]) -> dict[int, int]:
    counts: dict[int, int] = {1: 0, 2: 0, 3: 0, 4: 0}
    for d in items:
        sev = d.get("severity")
        counts[sev] = counts.get(sev, 0) + 1
    return counts


def print_diagnostics(
    path: Path, root: Path, items: list[dict], *, verbose: bool, need_blank: bool
) -> tuple[list[dict], bool]:
    """Print diagnostics. Return (raw items, whether something was printed)."""
    shown = filter_items(items)
    rel_s = rel_display(path, root)

    if not shown:
        if verbose:
            if need_blank:
                print()
            print(
                f"{color('---', C.DIM)} {color(rel_s, C.CYAN)} "
                f"{color('[clean]', C.GREEN)}"
            )
            return items, True
        return items, False

    if need_blank:
        print()
    print(
        f"{color('---', C.DIM)} {color(rel_s, C.CYAN, C.BOLD)} "
        f"{color(f'[{len(shown)}]', C.YELLOW)}"
    )
    for d in shown:
        start = d.get("range", {}).get("start", {})
        line = start.get("line", 0) + 1
        col = start.get("character", 0) + 1
        sev_name, sev_code = severity_style(d.get("severity"))
        code = d.get("code", "")
        code_s = color(f"[{code}]", C.DIM) if code != "" else ""
        loc = color(f"@{line}:{col}", C.GRAY)
        msg = d.get("message", "").rstrip()
        print(f"  {color(sev_name, sev_code)}: {msg}  {code_s} {loc}".rstrip())
    return items, True


def _plural(n: int, one: str, many: str | None = None) -> str:
    if n == 1:
        return f"{n} {one}"
    return f"{n} {many or one + 's'}"


def print_summary(all_items: list[dict], file_count: int) -> tuple[int, int]:
    counts = count_by_severity(all_items)
    errors, warnings = counts.get(1, 0), counts.get(2, 0)
    infos, hints = counts.get(3, 0), counts.get(4, 0)
    total_all = errors + warnings + infos + hints
    print()
    parts = [
        color(_plural(errors, "error"), C.RED, C.BOLD),
        color(_plural(warnings, "warning"), C.YELLOW, C.BOLD),
        color(_plural(infos, "info", "info"), C.BLUE),
        color(_plural(hints, "hint"), C.GRAY),
    ]
    print(f"Summary: {total_all} diagnostics in {file_count} files ({', '.join(parts)})")
    return errors, warnings


def diagnostic_exit_code(errors: int, warnings: int, warnings_as_errors: bool) -> int:
    return int(errors > 0 or (warnings_as_errors and warnings > 0))


def wait_index(client: LspClient, wait_index_s: float, n_files: int) -> bool:
    print(
        color(
            f"indexing workspace (check {n_files} file(s); "
            f"wait_index={'forever' if wait_index_s <= 0 else f'{wait_index_s}s'})...",
            C.DIM,
        ),
        file=sys.stderr,
        flush=True,
    )
    progress_end = False
    deadline = None if wait_index_s <= 0 else (time.time() + wait_index_s)
    while not progress_end:
        client.raise_if_closed()
        if deadline is not None and time.time() >= deadline:
            break
        progress_end = (
            handle_server_requests(client, client.drain(wait=0.2), show_progress=True)
            or progress_end
        )
    return progress_end


def check_files(
    files: list[Path],
    root: Path,
    wait_index_s: float,
    verbose: bool,
    warnings_as_errors: bool,
) -> int:
    ls_bin = resolve_emmylua_ls()

    root = root.resolve()
    root_uri = root.as_uri()

    t0 = time.perf_counter()
    proc = subprocess.Popen(
        [str(ls_bin), "-c", "stdio", "--editor", "neovim", "--log-level", "error"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        bufsize=0,
    )
    assert proc.stdin is not None and proc.stdout is not None

    client = LspClient(proc.stdout, proc.stdin)
    try:
        client.request(
            "initialize",
            {
                "processId": os.getpid(),
                "rootUri": root_uri,
                "rootPath": str(root),
                "capabilities": {
                    "window": {"workDoneProgress": True},
                    "textDocument": {
                        "diagnostic": {},
                        "synchronization": {"didOpen": True},
                        "publishDiagnostics": {},
                    },
                    "workspace": {
                        "workspaceFolders": True,
                        "configuration": True,
                        "diagnostics": {"refreshSupport": True},
                    },
                },
                "workspaceFolders": [{"uri": root_uri, "name": root.name}],
                "clientInfo": {"name": "emmylua_ls_check", "version": SCRIPT_VERSION},
            },
            timeout=60,
        )
        client.notify("initialized", {})

        if not wait_index(client, wait_index_s, len(files)):
            print(
                f"error: workspace index not finished within {wait_index_s}s\n"
                f"  emmylua_ls indexes the whole workspace root, not only the check path.\n"
                f"  retry: --wait-index 0\n"
                f"  or shrink root: --root <dir>",
                file=sys.stderr,
            )
            return 2

        t_index = time.perf_counter() - t0
        print(color(f"index complete ({t_index:.1f}s)", C.GREEN), file=sys.stderr, flush=True)
        handle_server_requests(client, client.drain(wait=0.05), show_progress=verbose)

        # Fast path: no didOpen of file bodies — workspace already loaded from disk.
        # Prefer per-file textDocument/diagnostic (workspace/diagnostic is much slower).
        pull_timeout = 120.0
        all_items: list[dict] = []
        printed_any = False
        for path in files:
            handle_server_requests(client, client.drain(wait=0.0), show_progress=verbose)
            result = client.request(
                "textDocument/diagnostic",
                {"textDocument": {"uri": path.resolve().as_uri()}},
                timeout=pull_timeout,
            )
            items = result.get("items", []) if isinstance(result, dict) else []
            raw, did_print = print_diagnostics(
                path, root, items, verbose=verbose, need_blank=printed_any
            )
            all_items.extend(raw)
            printed_any = printed_any or did_print

        errors, warnings = print_summary(all_items, len(files))
        total = time.perf_counter() - t0
        print(color(f"elapsed: {total:.1f}s (index {t_index:.1f}s)", C.DIM), file=sys.stderr)
        return diagnostic_exit_code(errors, warnings, warnings_as_errors)
    finally:
        try:
            client.request("shutdown", None, timeout=5)
            client.notify("exit")
        except Exception:
            pass
        client.close()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Check Lua files or directories with emmylua_ls (stdio LSP, one-shot)"
    )
    p.add_argument("--version", action="version", version=f"%(prog)s {SCRIPT_VERSION}")
    p.add_argument(
        "paths",
        nargs="+",
        type=Path,
        help="One or more Lua files/directories to check",
    )
    p.add_argument(
        "--root",
        type=Path,
        default=None,
        help="Workspace root (default: nearest .emmyrc.json/.git)",
    )
    p.add_argument(
        "--wait-index",
        type=float,
        default=0.0,
        help="Seconds to wait for workspace index (default: 0 = forever)",
    )
    p.add_argument("-v", "--verbose", action="store_true")
    p.add_argument(
        "--warnings-as-errors",
        action="store_true",
        help="Return 1 when warnings are found (errors always return 1)",
    )
    p.add_argument("--no-color", action="store_true", help="Disable ANSI colors")
    p.add_argument("--color", action="store_true", help="Force ANSI colors")
    args = p.parse_args(argv)

    global _USE_COLOR
    if args.no_color:
        _USE_COLOR = False
    elif args.color:
        _USE_COLOR = True
    else:
        _USE_COLOR = sys.stdout.isatty()

    targets = [path.resolve() for path in args.paths]
    try:
        files = collect_targets(targets)
        if args.root is not None:
            root, root_marker = find_root(targets[0], args.root)
        else:
            detected = [(target, *find_root(target, None)) for target in targets]
            roots = {root for _, root, _ in detected}
            if len(roots) != 1:
                details = "\n".join(f"  {target} -> {root}" for target, root, _ in detected)
                raise ValueError(
                    "paths resolve to different workspace roots; use --root to choose one:\n"
                    f"{details}"
                )
            _, root, root_marker = detected[0]
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    print(color(f"root: {root}", C.DIM), flush=True)
    print(color(f"marker: {root_marker}", C.DIM), flush=True)
    print(color(f"files: {len(files)}", C.DIM), flush=True)
    print(flush=True)

    if args.verbose:
        for target in targets:
            print(f"target={target}", file=sys.stderr)

    try:
        return check_files(
            files=files,
            root=root,
            wait_index_s=args.wait_index,
            verbose=args.verbose,
            warnings_as_errors=args.warnings_as_errors,
        )
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
