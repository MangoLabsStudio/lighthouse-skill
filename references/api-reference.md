# Lighthouse Open API Reference

Canonical reference for the Lighthouse Open API v1. Authoritative source is the
backend controller at
`kol-dao-service/src/modules/open-api/open-api.controller.ts` and its DTOs. If
this document and the source disagree, the source wins.

## Overview

### Base URL

| Environment | Base URL |
|-------------|----------|
| Production  | `https://service.lhdao.top/open-api/v1` |
| Dev / Beta  | `https://service.lhdaobeta.top/open-api/v1` |

Every example below assumes the caller has exported:

```bash
export LIGHTHOUSE_API_BASE="https://service.lhdao.top/open-api/v1"
export LIGHTHOUSE_API_KEY="lh_live_xxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### Authentication

All endpoints require the header `X-API-Key: <key>`. Keys are issued via the
Lighthouse dashboard and are prefixed `lh_live_`. The server stores only the
SHA-256 hash of the key — there is no bearer-token flow.

Required on every request:

```
X-API-Key: $LIGHTHOUSE_API_KEY
```

Each key carries a permission set. The required permission for each endpoint:

| Endpoint                         | Required permission |
|----------------------------------|---------------------|
| `GET /balance`                   | `balance:read`      |
| `GET /pricing`                   | `campaign:read`     |
| `POST /campaigns/engagement`     | `campaign:create`   |
| `GET /campaigns/:id`             | `campaign:read`     |
| `GET /campaigns`                 | `campaign:read`     |

### Rate limiting

Per-key sliding window: default 60 requests per 60 seconds (configurable per
key). Every response carries:

- `X-RateLimit-Limit` — per-minute quota for this key
- `X-RateLimit-Remaining` — requests remaining in the current window
- `X-RateLimit-Reset` — unix seconds when the window resets

Exceeding the limit returns HTTP 429 with
`{ "code": "RATE_LIMIT_EXCEEDED", ... }`.

### Error envelope

Guard- and interceptor-raised errors use this shape:

```json
{
  "code": "INVALID_API_KEY",
  "message": "Missing X-API-Key header",
  "statusCode": 401
}
```

DTO validation errors (400) follow Nest's default shape:

```json
{
  "statusCode": 400,
  "message": ["targetUrl must be a valid URL"],
  "error": "Bad Request"
}
```

See [Error Codes](#error-codes) at the bottom of this doc.

---

## 1. GET /balance

Return the LUX balances for the user who owns the API key.

- **Method / path**: `GET /open-api/v1/balance`
- **Required permission**: `balance:read`
- **Query / body**: none

### curl

```bash
curl -sS "$LIGHTHOUSE_API_BASE/balance" \
  -H "X-API-Key: $LIGHTHOUSE_API_KEY"
```

### Response 200 (`BalanceResponseDto`)

```json
{
  "oldLux": 1200.5,
  "newLux": 842.0,
  "totalLux": 2042.5
}
```

| Field      | Type   | Description |
|------------|--------|-------------|
| `oldLux`   | number | Legacy LUX balance. |
| `newLux`   | number | Labour-earned LUX, net of frozen amount. |
| `totalLux` | number | Combined spendable balance. Use this when deciding whether to create a campaign. |

All three values are numbers in LUX (not wei / sub-units).

---

## 2. GET /pricing

Return the current pricing table. Use this to estimate `totalBudget` before
calling `POST /campaigns/engagement` — the backend computes budget from the
same table.

- **Method / path**: `GET /open-api/v1/pricing`
- **Required permission**: `campaign:read`
- **Query / body**: none

### curl

```bash
curl -sS "$LIGHTHOUSE_API_BASE/pricing" \
  -H "X-API-Key: $LIGHTHOUSE_API_KEY"
```

### Response 200 (`PricingResponseDto`)

```json
{
  "prices": {
    "LIKE":         { "A": 0.4, "B": 0.3, "C": 0.2, "D": 0.1, "E": 0.1 },
    "COMMENT":      { "A": 0.8, "B": 0.6, "C": 0.4, "D": 0.1, "E": 0.1 },
    "RT":           { "A": 20,  "B": 15,  "C": 10,  "D": 5,   "E": 5   },
    "FOLLOW":       { "A": 12,  "B": 9,   "C": 6,   "D": 3,   "E": 3   },
    "COMMENT_LIKE": { "A": 1.2, "B": 0.9, "C": 0.6, "D": 0.2, "E": 0.2 }
  },
  "platformFeeRate": 0.05,
  "currency": "newLUX"
}
```

| Field             | Type                                    | Notes |
|-------------------|-----------------------------------------|-------|
| `prices`          | `Record<ActionType, Record<Tier, number>>` | Reward paid per completion. Action types: `LIKE`, `RT`, `COMMENT`, `FOLLOW`, `COMMENT_LIKE`. Tiers: `A`, `B`, `C`, `D`, `E`. Tier `S` is not a buyer-selectable tier via the open API. |
| `platformFeeRate` | number                                  | Fee on top of `totalBudget` when creating an Engagement campaign. Currently fixed at `0.05` (5%). |
| `currency`        | string                                  | Always `"newLUX"`. |

### Computing expected cost

```
totalBudget   = Σ over actions Σ over tiers  slots[tier] × prices[action][tier]
platformFee   = totalBudget × platformFeeRate
totalCost     = totalBudget + platformFee
```

---

## 3. POST /campaigns/engagement

Create an Engagement (Like / RT / Comment / Follow / Comment+Like) campaign.

**Important — cost is server-calculated.** You do NOT send a budget. The server
multiplies each tier's slot count by the price table returned from
`GET /pricing`, sums across all actions, and adds a 5% platform fee. The
resulting `totalCost` is debited from the user's LUX balance.

- **Method / path**: `POST /open-api/v1/campaigns/engagement`
- **Required permission**: `campaign:create`
- **Content-Type**: `application/json`

### Request body schema (`CreateEngagementDto`)

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `targetUrl` | string (URL) | yes | Target tweet URL, e.g. `https://x.com/user/status/1234567890`. Validated as a well-formed URL. |
| `actions` | `ActionDto[]` | yes | At least 1 entry. Total tier slots across all actions must be > 0. |
| `actions[].actionType` | enum | yes | One of `LIKE`, `RT`, `COMMENT`, `FOLLOW`, `COMMENT_LIKE`. |
| `actions[].tierSlots` | object | no | Map of tier → slot count. Keys must be in `{A, B, C, D, E}`; values are non-negative integers. Missing tiers count as 0. Absent / null / omitted is treated as all-zero for that action. |
| `expiresInHours` | integer (≥ 1) | no | Campaign lifetime in hours. Default `8`. |

### Validation rules (from DTO validators)

- **`targetUrl`** — required, must be a valid URL (`IsUrl`).
- **`actions`** — array, min size 1 (`ArrayMinSize(1)`).
- **`tierSlots` shape** — object only; keys restricted to `A/B/C/D/E`; values
  must be non-negative integers (`TierSlotsValidator`).
- **Non-empty slots** — summed across every action and tier, total slots must
  be strictly greater than 0. Otherwise:
  `EMPTY_TIER_SLOTS: at least one action must have positive tier slots`.
- **Action conflict** — `COMMENT_LIKE` cannot be combined with standalone
  `LIKE` or `COMMENT` in the same request. Otherwise:
  `COMMENT_LIKE cannot be combined with standalone LIKE or COMMENT`.
  (`COMMENT_LIKE` alone, or combined with `RT`/`FOLLOW`, is fine.)
- **`expiresInHours`** — optional; if present, must be ≥ 1.

### Example: compute `totalCost` before posting

For `actions = [{ actionType: "LIKE", tierSlots: { A: 5, B: 10 } }]` with the
default pricing:

```
totalBudget = 5 × 0.4  +  10 × 0.3  =  2.0 + 3.0  =  5.0
platformFee = 5.0 × 0.05             =  0.25
totalCost   = 5.0 + 0.25             =  5.25
```

The server will reject the request with HTTP 400
`"Insufficient LUX balance"` if `totalCost > totalLux`.

### curl

```bash
curl -sS -X POST "$LIGHTHOUSE_API_BASE/campaigns/engagement" \
  -H "X-API-Key: $LIGHTHOUSE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "targetUrl": "https://x.com/user/status/1234567890",
    "actions": [
      { "actionType": "LIKE", "tierSlots": { "A": 5, "B": 10 } },
      { "actionType": "RT",   "tierSlots": { "A": 2 } }
    ],
    "expiresInHours": 8
  }'
```

### Response 201 (`CampaignResponseDto`)

```json
{
  "id": "clxyz123abc",
  "status": "ACTIVE",
  "type": "ENGAGEMENT",
  "targetUrl": "https://x.com/user/status/1234567890",
  "totalBudget": 45.0,
  "platformFee": 2.25,
  "totalCost": 47.25,
  "actions": [
    {
      "actionType": "LIKE",
      "baseReward": 0.4,
      "targetCount": 15,
      "tierSlots": { "A": 5, "B": 10 }
    },
    {
      "actionType": "RT",
      "baseReward": 20,
      "targetCount": 2,
      "tierSlots": { "A": 2 }
    }
  ],
  "createdAt": "2026-04-20T10:30:00.000Z",
  "expiresAt": "2026-04-20T18:30:00.000Z"
}
```

| Response field | Type | Notes |
|----------------|------|-------|
| `id` | string | Campaign ID. Use this for follow-up `GET` calls. |
| `status` | enum | One of `ACTIVE`, `PAUSED`, `ENDED`, `CLOSED`. Newly created campaigns start in `ACTIVE`. |
| `type` | string | Always `ENGAGEMENT` for this endpoint. |
| `targetUrl` | string? | Echo of the request URL. |
| `totalBudget` | number | Sum of `slots × price` across all actions, exclusive of fee. |
| `platformFee` | number? | 5% of `totalBudget`. Returned on create; may be omitted on read responses. |
| `totalCost` | number? | `totalBudget + platformFee`. Returned on create; this is the amount debited from LUX. |
| `actions[].actionType` | string | Echoed from request. |
| `actions[].baseReward` | number | Per-completion reward (A-tier price). |
| `actions[].targetCount` | integer | Total slots across all tiers for this action. |
| `actions[].tierSlots` | object? | Echo of request tier breakdown — returned on create. |
| `createdAt` / `expiresAt` | ISO-8601 string | UTC timestamps. |

---

## 4. GET /campaigns/:id

Fetch a single campaign owned by the API key's user, including live
completion counts.

- **Method / path**: `GET /open-api/v1/campaigns/{id}`
- **Required permission**: `campaign:read`

### Path params

| Name | Type   | Required | Description |
|------|--------|:--------:|-------------|
| `id` | string |    yes   | Campaign ID as returned by create. |

### curl

```bash
curl -sS "$LIGHTHOUSE_API_BASE/campaigns/clxyz123abc" \
  -H "X-API-Key: $LIGHTHOUSE_API_KEY"
```

### Response 200 (`CampaignResponseDto`)

```json
{
  "id": "clxyz123abc",
  "status": "ACTIVE",
  "type": "ENGAGEMENT",
  "targetUrl": "https://x.com/user/status/1234567890",
  "totalBudget": 45.0,
  "consumedBudget": 12.5,
  "remainingPool": 32.5,
  "actions": [
    {
      "actionType": "LIKE",
      "baseReward": 0.4,
      "targetCount": 15,
      "completedCount": 7
    },
    {
      "actionType": "RT",
      "baseReward": 20,
      "targetCount": 2,
      "completedCount": 0
    }
  ],
  "createdAt": "2026-04-20T10:30:00.000Z",
  "expiresAt": "2026-04-20T18:30:00.000Z"
}
```

| Response field | Type | Notes |
|----------------|------|-------|
| `consumedBudget` | number? | LUX already paid out to sellers. Typical for read responses. |
| `remainingPool` | number? | LUX still available for rewards. |
| `actions[].completedCount` | integer? | Number of completed participants for this action. |
| `platformFee` / `totalCost` / `actions[].tierSlots` | — | Not guaranteed to be present on read; prefer the create response to capture these. |

On an unknown or cross-tenant ID, the backend responds with 404 (the service
layer raises `NotFoundException`; treat as a `CAMPAIGN_NOT_FOUND`-style
condition).

---

## 5. GET /campaigns

Paginated list of Engagement campaigns owned by the API key's user, newest
first.

- **Method / path**: `GET /open-api/v1/campaigns`
- **Required permission**: `campaign:read`

### Query params (`QueryCampaignsDto`)

| Name | Type | Required | Default | Description |
|------|------|:--------:|---------|-------------|
| `status` | enum | no | — | One of `ACTIVE`, `PAUSED`, `ENDED`, `CLOSED`. Omit to include all. |
| `page` | integer (≥ 1) | no | `1` | 1-based page number. |
| `pageSize` | integer (1–100) | no | `20` | Items per page; server rejects values > 100. |

### curl

```bash
curl -sS "$LIGHTHOUSE_API_BASE/campaigns?status=ACTIVE&page=1&pageSize=20" \
  -H "X-API-Key: $LIGHTHOUSE_API_KEY"
```

### Response 200 (`PaginatedCampaignResponseDto`)

```json
{
  "items": [
    {
      "id": "clxyz123abc",
      "status": "ACTIVE",
      "type": "ENGAGEMENT",
      "targetUrl": "https://x.com/user/status/1234567890",
      "totalBudget": 45.0,
      "consumedBudget": 12.5,
      "remainingPool": 32.5,
      "actions": [
        {
          "actionType": "LIKE",
          "baseReward": 0.4,
          "targetCount": 15,
          "completedCount": 7
        }
      ],
      "createdAt": "2026-04-20T10:30:00.000Z",
      "expiresAt": "2026-04-20T18:30:00.000Z"
    }
  ],
  "total": 1,
  "page": 1,
  "pageSize": 20
}
```

| Field | Type | Description |
|-------|------|-------------|
| `items` | `CampaignResponseDto[]` | Each item is the same shape as `GET /campaigns/:id`. |
| `total` | integer | Total matching campaigns across all pages. |
| `page` | integer | Echoed page. |
| `pageSize` | integer | Echoed page size. |

---

## Error Codes

Guard and interceptor errors carry a stable `code` string. DTO validation
failures are plain Nest `BadRequestException`s (no `code`, just a `message`
array).

| HTTP | Code | Source | Meaning | Suggested agent action |
|------|------|--------|---------|------------------------|
| 401  | `INVALID_API_KEY`       | `ApiKeyGuard` | Missing header, unknown key, or `isActive=false`. | Stop. Ask the user for a valid `lh_live_*` key; do not retry. |
| 401  | `API_KEY_EXPIRED`       | `ApiKeyGuard` | `expiresAt` has passed. | Stop. Ask the user to rotate the key. |
| 403  | `PERMISSION_DENIED`     | `ApiKeyGuard` | Key lacks a required scope (`balance:read`, `campaign:read`, `campaign:create`). | Stop. Tell the user which scope is needed. |
| 429  | `RATE_LIMIT_EXCEEDED`   | `OpenApiRateLimitInterceptor` | Per-key quota exhausted. Response includes `X-RateLimit-*` headers. | Wait until `X-RateLimit-Reset`, then retry. Back off on repeated hits. |
| 400  | _(no code)_             | `class-validator` | DTO validation. `message` is an array of human-readable strings, e.g. `"targetUrl must be a valid URL"`, `"EMPTY_TIER_SLOTS: at least one action must have positive tier slots"`, `"COMMENT_LIKE cannot be combined with standalone LIKE or COMMENT"`. | Read every entry of `message`. Fix the specific field; do not retry unchanged. |
| 400  | _(no code)_             | Service layer | `message === "Insufficient LUX balance"` — budget exceeds balance. | Call `GET /balance`, reduce `tierSlots`, or ask the user to top up. Do not retry the identical request. |
| 404  | _(no code)_             | Service layer | Campaign not found, or not owned by this API key's user. | Verify the ID; do not retry. |

Note: the backend does **not** emit HTTP 422. NestJS default validation uses
400, so any reference to 422 in older docs is incorrect.

---

## Notes on balance checking before create-engagement

The server rejects an over-budget `POST /campaigns/engagement` with a plain
HTTP 400 carrying the literal message `"Insufficient LUX balance"` — there is
no dedicated error code, and the rejection happens after the DTO is accepted.
Agents should avoid this failure mode proactively:

1. `GET /pricing` to fetch the current price table and `platformFeeRate`.
2. Compute the expected cost locally:
   ```
   totalBudget = Σ slots[tier] × prices[action][tier]
   totalCost   = totalBudget × (1 + platformFeeRate)
   ```
3. `GET /balance` and check `totalCost ≤ totalLux`.
4. Only then `POST /campaigns/engagement`.

This sequence also lets the agent present the user an accurate cost estimate
before spending LUX.
