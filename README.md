# Hive 🐝

An AI-driven development lifecycle (AI-DLC) for [beelieve-ai](https://github.com/beelieve-ai), built on Claude Code skills, agents, and hooks and packaged as an installable plugin.

**Documents in `docs/` are the source of truth for intent. GitHub Issues are the execution layer.** Every stage transition that matters passes through a human approval gate — nothing is auto-accepted (single exception: `/hive:bumble --yolo` delegates the ADR-acceptance and plan-approval verdicts for artifacts created during that run).

## Install

Hive ships as a Claude Code plugin. Add the marketplace and install it:

```
/plugin marketplace add beelieve-ai/hive
/plugin install hive@beelieve-ai
```

Commands are then available namespaced under `hive:` — `/hive:pollinate`, `/hive:forage`, `/hive:waggle`, `/hive:comb`, `/hive:swarm`, `/hive:bumble`, `/hive:sting` — and work in **any** repo: doc links and issue bodies are built from the current repo's `gh` remote, and the conventions in `rules/colony.md` are injected at session start. Update later with `/plugin update` (a new version arrives only when `plugin.json`'s `version` is bumped).

**Local development** (working on Hive itself): load the plugin straight from a checkout with `claude --plugin-dir .`, or add the local path as a marketplace (`/plugin marketplace add /path/to/hive`).

## The flow

```
Idea → PRD → Research → ADR → Plan → Build → Review
```

| Stage | Command | Produces | Human gate |
|---|---|---|---|
| Idea → PRD | `/hive:pollinate <idea>` | `docs/prd/PRD-NNN-slug.md` via a one-question-at-a-time grilling interview | PRD approval |
| Research | `/hive:forage <PRD-id>` | `docs/research/RES-NNN-*.md` — scout agents answer the PRD's open questions in parallel | all research docs `status: answered` |
| ADR | `/hive:waggle <PRD-id> [topic]` | `docs/adr/ADR-NNNN-*.md` (MADR 4.0) — one architect agent per worthy decision + root `ARCHITECTURE.md` bedrock digest | ADR acceptance |
| Plan | `/hive:comb <PRD-id>` | `docs/plans/` plan.yaml, reviewed by three parallel plan reviewers, then materialized as a GitHub milestone + epic + task DAG | plan approval before materialization |
| Build + Review | `/hive:swarm <milestone>` | Dependency-ordered execution: worker implements each issue on a branch, guard reviews the diff, PRs are squash-merged; merge blockers are auto-resolved (worker merge-fix rounds + guard re-review), main re-verified after every merge via the plan's milestone verification | unresolvable merge blockers park under `hive:parked` with the PR URL |
| Autopilot | `/hive:bumble <PRD-id> [--yolo]` | Cascades Research → ADR → Plan → Build for one approved PRD, deriving the current phase from the artifacts; resumable by re-running | all phase gates inline; `--yolo` delegates the three approval gate types for artifacts created in the run |
| Anytime | `/hive:sting <doc-or-id>` | Sharpens any lifecycle artifact through another grilling interview — doc edits only | every edit individually agreed |
| Feedback | `/hive:tremble [--all]` | Mines this project's own session transcripts + audit logs for friction the hive itself caused, then drafts sanitized issues in `beelieve-ai/hive` — `tremble-analyzer` agents analyze each session in parallel | per-issue approval before filing |

A typical end-to-end run:

```
/hive:pollinate a CLI that syncs labels across repos   # interview → PRD draft → approve it
/hive:forage PRD-001                                   # scouts answer open questions
/hive:waggle PRD-001                                   # decide architecture → accept ADRs
/hive:comb PRD-001                                     # plan → review → approve → issues created
/hive:swarm 1                                          # build the milestone to completion

# or, after approving the PRD, autopilot the rest:
/hive:bumble PRD-001
```

## How execution works

`/hive:comb` turns an approved plan into one **milestone per goal**, with an **Epic issue** and **Task sub-issues** wired together by native GitHub issue dependencies (`blocked by` / `blocking`) — no GitHub Projects. `/hive:swarm` then walks the DAG: for each ready task, a **worker** agent branches from fresh main, implements, and pushes; a read-only **guard** agent reviews the branch against the issue's acceptance criteria and any referenced ADRs; the PR is squash-merged, auto-closing the issue. Issues carry the `hive:managed` label plus a cosmetic `phase:build` / `phase:review` flip.

**Autopilot.** `/hive:bumble <PRD-id>` reads the lifecycle state straight from the docs and the milestone marker, then runs Research → ADR → Plan → Build in order — each phase no-ops when it has nothing to do. It pauses at every human gate inline and, on any failure, halts with a resume instruction. There is no state file: re-running `/hive:bumble` simply resumes from the artifacts on disk. Add `--yolo` to delegate the three approval gate types (ADR acceptance, plan approval, and research-assumption acceptance) for artifacts created during that run.

## Feedback: `/hive:tremble`

Everything above is the lifecycle. `/hive:tremble [--all]` sits **outside** it: it
mines *this* project's own Claude Code session transcripts and hive audit logs for
evidence of friction the hive system itself caused, drafts sanitized GitHub issues
about those weaknesses, and — only after per-issue approval — files them upstream in
`beelieve-ai/hive` (the one deliberately hardcoded target repo). Four-layer
sanitization keeps project-specific information — paths, names, code, quotes — on the
machine; a read-only `tremble-analyzer` agent reads each session and returns only
generic findings against a fixed friction taxonomy. `--all` forces a re-scan of
already-analyzed sessions.

## Agents

- **scout** — read-only research, spawned per independent question cluster
- **architect** — drafts one ADR per candidate decision
- **planner** — drafts the plan.yaml task DAG
- **plan-reviewer-context / -dag / -sizing** — three parallel read-only plan checks (self-containedness, dependency soundness, task sizing)
- **worker** — implements exactly one task issue per invocation
- **guard** — read-only review verdict on the worker's branch
- **tremble-analyzer** — read-only per-session friction analyzer for `/hive:tremble`, returning sanitized findings

Reviewers never write; verdict loops belong to the orchestrating command.

## Repository layout

```
.claude-plugin/
  plugin.json       plugin manifest (name, version — authoritative)
  marketplace.json  marketplace catalog entry
models.yaml         per-role model presets (quality / balanced / cheap) — see below
skills/             the /hive:* commands above + supporting skills (each authoring skill carries its own Template)
agents/             the agents above
hooks/              SessionStart hook that injects the conventions
rules/
  colony.md         the full conventions
docs/               output tree, populated in the repo Hive runs against
  prd/ research/ adr/ plans/    PRD-NNN / RES-NNN / ADR-NNNN / PLAN-NNN
CHANGELOG.md · LICENSE
ARCHITECTURE.md     bedrock digest of accepted ADRs (lazily created by /hive:waggle, imported by root CLAUDE.md)
```

## Conventions

The full rules — naming, cross-linking, ID allocation, `gh` automation ground rules, branch/PR flow — live in [`rules/colony.md`](rules/colony.md) and are injected into every session by the plugin's SessionStart hook. Highlights:

- IDs are append-only and never reused; accepted ADRs are never edited, only superseded via `/hive:waggle`.
- Docs hold intent, issues hold execution state — status is synced between them only at `/hive:comb` materialization and `/hive:swarm` completion.
- All `gh` automation uses `--json` output; new issue/PR numbers are parsed strictly from the creation URL.
- Requires GitHub CLI ≥ 2.94.0 with sub-issues and dependencies; native issue types are used on organization repos, with a `type:*` label fallback on user-owned repos.

## Model presets

`models.yaml` at the plugin root picks which Claude model each agent role runs
on, via three presets — `quality`, `balanced`, `cheap` — selected by a
top-level `active:` key. Hive orchestrator commands read it and pass the
resolved model on every agent spawn. Override per project with
`.hive/models.yaml`: `active:` switches the preset, and an optional flat
`agents:` map pins individual roles on top of it (e.g.
`agents: {scout: fable}`) — precedence: `agents:` pin > active preset >
frontmatter, no deep-merge. If config resolution fails, each agent falls
back to its frontmatter default (aligned to `balanced`) — model config never hard-fails a
run. Full semantics live in [`rules/colony.md`](rules/colony.md).

## Versioning & releases

Hive follows [Semantic Versioning](https://semver.org). The authoritative version is the `version` field in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json); installed plugins update **only** when it is bumped (an unbumped commit is not delivered as an update). Each release:

1. Bumps `version` in `plugin.json`.
2. Adds a dated entry to [`CHANGELOG.md`](CHANGELOG.md) (Keep a Changelog format).
3. Is tagged `vX.Y.Z` on the release commit.
