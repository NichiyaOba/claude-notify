#!/usr/bin/env bash
#
# claude-notify.tmux - TPM entry point
#
# A tmux plugin that monitors Claude Code and notifies on response completion.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/scripts/helpers.sh"
source "$CURRENT_DIR/scripts/variables.sh"

watcher_interpolation="#($CURRENT_DIR/scripts/claude-watcher.sh)"

add_watcher_to_status_right() {
	local status_right_value
	status_right_value="$(get_tmux_option "status-right" "")"
	# Prevent duplicate insertion
	if ! [[ "$status_right_value" == *"claude-watcher"* ]]; then
		local new_value="${watcher_interpolation} ${status_right_value}"
		set_tmux_option "status-right" "$new_value"
	fi
}

set_status_interval() {
	# Set interval to 5s for responsive monitoring
	local current_interval
	current_interval="$(get_tmux_option "status-interval" "15")"
	if [ "$current_interval" -gt 5 ] 2>/dev/null; then
		tmux set-option -g status-interval 5
	fi
}

detect_and_set_terminal_app() {
	local current
	current="$(get_tmux_option "$terminal_app_option" "")"
	[ -n "$current" ] && return  # ユーザーが手動設定済み

	local client_pid terminal_pid bundle_id
	client_pid=$(tmux display-message -p '#{client_pid}' 2>/dev/null)
	if [ -n "$client_pid" ]; then
		terminal_pid=$(ps -o ppid= -p "$client_pid" 2>/dev/null | tr -d ' ')
		if [ -n "$terminal_pid" ]; then
			local app_name
			app_name=$(ps -o comm= -p "$terminal_pid" 2>/dev/null)
			case "$app_name" in
				*ghostty*) bundle_id="com.mitchellh.ghostty" ;;
				*iTerm*)   bundle_id="com.googlecode.iterm2" ;;
				*Terminal*) bundle_id="com.apple.Terminal" ;;
				*warp*)    bundle_id="dev.warp.Warp-Stable" ;;
			esac
		fi
	fi
	set_tmux_option "$terminal_app_option" "${bundle_id:-com.apple.Terminal}"
}

main() {
	detect_and_set_terminal_app
	add_watcher_to_status_right
	set_status_interval
}
main
