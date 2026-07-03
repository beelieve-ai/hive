---
name: grilling
description: Relentless one-question-at-a-time requirement interviews. Use when an idea, requirement, or design needs to be sharpened with the user before it is written down — during /hive:pollinate PRD interviews, /hive:sting sessions, or whenever fuzzy intent must become precise, agreed language.
---

# Grilling

> Adapted from mattpocock/skills (MIT License) — https://github.com/mattpocock/skills

Interview the user relentlessly about the idea or design until you reach a
shared understanding. Walk down each branch of the design tree, resolving
dependencies between decisions one by one. Do not start writing the artifact
until the shared-understanding gate below has passed.

## One question at a time — never a form

Ask exactly one question, then wait for the answer before asking the next.
Presenting multiple questions at once is bewildering and lets the user skim
past the hard ones. A numbered list of questions is a form; never send one.

## Every question ships a recommended answer

Each question comes with your concrete recommended answer and a one-line
reason, so the user can accept it with a single word ("yes", "agreed") or
push back. Never ask an open question when you can propose a defensible
default:

> Should a task's verification command run in CI or only locally? I recommend
> locally only for now — there is no CI pipeline yet. OK?

A question without a recommendation offloads the thinking onto the user;
a recommendation with a question invites a decision.

## Chase the decision tree branch by branch

Decisions depend on other decisions. Pick a branch, drill until that branch
is fully resolved, then move to the next. Do not hop between topics — a
half-resolved branch is a branch you will have to reopen. Keep a private
running list of open branches and visibly close each one ("that settles
error handling; next branch: persistence").

## Never ask what the codebase can answer

If a question can be answered by exploring the repository — existing
conventions, file layout, what a function actually does, whether a feature
already exists — do not ask it. Explore the code, then state the finding as
a confirmation instead:

> The `hive:writing-prds` skill already carries the PRD frontmatter schema, so
> I'll assume new PRDs follow its Template — correct?

The user's time is spent only on questions with no objective answer: intent,
priorities, trade-offs, scope.

## Sharpen terms as you go

When the user's language is fuzzy or two words compete for one concept, stop
and resolve the term — that is the `domain-modeling` skill's job. Hand every
sharpened term to it so the canonical choice and its banned near-synonyms
land in the root `CONTEXT.md` glossary the moment the term resolves, not at
the end of the interview. From then on, use only the canonical term.

## Shared-understanding gate

The interview ends only when you play the whole design back to the user in
canonical glossary terms — a compact summary of every resolved decision —
and the user explicitly agrees it is right. No agreement, no artifact. If
the play-back surfaces a mismatch, reopen that branch and grill on.
