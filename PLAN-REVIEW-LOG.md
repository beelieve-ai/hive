# Plan Review Log: branch/PR-based artifact workflow for the Hive lifecycle

Act 1 (grill) complete — plan locked with the user. MAX_ROUNDS=5.

## Round 1 — Codex

1. **ID-allocation breaks under parallel artifact branches.** IDs are minted by globbing the checkout (pollinate SKILL.md:71 PRD-*, forage :134 RES-*, waggle :156 ADR-*, comb :138 PLAN-*). Two branches off main can both mint ADR-0010; different slugs mean Git won't even conflict. Plan only flags audit-log conflicts — the smaller problem. Add a pre-merge ID-collision check (rename/relink before merge) or forbid concurrent ID-allocating branches.
2. **"Current branch = state" is too blunt.** "On a non-default branch, just commit there" silently mixes lifecycle docs into arbitrary branches (issue/... worker branches, plugin-work branches like the current `branch-pr-support`). Suggest: stack only on recognized doc/integration branches; ask/stop on arbitrary ones.
3. **Auto-merge rule conflicts with the bumble/yolo contract.** colony.md:185 scopes --yolo to ADR acceptance, plan approval, research-assumption acceptance for artifacts created that run; headless without --yolo never auto-approves (bumble SKILL.md:135 repeats it). A blanket "autonomous runs auto-merge authored PRs" overextends yolo. Bind merge consent to the existing gates instead.
4. **Waggle assumption is false.** waggle SKILL.md:288 commits locally; :302 explicitly says "Do not push — comb pushes docs before materializing." No direct push exists there; the plan is changing local-commit semantics, not replacing a push.
5. **Direct-push inventory incomplete.** Missed: pollinate approval commit+push (:128), forage assumption-acceptance commit+push (:245), comb Decline push (:232), swarm pause-resolution commit (:44) and PRD-mode reconciliation (:89).
6. **Comb resume not ready for "docs not on main".** Step 0 discovers plans by local glob and verifies write-backs on origin/main (:61, :86). Plan PR left open + rerun on main → comb doesn't see the reviewed plan and allocates a duplicate PLAN id. Open-PR detection must be part of comb's resume logic, not a nicety.
7. **gh-conventions Branch/PR flow is not reusable as-is.** It's issue-shaped: `issue/<n>-<slug>` branches, `Closes #<n>` footers (:235). Doc PRs need their own naming, body, and merge-failure behavior.
8. **Blob-link inventory misses agents/planner.md:46** (emits blob/<default-branch> URLs) and comb :329 hardcodes "blob/main" instead of the default-branch abstraction.
9. **Semver: MINOR questionable under repo policy.** CLAUDE.md calls behavior that breaks existing usage MAJOR; direct-push → PR flow with new asks is observable behavior change.

Better direction: keep the central doc-flow, tighten it — stack only on explicit doc branches, ID-collision checks before merge, comb resume detects open artifact/write-back PRs, bind bumble merge behavior to existing yolo gate rules.

VERDICT: REVISE

### Claude's response (Round 1)

Accepted 1, 3, 4, 5, 6, 7, 8, 9. Finding 2 changed a grill-settled decision, so it went to the user, who chose a middle path: session-scoped guard (doc-intended branches stack silently; unrecognized non-default branches get one ask per session; default branch → artifact PR).

- (1) Added Approach step 6: pre-merge ID-collision check against origin/main with renumber+relink before merge; allocation stays local-glob.
- (3) Replaced the blanket "autonomous auto-merge" with merge-consent-rides-existing-gates: --yolo covers only artifacts created+approved that run; headless without --yolo leaves PRs open and reports; swarm authors no artifacts.
- (4) Reworded waggle: local-commit semantics change (insert PR flow, drop defer-to-comb note), not a push replacement.
- (5) Inventory extended: pollinate :128, forage :245, comb Decline :232, swarm :44/:89.
- (6) Comb Step 0 gains open-PR detection (docs/PLAN-* head branches / plan-file diffs) before allocating a PLAN id; write-back verification recognizes a pending auto-merge PR.
- (7) Doc flow declared doc-shaped: own branch naming, PR body, no Closes footer; reuses only merge mechanics + failure classification.
- (8) planner.md added to the blob-link inventory (no behavior change); comb :329 "blob/main" wording normalized.
- (9) Semver: MAJOR.

Nothing rejected outright.

## Round 2 — Codex

Confirms all Round-1 findings addressed (ID collisions in scope, branch guard, yolo alignment, waggle wording, inventory, comb open-PR detection, doc-shaped flow, planner in blob inventory, MAJOR semver). Remaining:

1. **Material — comb Decline misclassified as a mechanical write-back.** Decline persists the reviewed plan.yaml (a newly allocated PLAN-NNN artifact) with the audit log (comb SKILL.md:232); the ID-collision check as written only covers "artifact-PR merges", so a Decline PR could auto-merge a colliding PLAN-007 without the renumber+relink guard. Fix: treat Decline as an authored artifact PR, or apply the collision check to any PR introducing lifecycle artifact files.
2. **Minor — wording slip in Assumption 2**: "it is issue-shaped as written" reads as describing the new doc flow instead of the existing gh-conventions section.

VERDICT: REVISE

### Claude's response (Round 2)

Accepted both. (1) Decline stays auto-merge (declining already answered the only question) but is now explicitly subject to the ID-collision check; the check itself is broadened to "any PR that introduces a lifecycle artifact file, authored or write-back-labelled alike". (2) Assumption 2 reworded — issue-shaped clearly refers to the existing gh-conventions section, with an explicit do-not-copy-verbatim warning.

## Round 3 — Codex

Both Round-2 blockers confirmed fixed: Decline is guarded by the lifecycle-artifact ID-collision check despite remaining auto-merge; Assumption 2 correctly scopes "issue-shaped" to the existing gh-conventions flow. No remaining material contradiction; leftover rough edges (renumber+relink delicacy, per-session branch confirmation) are explicitly called out as accepted risks.

VERDICT: APPROVED

## Act 1 reopened (2026-07-05) — milestone-based build branching

User reversed the "main directly" swarm decision after implementation (fc33e5f). Re-grill settled: explicit issue close per task (Closes #N doesn't fire off-default-branch); gate-parity ask on the final milestone→main PR (even under --yolo); merge commit, not squash; cut fresh from main and reconcile drift at the final PR via the existing merge-blocker protocol; swarm creates milestone/<n>-<slug> at milestone start; closeout only after the main merge (deferred-closeout on "leave open"). Verification: per-task on the milestone branch + final run on main (folded as conventional). PLAN.md gained an Addendum superseding the old decision.

## Round 4 — Codex (addendum review)

1. Plan internally contradictory: assumption 4 and Out-of-scope still assert task PRs target main.
2. Resume/idempotency underspecified: no probes for the milestone→main PR (open/merged/closed-unmerged); Step 5 could close epic/milestone while the final PR is open.
3. "Existing merge-blocker protocol" not reusable as stated: worker merge-fix rebases onto origin/main (worker.md:88, swarm:352); final-PR fixes have no defined actor, checkout, guard flow, or retry count.
4. Guard reviews `git diff main...HEAD` (swarm:300) — must diff against the milestone branch.
5. Worker hard-codes fresh main (worker.md:3, :29) — base must become an input.
6. Verification needs real state changes: red-main override (swarm:185), verification on synced main (:389), synthetic-fix acceptance "passes on main" (:398) all need milestone-branch equivalents plus a separate final main verification.
7. colony.md:303 "never close issues manually" and the :365 residual risk rely on auto-close — the new sanctioned per-task close must update these ground rules.
8. Milestone-branch lifecycle lacks durable-state probes (local/remote branch, final PR states, deleted-after-merge).

VERDICT: REVISE

### Claude's response (Round 4)

Accepted all eight — all implementation-spec gaps, none touching settled intent. (1) Assumption 4 and Out-of-scope rewritten to defer to the Addendum. (2)+(8) New "Machinery delta" item 3: remote-branch and final-PR probes (merged → closeout, open → re-pose ask, closed-unmerged → PAUSE), wired before Step 5. (3)+(5) Machinery delta 1+4: <base> becomes an explicit parameter in worker briefings, merge-fix rounds, and the Branch/PR flow; final-PR blockers = merge-fix rounds with base main, 2-round cap, guard + verification as tasks. (4) Guard diffs <base>...HEAD (delta 2). (6) Red-base override, synthetic fixes cut from/PR'd into the milestone branch, final main verification red → PAUSE (delta 5). (7) Ground-rule updates named as in-scope files (delta 6).

## Round 5 — Codex (final round, cap reached)

Confirms all Round-4 findings materially addressed (base parameterization, guard diff base, final-PR probes before closeout, red-base verification, sanctioned closes, colony/gh-conventions scope). Three narrow leftovers:
1. Stale main-target cue in the docs-only key decision ("worker PRs target main").
2. Recut rule unsafe: missing branch + no merged final PR → fresh cut could recreate an empty branch over already-merged, explicitly-closed task work.
3. "Park" undefined for final-PR blocker exhaustion — task parking labels a task issue; the final PR has none.

VERDICT: REVISE (cap reached → deadlock resolution)

### Claude's response (Round 5 / resolution)

Accepted all three and applied: (1) key decision reworded to defer build targeting to the Addendum; (2) recut conditioned on "no task PR merged AND no task issue closed", otherwise PAUSE as corrupted branch state; (3) final-PR exhaustion defined as a milestone-level PAUSE (report PR URL + classified blocker, stop; phase advancement blocks). Position: the plan is converged in substance — round 5's findings were fixes, not disagreements; presented to the user as deadlock-with-fixes for sign-off.
