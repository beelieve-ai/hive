---
name: swarm
description: "Work an already-materialized milestone to completion — dependency-ordered task execution with worker/guard loops, squash-merged PRs, and epic/milestone closing. Invoke explicitly as /hive:swarm <milestone-title-or-number> (e.g. /hive:swarm smoke-test or /hive:swarm 3). Refuses to start unless the milestone description contains the plan-review: passed marker."
disable-model-invocation: true
---

# /hive:swarm — execute a materialized milestone

You are the orchestrator. `$ARGUMENTS` is a milestone **title or number**.
You work through the milestone's task DAG one issue at a time — worker
implements, guard reviews, you open and squash-merge the PR — until every
task and the epic are closed and the milestone itself is closed. Load the
**gh-conventions** skill for the exact `gh` command syntax before running
any `gh` command; the ordering, gates, and write-back timing below are
load-bearing and stated inline.

Ground rules that bind every step:

- All `gh` reads use `--json`. The new PR number comes from the sanctioned
  URL-stdout exception: strict `/pull/<number>` parse of the `gh pr create`
  stdout (fail on zero or multiple matches) followed by a
  `gh pr view <n> --json number,state,headRefName` verify.
- Guard verdicts are parsed **only** from the FIRST fenced ```json block of
  the reply; a missing or unparseable block counts as **fail**, never pass.
- You **never read code or diffs yourself** — all implementation and review
  detail stays in the worker and guard subagent contexts. You keep only a
  running table of `issue# → 1-line summary`.
- All durable state lives in GitHub. /hive:swarm is **idempotent**: after an
  interruption or context compaction, re-running it resumes cleanly from
  the state map (Step 1) plus the per-issue resume-safety checks (Step 3.3).
- Pauses are real: when a step says PAUSE, stop and put the decision to the
  user with **AskUserQuestion** — state the situation (PR URL, findings,
  blocker), offer the concrete ways forward as options with your
  recommendation first (`(Recommended)`, reason in the description), and let
  "Other" catch what you didn't foresee. Never mark progress manually, never
  close issues to force the loop forward (the sole exception is the two
  sanctioned `gh issue close` cases in Steps 3.3 and 3.8, which reconcile
  GitHub with an already-merged state).

## Step 0 — Resolve the milestone and check the gate

1. Resolve `$ARGUMENTS` via
   `gh api "repos/{owner}/{repo}/milestones?state=all" --paginate` and
   match locally against `.title` (exact) or `.number`. Fail loudly on
   zero or multiple matches. Capture both the **milestone number** (used
   for every PATCH) and the **title** (used by `gh issue list --milestone`).
2. **Deterministic gate**: the milestone `.description` must contain the
   literal marker `plan-review: passed`. If it does not, **REFUSE to
   start** — report that the milestone has no passed plan review (run
   /hive:comb first) and stop. Never proceed on a missing marker, never ask
   the user to waive this gate.
3. Resolve the PRD: grep `docs/prd/*.md` frontmatter for
   `milestone: <milestone-number>`. Exactly one match is expected —
   record its path (needed for the Step 5 status sync). On zero or
   multiple matches, report the anomaly and stop.

## Step 1 — Build the state map and discover the epic

1. **ONE call** builds the entire state map:

   ```bash
   gh issue list --milestone "<title>" --state all --limit 1000 --json number,title,state,blockedBy,blocking,parent,issueType,labels
   ```

   The explicit `--limit 1000` is load-bearing: without it `gh issue list`
   returns at most 30 issues (newest first), silently truncating larger
   milestones — the epic (created first, so truncated first) would vanish
   and every downstream step would trust an incomplete map. If the call
   ever returns exactly as many issues as the limit, assume truncation:
   raise the limit and re-run until the returned count is below it.

2. **Discover the epic**: filter for issues that carry the `hive:managed`
   label AND are epics per the mode-agnostic test (`issueType == "Epic"`
   OR label `type:epic` — label mode covers user-owned repos, where native
   issue types don't exist and `issueType` is null). There must be
   **exactly one** — abort with a report on zero matches (milestone not
   materialized by /hive:comb?) or multiple matches (corrupted milestone).
   Capture its number as `epic#`.
3. **Task set** = issues with the `hive:managed` label AND
   `parent.number == epic#` AND the mode-agnostic task test
   (`issueType == "Task"` OR label `type:task`). If any
   `hive:managed` issue in the milestone is neither the epic nor parented
   to it (an orphaned managed task), **abort** with a report — never work
   an inconsistent DAG. Issues without `hive:managed` are not yours;
   ignore them (note their existence in the final report).
4. The **epic is excluded** from the ready set and from the
   unblocking-most counts — it is bookkeeping, not work.

## Step 2 — Ready set and selection

1. **Ready set** = open tasks whose `blockedBy` entries are **all closed**,
   resolved from the same state map. A `blockedBy` entry that does not
   appear in the map counts as an external blocker — that task is not
   ready. (Residual risk, accepted per colony rules: a closed-but-unmerged
   blocker is trusted as done.)
2. If the ready set is **empty but open tasks remain** → report the
   blockage precisely (which open tasks are blocked by what — likely a
   dependency cycle or an external blocker) and **STOP**.
3. If open tasks remain, pick **unblocking-most-first**: the ready task
   with the highest `blocking` count (most other issues name it in their
   `blockedBy`). Tie-break by lowest issue number for determinism.
4. If **no open tasks remain**, go to Step 5 (termination).

## Step 3 — Work one issue

Let `<n>` be the selected issue number. Execute these sub-steps in order.

### 3.1 Assert clean working tree

`git status --porcelain` must be empty — the previous worker was required
to leave it clean. If it is dirty, **stop and report** what is dirty; never
stash, clean, or commit stray state yourself.

### 3.2 Sync main

```bash
git switch main && git pull --ff-only origin main
```

Always — local main is stale after every squash-merge, and the worker must
branch from a fresh tree.

### 3.3 Resume-safety check (never collide)

Probe all three places prior work could live. The branch is
`issue/<n>-<slug>`; derive the slug deterministically from the issue
title (lowercase, non-alphanumerics → hyphens, collapse repeats, trim)
and pass that exact branch name to the worker in 3.4. Probe by pattern:

1. Remote branch: `git ls-remote --heads origin "issue/<n>-*"`
2. Local branch: `git branch --list "issue/<n>-*"`
3. PR — probe UNCONDITIONALLY, never gated on a branch existing (a
   squash-merge with `--delete-branch` removes the branch, so the
   merged-PR-but-open-issue case has no branch to find):
   `gh pr list --state all --json number,state,headRefName`, filtered
   for heads matching `issue/<n>-`.

Decide from the findings — resume or skip, **never re-implement over
existing work**:

- **No branch, no PR** → fresh task; continue with 3.4.
- **Branch exists, no PR** → the worker was interrupted. If the local
  branch is missing, fetch it (`git fetch origin <branch>` and create the
  local tracking branch). Spawn the worker in **resume mode** (3.4) —
  explicitly telling it the branch already exists, to switch to it,
  complete the work, verify, commit, and push — then continue with 3.5.
- **Open PR exists** → guard already passed (PRs are only created after a
  pass) and the merge was interrupted. Skip to 3.7 (merge) with that PR.
- **Merged PR but the issue is somehow still open** → the work is done;
  `gh issue close <n>`, record `issue# → closed (recovered: PR already
  merged)`, and return to Step 4. **Never re-implement.**
- **Closed-but-unmerged PR** → ambiguous human intervention; PAUSE and ask
  the user how to proceed.

### 3.4 Spawn the worker

Fetch the full issue body: `gh issue view <n> --json title,body`. From the
body's header block (`**PRD:** ... · **Implements:** ... · **ADR:** ...`)
extract the PRD id and any ADR ids, and resolve them to local paths by
globbing `docs/prd/<PRD-id>-*.md` and `docs/adr/<ADR-id>-*.md`.

Spawn the **worker** agent (Agent tool, subagent_type `hive:worker`) with
exactly: the issue number `<n>`, the **exact branch name** `issue/<n>-<slug>` derived in 3.3, the
**full issue body**, and the resolved **PRD/ADR file paths**.
The worker creates that branch from the fresh main you prepared,
implements, runs the issue's Verification command until green, commits
(Conventional Commits), and pushes the branch. It creates no PR and never
merges. It returns a summary of at most 3 lines — record it in your
running table. If the worker reports a conflict or an unpassable
verification instead, PAUSE and surface that to the user.

### 3.5 Flip the phase label

```bash
gh issue edit <n> --remove-label phase:build --add-label phase:review
```

Cosmetic UI state only — resume and ready logic **never** key off labels,
so a missed or duplicate flip is harmless; do it anyway for visibility.

### 3.6 Guard review loop (max 2 fix rounds)

1. Ensure the worker's branch is checked out (`git switch <branch>`) —
   guard reviews the working tree's `git diff main...HEAD`.
2. Spawn the **guard** agent (Agent tool, subagent_type `hive:guard`) with:
   the issue number, the full
   issue body (acceptance criteria + Verification command), and the linked
   PRD/ADR paths. Guard reviews the diff against the acceptance criteria
   and ADR constraints and runs the Verification command.
3. Parse the verdict from the **FIRST fenced ```json block** of guard's
   reply against `{"verdict":"pass|fail","findings":[{"task","issue","fix"}]}`.
   Missing or unparseable block = **fail**, never pass.
4. **On fail**: send the findings back to the **worker** on the **same
   branch** (fix-round mode — worker switches to the existing branch,
   addresses every finding, re-verifies, commits, pushes), then re-run
   guard from step 2. **Max 2 fix rounds**; if guard still fails after the
   second fix round, **PAUSE** — present the outstanding findings to the
   user and ask how to proceed. Never merge a failing branch.
5. **On pass**: continue with 3.7.

### 3.7 PR create, squash-merge

1. From the issue branch: `gh pr create --fill --body "Closes #<n>"` —
   capture stdout; strict `/pull/<number>` parse (fail on zero or multiple
   matches); verify via `gh pr view <pr#> --json number,state,headRefName`.
   (On the resume path from 3.3 an open PR already exists — skip creation
   and use its captured number instead.)
2. `gh pr merge <pr#> --squash --delete-branch` — always target the PR by
   its explicit number, never rely on branch context (on resume you may be
   on `main` with no local issue branch). Auto-closes the issue via the
   `Closes #<n>` body.
3. If the merge **fails** (branch protection, required checks, conflicts):
   **PAUSE with the PR URL** — never mark progress manually, never close
   the issue yourself, never bypass the failure.

### 3.8 Verify the issue actually closed

`gh issue view <n> --json state` — if it is somehow **still open** after
the merge, close it explicitly: `gh issue close <n>`. This protects the
termination invariant (Step 5 fires only when every task is closed).

### 3.9 Sync main again

`git switch main && git pull --ff-only origin main` — mandatory after
every squash-merge, before anything else happens.

### 3.10 Progress comment on the epic

Post exactly one line:

```bash
gh issue comment <epic#> --body "#<n> <title> — merged via PR #<pr#>: <1-line summary>"
```

Add the same line to your running `issue# → 1-line summary` table.

## Step 4 — Loop

**Recompute the state map from scratch** (repeat Step 1's single
`gh issue list` call — never trust cached state) and return to Step 2.
Repeat until no open tasks remain.

## Step 5 — Termination (all tasks closed)

Execute in exactly this order:

1. **Sync main**: `git switch main && git pull --ff-only origin main`.
2. Edit the PRD (path from Step 0.3): set frontmatter
   `status: implemented`. This is one of the two sanctioned doc↔issue sync
   points (the other is /hive:comb materialization).
3. Commit and push:
   `git add <prd-path> && git commit -m "docs(prd): mark <PRD-id> implemented" && git push origin main`.
4. **Close the epic explicitly**: `gh issue close <epic#>`. This is
   load-bearing — the epic shares the milestone with the tasks and nothing
   auto-closes it, so without this step the milestone could never be
   emptied and the loop's termination promise would be broken.
5. **Close the milestone**:
   `gh api repos/{owner}/{repo}/milestones/<milestone-number> -X PATCH -f state=closed`.
6. **Final report** to the user: the milestone and epic that were closed,
   the running table of `issue# → 1-line summary` (every task, including
   any recovered/skipped ones), any non-`hive:managed` issues that were
   ignored, and the PRD now marked `status: implemented`.

## Context discipline (binding throughout)

- Never run `git diff`, never Read implementation files, never inspect PR
  file contents — that detail belongs exclusively to worker and guard.
- Your only memory is the running `issue# → 1-line summary` table and the
  current state map; everything else is re-derivable from GitHub, which is
  what makes re-running /hive:swarm after any interruption safe.
