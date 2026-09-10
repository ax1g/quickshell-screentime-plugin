import QtQuick
import qs.Commons
import qs.Ui

// Panel config menu: prefs, week window, today reset.
// Values thread in from BarWidget settings; Panel writes back on signals.
// Lives in the config slide-over drawer, which owns the title.
// Outer-id reads are idiomatic in delegates; muted for the linter.
// qmllint disable unqualified

Column {
    id: root
    required property color foreground
    required property string fontFamily
    required property color accent
    required property color urgent
    required property bool hideYearly
    required property bool hideDailyInsights
    required property bool hideYearInsights
    required property int weekCount
    required property var weekOptions
    required property bool weekTotalAsPct
    required property bool hideEasterEggs

    signal yearlyToggled
    signal dailyInsightsToggled
    signal yearInsightsToggled
    signal weekWindowSelected(int count)
    signal weekTotalModeToggled
    signal easterEggsToggled
    signal resetRequested

    width: parent.width
    spacing: Style.space(8)

    Toggle {
        width: root.width
        label: "Yearly overview"
        description: "Month bars and yearly retro cards"
        checked: !root.hideYearly
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: root.yearlyToggled()
    }

    Toggle {
        width: root.width
        label: "Daily insights"
        description: "Top app, vs yesterday, busiest day"
        checked: !root.hideDailyInsights
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: root.dailyInsightsToggled()
    }

    Toggle {
        width: root.width
        label: "Yearly insights"
        description: "Retro cards in the yearly overview"
        checked: !root.hideYearInsights
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: root.yearInsightsToggled()
    }

    Toggle {
        width: root.width
        label: "Week total as %"
        description: "Header shows share of 168 hours"
        checked: root.weekTotalAsPct
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: root.weekTotalModeToggled()
    }

    Toggle {
        width: root.width
        label: "Easter eggs"
        description: "Hourglass flip and hover sparkles"
        checked: !root.hideEasterEggs
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: root.easterEggsToggled()
    }

    // Week window option boxes; retention already covers the largest one.
    Item {
        width: root.width
        height: Math.max(weekLabel.implicitHeight, weekBoxes.implicitHeight) + Style.space(8)

        Text {
            id: weekLabel
            text: "Week trend"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        Row {
            id: weekBoxes
            spacing: Style.space(6)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                model: root.weekOptions

                Rectangle {
                    required property int modelData
                    readonly property bool chosen: modelData === root.weekCount
                    width: Style.space(40)
                    height: Style.space(24)
                    radius: Style.space(4)
                    color: chosen ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15) : "transparent"
                    border.color: chosen ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                    border.width: 1

                    Text {
                        text: modelData
                        color: chosen ? root.accent : root.foreground
                        opacity: chosen ? 1.0 : 0.6
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: chosen
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.weekWindowSelected(modelData)
                    }
                }
            }
        }
    }

    // 3-click reset: arm, confirm, execute. Mouse-leave or 3s disarms.
    Item {
        width: root.width
        height: Math.max(resetLabel.implicitHeight, resetState.implicitHeight) + Style.space(8)

        property int stage: 0

        Timer {
            id: resetRevertTimer
            interval: 3000
            repeat: false
            onTriggered: parent.stage = 0
        }

        Text {
            id: resetLabel
            text: "Reset today"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: resetState
            text: parent.stage === 0 ? "RESET" : parent.stage === 1 ? "SURE?" : "REALLY?"
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (parent.stage >= 2) {
                    parent.stage = 0;
                    resetRevertTimer.stop();
                    root.resetRequested();
                } else {
                    parent.stage++;
                    resetRevertTimer.restart();
                }
            }
            onContainsMouseChanged: {
                if (!containsMouse && parent.stage > 0) {
                    parent.stage = 0;
                    resetRevertTimer.stop();
                }
            }
        }
    }
}
// qmllint enable unqualified
