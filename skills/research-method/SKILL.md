---
name: research-method
description: How to run the research phase of the hive lifecycle — deriving open questions from a PRD, the codebase-first search order, evidence-cited findings, the done criterion, and how findings flow into docs/research/ RES docs linked back to the PRD. Use when answering a PRD's open questions during /hive:forage or any scout research task.
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

## 3. Cite evidence — every finding

A finding without evidence is an opinion. Every answer states where it came
from:

- **File paths** (with line context where useful) for codebase findings —
  e.g. `src/auth/session.py:42` defines the session TTL.
- **URLs** for web findings — the specific page, not the site root.
- **Command output** for empirical findings — quote the command and the
  relevant output (e.g. `gh --version` → `gh version 2.96.0`).

Distinguish clearly between what a source *states* and what you *infer*
from it.

## 4. When research is done

Research is done when **every** question in the doc has one of:

- a **sourced answer** — conclusion plus the evidence above, or
- an explicit **"unknowable now"** — stating *why* it cannot be answered
  yet and *what would resolve it* (a decision that must be made first, an
  experiment to run, access that is missing, an upstream release).

No question may be silently dropped, merged away, or left half-answered.
"Unknowable now" is a legitimate result; a missing answer is not.

## 5. Persist and link

- Scouts return findings as a structured summary; the orchestrator persists
  them to `docs/research/RES-NNN-slug.md` with frontmatter per the template
  (`id`, `prd`, `status`, `questions`, `created`).
- A research doc starts `status: open` and is flipped to `status: answered`
  only when the done criterion above holds for every question it carries.
- Each RES id is added to the owning PRD's `research:` frontmatter list,
  and the doc body references the PRD by ID **and** repo-relative link.
  "Unknowable now" items that block requirements should also surface in the
  PRD's Open Questions so `/hive:waggle` and `/hive:comb` see them.

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

<!-- One section per question. Status flips to `answered` only when every
     question has an Answer backed by Evidence. -->

## Q1: <question>

### Findings

<What was found: codebase, prior ADRs, web — in that search order.>

### Evidence

<Citations: file paths, ADR ids, URLs.>

### Answer

<The concise answer to the question.>
```
