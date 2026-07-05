---
name: pollinate
description: "Turn a raw idea into an approved PRD via a grilling interview. Invoke as /hive:pollinate <idea> — the argument is the idea in one or a few sentences. Runs a one-question-at-a-time interview with domain-modeling active, then drafts docs/prd/PRD-NNN-<slug>.md (status: draft) and waits for the human approval gate."
disable-model-invocation: true
---

# /hive:pollinate — Idea → PRD

Interview the user about the idea in `$ARGUMENTS`, sharpen it into canonical
language, and draft a PRD. You (the orchestrating session) conduct the whole
interview yourself — no subagents are dispatched by this command.

## Step 0 — Setup

1. Read the idea from `$ARGUMENTS`. If `$ARGUMENTS` is empty, ask for the
   idea via **AskUserQuestion** before anything else — never in plain prose:
   offer your best context-derived guesses as options (open TODOs, recent
   branches/commits, gaps the repo suggests), each as a concrete one-line
   idea; the automatic "Other" carries the user's own one-sentence idea. If
   the repo gives no signal, offer example directions so the user sees the
   expected shape of an answer.
2. **Load the `hive:grilling` and `hive:domain-modeling` skills now** (Skill
   tool), before the first question. They govern the entire interview. Also
   load `hive:writing-prds` and `hive:crosslinking` — you will need them for
   the draft.
3. If root `CONTEXT.md` exists, read it and use only its canonical terms from
   the first question onward.

## Step 1 — Grilling interview (with domain-modeling active)

Run the interview exactly per the `grilling` skill. The load-bearing rules:

- **One question at a time — never a form.** Ask a single question via
  **AskUserQuestion** (one question per call, per `hive:grilling`), wait for
  the answer, then ask the next.
- **Every question ships a concrete recommended answer** — the first option,
  labelled `(Recommended)`, with the reason in its description — so the user
  can accept with a single click or push back.
- **Walk the design tree branch by branch.** Pick a branch (scope, users,
  behavior, edge cases, constraints, …), drill until it is fully resolved,
  visibly close it, then move to the next. Never hop between half-resolved
  branches.
- **Never ask what the codebase can answer.** If the repository can settle a
  question (existing conventions, file layout, whether something already
  exists), explore it with Read/Grep/Glob and state the finding as a
  confirmation instead of a question.
- **Sharpen fuzzy terms the moment they appear.** When the user's language is
  vague, overloaded, or two words compete for one concept, resolve the term
  per `domain-modeling` and write the glossary entry into root `CONTEXT.md`
  **inline, right then** — never batched for the end of the session. If
  `CONTEXT.md` does not exist yet, create it lazily on the first resolved
  term, following the `CONTEXT-FORMAT.md` reference in the domain-modeling
  skill directory (title + purpose line, `## <Term>` sections in alphabetical
  order, each with a tight definition and an `Avoid:` line). From then on use
  only the canonical term.
- **Challenge against the existing glossary**: if the user's usage conflicts
  with a `CONTEXT.md` entry, call it out — either the usage bends or the
  entry is deliberately revised.

### Shared-understanding gate

The interview ends **only** when you play the whole design back to the user
in canonical glossary terms — a compact summary of every resolved decision —
and the user explicitly agrees it is right. No agreement, no PRD. If the
play-back surfaces a mismatch, reopen that branch and grill on.

## Step 2 — Draft the PRD

Only after the shared-understanding gate has passed:

1. **Allocate the ID** per `crosslinking`: glob `docs/prd/PRD-*.md`, take the
   highest `NNN` + 1, zero-padded to three digits (`PRD-001` when the glob
   matches nothing). IDs are append-only — never reuse the number of a
   deleted or abandoned PRD. Derive a short kebab-case `<slug>` from the
   title.
2. Write `docs/prd/PRD-NNN-<slug>.md` from the template at
   the **Template** in the `hive:writing-prds` skill, following that skill:
   - Frontmatter: `id: PRD-NNN`, `title`, **`status: draft`**, `created:`
     today's date, `research: []`, `adrs: []`, `milestones: []`.
   - Body sections in order: **Problem**, **Goals / Non-Goals**,
     **Requirements**, **Open Questions**.
   - Each requirement is a stable anchor heading of the exact form
     `### R1: <title>` (referenced downstream as `PRD-NNN-R1`; append-only,
     never renumbered).
   - Requirements and all prose use **canonical glossary terms only** — a
     word from any `Avoid:` list is a defect.
   - Every requirement carries **testable acceptance criteria**: observable,
     binary, and tied to a named verification method (a command, a test
     invocation, a manual step). If you cannot name how a criterion will be
     checked, sharpen it or move it to Open Questions.
   - Everything genuinely unresolved from the interview goes into
     **Open Questions** — this section is `/hive:forage`'s primary input.
3. If the PRD came out with multiple independent goals, different approval
   owners, or more than ~7 requirements, split it per `writing-prds`
   (separate PRD files, cross-referenced by ID + repo-relative link in each
   Problem section) and tell the user you did so.

## Step 3 — Commit the draft

Commit the new PRD **together with `CONTEXT.md`** when the interview touched
it — the vocabulary and the artifact that coined it share one commit (per
`domain-modeling`). Sync local main first per the `gh-conventions` skill
(`git switch main && git pull --ff-only origin main` before any commit on
main). Use a Conventional Commit, e.g.:

```
docs(prd): add PRD-NNN <short title>
```

Then push (`git push origin main`).

## Step 4 — Approval gate (human only — NEVER auto-approve)

1. Present the PRD to the user: path, one-line summary per requirement, and
   the Open Questions list. Point out that `/hive:forage PRD-NNN` answers the open
   questions next.
2. Ask for the verdict with **AskUserQuestion** (one call, per the colony
   ground rule): options **"Approve the PRD (Recommended)"** (description:
   the shared-understanding gate passed; approval unlocks the rest of the
   lifecycle), **"Request changes"**, and **"Leave as draft for now"**.
   The PRD moves to `approved` **only** when the user selects Approve or
   edits the frontmatter themselves. Never flip it on your own initiative,
   never infer approval from silence or from enthusiasm about the draft.
3. If the user requests changes: revise the draft (reopening grilling
   branches as needed, updating `CONTEXT.md` inline if terms shift), commit
   the revision, and present again. While `status: draft`, the document is
   freely editable.
4. When the user declares approval in conversation, set `status: approved` in
   the frontmatter, append a `prd-approved` entry (subject: the PRD id,
   detail: `—`) to the PRD's audit log (`docs/audit/PRD-NNN-audit.md`,
   created now if absent — schema and rules in the colony `Audit log`
   section), and commit + push both files together:

```
docs(prd): approve PRD-NNN
```

   (If the user already edited the status themselves, append the
   `prd-approved` entry now if the audit log lacks it, then commit whatever
   is uncommitted, or confirm it is committed.)

5. Report: PRD ID, path, status, and the suggested next step
   (`/hive:forage PRD-NNN` if Open Questions exist, otherwise `/hive:waggle PRD-NNN`).
