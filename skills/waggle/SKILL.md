---
name: waggle
description: Drive architecture decisions for a PRD into MADR 4.0 ADRs — worthiness-test candidates, spawn one architect per passing decision, present options, and record human acceptance. Invoke as /hive:waggle <PRD-id> [topic], e.g. `/hive:waggle PRD-003` or `/hive:waggle PRD-003 queue backend` to focus on one topic.
disable-model-invocation: true
---

# /hive:waggle — architecture decisions for a PRD

You are the orchestrator. Read the `hive:writing-adrs` and `hive:crosslinking` skills
before doing anything else — the ADR-worthiness test, the MADR 4.0 quality
bar, ID allocation, and the append-only status lifecycle defined there govern
this whole command. If root `CONTEXT.md` exists, read it and use its
canonical vocabulary throughout.

Human gates are mandatory here: **never set `status: accepted` without the
user's explicit acceptance in this conversation.** No exceptions, no
"the recommendation is obvious", no batching acceptances the user did not
individually give.

## 1. Resolve $ARGUMENTS

`$ARGUMENTS` is `<PRD-id> [topic]`:

- The **first whitespace-separated token** is the PRD id — accept `PRD-NNN`
  or a bare number `NNN` (zero-pad to three digits).
- **Everything after it** (if anything) is a free-text *topic* that narrows
  which decisions this run considers. No topic ⇒ consider all architecture
  decisions the PRD raises.

Resolve the PRD file by globbing `docs/prd/PRD-NNN-*.md`. Fail loudly on
zero or multiple matches — never guess. If `$ARGUMENTS` is empty, ask the
user which PRD to run against and stop until answered.

Read the PRD. If its `status:` is `draft`, warn the user that ADRs normally
follow PRD approval and ask whether to proceed; continue only on their yes.

## 2. Gather inputs

- From the PRD frontmatter `research:` list, resolve each RES id to its file
  under `docs/research/RES-NNN-*.md` and read the ones whose `status:` is
  `answered` (warn about, but do not read conclusions from, unanswered ones).
- From the PRD frontmatter `adrs:` list, read any existing ADRs — they are
  prior decisions; a new run may **supersede** them but never re-open them
  by editing.
- Glob `docs/adr/ADR-*.md` once now to know the existing ADR set.

## 3. Identify candidate decisions

From the PRD (requirements, Open Questions, body) and the accepted research
findings, list the candidate architecture decisions — each phrased as a
neutral question ("How do we persist X?", "Which protocol between A and B?").
If a topic was given, keep only candidates matching it, but **mention** any
obviously ADR-worthy candidates outside the topic so the user knows they
exist for a later run.

If a candidate would change what an existing **accepted** ADR decided, it is
a **supersede candidate**: it still goes through the full flow below, and you
must note which ADR it would supersede.

## 4. ADR-worthiness test — the gate before any drafting

Apply the three-leg test from `writing-adrs` to **every** candidate:
hard to reverse ∧ surprising without context ∧ a real trade-off. All three
legs must pass; any leg failing means **no ADR** for that candidate.

Failed candidates never vanish silently: for each one, append a one-line
rationale to the PRD — into its **Open Questions** section (or body where it
fits better), e.g. "Retry library choice: not ADR-worthy (trivially
reversible); picked tenacity." Edit the PRD file now; this edit is part of
this run's commit.

If **no** candidate passes, report that (with the recorded rationales),
commit the PRD edit per step 8, and stop — a run that writes zero ADRs is a
valid outcome.

## 5. Allocate IDs and spawn architects

Allocate one `ADR-NNNN` id per passing candidate **up front**: glob
`docs/adr/ADR-*.md`, take max + 1, four digits, then assign consecutive
numbers. (Architects may run in parallel — if each globbed for itself they
would collide; the orchestrator owns allocation.)

Spawn **one `hive:architect` agent per passing decision** with the Agent tool.
Independent decisions are spawned **in parallel in one message**; decisions
that depend on each other's outcome run sequentially, feeding the earlier
draft's path/content into the later prompt. Each architect prompt must
contain:

- the assigned `ADR-NNNN` id (tell it to use exactly this id),
- the decision to be made, phrased as the question from step 3,
- the PRD path,
- the accepted-research doc paths from step 2,
- any existing ADR paths that bear on the decision — and for a supersede
  candidate, the superseded ADR's path plus the instruction to set
  `supersedes: ADR-NNNN` in frontmatter and explain in Context what changed.

The architect returns the complete ADR document (frontmatter + MADR body)
followed by a short recommendation note. It has no Write tool — persisting
is your job.

## 6. Persist the drafts

For each returned draft, before writing:

- Verify the frontmatter carries the assigned id, `derived-from:` the PRD
  id, and **`status: proposed`** — if the draft says anything else (even
  `accepted`), force it to `proposed`.
- Verify all MADR sections from the `hive:writing-adrs` **Template** are present with
  ≥ 2 real options; if the draft is structurally incomplete, re-invoke that
  architect once with the specific gap named. Still incomplete ⇒ report the
  failure to the user and drop that candidate from this run (do not write a
  broken ADR).

Write each verified draft to `docs/adr/ADR-NNNN-<slug>.md` (slug: short,
lowercase, hyphenated, from the decision topic). Do **not** touch the PRD's
`adrs:` list yet — that happens only on acceptance.

## 7. Present and gate — per decision, never in bulk

For **each** ADR, one at a time: show the user the considered options with
their honest pros/cons, the architect's recommendation, and the file path.
Then ask for an explicit verdict. Possible outcomes:

- **Accept** — the user explicitly accepts the chosen option. Only then:
  1. Flip the ADR's frontmatter to `status: accepted`.
  2. Append its id to the PRD's `adrs:` frontmatter list (bare id, no link).
  3. If it supersedes an older ADR: flip the old ADR's `status:` to
     `superseded` and add a forward link to the successor — per
     `writing-adrs`, these are the **only** edits ever permitted on an
     accepted ADR.
- **Accept a different option** — while `status: proposed` the doc is
  editable: update the Decision Outcome (and consequences) to the user's
  chosen option, show the revised text, then on their confirmation proceed
  as Accept.
- **Reject / defer** — leave the file at `status: proposed` (its id stays
  retired either way — ids are never reused), and record a one-line note in
  the PRD's Open Questions that the decision is drafted but undecided
  (`ADR-NNNN proposed, pending`).

An accepted ADR is final. If the user later changes their mind, the answer
is a **new** `/hive:waggle` run that supersedes it — never an edit.

## 8. Commit

Sync main first per the `gh-conventions` skill (`git switch main && git pull
--ff-only origin main`) — never commit on a stale main. Then commit all of
this run's doc changes together: new ADR files, the PRD frontmatter/Open
Questions edits, and any `superseded` flips. Conventional commit, e.g.:

```
docs(adr): add ADR-0007 queue backend for PRD-003
```

Do not push issues, create issues, or touch anything under `.github` — this
command produces documents only. (`/hive:comb` pushes docs before materializing.)

## 9. Report

End with a short summary: accepted ADRs (id + chosen option), proposed-but-
undecided ADRs, worthiness-rejected candidates with where their rationale
was recorded, and any superseded ADRs. Suggest `/hive:comb <PRD-id>` as the next
step when the PRD's decision surface is covered.
