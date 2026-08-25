#!/usr/bin/env python3
"""Format Lua files/directories with EmmyLua CodeFormat.

Usage:
  ./scripts/emmylua_format.py path/to/file.lua
  ./scripts/emmylua_format.py path/to/dir
  ./scripts/emmylua_format.py file1.lua file2.lua path/to/dir
  ./scripts/emmylua_format.py --check path/to/dir
  ./scripts/emmylua_format.py --no-color path/to/dir
  ./scripts/emmylua_format.py --version

The wrapper installs the official CodeFormat release when it is not available.
Exit: 0 for success, 1 for --check differences, and 2 for wrapper errors.
"""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path

RELEASE_BASE_URL = (
    "https://github.com/CppCXY/EmmyLuaCodeStyle/releases/latest/download"
)
SCRIPT_VERSION = "1.0.1"


def user_install_path() -> Path:
    binary = "CodeFormat.exe" if os.name == "nt" else "CodeFormat"
    if os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
        return base / "emmylua-code-style" / "bin" / binary
    return Path.home() / ".local" / "bin" / binary


def release_asset() -> str:
    system = platform.system().lower()
    machine = platform.machine().lower()

    if system == "linux":
        if machine in ("x86_64", "amd64"):
            return "linux-x64.tar.gz"
        if machine in ("aarch64", "arm64"):
            return "linux-aarch64.tar.gz"

    if system == "darwin":
        if machine in ("x86_64", "amd64"):
            return "darwin-x64.tar.gz"
        if machine in ("aarch64", "arm64"):
            return "darwin-arm64.tar.gz"

    if system == "windows":
        if machine in ("x86_64", "amd64"):
            return "win32-x64.zip"

    raise RuntimeError(f"unsupported platform: {platform.system()} {platform.machine()}")


def download(url: str, destination: Path) -> None:
    request = urllib.request.Request(
        url, headers={"User-Agent": f"emmylua-format/{SCRIPT_VERSION}"}
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
    binary_name = "CodeFormat.exe" if os.name == "nt" else "CodeFormat"
    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as package:
            matches = [info for info in package.infolist() if Path(info.filename).name == binary_name]
            if len(matches) != 1 or matches[0].is_dir():
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
        raise RuntimeError("downloaded CodeFormat binary is empty")
    if os.name != "nt":
        destination.chmod(0o755)


def verify_binary(binary: Path) -> str:
    result = subprocess.run(
        [binary, "--help"],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    output = (result.stdout or result.stderr).strip()
    if not output.startswith("Usage:") or "CodeFormat [check/format/rangeformat]" not in output:
        raise RuntimeError(f"downloaded binary failed verification: {output or result.returncode}")
    return "CodeFormat"


def install_codeformat(target: Path) -> Path:
    asset = release_asset()
    url = f"{RELEASE_BASE_URL}/{asset}"
    print("CodeFormat not found; installing official EmmyLua CodeStyle release", file=sys.stderr)
    print(f"download: {url}", file=sys.stderr)
    print(f"install: {target}", file=sys.stderr)

    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="emmylua-codeformat-install-") as tmp:
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


def resolve_codeformat() -> Path:
    found = shutil.which("CodeFormat")
    if found:
        return Path(found)
    installed = user_install_path()
    if installed.is_file():
        return installed
    return install_codeformat(installed)


def collect_paths(raw_paths: list[Path]) -> list[Path]:
    paths: set[Path] = set()
    for raw in raw_paths:
        path = raw.resolve()
        if not path.exists():
            raise ValueError(f"path not found: {path}")
        if path.is_file() and path.suffix.lower() not in (".lua", ".luau"):
            raise ValueError(f"format file must be .lua or .luau: {path}")
        if path.is_dir() and not any(
            candidate.is_file() and candidate.suffix.lower() in (".lua", ".luau")
            for candidate in path.rglob("*")
        ):
            raise ValueError(f"no Lua files found: {path}")
        paths.add(path)
    return [
        path
        for path in sorted(paths)
        if not any(parent != path and parent.is_dir() and parent in path.parents for parent in paths)
    ]


def run_codeformat(binary: Path, path: Path, check: bool) -> int:
    # Do not pass -d/--detect-config: walking the repo can hit broken symlink loops
    # (e.g. a stale luarocks lockfile.lfs under luajit/) and abort CodeFormat.
    selector = "-w" if path.is_dir() else "-f"
    if check:
        command = [str(binary), "check", selector, str(path), "--diagnosis-as-error"]
    else:
        command = [str(binary), "format", selector, str(path), "-ow"]
    return subprocess.run(command, check=False).returncode


def colored(text: str, code: str, enabled: bool) -> str:
    return f"\033[{code}m{text}\033[0m" if enabled else text


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Format Lua files/directories with EmmyLua CodeFormat")
    parser.add_argument("--version", action="version", version=f"%(prog)s {SCRIPT_VERSION}")
    parser.add_argument("paths", nargs="+", type=Path, help="Lua files/directories to format")
    parser.add_argument("--check", action="store_true", help="Check formatting without modifying files")
    color_group = parser.add_mutually_exclusive_group()
    color_group.add_argument("--no-color", action="store_true", help="Disable colored output")
    color_group.add_argument("--color", action="store_true", help="Force colored output")
    args = parser.parse_args(argv)

    try:
        paths = collect_paths(args.paths)
        codeformat = resolve_codeformat()
        use_color = args.color or (not args.no_color and sys.stdout.isatty())
        action = "Checking" if args.check else "Formatting"
        failed = False
        for path in paths:
            print(f"{colored(action + ':', '36', use_color)} {path}", flush=True)
            status = run_codeformat(codeformat, path, args.check)
            if status != 0:
                if args.check:
                    failed = True
                else:
                    return 2
        return 1 if failed else 0
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
