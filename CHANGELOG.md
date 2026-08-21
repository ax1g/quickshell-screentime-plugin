# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-08-21

### Added

- Yearly overview drawer behind the hero hourglass: `< year >` navigation back
  to the first recorded year, one bar per month scaled against the busiest
  month with exact hours on hover, a BACK button, and a full-card overlay
  that keeps the panel's show-less height.
- Persistent monthly aggregates: days rolled out of the 95-day retention
  window are folded into per-month totals, so the yearly overview covers the
  whole history instead of forgetting it. Retention itself grew from 31 to
  95 days so all 13 paginated trend weeks keep their daily detail.
- ISO week numbers in the week graph header (`Aug 2026 · W34`), paginated
  across 13 Mon-Sun weeks.
- Week total toggle: click the header total to flip between duration and its
  share of the week's 168 hours; the tooltip phrases either as an insight.
- Donut cross-highlight: hovering a legend row highlights its ring slice,
  and hovering a slice highlights its row.
- Hero hourglass easter egg: it flips over on every full hour, and gold
  sparkles burst around the cursor on hover, scattered and sized anew each
  time.

### Changed

- Week bars follow the theme: today's bar in the accent colour, other days
  at low opacity, empty and future days as faint tracks.
- App list uses a fixed-height scroll area with vertically centred rows.
- Insights labels joined to their values with a middle dot; delta spacing
  tightened.

### Fixed

- Steam games now resolve to their real titles in production: the old
  JavaScript-side lookup used Node-only APIs that throw inside QML, so
  `steam_app_*` labels were broken. Resolution moved into the Python
  resolver, which reads local appmanifests; unresolved ids keep a stable
  tracking key.
- Insights section no longer overlaps the week graph (a misplaced brace made
  it stack on top of the chart).
- The yearly overview no longer flashes across the panel while the panel is
  opening.
- Hovering the yearly overview no longer reaches the donut chart underneath;
  its background is fully opaque.
- Calendar month rows no longer emit `Unable to assign [undefined] to bool`
  warnings.

## [1.2.2] - 2026-08-19

### Fixed

- Live screen-time tracking now continues after each timer tick and correctly
  resumes after app resolution.

## [1.2.1] - 2026-08-19

### Added

- `State.js` state-machine module: bucket lifecycle, suspend detection, and
  midnight rollover extracted from `Service.qml` into pure, testable
  functions.
- `lib/browser_aliases.json` as single source of truth for browser
  canonicalization; `Model.js` and `resolve_app.py` read from it.
- `State.js` unit tests and data-safety test coverage for pruning, midnight
  rollover, and corrupt-input recovery.

### Changed

- Project reorganized: `Model.js` → `lib/Model.js`,
  `resolve_app.py` → `scripts/resolve_app.py`.

### Fixed

- Deprecated `Qt.include()` replaced with inline JSON to silence QML
  warnings.
- `persist()` calls restored after `State.js` extraction accidentally
  dropped them.
- `closeActiveBucket` consolidated through `State.closeActiveBucket` in
  rollover; remaining `root.closeActiveBucket` references removed.
- Service wired to `State.applyResolvedApp`; resolver aliases guarded
  against missing entries.
- Shadowed variable `d` renamed to `dt` in `commitElapsed`.

## [1.2.0] - 2026-08-18

### Added

- Interactive week-trend bars: click any day to view that day's apps,
  donut, hero total, and insights; click again or close the panel to
  return to today's live data. Active bar highlighted with an accent
  dot indicator.
- Scrollable app list: bounded legend with a thin scrollbar; Show More
  toggles the full app list inline (renamed from Patterns).
- Clean app names: reverse-DNS compositor IDs shortened to the last
  segment and title-cased (`com.github.user.Codium` → `Codium`).
- Donut slices below 3% auto-collapse into the "Other" bucket so the
  chart stays readable with many small apps.
- Donut centre now shows the full date ("Aug 15") instead of a
  hardcoded "TODAY" label.
- Insights always show three rows; missing data shows an em-dash
  placeholder instead of omitting the row.
- Empty donut draws a dim ring so the chart area is visible even with
  no tracked data for the selected day.

### Changed

- Panel close resets selected day only (expanded state preserved) so
  the panel always opens showing today's live data.
- Hero hourglass icon enlarged for better readability; subtitle font
  reduced to caption size.
- Insights labels use weekday names for all non-today items:
  "Top app (Fri)", "vs (Thu)"; today keeps "Top app" / "vs yesterday".
- Extra spacing between insights icon and label text.

### Fixed

- Week-trend bars no longer vanish when the selected past day has
  data; the section stays visible so the user can switch days.
- Insight icons (star, arrow, circle) render correctly with day-name
  labels via prefix matching instead of exact equality.
- Scrollbar ratio guarded against Infinity when content is empty.
- `busiestWeekDay` guarded against empty `todayKey` input.

## [1.1.0] - 2026-08-16

### Fixed

- Suspend and clock jumps no longer accrue wall-clock time as screen time: a
  bucket crossing a suspend gap is dropped instead of counting the sleep,
  and the gap baseline is re-anchored so tracking resumes from the moment of
  wake. A 5s heartbeat keeps the baseline fresh, so suspends from ~30s up
  are detected instead of only multi-minute ones.
- The idle screensaver and xdg desktop-portal windows no longer count as
  tracked apps, matching the "idle and locked time is never counted" claim.
- A corrupt `history.json` is preserved (moved aside) before tracking
  resumes, instead of being silently overwritten and losing all history.
- Terminal resolution now also covers Omarchy's own terminal
  (`org.omarchy.terminal`), which was previously tracked as itself.
- Panel no longer emits `Unable to assign [undefined] to QString` warnings at
  startup: chart data is gated on the service being ready, and the Model
  helpers tolerate empty day keys.
- Resolver runs are guarded against overlap, and a watchdog kills a stuck
  resolver process and re-arms the refresh timer so terminal tracking
  recovers instead of stalling forever.

### Changed

- README gains a concise "At a glance" feature list for the plugin listing.

## [1.0.0] - 2026-08-15

Initial marketplace release.

### Added

- Long-running screen-time service: tracks focused time per app, persists to
  `~/.config/omarchy/screen-time/history.json`, and survives shell restarts
  and plugin reloads.
- Terminal resolution (`resolve_app.py`): reports what is actually running
  inside a focused terminal (e.g. `opencode` rather than `foot`), with
  per-browser canonicalization so browsers aggregate under a single key.
- Bar widget: today's total as "glyph + time", right-click toggles to an
  icon-only mode (remembered in the widget entry).
- Popup panel: donut chart with legend, hover highlighting (slice highlight,
  dimmed siblings, app name + time in the centre), and behaviour insights
  (top app, vs. yesterday, busiest day in 7).
- Donut slices beyond six collapse into an "Other" bucket so the chart stays
  readable with many apps.
- History retention: days older than 31 are pruned automatically.
- Theme integration: slice colours are generated from the theme accent, so
  the palette follows theme swaps.
- Tests for the pure logic (`Model.js`, `resolve_app.py`) and a CI workflow.

### Changed

- Icon-only underline now aligns with the painted glyph (OpticalGlyph).
- README screenshots live under `assets/`.

### Fixed

- Open-panel indicator drifted off the icon-only glyph (Nerd Font ink sits
  offset within its advance box).
