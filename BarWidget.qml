import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar widget: today's total screen time with a popup listing per-app usage
// and behaviour insights. The heavy lifting lives in Service.qml; this only
// reads its state and hosts the panel.
BarWidget {
  id: root
  moduleName: "agx.screen-time"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("agx.screen-time") : null
  readonly property string label: service ? service.barLabel : ""
  readonly property bool hasActivity: service ? service.hasActivity : false

  readonly property string glyph: "󰔟"

  // Vertical bar (left/right edge): the button's text label is hidden in
  // vertical mode, so the content is drawn as stacked OpticalGlyph lines —
  // icon first, then the duration split per token so each line fits the
  // icon slot. Same shape as omarchy.clock's vertical stack.
  readonly property var verticalLines: {
    if (!root.vertical) return []
    var lines = [root.glyph]
    if (!root.iconOnly && root.label) {
      var parts = String(root.label).split(" ")
      for (var i = 0; i < parts.length; i++) if (parts[i]) lines.push(parts[i])
    }
    return lines
  }

  // Icon-only mode: right-clicking shrinks the widget to just the glyph.
  // The state lives in the widget's shell.json entry ("iconOnly"), so it
  // survives restarts and follows the widget across bar slots.
  readonly property bool iconOnly: {
    var v = root.setting("iconOnly", false)
    return v === true || v === "true"
  }

  function toggleIconOnly() {
    var next = !root.iconOnly
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.iconOnly = next
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // The bar's open-panel indicator (underline) tracks the painted label
  // width instead of a fraction of the slot, mirroring omarchy.clock. In
  // icon-only mode the glyph is painted through an OpticalGlyph so its ink
  // (not its advance box) is centred, and the mark takes that painted width
  // so it lines up with the visible glyph rather than drifting off it.
  readonly property real openPanelIndicatorWidth: {
    if (root.iconOnly && !root.vertical && iconGlyph)
      return Math.max(1, Math.round(iconGlyph.tightWidth))
    return button.labelWidth
  }
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // ---- Panel shape contract for shell.summon/hide/toggle routing ---------
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "agx.screen-time"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function status(): void {
      var p = panelLoader.item
      console.log("agx.screen-time status: opened=" + (p ? p.opened : "no-panel")
        + " label=" + root.label + " hasActivity=" + root.hasActivity
        + " apps=" + (root.service ? root.service.appList().length : "none"))
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical
      ? ""
      : root.iconOnly ? root.glyph : root.glyph + " " + root.label
    labelVisible: !root.vertical && !root.iconOnly
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.5
    tooltipText: root.hasActivity ? "Screen time today \u00b7 " + root.label : "Screen time \u00b7 no activity yet"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleIconOnly()
      else root.togglePanel()
    }

    // Icon-only mode: the Text label is hidden (the slot still sizes off its
    // advance width) and the glyph is painted through an OpticalGlyph, which
    // shifts the Text so the glyph's ink is centred instead of sitting
    // somewhere inside its advance box.
    OpticalGlyph {
      id: iconGlyph
      visible: !root.vertical && root.iconOnly
      anchors.fill: parent
      text: root.glyph
      fontFamily: button.fontFamily
      fontSize: button.fontSize
      color: button.foreground
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData === root.glyph
            ? Style.font.icon
            : (modelData.length > 3 ? button.fontSize * 0.9 : button.fontSize)
          color: button.foreground
        }
      }
    }
  }
}
