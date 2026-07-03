# CONTEXT.md Format

> Adapted from mattpocock/skills (MIT License) — https://github.com/mattpocock/skills

The root `CONTEXT.md` is a glossary and nothing else. This file defines its
exact shape.

## Structure

```md
# Hive Glossary

Canonical vocabulary for this project — use these terms, avoid the banned synonyms.

## Customer

A person or organization that places orders. The Customer is the party the
contract is with, independent of which User acts on its behalf.

Avoid: client, buyer, account

## Order

A confirmed request by a Customer to purchase specific items. An Order exists
from confirmation onward; before confirmation it is only a cart.

Avoid: purchase, transaction, basket
```

- **Title** (`# ...`), then a **one-line purpose header** stating what the
  file is.
- Then **one `## <Term>` section per term**, each containing:
  - a **one-paragraph definition** — what the term IS, tight and opinionated;
  - an **`Avoid: <banned synonyms>`** line listing the near-synonyms that
    must not be used for this concept.
- **Alphabetical order** of terms, always — new entries are inserted in
  place, never appended.
- **Nothing but glossary content.** No implementation details, no execution
  state, no decisions, no TODOs, no prose between entries.

## Rules

- **Be opinionated.** When multiple words exist for one concept, pick the
  best one as the section heading and list the rest under `Avoid:`.
- **Keep definitions tight.** One paragraph, a few sentences at most. Define
  what the term IS, not how it is implemented.
- **Only project-specific terms.** General programming concepts (timeout,
  retry, error type) do not belong, even if the project uses them heavily.
  Before adding a term ask: is this concept unique to this project's domain?
  Only then does it belong.
- **Every entry has an `Avoid:` line.** If no synonym is banned yet, the term
  probably was not contested enough to need an entry.
