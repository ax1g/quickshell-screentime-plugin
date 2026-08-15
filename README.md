# Screen Time

A bar widget showing today's screen time with a popup listing per-app usage
and a few behaviour insights (top app, vs. yesterday, busiest day). A
long-running service tracks focused time per app and persists it to disk, so
data survives shell restarts and plugin reloads.

## Requirements

- Omarchy shell (Quickshell-based)
- Hyprland (`hyprctl`, used to resolve the app running inside a focused
  terminal)
- A Nerd Font for the glyphs (`󰥔`) — most Omarchy themes ship one

## Install

```bash
omarchy plugin add <repo-url>
omarchy plugin enable agx.screen-time
```

or install by hand:

1. Clone into `~/.config/omarchy/plugins/agx.screen-time/`
2. `omarchy-shell shell rescanPlugins`
3. `omarchy plugin enable agx.screen-time`

## How tracking works

The service listens to the compositor's active toplevel and accrues focused
time per app. Idle, locked, or desktop time is not counted. When a terminal
is focused, a resolver (`resolve_app.py`) walks `/proc` to find the process
actually running inside it (e.g. `opencode` rather than `foot`), re-resolving
every few seconds in case the foreground command changes.

## Data

Screen-time history is stored as append-only JSON at
`~/.config/omarchy/screen-time/history.json`, shaped as
`{ "<YYYY-MM-DD>": { "total": <ms>, "apps": { "<appId>": <ms> } } }`.
Deleting the file resets tracking.

Right-click toggles the bar label between "glyph + time" and the glyph
alone; the choice is remembered in the widget's entry.

