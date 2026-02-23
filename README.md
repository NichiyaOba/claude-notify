# claude-notify

A tmux plugin that monitors [Claude Code](https://docs.anthropic.com/en/docs/claude-code) processes and displays their status in the tmux status bar.

## Features

- Scans all tmux panes for running Claude Code processes
- Detects response completion via CPU usage state transitions
- Displays per-process status in the status bar with project name and pane location
- Completed/exited indicators auto-clear after a configurable timeout

### Status Bar Format

```
🤖myapp(0:1.0) ✅api(0:2.1) 💀tools(1:0.0)
```

| Icon | Meaning |
|------|---------|
| 🤖 | Processing (CPU active) |
| ✅ | Completed (auto-clears after timeout) |
| 💀 | Exited unexpectedly (auto-clears after timeout) |

Each entry shows `icon` + `project_name` + `(session:window.pane)`.

## Requirements

- tmux 3.0+
- [TPM](https://github.com/tmux-plugins/tpm)

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
| `@claude-notify-display-timeout` | `30` | Seconds to keep completed/exited entries visible |
| `@claude-notify-max-name-length` | `10` | Maximum characters for project name display |

Example:

```bash
set -g @claude-notify-cpu-threshold 5
set -g @claude-notify-display-timeout 60
set -g @claude-notify-max-name-length 15
```

### Status Bar Width

The default `status-right-length` (40 characters) may be too narrow when monitoring multiple Claude processes. Increase it to ensure all entries are visible:

```bash
set -g status-right-length 120
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
     │                                   │                 💀 (auto-clear)
     │                           [CPU ≤ threshold]            │
     │                                   ↓                    │
     │                               waiting                  │
     │                            ✅ (auto-clear)             │
     │                                   │                    │
     └────────[timeout: cleanup]─────────┴────────────────────┘
```

- **processing**: Claude is actively generating a response (CPU > threshold) — displayed as 🤖
- **low_once**: CPU dropped below threshold once — debounce tick to prevent false positives
- **waiting**: CPU stayed low for 2 consecutive ticks — displayed as ✅
- **exited**: Claude process disappeared while processing — displayed as 💀

Completed and exited entries are automatically removed from the status bar after the configured timeout (default: 30 seconds).

## License

[MIT](LICENSE)
