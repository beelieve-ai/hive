---
name: comb
description: "Turn an approved PRD into a reviewed plan.yaml and materialize it as a GitHub milestone with an epic and a task DAG. Invoke explicitly as /hive:comb <PRD-id> [--new-phase] (e.g. /hive:comb PRD-003). One comb run = one plan = one milestone = one phase; --new-phase plans the next phase of a PRD whose phases are all implemented. Runs planner → three parallel plan reviewers → human approval gate → idempotent materialization."
disable-model-invocation: true
---

# /hive:comb — plan an approved PRD

You are the orchestrator. `$ARGUMENTS` is the PRD id (e.g. `PRD-003`),
optionally followed by `--new-phase`. You draft a plan via the planner
agent, get it past three parallel reviewers, present it to the user for
explicit approval, and only then materialize it into GitHub issues. **One
comb run = one plan.yaml = one milestone = one phase**; a PRD phases into
several milestones by being combed several times, tracked append-only in
its `milestones:` frontmatter list (schema in `hive:writing-prds`). Load the **`hive:gh-conventions`** skill for
the exact `gh` command syntax before running any `gh` command; the
sequencing and gates below are load-bearing and stated inline.

Ground rules that bind every step:

- The human gate before materialization is **mandatory** — never skip it,
  never treat silence as approval.
- Reviewer verdicts are parsed **only** from the FIRST fenced ```json block
  of each reply; a missing or unparseable block counts as **fail**, never
  pass.
- All `gh` reads use `--json`. New issue numbers come from the sanctioned
  URL-stdout exception: strict `/issues/<number>` parse (fail on zero or
  multiple matches) followed by a `gh issue view <n> --json ...` verify.
- You never read code or implement anything — planning detail lives in the
  planner and reviewer subagent contexts.

## Step 0 — Resolve inputs and detect resume state

1. Parse `$ARGUMENTS`: strip an optional `--new-phase` flag wherever it
   appears (record it); the remaining token is the PRD id. Glob
   `docs/prd/<PRD-id>-*.md` — exactly one match, else abort with the
   candidates found. Read its frontmatter and route on `status:`:
   - `draft` → tell the user to approve the PRD first and stop.
   - `approved`, `planned`, or `implemented` → continue; item 3 decides
     between resuming an open phase and starting a new one (`planned` and
     `implemented` are derived from the `milestones:` list per
     `hive:writing-prds` — neither is a stop by itself).

   **Legacy frontmatter**: singular non-null `milestone:` / `epic_issue:`
   fields are read as a one-entry `milestones:` list (its `plan:` resolved
   from the item-3 grep; its `status:` mirrors the PRD status —
   `implemented` if the PRD says `implemented`, else `planned`). Rewrite to
   list form at the next frontmatter write (4.5).
2. Collect ADR paths from two sources:
   - for each id in the PRD's `adrs:` frontmatter list, glob
     `docs/adr/<id>-*.md` and confirm the doc's `status: accepted`;
   - glob `docs/adr/ADR-*.md` and add every ADR whose frontmatter says
     `scope: repo` **and** `status: accepted` — repo-scoped platform
     decisions bind every plan without appearing on any PRD's `adrs:`
     list.

   Pass **only accepted ADRs** to the planner, as planner input in Step
   1.2 — never edit a returned plan's `adrs:` yourself (that list is
   planner output, vetted by the reviewers). An empty combined list is
   valid — the whole flow works with zero ADRs (`adrs: []`).
3. Resume/phase check: grep `docs/plans/PLAN-*.yaml` for `prd: <PRD-id>`
   (**multiple matches are legitimate** — one plan per phase) and read the
   PRD's `milestones:` list. Decide in this order — first rule that
   applies wins:
   - **A plan with `status: draft` exists** → resume that phase at Step 2
     (review loop). More than one non-materialized (`draft`/`reviewed`)
     plan for one PRD → abort and report the candidates (phases are
     planned one at a time; this state is corrupted).
   - **A plan with `status: reviewed` exists** → resume that phase at
     Step 3 (gate). If any task already has a non-null `issue:` or the
     milestone already exists, an earlier materialization was interrupted
     — say so in the summary; the gate still applies before continuing.
   - **A `materialized` plan is missing from the `milestones:` list (no
     entry with its plan id) or its completion is unverified** →
     **repair/adopt, never re-plan**: verify the materialization actually
     finished (a failure between the status write in 4.5 and the final
     steps 4.6/4.7 must be resumable, not stranded):
     - **`milestones:` entry present?** Missing → resume at Step 4.5
       item 2 (append the entry; reconcile the milestone/epic numbers
       from GitHub per Step 4.0's lookups), then 4.6, 4.7.
     - **Milestone marker present?** Resolve the milestone number (the
       plan's `milestones:` entry, or lookup by the plan's
       `milestone_title` per Step 4.0) and GET its description — it must
       contain `plan-review: passed (PLAN-NNN)`. Missing → resume at
       Step 4.6 (idempotent), then 4.7.
     - **Write-backs committed and pushed?** The plan.yaml (all `issue:`
       numbers, `status: materialized`) and the PRD frontmatter
       write-backs must be clean in the working tree (`git status
       --porcelain` empty for those paths) **and** present on
       `origin/main` (fetch, then confirm the files on `origin/main`
       carry the write-backs). Not committed or not pushed → resume at
       Step 4.7.
     - All complete → nothing to repair; fall through to the next rule.
     The human gate is not re-required on this path: `status:
     materialized` can only have been written after approval, and steps
     4.5 item 2 / 4.6 / 4.7 create no issues.
   - **A `milestones:` entry has `status != implemented`** (its plan
     cleanly materialized) → that phase awaits execution — report the
     existing milestone/epic/issue numbers, point at
     `/hive:swarm <PRD-id>`, and stop.
   - **No plan matches at all** → fresh run (first phase), continue with
     Step 1.
   - **Every phase is implemented** → a new phase is a deliberate act:
     with `--new-phase`, continue with Step 1; without it, ask via
     **AskUserQuestion** whether to plan a new phase for this PRD
     (decline → stop). The new phase allocates a new PLAN-NNN (Step 1)
     and appends a new `milestones:` entry (4.5); the PRD legally
     transitions `implemented → planned` per `hive:writing-prds` — the
     approval gate is **not** re-run (it covers content, not phasing).

## Model preset resolution

Before spawning any agent below — including re-spawns and fix rounds — resolve
its model from the Hive model config:

1. Read `models.yaml` under the Hive plugin root (the `Hive plugin root:` path
   injected at session start). Missing or unparseable → warn once, omit the
   `model` param on all spawns (agent frontmatter defaults apply), and skip
   the remaining steps.
2. If `.hive/models.yaml` exists at the repo root, read it. Unparseable →
   warn once and ignore it entirely; the plugin config still applies. It has
   two optional flat keys: `active:` (preset switch) and `agents:`
   (role → model pins).
3. `active` = the project file's `active:` if set, else the plugin's.
4. For each spawn, `<role>` = the agent name without the `hive:` prefix,
   normalized so that any `plan-reviewer-*` agent maps to the single
   `plan-reviewer` key (e.g. `hive:plan-reviewer-dag` → `plan-reviewer`).
5. `model` = the project file's `agents.<role>` if set, else
   `presets[active][<role>]` from the plugin config. Neither present →
   warn and omit `model` for that spawn.

Pass the resolved model as the `model` parameter on the Agent call. Never
hard-fail the command over model config — a warning plus frontmatter fallback
is always the correct degradation.

### Worker tier for plan calibration

Once per run, additionally resolve the **worker** role's model with the same
rules and classify the implementor tier: a haiku-class name → `weak`;
`sonnet`/`opus`/`fable` → `strong`; resolution failed or name unrecognized →
`weak` (the safe default — worst case is an overly explicit plan). For an
unrecognized name in an interactive session, you may confirm the tier via
AskUserQuestion instead of silently defaulting. Pass the resolved worker
model and tier to the planner in Step 1.2; the planner records them in the
plan's `calibration:` block and calibrates task-body explicitness per the
`hive:decomposition` skill's **Calibration and weak-mode anatomy** section.

## Step 1 — Draft the plan

1. Allocate the plan id: glob `docs/plans/PLAN-*.yaml`, take the highest
   `NNN` + 1, zero-padded to three digits (`PLAN-001` if none exist).
   IDs are append-only, never reused.
2. Spawn the **planner** agent (Agent tool, subagent_type `hive:planner`)
   with: the PRD path, the list of
   accepted ADR paths (possibly empty), the allocated PLAN-NNN id, and the
   worker model + implementor tier from **Worker tier for plan
   calibration**.
   The planner returns the complete plan.yaml as a single fenced ```yaml
   block — it never writes files.
3. Extract that YAML block and write it to
   `docs/plans/PLAN-NNN-<slug>.yaml` (slug derived from the PRD slug or
   the plan's `milestone_title`). Sanity-check before proceeding:
   `status: draft`, `review: null`, `prd:` matches `$ARGUMENTS`, a
   non-empty `milestone_verification.command` is present (the sizing
   reviewer additionally judges its quality), a `calibration:` block with
   the tier you passed is present, every
   task has `issue: null`, and every task body starts with the
   crosslinking header block (`**PRD:** ...` with full
   `https://github.com/<owner>/<repo>/blob/<default-branch>/...` URLs built
   for the current repo per `hive:crosslinking`). If the
   returned content violates any of these, send it back to the planner
   with the defect named — do not patch planner output yourself beyond
   frontmatter fields this skill owns (`review`, `reviewed_by`,
   `reviewed_at`, `status`, `issue:` write-backs).

## Step 2 — Review loop (max 3 iterations total)

Track an iteration counter starting at 1. An "iteration" is one
reviewer round; the cap of **3 total** includes the first round.

1. **Round 1: spawn ALL THREE reviewers IN PARALLEL — three Agent tool
   calls in ONE message**: `hive:plan-reviewer-context`,
   `hive:plan-reviewer-dag`, `hive:plan-reviewer-sizing`. Each gets exactly
   one input: the plan.yaml
   path.
2. **Parse each reply**: take the FIRST fenced ```json block and parse it
   against `{"verdict":"pass|fail","findings":[{"task","issue","fix"}]}`.
   A reply with no such block, or a block that fails to parse, means that
   reviewer **failed** (and counts as a failing reviewer for rerun
   selection). Never infer a pass from prose.
3. **Aggregate**: overall pass = all three verdicts are `"pass"`.
4. **On overall pass** → Edit the plan.yaml frontmatter:
   `review: passed`, `reviewed_by: [context, dag, sizing]`,
   `reviewed_at: <today, YYYY-MM-DD>`, `status: reviewed`, and append a
   `plan-reviewed` entry (subject: PLAN-NNN) to the PRD's audit log per the
   colony `Audit log` section. Go to Step 3.
5. **On fail** — if the iteration counter is already 3, **abort with a
   report**: list every outstanding finding grouped by task key and by
   reviewer, leave the plan at `status: draft`, and stop. Otherwise:
   a. **Group findings per task key, MERGED across reviewers** — collect
      every finding from every failing reviewer under its `task` key.
      Distinct issues on the same task are **never dropped or
      deduplicated away**; only literally identical findings may collapse
      into one.
   b. Snapshot the current plan's structure for the later diff: the
      ordered list of task keys and each task's `depends_on` list.
   c. Send the grouped findings to the **planner** (Agent tool) together
      with the current plan.yaml path, asking for a revised plan. It
      returns the full revised document; overwrite the plan.yaml with it
      (keep `status: draft`; re-run the Step 1.3 sanity checks).
   d. **Classify the correction by diffing** the snapshot against the
      revised plan — compare task keys (set), their order, and every
      task's `depends_on`:
      - Any key added/removed (split/merge), any reorder, or any
        `depends_on` change → **STRUCTURAL** → increment the counter and
        re-run **all three** reviewers in parallel (one message).
      - Everything else (body text, links, criteria, titles,
        `parallel_ok`, `implements`/`adr_refs` edits) → **CONTENT** →
        increment the counter and re-run **only the reviewers that failed
        the previous round** (in parallel, one message, if more than one).
        Reviewers that passed keep their pass.
   e. Parse and aggregate again from step 2.2.

## Step 3 — Human gate (mandatory)

Show the user a task summary table built from the reviewed plan: for each
task its key, title, `depends_on`, an approximate size (files touched per
its Context block), plus the milestone title and epic title. If resuming an
interrupted materialization, also list what already exists (milestone,
epic number, task issue numbers already recorded).

Then ask for the verdict with **AskUserQuestion** (one call): options
**"Approve — materialize the plan"** (description: exactly what will be
created — milestone, epic, N task issues), **"Request changes"**, and
**"Decline"**. Do not materialize on anything less than an explicit Approve
selection. If the user requests changes, send them to the planner as
findings (Step 2.5 flow, fresh iteration counter) and re-run all three
reviewers before returning to this gate. If the user declines, stop — the
plan stays `status: reviewed`.

Sole exception: under a `/hive:bumble --yolo` run, approval for a plan
drafted and reviewed within that same run was delegated at invocation per
the colony carve-out — record it as approved without posing the question;
a plan that already existed when the bumble run started is always posed to
the human.

Record the verdict in the PRD's audit log (colony `Audit log` section):
`plan-approved` (`by: human`, or `by: yolo` under the carve-out) or
`plan-declined`, subject: PLAN-NNN. On a resume that re-poses this gate,
skip the append when the log already records that verdict. An approval's
entry rides the Step 4.2 commit; a Decline commits the audit log
**together with the reviewed plan.yaml** (sync main first per
`gh-conventions`, then push) before stopping — never split the entry from
the plan it records.

## Step 4 — Materialize (only after approval; resumable and IDEMPOTENT)

A partial failure (rate limit, network, crash) must **never** duplicate
the milestone, the epic, or any task. Two mechanisms guarantee this:
issue numbers are written back into plan.yaml **immediately** after each
create (never batched), and on every (re-)entry you first look up what
already exists on GitHub and reuse/skip it.

### 4.0 Pre-scan (always, even on a fresh run)

0. **Issue-type mode probe** (per gh-conventions):
   `gh api repos/{owner}/{repo} --jq .owner.type` — `Organization` →
   native `--type` mode, after verifying the org actually exposes the
   **Epic** and **Task** types (`gh api orgs/{owner}/issue-types --jq
   '.[].name'`); either missing → **fall back to label mode and note it
   in the summary**. `User` → label mode (`type:epic` / `type:task`
   labels, no `--type`). Then **ensure all labels exist** idempotently:
   `gh label create <name> --force` for `hive:managed`, `phase:build`,
   `phase:review`, `hive:parked`, and — label mode only — `type:epic`,
   `type:task`.
1. **Milestone lookup by title**: per gh-conventions,
   `gh api "repos/{owner}/{repo}/milestones?state=all" --paginate` and
   match the plan's `milestone_title` exactly against `.title`. Exactly
   one match → capture its `.number` and **reuse it, do not create**.
   Multiple matches → abort and report.
2. If the milestone exists, list its `hive:managed` issues:
   `gh issue list --milestone "<title>" --state all --json
   number,title,state,parent,issueType,labels`. Note any existing epic
   (label `hive:managed` AND the mode-agnostic epic test: `issueType.name
   == "Epic"` OR label `type:epic`; more than one → abort and report) and
   existing tasks, for reuse below.

### 4.1 Milestone

If not found in 4.0, create it:
`gh api repos/{owner}/{repo}/milestones -f title="<milestone_title>"`,
capturing **`.number`** from the POST response (e.g. `--jq .number`).
This is a **milestone number** — a numbering space separate from issue
numbers. It is what the PRD's `milestones:` entry stores in its
`milestone:` field and what every later PATCH targets; never confuse it
with an issue number.

Then (created or reused) stamp the **provenance mirror** into the
milestone description via read-modify-write per `hive:gh-conventions` —
skip lines already present (resume case), never blind-PATCH:

```
prd: PRD-NNN
plan: PLAN-NNN
```

The mirror is human-facing provenance for people browsing GitHub. The
authoritative link is the PRD's `milestones:` list — nothing parses the
mirror for scheduling.

### 4.2 Commit and push docs BEFORE creating any issues

Issue bodies link to the docs via full
`https://github.com/<owner>/<repo>/blob/<default-branch>/...` URLs — those
links 404 unless the docs are on the default branch first. So, before the first
`gh issue create`:

1. `git switch main && git pull --ff-only origin main` (never commit on a
   stale main).
2. Commit the reviewed plan.yaml, the PRD's audit log, and the PRD if its
   file changed, e.g. `docs(plans): add PLAN-NNN for $ARGUMENTS`.
3. `git push origin main`. If the push fails, stop and report — do not
   create issues against unpushed docs.

Skip the commit if the docs are already committed and pushed (resume
case, nothing staged) — but always verify main is synced and the plan
file is on the remote before proceeding.

### 4.3 Epic issue

If 4.0 found an existing `hive:managed` epic in the milestone, reuse its
number. Otherwise create it from the plan's `epic:` block:

```
# native mode
gh issue create --title "<epic.title>" --body "<epic.body>" --milestone "<milestone_title>" --label hive:managed --type Epic
# label mode
gh issue create --title "<epic.title>" --body "<epic.body>" --milestone "<milestone_title>" --label hive:managed,type:epic
```

The `hive:managed` label **and** the milestone are load-bearing —
`/hive:swarm`'s epic discovery filters on both; an epic missing either is
invisible to the build loop. The epic body must start with the
crosslinking header block (full `blob/main` URLs; **Implements:** lists
the PRD id itself).

Capture the epic number from the create command's URL stdout: strict
parse of exactly one `/issues/<number>` match — **fail on no match or
multiple matches** — then verify with
`gh issue view <n> --json number,title,issueType,milestone,labels` that
type (native mode) or `type:epic` label (label mode), milestone, and label
all match what was requested.

### 4.4 Task issues — topological order, immediate write-back

Compute a topological order of the plan's tasks from `depends_on`
(dependencies first, so every `--blocked-by` value references an
already-created issue number; the dag reviewer guaranteed the graph is
cycle-free). Then for each task in that order:

1. **Skip if already created**: if the task's `issue:` in plan.yaml is
   non-null, verify it still exists
   (`gh issue view <n> --json number,state,issueType,milestone,parent,labels,blockedBy`)
   and move on. If `issue:` is null but 4.0 found an existing
   `hive:managed` task (per the mode-agnostic task test:
   `issueType.name == "Task"` OR label `type:task`) in the milestone
   with the identical title, adopt
   that number: verify it via `gh issue view --json`, write it back into
   plan.yaml, and move on — never create a duplicate.
2. Otherwise create it. The body is the task's `body:` verbatim — it
   already starts with the crosslinking header block and carries the
   task's `## Context`, `## Acceptance criteria`, and `## Verification`
   sections (verified in Step 1.3). Map the task's `depends_on` keys to
   the issue numbers already recorded in plan.yaml:

   ```
   # native mode
   gh issue create --title "<task.title>" --body "<task.body>" --milestone "<milestone_title>" --parent <epic#> --blocked-by <n1>,<n2> --label phase:build,hive:managed --type Task
   # label mode
   gh issue create --title "<task.title>" --body "<task.body>" --milestone "<milestone_title>" --parent <epic#> --blocked-by <n1>,<n2> --label phase:build,hive:managed,type:task
   ```

   Omit `--blocked-by` entirely for tasks with no dependencies. If any
   `depends_on` key maps to a null `issue:`, the topological order is
   broken — abort and report rather than guessing.
3. Capture the number from URL stdout (strict single-match
   `/issues/<number>` parse, fail on zero/multiple) and verify with
   `gh issue view <n> --json number,title,issueType,milestone,parent,labels,blockedBy`
   that type (native mode) or `type:task` label (label mode), milestone,
   parent, labels, and blockedBy all match.
4. **Immediately Edit plan.yaml**, setting this task's `issue: <n>` —
   before creating the next issue, never batched at the end. This
   write-back is the resume record.

If any create or verify fails mid-loop, stop and report which tasks were
created; re-running `/hive:comb $ARGUMENTS` resumes here without duplicates.

### 4.5 Doc status write-backs

After **all** tasks have issue numbers:

1. plan.yaml: `status: materialized`.
2. PRD frontmatter: **append** the phase entry to the `milestones:` list —
   `plan: PLAN-NNN`, `milestone: <milestone-number>` (the number from 4.1,
   not an issue number), `epic_issue: <epic#>`, `status: planned` — and
   set `status: planned`. The list is append-only: never overwrite or
   reorder existing entries, and append only if the plan id is not yet
   represented (the Step 0.3 repair/adopt path may re-enter here). If the
   PRD still carries legacy singular `milestone:`/`epic_issue:` fields,
   convert them to their list entry first, then delete the singular
   fields.
3. Append `plan-materialized` (subject: PLAN-NNN) and `prd-planned`
   (subject: the PRD id, detail: `plan: PLAN-NNN; milestone: <n>`) entries
   to the PRD's audit log.

Note: `status: materialized` alone does not mean the run finished —
steps 4.6 and 4.7 still follow, and Step 0 item 3's materialized branch
verifies their completion on re-entry before declaring there is nothing
to do.

### 4.6 Milestone marker (read-modify-write — never blind PATCH)

Append `plan-review: passed (PLAN-NNN)` to the milestone description:

1. GET: `gh api repos/{owner}/{repo}/milestones/<milestone-number> --jq .description`
2. If the marker line is already present (resume case), skip the PATCH.
   Otherwise append the line to the fetched text.
3. PATCH the **full** resulting text back:
   `gh api repos/{owner}/{repo}/milestones/<milestone-number> -X PATCH -f description="<full updated text>"`

This marker is `/hive:swarm`'s deterministic start gate — without it the
milestone is refused.

### 4.7 Final commit and push

Sync main again if anything was merged meanwhile
(`git switch main && git pull --ff-only origin main`), then commit the
write-backs (plan.yaml issue numbers + status, PRD frontmatter, audit
log), e.g.
`docs(plans): materialize PLAN-NNN into milestone <title>`, and
`git push origin main`.

### 4.8 Glossary-gaps tracker (idempotent)

Audit logs are append-only provenance with no "resolved" event, so
resolution is **computed**, never recorded:

1. Read `docs/audit/<PRD-ID>-audit.md` and collect every term from
   `glossary gaps: ...` lists in entry detail fields (comma-separated
   terms, per `/hive:waggle`). No such lists → skip this step entirely.
2. Drop every collected term that now has a `## <Term>` entry in root
   `CONTEXT.md` — the glossary itself is the resolution ground truth.
   Compare normalized per the gh-conventions tracker section
   (case-insensitive, trimmed, singular/plural folded). A missing
   `CONTEXT.md` resolves nothing.
3. Reconcile the tracker issue per the **Glossary-gaps tracker issue**
   section of `hive:gh-conventions` (exact title `Glossary gaps:
   <PRD-ID>`, label `glossary`, no `hive:managed`, this milestone):
   unresolved terms remain → create it, or update the body and reopen if
   closed; unresolved set empty → close an open tracker. This issue is a
   reminder for `/hive:sting` / grilling — comb never edits `CONTEXT.md`.

## Final report

Print: the plan id and path, review iterations used, milestone title and
**milestone number**, epic issue number, a `task key → issue #` table in
creation order, the glossary-gaps tracker state if step 4.8 touched it
(issue number + unresolved terms, and that they are settled via
`/hive:sting` or a grilling session), and the follow-up command:
`/hive:swarm <PRD-id>` (runs every remaining phase in order; pass the
milestone title or number instead to run just this one).
