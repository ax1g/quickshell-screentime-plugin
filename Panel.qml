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
  property bool patternsExpanded: false

  // ---- Donut chart state ------------------------------------------------
  readonly property var segments: Model.arcSegments(root.apps)
  readonly property var sliceColors: Model.sliceColors(root.apps.length, Color.accent)

  // Index of the legend row under the pointer, -1 when nothing is hovered.
  property int hoveredIndex: -1

  readonly property string hoveredAppName: {
    if (root.hoveredIndex >= 0 && root.hoveredIndex < root.apps.length)
      return String(root.apps[root.hoveredIndex].app || "")
    return ""
  }
  readonly property double hoveredAppMs: {
    if (root.hoveredIndex >= 0 && root.hoveredIndex < root.apps.length)
      return Number(root.apps[root.hoveredIndex].ms) || 0
    return root.todayTotal
  }

  // Ring geometry: the radius is fixed for the widest (hovered) stroke so
  // growing the stroke never clips against the Shape bounds.
  readonly property real ringSize: Style.space(116)
  readonly property real ringBaseWidth: Style.space(14)
  readonly property real ringHoverWidth: Style.space(19)
  readonly property real ringRadius: root.ringSize / 2 - root.ringHoverWidth / 2

  // Slice color at a given alpha. ShapePath has no opacity property, so
  // dimming (and the hover highlight) has to come through the stroke color.
  function sliceColor(index, alpha) {
    var hex = String(root.sliceColors[index] || Color.accent).replace(/[#\s]/g, "")
    var r = parseInt(hex.substr(0, 2), 16) / 255
    var g = parseInt(hex.substr(2, 2), 16) / 255
    var b = parseInt(hex.substr(4, 2), 16) / 255
    return Qt.rgba(r, g, b, alpha)
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

  // p key / corner-label click: expand the pattern rows below the app list,
  // scrolling them into view so the toggle is visible wherever the list ends.
  function togglePatterns() {
    root.patternsExpanded = !root.patternsExpanded
    if (root.patternsExpanded) {
      Qt.callLater(function() {
        panelScroll.contentY = Math.max(0, panelScroll.contentHeight - panelScroll.height)
      })
    }
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
        else if (t === "p" || t === "P") root.togglePatterns()
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

          // ---- Hero: today's total, PATTERNS marker top-right ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              text: "󰔟"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              // Nerd Font glyphs paint ~15% of the em above their text box
              // (see PanelSectionHeader), so the clock reads ~2px high; drop
              // it half the overshoot to sit on the label's true center.
              anchors.verticalCenterOffset: Math.ceil(heroIcon.font.pixelSize * 0.15 / 2)
            }

            Text {
              id: patternsCorner
              text: root.patternsExpanded ? "PATTERNS \u25be" : "PATTERNS \u25b8"
              color: patternsCornerMouse.containsMouse
                ? root.contentForeground
                : Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter

              MouseArea {
                id: patternsCornerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.togglePatterns()
              }
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.rightMargin: patternsCorner.implicitWidth + Style.space(12)
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
                text: root.todayTotal > 0 ? Model.fmtWords(root.todayTotal) : "0 MINUTES"
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

          // ---- Per-app donut + legend ----------------------------------
          Item {
            width: parent.width
            visible: root.apps.length > 0
            implicitHeight: visible ? Math.max(root.ringSize, legendColumn.implicitHeight) : 0

            // Clear the hover highlight once the pointer leaves the whole
            // breakdown row (donut or legend).
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onExited: root.hoveredIndex = -1
            }

            Item {
              id: donutItem
              width: root.ringSize
              height: root.ringSize
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter

              // Qt's Shape does not pick up ShapePath children that are
              // created after it initializes, so a Repeater inside a Shape
              // renders nothing. Canvas is the QML-native way to draw a ring
              // with a variable number of slices; it repaints only on demand.
              Canvas {
                id: donutCanvas
                anchors.fill: parent

                Connections {
                  target: root
                  function onSegmentsChanged() { donutCanvas.requestPaint() }
                  function onHoveredIndexChanged() { donutCanvas.requestPaint() }
                  function onSliceColorsChanged() { donutCanvas.requestPaint() }
                }

                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var segs = root.segments
                  if (!segs || segs.length === 0) return
                  var size = width
                  var cx = size / 2
                  var cy = size / 2
                  var rad = root.ringRadius
                  var hovered = root.hoveredIndex
                  var anyHovered = hovered >= 0
                  var toRad = Math.PI / 180
                  for (var i = 0; i < segs.length; i++) {
                    var seg = segs[i]
                    ctx.lineWidth = hovered === i ? root.ringHoverWidth : root.ringBaseWidth
                    ctx.strokeStyle = root.sliceColor(i, anyHovered && hovered !== i ? 0.45 : 1.0)
                    ctx.beginPath()
                    ctx.arc(cx, cy, rad, seg.startAngle * toRad, (seg.startAngle + seg.sweepAngle) * toRad, false)
                    ctx.stroke()
                  }
                }
              }

              // Center readout: hovered app's name + time, else today's total.
              Column {
                anchors.centerIn: parent
                width: parent.width * 0.6
                spacing: Style.space(1)

                Text {
                  text: root.hoveredAppName !== "" ? root.hoveredAppName : "TODAY"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: root.hoveredAppName !== ""
                  elide: Text.ElideRight
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                }

                Text {
                  text: Model.fmt(root.hoveredAppMs)
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  elide: Text.ElideRight
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                }
              }
            }

            Column {
              id: legendColumn
              anchors.left: donutItem.right
              anchors.leftMargin: Style.space(16)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(5)

              Repeater {
                model: root.apps

                Item {
                  required property var modelData
                  required property int index

                  readonly property string appName: String(modelData.app || "")
                  readonly property string timeLabel: Model.fmt(modelData.ms)

                  width: parent.width
                  implicitHeight: Math.max(swatch.implicitHeight, Math.max(appNameText.implicitHeight, appTimeText.implicitHeight))

                  MouseArea {
                    id: legendRowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.hoveredIndex = index
                    onExited: if (root.hoveredIndex === index) root.hoveredIndex = -1
                  }

                  Rectangle {
                    id: swatch
                    width: Style.space(7)
                    height: width
                    radius: width / 2
                    color: root.sliceColors[index] || Color.accent
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    id: appNameText
                    text: appName
                    color: root.contentForeground
                    opacity: 0.6
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    width: parent.width - appTimeText.implicitWidth - Style.space(8)
                    anchors.left: swatch.right
                    anchors.leftMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    id: appTimeText
                    text: timeLabel
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }

          // ---- Patterns (collapsed by default, toggle with p/click) ----
          Item {
            width: parent.width
            visible: root.patternsExpanded && root.insightRows.length > 0
            implicitHeight: visible ? patternsColumn.implicitHeight : 0

            Column {
              id: patternsColumn
              width: parent.width
              spacing: Style.space(6)

              PanelSeparator {
                width: parent.width
                foreground: root.contentForeground
              }

              Repeater {
                model: root.insightRows

                Item {
                  required property var modelData

                  readonly property string label: String(modelData.label || "")
                  readonly property string value: String(modelData.value || "")

                  width: parent.width
                  implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

                  Text {
                    id: labelText
                    text: label
                    color: root.contentForeground
                    opacity: 0.6
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    id: valueText
                    text: value
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
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
