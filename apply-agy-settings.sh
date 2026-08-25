#!/bin/bash
set -euo pipefail

SETTINGS_DIR="$HOME/.gemini/antigravity-cli"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/statusline-agy.sh"

# Create the directory if it doesn't exist
mkdir -p "$SETTINGS_DIR"

if [ -f "$SETTINGS_FILE" ]; then
    # Append statusLine to the existing file
    jq --arg script "$SCRIPT_PATH" '. + {statusLine: {type: "", command: ("bash " + $script), enabled: true}}' "$SETTINGS_FILE" > /tmp/agy_settings.json
    cat /tmp/agy_settings.json > "$SETTINGS_FILE"
    rm /tmp/agy_settings.json
    echo "✅ Added the statusLine setting to your existing settings.json"
else
    # Create new
    echo "{\"statusLine\": {\"type\": \"\", \"command\": \"bash $SCRIPT_PATH\", \"enabled\": true}}" > "$SETTINGS_FILE"
    echo "✅ Created settings.json with the statusLine setting"
fi

echo "✨ Restart Antigravity CLI to see the status line"
