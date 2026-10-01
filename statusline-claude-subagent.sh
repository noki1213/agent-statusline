#!/bin/bash
# Claude Code subagent status line script (subagentStatusLine)
# One row per subagent in the agent panel:
#   <type>  <description>  <model> <effort>  <elapsed>
# The description is shortened to fit the row width.

input=$(cat)

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

transcript_path=$(echo "$input" | jq -r '.transcript_path // ""')
subagent_dir="${transcript_path%.jsonl}/subagents"

# The task's effort is absent when the subagent inherits the session's effort,
# so fall back to the effort recorded in its own transcript, then the session's.
last_effort() {
	[ -f "$1" ] || return
	tail -n 40 "$1" | grep -o '"effort":"[^"]*"' | tail -n 1 | cut -d'"' -f4
}
session_effort=""
session_effort_read=false

now_ms=$(($(date +%s) * 1000))

echo "$input" | jq -c '.columns as $c | .tasks[]? | . + {columns: $c}' | while read -r task; do
	id=$(echo "$task" | jq -r '.id')
	# The agent type (general-purpose, Explore, ...) is only in the subagent's meta file
	agent_type=$(jq -r '.agentType // ""' "$subagent_dir/agent-${id}.meta.json" 2>/dev/null)
	effort=$(echo "$task" | jq -r '.effort // "" | tostring')
	if [ -z "$effort" ]; then
		effort=$(last_effort "$subagent_dir/agent-${id}.jsonl")
		if [ -z "$effort" ]; then
			if ! $session_effort_read; then
				session_effort=$(last_effort "$transcript_path")
				session_effort_read=true
			fi
			effort="$session_effort"
		fi
	fi

	echo "$task" | jq -c \
		--arg effort "$effort" --arg agent_type "$agent_type" --argjson now "$now_ms" \
		--arg green "$GREEN" --arg red "$RED" --arg gray "$GRAY" \
		--arg cyan "$CYAN" --arg reset "$RESET" '
		# Display width: wide (CJK and similar) characters take two columns
		def width: [explode[] | if . >= 4352 then 2 else 1 end] | add // 0;
		def fit($w):
			if $w <= 0 then ""
			elif width <= $w then .
			else (explode | reduce .[] as $ch ({s: [], w: 0};
				(if $ch >= 4352 then 2 else 1 end) as $cw
				| if .w + $cw <= $w - 1 then {s: (.s + [$ch]), w: (.w + $cw)} else . end)
				| .s | implode) + "…"
			end;
		def model_name:
			sub("^claude-"; "") | sub("-[0-9]{8}$"; "") | sub("\\[.*\\]$"; "") | split("-")
			| (.[0][:1] | ascii_upcase) + .[0][1:] + (if length > 1 then " " + (.[1:] | join(".")) else "" end);
		def elapsed($ms):
			($ms / 1000 | floor) as $s
			| if $s >= 3600 then "\($s / 3600 | floor)h\($s % 3600 / 60 | floor)m"
			  elif $s >= 60 then "\($s / 60 | floor)m\($s % 60)s"
			  else "\($s)s" end;

		(.status // "") as $status
		| (if $status == "running" then $green elif $status == "failed" or $status == "killed" then $red else $gray end) as $color
		| (.name // (if $agent_type == "" then null else $agent_type end) // .type // "agent") as $kind
		| (.label // .description // "" | gsub("[\r\n]+"; " ")) as $desc
		| ([(.model // "" | if . == "" then empty else model_name end), (if $effort == "" then empty else $effort end)] | join(" ")) as $model
		| (if $status == "running" and (.startTime // 0) > 0 then elapsed($now - .startTime) else "" end) as $time
		| ([$model, $time] | map(select(. != "")) | join("  ")) as $tail
		# kind (colored by status) + "  " + desc + "  " + tail
		| ((.columns // 80) - ($kind | width) - 2 - (if $tail == "" then 0 else ($tail | width) + 2 end)) as $room
		| ($desc | fit($room)) as $d
		| {id: .id, content: (
			$color + $kind + $reset
			+ (if $d == "" then "" else "  " + $d end)
			+ (if $tail == "" then "" else "  " + $cyan + $tail + $reset end))}'
done
