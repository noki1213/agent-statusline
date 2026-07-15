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
5h  ███░░░░░░░  34%
7d  █░░░░░░░░░  8%
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

### 1. Clone

```bash
git clone https://github.com/noki1213/agent-statusline.git
cd agent-statusline
chmod +x statusline-claude.sh statusline-agy.sh
```

### 2. Configure Local Settings

Create a `.env` file in the repository root to specify the path to your custom CLI tool (if necessary). This file is ignored by Git, keeping your local paths private.

```bash
echo 'AGY_USAGE_COMMAND="/path/to/your/cli"' > .env
```

### 3. Apply Settings to Agents

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
5h  ███░░░░░░░  34%
7d  █░░░░░░░░░  8%
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

### 1. クローン

```bash
git clone https://github.com/noki1213/agent-statusline.git
cd agent-statusline
chmod +x statusline-claude.sh statusline-agy.sh
```

### 2. ローカル設定ファイルの作成

必要に応じて、利用する CLI ツールのパスを指定するため、リポジトリの直下に `.env` ファイルを作成してください。このファイルは Git の追跡から外れるため、ローカルパスが外部に公開されることはありません。

```bash
echo 'AGY_USAGE_COMMAND="/path/to/your/cli"' > .env
```

### 3. 各エージェントへの設定適用

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
