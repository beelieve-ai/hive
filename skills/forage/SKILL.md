---
name: forage
description: "Run the research phase of the Hive lifecycle for one PRD. Invoke as /hive:forage <PRD-id> (e.g. /hive:forage PRD-003). Extracts the PRD's open questions, dispatches scout agents in parallel per independent question cluster, persists their findings as docs/research/RES-NNN docs, and links the RES ids into the PRD frontmatter. Gate: every research doc reaches status: answered."
disable-model-invocation: true
---

# /hive:forage — research a PRD's open questions

You are the orchestrator. Scouts do the research; **you** persist their
findings — scouts are read-only and never write files. You never emit the
old spec names for this phase; the command is `/hive:forage`, the agent is
`hive:scout`.

## 1. Resolve the PRD

**First action:** load the `hive:research-method` skill via the Skill tool.
It is the single source of truth for the method, and every pointer below
assumes it is in context. It is not invocation-disabled; forage runs in the
main thread, so this works standalone and under `/hive:bumble` alike.

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

Derive the questions per `research-method` §1 — two mandatory sources: the
PRD's **Open Questions** verbatim, and implicit gaps found while reading the
requirements. Inline reminder: settlement records are never researchable —
see research-method §1.

Forage-specific actions on top of the method:

- **Gaps you surface**: make each explicit and **append it to the PRD's Open
  Questions section now** — the PRD stays the source of truth.
- Drop questions already answered by previously linked RES docs (step 1.3).
- **Re-run ownership**: a question still owned by a linked `open` RES doc
  routes back into that same doc (steps 1.3, 3, 5) — never a new RES id.
- If no open questions remain, report that the PRD needs no foraging and
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

## 4. Dispatch scouts

Spawn one **scout** subagent per cluster with the Agent tool (subagent_type
`hive:scout`). For independent clusters, spawn **all of them in parallel in one
single message** (multiple Agent calls in the same message) — never
serialize independent clusters.

Each scout's prompt must contain:

- The PRD id and repo-relative path.
- The cluster's questions, **verbatim**, as a numbered list.
- Pointers to the relevant `### R<n>` requirement anchors and any repo
  context that matters for this cluster (related `docs/adr/`,
  `docs/research/`, `CONTEXT.md` if present, prior findings for dependent
  clusters).
- A slim contract reminder — the scout's own prompt and its auto-loaded
  `research-method` skill already carry the method, so remind only:
  read-only; return the structured summary the contract defines — per
  question tagged Evidence, a Confidence rating per answer, and Assumptions
  Log entries for any `[ASSUMED]` claims.

**Do not include your expected answer in the scout prompt** — give questions
and context only. A leading answer biases the research.

## 5. Persist the findings (orchestrator writes the files)

For each scout reply, write one research doc from
the `hive:research-method` **Template**. **Exception — cluster bound to an existing
`open` RES doc (step 3): update that doc in place instead.** Keep its id
and filename; merge the new findings, evidence, and answers into its
existing `## Q<n>` sections (append new `## Q<n>` sections only for
questions the doc did not already carry). **Merges are append/update-only:
preserve every existing acceptance marker** (`— accepted YYYY-MM-DD by
human|yolo`) in the Assumptions Log — remove one only if the human
explicitly reopens that assumption. Then re-evaluate its status per 5.3
below — flip it to `answered` only when **every** question in the doc now
meets the done criterion. Never allocate a new RES id for questions an
existing linked doc already owns.

For each new cluster:

1. **Allocate the ID** per crosslinking rules: glob
   `docs/research/RES-*.md`, take the highest `NNN` + 1, zero-padded to
   three digits. Append-only, never reused. Allocate at write time, one
   doc after another.
2. Write `docs/research/RES-NNN-<slug>.md` (slug from the cluster topic)
   from the `research-method` **Template**: frontmatter `id`, `prd` (bare
   PRD id), `status`, `questions` (the verbatim list), `created` (today).
   Body: one `## Q<n>` section per question with `### Findings`,
   `### Evidence` (provenance-tagged citations —
   `[VERIFIED: <source>]`/`[CITED: <url>]`/`[ASSUMED]`), and `### Answer`
   (carrying its
   `**Confidence:** HIGH | MEDIUM | LOW`), plus the doc-level
   `## Assumptions Log` (one `A<n>` bullet per `[ASSUMED]` claim, or
   "None."). Include a body reference to the PRD by ID **and** repo-relative
   link (e.g. `[PRD-003](../prd/PRD-003-slug.md)`).
3. **Set the status honestly.** `status: answered` only if **every**
   question in the doc meets the done criterion of `research-method`: a
   sourced answer backed by evidence, or an explicit "unknowable now"
   stating why and what would resolve it. Otherwise `status: open`.
4. **Spot-check before persisting — do not trust the report.** Before a doc
   is written, verify the scout's citations resolve, as **existence checks
   that pull no file content into context**:
   - Every question carries **at least one** Evidence citation.
   - A cited file exists — check with Glob.
   - When a citation names a symbol or string, Grep for it **in that file**
     with the output mode set to matching file paths only, never content.
   - Bare line numbers are accepted once the file exists.
   - ADR/RES ids resolve via Glob.
   - Web citations get a **specificity look** (a real page, not a site
     root) — never a fetch.
   A non-resolving citation is treated like a dropped question: fold it into
   the single re-dispatch below (5.5). No new retry loop.
5. If a scout dropped, merged away, or half-answered a question — or a
   citation failed the 5.4 spot-check — re-dispatch that scout **once** with
   only the missing questions and merge the result. Still incomplete
   afterwards → persist the doc as `status: open`. **Never fabricate an
   answer or flip a status to force the gate.**

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
  PRD's Open Questions with a reference to their RES doc, so `/hive:waggle`
  and `/hive:comb` see them.

## 8. Commit

Sync local main first per the `gh-conventions` skill
(`git switch main && git pull --ff-only origin main` before any commit on
main — after any prior squash-merge, local main is stale).

Audit the `res-answered` log, **deduping on event + subject only** (the
`res-answered` event and the RES id — not the detail). For every RES doc in
the PRD's `research:` list now at `status: answered` whose event + subject
entry the audit log does not yet carry, append (or recover, on re-run) one
line per the colony `Audit log` section — **exactly one `res-answered` line
per answered doc**; never a line for an assumption acceptance alone. Derive
its detail from the doc's acceptance markers: `accepted: A1, A2` for the
`A<n>` ids accepted at the flip, else `—` (a doc with A1 accepted but A2
still open stays `open` and gets no line). Deriving from the docs, not from
what "this run" did, means an interrupted run's missing entry is recovered
on re-run and nothing is double-logged; no doc flipped means the audit log
is not touched (never create an empty one). Then commit the new/updated
research docs, the PRD, and the audit log when touched, together
(Conventional Commits), e.g.:

```
docs(research): add RES-004, RES-005 for PRD-003
```

Then push (`git push origin main`). Do not commit unrelated files. No
`gh` calls happen in this command — nothing touches GitHub issues here.

## 9. Gate: research docs `status: answered`

Verify **every RES doc listed in the PRD's `research:` frontmatter** — not
only the docs created or updated in this run — carries `status: answered`.
A doc may not be `answered` while any question relies on an unaccepted
`[ASSUMED]` claim (per the `research-method` done criterion — not restated
here). Resolve that reliance through the acceptance flow below before
judging the gate.

### 9.1 Assumption acceptance

At forage entry, **snapshot** the unaccepted `A<n>` ids of every linked
`open` RES doc — the assumptions that pre-date this run. This snapshot
scopes `--yolo` auto-acceptance, mirroring bumble's ADR-snapshot discipline.

For each unaccepted assumption a blocked doc relies on:

- **Interactive, or a snapshotted (pre-existing) id under `--yolo`:** pose
  **one AskUserQuestion per assumption** — options `Keep open — I'll resolve
  it (Recommended)` first, then `Accept assumption`. Snapshot ids **always**
  go to the human, even under `--yolo`.
- **`/hive:bumble --yolo`, id introduced during this run (not in the
  snapshot):** auto-accept — **no question is posed**, and the yolo answer
  is **`Accept assumption`**, deliberately NOT the human-recommended
  `Keep open` option (unlike the other yolo gates, which take the
  recommendation). Mark it `by yolo` and list it in the run report.

**On Accept (human or yolo):** edit the doc — write the acceptance marker
(`— accepted YYYY-MM-DD by human|yolo`) on that `A<n>`, and flip
`status: answered` only if the whole done criterion now holds. **Commit +
push the marker edit regardless of whether the doc flips** — the marker is
the sole provenance record while the doc stays `open`. When the doc **does**
flip in that same edit, its single `res-answered` audit line (step 8,
`by: human|yolo`, detail `accepted: …`) joins that commit. Then re-evaluate
the gate.

**On Keep-open, or headless without `--yolo`:** report the gate is unmet,
naming the blocking assumptions, and stop.

### 9.2 Report

- **All answered** → the gate is met. Report a summary table (`RES id →
  topic → questions → status`) with a **worst-confidence-per-doc** column
  (legacy docs without ratings show `—`), explicitly listing any "unknowable
  now" results (they satisfy the done criterion but the user must know they
  exist), **all LOW-confidence answers**, the **combined Assumptions Log
  entries**, and any questions deferred in step 6. Tell the user the PRD is
  ready for `/hive:waggle` / `/hive:comb`.
- **Any doc still `open`** → the gate is **not** met. Report exactly which
  questions remain unanswered (and which assumptions were kept open) and
  why, and stop. The user resolves them (decision, access, experiment) and
  re-runs `/hive:forage $ARGUMENTS`; a re-run skips already-answered
  questions (step 2) and merges residual answers back into the still-`open`
  doc that owns them (steps 3 and 5) until it can honestly flip to
  `answered`. Never auto-accept (outside the `--yolo` snapshot scope) or
  skip the gate.
