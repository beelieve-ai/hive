# Colony Rules — Hive AI-DLC Conventions

Conventions for the Hive AI-DLC lifecycle, delivered by the `hive` plugin and
injected every session. (Hive project: https://github.com/beelieve-ai/hive.)

## Plugin namespacing

Installed as a plugin, every Hive command, skill, and agent is namespaced
under `hive:`:

- **Commands**: `/hive:pollinate`, `/hive:forage`, `/hive:waggle`,
  `/hive:comb`, `/hive:swarm`, `/hive:sting`, `/hive:bumble`.
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
  MADR 4.0), `docs/plans/` (PLAN-NNN plan.yaml). `docs/audit/` holds the
  per-PRD audit log — provenance, not intent (see Audit log below).
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
- **`/hive:bumble <PRD-id> [--yolo]` autopilots the lifecycle for one
  approved PRD** — it derives the current phase from the artifacts and
  cascades Research → ADR → Plan → Build to completion, pausing inline at
  every human gate.

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
| `/bumble` | — (new) | command |
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

## Audit log (per-PRD provenance)

Every PRD gets one **audit log**: an append-only file at
`docs/audit/PRD-NNN-audit.md` recording who decided what, when, across that
PRD's lifecycle. It is **provenance — neither intent nor execution state**:
the docs-are-intent / issues-are-execution split does not apply to it, and
it is **never read for routing or resume** — the artifacts remain the state.

- **One markdown line per event, fixed schema**:
  `- <UTC timestamp> · <event> · <subject> · <detail> · by: human|yolo`
  e.g. `- 2026-07-04T14:32Z · adr-accepted · ADR-0007 · option: embedded queue · by: human`.
  Timestamp via `date -u +%Y-%m-%dT%H:%MZ`. All five fields appear on every
  line: `subject` is the artifact the event is about (a doc id like
  `ADR-0007`, or an issue number); `detail` is short free text — write `—`
  when there is nothing to add.
- **Events recorded**: every human gate verdict (`prd-approved`,
  `adr-accepted`, `adr-rejected`, `plan-approved`, `plan-declined`,
  `pause-resolved`), every `--yolo` auto-accept (same event names,
  `by: yolo`), and every doc status flip (`res-answered`, `plan-reviewed`,
  `plan-materialized`, `prd-planned`, `prd-implemented`, `adr-superseded`).
  Halts, errors, and retries are **not** logged.
- **Writer**: the phase that owns a status write appends the entry at the
  same moment and commits it **in the same commit** as the artifact it
  records — standalone runs and `/hive:bumble` runs behave identically;
  bumble itself never writes audit entries. `by: yolo` marks exactly the
  verdicts auto-accepted under the `--yolo` carve-out.
- **Lazily created, forward-only**: the file is created at the PRD's first
  recorded event (header line `# Audit log — PRD-NNN`, then entries);
  pre-existing PRDs are never backfilled. Entries are append-only — never
  edited, reordered, or deleted.
- **Repo-scoped ADRs have no audit log** — no parent PRD; their acceptance
  trail is the ADR file itself (its `status:` flips, plus git history), and
  worthiness-rejected or deferred standalone candidates stay in
  `docs/adr/DECISIONS.md`.

## Ground rules

- **Human gates are mandatory**: PRD approval, ADR acceptance, plan approval
  before materialization. Never skip, never auto-accept. **Single, narrow
  carve-out — `/hive:bumble --yolo`**: passing `--yolo` on a `/hive:bumble`
  invocation IS the human's explicit gate declaration, delegated in advance
  for that run only, covering exactly two gate types — per-ADR acceptance
  (the architect's recommended option) and plan approval before
  materialization — and only for artifacts created during that run. At those
  gates no question is posed — the answer was given at invocation — and every
  auto-accepted verdict is listed in the run report. `--yolo` never extends
  to PRD approval, to pre-existing proposed ADRs or plans, to any PAUSE,
  error, or ambiguity resolution, or to missing-argument prompts: those
  always go to the human, flag or no flag. Headless runs without `--yolo`
  still never auto-approve.
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
  One delegation exception: the two gate types `/hive:bumble --yolo` covers
  are answered by the flag itself, per the human-gates carve-out above — no
  question is posed there. One environment exception: in a
  headless/non-interactive run the tool genuinely does not exist — state that
  limitation once, then fall back to prose; **gates still never auto-approve
  there**.
- **Reviewers are read-only** (no Write/Edit). Verdict loops belong to the
  orchestrator.
- **Docs = intent, issues = execution state.** Never duplicate execution
  status back into docs except at the defined sync points: `/hive:comb`
  materialization and `/hive:swarm` completion. The per-PRD audit log is
  provenance and exempt from this split (see Audit log above).
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
- **Issue-type mode** — probe once per materialization:
  `gh api repos/{owner}/{repo} --jq .owner.type`.
  - `Organization` → **native types** — but verify, don't assume: the org
    must expose the **Epic** and **Task** issue types
    (`gh api orgs/{owner}/issue-types`); either missing → fall back to
    label mode. Both present → create with `--type`, no type labels.
  - `User` → **label mode**: custom issue types do not exist on user-owned
    repos. Create without `--type`, adding the `type:epic` / `type:task`
    label instead.

  Reads never need the probe: discovery filters match **either** the native
  `issueType` **or** the `type:*` label (see gh-conventions).
- `gh issue edit` uses `--parent` (not the older `--set-parent`, which does
  **not** exist).
- JSON fields `blockedBy`, `blocking`, `parent`, `issueType`, `subIssues`
  must be present on `gh issue list` / `gh issue view`.

## Labels

Only these labels exist:

- `hive:managed` — marks every issue created by this system.
- `phase:build` — tasks are created with it.
- `phase:review` — flipped to when guard review starts.
- `type:epic` / `type:task` — **label mode only** (user-owned repos): stand
  in for the native Epic/Task issue types.

Labels are **ensured idempotently before the first issue create**
(`gh label create <name> --force` — see gh-conventions); a fresh repo has
none of them.

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

## Model presets

Which Claude model each Hive agent role runs on is configured in one file,
`models.yaml` at the **plugin root** (next to `.claude-plugin/`, shipped with
the plugin). It defines three presets — `quality`, `balanced`, `cheap` — each a
per-role matrix (`architect`, `planner`, `guard`, `worker`, `scout`,
`plan-reviewer`), with a top-level `active:` key selecting the live preset.

- **Role key = agent name minus the `hive:` prefix, normalized**: any
  `plan-reviewer-*` agent maps to the single `plan-reviewer` key before the
  preset lookup (e.g. `hive:plan-reviewer-dag` → `plan-reviewer`) — the three
  reviewer variants are one class of work.
- **Orchestrator skills resolve and pass the model at spawn time.** Every Hive
  command that spawns agents (`/hive:forage`, `/hive:waggle`, `/hive:comb`,
  `/hive:swarm`) reads `models.yaml`, resolves `presets[active][role]`, and
  passes it as the `model` param on **every** Agent spawn — including re-spawns
  in comb's planner fix rounds and swarm's worker fix rounds. `/hive:bumble`
  inherits this by executing the phase skills fresh.
- **Per-project override at `.hive/models.yaml`** (a Hive-scoped path — a bare
  `models.yaml` at repo root could collide with a consuming repo's tooling).
  **Two-key shallow rule, no deep-merge**: the project file may set `active:`
  alone (the plugin's shipped presets still apply); if it also contains a
  `presets:` block, that block wins **wholesale**. No per-role merging.
- **Frontmatter is the fallback tier, aligned to `balanced`.** Each agent still
  pins `model:` in its frontmatter. The spawn-time param wins whenever config
  resolves; on **any** resolution failure (missing or unparseable plugin
  `models.yaml`, missing preset, or missing role key) the skill omits the
  `model` param and the agent's frontmatter default applies, with a one-line
  warning. An unparseable `.hive/models.yaml` is ignored entirely — the plugin
  config still applies. Model config never hard-fails a lifecycle command.

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
