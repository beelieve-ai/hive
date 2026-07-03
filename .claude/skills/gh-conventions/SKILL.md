---
name: gh-conventions
description: Exact gh commands for the Hive lifecycle — milestones via the REST API, epic/task creation with native types and dependencies, DAG reads, issue/PR number capture, and the branch/PR/squash-merge flow. Load whenever creating or editing milestones, issues, or PRs for hive:managed work.
---

# gh conventions

Exact `gh` commands for this system. Verified against **gh 2.96.0** — do not
substitute flags from memory. Ground rule: all `gh` automation reads state via
`--json`; the single sanctioned exception is documented below (issue/PR number
capture). All issues created by the system carry the `hive:managed` label.

## Milestones (REST API only — no native `gh milestone` command)

### Create

```bash
gh api repos/{owner}/{repo}/milestones -f title="<milestone title>"
```

Capture **`.number`** from the POST response (e.g. append `--jq .number`).
This is a **milestone number**, a separate numbering space from issue numbers —
never confuse the two. The milestone number is what PRD frontmatter stores in
`milestone:` and what every PATCH targets:

```bash
gh api repos/{owner}/{repo}/milestones/<milestone-number> -X PATCH ...
```

### Update the description (read-modify-write — never blind-overwrite)

Milestone descriptions accumulate marker lines (e.g. `plan-review: passed
(PLAN-NNN)`). A blind PATCH with only the new text would destroy existing
content. Always:

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

### Create an epic

```bash
gh issue create --title "..." --body "..." --milestone "<milestone title>" --label hive:managed --type Epic
```

Note: `--milestone` on `gh issue create` takes the **title**, not the number.
Both the label and the milestone are load-bearing — `/swarm` discovers the epic
by filtering on them.

### Create a task

```bash
gh issue create --title "..." --body "..." --milestone "<milestone title>" --parent <epic#> --blocked-by <n1>,<n2> --label phase:build,hive:managed --type Task
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

### Read the DAG (the full /swarm field set)

```bash
gh issue list --milestone "<milestone title>" --state all --json number,title,state,blockedBy,blocking,parent,issueType,labels
```

All eight fields are required: epic discovery needs `issueType` + `labels`,
task-set filtering needs `parent`, unblocking-most-first selection needs
`blocking`, and readiness needs `state` + `blockedBy`.

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

Confirm type, milestone, parent, labels, and blockedBy all match what was
requested. This exception applies **only** to number capture from these two
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

If `gh pr merge` fails (branch protection, required checks, conflicts):
**PAUSE and surface the PR URL** to the user. Never mark the task as done,
never close the issue manually, never bypass the failure.
