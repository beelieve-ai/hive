---
name: swarm
description: "Execute a PRD's materialized milestones to completion — dependency-ordered task execution on a per-milestone integration branch (task PRs squash-merge into milestone/<n>-<slug>; one final gate-asked merge-commit PR lands the milestone on main), with worker/guard loops, agentic merge-blocker resolution (parking unresolvable PRs under hive:parked instead of halting), post-merge milestone verification, and epic/milestone closing. Invoke as /hive:swarm <PRD-id> (e.g. /hive:swarm PRD-003) to work every remaining phase strictly in order, or as /hive:swarm <milestone-title-or-number> (e.g. /hive:swarm smoke-test or /hive:swarm 3) to run a single milestone. Refuses to start a milestone unless its description contains the plan-review: passed marker."
disable-model-invocation: true
---

# /hive:swarm — execute a PRD's materialized milestones

You are the orchestrator. `$ARGUMENTS` is either a **PRD id** (`PRD-NNN` —
the primary form: execute everything left for that PRD, milestone by
milestone, strictly in phase order) or a milestone **title or number** (the
single-phase form). Either way you work through each milestone's task DAG
one issue at a time — worker implements, guard reviews, you open and
squash-merge the PR — until every task is closed, then land the milestone
on main via one final PR (Step 4.5) and close the epic and milestone.
**Each milestone builds on its own integration branch**
`milestone/<milestone-number>-<slug>` (**`<base>`** everywhere below), cut
from fresh main at milestone start: task branches cut from `<base>`, task
PRs target `<base>`, and main only changes at the final merge-commit PR.
Milestone execution is **strictly sequential**: one milestone finishes
(Step 5 closeout included) before the next begins — never interleave. Load the **gh-conventions** skill for the exact `gh`
command syntax before running any `gh` command; the ordering, gates, and
write-back timing below are load-bearing and stated inline.

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
  close issues to force the loop forward (the sole exceptions are the
  sanctioned `gh issue close` cases in Steps 3.3, 3.7, and 3.8, which
  reconcile GitHub with an already-merged state — `Closes #N` does not
  auto-close on merges into a non-default branch, so the post-merge close
  in 3.7 is the normal path, not a repair). Every resolved PAUSE gets a
  `pause-resolved` entry (subject: the issue number, detail: the decision,
  `by: human`) in the PRD's audit log per the colony `Audit log` section —
  but **never append it mid-loop**: the working tree must stay clean
  between issues (Step 3.1) and on the worker's branch. Record the
  resolution in your running table and append all pending entries at
  Step 5; when a resolution ends the run instead, sync main, then append
  and commit the entries via the doc commit flow's write-back variant
  (PR + auto-squash-merge, per `hive:gh-conventions`) before stopping.

## Step 0 — Resolve the argument to a milestone queue

**Mode detection**: `$ARGUMENTS` matching `PRD-\d+` (case-insensitive,
whole token) → **PRD mode**; normalize it to the canonical `<PRD-id>`
first — uppercase `PRD`, number zero-padded to three digits (`prd-3` →
`PRD-003`) — and use that normalized id for every lookup below (globs are
case- and padding-sensitive). Anything else → **single-milestone mode**
(title or number — the full legacy surface, and the "run just this one
phase" override).

In both modes, reading a PRD's phases means its `milestones:` frontmatter
list (schema in `hive:writing-prds`) — the authoritative PRD→milestone
link. **Legacy frontmatter**: singular non-null `milestone:`/`epic_issue:`
fields are read as a one-entry list (its `plan:` resolved by grepping
`docs/plans/PLAN-*.yaml` for `prd: <PRD-id>`; its `status:` mirroring the
PRD status) and rewritten to list form at the Step 5 write-back.

### PRD mode

1. Glob `docs/prd/<PRD-id>-*.md` (the normalized id) — exactly one match,
   else abort with the candidates found. Read its `milestones:` list.
   Empty (and no legacy fields) → error: nothing is materialized for this
   PRD; run `/hive:comb <PRD-id>` first.
2. **Candidate selection is status-first**: take every entry with
   `status != implemented`, **in list order** (list order = phase order =
   execution order). For each, validate against GitHub (milestone lookup
   by number per `gh-conventions`):
   - milestone **open with open `hive:managed` issues** → execute it
     (queue it);
   - milestone open (or closed) with **all its issues closed** but the
     entry still `planned` → an interrupted finalization: queue it for
     **Step 0.5 + Step 1 + Steps 4.5 + 5** (setup and epic discovery still
     run — they bind `<base>`, the verification command, and `epic#` — but
     the work loop, Steps 2–4, is skipped; the epic/milestone are never
     closed while the final PR is unmerged);
   - milestone **closed or missing while open issues remain / entry says
     planned with no explanation** → frontmatter↔GitHub drift: **fail
     loudly** with what disagrees, and stop. Never guess, never
     auto-repair drift.
3. Zero candidates → every phase is implemented: report the PRD as
   complete and stop. If the PRD `status:` is somehow not yet
   `implemented`, reconcile the doc first — sync main, derive the status
   per `hive:writing-prds` (here: all entries implemented → set
   `status: implemented`), append the `prd-implemented` audit entry
   (subject: the PRD id, detail: `plans: <every PLAN-NNN in the list>`) if
   not already recorded, and commit per Step 5 item 3 (write-back variant)
   — no milestone steps run on this path.
4. Work the queue **strictly sequentially in list order**: for each
   milestone queued for execution, run Step 0.5, then Steps 1–5; an
   **interrupted-finalization** entry still runs Step 0.5 and Step 1
   (binding `<base>`, the verification command, and `epic#`), then skips
   the work loop (Steps 2–4) straight to Step 4.5. Only after Step 5
   finishes one milestone does the next enter the queue's front. A
   milestone whose final PR is deliberately left open (Step 4.5) blocks
   the queue — later phases build on earlier ones.

### Single-milestone mode

1. Resolve `$ARGUMENTS` via
   `gh api "repos/{owner}/{repo}/milestones?state=all" --paginate` and
   match locally against `.title` (exact) or `.number`. Fail loudly on
   zero or multiple matches. Capture both the **milestone number** (used
   for every PATCH) and the **title** (used by `gh issue list --milestone`).
2. Resolve the owning PRD: read `docs/prd/*.md` frontmatter and find the
   PRD whose `milestones:` list contains an entry with
   `milestone: <milestone-number>` (a legacy singular `milestone:` field
   matches too). Exactly one match is expected — record its path and the
   matching entry (needed for the Step 5 status sync). On zero or multiple
   matches, report the anomaly and stop.
3. **Out-of-order guard**: if an **earlier** entry in that PRD's list is
   not yet `implemented`, warn — name the earlier milestone and its open
   issue count — and confirm via **AskUserQuestion** before proceeding
   (later phases usually build on earlier ones). PRD mode cannot get out
   of order; this guard exists only here.
4. The queue is this single milestone; run Step 0.5, then Steps 1–5.

### Step 0.5 — Per-milestone gate and setup (both modes)

1. **Deterministic gate**: the milestone `.description` must contain the
   literal marker `plan-review: passed`. If it does not, **REFUSE to start
   that milestone** — report that it has no passed plan review (run
   /hive:comb first) and stop. Never proceed on a missing marker, never ask
   the user to waive this gate.
2. **Resolve the milestone verification command**: capture the `PLAN-NNN`
   id from the marker line (`plan-review: passed (PLAN-NNN)`), glob
   `docs/plans/PLAN-NNN-*.yaml`, and read its
   `milestone_verification.command`. The glob must match **exactly one**
   file. Record the command (per milestone — a fresh resolve each time the
   queue advances). An older marker without a plan id, a missing plan
   file, multiple matching plan files (ambiguous — never guess which
   command to run), or a plan without the field →
   **no milestone verification for this milestone** (note it, and the
   reason, in the final report) — never fail the run over it.
3. **Ensure the parked label exists** (legacy milestones were materialized
   before it; idempotent): `gh label create hive:parked --force`.
4. **Milestone integration branch** — the working name is
   `milestone/<milestone-number>-<slug>` (slug from the milestone title
   like issue slugs: lowercase, non-alphanumerics → hyphens, collapse
   repeats, trim), but the milestone **number**, never the drift-prone
   slug, is the identity in every probe below. Probe durable state in
   order:
   1. **Remote branch exists**
      (`git ls-remote --heads origin "milestone/<milestone-number>-*"`) →
      **adopt its actual ref name as `<base>`** (read it from the
      `ls-remote` output; never re-derive from the current milestone
      title, which may have been edited since the cut, yielding a name
      that does not exist on the remote). More than one match → PAUSE
      (ambiguous milestone branch). Reuse it, never re-cut: fetch and
      create/update the local tracking branch.
   2. **No remote branch** → probe the final PR by number prefix (robust
      to slug drift and to gh's 30-item default):
      `gh pr list --base <default-branch> --state all --limit 1000 --json number,state,mergedAt,headRefName`,
      filtered for `headRefName` starting `milestone/<milestone-number>-`.
      A **merged** match → the milestone is already on main: capture its
      `headRefName` as `<base>` and its number, and treat this as an
      interrupted finalization (Step 4.5 item 1 confirms merged and routes
      to Step 5). A **closed-unmerged** match → PAUSE (a human closed the
      milestone PR — never re-open or re-create silently).
   3. **No remote branch, no final PR** → safe to cut fresh **only if no
      task issue of this milestone is closed and no task PR has merged**
      (probe: `gh issue list --milestone "<title>" --state closed --json
      number,labels` must return no `hive:managed` tasks, and
      `gh pr list --state merged --limit 1000 --json headRefName` filtered
      for this milestone's `issue/<n>-` heads must be empty); otherwise the
      branch vanished with merged work on it → **PAUSE as corrupted branch
      state**, never recut an empty branch over closed tasks. When safe,
      first delete any leftover local `<base>` from an interrupted prior
      cut (`git branch -D <base>` if it exists — safe: the probes just
      established no merged work is on it), then cut fresh:
      `git switch main && git pull --ff-only origin main &&
      git switch -c <base> && git push -u origin <base>`.
   Every later "sync" in Steps 3–4 targets `<base>`; main is touched again
   only at Step 4.5.

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
   label AND are epics per the mode-agnostic test (`issueType.name ==
   "Epic"` OR label `type:epic` — label mode covers user-owned repos, where native
   issue types don't exist and `issueType` is null). There must be
   **exactly one** — abort with a report on zero matches (milestone not
   materialized by /hive:comb?) or multiple matches (corrupted milestone).
   Capture its number as `epic#`.
3. **Task set** = issues with the `hive:managed` label AND
   `parent.number == epic#` AND the mode-agnostic task test
   (`issueType.name == "Task"` OR label `type:task`). If any
   `hive:managed` issue in the milestone is neither the epic nor parented
   to it (an orphaned managed task), **abort** with a report — never work
   an inconsistent DAG. Issues without `hive:managed` are not yours;
   ignore them (note their existence in the final report).
4. The **epic is excluded** from the ready set and from the
   unblocking-most counts — it is bookkeeping, not work.

## Step 2 — Ready set and selection

1. **Ready set** = open tasks whose `blockedBy` entries are **all closed**,
   resolved from the same state map, **excluding tasks labeled
   `hive:parked`**. A `blockedBy` entry that does not appear in the map
   counts as an external blocker — that task is not ready. (Residual risk,
   accepted per colony rules: a closed-but-unmerged blocker is trusted as
   done.) Parked exclusion is the single gate that keeps a parked task's
   open PR from ever being auto-merged on resume — unparking is a human
   act: resolve and remove the label (or merge the PR) and re-run
   /hive:swarm.
2. **Red-base override**: if milestone verification is currently red
   (Step 3.9a), the only selectable task is its open synthetic fix task —
   nothing else is worked or merged until the milestone branch is green
   again.
3. If the ready set is **empty but open tasks remain** → this is the run's
   human gate. Report precisely: every `hive:parked` task with its PR URL
   and park reason, and every other open task with what blocks it (a
   parked dependency, a dependency cycle, an external blocker). Then
   **STOP**.
4. If open tasks remain, pick **unblocking-most-first**: the ready task
   with the highest `blocking` count (most other issues name it in their
   `blockedBy`). Tie-break by lowest issue number for determinism.
5. If **no open tasks remain**, go to Step 4.5 (final merge), then Step 5.

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

## Step 3 — Work one issue

Let `<n>` be the selected issue number. Execute these sub-steps in order.

### 3.1 Assert clean working tree

`git status --porcelain` must be empty — the previous worker was required
to leave it clean. If it is dirty, **stop and report** what is dirty; never
stash, clean, or commit stray state yourself.

### 3.2 Sync the base

```bash
git switch <base> && git pull --ff-only origin <base>
```

Always — the local base is stale after every squash-merge, and the worker
must branch from a fresh tree.

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
**base branch** `<base>`, the
**full issue body**, and the resolved **PRD/ADR file paths**.
The worker creates that branch from the fresh `<base>` you prepared,
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
   guard reviews the working tree's `git diff <base>...HEAD` (diffing
   against main would re-review already-merged milestone work as part of
   this task).
2. Spawn the **guard** agent (Agent tool, subagent_type `hive:guard`) with:
   the issue number, the **base branch** `<base>` (its diff target), the full
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

### 3.7 PR create, squash-merge, explicit close

1. From the issue branch:
   `gh pr create --fill --base <base> --body "Closes #<n>"` —
   capture stdout; strict `/pull/<number>` parse (fail on zero or multiple
   matches); verify via
   `gh pr view <pr#> --json number,state,headRefName,baseRefName`
   (baseRefName must be `<base>`).
   (On the resume path from 3.3 an open PR already exists — skip creation
   and use its captured number instead.)
2. `gh pr merge <pr#> --squash --delete-branch` — always target the PR by
   its explicit number, never rely on branch context (on resume you may be
   on `<base>` with no local issue branch). **If the merge fails**, run the
   merge-blocker protocol (3.7a) — never mark progress manually, never
   close the issue yourself, never bypass the failure; only park (3.7b)
   after the protocol is exhausted. **Do not proceed to item 3 until the
   merge has actually succeeded** (the close there must never fire on an
   unmerged PR).
3. **Only after the merge succeeds, close the issue explicitly**:
   `gh issue close <n>` — the `Closes #<n>`
   body links the PR but does **not** auto-close on a merge into a
   non-default branch. This close is sanctioned: the work is merged,
   reviewed, and CI-gated at this point, and the loop's dependency
   readiness keys off closed issues.

### 3.7a Merge-blocker protocol (max 2 fix attempts)

1. **Classify** per the gh-conventions `Merge failures` section
   (`gh pr view <pr#> --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup`):
   - *Pending checks* → poll (~60s interval, 10-minute budget), then
     re-classify. Not settled within budget → park with reason "checks did
     not settle". An empty rollup is green, not pending.
   - *Structurally unresolvable* (approval required, protection rule with
     green checks, permission error, draft) or *unknown after one re-poll*
     → park immediately — worker rounds cannot fix policy.
   - *Agent-fixable* (conflicts, stale base, failed checks) → continue.
2. **Collect failure context** for the briefing: for failed GitHub Actions
   checks, `gh run view <run-id> --log-failed`; for other checks, the
   details URL; if no log is retrievable, tell the worker to re-run the
   task's Verification command and diagnose from that. (Passing logs
   through verbatim is not "reading diffs" — implementation detail still
   stays in the worker's context.)
3. **Merge-fix round**: spawn the **worker** on the same branch in
   merge-fix mode with: the issue number, the exact branch name, the
   **base branch** `<base>`, the
   classification, and the failure context. It rebases onto
   `origin/<base>`,
   resolves conflicts, fixes the failing checks, re-verifies, and pushes
   with `--force-with-lease`.
4. **Fast-forward the local base** (`git switch <base> && git pull
   --ff-only origin <base>`) — the rebase absorbed new base-side commits,
   and guard's `git diff <base>...HEAD` against a stale local base would
   pollute the review with changes already merged.
5. **Guard always re-reviews**: run the full 3.6 guard review loop on the
   rebased branch (same inputs, same max 2 fix rounds). If that loop ends
   unresolved, park (3.7b) instead of pausing.
6. **Retry the merge** (3.7 item 2). If it fails again, re-enter this
   protocol; after **2 merge-fix attempts** for this PR (regardless of
   whether the second blocker is new), park.

### 3.7b Park the task (the human gate, without halting the swarm)

1. `gh issue edit <n> --add-label hive:parked`.
2. Comment the PR with the gate summary:
   `gh pr comment <pr#> --body "hive:parked — <classification>; attempted: <what each fix round did>; blocked because: <why it still fails>"`.
3. Record `issue# → parked (<reason>, <PR URL>)` in your running table.
4. **Return to Step 4** — the swarm continues with independent tasks;
   dependents of the parked issue stay blocked naturally via `blockedBy`,
   and Step 2 excludes parked tasks from selection. Do not pause.

### 3.8 Verify the issue actually closed

`gh issue view <n> --json state` — if it is somehow **still open** after
3.7 item 3, close it explicitly: `gh issue close <n>`. This protects the
termination invariant (Step 4.5 fires only when every task is closed).

### 3.9 Sync the base again

`git switch <base> && git pull --ff-only origin <base>` — mandatory after
every squash-merge, before anything else happens.

### 3.9a Milestone verification (when Step 0.5 recorded a command)

Run the recorded `milestone_verification.command` from the repo root on the
freshly synced `<base>`. Its exit code is the whole verdict — never
interpret output.

- **Green** → continue with 3.10.
- **Red** → the milestone branch is broken; fix forward, never revert,
  never rewrite history:
  1. Create a **synthetic fix task issue** with the exact conventions comb
     uses at materialization (gh-conventions `Create a task`): assigned to
     the milestone, `--parent <epic#>`, labels `phase:build,hive:managed`
     plus the mode's task type, **no `--blocked-by`**. Title:
     `fix: milestone verification failure after #<n>`. Body: the
     crosslinking header block (**PRD:** the Step 0 PRD ·
     **Implements:** the requirement id(s) from `#<n>`'s own header block —
     the fix restores their verified state · **ADR:** —), `## Context` with the
     failing command, its output, and the merge that preceded it
     (issue `#<n>`, PR `#<pr#>`), `## Acceptance criteria` — the milestone
     verification command passes on the milestone branch — and
     `## Verification` — that
     same command. Capture and verify the number per gh-conventions.
  2. Post the 3.10 progress comment for `#<n>` first (it did merge), then
     return to Step 4. The Step 2 red-base override makes this fix task
     the only selectable work; it flows through the normal
     worker → guard → PR → merge → 3.9a path (cut from and merged into
     `<base>` like any task).
  3. If milestone verification is **still red after 2 synthetic fix tasks**
     for the same incident, **PAUSE** — the milestone branch is broken and
     nothing else may merge, so this gate halts the run: present the
     failure output and both fix attempts to the user.

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

## Step 4.5 — Final merge to main (all tasks closed; gate-parity)

The milestone lands on main through **one final PR** — a **merge commit**,
so main keeps the per-task squashed commits. Never squash the milestone,
never push `<base>` onto main directly.

1. **Probe the final PR's durable state**:
   `gh pr list --head <base> --base <default-branch> --state all --json number,state,mergedAt`.
   - **Merged** → the milestone is on main; go to item 5 (final
     verification) and then Step 5.
   - **Closed-unmerged** → PAUSE (a human closed the milestone PR — never
     re-open or re-create silently).
   - **Open** → continue with item 3 (re-pose the gate).
   - **None** → create it (item 2).
2. **Create the final PR**: sync `<base>` (Step 3.9), then
   `gh pr create --base <default-branch> --head <base> --title "milestone: <milestone title>" --body "Milestone <title> (epic #<epic#>) — <k> tasks. plan: PLAN-NNN"`
   — capture stdout, strict `/pull/<number>` parse, verify via
   `gh pr view <pr#> --json number,state,baseRefName,headRefName`. No
   `Closes` footers — the epic and tasks are closed explicitly.
3. **Mergeability**: classify per the gh-conventions `Merge failures`
   section (poll pending checks — this PR's CI is the integration test
   against current main).
   - **Agent-fixable** (BEHIND, conflicts, failed checks) → up to **2
     integration-merge rounds**. Spawn the **worker** in
     **integration-merge mode** (`agents/worker.md`) on `<base>` itself —
     not a fix branch, not an issue branch — with the classification, the
     failure context, and the milestone verification command. It merges
     `origin/main` into `<base>` (a merge commit — **never** a rebase; this
     both preserves the per-task commits and makes main an ancestor, so a
     BEHIND blocker actually clears), resolves conflicts, fixes failing
     checks, re-runs milestone verification on `<base>`, and pushes
     `<base>`. There is **no guard review and no issue** here — the
     integration has no acceptance criteria of its own; milestone
     verification (re-run on the branch now, and again on main at item 5)
     is its check. After the worker returns, sync `<base>` (Step 3.9) and
     re-probe this PR.
   - **Structurally unresolvable** blockers, or still blocked after 2
     rounds → **milestone-level PAUSE**: report the PR URL and the
     classified blocker and stop the run — there is no task issue to park,
     and phase advancement must block on this PR.
4. **The gate** (even under `/hive:bumble --yolo` — the carve-out covers
   doc gates, not code landing on main): ask via **AskUserQuestion** —
   **"Merge now (Recommended)"** (description: what lands — milestone
   title, task count, merge-commit method) or **"Leave open for
   review"**. Merge now →
   `gh pr merge <pr#> --merge --delete-branch`. **If that merge command
   fails** (main advanced between the item-3 check and the approval),
   re-enter item 3 to re-classify and integration-merge, then return to
   this gate. Leave open → report the
   PR URL and **end the run** with closeout deferred; a re-run detects
   the merged PR (item 1) and finishes. **Any headless run — with or
   without `--yolo`, since this gate is never yolo-delegated** — cannot
   pose the ask, so it leaves the PR open and reports it, never merges.
5. **Sync main and final-verify**:
   `git switch main && git pull --ff-only origin main`; when Step 0.5
   recorded a verification command, run it once on main. **Red → PAUSE**
   (the final PR's CI already tested this integration — a red main here
   is exceptional; present the output, do not fix forward silently).
   Green (or no command) → Step 5.

## Step 5 — Milestone closeout (final PR merged)

Runs once per milestone in the queue, **only after Step 4.5 confirms the
final PR is merged**. Execute in exactly this order:

1. **Sync main**: `git switch main && git pull --ff-only origin main`
   (already done by 4.5 item 5 — re-assert, it is cheap).
2. Edit the PRD (path from Step 0): flip **this milestone's**
   `milestones:` entry to `status: implemented` (rewriting legacy singular
   `milestone:`/`epic_issue:` fields to list form if still present —
   append-only, never reorder). Then derive the PRD `status:` per
   `hive:writing-prds`: **every** entry `implemented` and the list
   non-empty → `status: implemented`; otherwise it stays `planned`. This
   is one of the two sanctioned doc↔issue sync points (the other is
   /hive:comb materialization). Append to the PRD's audit log — creating
   the file if absent (colony `Audit log` section):
   - `milestone-implemented` (subject: the entry's PLAN-NNN, detail:
     `prd: <PRD-id>; milestone: <milestone-number>`);
   - one `pause-resolved` entry per resolution recorded in your running
     table for this milestone;
   - **only if** the derived status flipped to implemented:
     `prd-implemented` (subject: the PRD id, detail:
     `plans: <every PLAN-NNN in the list>`).
3. Commit via the doc commit flow's **write-back variant**
   (`hive:gh-conventions`): doc branch off fresh main, then
   `git add <prd-path> docs/audit/<PRD-id>-audit.md && git commit -m "docs(prd): mark <PRD-id> milestone <milestone-number> implemented"`
   (use `docs(prd): mark <PRD-id> implemented` when the PRD-level status
   flipped), push, PR, auto-squash-merge with no ask, sync main. A blocked
   merge → stop and report the PR URL.
4. **Close the epic explicitly**: `gh issue close <epic#>`. This is
   load-bearing — the epic shares the milestone with the tasks and nothing
   auto-closes it, so without this step the milestone could never be
   emptied and the loop's termination promise would be broken.
5. **Close the milestone**:
   `gh api repos/{owner}/{repo}/milestones/<milestone-number> -X PATCH -f state=closed`.
6. **Advance the queue** (PRD mode): if candidates remain, proceed to the
   next milestone in list order per Step 0 item 4 (Step 0.5 then Step 1,
   then the work loop — or, for an interrupted finalization, Step 0.5 and
   Step 1 then straight to Step 4.5). Otherwise —
   and always in single-milestone mode — final report.

## Final report

Report to the user, per milestone worked: the milestone and epic that were
closed, the final milestone→main PR (number and state — merged, or left
open for review), and the running table of `issue# → 1-line summary`
(every task, including any recovered/skipped ones), plus any
non-`hive:managed` issues
that were ignored, any interrupted finalizations that were finished, whether
milestone verification ran (and "legacy plan — no milestone verification",
with the reason, when Step 0.5 found none), and the PRD's resulting status
(`implemented`, or `planned` with the phases still remaining). (A run that
ends at Step 2.3 instead — parked tasks remaining — reports the same table
plus every parked PR with URL and reason; that report is the human gate. A
parked milestone never closes, and a final PR left open defers the
closeout, so in PRD mode the queue does not advance past either — later
phases build on earlier ones.)

## Context discipline (binding throughout)

- Never run `git diff`, never Read implementation files, never inspect PR
  file contents — that detail belongs exclusively to worker and guard.
- Your only memory is the running `issue# → 1-line summary` table and the
  current state map; everything else is re-derivable from GitHub, which is
  what makes re-running /hive:swarm after any interruption safe.
