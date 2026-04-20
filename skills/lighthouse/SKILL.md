---
name: lighthouse
description: Use when the user wants to buy Twitter engagement (likes/RT/comments/follows) on the Lighthouse platform, check LUX balance, or track engagement campaigns. Calls Lighthouse Open API with LIGHTHOUSE_API_KEY env var.
---

# Lighthouse Skill

## Prerequisites

Before calling any Lighthouse endpoint, make sure the environment is set up correctly and that the user's API key is available to the shell (not to chat).

### Environment setup

The skill reads two environment variables:

- `LIGHTHOUSE_API_KEY` **(required)** — the buyer's Open API key. Format `lh_live_...`. Get one from the Lighthouse admin panel. (Dev and production use the same prefix; switch environments via `LIGHTHOUSE_API_BASE`.)
- `LIGHTHOUSE_API_BASE` **(optional)** — defaults to production `https://service.lhdao.top/open-api/v1`. For the dev environment use `https://service.lhdaobeta.top/open-api/v1`.

Example (user runs this in their own shell):

```bash
export LIGHTHOUSE_API_KEY=lh_live_xxxxxxxxxxxxxxxxxxxxxxxx
# optional — only if targeting dev
export LIGHTHOUSE_API_BASE=https://service.lhdaobeta.top/open-api/v1
```

### Critical safety rule — API key handling

**Never ask the user to paste the API key into chat.** The key is a bearer credential; once it appears in the transcript it is effectively leaked (transcripts are logged, synced, and may be shared).

If `$LIGHTHOUSE_API_KEY` is missing, empty, or does not start with `lh_live_`:

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
    { "actionType": "LIKE", "tierSlots": { "A": 50, "B": 100 } },
    { "actionType": "RT",   "tierSlots": { "A": 3 } }
  ],
  "expiresInHours": 8,      // optional
  "releaseCurve": "FLAT",   // optional, default FLAT
  "releaseDuration": 60     // optional, default 60 min
}
```

The backend computes the budget and platform fee itself from `tierSlots × price`. The Agent's job is to **translate user intent into `tierSlots`** — no `totalBudget`, no `targetCount`, no `mode`, no top-level `targetTiers` fields exist on the wire.

### One request → N atomic campaigns

**Each entry in `actions[]` becomes its own campaign.** A single POST with
two actions creates two separate campaigns atomically (all-or-nothing, rolled
back on failure). The response has the batch shape:

```jsonc
{
  "campaigns": [ /* CampaignResponseDto for action 1 */,
                 /* CampaignResponseDto for action 2 */ ],
  "totalBudget": 45.0,
  "platformFee":  2.25,
  "totalCost":   47.25
}
```

When reporting back to the user, the Agent MUST say "Created N campaigns"
with N = `campaigns.length`, not "Created a campaign". The confirmation block
(step 4 of the Safety Flow) MUST enumerate the N sub-campaigns so the user
sees exactly what will be spawned.

### Release scheduling (`releaseCurve`, `releaseDuration`)

Applied to every sub-campaign created by the request. Most Agents should
leave these at their defaults unless the buyer explicitly asks to tune
pacing.

- **`releaseCurve`** — default `FLAT`.
  - `FLAT` — steady release. Use when in doubt; fits almost every campaign.
  - `INCREASING` — starts slow, accelerates. Good for audience warm-up when
    the buyer wants early slots to look organic before opening the floodgates.
  - `DECREASING` — front-loaded rush. Good when the buyer wants maximum
    visibility in the first minutes (news spikes, product launches).
  - `BATCH` — everything unlocks at once at the end. Use for simultaneous
    reveals / coordinated pushes.
  - `PARABOLIC` — bell curve (slow, peak mid-way, taper). Rarely what the
    user wants unless they say so.
- **`releaseDuration`** — integer minutes in `[1, 1440]`, default `60`.
  Short campaigns (e.g. `expiresInHours ≤ 2`) should use a shorter duration
  (15–30 min) so the release isn't still unlocking slots as the campaign
  expires. Long campaigns can leave the default or raise it.

Omit both fields to apply backend defaults — match the `expiresInHours`
convention: if the default is what the buyer wants, don't send the field.

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

> **You MUST execute steps 1–6 in order before any `POST /campaigns/engagement` call. No exceptions, no shortcuts.**

This flow is not advisory. A LUX-spending call without this flow is a bug — the Agent is spending the buyer's money without confirmation.

### The steps

1. **Call `GET /balance`, show the result to the user.** Record `totalLux`. The buyer needs to see their current balance before approving a spend.

2. **Call `GET /pricing`.** Keep the `prices` table and `platformFeeRate` in memory for this session's cost calculations. Do not hard-code numbers — pricing is admin-editable.

3. **Parse the user's intent and propose `actions[].tierSlots`** (see Business Guidance + `references/pricing-and-tiers.md` §4). If the intent is ambiguous — e.g. "buy likes" with no count, or a tier preference that conflicts with budget — **ASK, don't guess.**

4. **Compute the cost locally and present a structured block** to the user. Use this exact shape — one line per sub-campaign that will be created, so the user can see the atomic batch explicitly:

   ```
   ─ Target tweet: <URL>
   ─ Campaigns to create (atomic): 2
     · #1 LIKE → A:50, B:100 → 50×0.4 + 100×0.3 = 50 LUX
     · #2 RT   → A:3         → 3×20 = 60 LUX
   ─ Subtotal: 110 LUX
   ─ Platform fee (5%): 5.5 LUX
   ─ Total cost: 115.5 LUX
   ─ Balance after: <totalLux − 115.5> LUX
   ─ Release: FLAT / 60 min (default)
   ─ Expires in: 8h (default)
   ```

   Show the per-sub-campaign math. Don't hand-wave the numbers. The "N
   atomic" count must equal `actions.length` — that's how many sub-campaigns
   the server will spawn. If the user tuned `releaseCurve` or
   `releaseDuration`, show the chosen values on the `Release:` line (strip
   the `(default)` suffix).

5. **Explicitly ask for confirmation:** "是否确认创建？(yes/no)" or "Confirm creation? (yes/no)". Wait for the reply.

6. **Only proceed on an explicit confirmation token:** `yes`, `确认`, `ok`, `确定`. Any ambiguous reply ("sure I guess", "let me think", "maybe", "…", a new question) → re-ask. Do NOT assume consent.

   **High-value guard.** If `total_cost > 500 LUX`, include an extra warning line **before** the confirmation question:

   > ⚠️ This is a high-value investment. Please double-check the parameters.

   This is in addition to — not instead of — the normal confirmation.

7. **Forbidden: looping or batch-creating campaigns without a separate confirmation per item.** If the user says "create these 5 campaigns," run steps 3–6 individually for each one. Do not collapse them into a single "confirm all 5?" prompt.

### Bad vs. Good Agent

**Bad:**

> User: "Buy 100 likes for https://x.com/foo/123"
> Agent: *immediately calls `POST /campaigns/engagement` with a guessed tierSlots*
>
> (No balance check, no pricing fetch, no cost breakdown, no confirmation. The Agent just spent the buyer's LUX without asking.)

**Good:**

> User: "Buy 100 likes for https://x.com/foo/123"
> Agent: Calls `GET /balance` → `totalLux: 200`. Calls `GET /pricing` → `LIKE.A = 0.4`.
> Proposes `actions: [{ actionType: "LIKE", tierSlots: { A: 100 } }]` (quality-first default).
> Computes: `computed_budget = 100 × 0.4 = 40.0`, `fee = 2.0`, `total_cost = 42.0`.
> Presents the block ("Campaigns to create (atomic): 1", action math, subtotal, fee, total, balance after = 158 LUX, release: FLAT / 60 min default, expires in: 8h default). Waits.
> User: "confirm"
> Agent: Calls `POST /campaigns/engagement` with `{targetUrl, actions}` (no optional fields — let defaults apply), reads `campaigns[0].id` from the batch response, and reports "Created 1 campaign: <id>. Total debited 42.0 LUX."

## Error Handling

Guard and interceptor errors return `{ code, message, statusCode }`. DTO validation errors (plain Nest `BadRequestException`) return `{ statusCode: 400, message: [...], error: "Bad Request" }` — **no `code` field**, and `message` is an array of strings. Service-layer business errors (e.g. insufficient balance, not found) are also plain `BadRequestException` / `NotFoundException` without a `code`. Map as follows; **do not silently retry** — retrying a bad request with the same inputs just burns rate limit.

| HTTP | Code | Meaning | Agent action |
|------|------|---------|--------------|
| 401 | `INVALID_API_KEY` | Missing `X-API-Key` header, unknown key, or `isActive=false`. | Stop. Ask the user to check or rotate the key via the admin Web UI. Do NOT retry. |
| 401 | `API_KEY_EXPIRED` | Key's `expiresAt` has passed. | Stop. Ask the user to rotate the key. Do NOT retry. |
| 403 | `PERMISSION_DENIED` | Key is valid but lacks a required scope (`balance:read`, `campaign:read`, `campaign:create`). | Stop. Tell the user which scope is needed. Do NOT retry. |
| 400 | _(no code)_ | Class-validator DTO error. `message` is an array of strings, e.g. `"targetUrl must be a valid URL"`, `"COMMENT_LIKE cannot be combined with standalone LIKE or COMMENT"`. | Read every entry of `message` to the user. Fix the specific field. Do NOT auto-fix and retry without user confirmation. |
| 400 | _(no code)_ | `EMPTY_TIER_SLOTS: <ACTION>` — match by the literal `EMPTY_TIER_SLOTS:` string prefix (plain `BadRequestException`, no code field). Raised when the listed action has all-zero `tierSlots`. | The Agent proposed an action with every tier = 0; that action contributes nothing. Remove it from `actions[]` or populate at least one tier with a positive integer, then re-confirm with the user before retrying. |
| 400 | _(no code)_ | Service-layer error — match by `message` substring `"Insufficient LUX balance"`. Budget exceeds balance. | Re-run `GET /balance`, report the shortfall (`needed − have = X LUX`) to the user. Reduce `tierSlots` or ask the user to top up. Do NOT retry unchanged. |
| 404 | _(no code)_ | Campaign not found, or not owned by this API key's user. | Verify the ID. Do NOT retry. |
| 429 | `RATE_LIMIT_EXCEEDED` | Per-key sliding-window quota exhausted. Response includes `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`. | Wait until `X-RateLimit-Reset`, retry once. If still 429, abort and tell the user to slow down. |
| 4xx / 5xx other | — | Unknown / unexpected. | Report the raw response (status + body, key redacted) to the user. Do not silently retry. |

The backend does **not** emit HTTP 422. If you see a 400 mentioning LIKE / COMMENT / COMMENT_LIKE, re-read the "COMMENT_LIKE mutual exclusion" rule in Business Guidance rather than guessing a fix.

## Tool Preference

Prefer the bundled CLI wrapper, fall back to `curl` when the script is not available.

### Preferred: `./scripts/lighthouse`

The wrapper is shorter and performs local validation (env-var presence, `lh_live_` prefix check, tier-key whitelist, `COMMENT_LIKE` mutex, non-empty-slots rule) before hitting the network. Use it whenever `./scripts/lighthouse` exists in the working tree.

```bash
./scripts/lighthouse balance
./scripts/lighthouse pricing
./scripts/lighthouse campaigns list [--status ACTIVE|PAUSED|ENDED|CLOSED] [--page N] [--page-size N]
./scripts/lighthouse campaigns get <campaign-id>
./scripts/lighthouse campaigns create-engagement \
    --url <tweet-url> \
    --action TYPE:A=N,B=M[,C=P,D=Q,E=R] \
    [--action TYPE:...] \
    [--expires-in-hours N] [--print-body]
```

**Action spec format:** `TYPE:TIER=N,TIER=N,...` where `TYPE` is one of `LIKE|RT|COMMENT|FOLLOW|COMMENT_LIKE` and `TIER` is one of `A|B|C|D|E` (S is rejected client-side). Repeat `--action` to include multiple action types in one campaign.

**`--print-body`** renders the JSON that would be POSTed and exits without calling the API. Use this to preview the exact request before spending LUX.

Example — 100 A-tier likes + 50 B-tier likes + 3 A-tier RTs, default 8h expiry:

```bash
./scripts/lighthouse campaigns create-engagement \
    --url https://x.com/user/status/123 \
    --action LIKE:A=100,B=50 \
    --action RT:A=3 \
    --print-body
```

### Fallback: `curl`

When the script is not installed, use `curl` directly. Always pass the key via the `X-API-Key` header — **never** via URL query string, request body, or shell arg visible in `ps`.

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

**GET `/campaigns`** — list owned campaigns (paginated):

```bash
curl -sS -H "X-API-Key: $LIGHTHOUSE_API_KEY" \
     "$LIGHTHOUSE_API_BASE/campaigns?status=ACTIVE&page=1&pageSize=20"
```

**GET `/campaigns/{id}`** — inspect a campaign's status and fill progress:

```bash
curl -sS -H "X-API-Key: $LIGHTHOUSE_API_KEY" \
     "$LIGHTHOUSE_API_BASE/campaigns/<campaign-id>"
```

**POST `/campaigns/engagement`** — create one Engagement campaign per action, atomically. Body is `{targetUrl, actions, expiresInHours?, releaseCurve?, releaseDuration?}`. The server computes budget and fee from each `actions[i].tierSlots` × the pricing table — you do NOT send a budget. Response is the batch shape (`campaigns[]` + aggregate cost):

```bash
# Minimal request — one action, defaults for everything else.
curl -sS -X POST "$LIGHTHOUSE_API_BASE/campaigns/engagement" \
  -H "X-API-Key: $LIGHTHOUSE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "targetUrl": "https://x.com/user/status/123",
    "actions": [
      {"actionType": "LIKE", "tierSlots": {"A": 50, "B": 100}}
    ]
  }'

# Multi-action request with tuned release schedule — creates N campaigns atomically.
curl -sS -X POST "$LIGHTHOUSE_API_BASE/campaigns/engagement" \
  -H "X-API-Key: $LIGHTHOUSE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "targetUrl": "https://x.com/user/status/123",
    "actions": [
      {"actionType": "LIKE", "tierSlots": {"A": 50, "B": 100}},
      {"actionType": "RT",   "tierSlots": {"A": 3}}
    ],
    "expiresInHours": 4,
    "releaseCurve": "INCREASING",
    "releaseDuration": 30
  }'
```

Omit `expiresInHours` / `releaseCurve` / `releaseDuration` to apply the backend defaults (8h, FLAT, 60 min). The response is `{ campaigns: [...], totalBudget, platformFee, totalCost }` — always iterate `campaigns[]`, never assume `.id` at the top level.

### Secrets hygiene

- **Never** echo, log, or commit the value of `$LIGHTHOUSE_API_KEY`. Reference it by variable name only.
- Do not include the key in error messages, diagnostic dumps, chat output, or commit messages — even partially redacted.
- If the user accidentally pastes their key into chat, tell them to rotate it via the admin Web UI immediately (the transcript is already logged).

