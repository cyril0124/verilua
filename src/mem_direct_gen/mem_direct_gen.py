#!/usr/bin/env python3
"""Generate the mem_direct entry table from a Verilator root header.

Parses `V<top>___024root.h`, extracts design-state members (CData/SData/IData/
QData/VlWide/VlUnpacked), and emits a C++ TU that is compiled into a standalone
`libmem_direct.so` loaded at runtime via `VL_MEM_DIRECT_SO` (see
docs/reference/mem_direct.mdx).

Usage:
    mem_direct_gen.py <root_header> <out_cpp> <root_class> \
        [--include PAT]... [--exclude PAT]...

Outputs `<out_cpp>` (entry metadata, no root-header include) plus
`<out_stem>_chunk<i>.cpp` offset TUs (the only files that include the root
header; kept small so huge designs compile fast and in parallel).

Example:
    python3 mem_direct_gen.py \
        sim_build/Vtb_top___024root.h mem_direct_generated.cpp Vtb_top___024root \
        --include 'glob:tb_top.u_dut.*' \
        --exclude 're:.*__GEN_.*'

    g++ -std=c++20 -O2 -fPIC -shared \
        -Isim_build -I$(verilator --getenv VERILATOR_ROOT)/include \
        mem_direct_generated*.cpp -o libmem_direct.so

Filter patterns match hierarchical names (e.g. `tb_top.u_top.reg32`): a bare
string or `glob:` prefix uses shell-style globbing (exact match when it has no
wildcard), `re:` uses Python `re.search`. Includes are applied first, then
excludes; a configured include matching zero fields fails the run. Names
starting with `__`, `unnamedblk*`, and `____Vxrand*` are always skipped.

Callers: the xmake verilua rule (`verilua.verilator_mem_direct*` values) and
`vl-verilator --vl-mem-direct[-include/-exclude]` run this automatically.
"""

from __future__ import annotations

import argparse
import fnmatch
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional, Sequence


BASIC_TYPES = ("CData", "SData", "IData", "QData", "WData")


@dataclass
class Field:
    raw_name: str
    hier_name: str
    type_name: str
    rtl_width: int
    array_size: int


def field_to_hier(raw: str) -> str:
    s = re.sub(r"__BRA__(\d+)__KET__", r"[\1]", raw)
    return s.replace("__DOT__", ".")


def should_skip(raw_name: str) -> bool:
    if raw_name.startswith("__"):
        return True
    if "unnamedblk" in raw_name:
        return True
    if "____Vxrand" in raw_name:
        return True
    return False


def parse_header(text: str) -> List[Field]:
    fields: List[Field] = []

    def add_basic(type_name: str, range_s: str, raw_name: str, array_size: int = 0) -> None:
        if should_skip(raw_name):
            return
        m = re.match(r"(\d+):(\d+)", range_s)
        if not m:
            raise ValueError(f"bad range for {raw_name}: {range_s}")
        hi, lo = int(m.group(1)), int(m.group(2))
        fields.append(
            Field(
                raw_name=raw_name,
                hier_name=field_to_hier(raw_name),
                type_name=type_name,
                rtl_width=hi - lo + 1,
                array_size=array_size,
            )
        )

    for type_name in BASIC_TYPES:
        pat = re.compile(
            rf"{type_name}/\*(\d+:\d+)\*/\s+([A-Za-z0-9_]+)\s*;"
        )
        for range_s, raw_name in pat.findall(text):
            add_basic(type_name, range_s, raw_name)

    for n, range_s, raw_name in re.findall(
        r"VlWide<(\d+)>\s*/\*(\d+:\d+)\*/\s+([A-Za-z0-9_]+)\s*;", text
    ):
        if should_skip(raw_name):
            continue
        m = re.match(r"(\d+):(\d+)", range_s)
        assert m
        hi, lo = int(m.group(1)), int(m.group(2))
        fields.append(
            Field(
                raw_name=raw_name,
                hier_name=field_to_hier(raw_name),
                type_name=f"VlWide<{n}>",
                rtl_width=hi - lo + 1,
                array_size=0,
            )
        )

    for type_name in BASIC_TYPES:
        pat = re.compile(
            rf"VlUnpacked<{type_name}/\*(\d+:\d+)\*/\s*,\s*(\d+)>\s+([A-Za-z0-9_]+)\s*;"
        )
        for range_s, arr, raw_name in pat.findall(text):
            add_basic(type_name, range_s, raw_name, array_size=int(arr))

    for n, range_s, arr, raw_name in re.findall(
        r"VlUnpacked<VlWide<(\d+)>\s*/\*(\d+:\d+)\*/\s*,\s*(\d+)>\s+([A-Za-z0-9_]+)\s*;",
        text,
    ):
        if should_skip(raw_name):
            continue
        m = re.match(r"(\d+):(\d+)", range_s)
        assert m
        hi, lo = int(m.group(1)), int(m.group(2))
        fields.append(
            Field(
                raw_name=raw_name,
                hier_name=field_to_hier(raw_name),
                type_name=f"VlWide<{n}>",
                rtl_width=hi - lo + 1,
                array_size=int(arr),
            )
        )

    # Dedup by raw_name, keep first
    seen = set()
    unique: List[Field] = []
    for f in fields:
        if f.raw_name in seen:
            continue
        seen.add(f.raw_name)
        unique.append(f)
    return unique


def compile_pattern(pat: str) -> re.Pattern[str]:
    """Compile a user pattern against hier names.

    - re:<regex>     -> re.search
    - glob:<glob>    -> fullmatch via fnmatch
    - bare           -> default glob (no wildcard => exact)
    """
    if pat.startswith("re:"):
        return re.compile(pat[3:])
    if pat.startswith("glob:"):
        g = pat[5:]
        return re.compile(fnmatch.translate(g))
    # bare: default glob
    return re.compile(fnmatch.translate(pat))


def is_regex_pattern(pat: str) -> bool:
    return pat.startswith("re:")


def matches(name: str, compiled: re.Pattern[str], original: str) -> bool:
    if is_regex_pattern(original):
        return compiled.search(name) is not None
    return compiled.fullmatch(name) is not None


def apply_filters(
    fields: Sequence[Field],
    includes: Sequence[str],
    excludes: Sequence[str],
) -> tuple[List[Field], int, int, int]:
    """Return (final_fields, n_parsed, n_after_include, n_after_exclude)."""
    n_parsed = len(fields)
    cur: List[Field] = list(fields)

    if includes:
        inc = [(p, compile_pattern(p)) for p in includes]
        cur = [f for f in cur if any(matches(f.hier_name, c, p) for p, c in inc)]
    n_after_include = len(cur)

    if excludes:
        exc = [(p, compile_pattern(p)) for p in excludes]
        cur = [f for f in cur if not any(matches(f.hier_name, c, p) for p, c in exc)]
    n_after_exclude = len(cur)

    return cur, n_parsed, n_after_include, n_after_exclude


def field_mem_bytes(f: Field) -> int:
    """Per-element byte size, derived from Verilator's fixed type ABI.

    Computed in Python instead of emitting `sizeof(...)` so the generated TUs
    do not need one member-name lookup per field (very slow for GCC on root
    classes with hundreds of thousands of members).
    """
    t = f.type_name
    if t == "CData":
        return 1
    if t == "SData":
        return 2
    if t in ("IData", "WData"):
        return 4
    if t == "QData":
        return 8
    m = re.match(r"VlWide<(\d+)>$", t)
    if m:
        return 4 * int(m.group(1))
    raise ValueError(f"unknown type for {f.raw_name}: {t}")


# Fields per offset-chunk TU. Each chunk TU includes the (potentially huge)
# Verilator root header; keeping chunks small bounds per-TU compile time and
# lets the build compile them in parallel.
CHUNK_SIZE = 2048


def emit_cpp(fields: Sequence[Field], root_class: str, out_path: Path) -> List[Path]:
    """Write the main TU plus offsetof chunk TUs; return all written paths.

    Layout:
      - `<out>.cpp`: entry table (no root-header include -> compiles instantly),
        accessors, prepare().
      - `<out>_chunk<i>.cpp`: `const uint64_t g_md_off_<i>[]` filled with
        offsetof() values; the only TUs that include the root header.
    """
    written: List[Path] = []
    stem = out_path.with_suffix("")

    assert root_class.endswith("___024root"), f"unexpected root class name: {root_class}"
    model_class = root_class[: -len("___024root")]
    syms_class = model_class + "__Syms"

    # Remove stale chunk TUs from a previous run (field count may shrink).
    for old in sorted(out_path.parent.glob(f"{stem.name}_chunk*.cpp")):
        old.unlink()

    n_chunks = max(1, (len(fields) + CHUNK_SIZE - 1) // CHUNK_SIZE)

    for ci in range(n_chunks):
        chunk = fields[ci * CHUNK_SIZE:(ci + 1) * CHUNK_SIZE]
        lines: List[str] = []
        w = lines.append
        w("// Auto-generated by mem_direct_gen.py. Do not edit.")
        if ci == 0:
            # Syms header pulls in the root header and is needed by the
            # self-locating mem_direct_base() below.
            w(f'#include "{syms_class}.h"')
            w('#include "verilated.h"')
            w('#include "verilated_syms.h"')
        else:
            w(f'#include "{root_class}.h"')
        w("#include <cstddef>")
        w("#include <cstdint>")
        w("")
        w("// Verilator root members are non-standard-layout; offsetof on them is")
        w("// conditionally-supported and fine on GCC/Clang.")
        w("#if defined(__GNUC__) || defined(__clang__)")
        w('#pragma GCC diagnostic ignored "-Winvalid-offsetof"')
        w("#endif")
        w("")
        w(f"extern const uint64_t mem_direct_off_{ci}[];")
        w(f"const uint64_t mem_direct_off_{ci}[] = {{")
        for f in chunk:
            w(f"    offsetof({root_class}, {f.raw_name}),")
        w("};")
        if ci == 0:
            w("")
            w("// Self-locating design-state base pointer. Any DPI/VPI scope registered")
            w("// by the model points back to its symbol table, and the root object is")
            w("// embedded by value in it. The Verilated symbols resolve against the")
            w("// simulation binary when this library is dlopen'ed (verilated.mk links")
            w("// the binary with -rdynamic). Assumes a single Verilated model per")
            w("// process; returns 0 before the model is constructed.")
            w('extern "C" uint64_t mem_direct_base() {')
            w("    const VerilatedScopeNameMap *scopes = Verilated::scopeNameMap();")
            w("    if (!scopes || scopes->empty()) return 0;")
            w("    const VerilatedScope *scope = scopes->begin()->second;")
            w(f"    auto *syms = static_cast<{syms_class} *>(scope->symsp());")
            w("    return reinterpret_cast<uint64_t>(&syms->TOP);")
            w("}")
        chunk_path = out_path.parent / f"{stem.name}_chunk{ci}.cpp"
        chunk_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        written.append(chunk_path)

    lines = []
    w = lines.append
    w("// Auto-generated by mem_direct_gen.py. Do not edit.")
    w("// Entry metadata only; offsetof values live in the *_chunk*.cpp TUs so")
    w("// this TU never includes the (huge) Verilator root header.")
    w("#include <cstdint>")
    w("")
    w("struct mem_direct_entry {")
    w("    const char *name;")
    w("    const char *raw_name;")
    w("    uint32_t rtl_width;")
    w("    uint32_t mem_bytes;")
    w("    uint64_t array_size;")
    w("};")
    w("")
    w("static const mem_direct_entry g_md_entries[] = {")
    for f in fields:
        w(
            f'    {{"{f.hier_name}", "{f.raw_name}", {f.rtl_width}, '
            f"{field_mem_bytes(f)}, {f.array_size}ULL}},"
        )
    w("};")
    w(f"static const int g_md_count = {len(fields)};")
    w(f"static const int g_md_chunk_size = {CHUNK_SIZE};")
    w("static int g_md_ready = 0;")
    w("")
    for ci in range(n_chunks):
        w(f"extern const uint64_t mem_direct_off_{ci}[];")
    w("")
    w("static const uint64_t *const g_md_off_chunks[] = {")
    for ci in range(n_chunks):
        w(f"    mem_direct_off_{ci},")
    w("};")
    w("")
    w('extern "C" int mem_direct_prepare(void *base_ptr) {')
    w("    if (!base_ptr) return -1;")
    w("    g_md_ready = 1;")
    w("    return g_md_count;")
    w("}")
    w("")
    w('extern "C" int mem_direct_count() { return g_md_ready ? g_md_count : 0; }')
    w("")
    w('extern "C" const char *mem_direct_entry_name(int i) {')
    w("    if (!g_md_ready || i < 0 || i >= g_md_count) return nullptr;")
    w("    return g_md_entries[i].name;")
    w("}")
    w("")
    w('extern "C" uint64_t mem_direct_entry_offset(int i) {')
    w("    if (!g_md_ready || i < 0 || i >= g_md_count) return 0;")
    w("    return g_md_off_chunks[i / g_md_chunk_size][i % g_md_chunk_size];")
    w("}")
    w("")
    w('extern "C" uint32_t mem_direct_entry_mem_bytes(int i) {')
    w("    if (!g_md_ready || i < 0 || i >= g_md_count) return 0;")
    w("    return g_md_entries[i].mem_bytes;")
    w("}")
    w("")
    w('extern "C" uint32_t mem_direct_entry_rtl_width(int i) {')
    w("    if (!g_md_ready || i < 0 || i >= g_md_count) return 0;")
    w("    return g_md_entries[i].rtl_width;")
    w("}")
    w("")
    w('extern "C" uint64_t mem_direct_entry_array_size(int i) {')
    w("    if (!g_md_ready || i < 0 || i >= g_md_count) return 0;")
    w("    return g_md_entries[i].array_size;")
    w("}")
    w("")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    written.insert(0, out_path)
    return written


def normalize_list(values: Optional[Iterable[str]]) -> List[str]:
    if not values:
        return []
    out: List[str] = []
    for v in values:
        if v is None:
            continue
        s = str(v).strip()
        if s:
            out.append(s)
    return out


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="Generate mem_direct_generated.cpp from Verilator root header")
    ap.add_argument("root_header", type=Path, help="Path to V*___024root.h")
    ap.add_argument("out_cpp", type=Path, help="Output mem_direct_generated.cpp")
    ap.add_argument("root_class", help="C++ root class name, e.g. Vtb_top___024root")
    ap.add_argument(
        "--include",
        action="append",
        default=[],
        help="Include pattern (repeatable). glob:/re:/bare-glob. Empty list = all.",
    )
    ap.add_argument(
        "--exclude",
        action="append",
        default=[],
        help="Exclude pattern (repeatable). Applied after include.",
    )
    args = ap.parse_args(argv)

    includes = normalize_list(args.include)
    excludes = normalize_list(args.exclude)

    if not args.root_header.is_file():
        print(f"[mem_direct_gen] root header not found: {args.root_header}", file=sys.stderr)
        return 2

    text = args.root_header.read_text(encoding="utf-8", errors="replace")
    fields = parse_header(text)
    if not fields and not includes:
        # No fields at all (and not a filter miss): hard fail like old lua gen
        print(f"[mem_direct_gen] no fields parsed from {args.root_header}", file=sys.stderr)
        return 1

    final, n_parsed, n_inc, n_exc = apply_filters(fields, includes, excludes)

    print(
        f"[mem_direct_gen] parsed={n_parsed} after_include={n_inc} "
        f"after_exclude={n_exc} final={len(final)}"
    )
    if includes:
        print(f"[mem_direct_gen] include({len(includes)}): {includes[:5]}{'...' if len(includes) > 5 else ''}")
    if excludes:
        print(f"[mem_direct_gen] exclude({len(excludes)}): {excludes[:5]}{'...' if len(excludes) > 5 else ''}")
    for f in final[:8]:
        print(f"[mem_direct_gen]   sample: {f.hier_name}")
    if len(final) > 8:
        print(f"[mem_direct_gen]   ... ({len(final) - 8} more)")

    if includes and len(final) == 0:
        print(
            "[mem_direct_gen] ERROR: include patterns matched 0 fields "
            f"(parsed={n_parsed}). Check --include/--exclude.",
            file=sys.stderr,
        )
        return 1

    if len(final) == 0:
        print(f"[mem_direct_gen] no fields left after filters from {args.root_header}", file=sys.stderr)
        return 1

    args.out_cpp.parent.mkdir(parents=True, exist_ok=True)
    written = emit_cpp(final, args.root_class, args.out_cpp)
    print(f"[mem_direct_gen] {len(final)} fields -> {len(written)} files ({args.out_cpp} + {len(written) - 1} offset chunk(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
