import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Popup for the screen-time bar widget: today's total, the per-app
// breakdown, and a short behaviour-insights section. Read-only — the panel
// is a mirror of the Service's live state.
Panel {
  id: root
  moduleName: "agx.screen-time"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // The bar tracks the widget mounted in its slot — BarWidget.qml — so the
  // popout coordinator and panel switching must identify us by that widget.
  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("agx.screen-time") : null
  readonly property var today: service ? service.today : null
  readonly property var days: service ? service.days : {}
  readonly property string todayKey: service ? service.todayKey : ""

  readonly property var apps: Model.appList(root.today)
  readonly property var insightRows: Model.insights(root.today, root.days, root.todayKey)
  readonly property double todayTotal: root.today ? (root.today.total || 0) : 0
  readonly property double yesterdayTotal: Model.totalFor(root.days, Model.prevKey(root.todayKey))
  readonly property string deltaLabel: {
    if (yesterdayTotal <= 0 || todayTotal <= 0) return ""
    var d = todayTotal - yesterdayTotal
    return "vs yesterday " + (d < 0 ? "-" : "+") + Model.fmtWords(Math.abs(d))
  }

  // Guarded so the widget renders before the bar is injected.
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function scrollBy(dy) {
    var flick = panelScroll
    if (!flick || flick.contentHeight <= flick.height) return
    flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy))
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(480))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.scrollBy(-dy * Style.space(24))
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "g") panelScroll.contentY = 0
        else if (t === "G") panelScroll.contentY = Math.max(0, panelScroll.contentHeight - panelScroll.height)
      }

      Flickable {
        id: panelScroll
        anchors.fill: parent
        contentWidth: panelColumn.width
        contentHeight: panelColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: panelColumn
          width: panelScroll.width
          spacing: Style.space(12)

          // ---- Hero: today's total -------------------------------------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              text: "󰥔"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Screen Time"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: root.todayTotal > 0
                  ? Model.fmtWords(root.todayTotal) + (root.deltaLabel ? "  \u00b7  " + root.deltaLabel : "")
                  : "0 MINUTES"
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          // ---- Per-app breakdown ---------------------------------------
          Item {
            width: parent.width
            visible: root.apps.length > 0
            implicitHeight: visible ? appColumn.implicitHeight : 0

            Column {
              id: appColumn
              width: parent.width
              spacing: Style.space(10)

              Repeater {
                model: root.apps

                Item {
                  required property var modelData
                  required property int index

                  readonly property string appName: String(modelData.app || "")
                  readonly property string timeLabel: Model.fmt(modelData.ms)
                  readonly property int pct: modelData.pct
                  readonly property int barHeight: Style.space(5)
                  readonly property int barGap: Style.space(5)

                  width: parent.width
                  implicitHeight: appRow.implicitHeight + barGap + barHeight

                  Row {
                    id: appRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: Style.space(8)

                    Text {
                      id: nameLabel
                      text: appName
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      width: parent.width - appTime.width - parent.spacing
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      id: appTime
                      text: timeLabel
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                      width: Style.space(64)
                      horizontalAlignment: Text.AlignRight
                      elide: Text.ElideRight
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: appRow.bottom
                    anchors.topMargin: barGap
                    height: barHeight
                    radius: Style.cornerRadius > 0 ? height / 2 : 0
                    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                    Rectangle {
                      width: Math.round(parent.width * (pct / 100))
                      height: parent.height
                      radius: parent.radius
                      color: Style.selectedStateColor(root.contentForeground, Color.accent)

                      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }
                  }
                }
              }
            }
          }

          // ---- Insights -------------------------------------------------
          Item {
            width: parent.width
            visible: root.insightRows.length > 0
            implicitHeight: visible ? insightColumn.implicitHeight : 0

            Column {
              id: insightColumn
              width: parent.width
              spacing: Style.space(6)

              PanelSeparator {
                width: parent.width
                foreground: root.contentForeground
              }

              Text {
                text: "PATTERNS"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1.2
                font.bold: true
              }

              Repeater {
                model: root.insightRows

                Item {
                  required property var modelData

                  readonly property string label: String(modelData.label || "").toUpperCase()
                  readonly property string value: String(modelData.value || "")

                  width: parent.width
                  implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

                  Text {
                    id: labelText
                    text: label
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    id: valueText
                    text: value
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    width: parent.width * 0.62
                    horizontalAlignment: Text.AlignRight
                  }
                }
              }
            }
          }

          Item {
            width: parent.width
            height: Style.space(2)
          }
        }
      }
    }
  }
}
