#!/usr/bin/env python3
"""CAD commands: vlog, vsim, dc_shell -f runsynth.tcl. Output goes to the console."""

import argparse
import glob
import os
import shutil
import subprocess
import sys
from pathlib import Path


# Project directory. An absolute --proj is used as-is; otherwise it is under $HOME.
def project(rel):
    path = Path(rel)
    return path if path.is_absolute() else Path.home() / path


# First executable match from the patterns, then PATH.
def tool(name, patterns):
    for pattern in patterns:
        for hit in sorted(glob.glob(pattern)):
            if os.path.isfile(hit) and os.access(hit, os.X_OK):
                return hit
    found = shutil.which(name)
    if not found:
        sys.exit(f"{name} not found. Look under /usr/local/mgc or /usr/local/synopsys.")
    return found


# Questa binary (vlib, vlog, or vsim).
def questa(name):
    return tool(name, [
        f"/usr/local/mgc/questasim/bin/{name}",
        f"/usr/local/mgc/*/questasim/bin/{name}",
        f"/usr/local/mgc/questa*/bin/{name}",
    ])


# Design Compiler binary.
def dc_shell():
    return tool("dc_shell", [
        "/usr/local/synopsys/syn/U-2022.12-SP7-2/bin/dc_shell",
        "/usr/local/synopsys/syn/*/bin/dc_shell",
    ])


# Run a tool, print its output, and save the same text to log. Returns the exit code.
def stream(cmd, cwd, log):
    log.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.Popen(
        cmd, cwd=str(cwd), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        universal_newlines=True,
    )
    with log.open("w") as out:
        for line in proc.stdout:
            sys.stdout.write(line)
            out.write(line)
    return proc.wait()


# Create directories under the CAD project.
def op_dirs(args):
    root = project(args.proj)
    for rel in args.dirs:
        (root / rel).mkdir(parents=True, exist_ok=True)


# Rebuild work/ and compile rtl/param.sv, then the other files.
def op_vlog(args):
    proj = project(args.proj)
    work = proj / "work"
    shutil.rmtree(work, ignore_errors=True)
    subprocess.run([questa("vlib"), "work"], cwd=proj, check=False)
    files = ["rtl/param.sv"] + [f for f in args.files if f != "rtl/param.sv"]
    sys.exit(stream(
        [questa("vlog"), "-64", "-sv", "+acc",
         "+incdir+tb/part1", "+incdir+rtl", "+incdir+rtl/part1", *files],
        proj, proj / "log" / "vlog.log",
    ))


# Run the testbench in the console (vsim -c).
def op_vsim(args):
    proj = project(args.proj)
    sys.exit(stream(
        [questa("vsim"), "-64", "-c", "-work", str(proj / "work"), args.top,
         "-sv_seed", args.seed, f"-GPIPELINED={args.pipelined}",
         "-do", "run -all; quit"],
        proj, proj / "log" / "vsim.log",
    ))


# Synthesize with dc_shell -f runsynth.tcl. setupdc.tcl is always syn/setupdc.tcl.
def op_vsyn(args):
    proj = project(args.proj)
    syn = proj / "syn"
    if not (syn / "setupdc.tcl").is_file():
        sys.exit("syn/setupdc.tcl is missing. Keep that file in syn/.")
    sys.exit(stream([dc_shell(), "-f", "runsynth.tcl"], syn, proj / "log" / "vsyn.log"))


# Remove leftover params.sv copies so link cannot pull them back.
def op_tidy(args):
    proj = project(args.proj)
    shutil.rmtree(proj / "constraint/param", ignore_errors=True)
    shutil.rmtree(proj / "constraint/config", ignore_errors=True)
    for rel in (
        "rtl/param_pkg.sv", "tb/part1/params.sv", "sim/part1/params.sv", "syn/params.sv",
    ):
        path = proj / rel
        if path.is_file():
            path.unlink()


# Subcommands: dirs, vlog, vsim, vsyn, tidy.
# CAD is Python 3.6, so this stays clear of 3.7-only argparse (required= on subparsers).
def parser():
    main = argparse.ArgumentParser(description="CAD operations")
    sub = main.add_subparsers(dest="op")

    dirs = sub.add_parser("dirs")
    dirs.add_argument("--proj", required=True)
    dirs.add_argument("dirs", nargs="+")
    dirs.set_defaults(func=op_dirs)

    vlog = sub.add_parser("vlog")
    vlog.add_argument("--proj", required=True)
    vlog.add_argument("files", nargs="*")
    vlog.set_defaults(func=op_vlog)

    vsim = sub.add_parser("vsim")
    vsim.add_argument("--proj", required=True)
    vsim.add_argument("--top", required=True)
    vsim.add_argument("--seed", required=True)
    vsim.add_argument("--pipelined", required=True)
    vsim.set_defaults(func=op_vsim)

    vsyn = sub.add_parser("vsyn")
    vsyn.add_argument("--proj", required=True)
    vsyn.set_defaults(func=op_vsyn)

    tidy = sub.add_parser("tidy")
    tidy.add_argument("--proj", required=True)
    tidy.set_defaults(func=op_tidy)
    return main


if __name__ == "__main__":
    parsed = parser().parse_args()
    # No subcommand: 3.6 leaves dest unset instead of erroring.
    if not hasattr(parsed, "func"):
        sys.exit("Use dirs, vlog, vsim, vsyn, or tidy.")
    parsed.func(parsed)
