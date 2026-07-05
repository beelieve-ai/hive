# Hive

This repository is the Hive — an AI-driven development lifecycle (Idea → PRD → Research → ADR → Plan → Build → Review), packaged as a Claude Code plugin (`.claude-plugin/`, `skills/`, `agents/`, `hooks/`).
Documents under `docs/` are the source of truth for intent; GitHub Issues are the execution layer.
Conventions live in `rules/colony.md` (injected each session by the plugin's SessionStart hook).
When developing Hive itself, load it with `claude --plugin-dir .` so the `hive:*` commands, skills, and agents are active.

## Semantic versioning (non-negotiable)

Every change to this plugin MUST bump its version following
[Semantic Versioning 2.0.0](https://semver.org) (`MAJOR.MINOR.PATCH`):

- **MAJOR** — backward-incompatible changes (renamed/removed args, changed
  invocation, behavior that breaks existing usage).
- **MINOR** — backward-compatible new functionality.
- **PATCH** — backward-compatible bug fixes, doc/wording tweaks that don't
  change behavior.

The plugin version lives in `.claude-plugin/plugin.json` and is the single
source of truth. Bump it on every change — no change ships without a version
bump.
