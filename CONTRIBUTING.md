# Contributing to Screen Time

Thanks for your interest in contributing! This document explains how to get
started.

## Development setup

1. Clone the repo:
   ```
   git clone https://github.com/ax1g/quickshell-screentime-plugin.git
   ```
2. Install [Omarchy](https://github.com/ax1g/omarchy) with Quickshell.
3. Link the plugin into your Omarchy config:
   ```
   omarchy plugin add quickshell-screentime-plugin
   ```
4. The shell hot-reloads the plugin on file save — no build step required.

## Running tests

```bash
# JavaScript (Model.js + State.js + Service.qml pause machine + Panel wiring)
node --check js/Model.js && node --check js/State.js
npx -y prettier@3.9.6 --no-semi --check js/ tests/
node --test tests/model.test.js tests/state.test.js tests/service.test.js tests/panel.test.js

# Python (resolve_app.py) — ruff pinned in CI, any recent ruff works locally
ruff check python/ tests/
ruff format --check python/ tests/
python3 -m unittest discover -s tests

# QML lint (qmllint + .qmllint.ini + lint/ import stubs in repo root)
qmllint -I lint qml/*.qml qml/components/*.qml

# Headless runtime checks (skips cleanly without Qt 6)
./tests/geometry/run.sh
```

`qmllint` and `qmlformat` ship with Qt 6 (`qt6-declarative-dev-tools`;
binaries live in `/usr/lib/qt6/bin`). Any warning fails the check
(`MaxWarnings=0`); shell/framework imports resolve via `lint/` — see
`lint/README.md` before adding a suppression. Check QML formatting with:

```bash
for f in qml/*.qml qml/components/*.qml; do
  qmlformat "$f" | cmp -s - "$f" || echo "needs formatting: $f"
done
```

All tests must pass before submitting a PR. CI runs these checks automatically.

## Project structure

```
.
├── qml/
│   ├── BarWidget.qml       Bar widget (today's total, popup host)
│   ├── Service.qml         Long-running background service (timers, persistence)
│   ├── Panel.qml           Popup shell: state, derivations, drawer slide chrome
│   ├── WeekTrend.qml       Paginated Mon-Sun bar chart with pager
│   ├── YearDrawer.qml      Yearly overview: month bars + retro masonry
│   ├── MonthRow.qml        One year-overview month row
│   └── components/         Leaves: DonutChart, AppLegend, LegendRow, HeroHeader,
│                           Sparkle, InsightCard, InsightList, PagerArrow,
│                           BackButton, CardColumn, ScreenTip, ConfigMenu
├── js/
│   ├── Model.js            Pure JS helpers (formatting, aggregation, donut math)
│   ├── State.js            Pure JS state machine (bucket lifecycle, suspend, midnight)
│   └── browser_aliases.json
├── python/
│   └── resolve_app.py      Terminal foreground process resolver
├── tests/                  Unit tests (Node.js + Python) plus
│                           tests/geometry/ (headless QML runtime checks)
├── lint/                   qmllint import stubs (vendored shell + Quickshell API)
└── docs/assets/            Historical changelog images
```

### Architecture

- **State.js** owns all state transitions as pure functions. Every input is
  passed explicitly, every output is a new object. Fully testable in Node.js.
- **Model.js** owns display logic: formatting, aggregation, donut geometry.
  Also pure and testable.
- **Service.qml** owns side effects: timers, disk I/O, process spawning, QML
  property bindings. Delegates state transitions to State.js.
- **Panel.qml** owns popup state and derivations; sections live in `qml/` and
  `qml/components/` as leaves with explicit `required` props and signals.
  Never reach into a parent by id; never rely on same-directory lookup for
  a name the shell also provides (that outage is why the tooltip is named
  `ScreenTip`, not `PanelToolTip`).

### QML rules

- Keep code simple and readable; extract a component when a file gets hard to follow.
- Qualify outer access with the nearest id (`rowDelegate.index`).
  Delegate-boundary outer-id reads take one standard note plus a scoped
  `// qmllint disable/enable unqualified` pair.
- Comments are WHY-only: file headers one line, inline only where the
  reason isn't obvious from the code.
- Hot-reload tracks edits, not moves: restart the shell after renaming or
  moving QML files, or it serves stale trees with phantom paths.
- Verify visually, not just by lint: open the panel via
  `quickshell ipc call agx.screen-time open` (with
  `QS_CONFIG_PATH=/usr/share/omarchy/shell`) and screenshot with `grim`.

## Making changes

1. **Open an issue first** for non-trivial changes so the approach can be
   discussed.
2. **Follow TDD**: write a failing test that defines the desired behavior,
   then implement the minimal code to make it pass.
3. **Keep changes focused**: one logical change per commit. Do not mix
   unrelated fixes.
4. **Run the full test suite** before pushing:
    ```
    node --test tests/model.test.js tests/state.test.js tests/service.test.js tests/panel.test.js && python3 -m unittest discover -s tests
    ```

## Code style

- **JavaScript**: `var` (QML engine compatibility), no `let`/`const` in
  source files (tests may use `const`/`let`). Formatted with
  `prettier --no-semi`; never hand-format against it.
- **Python**: ruff-clean (`ruff check` + `ruff format --check`), no external
  dependencies.
- **QML**: explicit `required` props + signals between components; see
  QML rules above. `var` in JS-flavored logic only where the engine
  requires it. Formatted with `qmlformat` (defaults); vendored files under
  `lint/` stay byte-identical to upstream and are never reformatted.

## Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>
```

Types: `feat`, `fix`, `test`, `refactor`, `chore`, `docs`, `perf`, `style`.

- Summary: imperative mood, lowercase, no period, max 72 chars.
- One logical change per commit.

## Browser aliases

`js/browser_aliases.json` is the single source of truth. `python/resolve_app.py`
reads it directly; Node reads it via `require`. QML cannot, so `js/Model.js`
mirrors it as a `qmlBrowserAliases()` literal.

If you add a new browser, update **both**:

- `js/browser_aliases.json`
- `js/Model.js` → `qmlBrowserAliases()`

They must match exactly (`tests/model.test.js` fails otherwise).

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).
