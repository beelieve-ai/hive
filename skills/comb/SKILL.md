---
name: comb
description: "Turn an approved PRD into a reviewed plan.yaml and materialize it as a GitHub milestone with an epic and a task DAG. Invoke explicitly as /hive:comb <PRD-id> (e.g. /hive:comb PRD-003). Runs planner → three parallel plan reviewers → human approval gate → idempotent materialization."
disable-model-invocation: true
---

# /hive:comb — plan an approved PRD

You are the orchestrator. `$ARGUMENTS` is the PRD id (e.g. `PRD-003`).
You draft a plan via the planner agent, get it past three parallel
reviewers, present it to the user for explicit approval, and only then
materialize it into GitHub issues. Load the **`hive:gh-conventions`** skill for
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

1. Glob `docs/prd/$ARGUMENTS-*.md` — exactly one match, else abort with the
   candidates found. Read its frontmatter. Require `status: approved` (if
   `draft`, tell the user to approve the PRD first and stop). If
   `status: planned`, this PRD was already materialized — but do **NOT**
   stop yet: the PRD is flipped to `planned` in Step 4.5, *before* the
   milestone marker (4.6) and the final commit+push (4.7) run, so a crash
   in that window leaves `status: planned` with the run unfinished.
   Continue to item 3 and run its `status: materialized` completion
   verification; only report "already materialized" and stop after **both**
   of its checks (marker present, write-backs pushed) confirm completion.
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
3. Resume check: grep `docs/plans/PLAN-*.yaml` for `prd: $ARGUMENTS`.
   - No match → fresh run, continue with Step 1.
   - Match with `status: draft` → resume at Step 2 (review loop).
   - Match with `status: reviewed` → resume at Step 3 (gate). If any task
     already has a non-null `issue:` or the milestone already exists, an
     earlier materialization was interrupted — say so in the summary; the
     gate still applies before continuing.
   - Match with `status: materialized` → **verify the materialization
     actually finished before stopping** (a failure between the status
     write in 4.5 and the final steps 4.6/4.7 must be resumable, not
     stranded):
     - **Milestone marker present?** Resolve the milestone number (PRD
       `milestone:` frontmatter, or lookup by the plan's
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
     - Both complete → nothing to do; report the existing
       milestone/epic/issue numbers and stop.
     The human gate is not re-required on this path: `status:
     materialized` can only have been written after approval, and steps
     4.6/4.7 create no issues.

## Step 1 — Draft the plan

1. Allocate the plan id: glob `docs/plans/PLAN-*.yaml`, take the highest
   `NNN` + 1, zero-padded to three digits (`PLAN-001` if none exist).
   IDs are append-only, never reused.
2. Spawn the **planner** agent (Agent tool, subagent_type `hive:planner`)
   with: the PRD path, the list of
   accepted ADR paths (possibly empty), and the allocated PLAN-NNN id.
   The planner returns the complete plan.yaml as a single fenced ```yaml
   block — it never writes files.
3. Extract that YAML block and write it to
   `docs/plans/PLAN-NNN-<slug>.yaml` (slug derived from the PRD slug or
   the plan's `milestone_title`). Sanity-check before proceeding:
   `status: draft`, `review: null`, `prd:` matches `$ARGUMENTS`, every
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
   `reviewed_at: <today, YYYY-MM-DD>`, `status: reviewed`. Go to Step 3.
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

## Step 4 — Materialize (only after approval; resumable and IDEMPOTENT)

A partial failure (rate limit, network, crash) must **never** duplicate
the milestone, the epic, or any task. Two mechanisms guarantee this:
issue numbers are written back into plan.yaml **immediately** after each
create (never batched), and on every (re-)entry you first look up what
already exists on GitHub and reuse/skip it.

### 4.0 Pre-scan (always, even on a fresh run)

1. **Milestone lookup by title**: per gh-conventions,
   `gh api "repos/{owner}/{repo}/milestones?state=all" --paginate` and
   match the plan's `milestone_title` exactly against `.title`. Exactly
   one match → capture its `.number` and **reuse it, do not create**.
   Multiple matches → abort and report.
2. If the milestone exists, list its `hive:managed` issues:
   `gh issue list --milestone "<title>" --state all --json
   number,title,state,parent,issueType,labels`. Note any existing epic
   (`issueType == "Epic"` with label `hive:managed`; more than one →
   abort and report) and existing tasks, for reuse below.

### 4.1 Milestone

If not found in 4.0, create it:
`gh api repos/{owner}/{repo}/milestones -f title="<milestone_title>"`,
capturing **`.number`** from the POST response (e.g. `--jq .number`).
This is a **milestone number** — a numbering space separate from issue
numbers. It is what the PRD's `milestone:` frontmatter stores and what
every later PATCH targets; never confuse it with an issue number.

### 4.2 Commit and push docs BEFORE creating any issues

Issue bodies link to the docs via full
`https://github.com/<owner>/<repo>/blob/<default-branch>/...` URLs — those
links 404 unless the docs are on the default branch first. So, before the first
`gh issue create`:

1. `git switch main && git pull --ff-only origin main` (never commit on a
   stale main).
2. Commit the reviewed plan.yaml (and the PRD if its file changed), e.g.
   `docs(plans): add PLAN-NNN for $ARGUMENTS`.
3. `git push origin main`. If the push fails, stop and report — do not
   create issues against unpushed docs.

Skip the commit if the docs are already committed and pushed (resume
case, nothing staged) — but always verify main is synced and the plan
file is on the remote before proceeding.

### 4.3 Epic issue

If 4.0 found an existing `hive:managed` epic in the milestone, reuse its
number. Otherwise create it from the plan's `epic:` block:

```
gh issue create --title "<epic.title>" --body "<epic.body>" --milestone "<milestone_title>" --label hive:managed --type Epic
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
type, milestone, and label all match what was requested.

### 4.4 Task issues — topological order, immediate write-back

Compute a topological order of the plan's tasks from `depends_on`
(dependencies first, so every `--blocked-by` value references an
already-created issue number; the dag reviewer guaranteed the graph is
cycle-free). Then for each task in that order:

1. **Skip if already created**: if the task's `issue:` in plan.yaml is
   non-null, verify it still exists
   (`gh issue view <n> --json number,state,issueType,milestone,parent,labels,blockedBy`)
   and move on. If `issue:` is null but 4.0 found an existing
   `hive:managed` Task in the milestone with the identical title, adopt
   that number: verify it via `gh issue view --json`, write it back into
   plan.yaml, and move on — never create a duplicate.
2. Otherwise create it. The body is the task's `body:` verbatim — it
   already starts with the crosslinking header block and carries the
   task's `## Context`, `## Acceptance criteria`, and `## Verification`
   sections (verified in Step 1.3). Map the task's `depends_on` keys to
   the issue numbers already recorded in plan.yaml:

   ```
   gh issue create --title "<task.title>" --body "<task.body>" --milestone "<milestone_title>" --parent <epic#> --blocked-by <n1>,<n2> --label phase:build,hive:managed --type Task
   ```

   Omit `--blocked-by` entirely for tasks with no dependencies. If any
   `depends_on` key maps to a null `issue:`, the topological order is
   broken — abort and report rather than guessing.
3. Capture the number from URL stdout (strict single-match
   `/issues/<number>` parse, fail on zero/multiple) and verify with
   `gh issue view <n> --json number,title,issueType,milestone,parent,labels,blockedBy`
   that type, milestone, parent, labels, and blockedBy all match.
4. **Immediately Edit plan.yaml**, setting this task's `issue: <n>` —
   before creating the next issue, never batched at the end. This
   write-back is the resume record.

If any create or verify fails mid-loop, stop and report which tasks were
created; re-running `/hive:comb $ARGUMENTS` resumes here without duplicates.

### 4.5 Doc status write-backs

After **all** tasks have issue numbers:

1. plan.yaml: `status: materialized`.
2. PRD frontmatter: `milestone: <milestone-number>` (the number from 4.1,
   not an issue number), `epic_issue: <epic#>`, `status: planned`.

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
write-backs (plan.yaml issue numbers + status, PRD frontmatter), e.g.
`docs(plans): materialize PLAN-NNN into milestone <title>`, and
`git push origin main`.

## Final report

Print: the plan id and path, review iterations used, milestone title and
**milestone number**, epic issue number, a `task key → issue #` table in
creation order, and the follow-up command:
`/hive:swarm <milestone_title>`.
