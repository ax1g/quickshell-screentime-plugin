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
# JavaScript (Model.js + State.js)
node --check lib/Model.js && node --check lib/State.js
node --test tests/model.test.js tests/state.test.js

# Python (resolve_app.py)
python3 -m py_compile scripts/resolve_app.py
python3 -m unittest discover -s tests

# QML lint (best-effort, requires qt6-declarative-tools)
qmllint Service.qml BarWidget.qml Panel.qml
```

All tests must pass before submitting a PR. CI runs these checks automatically.

## Project structure

```
BarWidget.qml       Bar widget (today's total, popup host)
Panel.qml           Popup panel (donut chart, legend, insights)
Service.qml         Long-running background service (timers, persistence)
lib/
  Model.js          Pure JS helpers (formatting, aggregation, donut math)
  State.js          Pure JS state machine (bucket lifecycle, suspend, midnight)
scripts/
  resolve_app.py    Terminal foreground process resolver
tests/              Unit tests (Node.js + Python)
docs/assets/        README images
```

### Architecture

- **State.js** owns all state transitions as pure functions. Every input is
  passed explicitly, every output is a new object. Fully testable in Node.js.
- **Model.js** owns display logic: formatting, aggregation, donut geometry.
  Also pure and testable.
- **Service.qml** owns side effects: timers, disk I/O, process spawning, QML
  property bindings. Delegates state transitions to State.js.
- **Panel.qml** and **BarWidget.qml** are read-only views of the service state.

## Making changes

1. **Open an issue first** for non-trivial changes so the approach can be
   discussed.
2. **Follow TDD**: write a failing test that defines the desired behavior,
   then implement the minimal code to make it pass.
3. **Keep changes focused**: one logical change per commit. Do not mix
   unrelated fixes.
4. **Run the full test suite** before pushing:
   ```
   node --test tests/model.test.js tests/state.test.js && python3 -m unittest discover -s tests
   ```

## Code style

- **JavaScript**: `var` (QML engine compatibility), no `let`/`const` in
  source files (tests may use `const`/`let`).
- **Python**: PEP 8, no external dependencies.
- **QML**: follow existing patterns in the file you're editing.
- **No comments unless asked** — the code should be self-documenting.

## Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>
```

Types: `feat`, `fix`, `test`, `refactor`, `chore`, `docs`, `perf`, `style`.

- Summary: imperative mood, lowercase, no period, max 72 chars.
- One logical change per commit.

## Browser aliases

If you add a new browser, update **both** files:

- `lib/Model.js` → `BROWSER_ALIASES`
- `scripts/resolve_app.py` → `BROWSER_BINARY_TO_APP`

They must contain the same keys and map to the same canonical names.

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).
