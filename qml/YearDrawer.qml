import QtQuick
import qs.Commons
import qs.Ui
import "components"
import "../js/Model.js" as Model

// Yearly overview: per-month bars plus Wrapped-style retro cards.
// Drawer slide chrome lives in Panel; this is the scrolling content.
Item {
    id: root
    anchors.fill: parent
    required property color foreground
    required property string fontFamily
    required property color panelBackground
    required property color accent
    required property bool serviceReady
    required property var days
    required property var months
    required property var years
    required property string todayKey
    required property int currentYear
    required property int currentYearOffset
    required property int oldestDataYear
    required property string calendarYearTotal
    required property var yearFacts
    required property var monthNamesShort
    required property var monthNamesLong

    signal closeRequested
    signal prevYearRequested
    signal nextYearRequested

    Rectangle {
        anchors.fill: parent
        color: root.panelBackground
        radius: Style.space(6)
    }

    // Swallows hover and clicks so they don't reach the donut, legend
    // and week graph beneath the drawer. Declared before the scroll
    // view so the drawer's own controls stay on top of it.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: function (mouse) {
            mouse.accepted = true;
        }
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
            color: yearHeroIconMouse.containsMouse ? root.foreground : Qt.darker(root.foreground, 1.2)
            font.family: root.fontFamily
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
                onClicked: root.closeRequested()
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
                color: root.foreground
                font.family: root.fontFamily
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
                    color: yearPrevMouse.enabled && yearPrevMouse.containsMouse ? root.foreground : Qt.darker(root.foreground, 1.4)
                    opacity: yearPrevMouse.enabled ? 1.0 : 0.25
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                        }
                    }
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        id: yearPrevMouse
                        anchors.fill: parent
                        anchors.margins: -Style.space(6)
                        hoverEnabled: true
                        enabled: root.currentYear > root.oldestDataYear
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.prevYearRequested()
                    }
                }

                Text {
                    id: yearValue
                    text: String(root.currentYear)
                    color: Qt.darker(root.foreground, 1.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    id: yearNextGlyph
                    text: "\uf054"
                    color: yearNextMouse.enabled && yearNextMouse.containsMouse ? root.foreground : Qt.darker(root.foreground, 1.4)
                    opacity: yearNextMouse.enabled ? 1.0 : 0.25
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                        }
                    }
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        id: yearNextMouse
                        anchors.fill: parent
                        anchors.margins: -Style.space(6)
                        hoverEnabled: true
                        enabled: root.currentYearOffset > 0
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.nextYearRequested()
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
                    color: backCornerMouse.containsMouse ? root.foreground : Qt.darker(root.foreground, 1.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "BACK"
                    color: backCornerMouse.containsMouse ? root.foreground : Qt.darker(root.foreground, 1.4)
                    font.family: root.fontFamily
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
                onClicked: root.closeRequested()
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

                readonly property var months: root.serviceReady ? Model.monthlyTotals(root.days, root.months, root.currentYear, root.years, root.todayKey) : []
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
                // Wide enough for any "NNNh NNm" total at the current font.
                readonly property real hoursW: hoursMetrics.implicitWidth

                Text {
                    id: hoursMetrics
                    visible: false
                    text: "8888h"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                }

                // Delegates read outer ids (idiomatic QML); silence the
                // linter for that documented pattern.
                // qmllint disable unqualified
                Repeater {
                    model: 12

                    Item {
                        id: monthRow
                        required property int index

                        width: heatGrid.width
                        height: Style.space(12)

                        readonly property bool isCurrentMonth: heatGrid.isThisYear && monthRow.index === heatGrid.nowMonth
                        readonly property real hoursW: heatGrid.hoursW
                        readonly property real availW: heatGrid.width - heatGrid.labelW - heatGrid.labelGap - hoursW - heatGrid.labelGap
                        readonly property real ratio: heatGrid.maxMs > 0 ? (heatGrid.months[monthRow.index] ? heatGrid.months[monthRow.index].ms / heatGrid.maxMs : 0) : 0

                        Text {
                            text: root.monthNamesShort[monthRow.index]
                            color: root.foreground
                            opacity: monthRow.isCurrentMonth ? 1.0 : 0.55
                            font.family: root.fontFamily
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
                            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
                        }

                        Rectangle {
                            id: monthBar
                            x: heatGrid.labelW + heatGrid.labelGap
                            width: Math.max(0, monthRow.availW * monthRow.ratio)
                            height: parent.height
                            radius: Style.space(2)
                            color: monthRow.isCurrentMonth ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.8)

                            MouseArea {
                                id: monthBarMouse
                                anchors.fill: parent
                                anchors.margins: -Style.space(4)
                                hoverEnabled: true
                            }

                            PanelToolTip {
                                foreground: root.foreground
                                fontFamily: root.fontFamily
                                tipBackground: root.panelBackground

                                hovered: monthBarMouse.containsMouse
                                tipText: {
                                    var m = heatGrid.months[monthRow.index];
                                    return root.monthNamesLong[monthRow.index] + " \u00b7 " + (m ? Model.fmt(m.ms) : "0h");
                                }
                            }
                        }

                        Text {
                            text: {
                                var m = heatGrid.months[monthRow.index];
                                return m ? m.hours : "0h";
                            }
                            color: root.foreground
                            opacity: monthRow.isCurrentMonth ? 1.0 : 0.55
                            font.family: root.fontFamily
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
                // qmllint enable unqualified

                Item {
                    width: parent.width
                    height: Style.space(10) + 1 + Style.space(4)
                    visible: root.yearFacts.length > 0
                    PanelSeparator {
                        anchors.top: parent.top
                        anchors.topMargin: Style.space(10)
                        foreground: root.foreground
                    }
                }

                Text {
                    text: "Insights " + root.currentYear
                    visible: root.yearFacts.length > 0
                    color: root.foreground
                    font.family: root.fontFamily
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
                        InsightCard {
                            // Outer-id read, idiomatic for delegates.
                            // qmllint disable unqualified
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            // qmllint enable unqualified
                        }
                    }

                    // Masonry split: cards keep their own height, so the two
                    // columns drift independently instead of flexing to match.
                    function splitCards() {
                        var cards = root.yearFacts;
                        var left = [];
                        var right = [];
                        var leftScore = 0;
                        var rightScore = 0;
                        for (var i = 0; i < cards.length; i++) {
                            var score = cardScore(cards[i]);
                            if (leftScore <= rightScore) {
                                left.push(cards[i]);
                                leftScore += score;
                            } else {
                                right.push(cards[i]);
                                rightScore += score;
                            }
                        }
                        leftCards = left;
                        rightCards = right;
                    }

                    function cardScore(card) {
                        return estimateLines(String(card.value || "")) + estimateLines(String(card.sub || ""));
                    }

                    function estimateLines(text) {
                        var cardW = width > 0 ? (width - Style.space(8)) / 2 : 320;
                        var innerW = Math.max(1, cardW - Style.space(20));
                        var charsPerLine = Math.max(4, Math.floor(innerW / (Style.font.bodySmall * 0.55)));
                        return Math.max(1, Math.ceil(text.length / charsPerLine));
                    }

                    onWidthChanged: splitCards()

                    Connections {
                        target: root
                        function onYearFactsChanged() {
                            yearlyInsightsGrid.splitCards();
                        }
                    }

                    Component.onCompleted: splitCards()

                    Row {
                        id: cardsRow
                        spacing: Style.space(8)
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top

                        // Delegates read outer ids (idiomatic QML); silence the
                        // linter for that documented pattern.
                        // qmllint disable unqualified
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
                        // qmllint enable unqualified
                    }
                }
            }
        }
    }
}
