#!/usr/bin/env python3
"""Compute the next release version from a list of existing release branches.

Reads branch names on stdin (one per line). Branches matching
`<prefix>vMAJOR.MINOR.PATCH` exactly are parsed as semver; anything else is
ignored. Picks the highest version, applies the requested bump, prints the
result to stdout (without the leading 'v').

Usage:
  next_release_version.py --bump major|minor --prefix release/  <branches.txt

If no branch matches, prior version is treated as 0.0.0 (so --bump major
yields 1.0.0 and --bump minor yields 0.1.0).
"""

import argparse
import re
import sys


def parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--bump", required=True, choices=("major", "minor"))
    p.add_argument("--prefix", required=True)
    return p.parse_args(argv)


def discover_highest(lines, prefix):
    pattern = re.compile(rf"^{re.escape(prefix)}v(\d+)\.(\d+)\.(\d+)$")
    highest = (0, 0, 0)
    for line in lines:
        line = line.strip()
        m = pattern.match(line)
        if not m:
            continue
        ver = tuple(int(x) for x in m.groups())
        if ver > highest:
            highest = ver
    return highest


def bump(ver, kind):
    major, minor, patch = ver
    if kind == "major":
        return (major + 1, 0, 0)
    if kind == "minor":
        return (major, minor + 1, 0)
    raise ValueError(f"unknown bump: {kind}")


def main(argv):
    args = parse_args(argv[1:])
    highest = discover_highest(sys.stdin, args.prefix)
    nxt = bump(highest, args.bump)
    print(f"{nxt[0]}.{nxt[1]}.{nxt[2]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
