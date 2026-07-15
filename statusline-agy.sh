#!/bin/bash
# Antigravity CLI ステータスライン表示スクリプト（スマートキャッシュ＆主副2段表示版）

# ---------- 環境変数の読み込み ----------
if [ -f "$(dirname "$0")/.env" ]; then
    source "$(dirname "$0")/.env"
fi

input=$(cat)

# ---------- stdin から情報を取得 ----------
eval "$(echo "$input" | jq -r '
	"model_name=" + (.model.display_name // "Unknown" | @sh),
	"used_pct=" + (.context_window.used_percentage // 0 | tostring),
	"task_count=" + (.task_count // 0 | tostring),
	"artifact_count=" + (.artifact_count // 0 | tostring),
	"subagents=" + (if .subagents | type == "array" then (.subagents | length) else 0 end | tostring)
' 2>/dev/null)"

# ---------- キャッシュ更新（非同期）----------
CACHE_FILE="/tmp/agy_quota_cache.json"
CTX_FILE="/tmp/agy_last_ctx.txt"
UPDATE_SCRIPT="/tmp/update_agy_quota.sh"

cat << 'EOF' > "$UPDATE_SCRIPT"
#!/bin/bash
FORCE_UPDATE=$2
if [ "$FORCE_UPDATE" != "force" ] && [ -f "$1" ]; then
    # 5分未満なら更新しない
    if find "$1" -mmin -5 2>/dev/null | grep -q .; then exit 0; fi
fi
touch "$1" # タイムスタンプ更新（多重起動防止）
AGY_CLI_CMD="${AGY_USAGE_COMMAND:-agy-usage-cli}"
${AGY_CLI_CMD} usage --provider antigravity --format json > "${1}.tmp" 2>/dev/null
if [ -s "${1}.tmp" ]; then
    mv "${1}.tmp" "$1"
fi
EOF
chmod +x "$UPDATE_SCRIPT"

LAST_CTX=$(cat "$CTX_FILE" 2>/dev/null || echo "")
if [ -n "$used_pct" ] && [ "$used_pct" != "$LAST_CTX" ]; then
	echo "$used_pct" > "$CTX_FILE"
	"$UPDATE_SCRIPT" "$CACHE_FILE" force >/dev/null 2>&1 &
else
	"$UPDATE_SCRIPT" "$CACHE_FILE" normal >/dev/null 2>&1 &
fi

# ---------- ANSIカラー ----------
GREEN=$'\e[38;2;51;165;165m'
YELLOW=$'\e[38;2;244;201;128m'
RED=$'\e[38;2;252;156;156m'
BLUE=$'\e[38;2;74;143;191m'
CYAN=$'\e[38;2;74;174;200m'
MAGENTA=$'\e[38;2;184;127;204m'
WHITE=$'\e[38;2;196;196;196m'
GRAY=$'\e[38;2;74;88;92m'
RESET=$'\e[0m'

color_for_pct() {
	local pct="$1"
	if [ -z "$pct" ] || [ "$pct" = "null" ]; then
		printf '%s' "$GRAY"
		return
	fi
	local ipct
	ipct=$(printf "%.0f" "$pct" 2>/dev/null || echo "0")
	if [ "$ipct" -ge 80 ]; then
		printf '%s' "$RED"
	elif [ "$ipct" -ge 50 ]; then
		printf '%s' "$YELLOW"
	else
		printf '%s' "$GREEN"
	fi
}

progress_bar() {
	local pct="$1"
	local ideal="${2:-}"
	local filled
	filled=$(awk "BEGIN{printf \"%d\", int($pct / 10 + 0.5)}" 2>/dev/null || echo 0)
	[ "$filled" -gt 10 ] 2>/dev/null && filled=10
	[ "$filled" -lt 0 ] 2>/dev/null && filled=0
	local bar=""
	for i in $(seq 1 10); do
		if [ -n "$ideal" ] && [ "$i" -eq "$ideal" ]; then
			bar="${bar}┃"
		elif [ "$i" -le "$filled" ]; then
			bar="${bar}█"
		else
			bar="${bar}░"
		fi
	done
	printf '%s' "$bar"
}

progress_bar_small() {
	local pct="$1"
	local filled
	filled=$(awk "BEGIN{printf \"%d\", int($pct / 20 + 0.5)}" 2>/dev/null || echo 0)
	[ "$filled" -gt 5 ] 2>/dev/null && filled=5
	[ "$filled" -lt 0 ] 2>/dev/null && filled=0
	local bar=""
	for i in $(seq 1 5); do
		if [ "$i" -le "$filled" ]; then
			bar="${bar}█"
		else
			bar="${bar}░"
		fi
	done
	printf '%s' "$bar"
}

cwd="$PWD"
dir_name=$(echo "$cwd" | sed "s|^/Users/$(whoami)|~|")

git_branch=""
git_repo=""
git_line_color="$GREEN"
git_no_remote=false
git_not_owned=false
git_unpushed=0
git_behind=0

if [ -n "$cwd" ] && [ -d "$cwd" ]; then
	git_branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null || true)
	if [ -n "$git_branch" ]; then
		git_toplevel=$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel 2>/dev/null || true)
		git_repo=$(basename "$git_toplevel")
		has_remote=$(git -C "$cwd" --no-optional-locks remote 2>/dev/null | wc -l | tr -d ' ')

		if [ "$has_remote" -gt 0 ]; then
			github_user=$(grep '^\s*user:' ~/.config/gh/hosts.yml 2>/dev/null | head -1 | awk '{print $2}')
			if [ -n "$github_user" ]; then
				remote_url=$(git -C "$cwd" --no-optional-locks remote get-url origin 2>/dev/null || true)
				if [ -n "$remote_url" ] && ! echo "$remote_url" | grep -q "$github_user"; then
					git_not_owned=true
					git_line_color=""
				fi
			fi
		fi

		if ! $git_not_owned; then
			porcelain=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null || true)
			has_unstaged=$(echo "$porcelain" | grep -c '^.[^ ]' 2>/dev/null || echo 0)
			has_staged=$(echo "$porcelain" | grep -c '^[^ ?] ' 2>/dev/null || echo 0)

			if [ "$has_unstaged" -gt 0 ]; then
				git_line_color="$RED"
			elif [ "$has_staged" -gt 0 ]; then
				git_line_color="$YELLOW"
			elif [ "$has_remote" -eq 0 ]; then
				git_line_color="$BLUE"
				git_no_remote=true
			else
				git_unpushed=$(git -C "$cwd" --no-optional-locks rev-list "@{u}..HEAD" --count 2>/dev/null || echo 0)
				git_behind=$(git -C "$cwd" --no-optional-locks rev-list "HEAD..@{u}" --count 2>/dev/null || echo 0)
				if [ "$git_unpushed" -gt 0 ] || [ "$git_behind" -gt 0 ]; then
					git_line_color="$BLUE"
				else
					git_line_color="$GREEN"
				fi
			fi
		fi
	fi
fi

# ---------- 自動モデル判定（主／副の割り当て） ----------
model_lower=$(echo "$model_name" | tr '[:upper:]' '[:lower:]')
if [[ "$model_lower" == *"claude"* || "$model_lower" == *"gpt"* ]]; then
	PRIMARY_NAME="Claude/GPT"
	PRIMARY_5H_ID="antigravity-quota-summary-3p-5h"
	PRIMARY_7D_ID="antigravity-quota-summary-3p-weekly"
	ALT_NAME="Gemini"
	ALT_5H_ID="antigravity-quota-summary-gemini-5h"
	ALT_7D_ID="antigravity-quota-summary-gemini-weekly"
else
	PRIMARY_NAME="Gemini"
	PRIMARY_5H_ID="antigravity-quota-summary-gemini-5h"
	PRIMARY_7D_ID="antigravity-quota-summary-gemini-weekly"
	ALT_NAME="Claude/GPT"
	ALT_5H_ID="antigravity-quota-summary-3p-5h"
	ALT_7D_ID="antigravity-quota-summary-3p-weekly"
fi

P_5H_PCT=""
P_5H_RESET="0"
P_7D_PCT=""
P_7D_RESET="0"
A_5H_PCT=""
A_7D_PCT=""

if [ -s "$CACHE_FILE" ]; then
	eval "$(jq -r --arg p5 "$PRIMARY_5H_ID" --arg p7 "$PRIMARY_7D_ID" --arg a5 "$ALT_5H_ID" --arg a7 "$ALT_7D_ID" '
	  (.[0].usage.extraRateWindows[]? | select(.id == $p5) | 
	    "P_5H_PCT=" + (.window.usedPercent | tostring) + "\n" +
	    "P_5H_RESET=" + (if .window.resetsAt then (.window.resetsAt | fromdateiso8601 | tostring) else "0" end)
	  ),
	  (.[0].usage.extraRateWindows[]? | select(.id == $p7) | 
	    "P_7D_PCT=" + (.window.usedPercent | tostring) + "\n" +
	    "P_7D_RESET=" + (if .window.resetsAt then (.window.resetsAt | fromdateiso8601 | tostring) else "0" end)
	  ),
	  (.[0].usage.extraRateWindows[]? | select(.id == $a5) | 
	    "A_5H_PCT=" + (.window.usedPercent | tostring)
	  ),
	  (.[0].usage.extraRateWindows[]? | select(.id == $a7) | 
	    "A_7D_PCT=" + (.window.usedPercent | tostring)
	  )
	' "$CACHE_FILE" 2>/dev/null)"
fi

fmt_pct() {
	local p="$1"
	if [ -n "$p" ] && [ "$p" != "null" ]; then
		printf "%.0f" "$p" 2>/dev/null || echo ""
	else
		echo ""
	fi
}

P_5H_PCT=$(fmt_pct "$P_5H_PCT")
P_7D_PCT=$(fmt_pct "$P_7D_PCT")
A_5H_PCT=$(fmt_pct "$A_5H_PCT")
A_7D_PCT=$(fmt_pct "$A_7D_PCT")

ideal_bar_pos() {
	local reset_epoch="$1"
	local window_sec="$2"
	[ -z "$reset_epoch" ] || [ "$reset_epoch" = "0" ] && echo "" && return
	local now
	now=$(date +%s)
	local start=$(( reset_epoch - window_sec ))
	local elapsed=$(( now - start ))
	[ "$elapsed" -le 0 ] && echo "1" && return
	local pos
	pos=$(awk "BEGIN{printf \"%d\", int($elapsed / $window_sec * 10 + 0.5)}" 2>/dev/null || echo "")
	[ "$pos" -gt 10 ] 2>/dev/null && pos=10
	[ "$pos" -lt 1 ] 2>/dev/null && pos=1
	echo "$pos"
}

IDEAL_P5=$(ideal_bar_pos "$P_5H_RESET" "18000")
IDEAL_P7=$(ideal_bar_pos "$P_7D_RESET" "604800")

countdown() {
	local epoch="$1"
	[ -z "$epoch" ] || [ "$epoch" = "0" ] && echo "" && return
	local now
	now=$(date +%s)
	local diff=$(( epoch - now ))
	[ "$diff" -le 0 ] && echo "" && return
	local days=$(( diff / 86400 ))
	local hours=$(( (diff % 86400) / 3600 ))
	local mins=$(( (diff % 3600) / 60 ))
	if [ "$days" -eq 0 ]; then
		printf '   %02dh %02dm' "$hours" "$mins"
	else
		printf '%dd %02dh %02dm' "$days" "$hours" "$mins"
	fi
}

p5_reset_display=""
if [ -n "$P_5H_RESET" ] && [ "$P_5H_RESET" != "0" ]; then
	cd5=$(countdown "$P_5H_RESET")
	[ -n "$cd5" ] && p5_reset_display="→ ${cd5}"
fi

p7_reset_display=""
if [ -n "$P_7D_RESET" ] && [ "$P_7D_RESET" != "0" ]; then
	cd7=$(countdown "$P_7D_RESET")
	[ -n "$cd7" ] && p7_reset_display="→ ${cd7}"
fi

reset_datetime() {
	local epoch="$1"
	[ -z "$epoch" ] || [ "$epoch" = "0" ] && echo "" && return
	local dt
	dt=$(date -r "$epoch" +'%m/%d %a %H:%M')
	printf '(%s)' "$dt"
}

ctx_pct_int=0
if [ -n "$used_pct" ] && [ "$used_pct" != "null" ] && [ "$used_pct" != "0" ]; then
	ctx_pct_int=$(printf "%.0f" "$used_pct" 2>/dev/null || echo 0)
fi

ctx_color=$WHITE
if [ "$ctx_pct_int" -ge 80 ]; then
	ctx_color=$RED
elif [ "$ctx_pct_int" -ge 50 ]; then
	ctx_color=$YELLOW
fi

# ---------- 行の組み立て ----------
SEP="${GRAY} │ ${RESET}"

line1="${WHITE}󰉋 ${dir_name}${RESET}"

line2=""
if [ -n "$git_repo" ] && [ -n "$git_branch" ]; then
	GH_VIS_SCRIPT="${GH_VISIBILITY_SCRIPT:-gh-visibility.sh}"
	vis=$("${GH_VIS_SCRIPT}" "$git_toplevel" 2>/dev/null || echo "")
	push_mark=""
	if ! $git_no_remote; then
		[ "$git_unpushed" -gt 0 ] && push_mark="${push_mark} ↑${git_unpushed}"
		[ "$git_behind" -gt 0 ] && push_mark="${push_mark} ↓${git_behind}"
	fi
	if [ "$git_branch" = "main" ] || [ "$git_branch" = "master" ]; then
		line2="${git_line_color}${vis} ${git_repo} [${git_branch}]${push_mark}${RESET}"
	else
		line2="${git_line_color}${vis} ${git_repo} ${MAGENTA}[${git_branch}]${git_line_color}${push_mark}${RESET}"
	fi
elif [ -n "$git_branch" ]; then
	if [ "$git_branch" = "main" ] || [ "$git_branch" = "master" ]; then
		line2="${git_line_color} [${git_branch}]${push_mark}${RESET}"
	else
		line2="${git_line_color} ${MAGENTA}[${git_branch}]${git_line_color}${push_mark}${RESET}"
	fi
fi

# 3行目：モデル名 + CTX + Tasks/Subagents
extras=""
[ -n "$task_count" ] && [ "$task_count" -gt 0 ] && extras="${SEP}⚙Tasks: ${task_count}"
[ -n "$subagents" ] && [ "$subagents" -gt 0 ] && extras="${extras}${SEP}🤖Subagents: ${subagents}"
line3="${model_name}${SEP}${ctx_color}CTX ${ctx_pct_int}%${RESET}${extras}"

# 4行目（メインモデル 5h）
line4=""
if [ -n "$P_5H_PCT" ]; then
	c5=$(color_for_pct "$P_5H_PCT")
	bar5=$(progress_bar "$P_5H_PCT" "$IDEAL_P5")
	line4="${c5}5h ${bar5} $(printf '%3s' "${P_5H_PCT}")%${RESET}"
	if [ -n "$p5_reset_display" ]; then
		dt5=$(reset_datetime "$P_5H_RESET")
		line4+=" ${p5_reset_display} ${dt5}"
	fi
else
	line4="${GRAY}5h  ░░░░░░░░░░   --%${RESET}"
fi

# 5行目（メインモデル 7d）
line5=""
if [ -n "$P_7D_PCT" ]; then
	c7=$(color_for_pct "$P_7D_PCT")
	bar7=$(progress_bar "$P_7D_PCT" "$IDEAL_P7")
	line5="${c7}7d ${bar7} $(printf '%3s' "${P_7D_PCT}")%${RESET}"
	if [ -n "$p7_reset_display" ]; then
		dt7=$(reset_datetime "$P_7D_RESET")
		line5+=" ${p7_reset_display} ${dt7}"
	fi
else
	line5="${GRAY}7d  ░░░░░░░░░░   --%${RESET}"
fi

# 6行目（サブモデル 1行コンパクト表示）
line6=""
if [ -n "$A_5H_PCT" ] && [ -n "$A_7D_PCT" ]; then
	c_a5=$(color_for_pct "$A_5H_PCT")
	bar_a5=$(progress_bar_small "$A_5H_PCT")
	c_a7=$(color_for_pct "$A_7D_PCT")
	bar_a7=$(progress_bar_small "$A_7D_PCT")
	line6="${GRAY}↳ ${ALT_NAME}: ${c_a5}5h ${bar_a5} $(printf '%3s' "${A_5H_PCT}")%${GRAY} │ ${c_a7}7d ${bar_a7} $(printf '%3s' "${A_7D_PCT}")%${RESET}"
fi

# ---------- 出力 ----------
printf '%s\n' "$line1"
[ -n "$line2" ] && printf '%s\n' "$line2"
printf '%s\n' "$line3"
printf '%s\n' "$line4"
if [ -n "$line6" ]; then
	printf '%s\n' "$line5"
	printf '%s' "$line6"
else
	printf '%s' "$line5"
fi
