#!/bin/bash
# Claude Code status line script (with rate-limit display)
# Line 1: model name | context usage | lines edited | directory name | repo name:branch name
# Line 2: 5-hour rate-limit progress bar
# Line 3: 7-day rate-limit progress bar
#
# Use the official rate_limits field introduced in v2.1.80

input=$(cat)

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
	"effort=" + (.effort.level // "" | @sh),
	"used_pct=" + (.context_window.used_percentage // 0 | tostring),
	"ctx_size=" + (.context_window.context_window_size // 0 | tostring),
	"cwd=" + (.cwd // "" | @sh),
	"cc_version=" + (.version // "0.0.0" | @sh),
	"five_hour_pct=" + (.rate_limits.five_hour.used_percentage // "" | tostring),
	"five_hour_resets_at=" + (.rate_limits.five_hour.resets_at // 0 | tostring),
	"seven_day_pct=" + (.rate_limits.seven_day.used_percentage // "" | tostring),
	"seven_day_resets_at=" + (.rate_limits.seven_day.resets_at // 0 | tostring)
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
git_not_owned=false
git_unpushed=0
git_behind=0
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
	git_branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null || true)
	if [ -n "$git_branch" ]; then
		# Use the git top-level directory name as the repo name
		git_toplevel=$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel 2>/dev/null || true)
		git_repo=$(basename "$git_toplevel")

		# Check whether a remote is configured
		has_remote=$(git -C "$cwd" --no-optional-locks remote 2>/dev/null | wc -l | tr -d ' ')

		# Check whether this is someone else's repo (one that was just cloned)
		if [ "$has_remote" -gt 0 ]; then
			github_user=$(grep '^\s*user:' ~/.config/gh/hosts.yml 2>/dev/null | head -1 | awk '{print $2}')
			if [ -n "$github_user" ]; then
				remote_url=$(git -C "$cwd" --no-optional-locks remote get-url origin 2>/dev/null || true)
				if [ -n "$remote_url" ] && ! echo "$remote_url" | grep -q "$github_user"; then
					# Someone else's repo → no color, no ↑↓
					git_not_owned=true
					git_line_color=""
				fi
			fi
		fi

		if ! $git_not_owned; then
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
			elif [ "$has_remote" -eq 0 ]; then
				# No remote → blue
				git_line_color="$BLUE"
				git_no_remote=true
			else
				# Check whether there are unpushed commits
				git_unpushed=$(git -C "$cwd" --no-optional-locks rev-list "@{u}..HEAD" --count 2>/dev/null || echo 0)
				git_behind=$(git -C "$cwd" --no-optional-locks rev-list "HEAD..@{u}" --count 2>/dev/null || echo 0)
				if [ "$git_unpushed" -gt 0 ] || [ "$git_behind" -gt 0 ]; then
					# Unpushed/unpulled commits exist → blue
					git_line_color="$BLUE"
				else
					# Fully clean state → green
					git_line_color="$GREEN"
				fi
			fi
		fi
	fi
fi

# ---------- Rate-limit info (from the official rate_limits field) ----------
# From v2.1.80 onward, the rate_limits field is included in stdin's JSON
# resets_at arrives as-is, as epoch seconds (an integer)
FIVE_HOUR_PCT=""
FIVE_HOUR_RESET="0"
if [ -n "$five_hour_pct" ] && [ "$five_hour_pct" != "null" ] && [ "$five_hour_pct" != "" ]; then
	FIVE_HOUR_PCT=$(printf "%.0f" "$five_hour_pct" 2>/dev/null || echo "")
	FIVE_HOUR_RESET="$five_hour_resets_at"
fi

SEVEN_DAY_PCT=""
SEVEN_DAY_RESET="0"
if [ -n "$seven_day_pct" ] && [ "$seven_day_pct" != "null" ] && [ "$seven_day_pct" != "" ]; then
	SEVEN_DAY_PCT=$(printf "%.0f" "$seven_day_pct" 2>/dev/null || echo "")
	SEVEN_DAY_RESET="$seven_day_resets_at"
fi

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
		printf '   %02dh %02dm' "$hours" "$mins"
	else
		printf '%dd %02dh %02dm' "$days" "$hours" "$mins"
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
	GH_VIS_SCRIPT="${GH_VISIBILITY_SCRIPT:-gh-visibility.sh}"
	vis=$("${GH_VIS_SCRIPT}" "$git_toplevel" 2>/dev/null || echo "")
	push_mark=""
	if $git_no_remote; then
		push_mark=""
	else
		[ "$git_unpushed" -gt 0 ] && push_mark="${push_mark} ↑${git_unpushed}"
		[ "$git_behind" -gt 0 ] && push_mark="${push_mark} ↓${git_behind}"
	fi
	if [ "$git_branch" = "main" ] || [ "$git_branch" = "master" ]; then
		line2="${git_line_color}${vis:-} ${git_repo} [${git_branch}]${push_mark}${RESET}"
	else
		line2="${git_line_color}${vis:-} ${git_repo} ${MAGENTA}[${git_branch}]${git_line_color}${push_mark}${RESET}"
	fi
elif [ -n "$git_branch" ]; then
	if [ "$git_branch" = "main" ] || [ "$git_branch" = "master" ]; then
		line2="${git_line_color} [${git_branch}]${push_mark}${RESET}"
	else
		line2="${git_line_color} ${MAGENTA}[${git_branch}]${git_line_color}${push_mark}${RESET}"
	fi
fi

# Line 3: model name + effort + CTX
# effort is only passed for models that support it, so skip the display when it's empty
effort_part=""
if [ -n "$effort" ]; then
	effort_part="${SEP}${effort}"
fi
line3="${model_name}${effort_part}${SEP}${ctx_color}CTX ${ctx_pct_int}%${RESET}"

# ---------- Build a reset-time string from epoch seconds ----------
# Format like " 3/18 Wed 14:32", with month/day space-padded
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

# ---------- Line 4 (5-hour rate limit) ----------
line4=""
if [ -n "$FIVE_HOUR_PCT" ]; then
	c5=$(color_for_pct "$FIVE_HOUR_PCT")
	bar5=$(progress_bar "$FIVE_HOUR_PCT" "$IDEAL5")
	line4="${c5}5h ${bar5} $(printf '%3s' "${FIVE_HOUR_PCT}")%${RESET}"
	if [ -n "$five_reset_display" ]; then
		dt5=$(reset_datetime "$FIVE_HOUR_RESET")
		line4+=" ${five_reset_display} ${dt5}"
	fi
else
	line4="${GRAY}5h  ░░░░░░░░░░   --%${RESET}"
fi

# ---------- Line 5 (7-day rate limit) ----------
line5=""
if [ -n "$SEVEN_DAY_PCT" ]; then
	c7=$(color_for_pct "$SEVEN_DAY_PCT")
	bar7=$(progress_bar "$SEVEN_DAY_PCT" "$IDEAL7")
	line5="${c7}7d ${bar7} $(printf '%3s' "${SEVEN_DAY_PCT}")%${RESET}"
	if [ -n "$seven_reset_display" ]; then
		dt7=$(reset_datetime "$SEVEN_DAY_RESET")
		line5+=" ${seven_reset_display} ${dt7}"
	fi
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
