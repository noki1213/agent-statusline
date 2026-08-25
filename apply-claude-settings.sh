#!/bin/bash
set -euo pipefail

SETTINGS_DIR="$HOME/.claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/statusline-claude.sh"

# Create the directory if it doesn't exist
mkdir -p "$SETTINGS_DIR"

if [ -f "$SETTINGS_FILE" ]; then
    # Append statusLine to the existing file
    jq --arg script "$SCRIPT_PATH" '. + {statusLine: {type: "command", command: ("bash " + $script)}}' "$SETTINGS_FILE" > /tmp/claude_settings.json
    cat /tmp/claude_settings.json > "$SETTINGS_FILE"
    rm /tmp/claude_settings.json
    echo "✅ Added the statusLine setting to your existing settings.json"
else
    # Create new
    echo "{\"statusLine\": {\"type\": \"command\", \"command\": \"bash $SCRIPT_PATH\"}}" > "$SETTINGS_FILE"
    echo "✅ Created settings.json with the statusLine setting"
fi

echo "✨ Restart Claude Code to see the status line"
