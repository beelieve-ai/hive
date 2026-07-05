---
name: swarm
description: "Execute a PRD's materialized milestones to completion — dependency-ordered task execution with worker/guard loops, agentic merge-blocker resolution (parking unresolvable PRs under hive:parked instead of halting), squash-merged PRs, post-merge milestone verification, and epic/milestone closing. Invoke as /hive:swarm <PRD-id> (e.g. /hive:swarm PRD-003) to work every remaining phase strictly in order, or as /hive:swarm <milestone-title-or-number> (e.g. /hive:swarm smoke-test or /hive:swarm 3) to run a single milestone. Refuses to start a milestone unless its description contains the plan-review: passed marker."
disable-model-invocation: true
---

# /hive:swarm — execute a PRD's materialized milestones

You are the orchestrator. `$ARGUMENTS` is either a **PRD id** (`PRD-NNN` —
the primary form: execute everything left for that PRD, milestone by
milestone, strictly in phase order) or a milestone **title or number** (the
single-phase form). Either way you work through each milestone's task DAG
one issue at a time — worker implements, guard reviews, you open and
squash-merge the PR — until every task and the epic are closed and the
milestone itself is closed. Milestone execution is **strictly sequential**:
one milestone finishes (Step 5 closeout included) before the next begins —
never interleave. Load the **gh-conventions** skill for the exact `gh`
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
  close issues to force the loop forward (the sole exception is the two
  sanctioned `gh issue close` cases in Steps 3.3 and 3.8, which reconcile
  GitHub with an already-merged state). Every resolved PAUSE gets a
  `pause-resolved` entry (subject: the issue number, detail: the decision,
  `by: human`) in the PRD's audit log per the colony `Audit log` section —
  but **never append it mid-loop**: the working tree must stay clean
  between issues (Step 3.1) and on the worker's branch. Record the
  resolution in your running table and append all pending entries at
  Step 5; when a resolution ends the run instead, sync main, then append
  and commit the entries before stopping.

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
     entry still `planned` → an interrupted closeout: queue it for
     **Step 5 only** (write-back and closing, no work loop);
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
   not already recorded, and commit+push per Step 5 item 3 — no milestone
   steps run on this path.
4. Work the queue **strictly sequentially in list order**: for each
   milestone queued for execution, run Step 0.5, then Steps 1–5; an
   **interrupted-closeout** entry (queued for Step 5 only) skips straight
   to Step 5 — no gate, no work loop. Only after Step 5 finishes one
   milestone does the next enter the queue's front.

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
2. **Red-main override**: if milestone verification is currently red
   (Step 3.9a), the only selectable task is its open synthetic fix task —
   nothing else is worked or merged until main is green again.
3. If the ready set is **empty but open tasks remain** → this is the run's
   human gate. Report precisely: every `hive:parked` task with its PR URL
   and park reason, and every other open task with what blocks it (a
   parked dependency, a dependency cycle, an external blocker). Then
   **STOP**.
4. If open tasks remain, pick **unblocking-most-first**: the ready task
   with the highest `blocking` count (most other issues name it in their
   `blockedBy`). Tie-break by lowest issue number for determinism.
5. If **no open tasks remain**, go to Step 5 (termination).

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
3. If the merge **fails**: run the merge-blocker protocol (3.7a) — never
   mark progress manually, never close the issue yourself, never bypass
   the failure. Only park (3.7b) after the protocol is exhausted.

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
   classification, and the failure context. It rebases onto `origin/main`,
   resolves conflicts, fixes the failing checks, re-verifies, and pushes
   with `--force-with-lease`.
4. **Fast-forward local main** (`git switch main && git pull --ff-only
   origin main`) — the rebase absorbed new main-side commits, and guard's
   `git diff main...HEAD` against a stale local main would pollute the
   review with changes already merged.
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
the merge, close it explicitly: `gh issue close <n>`. This protects the
termination invariant (Step 5 fires only when every task is closed).

### 3.9 Sync main again

`git switch main && git pull --ff-only origin main` — mandatory after
every squash-merge, before anything else happens.

### 3.9a Milestone verification (when Step 0.5 recorded a command)

Run the recorded `milestone_verification.command` from the repo root on the
freshly synced main. Its exit code is the whole verdict — never interpret
output.

- **Green** → continue with 3.10.
- **Red** → main is broken; fix forward, never revert, never rewrite
  history:
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
     verification command passes on main — and `## Verification` — that
     same command. Capture and verify the number per gh-conventions.
  2. Post the 3.10 progress comment for `#<n>` first (it did merge), then
     return to Step 4. The Step 2 red-main override makes this fix task
     the only selectable work; it flows through the normal
     worker → guard → PR → merge → 3.9a path.
  3. If milestone verification is **still red after 2 synthetic fix tasks**
     for the same incident, **PAUSE** — main is broken and nothing else
     may merge, so this gate halts the run: present the failure output and
     both fix attempts to the user.

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

## Step 5 — Milestone closeout (all its tasks closed)

Runs once per milestone in the queue. Execute in exactly this order:

1. **Sync main**: `git switch main && git pull --ff-only origin main`.
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
3. Commit and push:
   `git add <prd-path> docs/audit/<PRD-id>-audit.md && git commit -m "docs(prd): mark <PRD-id> milestone <milestone-number> implemented" && git push origin main`
   (use `docs(prd): mark <PRD-id> implemented` when the PRD-level status
   flipped).
4. **Close the epic explicitly**: `gh issue close <epic#>`. This is
   load-bearing — the epic shares the milestone with the tasks and nothing
   auto-closes it, so without this step the milestone could never be
   emptied and the loop's termination promise would be broken.
5. **Close the milestone**:
   `gh api repos/{owner}/{repo}/milestones/<milestone-number> -X PATCH -f state=closed`.
6. **Advance the queue** (PRD mode): if candidates remain, proceed to the
   next milestone in list order per Step 0 item 4 (Step 0.5 then Step 1,
   or straight to Step 5 for an interrupted closeout). Otherwise — and
   always in single-milestone mode — final report.

## Final report

Report to the user, per milestone worked: the milestone and epic that were
closed and the running table of `issue# → 1-line summary` (every task,
including any recovered/skipped ones), plus any non-`hive:managed` issues
that were ignored, any interrupted closeouts that were finished, whether
milestone verification ran (and "legacy plan — no milestone verification",
with the reason, when Step 0.5 found none), and the PRD's resulting status
(`implemented`, or `planned` with the phases still remaining). (A run that
ends at Step 2.3 instead — parked tasks remaining — reports the same table
plus every parked PR with URL and reason; that report is the human gate. A
parked milestone never closes, so in PRD mode the queue does not advance
past it — later phases build on earlier ones.)

## Context discipline (binding throughout)

- Never run `git diff`, never Read implementation files, never inspect PR
  file contents — that detail belongs exclusively to worker and guard.
- Your only memory is the running `issue# → 1-line summary` table and the
  current state map; everything else is re-derivable from GitHub, which is
  what makes re-running /hive:swarm after any interruption safe.
