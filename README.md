<p align="center">
  <img src="preview.png" alt="Screen Time" width="100%"/>
</p>

# Screen Time

Know where your time goes. A lightweight service tracks focused time per app,
shows today's total in the bar, and breaks your history into a donut chart, a
20-week trend, and a yearly overview — terminal-aware, keyboard-first, fully
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
- 20-week trend: paginated Mon–Sun pages with date-range headers
  (`Aug 31 – Sep 6, 2026 · W36`); click any day to inspect it, click again
  for today. Header total flips between time and share of the week's
  168 hours.
- Yearly overview: per-month bars across every recorded year, plus a
  Wrapped-style retro — day counts, longest streak and break, top months,
  busiest Mon–Sun week, weekday rhythm, peak day.
- Usage patterns: top app, vs yesterday, and busiest day of the week you're
  looking at. Insight and retro colours follow your theme.
- Configurable: the gear next to SHOW MORE opens sectioned prefs that
  persist — hide the yearly overview or insights, set the week trend to
  4/8/12/16/20 weeks, rename apps and ignore the noisy ones, tune
  retention with a stored-footprint readout, recolor the trophy and hero
  icons from theme swatches, mute the playful extras, triple-confirmed
  reset today (archives untouched), or four-click wipe everything
  (no undo).
- Daily goal: set Off/4/6/8h; a ✓ badge lands in the bar when the day
  reaches it, with remaining time in the tooltip and a progress bar
  under the hero total.
- Keyboard-first: the panel opens, closes, scrolls and triggers every
  control from the keyboard — see [Keybinds & hints](#keybinds--hints)
  below. Summon and control the panel via the `agx.screen-time` IPC
  target (`open`, `toggle`, `resetToday`, `resetAll`, `status`).
- Private by design: one local JSON file; old days roll into a two-year
  per-day archive, then monthly totals.
- Hourglass easter egg: flips over on the hour; gold sparkles on hover;
  header icons spin as you navigate (mute it all with Playful extras).

## Keybinds & hints

The panel is keyboard-first: every control can be reached from the
keyboard without touching the mouse, and the scroll wheel works
anywhere a list overflows.

### Navigation

| Key | Action |
|---|---|
| `f` | Toggle hint mode — every pressable gets a key badge |
| `j` / `↓` | Scroll down (follows the open view) |
| `k` / `↑` | Scroll up (follows the open view) |
| `Esc` | First exit hint mode; a second press closes the panel |
| `Tab` / `Shift+Tab` | Jump to the next / previous bar panel |
| `p` | Expand / collapse Show More |

### Hint mode

Press `f` and the panel badges every pressable with its key — a single
letter on the home panel and yearly view, a two-letter tag on the
settings menu (it has far more controls than letters). Typing the key
performs that action and exits hint mode; the badges disappear on any
other press.

**Home panel**

| Badge | Action |
|---|---|
| `y` | Open the yearly overview |
| `c` | Open the settings |
| `m` | Expand / collapse Show More |
| `b` / `n` | Previous / next week in the trend |
| `t` | Flip the week total between logged time and % of 168h |
| `1`–`7` | Inspect that weekday's bar (focus its data) |

**Yearly overview**

| Badge | Action |
|---|---|
| `b` / `n` | Previous / next year |
| `m` | Back to the home panel |

**Settings**

Every row carries a two-letter tag, starting with `aa` on the back
button and flowing down the menu in render order. Typing a tag triggers
its control — toggles flip, swatches recolor, and the staged
destructive confirmations (reset / wipe) advance one step per press,
just like a click.

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
- Daily detail older than the retention window (30/95/365 days, always
  covering the chosen week trend) is pruned, but its total folds into a
  per-day archive first — the current and previous calendar year's day
  totals survive as `"years"`, so the yearly overview keeps day counts,
  streaks, and peak days even though raw app detail is forgotten. Older
  years live on as per-month aggregates. Delete the file to reset.

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
