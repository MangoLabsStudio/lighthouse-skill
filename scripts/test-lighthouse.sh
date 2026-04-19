#!/usr/bin/env bash
# Smoke test for scripts/lighthouse. Exits non-zero on failure.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/lighthouse"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

expect_fail() {
  local label="$1" msg="$2"; shift 2
  out=$(LIGHTHOUSE_API_KEY=lh_live_dummy "$SCRIPT" "$@" 2>&1) && fail "$label: expected failure"
  echo "$out" | grep -q "$msg" || fail "$label: missing message '$msg' in: $out"
  pass "$label"
}

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

# Input validation smoke tests (S1)
expect_fail "missing actions" "at least one of" \
  campaigns create-engagement --url https://x.com/x/status/1 --budget 100

expect_fail "bad budget" "non-negative number" \
  campaigns create-engagement --url https://x.com/x/status/1 --budget abc --like 1

expect_fail "bad mode" "OPEN or INVITE" \
  campaigns create-engagement --url https://x.com/x/status/1 --budget 100 --like 1 --mode open

expect_fail "bad tier" "invalid tier" \
  campaigns create-engagement --url https://x.com/x/status/1 --budget 100 --like 1 --tiers foo

# --print-body success path
out=$(LIGHTHOUSE_API_KEY=lh_live_dummy "$SCRIPT" \
  campaigns create-engagement --url https://x.com/x/status/1 --budget 100 --like 5 --print-body 2>&1) \
  || fail "--print-body should succeed, got: $out"
echo "$out" | grep -q '"totalBudget":100' || fail "--print-body missing totalBudget: $out"
echo "$out" | grep -q '"actionType":"LIKE"' || fail "--print-body missing LIKE action: $out"
echo "$out" | grep -q "expiresInHours" && fail "--print-body should NOT include expiresInHours by default: $out"
pass "--print-body default (no expiresInHours)"

out=$(LIGHTHOUSE_API_KEY=lh_live_dummy "$SCRIPT" \
  campaigns create-engagement --url https://x.com/x/status/1 --budget 100 --like 5 --print-body --expires-in-hours 4 2>&1) \
  || fail "--print-body with expires should succeed, got: $out"
echo "$out" | grep -q '"expiresInHours":4' || fail "--print-body missing expiresInHours:4: $out"
pass "--print-body with --expires-in-hours"

echo "ALL SMOKE TESTS PASSED"
