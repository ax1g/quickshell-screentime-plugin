# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
