import QtQuick
import qs.Commons
import qs.Ui
import "../js/Model.js" as Model

import "components"

// Popup for the bar widget: day total, per-app breakdown, insights.
// Read-only mirror of the Service's live state.
Panel {
    id: root
    moduleName: "agx.screen-time"

    property var anchorItem: null
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root

    // Panel switching identifies us by the bar widget, not the panel.
    readonly property var service: bar && bar.shell ? bar.shell.serviceFor("agx.screen-time") : null
    readonly property bool serviceReady: service && service.ready === true
    readonly property var today: service ? service.today : null
    readonly property var days: service ? service.days : {}
    readonly property var months: service ? service.months : {}
    readonly property var years: service ? service.years : {}
    readonly property string todayKey: serviceReady ? service.todayKey : ""

    // Empty selection = live today; everything derives from activeDay.
    property string selectedKey: ""
    readonly property var activeDay: serviceReady ? Model.dayFor(root.days, root.today, root.selectedKey, root.todayKey) : null
    readonly property string activeDayKey: root.selectedKey || root.todayKey
    readonly property string activeDayLabel: serviceReady ? Model.formatDate(root.activeDayKey) : ""
    readonly property double dayTotal: root.activeDay ? (root.activeDay.total || 0) : 0

    // Gated on service.ready: unloaded history would label NaN-NaN-NaN.
    readonly property var groupedApps: serviceReady ? Model.groupedApps(Model.appList(root.activeDay), Model.DONUT_MAX_SLICES, Model.DONUT_MIN_PCT) : []
    readonly property var fullApps: serviceReady ? Model.appList(root.activeDay) : []
    // Single derivation for the paginated week trend; offset clamps 0-12.
    readonly property var weekView: serviceReady ?
    Model.weekView(root.days, root.todayKey, 13, Math.max(0, Math.min(root.weekOffset, 12))) : null
    // Its Sunday anchors "Busiest day (7d)" to the visible week.
    readonly property string insightWeekEndKey: root.weekView ? root.weekView.weekEndKey : ""
    readonly property var insightRows: serviceReady ? Model.insights(root.activeDay, root.days, root.todayKey, root.activeDayKey, root.insightWeekEndKey) : []
    readonly property var scrollableWeeks: root.weekView ? root.weekView.weeks : []
    readonly property double scrollableMax: Model.scrollableTrendMax(root.scrollableWeeks)
    readonly property var visibleWeek: root.weekView ? root.weekView.week : null
    readonly property double visibleWeekMax: root.weekView ? root.weekView.max : 0
    // Ticks share the bars' scale so bar tops land on gridlines.
    readonly property var axisTicks: Model.weekAxisTicks(root.visibleWeekMax)
    readonly property double axisMaxMs: root.axisTicks.length ? root.axisTicks[root.axisTicks.length - 1] : 0
    readonly property double visibleWeekTotalMs: root.weekView ? root.weekView.totalMs : 0
    // Current week beating all older weeks earns the record trophy.
    readonly property bool recordWeek: root.weekOffset === 0 && serviceReady ? (root.weekView ? root.weekView.isRecord : false) : false
    property bool expanded: false
    property bool calendarOpen: false
    property int weekOffset: 0
    // True while an older week holds data (enables the prev pager).
    readonly property bool hasPrevWeekData: root.weekView ? root.weekView.hasPrev : false
    // Header total flips between absolute time and week-share.
    property bool weekTotalAsPct: false

    // currentYearOffset: years back from today; 0 = this year.
    readonly property int todayYear: serviceReady ? (Number(root.todayKey.split("-")[0]) || new Date().getFullYear()) : new Date().getFullYear()
    property int currentYearOffset: 0
    readonly property int currentYear: root.todayYear - root.currentYearOffset
    readonly property int oldestDataYear: serviceReady ? Model.firstDataYear(root.days, root.months, root.years) : root.todayYear
    // Header total and retro cards share one year merge.
    readonly property var yearView: serviceReady ? Model.yearView(root.days, root.months, root.years, root.currentYear, root.todayKey, Color.accent) : null
    readonly property string calendarYearTotal: root.yearView ? root.yearView.totalLabel : "0h"
    readonly property var yearFacts: root.yearView ? root.yearView.facts : []
    readonly property var monthNamesShort: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    readonly property var monthNamesLong: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    // Donut shows the grouped view; the legend expands inline.
    readonly property var segments: Model.arcSegments(root.groupedApps)
    readonly property var sliceColors: Model.sliceColors(root.groupedApps.length, Color.accent)
    readonly property int groupedCount: root.groupedApps.length
    readonly property color otherColor: root.groupedCount > 0 ? (root.sliceColors[root.groupedCount - 1] || Color.accent) : Color.accent

    // Donut diameter; also sizes the donut+legend row.
    readonly property real ringSize: Style.space(116)

    // 6-row grouped list fits; the expanded list scrolls inside.
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
        // Snapshot show-less height so the drawer keeps it while expanded.
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

    // Slide animates on toggle only; layout moves snap. Opens expanded.
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

            // Full-card overlay; coordinates are card-relative, not panel-wide.
            readonly property real drawerWidth: width

            // Show-less height, captured before expanding.
            property real collapsedCardH: 0

            Item {
                id: calendarDrawer
                width: keyCatcher.drawerWidth
                height: keyCatcher.height
                anchors.top: parent.top
                x: root.calendarOpen ? 0 : -keyCatcher.drawerWidth
                z: 10
                visible: x > -keyCatcher.drawerWidth

                // Layout-driven x must snap, or the drawer flashes across.
                property bool sliding: false

                Behavior on x {
                    enabled: calendarDrawer.sliding
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                // Disarm at rest so resizes don't replay the slide.
                onXChanged: {
                    if (root.calendarOpen ? x >= 0 : x <= -keyCatcher.drawerWidth)
                        sliding = false;
                }

                YearDrawer {
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    panelBackground: root.bar ? root.bar.background : Color.background
                    accent: Color.accent
                    currentYear: root.currentYear
                    currentYearOffset: root.currentYearOffset
                    oldestDataYear: root.oldestDataYear
                    calendarYearTotal: root.calendarYearTotal
                    yearFacts: root.yearFacts
                    yearMonths: root.yearMonths
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
                                onDaySelected: function (key) {
                                    root.selectDay(key);
                                }
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

    // Reset to live today on dismiss.
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
