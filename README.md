# claude-map

A tmux plugin that monitors [Claude Code](https://docs.anthropic.com/en/docs/claude-code) processes and displays their status in the tmux status bar.

## Features

- Scans all tmux panes for running Claude Code processes
- Detects response completion via CPU usage state transitions
- Detects permission prompts (tool approval requests) and shows distinct status
- Quick navigation to Claude panes via `prefix + C` selector
- Displays per-process status in the status bar with project name and pane location
- Completed/exited indicators auto-clear after a configurable timeout

### Status Bar Format

```
🤖myapp(0:1.0) 💬api(0:2.1) ✅tools(1:0.0)
```

| Icon | Meaning |
|------|---------|
| 🤖 | Processing (CPU active) |
| 💬 | Awaiting permission (user action required) |
| ✅ | Completed (auto-clears after timeout) |
| 💀 | Exited unexpectedly (auto-clears after timeout) |

Each entry shows `icon` + `project_name` + `(session:window.pane)`.

### Claude Process Selector

Press `prefix + C` (Shift+c) to open the Claude process selector. Behavior depends on the number of active Claude processes:

- **0 processes**: displays a message
- **1 process**: navigates directly to that pane
- **2+ processes**: opens an interactive selector (fzf popup if available, otherwise tmux display-menu)

> **Note**: デフォルトキーは `C`（Shift+c）です。tmux 標準の `prefix + c`（新しいウィンドウ作成）と競合しないようにしています。変更したい場合は `@claude-map-selector-key` を設定してください。

## Requirements

- tmux 3.0+
- [TPM](https://github.com/tmux-plugins/tpm)

## Installation

### With TPM

Add to `~/.tmux.conf`:

```bash
set -g @plugin 'NichiyaOba/claude-map'
```

Reload tmux and install:

```bash
tmux source-file ~/.tmux.conf
# Press prefix + I to install plugins
```

### Manual

```bash
git clone https://github.com/NichiyaOba/claude-map.git ~/.tmux/plugins/claude-map
```

Add to `~/.tmux.conf`:

```bash
run-shell ~/.tmux/plugins/claude-map/claude-map.tmux
```

## Configuration

All options are set in `~/.tmux.conf`:

| Option | Default | Description |
|--------|---------|-------------|
| `@claude-map-cpu-threshold` | `3` | CPU% threshold for "processing" detection |
| `@claude-map-display-timeout` | `30` | Seconds to keep completed/exited entries visible |
| `@claude-map-max-name-length` | `10` | Maximum characters for project name display |
| `@claude-map-selector-key` | `C` | Key binding for Claude process selector (with prefix) |
| `@claude-map-prompt-pattern` | `[0-9]+\. Yes` | Regex pattern for detecting permission prompts |

Example:

```bash
set -g @claude-map-cpu-threshold 5
set -g @claude-map-display-timeout 60
set -g @claude-map-max-name-length 15
```

### Status Bar Width

The default `status-right-length` (40 characters) may be too narrow when monitoring multiple Claude processes. Increase it to ensure all entries are visible:

```bash
set -g status-right-length 120
```

## How It Works

The watcher script runs on each tmux status refresh (every 5 seconds) and tracks Claude Code processes through a simple state machine:

```
processing 🤖
  ├── CPU ≤ threshold + prompt detected → prompting 💬
  ├── CPU ≤ threshold (1st tick)        → low_once 🤖
  └── process exits                     → exited 💀

prompting 💬
  ├── CPU > threshold                   → processing 🤖
  ├── prompt disappears                 → low_once 🤖
  └── process exits                     → exited 💀

low_once 🤖
  ├── CPU > threshold                   → processing 🤖
  ├── CPU ≤ threshold + prompt detected → prompting 💬
  ├── CPU ≤ threshold (2nd tick)        → waiting ✅
  └── process exits                     → exited 💀

waiting ✅  → auto-clears after timeout
exited 💀   → auto-clears after timeout
```

- **processing**: Claude is actively generating a response (CPU > threshold) — displayed as 🤖
- **prompting**: Claude is waiting for permission approval (tool execution) — displayed as 💬
- **low_once**: CPU dropped below threshold once — debounce tick to prevent false positives
- **waiting**: CPU stayed low for 2 consecutive ticks — displayed as ✅
- **exited**: Claude process disappeared while processing — displayed as 💀

Completed and exited entries are automatically removed from the status bar after the configured timeout (default: 30 seconds).

Permission prompt detection uses `tmux capture-pane` to scan the pane content for patterns matching Claude Code's tool approval UI. The default pattern (`[0-9]+\. Yes`) matches numbered choice options. Override with `@claude-map-prompt-pattern` if needed.

## License

[MIT](LICENSE)
