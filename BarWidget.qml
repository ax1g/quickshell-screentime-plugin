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

  readonly property string glyph: "󰥔"

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
      ? root.glyph
      : root.glyph + " " + root.label
    labelVisible: !root.vertical
    horizontalMargin: 8.5
    tooltipText: root.hasActivity ? "Screen time today \u00b7 " + root.label : "Screen time \u00b7 no activity yet"
    onPressed: function(b) {
      root.togglePanel()
    }
  }
}
