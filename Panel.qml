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
  readonly property bool serviceReady: service && service.ready === true
  readonly property var today: service ? service.today : null
  readonly property var days: service ? service.days : {}
  readonly property string todayKey: serviceReady ? service.todayKey : ""

  // Day selection: clicking a week-trend bar sets selectedKey; empty = live
  // today.  All derived data flows from activeDay / activeDayKey so the
  // donut, legend, hero, and insights automatically reflect the selection.
  property string selectedKey: ""
  readonly property var activeDay: serviceReady ? Model.dayFor(root.days, root.today, root.selectedKey, root.todayKey) : null
  readonly property string activeDayKey: root.selectedKey || root.todayKey
  readonly property string activeDayLabel: serviceReady ? Model.relativeDayLabel(root.activeDayKey, root.todayKey) : ""
  readonly property double dayTotal: root.activeDay ? (root.activeDay.total || 0) : 0

  // All derived data is gated on service.ready: before the service has
  // loaded its history, todayKey is "" and the Model helpers would produce
  // garbage labels ("NaN-NaN-NaN") instead of an empty chart.
  readonly property var groupedApps: serviceReady ? Model.groupedApps(Model.appList(root.activeDay), Model.DONUT_MAX_SLICES, Model.DONUT_MIN_PCT) : []
  readonly property var fullApps: serviceReady ? Model.appList(root.activeDay) : []
  readonly property var insightRows: serviceReady ? Model.insights(root.activeDay, root.days, root.todayKey, root.activeDayKey) : []
  readonly property var weekTrend: serviceReady ? Model.weekTrend(root.days, root.todayKey) : []
  readonly property double weekMax: {
    var max = 0
    var list = root.weekTrend
    for (var i = 0; i < list.length; i++) max = Math.max(max, Number(list[i].ms) || 0)
    return max
  }
  property bool expanded: false

  // Donut always shows the grouped view; the legend expands inline.
  readonly property var segments: Model.arcSegments(root.groupedApps)
  readonly property var sliceColors: Model.sliceColors(root.groupedApps.length, Color.accent)
  readonly property int groupedCount: root.groupedApps.length
  // The "Other" slice color: last in the grouped palette.
  readonly property color otherColor: root.groupedCount > 0
    ? (root.sliceColors[root.groupedCount - 1] || Color.accent) : Color.accent

  // Ring geometry: the radius is fixed for the base stroke so it never
  // clips against the Shape bounds.
  readonly property real ringSize: Style.space(116)
  readonly property real ringBaseWidth: Style.space(14)
  readonly property real ringRadius: root.ringSize / 2 - root.ringBaseWidth / 2

  // Legend scroll cap: fits the 6-row grouped list fully; when expanded
  // the full app list scrolls inside this height with a ▾ indicator.
  readonly property real legendMaxHeight: Style.space(140)

  // Slice color at a given alpha (alpha 1 for the ring, dimmed variants
  // used by the trend bars).
  function sliceColor(index, alpha) {
    var hex = String(root.sliceColors[index] || Color.accent).replace(/[#\s]/g, "")
    var r = parseInt(hex.substr(0, 2), 16) / 255
    var g = parseInt(hex.substr(2, 2), 16) / 255
    var b = parseInt(hex.substr(4, 2), 16) / 255
    return Qt.rgba(r, g, b, alpha)
  }

  // Per-row glyph for the patterns section: a filled star for the top app,
  // a trend arrow for vs-yesterday, a hollow star for the busiest day.
  function insightIcon(label, value) {
    if (label.indexOf("Top app") === 0) return "\u2605"
    if (label.indexOf("vs") === 0) return root.deltaArrow(value)
    if (label.indexOf("Busiest") === 0) return "\u2606"
    return ""
  }

  // More time than yesterday reads full, less time reads dimmed.
  function insightIconColor(label, value) {
    if (label.indexOf("vs") === 0 && String(value).charAt(0) === "-")
      return Qt.darker(root.contentForeground, 1.5)
    return root.contentForeground
  }

  function deltaArrow(value) {
    var sign = String(value).charAt(0)
    if (sign === "+") return "\u2197"
    if (sign === "-") return "\u2198"
    return "\u2192"
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

  function toggleExpanded() {
    root.expanded = !root.expanded
  }

  function selectDay(key) {
    if (!key) return
    if (key === root.todayKey || root.selectedKey === key)
      root.selectedKey = ""
    else
      root.selectedKey = key
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
        if (t === "p" || t === "P") root.toggleExpanded()
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

          // ---- Hero: today's total, SHOW MORE/LESS toggle top-right ------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              text: "󰔟"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.fontPx(2.8)
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.topMargin: -Style.space(4)
            }

            Row {
              id: showMoreCorner
              spacing: Style.space(2)
              anchors.right: parent.right
              anchors.top: parent.top

              Text {
                text: root.expanded ? "SHOW LESS" : "SHOW MORE"
                color: showMoreCornerMouse.containsMouse
                  ? root.contentForeground
                  : Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: root.expanded ? "\u25be" : "\u25b8"
                color: showMoreCornerMouse.containsMouse
                  ? root.contentForeground
                  : Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              id: showMoreCornerMouse
              anchors.fill: showMoreCorner
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleExpanded()
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.rightMargin: showMoreCorner.implicitWidth + Style.space(12)
              anchors.top: parent.top
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
                text: root.dayTotal > 0 ? Model.fmtWords(root.dayTotal) : "0 MINUTES"
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          // ---- Per-app donut + legend ------------------------------------
          Item {
            width: parent.width
            implicitHeight: Math.max(root.ringSize, legendScroll.height)

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
                  function onSliceColorsChanged() { donutCanvas.requestPaint() }
                }

                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var segs = root.segments
                  var size = width
                  var cx = size / 2
                  var cy = size / 2
                  var rad = root.ringRadius
                  var toRad = Math.PI / 180

                  if (!segs || segs.length === 0) {
                    ctx.lineWidth = root.ringBaseWidth
                    ctx.strokeStyle = Qt.rgba(
                      root.contentForeground.r,
                      root.contentForeground.g,
                      root.contentForeground.b, 0.1)
                    ctx.beginPath()
                    ctx.arc(cx, cy, rad, 0, Math.PI * 2, false)
                    ctx.stroke()
                    return
                  }

                  for (var i = 0; i < segs.length; i++) {
                    var seg = segs[i]
                    ctx.lineWidth = root.ringBaseWidth
                    ctx.strokeStyle = root.sliceColor(i, 1.0)
                    ctx.beginPath()
                    ctx.arc(cx, cy, rad, seg.startAngle * toRad, (seg.startAngle + seg.sweepAngle) * toRad, false)
                    ctx.stroke()
                  }
                }
              }

              // Center readout: active day label + total.
              Column {
                anchors.centerIn: parent
                width: parent.width * 0.6
                spacing: Style.space(1)

                Text {
                  text: root.activeDayLabel.toUpperCase()
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideRight
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                }

                Text {
                  text: Model.fmt(root.dayTotal)
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

            Flickable {
              id: legendScroll
              anchors.left: donutItem.right
              anchors.leftMargin: Style.space(16)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              clip: true
              contentWidth: width
              contentHeight: legendList.implicitHeight
              height: Math.min(legendList.implicitHeight, root.legendMaxHeight)
              interactive: contentHeight > height
              flickableDirection: Flickable.VerticalFlick
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: legendList
                width: parent.width - Style.space(8)
                spacing: Style.space(5)

                // Empty-state message when the selected day has no data.
                Text {
                  visible: root.groupedApps.length === 0
                  text: "No data"
                  color: root.contentForeground
                  opacity: 0.4
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                }

                Repeater {
                  model: root.expanded ? root.fullApps : root.groupedApps

                  Item {
                    required property var modelData
                    required property int index

                    readonly property string appName: String(modelData.app || "")
                    readonly property string appLabel: Model.displayName(modelData.app)
                    readonly property string timeLabel: Model.fmt(modelData.ms)
                    // Top N-1 apps keep the grouped palette; everything that
                    // was collapsed into "Other" shares that slice's color.
                    readonly property color swatchColor: root.expanded && index >= root.groupedCount - 1
                      ? root.otherColor
                      : (root.sliceColors[index] || Color.accent)

                    width: parent.width
                    implicitHeight: Math.max(swatch.implicitHeight, Math.max(appNameText.implicitHeight, appTimeText.implicitHeight))

                    Rectangle {
                      id: swatch
                      width: Style.space(7)
                      height: width
                      radius: width / 2
                      color: swatchColor
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      id: appNameText
                      text: appLabel
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

            // Thin scrollbar indicator on the right edge.
            Rectangle {
              property real ratio: legendScroll.contentHeight > 0
                ? legendScroll.height / legendScroll.contentHeight : 0
              visible: legendScroll.contentHeight > legendScroll.height
              width: Style.space(3)
              height: Math.max(Style.space(16), legendScroll.height * ratio)
              radius: width / 2
              color: root.contentForeground
              opacity: 0.25
              anchors.right: legendScroll.right
              y: legendScroll.y + (legendScroll.height - height) * (
                   legendScroll.contentHeight > legendScroll.height
                     ? legendScroll.contentY / (legendScroll.contentHeight - legendScroll.height)
                     : 0)
            }
          }

          // ---- Week trend + insights (only on SHOW MORE) -----------------
          Item {
            width: parent.width
            visible: root.expanded
            implicitHeight: visible ? patternsColumn.implicitHeight : 0

            Column {
              id: patternsColumn
              width: parent.width
              spacing: Style.space(10)

              PanelSeparator {
                width: parent.width
                foreground: root.contentForeground
              }

              // 7-day trend strip: bars scale to the busiest day; the
              // active day (selected or today) is full accent, the rest dim.
              Row {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.weekTrend

                  Column {
                    required property var modelData

                    readonly property bool isActive: modelData.key === root.activeDayKey

                    width: (parent.width - parent.spacing * 6) / 7
                    spacing: Style.space(3)

                    Item {
                      id: trendSlot
                      width: parent.width
                      height: Style.space(42)

                      MouseArea {
                        id: trendSlotMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectDay(modelData.key)
                      }

                      Rectangle {
                        width: parent.width * 0.42
                        radius: Style.space(2)
                        color: isActive ? root.sliceColor(0, 1.0) : root.sliceColor(0, 0.28)
                        opacity: trendSlotMouse.containsMouse && !isActive ? 0.5 : 1.0
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        height: {
                          if (modelData.ms <= 0 || root.weekMax <= 0) return 3
                          return Math.max(3, trendSlot.height * Number(modelData.ms) / root.weekMax)
                        }
                      }
                    }

                    Text {
                      text: modelData.label
                      color: root.contentForeground
                      opacity: isActive ? 1.0 : 0.5
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: isActive
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                    }

                    // Dot indicator under the active day.
                    Rectangle {
                      width: Style.space(3)
                      height: width
                      radius: width / 2
                      color: root.sliceColor(0, 1.0)
                      visible: isActive
                      anchors.horizontalCenter: parent.horizontalCenter
                    }
                  }
                }
              }

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
                  implicitHeight: Math.max(iconText.implicitHeight, Math.max(labelText.implicitHeight, valueText.implicitHeight))

                  Text {
                    id: iconText
                    text: root.insightIcon(label, value)
                    color: root.insightIconColor(label, value)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    width: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    id: labelText
                    text: label
                    color: root.contentForeground
                    opacity: 0.6
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    anchors.left: iconText.right
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
                    width: parent.width * 0.55
                    horizontalAlignment: Text.AlignRight
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // Reset to today's live data when the panel is dismissed.
  Connections {
    target: root.controller
    function onOpenChanged() {
      if (!root.controller.open) root.selectedKey = ""
    }
  }
}
