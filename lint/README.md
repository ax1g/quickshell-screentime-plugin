# Lint imports

`qmllint` cannot see the shell this plugin runs inside: `qs.Commons`,
`qs.Ui` (omarchy-shell) and `Quickshell.*` (the compositor toolkit) are not
installed on a bare runner. Without them every shell type is an unresolved
import and real diagnostics drown in noise — so this directory provides the
import context and CI lints with `qmllint -I lint`.

## Layout

- `qs/Commons/`, `qs/Ui/` — **verbatim snapshots** of omarchy-shell
  (`omacom/omarchy`, branch `quattro`, `shell/Commons`,
  `shell/Ui`). Only the types this plugin uses are vendored
  (Style, Color, BarWidget, Panel, PanelController, WidgetButton,
  OpticalGlyph, PanelSeparator, PanelKeyCatcher). Never hand-edit these;
  refresh them from upstream instead (see below).
- `qs/Ui/KeyboardPanel.qml` — hand-written minimal stub. The real frame
  owns focus scopes and layer rules; this covers exactly the eight members
  our `Panel.qml` uses (`anchorItem`, `owner`, `bar`, `open`,
  `focusTarget`, `contentWidth/Height`, `fittedContent*`).
- `Quickshell/`, `Quickshell/Io/`, `Quickshell/Wayland/` — hand-written
  minimal stubs for the stable C++ API surface this repo touches
  (`env`, `FileView`, `JsonAdapter`, `Process`, `StdioCollector`,
  `SplitParser`, `FileViewError`, `IpcHandler`, `ToplevelManager`).
  `environment` stays `var` on purpose: a JS literal assigned to the real
  `QVariantHash` warns (Map-vs-Hash inference) while `var` accepts both.

## Dual environments

On a machine with omarchy installed, the real `Quickshell.*` modules shadow
these stubs (built-in import paths win over `-I`); on bare CI only the
stubs resolve. Both modes must lint clean — the remaining suppressions are
audited framework artifacts, each with a WHY comment at the site
(`FileViewAdapter` is C++-only; `QProcess::ExitStatus` never loads into
lint; `Style.font`/`bar.*` are `QtObject`-typed upstream).

## Refreshing the snapshots

```bash
REF=quattro  # or newer
for f in Commons/Style.qml Commons/Color.qml Commons/BorderGeometry.js \
    Ui/BarWidget.qml Ui/Panel.qml Ui/PanelController.qml \
    Ui/WidgetButton.qml Ui/OpticalGlyph.qml Ui/PanelSeparator.qml \
    Ui/PanelKeyCatcher.qml; do
  curl -s "https://raw.githubusercontent.com/omacom/omarchy/$REF/shell/$f" \
    -o "lint/qs/$f"
done
qmllint -I lint qml/*.qml qml/components/*.qml
```

`qmlformat` never runs here: snapshots stay byte-identical to upstream.
