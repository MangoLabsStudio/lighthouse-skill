# Example: Batch Planning — Per-Item Confirmation

Scenario — the buyer wants the same engagement pattern on several tweets.
The Agent does NOT auto-loop. Every campaign requires its own explicit
confirmation, even when the buyer tries to pre-authorize the batch.

This file demonstrates the safety flow's strength, not its convenience.

---

**User:**

帮我给这 5 条推文各买 100 赞：

- https://x.com/a/status/1
- https://x.com/b/status/2
- https://x.com/c/status/3
- https://x.com/d/status/4
- https://x.com/e/status/5

**Agent:**

明白。先说清楚流程：**我会一条一条来，每条都需要你单独确认。** 这是硬性
安全规则——批量一次授权 5 条等于把钱交给我盲发，不会这么做。

我先把余额和价格拉一次，之后 5 条都复用这份缓存。

```bash
$ ./scripts/lighthouse balance
```

```json
{ "oldLux": 0, "newLux": 350, "totalLux": 350 }
```

```bash
$ ./scripts/lighthouse pricing
```

```json
{
  "prices": {
    "LIKE": { "A": 0.4, "B": 0.3, "C": 0.2, "D": 0.1, "E": 0.1 },
    "RT":   { "A": 20,  "B": 15,  "C": 10,  "D": 5,   "E": 5   }
  },
  "platformFeeRate": 0.05,
  "currency": "newLUX"
}
```

每条推文的提案都一样：

- LIKE：A=100 → 100 × 0.4 = 40 LUX
- 手续费 5% = 2 LUX
- 单条 total = 42 LUX
- 5 条累计 = 210 LUX（在 350 LUX 余额内）

好，开始第 1 条。

---

### #1 — https://x.com/a/status/1

```
─ Target tweet: https://x.com/a/status/1
─ Actions:
  · LIKE → A:100 → 100×0.4 = 40 LUX
─ Subtotal: 40 LUX
─ Platform fee (5%): 2 LUX
─ Total cost: 42 LUX
─ Balance after: 308 LUX
─ Expiration: default 8h
```

是否确认创建？(yes/no)

**User:**

yes

**Agent:**

```bash
$ ./scripts/lighthouse campaigns create-engagement \
    --url https://x.com/a/status/1 --action LIKE:A=100
```

```json
{ "id": "clkh1aa00001", "status": "ACTIVE", "totalCost": 42, ... }
```

第 1 条完成，ID `clkh1aa00001`，余额 308 LUX。接下来第 2 条。

---

### #2 — https://x.com/b/status/2

同样的提案：LIKE A=100，42 LUX，余额将变为 266 LUX。

是否确认创建？(yes/no)

**User:**

yes，剩下的都一样，自动确认跑完吧。

**Agent:**

抱歉，这个不能做。

**安全策略硬性要求每条活动都要单独、显式确认**——哪怕提案完全一样。原因是：
批量授权意味着只要我中间算错一条、URL 粘错、或者价格表在 60 秒后刷新，
你的 LUX 就被我悄悄花掉了，事后无法回滚。

我会继续每条问一次，你只需要回 `yes` 就能快速推进。这样既保留你手动叫停
的权利，也让我每次都把最新余额和提案再核对一遍。

第 2 条的确认问题还在 ↑，需要你回复 yes 才会发。

**User:**

……行吧。yes。

**Agent:**

```bash
$ ./scripts/lighthouse campaigns create-engagement \
    --url https://x.com/b/status/2 --action LIKE:A=100
```

```json
{ "id": "clkh1bb00002", "status": "ACTIVE", "totalCost": 42, ... }
```

第 2 条完成，余额 266 LUX。

---

### #3 — https://x.com/c/status/3

LIKE A=100 → 42 LUX，余额将变为 224 LUX。确认？(yes/no)

**User:**

yes

**Agent:**

```bash
$ ./scripts/lighthouse campaigns create-engagement \
    --url https://x.com/c/status/3 --action LIKE:A=100
```

```json
{ "id": "clkh1cc00003", "status": "ACTIVE", "totalCost": 42, ... }
```

第 3 条完成，余额 224 LUX。

---

### #4 — https://x.com/d/status/4

LIKE A=100 → 42 LUX，余额将变为 182 LUX。确认？(yes/no)

**User:**

yes

**Agent:**

```bash
$ ./scripts/lighthouse campaigns create-engagement \
    --url https://x.com/d/status/4 --action LIKE:A=100
```

```json
{ "id": "clkh1dd00004", "status": "ACTIVE", "totalCost": 42, ... }
```

第 4 条完成，余额 182 LUX。

---

### #5 — https://x.com/e/status/5

LIKE A=100 → 42 LUX，余额将变为 140 LUX。确认？(yes/no)

**User:**

yes

**Agent:**

```bash
$ ./scripts/lighthouse campaigns create-engagement \
    --url https://x.com/e/status/5 --action LIKE:A=100
```

```json
{ "id": "clkh1ee00005", "status": "ACTIVE", "totalCost": 42, ... }
```

第 5 条完成。

---

**汇总：**

| # | Campaign ID | 目标 | 扣款 |
|---|-------------|------|------|
| 1 | clkh1aa00001 | a/status/1 | 42 LUX |
| 2 | clkh1bb00002 | b/status/2 | 42 LUX |
| 3 | clkh1cc00003 | c/status/3 | 42 LUX |
| 4 | clkh1dd00004 | d/status/4 | 42 LUX |
| 5 | clkh1ee00005 | e/status/5 | 42 LUX |

共 5 条 ACTIVE 活动，累计扣款 210 LUX，剩余余额 140 LUX。
