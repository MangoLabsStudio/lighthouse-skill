# Pricing & Tiers Reference

Canonical reference for how Lighthouse prices Engagement tasks, what each KOL tier means, and how an Agent should translate a buyer's natural-language intent into the real API's `actions[].tierSlots` input before calling `POST /open-api/v1/campaigns/engagement`.

All prices are in **newLUX** (the platform reward token). For endpoint-level request/response details, see `api-reference.md`. This doc only covers pricing math and tier selection.

---

## 1. Fee formula

The Engagement endpoint takes `actions: [{ actionType, tierSlots: { A, B, C, D, E } }]` — it does **not** accept `totalBudget` or `targetCount`. The server derives the budget from `tierSlots` × the current price table, then adds a flat **5% platform fee**.

```
computed_budget = Σ_action Σ_tier ( tierSlots[action][tier] × price[action][tier] )
platformFee     = computed_budget × 0.05
totalCost       = computed_budget × 1.05          ← debited from buyer's LUX wallet
```

**Worked example — single action, two tiers**

```
actions = [
  { actionType: "LIKE", tierSlots: { A: 50, B: 100 } }
]

computed_budget = 50 × 0.4  +  100 × 0.3
                = 20        +  30
                = 50.0   newLUX

platformFee     = 50.0 × 0.05   =  2.5   newLUX
totalCost       = 50.0 × 1.05   = 52.5   newLUX
```

The buyer pays **52.5 newLUX**. Sellers collectively earn up to **50.0 newLUX** as the 150 slots are filled.

**Source**
- `kol-dao-service/src/modules/unified-campaign/service/campaign.service.ts:141-149` — fee rate selection, `totalCost = totalSpend + platformFee`.
- `kol-dao-service/src/modules/open-api/open-api.service.ts:210` — `platformFeeRate: 0.05` returned by `/pricing`.
- `kol-dao-service/src/modules/open-api/dto/pricing-response.dto.ts:17-18` — contract: *"平台手续费率（Engagement 固定 5%）"*.

---

## 2. Tier semantics (S / A / B / C / D / E)

Tiers classify KOL sellers by influence and reputation. Higher tier = broader reach, higher per-action reward, scarcer supply. The trade-off is always **quality × reach vs. cost**. Tier assignment is maintained by the KOL power-score / reputation pipeline; this doc only covers how a buyer should think about them.

| Tier | Meaning for a buyer |
|------|---------------------|
| **S** | Top-tier KOLs, premium reach. **Not eligible on the Engagement endpoint** — `tierSlots` only accepts A–E. S deals go through Tweet-creation campaigns or hand-negotiated flows. |
| **A** | Established KOLs with reliable audience. The "list-price" tier — the default choice when the buyer wants quality and hasn't specified otherwise. |
| **B** | Mid-tier KOLs with solid delivery. Balanced reach-vs-cost sweet spot. |
| **C** | Growing accounts, lower reach but active. Good for amplification rounds. |
| **D** | Small accounts, entry-level delivery. Cheap reach, long-tail exposure. |
| **E** | Floor tier. Maximum volume at minimum cost; lowest quality guarantee. Priced identically to D in the default table. |

**Source**
- Tier enum: `kol-dao-service/prisma/schema.prisma` (`Tier` enum).
- S/E exclusion rationale: `kol-dao-service/src/modules/unified-campaign/constants.ts:7-13` header comment — S is not exposed on Engagement; E mirrors D's floor.
- `tierSlots` DTO keys restricted to A–E: `kol-dao-service/src/modules/open-api/dto/create-engagement.dto.ts`.

---

## 3. Full pricing table

Default per-action reward paid to a seller of the given tier, in newLUX.

| Action         | A    | B    | C    | D    | E    |
|----------------|------|------|------|------|------|
| `LIKE`         | 0.4  | 0.3  | 0.2  | 0.1  | 0.1  |
| `COMMENT`      | 0.8  | 0.6  | 0.4  | 0.1  | 0.1  |
| `RT`           | 20   | 15   | 10   | 5    | 5    |
| `FOLLOW`       | 12   | 9    | 6    | 3    | 3    |
| `COMMENT_LIKE` | 1.2  | 0.9  | 0.6  | 0.2  | 0.2  |

**Source**
- Contract example: `kol-dao-service/src/modules/open-api/dto/pricing-response.dto.ts:7-13`.
- Runtime defaults: `kol-dao-service/src/modules/unified-campaign/constants.ts:7-13` (`DEFAULT_TIER_ACTION_PRICE`).
- Admin override: `SystemConfig.unified_campaign_pricing` (key defined in `constants.ts`).

### Prices are dynamic — always call `/pricing` first

The numbers above are **defaults**. Admin can edit the table at runtime; cached for 60 seconds server-side.

- Loader: `kol-dao-service/src/modules/unified-campaign/service/campaign-pricing.service.ts:17-47` — checks `SystemConfig.unified_campaign_pricing`, falls back to the constants above, 60s in-memory cache.
- Public endpoint: `GET /open-api/v1/pricing` → `{ prices, platformFeeRate, currency }`. See `api-reference.md`.

**Agent rule:** call `GET /pricing` **once per session** and reuse the result. Never hard-code the numbers above in computed totals shown to the user.

---

## 4. Budget estimation heuristic (Agent behavior)

This is the core translation layer. The buyer speaks in natural language ("buy me 100 likes for 50 LUX"); the API speaks in `tierSlots`. The Agent is responsible for the mapping, and must show the user the computed cost **before** calling `POST /campaigns/engagement`.

### Step 1 — Fetch the price table

```
GET /open-api/v1/pricing
```

Cache the `prices` and `platformFeeRate` for the rest of the session.

### Step 2 — Classify the intent

Pattern-match the buyer's request into one of four shapes:

| Intent shape | What the buyer gave you | Default strategy |
|--------------|-------------------------|------------------|
| **count + budget** | "100 likes for 50 LUX" | Maximize count within budget; fill cheaper tiers first. |
| **count only** | "I want 100 likes" | Quote the all-A plan (quality default); offer a cheaper fallback. |
| **budget only** | "I have 100 LUX for engagement" | Ask which action type, then A-tier single-action. |
| **tier preference** | "only A or B" | Constrain to those tiers; within the constraint, use the strategy above. |

### Step 3 — Compute `tierSlots`

**Shape 1: count + budget**

Goal: deliver the requested count without exceeding the budget (pre-fee). Strategy: prefer higher tiers for quality; only dilute to cheaper tiers if the budget forces it.

```
target_gross = budget / 1.05        # back out the 5% fee to get the pre-fee ceiling
cost_all_A   = count × price[action][A]
```

- If `cost_all_A ≤ target_gross` → propose all-A: `{ action: { A: count } }`.
- Else → walk tiers A → B → C → D → E until the plan fits. A simple deterministic rule that works: split between the best tier that fits and the next-cheaper tier.

**Worked example 1a — fits in A-tier**

Intent: "100 likes, budget 50 LUX"

```
target_gross  = 50 / 1.05 ≈ 47.619
cost_all_A    = 100 × 0.4 = 40.0          ≤ 47.619  ✓

Plan:         actions = [{ LIKE, tierSlots: { A: 100 } }]
computed     = 100 × 0.4 = 40.0
platformFee  = 40.0 × 0.05 = 2.0
totalCost    = 42.0 newLUX                (under 50 LUX budget ✓)
```

**Worked example 1b — doesn't fit in A-tier**

Intent: "100 likes, budget 30 LUX"

```
target_gross  = 30 / 1.05 ≈ 28.571
cost_all_A    = 100 × 0.4 = 40.0          > 28.571  ✗ (need cheaper mix)

Try 50 A + 50 E:
  cost        = 50 × 0.4 + 50 × 0.1 = 20 + 5 = 25.0   ≤ 28.571  ✓

Plan:         actions = [{ LIKE, tierSlots: { A: 50, E: 50 } }]
computed     = 25.0
platformFee  = 25.0 × 0.05 = 1.25
totalCost    = 26.25 newLUX               (under 30 LUX budget ✓)
```

If even all-E overshoots the budget (e.g. "200 likes, 15 LUX": all-E = 20 LUX > 14.285), the Agent must **tell the user the count isn't achievable within budget** and offer two concrete alternatives (reduce count, or increase budget). Never silently truncate.

**Shape 2: count only** — default to all-A, show the cost, offer a cheaper fallback.

Intent: "I want 500 retweets"

```
Proposal A (quality):
  actions = [{ RT, tierSlots: { A: 500 } }]
  computed = 500 × 20 = 10000
  totalCost = 10500 newLUX

Proposal B (budget):
  actions = [{ RT, tierSlots: { C: 500 } }]
  computed = 500 × 10 = 5000
  totalCost = 5250 newLUX
```

Present both, ask the user to pick.

**Shape 3: budget only** — ask which action. Once they answer, quote the A-tier volume that budget buys.

Intent: "I have 100 LUX, what can I get?" → reply: "Which action — LIKE, RT, COMMENT, FOLLOW, or COMMENT_LIKE?"

If the user says "LIKE":
```
target_gross = 100 / 1.05 ≈ 95.238
A-tier max   = floor(95.238 / 0.4) = 238 likes

Plan:        actions = [{ LIKE, tierSlots: { A: 238 } }]
computed     = 238 × 0.4 = 95.2
totalCost    = 99.96 newLUX
```

**Shape 4: tier preference** — constrain the tier set, then re-run the relevant shape above.

Intent: "100 likes, only A or B, budget 35 LUX"

```
target_gross = 35 / 1.05 ≈ 33.333
all-A        = 40.0    ✗
all-B        = 30.0    ✓ (fits)

Plan:        actions = [{ LIKE, tierSlots: { B: 100 } }]
totalCost    = 31.5 newLUX
```

(A mix like `{ A: 30, B: 70 }` = 12 + 21 = 33 is also valid; either is defensible — pick one and show it.)

### Step 4 — Always show the final plan before confirming

Render the proposed order in a fixed, readable shape:

```
Action        Tier  Slots  Unit price  Subtotal
LIKE           A      50      0.4        20.0
LIKE           B     100      0.3        30.0
                                         -----
computed_budget                           50.0
platform fee (5%)                          2.5
───────────────────────────────────────────────
totalCost                                 52.5 newLUX
```

Get an explicit **yes/no** from the user, then call `POST /campaigns/engagement` with `{ targetUrl, actions, expiresInHours? }`.

### Judgment calls left to the Agent

- **Which mix to prefer when multiple fit** — bias toward A-tier when the budget allows. When it doesn't, prefer a two-tier split (A + one cheaper tier) over a three- or four-tier spread; it's easier for the user to reason about.
- **How many fallback proposals to show** — usually two (quality default + budget fallback). Don't flood the user with five variants.
- **Rounding** — slots are integers. Always `floor` when dividing budget by unit price; never round up, or you'll exceed the budget.

---

## 5. Expiration defaults

The Engagement endpoint accepts an optional `expiresInHours`. Backend default is **8 hours**.

| Flavor        | `expiresInHours` | When to use |
|---------------|------------------|-------------|
| **Default**   | **8**            | Standard campaigns. Backend default — fires if the buyer omits the field. |
| **Urgent**    | **2–4**          | Time-boxed pushes (launch window, news spike). Buyer sets explicitly. |
| **Long-tail** | **24**           | Campaigns that benefit from overnight KOL pickup across time zones. Buyer sets explicitly. |

**Source**
- 8h default: `kol-dao-service/src/modules/unified-campaign/service/campaign.service.ts:249-251` —
  ```ts
  expiresAt: type === CampaignTypeV2.ENGAGEMENT
    ? new Date(Date.now() + 8 * 60 * 60 * 1000) // 8小时后自动关闭
    : null,
  ```
- 2–4h "urgent" and 24h "long-tail" are product-level recommendations, not enforced presets. Any positive integer is accepted.

---

## Quick lookups

- Pricing endpoint (runtime truth): `GET /open-api/v1/pricing` → `{ prices, platformFeeRate: 0.05, currency: "newLUX" }`.
- Fee rate for Engagement: `0.05` (`campaign.service.ts:141-145`).
- Price cache TTL: 60s (`campaign-pricing.service.ts:13`).
- Pricing override key: `SystemConfig.unified_campaign_pricing` (`constants.ts`).
- Request DTO (source of truth for Agent input shape): `kol-dao-service/src/modules/open-api/dto/create-engagement.dto.ts`.
- Endpoint-level request/response details: see `api-reference.md`.
