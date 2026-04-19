# Lighthouse Open API Reference

Canonical reference for the Lighthouse Open API v1. Source of truth is the backend
controller at `kol-dao-service/src/modules/open-api/open-api.controller.ts` and its DTOs.

## Base URL

| Environment | Base URL |
|-------------|----------|
| Production  | `https://service.lhdao.top/open-api/v1` |
| Dev / Beta  | `https://service.lhdaobeta.top/open-api/v1` |

Examples below assume the caller has exported:

```bash
export LIGHTHOUSE_API_BASE="https://service.lhdao.top/open-api/v1"
export LIGHTHOUSE_API_KEY="lh_live_xxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

## Authentication

All endpoints require the header `X-API-Key: <key>`. Keys are issued via the
Lighthouse dashboard and are prefixed `lh_live_`. The server hashes the key
(SHA-256) and looks it up; there is no bearer-token flow.

Required header on every request:

```
X-API-Key: $LIGHTHOUSE_API_KEY
```

Each key carries a permission set. The endpoints below declare their required
permission via `@RequireApiPermission(...)`:

| Endpoint                         | Required permission |
|----------------------------------|---------------------|
| `GET /balance`                   | `balance:read`      |
| `POST /campaigns/engagement`     | `campaign:create`   |
| `GET /campaigns/:id`             | `campaign:read`     |
| `GET /campaigns`                 | `campaign:read`     |

## Rate limiting

Per-key sliding window: default 60 requests per 60 seconds (configurable per
key). Every response carries:

- `X-RateLimit-Limit` — per-minute quota for this key
- `X-RateLimit-Remaining` — requests remaining in the current window
- `X-RateLimit-Reset` — unix seconds when the window resets

Exceeding the limit returns HTTP 429 with `{ "code": "RATE_LIMIT_EXCEEDED", ... }`.

## Common error envelope

Errors use a consistent JSON shape (`ErrorResponseDto`):

```json
{
  "code": "INVALID_API_KEY",
  "message": "Missing X-API-Key header",
  "statusCode": 401
}
```

### Known error codes

| Code | HTTP | Meaning | Suggested agent action |
|------|------|---------|------------------------|
| `INVALID_API_KEY` | 401 | Header missing, or key revoked / unknown. | Stop. Ask the user to set `LIGHTHOUSE_API_KEY` to a valid `lh_live_*` key; do not retry. |
| `API_KEY_EXPIRED` | 401 | Key’s `expiresAt` has passed. | Stop. Ask the user to rotate the key in the dashboard. |
| `PERMISSION_DENIED` | 403 | Key lacks the scope required by this route. | Stop. Tell the user which scope is needed (e.g. `campaign:create`). |
| `INSUFFICIENT_BALANCE` | 400 | LUX balance is below `totalBudget + platformFee`. *(From backend: current message is the literal string `Insufficient LUX balance`; treat any 400 containing that substring as this condition.)* | Call `GET /balance`, reduce `tierSlots`, or ask the user to top up. Do not retry the identical request. |
| `RATE_LIMITED` | 429 | Per-key quota exhausted. *(From backend: emitted as `RATE_LIMIT_EXCEEDED`.)* | Wait until `X-RateLimit-Reset`, then retry. Back off on repeated hits. |
| `CAMPAIGN_NOT_FOUND` | 404 | `id` does not belong to this API key’s user. | Verify the ID; do not retry. |
| Validation error (422 / 400) | 422 or 400 | Request body failed `class-validator` checks (e.g. `targetUrl must be a valid URL`, `EMPTY_TIER_SLOTS`, `COMMENT_LIKE cannot be combined with standalone LIKE or COMMENT`). The body may be Nest’s default shape: `{ "statusCode": 400, "message": [ ... ], "error": "Bad Request" }`. | Read every message in `message`. Fix the specific field; do not retry unchanged. |

---

## GET /balance

Query the current LUX balance for the API key’s user.

**Method / path**: `GET /open-api/v1/balance`

**Required permission**: `balance:read`

**Headers**:
- `X-API-Key: $LIGHTHOUSE_API_KEY` (required)

**Request body**: none. **Query params**: none.

### curl

```bash
curl -sS "$LIGHTHOUSE_API_BASE/balance" \
  -H "X-API-Key: $LIGHTHOUSE_API_KEY"
```

### Response 200

```json
{
  "oldLux": 1200.5,
  "newLux": 842.0,
  "totalLux": 2042.5
}
```

| Field      | Type   | Description |
|------------|--------|-------------|
| `oldLux`   | number | Legacy LUX balance (from the `user.lux` column). |
| `newLux`   | number | Labour-earned LUX net of frozen amount (`newLux - frozenNewLux`). |
| `totalLux` | number | `oldLux + newLux`. Use this when deciding whether you can afford a campaign. |

---

## POST /campaigns/engagement

Create an Engagement (Like / RT / Comment / Follow / Comment+Like) campaign.
`totalBudget` is computed server-side from `tierSlots × pricing`, then a 5%
platform fee is charged on top.

**Method / path**: `POST /open-api/v1/campaigns/engagement`

**Required permission**: `campaign:create`

**Headers**:
- `X-API-Key: $LIGHTHOUSE_API_KEY` (required)
- `Content-Type: application/json` (required)

### Request body schema (`CreateEngagementDto`)

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `targetUrl` | string (URL) | yes | Target tweet URL, e.g. `https://x.com/user/status/1234567890`. Validated as a URL. |
| `actions` | `ActionDto[]` | yes | At least 1 entry; total tier slots across all actions must be > 0. |
| `actions[].actionType` | enum | yes | One of `LIKE`, `RT`, `COMMENT`, `FOLLOW`, `COMMENT_LIKE`. `COMMENT_LIKE` cannot be combined with standalone `LIKE` or `COMMENT`. |
| `actions[].tierSlots` | object | no | Map of tier → slot count. Keys must be in `{A,B,C,D,E}`; values are non-negative integers. Missing tiers count as 0. |
| `expiresInHours` | integer (≥ 1) | no | Campaign lifetime in hours. Default `8`. |

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

### Response 201

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
| `status` | enum | One of `ACTIVE`, `PAUSED`, `ENDED`, `CLOSED`. |
| `type` | string | Always `ENGAGEMENT` for this endpoint. |
| `targetUrl` | string? | Echo of the request URL. |
| `totalBudget` | number | Sum of `slots × price` across all actions (excluding fee). |
| `platformFee` | number | 5% of `totalBudget`. **Only present on the create response.** |
| `totalCost` | number | `totalBudget + platformFee`. **Only present on the create response.** This is the amount debited from LUX balance. |
| `actions[]` | array | Per-action breakdown; `tierSlots` is echoed back only on create. |
| `createdAt` / `expiresAt` | ISO-8601 string | UTC timestamps. |

### Pricing (default, newLUX per completion)

| ActionType | A | B | C | D | E |
|------------|---|---|---|---|---|
| LIKE | 0.4 | 0.3 | 0.2 | 0.1 | 0.1 |
| COMMENT | 0.8 | 0.6 | 0.4 | 0.1 | 0.1 |
| RT | 20 | 15 | 10 | 5 | 5 |
| FOLLOW | 12 | 9 | 6 | 3 | 3 |
| COMMENT_LIKE | 1.2 | 0.9 | 0.6 | 0.2 | 0.2 |

The authoritative table is returned by `GET /open-api/v1/pricing`; these values
are the defaults at time of writing.

---

## GET /campaigns/:id

Fetch a single campaign created by the API key’s user, with live completion
counts.

**Method / path**: `GET /open-api/v1/campaigns/{id}`

**Required permission**: `campaign:read`

**Path params**:

| Name | Type | Required | Description |
|------|------|:--------:|-------------|
| `id` | string | yes | Campaign ID as returned by create. |

### curl

```bash
curl -sS "$LIGHTHOUSE_API_BASE/campaigns/clxyz123abc" \
  -H "X-API-Key: $LIGHTHOUSE_API_KEY"
```

### Response 200

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
| `consumedBudget` | number | LUX already paid out to sellers. **Present on read responses only.** |
| `remainingPool` | number | LUX still available for rewards. **Present on read responses only.** |
| `actions[].completedCount` | integer | Number of completed participants per action. **Present on read responses only.** |
| `actions[].tierSlots` | object? | Not returned on read — only on create. |

404 `CAMPAIGN_NOT_FOUND` if the ID does not belong to this API key’s user.

---

## GET /campaigns

Paginated list of Engagement campaigns owned by the API key’s user, newest
first.

**Method / path**: `GET /open-api/v1/campaigns`

**Required permission**: `campaign:read`

### Query params

| Name | Type | Required | Default | Description |
|------|------|:--------:|---------|-------------|
| `status` | enum | no | — | One of `ACTIVE`, `PAUSED`, `ENDED`, `CLOSED`. Omit to include all. |
| `page` | integer (≥ 1) | no | `1` | 1-based page number. |
| `pageSize` | integer (1–100) | no | `20` | Items per page; server clamps at 100. |

### curl

```bash
curl -sS "$LIGHTHOUSE_API_BASE/campaigns?status=ACTIVE&page=1&pageSize=20" \
  -H "X-API-Key: $LIGHTHOUSE_API_KEY"
```

### Response 200

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
| `items` | `CampaignResponseDto[]` | Same shape as `GET /campaigns/:id` (read-mode fields: `consumedBudget`, `remainingPool`, `completedCount`). |
| `total` | integer | Total matching campaigns. |
| `page` | integer | Echoed page. |
| `pageSize` | integer | Echoed page size. |
