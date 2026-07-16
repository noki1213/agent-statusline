#!/bin/bash
# Copilot CLI status line script
# (fetch monthly Premium usage via GitHub CLI's internal API)
# v1.0

if [ ! -t 0 ]; then
	# Read piped input (JSON) if present
	input=$(cat)
else
	input="{}"
fi

# ---------- ANSI colors ----------
GREEN=$'\e[38;2;51;165;165m'
YELLOW=$'\e[38;2;244;201;128m'
RED=$'\e[38;2;252;156;156m'
BLUE=$'\e[38;2;74;143;191m'
CYAN=$'\e[38;2;74;174;200m'
MAGENTA=$'\e[38;2;184;127;204m'
WHITE=$'\e[38;2;196;196;196m'
GRAY=$'\e[38;2;74;88;92m'
RESET=$'\e[0m'
DIM=$'\e[2m'

# ---------- Return a color based on the usage percentage ----------
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

# ---------- Progress bar (10 segments) ----------
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

# ---------- Get the needed info from stdin ----------
# Only parse it when the caller passed in JSON
eval "$(echo "$input" | jq -r '
	"cwd=" + (.cwd // "" | @sh),
	"model_name=" + (.model.display_name // "Copilot" | @sh),
	"used_pct=" + (.context_window.used_percentage // 0 | tostring)
' 2>/dev/null || true)"

dir_name=""
if [ -n "$cwd" ]; then
	dir_name=$(echo "$cwd" | sed "s|^/Users/$(whoami)|~|")
else
    # Fall back to the current directory if cwd can't be obtained
    dir_name=$(pwd | sed "s|^/Users/$(whoami)|~|")
    cwd=$(pwd)
fi

# ---------- Git repo info ----------
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

# ---------- Fetch Copilot usage (via gh api) ----------
CACHE_DIR="$HOME/.cache/copilot-statusline"
CACHE_FILE="$CACHE_DIR/usage.json"
mkdir -p "$CACHE_DIR"

# If the cache is missing or more than 5 minutes old, refresh it in the background while using (or waiting for) the stale value this run
if [ ! -f "$CACHE_FILE" ] || [ $(find "$CACHE_FILE" -mmin +5 2>/dev/null | wc -l) -gt 0 ]; then
    gh api /copilot_internal/user \
      -H "Editor-Version: vscode/1.96.2" \
      -H "Editor-Plugin-Version: copilot-chat/0.26.7" \
      -H "User-Agent: GitHubCopilotChat/0.26.7" \
      -H "X-Github-Api-Version: 2025-04-01" > "$CACHE_FILE.tmp" 2>/dev/null
    if [ $? -eq 0 ]; then
        mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    else
        rm -f "$CACHE_FILE.tmp"
    fi
fi

copilot_plan="unknown"
PREMIUM_USED_PCT=""
RESET_EPOCH=0
ENTITLEMENT=""

if [ -f "$CACHE_FILE" ]; then
    copilot_plan=$(jq -r '.copilot_plan // "unknown"' "$CACHE_FILE")
    
    # Get the remaining Premium percentage
    premium_rem_pct=$(jq -r '.quota_snapshots.premium_interactions.percent_remaining // empty' "$CACHE_FILE")
    entitlement=$(jq -r '.quota_snapshots.premium_interactions.entitlement // empty' "$CACHE_FILE")
    
    if [ -n "$premium_rem_pct" ]; then
        # NOTE: here we back-calculate "used" percentage, not "remaining"!
        PREMIUM_USED_PCT=$(awk "BEGIN {print 100 - $premium_rem_pct}")
    fi
    if [ -n "$entitlement" ]; then
        ENTITLEMENT=$(printf "%.0f" "$entitlement" 2>/dev/null || echo "")
    fi

    reset_utc=$(jq -r '.quota_reset_date_utc // ""' "$CACHE_FILE")
    if [ -n "$reset_utc" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            RESET_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S.000Z" "$reset_utc" "+%s" 2>/dev/null || echo 0)
        fi
    fi
fi

# ---------- Countdown calculation ----------
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

reset_display=""
if [ -n "$RESET_EPOCH" ] && [ "$RESET_EPOCH" != "0" ]; then
	cd_time=$(countdown "$RESET_EPOCH")
	[ -n "$cd_time" ] && reset_display="→ ${cd_time}"
fi

# ---------- Build a reset-time string from epoch seconds ----------
reset_datetime() {
	local epoch="$1"
	[ -z "$epoch" ] || [ "$epoch" = "0" ] && echo "" && return
	local dt
	# Use Japanese weekday names (e.g. "土") only in a Japanese locale
	if [[ "${LANG:-}" == *"ja"* ]] || [[ "${LC_ALL:-}" == *"ja"* ]] || [[ "${LC_TIME:-}" == *"ja"* ]]; then
		dt=$(LC_TIME="ja_JP.UTF-8" date -r "$epoch" +'%m/%d %a %H:%M')
	else
		dt=$(date -r "$epoch" +'%m/%d %a %H:%M')
	fi
	printf '(%s)' "$dt"
}

# ---------- Calculate the ideal position (approximating the monthly limit as 30 days = 2592000 seconds) ----------
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
IDEAL=$(ideal_bar_pos "$RESET_EPOCH" "2592000")

# ---------- Building line 1 and line 2 ----------
SEP="${GRAY} │ ${RESET}"
ctx_color=$WHITE
line1="${WHITE}󰉋 ${dir_name}${RESET}"
line2=""

if [ -n "$git_repo" ] && [ -n "$git_branch" ]; then
	GH_VIS_SCRIPT="${GH_VISIBILITY_SCRIPT:-gh-visibility.sh}"
	vis=$(command -v "$GH_VIS_SCRIPT" >/dev/null && "$GH_VIS_SCRIPT" "$git_toplevel" 2>/dev/null || echo "")
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

# ---------- Line 3 (model name / context) ----------
ctx_pct_int=0
if [ -n "$used_pct" ] && [ "$used_pct" != "null" ] && [ "$used_pct" != "0" ]; then
	ctx_pct_int=$(printf "%.0f" "$used_pct" 2>/dev/null || echo 0)
fi

# Adjustable, e.g. hiding it when CTX is 0, but we match Claude's behavior here
line3="${model_name}${SEP}${ctx_color}CTX ${ctx_pct_int}%${RESET}"

# ---------- Line 4 (Premium) ----------
# Note: Chat is unlimited, so it's hidden to save display space (went with option C)
line4=""
if [ -n "$PREMIUM_USED_PCT" ]; then
	c=$(color_for_pct "$PREMIUM_USED_PCT")
	bar=$(progress_bar "$PREMIUM_USED_PCT" "$IDEAL")
	display_pct=$(printf "%.0f" "$PREMIUM_USED_PCT")
    
	# Use the "30d" prefix to keep the look fully consistent with Claude/Agy
	line4="${c}30d ${bar} $(printf '%3s' "${display_pct}")%${RESET}"
	if [ -n "$reset_display" ]; then
		dt_str=$(reset_datetime "$RESET_EPOCH")
		line4+=" ${reset_display} ${dt_str}"
	fi
fi

# ---------- Output ----------
printf '%s\n' "$line1"
[ -n "$line2" ] && printf '%s\n' "$line2"
printf '%s\n' "$line3"
[ -n "$line4" ] && printf '%s\n' "$line4"
