#!/usr/bin/env bash

# CPU% threshold for processing detection (two consecutive ticks below → waiting)
cpu_threshold_option="@claude-notify-cpu-threshold"
cpu_threshold_default="3"

# How long (seconds) to keep completed/exited entries visible in the status bar
display_timeout_option="@claude-notify-display-timeout"
display_timeout_default="30"

# Maximum characters for project name display
max_name_length_option="@claude-notify-max-name-length"
max_name_length_default="10"

# Key binding for Claude process selector
selector_key_option="@claude-notify-selector-key"
selector_key_default="C"

# Regex pattern for detecting Claude Code permission prompts
prompt_pattern_option="@claude-notify-prompt-pattern"
prompt_pattern_default='(Do you want to proceed|[0-9]+\. Yes|Type something\.|❯ [0-9]+\.)'

# Runtime state file directory
state_dir="${TMPDIR:-/tmp}/tmux-claude-watcher"
