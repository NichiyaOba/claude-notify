#!/usr/bin/env bash
#
# claude-watcher.sh - Claude Code process monitor & notification script
#
# Periodically invoked from tmux status-right to monitor Claude Code processes
# running in each pane. Sends popup + OS notification on response completion
# (processing → waiting/exited).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/variables.sh"

# --- Load configuration ---
CPU_THRESHOLD=$(get_tmux_option "$cpu_threshold_option" "$cpu_threshold_default")
SOUND=$(get_tmux_option "$sound_option" "$sound_default")
MACOS_NOTIFY=$(get_tmux_option "$macos_notify_option" "$macos_notify_default")
USE_TERMINAL_NOTIFIER=$(get_tmux_option "$terminal_notifier_option" "$terminal_notifier_default")

mkdir -p "$state_dir"

# --- Utilities ---

# Find a Claude process among the direct children of the given shell PID.
# Args: shell_pid
# Output: Claude's PID (empty if not found)
find_claude_pid() {
	local shell_pid="$1"
	local child_pids
	child_pids=$(pgrep -P "$shell_pid" 2>/dev/null)
	for pid in $child_pids; do
		local cmd
		cmd=$(ps -p "$pid" -o comm= 2>/dev/null)
		if [[ "$cmd" == *"claude"* ]]; then
			echo "$pid"
			return
		fi
	done
}

# Get CPU usage percentage for a PID.
# Args: pid
# Output: integer part of CPU%
get_cpu_usage() {
	local pid="$1"
	local cpu
	cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')
	if [ -n "$cpu" ]; then
		printf "%.0f" "$cpu" 2>/dev/null || echo "0"
	else
		echo ""
	fi
}

# Derive a project name from the pane's working directory.
get_project_name() {
	local pane_path="$1"
	basename "$pane_path"
}

# Send an OS notification (macOS or Linux).
# Args: title, message, session, window, pane_index
send_notification() {
	local title="$1"
	local message="$2"
	local session="$3"
	local window="$4"
	local pane_index="$5"

	[ "$MACOS_NOTIFY" = "on" ] || return

	if [[ "$OSTYPE" == darwin* ]]; then
		if [ "$USE_TERMINAL_NOTIFIER" = "on" ] && command -v terminal-notifier >/dev/null 2>&1; then
			local tmux_path terminal_app navigate_cmd
			tmux_path=$(command -v tmux)
			terminal_app=$(get_tmux_option "$terminal_app_option" "com.apple.Terminal")

			navigate_cmd="${tmux_path} select-window -t '${session}:${window}' && ${tmux_path} select-pane -t '${pane_index}'"

			terminal-notifier \
				-title "$title" \
				-message "$message" \
				-sound "$SOUND" \
				-execute "$navigate_cmd" \
				-activate "$terminal_app" \
				-group "claude-notify-${session}-${window}-${pane_index}" \
				2>/dev/null &
		else
			# フォールバック: osascript（クリック非対応）
			local safe_title="${title//\"/\\\"}"
			local safe_message="${message//\"/\\\"}"
			osascript -e "display notification \"$safe_message\" with title \"$safe_title\" sound name \"$SOUND\"" 2>/dev/null &
		fi
	elif command -v notify-send >/dev/null 2>&1; then
		notify-send "$title" "$message" 2>/dev/null &
	fi
}

# Show a tmux popup notification (Enter to jump, Esc to dismiss).
send_tmux_popup() {
	local target_pane="$1"
	local session="$2"
	local window="$3"
	local pane_index="$4"
	local project="$5"
	local event_type="$6"  # "completed" or "exited"

	local display_text
	if [ "$event_type" = "exited" ]; then
		display_text="Claude Code exited"
	else
		display_text="Claude Code response completed"
	fi

	# Escape single quotes for safe shell embedding
	local sq="'"
	project="${project//$sq/$sq\\$sq$sq}"
	session="${session//$sq/$sq\\$sq$sq}"

	tmux display-popup -E -T " Claude Notify " -w 50 -h 8 \
		"printf '\n  📍 %s (%s:%s.%s)\n\n  %s\n\n  Enter: Jump to pane  |  Esc: Dismiss\n' \
		'$project' '$session' '$window' '$pane_index' '$display_text'; \
		read -rsn1 key; \
		if [ \"\$key\" = '' ]; then \
			tmux select-window -t '$session:$window' && tmux select-pane -t '$pane_index'; \
		fi"
}

# Dispatch notifications for a pane event.
notify() {
	local pane_id="$1"
	local session="$2"
	local window="$3"
	local pane_index="$4"
	local pane_path="$5"
	local event_type="$6"

	local project
	project=$(get_project_name "$pane_path")

	# OS notification
	if [ "$event_type" = "exited" ]; then
		send_notification "Claude Code - $project" "Process exited ($session:$window.$pane_index)" \
			"$session" "$window" "$pane_index"
	else
		send_notification "Claude Code - $project" "Response completed ($session:$window.$pane_index)" \
			"$session" "$window" "$pane_index"
	fi

	# tmux popup (run in background to avoid blocking the monitor)
	send_tmux_popup "$pane_id" "$session" "$window" "$pane_index" "$project" "$event_type" &
}

# --- Main monitor loop ---

# Scan all panes.
# Format: #{pane_id}\t#{pane_pid}\t#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_current_path}
while IFS=$'\t' read -r pane_id pane_pid session_name window_index pane_index pane_path; do
	# State files for this pane (pane_id is like %0, %1)
	local_id="${pane_id//%/}"
	state_file="$state_dir/${local_id}.state"
	notified_file="$state_dir/${local_id}.notified"

	# Look for a Claude process
	claude_pid=$(find_claude_pid "$pane_pid")

	if [ -n "$claude_pid" ]; then
		# Claude is running
		cpu=$(get_cpu_usage "$claude_pid")

		if [ -z "$cpu" ]; then
			# Failed to read CPU — skip
			continue
		fi

		if [ "$cpu" -gt "$CPU_THRESHOLD" ] 2>/dev/null; then
			# Processing state
			echo "processing" > "$state_file"
			# Reset notification flag
			rm -f "$notified_file"
		else
			# CPU below threshold
			prev_state=""
			[ -f "$state_file" ] && prev_state=$(<"$state_file")

			if [ "$prev_state" = "processing" ]; then
				# processing → first low-CPU tick: transition to low_once
				echo "low_once" > "$state_file"
			elif [ "$prev_state" = "low_once" ]; then
				# Two consecutive low-CPU ticks → waiting (response completed)
				echo "waiting" > "$state_file"
				if [ ! -f "$notified_file" ]; then
					notify "$pane_id" "$session_name" "$window_index" "$pane_index" "$pane_path" "completed"
					touch "$notified_file"
				fi
			fi
			# If prev_state is waiting or empty, do nothing (initial state or already notified)
		fi
	else
		# No Claude process found
		prev_state=""
		[ -f "$state_file" ] && prev_state=$(<"$state_file")

		if [ "$prev_state" = "processing" ] || [ "$prev_state" = "low_once" ]; then
			# processing/low_once → exited (process disappeared)
			echo "exited" > "$state_file"
			if [ ! -f "$notified_file" ]; then
				notify "$pane_id" "$session_name" "$window_index" "$pane_index" "$pane_path" "exited"
				touch "$notified_file"
			fi
		elif [ "$prev_state" = "waiting" ] || [ "$prev_state" = "exited" ]; then
			# Already notified — clean up state files
			rm -f "$state_file" "$notified_file"
		fi
		# If prev_state is empty, do nothing (pane without Claude)
	fi
done < <(tmux list-panes -a -F '#{pane_id}	#{pane_pid}	#{session_name}	#{window_index}	#{pane_index}	#{pane_current_path}')

# --- Status bar output ---
# Count panes currently in processing state
processing_count=0
for sf in "$state_dir"/*.state; do
	[ -f "$sf" ] || continue
	state=$(<"$sf")
	if [ "$state" = "processing" ] || [ "$state" = "low_once" ]; then
		processing_count=$((processing_count + 1))
	fi
done

if [ "$processing_count" -gt 0 ]; then
	echo "🤖${processing_count}"
else
	echo ""
fi
