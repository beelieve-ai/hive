---
name: decomposition
description: Task decomposition rules for Hive plans — sizing heuristics (one task per fresh-context agent session, 2–5 files), the self-containedness checklist for task bodies, DAG design with explicit depends_on edges and honest parallel_ok, and the mandatory runnable Verification section.
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

## Verification section (mandatory)

Every task body ends with a `## Verification` section containing **runnable
command(s)** whose failure means the task is not done:

```
## Verification
- `pytest tests/test_ingest.py -q` — all tests pass
- `python -m hive.ingest --dry-run sample.csv` — exits 0 and prints 3 rows
```

- Commands must be executable by the worker from the repo root with no manual
  setup beyond what the task itself establishes.
- "Code review looks good" or "file exists" alone is not verification — prefer
  a test invocation or an observable behavior check. (A `test -f path` check
  is acceptable only for pure file-creation tasks.)

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
adr_refs: [ADR-NNNN]         # ADRs whose decisions constrain this task ([] only if the plan has no ADRs)
```

- Each requirement ID must exist as a `### R<n>: ...` anchor in the referenced
  PRD; each ADR ref must be an accepted ADR listed in the plan's `adrs:`.
- Every PRD requirement in scope must be covered by at least one task —
  uncovered requirements mean the decomposition is incomplete.
- The task body's header block repeats this traceability per the crosslinking
  skill (`**PRD:** ... · **Implements:** ... · **ADR:** ...`).

## Template

The planner emits `plan.yaml` from this skeleton (this skill is the source of
truth — no external template file is required):

```yaml
plan: PLAN-NNN
prd: PRD-NNN
adrs: [ADR-NNNN]
status: draft | reviewed | materialized
review: null            # set to "passed" by /hive:comb after all three reviewers pass
reviewed_by: []
reviewed_at: null
milestone_title: ...
epic:
  title: ...
  body: ...
tasks:
  - key: T1              # stable key inside the plan; issue number assigned at materialization
    title: ...
    implements: [PRD-NNN-R1]   # requirement IDs
    adr_refs: [ADR-NNNN]
    depends_on: []       # list of task keys → becomes GH "blocked by"
    parallel_ok: true
    body: |
      ## Context
      <self-contained: concrete file paths, conventions, links>
      ## Acceptance criteria
      - ...
      ## Verification
      <command(s) to run, e.g. test invocation>
    issue: null          # GH issue number, filled at materialization by /hive:comb
```
