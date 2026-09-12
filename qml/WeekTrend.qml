import QtQuick
import qs.Commons
import "components"
import "../js/Model.js" as Model

// Paginated Mon-Sun page; offset 0 = current week, maxOffset = oldest page.
Column {
    id: root
    required property color foreground
    required property string fontFamily
    required property color tipBackground
    required property color accent
    required property int weekOffset
    required property int maxOffset
    required property bool hasPrevWeekData
    required property var visibleWeek
    required property bool recordWeek
    required property bool weekTotalAsPct
    required property double visibleWeekTotalMs
    required property var axisTicks
    required property double axisMaxMs
    required property string activeDayKey
    required property color recordColor
    required property bool showRecordTrophy
    required property bool hintMode

    signal prevWeekRequested
    signal nextWeekRequested
    signal weekTotalToggled
    signal daySelected(string key)

    width: parent.width
    spacing: Style.space(8)

    // Prev arrow fades at the oldest page.
    Item {
        width: parent.width
        implicitHeight: Math.max(navRow.implicitHeight, weekTotalLabel.implicitHeight)

        Row {
            id: navRow
            spacing: Style.space(10)
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            PagerArrow {
                id: prevArrow
                glyph: "\uf053"
                active: root.weekOffset < root.maxOffset && root.hasPrevWeekData
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.prevWeekRequested()
            }

            HintBadge {
                label: "b"
                fontFamily: root.fontFamily
                accent: root.accent
                show: root.hintMode && root.weekOffset < root.maxOffset && root.hasPrevWeekData
                anchors.top: prevArrow.top
                anchors.left: prevArrow.left
            }

            Text {
                text: root.visibleWeek ? Model.weekRangeLabel(root.visibleWeek) : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
                // Cap width so long labels elide instead of overlapping.
                width: Math.max(40, Math.min(implicitWidth, root.width - weekTotalLabel.implicitWidth - Style.space(76)))
                anchors.verticalCenter: parent.verticalCenter
            }

            PagerArrow {
                id: nextArrow
                glyph: "\uf054"
                active: root.weekOffset > 0
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.nextWeekRequested()
            }

            HintBadge {
                label: "n"
                fontFamily: root.fontFamily
                accent: root.accent
                show: root.hintMode && root.weekOffset > 0
                anchors.top: nextArrow.top
                anchors.left: nextArrow.left
            }
        }

        // Busiest Week Trophy: gold by default, configurable and
        // hideable via the settings.
        Text {
            visible: root.recordWeek && root.showRecordTrophy
            text: "\uF091"
            color: root.recordColor
            font.family: root.fontFamily
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

            ScreenTip {
                foreground: root.foreground
                fontFamily: root.fontFamily
                tipBackground: root.tipBackground

                hovered: recordTrophyMouse.containsMouse
                tipText: "Busiest Week Trophy — your best week on record"
            }
        }

        Text {
            id: weekTotalLabel
            text: root.weekTotalAsPct ? Math.round(root.visibleWeekTotalMs / (7 * 24 * 3600000) * 100) + "%" : Model.fmt(root.visibleWeekTotalMs)
            color: root.foreground
            opacity: weekTotalMouse.containsMouse ? 1.0 : 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            anchors.right: parent.right
            anchors.rightMargin: Style.space(2)
            anchors.verticalCenter: parent.verticalCenter

            HintBadge {
                label: "t"
                fontFamily: root.fontFamily
                accent: root.accent
                show: root.hintMode
                anchors.top: weekTotalLabel.top
                anchors.right: weekTotalLabel.right
            }

            MouseArea {
                id: weekTotalMouse
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.weekTotalToggled()
            }

            ScreenTip {
                foreground: root.foreground
                fontFamily: root.fontFamily
                tipBackground: root.tipBackground

                hovered: weekTotalMouse.containsMouse
                tipText: root.weekTotalAsPct ? "% of the week's 168 hours" : "logged of 168 possible hours"
            }
        }
    }

    // Day bars on the drawer background; no plate.
    Item {
        width: parent.width
        // Inner column grew for the number + badge rows below the
        // weekday labels; the 12px top pad and 8px clearance stand.
        height: Style.space(114) + Style.space(20)
        clip: true

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: Style.space(12)
            height: Style.space(114)

            // Outer-id reads are idiomatic in delegates; muted for the linter.
            // qmllint disable unqualified
            Repeater {
                model: root.axisTicks

                WeekTick {
                    axisMaxMs: root.axisMaxMs
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                }
            }
            // qmllint enable unqualified

            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: Style.space(26)
                anchors.verticalCenter: parent.verticalCenter
                z: 2
                spacing: 0

                // Outer-id reads are idiomatic in delegates; muted for the linter.
                // qmllint disable unqualified
                Repeater {
                    model: root.visibleWeek ? root.visibleWeek.days : []

                    WeekDayBar {
                        activeDayKey: root.activeDayKey
                        axisMaxMs: root.axisMaxMs
                        foreground: root.foreground
                        accent: root.accent
                        fontFamily: root.fontFamily
                        hintMode: root.hintMode
                        dayNumber: Model.weekdayNumber(modelData.key)
                        onSelected: function (key) {
                            root.daySelected(key);
                        }
                    }
                }
                // qmllint enable unqualified
            }
        }
    }
}
