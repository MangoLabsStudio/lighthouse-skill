#!/usr/bin/env bash
# Lighthouse Skill installer — clones the repo into ~/.claude/skills/lighthouse
# for "plain skill" mode. For plugin mode, use /plugin install inside Claude Code.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/MangoLabsStudio/lighthouse-skill/main/install.sh | bash
#
# Or with a pinned version:
#   curl -sSL https://raw.githubusercontent.com/MangoLabsStudio/lighthouse-skill/v0.2.0/install.sh | bash

set -euo pipefail

REPO="https://github.com/MangoLabsStudio/lighthouse-skill.git"
DEST="${LIGHTHOUSE_SKILL_DIR:-$HOME/.claude/skills/lighthouse}"
REF="${LIGHTHOUSE_SKILL_REF:-main}"

info()  { printf '\033[36m[lighthouse]\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m[lighthouse]\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[31m[lighthouse]\033[0m %s\n' "$*" >&2; exit 1; }

command -v git  >/dev/null || die "git is required"
command -v curl >/dev/null || warn "curl not found — scripts/lighthouse needs curl to call the API"
command -v jq   >/dev/null || warn "jq not found — scripts/lighthouse needs jq (install: brew install jq / apt install jq)"

if [ -d "$DEST/.git" ]; then
  info "existing install at $DEST — updating to $REF"
  git -C "$DEST" fetch --tags --quiet origin
  git -C "$DEST" checkout --quiet "$REF"
  git -C "$DEST" pull --ff-only --quiet origin "$REF" 2>/dev/null || true
else
  info "cloning into $DEST"
  mkdir -p "$(dirname "$DEST")"
  git clone --quiet --branch "$REF" --depth 1 "$REPO" "$DEST" 2>/dev/null \
    || git clone --quiet "$REPO" "$DEST"
  if [ "$REF" != "main" ]; then
    git -C "$DEST" checkout --quiet "$REF"
  fi
fi

info "installed at $DEST"
info "next: export LIGHTHOUSE_API_KEY=lh_live_... (get one from the Lighthouse admin)"
info "verify:  $DEST/scripts/lighthouse balance"
echo
info "SKILL.md lives at $DEST/skills/lighthouse/SKILL.md"
