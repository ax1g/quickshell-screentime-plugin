import QtQuick
import qs.Commons
import "components"
import "../js/Model.js" as Model

// Paginated Mon-Sun page; offset 0 = current week.
Column {
    id: root
    required property color foreground
    required property string fontFamily
    required property color tipBackground
    required property color accent
    required property int weekOffset
    required property bool hasPrevWeekData
    required property var visibleWeek
    required property bool recordWeek
    required property bool weekTotalAsPct
    required property double visibleWeekTotalMs
    required property var axisTicks
    required property double axisMaxMs
    required property string activeDayKey

    signal prevWeekRequested
    signal nextWeekRequested
    signal weekTotalToggled
    signal daySelected(string key)

    width: parent.width
    spacing: Style.space(8)

    // Arrows fade at the 13-week edges.
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
                color: weekPrevMouse.enabled && weekPrevMouse.containsMouse ? root.foreground : Qt.darker(root.foreground, 1.4)
                opacity: weekPrevMouse.enabled ? 1.0 : 0.25
                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }
                }
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                    id: weekPrevMouse
                    anchors.fill: parent
                    anchors.margins: -Style.space(6)
                    hoverEnabled: true
                    enabled: root.weekOffset < 12 && root.hasPrevWeekData
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.prevWeekRequested()
                }
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

            Text {
                text: "\uf054"
                color: weekNextMouse.enabled && weekNextMouse.containsMouse ? root.foreground : Qt.darker(root.foreground, 1.4)
                opacity: weekNextMouse.enabled ? 1.0 : 0.25
                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }
                }
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                    id: weekNextMouse
                    anchors.fill: parent
                    anchors.margins: -Style.space(6)
                    hoverEnabled: true
                    enabled: root.weekOffset > 0
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.nextWeekRequested()
                }
            }
        }

        // Gold glyph while the current week leads on record.
        Text {
            visible: root.recordWeek
            text: "\uF091"
            color: "#FFD700"
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
                tipText: "Busiest week on record — new high!"
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
        // 12px top pad for the peak label, 8px bottom clearance.
        height: Style.space(80) + Style.space(20)
        clip: true

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: Style.space(12)
            height: Style.space(80)

            // Outer-id reads are idiomatic in delegates; muted for the linter.
            // qmllint disable unqualified
            Repeater {
                model: root.axisTicks

                Item {
                    id: tickDelegate
                    required property double modelData
                    width: parent.width
                    height: 1
                    z: 1
                    y: root.axisMaxMs > 0 ? (parent.height - Style.space(14) - Style.space(64) * Number(tickDelegate.modelData) / root.axisMaxMs) : parent.height

                    // Gridlines stop before the y-axis labels.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(26)
                        height: 1
                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                    }

                    Text {
                        text: Model.fmtWholeHours(tickDelegate.modelData)
                        color: Qt.darker(root.foreground, 1.35)
                        font.family: root.fontFamily
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

                    Item {
                        id: dayDelegate
                        required property var modelData
                        required property int index

                        width: (parent.width - parent.spacing * 6) / 7
                        height: Style.space(80)

                        property bool isActive: modelData.key === root.activeDayKey
                        property bool isFuture: modelData.isFuture
                        property bool isEmpty: !isFuture && modelData.ms <= 0
                        property bool hasData: !isFuture && !isEmpty && root.axisMaxMs > 0
                        property real barPx: hasData ? Math.max(3, Style.space(64) * Number(modelData.ms) / root.axisMaxMs) : 0

                        Rectangle {
                            width: parent.width * 0.5
                            radius: Style.space(2)
                            color: (parent.isFuture || parent.isEmpty) ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10) : (parent.isActive ? root.accent : (barMouse.containsMouse ? Qt.lighter(root.foreground, 1.4) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.9)))
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
                                onClicked: root.daySelected(dayDelegate.modelData.key)
                            }
                        }

                            Text {
                                text: dayDelegate.modelData.label
                            color: root.foreground
                                opacity: (parent.isActive || (!parent.isFuture && dayDelegate.modelData.ms > 0)) ? 1.0 : 0.45
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: parent.isActive
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            anchors.bottom: parent.bottom
                        }
                    }
                }
                // qmllint enable unqualified
            }
        }
    }
}
