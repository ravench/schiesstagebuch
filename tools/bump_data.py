#!/usr/bin/env python3
"""Moves calibre-data to a commit and regenerates everything that depends on it, in one go:

    python3 tools/bump_data.py [commit]    # default: calibre-data's origin/main

the submodule, Resources/Calibers.json and WeaponIcons.json (generate_assets.py) and the strings
(localize.py). Prints the calibre-data commits brought in, for the pull request. Commit the
result yourself (`git add calibre-data Schiesstagebuch`). Ported from Kaliberfinder's tool."""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "calibre-data")


def git(*args):
    return subprocess.check_output(["git", *args], cwd=DATA, text=True).strip()


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "origin/main"
    git("fetch", "-q", "origin")
    old = git("rev-parse", "HEAD")
    git("checkout", "-q", target)
    new = git("rev-parse", "HEAD")
    for tool in ("generate_assets.py", "localize.py"):
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", tool)], check=True)
    print(git("log", "--oneline", f"{old}..{new}") if old != new else f"calibre-data already at {new[:7]}")


if __name__ == "__main__":
    main()
