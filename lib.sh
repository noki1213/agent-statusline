#!/bin/bash
# Shared by the status line scripts: colors, usage bars and reset times.
# Sourced, not run.

# ---------- ANSI colors ----------
GREEN=$'\e[38;2;51;165;165m'
YELLOW=$'\e[38;2;244;201;128m'
RED=$'\e[38;2;252;156;156m'
BLUE=$'\e[38;2;74;143;191m'
CYAN=$'\e[38;2;74;174;200m'
WHITE=$'\e[38;2;196;196;196m'
GRAY=$'\e[38;2;74;88;92m'
BLACK=$'\e[38;2;0;0;0m'
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
	# The caller draws the bar in color_for_pct's color; a marker on a filled cell
	# is drawn black (the terminal background) on that color, so the used cell stays visible
	local fg bg
	fg=$(color_for_pct "$pct")
	bg="${fg/38;/48;}"
	local bar=""
	for i in $(seq 1 10); do
		if [ -n "$ideal" ] && [ "$i" -eq "$ideal" ]; then
			if [ "$i" -le "$filled" ]; then
				bar="${bar}${bg}${BLACK}┃${RESET}${fg}"
			else
				bar="${bar}┃"
			fi
		elif [ "$i" -le "$filled" ]; then
			bar="${bar}█"
		else
			bar="${bar}░"
		fi
	done
	printf '%s' "$bar"
}

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
	[ "$elapsed" -le 0 ] && echo "" && return
	# The marker goes in the cell that contains the elapsed fraction (e.g. 13% -> cell 2)
	local pos
	pos=$(awk "BEGIN{p=int($elapsed * 10 / $window_sec); if (p * $window_sec < $elapsed * 10) p++; printf \"%d\", p}" 2>/dev/null || echo "")
	[ "$pos" -gt 10 ] 2>/dev/null && pos=10
	[ "$pos" -lt 1 ] 2>/dev/null && pos=1
	echo "$pos"
}

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

# ---------- Repo name ----------
# Print the repo name for a directory. In a linked worktree, use the main
# worktree's folder name rather than the worktree's own folder name.
git_repo_name() {
	local dir="$1" top gitdir common main
	{
		read -r top
		read -r gitdir
		read -r common
	} < <(git -C "$dir" --no-optional-locks rev-parse --show-toplevel --absolute-git-dir --path-format=absolute --git-common-dir 2>/dev/null)
	if [ -n "$gitdir" ] && [ "$gitdir" != "$common" ]; then
		main=$(git -C "$dir" --no-optional-locks worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
		[ -n "$main" ] && top="$main"
	fi
	basename "$top"
}
