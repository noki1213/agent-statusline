#!/bin/bash
# Claude Code status line script (with rate-limit display)
# Line 1: model name | context usage | lines edited | directory name | repo name:branch name
# Line 2: 5-hour rate-limit progress bar
# Line 3: 7-day rate-limit progress bar
#
# Reference: https://github.com/loadbalance-sudachi-kun/claude-code-statusline

input=$(cat)

# ---------- ANSI colors ----------
GREEN=$'\e[38;2;51;165;165m'
YELLOW=$'\e[38;2;244;201;128m'
RED=$'\e[38;2;252;156;156m'
BLUE=$'\e[38;2;74;143;191m'
CYAN=$'\e[38;2;74;174;200m'
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
# $1: actual usage percentage, $2: ideal-position cell number (1-10, optional)
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
			# Overwrite the ideal-position cell with ┃
			bar="${bar}┃"
		elif [ "$i" -le "$filled" ]; then
			bar="${bar}█"
		else
			bar="${bar}░"
		fi
	done
	printf '%s' "$bar"
}

# ---------- Get the needed info from stdin (batch-processed with jq) ----------
eval "$(echo "$input" | jq -r '
	"model_name=" + (.model.display_name // "Unknown" | @sh),
	"used_pct=" + (.context_window.used_percentage // 0 | tostring),
	"ctx_size=" + (.context_window.context_window_size // 0 | tostring),
	"cwd=" + (.cwd // "" | @sh),
	"cc_version=" + (.version // "0.0.0" | @sh)
' 2>/dev/null)"

# ---------- Current directory (full path, abbreviated with ~) ----------
dir_name=""
if [ -n "$cwd" ]; then
	dir_name=$(echo "$cwd" | sed "s|^/Users/$(whoami)|~|")
fi

# ---------- Git repo name and branch name ----------
git_branch=""
git_repo=""
git_line_color="$GREEN"
git_no_remote=false
git_unpushed=0
git_behind=0
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
	git_branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null || true)
	if [ -n "$git_branch" ]; then
		# Use the git top-level directory name as the repo name
		git_toplevel=$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel 2>/dev/null || true)
		git_repo=$(basename "$git_toplevel")

		# Inspect the git status and decide the color
		porcelain=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null || true)
		# Check for unstaged changes (new/modified/deleted) (2nd char is not a space)
		has_unstaged=$(echo "$porcelain" | grep -c '^.[^ ]' 2>/dev/null || echo 0)
		# Check for staged-but-uncommitted changes (1st char shows a change, 2nd char is a space)
		has_staged=$(echo "$porcelain" | grep -c '^[^ ?] ' 2>/dev/null || echo 0)

		if [ "$has_unstaged" -gt 0 ]; then
			# Unstaged changes exist (needs git add) → red
			git_line_color="$RED"
		elif [ "$has_staged" -gt 0 ]; then
			# Staged with git add but not yet committed → yellow
			git_line_color="$YELLOW"
		else
			# Check whether a remote is configured
			has_remote=$(git -C "$cwd" --no-optional-locks remote 2>/dev/null | wc -l | tr -d ' ')
			if [ "$has_remote" -eq 0 ]; then
				# No remote → mark it blue with a ↑✗
				git_line_color="$BLUE"
				git_no_remote=true
			else
				# Check whether there are unpushed commits
				git_unpushed=$(git -C "$cwd" --no-optional-locks rev-list "@{u}..HEAD" --count 2>/dev/null || echo 0)
				git_behind=$(git -C "$cwd" --no-optional-locks rev-list "HEAD..@{u}" --count 2>/dev/null || echo 0)
				if [ "$git_unpushed" -gt 0 ]; then
					# Unpushed commits present → blue
					git_line_color="$BLUE"
				else
					# Fully clean state → green
					git_line_color="$GREEN"
				fi
			fi
		fi
	fi
fi

# ---------- Rate limit info (fetched via a Haiku probe, with caching) ----------
CACHE_FILE="/tmp/claude-usage-cache.json"
CACHE_TTL=360
FIVE_HOUR_UTIL=""
FIVE_HOUR_RESET=""
SEVEN_DAY_UTIL=""
SEVEN_DAY_RESET=""

fetch_usage() {
	local token
	token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)
	[ -z "$token" ] && return 1

	local access_token
	if echo "$token" | jq -e . >/dev/null 2>&1; then
		access_token=$(echo "$token" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
	else
		access_token="$token"
	fi
	[ -z "$access_token" ] && return 1

	# Send a minimal request to Haiku to get the rate-limit headers
	local full_response
	full_response=$(curl -sD- --max-time 8 -o /dev/null \
		-H "Authorization: Bearer ${access_token}" \
		-H "Content-Type: application/json" \
		-H "User-Agent: claude-code/${cc_version:-0.0.0}" \
		-H "anthropic-beta: oauth-2025-04-20" \
		-H "anthropic-version: 2023-06-01" \
		-d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"h"}]}' \
		"https://api.anthropic.com/v1/messages" 2>/dev/null || true)
	local headers="$full_response"
	[ -z "$headers" ] && return 1

	# Extract the rate-limit headers
	local h5_util h5_reset h7_util h7_reset
	h5_util=$(echo "$headers" | grep -i 'anthropic-ratelimit-unified-5h-utilization' | tr -d '\r' | awk '{print $2}')
	h5_reset=$(echo "$headers" | grep -i 'anthropic-ratelimit-unified-5h-reset' | tr -d '\r' | awk '{print $2}')
	h7_util=$(echo "$headers" | grep -i 'anthropic-ratelimit-unified-7d-utilization' | tr -d '\r' | awk '{print $2}')
	h7_reset=$(echo "$headers" | grep -i 'anthropic-ratelimit-unified-7d-reset' | tr -d '\r' | awk '{print $2}')

	[ -z "$h5_util" ] && return 1

	# Save it to the cache file
	jq -n \
		--arg h5u "$h5_util" --arg h5r "$h5_reset" \
		--arg h7u "$h7_util" --arg h7r "$h7_reset" \
		'{five_hour_util: $h5u, five_hour_reset: $h5r, seven_day_util: $h7u, seven_day_reset: $h7r}' \
		> "$CACHE_FILE"
	return 0
}

load_usage() {
	local data="$1"
	eval "$(echo "$data" | jq -r '
		"FIVE_HOUR_UTIL=" + (.five_hour_util // empty),
		"FIVE_HOUR_RESET=" + (.five_hour_reset // empty),
		"SEVEN_DAY_UTIL=" + (.seven_day_util // empty),
		"SEVEN_DAY_RESET=" + (.seven_day_reset // empty)
	' 2>/dev/null)"
}

# Check whether the cache has expired
USE_CACHE=false
if [ -f "$CACHE_FILE" ]; then
	cache_age=$(( $(date +%s) - $(stat -f '%m' "$CACHE_FILE" 2>/dev/null || echo 0) ))
	if [ "$cache_age" -lt "$CACHE_TTL" ]; then
		USE_CACHE=true
	fi
fi

if $USE_CACHE; then
	load_usage "$(cat "$CACHE_FILE")"
else
	if fetch_usage; then
		load_usage "$(cat "$CACHE_FILE")"
	elif [ -f "$CACHE_FILE" ]; then
		load_usage "$(cat "$CACHE_FILE")"
	fi
fi

# Convert the usage rate from a 0.0-1.0 fraction to a percentage
to_pct() {
	local val="$1"
	if [ -z "$val" ] || [ "$val" = "null" ] || [ "$val" = "0" ]; then
		echo ""
		return
	fi
	awk "BEGIN{printf \"%.0f\", $val * 100}" 2>/dev/null || echo ""
}

FIVE_HOUR_PCT=$(to_pct "$FIVE_HOUR_UTIL")
SEVEN_DAY_PCT=$(to_pct "$SEVEN_DAY_UTIL")

# ---------- Calculate the ideal-position cell (worked back from the reset time) ----------
# reset time - window width = start time; derive the elapsed fraction from the difference with the current time
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

IDEAL5=$(ideal_bar_pos "$FIVE_HOUR_RESET" "18000")   # 5時間 = 18000秒
IDEAL7=$(ideal_bar_pos "$SEVEN_DAY_RESET" "604800")  # 7日間 = 604800秒

# ---------- Convert epoch seconds to remaining time in Xd XXh XXm format ----------
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
		printf '  %2dh%2dm' "$hours" "$mins"
	else
		printf '%dd%2dh%2dm' "$days" "$hours" "$mins"
	fi
}

five_reset_display=""
if [ -n "$FIVE_HOUR_RESET" ] && [ "$FIVE_HOUR_RESET" != "0" ]; then
	cd5=$(countdown "$FIVE_HOUR_RESET")
	[ -n "$cd5" ] && five_reset_display="→ ${cd5}"
fi

seven_reset_display=""
if [ -n "$SEVEN_DAY_RESET" ] && [ "$SEVEN_DAY_RESET" != "0" ]; then
	cd7=$(countdown "$SEVEN_DAY_RESET")
	[ -n "$cd7" ] && seven_reset_display="→ ${cd7}"
fi

# ---------- Convert context usage to an integer percentage ----------
ctx_pct_int=0
if [ -n "$used_pct" ] && [ "$used_pct" != "null" ] && [ "$used_pct" != "0" ]; then
	ctx_pct_int=$(printf "%.0f" "$used_pct" 2>/dev/null || echo 0)
fi

# ---------- Building line 1 ----------
SEP="${GRAY} │ ${RESET}"
ctx_color=$WHITE

# Line 1: directory
line1="${WHITE}󰉋 ${dir_name}${RESET}"

# Line 2: git (only when inside a repo)
line2=""
if [ -n "$git_repo" ] && [ -n "$git_branch" ]; then
	push_mark=""
	if $git_no_remote; then
		push_mark=" ↑✗"
	else
		[ "$git_unpushed" -gt 0 ] && push_mark="${push_mark} ↑${git_unpushed}"
		[ "$git_behind" -gt 0 ] && push_mark="${push_mark} ↓${git_behind}"
	fi
	line2="${git_line_color} ${git_repo} [${git_branch}]${push_mark}${RESET}"
elif [ -n "$git_branch" ]; then
	line2="${git_line_color} [${git_branch}]${push_mark}${RESET}"
fi

# Line 3: model name + CTX
line3="${model_name}${SEP}${ctx_color}CTX ${ctx_pct_int}%${RESET}"

# ---------- Line 4 (5-hour rate limit) ----------
line4=""
if [ -n "$FIVE_HOUR_PCT" ]; then
	c5=$(color_for_pct "$FIVE_HOUR_PCT")
	bar5=$(progress_bar "$FIVE_HOUR_PCT" "$IDEAL5")
	line4="${c5}5h  ${bar5}  $(printf '%3s' "${FIVE_HOUR_PCT}")%${RESET}"
	[ -n "$five_reset_display" ] && line4+="  ${five_reset_display}"
else
	line4="${GRAY}5h  ░░░░░░░░░░   --%${RESET}"
fi

# ---------- Line 5 (7-day rate limit) ----------
line5=""
if [ -n "$SEVEN_DAY_PCT" ]; then
	c7=$(color_for_pct "$SEVEN_DAY_PCT")
	bar7=$(progress_bar "$SEVEN_DAY_PCT" "$IDEAL7")
	line5="${c7}7d  ${bar7}  $(printf '%3s' "${SEVEN_DAY_PCT}")%${RESET}"
	[ -n "$seven_reset_display" ] && line5+="  ${seven_reset_display}"
else
	line5="${GRAY}7d  ░░░░░░░░░░   --%${RESET}"
fi

# ---------- Output ----------
printf '%s\n' "$line1"
# Only emit line 2 when a git repo is present
[ -n "$line2" ] && printf '%s\n' "$line2"
printf '%s\n' "$line3"
printf '%s\n' "$line4"
printf '%s' "$line5"
