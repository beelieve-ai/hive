---
name: gh-conventions
description: Exact gh commands for the Hive lifecycle — milestones via the REST API, epic/task creation with native types (org repos) or type:* label fallback (user repos) and dependencies, DAG reads, issue/PR number capture, the branch/PR/squash-merge flow, and the doc commit flow every Hive command uses to persist lifecycle documents. Load whenever creating or editing milestones, issues, or PRs for hive:managed work, or committing lifecycle docs.
---

# gh conventions

Exact `gh` commands for this system. Verified against **gh 2.96.0** — do not
substitute flags from memory. Ground rule: all `gh` automation reads state via
`--json`; the single sanctioned exception is documented below (issue/PR number
capture). All issues created by the system carry the `hive:managed` label —
sole exception: the **glossary-gaps tracker** (see its section below), which
deliberately omits it so `/hive:swarm` ignores the issue.

## Resolving the current repo (portability)

The Hive runs against **whatever repo the session is in** — never a hardcoded
one. `gh api repos/{owner}/{repo}/...` auto-fills `{owner}`/`{repo}` from the
current repo, so those templates are already repo-agnostic. When you need the
owner/repo and default branch as literals (e.g. to build absolute
`blob` URLs for issue-body links, per `hive:crosslinking`), resolve them once:

```bash
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
branch=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
branch=${branch:-$(git symbolic-ref --short HEAD)}   # fall back to the local
                                                     # branch before first push,
                                                     # when GitHub has no default yet
# -> $repo (<owner>/<repo>) and $branch (<default-branch>)
```

Then form links as
`https://github.com/<owner>/<repo>/blob/<default-branch>/<path>`. The
`defaultBranchRef` fallback matters only on a brand-new repo with nothing pushed
— by the time `/hive:comb` links to docs it has already pushed them, so the
default branch resolves — but it keeps the URL well-formed either way.

## Milestones (REST API only — no native `gh milestone` command)

### Create

```bash
gh api repos/{owner}/{repo}/milestones -f title="<milestone title>"
```

Capture **`.number`** from the POST response (e.g. append `--jq .number`).
This is a **milestone number**, a separate numbering space from issue numbers —
never confuse the two. The milestone number is what the PRD frontmatter's
`milestones:` entry stores in its `milestone:` field (schema in
`hive:writing-prds`) and what every PATCH targets:

```bash
gh api repos/{owner}/{repo}/milestones/<milestone-number> -X PATCH ...
```

### Update the description (read-modify-write — never blind-overwrite)

Milestone descriptions accumulate marker lines (e.g. `plan-review: passed
(PLAN-NNN)`) and the **provenance mirror block** `/hive:comb` stamps at
creation:

```
prd: PRD-NNN
plan: PLAN-NNN
```

The mirror is human-facing provenance only — the authoritative
PRD→milestone link is the PRD frontmatter's `milestones:` list, and nothing
ever parses the mirror for scheduling. A blind PATCH with only the new text
would destroy existing content. Always:

1. GET the current description:
   `gh api repos/{owner}/{repo}/milestones/<number> --jq .description`
2. Append or modify the line in the fetched text.
3. PATCH the full result back:
   `gh api repos/{owner}/{repo}/milestones/<number> -X PATCH -f description="<full updated text>"`

### Lookup by title or number

Users may pass either. List all milestones (open **and** closed) with
pagination and match locally:

```bash
gh api "repos/{owner}/{repo}/milestones?state=all" --paginate
```

Match the argument against `.title` (exact) or `.number`. Fail loudly on zero
or multiple matches.

## Issues

### Issue-type mode (probe once before the first create)

Custom issue types only exist on **organization** repos. Probe:

```bash
gh api repos/{owner}/{repo} --jq .owner.type
```

- `Organization` → verify the org exposes the **Epic** and **Task** types:
  `gh api orgs/{owner}/issue-types --jq '.[].name'` (verified live on
  `beelieve-ai`). Both present → **native mode**: create with `--type Epic`
  / `--type Task`. Either missing → fall back to **label mode** and note it.
- `User` → **label mode**: omit `--type`; add `type:epic` / `type:task` to
  the `--label` list instead.

Reads are mode-agnostic — filter on `issueType` **OR** the `type:*` label —
so only the write path needs the probe.

### Ensure labels exist (before the first create)

A fresh repo has no labels; `gh issue create --label` fails on missing ones.
Ensure idempotently (`--force` updates instead of erroring on existing):

```bash
gh label create hive:managed --force
gh label create phase:build --force
gh label create phase:review --force
gh label create hive:parked --force
# label mode only:
gh label create type:epic --force
gh label create type:task --force
```

### Create an epic

```bash
# native mode
gh issue create --title "..." --body "..." --milestone "<milestone title>" --label hive:managed --type Epic
# label mode
gh issue create --title "..." --body "..." --milestone "<milestone title>" --label hive:managed,type:epic
```

Note: `--milestone` on `gh issue create` takes the **title**, not the number.
Both the label and the milestone are load-bearing — `/hive:swarm` discovers the epic
by filtering on them.

### Create a task

```bash
# native mode
gh issue create --title "..." --body "..." --milestone "<milestone title>" --parent <epic#> --blocked-by <n1>,<n2> --label phase:build,hive:managed --type Task
# label mode
gh issue create --title "..." --body "..." --milestone "<milestone title>" --parent <epic#> --blocked-by <n1>,<n2> --label phase:build,hive:managed,type:task
```

Create tasks in **topological order** (dependencies first) so every
`--blocked-by` value references an already-existing issue number. Omit
`--blocked-by` entirely for tasks with no dependencies.

Bodies are always multiline — pass them with `--body-file <file>` (write
the body to a temp file first) instead of `--body "..."`, which corrupts
under shell quoting. Stdout stays the same single-URL line.

### Edit dependencies / parent

```bash
gh issue edit <N> --add-blocked-by <M>
gh issue edit <N> --parent <epic#>
```

The parent flag on `gh issue edit` is **`--parent`** — there is no
`--set-parent` flag (verified against gh 2.96.0; do not use it, it will error).

### Read the DAG (the full /hive:swarm field set)

```bash
gh issue list --milestone "<milestone title>" --state all --json number,title,state,blockedBy,blocking,parent,issueType,labels
```

All eight fields are required: epic discovery needs `issueType` + `labels`,
task-set filtering needs `parent`, unblocking-most-first selection needs
`blocking`, and readiness needs `state` + `blockedBy`.

**Epic test** (mode-agnostic): `issueType.name == "Epic"` **OR** labels
contain `type:epic`. **Task test**: `issueType.name == "Task"` **OR** labels
contain `type:task`. In label mode `issueType` is simply `null` — the field
still exists in the JSON, so requesting it never fails.

Shape caveat (verified live): `blockedBy` and `blocking` are **nested
objects** `{"nodes": [{number, state, ...}], "totalCount": N}`, not flat
arrays — on both `gh issue list` and `gh issue view`. Read blocker numbers
with `.blockedBy.nodes[].number`; a naive `.blockedBy[].number` jq fails.
`parent` is an object (`.parent.number`) or null.

## Issue/PR number capture (the one sanctioned --json exception)

`gh issue create` and `gh pr create` have **no `--json` flag**. Their
non-interactive stdout is a single URL — capture the new number from it:

1. Run the create command, capture stdout.
2. Strict-parse: exactly one match of `/issues/<number>` (for issues) or
   `/pull/<number>` (for PRs) at the end of a URL. **Fail on no match and fail
   on multiple matches** — never guess, never take "the last number".
3. Verify the created object via `--json` before relying on the number:

```bash
gh issue view <n> --json number,title,issueType,milestone,parent,labels,blockedBy
```

Confirm type (native mode) or `type:*` label (label mode), milestone, parent,
labels, and blockedBy all match what was requested. This exception applies **only** to number capture from these two
create commands; every other read stays `--json`.

## Glossary-gaps tracker issue (the one non-managed system issue)

`/hive:comb` maintains at most **one** tracker issue per PRD for glossary
terms flagged by architects but not yet settled in root `CONTEXT.md`. It is
a reminder, not work for the build loop, hence its deliberate exceptions:

- **Title (the dedup key)**: exactly `Glossary gaps: <PRD-ID>` (e.g.
  `Glossary gaps: PRD-003`). Never vary it — lookup is by exact title.
- **Labels**: `glossary` only — ensure it exists first
  (`gh label create glossary --force`). **No `hive:managed`** (the
  documented exception to the ground rule above: an unparented
  `hive:managed` issue in a milestone makes `/hive:swarm` abort) and no
  `type:*` label — the tracker is neither epic nor task.
- **Milestone**: the PRD's milestone.
- **Lookup before create** — across open AND closed issues:
  `gh issue list --milestone "<milestone title>" --state all --label glossary --json number,title,state`,
  match the exact issue title. Multiple matches → abort and report.
- **Body**: one markdown checklist line per unresolved term —
  `- [ ] <Term> — <one-line why>`. On re-runs, **replace the body** with
  the current unresolved set and add one comment noting the delta (terms
  added/resolved since last run); skip the comment when nothing changed.
- **Term matching is normalized**: compare terms case-insensitively,
  whitespace-trimmed, singular/plural folded — applied identically to
  audit-parsed terms and `CONTEXT.md` `## <Term>` headings, so case or
  plural drift never duplicates a checklist item.
- **Lifecycle**: closed tracker but unresolved terms remain → **reopen**
  it (`gh issue reopen <n>`) and update; unresolved set empty → close it
  (`gh issue close <n>`). Humans may also close it manually; the next
  comb run corrects state either way.

## Doc commit flow (lifecycle documents)

How every Hive command persists lifecycle docs (`docs/**`, plus riders like
`CONTEXT.md`, `ARCHITECTURE.md`, the root `CLAUDE.md` import line, and audit
logs). **Hive never pushes directly to the default branch** — doc changes
reach it only through a squash-merged PR. This flow is doc-shaped; do not
copy the issue flow below verbatim (different branch names, no `Closes #N`
footer, different merge rules).

### Where to commit (decide once per commit point)

1. **On the default branch** → create a doc branch and work there:
   `git switch -c docs/<primary-artifact-id>-<slug>` (e.g.
   `docs/PRD-004-checkout`, `docs/PLAN-007-materialize` for a write-back).
   One branch per command run — later commits of the same run reuse it.
2. **On a doc-intended non-default branch** → commit there; merging is the
   user's business (the dedicated-branch workflow). Doc-intended = the
   branch already carries Hive doc commits (its history since diverging
   from the default touches `docs/`), or the user confirmed it this
   session. Push only if the branch tracks a remote.
3. **On any other non-default branch** (a worker `issue/*` branch, an
   unrelated feature branch) → ask via **AskUserQuestion**, once per branch
   per session: commit lifecycle docs here, or branch off the default
   instead (option 1)? Remember the answer for the session. Lifecycle docs
   never mix into unrelated branches silently.

### Two variants (only case 1 creates a PR)

- **Authored artifact** — new or edited PRD / RES / ADR / plan content and
  its riders. Commit (Conventional Commits), push
  (`git push -u origin <doc-branch>`), open the PR
  (`gh pr create --fill` — no `Closes` footer; body names the artifact
  ids). **Merge consent rides the human gates, never a new blanket rule**:
  - Interactive runs: ask via **AskUserQuestion** — "Merge now
    (Recommended)" (squash-merge, then the mandatory main sync) or "Leave
    open for review" (report the PR URL; **stay on the doc branch** so
    dependent commands stack on it). A command whose gate already approved
    exactly this content (e.g. comb's plan approval) merges without a
    second ask.
  - `/hive:bumble --yolo`: auto-merge only PRs recording gate verdicts the
    carve-out covers, for artifacts created during that run. Headless
    without `--yolo`: never merge — leave the PR open and report it,
    exactly as gates never auto-approve.
- **Write-back** — mechanical bookkeeping only (issue numbers, status
  flips, audit entries). Same branching, then PR + **immediate
  auto-squash-merge, no ask**, any mode. A blocked merge → classify per
  Merge failures below, stop, and hand the user the PR URL.

### ID-collision check (before any Hive-driven merge)

IDs are minted by globbing the local checkout, so two parallel branches can
mint the same `ADR-0010` without a git conflict. Before merging **any doc
PR that introduces a lifecycle artifact file** (`docs/prd/PRD-*`,
`docs/research/RES-*`, `docs/adr/ADR-*`, `docs/plans/PLAN-*`) — authored or
write-back-labelled alike (e.g. comb's Decline PR carries a new plan):

1. `git fetch origin <default-branch>`, then list the artifact directory on
   the remote default (e.g. `git ls-tree --name-only origin/<default-branch> docs/adr/`).
2. If the new file's ID already exists there under a different file,
   renumber before merging: rename the file to the next free ID and update
   the frontmatter `id:` and **every** reference to the old ID on the
   branch (docs, audit lines, plan fields).

After every squash-merge, the mandatory main sync below applies.

## Branch / PR flow

One issue = one branch = one squash-merged PR.

1. **Start from fresh main** (see sync rule below), then:
   `git switch -c issue/<n>-<slug>`
2. Implement, run the issue's verification command, commit
   (Conventional Commits).
3. Push — `gh pr create` needs a pushed branch in non-interactive use:
   `git push -u origin issue/<n>-<slug>`
4. Create the PR:
   `gh pr create --fill --body "Closes #<n>"`
   (`--body` overrides the fill body; the title still comes from the commits.
   `Closes #<n>` auto-closes the issue on merge.)
5. Merge:
   `gh pr merge --squash --delete-branch`
6. **Sync local main — mandatory after EVERY squash-merge:**

```bash
git switch main && git pull --ff-only origin main
```

`gh pr merge` does not update local main. After a squash-merge, local main is
**always stale**; skipping the sync makes the next branch build on an old tree
and blocks any later push from main. Run the sync before cutting the next
branch and before any commit on main — no exceptions.

## Merge failures

If `gh pr merge` fails: never mark the task as done, never close the issue
manually, never bypass the failure. **Classify the blocker before reacting**:

```bash
gh pr view <pr#> --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup
```

- **Agent-fixable** — `mergeable: CONFLICTING` (conflicts),
  `mergeStateStatus: BEHIND` (stale base), or failed entries in
  `statusCheckRollup` → eligible for `/hive:swarm`'s merge-blocker protocol
  (merge-fix worker rounds).
- **Pending** — rollup entries still queued/in progress → poll (~60s
  interval, 10-minute budget) and re-classify once settled. An **empty**
  rollup means no checks are configured — that is green, not pending.
- **Structurally unresolvable** — `reviewDecision: REVIEW_REQUIRED` or
  `CHANGES_REQUESTED` (a human approval gate), `mergeStateStatus: BLOCKED`
  with green checks (a protection rule no agent can satisfy), permission
  errors from `gh`, or a draft PR → escalate to the human immediately with
  the PR URL and the classified reason.
- **Unknown** — `mergeable: UNKNOWN` or API errors → re-poll once after a
  short wait; still unknown → treat as structurally unresolvable.

Failing-check logs for a worker briefing: GitHub Actions checks via
`gh run view <run-id> --log-failed`; other checks → pass the details URL;
no retrievable log → the worker re-runs the task's Verification command
locally and diagnoses from that output.
