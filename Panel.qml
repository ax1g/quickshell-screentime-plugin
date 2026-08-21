import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model

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
  readonly property var months: service ? service.months : {}
  readonly property string todayKey: serviceReady ? service.todayKey : ""

  // Day selection: clicking a week-trend bar sets selectedKey; empty = live
  // today.  All derived data flows from activeDay / activeDayKey so the
  // donut, legend, hero, and insights automatically reflect the selection.
  property string selectedKey: ""
  readonly property var activeDay: serviceReady ? Model.dayFor(root.days, root.today, root.selectedKey, root.todayKey) : null
  readonly property string activeDayKey: root.selectedKey || root.todayKey
  readonly property string activeDayLabel: serviceReady ? Model.formatDate(root.activeDayKey) : ""
  readonly property double dayTotal: root.activeDay ? (root.activeDay.total || 0) : 0

  // All derived data is gated on service.ready: before the service has
  // loaded its history, todayKey is "" and the Model helpers would produce
  // garbage labels ("NaN-NaN-NaN") instead of an empty chart.
  readonly property var groupedApps: serviceReady ? Model.groupedApps(Model.appList(root.activeDay), Model.DONUT_MAX_SLICES, Model.DONUT_MIN_PCT) : []
  readonly property var fullApps: serviceReady ? Model.appList(root.activeDay) : []
  readonly property var insightRows: serviceReady ? Model.insights(root.activeDay, root.days, root.todayKey, root.activeDayKey) : []
  readonly property var scrollableWeeks: serviceReady ? Model.monSunWeeks(root.days, root.todayKey, 13) : []
  readonly property double scrollableMax: Model.scrollableTrendMax(root.scrollableWeeks)
  readonly property var visibleWeek: root.scrollableWeeks.length > root.weekOffset
    ? root.scrollableWeeks[root.weekOffset] : null
  readonly property double visibleWeekMax: {
    if (!root.visibleWeek) return 0
    var max = 0
    var days = root.visibleWeek.days
    for (var i = 0; i < days.length; i++) {
      var ms = Number(days[i].ms) || 0
      if (ms > max) max = ms
    }
    return max
  }
  // Sum of the visible week's days, shown under the paginated bar graph.
  readonly property double visibleWeekTotalMs: root.visibleWeek
    ? Model.weekTotal(root.visibleWeek.days) : 0
  property bool expanded: false
  property bool calendarOpen: false
  property int weekOffset: 0
  // Header total toggles between absolute time and share of the full week.
  property bool weekTotalAsPct: false

  // Calendar view: yearly overview with navigation. currentYearOffset counts
  // how many years back from today we are viewing; 0 = current year.
  readonly property int todayYear: serviceReady ? Number(root.todayKey.split("-")[0]) || 2026 : 2026
  property int currentYearOffset: 0
  readonly property int currentYear: root.todayYear - root.currentYearOffset
  readonly property int oldestDataYear: serviceReady ? Model.firstDataYear(root.days, root.months) : root.todayYear
  readonly property string calendarYearTotal: serviceReady ? Model.fmt(Model.yearTotal(root.days, root.months, root.currentYear)) : "0h"
  readonly property var monthNamesShort: ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
  readonly property var monthNamesLong: ["January","February","March","April","May","June","July","August","September","October","November","December"]

  // Shared panel-styled tooltip: matches the drawer's background, foreground
  // and font so popups read as part of the shell rather than platform chrome.
  component PanelToolTip: ToolTip {
    id: panelTip
    property string tipText: ""
    delay: 300
    padding: 0
    background: Rectangle {
      color: bar ? bar.background : Color.background
      border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.25)
      border.width: 1
      radius: Style.space(3)
    }
    contentItem: Text {
      text: panelTip.tipText
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      leftPadding: Style.space(8)
      rightPadding: Style.space(8)
      topPadding: Style.space(4)
      bottomPadding: Style.space(4)
    }
  }

  // Donut always shows the grouped view; the legend expands inline.
  readonly property var segments: Model.arcSegments(root.groupedApps)
  readonly property var sliceColors: Model.sliceColors(root.groupedApps.length, Color.accent)
  readonly property int groupedCount: root.groupedApps.length
  // The "Other" slice color: last in the grouped palette.
  readonly property color otherColor: root.groupedCount > 0
    ? (root.sliceColors[root.groupedCount - 1] || Color.accent) : Color.accent

  // Donut cross-highlight: which ring slice is hovered (-1 = none), plus
  // the label pair shown in the donut center while hovering.
  property int hoverSlice: -1
  property string hoverApp: ""
  property double hoverMs: 0
  readonly property bool sliceHovered: root.hoverSlice >= 0
    && root.hoverSlice < root.segments.length && root.hoverApp !== ""

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
    // Freeze the collapsed card height before growing, so the yearly
    // overview drawer can keep show-less dimensions while expanded.
    if (!root.expanded) keyCatcher.collapsedCardH = keyCatcher.height
    root.expanded = !root.expanded
  }

  function selectDay(key) {
    if (!key) return
    if (key === root.todayKey || root.selectedKey === key)
      root.selectedKey = ""
    else
      root.selectedKey = key
  }

  function setSliceHover(slice, appName, ms) {
    root.hoverSlice = slice
    root.hoverApp = appName
    root.hoverMs = ms
  }

  function clearHover() {
    root.hoverSlice = -1
    root.hoverApp = ""
    root.hoverMs = 0
  }

  // Open/close the yearly overview. Arms the drawer slide so the move
  // animates; layout-driven repositions stay instant (see calendarDrawer).
  function openCalendar(open) {
    calendarDrawer.sliding = true
    root.calendarOpen = open
  }

  // Angle hit-test for the ring; x/y are in donutItem coordinates. Angles
  // are degrees clockwise from 12 o'clock (arcSegments' convention); atan2
  // with y-down screen coordinates matches once normalized to [-90, 270).
  function sliceAt(x, y) {
    var segs = root.segments
    if (!segs || segs.length === 0) return -1
    var dx = x - donutItem.width / 2
    var dy = y - donutItem.height / 2
    var r = Math.sqrt(dx * dx + dy * dy)
    var inner = root.ringRadius - root.ringBaseWidth / 2 - Style.space(3)
    var outer = root.ringRadius + root.ringBaseWidth / 2 + Style.space(3)
    if (r < inner || r > outer) return -1
    var deg = Math.atan2(dy, dx) * 180 / Math.PI
    if (deg < -90) deg += 360
    for (var i = 0; i < segs.length; i++) {
      var start = segs[i].startAngle
      var end = start + segs[i].sweepAngle
      if (end <= 360 ? (deg >= start && deg <= end)
                     : (deg >= start || deg <= end - 360))
        return i
    }
    return -1
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
      clip: true
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.scrollBy(-dy * Style.space(24))
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "p" || t === "P") root.toggleExpanded()
      }

      // ---- Calendar side drawer (full-card overlay) -----------------------
      // Relative to the card content area (this item), NOT panel.width —
      // the KeyboardPanel is the full-screen overlay window.
      readonly property real drawerWidth: width

      // Height of the card in the collapsed (show less) state, captured by
      // toggleExpanded() before expansion so the drawer keeps that size.
      property real collapsedCardH: 0

      Item {
        id: calendarDrawer
        width: keyCatcher.drawerWidth
        height: keyCatcher.collapsedCardH > 0
          ? Math.min(keyCatcher.height, keyCatcher.collapsedCardH) : keyCatcher.height
        anchors.top: parent.top
        x: root.calendarOpen ? 0 : -keyCatcher.drawerWidth
        z: 10
        visible: x > -keyCatcher.drawerWidth

        // True only while an open/close toggle drives the slide. Layout-driven
        // x changes (the panel width arriving on open, later resizes) must
        // snap instantly, otherwise the drawer flashes across the content.
        property bool sliding: false

        Behavior on x {
          enabled: calendarDrawer.sliding
          NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        // Disarm once the drawer reaches its resting position so later
        // layout-driven moves don't replay the slide.
        onXChanged: {
          if (root.calendarOpen ? x >= 0 : x <= -keyCatcher.drawerWidth)
            sliding = false
        }

        Rectangle {
          anchors.fill: parent
          color: bar ? bar.background : Color.background
          radius: Style.space(6)
        }

        // Swallows hover and clicks so they don't reach the donut, legend
        // and week graph beneath the drawer. Declared before the scroll
        // view so the drawer's own controls stay on top of it.
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onClicked: function (mouse) { mouse.accepted = true }
        }

        Flickable {
          id: calendarScroll
          anchors.fill: parent
          anchors.margins: Style.space(6)
          contentWidth: width
          contentHeight: calendarColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          Column {
            id: calendarColumn
            width: calendarScroll.width
            spacing: Style.space(4)

            Item {
              id: yearHeader
              width: parent.width
              height: Math.max(calendarBack.implicitHeight, yearNav.implicitHeight, yearTotalLabel.implicitHeight)

              // Closes the yearly overview and returns to the main panel.
              Text {
                id: calendarBack
                text: "\uf053"
                color: calendarBackMouse.containsMouse
                  ? root.contentForeground : Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  id: calendarBackMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(6)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openCalendar(false)
                }
              }

              Row {
                id: yearNav
                spacing: Style.space(10)
                anchors.centerIn: parent

                Text {
                  text: "\uf053"
                  color: yearPrevMouse.enabled && yearPrevMouse.containsMouse
                    ? root.contentForeground : Qt.darker(root.contentForeground, 1.4)
                  opacity: yearPrevMouse.enabled ? 1.0 : 0.25
                  Behavior on opacity { NumberAnimation { duration: 150 } }
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter

                  MouseArea {
                    id: yearPrevMouse
                    anchors.fill: parent
                    anchors.margins: -Style.space(6)
                    hoverEnabled: true
                    enabled: root.currentYear > root.oldestDataYear
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.currentYearOffset += 1
                  }
                }

                Text {
                  text: String(root.currentYear)
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: "\uf054"
                  color: yearNextMouse.enabled && yearNextMouse.containsMouse
                    ? root.contentForeground : Qt.darker(root.contentForeground, 1.4)
                  opacity: yearNextMouse.enabled ? 1.0 : 0.25
                  Behavior on opacity { NumberAnimation { duration: 150 } }
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter

                  MouseArea {
                    id: yearNextMouse
                    anchors.fill: parent
                    anchors.margins: -Style.space(6)
                    hoverEnabled: true
                    enabled: root.currentYearOffset > 0
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.currentYearOffset -= 1
                  }
                }
              }

              Text {
                id: yearTotalLabel
                text: root.calendarYearTotal
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            // Year overview: one bar per month, length = share of the
            // busiest month. Hover a bar for its exact total.
            Column {
              id: heatGrid
              width: parent.width
              spacing: Style.space(3)

              readonly property var months: root.serviceReady
                ? Model.monthlyTotals(root.days, root.months, root.currentYear) : []
              readonly property real maxMs: {
                var max = 0
                for (var i = 0; i < months.length; i++) {
                  if (months[i].ms > max) max = months[i].ms
                }
                return max
              }
              readonly property bool isThisYear: root.currentYear === new Date().getFullYear()
              readonly property int nowMonth: new Date().getMonth()
              readonly property real labelW: Style.space(26)
              readonly property real labelGap: Style.space(4)
              // Wide enough for any "NNNh NNm" total at the current font.
              readonly property real hoursW: hoursMetrics.implicitWidth

              Text {
                id: hoursMetrics
                visible: false
                text: "888h 88m"
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              Repeater {
                model: 12

                Item {
                  id: monthRow
                  required property int index

                  width: heatGrid.width
                  height: Style.space(10)

                  readonly property bool isCurrentMonth: heatGrid.isThisYear && index === heatGrid.nowMonth
                  readonly property real hoursW: heatGrid.hoursW
                  readonly property real availW: heatGrid.width - heatGrid.labelW - heatGrid.labelGap - hoursW - heatGrid.labelGap
                  readonly property real ratio: heatGrid.maxMs > 0
                    ? (heatGrid.months[index] ? heatGrid.months[index].ms / heatGrid.maxMs : 0) : 0

                  Text {
                    text: root.monthNamesShort[monthRow.index]
                    color: root.contentForeground
                    opacity: monthRow.isCurrentMonth ? 1.0 : 0.55
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: monthRow.isCurrentMonth
                    width: heatGrid.labelW
                    elide: Text.ElideRight
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  // Faint full-width track so empty months still read as rows.
                  Rectangle {
                    x: heatGrid.labelW + heatGrid.labelGap
                    width: monthRow.availW
                    height: parent.height
                    radius: Style.space(2)
                    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                  }

                  Rectangle {
                    id: monthBar
                    x: heatGrid.labelW + heatGrid.labelGap
                    width: Math.max(0, monthRow.availW * monthRow.ratio)
                    height: parent.height
                    radius: Style.space(2)
                    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.8)

                    MouseArea {
                      id: monthBarMouse
                      anchors.fill: parent
                      anchors.margins: -Style.space(4)
                      hoverEnabled: true
                    }

                    PanelToolTip {
                      visible: monthBarMouse.containsMouse
                      tipText: {
                        var m = heatGrid.months[monthRow.index]
                        return root.monthNamesLong[monthRow.index] + " \u00b7 " + (m ? Model.fmt(m.ms) : "0h")
                      }
                    }
                  }

                  Text {
                    text: {
                      var m = heatGrid.months[monthRow.index]
                      return m ? m.hours : "0h"
                    }
                    color: root.contentForeground
                    opacity: monthRow.isCurrentMonth ? 1.0 : 0.55
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: monthRow.isCurrentMonth
                    horizontalAlignment: Text.AlignRight
                    width: monthRow.hoursW
                    elide: Text.ElideRight
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }
            }
          }
        }
      }

      // ---- Main content (full width, drawer slides over it) --------------
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
            height: implicitHeight
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            // Easter egg: the hourglass is turned exactly on the hour.
            property int lastFlipHour: -1

            Timer {
              id: hourTick
              interval: root.serviceReady ? Model.msUntilNextHour(Date.now()) : 60000
              repeat: false
              running: root.serviceReady
              onTriggered: {
                var h = new Date().getHours()
                if (h !== parent.lastFlipHour) {
                  parent.lastFlipHour = h
                  heroFlip.restart()
                }
                interval = Model.msUntilNextHour(Date.now())
                restart()
              }
            }

            SequentialAnimation {
              id: heroFlip
              NumberAnimation {
                target: heroIcon
                property: "rotation"
                from: 0
                to: 360
                duration: 700
                easing.type: Easing.OutBack
              }
            }

            Text {
              id: heroIcon
              text: "󰔟"
              color: heroIconMouse.containsMouse
                ? root.contentForeground
                : (root.calendarOpen ? root.contentForeground : root.contentForeground)
              font.family: root.contentFontFamily
              font.pixelSize: Style.fontPx(2.8)
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.topMargin: -Style.space(4)

              MouseArea {
                id: heroIconMouse
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openCalendar(!root.calendarOpen)
                onContainsMouseChanged: if (containsMouse) sparkles.launch()
              }
            }

            // Hover sparkles: a handful of tiny stars drifting up from the
            // hourglass and fading out. Replays on every hover-enter.
            Item {
              id: sparkles
              anchors.centerIn: heroIcon
              width: heroIcon.width + Style.space(16)
              height: heroIcon.height + Style.space(10)
              z: 5

              property bool go: false

              function launch() {
                go = false
                go = true
              }

              Repeater {
                id: sparkleRepeater
                model: 6

                Text {
                  id: sp
                  required property int index

                  text: "\u2726"
                  color: "#FFD700"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  opacity: 0
                  x: sparkles.width * (0.12 + 0.76 * Math.random())
                  y: sparkles.height * 0.55
                  scale: 1

                  readonly property real startY: sparkles.height * 0.55
                  readonly property real drift: Style.space(8) + Style.space(8) * Math.random()

                  SequentialAnimation {
                    running: sparkles.go
                    PauseAnimation { duration: sp.index * 80 }
                    NumberAnimation { target: sp; property: "opacity"; from: 0; to: 0.85; duration: 180 }
                    ParallelAnimation {
                    NumberAnimation { target: sp; property: "y"; from: sp.startY; to: sp.startY - sp.drift; duration: 650; easing.type: Easing.OutQuad }
                    NumberAnimation { target: sp; property: "opacity"; from: 0.85; to: 0; duration: 650; easing.type: Easing.InQuad }
                    NumberAnimation { target: sp; property: "scale"; from: 1; to: 0.6; duration: 650 }
                    }
                  }
                }
              }
            }

            Row {
              id: showMoreCorner
              spacing: Style.space(4)
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
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          // ---- Per-app donut + legend ------------------------------------
          Item {
            width: parent.width
            height: implicitHeight
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
                  function onHoverSliceChanged() { donutCanvas.requestPaint() }
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
                    // Cross-highlight: the hovered slice stays full, the
                    // rest dim so the eye locks onto one app.
                    ctx.strokeStyle = root.sliceColor(
                      i, root.hoverSlice < 0 || i === root.hoverSlice ? 1.0 : 0.25)
                    ctx.beginPath()
                    ctx.arc(cx, cy, rad, seg.startAngle * toRad, (seg.startAngle + seg.sweepAngle) * toRad, false)
                    ctx.stroke()
                  }
                }
              }

              // Slice hover: pointer feedback plus the app's own readout
              // in place of the day summary.
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                cursorShape: root.hoverSlice >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPositionChanged: function(mouse) {
                  var i = root.sliceAt(mouse.x, mouse.y)
                  if (i >= 0) {
                    var seg = root.segments[i]
                    root.setSliceHover(i, Model.displayName(seg.app), seg.ms || 0)
                  } else {
                    root.clearHover()
                  }
                }
                onContainsMouseChanged: if (!containsMouse) root.clearHover()
              }

              // Center readout: active day label + total, or the hovered
              // slice's app while cross-highlighting.
              Column {
                anchors.centerIn: parent
                width: parent.width * 0.6
                spacing: Style.space(1)

                Text {
                  text: root.sliceHovered ? root.hoverApp : root.activeDayLabel
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideRight
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                }

                Text {
                  text: Model.fmt(root.sliceHovered ? root.hoverMs : root.dayTotal)
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
              // Fixed height so the panel size stays identical across days.
              height: root.legendMaxHeight
              interactive: contentHeight > height
              flickableDirection: Flickable.VerticalFlick
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: legendList
                width: parent.width - Style.space(8)
                spacing: Style.space(5)
                // Vertically center short lists within the fixed-height
                // viewport; clamp to 0 so long lists still scroll from top.
                y: Math.max(0, (legendScroll.height - implicitHeight) / 2)

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
            height: visible ? patternsColumn.implicitHeight : 0
            implicitHeight: height

            Column {
              id: patternsColumn
              width: parent.width
              spacing: Style.space(10)

              PanelSeparator {
                width: parent.width
                foreground: root.contentForeground
              }

              // Paginated Mon-Sun week bar graph with < Month Year > navigation.
              // Shows one week at a time; weekOffset 0 = current week.
              Item {
                width: parent.width
                height: weekNavColumn.implicitHeight
                implicitHeight: height

                Column {
                  id: weekNavColumn
                  width: parent.width
                  spacing: Style.space(18)

                  // Header row: < Month Year > on the left, the visible
                  // week's total on the right. Arrows stay visible but fade
                  // out at the edges of the 13-week window.
                  Item {
                    width: parent.width
                    implicitHeight: Math.max(navRow.implicitHeight, weekTotalLabel.implicitHeight)

                    Row {
                      id: navRow
                      spacing: Style.space(10)
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        text: "\uf053"
                        color: weekPrevMouse.enabled && weekPrevMouse.containsMouse
                          ? root.contentForeground : Qt.darker(root.contentForeground, 1.4)
                        opacity: weekPrevMouse.enabled ? 1.0 : 0.25
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                          id: weekPrevMouse
                          anchors.fill: parent
                          anchors.margins: -Style.space(6)
                          hoverEnabled: true
                          enabled: root.weekOffset < 12
                          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                          onClicked: root.weekOffset = Math.min(12, root.weekOffset + 1)
                        }
                      }

                      Text {
                        text: {
                          if (!root.visibleWeek) return ""
                          var d = root.visibleWeek.days[0]
                          if (!d) return ""
                          var parts = d.key.split("-")
                          var monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
                          var mi = Number(parts[1]) - 1
                          return (monthNames[mi] || "") + " " + parts[0] + " \u00b7 W" + Model.isoWeekNumber(d.key)
                        }
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      Text {
                        text: "\uf054"
                        color: weekNextMouse.enabled && weekNextMouse.containsMouse
                          ? root.contentForeground : Qt.darker(root.contentForeground, 1.4)
                        opacity: weekNextMouse.enabled ? 1.0 : 0.25
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                          id: weekNextMouse
                          anchors.fill: parent
                          anchors.margins: -Style.space(6)
                          hoverEnabled: true
                          enabled: root.weekOffset > 0
                          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                          onClicked: root.weekOffset = Math.max(0, root.weekOffset - 1)
                        }
                      }
                    }

                    Text {
                      id: weekTotalLabel
                      text: root.weekTotalAsPct
                        ? Math.round(root.visibleWeekTotalMs / (7 * 24 * 3600000) * 100) + "%"
                        : Model.fmt(root.visibleWeekTotalMs)
                      color: root.contentForeground
                      opacity: weekTotalMouse.containsMouse ? 1.0 : 0.6
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter

                      MouseArea {
                        id: weekTotalMouse
                        anchors.fill: parent
                        anchors.margins: -Style.space(4)
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.weekTotalAsPct = !root.weekTotalAsPct
                      }

                      PanelToolTip {
                        visible: weekTotalMouse.containsMouse
                        tipText: root.weekTotalAsPct
                          ? "% of the week's 168 hours"
                          : "logged of 168 possible hours"
                      }
                    }
                  }

                  // 7 day bars for the visible week.
                  Row {
                    width: parent.width
                    spacing: 0
                    topPadding: Style.space(8)

                      Repeater {
                        model: root.visibleWeek ? root.visibleWeek.days : []

                        Item {
                          required property var modelData
                          required property int index

                          width: (parent.width - parent.spacing * 6) / 7
                          height: Style.space(80)

                          property bool isActive: modelData.key === root.activeDayKey
                          property bool isFuture: modelData.isFuture
                          property bool isEmpty: !isFuture && modelData.ms <= 0
                          property bool hasData: !isFuture && !isEmpty && root.visibleWeekMax > 0
                          property real barPx: hasData
                            ? Math.max(3, Style.space(64) * Number(modelData.ms) / root.visibleWeekMax)
                            : 3

                          Rectangle {
                            width: parent.width * 0.5
                            radius: Style.space(2)
                            color: (parent.isFuture || parent.isEmpty)
                              ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
                              : (parent.isActive
                                  ? Color.accent
                                  : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.28))
                            opacity: parent.hasData && barMouse.containsMouse && !parent.isActive ? 0.5 : 1.0
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Style.space(14)
                            height: parent.barPx

                            MouseArea {
                              id: barMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              enabled: !parent.parent.isFuture && !parent.parent.isEmpty
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.selectDay(modelData.key)
                            }
                          }

                          Text {
                            text: modelData.label
                            color: root.contentForeground
                            opacity: (parent.isActive || (!parent.isFuture && modelData.ms > 0)) ? 1.0 : 0.3
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: parent.isActive
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            anchors.bottom: parent.bottom
                          }
                        }
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
                  height: implicitHeight
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
                    anchors.leftMargin: Style.space(2)
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
      if (!root.controller.open) {
        root.selectedKey = ""
        root.openCalendar(false)
        root.weekOffset = 0
        root.clearHover()
      }
    }
  }
}
