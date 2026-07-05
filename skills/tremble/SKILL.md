---
name: tremble
description: "Mine this project's Claude Code session transcripts and hive audit logs for evidence that the HIVE SYSTEM itself caused friction, then — only with explicit per-issue approval — file sanitized upstream issues in beelieve-ai/hive. No project-specific information ever leaves the machine. Invoke explicitly as /hive:tremble [--all]; --all forces a full re-scan of every session, ignoring prior state."
disable-model-invocation: true
---

# /hive:tremble — turn session friction into sanitized upstream issues

You are the orchestrator. Like the bee's **tremble dance** — the signal that
the hive's foraging workflow is off and needs attention — this command reads
the current project's session history for places the **hive system itself**
tripped the user up, and (only with explicit approval) files generic issues
about those weaknesses in `beelieve-ai/hive`. `$ARGUMENTS` is empty or the
single flag `--all`.

**The core promise is privacy.** No project path, product name, code, quote,
doc ID, or title ever leaves the machine — only generic findings about hive's
behavior. Every mechanism below serves that promise; none of it is optional.

Ground rules that bind every step:

- **Nothing reaches GitHub before the per-issue human gate approves the exact
  text it would contain** — not an issue, not a comment, not even a dedup
  search query. Sequencing is part of the privacy guarantee (Steps 7–8).
- **All user interaction goes through `AskUserQuestion`** (colony rules): one
  decision per call, the recommended option first labelled `(Recommended)`
  with its reason, real alternatives next, the tool's automatic "Other" as the
  escape hatch. Never ask in prose.
- **The target repo is hardcoded and exceptional.** Every GitHub call is
  explicit `gh --repo beelieve-ai/hive ...`. Hive's `gh-conventions` resolve
  the *current* repo for lifecycle work; tremble does the opposite and spells
  out its own `--repo` on every call. Do **not** load gh-conventions'
  current-repo resolution.
- **All state and scratch live OUTSIDE the repo**, under the Claude project
  directory — repo-local state would dirty every consumer worktree and risk an
  accidental commit of transcript excerpts.
- **Analyzers are read-only and never read raw transcripts** — you hand them
  bounded excerpts; they hand back structured, sanitized-by-construction
  findings. You own merging, sanitization, the gate, submission, and state.

## Step 0 — Resolve arguments and the state/scratch root

1. Split `$ARGUMENTS`. The only accepted token is `--all`; record it as the
   run's `all` flag. Any other non-empty token → ambiguous arguments: pose the
   interpretation via **AskUserQuestion** and stop on an unrecognized answer.
2. **Resolve the main repo root** (state keys off it, not the cwd — a project's
   sessions span worktrees). The git common dir is the main worktree's `.git`:

   ```bash
   common=$(git rev-parse --path-format=absolute --git-common-dir)  # <main>/.git
   main_root=$(dirname "$common")
   ```

3. **Encode** a path to its transcript-dir name by replacing every `/` and `.`
   with `-` (e.g. `/home/u/dev/hive` → `-home-u-dev-hive`;
   `/home/u/dev/hive/.claude/worktrees/wt` →
   `-home-u-dev-hive--claude-worktrees-wt`). Verify the derived directory
   actually exists under `~/.claude/projects/`. The encoding is **lossy**
   (`/` and `.` collapse to the same character), so **never auto-match by
   prefix or similarity** — a near-miss could silently read *another
   project's* transcripts, breaking tremble's scope guarantee. If the derived
   directory is missing or more than one candidate plausibly corresponds,
   enumerate the candidates and pose the choice via **AskUserQuestion**
   (include a "none of these — abort" option); with no plausible candidate,
   fail loud and stop.
4. **State/scratch root** = `~/.claude/projects/<encode(main_root)>/hive-tremble/`
   with `state.json`, `reports/<timestamp>.md`, and `tmp/<run-id>/`. Create it
   if absent. Generate `run-id` and timestamps from `date -u +%Y%m%dT%H%M%SZ`
   (never invent them). **Startup sweep:** remove any leftover `tmp/*/` dirs
   from crashed prior runs before doing anything else, so transcript excerpts
   never linger:

   ```bash
   rm -rf ~/.claude/projects/<encode(main_root)>/hive-tremble/tmp/*/
   ```

## Step 1 — Discover sessions (aggregate all worktrees of this project)

1. **Enumerate every worktree** of this git project — the main repo *and* all
   its worktrees — because a project's sessions are split across their
   transcript dirs; strict-cwd would silently miss or double-count them:

   ```bash
   git worktree list --porcelain | awk '/^worktree /{print $2}'
   ```

2. For each worktree path, encode it (Step 0.3) and collect every `*.jsonl`
   under `~/.claude/projects/<encoded>/` — one JSONL per session, session ID =
   filename stem. This is the **candidate set**.
3. **Locate audit logs** (corroborating evidence only): `docs/audit/*.md` in
   the main repo, tolerating their absence.
4. **stat every candidate at run start** and remember size + mtime — this is
   the in-flight guard (Step 10 re-stats before writing state):

   ```bash
   stat -c '%s %Y' <file>     # Linux; BSD/macOS: stat -f '%z %m'
   ```

5. **Sessions to analyze** = candidate set minus those `state.json` records as
   fully analyzed **at their recorded size + mtime** (a file that grew since is
   re-scanned). `--all` ignores state and re-scans every candidate.
6. **Pre-spawn report + bail-out.** Before spawning anything, report the
   session count and rough volume (total JSONL bytes), then pose via
   **AskUserQuestion**: *Proceed* `(Recommended)` / *Cancel* — the first run on
   a mature project can be expensive even with prefiltering, so the user gets
   to bail before tokens burn. Stop on Cancel.

## Step 2 — Build the redaction blocklist and the precedence allowlist

Do this once, up front — sanitization (Step 6) depends on it.

1. **Harvest the blocklist** of known project identifiers:
   - repo/remote names — `git remote -v`;
   - the cwd and main-repo absolute paths **and each of their path segments**;
   - `docs/` doc IDs and titles — from `docs/prd/*.md`, `docs/adr/*.md`,
     `docs/plans/*.yaml` filenames (IDs) and their frontmatter/first-heading
     titles.
2. **Build the allowlist, which takes precedence over the blocklist**: upstream
   hive vocabulary — `hive`, every `hive:*` command/agent/skill name, the
   logical bee names (pollinate, forage, waggle, comb, swarm, sting, bumble,
   tremble, scout, worker, guard, architect, planner, plan-reviewer-*), colony
   terms, the doc-kind tokens (PRD/RES/ADR/PLAN as generic kinds), and the
   hardcoded target-repo tokens `beelieve-ai` / `beelieve-ai/hive`. A token on
   the allowlist is **never** flagged even if the harvest also produced it —
   otherwise running tremble on the hive repo itself would blocklist the very
   words every legitimate finding must contain.

## Step 3 — Prefilter transcripts into bounded excerpt scratch files

Raw JSONL is huge and bloated with hook/context noise; analyzers never read it
end-to-end. For each session to analyze, run a **read-only Bash prefilter** that
extracts bounded windows around robust surface markers into scratch files under
`tmp/<run-id>/<session-id>/` (never under the worktree — excerpts must not be
committable). Target **surface markers, not deep schema** (the JSONL format is
not a stable public API):

```bash
# match lines carrying signal markers, then emit ±K-line windows around each
grep -nE '/hive:|hive:[a-z-]+|is_error|tool_use_error|AskUserQuestion|interrupted|"role":"user"' \
  "$session" \
| cut -d: -f1 \
| awk -v K=6 '{for(i=$1-K;i<=$1+K;i++) if(i>0) keep[i]=1}
             END{for(i in keep) print i}' \
| sort -n | uniq \
| awk 'NR==FNR{keep[$1];next} FNR in keep' - "$session" \
> tmp/<run-id>/<session-id>/excerpts.txt
```

- Keep markers **few and robust** (user text, error fields, `/hive:` strings,
  subagent spawns, AskUserQuestion). If a session yields **zero** excerpts
  unexpectedly, **fail loud** (note it in the report) rather than silently
  skipping — marker rot is a known risk.
- If an excerpt file is still oversized for one analyzer context, split it into
  disjoint chunk files (`excerpts.NN.txt`) now.
- Also gather the relevant `docs/audit/*.md` paths as optional corroboration.

## Step 4 — Spawn one analyzer per session, in parallel

Spawn the **`hive:tremble-analyzer`** agent (Agent tool, `subagent_type:
hive:tremble-analyzer`) **once per session, in parallel**, passing that
session's excerpt file paths and the corroborating `docs/audit/` paths. For a
session split in Step 3, spawn one analyzer per chunk and treat their findings
as one session's output.

Each analyzer hunts a **fixed taxonomy** plus one catch-all and returns its
findings as the FIRST fenced ```json block — `{"findings":[...]}`, each finding
`{category, component, description, impact, suggestion, evidence}`, sanitized by
construction. Parse **only** that block; a missing or unparseable block is an
**error for that analyzer** (re-spawn once, then record the session as failed in
the report), never "no findings". An empty `findings` array is a valid outcome.
The category slugs are exactly:

`command-error` · `user-correction` · `retry-loop` · `gate-reversed` ·
`convention-confusion` · `workaround` · `other`

`docs/audit/` entries are **corroborating evidence only** — colony rules make
the audit log provenance that deliberately omits halts, errors, and retries, so
its silence never proves nothing went wrong and it is never mined as complete
lifecycle state.

## Step 5 — Merge and dedup (local)

Merge findings across all analyzers. **Collapse recurrences of the same
weakness into one finding with an `occurrences` count** — group by
`(category, component)` and semantic equivalence of the description; the count
is how many distinct instances/sessions exhibited it. Recurrence is signal, not
noise: it strengthens the case and is surfaced in the issue body and the dedup
comment.

## Step 6 — Sanitization (layers 2–3, before anything is shown or sent)

Findings arrive sanitized **by construction** (layer 1, the analyzer's job).
Apply the remaining machine layers to every draft's title, body, and any
comment text **before** it reaches the human gate:

1. **Deterministic redaction check (layer 2).** Mechanically scan the text for:
   any blocklist hit (Step 2), absolute paths, path-like segments, code fences,
   and long verbatim-looking quotes. **Block or rewrite** every hit before
   proceeding. The **allowlist takes precedence** — an allowlisted token
   (hive vocabulary, `beelieve-ai/hive`) is never treated as a leak.
2. **LLM sanitization pass (layer 3).** Re-read each draft yourself hunting for
   leaked specifics the mechanical scan cannot classify — paraphrased project
   details, tell-tale nouns, anything that identifies *what the project was
   about* rather than *what hive did*. Generalize harder; when in doubt, a
   finding too vague to leak beats one that leaks.

Layer 4 is the human gate in Step 7, which always shows the verbatim final text
— never a summary.

## Step 7 — Per-issue approval gate (before any GitHub call)

For each surviving draft, compose the exact final **title**, **body** (Step 9
template), and **labels** (`session-feedback` + `feedback:<category>`), then
make **one `AskUserQuestion` call** (one decision per call) presenting that
text **verbatim** with options:

- **Approve** `(Recommended)` — file exactly as shown.
- **Edit** — revise per the user's amendments.
- **Skip** — do not file; record as skipped.

**Edit loop:** the user's amendments come through the question's free-form
"Other"/notes. Revise the draft, **re-run sanitization layers 2–3** (Step 6) on
the revised text, and **re-gate** with a fresh AskUserQuestion showing the new
verbatim text. Loop until Approve or Skip. Nothing — not even a dedup search
query (Step 8) — touches GitHub until this gate approves the text.

## Step 8 — Tracker dedup, after approval, using approved text only

Only now, for each **approved** draft, search existing open issues in the target
repo using **only the approved sanitized title/keywords**:

```bash
gh issue list --repo beelieve-ai/hive --state open --label session-feedback \
  --search "<approved keywords>" --json number,title,url
```

- **No match** → file the new issue (Step 9).
- **Match** → recurrence is signal: draft a short **"seen again"** supporting
  comment (mention the `occurrences` count), pass it through sanitization
  layers 2–3, and pose a follow-up **AskUserQuestion** showing the comment
  **verbatim** with options: **Post comment on #N** `(Recommended)` /
  **File new issue anyway** / **Skip**. Act on the choice.

## Step 9 — Submission (explicit `--repo beelieve-ai/hive` on every call)

**Lazily ensure labels** — only when the first approved issue/comment actually
needs them (a category label is created the first time that category is filed):

```bash
gh label create session-feedback --repo beelieve-ai/hive --force
gh label create "feedback:<category>" --repo beelieve-ai/hive --force
```

**Issue body** (write to a temp file under `tmp/<run-id>/` and pass with
`--body-file` — multiline bodies corrupt under `--body` quoting). Template —
generic throughout, no lifecycle PRD/ADR header block (these are upstream
feedback issues, not `hive:managed` lifecycle work):

```
## What happened
<generic account of the friction — hive's behavior only>

## Affected hive component / command
<e.g. /hive:comb, hive:guard, plan schema, audit log>

## Impact
<how it affected the run, generically>

## Suggested improvement
<concrete change to hive>

## Occurrences
<count of distinct instances observed>
```

**Create** the issue, capturing the number from the single-URL stdout (the one
sanctioned non-`--json` exception): strict `/issues/<number>` parse, **fail on
zero or multiple matches**, then verify with a `--json` read:

```bash
gh issue create --repo beelieve-ai/hive --title "<approved title>" \
  --body-file <file> --label "session-feedback,feedback:<category>"
gh issue view <n> --repo beelieve-ai/hive --json number,title,labels,url
```

**Comment** (dedup path): `gh issue comment <n> --repo beelieve-ai/hive
--body-file <file>` — capture the returned comment URL. Every GitHub op is
`--repo beelieve-ai/hive`; every read is `--json`.

## Step 10 — State and local report (outside the repo)

1. **Report first.** Write `reports/<timestamp>.md` recording **every** finding
   of the run with its verdict — `filed (#N)`, `commented (#N)`,
   `edited-then-filed (#N)`, or `skipped` — plus any sessions that yielded zero
   excerpts or failed analysis. Skipped findings are never silently lost; the
   report doubles as the audit trail of exactly what left the machine.
2. **Re-stat, then update `state.json`.** For each analyzed session, `stat` it
   **again**. If its size or mtime changed during the run, **leave it out of
   state** so the next run re-scans it. The session running tremble grows its
   own JSONL continuously and so is *always* excluded by this mechanic — which
   is why tremble needs no knowledge of its own session ID. For each session
   that did **not** change, record `{session-id, size, mtime}` (mtime + size are
   what let a later grown file be re-scanned; the ID alone is insufficient for
   an active session). `--all` re-scans regardless of prior state.
3. **Clean up.** Remove `tmp/<run-id>/` now that the report is written.

## Final report to the user

Summarize: sessions discovered vs. analyzed (and any excluded as in-flight or
failed), findings after merge with their occurrence counts, and each finding's
verdict — issues filed (numbers + URLs), comments posted, edited-then-filed, and
skipped — plus the paths to `reports/<timestamp>.md` and `state.json`.

## Context discipline (binding throughout)

- You **never read raw transcripts yourself** — the prefilter bounds them and
  analyzers consume the excerpts. Your working memory is the merged finding
  list and each finding's verdict.
- **Nothing project-specific ever leaves the machine.** When any layer is
  uncertain whether a token leaks, treat it as a leak and generalize — the
  human gate always sees the verbatim final text, never a summary.
