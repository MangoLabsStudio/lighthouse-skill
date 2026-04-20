# Changelog

## v0.2.0 — 2026-04-19

### Added
- `.claude-plugin/plugin.json` manifest — skill is now a proper Claude Code plugin, installable via `/plugin install`
- `install.sh` — one-line curl-to-shell installer for non-Claude-Code users (Agent SDK, Copilot CLI, etc.)
- README install section now covers three paths: plugin, curl, manual git clone

### Changed
- **Repo layout restructured** for plugin convention:
  - `SKILL.md` → `skills/lighthouse/SKILL.md`
  - `references/` → `skills/lighthouse/references/`
  - `examples/` → `skills/lighthouse/examples/`
  - `scripts/` stays at plugin root (shared CLI utility)

### Migration for existing v0.1.0 users
- If you installed via `git clone ~/.claude/skills/lighthouse`, just `git pull`. SKILL.md moved inside `skills/lighthouse/`, but Claude Code will still find it because frontmatter is intact.
- Or reinstall cleanly: `rm -rf ~/.claude/skills/lighthouse && curl -sSL .../install.sh | bash`

## v0.1.0 — 2026-04-19
- Initial public release: SKILL.md + references + examples + scripts/lighthouse CLI + smoke tests + CI.
- Covers balance / pricing / campaigns (list, get, create-engagement) with mandatory safety confirmation flow.
