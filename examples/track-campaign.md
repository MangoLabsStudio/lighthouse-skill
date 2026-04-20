# Example: Track Active Campaigns

Scenario — the buyer wants a quick status check on their recently created
campaigns, then drills into one of them.

---

**User:**

看看我最近创建的任务进度如何。

**Agent:**

好，拉一下当前 ACTIVE 的活动列表。

```bash
$ ./scripts/lighthouse campaigns list --status ACTIVE
```

```json
{
  "items": [
    {
      "id": "clkg7x9p20001abcd",
      "status": "ACTIVE",
      "type": "ENGAGEMENT",
      "targetUrl": "https://x.com/foo/status/123",
      "totalBudget": 170,
      "consumedBudget": 62,
      "remainingPool": 108,
      "actions": [
        { "actionType": "LIKE", "baseReward": 0.4, "targetCount": 50, "completedCount": 45 },
        { "actionType": "RT",   "baseReward": 20,  "targetCount": 20, "completedCount": 2  }
      ],
      "createdAt": "2026-04-19T09:12:03.000Z",
      "expiresAt": "2026-04-19T17:12:03.000Z"
    },
    {
      "id": "clkg8a1kz0004efgh",
      "status": "ACTIVE",
      "type": "ENGAGEMENT",
      "targetUrl": "https://x.com/bar/status/456",
      "totalBudget": 77,
      "consumedBudget": 19,
      "remainingPool": 58,
      "actions": [
        { "actionType": "LIKE",   "baseReward": 0.4, "targetCount": 100, "completedCount": 30 },
        { "actionType": "FOLLOW", "baseReward": 12,  "targetCount": 4,   "completedCount": 1  }
      ],
      "createdAt": "2026-04-19T10:45:11.000Z",
      "expiresAt": "2026-04-19T18:45:11.000Z"
    },
    {
      "id": "clkg8m2nq0007ijkl",
      "status": "ACTIVE",
      "type": "ENGAGEMENT",
      "targetUrl": "https://x.com/baz/status/789",
      "totalBudget": 300,
      "consumedBudget": 0,
      "remainingPool": 300,
      "actions": [
        { "actionType": "RT", "baseReward": 20, "targetCount": 15, "completedCount": 0 }
      ],
      "createdAt": "2026-04-19T11:30:44.000Z",
      "expiresAt": "2026-04-19T19:30:44.000Z"
    }
  ],
  "total": 3,
  "page": 1,
  "pageSize": 20
}
```

一共 3 条 ACTIVE：

| # | 目标 | 动作进度 | 预算使用 | 到期 |
|---|------|---------|---------|------|
| 1 | foo/status/123 | LIKE 45/50 (90%)·RT 2/20 (10%) | 62 / 170 LUX | 17:12 UTC |
| 2 | bar/status/456 | LIKE 30/100 (30%)·FOLLOW 1/4 (25%) | 19 / 77 LUX | 18:45 UTC |
| 3 | baz/status/789 | RT 0/15 (0%) | 0 / 300 LUX | 19:30 UTC |

第 1 条点赞几乎打满，转发还没起量；第 2 条进度正常；第 3 条刚发出去，还
没被接单。

**User:**

那第二条具体多少。

**Agent:**

```bash
$ ./scripts/lighthouse campaigns get clkg8a1kz0004efgh
```

```json
{
  "id": "clkg8a1kz0004efgh",
  "status": "ACTIVE",
  "type": "ENGAGEMENT",
  "targetUrl": "https://x.com/bar/status/456",
  "totalBudget": 77,
  "consumedBudget": 19,
  "remainingPool": 58,
  "actions": [
    {
      "actionType": "LIKE",
      "baseReward": 0.4,
      "targetCount": 100,
      "completedCount": 30,
      "tierSlots": { "A": 50, "B": 50 }
    },
    {
      "actionType": "FOLLOW",
      "baseReward": 12,
      "targetCount": 4,
      "completedCount": 1,
      "tierSlots": { "A": 2, "B": 2 }
    }
  ],
  "createdAt": "2026-04-19T10:45:11.000Z",
  "expiresAt": "2026-04-19T18:45:11.000Z"
}
```

明细：

- **LIKE**：100 个席位（A=50, B=50），已完成 30，单价 A=0.4 / B=0.3 LUX（50×0.4 + 50×0.3 = 35 LUX）
- **FOLLOW**：4 个席位（A=2, B=2），已完成 1，单价 A=12 / B=9 LUX（2×12 + 2×9 = 42 LUX）
- 总预算 77 LUX，已结算 19 LUX，池子里还剩 58 LUX
- 到期前还有 ~8 小时，按当前节奏 LIKE 能跑完，FOLLOW 可能吃紧

要不要补一条更大的 LIKE 活动或者延长 FOLLOW？
