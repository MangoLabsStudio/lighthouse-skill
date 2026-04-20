# Example: End-to-End Buy Engagement

Scenario — the buyer wants engagement on a specific tweet with a fixed LUX
budget. The Agent translates intent into `tierSlots`, presents a cost
breakdown, and only posts after explicit confirmation.

---

**User:**

帮我给 https://x.com/foo/status/123 买 50 个赞和 20 转发，预算控制在 200 LUX。

**Agent:**

好的。在发起之前我先确认一下余额和当前价格表。

```bash
$ ./scripts/lighthouse balance
```

```json
{
  "oldLux": 0,
  "newLux": 500,
  "totalLux": 500
}
```

```bash
$ ./scripts/lighthouse pricing
```

```json
{
  "prices": {
    "LIKE": { "A": 0.4, "B": 0.3, "C": 0.2, "D": 0.1, "E": 0.1 },
    "RT":   { "A": 20,  "B": 15,  "C": 10,  "D": 5,   "E": 5   },
    "COMMENT":      { "A": 0.8, "B": 0.6, "C": 0.4, "D": 0.1, "E": 0.1 },
    "FOLLOW":       { "A": 12,  "B": 9,   "C": 6,   "D": 3,   "E": 3   },
    "COMMENT_LIKE": { "A": 1.2, "B": 0.9, "C": 0.6, "D": 0.2, "E": 0.2 }
  },
  "platformFeeRate": 0.05,
  "currency": "newLUX"
}
```

余额 500 LUX，够用。不过 50 赞 + 20 转发如果全部走 A 档要 `50×0.4 + 20×20
= 20 + 400 = 420` LUX，超预算太多。赞的单价很便宜，所以我打算 **点赞全部
A 档保证质量**，转发则下沉到 C/D 档把总价压进 200 LUX。

我的方案：

- LIKE：A=50 (50×0.4 = 20 LUX)
- RT：C=10, D=10 (10×10 + 10×5 = 150 LUX)

合计 170 LUX + 5% 手续费 = 178.5 LUX，留 21.5 LUX 余量。过期时间沿用后端
默认 8 小时。

```
─ Target tweet: https://x.com/foo/status/123
─ Actions:
  · LIKE → A:50        → 50×0.4 = 20 LUX
  · RT   → C:10, D:10  → 10×10 + 10×5 = 150 LUX
─ Subtotal: 170 LUX
─ Platform fee (5%): 8.5 LUX
─ Total cost: 178.5 LUX
─ Balance after: 321.5 LUX
─ Expiration: default 8h
```

是否确认创建？(yes/no)

**User:**

确认

**Agent:**

好，开始创建。

```bash
$ ./scripts/lighthouse campaigns create-engagement \
    --url https://x.com/foo/status/123 \
    --action LIKE:A=50 \
    --action RT:C=10,D=10
```

```json
{
  "id": "clkg7x9p20001abcd",
  "status": "ACTIVE",
  "type": "ENGAGEMENT",
  "targetUrl": "https://x.com/foo/status/123",
  "totalBudget": 170,
  "platformFee": 8.5,
  "totalCost": 178.5,
  "actions": [
    {
      "actionType": "LIKE",
      "baseReward": 0.4,
      "targetCount": 50,
      "tierSlots": { "A": 50 }
    },
    {
      "actionType": "RT",
      "baseReward": 20,
      "targetCount": 20,
      "tierSlots": { "C": 10, "D": 10 }
    }
  ],
  "createdAt": "2026-04-19T09:12:03.000Z",
  "expiresAt": "2026-04-19T17:12:03.000Z"
}
```

创建成功。

- Campaign ID：`clkg7x9p20001abcd`
- 实际扣款：178.5 LUX（剩余 321.5 LUX）
- 状态：ACTIVE，17:12 UTC 过期（8 小时窗口）

接下来你可以随时用 `./scripts/lighthouse campaigns get clkg7x9p20001abcd`
查看完成进度。
