#!/usr/bin/env python3
"""Resolve `"version": "..."` conflicts in package.json-style files.

Reads the file at argv[1]. If every git conflict block in the file consists
solely of one `"version": "..."` line on each side, rewrites the file with
HEAD's value chosen and conflict markers removed. Any other conflict shape
(extra lines on either side, non-version conflict) leaves the file unchanged
and exits 1. Files with no conflict markers are left unchanged and exit 0.
"""

import re
import sys

VERSION_LINE = re.compile(r'^\s*"version":\s*"[^"]*",?\s*$')
START = "<<<<<<<"
MID = "======="
END = ">>>>>>>"


def resolve(path):
    with open(path) as f:
        lines = f.readlines()

    out = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if line.startswith(START):
            j = i + 1
            while j < n and not lines[j].startswith(MID):
                j += 1
            if j == n:
                raise ValueError(
                    f"Unterminated conflict block starting at line {i + 1}"
                )
            k = j + 1
            while k < n and not lines[k].startswith(END):
                k += 1
            if k == n:
                raise ValueError(
                    f"Unterminated conflict block starting at line {i + 1}"
                )

            head_lines = lines[i + 1:j]
            other_lines = lines[j + 1:k]

            if len(head_lines) != 1 or not VERSION_LINE.match(head_lines[0]):
                raise ValueError(
                    f"Conflict at line {i + 1} is not a single version-line on the HEAD side"
                )
            if len(other_lines) != 1 or not VERSION_LINE.match(other_lines[0]):
                raise ValueError(
                    f"Conflict at line {i + 1} is not a single version-line on the incoming side"
                )

            out.append(head_lines[0])
            i = k + 1
        else:
            out.append(line)
            i += 1

    with open(path, "w") as f:
        f.writelines(out)


def main():
    if len(sys.argv) != 2:
        print("usage: resolve_package_versions.py <file>", file=sys.stderr)
        return 2
    try:
        resolve(sys.argv[1])
    except ValueError as e:
        print(f"resolve_package_versions: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
