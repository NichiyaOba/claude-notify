# claude-notify

A tmux plugin that monitors [Claude Code](https://docs.anthropic.com/en/docs/claude-code) processes and sends notifications when responses complete.

## Features

- Scans all tmux panes for running Claude Code processes
- Detects response completion via CPU usage state transitions
- Sends a tmux popup with one-key navigation to the target pane
- Sends OS notifications (macOS & Linux)
- Clickable notifications: click to jump to the target pane (requires [terminal-notifier](https://github.com/julienXX/terminal-notifier))
- Shows the number of active Claude processes in the status bar (e.g. 🤖2)

## Requirements

- tmux 3.2+ (for `display-popup` support)
- [TPM](https://github.com/tmux-plugins/tpm)
- macOS (uses `osascript`) or Linux with `notify-send`
- [terminal-notifier](https://github.com/julienXX/terminal-notifier) (optional, for clickable notifications on macOS)

## Installation

### With TPM

Add to `~/.tmux.conf`:

```bash
set -g @plugin 'NichiyaOba/claude-notify'
```

Reload tmux and install:

```bash
tmux source-file ~/.tmux.conf
# Press prefix + I to install plugins
```

### Manual

```bash
git clone https://github.com/NichiyaOba/claude-notify.git ~/.tmux/plugins/claude-notify
```

Add to `~/.tmux.conf`:

```bash
run-shell ~/.tmux/plugins/claude-notify/claude-notify.tmux
```

## Configuration

All options are set in `~/.tmux.conf`:

| Option | Default | Description |
|--------|---------|-------------|
| `@claude-notify-cpu-threshold` | `3` | CPU% threshold for "processing" detection |
| `@claude-notify-sound` | `Glass` | Notification sound name (macOS only) |
| `@claude-notify-macos-notify` | `on` | Enable/disable OS notifications (macOS: `osascript`, Linux: `notify-send`) |
| `@claude-notify-terminal-notifier` | `on` | Enable/disable terminal-notifier for clickable notifications (falls back to `osascript` if unavailable) |
| `@claude-notify-terminal-app` | (auto-detect) | Terminal app bundle ID for notification click focus (e.g. `com.mitchellh.ghostty`) |

Example:

```bash
set -g @claude-notify-cpu-threshold 5
set -g @claude-notify-sound "Ping"
set -g @claude-notify-macos-notify off
set -g @claude-notify-terminal-notifier on
set -g @claude-notify-terminal-app "com.mitchellh.ghostty"
```

## How It Works

The watcher script runs on each tmux status refresh (every 5 seconds) and tracks Claude Code processes through a simple state machine:

```
(no state) ──[Claude found, CPU > threshold]──→ processing
     ↑                                             │
     │                                   ┌─────────┴──────────┐
     │                           [CPU ≤ threshold]     [process exits]
     │                                   ↓                     ↓
     │                               low_once               exited
     │                                   │            (exit notification)
     │                           [CPU ≤ threshold]            │
     │                                   ↓                    │
     │                               waiting                  │
     │                        (completion notification)       │
     │                                   │                    │
     └─────────[next scan: cleanup]──────┴────────────────────┘
```

- **processing**: Claude is actively generating a response (CPU > threshold)
- **low_once**: CPU dropped below threshold once — debounce tick to prevent false positives
- **waiting**: CPU stayed low for 2 consecutive ticks — completion notification sent
- **exited**: Claude process disappeared while processing — exit notification sent

## License

[MIT](LICENSE)
