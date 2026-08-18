# Screen Time

Per-app screen time for the Omarchy bar. A lightweight service tracks how long
each app keeps focus, the bar shows today's total, and a popup breaks the day
down into a donut chart with a 7-day usage trend.

<p align="center">
  <img src="assets/preview.png" width="47%" alt="Screen Time panel preview"/>
</p>

<p align="center">
  <img src="assets/image1.png" width="23%" alt="Today's donut breakdown"/>
  <img src="assets/image2.png" width="23%" alt="Clickable week-trend bars"/>
  <img src="assets/image3.png" width="23%" alt="Insights with weekday labels"/>
</p>

## Features

| Feature | What it does |
| --- | --- |
| **Time in the bar** | Today's total, live, right next to your tray. |
| **Per-app tracking** | Focus time per app; idle, locked, asleep and desktop time never counted. |
| **Terminal-aware** | A focused terminal reports what's actually running inside it (`opencode`, not `foot`), re-resolving every few seconds; browser subprocesses are canonicalized into one app. |
| **Donut breakdown** | Today's apps in a ring with a legend and the day's total in the centre; six biggest + "Other". |
| **Clickable week bars** | Click any day in the 7-day trend to view that day's apps, donut, and insights; click again or close the panel to return to today. |
| **Scrollable app list** | Bounded legend with a thin scrollbar; Show More expands the full list inline. |
| **Clean app names** | Reverse-DNS IDs shortened to the last segment and title-cased (`com.github.user.Codium` → `Codium`). |
| **Usage patterns** | Press `p` for a 7-day trend, top app, vs. yesterday, and your busiest day. |
| **Icon-only mode** | Right-click to collapse the widget to a single glyph; remembered. |
| **Keyboard-first** | `Esc` closes the panel, `p` toggles patterns, `j`/`k`/arrows scroll; mouse wheel works too. |
| **Keybind-friendly** | Summon the panel from a script or keybind via the `agx.screen-time` IPC target. |
| **Private by design** | Local JSON, pruned after 31 days; colours generated from your theme's accent. |

## Install

```bash
omarchy plugin add https://github.com/ax1g/quickshell-screentime-plugin.git
omarchy plugin enable agx.screen-time
```

Requires Omarchy, Hyprland, and a Nerd Font for the glyphs.

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
  }
}
```

- Per-app focus time in milliseconds, keyed by day (`YYYY-MM-DD`).
- Focus is credited to the day it started on, so a session spanning midnight
  still lands on the right day.
- History older than 31 days is pruned automatically. Delete the file to reset.

## Development

The shell hot-reloads the plugin whenever a file changes, so a symlink into
your checkout is all you need to iterate:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/agx.screen-time
node --check Model.js && node --test tests/model.test.js
python3 -m unittest discover -s tests
```

The same checks run in CI on every push.

## License

MIT
