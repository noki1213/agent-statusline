#!/bin/bash
set -euo pipefail

SETTINGS_DIR="$HOME/.claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/statusline-claude.sh"

# ディレクトリがない場合は作成
mkdir -p "$SETTINGS_DIR"

if [ -f "$SETTINGS_FILE" ]; then
    # 既存のファイルに statusLine を追記
    jq --arg script "$SCRIPT_PATH" '. + {statusLine: {type: "command", command: ("bash " + $script)}}' "$SETTINGS_FILE" > /tmp/claude_settings.json
    mv /tmp/claude_settings.json "$SETTINGS_FILE"
    echo "✅ 既存の settings.json に statusLine の設定を追加しました！"
else
    # 新規作成
    echo "{\"statusLine\": {\"type\": \"command\", \"command\": \"bash $SCRIPT_PATH\"}}" > "$SETTINGS_FILE"
    echo "✅ settings.json を新規作成し、statusLine の設定を追加しました！"
fi

echo "✨ これで Claude Code を再起動するとステータスラインが表示されます！"
