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

    // Config-menu prefs (BarWidget settings, pushed via injectPanel).
    // Missing keys behave as today, so old installs need no migration.
    // The `in` probe keeps this safe if the shell ever withholds settings.
    readonly property var prefs: ("settings" in root) && root.settings ? root.settings : ({})
    readonly property bool hideYearly: root.prefs.hideYearly === true
    readonly property bool hideDailyInsights: root.prefs.hideDailyInsights === true
    readonly property bool hideYearInsights: root.prefs.hideYearInsights === true
    readonly property bool hideEasterEggs: root.prefs.hideEasterEggs === true
    readonly property bool hideRecordTrophy: root.prefs.hideRecordTrophy === true
    // Week presets; retention (95d) already covers the largest one.
    readonly property var weekOptions: [4, 8, 12]
    readonly property int weekCount: {
        var n = Number(root.prefs.weekCount);
        // Stored 13s predate the 12-week max; keep those users on max.
        if (n === 13)
            return 12;
        return root.weekOptions.indexOf(n) >= 0 ? n : 12;
    }
    readonly property int maxWeekOffset: root.weekCount - 1

    function writeSetting(key, value) {
        if (root.hostWidget && typeof root.hostWidget.setSetting === "function")
            root.hostWidget.setSetting(key, value);
    }

    function selectWeekWindow(count) {
        if (root.weekOptions.indexOf(count) >= 0 && count !== root.weekCount)
            root.writeSetting("weekCount", count);
    }

    // Busiest Week Trophy swatches, derived from the live theme; gold is
    // the default so old installs keep it. A stored pick stays selected
    // across theme switches (the menu shows it as a custom slot).
    readonly property string recordDefaultColor: "#ffd700"
    readonly property var recordColorOptions: Model.themeSwatches(Color.accent, Color.foreground, Color.muted)
    readonly property string recordColor: Model.pickSwatch(root.prefs.recordColor, root.recordDefaultColor)

    function selectRecordColor(color) {
        var c = Model.normalizeHex(color, "");
        if (c && c !== root.recordColor)
            root.writeSetting("recordColor", c);
    }

    // Hero icon color for the hourglass, the yearly hero and the settings
    // glyph. Options follow the theme; empty follows the theme
    // foreground, so old installs keep it. Stored picks survive theme
    // switches like the trophy color above.
    readonly property string heroDefaultColor: ""
    readonly property var heroColorOptions: Model.themeSwatches(Color.accent, Color.foreground, Color.muted)
    readonly property string heroColor: Model.pickSwatch(root.prefs.heroColor, root.heroDefaultColor)

    function selectHeroColor(color) {
        if (color === "") {
            if (root.heroColor !== "")
                root.writeSetting("heroColor", "");
            return;
        }
        var c = Model.normalizeHex(color, "");
        if (c && c !== root.heroColor)
            root.writeSetting("heroColor", c);
    }

    // User tracking prefs: normalized once here, pushed to the service
    // (which owns accrual) and applied to history views below.
    readonly property var ignoredList: Model.parseIgnoredApps(root.prefs.ignoredApps)
    readonly property var appAliases: Model.parseAppAliases(root.prefs.appAliases)

    function pushTrackingPrefs() {
        if (root.service && typeof root.service.setTrackingPrefs === "function")
            root.service.setTrackingPrefs(root.ignoredList, root.appAliases);
        if (root.service && typeof root.service.setKeepDays === "function")
            root.service.setKeepDays(root.keepDays);
    }
    onServiceChanged: root.pushTrackingPrefs()
    onIgnoredListChanged: root.pushTrackingPrefs()
    onAppAliasesChanged: root.pushTrackingPrefs()

    // Settings-menu list editing: prefs store comma strings, the menu
    // shows one row per entry with a save box and remove buttons.
    readonly property var aliasEntries: Model.aliasPairs(root.prefs.appAliases)
    function addIgnored(name) {
        root.writeSetting("ignoredApps", Model.ignoredWith(root.ignoredList, name).join(", "));
    }
    function removeIgnored(name) {
        root.writeSetting("ignoredApps", Model.ignoredWithout(root.ignoredList, name).join(", "));
    }
    function addAlias(from, to) {
        root.writeSetting("appAliases", Model.aliasesWith(root.prefs.appAliases, from, to));
    }
    function removeAlias(from) {
        root.writeSetting("appAliases", Model.aliasesWithout(root.prefs.appAliases, from));
    }

    // Retention window (30/95/365d) with a storage-footprint readout.
    readonly property var keepDaysOptions: [30, 95, 365]
    readonly property int keepDays: Model.parseKeepDays(root.prefs.keepDays)
    onKeepDaysChanged: root.pushTrackingPrefs()
    readonly property var storageSummary: Model.storageSummary(root.days, root.months, root.years)
    readonly property string storageLabel: Model.storageLabel(root.storageSummary)

    // First-run onboarding: nothing recorded anywhere and nothing today.
    // The donut already draws a dim ring when empty; coach marks below
    // explain what tracking covers and where settings live.
    readonly property bool showOnboarding: serviceReady && root.storageSummary.totalMs <= 0 && root.dayTotal <= 0

    // Empty selection = live today; everything derives from activeDay.
    // Ignored apps are stripped for display so the donut, legend and
    // insights agree with what tracking now records.
    property string selectedKey: ""
    readonly property var activeDay: serviceReady ? Model.filterIgnoredDay(Model.dayFor(root.days, root.today, root.selectedKey, root.todayKey), root.ignoredList) : null
    readonly property string activeDayKey: root.selectedKey || root.todayKey
    readonly property string activeDayLabel: serviceReady ? Model.formatDate(root.activeDayKey) : ""
    readonly property double dayTotal: root.activeDay ? (root.activeDay.total || 0) : 0

    // Gated on service.ready: unloaded history would label NaN-NaN-NaN.
    readonly property var groupedApps: serviceReady ? Model.groupedApps(Model.appList(root.activeDay), Model.DONUT_MAX_SLICES, Model.DONUT_MIN_PCT) : []
    readonly property var fullApps: serviceReady ? Model.appList(root.activeDay) : []
    // Single derivation for the paginated week trend; offset clamps to pages.
    readonly property var weekView: serviceReady ? Model.weekView(root.days, root.todayKey, root.weekCount, Math.max(0, Math.min(root.weekOffset, root.maxWeekOffset))) : null
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
    // The Busiest Week Trophy follows the viewed week at any page: it
    // marks the unique best week on record, not just a leading current week.
    readonly property bool recordWeek: serviceReady ? (root.weekView ? root.weekView.isRecord : false) : false
    property bool expanded: false
    property bool calendarOpen: false
    property bool configOpen: false
    property int weekOffset: 0
    // True while an older week holds data (enables the prev pager).
    readonly property bool hasPrevWeekData: root.weekView ? root.weekView.hasPrev : false
    // Week total mode persists; toggling writes the setting through.
    property bool weekTotalAsPct: root.prefs.weekTotalAsPct === true
    onMaxWeekOffsetChanged: root.weekOffset = Math.min(root.weekOffset, root.maxWeekOffset)

    // currentYearOffset: years back from today; 0 = this year.
    readonly property int todayYear: serviceReady ? (Number(root.todayKey.split("-")[0]) || new Date().getFullYear()) : new Date().getFullYear()
    property int currentYearOffset: 0
    readonly property int currentYear: root.todayYear - root.currentYearOffset
    readonly property int oldestDataYear: serviceReady ? Model.firstDataYear(root.days, root.months, root.years) : root.todayYear
    // Header total, month bars and retro cards share one year merge.
    // Skipped entirely while hidden; the drawer cannot open either.
    readonly property var yearView: serviceReady && !root.hideYearly ? Model.yearView(root.days, root.months, root.years, root.currentYear, root.todayKey, Color.accent) : null
    readonly property string calendarYearTotal: root.yearView ? root.yearView.totalLabel : "0h"
    readonly property var yearFacts: root.yearView ? root.yearView.facts : []
    readonly property var yearMonths: root.yearView ? root.yearView.months : []
    readonly property var monthNamesShort: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    readonly property var monthNamesLong: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    // Daily goal in whole hours (0 = off) with live progress off the
    // filtered active day, so ignored apps never push the goal.
    readonly property var dailyGoalOptions: [0, 4, 6, 8]
    readonly property int dailyGoalHours: Model.parseDailyGoalHours(root.prefs.dailyGoalHours)
    readonly property var goalProgress: Model.goalProgress(root.dayTotal, root.dailyGoalHours)

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
        // The two drawers never overlap: opening one closes the other.
        if (open)
            root.configOpen = false;
        if (open && !root.expanded) {
            keyCatcher.collapsedCardH = keyCatcher.height;
            root.expanded = true;
        }
        root.calendarOpen = open;
        if (open)
            yearDrawer.swingCalendar();
        else if (!root.configOpen)
            root.celebrateHome();
    }

    // Config slides from the right; same chrome contract as the calendar.
    // Like the yearly drawer, it opens expanded: settings get the full
    // panel even from SHOW LESS mode.
    function openConfig(open) {
        configDrawer.sliding = true;
        if (open) {
            // Claim the flag first: the calendar close below must not read
            // this as a return to the main panel.
            root.configOpen = true;
            root.openCalendar(false);
            if (!root.expanded) {
                keyCatcher.collapsedCardH = keyCatcher.height;
                root.expanded = true;
            }
        } else {
            root.configOpen = false;
        }
        if (open)
            configGearSpin.restart();
        else if (!root.calendarOpen)
            root.celebrateHome();
    }

    // Return-to-main celebration, once both drawers rest closed and only
    // while the panel itself stays open (dismiss closes drawers silently).
    function celebrateHome() {
        if (root.opened)
            heroHeader.spinHourglass();
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
                    id: yearDrawer
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    panelBackground: root.bar ? root.bar.background : Color.background
                    accent: Color.accent
                    heroColor: root.heroColor
                    currentYear: root.currentYear
                    currentYearOffset: root.currentYearOffset
                    oldestDataYear: root.oldestDataYear
                    calendarYearTotal: root.calendarYearTotal
                    yearFacts: root.yearFacts
                    hideYearInsights: root.hideYearInsights
                    yearMonths: root.yearMonths
                    monthNamesShort: root.monthNamesShort
                    monthNamesLong: root.monthNamesLong
                    onCloseRequested: root.openCalendar(false)
                    onPrevYearRequested: root.currentYearOffset += 1
                    onNextYearRequested: root.currentYearOffset -= 1
                }
            }

            // Config drawer: same slide contract, mirrored from the right.
            Item {
                id: configDrawer
                width: keyCatcher.drawerWidth
                height: keyCatcher.height
                anchors.top: parent.top
                x: root.configOpen ? 0 : keyCatcher.drawerWidth
                z: 11
                visible: x < keyCatcher.drawerWidth

                property bool sliding: false

                Behavior on x {
                    enabled: configDrawer.sliding
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                // Disarm at rest so resizes don't replay the slide.
                onXChanged: {
                    if (root.configOpen ? x <= 0 : x >= keyCatcher.drawerWidth)
                        sliding = false;
                }

                Rectangle {
                    anchors.fill: parent
                    color: root.bar ? root.bar.background : Color.background
                    radius: Style.space(6)
                }

                // Swallow hover/clicks so they don't reach the panel beneath.
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: function (mouse) {
                        mouse.accepted = true;
                    }
                }

                // Fixed header; the menu scrolls beneath it on short panels.
                // Full-bleed like the main panel and year drawer: no side
                // margins, components carry their own insets.
                Item {
                    id: configHeader
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    // Flush top like the year hero; breathing room lives below.
                    height: Math.max(configHeroIcon.implicitHeight, configHeroLabels.implicitHeight, configBack.implicitHeight) + Style.space(6)

                    Text {
                        id: configHeroIcon
                        text: "\uf013"
                        color: root.heroColor !== "" ? root.heroColor : Qt.darker(root.contentForeground, 1.2)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.fontPx(2.4)
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.topMargin: -Style.space(4)
                    }

                    // Settings sweep, matching the home gear: a full turn
                    // as the drawer slides in over it.
                    NumberAnimation {
                        id: configGearSpin
                        target: configHeroIcon
                        property: "rotation"
                        from: 0
                        to: 360
                        duration: 450
                        easing.type: Easing.OutBack
                    }

                    Column {
                        id: configHeroLabels
                        anchors.left: configHeroIcon.right
                        anchors.leftMargin: Style.space(14)
                        anchors.right: parent.right
                        anchors.rightMargin: configBack.implicitWidth + Style.space(12)
                        anchors.top: parent.top
                        spacing: 0

                        Text {
                            text: "Screen Time"
                            color: root.contentForeground
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.fontPx(1.5)
                            font.bold: true
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: "Settings"
                            color: Qt.darker(root.contentForeground, 1.4)
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    BackButton {
                        id: configBack
                        anchors.right: parent.right
                        anchors.top: parent.top
                        foreground: root.contentForeground
                        fontFamily: root.contentFontFamily
                        onClicked: root.openConfig(false)
                    }
                }

                Flickable {
                    id: configScroll
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.top: configHeader.bottom
                    contentWidth: width
                    contentHeight: configColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height

                    Column {
                        id: configColumn
                        // Gutter for the scrollbar so the bar never covers rows.
                        width: configScroll.width - Style.space(8)
                        spacing: Style.space(10)

                        ConfigMenu {
                            foreground: root.contentForeground
                            fontFamily: root.contentFontFamily
                            accent: Color.accent
                            urgent: Color.urgent
                            hideYearly: root.hideYearly
                            hideDailyInsights: root.hideDailyInsights
                            hideYearInsights: root.hideYearInsights
                            weekCount: root.weekCount
                            weekOptions: root.weekOptions
                            weekTotalAsPct: root.weekTotalAsPct
                            hideEasterEggs: root.hideEasterEggs
                            hideRecordTrophy: root.hideRecordTrophy
                            recordColor: root.recordColor
                            recordColorOptions: root.recordColorOptions
                            recordDefaultColor: root.recordDefaultColor
                            heroColor: root.heroColor
                            heroColorOptions: root.heroColorOptions
                            heroDefaultColor: root.heroDefaultColor
                            ignoredEntries: root.ignoredList
                            aliasEntries: root.aliasEntries
                            dailyGoalHours: root.dailyGoalHours
                            dailyGoalOptions: root.dailyGoalOptions
                            keepDays: root.keepDays
                            keepDaysOptions: root.keepDaysOptions
                            storageLabel: root.storageLabel
                            onYearlyToggled: root.writeSetting("hideYearly", !root.hideYearly)
                            onDailyInsightsToggled: root.writeSetting("hideDailyInsights", !root.hideDailyInsights)
                            onYearInsightsToggled: root.writeSetting("hideYearInsights", !root.hideYearInsights)
                            onWeekWindowSelected: function (count) {
                                root.selectWeekWindow(count);
                            }
                            onRecordColorSelected: function (color) {
                                root.selectRecordColor(color);
                            }
                            onHeroColorSelected: function (color) {
                                root.selectHeroColor(color);
                            }
                            onIgnoredAdded: function (name) {
                                root.addIgnored(name);
                            }
                            onIgnoredRemoved: function (name) {
                                root.removeIgnored(name);
                            }
                            onAliasAdded: function (from, to) {
                                root.addAlias(from, to);
                            }
                            onAliasRemoved: function (from) {
                                root.removeAlias(from);
                            }
                            onDailyGoalSelected: function (hours) {
                                if (hours !== root.dailyGoalHours)
                                    root.writeSetting("dailyGoalHours", hours);
                            }
                            onKeepDaysSelected: function (days) {
                                if (days !== root.keepDays)
                                    root.writeSetting("keepDays", days);
                            }
                            onWeekTotalModeToggled: root.writeSetting("weekTotalAsPct", !root.weekTotalAsPct)
                            onTrophyToggled: root.writeSetting("hideRecordTrophy", !root.hideRecordTrophy)
                            onEasterEggsToggled: root.writeSetting("hideEasterEggs", !root.hideEasterEggs)
                            onResetRequested: {
                                if (root.service)
                                    root.service.resetToday();
                            }
                            onWipeRequested: {
                                if (root.service)
                                    root.service.resetAll();
                            }
                        }
                    }
                }

                // Thin scrollbar on the right edge, same idiom as AppLegend:
                // only visible while the menu overflows.
                Rectangle {
                    property real ratio: configScroll.contentHeight > 0 ? configScroll.height / configScroll.contentHeight : 0
                    visible: configScroll.contentHeight > configScroll.height
                    width: 2
                    height: Math.max(Style.space(16), configScroll.height * ratio)
                    radius: width / 2
                    color: root.contentForeground
                    opacity: 0.25
                    anchors.right: configScroll.right
                    y: configScroll.y + (configScroll.height - height) * (configScroll.contentHeight > configScroll.height ? configScroll.contentY / (configScroll.contentHeight - configScroll.height) : 0)
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
                        id: heroHeader
                        foreground: root.contentForeground
                        fontFamily: root.contentFontFamily
                        heroColor: root.heroColor
                        serviceReady: root.serviceReady
                        expanded: root.expanded
                        calendarOpen: root.calendarOpen
                        calendarEnabled: !root.hideYearly
                        easterEggs: !root.hideEasterEggs
                        configOpen: root.configOpen
                        dayTotal: root.dayTotal
                        activeDayKey: root.activeDayKey
                        activeDayLabel: root.activeDayLabel
                        goalProgress: root.goalProgress
                        onExpandToggled: root.toggleExpanded()
                        onCalendarToggled: root.openCalendar(!root.calendarOpen)
                        onConfigToggled: root.openConfig(!root.configOpen)
                    }

                    // First-run coach marks; hidden once anything is tracked.
                    Item {
                        width: parent.width
                        visible: root.showOnboarding
                        height: visible ? onboardingColumn.implicitHeight : 0
                        implicitHeight: height

                        Column {
                            id: onboardingColumn
                            width: parent.width
                            spacing: Style.space(4)

                            Text {
                                text: "No screen time yet — focus any window to start"
                                color: root.contentForeground
                                opacity: 0.75
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: true
                                width: parent.width
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                text: "Terminals track what runs inside · games count too"
                                color: root.contentForeground
                                opacity: 0.4
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.caption
                                width: parent.width
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                text: "Right-click the bar for icon-only · gear for settings"
                                color: root.contentForeground
                                opacity: 0.4
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.caption
                                width: parent.width
                                wrapMode: Text.WordWrap
                            }
                        }
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
                                maxOffset: root.maxWeekOffset
                                hasPrevWeekData: root.hasPrevWeekData
                                visibleWeek: root.visibleWeek
                                recordWeek: root.recordWeek
                                showRecordTrophy: !root.hideRecordTrophy
                                weekTotalAsPct: root.weekTotalAsPct
                                visibleWeekTotalMs: root.visibleWeekTotalMs
                                axisTicks: root.axisTicks
                                axisMaxMs: root.axisMaxMs
                                activeDayKey: root.activeDayKey
                                recordColor: root.recordColor
                                onPrevWeekRequested: root.weekOffset = Math.min(root.maxWeekOffset, root.weekOffset + 1)
                                onNextWeekRequested: root.weekOffset = Math.max(0, root.weekOffset - 1)
                                onWeekTotalToggled: root.writeSetting("weekTotalAsPct", !root.weekTotalAsPct)
                                onDaySelected: function (key) {
                                    root.selectDay(key);
                                }
                            }

                            PanelSeparator {
                                visible: !root.hideDailyInsights
                                width: parent.width
                                foreground: root.contentForeground
                                strength: 0.12
                            }

                            InsightList {
                                visible: !root.hideDailyInsights
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

    // Reset to live today on dismiss (week-total mode persists).
    Connections {
        target: root.controller
        function onOpenChanged() {
            if (!root.controller.open) {
                root.selectedKey = "";
                root.openCalendar(false);
                root.weekOffset = 0;
                root.currentYearOffset = 0;
                root.openConfig(false);
                donutChart.clearHover();
            }
        }
    }
}
