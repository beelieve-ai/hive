---
name: crosslinking
description: Cross-linking and ID-allocation rules for Hive lifecycle artifacts — how docs reference docs, how issues link back to docs, the mandatory issue-body header block, PRD↔issue sync points, and append-only ID allocation via directory globbing.
---

# Cross-linking

Rules for how Hive artifacts (PRDs, research docs, ADRs, plans, GitHub issues)
reference each other. Documents are the source of truth for intent; issues are
the execution layer. Links must resolve in both worlds.

## Doc → Doc

Every reference from one document to another uses **both** forms together:

1. The stable ID, e.g. `ADR-0007`, `PRD-003`, `RES-002` — greppable, survives renames of prose.
2. A repo-relative markdown link, e.g. `[ADR-0007](../adr/ADR-0007-queue-backend.md)` — clickable in editors and GitHub file view.

Combined: `[ADR-0007](../adr/ADR-0007-queue-backend.md)`. Never link by ID
alone in body prose, and never link by path alone without the ID visible.

Frontmatter fields (`research:`, `adrs:`, `prd:`, `informed-by:`,
`derived-from:`, `supersedes:`) carry bare IDs only — no links in YAML.

## Issue → Doc

Issue bodies render in the GitHub web UI, where repo-relative links do not
resolve. Therefore every link from an issue body to a document uses the **full
hardcoded URL**:

```
https://github.com/beelieve-ai/hive/blob/main/docs/prd/PRD-NNN-slug.md
```

No placeholders, no `../blob/main/...` relative forms, no shortened paths.
Link to a specific requirement with its anchor when useful:
`https://github.com/beelieve-ai/hive/blob/main/docs/prd/PRD-NNN-slug.md#r1-title-slug`.

(This is why `/comb` materialization commits and pushes the docs **before**
creating any issue — otherwise these `blob/main/...` links 404.)

## Issue header block (mandatory)

Every generated issue body — epic and task alike — **starts** with this header
block, before any other content:

```
**PRD:** [PRD-NNN](https://github.com/beelieve-ai/hive/blob/main/docs/prd/PRD-NNN-slug.md) · **Implements:** PRD-NNN-R1 · **ADR:** ADR-NNNN
```

- **PRD:** the governing PRD, linked with the full URL.
- **Implements:** the requirement ID(s) this issue implements (`PRD-NNN-R1`;
  comma-separate multiple). For the epic, list the PRD ID itself.
- **ADR:** the ADR ID(s) constraining this work. Omit the `· **ADR:** ...`
  segment only when the plan genuinely has no ADRs (`adrs: []`).

## Doc → Issue (sync points)

Execution state flows back into documents **only** at the defined sync points:

- At `/comb` materialization, the PRD frontmatter gets `milestone:` (the GitHub
  **milestone number**, captured from the milestone-create API response — not
  an issue number) and `epic_issue:` (the epic's issue number), and PRD
  `status:` becomes `planned`. Each plan task gets its `issue:` number written
  back into `plan.yaml` immediately after creation.
- At `/swarm` completion, PRD `status:` becomes `implemented`.

Never mirror per-task progress, PR state, or labels into documents anywhere
else.

## ID allocation

- To allocate a new ID, glob the target doc directory for the pattern and take
  the next free number: e.g. for a new ADR, glob `docs/adr/ADR-*.md`, find the
  highest `NNNN`, use highest + 1. Same procedure for `docs/prd/PRD-*.md`,
  `docs/research/RES-*.md`, `docs/plans/PLAN-*.yaml`.
- PRD/RES/PLAN use three digits (`PRD-001`), ADRs use four (`ADR-0001`).
  Zero-pad accordingly.
- IDs are **append-only and never reused** — a deleted or abandoned doc's
  number stays retired forever.

## ADR reference lifecycle

An ADR reference becomes stale **only by supersession, never by deletion**.
Accepted ADRs are never edited or removed; a new ADR with
`supersedes: ADR-NNNN` replaces it, and the old ADR's `status:` becomes
`superseded`. Links to a superseded ADR remain valid history — readers follow
the supersession chain forward.
