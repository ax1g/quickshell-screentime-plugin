import QtQuick
import qs.Commons
import qs.Ui
import "../js/Model.js" as Model

import "components"

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
    readonly property var weekView: serviceReady ?
    // Clamped like the pager buttons (0–12): a stray offset must show an
    // empty week, never diverge from the navigation.
    Model.weekView(root.days, root.todayKey, 13, Math.max(0, Math.min(root.weekOffset, 12))) : null
    // Sunday of the visible week: anchors "Busiest day (7d)" to the week the
    // user is looking at instead of always the current week.
    readonly property string insightWeekEndKey: root.weekView ? root.weekView.weekEndKey : ""
    readonly property var insightRows: serviceReady ? Model.insights(root.activeDay, root.days, root.todayKey, root.activeDayKey, root.insightWeekEndKey) : []
    readonly property var scrollableWeeks: root.weekView ? root.weekView.weeks : []
    readonly property double scrollableMax: Model.scrollableTrendMax(root.scrollableWeeks)
    readonly property var visibleWeek: root.weekView ? root.weekView.week : null
    readonly property double visibleWeekMax: root.weekView ? root.weekView.max : 0
    // Y-axis for the week bar graph: baseline, midpoint and peak gridlines,
    // derived from the same maximum the bars scale against so a bar's top
    // always lands on the gridline its duration describes.
    readonly property var axisTicks: Model.weekAxisTicks(root.visibleWeekMax)
    readonly property double axisMaxMs: root.axisTicks.length ? root.axisTicks[root.axisTicks.length - 1] : 0
    // Sum of the visible week's days, shown under the paginated bar graph.
    readonly property double visibleWeekTotalMs: root.weekView ? root.weekView.totalMs : 0
    // True while the current week beats every older week in the window:
    // drives the gold record-week trophy beside the week total.
    readonly property bool recordWeek: root.weekOffset === 0 && serviceReady ? (root.weekView ? root.weekView.isRecord : false) : false
    property bool expanded: false
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
    readonly property var monthNamesShort: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    readonly property var monthNamesLong: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    // Donut always shows the grouped view; the legend expands inline.
    readonly property var segments: Model.arcSegments(root.groupedApps)
    readonly property var sliceColors: Model.sliceColors(root.groupedApps.length, Color.accent)
    readonly property int groupedCount: root.groupedApps.length
    // The "Other" slice color: last in the grouped palette.
    readonly property color otherColor: root.groupedCount > 0 ? (root.sliceColors[root.groupedCount - 1] || Color.accent) : Color.accent

    // Donut diameter; also sizes the donut+legend row.
    readonly property real ringSize: Style.space(116)

    // Legend scroll cap: fits the 6-row grouped list fully; when expanded
    // the full app list scrolls inside this height with a ▾ indicator.
    readonly property real legendMaxHeight: Style.space(140)

    // Guarded so the widget renders before the bar is injected.
    readonly property color contentForeground: bar ? bar.foreground : Color.foreground
    readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

    function open() {
        root.controller.show();
    }

    function close() {
        root.controller.hide();
    }

    function toggle() {
        if (root.opened)
            root.close();
        else
            root.open();
    }

    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.barIdentity, direction);
        return false;
    }

    function scrollBy(dy) {
        var flick = panelScroll;
        if (!flick || flick.contentHeight <= flick.height)
            return;
        flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy));
    }

    function toggleExpanded() {
        // Freeze the collapsed card height before growing, so the yearly
        // overview drawer can keep show-less dimensions while expanded.
        if (!root.expanded)
            keyCatcher.collapsedCardH = keyCatcher.height;
        root.expanded = !root.expanded;
    }

    function selectDay(key) {
        if (!key)
            return;
        if (key === root.todayKey || root.selectedKey === key)
            root.selectedKey = "";
        else
            root.selectedKey = key;
    }

    // Open/close the yearly overview. Arms the drawer slide so the move
    // animates; layout-driven repositions stay instant (see calendarDrawer).
    // Opening the yearly view also grows the card to full height so the
    // yearly graph never renders squeezed inside the show-less height.
    function openCalendar(open) {
        calendarDrawer.sliding = true;
        if (open && !root.expanded) {
            keyCatcher.collapsedCardH = keyCatcher.height;
            root.expanded = true;
        }
        root.calendarOpen = open;
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
            onMoveRequested: function (dx, dy) {
                if (dy !== 0)
                    root.scrollBy(-dy * Style.space(24));
            }
            onCloseRequested: root.close()
            onTabRequested: function (direction) {
                root.switchPanel(direction);
            }
            onTextKey: function (t) {
                if (t === "p" || t === "P")
                    root.toggleExpanded();
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
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                // Disarm once the drawer reaches its resting position so later
                // layout-driven moves don't replay the slide.
                onXChanged: {
                    if (root.calendarOpen ? x >= 0 : x <= -keyCatcher.drawerWidth)
                        sliding = false;
                }

                YearDrawer {
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  panelBackground: root.bar ? root.bar.background : Color.background
                  accent: Color.accent
                  serviceReady: root.serviceReady
                  days: root.days
                  months: root.months
                  years: root.years
                  todayKey: root.todayKey
                  currentYear: root.currentYear
                  currentYearOffset: root.currentYearOffset
                  oldestDataYear: root.oldestDataYear
                  calendarYearTotal: root.calendarYearTotal
                  yearFacts: root.yearFacts
                  monthNamesShort: root.monthNamesShort
                  monthNamesLong: root.monthNamesLong
                  onCloseRequested: root.openCalendar(false)
                  onPrevYearRequested: root.currentYearOffset += 1
                  onNextYearRequested: root.currentYearOffset -= 1
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

                    HeroHeader {
                        foreground: root.contentForeground
                        fontFamily: root.contentFontFamily
                        serviceReady: root.serviceReady
                        expanded: root.expanded
                        calendarOpen: root.calendarOpen
                        dayTotal: root.dayTotal
                        activeDayKey: root.activeDayKey
                        activeDayLabel: root.activeDayLabel
                        onExpandToggled: root.toggleExpanded()
                        onCalendarToggled: root.openCalendar(!root.calendarOpen)
                    }

                    // ---- Per-app donut + legend ------------------------------------
                    Item {
                      width: parent.width
                      height: Math.max(root.ringSize, root.legendMaxHeight)

                      DonutChart {
                        id: donutChart
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        segments: root.segments
                        sliceColors: root.sliceColors
                        ringSize: root.ringSize
                        activeDayLabel: root.activeDayLabel
                        dayTotal: root.dayTotal
                        foreground: root.contentForeground
                        fontFamily: root.contentFontFamily
                        accent: Color.accent
                      }

                      AppLegend {
                        anchors.left: donutChart.right
                        anchors.leftMargin: Style.space(16)
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: root.legendMaxHeight
                        rows: root.expanded ? root.fullApps : root.groupedApps
                        expanded: root.expanded
                        groupedCount: root.groupedCount
                        sliceColors: root.sliceColors
                        otherColor: root.otherColor
                        foreground: root.contentForeground
                        fontFamily: root.contentFontFamily
                        accent: Color.accent
                        maxHeight: root.legendMaxHeight
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

                            // Paginated Mon-Sun week bar graph; weekOffset 0 = current week.
                            WeekTrend {
                              foreground: root.contentForeground
                              fontFamily: root.contentFontFamily
                              tipBackground: root.bar ? root.bar.background : Color.background
                              accent: Color.accent
                              weekOffset: root.weekOffset
                              hasPrevWeekData: root.hasPrevWeekData
                              visibleWeek: root.visibleWeek
                              recordWeek: root.recordWeek
                              weekTotalAsPct: root.weekTotalAsPct
                              visibleWeekTotalMs: root.visibleWeekTotalMs
                              axisTicks: root.axisTicks
                              axisMaxMs: root.axisMaxMs
                              activeDayKey: root.activeDayKey
                              onPrevWeekRequested: root.weekOffset = Math.min(12, root.weekOffset + 1)
                              onNextWeekRequested: root.weekOffset = Math.max(0, root.weekOffset - 1)
                              onWeekTotalToggled: root.weekTotalAsPct = !root.weekTotalAsPct
                              onDaySelected: function(key) { root.selectDay(key) }
                            }

                            PanelSeparator {
                                width: parent.width
                                foreground: root.contentForeground
                                strength: 0.12
                            }

                            InsightList {
                                rows: root.insightRows
                                foreground: root.contentForeground
                                fontFamily: root.contentFontFamily
                                accent: Color.accent
                                urgent: Color.urgent
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
                root.selectedKey = "";
                root.openCalendar(false);
                root.weekOffset = 0;
                root.currentYearOffset = 0;
                root.weekTotalAsPct = false;
                donutChart.clearHover();
            }
        }
    }
}
