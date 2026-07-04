# Changelog

All notable changes to the Hive plugin are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The
authoritative version is the `version` field in
`.claude-plugin/plugin.json`; installed plugins update only when it is bumped.

## [0.1.0] — 2026-07-03

Initial release: the Hive AI-DLC is now an installable, portable Claude Code
plugin.

### Added
- `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` — the
  `hive` plugin and its `beelieve-ai` marketplace entry (`source: "./"`).
- SessionStart hook (`hooks/hooks.json` + `hooks/inject-colony.sh`) that injects
  the `rules/colony.md` conventions every session — the plugin equivalent of
  the old `.claude/rules/` auto-load.
- Each authoring skill now embeds its artifact **Template**
  (`hive:writing-prds`, `hive:writing-adrs`, `hive:research-method`,
  `hive:decomposition`), so scaffolding needs no external template files and
  works in any repo.
- `LICENSE` (MIT).

### Changed
- Restructured from project-local `.claude/{skills,agents,rules}` to plugin-root
  `skills/`, `agents/`, `rules/`.
- Commands, skills, and agents are namespaced under `hive:` — commands are
  invoked as `/hive:pollinate` … `/hive:sting`, and agents are spawned by their
  `hive:<name>` `subagent_type` (a **bare** agent name does not resolve).
- Cross-link and issue-body URLs are now built from the **current** repo via
  `gh repo view --json nameWithOwner,defaultBranchRef` instead of a hardcoded
  `beelieve-ai/hive` — the plugin produces correct links in any repo. The
  default-branch lookup falls back to the local branch on a brand-new repo with
  nothing pushed yet, so the URL stays well-formed.

### Removed
- `docs/templates/*` — the templates now live inside their owning skills.

### Notes
- The always-on conventions arrive via a SessionStart hook as
  `additionalContext` (system-reminder tier). This faithfully reproduces the
  prior main-thread behavior; plugins cannot ship an auto-loaded `CLAUDE.md`.
