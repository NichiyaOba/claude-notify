#!/usr/bin/env bash

# CPU% threshold for processing detection (two consecutive ticks below → waiting)
cpu_threshold_option="@claude-notify-cpu-threshold"
cpu_threshold_default="3"

# Notification sound (macOS only)
sound_option="@claude-notify-sound"
sound_default="Glass"

# Enable/disable OS notifications
macos_notify_option="@claude-notify-macos-notify"
macos_notify_default="on"

# Runtime state file directory
state_dir="${TMPDIR:-/tmp}/tmux-claude-watcher"
