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

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

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
			has_unstaged=$(echo "$porcelain" | grep -c '^.[^ ]' 2>/dev/null || true)
			has_staged=$(echo "$porcelain" | grep -c '^[^ ?] ' 2>/dev/null || true)
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
        # This calculates the "used" percentage, not "remaining".
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

reset_display=""
if [ -n "$RESET_EPOCH" ] && [ "$RESET_EPOCH" != "0" ]; then
	cd_time=$(countdown "$RESET_EPOCH")
	[ -n "$cd_time" ] && reset_display="→ ${cd_time}"
fi

IDEAL=$(ideal_bar_pos "$RESET_EPOCH" "2592000")

# ---------- Building line 1 and line 2 ----------
SEP="${GRAY} │ ${RESET}"
line1="󰉋 ${dir_name}"
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
line3="${model_name}${SEP}CTX ${ctx_pct_int}%"

# ---------- Line 4 (Premium) ----------
# Chat is unlimited, so it is hidden to save display space
line4=""
if [ -n "$PREMIUM_USED_PCT" ]; then
	c=$(color_for_pct "$PREMIUM_USED_PCT")
	bar=$(progress_bar "$PREMIUM_USED_PCT" "$IDEAL")
	display_pct=$(printf "%.0f" "$PREMIUM_USED_PCT")
    
	# Use the "1m" prefix so the look exactly matches other AI coding CLIs' status lines
	line4="${c}1m  ${bar} $(printf '%3s' "${display_pct}")%${RESET}"
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
