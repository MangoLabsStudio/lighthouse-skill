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

