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
    echo "✅ 既存の settings.json に statusLine の設定を追加しました！"
else
    # Create new
    echo "{\"statusLine\": {\"type\": \"command\", \"command\": \"bash $SCRIPT_PATH\"}}" > "$SETTINGS_FILE"
    echo "✅ settings.json を新規作成し、statusLine の設定を追加しました！"
fi

echo "✨ これで Claude Code を再起動するとステータスラインが表示されます！"
