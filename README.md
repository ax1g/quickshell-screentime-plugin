<p align="center">
  <img src="preview.png" alt="Screen Time" width="100%"/>
</p>

# Screen Time

Know where your time goes. A lightweight service tracks focused time per app,
shows today's total in the bar, and breaks your history into a donut chart, a
13-week trend, and a yearly overview — terminal-aware, keyboard-first, fully
local.

## Features

- Live bar widget: today's total in your bar font, updated as you work.
  Right-click collapses it to a single glyph; remembered.
- Per-app tracking: idle, locked, suspend and desktop time never counted. A
  focused terminal shows what runs inside it (`opencode`, not `foot`),
  re-resolved live; `steam_app_123456` becomes the game title from local
  Steam metadata. Reverse-DNS IDs shortened; Chromium web apps fold by
  hostname across profiles.
- Games count too: whatever you play — Steam, Battle.net, browser, emulator —
  gets timed like any other app. It's focused time, so an evening of being
  AFK in a lobby won't inflate your hours the way Steam's counter does.
- Donut chart: six biggest apps + "Other", day total in the centre. Hover a
  slice or legend row to spotlight that app; Show More expands the full
  scrollable list.
- 13-week trend: paginated Mon–Sun pages with date-range headers
  (`Aug 31 – Sep 6, 2026 · W36`); click any day to inspect it, click again
  for today. Header total flips between time and share of the week's
  168 hours.
- Yearly overview: per-month bars across every recorded year, plus a
  Wrapped-style retro — day counts, longest streak and break, top months,
  busiest Mon–Sun week, weekday rhythm, peak day.
- Usage patterns: top app, vs yesterday, and busiest day of the week you're
  looking at. Insight and retro colours follow your theme.
- Keyboard-first and keybind-friendly: `Esc` closes, `j`/`k` and arrows
  scroll, wheel works; summon and control the panel via the
  `agx.screen-time` IPC target.
- Private by design: one local JSON file; old days roll into a two-year
  per-day archive, then monthly totals.
- Hourglass easter egg: flips over on the hour; gold sparkles on hover.

## Install

```bash
omarchy plugin add https://github.com/ax1g/quickshell-screentime-plugin.git
omarchy plugin enable agx.screen-time
```

Requires Omarchy and Hyprland. A Nerd Font provides the glyphs, and
`python3` (preinstalled on Omarchy) powers terminal and Steam name
resolution — without it the plugin still tracks, but terminals show under
their own name (`foot`, `kitty`) instead of what runs inside them.

## Uninstall

```bash
omarchy plugin disable agx.screen-time
omarchy plugin remove agx.screen-time
```

To also delete the history file:

```bash
rm ~/.config/omarchy/screen-time/history.json
```

## Data

Everything lives in one local file, `~/.config/omarchy/screen-time/history.json`:

```json
{
  "days": {
    "2026-08-16": { "total": 490875, "apps": { "zen": 313349, "opencode": 148706 } }
  },
  "months": {
    "2026-07": 9823400
  },
  "years": {
    "2026": { "2026-08-15": 582190 }
  }
}
```

- Per-app focus time in milliseconds, keyed by day (`YYYY-MM-DD`).
- A session spanning midnight splits there, so each day keeps its own
  seconds.
- Daily detail older than ~3 months (95 days, matching the 13-week trend) is
  pruned, but its total folds into a per-day archive first — the current and
  previous calendar year's day totals survive as `"years"`, so the yearly
  overview keeps day counts, streaks, and peak days even though raw app
  detail is forgotten. Older years live on as per-month aggregates. Delete
  the file to reset.

## Development

The shell hot-reloads the plugin whenever a file changes, so a symlink into
your checkout is all you need to iterate:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/agx.screen-time
node --check lib/Model.js && node --check lib/State.js
node --test tests/model.test.js tests/state.test.js
python3 -m unittest discover -s tests
```

The same checks run in CI on every push.

## License

MIT
