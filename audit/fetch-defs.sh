#!/usr/bin/env bash
# Downloads the pinned Roblox API definitions used by luau-lsp analyze.
# The file is gitignored (generated, third-party); the sha256 pins it.
set -euo pipefail
cd "$(dirname "$0")/.."

DEFS=audit/defs/globalTypes.d.lua
SHA="ca53b8cb9bf82d66690805b5d3bbd8e04d684cef3fe544e1becd061a64ca3ab0"
URL="https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.lua"

mkdir -p audit/defs
if [ -f "$DEFS" ] && echo "$SHA  $DEFS" | shasum -a 256 -c --status 2>/dev/null; then
  echo "defs: cached ($SHA)"
  exit 0
fi
curl -sL "$URL" -o "$DEFS"
echo "$SHA  $DEFS" | shasum -a 256 -c
