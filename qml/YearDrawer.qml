import QtQuick
import qs.Commons
import qs.Ui
import "components"
import "../js/Model.js" as Model

// Yearly overview: per-month bars plus Wrapped-style retro cards.
// Drawer slide chrome lives in Panel; this is the scrolling content.
// Month bars come from Panel's shared yearView merge via yearMonths.
Item {
    id: root
    anchors.fill: parent
    required property color foreground
    required property string fontFamily
    // Override for the year hero glyph; "" follows the foreground.
    required property string heroColor
    required property color panelBackground
    required property color accent
    required property int currentYear
    required property int currentYearOffset
    required property int oldestDataYear
    required property string calendarYearTotal
    required property bool hintMode
    required property var yearFacts
    required property bool hideYearInsights
    // Playful-extras kill switch, like the main hero: the entry swing
    // mutes with it.
    required property bool easterEggs
    required property var yearMonths
    required property var yearDays
    required property string yearGraph
    required property int heatmapSavedWeek
    required property string todayKey
    required property var monthNamesShort
    required property var monthNamesLong

    signal closeRequested
    signal prevYearRequested
    signal nextYearRequested
    signal yearGraphSelected(string mode)
    signal heatmapPositionSaved(int week)

    // Entry celebration, called by the panel as the drawer slides in.
    function swingCalendar() {
        if (root.easterEggs)
            calendarSwing.restart();
    }

    // Keyboard scrolling for the year overview. Duplicates the panel's
    // flickable math instead of reaching up: drawers never read parents.
    function scrollBy(dy) {
        var flick = calendarScroll;
        if (!flick || flick.contentHeight <= flick.height)
            return;
        flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy));
    }

    Rectangle {
        anchors.fill: parent
        color: root.panelBackground
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

    // Fixed hero header; the overview scrolls beneath it.
    Item {
        id: yearHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: implicitHeight
        // Extra height is breathing room below the hero.
        implicitHeight: Math.max(yearHeroIcon.implicitHeight, yearHeroLabels.implicitHeight, backCorner.implicitHeight) + Style.space(3)

        // Icon returns to the main panel.
        Text {
            id: yearHeroIcon
            text: "\uf073"
            color: root.heroColor !== "" ? root.heroColor : (yearHeroIconMouse.containsMouse ? root.foreground : Qt.darker(root.foreground, 1.2))
            font.family: root.fontFamily
            font.pixelSize: Style.fontPx(2.4)
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: -Style.space(4)
            // Pendulum pivot: the top hangs on the wall while the
            // bottom swings left and right on entry.
            transformOrigin: Item.Top

            MouseArea {
                id: yearHeroIconMouse
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeRequested()
            }
        }

        // Entry swing: a small damped sway, settling back to rest.
        SequentialAnimation {
            id: calendarSwing

            NumberAnimation {
                target: yearHeroIcon
                property: "rotation"
                from: 0
                to: 12
                duration: 140
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: yearHeroIcon
                property: "rotation"
                to: -9
                duration: 200
                easing.type: Easing.InOutQuad
            }

            NumberAnimation {
                target: yearHeroIcon
                property: "rotation"
                to: 0
                duration: 260
                easing.type: Easing.OutCubic
            }
        }

        Column {
            id: yearHeroLabels
            anchors.left: yearHeroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.rightMargin: backCorner.implicitWidth + graphToggle.implicitWidth + Style.space(20)
            anchors.top: parent.top
            spacing: 0

            Text {
                text: root.calendarYearTotal
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.fontPx(1.5)
                font.bold: true
                font.letterSpacing: 2.4
                elide: Text.ElideRight
                width: parent.width
            }

            Row {
                width: parent.width
                spacing: Style.space(5)

                PagerArrow {
                    id: prevYearArrow
                    glyph: "\uf053"
                    active: root.currentYear > root.oldestDataYear
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    tipText: "Previous year"
                    tipBackground: root.panelBackground
                    onClicked: root.prevYearRequested()
                }

                HintBadge {
                    label: "b"
                    fontFamily: root.fontFamily
                    accent: root.accent
                    show: root.hintMode && root.currentYear > root.oldestDataYear
                    anchors.top: prevYearArrow.top
                    anchors.left: prevYearArrow.left
                }

                Text {
                    id: yearValue
                    text: String(root.currentYear)
                    color: Qt.darker(root.foreground, 1.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }

                PagerArrow {
                    id: nextYearArrow
                    glyph: "\uf054"
                    active: root.currentYearOffset > 0
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    tipText: "Next year"
                    tipBackground: root.panelBackground
                    onClicked: root.nextYearRequested()
                }

                HintBadge {
                    label: "n"
                    fontFamily: root.fontFamily
                    accent: root.accent
                    show: root.hintMode && root.currentYearOffset > 0
                    anchors.top: nextYearArrow.top
                    anchors.left: nextYearArrow.left
                }
            }
        }

        // Graph switcher by the Back button, mirroring the main
        // panel's day toggle by the settings gear: one icon flips
        // bars ↔ heatmap in place; the pick persists in settings.
        Text {
            id: graphToggle
            text: root.yearGraph === "heatmap" ? "\uf0c9" : "\uf00a"
            color: graphToggleMouse.containsMouse ? root.foreground : Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            anchors.right: backCorner.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: backCorner.verticalCenter
        }

        MouseArea {
            id: graphToggleMouse
            anchors.fill: graphToggle
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.yearGraphSelected(root.yearGraph === "heatmap" ? "bars" : "heatmap")

            ScreenTip {
                foreground: root.foreground
                fontFamily: root.fontFamily
                tipBackground: root.panelBackground

                hovered: graphToggleMouse.containsMouse
                tipText: root.yearGraph === "heatmap" ? "Show month bars" : "Show heatmap"
            }
        }

        HintBadge {
            label: "g"
            fontFamily: root.fontFamily
            accent: root.accent
            show: root.hintMode
            anchors.top: graphToggle.top
            anchors.right: graphToggle.right
        }

        BackButton {
            id: backCorner
            anchors.right: parent.right
            anchors.top: parent.top
            foreground: root.foreground
            fontFamily: root.fontFamily
            tipText: "Back to screen time"
            tipBackground: root.panelBackground
            onClicked: root.closeRequested()
        }

        HintBadge {
            label: "m"
            fontFamily: root.fontFamily
            accent: root.accent
            show: root.hintMode
            anchors.top: backCorner.top
            anchors.right: backCorner.right
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
            // Gutter for the scrollbar so the bar never covers rows.
            width: calendarScroll.width - Style.space(8)
            spacing: Style.space(10)

            // Month bars scale to the busiest month; hover for exact total.
            Column {
                id: heatGrid
                width: parent.width
                spacing: Style.space(6)
                bottomPadding: Style.space(2)

                readonly property var months: root.yearMonths
                readonly property real maxMs: {
                    var max = 0;
                    for (var i = 0; i < months.length; i++) {
                        if (months[i].ms > max)
                            max = months[i].ms;
                    }
                    return max;
                }
                readonly property bool isThisYear: root.currentYear === new Date().getFullYear()
                readonly property int nowMonth: new Date().getMonth()
                readonly property real labelW: Style.space(26)
                readonly property real labelGap: Style.space(4)
                // Width fits any hour total at this font.
                readonly property real hoursW: hoursMetrics.implicitWidth

                Text {
                    id: hoursMetrics
                    visible: false
                    text: "8888h"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                }

                // One graph shows at a time; layout snaps to the visible one.
                Item {
                    width: parent.width
                    visible: root.yearGraph === "bars"
                    height: visible ? barsColumn.implicitHeight : 0
                    implicitHeight: height

                    Column {
                        id: barsColumn
                        width: parent.width
                        spacing: Style.space(6)

                        // Outer-id reads are idiomatic in delegates; muted for the linter.
                        // qmllint disable unqualified
                        Repeater {
                            model: 12

                            MonthRow {
                                months: heatGrid.months
                                maxMs: heatGrid.maxMs
                                monthShort: root.monthNamesShort
                                monthLong: root.monthNamesLong
                                isThisYear: heatGrid.isThisYear
                                nowMonth: heatGrid.nowMonth
                                gridWidth: barsColumn.width
                                hoursW: heatGrid.hoursW
                                foreground: root.foreground
                                fontFamily: root.fontFamily
                                panelBackground: root.panelBackground
                                accent: root.accent
                            }
                        }
                        // qmllint enable unqualified
                    }
                }

                Item {
                    width: parent.width
                    visible: root.yearGraph === "heatmap"
                    height: visible ? yearHeatmap.implicitHeight : 0
                    implicitHeight: height

                    YearHeatmap {
                        id: yearHeatmap
                        width: parent.width
                        weeks: Model.yearHeatmap(root.yearDays, root.currentYear, root.todayKey).weeks
                        currentMonth: heatGrid.isThisYear ? root.monthNamesShort[heatGrid.nowMonth] : ""
                        savedWeek: root.heatmapSavedWeek
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        accent: root.accent
                        panelBackground: root.panelBackground
                        onPositionSaved: function (week) {
                            root.heatmapPositionSaved(week);
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: Style.space(10) + 1 + Style.space(4)
                    visible: !root.hideYearInsights && root.yearFacts.length > 0
                    PanelSeparator {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        foreground: root.foreground
                    }
                }

                Text {
                    text: "Insights " + root.currentYear
                    visible: !root.hideYearInsights && root.yearFacts.length > 0
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                    width: parent.width
                    topPadding: Style.space(4)
                    bottomPadding: Style.space(6)
                }

                Row {
                    id: yearlyInsightsGrid
                    width: parent.width
                    visible: !root.hideYearInsights && root.yearFacts.length > 0
                    spacing: Style.space(8)

                    property var leftCards: []
                    property var rightCards: []

                    // Masonry split: each card lands in the currently shorter
                    // column, measured in real pixels once delegates exist,
                    // estimated before. Runs on facts/width changes only —
                    // never on heights — so a re-split cannot loop against
                    // its own layout; the deferred pass swaps estimates for
                    // measurements after delegates polish.
                    function splitCards() {
                        var cards = root.yearFacts;
                        var measured = measuredHeights();
                        var left = [];
                        var right = [];
                        var leftH = 0;
                        var rightH = 0;
                        for (var i = 0; i < cards.length; i++) {
                            var h = measured[String(cards[i].label)] || estimateHeight(cards[i]);
                            if (leftH <= rightH) {
                                left.push(cards[i]);
                                leftH += h + Style.space(8);
                            } else {
                                right.push(cards[i]);
                                rightH += h + Style.space(8);
                            }
                        }
                        yearlyInsightsGrid.leftCards = left;
                        yearlyInsightsGrid.rightCards = right;
                    }

                    function measuredHeights() {
                        var out = {};
                        var cols = [leftColumn, rightColumn];
                        for (var c = 0; c < cols.length; c++) {
                            var kids = cols[c].children;
                            for (var k = 0; k < kids.length; k++) {
                                if (kids[k].label !== undefined && kids[k].implicitHeight > 0)
                                    out[String(kids[k].label)] = kids[k].implicitHeight;
                            }
                        }
                        return out;
                    }

                    function estimateHeight(card) {
                        var lines = estimateLines(String(card.value || "")) + estimateLines(String(card.sub || ""));
                        return (lines + 2) * (Style.font.bodySmall + 4) + Style.space(20);
                    }

                    function estimateLines(text) {
                        var cardW = width > 0 ? (width - Style.space(8)) / 2 : 320;
                        var innerW = Math.max(1, cardW - Style.space(20));
                        var charsPerLine = Math.max(4, Math.floor(innerW / (Style.font.bodySmall * 0.55)));
                        return Math.max(1, Math.ceil(text.length / charsPerLine));
                    }

                    onWidthChanged: {
                        splitCards();
                        measureTimer.restart();
                    }

                    Connections {
                        target: root
                        function onYearFactsChanged() {
                            yearlyInsightsGrid.splitCards();
                            measureTimer.restart();
                        }
                    }

                    Component.onCompleted: {
                        splitCards();
                        measureTimer.restart();
                    }

                    Timer {
                        id: measureTimer
                        interval: 100
                        repeat: false
                        onTriggered: yearlyInsightsGrid.splitCards()
                    }

                    // Outer-id reads are idiomatic in delegates; muted for the linter.
                    // qmllint disable unqualified
                    CardColumn {
                        id: leftColumn
                        width: (parent.width - Style.space(8)) / 2
                        cards: yearlyInsightsGrid.leftCards
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                    }

                    CardColumn {
                        id: rightColumn
                        width: (parent.width - Style.space(8)) / 2
                        cards: yearlyInsightsGrid.rightCards
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                    }
                    // qmllint enable unqualified
                }
            }
        }
    }

    // Thin scrollbar on the right edge, same idiom as the settings
    // menu: only visible while the year content overflows.
    Rectangle {
        property real ratio: calendarScroll.contentHeight > 0 ? calendarScroll.height / calendarScroll.contentHeight : 0
        visible: calendarScroll.contentHeight > calendarScroll.height
        width: 2
        height: Math.max(Style.space(16), calendarScroll.height * ratio)
        radius: width / 2
        color: root.foreground
        opacity: 0.25
        anchors.right: calendarScroll.right
        y: calendarScroll.y + (calendarScroll.height - height) * (calendarScroll.contentHeight > calendarScroll.height ? calendarScroll.contentY / (calendarScroll.contentHeight - calendarScroll.height) : 0)
    }
}
