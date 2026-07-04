#!/usr/bin/env bash
# SessionStart hook: inject the Colony conventions (rules/colony.md) into the
# session as additionalContext. This replaces the project-local
# `.claude/rules/` auto-load, which installed plugins cannot provide.
set -euo pipefail

root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
colony="$root/rules/colony.md"

# Emit the file's contents as SessionStart additionalContext, with the resolved
# plugin root appended so sessions can locate the plugin. Encoding via python3
# keeps the JSON valid regardless of what colony.md contains.
python3 - "$colony" "$root" <<'PY'
import json, sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        content = fh.read() + "\n\n"
except OSError:
    # No conventions file → still inject the plugin root line.
    content = ""

content += "Hive plugin root: " + sys.argv[2]

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": content,
    }
}))
PY
