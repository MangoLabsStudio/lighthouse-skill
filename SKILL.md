---
name: lighthouse
description: Use when the user wants to buy Twitter engagement (likes/RT/comments/follows) on the Lighthouse platform, check LUX balance, or track engagement campaigns. Calls Lighthouse Open API with LIGHTHOUSE_API_KEY env var.
---

# Lighthouse Skill

## Prerequisites

Before calling any Lighthouse endpoint, make sure the environment is set up correctly and that the user's API key is available to the shell (not to chat).

### Environment setup

The skill reads two environment variables:

- `LIGHTHOUSE_API_KEY` **(required)** — the buyer's Open API key. Format `lh_live_...` (production) or `lh_test_...` (dev). Get one from the Lighthouse admin panel.
- `LIGHTHOUSE_API_BASE` **(optional)** — defaults to production `https://service.lhdao.top/open-api/v1`. For the dev environment use `https://service.lhdaobeta.top/open-api/v1`.

Example (user runs this in their own shell):

```bash
export LIGHTHOUSE_API_KEY=lh_live_xxxxxxxxxxxxxxxxxxxxxxxx
# optional — only if targeting dev
export LIGHTHOUSE_API_BASE=https://service.lhdaobeta.top/open-api/v1
```

### Critical safety rule — API key handling

**Never ask the user to paste the API key into chat.** The key is a bearer credential; once it appears in the transcript it is effectively leaked (transcripts are logged, synced, and may be shared).

If `$LIGHTHOUSE_API_KEY` is missing, empty, or does not start with `lh_live_` / `lh_test_`:

1. Tell the user the key is missing / malformed.
2. Ask them to `export LIGHTHOUSE_API_KEY=...` in their own shell.
3. Ask them to restart the Claude Code / Agent session so the new env var is picked up.
4. **Do NOT** offer to accept the key inline, do NOT suggest pasting it into chat, and do NOT write it to a file on the user's behalf.

### Verify setup

Run the bundled CLI wrapper:

```bash
./scripts/lighthouse balance
```

Or the equivalent curl:

```bash
curl -sS -H "X-API-Key: $LIGHTHOUSE_API_KEY" "$LIGHTHOUSE_API_BASE/balance"
```

Expected output — a JSON object containing at least:

```json
{
  "oldLux": 0,
  "newLux": 42.5,
  "totalLux": 42.5
}
```

If you get `401` or an `INVALID_API_KEY` error, go back to the env-setup step. Do not proceed to any `POST` endpoint until `balance` returns successfully.

### References

Deeper reading (load on demand — the body of this skill stays self-contained):

- `references/api-reference.md` — full endpoint list, request/response schemas, error codes.
- `references/pricing-and-tiers.md` — fee formula, tier semantics, default baseRewards, budget worked examples.
- `references/action-combinations.md` — which action combinations are legal (in particular the `COMMENT_LIKE` exclusion rules).
- `examples/` — end-to-end recipes (this directory may be empty right now; it will be filled in a later task).

## Business Guidance

The Lighthouse Open API does not accept a free-form budget. The real
`POST /campaigns/engagement` request shape is:

```jsonc
{
  "targetUrl": "https://x.com/user/status/123",
  "actions": [
    { "actionType": "LIKE", "tierSlots": { "A": 50, "B": 100 } }
  ],
  "expiresInHours": 8   // optional
}
```

The backend computes the budget and platform fee itself from `tierSlots × price`. The Agent's job is to **translate user intent into `tierSlots`** — no `totalBudget`, no `targetCount`, no `mode`, no top-level `targetTiers` fields exist on the wire.

This section tells the Agent what to do before every campaign create. Deeper strategy (which tier mix fits a given intent) lives in `references/pricing-and-tiers.md` §4; the Agent should load that file when translating non-trivial requests.

### Required call order before every `POST /campaigns/engagement`

1. **`GET /balance`** — confirm the buyer has funds. Record `totalLux`.
2. **`GET /pricing`** — fetch the current `prices` table and `platformFeeRate`. Cache both for the rest of the session; prices are dynamic (admin-editable, 60s server cache).
3. **Translate intent → `actions[].tierSlots`** using heuristics from `references/pricing-and-tiers.md` §4 (the translation is load-bearing — do not shortcut it).
4. **Compute cost locally**:
   ```
   computed_budget = Σ slot × prices[action][tier]
   platform_fee    = computed_budget × platformFeeRate      (0.05 today)
   total_cost      = computed_budget + platform_fee         (= computed_budget × 1.05)
   ```
5. **Present the proposal to the user** (see the Mandatory Safety Flow below for the required block format). Get explicit confirmation, then `POST`.

### Validation rules — apply BEFORE posting

The backend enforces these. Catch them client-side for better UX:

- **Tier keys** — `tierSlots` keys must be in `{A, B, C, D, E}`. **`S` is not allowed** on this endpoint; S-tier deals go through Tweet campaigns or hand-negotiated flows.
- **Non-empty slots** — at least one `tierSlots[tier] > 0` across all actions. An empty request returns `EMPTY_TIER_SLOTS`.
- **Slot values** — non-negative integers. No floats, no negatives.
- **`COMMENT_LIKE` mutual exclusion** — `COMMENT_LIKE` is a combo action (one KOL both comments and likes). It **cannot appear alongside standalone `LIKE` or `COMMENT`** in the same request. Legal partners for `COMMENT_LIKE`: `RT`, `FOLLOW` only.
  - Legal: `[LIKE]`, `[LIKE, RT]`, `[LIKE, COMMENT, RT, FOLLOW]`, `[COMMENT_LIKE]`, `[COMMENT_LIKE, RT, FOLLOW]`.
  - Illegal (400): `[COMMENT_LIKE, LIKE, …]`, `[COMMENT_LIKE, COMMENT, …]`.
- **`targetUrl`** — must be a valid URL.
- **`expiresInHours`** — optional, integer ≥ 1 if present.

### Expiration — default 8h

- **Default: 8 hours.** The backend hard-codes this. **If 8h is what the buyer wants, do NOT send `expiresInHours` at all** — let the backend default apply so future changes follow automatically.
- **Urgent: 2–4 hours** — launch windows, news spikes. Set explicitly.
- **Long-tail: 24 hours** — overnight pickup across time zones. Set explicitly.
- Only include `expiresInHours` when the buyer's intent is non-default.

### Tier preference cues from the buyer

Map natural-language intent to `tierSlots` tiers:

| Buyer says | Default tier choice |
|---|---|
| "top KOLs only", "premium", "brand launch" | **A only** (S is not available here) |
| "any tier", nothing specified | **A** — quality-first default; offer a cheaper fallback |
| "cheapest", "maximum volume" | **D** or **E** (lowest price; D and E are priced identically by default) |
| count + budget that doesn't fit in A | **Mix** — A first, fill the remainder from a cheaper tier (prefer two-tier splits for readability) |
| Specific tier list ("only A or B") | Constrain to those tiers, then apply the strategy above inside the constraint |

If the buyer gives you a count + budget that doesn't fit even at the cheapest tier, **tell them the count isn't achievable** and offer concrete alternatives (reduce count, or raise budget). Never silently truncate.

When ambiguity remains (e.g. "buy likes" with no count), **ask** — don't guess.

## Mandatory Safety Flow

> **You MUST execute steps 1–5 in order before any `POST /campaigns/engagement` call. No exceptions, no shortcuts.**

This flow is not advisory. A LUX-spending call without this flow is a bug — the Agent is spending the buyer's money without confirmation.

### The 7 steps

1. **Call `GET /balance`, show the result to the user.** The user needs to see their current `newLux` balance before approving a spend.

2. **Compute `totalCost = totalBudget × 1.05`.** Break down `totalBudget` by action and tier, then add the 5% fee. Show your work — don't hand-wave the number.

3. **Present a structured confirmation block to the user.** Use this exact fenced format:

   ```
   ─ Target tweet: <URL>
   ─ Actions: LIKE×100, RT×50
   ─ Budget: 100 LUX
   ─ Platform fee: 5 LUX (5%)
   ─ Total cost: 105 LUX
   ─ Balance after: <balance minus 105> LUX
   ```

4. **Explicitly ask for confirmation:** "是否确认创建？(yes/no)" (or English equivalent: "Confirm creation? (yes/no)").

5. **Only proceed if the user replies with a confirmation token:** `yes`, `确认`, `ok`, `确定`. Any ambiguous reply ("sure I guess", "let me think", "maybe", "…", a new question) → re-ask. Do NOT assume consent.

6. **High-value guard.** If `totalBudget > 500 LUX`, include an extra warning line in the confirmation block, e.g.:

   > ⚠️ This is a high-value investment. Please double-check the parameters.

   This is in addition to — not instead of — the normal confirmation.

7. **Forbidden: looping or batch-creating campaigns without a separate confirmation per item.** If the user says "create these 5 campaigns," confirm each one individually, one balance check + one confirmation block + one explicit `yes` per campaign. Do not collapse them into a single "confirm all 5?" prompt.

### Bad vs. Good Agent

**Bad:**

> User: "Buy 100 likes for https://x.com/foo/123"
> Agent: *immediately calls `POST /campaigns/engagement` with a budget guess*
>
> (This is wrong — no balance check, no cost breakdown, no confirmation. The Agent just spent the buyer's LUX without asking.)

**Good:**

> User: "Buy 100 likes for https://x.com/foo/123"
> Agent: Calls `GET /balance` → returns `newLux: 200`.
> Computes `100 × 0.4 = 40 LUX` budget, `+ 5% fee = 42 LUX` total.
> Presents the confirmation block (target, actions, budget, fee, total, balance after = 158 LUX). Waits.
> User: "confirm"
> Agent: Calls `POST /campaigns/engagement`, returns the campaign ID and a link.

## Error Handling

All Lighthouse Open API errors return a JSON body with at least `{ code, message }`. Map HTTP status + code to one of the actions below. **Do not silently retry** — retrying a bad request with the same inputs just burns rate limit.

| HTTP       | Code                     | Meaning                                                                        | Agent action                                                                                                 |
|------------|--------------------------|--------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| 401        | `INVALID_API_KEY`        | API key wrong / expired / revoked.                                             | Tell the user to check or rotate their key. Do NOT retry.                                                    |
| 403        | `PERMISSION_DENIED`      | Key is valid but does not have permission for this endpoint / resource.        | Tell the user. Do NOT retry.                                                                                 |
| 400        | `INSUFFICIENT_BALANCE` (or BadRequest with `"Insufficient LUX balance"` in message) | Buyer cannot afford the campaign.              | Re-run `GET /balance`, report the shortfall (`needed − have = X LUX`) to the user. Do NOT retry.             |
| 429        | `RATE_LIMIT_EXCEEDED`    | Too many requests in the window.                                               | Wait 60 seconds, retry once. If still 429, abort and tell the user to slow down.                             |
| 422        | Validation error         | Request body malformed (bad tier key, illegal action combination, etc.).       | Read the error detail aloud to the user. Do NOT auto-fix and retry without user confirmation.                |
| 4xx / 5xx other | —                   | Unknown / unexpected.                                                          | Report the raw response (status + body) to the user. Do not silently retry.                                  |

Note: the 422 row includes the `COMMENT_LIKE` exclusion rule. If you see a 422 mentioning LIKE/COMMENT/COMMENT_LIKE, re-read the "COMMENT_LIKE mutual exclusion" section above rather than guessing a fix.

## Tool Preference

Prefer the bundled CLI wrapper, fall back to `curl` when the script is not available.

### Preferred: `./scripts/lighthouse`

The wrapper is shorter, safer, and performs local validation (env-var presence, key prefix, basic request-shape checks) before hitting the network. Use it whenever `./scripts/lighthouse` exists in the working tree.

```bash
./scripts/lighthouse balance
./scripts/lighthouse campaigns list [--status ACTIVE|PAUSED|ENDED|CLOSED] [--page N] [--page-size N]
./scripts/lighthouse campaigns get <campaign-id>
./scripts/lighthouse campaigns create-engagement \
    --url <tweet-url> --budget <lux> \
    [--like N] [--rt N] [--comment N] [--follow N] [--comment-like N] \
    [--mode OPEN|INVITE] [--tiers S,A,B] [--expires-in-hours N]
```

### Fallback: `curl`

When the script is not installed (e.g. the user is running Lighthouse from a different checkout), use `curl` directly. Always pass the key via the `X-API-Key` header — **never** via URL query string, request body, or shell arg visible in `ps`.

Generic template:

```bash
curl -sS -H "X-API-Key: $LIGHTHOUSE_API_KEY" \
     -H "Content-Type: application/json" \
     -X POST "$LIGHTHOUSE_API_BASE/campaigns/engagement" \
     -d '{...}'
```

One example per endpoint (brief — full schemas live in `references/api-reference.md`):

**GET `/balance`** — current wallet:

```bash
curl -sS -H "X-API-Key: $LIGHTHOUSE_API_KEY" \
     "$LIGHTHOUSE_API_BASE/balance"
```

**GET `/pricing`** — authoritative tier × action price table + fee rate:

```bash
curl -sS -H "X-API-Key: $LIGHTHOUSE_API_KEY" \
     "$LIGHTHOUSE_API_BASE/pricing"
```

**POST `/campaigns/engagement`** — create an Engagement campaign:

```bash
curl -sS -H "X-API-Key: $LIGHTHOUSE_API_KEY" \
     -H "Content-Type: application/json" \
     -X POST "$LIGHTHOUSE_API_BASE/campaigns/engagement" \
     -d '{
       "targetUrl": "https://x.com/foo/status/123",
       "actions": [
         { "actionType": "LIKE", "tierSlots": { "A": 100 } }
       ],
       "expiresInHours": 8
     }'
```

**GET `/campaigns/{id}`** — inspect a campaign's status and fill progress:

```bash
curl -sS -H "X-API-Key: $LIGHTHOUSE_API_KEY" \
     "$LIGHTHOUSE_API_BASE/campaigns/<campaign-id>"
```

### Secrets hygiene

- **Never** echo, log, or commit the value of `$LIGHTHOUSE_API_KEY`. Reference it by variable name only.
- Do not include the key in error messages, diagnostic dumps, or chat output — even partially redacted.
- If the user accidentally pastes their key into chat, tell them to rotate it immediately (the transcript is already logged).

