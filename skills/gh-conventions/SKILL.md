---
name: gh-conventions
description: Exact gh commands for the Hive lifecycle — milestones via the REST API, epic/task creation with native types (org repos) or type:* label fallback (user repos) and dependencies, DAG reads, issue/PR number capture, and the branch/PR/squash-merge flow. Load whenever creating or editing milestones, issues, or PRs for hive:managed work.
---

# gh conventions

Exact `gh` commands for this system. Verified against **gh 2.96.0** — do not
substitute flags from memory. Ground rule: all `gh` automation reads state via
`--json`; the single sanctioned exception is documented below (issue/PR number
capture). All issues created by the system carry the `hive:managed` label.

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
