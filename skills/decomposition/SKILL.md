---
name: decomposition
description: Task decomposition rules for Hive plans — sizing heuristics (one task per fresh-context agent session, 2–5 files), the self-containedness checklist for task bodies, calibration-aware weak-mode task anatomy (Preflight/Goal/Files/Changes), DAG design with explicit depends_on edges and honest parallel_ok, and the mandatory runnable Verification section.
---

# Decomposition

How to break an approved PRD (plus its accepted ADRs) into a `plan.yaml` task
DAG that fresh-context worker agents can execute one issue at a time. The
plan-reviewer agents (context, dag, sizing) check exactly these rules — write
to pass them the first time.

## Task sizing

**One task ≈ one fresh-context agent session ≈ 2–5 files touched.**

- A worker starts with an empty context, reads only its own issue plus the
  linked PRD/ADR sections, implements, verifies, and commits. If a task cannot
  be completed comfortably in one such session, it is too big — split it.
- 2–5 files touched (created or edited) is the target band. One file is fine
  when the change is genuinely isolated; more than 5 is a strong split signal.
- Split along seams that keep each piece independently verifiable (e.g. data
  model first, then consumer; not "first half of the function, second half").
- Do not merge trivially small tasks just to reduce count — a small,
  well-verified task is cheaper than an entangled one.
- **Vertical slices — every task ends green.** After any task's verification
  passes, the repo builds, tests pass, and the functionality delivered so
  far demonstrably works end to end. No task may leave the system broken
  for a later task to repair — split along seams that keep this true.
  Granularity serves verifiability, never ceremony: don't pad steps to
  look thorough.

## Self-containedness checklist

The worker sees **only its own issue body**. Every task `body:` must satisfy
all of the following:

- [ ] **Concrete existing file paths** — name the exact files to create or
  modify (`src/foo/bar.py`, not "the parser module"). Paths to existing files
  must actually exist at planning time (reviewers verify with Glob); paths to
  new files state their intended location explicitly.
- [ ] **Conventions restated or linked** — any project convention the task
  relies on (naming, error handling, test layout) is either restated inline or
  linked via full URL to the governing doc. Never assume the worker knows it.
- [ ] **No "see previous task" references** — a task body never points at
  another task's body, discussion, or output description. If task B needs to
  know what task A produced, describe the artifact concretely in B's body
  (file path, shape, contract) *and* add the dependency edge.
- [ ] **Acceptance criteria** — measurable, checkable statements of done.
- [ ] **Verification section** — see below.

## Calibration and weak-mode anatomy

Every plan carries a top-level `calibration:` block recording the worker
model and implementor tier the orchestrator resolved (`weak` or `strong`;
unresolved → `weak`). Task-body explicitness is calibrated to it: a weak
implementor executes instructions — it cannot reliably infer intent,
recover from a false premise, or debug a broken intermediate state.

In **weak** mode, every task's `## Context` section contains, in order,
these `###` subsections:

- **Preflight** — the assumptions this task rests on that the planner could
  not fully verify at planning time. Each entry: the assumption plus one
  check command meeting the Verification bar (repo-root runnable, headless,
  self-asserting — exit code decides). The list ends with the literal line
  **"If any check fails: stop and report — do not improvise."** Write
  `Preflight: none` when everything was verified during planning. Preflight
  is the unresolvable residue — never a dumping ground for facts the
  planner could have checked itself with Read/Grep/Glob.
- **Goal** — one sentence: what this task makes true.
- **Files** — the exact paths to create or modify, one per line.
- **Changes** — a concrete description of each change. Short code snippets
  only where a weak model would plausibly get it wrong (tricky APIs, exact
  signatures, non-obvious idioms) — never full pre-written diffs; prose
  naming the function, its shape, and its behavior is the default.

In **strong** mode the subsections are optional; the self-containedness
checklist above binds in full either way.

A task's `## Context` block may embed a ```` ```mermaid ```` fenced
diagram when the flow or data shape is easier shown than told — GitHub
renders it in the issue UI. Optional; fenced ASCII art only when mermaid cannot express the
figure, never both forms of the same figure.

## Verification section (mandatory)

Every task body ends with a `## Verification` section containing **runnable
command(s)** whose failure means the task is not done:

```
## Verification
- `pytest tests/test_ingest.py -q` — all tests pass
- `python -m hive.ingest --dry-run sample.csv | grep -qx 'rows: 3'` — asserts the dry run reports exactly 3 rows
```

- Commands must be executable by the worker from the repo root with no manual
  setup beyond what the task itself establishes.
- Commands must be **self-asserting**: the assertion lives in the command
  itself — a test runner, a `grep -q` pipe, a script that exits nonzero on
  failure. The **exit code alone** decides pass/fail; a human (or agent)
  reading output and judging it is not verification. Prose like "exits 0 and
  prints 3 rows" fails review — encode the expectation
  (`… | grep -qx 'rows: 3'`).
- "Code review looks good", "check the UI looks right", or "file exists"
  alone is not verification — anything needing eyes must be rewritten into an
  automated check (assertion test, snapshot test, e2e script). There is no
  manual-verification escape hatch. (A `test -f path` check is acceptable
  only for pure file-creation tasks.)

## Milestone verification (mandatory)

Every plan carries a **plan-level** `milestone_verification.command` — the
integration check `/hive:swarm` runs on `main` after **every** squash-merge.
Per-task commands pass in isolation while the integrated milestone quietly
breaks; this command is what keeps main green across the whole build loop.

- Same rules as task verification: repo-root runnable, headless,
  self-asserting, exit code decides.
- Scope it to run after every merge: the full test suite when it's fast, a
  smoke subset when it isn't — that scope is the planner's judgment, but it
  must exist.

## DAG design

- **Explicit `depends_on` edges**: if task B consumes *any* output of task A —
  a file, a function, a schema, a config key — B **requires** a `depends_on`
  edge to A. No implicit ordering, no "they'll probably run in order".
  `depends_on` lists task keys (`T1`, `T2`) and becomes GitHub `blocked by` at
  materialization.
- **Mark `parallel_ok` honestly**: `parallel_ok: true` asserts the task can run
  concurrently with every other task it shares no dependency path with — same
  files untouched, no hidden shared state. When in doubt, set `false`.
- **Cycle-free, always**: the graph must have a valid topological order
  (materialization creates issues in that order so `--blocked-by` can reference
  already-created issue numbers).
- **Shallow where possible**: prefer a wide graph of independent tasks over a
  long chain. Only add an edge for a real consumption relationship — a fake
  edge serializes work for nothing, a missing edge breaks the build.

## Traceability

Every task implements **specific requirement IDs** and names the ADRs that
constrain it:

```yaml
implements: [PRD-NNN-R1]     # requirement anchors from the PRD, never empty
adr_refs: [ADR-NNNN]         # ADRs whose decisions constrain THIS task ([] when none do)
```

- Each requirement ID must exist as a `### R<n>: ...` anchor in the referenced
  PRD; each ADR ref must be an accepted ADR listed in the plan's `adrs:`.
- `adr_refs: []` is valid whenever no ADR in the plan's `adrs:` constrains
  that particular task — plans carry repo-scoped platform ADRs that do not
  bind every task. Citing them where they *do* apply is the planner's
  judgment; a worker only ever sees the ADRs named in its own task.
- Every PRD requirement in scope must be covered by at least one task —
  uncovered requirements mean the decomposition is incomplete.
- The task body's header block repeats this traceability per the crosslinking
  skill (`**PRD:** ... · **Implements:** ... · **ADR:** ...`).

## Template

The planner emits `plan.yaml` from this skeleton (this skill is the source of
truth — no external template file is required). The epic `body:` may carry a
mermaid `graph` of the task DAG — a static snapshot at materialization;
execution state stays in GitHub dependencies, never the doc:

```yaml
plan: PLAN-NNN
prd: PRD-NNN
adrs: [ADR-NNNN]        # all accepted ADRs given by /hive:comb — PRD-listed and repo-scoped
status: draft | reviewed | materialized
review: null            # set to "passed" by /hive:comb after all three reviewers pass
reviewed_by: []
reviewed_at: null
calibration:
  worker_model: haiku    # resolved by /hive:comb from models.yaml / .hive/models.yaml
  tier: weak             # weak | strong — unresolved defaults to weak
milestone_title: ...
milestone_verification:
  command: ...           # self-asserting, repo-root runnable; /hive:swarm runs it on main after every merge
epic:
  title: ...
  body: |
    ...
tasks:
  - key: T1              # stable key inside the plan; issue number assigned at materialization
    title: ...
    implements: [PRD-NNN-R1]   # requirement IDs
    adr_refs: [ADR-NNNN]       # ADRs constraining this task; [] when none do
    depends_on: []       # list of task keys → becomes GH "blocked by"
    parallel_ok: true
    body: |
      ## Context
      <self-contained: concrete file paths, conventions, links.
       weak tier: the ### Preflight / ### Goal / ### Files / ### Changes
       subsections per "Calibration and weak-mode anatomy">
      ## Acceptance criteria
      - ...
      ## Verification
      <command(s) to run, e.g. test invocation>
    issue: null          # GH issue number, filled at materialization by /hive:comb
```
