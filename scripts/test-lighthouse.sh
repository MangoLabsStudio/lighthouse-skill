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
pass "missing key handled"

# Bad key prefix must error clearly
LIGHTHOUSE_API_KEY="bad_key_123" out=$("$SCRIPT" balance 2>&1) && fail "expected non-zero for bad prefix"
echo "$out" | grep -qi "lh_live_" || fail "bad-prefix error should mention expected format"
pass "bad key prefix handled"

# Help command works
"$SCRIPT" --help | grep -qi "lighthouse balance" || fail "--help missing usage"
pass "--help output OK"

echo "ALL SMOKE TESTS PASSED"
