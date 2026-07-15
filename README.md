# agent-statusline

[English](#english) | [日本語](#japanese)

<a name="english"></a>
A custom status line script for [Claude Code](https://claude.ai/code) and Antigravity (Windsurf) that displays context usage, rate limit progress bars, and git information.

## Preview

**For Claude Code (`statusline-claude.sh`)**
```
~/path/to/agent-statusline
git: agent-statusline [main]
Claude Sonnet 4.6 │ CTX 12%
5h ┃██░░░░░░░░  24% →    03h 15m
7d █┃██░░░░░░  37% → 5d 08h 14m
```

**For Antigravity (`statusline-agy.sh`)**
```
~/path/to/agent-statusline
git: agent-statusline [main]
Claude Sonnet 4.6 │ CTX 0%
5h ┃░░░░░░░░░   9% →    04h 22m
7d █┃██░░░░░░  37% → 5d 08h 14m
↳ Claude/GPT: 5h ░░░░░   0% │ 7d ███░░  58%
```

## What it shows

| Line | Content |
|------|---------|
| 1 | Current directory path |
| 2 | Git repo name and branch (only inside a git repo) |
| 3+ | Agent specific usage and rate limits |

Colors change based on usage: green (< 50%) → yellow (50–79%) → red (≥ 80%)

**✨ Unique Feature: Ideal Progress Marker (`┃`)**
The progress bar includes a vertical bar marker (`┃`) that indicates your "ideal" usage pace based on the time remaining until your rate limits reset. If your current usage bar stays behind this marker, you are using the AI at a safe and sustainable pace without hitting the limits!

## Requirements

- macOS
- `jq`
- `curl`
- `bash`

Install `jq` if you haven't:
```bash
brew install jq
```

## Setup

### 1. Download

Download the latest `Source code (zip)` from the [Releases](https://github.com/noki1213/agent-statusline/releases) page and extract it to your preferred location.

*(For Git users: `git clone https://github.com/noki1213/agent-statusline.git`)*

Open your terminal, navigate to the extracted folder, and make the scripts executable:

```bash
cd path/to/agent-statusline
chmod +x statusline-claude.sh statusline-agy.sh apply-claude-settings.sh apply-agy-settings.sh
```

### 2. Apply Settings to Agents

#### For Claude Code

Run the included setup script to automatically configure Claude Code:

```bash
./apply-claude-settings.sh
```

#### For Antigravity

Run the included setup script to automatically configure Antigravity:

```bash
./apply-agy-settings.sh
```

## Notes

- Rate limit info is fetched and cached locally to avoid excessive API calls.
- Credentials are read securely from the macOS keychain (or local CLI).

---

<a name="japanese"></a>
# 日本語ドキュメント

Claude Code および Antigravity 向けのカスタムステータスラインスクリプトです。コンテキスト使用率・レートリミットのプログレスバー・git 情報などを表示します。

## プレビュー

**Claude Code の場合 (`statusline-claude.sh`)**
```
~/path/to/agent-statusline
git: agent-statusline [main]
Claude Sonnet 4.6 │ CTX 12%
5h ┃██░░░░░░░░  24% →    03h 15m
7d █┃██░░░░░░  37% → 5d 08h 14m
```

**Antigravity の場合 (`statusline-agy.sh`)**
```
~/path/to/agent-statusline
git: agent-statusline [main]
Claude Sonnet 4.6 │ CTX 0%
5h ┃░░░░░░░░░   9% →    04h 22m
7d █┃██░░░░░░  37% → 5d 08h 14m
↳ Claude/GPT: 5h ░░░░░   0% │ 7d ███░░  58%
```

## 表示内容

| 行 | 内容 |
|----|------|
| 1 | 現在のディレクトリパス |
| 2 | git リポジトリ名とブランチ名（git リポジトリ内のみ） |
| 3行目以降 | 各エージェント固有の使用率・レートリミット情報 |

使用率に応じて色が変わります：緑（50% 未満）→ 黄（50〜79%）→ 赤（80% 以上）

**✨ ユニークな機能：理想進捗マーカー（`┃`）**
プログレスバーの中にある縦棒（`┃`）は、リセット時刻までの残り時間から逆算した「理想の消費ペース」を示しています。現在の使用量がこのマーカーより左側に収まっていれば、制限に引っかかることなく安全なペースで使えているという画期的な目安になります！

## 必要なもの

- macOS
- `jq`
- `curl`
- `bash`

`jq` のインストール（未インストールの場合）:
```bash
brew install jq
```

## セットアップ

### 1. ダウンロード

[Releases ページ](https://github.com/noki1213/agent-statusline/releases) から最新の `Source code (zip)` をダウンロードし、好きな場所に解凍してください。

*（Git を使う場合: `git clone https://github.com/noki1213/agent-statusline.git`）*

ターミナルを開き、解凍したフォルダに移動して実行権限を付与します：

```bash
cd path/to/agent-statusline
chmod +x statusline-claude.sh statusline-agy.sh apply-claude-settings.sh apply-agy-settings.sh
```

### 2. 各エージェントへの設定適用

#### Claude Code の場合

同梱されているセットアップスクリプトを実行するだけで、自動で設定が反映されます：

```bash
./apply-claude-settings.sh
```

#### Antigravity の場合

同梱されているセットアップスクリプトを実行するだけで、自動で設定が反映されます：

```bash
./apply-agy-settings.sh
```

## 備考

- レートリミット情報は最小限のリクエストで取得され、API 呼び出しを抑えるために一定時間キャッシュされます。
- 認証情報やローカルパスは安全に管理（キーチェーンや `.env` を利用）される設計になっています。
