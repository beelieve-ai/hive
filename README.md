# Hive 🐝

An AI-driven development lifecycle (AI-DLC) for [beelieve-ai](https://github.com/beelieve-ai), built on Claude Code skills and agents.

**Documents in `docs/` are the source of truth for intent. GitHub Issues are the execution layer.** Every stage transition that matters passes through a human approval gate — nothing is auto-accepted.

## The flow

```
Idea → PRD → Research → ADR → Plan → Build → Review
```

| Stage | Command | Produces | Human gate |
|---|---|---|---|
| Idea → PRD | `/pollinate <idea>` | `docs/prd/PRD-NNN-slug.md` via a one-question-at-a-time grilling interview | PRD approval |
| Research | `/forage <PRD-id>` | `docs/research/RES-NNN-*.md` — scout agents answer the PRD's open questions in parallel | all research docs `status: answered` |
| ADR | `/waggle <PRD-id> [topic]` | `docs/adr/ADR-NNNN-*.md` (MADR 4.0) — one architect agent per worthy decision | ADR acceptance |
| Plan | `/comb <PRD-id>` | `docs/plans/` plan.yaml, reviewed by three parallel plan reviewers, then materialized as a GitHub milestone + epic + task DAG | plan approval before materialization |
| Build + Review | `/swarm <milestone>` | Dependency-ordered execution: worker implements each issue on a branch, guard reviews the diff, PRs are squash-merged | merge failures pause with the PR URL |
| Anytime | `/sting <doc-or-id>` | Sharpens any lifecycle artifact through another grilling interview — doc edits only | every edit individually agreed |

A typical end-to-end run:

```
/pollinate a CLI that syncs labels across repos   # interview → PRD draft → approve it
/forage PRD-001                                   # scouts answer open questions
/waggle PRD-001                                   # decide architecture → accept ADRs
/comb PRD-001                                     # plan → review → approve → issues created
/swarm 1                                          # build the milestone to completion
```

## How execution works

`/comb` turns an approved plan into one **milestone per goal**, with an **Epic issue** and **Task sub-issues** wired together by native GitHub issue dependencies (`blocked by` / `blocking`) — no GitHub Projects. `/swarm` then walks the DAG: for each ready task, a **worker** agent branches from fresh main, implements, and pushes; a read-only **guard** agent reviews the branch against the issue's acceptance criteria and any referenced ADRs; the PR is squash-merged, auto-closing the issue. Issues carry the `hive:managed` label plus a cosmetic `phase:build` / `phase:review` flip.

## Agents

- **scout** — read-only research, spawned per independent question cluster
- **architect** — drafts one ADR per candidate decision
- **planner** — drafts the plan.yaml task DAG
- **plan-reviewer-context / -dag / -sizing** — three parallel read-only plan checks (self-containedness, dependency soundness, task sizing)
- **worker** — implements exactly one task issue per invocation
- **guard** — read-only review verdict on the worker's branch

Reviewers never write; verdict loops belong to the orchestrating command.

## Repository layout

```
docs/
  prd/         PRD-NNN   product requirements
  research/    RES-NNN   research findings
  adr/         ADR-NNNN  architecture decision records (MADR 4.0, append-only)
  plans/       PLAN-NNN  plan.yaml audit trail
  templates/   one template per artifact type
.claude/
  skills/      the /commands above + supporting skills
  agents/      the agents above
  rules/       colony.md — the full conventions
CONTEXT.md     canonical glossary (lazily created by grilling sessions)
```

## Conventions

The full rules — naming, cross-linking, ID allocation, `gh` automation ground rules, branch/PR flow — live in [`.claude/rules/colony.md`](.claude/rules/colony.md) and are auto-loaded into every session. Highlights:

- IDs are append-only and never reused; accepted ADRs are never edited, only superseded via `/waggle`.
- Docs hold intent, issues hold execution state — status is synced between them only at `/comb` materialization and `/swarm` completion.
- All `gh` automation uses `--json` output; new issue/PR numbers are parsed strictly from the creation URL.
- Requires GitHub CLI ≥ 2.94.0 with native issue types, sub-issues, and dependencies.
