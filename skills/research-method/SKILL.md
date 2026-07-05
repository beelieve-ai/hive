---
name: research-method
description: How to run the research phase of the hive lifecycle — deriving open questions from a PRD, the codebase-first search order, evidence-cited findings with provenance tags (VERIFIED/CITED/ASSUMED), confidence ratings capped by those tags, the human-gated Assumptions Log, the done criterion, and how findings flow into docs/research/ RES docs linked back to the PRD. Use when answering a PRD's open questions during /hive:forage or any scout research task.
---

# Research method

Research turns a PRD's open questions into sourced answers. It is run by
scout agents during `/hive:forage`; findings land in `docs/research/RES-NNN-slug.md`
(see the **Template** at the end of this skill) and link back into the PRD.

If a root `CONTEXT.md` glossary exists, read it first and use its canonical
vocabulary when phrasing questions and findings.

## 1. Derive the questions

Two sources, both mandatory:

- The PRD's **Open Questions** section — take every entry verbatim.
  Settlement records are the exception: worthiness-rejection rationales
  ("…: not ADR-worthy (…)") and "ADR-NNNN proposed, pending" notes are
  records of decisions, not questions — exclude them.
- **Gaps found while reading the requirements** — read each `### R<n>`
  requirement and its acceptance criteria; anything that cannot be
  implemented or verified without information nobody has written down is an
  implicit open question. Make it explicit and add it to the question list
  (and note it back into the PRD's Open Questions so the doc stays the
  source of truth).

Cluster related questions; independent clusters can be researched in
parallel by separate scouts.

## 2. Search order

Cheapest, most authoritative source first:

1. **Codebase** — Grep/Glob/Read this repo. What already exists, what
   conventions are established, what an answer must be compatible with.
2. **Prior ADRs and docs** — `docs/adr/`, `docs/research/`, `docs/prd/`,
   `CONTEXT.md`. A question may already be answered or explicitly decided;
   an accepted ADR is binding context, not something to relitigate.
3. **The web** — only for what the repo cannot answer: external APIs,
   library behavior, ecosystem practice. Prefer primary sources (official
   docs, changelogs, source code) over blog posts.

**Training data is a hypothesis, not a source** — a starting guess to
verify against the rungs above, never a citation. "As of my training" is a
warning flag, not evidence: confirm it or tag it `[ASSUMED]`.

## 3. Evidence and provenance

A claim without evidence is an opinion. Every **material claim in an Answer
must be backed by a tagged Evidence entry**. Claim tags live in Evidence
citations **only** — Findings prose carries no inline tags; the Evidence
section is the ledger. Three tags:

- **`[VERIFIED: <source>]`** — confirmed against this codebase or an
  official/primary source. Transport is irrelevant: official docs pulled
  via WebFetch are primary. Cite file paths (with line context —
  `src/auth/session.py:42`), ADR ids, or the primary URL/command output.
- **`[CITED: <url>]`** — web-sourced, not yet confirmed against an official
  source. Cite the specific page, not the site root.
- **`[ASSUMED]`** — inference or training knowledge, no source. Repeats as a
  bullet in the **Assumptions Log**; the Evidence entry cites its `A<n>` id.

**Tags set the confidence ceiling** — never an upgrade above it:
`[VERIFIED]` → up to **HIGH**; `[CITED]` + independent corroboration → up
to **MEDIUM**; `[CITED]` single-source → **LOW**; `[ASSUMED]` → **LOW**.

**Downgrade below the ceiling** when the source is version-mismatched,
covers only part of the answer, or is contradicted by another source.
Never upgrade above it — a corroborated CITED claim can never be rated HIGH.

**Never present LOW as authoritative**; an existence proof ("this API
exists") is not an authoritative source for how it behaves. **Negative
findings cite too**: state what was searched and where (`grep -rn X src/`
→ no hits).

## 4. Honest reporting

- **Evidence before claims.** Skipping verification is dishonesty, not
  efficiency.
- **A non-answer is a valuable result.** "Couldn't find X", "sources
  contradict", "LOW confidence" are all legitimate outcomes; confident
  padding is the failure mode.
- **Never assert "X is impossible"** without official verification.
  "Didn't find it" ≠ "doesn't exist".
- **Hedge words in an Answer = missing evidence.** "Should", "probably",
  "seems" mean you have not verified — get the evidence or downgrade the
  confidence.

## 5. Search hygiene and bias counters

- **Vary phrasing** — one wording finds one slice of the web.
- **Never inject the current year** into queries — check each source's
  publication date instead; year-stuffing biases toward stale SEO pages.
- **Confirmation counter** — once you have a formed answer, run one cycle
  searching *against* it; zero criticism means the search was too narrow,
  not that the answer is airtight.
- **Survivorship counter** — weight "we migrated away from X" reports
  higher than "we love X" ones; failures are underpublished.

Apply the counters **once, at decision points** — not on every query.

**When NOT to think** — skip the counters entirely for: trivial version
lookups, codebase-only questions, and questions already settled by an
accepted ADR.

## 6. When research is done

Research is done when **every** question has a **Confidence-rated Answer**
that is one of:

- a **sourced answer** — conclusion plus tagged Evidence, or
- an explicit **"unknowable now"** — stating *why* it cannot be answered
  yet and *what would resolve it* (a decision that must be made first, an
  experiment to run, access that is missing, an upstream release).
  "Cannot verify" maps here. **Boundary rule:** an "unknowable now" that
  names a best guess IS an `[ASSUMED]` answer and must be written as one.

A question **fails the criterion while its Answer relies on any unaccepted
`[ASSUMED]` claim** — not only when the evidence is ASSUMED-only. The
Assumptions Log records which Q each entry backs. The question stays unmet
until every such assumption is resolved or **accepted at the forage gate**.

No question may be silently dropped, merged away, or left half-answered.

## 7. Persist and link

- Scouts return findings as a structured summary; the orchestrator persists
  them to `docs/research/RES-NNN-slug.md` per the template — including tags,
  confidence ratings, and the Assumptions Log.
- The **forage orchestrator spot-checks scout citations** (existence checks
  only, no content pulled into context) before persisting; a citation that
  does not resolve is treated like a dropped question (forage re-dispatches
  once).
- A research doc starts `status: open` and is flipped to `status: answered`
  only when the done criterion above holds for every question it carries.
- Each RES id is added to the owning PRD's `research:` frontmatter list,
  and the doc body references the PRD by ID **and** repo-relative link.
  "Unknowable now" items that block requirements should also surface in the
  PRD's Open Questions so `/hive:waggle` and `/hive:comb` see them.

## Diagrams

Findings may embed ```` ```mermaid ```` fenced blocks under `### Findings`
where a figure aids understanding — a discovered architecture or sequence
flow. Optional, never mandatory. Fall back to fenced ASCII art only when
mermaid cannot express the figure; never emit both forms of the same figure.

## Template

Scaffold a new research doc from this skeleton (this skill is the source of
truth — no external template file is required):

```markdown
---
id: RES-NNN
prd: PRD-NNN
status: open | answered
questions: []         # the open questions this doc addresses
created: YYYY-MM-DD
---

# RES-NNN: <title>

<!-- One section per question. Every material Answer claim is backed by a
     tagged Evidence entry. Status flips to `answered` only when every
     question has an Answer with a Confidence rating and no unaccepted
     [ASSUMED] claim remains. -->

## Q1: <question>

### Findings

<Codebase, prior ADRs, web — in search order. No inline tags; Evidence
 is the ledger.>

### Evidence

- [VERIFIED: src/foo.py:42] …
- [CITED: https://…] …
- [ASSUMED] … (backs A1)

### Answer

<The concise answer.>

**Confidence:** HIGH | MEDIUM | LOW

## Assumptions Log

<!-- One bullet per [ASSUMED] claim. "None." if there are none. Acceptance
     markers are written only by the forage gate. -->

- **A1** (backs Q1): <the assumption> — what would verify it: <check>.
- **A2** (backs Q2): <the assumption> — what would verify it: <check>
  — accepted YYYY-MM-DD by human|yolo
```
