# Hive Glossary

Canonical vocabulary for this project — use these terms, avoid the banned synonyms.

## Audit log

The append-only provenance file of one PRD's lifecycle —
`docs/audit/PRD-NNN-audit.md` — recording every human gate verdict, every
`--yolo` auto-accept, and every doc status flip as one fixed-schema markdown
line per event. Provenance, not state: it is never read for routing or
resume; the artifacts remain the state.

Avoid: audit trail, decision log, history file, run log
