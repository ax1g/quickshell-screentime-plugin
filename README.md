<p align="center">
  <img src="preview.png" alt="Screen Time" width="100%"/>
</p>

# Screen Time

Know where your time goes. A lightweight service tracks focused time per app,
shows today's total in the bar, and breaks your history into a donut chart, a
52-week trend, and a yearly overview — terminal-aware, keyboard-first, fully
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
- 52-week trend: paginated Mon–Sun pages with date-range headers
  (`Aug 31 – Sep 6, 2026 · W36`); click any day to inspect it, click again
  for today. Header total flips between time and share of the week's
  168 hours.
- Yearly overview: per-month bars across every recorded year, plus a
  Wrapped-style retro — day counts, longest streak and break, top months,
  busiest Mon–Sun week, weekday rhythm, peak day.
- Usage patterns: top app, vs yesterday, and busiest day of the week you're
  looking at. Insight and retro colours follow your theme.
- Configurable: the gear next to SHOW MORE opens sectioned prefs that
  persist — hide the yearly overview or insights, set the weekly graph to
  12/24/36/52 weeks, rename apps and ignore the noisy ones, see the
  storage footprint and the totals that never expire, recolor the trophy
  and hero icons from theme swatches, mute the playful extras,
  triple-confirmed reset today (archives untouched), or four-click wipe
  everything (no undo).
- Daily goal: set Off/4/6/8h; a ✓ badge lands in the bar when the day
  reaches it, with remaining time in the tooltip and a progress bar
  under the hero total.
- Keyboard-first: the panel opens, closes, scrolls and triggers every
  control from the keyboard — see [Keybinds & hints](#keybinds--hints)
  below. Summon and control the panel via the `agx.screen-time` IPC
  target (`open`, `toggle`, `resetToday`, `resetAll`, `status`).
- Private by design: one local JSON file; old days roll into a
  perpetual per-day archive, and only the app breakdown is ever forgotten.
- Hourglass easter egg: flips over on the hour; gold sparkles on hover;
  header icons spin as you navigate (mute it all with Playful extras).

## Keybinds & hints

The panel is keyboard-first, and `f` is the only key you need to
remember: press it and every pressable gets a key badge. Type the
badge to trigger that control — single letters on the home panel (`y`
yearly, `c` settings, `m` more, `b`/`n` week pages, `t` week total,
`1`–`7` days), `b`/`n` to move between years in the yearly view, and
two-letter tags on the settings menu. The badges disappear on any other
press.

Everything else is standard: `j`/`↓` and `k`/`↑` scroll, `Esc` exits
first hint mode then the panel, `Tab`/`Shift+Tab` move between bar
panels, `p` expands Show More, and the wheel scrolls any overflowing
list.

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
- Per-app detail is kept for a full year, always covering the chosen
  weekly graph. As days age past it, each one's total folds into an
  ever-growing per-day archive in `"years"` — day counts, streaks, peak
  days, top months, insights and every yearly total are derived from it
  forever, so every recorded year stays browsable for as long as the
  file exists. Only the app breakdown is ever forgotten.
- `months` only appears in files written by older versions: current
  writes persist `days` and `years`, and readers keep honoring any
  legacy month lumps.
- The Wipe-all control in Settings, or deleting the file, is the only
  way to lose history.

## Development

The shell hot-reloads the plugin whenever a file changes, so a symlink into
your checkout is all you need to iterate:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/agx.screen-time
node --check js/Model.js && node --check js/State.js
npx -y prettier@3.9.6 --no-semi --check js/ tests/
node --test tests/model.test.js tests/state.test.js tests/service.test.js tests/panel.test.js
ruff check python/ tests/ && ruff format --check python/ tests/
python3 -m unittest discover -s tests
qmllint -I lint qml/*.qml qml/components/*.qml
./tests/geometry/run.sh
```

The same checks run in CI on every push. See CONTRIBUTING.md for the
project structure and QML rules.

## License

MIT
