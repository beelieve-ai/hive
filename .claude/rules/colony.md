# Colony Rules — Hive AI-DLC Conventions

Auto-loaded conventions for the Hive lifecycle in this repository
(https://github.com/beelieve-ai/hive).

## Lifecycle

**Idea → PRD → Research → ADR → Plan → Build → Review**

- **Documents in `docs/` are the source of truth for intent**:
  `docs/prd/` (PRD-NNN), `docs/research/` (RES-NNN), `docs/adr/` (ADR-NNNN,
  MADR 4.0), `docs/plans/` (PLAN-NNN plan.yaml audit trail).
- **GitHub Issues are the execution layer**: one **milestone per goal**,
  native **sub-issues** for the Epic → Task hierarchy, native **issue
  dependencies** (`blocked by` / `blocking`) for the task DAG.
  No GitHub Projects — keep it simple.

## Naming map

The Hive uses bee-themed names. This table is the **only** place the
original names from the bootstrap spec may appear — never emit the
old command, agent, or label names anywhere else.

| Hive name | Original name | Kind |
|---|---|---|
| `/pollinate` | `/prd` | command |
| `/forage` | `/research` | command |
| `/waggle` | `/adr` | command |
| `/comb` | `/plan` | command |
| `/swarm` | `/goal` | command |
| `/sting` | — (new) | command |
| `scout` | `researcher` | agent |
| `worker` | `implementer` | agent |
| `guard` | `code-reviewer` | agent |
| `architect` | `architect` (unchanged) | agent |
| `planner` | `planner` (unchanged) | agent |
| `plan-reviewer-context` | unchanged | agent |
| `plan-reviewer-dag` | unchanged | agent |
| `plan-reviewer-sizing` | unchanged | agent |

Doc IDs stay standard: PRD / RES / ADR / PLAN.

## Cross-linking rules

- **Doc → Doc**: reference by ID (e.g. `ADR-0007`) **and** a repo-relative
  markdown link (e.g. `[ADR-0007](../adr/ADR-0007-slug.md)`).
- **Issue → Doc**: always full hardcoded URLs under
  `https://github.com/beelieve-ai/hive/blob/main/...` so links resolve in
  the GitHub issue UI. No placeholders.
- **Issue-body header block** — every generated issue body starts with:

  ```
  **PRD:** [PRD-NNN](https://github.com/beelieve-ai/hive/blob/main/docs/prd/PRD-NNN-slug.md) · **Implements:** PRD-NNN-R1 · **ADR:** ADR-NNNN
  ```

- **Doc → Issues**: PRD frontmatter gets `milestone` + `epic_issue` at
  `/comb` materialization.
- **ADRs are append-only**: never edit an accepted ADR's decision —
  supersede it via `/waggle`.

## ID allocation

- Next free number = glob over the doc directory (e.g. `docs/adr/ADR-*.md`)
  and take max + 1.
- IDs are append-only and never reused — even for deleted or abandoned docs.

## Ground rules

- **Human gates are mandatory**: PRD approval, ADR acceptance, plan approval
  before materialization. Never skip, never auto-accept.
- **Reviewers are read-only** (no Write/Edit). Verdict loops belong to the
  orchestrator.
- **Docs = intent, issues = execution state.** Never duplicate execution
  status back into docs except at the defined sync points: `/comb`
  materialization and `/swarm` completion.
- **All `gh` automation uses `--json` output**, never parses human-readable
  output — with **one sanctioned exception**: `gh issue create` and
  `gh pr create` have no `--json` flag. New numbers are captured from their
  single-URL stdout with a strict `/issues/<number>` (resp. `/pull/<number>`)
  parse that **fails on no match or multiple matches**, then verified via
  `gh issue view <n> --json ...`.

## Preflight outcomes (verified 2026-07-03)

- `gh` **2.96.0** (spec requires ≥ 2.94.0) ✓
- Org `beelieve-ai` has native issue types: **Task, Bug, Feature, Epic** —
  native types are used, no type labels.
- `gh issue edit` uses `--parent` (the spec's `--set-parent` does **not**
  exist).
- JSON fields `blockedBy`, `blocking`, `parent`, `issueType`, `subIssues`
  verified on `gh issue list` / `gh issue view`.

## Labels

Only three labels exist:

- `hive:managed` — marks every issue created by this system.
- `phase:build` — tasks are created with it.
- `phase:review` — flipped to when guard review starts.

The `phase:*` flip is **cosmetic UI state only** — resume and ready logic
never keys off labels. The spec's four doc-phase labels
(prd/research/adr/plan) were dropped: doc phases live in the doc's
`status:` frontmatter, which is the source of truth.

## Branch / PR flow

1. Branch `issue/<n>-<slug>` from **fresh** main.
2. worker implements, commits, and pushes: `git push -u origin <branch>`.
3. `gh pr create --fill --body "Closes #<n>"`
4. `gh pr merge --squash --delete-branch` (auto-closes the issue).
5. **Always** afterwards: `git switch main && git pull --ff-only origin main`
   — local main is stale after **every** squash-merge; sync before cutting
   the next branch and before any commit on main.

Merge failures (branch protection, required checks) **pause with the PR
URL** — never mark progress or close issues manually.

## Worker isolation

worker runs **without** worktree isolation for now — `/swarm` is serial,
one issue at a time, so worktrees add complexity without benefit.
`isolation: worktree` is the recorded enhancement path for parallel
execution.

## Residual risks (spec-faithful, accepted)

- A **closed-but-unmerged blocker is trusted as done** — the happy path
  auto-closes issues via squash-merge, so a manually closed issue passes as
  a satisfied dependency.
- **CONTENT-only plan-review reruns don't re-check previously passing
  reviewers** — only failed reviewers rerun on content-level corrections.

## CONTEXT.md governance

Root `CONTEXT.md` is a version-controlled **glossary of canonical terms
only** — no implementation details, no execution state. It is lazily
created by the first grilling session that resolves a term, updated inline
the moment a term resolves, and committed alongside the artifact whose
grilling resolved it.
