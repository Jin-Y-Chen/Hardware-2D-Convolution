#!/usr/bin/env python3
"""Run the local pdflatex. TinyTeX on Linux, MiKTeX on Windows, else PATH."""

import os
import shutil
import sys

CANDIDATES = (
    "/home/jin/.TinyTeX/bin/x86_64-linux/pdflatex",
    os.path.join(
        os.environ.get("LOCALAPPDATA", ""),
        "Programs",
        "MiKTeX",
        "miktex",
        "bin",
        "x64",
        "pdflatex.exe",
    ),
)


def find_pdflatex():
    for path in CANDIDATES:
        if path and os.path.isfile(path):
            return path
    return shutil.which("pdflatex")


def main():
    exe = find_pdflatex()
    if not exe:
        sys.stderr.write("pdflatex not found. Install TinyTeX or MiKTeX.\n")
        return 1
    os.execv(exe, [exe, *sys.argv[1:]])


if __name__ == "__main__":
    sys.exit(main())
