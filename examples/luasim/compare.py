#!/usr/bin/env python3
"""Compare the Lua and SystemVerilog example models with identical drivers."""

import argparse
import csv
import difflib
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess


EXAMPLES = Path(__file__).resolve().parent
ROOT = EXAMPLES.parent.parent
CASES = {
    "comb_arbiter": {
        "top": "CombArbiter",
        "trace": "comb_trace.csv",
        "marker": "PASS: clockless priority arbitration",
        "rows": 13,
    },
    "axi4_memory": {
        "top": "AXI4Memory",
        "trace": "axi4_trace.csv",
        "marker": "PASS: AXI4Memory",
        "rows": None,
    },
}


def execute(command, environment, log_path, timeout, project):
    with log_path.open("w") as log:
        process = subprocess.Popen(
            command, cwd=project, env=environment,
            stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
        )
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise RuntimeError(f"Command timed out; see {log_path}") from None
    if code != 0:
        raise RuntimeError(f"Command exited {code}; see {log_path}")


def check_trace(example, content):
    rows = list(csv.DictReader(content.splitlines()))
    if not rows:
        raise RuntimeError(f"{example}: trace is empty")
    if example == "comb_arbiter":
        if len(rows) != CASES[example]["rows"]:
            raise RuntimeError(f"{example}: expected 13 checked input states")
    else:
        counts = dict.fromkeys(("aw", "w", "b", "ar", "r"), 0)
        for row in rows:
            if row["reset_n"] == "0":
                continue
            for channel in counts:
                if row[channel + "valid"] == "1" and row[channel + "ready"] == "1":
                    counts[channel] += 1
        expected = {"aw": 4, "w": 41, "b": 4, "ar": 7, "r": 50}
        if counts != expected:
            raise RuntimeError(f"{example}: unexpected handshake counts {counts}")
    return len(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--example", action="append", choices=tuple(CASES))
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--build-timeout", type=int, default=180)
    args = parser.parse_args()
    rtl_simulator = os.getenv("SIM") or "iverilog"
    if rtl_simulator not in ("iverilog", "vcs", "verilator"):
        parser.error("SIM must be iverilog, vcs or verilator")
    examples = list(dict.fromkeys(args.example or CASES))
    output = EXAMPLES / "build/comparison"
    output.mkdir(parents=True, exist_ok=True)

    environment = os.environ.copy()
    for key in ("SIM", "VL_CFG_FILE", "VL_LUA_SCRIPT", "VL_DUT_TOP", "VL_POST_INIT_SCRIPT",
                "VL_XMK_NO_INTERNAL_CLOCK", "VL_XMK_USE_NATIVE_CLOCK", "VL_XMK_USE_INERTIAL_PUT"):
        environment.pop(key, None)

    results = []
    for example in examples:
        project = EXAMPLES / example
        specification = CASES[example]
        baseline = None
        for simulator in ("luasim", rtl_simulator):
            directory = output / example / simulator
            directory.mkdir(parents=True, exist_ok=True)
            (directory / "difference.diff").unlink(missing_ok=True)
            run_env = environment.copy()
            run_env["SIM"] = simulator
            target = "test"
            top = "tb_top" if simulator == "luasim" else specification["top"]
            trace_path = project / "build" / simulator / top / specification["trace"]
            try:
                execute(["xmake", "f", "-y", "-P", "."],
                        run_env, directory / "configure.log", args.build_timeout, project)
                execute(["xmake", "build", "-P", ".", target],
                        run_env, directory / "build.log", args.build_timeout, project)
                trace_path.unlink(missing_ok=True)
                execute(["xmake", "run", "-P", ".", target],
                        run_env, directory / "run.log", args.timeout, project)
                if specification["marker"] not in (directory / "run.log").read_text():
                    raise RuntimeError("Self-check pass marker is missing")
                content = trace_path.read_text()
                (directory / specification["trace"]).write_text(content)
                count = check_trace(example, content)
                if baseline is None:
                    baseline = content
                elif content != baseline:
                    difference = difflib.unified_diff(
                        baseline.splitlines(keepends=True), content.splitlines(keepends=True),
                        fromfile="luasim", tofile=simulator,
                    )
                    (directory / "difference.diff").write_text("".join(difference))
                    raise RuntimeError(f"Sampled behavior differs; see {directory / 'difference.diff'}")
                result = dict(example=example, simulator=simulator, passed=True, samples=count,
                              trace=str(trace_path.relative_to(ROOT)))
            except (RuntimeError, OSError) as error:
                result = dict(example=example, simulator=simulator, passed=False, error=str(error))
                results.append(result)
                (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
                print(f"FAIL {example} {simulator}: {error}", flush=True)
                return 1
            results.append(result)
            (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
            print(f"PASS {example} {simulator}: {count} samples match", flush=True)

    sources = [EXAMPLES / "compare.py"]
    for example in examples:
        sources.extend(p for p in (EXAMPLES / example).iterdir() if p.suffix in (".lua", ".sv"))
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    (output / "sources.json").write_text(json.dumps(hashes, indent=2) + "\n")
    print("PASS: sampled Lua/SV behavior matches; this is not a formal equivalence proof")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
