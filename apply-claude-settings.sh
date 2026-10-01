#!/bin/bash
set -euo pipefail

SETTINGS_DIR="$HOME/.claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/statusline-claude.sh"
SUBAGENT_SCRIPT_PATH="$SCRIPT_DIR/statusline-claude-subagent.sh"

# Create the directory if it doesn't exist
mkdir -p "$SETTINGS_DIR"

if [ -f "$SETTINGS_FILE" ]; then
    # Append statusLine and subagentStatusLine to the existing file
    jq --arg script "$SCRIPT_PATH" --arg subagent "$SUBAGENT_SCRIPT_PATH" '. + {statusLine: {type: "command", command: ("bash " + $script)}, subagentStatusLine: {type: "command", command: ("bash " + $subagent)}}' "$SETTINGS_FILE" > /tmp/claude_settings.json
    cat /tmp/claude_settings.json > "$SETTINGS_FILE"
    rm /tmp/claude_settings.json
    echo "✅ Added the statusLine and subagentStatusLine settings to your existing settings.json"
else
    # Create new
    echo "{\"statusLine\": {\"type\": \"command\", \"command\": \"bash $SCRIPT_PATH\"}, \"subagentStatusLine\": {\"type\": \"command\", \"command\": \"bash $SUBAGENT_SCRIPT_PATH\"}}" > "$SETTINGS_FILE"
    echo "✅ Created settings.json with the statusLine and subagentStatusLine settings"
fi

echo "✨ Restart Claude Code to see the status line"
