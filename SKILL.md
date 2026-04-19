---
name: lighthouse
description: Use when the user wants to buy Twitter engagement (likes/RT/comments/follows) on the Lighthouse platform, check LUX balance, or track engagement campaigns. Calls Lighthouse Open API with LIGHTHOUSE_API_KEY env var.
---

# Lighthouse Skill

## Prerequisites

Before calling any Lighthouse endpoint, make sure the environment is set up correctly and that the user's API key is available to the shell (not to chat).

### Environment setup

The skill reads two environment variables:

- `LIGHTHOUSE_API_KEY` **(required)** — the buyer's Open API key. Format `lh_live_...` (production) or `lh_test_...` (dev). Get one from the Lighthouse admin panel.
- `LIGHTHOUSE_API_BASE` **(optional)** — defaults to production `https://service.lhdao.top/open-api/v1`. For the dev environment use `https://service.lhdaobeta.top/open-api/v1`.

Example (user runs this in their own shell):

```bash
export LIGHTHOUSE_API_KEY=lh_live_xxxxxxxxxxxxxxxxxxxxxxxx
# optional — only if targeting dev
export LIGHTHOUSE_API_BASE=https://service.lhdaobeta.top/open-api/v1
```

### Critical safety rule — API key handling

**Never ask the user to paste the API key into chat.** The key is a bearer credential; once it appears in the transcript it is effectively leaked (transcripts are logged, synced, and may be shared).

If `$LIGHTHOUSE_API_KEY` is missing, empty, or does not start with `lh_live_` / `lh_test_`:

1. Tell the user the key is missing / malformed.
2. Ask them to `export LIGHTHOUSE_API_KEY=...` in their own shell.
3. Ask them to restart the Claude Code / Agent session so the new env var is picked up.
4. **Do NOT** offer to accept the key inline, do NOT suggest pasting it into chat, and do NOT write it to a file on the user's behalf.

### Verify setup

Run the bundled CLI wrapper:

```bash
./scripts/lighthouse balance
```

Or the equivalent curl:

```bash
curl -sS -H "X-API-Key: $LIGHTHOUSE_API_KEY" "$LIGHTHOUSE_API_BASE/balance"
```

Expected output — a JSON object containing at least:

```json
{
  "oldLux": 0,
  "newLux": 42.5,
  "totalLux": 42.5
}
```

If you get `401` or an `INVALID_API_KEY` error, go back to the env-setup step. Do not proceed to any `POST` endpoint until `balance` returns successfully.

### References

Deeper reading (load on demand — the body of this skill stays self-contained):

- `references/api-reference.md` — full endpoint list, request/response schemas, error codes.
- `references/pricing-and-tiers.md` — fee formula, tier semantics, default baseRewards, budget worked examples.
- `references/action-combinations.md` — which action combinations are legal (in particular the `COMMENT_LIKE` exclusion rules).
- `examples/` — end-to-end recipes (this directory may be empty right now; it will be filled in a later task).
