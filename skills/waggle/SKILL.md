---
name: waggle
description: Drive architecture decisions into MADR 4.0 ADRs — worthiness-test candidates, spawn one architect per passing decision, present options, and record human acceptance. Invoke as /hive:waggle <PRD-id> [topic] for a PRD's decisions (e.g. `/hive:waggle PRD-003` or `/hive:waggle PRD-003 queue backend`), or /hive:waggle --standalone <topic> for a cross-cutting repo-scoped platform decision with no parent PRD (e.g. `/hive:waggle --standalone CI provider`).
disable-model-invocation: true
---

# /hive:waggle — architecture decisions for a PRD (or standalone)

You are the orchestrator. Read the `hive:writing-adrs` and `hive:crosslinking` skills
before doing anything else — the ADR-worthiness test, the MADR 4.0 quality
bar, ID allocation, and the append-only status lifecycle defined there govern
this whole command. If root `CONTEXT.md` exists, read it and use its
canonical vocabulary throughout.

Human gates are mandatory here: **never set `status: accepted` without the
user's explicit acceptance in this conversation.** No exceptions, no
"the recommendation is obvious", no batching acceptances the user did not
individually give — with one delegated exception: under a
`/hive:bumble --yolo` run, the acceptance verdict for ADRs drafted in that
run was delegated at invocation per the colony carve-out — the recommended
option is recorded as accepted without posing the question; pre-existing
proposed ADRs still gate normally.

## 1. Resolve $ARGUMENTS

`$ARGUMENTS` is `<PRD-id> [topic]` or `--standalone <topic>`:

- If the **first whitespace-separated token** is `--standalone`, this is a
  **standalone run**: a repo-scoped platform decision (`scope: repo`,
  no parent PRD). Everything after the flag is the *topic* — required; if
  missing, ask for it via **AskUserQuestion** (offer plausible
  platform-decision topics from repo signals as options, "Other" for
  free text). The flag is mandatory for PRD-less runs — a bare topic is
  indistinguishable from a mistyped PRD id and must fail the PRD glob
  below, never be silently reinterpreted.
- Otherwise the first token is the PRD id — accept `PRD-NNN` or a bare
  number `NNN` (zero-pad to three digits).
- **Everything after it** (if anything) is a free-text *topic* that narrows
  which decisions this run considers. No topic ⇒ consider all architecture
  decisions the PRD raises.

For a PRD run, resolve the PRD file by globbing `docs/prd/PRD-NNN-*.md`.
Fail loudly on zero or multiple matches — never guess. If `$ARGUMENTS` is
empty, ask which PRD to run against via **AskUserQuestion**: glob
`docs/prd/PRD-*.md` and offer the found PRDs as options (id + title,
approved ones first), "Other" for anything else. Stop until answered.

Read the PRD. If its `status:` is `draft`, put the decision via
**AskUserQuestion**: warn that ADRs normally follow PRD approval, options
**"Stop — approve the PRD first (Recommended)"** and **"Proceed on the
draft anyway"**. Continue only on an explicit Proceed selection.

(Standalone runs skip all PRD resolution — there is no PRD.)

## 2. Gather inputs

- PRD run only: from the PRD frontmatter `research:` list, resolve each RES
  id to its file under `docs/research/RES-NNN-*.md` and read the ones whose
  `status:` is `answered` (warn about, but do not read conclusions from,
  unanswered ones).
- PRD run only: from the PRD frontmatter `adrs:` list, read any existing
  ADRs — they are prior decisions; a new run may **supersede** them but
  never re-open them by editing.
- **Every run**: glob `docs/adr/ADR-*.md` once now to know the existing ADR
  set, and read **in full** every ADR whose frontmatter says
  `scope: repo` and `status: accepted` — repo-scoped decisions are not on
  any PRD's `adrs:` list, and supersede detection only works against
  decisions actually read.

## 3. Identify candidate decisions

**PRD run — resume check before mining.** Before mining new candidates,
glob `docs/adr/ADR-*.md` for docs with `status: proposed` and
`derived-from:` equal to this PRD. For any such draft that does **not**
carry a settlement note in the PRD's Open Questions (an `ADR-NNNN
proposed, pending` line), the prior run was interrupted between persisting
the draft and gating it: resume that ADR's step-7 acceptance gate first,
before any new drafting — never allocate a fresh id for a decision an
existing proposed draft already covers.

Also repair the Accept-path crash window: any `status: accepted` ADR with
`derived-from:` this PRD whose id is missing from the PRD's `adrs:`
frontmatter list means a prior run was interrupted mid-Accept — append the
id now and re-run the remaining step-7 Accept bookkeeping (supersede flip,
bedrock digest sync, audit-log append) for it; all of it is idempotent.

PRD run: from the PRD (requirements, Open Questions, body) and the accepted
research findings, list the candidate architecture decisions — each phrased
as a neutral question ("How do we persist X?", "Which protocol between A
and B?"). If a topic was given, keep only candidates matching it, but
**mention** any obviously ADR-worthy candidates outside the topic so the
user knows they exist for a later run.

Candidates already **settled** are skipped — never re-derived, re-tested,
or re-drafted. Settled means: covered by an existing **accepted** ADR;
carrying an `ADR-NNNN proposed, pending` note (an explicit human
Reject/defer verdict already given — never re-ask it); or carrying a
worthiness-rejection rationale line in the PRD. This keeps re-runs
idempotent: no duplicate ADR ids, no duplicate rationale lines.

Standalone run: the candidates are the decision(s) the topic names, phrased
the same way — this mode drafts what the user asked for; it does not mine a
document for adjacent candidates (there is none to mine). If the topic
plainly bundles several separable decisions, list them individually.

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
this run's commit. In a standalone run there is no PRD: append the
rationale line to `docs/adr/DECISIONS.md` instead (create it on first use —
an append-only log of worthiness-rejected and deferred standalone
candidates).

If **no** candidate passes, report that (with the recorded rationales),
commit the PRD or `DECISIONS.md` edit per step 8, and stop — a run that
writes zero ADRs is a valid outcome.

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
- the PRD path — or, in a standalone run, the statement that this is a
  repo-scoped platform decision (`scope: repo`, `derived-from: null`) with
  the topic as stated, so the architect derives decision drivers from repo
  conventions, existing accepted ADRs, and the decision context itself
  instead of PRD requirements,
- the accepted-research doc paths from step 2 (PRD runs),
- any existing ADR paths that bear on the decision — and for a supersede
  candidate, the superseded ADR's path plus the instruction to set
  `supersedes: ADR-NNNN` in frontmatter and explain in Context what changed.

The architect returns the complete ADR document (frontmatter + MADR body)
followed by a short recommendation note. It has no Write tool — persisting
is your job.

## 6. Persist the drafts

For each returned draft, before writing:

- Verify the frontmatter carries the assigned id and **`status: proposed`**
  — if the draft says anything else (even `accepted`), force it to
  `proposed`. PRD run: `scope: prd` (or absent — prd is the default) and
  `derived-from:` the PRD id. Standalone run: `scope: repo` and
  `derived-from: null`.
- Verify all MADR sections from the `hive:writing-adrs` **Template** are present with
  ≥ 2 real options; if the draft is structurally incomplete, re-invoke that
  architect once with the specific gap named. Still incomplete ⇒ report the
  failure to the user and drop that candidate from this run (do not write a
  broken ADR). The `## Domain context` section counts as present in its
  one-line skip form (`No domain impact: <reason>.`) — that is valid, not
  incomplete; a missing or empty Domain context section is a gap.
- Verify **provenance**: every web-sourced claim in option prose carries an
  inline tag + confidence in the pinned format
  (`[VERIFIED: <source>, confidence: <RATING>]` /
  `[CITED: <url>, confidence: <RATING>]` / `[ASSUMED, confidence: LOW]`,
  where `<RATING>` is `HIGH`/`MEDIUM`/`LOW` at or below the tag's
  `research-method` ceiling), the
  `## Assumptions` section is present (`None.` is valid), and every inline
  `[ASSUMED]` claim has a matching Assumptions bullet. Gaps are handled
  exactly like structural incompleteness above: one re-invoke with the gap
  named, then report-and-drop.

Write each verified draft to `docs/adr/ADR-NNNN-<slug>.md` (slug: short,
lowercase, hyphenated, from the decision topic). Do **not** touch the PRD's
`adrs:` list yet — that happens only on acceptance.

## 7. Present and gate — per decision, never in bulk

For **each** ADR, one at a time: show the user the considered options with
their honest pros/cons, the architect's recommendation, the file path, and —
explicitly called out — the draft's `## Assumptions` entries, so acceptance
happens with every unverified claim in view. A resumed pre-existing
`status: proposed` ADR with no `## Assumptions` section predates the
provenance discipline: flag it as "no provenance block present (pre-0.7.0
draft)" and let the human decide — never re-draft it for that reason alone.
Then ask for the verdict with **AskUserQuestion** — one call per ADR, never
batched: first option **"Accept <chosen option> (Recommended)"** with the
architect's one-line justification in the description, then one option per
considered alternative ("Accept <other option> instead"), then
**"Reject / defer"**. Possible outcomes:

- **Accept** — the user explicitly accepts the chosen option. Only then:
  1. Flip the ADR's frontmatter to `status: accepted`.
  2. PRD run: append its id to the PRD's `adrs:` frontmatter list (bare id,
     no link). Standalone run: no back-link — `/hive:comb` discovers
     accepted `scope: repo` ADRs by glob.
  3. If it supersedes an older ADR: flip the old ADR's `status:` to
     `superseded` and add a forward link to the successor — per
     `writing-adrs`, these are the **only** edits ever permitted on an
     accepted ADR. For a PRD run, also replace the superseded id with the
     successor's id in the PRD's `adrs:` frontmatter list if the old id is
     present — a stale superseded id left in `adrs:` makes the next
     `/hive:comb` abort.
  4. **Sync the bedrock digest** per `writing-adrs`: condense this ADR's
     **final accepted** Decision Outcome — as it stands after any revision,
     never the architect's draft recommendation — into a bedrock entry in
     root `ARCHITECTURE.md` (replace an existing entry in place; insert a new
     one at its id-sorted position); if it superseded an older ADR, delete
     that ADR's entry. If `ARCHITECTURE.md` does not exist yet, create it
     from the `writing-adrs` skeleton and **backfill**: glob
     `docs/adr/ADR-*.md`, check each file's frontmatter, and read **in full**
     every `status: accepted` ADR (both scopes) not already read this run,
     condensing one entry each — the step-2 glob alone is only a file
     listing, and accepted `scope: prd` ADRs of other PRDs are otherwise
     never in context. Then — on **every** digest sync, not only first
     creation — ensure the repo's root `CLAUDE.md` contains an active import
     line for the digest (`@ARCHITECTURE.md` or `@./ARCHITECTURE.md`; a
     mention inside a code span/fence doesn't count — import parsing skips
     those). Append `@ARCHITECTURE.md` on its own line if absent (mind a
     missing trailing newline); create a minimal `CLAUDE.md` containing just
     that import if none exists.
- **Accept a different option** — while `status: proposed` the doc is
  editable: update the Decision Outcome (and consequences) to the user's
  chosen option, show the revised text, then confirm via **AskUserQuestion**
  ("Accept the revised ADR (Recommended)" / "Revise further") and proceed
  as Accept only on that explicit confirmation. After **any** revision on
  this path — including each "Revise further" round — rerun the step-6
  provenance checks on the revised text and re-state its Assumptions
  entries before asking for confirmation: edits made after persistence must
  not smuggle untagged or unlisted claims past the gate.
- **Reject / defer** — leave the file at `status: proposed` (its id stays
  retired either way — ids are never reused), and record a one-line note
  that the decision is drafted but undecided (`ADR-NNNN proposed,
  pending`) — in the PRD's Open Questions, or in `docs/adr/DECISIONS.md`
  for a standalone run.

**Whatever the verdict, append it to the PRD's audit log** per the colony
`Audit log` section: `adr-accepted` (detail: the chosen option) or
`adr-rejected` (detail: proposed, pending); a supersede additionally gets
an `adr-superseded` entry for the old id (detail: superseded by the new
id). If the architect's note flagged glossary gaps, append them to the
entry's detail field now, at entry-creation time (entries are append-only,
never edited later): `option: <chosen>; glossary gaps: TermA, TermB` —
terms only, comma-separated. This is how `/hive:comb` later finds
unresolved gaps. Standalone runs have no parent PRD and no audit log —
skip this (their gaps surface in the step-9 report only).

An accepted ADR is final. If the user later changes their mind, the answer
is a **new** `/hive:waggle` run that supersedes it — never an edit.

## 8. Commit

Persist all of this run's doc changes together through the **doc commit
flow** (`hive:gh-conventions`, authored-artifact variant): new ADR files,
the PRD frontmatter/Open Questions edits (or `docs/adr/DECISIONS.md` for a
standalone run), any `superseded` flips, the PRD's audit log entries from
step 7, plus the `ARCHITECTURE.md` and `CLAUDE.md` bedrock updates from
step 7 — one commit, Conventional, e.g.:

```
docs(adr): add ADR-0007 queue backend for PRD-003
docs(adr): add ADR-0001 CI provider (repo-scoped)
```

Per that flow: on the default branch this means a doc branch
(`docs/ADR-NNNN-<slug>`, the first accepted id), push, PR (new ADR files →
the ID-collision check applies before merging), then the merge ask —
"Merge now (Recommended)" / "Leave open for review". Under
`/hive:bumble --yolo` the ADR-acceptance verdicts the carve-out covered
also carry merge consent — auto-merge, no ask. On a doc-intended branch,
just commit there.

Do not push issues, create issues, or touch anything under `.github` — this
command produces documents only.

## 9. Report

End with a short summary: accepted ADRs (id + chosen option), proposed-but-
undecided ADRs, worthiness-rejected candidates with where their rationale
was recorded, and any superseded ADRs. List every **glossary gap** the
architects flagged (term + why), with the pointer that gaps are settled via
`/hive:sting` or a grilling session — never applied automatically. This
reporting is identical under a `--yolo` run: gaps are reported, never
auto-applied. For a PRD run the gaps are also in the audit log and
`/hive:comb` will raise a tracking issue for any still unresolved; for a
standalone run this report is their only surfacing. Note when the run created or updated
`ARCHITECTURE.md`, and — especially — when it touched the user's `CLAUDE.md`
(the only write outside `docs/`): surface that edit explicitly. For a PRD run, suggest
`/hive:comb <PRD-id>` as the next step when the PRD's decision surface is
covered. For a standalone run, note that the accepted repo-scoped ADR now
binds every future plan automatically.
