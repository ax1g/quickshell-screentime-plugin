---
name: screen-time-contributor
description: Conventions for working in the agx.screen-time Omarchy plugin. Read before changing code.
---

# AGENTS.md — agx.screen-time

Screen-time tracker for Omarchy: per-app focused time in the bar, with a
donut breakdown, paginated week trend, yearly overview, and insights.
Fully local (one JSON file), terminal-aware, keyboard-first.

## Layout

```
.
├── qml/                    # Shell entry points + section views
│   ├── BarWidget.qml       # Bar button + panel host
│   ├── Service.qml         # Side effects: timers, disk, processes
│   ├── Panel.qml           # Popup shell: state, derivations, drawers
│   ├── WeekTrend.qml       # Paginated Mon-Sun bar chart
│   ├── YearDrawer.qml      # Yearly overview + retro cards
│   ├── MonthRow.qml        # One year-overview month row
│   └── components/         # Leaves: one concern per file
│       ├── AppLegend.qml / DonutChart.qml / LegendRow.qml
│       ├── HeroHeader.qml / Sparkle.qml
│       ├── InsightList.qml / InsightCard.qml
│       ├── WeekDayBar.qml / WeekTick.qml / PagerArrow.qml
│       └── BackButton.qml / CardColumn.qml / ScreenTip.qml / ConfigMenu.qml
├── js/                     # Pure logic, Node- and QML-importable
│   ├── Model.js            # Display math (formatting, donut, trends, years)
│   ├── State.js            # Transitions (buckets, suspend, midnight)
│   └── browser_aliases.json
├── python/                 # Terminal/Steam foreground resolver
│   └── resolve_app.py
├── tests/                  # model, state, service, panel (node) + resolver (unittest)
├── lint/                   # qmllint import stubs (see lint/README.md)
├── docs/assets/            # Historical changelog images
└── manifest.json           # Plugin id, version, entry points
```

Never hand-edit vendored files under `lint/`. `Service.qml` owns side
effects; `State.js` owns transitions as pure functions; views are
read-only mirrors of the service.

## Commands

```bash
node --check js/Model.js && node --check js/State.js
npx -y prettier@3.9.6 --no-semi --check js/ tests/
node --test tests/model.test.js tests/state.test.js tests/service.test.js tests/panel.test.js
ruff check python/ tests/ && ruff format --check python/ tests/
python3 -m unittest discover -s tests
qmllint -I lint qml/*.qml qml/components/*.qml   # MaxWarnings=0: any warning fails
for f in qml/*.qml qml/components/*.qml; do qmlformat "$f" | cmp -s - "$f" || echo "needs formatting: $f"; done
./tests/geometry/run.sh   # headless runtime checks; skips without Qt 6
```

Visual check (lint is not enough):
`quickshell ipc call agx.screen-time open` (with
`QS_CONFIG_PATH=/usr/share/omarchy/shell`) and screenshot with `grim`.

## Atomic commits (non-negotiable)

- One logical change per commit. Never mix a fix, a feature, a refactor,
  formatting, or docs in one commit.
- Conventional Commits: `<type>(<scope>): <short summary>` — imperative,
  lowercase, no period, max 72 chars. Types: `feat`, `fix`, `test`,
  `refactor`, `chore`, `docs`, `perf`, `style`.
- `style` commits are behavior-neutral by definition; `refactor` commits
  keep all tests green with no behavior change.
- Commit only what the change needs (`git status` + `git diff` first).
  Never commit secrets, caches (`.ruff_cache/`), or `__pycache__/`.
- A commit must leave every suite green. If it doesn't, split it until it does.

## Complexity budget

- Prefer small pure functions with early returns over nested branches.
  Past three levels of nesting, extract a helper.
- A file that is hard to skim is too big: extract a component (`qml/`),
  a helper (`js/`), or a test fixture — don't grow it.
- No clever one-liners. Boring, obvious code wins every review.
- QML derivations stay thin: one `Model.*` view call per concern
  (`weekView`, `yearView`), computed once in `Panel.qml` and threaded down.

## Readability and comments

- Comments are WHY-only. One-line file headers; inline comments only where
  the reason isn't obvious from the code (sandbox constraints, framework
  typing lies, ordering hazards, one-way data loss).
- The opposite rule ("no comments, code is self-documenting") is banned:
  it was removed because silent rationale rots. Explain the trap, not the line.
- Name things after the domain (`activeDay`, `keepDays`, `weekOffset`),
  not the mechanism. No new abbreviations.
- QML: explicit `required` props + signals between components. Qualify
  outer access with the nearest id (`rowDelegate.index`). Delegate-context
  names (`index`, `modelData`) only work with a matching `required`
  declaration — a bare `row.index` is `undefined`, not an error.

## Language rules

- **QML**: 4 spaces, `qmlformat`-clean. `var` in JS-flavored logic only
  where the engine requires it. Scoped `// qmllint disable/enable` pairs
  for audited framework artifacts only, each with its WHY comment.
- **JavaScript**: `var`, no `let`/`const` in sources (tests may use them).
  Prettier (`--no-semi`, house style has no semicolons). `Model.js`/`State.js` stay
  importable by both Node and the QML engine (guarded `module`/`require`).
- **Python**: stdlib only, 3.9-compatible, `ruff`-clean.

## Preferences pattern

- All widget prefs funnel through `BarWidget.setSetting(key, value)` so no
  key is ever dropped; they persist in `shell.json`.
- `Panel.qml` reads them via `prefs` (with an `in` probe, so missing
  settings can't throw). New prefs default to current behavior — old
  installs never need migration.
- Destructive actions need staged confirmation (arm → confirm → execute)
  with auto-disarm, and must scope their blast radius in code *and* in tests.

## Tests

- Put behavior in `Model.js`/`State.js` so `node --test` can reach it.
- `tests/service.test.js` / `tests/panel.test.js` assert QML wiring by
  source shape (props, signals, derivations) — extend them when adding
  either, and keep the regexes tight to the contract, not the layout.
- Python behavior gets `unittest` cases in `tests/test_resolve_app.py`.

## Changelog

- The changelog speaks to users of the last release, not to the working
  tree. Before adding an entry, diff against the last released version:
  if no released user ever saw the old behavior, there is nothing to
  announce — fold the tweak into the feature's own entry instead.
- `Fixed` entries are for bugs in shipped behavior only. A fix to a
  feature that itself is still unreleased (e.g. restyling a settings
  page introduced in the same cycle) gets no entry at all.
- Internal work never appears: refactors, tests, tooling, file moves.
- `Added` entries sell like marketing: lead with the user win, not the
  mechanism. Write "Know your week at a glance", never "paginated
  Mon–Sun week view with ISO headers". One entry per feature, two lines max.
- No internals in user-facing lines: no file names, no pref keys, no
  function names (typed IPC commands are the exception — users run them).

## QA traps

- `tests/geometry/run.sh` instantiates the real components headlessly
  (Qt 6 `qmltestrunner`, offscreen) and asserts rows occupy space.
  Extend `geometry_test.qml` when adding rows, buttons, or required
  props to `ConfigMenu.qml` — keep its prop block in sync or it fails
  loudly. Thresholds stay relative (nonzero heights), never pixels.
- Never put an `anchors.fill` MouseArea inside an implicit-height
  `Column`: it collapses to zero. Size the row explicitly (fixed
  height or `Math.max(...)`) and fill against that.
- New prefs need a settings-matrix pass: every consumer (Panel
  derivation, Service push, BarWidget, menu UI) × every shape the
  setting can hold (missing, garbage, extremes). Pure helpers must
  return safe defaults, never throw; history input is validated once
  at the `sanitize*` boundary with `isDayKey`/`isMonthKey`.
- Unreachable-in-theory is not untested-in-practice: clock jumps,
  suspends past midnight, corrupt files, and missing helpers are the
  paths that break. Cover the transition, not just the happy day.

## Definition of done

- [ ] One commit per logical change, Conventional Commits, suites green.
- [ ] `qmllint`, `qmlformat`, `prettier`, `ruff`, Node + Python suites all pass.
- [ ] `tests/geometry/run.sh` passes (or skips loudly without Qt 6).
- [ ] Panel opened visually and screenshotted for UI changes.
- [ ] `CHANGELOG.md` entry under `[Unreleased]` for user-facing changes.
- [ ] No new warnings, no dead imports, no widened suppressions.
