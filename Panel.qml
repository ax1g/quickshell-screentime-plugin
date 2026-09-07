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
  readonly property var years: service ? service.years : {}
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
  // One derivation for the paginated week trend: the week list plus every
  // fact the panel used to thread separately (visible week, its max and
  // total, the record flag, older-week data, the Sunday key anchoring
  // "Busiest day (7d)" to the week on screen).
  readonly property var weekView: serviceReady
    // Clamped like the pager buttons (0–12): a stray offset must show an
    // empty week, never diverge from the navigation.
    ? Model.weekView(root.days, root.todayKey, 13, Math.max(0, Math.min(root.weekOffset, 12))) : null
  // Sunday of the visible week: anchors "Busiest day (7d)" to the week the
  // user is looking at instead of always the current week.
  readonly property string insightWeekEndKey: root.weekView ? root.weekView.weekEndKey : ""
  readonly property var insightRows: serviceReady
    ? Model.insights(root.activeDay, root.days, root.todayKey, root.activeDayKey, root.insightWeekEndKey) : []
  readonly property var scrollableWeeks: root.weekView ? root.weekView.weeks : []
  readonly property double scrollableMax: Model.scrollableTrendMax(root.scrollableWeeks)
  readonly property var visibleWeek: root.weekView ? root.weekView.week : null
  readonly property double visibleWeekMax: root.weekView ? root.weekView.max : 0
  // Y-axis for the week bar graph: baseline, midpoint and peak gridlines,
  // derived from the same maximum the bars scale against so a bar's top
  // always lands on the gridline its duration describes.
  readonly property var axisTicks: Model.weekAxisTicks(root.visibleWeekMax)
  readonly property double axisMaxMs: root.axisTicks.length
    ? root.axisTicks[root.axisTicks.length - 1] : 0
  // Sum of the visible week's days, shown under the paginated bar graph.
  readonly property double visibleWeekTotalMs: root.weekView ? root.weekView.totalMs : 0
  // True while the current week beats every older week in the window:
  // drives the gold record-week trophy beside the week total.
  readonly property bool recordWeek: root.weekOffset === 0 && serviceReady
    ? (root.weekView ? root.weekView.isRecord : false) : false
  property bool expanded: false
  // Expanding swaps the legend model: restart at the top instead of
  // opening scrolled mid-list.
  onExpandedChanged: legendScroll.contentY = 0
  property bool calendarOpen: false
  property int weekOffset: 0
  // Whether any week before the currently visible one has data.
  readonly property bool hasPrevWeekData: root.weekView ? root.weekView.hasPrev : false
  // Header total toggles between absolute time and share of the full week.
  property bool weekTotalAsPct: false

  // Calendar view: yearly overview with navigation. currentYearOffset counts
  // how many years back from today we are viewing; 0 = current year.
  readonly property int todayYear: serviceReady ? (Number(root.todayKey.split("-")[0]) || new Date().getFullYear()) : new Date().getFullYear()
  property int currentYearOffset: 0
  readonly property int currentYear: root.todayYear - root.currentYearOffset
  readonly property int oldestDataYear: serviceReady ? Model.firstDataYear(root.days, root.months, root.years) : root.todayYear
  // One derivation for the year view: the header total and the retro cards
  // share a single merge instead of paying for two.
  readonly property var yearView: serviceReady ? Model.yearView(root.days, root.months, root.years, root.currentYear, root.todayKey, Color.accent) : null
  readonly property string calendarYearTotal: root.yearView ? root.yearView.totalLabel : "0h"
  readonly property var yearFacts: root.yearView ? root.yearView.facts : []
  readonly property var monthNamesShort: ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
  readonly property var monthNamesLong: ["January","February","March","April","May","June","July","August","September","October","November","December"]

  // Shared panel-styled tooltip: matches the drawer's background, foreground
  // and font so popups read as part of the shell rather than platform chrome.
  // Tooltip with a dwell delay: sweeping across adjacent bars restarts the
  // timer on every enter, so the tip only appears after hovering one target
  // for 300ms instead of flashing along the sweep.
  component PanelToolTip: ToolTip {
    id: panelTip
    property string tipText: ""
    property bool hovered: false
    padding: 0
    visible: false
    Timer {
      id: showTimer
      interval: 300
      repeat: false
      running: panelTip.hovered
      onTriggered: panelTip.visible = true
    }
    onHoveredChanged: if (!hovered) panelTip.visible = false
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

  // Yearly fact card: glyph, label, value, and a supporting line. Heights
  // derive from its own content so cards never stretch to match a neighbour.
  component InsightCard: Rectangle {
    id: insightCard
    required property var modelData

    readonly property string glyph: String(modelData.glyph || "")
    readonly property string label: String(modelData.label || "")
    readonly property string stat: String(modelData.value || "")
    readonly property string oneLiner: String(modelData.sub || "")
    readonly property string accent: String(modelData.color || Color.accent)

    width: parent.width
    implicitHeight: cardColumn.implicitHeight + Style.space(20)
    height: implicitHeight
    radius: Style.space(6)
    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
    border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
    border.width: 1

    Column {
      id: cardColumn
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.top: parent.top
      anchors.topMargin: Style.space(10)
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(4)

        Text {
          text: insightCard.glyph
          color: insightCard.accent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.icon
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          text: insightCard.label
          color: root.contentForeground
          opacity: 0.6
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          wrapMode: Text.Wrap
          width: parent.width - Style.space(18)
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Text {
        text: insightCard.stat
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        width: parent.width
        wrapMode: Text.Wrap
      }

      Text {
        text: insightCard.oneLiner
        color: root.contentForeground
        opacity: 0.5
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        width: parent.width
        wrapMode: Text.Wrap
      }
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
  // Insight rendering reads row meaning (kind/dir from Model.insights),
  // never label text: renaming a label can't silently recolor anything.
  function insightIcon(kind, dir) {
    if (kind === "top") return "\u2605"
    if (kind === "delta") return root.deltaArrow(dir)
    if (kind === "busiest") return "\u2606"
    return ""
  }

  // Glyph colours follow the theme via Model.insightColors: star = accent,
  // delta direction = urgent / theme-derived green, busiest = accent sibling.
  // Re-evaluates on theme swaps through the Color bindings.
  readonly property var insightPalette: Model.insightColors(Color.accent, Color.urgent)
  function insightIconColor(kind, dir) {
    if (kind === "top") return root.insightPalette.star
    if (kind === "delta") {
      if (dir === "up") return root.insightPalette.up
      if (dir === "down") return root.insightPalette.down
      return Qt.darker(root.contentForeground, 1.5)
    }
    if (kind === "busiest") return root.insightPalette.busiest
    return root.contentForeground
  }

  // Right-hand value colour: only the signed delta carries a colour (its
  // direction), everything else stays neutral — logic over rainbow.
  function insightValueColor(kind, dir) {
    if (kind === "delta" && (dir === "up" || dir === "down"))
      return root.insightIconColor(kind, dir)
    return root.contentForeground
  }

  function deltaArrow(dir) {
    if (dir === "up") return "\u2197"
    if (dir === "down") return "\u2198"
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
  // Opening the yearly view also grows the card to full height so the
  // yearly graph never renders squeezed inside the show-less height.
  function openCalendar(open) {
    calendarDrawer.sliding = true
    if (open && !root.expanded) {
      keyCatcher.collapsedCardH = keyCatcher.height
      root.expanded = true
    }
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
        height: keyCatcher.height
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

        // Fixed hero header (consistent with the main panel's hero). It
        // stays put while the year overview below scrolls.
        Item {
          id: yearHeader
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: implicitHeight
          // Children anchor to the top, so the extra implicitHeight becomes
          // breathing room below the hero before the scroll view begins.
          implicitHeight: Math.max(yearHeroIcon.implicitHeight, yearHeroLabels.implicitHeight, backCorner.implicitHeight) + Style.space(3)

          // Left: large yearly icon (mirrors the main hero's hourglass).
          // Clicking it returns to the main panel.
          Text {
            id: yearHeroIcon
            text: "\uf073"
            color: yearHeroIconMouse.containsMouse
              ? root.contentForeground : Qt.darker(root.contentForeground, 1.2)
            font.family: root.contentFontFamily
            font.pixelSize: Style.fontPx(2.4)
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: -Style.space(4)

            MouseArea {
              id: yearHeroIconMouse
              anchors.fill: parent
              anchors.margins: -Style.space(6)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openCalendar(false)
            }
          }

          // Label stack: big bold year-total + year nav caption
          // (mirrors the main hero's value + caption).
          Column {
            id: yearHeroLabels
            anchors.left: yearHeroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.rightMargin: backCorner.implicitWidth + Style.space(12)
            anchors.top: parent.top
            spacing: 0

            Text {
              text: root.calendarYearTotal
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.fontPx(1.5)
              font.bold: true
              font.letterSpacing: 1.4
              elide: Text.ElideRight
              width: parent.width
            }

            Row {
              width: parent.width
              spacing: Style.space(10)

              Text {
                id: yearPrevGlyph
                text: "\uf053"
                color: yearPrevMouse.enabled && yearPrevMouse.containsMouse
                  ? root.contentForeground : Qt.darker(root.contentForeground, 1.4)
                opacity: yearPrevMouse.enabled ? 1.0 : 0.25
                Behavior on opacity { NumberAnimation { duration: 150 } }
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
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
                id: yearValue
                text: String(root.currentYear)
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: yearNextGlyph
                text: "\uf054"
                color: yearNextMouse.enabled && yearNextMouse.containsMouse
                  ? root.contentForeground : Qt.darker(root.contentForeground, 1.4)
                opacity: yearNextMouse.enabled ? 1.0 : 0.25
                Behavior on opacity { NumberAnimation { duration: 150 } }
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
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
          }

          // Corner action: BACK (mirrors the main hero's SHOW MORE/LESS).
          Item {
            id: backCorner
            anchors.right: parent.right
            anchors.top: parent.top
            width: backRow.implicitWidth
            height: backRow.implicitHeight

            Row {
              id: backRow
              anchors.fill: parent
              spacing: Style.space(4)

              Text {
                text: "\u25c2"
                color: backCornerMouse.containsMouse
                  ? root.contentForeground : Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: "BACK"
                color: backCornerMouse.containsMouse
                  ? root.contentForeground : Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              id: backCornerMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openCalendar(false)
            }
          }
        }

        Flickable {
          id: calendarScroll
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.top: yearHeader.bottom
          contentWidth: width
          contentHeight: calendarColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          Column {
            id: calendarColumn
            width: calendarScroll.width
            spacing: Style.space(10)

            // Year overview: one bar per month, length = share of the
            // busiest month. Hover a bar for its exact total.
            Column {
              id: heatGrid
              width: parent.width
              spacing: Style.space(6)
              topPadding: Style.space(10)
              bottomPadding: Style.space(2)

              readonly property var months: root.serviceReady
                ? Model.monthlyTotals(root.days, root.months, root.currentYear, root.years, root.todayKey) : []
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
                text: "8888h"
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              Repeater {
                model: 12

                Item {
                  id: monthRow
                  required property int index

                  width: heatGrid.width
                  height: Style.space(12)

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

                  // Faint full-width track behind months with data; empty
                  // months show no background, just the label and 0h.
                  Rectangle {
                    visible: monthRow.ratio > 0
                    x: heatGrid.labelW + heatGrid.labelGap
                    width: monthRow.availW
                    height: parent.height
                    radius: Style.space(2)
color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.07)
                  }

                  Rectangle {
                    id: monthBar
                    x: heatGrid.labelW + heatGrid.labelGap
                    width: Math.max(0, monthRow.availW * monthRow.ratio)
                    height: parent.height
                    radius: Style.space(2)
                    color: monthRow.isCurrentMonth
                      ? Color.accent
                      : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.8)

                    MouseArea {
                      id: monthBarMouse
                      anchors.fill: parent
                      anchors.margins: -Style.space(4)
                      hoverEnabled: true
                    }

                    PanelToolTip {
                      hovered: monthBarMouse.containsMouse
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

              Item {
                width: parent.width
                height: Style.space(10) + 1 + Style.space(4)
                visible: root.yearFacts.length > 0
                PanelSeparator {
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(10)
                  foreground: root.contentForeground
                }
              }

              Text {
                text: "Insights " + root.currentYear
                visible: root.yearFacts.length > 0
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                width: parent.width
                topPadding: Style.space(4)
                bottomPadding: Style.space(6)
              }

              Item {
                id: yearlyInsightsGrid
                width: parent.width
                height: cardsRow.height
                visible: root.yearFacts.length > 0

                property var leftCards: []
                property var rightCards: []

                Component {
                  id: cardsDelegate
                  InsightCard {}
                }

                // Masonry split: cards keep their own height, so the two
                // columns drift independently instead of flexing to match.
                function splitCards() {
                  var cards = root.yearFacts
                  var left = []
                  var right = []
                  var leftScore = 0
                  var rightScore = 0
                  for (var i = 0; i < cards.length; i++) {
                    var score = cardScore(cards[i])
                    if (leftScore <= rightScore) {
                      left.push(cards[i])
                      leftScore += score
                    } else {
                      right.push(cards[i])
                      rightScore += score
                    }
                  }
                  leftCards = left
                  rightCards = right
                }

                function cardScore(card) {
                  return estimateLines(String(card.value || ""))
                    + estimateLines(String(card.sub || ""))
                }

                function estimateLines(text) {
                  var cardW = width > 0 ? (width - Style.space(8)) / 2 : 320
                  var innerW = Math.max(1, cardW - Style.space(20))
                  var charsPerLine = Math.max(4, Math.floor(innerW / (Style.font.bodySmall * 0.55)))
                  return Math.max(1, Math.ceil(text.length / charsPerLine))
                }

                onWidthChanged: splitCards()

                Connections {
                  target: root
                  function onYearFactsChanged() { yearlyInsightsGrid.splitCards() }
                }

                Component.onCompleted: splitCards()

                Row {
                  id: cardsRow
                  spacing: Style.space(8)
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top

                  Column {
                    id: leftColumn
                    width: (parent.width - Style.space(8)) / 2
                    spacing: Style.space(8)

                    Repeater {
                      model: yearlyInsightsGrid.leftCards
                      delegate: cardsDelegate
                    }
                  }

                  Column {
                    id: rightColumn
                    width: (parent.width - Style.space(8)) / 2
                    spacing: Style.space(8)

                    Repeater {
                      model: yearlyInsightsGrid.rightCards
                      delegate: cardsDelegate
                    }
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
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.fontPx(2.8)
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.top: parent.top
              anchors.topMargin: -Style.space(4)

              MouseArea {
                id: heroIconMouse
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openCalendar(!root.calendarOpen)
                onContainsMouseChanged: if (containsMouse) sparkles.launch(heroIconMouse.mouseX, heroIconMouse.mouseY)
              }
            }

            // Hover sparkles: tiny stars burst around the cursor over the
            // hourglass, drift upward and fade out. Positions and sizes are
            // re-randomised on every hover-enter.
            Item {
              id: sparkles
              anchors.centerIn: heroIcon
              width: heroIcon.width + Style.space(16)
              height: heroIcon.height + Style.space(10)
              z: 5

              property bool go: false

              function launch(mx, my) {
                var p = mapFromItem(heroIconMouse, mx, my)
                go = false
                for (var i = 0; i < sparkleRepeater.count; i++)
                  sparkleRepeater.itemAt(i).respawn(p.x, p.y)
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
                  scale: 1

                  property real drift: Style.space(8)

                  function respawn(cx, cy) {
                    var spreadX = sparkles.width * 0.22
                    var spreadY = sparkles.height * 0.3
                    x = Math.max(2, Math.min(sparkles.width - 2, cx + (Math.random() * 2 - 1) * spreadX))
                    y = Math.max(sparkles.height * 0.2, Math.min(sparkles.height * 0.85, cy + (Math.random() * 2 - 1) * spreadY))
                    font.pixelSize = Style.font.caption * (0.65 + Math.random() * 0.85)
                    drift = Style.space(6) + Style.space(10) * Math.random()
                  }

                  SequentialAnimation {
                    running: sparkles.go
                    PauseAnimation { duration: sp.index * 80 }
                    NumberAnimation { target: sp; property: "opacity"; from: 0; to: 0.85; duration: 180 }
                    ParallelAnimation {
                    NumberAnimation { target: sp; property: "y"; from: sp.y; to: sp.y - sp.drift; duration: 650; easing.type: Easing.OutQuad }
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
              spacing: 0

              Text {
                text: root.dayTotal > 0 ? Model.fmt(root.dayTotal) : "0m"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.fontPx(1.5)
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: root.activeDayKey ? root.activeDayLabel + ", " + String(root.activeDayKey).split("-")[0] : ""
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
                onWidthChanged: donutCanvas.requestPaint()

                Connections {
                  target: root
                  function onSegmentsChanged() { donutCanvas.requestPaint() }
                  function onSliceColorsChanged() { donutCanvas.requestPaint() }
                  function onHoverSliceChanged() { donutCanvas.requestPaint() }
                  function onContentForegroundChanged() { donutCanvas.requestPaint() }
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
                cursorShape: Qt.ArrowCursor
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
              width: 2
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
                strength: 0.12
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
                  spacing: Style.space(8)

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
                          enabled: root.weekOffset < 12 && root.hasPrevWeekData
                          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                          onClicked: root.weekOffset = Math.min(12, root.weekOffset + 1)
                        }
                      }

                      Text {
                        text: root.visibleWeek ? Model.weekRangeLabel(root.visibleWeek) : ""
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        elide: Text.ElideRight
                        // Cap at the header width minus arrows and the week
                        // total so cross-year labels elide instead of
                        // overlapping it.
                        width: Math.max(40, Math.min(implicitWidth,
                          weekNavColumn.width - weekTotalLabel.implicitWidth - Style.space(76)))
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

                    // Record-week trophy: gold glyph beside the total while
                    // the current week beats every older week on record.
                    Text {
                      visible: root.recordWeek
                      text: "\uF091"
                      color: "#FFD700"
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      anchors.right: weekTotalLabel.left
                      anchors.rightMargin: Style.space(4)
                      anchors.verticalCenter: parent.verticalCenter

                      MouseArea {
                        id: recordTrophyMouse
                        anchors.fill: parent
                        anchors.margins: -Style.space(4)
                        hoverEnabled: true
                        cursorShape: Qt.ArrowCursor
                      }

                      PanelToolTip {
                        hovered: recordTrophyMouse.containsMouse
                        tipText: "Busiest week on record — new high!"
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
                      anchors.rightMargin: Style.space(2)
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
                        hovered: weekTotalMouse.containsMouse
                        tipText: root.weekTotalAsPct
                          ? "% of the week's 168 hours"
                          : "logged of 168 possible hours"
                      }
                    }
                  }

                  // 7 day bars for the visible week with a y-axis scale
                  // reference (gridlines plus whole-hour tick labels) that
                  // the bars scale against. No plate: the chart sits on the
                  // drawer background like every other widget.
                  Item {
                    width: parent.width
                    // 80px chart plus a 12px top pad (headroom for the top
                    // gridline's label) and an 8px bottom pad so the bars
                    // clear the edge instead of hugging it.
                    height: Style.space(80) + Style.space(20)
                    clip: true

                    // Chart content, nudged down to leave headroom for the
                    // top gridline's whole-hour label.
                    Item {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.topMargin: Style.space(12)
                      height: Style.space(80)

                    // Horizontal gridlines and right-hand labels at each tick.
                    Repeater {
                      model: root.axisTicks

                      Item {
                        required property double modelData
                        width: parent.width
                        height: 1
                        z: 1
                        y: root.axisMaxMs > 0
                          ? (parent.height - Style.space(14) - Style.space(64) * Number(modelData) / root.axisMaxMs)
                          : parent.height

                        // Continuous gridline over the bar area only, kept
                        // clear of the right-hand y-axis label column so the
                        // lines never cross the labels.
                        Rectangle {
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.rightMargin: Style.space(26)
                          height: 1
                          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
                        }

                        Text {
                          text: Model.fmtWholeHours(modelData)
                          color: Qt.darker(root.contentForeground, 1.35)
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: false
                          width: Style.space(20)
                          anchors.right: parent.right
                          anchors.rightMargin: Style.space(2)
                          anchors.verticalCenter: parent.verticalCenter
                          horizontalAlignment: Text.AlignRight
                        }
                      }
                    }

                    // 7 day bars for the visible week, ending just before the
                    // right-hand y-axis labels.
                    Row {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(26)
                      anchors.verticalCenter: parent.verticalCenter
                      z: 2
                      spacing: 0

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
                          property bool hasData: !isFuture && !isEmpty && root.axisMaxMs > 0
                          property real barPx: hasData
                            ? Math.max(3, Style.space(64) * Number(modelData.ms) / root.axisMaxMs)
                            : 0

                          Rectangle {
                            width: parent.width * 0.5
                            radius: Style.space(2)
                            color: (parent.isFuture || parent.isEmpty)
                              ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.10)
                              : (parent.isActive
                                  ? Color.accent
                                  : (barMouse.containsMouse
                                      ? Qt.lighter(root.contentForeground, 1.4)
                                      : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.9)))
                            opacity: 1.0
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
                            opacity: (parent.isActive || (!parent.isFuture && modelData.ms > 0)) ? 1.0 : 0.45
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
                }
              }

              PanelSeparator {
                width: parent.width
                foreground: root.contentForeground
                strength: 0.12
              }

              Repeater {
                model: root.insightRows

                Item {
                  required property var modelData

                  readonly property string label: String(modelData.label || "")
                  readonly property string value: String(modelData.value || "")
                  readonly property string kind: String(modelData.kind || "")
                  readonly property string dir: String(modelData.dir || "")

                  width: parent.width
                  height: implicitHeight
                  implicitHeight: Math.max(iconText.implicitHeight, Math.max(labelText.implicitHeight, valueText.implicitHeight))

                  Text {
                    id: iconText
                    text: root.insightIcon(kind, dir || null)
                    color: root.insightIconColor(kind, dir || null)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall + 3
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
                    anchors.leftMargin: Style.space(5)
                    anchors.right: valueText.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                  }

                  Text {
                    id: valueText
                    text: value
                    color: root.insightValueColor(kind, dir || null)
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
        root.currentYearOffset = 0
        root.weekTotalAsPct = false
        root.clearHover()
      }
    }
  }
}
