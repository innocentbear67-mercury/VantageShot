#!/usr/bin/env python3
"""Normalize luau-lsp analyze output into stable, diffable lines.

luau-lsp emits two diagnostic formats:
  A: /abs/repo/path/File.luau [game/Instance/Path](L,C): Code: message
     (sourcemap-resolved diagnostics)
  B: repo/rel/path/File.luau(L,C): Code: message
     (lint diagnostics)

Output: repo-relative-path:L:C: Code: message — sorted, deduped.
Usage: luau_compact.py <raw-output> <out-file> <repo-root-abs-path>
"""
import re
import sys

PAT_A = re.compile(r"^(.*?\.luau) \[game/[^\]]*\]\((\d+),(\d+)\): (.*)$")
PAT_B = re.compile(r"^(.*?\.luau)\((\d+),(\d+)\): (.*)$")


def main(raw, dst, repo_root):
    n = 0
    skipped = 0
    out_lines = []
    prefix = repo_root.rstrip("/") + "/"
    with open(raw) as f:
        for line in f:
            s = line.rstrip("\n")
            if not s or s.startswith("[INFO]") or s.startswith("[WARN]"):
                continue
            m = PAT_A.match(s)
            if m:
                path = m.group(1)
                if path.startswith("/"):
                    if path.startswith(prefix):
                        path = path[len(prefix):]
                    else:
                        path = path[path.rfind("/") + 1:]
                out_lines.append(f"{path}:{m.group(2)}:{m.group(3)}: {m.group(4)}")
                n += 1
                continue
            m = PAT_B.match(s)
            if m:
                out_lines.append(f"{m.group(1)}:{m.group(2)}:{m.group(3)}: {m.group(4)}")
                n += 1
                continue
            skipped += 1
    # Strip the repo-root prefix ANYWHERE in the line (message text can embed
    # absolute paths of other files) so ratchet keys are checkout-independent.
    prefix = repo_root.rstrip("/") + "/"
    with open(dst, "w") as out:
        for l in sorted(set(x.replace(prefix, "") for x in out_lines)):
            out.write(l + "\n")
    print(f"luau_compact: {n} diagnostics ({skipped} unclassified lines ignored) -> {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3]))
