---
name: writing-adrs
description: How to write architecture decision records for the hive lifecycle — the ADR-worthiness test that gates whether an ADR is written at all, MADR 4.0 conventions, the option-comparison quality bar, and the append-only status lifecycle with supersede procedure. Use when evaluating candidate decisions or drafting any document in docs/adr/.
---

# Writing ADRs

ADRs record architecture decisions in `docs/adr/ADR-NNNN-slug.md`, MADR 4.0
format, per the **Template** at the end of this skill. They are written by the
architect agent during `/hive:waggle` and accepted only by the human.

ADRs come in two scopes, declared in frontmatter:

- **`scope: prd`** (the default) — derived from a specific PRD's decision
  surface; `derived-from:` names that PRD.
- **`scope: repo`** — a standalone cross-cutting platform decision (CI/CD
  provider, build system, toolchain policy) with no parent PRD;
  `derived-from: null`. Authored via `/hive:waggle --standalone`. Accepted
  repo-scoped ADRs bind **every** plan: `/hive:comb` passes them to the
  planner alongside the PRD's own ADRs.

## The ADR-worthiness test — apply BEFORE writing

Every candidate decision must pass **all three** legs before an ADR is
drafted:

1. **Hard to reverse** — undoing it later costs real migration work, not
   just an edit. (A rename is reversible; a storage format is not.)
2. **Surprising without context** — a competent newcomer reading the code
   would ask "why on earth this?"; the answer isn't obvious from the code.
3. **A real trade-off exists** — there are at least two defensible options
   and choosing one genuinely gives something up. If one option dominates,
   there is no decision to record.

If **any leg fails, no ADR is written.** The rejected candidate must not
vanish silently: record a one-line rationale in the PRD — in its Open
Questions section or body — e.g. "Retry library choice: not ADR-worthy
(trivially reversible); picked tenacity, note in PRD body." This keeps the
decision discoverable without ADR ceremony. In a standalone
(`--standalone`) run there is no PRD: append the rationale line to
`docs/adr/DECISIONS.md` instead (create the file on first use — an
append-only log of worthiness-rejected and deferred standalone candidates).

## MADR 4.0 structure

Frontmatter per the template: `id`, `status`, `scope` (`prd` | `repo`),
`derived-from` (the PRD for `scope: prd`; `null` for `scope: repo`),
`informed-by` (RES ids), `supersedes`, `date`. Body sections, in order:

1. **Context and Problem Statement** — the forces at play and the question
   being decided, phrased neutrally (ideally as a question).
2. **Domain context** — the DDD lens on the decision, always at this fixed
   position (immediately after Context and Problem Statement); see the
   **Domain context (DDD)** section below for its content rules and its
   mandatory one-line skip form.
3. **Decision Drivers** — the criteria that matter, as a bulleted list.
   These are what the options get judged against.
4. **Considered Options** — a short list naming each option.
5. **Decision Outcome** — "Chosen option: <X>, because <justification tied
   to the drivers>." Include confirmation: how we will know the decision is
   working (a measurement, a review point).
6. **Consequences** — good and bad, honestly. Every decision has a "bad"
   consequence; if you can't name one, the trade-off leg of the worthiness
   test probably failed.
7. **Pros and Cons of the Options** — one subsection per option.
8. **Assumptions** — one bullet per inline `[ASSUMED]` claim, each with
   what would verify it; the bare line `None.` (no bullet) when there are
   none. Always present in new drafts — `/hive:waggle` validates inline
   `[ASSUMED]` tags against this section.

Use canonical glossary terms from root `CONTEXT.md` when it exists.
Reference the PRD (when one exists) and any research docs by ID **and**
repo-relative link.

## Option-comparison quality bar

- **Minimum 2 real options.** A strawman next to the intended choice does
  not count — each option must be something a reasonable engineer could
  ship. If only one real option exists, the worthiness test already failed.
- **Honest pros and cons for every option**, including the winner. The
  chosen option's cons and the losers' pros must survive review by someone
  who prefers the other side.
- **Explicit rejected-because reasoning** — each non-chosen option gets a
  clear statement of why it lost, tied to the decision drivers, not just
  a cons list. "Rejected because driver D2 (operational simplicity)
  outweighs its performance edge" beats "has downsides".
- **Provenance on web-sourced claims.** Every material claim that came from
  web research carries an inline tag + confidence exactly where it is used:
  `[VERIFIED: <source>, confidence: <RATING>]` /
  `[CITED: <url>, confidence: <RATING>]` / `[ASSUMED, confidence: LOW]` —
  uppercase tag and confidence, `<RATING>` being `HIGH`/`MEDIUM`/`LOW`: the
  claim's actual rating, at or below its tag's ceiling per the
  `research-method` skill (official docs fetched and read are primary,
  hence VERIFIED; a single-source CITED claim is LOW; downgrades allowed,
  upgrades never). Every `[ASSUMED]` claim repeats as a bullet in the
  ADR's `## Assumptions` section, which is always present (`None.` when
  empty).

## Domain context (DDD)

Every ADR carries a `## Domain context` section, fixed in position right
after Context and Problem Statement. It applies strategic Domain-Driven
Design to the decision; the drafting method lives in the architect agent —
this section defines what the document must contain.

- **Content**: the bounded contexts / subdomains the decision touches
  (each classified core / supporting / generic), and — where the decision
  spans contexts — their relationships in context-mapping vocabulary
  (shared kernel, customer–supplier, conformist, anticorruption layer,
  open-host service, separate ways). A few sentences or bullets; this is
  decision-altitude analysis, not a modeling workshop.
- **Derived fresh, intent first.** The domain picture is re-derived at
  drafting time from, in priority order: the PRD → accepted ADRs → root
  `CONTEXT.md` glossary → code signals. Intent documents outrank code;
  nothing is persisted as a separate context-map artifact (`CONTEXT.md`
  stays glossary-only, `ARCHITECTURE.md` stays a derived digest).
- **Skip rule**: a decision with no domain impact (CI provider, build
  system, toolchain policy) collapses the section to exactly one stated
  line — `No domain impact: <reason>.` — never silently omitted.
- **Tactical gate**: tactical patterns (aggregates, entities/value
  objects, domain events) appear **only when they are the decision or its
  direct consequence** — e.g. an ADR choosing event-driven integration
  names the domain events crossing the boundary; an ADR choosing a
  consistency boundary names the aggregate it draws. Otherwise the section
  stays strategic: ADRs must not prescribe implementation-level structure
  the planner and workers own.
- **Inferred models are assumptions**: where the domain picture was
  inferred rather than stated (greenfield repo, unclear architecture), tag
  those inferences `[ASSUMED, confidence: LOW]` inline and list them in
  `## Assumptions` like any other unverified claim — the acceptance gate
  sees them.

## Diagrams

Where a figure clarifies the decision — the architecture at stake, the
option topologies, a state machine — embed a ```` ```mermaid ```` fenced
block in the relevant section (usually Context and Problem Statement or
an option's subsection). Diagrams are optional: add one only where it aids
understanding. Fall back to fenced ASCII art only when mermaid cannot
express the figure; never emit both forms of the same figure.

## Status lifecycle — append-only

`proposed → accepted | superseded`:

- **proposed** — set by the architect at draft time. Freely editable while
  the options are presented and discussed.
- **accepted** — set **only by the human** during `/hive:waggle`; never
  auto-accept (sole delegation exception: `/hive:bumble --yolo` answers the
  acceptance gate for ADRs drafted in that run, per the colony carve-out).
  On acceptance a `scope: prd` ADR's id is appended to the
  PRD's `adrs:` frontmatter; a `scope: repo` ADR needs no back-link —
  `/hive:comb` discovers it by globbing `docs/adr/` for accepted
  repo-scoped ADRs.
- **superseded** — an accepted ADR's decision is **never edited**. If the
  decision changes, supersede it (below). Fixing a typo in prose is fine;
  changing what was decided, the options, or the reasoning is not.

## Supersede procedure

1. Write a **new** ADR (next free `ADR-NNNN`) through the normal `/hive:waggle`
   flow — worthiness test, ≥2 options (the old decision is usually one of
   them), human acceptance.
2. The new ADR's frontmatter sets `supersedes: ADR-NNNN` pointing at the
   old one, and its Context section links the old ADR and states what
   changed since it was accepted.
3. Flip the **old** ADR's `status` to `superseded` — this status flip and a
   forward link to the successor are the only permitted edits to an
   accepted ADR.

## The bedrock digest — root ARCHITECTURE.md

Root `ARCHITECTURE.md` is a **derived digest**: one condensed bedrock entry
per **accepted** ADR (both scopes), loaded into every session's context via
an `@ARCHITECTURE.md` import in the repo's root `CLAUDE.md`. It is **never a
source of truth** — planning always reads the full ADRs — and is written
**only** by `/hive:waggle` at its acceptance/supersede sync points. Proposed
ADRs, superseded ADRs, and `DECISIONS.md` entries never appear in it. It is
regenerable from the accepted ADR set at any time.

The file starts with a mandatory generated-file header comment:

````markdown
# Architecture bedrock

<!-- Derived digest — do NOT hand-edit. One entry per accepted ADR,
     maintained by /hive:waggle on acceptance/supersede. The full ADRs in
     docs/adr/ are the source of truth; this file is regenerable from the
     accepted ADR set at any time. -->
````

Each entry, ordered by ADR id ascending:

````markdown
## ADR-0007: Queue backend
[ADR-0007](docs/adr/ADR-0007-queue-backend.md)
**Decision:** Use Redis Streams as the job queue.
**Binds:** All async work goes through Redis Streams; introducing another
queue technology requires superseding this ADR.
````

- **Decision** — one sentence condensed from the ADR's **final accepted**
  Decision Outcome.
- **Binds** — the constraint phrased as an obligation on future work, not a
  restatement of the decision.
- Link repo-relative from root; ID + link per `hive:crosslinking`.
- Entries are keyed by their `## ADR-NNNN:` heading. A sync **replaces** an
  existing entry in place (idempotent) and **inserts** a new entry at its
  **id-sorted position** — a plain append would degrade the ascending-id
  order. Supersession **deletes** the superseded ADR's entry.

## Template

Scaffold a new ADR (MADR 4.0) from this skeleton (this skill is the source of
truth — no external template file is required):

```markdown
---
id: ADR-NNNN
status: proposed | accepted | superseded
scope: prd            # prd (default) | repo — repo = standalone cross-cutting platform decision
derived-from: PRD-NNN # the parent PRD; null when scope: repo
informed-by: [RES-NNN]
supersedes: null      # ADR-NNNN id this record supersedes, if any
date: YYYY-MM-DD
---

# ADR-NNNN: <title>

## Context and Problem Statement

<What is the issue we are deciding on, and why does it need a decision?>

## Domain context

<!-- Strategic DDD lens per the "Domain context (DDD)" section: bounded
     contexts / subdomains touched (core / supporting / generic) and their
     relationships; tactical patterns only when decision-relevant. For a
     decision with no domain impact, exactly one line:
     "No domain impact: <reason>." -->

<bounded contexts / subdomains this decision touches, or the one-line skip>

## Decision Drivers

- <driver 1>
- <driver 2>

## Considered Options

- <option 1>
- <option 2>

## Decision Outcome

Chosen option: "<option 1>", because <justification>.

### Consequences

- Good, because <positive consequence>
- Bad, because <negative consequence>

## Pros and Cons of the Options

### <option 1>

- Good, because <argument>
- Bad, because <argument>

### <option 2>

- Good, because <argument>
- Bad, because <argument>

## Assumptions

<!-- One bullet per inline [ASSUMED] claim — what is assumed and what would
     verify it. The bare line "None." (no bullet) when the draft carries no
     ASSUMED claims. -->

None.
```
