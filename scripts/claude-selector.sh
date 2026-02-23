#!/usr/bin/env bash
#
# claude-selector.sh - Interactive Claude process selector for tmux
#
# Invoked via tmux keybinding (prefix + c) to list and navigate
# to Claude Code processes running in tmux panes.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/variables.sh"

# --- Claudeプロセスを収集 ---
entries=()
pane_ids=()

for sf in "$state_dir"/*.state; do
	[ -f "$sf" ] || continue
	id=$(basename "$sf" .state)
	state=$(<"$sf")
	meta_file="$state_dir/${id}.meta"
	[ -f "$meta_file" ] || continue
	read -r project location < "$meta_file"

	case "$state" in
		processing|low_once) icon="🤖" ;;
		prompting)           icon="💬" ;;
		waiting)             icon="✅" ;;
		exited)              icon="💀" ;;
		*)                   continue ;;
	esac

	entries+=("${icon} ${project} (${location}) [%${id}]")
	pane_ids+=("$id")
done

count=${#entries[@]}

# --- ペインIDで遷移 ---
navigate_to_pane() {
	local id="$1"
	local target="%${id}"
	tmux switch-client -t "$target" 2>/dev/null
	tmux select-window -t "$target" 2>/dev/null
	tmux select-pane -t "$target" 2>/dev/null
}

# --- 件数に応じた処理 ---
if [ "$count" -eq 0 ]; then
	tmux display-message "No Claude processes found"
	exit 0
fi

if [ "$count" -eq 1 ]; then
	navigate_to_pane "${pane_ids[0]}"
	exit 0
fi

# --- ポップアップモード（fzfをdisplay-popup内で使用） ---
if [ "$1" = "--popup" ]; then
	selected=$(printf '%s\n' "${entries[@]}" | fzf --ansi \
		--prompt="Claude> " \
		--header="Select a Claude process" \
		--layout=reverse)

	if [ -n "$selected" ]; then
		# [%123] からペインIDを抽出
		pane_id=$(echo "$selected" | grep -oE '%[0-9]+' | tail -1)
		pane_id="${pane_id#%}"
		navigate_to_pane "$pane_id"
	fi
	exit 0
fi

# --- エントリポイント（キーバインドから呼び出し） ---
if command -v fzf &>/dev/null; then
	tmux display-popup -E "$0 --popup"
else
	# フォールバック: tmux display-menu
	menu_args=(-T "Claude Processes")
	for i in "${!entries[@]}"; do
		id="${pane_ids[$i]}"
		target="%${id}"
		menu_args+=("${entries[$i]}" "" "switch-client -t $target ; select-window -t $target ; select-pane -t $target")
	done
	tmux display-menu "${menu_args[@]}"
fi
