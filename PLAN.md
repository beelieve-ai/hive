# Plan: branch/PR-based artifact workflow for the Hive lifecycle

_Locked via grill — by Claude + Markus_

## Goal

Make branch/PR workflows a natural, first-class part of every Hive command that
writes lifecycle documents (PRDs, research, ADRs, plans, and their mechanical
write-backs), fixing issue #21 and generalizing beyond comb. There is **no
config knob**: one current-branch-aware rule makes both target workflows fall
out naturally — (a) each artifact on its own branch/PR merged to main, and
(b) all docs accumulating on one dedicated branch merged at the very end.
Direct pushes to main by Hive commands are eliminated entirely.

## Approach

1. **Centralize a "doc commit flow" in `skills/gh-conventions/SKILL.md`**
   (new section, referenced by all doc-writing skills), with two variants:
   - **Authored artifacts** (PRD, research doc, ADR, plan): if the session is
     on the default branch → create an artifact branch
     (`docs/<artifact-id>-<slug>`, e.g. `docs/PLAN-007-queue`), commit, push,
     open a PR to main. On a **doc-intended** non-default branch (one that
     already carries Hive doc commits, or one the user confirmed this
     session) → just commit there; merging is the user's business. On any
     **other** non-default branch (e.g. an `issue/N-*` worker branch or an
     unrelated feature branch) → one AskUserQuestion — "commit here / branch
     off main instead?" — asked once and remembered for the session, so
     lifecycle docs never silently mix into branches not meant for them.
     This flow is **doc-shaped, not the issue flow reused verbatim**: its own
     branch naming, a PR body linking the artifact (no `Closes #N` footer),
     and the existing merge-failure classification from `gh-conventions`
     reused as-is.
   - **Mechanical write-backs** (issue numbers into plan.yaml, status flips,
     audit-log entries): same branching rule, but the PR is **always
     auto-squash-merged immediately, no ask** — machine bookkeeping has
     nothing to review. Blocked merge → stop and hand the user the PR URL.
2. **Merge consent rides the existing gates — no new blanket rule.**
   Interactive commands (waggle, sting, forage, pollinate) pose the merge via
   AskUserQuestion — "merge now" (squash-merge + sync main) or "leave open
   for review"; comb's Approve gate covers its plan-PR merge (no second
   ask). Autonomous runs stay within the existing colony contract
   (`rules/colony.md` yolo carve-out): under bumble `--yolo`, artifacts
   created and approved within that run auto-squash-merge; headless runs
   **without** `--yolo` never auto-merge an authored artifact — they leave
   the PR open and report it, exactly as they never auto-approve. Swarm
   authors no artifacts, so only its (auto-merged) write-backs are affected.
   On "leave open", the session **stays on the artifact branch** so
   dependent commands stack on it.
3. **Dependencies work off the current checkout — no discovery machinery.**
   Commands read whatever branch is checked out. If a required doc exists only
   on an unmerged PR and the user is on main, the existing glob fails; the
   command reports it and points at a matching open artifact PR if one exists
   (best-effort title/path match, read-only lookup).
4. **Comb changes (`skills/comb/SKILL.md`)**:
   - The Step 3 **Approve gate covers the plan-PR merge**: on Approve, comb
     branches/PRs/auto-squash-merges the reviewed plan + audit log (replacing
     4.2's direct push), then proceeds to issue creation. No second ask.
   - Materialization (Step 4 issue creation) **still hard-requires docs on
     main** — the `blob/<default-branch>/` link scheme in `hive:crosslinking`
     is untouched. In the dedicated-branch workflow, comb pauses before
     Step 4 with instructions ("merge your branch, re-run /hive:comb to
     resume"); Step 0's resume detection gains this "docs not on main yet"
     state.
   - 4.7 (issue-number/status write-backs) uses the write-back variant
     (PR + auto-merge). The Step 3 Decline commit+push (comb SKILL.md ~:232)
     also auto-merges without an ask (declining already answered the only
     question), but it **introduces a newly allocated plan artifact**, so
     the ID-collision check applies to it like any authored-artifact PR.
   - **Step 0 resume learns about open artifact PRs**: before allocating a
     new PLAN id or declaring "no plan matches", comb scans open PRs whose
     head branch matches `docs/PLAN-*` (or whose diff touches
     `docs/plans/PLAN-*.yaml` for this PRD); a hit → report it and offer
     checkout/merge instead of minting a duplicate plan. Write-back
     verification ("on origin/main") likewise recognizes a pending
     auto-merge PR as the resumable state.
   - Normalize the hardcoded "blob/main" wording at comb SKILL.md ~:329 to
     the default-branch abstraction (doc consistency, no behavior change).
5. **Reroute every doc commit/push site** through the same flow:
   - `skills/waggle/SKILL.md` (~:288-302) — note: waggle currently commits
     **locally without pushing** ("comb pushes docs before materializing");
     the change here is inserting the artifact-PR flow at that commit point
     and dropping the defer-to-comb note, not replacing a push.
   - `skills/sting/SKILL.md` (~:186-193) — authored variant.
   - `skills/pollinate/SKILL.md` — draft commit (~:103-110) **and** the
     approval commit+push (~:128), authored variant.
   - `skills/forage/SKILL.md` — main commit (~:193-215) **and** the
     assumption-acceptance commit+push (~:245), authored variant.
   - `skills/swarm/SKILL.md` — milestone-complete status flip (~:438-456),
     pause-resolution commit (~:44), and PRD-mode reconciliation (~:89) —
     write-back variant (auto-merge).
6. **ID-collision check before any artifact-PR merge** (and on stacking
   branches at rebase/sync): IDs are minted by globbing the local checkout
   (pollinate :71, forage :134, waggle :156, comb :138), so two parallel
   branches can mint the same `ADR-0010` without a git conflict. Rule in the
   shared doc flow: immediately before merging **any PR that introduces a
   lifecycle artifact file** — authored or write-back-labelled alike (e.g.
   comb's Decline PR carries a new plan file) — fetch and re-glob the
   artifact directory on `origin/main`; on ID collision, renumber the
   branch's artifact (file + frontmatter + in-repo references) to the next
   free ID before merging. Allocation guidance stays local-glob (no new
   machinery at mint time).
7. **Update `rules/colony.md`** (source-of-truth conventions) with the doc
   commit flow rule and the merge-consent-rides-gates rule (extending the
   existing yolo carve-out section, not widening its scope).
8. **Version bump** in `.claude-plugin/plugin.json`: **MAJOR** — per this
   repo's own semver policy, replacing direct pushes with PR flows (new
   asks, PRs possibly left open, branch-aware commits) is observable
   behavior change to existing usage, not just an additive capability.
9. **Close issue #21** on merge, noting the generalized fix.

## Key decisions & tradeoffs

- **No config** — the checkout is the state. Rejected: a `.hive/config.yaml`
  docs-flow mode and branch-protection auto-detection (machinery the natural
  rule makes unnecessary).
- **Current-branch aware with a session-scoped guard**: on a doc-intended
  branch Hive just commits; on an unrecognized non-default branch it asks
  once per session before committing lifecycle docs there. The
  dedicated-branch workflow is simply "you checked out (and confirmed) a
  branch first". Rejected: a mandatory `docs/*` naming convention for
  dedicated branches (forces ceremony onto the natural flow).
- **Gate parity, bound to existing gates**: interactive = ask per authored
  PR (comb's Approve covers its plan PR); bumble `--yolo` = auto-merge only
  artifacts created and approved within that run (the existing colony
  carve-out, unwidened); headless without `--yolo` = leave the PR open and
  report, never auto-merge. Write-backs always auto-merge, never ask.
- **Docs-only reach for the dedicated branch**: materialization and build
  always require docs merged to main first, because issue bodies embed
  `blob/<default-branch>/` URLs. (Build branch targeting is governed by
  the Addendum.) Rejected: SHA-pinned or branch links (stale-snapshot
  links, unguaranteed after squash-merge; would also touch the
  crosslinking scheme).
- **Comb's Approve gate implies plan-PR merge consent** — the human just
  reviewed exactly that content; a second ask is ceremony.
- **Stay on the artifact branch after "leave open"** — switching to main
  would hide the artifact from the very next command.
- **Swarm task-issue PRs target a per-milestone integration branch** — see
  the Addendum below, which supersedes the earlier "main directly"
  decision (user reversal, re-grilled 2026-07-05).

## Assumptions to verify

1. The doc commit/push inventory in Approach step 5 (comb 4.2/4.7/Decline,
   sting, pollinate draft+approval, forage main+acceptance, swarm
   closeout/pause/reconciliation, waggle local commit) is now **complete** —
   no other skill/agent file commits or pushes lifecycle docs.
2. `skills/gh-conventions/SKILL.md` §"Branch / PR flow" (~:235-260) provides
   the merge/squash/sync-main mechanics and merge-failure classification the
   doc flow can reference. That existing section is issue-shaped
   (`issue/<n>-<slug>`, `Closes #<n>`) and must **not** be copied verbatim —
   the new doc flow defines its own branch naming, PR body, and has no
   `Closes` footer.
3. Comb Step 0's resume machinery can absorb both new states — "reviewed/
   approved but docs not yet on main" and "open plan/write-back PR pending"
   — without breaking existing resume rules.
4. ~~Superseded by the Addendum~~ — the worker/swarm task flow (one issue =
   one branch = one squash-merged PR, CI-gated) is retargeted from main to
   the per-milestone integration branch; see Addendum for the full delta.
5. The bumble `--yolo` carve-out (`rules/colony.md` ~:185, bumble SKILL.md
   ~:135) covers exactly ADR acceptance, plan approval, and
   research-assumption acceptance for artifacts created that run — the
   merge-consent rule extends those same gate events and nothing more.
6. The `blob/<default-branch>/` link requirement lives in
   `skills/crosslinking/SKILL.md`, `skills/gh-conventions/SKILL.md`, comb,
   `rules/colony.md`, and `agents/planner.md` (~:46) — planner needs no
   behavior change since the link scheme is untouched.
7. Waggle currently commits the PRD locally without pushing (deferring the
   push to comb); inserting the artifact-PR flow at that commit point is the
   only change it needs.

## Risks / open questions

- **Parallel artifact branches conflict on shared files**: two open artifact
  PRs both appending to the same PRD audit log (or frontmatter) will collide;
  the async freedom makes this reachable. Mitigation: accept and document —
  squash-merge conflicts surface at merge time and the second PR rebases;
  no locking machinery. ID collisions are handled separately by the
  pre-merge check (Approach step 6); the renumber path (file rename +
  reference relinking) is the most delicate part of that check.
- **Session-scoped branch confirmation is per-session state**: the "asked
  once, remembered" guard has no persistence across sessions; a new session
  on the same dedicated branch re-asks once. Accepted as the cost of no
  config.
- **`gh pr merge --squash --delete-branch` while checked out on the branch**
  being merged: post-merge sync steps must handle the branch deletion cleanly
  (switch to main first per existing convention).
- **Open-PR pointer matching** (step 3) is best-effort; a renamed PR title
  simply means no pointer, not a failure.

## Addendum — milestone-based build branching (re-grilled)

Supersedes the "main directly" swarm decision. The doc-flow work above is
already implemented (commit fc33e5f); this addendum changes only the build
phase (`/hive:swarm`, worker flow, gh-conventions issue flow, colony rules).

### Shape

`main → milestone/<n>-<slug> → issue/<n>-<slug> PRs → milestone branch →
one final PR → main`. Every issue remains its own CI-gated PR; the final
PR CI-tests the integrated milestone against current main.

### Settled decisions

1. **Swarm creates the branch at milestone start** — `milestone/<n>-<slug>`
   cut from fresh main. Comb stays documents-only; unbuilt milestones
   leave no branch.
2. **Task flow**: worker branches cut from the milestone branch; task PRs
   target it (`gh pr create --base milestone/<n>-<slug>`); squash-merge per
   task as today.
3. **Explicit issue close per task**: `Closes #N` does not fire on
   non-default-branch merges, so after each task PR merges, swarm runs
   `gh issue close <n>` (a new sanctioned close). The loop's closed-issue
   semantics (state map, dependency readiness, termination) are unchanged.
4. **Drift**: cut fresh, don't chase main mid-run; a BEHIND/CONFLICTING
   final PR is reconciled at the end (Machinery delta item 4).
5. **Final merge is a gate-parity ask**: swarm opens the milestone→main PR
   and asks "Merge now / Leave open for review" — including under
   `--yolo` (the carve-out covers doc gates, not code landing on main).
6. **Merge method: merge commit** (`gh pr merge --merge --delete-branch`) —
   main keeps the per-task squashed commits plus one merge commit; no
   milestone squash.
7. **Closeout only after the main merge**: PRD entry → `implemented`, epic
   close, milestone close, and the write-back PR fire only once the final
   PR is merged. "Leave open" ends the run with the closeout deferred; a
   re-run detects the merged PR and finishes.
8. **Verification placement**: `milestone_verification.command` runs on
   the milestone branch after every task merge, plus one final run on main
   after the final merge, before closeout.

### Machinery delta (what the shape change actually touches)

1. **The base branch becomes an explicit parameter everywhere it is
   hard-coded to main.** Worker briefings (`agents/worker.md` — "fresh
   main" in the description and Step 2, merge-fix rebase target in
   Step 5), swarm's worker/merge-fix briefings, and the gh-conventions /
   colony issue Branch/PR flow are parameterized: task branches cut from
   **fresh `<base>`** (`git switch <base> && git pull --ff-only origin
   <base>` — the sync-after-squash-merge rule applies to `<base>`, not
   main, during a milestone), task PRs `--base <base>`, merge-fix rounds
   rebase onto `origin/<base>`. During a milestone, `<base>` =
   `milestone/<n>-<slug>`.
2. **Guard diffs against the base**: the guard briefing's
   `git diff main...HEAD` becomes `git diff <base>...HEAD`, otherwise the
   guard re-reviews already-merged milestone work as part of each task.
3. **Milestone-branch durable-state probes** (swarm Step 0.5/1, resume):
   remote branch exists? (`git ls-remote --heads origin
   milestone/<n>-<slug>`) → reuse it, never re-cut; missing and no merged
   final PR → cut it fresh **only if no task PR has merged and no task
   issue is closed for this milestone** — otherwise the branch vanished
   with merged work on it: PAUSE as corrupted branch state, never recut
   an empty branch over closed tasks. Final-PR state:
   `gh pr list --head milestone/<n>-<slug> --base <default> --state all
   --json number,state,mergedAt` — merged → proceed to closeout (Step 5);
   open → re-pose the final-merge ask (or report and stop if declined
   again); closed-unmerged → PAUSE (a human closed the milestone PR —
   never re-open or re-create silently). Branch gone + PR merged is the
   normal post-merge state, not an error. Step 0's "all issues closed but
   entry still planned" candidate now routes through this final-PR probe
   **before** Step 5 — the epic/milestone are never closed while the
   final PR is unmerged.
4. **Final-PR blockers reuse the merge-fix machinery with `<base>` =
   main**: BEHIND/CONFLICTING or failing checks on the milestone→main PR
   get up to 2 merge-fix worker rounds, each briefed to merge
   `origin/main` into the milestone branch on a fix branch PR'd back into
   the milestone branch, guard-reviewed and verification-rerun like any
   task; exhausted retries or structurally unresolvable blockers are a
   **milestone-level PAUSE** (report the PR URL and the classified
   blocker, stop the run — the final PR has no task issue to label
   `hive:parked`, and phase advancement must block on it).
5. **Verification override renames**: the "red-main override" becomes a
   red-**base** override — a red milestone branch blocks further task
   merges and spawns the synthetic fix task cut from and PR'd into the
   milestone branch (acceptance: the command passes on the milestone
   branch). The **final** verification runs on main after the final merge;
   red there → PAUSE to the human (the final PR's CI already tested the
   integration — a red main here is exceptional, not fix-forward-able
   silently).
6. **Ground-rule updates in colony.md and gh-conventions**: the "never
   close issues manually" rule gains the third sanctioned close (per-task
   close after milestone-branch merge); the "closed-but-unmerged blocker"
   residual-risk wording is updated (auto-close no longer exists in the
   build loop — every close is explicit); the issue Branch/PR flow section
   documents the `<base>` parameter and the milestone-branch lifecycle.
7. **Version**: rides the unreleased 1.0.0 bump (same branch, nothing
   shipped between).

### Addendum risks

- A left-open final PR blocks the next phase in PRD mode (serial
  milestones) — accepted: that is the human gate doing its job.
- The branch-green invariant replaces the main-green invariant during a
  milestone; main is only proven green again at the final PR's CI, the
  post-merge verification run, and the doc-flow write-back PRs merging
  into it.
- Worker branch cleanup: task squash-merges delete `issue/*` branches as
  today; the milestone branch is deleted by the final merge.

## Out of scope

- Changing the issue-body link scheme (SHA-pinned or branch-relative URLs).
- Running materialization against a non-default branch (comb still requires
  docs on main before issue creation). Build-phase branch targeting is now
  governed by the Addendum (milestone integration branch).
- Any `.hive/` config surface or branch-protection auto-detection.
- Auto-discovering/merging open artifact PRs on behalf of the user.
- Mirroring per-task progress into docs (unchanged sync-point rules).
