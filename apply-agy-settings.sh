#!/bin/bash
set -euo pipefail

SETTINGS_DIR="$HOME/.gemini/antigravity-cli"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
SCRIPT_PATH="/Users/maaya/00_Home_Local/20_dev/claude-statusline/statusline-agy.sh"

# ディレクトリがない場合は作成
mkdir -p "$SETTINGS_DIR"

if [ -f "$SETTINGS_FILE" ]; then
    # 既存のファイルに statusLine を追記
    jq --arg script "$SCRIPT_PATH" '. + {statusLine: {type: "", command: ("bash " + $script), enabled: true}}' "$SETTINGS_FILE" > /tmp/agy_settings.json
    mv /tmp/agy_settings.json "$SETTINGS_FILE"
    echo "✅ 既存の settings.json に statusLine の設定を追加しました！"
else
    # 新規作成
    echo "{\"statusLine\": {\"type\": \"\", \"command\": \"bash $SCRIPT_PATH\", \"enabled\": true}}" > "$SETTINGS_FILE"
    echo "✅ settings.json を新規作成し、statusLine の設定を追加しました！"
fi

echo "✨ これで Antigravity CLI を再起動するとステータスラインが表示されます！"
