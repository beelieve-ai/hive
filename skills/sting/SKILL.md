---
name: sting
description: "Grill any lifecycle artifact — PRD draft, research doc, ADR, plan.yaml, or design note — through a one-question-at-a-time interview with domain-modeling active, sharpening its language and content. Invoke as /hive:sting <doc-path-or-id>, e.g. `/hive:sting PRD-003`, `/hive:sting ADR-0007`, or `/hive:sting docs/notes/queue-design.md`. Doc edits only, each after explicit agreement; never materializes issues, never accepts ADRs."
disable-model-invocation: true
---

# /hive:sting — grill an artifact

Run a grilling session on an existing document to sharpen it. You (the
orchestrating session) conduct the whole interview yourself — no subagents
are dispatched by this command.

## Hard boundaries — read before anything else

`/hive:sting` produces **agreed document edits and glossary entries. Nothing
else.** Explicitly:

- **Never materializes issues** — no milestones, no epics, no task issues,
  no labels, no `gh` writes of any kind.
- **Never runs `/hive:comb` or `/hive:swarm` logic** — no planning, no reviewer
  dispatch, no DAG work, no build/review loop. If the session concludes the
  plan itself needs rework, say so and point at `/hive:comb`.
- **Never accepts ADRs** — acceptance is `/hive:waggle`'s human gate. `/hive:sting`
  never flips any artifact's `status:` frontmatter, in either direction.
- **Decisions are offered, not executed.** A decision surfaced by the
  interview that passes the ADR-worthiness test is **offered to the user as
  a `/hive:waggle` run** — never drafted, never decided here.
- **An accepted ADR is never edited.** If grilling shows an accepted
  decision should change, the only route is supersession via a new
  `/hive:waggle` run — offer that instead.
- **Sharpening a PRD never resets its approval gate** — an `approved` (or
  `planned`/`implemented`) PRD stays at its status — **and never re-runs
  genesis**: `/hive:sting` refines the existing document; it does not restart
  the `/hive:pollinate` interview or redraft the PRD from scratch.
- **Append-only artifact rules are honored**: doc IDs, requirement anchors
  (`### R<n>:`), and plan task keys are stable references — **sharpen
  wording, never renumber**, reorder-and-renumber, or reuse them.
- **Each edit is applied only after explicit agreement** in the interview.
  No agreement, no edit — silence, ambiguity, or enthusiasm is not
  agreement.

## 1. Resolve $ARGUMENTS to the target artifact

`$ARGUMENTS` is a single document reference — a file path or an artifact ID:

- **Empty** ⇒ ask the user which document to grill and stop until answered.
- **Path** (contains `/` or ends in `.md`/`.yaml`, and the file exists) ⇒
  use it directly. Any markdown/yaml document in the repo is fair game,
  including free-form design notes outside `docs/`.
- **ID** (matches `PRD-\d+`, `RES-\d+`, `ADR-\d+`, or `PLAN-\d+`,
  case-insensitive; zero-pad bare short numbers to the canonical width —
  three digits for PRD/RES/PLAN, four for ADR) ⇒ glob the matching
  directory per `crosslinking`: `docs/prd/PRD-NNN-*.md`,
  `docs/research/RES-NNN-*.md`, `docs/adr/ADR-NNNN-*.md`,
  `docs/plans/PLAN-NNN-*.yaml`. **Fail loudly on zero or multiple
  matches** — never guess.
- Anything else ⇒ fail loudly, stating what was tried.

## 2. Setup

1. **Load the `hive:grilling` and `hive:domain-modeling` skills now** (Skill
   tool) — they govern the entire session.
2. Load the authoring skill matching the artifact type, so its quality bar
   drives the questions: `hive:writing-prds` for a PRD, `hive:writing-adrs`
   for an ADR (its ADR-worthiness test is needed either way — load it always),
   `hive:research-method` for a RES doc, `hive:decomposition` for a plan. Load
   `hive:crosslinking` as well.
3. Read the target document in full. If root `CONTEXT.md` exists, read it
   and use only its canonical terms from the first question onward.
4. Determine the artifact's **mutation class** from the table in step 6
   *before* the first question, and tell the user upfront what kinds of
   edits this session can and cannot apply (e.g. for an accepted ADR: no
   edits at all — the session can only grill toward a superseding
   `/hive:waggle` run or other documents).

## 3. Build the grill list

Read the document critically and collect the weak spots to interview on:

- **Fuzzy or overloaded terms** — vague words, two words competing for one
  concept, terms not yet in `CONTEXT.md`.
- **Glossary conflicts** — usage that contradicts an existing `CONTEXT.md`
  entry or lands on an `Avoid:` list.
- **Untestable or non-binary acceptance criteria** (PRDs, plan task
  Verification sections) — anything a reviewer could not check
  mechanically.
- **Contradictions with the repository** — where the doc claims something
  the code or sibling docs disagree with. Explore with Read/Grep/Glob
  first; never ask the user what the codebase can answer.
- **Unprobed edge cases and internal contradictions** — statements that
  break under a concrete scenario.
- **Undeclared decisions** — places where the doc silently assumes an
  architecture choice that was never recorded.

Keep this as your private list of open branches, per `grilling`.

## 4. The interview

Run it exactly per the `grilling` skill. The load-bearing rules:

- **One question at a time — never a form.** Ask a single question via
  **AskUserQuestion** (one question per call, per `hive:grilling`), wait
  for the answer, then ask the next.
- **Every question ships a concrete recommended answer** — the first
  option, labelled `(Recommended)`, with the reason in its description —
  so the user can accept with a single click or push back.
- **Walk the branches one at a time** — drill until a branch is fully
  resolved, visibly close it, then move on. Never hop between
  half-resolved branches.
- **Codebase-answerable questions are explored, not asked** — state the
  finding as a confirmation instead.
- **Sharpen fuzzy terms the moment they appear.** Resolve each term per
  `domain-modeling` and write the glossary entry into root `CONTEXT.md`
  **inline, right then** — never batched for the end. Create `CONTEXT.md`
  lazily on the first resolved term (per the `CONTEXT-FORMAT.md` reference
  in the domain-modeling skill directory) if it does not exist yet. From
  then on use only the canonical term.

### Applying edits — the agreement loop

When a branch resolves into a change to the target document:

1. **Propose the concrete edit**: quote the current text and the exact
   replacement (or the addition and where it goes).
2. **Get explicit agreement via AskUserQuestion** — one call per edit:
   **"Apply this edit (Recommended)"** (why in the description),
   **"Revise the wording"**, **"Skip it"**. Only an Apply selection is
   agreement to *that* edit. A counter-proposal (via Other or Revise)
   reopens the branch; agreement to the general idea is not agreement to
   the wording.
3. **Apply the edit immediately** after agreement (Edit tool), before
   moving to the next branch — never batch agreed edits for the end, so an
   interrupted session still leaves a consistent document.
4. Respect the mutation class (step 6) — if the agreed change is outside
   what this artifact may receive, say so and route it (e.g. to `/hive:waggle`
   or `/hive:comb`) instead of applying it.

## 5. Decisions surfaced by the interview

When a resolved branch turns out to be an **architecture decision** rather
than a wording fix, apply the three-leg **ADR-worthiness test** from
`writing-adrs`: hard to reverse ∧ surprising without context ∧ a real
trade-off.

- **Passes** ⇒ add it to a running list of `/hive:waggle` candidates. **Offer**
  it at wrap-up as a `/hive:waggle <PRD-id> <topic>` run for the user to invoke —
  never draft the ADR, never spawn an architect, never decide it here.
- **Fails** ⇒ no ADR ceremony; if the target (or governing) document is a
  PRD, offer a one-line rationale for its Open Questions section as a
  normal agreed edit.

## 6. Per-artifact mutation rules

| Artifact | What `/hive:sting` may edit (after agreement) | Never |
|---|---|---|
| PRD (any status) | Wording, acceptance criteria, Goals/Non-Goals, Open Questions; new requirements at the **next free** `R<n>`; a dropped requirement becomes a "Withdrawn: <reason>" body under its kept heading | Flip `status:`; renumber/reuse `R<n>` anchors; touch `milestone:`/`epic_issue:`; redraft from scratch |
| RES doc | Wording of questions/findings; sharpen evidence phrasing | Flip `status:`; invent findings the evidence does not carry |
| ADR `proposed` | Freely editable per `writing-adrs` — context, drivers, options, wording | Flip `status:` (acceptance belongs to `/hive:waggle`) |
| ADR `accepted` / `superseded` | **Nothing.** Offer a superseding `/hive:waggle` run instead | Any edit at all |
| plan.yaml `draft`/`reviewed` | Task titles, body context blocks, Verification wording | Task keys, `depends_on`, task split/merge/reorder — structural change is `/hive:comb`'s job (and would invalidate `review: passed`); flip `status:`/`review:` |
| plan.yaml `materialized` | Same wording-only scope, **with a warning**: docs are intent, issues are execution — the edit will *not* propagate to the already-created GitHub issues | `issue:` numbers, task keys, structure, status |
| Free-form design note | Anything, after agreement | — |

If the PRD's status is `planned` or `implemented`, also warn that
sharpened requirements do not retro-sync into existing issues (docs =
intent; issues sync only at `/hive:comb` materialization and `/hive:swarm`
completion).

## 7. Wrap-up

The session ends when the open-branch list is empty or the user calls it.
Play back a compact summary in canonical glossary terms: every edit
applied, every glossary entry written, every branch left open. If the
play-back surfaces a mismatch, reopen that branch and grill on.

## 8. Commit

If any file changed, commit **the target document together with
`CONTEXT.md`** when the session touched it — the vocabulary and the
artifact whose grilling resolved it share one commit (per
`domain-modeling`). Sync local main first per the `gh-conventions` skill
(`git switch main && git pull --ff-only origin main` before any commit on
main). Conventional commit, e.g.:

```
docs(prd): sharpen PRD-003 via sting session
```

Then push (`git push origin main`). If no edits were agreed, there is
nothing to commit — say so.

## 9. Report

End with: the document path and what changed (per edit, one line), new or
revised `CONTEXT.md` entries, the offered `/hive:waggle` candidates (exact
suggested invocations), and any proposed edits the user declined.
