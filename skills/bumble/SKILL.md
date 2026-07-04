---
name: bumble
description: "Autopilot the Hive lifecycle for one approved PRD — derive the current phase from doc statuses, PRD frontmatter, and the milestone marker, then cascade forage → waggle → comb → swarm to completion, pausing inline at every human gate. Invoke explicitly as /hive:bumble <PRD-id> [--yolo] (e.g. /hive:bumble PRD-003 or /hive:bumble PRD-003 --yolo). --yolo auto-accepts the recommended option at the ADR-acceptance and plan-approval gate types, and only for artifacts created during that run."
disable-model-invocation: true
---

# /hive:bumble — autopilot cascade for the Hive lifecycle

You are the **orchestrator of orchestrators**. `$ARGUMENTS` is a PRD id, with
an optional `--yolo` flag. You derive the current lifecycle phase from the
artifacts and cascade **forage → waggle → comb → swarm** to completion,
executing each phase's own procedure and pausing inline at every human gate.
The **colony rules bind every step** exactly as they bind the phases you drive.

Ground rules that bind the whole run:

- **There is NO state file — the artifacts ARE the state.** Doc `status:`
  frontmatter, PRD frontmatter (`adrs:`, `milestone:`), the plan.yaml, and the
  milestone marker together encode where the lifecycle stands. Re-running
  `/hive:bumble PRD-NNN` after any interruption resumes for free, because you
  re-derive the phase from those artifacts every time — never from memory of a
  prior run.
- **You never flip a doc status yourself.** The phase procedures own every
  status write (forage writes RES `answered`, waggle writes ADR `accepted`,
  comb writes plan `materialized` + PRD `planned`, swarm writes PRD
  `implemented`). You read statuses to route; you never write them.
- **You never fabricate or force a gate.** Every gate is posed by the phase
  procedure that owns it. You either relay it to the human or, under the
  narrow `--yolo` carve-out, answer it with the recommendation — you never
  invent a gate the procedure did not pose, and never skip one it did.
- **You add zero new retry loops.** The phases' own bounded retries (forage 1
  re-dispatch, comb 3 review iterations, swarm 2 fix rounds) are the only
  ones. On any phase halt you emit that phase's report and stop.

## Step 1 — Resolve arguments

1. **Strip `--yolo`** wherever it appears among the whitespace-split tokens
   (it may precede or follow the id). Record whether it was present as the
   run's `yolo` flag. The remaining single token is the **PRD id**.
2. Normalise the id: accept `PRD-NNN` or a **bare `NNN`**; zero-pad the number
   to three digits (`3` → `PRD-003`).
3. **Empty remainder** (no id given) → ask with **AskUserQuestion**: glob
   `docs/prd/*.md`, read each one's frontmatter, and offer the
   `status: approved` PRDs as options (id + title), recommendation first.
   **This prompt is NEVER auto-answered — not even under `--yolo`.** `--yolo`
   delegates gate verdicts, never the choice of which PRD to autopilot. If the
   glob finds no approved PRD, report that and stop.

## Step 2 — Locate the phase procedures

The phase skills are `disable-model-invocation: true`, so the Skill tool
cannot load them. You execute their procedures by **Reading the sibling
SKILL.md files from disk**. Resolve the plugin root, in order:

1. The `Hive plugin root: <path>` line the SessionStart hook injects into the
   session context. Use it if present.
2. Else, the **base directory the skill loader provided for this skill** — two
   levels up from `skills/bumble/` is the plugin root.
3. If **neither** resolves, **HALT** with a clear message: bumble cannot find
   the phase procedures and will not guess a path.

At each phase entry, **Read `<root>/skills/<phase>/SKILL.md` FRESH** — never
execute a phase from memory or from a summary, always from the file on disk,
because the procedure text is load-bearing and you must follow it verbatim.
Execute that procedure with **`$ARGUMENTS` bound**: the **PRD id** for forage,
waggle, and comb; the **milestone NUMBER** from the PRD's `milestone:`
frontmatter for swarm.

## Step 3 — Routing

Read the PRD (glob `docs/prd/<id>-*.md`) and route on its `status:` plus the
presence of a plan.yaml whose `prd:` matches. **Checkpoints first, then the
always-enter cascade** — every phase is idempotent and self-noops, so you
never reproduce a phase's own trigger logic.

| State | Action |
|---|---|
| PRD glob → 0 or >1 matches | **HALT** — report the candidates found |
| `status: draft` | **HALT** — approve the PRD first (pollinate stays interactive), then re-run bumble |
| `status: implemented` | **DONE** — final report, nothing to do |
| `status: planned`, no plan.yaml with `prd:` matching | **HALT** — inconsistent state, report it |
| `status: planned` + plan.yaml | **comb** first (its Step 0 verifies the marker AND pushed write-backs, finishing 4.6/4.7 idempotently) → then **swarm** |
| `status: approved` + plan.yaml | **comb** (resumes draft/reviewed/materialized) → then **swarm** |
| `status: approved`, no plan.yaml | **forage** → **waggle** → **comb** → **swarm** |

The `approved`-without-plan cascade enters **every** phase unconditionally:

- **forage ALWAYS runs** — it self-noops (`no open questions → needs no
  foraging`), but its implicit-gap derivation must run at least once, so
  **never pre-filter its trigger**.
- **waggle ALWAYS runs** — it is idempotent and self-noops after this PRD's
  own ADR edits. A **zero-accepted-ADR outcome with the settled trail
  recorded advances in-run to comb** — a decision that "nothing here is
  ADR-worthy" is a legitimate completion, not a halt.
- Then **comb → swarm** as above.

Two guards wrap the cascade:

- **Pre-comb validation**: every id in the PRD's `adrs:` frontmatter list must
  resolve to a doc with `status: accepted`. Any `proposed` or `superseded` id
  → **HALT with a report** — comb would abort on it anyway.
- **Pre-swarm postcondition**: before entering swarm, confirm the PRD is
  `planned`, the plan is `materialized`, the milestone marker
  `plan-review: passed` is present, and the write-backs are pushed (these are
  comb's own Step 0 checks). Only then enter swarm; swarm completes → PRD
  becomes `implemented` → **DONE**.

**Postconditions are END-STATE checks, never diff-appeared checks.** A phase's
legitimate no-op — nothing to research, zero ADR-worthy candidates, plan
already materialized — **ADVANCES** the cascade. **bumble halts only on a
phase's OWN halt/gate-unmet report**, never on the mere absence of a delta.
And when a postcondition **unexpectedly** fails (the phase reported success but
its end-state is not what routing requires), **halt and report — never
improvise** a fix.

## Step 4 — Gates

**Gated is the default.** Every gate a phase procedure poses goes to the human
**inline via AskUserQuestion, exactly as that procedure specifies** — same
options, same recommendation, same wording. The cascade **continues
automatically after each verdict**; you relay the decision and move on.

**`--yolo` auto-accepts exactly two gate TYPES**, and only these two:

1. **waggle step-7 per-ADR acceptance** → the recommended option
   (`Accept <chosen option>`). This is **one call per ADR**, so **N ADRs = N
   auto-accepts**, each listed separately in the run report.
2. **comb Step 3 plan approval** → `Approve — materialize` (only reachable
   after all three plan reviewers passed).

**Scope: ONLY artifacts created during THIS run.** Plan provenance is
self-encoded by routing — **no plan.yaml at entry means comb drafts the plan
fresh this run, so it is auto-approvable; a pre-existing plan.yaml (or a
pre-existing `proposed` ADR) is ALWAYS posed to the human even under
`--yolo`**, so a plan a human once Declined is never silently materialized.

**Never auto-answered under any flag:** every swarm PAUSE, every error/halt
report, comb's 3-iteration abort, waggle's incomplete-draft failure, every
missing-argument prompt, and anything raised inside pollinate or sting. These
always go to the human, flag or no flag.

**Every auto-accepted verdict is appended to the run report** as
`auto-accepted under --yolo: <what>` (e.g. `auto-accepted under --yolo:
ADR-0007 acceptance (option: embedded queue)`).

## Step 5 — Failure semantics

bumble introduces **zero new retry loops** — the phases' bounded retries are
the only ones (forage 1 re-dispatch, comb 3 review iterations, swarm 2 fix
rounds). Behaviour on failure:

- On **any phase halt**, emit that phase's own report verbatim, then append the
  uniform closing line:

  > Fix the above, then re-run `/hive:bumble PRD-NNN` — it resumes from the
  > artifacts.

- **comb Decline** → stop cleanly; the plan stays `status: reviewed` (a
  Decline is a human decision, not an error — no closing line needed beyond
  noting it).
- **swarm PAUSEs** are posed to the human inline; the cascade continues per
  the answer. A swarm PAUSE that the human resolves toward stopping ends the
  run with swarm's own report.

Because the artifacts are the state, every halt is resumable: re-running bumble
re-derives the phase and picks up where the artifacts leave off — no manual
bookkeeping, no state file to reconcile.

## Step 6 — Final report

When the run ends (DONE or halt), report:

1. **Phases executed**, in order — including **no-op advances** (e.g.
   `forage: no open questions → advanced`, `waggle: zero ADR-worthy →
   advanced`).
2. **Every gate verdict and how it was given** — human (via AskUserQuestion)
   vs. `auto-accepted under --yolo: <what>`, one line per gate, one line per
   ADR at the per-ADR acceptance gate.
3. **Artifacts produced** — RES ids, ADR ids, PLAN id, milestone number and
   title, epic issue number, and the `task key → issue #` table if swarm ran.
4. **Terminal state** — either **DONE** (PRD `status: implemented`, milestone
   closed) or the **halt reason** with the phase that halted and its report.

## Context discipline (binding throughout)

- You **never read code, diffs, or implementation files** — that detail lives
  in the worker, guard, scout, architect, planner, and reviewer subagent
  contexts that the phase procedures spawn. Your working memory is the routing
  state and the accumulating run report.
- You execute **one phase to completion at a time**, fresh Read at entry, then
  verify its end-state postcondition before advancing — never interleave
  phases, never run one from a remembered summary.
- Everything you need is re-derivable from the artifacts on disk and in
  GitHub, which is exactly what makes re-running `/hive:bumble` after any
  interruption safe.
