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
  echo "$out" | grep -q -e "$msg" || fail "$label: missing message '$msg' in: $out"
  pass "$label"
}

[ -x "$SCRIPT" ] || fail "scripts/lighthouse not executable"

# Missing API key must error clearly
unset LIGHTHOUSE_API_KEY
out=$("$SCRIPT" balance 2>&1) && fail "expected non-zero exit without key"
echo "$out" | grep -qi "LIGHTHOUSE_API_KEY" || fail "missing-key error should mention env var"
echo "$out" | grep -qi "required" || fail "missing-key error should say 'required'"
pass "missing key handled"

# Bad key prefix must error clearly.
(
  export LIGHTHOUSE_API_KEY="bad_key_123"
  out=$("$SCRIPT" balance 2>&1) && exit 99
  echo "$out" | grep -qi "must start with lh_live_" || exit 98
) || fail "bad key prefix test failed (code $?)"
pass "bad key prefix handled"

# Help command works
"$SCRIPT" --help | grep -qi "lighthouse balance" || fail "--help missing usage"
pass "--help output OK"

# --- Input validation for create-engagement ---

expect_fail "missing --url" "--url is required" \
  campaigns create-engagement --action LIKE:A=5

expect_fail "no --action" "at least one --action" \
  campaigns create-engagement --url https://x.com/x/status/1

expect_fail "bad action type" "invalid action type" \
  campaigns create-engagement --url https://x.com/x/status/1 --action FOO:A=5

expect_fail "bad tier (S)" "invalid tier" \
  campaigns create-engagement --url https://x.com/x/status/1 --action LIKE:S=5

expect_fail "bad count" "must be non-negative integer" \
  campaigns create-engagement --url https://x.com/x/status/1 --action LIKE:A=abc

expect_fail "zero total" "total slots must be > 0" \
  campaigns create-engagement --url https://x.com/x/status/1 --action LIKE:A=0,B=0

expect_fail "mutex COMMENT_LIKE + LIKE" "COMMENT_LIKE cannot be combined" \
  campaigns create-engagement --url https://x.com/x/status/1 \
  --action COMMENT_LIKE:A=5 --action LIKE:A=5

# --- Happy path --print-body ---
out=$(LIGHTHOUSE_API_KEY=lh_live_dummy "$SCRIPT" \
  campaigns create-engagement \
  --url URL \
  --action LIKE:A=5,B=10 \
  --action RT:A=3 \
  --expires-in-hours 4 \
  --print-body 2>&1) \
  || fail "--print-body should succeed, got: $out"
echo "$out" | grep -q '"targetUrl":"URL"'    || fail "--print-body missing targetUrl: $out"
echo "$out" | grep -q '"actionType":"LIKE"'  || fail "--print-body missing LIKE: $out"
echo "$out" | grep -q '"A":5'                || fail "--print-body missing A:5: $out"
echo "$out" | grep -q '"B":10'               || fail "--print-body missing B:10: $out"
echo "$out" | grep -q '"actionType":"RT"'    || fail "--print-body missing RT: $out"
echo "$out" | grep -q '"expiresInHours":4'   || fail "--print-body missing expiresInHours:4: $out"
echo "$out" | grep -q 'totalBudget'  && fail "--print-body must NOT include totalBudget: $out"
echo "$out" | grep -q 'targetCount'  && fail "--print-body must NOT include targetCount: $out"
echo "$out" | grep -q '"mode"'       && fail "--print-body must NOT include mode: $out"
echo "$out" | grep -q 'targetTiers'  && fail "--print-body must NOT include targetTiers: $out"
pass "--print-body happy path"

# --- --print-body without --expires-in-hours ---
out=$(LIGHTHOUSE_API_KEY=lh_live_dummy "$SCRIPT" \
  campaigns create-engagement \
  --url https://x.com/x/status/1 \
  --action LIKE:A=5 \
  --print-body 2>&1) \
  || fail "--print-body (no expires) should succeed, got: $out"
echo "$out" | grep -q 'expiresInHours' && fail "--print-body should NOT include expiresInHours by default: $out"
pass "--print-body default (no expiresInHours)"

echo "ALL SMOKE TESTS PASSED"
