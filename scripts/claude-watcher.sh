#!/usr/bin/env bash
#
# claude-watcher.sh - Claude Code process monitor for tmux status bar
#
# Periodically invoked from tmux status-right to monitor Claude Code processes
# running in each pane. Displays per-process status in the status bar.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/variables.sh"

# --- Load configuration ---
CPU_THRESHOLD=$(get_tmux_option "$cpu_threshold_option" "$cpu_threshold_default")
DISPLAY_TIMEOUT=$(get_tmux_option "$display_timeout_option" "$display_timeout_default")
MAX_NAME_LENGTH=$(get_tmux_option "$max_name_length_option" "$max_name_length_default")
PROMPT_PATTERN=$(get_tmux_option "$prompt_pattern_option" "$prompt_pattern_default")

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

# Derive a project name from the pane's working directory (truncated).
get_project_name() {
	local pane_path="$1"
	local name
	name=$(basename "$pane_path")
	# プロジェクト名を最大文字数に切り詰め
	if [ "${#name}" -gt "$MAX_NAME_LENGTH" ]; then
		name="${name:0:$MAX_NAME_LENGTH}"
	fi
	echo "$name"
}

# Save metadata (project name and location) for a pane.
save_meta() {
	local local_id="$1"
	local project="$2"
	local location="$3"
	echo "$project $location" > "$state_dir/${local_id}.meta"
}

# Record the timestamp when a process completes or exits.
save_done_at() {
	local local_id="$1"
	date +%s > "$state_dir/${local_id}.done_at"
}

# Check if the pane is showing a Claude Code permission prompt.
# Args: local_id (numeric pane ID without %)
is_prompting() {
	local pane_id="$1"
	local content
	content=$(tmux capture-pane -t "%${pane_id}" -p -J -S -30 2>/dev/null) || return 1
	echo "$content" | tail -n 20 | grep -qE "$PROMPT_PATTERN"
}

# --- Main monitor loop ---

# Scan all panes.
# Format: #{pane_id}\t#{pane_pid}\t#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_current_path}
while IFS=$'\t' read -r pane_id pane_pid session_name window_index pane_index pane_path; do
	# State files for this pane (pane_id is like %0, %1)
	local_id="${pane_id//%/}"
	state_file="$state_dir/${local_id}.state"
	meta_file="$state_dir/${local_id}.meta"
	done_file="$state_dir/${local_id}.done_at"

	# Look for a Claude process
	claude_pid=$(find_claude_pid "$pane_pid")

	# Derive display info
	project=$(get_project_name "$pane_path")
	location="${session_name}:${window_index}.${pane_index}"

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
			save_meta "$local_id" "$project" "$location"
			rm -f "$done_file"
		else
			# CPU below threshold
			prev_state=""
			[ -f "$state_file" ] && prev_state=$(<"$state_file")

			case "$prev_state" in
				processing)
					if is_prompting "$local_id"; then
						echo "prompting" > "$state_file"
					else
						echo "low_once" > "$state_file"
					fi
					save_meta "$local_id" "$project" "$location"
					;;
				low_once)
					if is_prompting "$local_id"; then
						echo "prompting" > "$state_file"
					else
						echo "waiting" > "$state_file"
						save_done_at "$local_id"
					fi
					save_meta "$local_id" "$project" "$location"
					;;
				prompting)
					if ! is_prompting "$local_id"; then
						# プロンプトが消えた（ユーザーが応答した）→ デバウンスへ
						echo "low_once" > "$state_file"
						save_meta "$local_id" "$project" "$location"
					fi
					;;
			esac
		fi
	else
		# No Claude process found
		prev_state=""
		[ -f "$state_file" ] && prev_state=$(<"$state_file")

		if [ "$prev_state" = "processing" ] || [ "$prev_state" = "low_once" ] || [ "$prev_state" = "prompting" ]; then
			# processing/low_once → exited (process disappeared)
			echo "exited" > "$state_file"
			save_meta "$local_id" "$project" "$location"
			save_done_at "$local_id"
		elif [ "$prev_state" = "waiting" ] || [ "$prev_state" = "exited" ]; then
			# タイムアウト済みでなければ保持（ステータスバー出力で処理）
			:
		else
			# prev_state is empty — pane without Claude, clean up stale files
			rm -f "$state_file" "$meta_file" "$done_file"
		fi
	fi
done < <(tmux list-panes -a -F '#{pane_id}	#{pane_pid}	#{session_name}	#{window_index}	#{pane_index}	#{pane_current_path}')

# --- Cleanup orphaned state files ---
# 存在しないペインのステートファイルを削除
existing_panes=$(tmux list-panes -a -F '#{pane_id}' | sed 's/^%//')
for sf in "$state_dir"/*.state; do
	[ -f "$sf" ] || continue
	id=$(basename "$sf" .state)
	if ! echo "$existing_panes" | grep -qx "$id"; then
		rm -f "$state_dir/${id}.state" "$state_dir/${id}.meta" "$state_dir/${id}.done_at" "$state_dir/${id}.notified"
	fi
done

# --- Status bar output ---
# 現在アクティブなペインは自分で見えるので表示しない
active_pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null | sed 's/^%//')

# 全ペインの状態を収集して個別表示
output=""
now=$(date +%s)
for sf in "$state_dir"/*.state; do
	[ -f "$sf" ] || continue
	id=$(basename "$sf" .state)
	# アクティブペインはスキップ
	[ "$id" = "$active_pane" ] && continue
	state=$(<"$sf")
	meta_file="$state_dir/${id}.meta"
	done_file="$state_dir/${id}.done_at"

	[ -f "$meta_file" ] || continue
	read -r project location < "$meta_file"

	case "$state" in
		processing|low_once)
			output+="🤖${project}(${location}) "
			;;
		prompting)
			output+="💬${project}(${location}) "
			;;
		waiting)
			# タイムアウトチェック
			if [ -f "$done_file" ]; then
				done_at=$(<"$done_file")
				if [ $((now - done_at)) -gt "$DISPLAY_TIMEOUT" ]; then
					rm -f "$sf" "$meta_file" "$done_file"
					continue
				fi
			fi
			output+="✅${project}(${location}) "
			;;
		exited)
			if [ -f "$done_file" ]; then
				done_at=$(<"$done_file")
				if [ $((now - done_at)) -gt "$DISPLAY_TIMEOUT" ]; then
					rm -f "$sf" "$meta_file" "$done_file"
					continue
				fi
			fi
			output+="💀${project}(${location}) "
			;;
	esac
done

# 末尾の空白を除去して出力
echo "${output% }"
