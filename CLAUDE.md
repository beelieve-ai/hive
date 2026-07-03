# Hive

This repository is the Hive — an AI-driven development lifecycle (Idea → PRD → Research → ADR → Plan → Build → Review), packaged as a Claude Code plugin (`.claude-plugin/`, `skills/`, `agents/`, `hooks/`).
Documents under `docs/` are the source of truth for intent; GitHub Issues are the execution layer.
Conventions live in `rules/colony.md` (injected each session by the plugin's SessionStart hook).
Canonical vocabulary lives in the root `CONTEXT.md` glossary (lazily created by grilling sessions).
When developing Hive itself, load it with `claude --plugin-dir .` so the `hive:*` commands, skills, and agents are active.
