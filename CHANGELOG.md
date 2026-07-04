# Changelog

All notable changes to the Hive plugin are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The
authoritative version is the `version` field in
`.claude-plugin/plugin.json`; installed plugins update only when it is bumped.

## [0.2.0] — 2026-07-04

### Added
- `/hive:bumble <PRD-id> [--yolo]` — an autopilot command that cascades
  Research → ADR → Plan → Build for one approved PRD. It derives the current
  phase from the artifacts on disk (no state file), pauses at every human gate
  inline, and — with `--yolo` — delegates the two **approval** gate types (ADR
  acceptance and plan approval) for artifacts created during that run.

### Changed
- The colony ground rules gain the narrow `--yolo` delegation carve-out: the
  two approval gates may be auto-decided, but only for artifacts created within
  the current `/hive:bumble --yolo` run.
- The SessionStart hook now injects the resolved plugin root (a `Hive plugin
  root:` line) alongside the conventions.
- `/hive:waggle` is now idempotent across re-runs: it resumes orphaned
  `status: proposed` drafts and skips candidates already settled (covered by
  an accepted ADR, an explicit defer, or a recorded worthiness rationale).

### Fixed
- `/hive:waggle` supersede now replaces the superseded id in the PRD's `adrs:`
  list — the stale id previously left behind made the next `/hive:comb` abort.
- `/hive:forage` (research-method) no longer treats `/hive:waggle`'s settlement
  notes in a PRD's Open Questions as researchable questions.

## [0.1.1] — 2026-07-04

### Fixed
- `CLAUDE.md` semantic-versioning section no longer instructs bumping a
  non-existent `version` field in `marketplace.json`; `.claude-plugin/plugin.json`
  is documented as the single source of truth.

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
- All user interaction runs through the **AskUserQuestion** tool, no
  exceptions — grilling interview questions, the PRD/ADR/plan gate verdicts,
  `/hive:sting` edit agreements, `/hive:swarm` PAUSE resolutions, and
  missing-argument prompts: one decision per call, the recommendation as the
  first option labelled `(Recommended)`, "Other" as the escape hatch. Even
  open-ended asks go through the tool, with context-derived guesses as
  options and "Other" carrying the free-form answer. Codified as a colony
  ground rule.
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
