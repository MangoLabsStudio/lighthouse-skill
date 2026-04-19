#!/usr/bin/env bash
# Smoke test for scripts/lighthouse. Exits non-zero on failure.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/lighthouse"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[ -x "$SCRIPT" ] || fail "scripts/lighthouse not executable"

# Missing API key must error clearly
unset LIGHTHOUSE_API_KEY
out=$("$SCRIPT" balance 2>&1) && fail "expected non-zero exit without key"
echo "$out" | grep -qi "LIGHTHOUSE_API_KEY" || fail "missing-key error should mention env var"
echo "$out" | grep -qi "required" || fail "missing-key error should say 'required'"
pass "missing key handled"

# Bad key prefix must error clearly. Use a subshell with explicit `export` so the
# var actually reaches the child process — `FOO=bar out=$(cmd)` is parsed as two
# separate shell assignments, not a command prefix, so the child wouldn't see it.
(
  export LIGHTHOUSE_API_KEY="bad_key_123"
  out=$("$SCRIPT" balance 2>&1) && exit 99
  echo "$out" | grep -qi "must start with lh_live_" || exit 98
) || fail "bad key prefix test failed (code $?)"
pass "bad key prefix handled"

# Help command works
"$SCRIPT" --help | grep -qi "lighthouse balance" || fail "--help missing usage"
pass "--help output OK"

echo "ALL SMOKE TESTS PASSED"
