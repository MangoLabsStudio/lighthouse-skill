# lighthouse-skill

Claude Code Skill for the Lighthouse platform — let AI Agents buy Twitter engagement via the Lighthouse Open API.

## What it does

- Check LUX balance + current pricing (tier × action price table, platform fee rate).
- Create Engagement campaigns (`LIKE` / `RT` / `COMMENT` / `FOLLOW` / `COMMENT_LIKE`).
- Track campaigns — list by status, inspect a single campaign's fill progress.
- Built-in **budget translation** — user intent like "100 likes in 50 LUX" is translated into the API's `tierSlots` shape (no free-form budget on the wire).
- Built-in **safety gate** — balance check + per-action cost breakdown + explicit per-item confirmation before any LUX is spent.

## Install

```bash
git clone git@github.com:MangoLabsStudio/lighthouse-skill.git ~/.claude/skills/lighthouse
export LIGHTHOUSE_API_KEY=lh_live_...
# Optional — default is production (https://service.lhdao.top/open-api/v1)
# export LIGHTHOUSE_API_BASE=https://service.lhdaobeta.top/open-api/v1
```

The API key is a bearer credential — export it in your own shell, never paste it into chat.

## Quick test

```bash
./scripts/lighthouse balance
```

Expected output is a JSON object containing `oldLux`, `newLux`, `totalLux`. A `401` / `INVALID_API_KEY` response means the env var is missing or wrong — fix that before running any `POST`.

## Requirements

- `curl`, `jq`
- Claude Code, or any Agent SDK that reads skills from `~/.claude/skills/`

## Demo

![Buying engagement](docs/demo-1.png)

(screenshot pending — see `examples/buy-engagement.md` for the full dialogue)

![Tracking campaigns](docs/demo-2.png)

(screenshot pending — see `examples/track-campaign.md` for the full dialogue)

![Batch planning — safety in action](docs/demo-3.png)

(screenshot pending — see `examples/batch-planning.md` for the full dialogue)

## Safety notes

- API key lives only in env vars; it is never pasted into chat or written to a file. If it leaks, rotate it immediately via the Lighthouse admin UI.
- Every campaign creation requires explicit user confirmation (`yes` / `确认` / `ok` / `确定`). Ambiguous replies re-prompt; they do not count as consent.
- ⚠️ Large-value spends (`total_cost > 500 LUX`) trigger an extra warning line before the confirmation prompt.
- Batch requests ("create these 5 campaigns") are never auto-looped — each item gets its own balance check, cost breakdown, and confirmation.

## Links

- Full skill behavior: [`SKILL.md`](SKILL.md)
- API reference: [`references/api-reference.md`](references/api-reference.md)
- Pricing & tiers: [`references/pricing-and-tiers.md`](references/pricing-and-tiers.md)
- Action combinations: [`references/action-combinations.md`](references/action-combinations.md)
- Examples:
  - [`examples/buy-engagement.md`](examples/buy-engagement.md)
  - [`examples/track-campaign.md`](examples/track-campaign.md)
  - [`examples/batch-planning.md`](examples/batch-planning.md)

## License

MIT. See [`LICENSE`](LICENSE).
