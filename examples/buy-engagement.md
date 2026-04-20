# Example: End-to-End Buy Engagement

Scenario — the buyer wants engagement on a specific tweet with a fixed LUX
budget. The Agent translates intent into `tierSlots`, presents a cost
breakdown, and only posts after explicit confirmation. Because the request
carries two actions, the server creates two atomic campaigns and the
response is the batch shape.

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

这是两个 action，**后端会原子创建 2 条独立活动**（要么都建成功，要么都回
滚），到时候返回 `campaigns[]` 里会有两个条目。过期时间沿用默认 8 小时，
释放节奏沿用默认 FLAT / 60 min。

```
─ Target tweet: https://x.com/foo/status/123
─ Campaigns to create (atomic): 2
  · #1 LIKE → A:50        → 50×0.4 = 20 LUX
  · #2 RT   → C:10, D:10  → 10×10 + 10×5 = 150 LUX
─ Subtotal: 170 LUX
─ Platform fee (5%): 8.5 LUX
─ Total cost: 178.5 LUX
─ Balance after: 321.5 LUX
─ Release: FLAT / 60 min (default)
─ Expires in: 8h (default)
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
  "campaigns": [
    {
      "id": "clkg7x9p20001abcd",
      "status": "ACTIVE",
      "type": "ENGAGEMENT",
      "targetUrl": "https://x.com/foo/status/123",
      "totalBudget": 20,
      "platformFee": 1,
      "totalCost": 21,
      "actions": [
        {
          "actionType": "LIKE",
          "baseReward": 0.4,
          "targetCount": 50,
          "tierSlots": { "A": 50 }
        }
      ],
      "createdAt": "2026-04-19T09:12:03.000Z",
      "expiresAt": "2026-04-19T17:12:03.000Z"
    },
    {
      "id": "clkg7x9p20002efgh",
      "status": "ACTIVE",
      "type": "ENGAGEMENT",
      "targetUrl": "https://x.com/foo/status/123",
      "totalBudget": 150,
      "platformFee": 7.5,
      "totalCost": 157.5,
      "actions": [
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
  ],
  "totalBudget": 170,
  "platformFee": 8.5,
  "totalCost": 178.5
}
```

创建成功，共 2 条活动：

- `clkg7x9p20001abcd` — LIKE，21 LUX
- `clkg7x9p20002efgh` — RT，157.5 LUX
- 合计扣款 **178.5 LUX**（剩余 321.5 LUX），状态均为 ACTIVE，17:12 UTC 过期

接下来你可以用 `./scripts/lighthouse campaigns get <id>` 分别跟踪这两条活
动的完成进度。
