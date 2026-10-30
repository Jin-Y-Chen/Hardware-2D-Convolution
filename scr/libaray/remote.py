#!/usr/bin/env python3
"""CAD commands: vlog, vsim, dc_shell -f runsynth.tcl. Output goes to the console."""

import argparse
import glob
import os
import re
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
         "+incdir+tb/part1", "+incdir+tb/part2", "+incdir+tb/part3", "+incdir+tb/part4",
         "+incdir+sim/part2", "+incdir+sim/part3",
         "+incdir+rtl", "+incdir+rtl/part1", "+incdir+rtl/part2", "+incdir+rtl/part3",
         *files],
        proj, proj / "log" / "vlog.log",
    ))


# Run the testbench in the console (vsim -c).
# -GPIPELINED is only for the MAC testbench.
# STAGE and INPUT_TVALID_PROB are sim.STAGE and sim.TVALID_PROB, not rtl/param.sv.
def op_vsim(args):
    proj = project(args.proj)
    cmd = [questa("vsim"), "-64", "-c", "-work", str(proj / "work"), args.top,
           "-sv_seed", args.seed]
    if args.pipelined is not None:
        cmd.append("-GPIPELINED=%s" % args.pipelined)
    if args.stage is not None:
        cmd.append("-GSTAGE=%s" % args.stage)
    if args.tvalid is not None:
        cmd.append("-GINPUT_TVALID_PROB=%s" % args.tvalid)
    cmd.extend(["-do", "run -all; quit"])
    sys.exit(stream(cmd, proj, proj / "log" / "vsim.log"))


# Write params.sv for part 2 and part 3. Both testbenches include that file.
# WIDTH R C K TVALID_PROB TREADY_PROB STAGE are the all_config fields.
def op_params(args):
    proj = project(args.proj)
    text = (
        "// Generated from constraint/all_config.json. Edit that file, not this one.\n"
        "`define WIDTHVAL %s\n"   # design.WIDTH
        "`define RVAL %s\n"       # design.R
        "`define CVAL %s\n"       # design.C
        "`define KVAL %s\n"       # design.K
        "`define TVPR %s\n"       # sim.TVALID_PROB
        "`define TRPR %s\n"       # sim.TREADY_PROB
        "`define STAGEVAL %s\n"   # sim.STAGE
        % (args.width, args.rows, args.cols, args.k, args.tvpr, args.trpr, args.stage)
    )
    for rel in ("sim/part2/params.sv", "sim/part3/params.sv"):
        path = proj / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)


# dc_shell runs in syn/, so sources are ../rtl/...
def rtl_rel(path):
    path = path.replace("\\", "/")
    for prefix in ("../rtl/", "rtl/", "./"):
        if path.startswith(prefix):
            path = path[len(prefix):]
    return "../rtl/" + path


# Patch TOP_MOD_NAME, clock, and SRC_FILE in the CAD copy of syn/runsynth.tcl.
def op_runsynth(args):
    tcl = project(args.proj) / "syn" / "runsynth.tcl"
    if not tcl.is_file():
        sys.exit("syn/runsynth.tcl is not on CAD. link does not copy syn/.")
    files = [rtl_rel(path) for path in args.files]
    src = '"%s"' % files[0] if len(files) == 1 else "[list " + " ".join('"%s"' % path for path in files) + "]"
    text = tcl.read_text(encoding="utf-8")
    subs = (
        (r'(set TOP_MOD_NAME )"[^"]*"', r'\g<1>"%s"' % args.top),
        (r'(set CLK_NAME\s+)"[^"]*"', r'\g<1>"%s"' % args.clk),
        (r'(set RST_NAME\s+)"[^"]*"', r'\g<1>"%s"' % args.rst),
        (r'(set CLK_PERIOD\s+)[^;]+', r'\g<1>%s' % args.period),
        (r'set SRC_FILE .*', "set SRC_FILE " + src + ";"),
    )
    for pattern, repl in subs:
        text, count = re.subn(pattern, repl, text, count=1, flags=re.M)
        if count != 1:
            sys.exit("Could not update syn/runsynth.tcl on CAD (TOP_MOD_NAME, CLK_NAME, RST_NAME, CLK_PERIOD, SRC_FILE).")
    tcl.write_text(text, encoding="utf-8")


# Synthesize with dc_shell -f runsynth.tcl. setupdc.tcl stays in syn/ on CAD.
def op_vsyn(args):
    proj = project(args.proj)
    syn = proj / "syn"
    if not (syn / "setupdc.tcl").is_file():
        sys.exit("syn/setupdc.tcl is missing on CAD. link does not copy syn/.")
    sys.exit(stream([dc_shell(), "-f", "runsynth.tcl"], syn, proj / "log" / "vsyn.log"))


# Remove leftover params.sv copies so link cannot pull them back.
def op_tidy(args):
    proj = project(args.proj)
    shutil.rmtree(proj / "constraint/param", ignore_errors=True)
    shutil.rmtree(proj / "constraint/config", ignore_errors=True)
    for rel in (
        "rtl/param_pkg.sv", "tb/part1/params.sv", "tb/part2/params.sv",
        "sim/part1/params.sv", "syn/params.sv",
    ):
        path = proj / rel
        if path.is_file():
            path.unlink()


# Subcommands: dirs, params, vlog, vsim, runsynth, vsyn, tidy.
# CAD is Python 3.6, so this stays clear of 3.7-only argparse (required= on subparsers).
def parser():
    main = argparse.ArgumentParser(description="CAD operations")
    sub = main.add_subparsers(dest="op")

    dirs = sub.add_parser("dirs")
    dirs.add_argument("--proj", required=True)
    dirs.add_argument("dirs", nargs="+")
    dirs.set_defaults(func=op_dirs)

    params = sub.add_parser("params")
    params.add_argument("--proj", required=True)
    params.add_argument("--width", required=True)
    params.add_argument("--rows", required=True)
    params.add_argument("--cols", required=True)
    params.add_argument("--k", required=True)
    params.add_argument("--tvpr", required=True)
    params.add_argument("--trpr", required=True)
    params.add_argument("--stage", required=True)
    params.set_defaults(func=op_params)

    vlog = sub.add_parser("vlog")
    vlog.add_argument("--proj", required=True)
    vlog.add_argument("files", nargs="*")
    vlog.set_defaults(func=op_vlog)

    vsim = sub.add_parser("vsim")
    vsim.add_argument("--proj", required=True)
    vsim.add_argument("--top", required=True)
    vsim.add_argument("--seed", required=True)
    vsim.add_argument("--pipelined")
    vsim.add_argument("--stage")
    vsim.add_argument("--tvalid")
    vsim.set_defaults(func=op_vsim)

    runsynth = sub.add_parser("runsynth")
    runsynth.add_argument("--proj", required=True)
    runsynth.add_argument("--top", required=True)
    runsynth.add_argument("--clk", required=True)
    runsynth.add_argument("--rst", required=True)
    runsynth.add_argument("--period", required=True)
    runsynth.add_argument("files", nargs="+")
    runsynth.set_defaults(func=op_runsynth)

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
        sys.exit("Use dirs, params, vlog, vsim, runsynth, vsyn, or tidy.")
    parsed.func(parsed)
