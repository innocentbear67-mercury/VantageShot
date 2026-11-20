#!/usr/bin/env bash
# VantageShot audit gate — the CI "new slop fails automatically" check.
# Runs: sourcemap -> luau-lsp analyze -> selene -> boundary check -> tests,
# then ratchets every result against audit/baseline.*.txt.
# Removals are always fine; anything NEW fails the build.
set -uo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

echo "== [0/6] tools =="
for t in luau-lsp selene lune rojo; do
  if command -v "$t" >/dev/null 2>&1; then echo "  $t OK"; else echo "  $t MISSING"; exit 2; fi
done
bash audit/fetch-defs.sh

echo "== [1/6] sourcemap =="
rojo sourcemap default.project.json --output sourcemap.json

echo "== [2/6] luau-lsp analyze =="
git ls-files '*.luau' | grep -vE '^(audit|tests)/' > /tmp/vs_files.txt
tr '\n' '\0' < /tmp/vs_files.txt | xargs -0 luau-lsp analyze \
  --definitions=audit/defs/globalTypes.d.lua --platform=roblox --sourcemap=sourcemap.json \
  > /tmp/vs_luau_raw.txt 2>&1 || true
python3 audit/luau_compact.py /tmp/vs_luau_raw.txt /tmp/vs_luau_now.txt "$(pwd)"
sort -o /tmp/vs_luau_now.txt /tmp/vs_luau_now.txt

echo "== [3/6] selene =="
xargs selene --no-summary < /tmp/vs_files.txt > /tmp/vs_selene_raw.txt 2>&1 || true
python3 audit/selene_compact.py /tmp/vs_selene_raw.txt /tmp/vs_selene_now.txt
sort -o /tmp/vs_selene_now.txt /tmp/vs_selene_now.txt

echo "== [4/6] boundary check =="
fail=0
if ! lune run audit/boundaries.luau > /tmp/vs_boundary.txt 2>&1; then
  cat /tmp/vs_boundary.txt; fail=1
else
  tail -1 /tmp/vs_boundary.txt
fi

echo "== [5/6] tests =="
if ! lune run tests/run.luau > /tmp/vs_tests.txt 2>&1; then
  cat /tmp/vs_tests.txt; fail=1
else
  tail -1 /tmp/vs_tests.txt
fi

echo "== [6/6] ratchet vs baseline =="
# Ratchet on (path: code: message) keys — line shifts from edits are not "new".
sed -E -e 's/:[0-9]+:[0-9]+:/:/' -e 's/at line [0-9]+/at line N/' audit/baseline.luau.txt | sort -u > /tmp/base_luau_keys.txt
sed -E -e 's/:[0-9]+:[0-9]+:/:/' -e 's/at line [0-9]+/at line N/' /tmp/vs_luau_now.txt | sort -u > /tmp/now_luau_keys.txt
comm -13 /tmp/base_luau_keys.txt /tmp/now_luau_keys.txt > /tmp/new_luau.txt || true
sed -E 's/:[0-9]+:[0-9]+:/:/' audit/baseline.selene.txt | sort -u > /tmp/base_selene_keys.txt
sed -E 's/:[0-9]+:[0-9]+:/:/' /tmp/vs_selene_now.txt | sort -u > /tmp/now_selene_keys.txt
comm -13 /tmp/base_selene_keys.txt /tmp/now_selene_keys.txt > /tmp/new_selene.txt || true
if [ -s /tmp/new_luau.txt ]; then
  echo "NEW luau diagnostics: $(wc -l < /tmp/new_luau.txt | tr -d ' ')"; head -10 /tmp/new_luau.txt; fail=1
fi
if [ -s /tmp/new_selene.txt ]; then
  echo "NEW selene warnings: $(wc -l < /tmp/new_selene.txt | tr -d ' ')"; head -10 /tmp/new_selene.txt; fail=1
fi

echo
echo "luau now:   $(wc -l < /tmp/vs_luau_now.txt | tr -d ' ')  (baseline: $(wc -l < audit/baseline.luau.txt | tr -d ' '))"
echo "selene now: $(wc -l < /tmp/vs_selene_now.txt | tr -d ' ')  (baseline: $(wc -l < audit/baseline.selene.txt | tr -d ' '))"
if [ "$fail" = 0 ]; then echo "AUDIT PASS: no new warnings"; else echo "AUDIT FAIL"; fi
exit $fail
