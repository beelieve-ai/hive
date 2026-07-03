---
id: PRD-000
title: Smoke test
status: planned
created: 2026-07-03
research: []
adrs: []
milestone: 1
epic_issue: 1
---

# PRD-000: Smoke test

## Problem

Verify the Hive lifecycle end-to-end with two trivial, dependency-ordered
requirements. The PRD approval gate was satisfied by the user's `/swarm`
directive authorizing this smoke test.

## Goals / Non-Goals

**Goals**

- Exercise the full PRD → plan → build → review → merge flow on a throwaway goal.

**Non-Goals**

- Producing any artifact of lasting value beyond the smoke-test evidence.

## Requirements

### R1: Pollen file

Create `smoke/pollen.txt` whose entire content is exactly the single line
`nectar-42`.

**Acceptance criteria**

- The file `smoke/pollen.txt` exists.
- Its content is exactly the single line `nectar-42`.

**Verification**

```bash
grep -qx "nectar-42" smoke/pollen.txt
```

### R2: Honey file consuming R1

Create `smoke/honey.txt` whose entire content is exactly `honey: ` followed by
the content of `smoke/pollen.txt` (i.e. the line `honey: nectar-42`), produced
**by reading `smoke/pollen.txt` from the working tree**, not by hardcoding
blindly.

**Acceptance criteria**

- The file `smoke/honey.txt` exists.
- Its content equals `honey: ` + the actual current content of
  `smoke/pollen.txt`.

**Verification**

```bash
test "$(cat smoke/honey.txt)" = "honey: $(cat smoke/pollen.txt)"
```

## Open Questions

- None.
