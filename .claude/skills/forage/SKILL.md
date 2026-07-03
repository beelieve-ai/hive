---
name: forage
description: "Run the research phase of the Hive lifecycle for one PRD. Invoke as /forage <PRD-id> (e.g. /forage PRD-003). Extracts the PRD's open questions, dispatches scout agents in parallel per independent question cluster, persists their findings as docs/research/RES-NNN docs, and links the RES ids into the PRD frontmatter. Gate: every research doc reaches status: answered."
disable-model-invocation: true
---

# /forage — research a PRD's open questions

You are the orchestrator. Scouts do the research; **you** persist their
findings — scouts are read-only and never write files. You never emit the
old spec names for this phase; the command is `/forage`, the agent is
`scout`.

## 1. Resolve the PRD

`$ARGUMENTS` is the PRD id (`PRD-NNN`; also accept a bare number like `003`
or a direct `docs/prd/...` path).

1. Glob `docs/prd/PRD-*.md` and match `$ARGUMENTS` against filename/id.
   **Fail loudly on zero or multiple matches** — never guess.
2. Read the matched PRD in full: frontmatter, every `### R<n>` requirement
   with its acceptance criteria, and the Open Questions section.
3. If the PRD's `research:` frontmatter already lists RES ids (a re-run),
   read those docs too — questions they already answer are **not**
   re-researched. Note every linked doc still at `status: open` and the
   questions it carries that don't yet meet the done criterion: those
   questions are **owned by that doc**. A re-run routes them back into
   that same doc (steps 3 and 5) — it never allocates a new RES id for
   them, otherwise the old doc would stay `open` forever.
4. If root `CONTEXT.md` exists, read it and use its canonical vocabulary
   throughout.

## 2. Derive the open questions

Two sources, both mandatory (per the `research-method` skill):

- Every entry in the PRD's **Open Questions** section, verbatim.
- **Gaps found while reading the requirements**: anything in an `### R<n>`
  requirement or its acceptance criteria that cannot be implemented or
  verified without information nobody has written down is an implicit open
  question. Make each one explicit and **append it to the PRD's Open
  Questions section now** — the PRD stays the source of truth.

Drop questions already answered by previously linked RES docs (step 1.3).
If no open questions remain, report that the PRD needs no foraging and
stop — do not create empty research docs.

## 3. Cluster the questions

Group related questions into clusters; each cluster becomes one scout
assignment and one RES doc. **Re-run exception:** the unanswered
questions of each previously linked, still-`open` RES doc (step 1.3)
form their own cluster, **bound to that existing doc** — do not mix
them into a new-doc cluster. That cluster's scout also gets the doc's
current content (partial findings, evidence) so the research continues
instead of restarting. Clusters are **independent** when no cluster
needs another cluster's answers to be researchable. If a genuine dependency
exists, order those clusters sequentially and feed the earlier findings
into the later scout's context; everything else runs in parallel.

## 4. Dispatch scouts

Spawn one **scout** subagent per cluster with the Agent tool (agent name
`scout`). For independent clusters, spawn **all of them in parallel in one
single message** (multiple Agent calls in the same message) — never
serialize independent clusters.

Each scout's prompt must contain:

- The PRD id and repo-relative path.
- The cluster's questions, **verbatim**, as a numbered list.
- Pointers to the relevant `### R<n>` requirement anchors and any repo
  context that matters for this cluster (related `docs/adr/`,
  `docs/research/`, `CONTEXT.md` if present, prior findings for dependent
  clusters).
- A reminder of the contract: read-only; follow `research-method`
  (codebase → prior docs/ADRs → web, evidence-cited); return a structured
  summary with, per question, the question verbatim, the answer (or an
  explicit "unknowable now" with why and what would resolve it), and the
  evidence citations; flag any implicit questions surfaced outside the
  cluster.

## 5. Persist the findings (orchestrator writes the files)

For each scout reply, write one research doc from
`docs/templates/research.md`. **Exception — cluster bound to an existing
`open` RES doc (step 3): update that doc in place instead.** Keep its id
and filename; merge the new findings, evidence, and answers into its
existing `## Q<n>` sections (append new `## Q<n>` sections only for
questions the doc did not already carry); then re-evaluate its status
per 5.3 below — flip it to `answered` only when **every** question in
the doc now meets the done criterion. Never allocate a new RES id for
questions an existing linked doc already owns.

For each new cluster:

1. **Allocate the ID** per crosslinking rules: glob
   `docs/research/RES-*.md`, take the highest `NNN` + 1, zero-padded to
   three digits. Append-only, never reused. Allocate at write time, one
   doc after another.
2. Write `docs/research/RES-NNN-<slug>.md` (slug from the cluster topic):
   frontmatter `id`, `prd` (bare PRD id), `status`, `questions` (the
   verbatim list), `created` (today). Body: one `## Q<n>` section per
   question with `### Findings`, `### Evidence`, `### Answer`, and a body
   reference to the PRD by ID **and** repo-relative link (e.g.
   `[PRD-003](../prd/PRD-003-slug.md)`).
3. **Set the status honestly.** `status: answered` only if **every**
   question in the doc meets the done criterion of `research-method`: a
   sourced answer backed by evidence, or an explicit "unknowable now"
   stating why and what would resolve it. Otherwise `status: open`.
4. If a scout dropped, merged away, or half-answered a question,
   re-dispatch that scout **once** with only the missing questions and
   merge the result. Still incomplete afterwards → persist the doc as
   `status: open`. **Never fabricate an answer or flip a status to force
   the gate.**

## 6. Route surfaced questions

Implicit questions scouts flagged outside their cluster:

- Append them to the PRD's Open Questions section.
- Cluster them and run **one** follow-up scout round (same procedure,
  steps 3–5). Questions surfaced during the follow-up round are appended
  to the PRD but not researched again this run — list them in the final
  report instead of looping forever.

## 7. Link back into the PRD

- Append every new RES id to the PRD's `research:` frontmatter list —
  bare IDs only, no links in YAML.
- "Unknowable now" items that block a requirement must also appear in the
  PRD's Open Questions with a reference to their RES doc, so `/waggle`
  and `/comb` see them.

## 8. Commit

Sync local main first per the `gh-conventions` skill
(`git switch main && git pull --ff-only origin main` before any commit on
main — after any prior squash-merge, local main is stale). Then commit
the new/updated research docs and the PRD (Conventional Commits), e.g.:

```
docs(research): add RES-004, RES-005 for PRD-003
```

Then push (`git push origin main`). Do not commit unrelated files. No
`gh` calls happen in this command — nothing touches GitHub issues here.

## 9. Gate: research docs `status: answered`

Verify **every RES doc listed in the PRD's `research:` frontmatter** —
not only the docs created or updated in this run — carries
`status: answered`.

- **All answered** → the gate is met. Report a summary table
  (`RES id → topic → questions → status`), explicitly listing any
  "unknowable now" results (they satisfy the done criterion but the user
  must know they exist) and any questions deferred in step 6, and tell the
  user the PRD is ready for `/waggle` / `/comb`.
- **Any doc still `open`** → the gate is **not** met. Report exactly which
  questions remain unanswered and why, and stop. The user resolves them
  (decision, access, experiment) and re-runs `/forage $ARGUMENTS`; a
  re-run skips already-answered questions (step 2) and merges residual
  answers back into the still-`open` doc that owns them (steps 3 and 5)
  until it can honestly flip to `answered`. Never auto-accept or skip
  the gate.
