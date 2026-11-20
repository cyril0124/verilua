"""Shared mem_direct post-step for the vl-verilator* wrappers.

Strips the wrapper-level `--vl-mem-direct[-include/-exclude]` flags from argv
and, after a successful verilator run, generates the mem_direct TUs from
`<Mdir>/V*___024root.h` and compiles them into `./libmem_direct.so`
(loaded at runtime via `VL_MEM_DIRECT_SO`). The offsetof chunk TUs are
compiled in parallel: they are the only files including the (potentially
huge) Verilator root header. See docs/reference/mem_direct.mdx.
"""

import argparse
import concurrent.futures
import glob
import os
import subprocess
import sys

RED = "\033[31m"
GREEN = "\033[32m"
RESET = "\033[0m"


def parse_args(argv, prefix):
    """Split wrapper argv into (namespace, verilator_args)."""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--vl-mem-direct", action="store_true")
    parser.add_argument("--vl-mem-direct-include", action="append", default=[])
    parser.add_argument("--vl-mem-direct-exclude", action="append", default=[])
    ns, remaining = parser.parse_known_args(argv)
    if (ns.vl_mem_direct_include or ns.vl_mem_direct_exclude) and not ns.vl_mem_direct:
        _die(prefix, "--vl-mem-direct-include/--vl-mem-direct-exclude require --vl-mem-direct")
    if ns.vl_mem_direct:
        # libmem_direct.so resolves Verilated symbols against the simulation
        # binary at dlopen; make sure the binary exports them even in flows
        # where verilator does not add -rdynamic itself (e.g. without --vpi).
        remaining = remaining + ["-LDFLAGS", "-rdynamic"]
    return ns, remaining


def post_step(ns, prefix, verilua_path, verilator, verilator_args):
    """Generate the entry table and compile libmem_direct.so. Dies on failure."""
    if not ns.vl_mem_direct:
        return

    # Verilator accepts both -Mdir and --Mdir; the last occurrence wins.
    mdir = "obj_dir"
    for i, arg in enumerate(verilator_args):
        if arg in ("-Mdir", "--Mdir") and i + 1 < len(verilator_args):
            mdir = verilator_args[i + 1]

    root_headers = sorted(glob.glob(os.path.join(mdir, "V*___024root.h")))
    if len(root_headers) != 1:
        _die(
            prefix,
            f"expected exactly one V*___024root.h under {mdir}, found {len(root_headers)}: {root_headers} "
            "(did verilator run codegen?)"
        )
    root_header = root_headers[0]
    root_class = os.path.basename(root_header)[:-len(".h")]

    gen_script = os.path.join(verilua_path, "src", "mem_direct_gen", "mem_direct_gen.py")
    if not os.path.isfile(gen_script):
        _die(prefix, f"mem_direct_gen.py not found: {gen_script}")

    out_cpp = "mem_direct_generated.cpp"
    out_so = "libmem_direct.so"

    gen_cmd = [sys.executable, gen_script, root_header, out_cpp, root_class]
    for pat in ns.vl_mem_direct_include:
        gen_cmd += ["--include", pat]
    for pat in ns.vl_mem_direct_exclude:
        gen_cmd += ["--exclude", pat]
    _run_or_die(prefix, gen_cmd, "mem_direct generate")

    verilator_root = subprocess.check_output([verilator, "--getenv", "VERILATOR_ROOT"]).decode().strip()
    if not verilator_root:
        _die(prefix, "`verilator --getenv VERILATOR_ROOT` returned empty")

    cxx = os.getenv("CXX", "g++")
    cxxflags = [
        "-std=c++20", "-O2", "-fPIC",
        f"-I{mdir}",
        f"-I{os.path.join(verilator_root, 'include')}",
        f"-I{os.path.join(verilator_root, 'include', 'vltstd')}",
    ]

    # Compile every generated TU in parallel, then link.
    srcs = sorted(glob.glob("mem_direct_generated*.cpp"))
    if not srcs:
        _die(prefix, "generator produced no mem_direct_generated*.cpp")
    objs = [s + ".o" for s in srcs]
    print(f"{prefix} mem_direct compile: {len(srcs)} TU(s), {os.cpu_count()} jobs max", flush=True)

    def _compile(src_obj):
        src, obj = src_obj
        cmd = [cxx, *cxxflags, "-c", src, "-o", obj]
        r = subprocess.run(cmd, capture_output=True, text=True)
        return src, cmd, r

    with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count()) as pool:
        for src, cmd, r in pool.map(_compile, zip(srcs, objs)):
            if r.returncode != 0:
                sys.stderr.write(r.stderr)
                _die(prefix, f"mem_direct compile failed for {src}: {' '.join(cmd)}")

    _run_or_die(prefix, [cxx, "-shared", "-Wl,-z,now", *objs, "-o", out_so], "mem_direct link")
    for obj in objs:
        os.remove(obj)

    print(f'''
{prefix} mem_direct library: {GREEN}{os.path.abspath(out_so)}{RESET}
{prefix} run with:
{GREEN}export VL_MEM_DIRECT_SO={os.path.abspath(out_so)}{RESET}
''', flush=True)


def _die(prefix, msg):
    print(f"{prefix} {RED}error:{RESET} {msg}", flush=True)
    sys.exit(1)


def _run_or_die(prefix, cmd_list, what):
    print(f"{prefix} {what}:\n{GREEN}{' '.join(cmd_list)}{RESET}", flush=True)
    rc = subprocess.call(cmd_list)
    if rc != 0:
        _die(prefix, f"{what} failed with exit code {rc}")
