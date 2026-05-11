#!/usr/bin/env python3
"""Set the top-level "version" field in package.json-style files in place.

Usage: set_version.py <version> <file> [<file> ...]

<version> must look like X.Y.Z, optionally followed by -prerelease and/or
+build metadata. The file is rewritten by regex-replacing only the version
string, so surrounding whitespace and key order are preserved.
"""

import json
import re
import sys
from pathlib import Path

SEMVER = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$")


def set_version(path, new_version):
    text = path.read_text()
    data = json.loads(text)
    if "version" not in data:
        raise ValueError(f"{path}: no top-level 'version' field")
    old = str(data["version"])
    pattern = re.compile(r'("version"\s*:\s*")' + re.escape(old) + r'(")')
    new_text, n = pattern.subn(rf"\g<1>{new_version}\g<2>", text, count=1)
    if n == 0:
        raise ValueError(f"{path}: could not locate 'version' field to rewrite")
    path.write_text(new_text)
    return old


def main(argv):
    if len(argv) < 3:
        print(
            "usage: set_version.py <version> <file> [<file> ...]",
            file=sys.stderr,
        )
        return 2
    version = argv[1]
    if not SEMVER.match(version):
        print(
            f"set_version: invalid semver: {version!r} "
            "(expected X.Y.Z with optional -prerelease / +build)",
            file=sys.stderr,
        )
        return 1
    for raw in argv[2:]:
        path = Path(raw)
        try:
            old = set_version(path, version)
        except (ValueError, FileNotFoundError, json.JSONDecodeError) as e:
            print(f"set_version: {e}", file=sys.stderr)
            return 1
        print(f"{path}: {old} -> {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
