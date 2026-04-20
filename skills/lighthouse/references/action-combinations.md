# Action Combinations

Decision helper for choosing engagement actions when creating a campaign. For the full baseReward tables, see [pricing-and-tiers.md](./pricing-and-tiers.md).

## Available actions

`LIKE`, `COMMENT`, `RT` (retweet), `FOLLOW`, `COMMENT_LIKE` (bundled like+comment, verified as one task).

## Mutex rule — COMMENT_LIKE

**`COMMENT_LIKE` is mutually exclusive with standalone `LIKE` and `COMMENT` in the same campaign.** You may combine it freely with `RT` and `FOLLOW`, but never with a standalone `LIKE` or `COMMENT` action.

Enforced server-side at campaign creation:

- `kol-dao-service/src/modules/unified-campaign/service/campaign.service.ts:51-59` — rejects with `COMMENT_LIKE cannot be combined with standalone LIKE or COMMENT`.
- `kol-dao-service/src/modules/open-api/dto/create-engagement.dto.ts:68-75` — same rule for Open API `/engagements` endpoint.

Rationale: `COMMENT_LIKE` already includes a like, so a standalone `LIKE` on the same target would double-count / double-pay. `COMMENT` is excluded for symmetry and to keep verification logic single-path.

## Cost profile (A-tier baseReward, LUX)

| Action         | A-tier | Relative cost |
| -------------- | -----: | ------------- |
| `LIKE`         |   0.4 | cheapest      |
| `COMMENT`      |   0.8 | cheap         |
| `COMMENT_LIKE` |   1.2 | low           |
| `FOLLOW`       |    12 | expensive     |
| `RT`           |    20 | most expensive |

Tier multipliers and full S/A/B/C/D/E numbers live in `pricing-and-tiers.md`. Non-A tiers scale down but preserve this ordering.

## Recommended combos by goal

| Goal            | Combo                 | Why |
| --------------- | --------------------- | --- |
| Boost visibility | `LIKE` + `RT`         | Algorithmic reach. RT drives impressions; LIKE is cheap filler that boosts engagement signal. |
| Social proof    | `LIKE` + `COMMENT`    | Populates the replies tab and the like counter — what a human visitor notices first. |
| Growth          | `FOLLOW` only         | Single-action campaign. Follower count is the only meaningful metric here; mixing dilutes the budget. |
| Bundled depth   | `COMMENT_LIKE` + `RT` | Every participant likes + comments + retweets. Maximum engagement per seller at ~1.6× the cost of `LIKE`+`RT`. Use when you need deep engagement rather than breadth. |

## Tips

- **Don't over-combine.** Every added action splits per-seller budget; 2-action campaigns usually outperform 4-action ones on completion rate.
- **`FOLLOW` is best alone.** It targets the author account, not a tweet, so pairing it with tweet actions confuses the task UI.
- **`RT` and `FOLLOW` are the only audit-whitelisted actions** (`campaign-audit.service.ts:26`) — others skip audit. Factor this into dispute risk.
