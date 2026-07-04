# Colony Rules — Hive AI-DLC Conventions

Conventions for the Hive AI-DLC lifecycle, delivered by the `hive` plugin and
injected every session. (Hive project: https://github.com/beelieve-ai/hive.)

## Plugin namespacing

Installed as a plugin, every Hive command, skill, and agent is namespaced
under `hive:`:

- **Commands**: `/hive:pollinate`, `/hive:forage`, `/hive:waggle`,
  `/hive:comb`, `/hive:swarm`, `/hive:sting`.
- **Agents** (spawn by this exact `subagent_type`): `hive:scout`,
  `hive:worker`, `hive:guard`, `hive:architect`, `hive:planner`,
  `hive:plan-reviewer-context` / `-dag` / `-sizing`. A **bare** agent name
  does not resolve — always spawn the `hive:`-prefixed type.
- **Skills** (load by this id): `hive:grilling`, `hive:writing-prds`, etc.

The bee-themed names in the map below are the **logical** names; the `hive:`
prefix is the packaging namespace, not part of the name.

## Lifecycle

**Idea → PRD → Research → ADR → Plan → Build → Review**

- **Documents in `docs/` are the source of truth for intent**:
  `docs/prd/` (PRD-NNN), `docs/research/` (RES-NNN), `docs/adr/` (ADR-NNNN,
  MADR 4.0), `docs/plans/` (PLAN-NNN plan.yaml audit trail).
- **ADRs have a scope**: `scope: prd` (default) derives from one PRD;
  `scope: repo` is a standalone cross-cutting platform decision (CI/CD,
  build system, toolchain) with no parent PRD (`derived-from: null`),
  authored via `/hive:waggle --standalone <topic>`. Accepted repo-scoped
  ADRs bind **every** plan — `/hive:comb` passes them to the planner
  alongside the PRD's own ADRs.
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
- **Issue → Doc**: always full absolute `blob` URLs so links resolve in the
  GitHub issue UI — no placeholders. Build them for the **current** repo,
  never a hardcoded one: resolve `<owner>/<repo>` and the `<default-branch>`
  once via `gh repo view --json nameWithOwner,defaultBranchRef` (see
  `hive:gh-conventions` — fall back to the local branch when the remote default
  is empty), then form
  `https://github.com/<owner>/<repo>/blob/<default-branch>/<path>`.
- **Issue-body header block** — every generated issue body starts with (URLs
  built for the current repo as above):

  ```
  **PRD:** [PRD-NNN](https://github.com/<owner>/<repo>/blob/<default-branch>/docs/prd/PRD-NNN-slug.md) · **Implements:** PRD-NNN-R1 · **ADR:** ADR-NNNN
  ```

  The `· **ADR:** ...` segment is omitted when no ADR constrains the task.

- **Doc → Issues**: PRD frontmatter gets `milestone` + `epic_issue` at
  `/hive:comb` materialization.
- **ADRs are append-only**: never edit an accepted ADR's decision —
  supersede it via `/hive:waggle`.

## Diagrams

- **Mermaid by default**: figures in any lifecycle artifact — PRD, RES,
  ADR, plan.yaml epic/task bodies, issue bodies — are ```` ```mermaid ````
  fenced blocks. GitHub and most modern markdown tooling render them
  natively.
- **Only where they aid understanding** — flows, architectures, state
  machines, dependency graphs. Never a mandatory or empty diagram section.
- **ASCII art is the fallback**, used only when mermaid cannot express the
  figure (byte/wire layouts, precise column alignment). Never emit both
  forms of the same figure.

## ID allocation

- Next free number = glob over the doc directory (e.g. `docs/adr/ADR-*.md`)
  and take max + 1.
- IDs are append-only and never reused — even for deleted or abandoned docs.

## Ground rules

- **Human gates are mandatory**: PRD approval, ADR acceptance, plan approval
  before materialization. Never skip, never auto-accept.
- **All user interaction goes through the `AskUserQuestion` tool — no
  exceptions.** Every question, gate verdict, PAUSE resolution, and
  missing-argument prompt: one decision per call, the recommended answer as
  the first option labelled `(Recommended)` with the reason in its
  description, real alternatives as the other options, and the tool's
  automatic "Other" as the escape hatch. Open-ended asks (e.g. "what is the
  idea?") are **not** exempt: still call the tool, offer your best
  context-derived guesses as options (existing docs, repo signals, recent
  work), and let "Other" carry the free-form answer. Never ask in plain
  prose. Selecting an explicit Approve/Accept option **is** the explicit
  human declaration the gates require — silence or enthusiasm still is not.
  Sole exception: in a headless/non-interactive run the tool genuinely does
  not exist — state that limitation once, then fall back to prose; **gates
  still never auto-approve there**.
- **Reviewers are read-only** (no Write/Edit). Verdict loops belong to the
  orchestrator.
- **Docs = intent, issues = execution state.** Never duplicate execution
  status back into docs except at the defined sync points: `/hive:comb`
  materialization and `/hive:swarm` completion.
- **All `gh` automation uses `--json` output**, never parses human-readable
  output — with **one sanctioned exception**: `gh issue create` and
  `gh pr create` have no `--json` flag. New numbers are captured from their
  single-URL stdout with a strict `/issues/<number>` (resp. `/pull/<number>`)
  parse that **fails on no match or multiple matches**, then verified via
  `gh issue view <n> --json ...`.

## Preflight requirements

Verify these against the **current** repo/org before materializing issues
(originally validated on `beelieve-ai` with gh 2.96.0, 2026-07-03):

- `gh` **≥ 2.94.0** — check `gh --version`.
- The target org must expose native issue types **Task, Bug, Feature, Epic** —
  native types are used, no type labels. Orgs without them need a fallback.
- `gh issue edit` uses `--parent` (not the older `--set-parent`, which does
  **not** exist).
- JSON fields `blockedBy`, `blocking`, `parent`, `issueType`, `subIssues`
  must be present on `gh issue list` / `gh issue view`.

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

worker runs **without** worktree isolation for now — `/hive:swarm` is serial,
one issue at a time, so worktrees add complexity without benefit.
`isolation: worktree` is the recorded enhancement path for parallel
execution.

## Residual risks (spec-faithful, accepted)

- A **closed-but-unmerged blocker is trusted as done** — the happy path
  auto-closes issues via squash-merge, so a manually closed issue passes as
  a satisfied dependency.
- **CONTENT-only plan-review reruns don't re-check previously passing
  reviewers** — only failed reviewers rerun on content-level corrections.
- **Per-task ADR citation has no hard forcing function** — `adr_refs: []`
  is valid whenever no plan ADR constrains that task, so a planner that
  fails to cite a relevant repo-scoped ADR drops the constraint silently
  (workers only see their own task's ADRs). Mitigated by the planner's
  read-and-cite instruction and the context reviewer's relevance check;
  accepted as planner/reviewer diligence.

## CONTEXT.md governance

Root `CONTEXT.md` is a version-controlled **glossary of canonical terms
only** — no implementation details, no execution state. It is lazily
created by the first grilling session that resolves a term, updated inline
the moment a term resolves, and committed alongside the artifact whose
grilling resolved it.

## ARCHITECTURE.md governance

Root `ARCHITECTURE.md` is a version-controlled **derived digest** — one
condensed bedrock entry per **accepted** ADR (both scopes), loaded into
every future session's context via an `@ARCHITECTURE.md` import in the repo's
root `CLAUDE.md`. It is **never a source of truth**: the full ADRs in
`docs/adr/` are, and planning always reads them in full. It is lazily
created and updated **only** at the `/hive:waggle` acceptance/supersede sync
points, is regenerable at any time from the accepted ADR set, and is never
hand-edited. Proposed ADRs, superseded ADRs, and `DECISIONS.md` entries
never appear in it.
