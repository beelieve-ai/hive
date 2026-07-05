# Changelog

All notable changes to the Hive plugin are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The
authoritative version is the `version` field in
`.claude-plugin/plugin.json`; installed plugins update only when it is bumped.

## [0.8.0] — 2026-07-05

### Added
- **Clickable artifact references in audit logs**: every doc-artifact ID
  (`PRD-NNN`, `RES-NNN`, `ADR-NNNN`, `PLAN-NNN`) written into a new audit
  entry — `subject` and `detail` alike — is now an inline relative Markdown
  link to the artifact file, resolved at write time by globbing the artifact
  directory (bare-ID fallback on zero or ambiguous matches; exact-token
  matching so requirement anchors like `PRD-003-R1` are untouched; `#NN`
  issue refs stay bare). Existing entries are not retrofitted, so
  idempotency/dedupe checks compare the logical ID across bare and linked
  forms. Normative rule in `rules/colony.md` (Audit log), supporting note in
  the `crosslinking` skill.

## [0.7.0] — 2026-07-05

### Added
- **Evidence provenance for the architect**: the ADR-drafting agent now
  follows the `research-method` evidence discipline (loaded via agent
  frontmatter, with an explicit-override note — tag semantics and
  confidence ceilings bind; the RES-doc output machinery is replaced by
  ADR-shaped output). Every web-sourced claim in option prose carries an
  inline tag + confidence (`[VERIFIED: <source>, confidence: <RATING>]` /
  `[CITED: <url>, confidence: <RATING>]` / `[ASSUMED, confidence: LOW]`,
  the rating at or below the tag's ceiling),
  and every draft ends with a mandatory `## Assumptions` section
  (`None.` when empty) — added to the `writing-adrs` template, MADR
  structure, and option-comparison quality bar.
- **Provenance validation in `/hive:waggle`**: step 6 verifies inline
  tag+confidence on web-sourced claims and that every inline `[ASSUMED]`
  claim has a matching Assumptions bullet (one architect re-invoke on
  gaps, then report-and-drop); step 7 calls out the Assumptions entries at
  the acceptance gate, re-runs the checks after any revision-path edit
  before final acceptance, and flags resumed pre-0.7.0 proposed drafts as
  having no provenance block instead of re-drafting them.
- **`/hive:bumble --yolo` assumption carve-out**: an ADR drafted in-run
  whose Assumptions section is non-`None.` is never auto-accepted — its
  acceptance gate always goes to the human.

## [0.6.0] — 2026-07-05

### Added
- **Evidence provenance for research**: every Evidence citation in a RES doc
  carries a claim tag — `[VERIFIED: <source>]` / `[CITED: <url>]` /
  `[ASSUMED]` — and every Answer a confidence rating capped by its tags
  (VERIFIED→up to HIGH; corroborated CITED→up to MEDIUM; single-source
  CITED and ASSUMED→LOW; downgrades allowed, upgrades never).
- **Assumptions Log** in the research template: stable per-doc `A<n>` ids
  for every `[ASSUMED]` claim; a question relying on an unaccepted
  assumption keeps its doc `status: open`.
- **Assumption-acceptance gate** in `/hive:forage`: one AskUserQuestion per
  blocking assumption (Keep-open recommended); acceptance is recorded by a
  doc marker (`accepted YYYY-MM-DD by human|yolo`) and surfaces in the
  `res-answered` audit detail at flip time. `/hive:bumble --yolo` now
  auto-accepts only assumptions introduced during that run (entry
  snapshot — pre-existing ones always go to the human), a third delegation
  gate type alongside ADR acceptance and plan approval.
- **Citation spot-check** in `/hive:forage` step 5: scout citations are
  verified as content-free existence checks before persisting; a
  non-resolving citation folds into the existing single re-dispatch.
- `research-method` gains honest-reporting rules (negative-claim guard,
  hedging tells), search hygiene, and confirmation/survivorship bias
  counters with an explicit skip list for trivial lookups.

### Changed
- The scout runs on **opus** (was `sonnet`): `balanced.scout` is raised to
  `opus` in `models.yaml` — research quality gates everything downstream —
  and the scout's frontmatter fallback matches. The scout returns a
  tightened, citation-only summary (no page dumps or tool transcripts) with
  a bounded-search rule.
- The research method is consolidated: `research-method` is the single
  source of truth; `agents/scout.md` and `/hive:forage` now point at it
  instead of restating search order, evidence rules, and done criterion.
- `/hive:sting` RES-doc forbidden edits additionally cover provenance tags,
  confidence ratings, and acceptance markers.
- Colony ground rules: the `--yolo` carve-out covers three gate types; the
  audit log documents the marker-based exemption for assumption
  acceptances.

## [0.5.1] — 2026-07-05

### Removed
- Accidental root `CONTEXT.md` (a consumer-project artifact that a grilling
  session created in the plugin's own source repo) and its references in
  `CLAUDE.md` and the README repository layout.

## [0.5.0] — 2026-07-05

### Added
- `/hive:tremble [--all]` — mines this project's own Claude Code session
  transcripts and hive audit logs for evidence of friction the hive system
  itself caused, drafts sanitized upstream issues about those weaknesses, and —
  only after per-issue approval — files them in `beelieve-ai/hive` (a
  deliberately hardcoded target, exceptional vs. the current-repo resolution
  lifecycle commands use). Four-layer sanitization (generic by construction,
  deterministic redaction check, LLM pass, human verbatim gate) keeps
  project-specific information — paths, names, code, quotes — on the machine;
  `--all` forces a re-scan of already-analyzed sessions.
- `tremble-analyzer` agent (spawned as `hive:tremble-analyzer`) — a read-only
  per-session analyzer (Read/Grep/Glob) that returns structured, sanitized
  findings against a fixed friction taxonomy plus a catch-all.

## [0.4.0] — 2026-07-05

### Added
- **Per-role model presets** (`models.yaml` at the plugin root): three presets
  — `quality`, `balanced`, `cheap` — each a per-role matrix (`architect`,
  `planner`, `guard`, `worker`, `scout`, `plan-reviewer`), with a top-level
  `active:` key selecting the live preset. The single `plan-reviewer` key
  covers all three reviewer variants.
- **Per-project override at `.hive/models.yaml`**: `active:` switches the
  preset, and an optional flat `agents:` map pins individual roles on top of
  it (e.g. `agents: {scout: fable}`). Precedence: `agents:` pin > active
  preset > frontmatter fallback. No deep-merge.

### Changed
- Orchestrator skills (`/hive:forage`, `/hive:waggle`, `/hive:comb`,
  `/hive:swarm`) now resolve `presets[active][role]` and pass it as the `model`
  param on every agent spawn, including comb's planner and swarm's worker fix
  rounds; `/hive:bumble` inherits this by running the phase skills fresh. On any
  resolution failure the param is omitted and the agent's frontmatter default
  applies, with a warning — model config never hard-fails a lifecycle command.
- Agent frontmatter aligned to the `balanced` preset as the fallback tier:
  `planner`, `guard`, and `plan-reviewer-sizing` move `opus` → `sonnet`.

## [0.3.0] — 2026-07-04

_Backfilled — this version shipped in the manifest without a changelog entry._

### Added
- **Per-PRD audit log**: one append-only provenance file per PRD at
  `docs/audit/PRD-NNN-audit.md` with a fixed one-line markdown schema, written
  by the phase that owns each status write in the same commit. Records human
  gate verdicts, `--yolo` auto-accepts, and doc status flips; exempt from the
  docs=intent / issues=execution split and never read for routing. Canonical
  term "audit log" added to the root `CONTEXT.md` glossary.

### Fixed
- Audit-log append instructions: review gaps closed (deterministic append
  anchors and ownership).

## [0.2.0] — 2026-07-04

### Added
- **Label-mode fallback for issue types**: user-owned repos have no custom
  issue types, so `/hive:comb` now probes `.owner.type` once — `User` →
  create epics/tasks with `type:epic` / `type:task` labels instead of
  `--type`; `Organization` → native types after verifying the org exposes
  Epic and Task (orgs missing either also fall back to label mode instead
  of failing mid-materialization). All discovery filters
  (`/hive:comb` pre-scan, `/hive:swarm`) are mode-agnostic (`issueType` OR
  `type:*` label).
- `/hive:comb` now ensures all required labels exist idempotently
  (`gh label create --force`) before the first issue create — a fresh repo
  has none, and `gh issue create --label` fails on missing labels.
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
  `status: proposed` drafts, skips candidates already settled (covered by
  an accepted ADR, an explicit defer, or a recorded worthiness rationale),
  and repairs accepted ADRs a mid-Accept interruption left out of the
  PRD's `adrs:` list.

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
