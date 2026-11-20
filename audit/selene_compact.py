#!/usr/bin/env python3
"""Compact Selene's pretty output into stable, diffable lines.

Usage: selene_compact.py <raw-selene-output> <out-file>
Output format: path:line:col: code: message
"""
import re
import sys

PAT_CODE = re.compile(r"^(warning|error)\[(\w+)\]: (.*)$")
PAT_LOC = re.compile(r"^\s*┌─ ([^:]+):(\d+):(\d+)")


def main(src, dst):
    n = 0
    with open(src) as f, open(dst, "w") as out:
        pending = None
        for line in f:
            m = PAT_CODE.match(line.rstrip("\n"))
            if m:
                pending = (m.group(1) + "[" + m.group(2) + "]", m.group(3))
                continue
            m = PAT_LOC.match(line)
            if m and pending:
                n += 1
                out.write(
                    f"{m.group(1)}:{m.group(2)}:{m.group(3)}: {pending[0]}: {pending[1]}\n"
                )
                pending = None
    print(f"selene_compact: {n} warnings -> {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
