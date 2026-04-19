# Pricing & Tiers Reference

Canonical reference for how Lighthouse prices Engagement tasks, what each KOL tier means, and how a buyer should estimate a budget before posting an order.

All prices are in **newLUX** (the platform reward token).

---

## 1. Platform fee — 5% on Engagement

Engagement campaigns (LIKE / RT / COMMENT / FOLLOW / COMMENT_LIKE) are charged a flat **5% platform fee** on top of the order budget. Tweet-creation campaigns use 10%; redemption codes waive the fee entirely — those are out of scope for this doc.

**Formula**

```
platformFee = totalBudget × 0.05
totalCost   = totalBudget × 1.05
```

- `totalBudget` is the sum the sellers (KOLs) are eligible to earn — i.e. `Σ (baseReward × targetCount)` across all actions.
- `totalCost` is what the buyer actually pays out of their LUX wallet at publish time.

**Source**
- `kol-dao-service/src/modules/unified-campaign/service/campaign.service.ts:141-149` — fee rate selection and `totalCost = totalSpend + platformFee`.
- `kol-dao-service/src/modules/open-api/open-api.service.ts:210` — `platformFeeRate: 0.05` returned by the public pricing endpoint.
- `kol-dao-service/src/modules/open-api/dto/pricing-response.dto.ts:17-18` — API contract: `"平台手续费率（Engagement 固定 5%）", example: 0.05`.

**Worked example**

Buyer wants `{ LIKE: 100 slots at A-tier }` → baseReward for A-tier LIKE is `0.4`.

```
totalBudget = 100 × 0.4      = 40.0  newLUX
platformFee = 40.0 × 0.05    =  2.0  newLUX
totalCost   = 40.0 + 2.0     = 42.0  newLUX  ← debited from buyer's wallet
```

---

## 2. Tier semantics (S / A / B / C / D / E)

Tiers classify KOL sellers by influence quality. Higher tier = broader reach, higher per-action reward, scarcer supply. The tier assignment itself is maintained by the KOL power-score / reputation pipeline (see `users-power-score.service.ts`); this doc focuses on how buyers should think about tiers when allocating slots.

| Tier | Who they are                                          | Typical use case                                                     | Cost (vs. A-tier baseline) |
|------|-------------------------------------------------------|----------------------------------------------------------------------|-----------------------------|
| **S** | Top-tier KOLs, premium reach. **Not used in the fixed Engagement price table** (`[0, 0]`) — S-tier deals are hand-negotiated or routed via Tweet campaigns, not posted as open Engagement slots. | High-stakes product launches, brand campaigns that need signal, not volume. | n/a in Engagement table |
| **A** | Established KOLs with reliable audience. The **default "list price" tier** — open-API docs and budget estimators quote A-tier prices. | Quality-biased orders: you want engagement from accounts that move markets / drive follow-through. | 1.0× (baseline) |
| **B** | Mid-tier KOLs, solid delivery.                        | Balanced reach-vs-cost. The sweet spot for most campaigns.           | ~0.75× A |
| **C** | Growing accounts, lower reach but active.             | Volume + moderate quality; good for amplification rounds.            | ~0.50× A |
| **D** | Small accounts, entry-level delivery.                 | Cheap reach, long-tail exposure, early-stage farming orders.         | ~0.25× A |
| **E** | Bottom tier (entry). Priced identically to D in the default Engagement table. | Maximum volume at minimum cost; quality is not guaranteed.           | ~0.25× A |

**Source**
- Tier enum values: `kol-dao-service/prisma/schema.prisma` (`Tier` enum).
- Default Engagement price table (tier multipliers): `kol-dao-service/src/modules/unified-campaign/constants.ts:7-13` (`DEFAULT_TIER_ACTION_PRICE`). Header comment explicitly states: *"D: LIKE=0.1 COMMENT=0.1 RT=5 FOLLOW=3; C: ×2, B: ×3, A: ×4, S/E: 0（不参与）"* — so S is excluded from the open Engagement price ladder, and E mirrors D's floor price in practice.
- Tier-score weighting (not price): `constants.ts:62-64` — `TIER_SCORE_MAP: { S: 1.0, A: 0.85, B: 0.7, C: 0.55, D: 0.4, E: 0.25 }`.

---

## 3. Default A-tier baseReward (per action)

These are the **fixed unit prices** paid to an A-tier KOL for a single completed action. They are read from `SystemConfig.unified_campaign_pricing` at runtime and fall back to the defaults below when the config is unset.

| Action          | A-tier baseReward (newLUX / action) |
|-----------------|-------------------------------------|
| `LIKE`          | **0.4**                             |
| `COMMENT`       | **0.8**                             |
| `RT`            | **20**                              |
| `FOLLOW`        | **12**                              |
| `COMMENT_LIKE`  | **1.2**                             |

**Full default table (all tiers, for reference)**

| Action         | S        | A    | B    | C    | D    | E    |
|----------------|----------|------|------|------|------|------|
| `LIKE`         | 0 (n/a)  | 0.4  | 0.3  | 0.2  | 0.1  | 0.1  |
| `COMMENT`      | 0 (n/a)  | 0.8  | 0.6  | 0.4  | 0.1  | 0.1  |
| `RT`           | 0 (n/a)  | 20   | 15   | 10   | 5    | 5    |
| `FOLLOW`       | 0 (n/a)  | 12   | 9    | 6    | 3    | 3    |
| `COMMENT_LIKE` | 0 (n/a)  | 1.2  | 0.9  | 0.6  | 0.2  | 0.2  |

**Source**
- `kol-dao-service/src/modules/unified-campaign/constants.ts:7-13` — `DEFAULT_TIER_ACTION_PRICE`. Values are stored as `[min, max]` ranges; all ranges are collapsed (`min === max`) so the "price" is just the single number shown above.
- `kol-dao-service/src/modules/unified-campaign/service/campaign-pricing.service.ts:17-47` — runtime loader: first checks `SystemConfig.unified_campaign_pricing`, falls back to `DEFAULT_TIER_ACTION_PRICE`; `getPrice()` returns `(range[0] + range[1]) / 2`.
- `kol-dao-service/src/modules/open-api/open-api.controller.ts:58-66` — the same numbers are embedded in the public OpenAPI docs for `POST /open-api/v1/campaigns/engagement`.
- Live authoritative source at runtime: `GET /open-api/v1/pricing` (`open-api.service.ts:198-213`).

> **Dynamic override:** Admin can edit the table via `campaignPricingService.updatePriceTable()` → writes `SystemConfig.unified_campaign_pricing`. Price cache TTL is 60 seconds (`campaign-pricing.service.ts:13`). So the numbers above are defaults; production values may drift — always trust `GET /open-api/v1/pricing` for real pricing.

---

## 4. Budget estimation heuristic

**Rule of thumb (A-tier, simple case):**

```
totalBudget ≈ N × baseReward[action][A]
totalCost   ≈ totalBudget × 1.05          # adds the 5% platform fee
```

**Mixed-tier case (what the backend actually computes):**

```
totalBudget = Σ_action Σ_tier ( tierSlots[action][tier] × price[action][tier] )
totalCost   = totalBudget × 1.05
```

The backend auto-computes `totalBudget` from `tierSlots` — buyers do not pass it directly. See `open-api.controller.ts:53-69`.

**Worked example A — single-tier order**

Buyer wants 500 A-tier likes on a tweet:

```
totalBudget = 500 × 0.4    = 200.0  newLUX
platformFee = 200.0 × 0.05 =  10.0  newLUX
totalCost   = 200.0 + 10.0 = 210.0  newLUX
```

**Worked example B — mixed tiers, mixed actions**

`actions = [ { LIKE, tierSlots: { A: 50, B: 100, C: 200 } }, { RT, tierSlots: { A: 10, B: 20 } } ]`

```
LIKE   :  50×0.4 + 100×0.3 + 200×0.2  =  20 + 30 + 40   =  90
RT     :  10×20  + 20×15              =  200 + 300      = 500
totalBudget                                              = 590
platformFee = 590 × 0.05                                 =  29.5
totalCost   = 590 + 29.5                                 = 619.5  newLUX
```

This matches the example the OpenAPI docs walk through at `open-api.controller.ts:68-69` (`5×0.4 + 10×0.3 = 5.0, platformFee = 0.25, totalCost = 5.25`).

---

## 5. Expiration defaults

Engagement campaigns auto-close 8 hours after creation unless the buyer specifies otherwise. This is a hard-coded default in `campaign.service.ts`.

| Flavor        | `expiresAt` from now | When to use                                                                 |
|---------------|----------------------|-----------------------------------------------------------------------------|
| **Default**   | **8 hours**          | Standard campaigns — the system default, enforced in code.                  |
| **Urgent**    | 2–4 hours            | Time-boxed pushes (launch window, news spike). Buyer must set `expiresAt` explicitly. |
| **Long-tail** | 24 hours             | Campaigns that benefit from overnight KOL pickup across time zones. Buyer must set `expiresAt` explicitly. |

**Source**
- 8h default: `kol-dao-service/src/modules/unified-campaign/service/campaign.service.ts:249-251` —
  ```ts
  expiresAt: type === CampaignTypeV2.ENGAGEMENT
    ? new Date(Date.now() + 8 * 60 * 60 * 1000) // 8小时后自动关闭
    : null,
  ```
- 2–4h "urgent" and 24h "long-tail" are product-level recommendations for buyers choosing a custom `expiresAt`; they are not hard-coded presets — the backend accepts any expiration the buyer sets.

---

## Quick lookups

- Pricing endpoint (runtime truth): `GET /open-api/v1/pricing` → returns `{ prices, platformFeeRate: 0.05, currency: "newLUX" }`.
- Fee constant for Engagement: `0.05` (Tweet: `0.10`, Redemption code: `0`) — `campaign.service.ts:141-145`.
- Price cache TTL: 60s (`campaign-pricing.service.ts:13`).
- Pricing override key: `SystemConfig.unified_campaign_pricing` (`constants.ts:72`).
