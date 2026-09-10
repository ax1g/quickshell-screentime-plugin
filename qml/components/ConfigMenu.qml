import QtQuick
import qs.Commons

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
    required property bool hideInsights
    required property int weekCount
    required property bool weekTotalAsPct
    required property bool hideEasterEggs

    signal yearlyToggled
    signal insightsToggled
    signal prevWeekWindowRequested
    signal nextWeekWindowRequested
    signal weekTotalModeToggled
    signal easterEggsToggled
    signal resetRequested

    width: parent.width
    spacing: Style.space(6)

    function activate(kind) {
        if (kind === "yearly")
            root.yearlyToggled();
        else if (kind === "insights")
            root.insightsToggled();
        else if (kind === "weektotal")
            root.weekTotalModeToggled();
        else if (kind === "easter")
            root.easterEggsToggled();
    }

    Repeater {
        model: [
            {
                kind: "yearly",
                label: "Yearly overview",
                shown: !root.hideYearly
            },
            {
                kind: "insights",
                label: "Insights",
                shown: !root.hideInsights
            },
            {
                kind: "weektotal",
                label: "Week total as %",
                shown: root.weekTotalAsPct
            },
            {
                kind: "easter",
                label: "Easter eggs",
                shown: !root.hideEasterEggs
            }
        ]

        Item {
            required property var modelData
            width: root.width
            height: Math.max(toggleLabel.implicitHeight, toggleState.implicitHeight)

            Text {
                id: toggleLabel
                text: modelData.label
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                id: toggleState
                text: modelData.shown ? "ON" : "OFF"
                color: modelData.shown ? root.accent : Qt.darker(root.foreground, 1.4)
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
                onClicked: root.activate(modelData.kind)
            }
        }
    }

    // Week window stepper; retention already covers up to 13 weeks.
    Item {
        width: root.width
        height: Math.max(weekLabel.implicitHeight, weekValue.implicitHeight)

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
            id: weekStepper
            spacing: Style.space(8)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            PagerArrow {
                glyph: "\uf053"
                active: root.weekCount > 4
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.prevWeekWindowRequested()
            }

            Text {
                id: weekValue
                text: root.weekCount + " wk"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }

            PagerArrow {
                glyph: "\uf054"
                active: root.weekCount < 13
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.nextWeekWindowRequested()
            }
        }
    }

    // 3-click reset: arm, confirm, execute. Mouse-leave or 3s disarms.
    Item {
        width: root.width
        height: Math.max(resetLabel.implicitHeight, resetState.implicitHeight)

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
            color: parent.stage === 0 ? Qt.darker(root.foreground, 1.4) : root.urgent
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
