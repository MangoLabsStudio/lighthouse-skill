# lighthouse-skill

Claude Code Skill / Plugin for the Lighthouse platform — let AI Agents buy Twitter engagement via the Lighthouse Open API.

## What it does

- Check LUX balance + current pricing (tier × action price table, platform fee rate).
- Create Engagement campaigns (`LIKE` / `RT` / `COMMENT` / `FOLLOW` / `COMMENT_LIKE`).
- Track campaigns — list by status, inspect a single campaign's fill progress.
- Built-in **budget translation** — user intent like "100 likes in 50 LUX" is translated into the API's `tierSlots` shape (no free-form budget on the wire).
- Built-in **safety gate** — balance check + per-action cost breakdown + explicit per-item confirmation before any LUX is spent.

## Install

Pick whichever path matches your setup.

### Option A — Claude Code plugin (recommended for Claude Code users)

```
/plugin marketplace add MangoLabsStudio/lighthouse-skill
/plugin install lighthouse-skill@lighthouse-skill
```

Restart Claude Code after the install so the new skill is picked up.

### Option B — one-line shell install (Agent SDK, Copilot CLI, standalone)

```bash
curl -sSL https://raw.githubusercontent.com/MangoLabsStudio/lighthouse-skill/main/install.sh | bash
```

Clones the repo into `~/.claude/skills/lighthouse`. Override the destination or ref via env vars:

```bash
LIGHTHOUSE_SKILL_DIR=~/my-skills/lighthouse \
LIGHTHOUSE_SKILL_REF=v0.2.0 \
  bash -c "$(curl -sSL https://raw.githubusercontent.com/MangoLabsStudio/lighthouse-skill/main/install.sh)"
```

### Option C — manual git clone (fully auditable)

```bash
git clone https://github.com/MangoLabsStudio/lighthouse-skill.git ~/.claude/skills/lighthouse
```

### After install (all options)

```bash
export LIGHTHOUSE_API_KEY=lh_live_...
~/.claude/skills/lighthouse/scripts/lighthouse balance   # verify setup
```

Expected output is a JSON object containing `oldLux`, `newLux`, `totalLux`. A `401` / `INVALID_API_KEY` response means the env var is missing or wrong — fix that before running any `POST`.

The API key is a bearer credential — export it in your own shell, never paste it into chat.

**Dev env:** the default API base is production (`https://service.lhdao.top/open-api/v1`). To hit the beta backend instead:

```bash
export LIGHTHOUSE_API_BASE=https://service.lhdaobeta.top/open-api/v1
```

## Requirements

- `curl`, `jq`, `git`
- Claude Code, or any Agent SDK that reads skills from `~/.claude/skills/`

## Where things live

This repo ships as a Claude Code plugin. Layout:

```
lighthouse-skill/
├── .claude-plugin/plugin.json          # plugin manifest
├── skills/lighthouse/
│   ├── SKILL.md                        # skill entry point
│   ├── references/                     # API ref, pricing & tiers, action combinations
│   └── examples/                       # buy-engagement, track-campaign, batch-planning
├── scripts/
│   ├── lighthouse                      # CLI wrapper around the Open API
│   └── test-lighthouse.sh              # smoke tests
├── install.sh                          # curl-to-shell installer
└── CHANGELOG.md
```

`scripts/lighthouse` lives at the plugin root as a general-purpose CLI — you can invoke it directly from any shell once the repo is cloned.

## Demo

- Buying engagement — screenshot pending; see [`skills/lighthouse/examples/buy-engagement.md`](skills/lighthouse/examples/buy-engagement.md) for the full dialogue.
- Tracking campaigns — screenshot pending; see [`skills/lighthouse/examples/track-campaign.md`](skills/lighthouse/examples/track-campaign.md) for the full dialogue.
- Batch planning (safety in action) — screenshot pending; see [`skills/lighthouse/examples/batch-planning.md`](skills/lighthouse/examples/batch-planning.md) for the full dialogue.

## Safety notes

- API key lives only in env vars; it is never pasted into chat or written to a file. If it leaks, rotate it immediately via the Lighthouse admin UI.
- Every campaign creation requires explicit user confirmation (`yes` / `确认` / `ok` / `确定`). Ambiguous replies re-prompt; they do not count as consent.
- Large-value spends (`total_cost > 500 LUX`) trigger an extra warning line before the confirmation prompt.
- Batch requests ("create these 5 campaigns") are never auto-looped — each item gets its own balance check, cost breakdown, and confirmation.

## Links

- Full skill behavior: [`skills/lighthouse/SKILL.md`](skills/lighthouse/SKILL.md)
- API reference: [`skills/lighthouse/references/api-reference.md`](skills/lighthouse/references/api-reference.md)
- Pricing & tiers: [`skills/lighthouse/references/pricing-and-tiers.md`](skills/lighthouse/references/pricing-and-tiers.md)
- Action combinations: [`skills/lighthouse/references/action-combinations.md`](skills/lighthouse/references/action-combinations.md)
- Changelog: [`CHANGELOG.md`](CHANGELOG.md)

## License

MIT. See [`LICENSE`](LICENSE).
