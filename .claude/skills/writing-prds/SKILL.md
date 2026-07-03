---
name: writing-prds
description: How to write PRDs for the hive lifecycle — document structure, stable requirement IDs, testable acceptance criteria, when to split a PRD, and the status lifecycle with its human approval gate. Use when drafting or revising any document in docs/prd/.
---

# Writing PRDs

A PRD captures **intent**: what problem we solve, what must be true when it is
solved, and what is deliberately out of scope. PRDs live in
`docs/prd/PRD-NNN-slug.md` and follow the template at `docs/templates/prd.md`.
They are the source of truth that `/forage`, `/waggle`, and `/comb` build on.

## Structure

Frontmatter per the template (`id`, `title`, `status`, `created`, `research`,
`adrs`, `milestone`, `epic_issue`). Body sections, in order:

1. **Problem** — who hurts, why, and why now. No solutions here.
2. **Goals / Non-Goals** — goals are outcomes, not features. Non-goals are
   explicit scope cuts; write down anything a reader might plausibly assume
   is included but isn't.
3. **Requirements** — one `### R<n>: <title>` heading per requirement, each
   with acceptance criteria (see below).
4. **Open Questions** — everything genuinely unresolved. This section is the
   primary input to `/forage`; a question that never gets written down never
   gets researched. It also holds one-line rationales for decisions that
   failed the ADR-worthiness test in `/waggle`.

## Requirement IDs

- Each requirement is a heading of the exact form `### R1: <title>` — the
  `R<n>` token is a **stable anchor**, referenced elsewhere as `PRD-NNN-R1`
  (in ADR frontmatter, plan.yaml `implements:` lists, and issue bodies).
- IDs are **append-only**. New requirements take the next free number.
  **Never renumber**, reorder-and-renumber, or reuse the ID of a deleted
  requirement — downstream plans and issues reference these tokens verbatim.
- A dropped requirement keeps its heading with the body replaced by a
  one-line "Withdrawn: <reason>" note, so `PRD-NNN-R<n>` never dangles.

## Acceptance criteria

Every requirement carries acceptance criteria. Each criterion must be:

- **Observable** — states something a reviewer can see or measure (file
  exists, endpoint returns X, command exits 0), not an internal quality
  ("code is clean") or an intention ("should be fast").
- **Binary** — pass or fail, no judgment scale. If it needs a threshold,
  name the threshold ("p95 latency < 200 ms"), never "reasonably fast".
- **Tied to a verification method** — say *how* it will be checked: a test
  invocation, a command, a manual step. If you cannot name a way to verify
  it, it is not a criterion yet — sharpen it or move it to Open Questions.

Bad: "Users can log in easily."
Good: "`POST /login` with valid credentials returns 200 and a session
cookie — verified by `pytest tests/test_login.py`."

## Vocabulary

If a root `CONTEXT.md` glossary exists, read it before writing and phrase
requirements in its canonical terms — never in a term its *Avoid* list bans.
If a key term in the PRD is fuzzy and not in the glossary, that is a signal
to sharpen it (via the grilling interview) rather than write around it.

## When to split a PRD

Split into separate PRDs when any of these hold:

- **Multiple independent goals** — the goals could ship separately and
  neither depends on the other's requirements.
- **Different approval owners** — parts of the scope are approved by
  different humans; one gate per document keeps approvals unambiguous.
- **More than ~7 requirements** — beyond that, plans balloon and the
  approval gate stops being a meaningful review. Split along goal lines.

When splitting, cross-reference the sibling PRDs by ID and repo-relative
link in each Problem section.

## Status lifecycle

`draft → approved → planned → implemented`, strictly forward:

- **draft** — set at creation by `/pollinate`. Freely editable.
- **approved** — set **only by the human** (edits the frontmatter or says
  so explicitly). This is a mandatory gate: `/forage`, `/waggle`, and
  `/comb` build on the PRD's content, and nothing may be auto-approved on
  the human's behalf. Post-approval sharpening (e.g. via `/sting`) never
  resets this gate.
- **planned** — set by `/comb` at materialization, together with the
  `milestone` and `epic_issue` frontmatter fields.
- **implemented** — set by `/swarm` when every task issue in the milestone
  is closed.
