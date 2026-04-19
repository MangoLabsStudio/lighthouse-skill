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

The following rules are IN-LINE (not in a reference file) because the Agent must have them in context for every Lighthouse call. They are distilled from `references/pricing-and-tiers.md` and `references/action-combinations.md` — if anything here conflicts with those docs, the reference file wins and this section should be updated.

### Fee formula — 5% platform fee on Engagement

```
platformFee = totalBudget × 0.05
totalCost   = totalBudget × 1.05
```

- `totalBudget` is the sum sellers (KOLs) can earn: `Σ (baseReward × targetCount)` across all actions and tiers.
- `totalCost` is what the buyer actually pays out of their LUX wallet at publish time.
- **Always show this computation to the user before asking for confirmation.** The buyer cares about `totalCost`; the backend also debits `totalCost`, not `totalBudget`.

### COMMENT_LIKE mutual exclusion

`COMMENT_LIKE` is a "combo" action (one KOL both comments and likes). It **cannot appear alongside standalone `LIKE` or standalone `COMMENT` in the same campaign** — the backend returns `400` if you try.

Legal action sets (partial list):
- `[LIKE]`, `[COMMENT]`, `[LIKE, COMMENT]`, `[LIKE, RT]`, `[LIKE, COMMENT, RT]`, `[LIKE, COMMENT, RT, FOLLOW]`
- `[COMMENT_LIKE]`, `[COMMENT_LIKE, RT]`, `[COMMENT_LIKE, RT, FOLLOW]`, `[COMMENT_LIKE, FOLLOW]`

Illegal (will 400):
- `[COMMENT_LIKE, LIKE, ...]` — conflict with LIKE
- `[COMMENT_LIKE, COMMENT, ...]` — conflict with COMMENT

Validate this locally before POSTing. If the user asks for something that's both "likes" and "comment+like combos," pick one — don't ship a request you already know will 400.

### Tier defaults

- Tiers are `S / A / B / C / D / E`. **S is not priced in the open Engagement table** — it's reserved for Tweet / hand-negotiated deals.
- If you omit `targetTiers`, **all eligible tiers** (A/B/C/D/E) are open — this is the default.
- Only narrow `targetTiers` when the buyer has an explicit quality target (e.g. "A-tier only for a brand launch"). Narrowing the tier list shrinks the pool of KOLs who can claim slots, so campaigns fill more slowly.

### Expiration defaults

- **Default: 8 hours.** The backend hard-codes this (`campaign.service.ts:249`). **If 8h is what the buyer wants, do NOT pass `expiresInHours` in the request body** — let the backend default apply, so future changes to the default follow automatically.
- **Urgent: 2–4 hours** — launch windows, news spikes, scheduled drops. Set `expiresInHours` explicitly.
- **Long-tail: 24 hours** — overnight pickup across time zones. Set `expiresInHours` explicitly.
- Only set `expiresInHours` when the buyer's intent is non-default.

### Budget estimation heuristic (A-tier)

Rough default A-tier unit prices — memorize these for off-the-cuff estimates; trust `GET /pricing` for authoritative numbers.

| Action          | A-tier baseReward (newLUX) |
|-----------------|----------------------------|
| `LIKE`          | 0.4                        |
| `COMMENT`       | 0.8                        |
| `COMMENT_LIKE`  | 1.2                        |
| `FOLLOW`        | 12                         |
| `RT`            | 20                         |

Formula for a single action, A-tier:

```
totalBudget ≈ N × baseReward
totalCost   ≈ totalBudget × 1.05
```

**Worked example — 100 A-tier likes:**

```
totalBudget = 100 × 0.4       = 40.0  newLUX
platformFee = 40.0 × 0.05     =  2.0  newLUX
totalCost   = 40.0 + 2.0      = 42.0  newLUX
```

For mixed tiers or mixed actions, sum `N_tier × baseReward_tier` across the matrix, then multiply the sum by 1.05. See `references/pricing-and-tiers.md` §4 for the full formula and a worked mixed example.

### Mode choice — OPEN vs. INVITE

- **OPEN** (default) — the campaign lands in the public Task Hall; any eligible KOL can claim a slot. Faster fill, broader reach, lower quality floor.
- **INVITE** — the buyer names specific KOL handles who can claim. Slower fill, higher quality control. Use only when the buyer has a specific KOL list.

Default to OPEN unless the buyer explicitly gave you handles to invite.

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

