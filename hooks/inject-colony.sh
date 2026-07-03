#!/usr/bin/env bash
# SessionStart hook: inject the Colony conventions (rules/colony.md) into the
# session as additionalContext. This replaces the project-local
# `.claude/rules/` auto-load, which installed plugins cannot provide.
set -euo pipefail

colony="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/rules/colony.md"

# Emit the file's contents as SessionStart additionalContext. Encoding via
# python3 keeps the JSON valid regardless of what colony.md contains.
python3 - "$colony" <<'PY'
import json, sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        content = fh.read()
except OSError:
    # No conventions file → inject nothing rather than failing the session.
    sys.exit(0)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": content,
    }
}))
PY
