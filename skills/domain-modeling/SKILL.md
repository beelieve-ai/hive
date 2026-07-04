---
name: domain-modeling
description: Sharpen fuzzy language into a canonical project vocabulary and maintain the root CONTEXT.md glossary. Use during grilling sessions (/hive:pollinate, /hive:sting) whenever a term is vague, overloaded, or contested, or whenever the glossary needs a new or corrected entry.
---

# Domain Modeling

> Adapted from mattpocock/skills (MIT License) — https://github.com/mattpocock/skills

Actively build and sharpen the project's vocabulary as you design. This is
the *active* discipline — challenging terms, probing edge cases, and writing
the glossary entry down the moment a term crystallises. Merely *reading*
`CONTEXT.md` for vocabulary is not this skill; that is a one-line habit any
agent can have. This skill is for changing the model, not consuming it.

## The glossary: root `CONTEXT.md`

- **One file, repo root, version-controlled.** `CONTEXT.md` is the single
  canonical glossary for this project.
- **Glossary-only.** Opinionated canonical terms, each with an `Avoid:` list
  of banned near-synonyms — and nothing else. No implementation details, no
  execution state, no specs, no scratch notes, no decision records. If it is
  not a term definition, it does not belong.
- **Lazily created.** Do not scaffold an empty glossary. The first session
  that resolves a term creates the file, following
  [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).
- **Updated inline, the moment a term resolves.** When the user and you agree
  on a canonical term, write the entry into `CONTEXT.md` right then — never
  batch glossary updates for the end of the session. A batched glossary is a
  forgotten glossary.
- **Committed alongside the artifact.** The `CONTEXT.md` change rides in the
  same commit as the PRD, ADR, or other document whose grilling resolved the
  term, so the vocabulary and the artifact that coined it share history.

## During a session

### Challenge against the glossary

When the user uses a term that conflicts with an existing `CONTEXT.md`
entry, call it out immediately: "The glossary defines *cancellation* as X,
but you seem to mean Y — which is it?" Either the usage bends to the
glossary or the glossary entry is deliberately revised.

### Sharpen fuzzy language

When the user uses a vague or overloaded word, propose a precise canonical
term with a recommendation, per the `grilling` skill: "You say *account* —
do you mean the Customer or the User? I recommend *Customer* here." Be
opinionated: when several words compete for one concept, pick the best one
and ban the rest via the entry's `Avoid:` list.

### Probe with concrete scenarios

Stress-test relationships between terms with specific edge-case scenarios
that force precise boundaries: "A milestone with a closed epic but one open
task — is that goal *done*?"

### Cross-reference with the code and docs

When the user states how something works, check whether the repository
agrees. Surface contradictions: "The code closes the whole Order, but you
just said partial cancellation exists — which is right?"

## Downstream obligations

- **Requirements and ADRs must use canonical terms.** A PRD requirement or
  ADR that uses a word from an `Avoid:` list is a defect — fix the document,
  or grill until the glossary changes.
- **Architecture decisions are not glossary content.** When a resolved
  question turns out to be a decision (not a term), route it to `/hive:waggle`,
  where the ADR-worthiness test in the `writing-adrs` skill decides whether
  it earns an ADR. `CONTEXT.md` never records decisions.
