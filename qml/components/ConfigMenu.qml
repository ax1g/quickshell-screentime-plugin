import QtQuick
import qs.Commons
import qs.Ui

// Panel config menu: prefs, week window, today reset.
// Values thread in from BarWidget settings; Panel writes back on signals.
// Lives in the config slide-over drawer, which owns the title.
// Rows mirror InsightList metrics: dim bodySmall labels, bold values right.
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
    required property bool hideRecordTrophy
    required property string recordColor
    required property var recordColorOptions

    signal yearlyToggled
    signal dailyInsightsToggled
    signal yearInsightsToggled
    signal weekWindowSelected(int count)
    signal weekTotalModeToggled
    signal trophyToggled
    signal easterEggsToggled
    signal recordColorSelected(string color)
    signal resetRequested

    width: parent.width
    spacing: Style.space(8)

    function activate(kind) {
        if (kind === "yearly")
            root.yearlyToggled();
        else if (kind === "daily")
            root.dailyInsightsToggled();
        else if (kind === "retro")
            root.yearInsightsToggled();
        else if (kind === "weektotal")
            root.weekTotalModeToggled();
        else if (kind === "trophy")
            root.trophyToggled();
        else if (kind === "easter")
            root.easterEggsToggled();
    }

    Repeater {
        model: [
            {
                kind: "yearly",
                label: "Yearly overview",
                sub: "Monthly bars and a year-in-review",
                shown: !root.hideYearly
            },
            {
                kind: "daily",
                label: "Daily highlights",
                sub: "Top app, change since yesterday, busiest day",
                shown: !root.hideDailyInsights
            },
            {
                kind: "retro",
                label: "Year-in-review cards",
                sub: "Fun yearly summaries inside the overview",
                shown: !root.hideYearInsights
            },
            {
                kind: "weektotal",
                label: "Show week total as %",
                sub: "Share of the full week (168 hours), not hours",
                shown: root.weekTotalAsPct
            },
            {
                kind: "trophy",
                label: "Busiest Week Trophy",
                sub: "Trophy for your best week on record",
                shown: !root.hideRecordTrophy
            },
            {
                kind: "easter",
                label: "Playful extras",
                sub: "Animated hourglass and cursor sparkles",
                shown: !root.hideEasterEggs
            }
        ]

        Item {
            required property var modelData
            width: root.width
            height: Math.max(toggleLabels.implicitHeight, toggleSwitch.implicitHeight) + Style.space(4)

            Column {
                id: toggleLabels
                anchors.left: parent.left
                anchors.right: toggleSwitch.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                    text: modelData.label
                    color: root.foreground
                    opacity: 0.6
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    width: parent.width
                    elide: Text.ElideRight
                }

                Text {
                    text: modelData.sub
                    color: root.foreground
                    opacity: 0.4
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    width: parent.width
                    elide: Text.ElideRight
                }
            }

            ToggleSwitch {
                id: toggleSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                trackHeight: 18
                // The row owns the click; this also drops the cursor-ring
                // padding so the track aligns flush with the other controls.
                interactive: false
                checked: modelData.shown
                foreground: root.foreground
                accent: root.accent
                onToggled: root.activate(modelData.kind)
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activate(modelData.kind)
            }
        }
    }

    // Week window option boxes; retention already covers the largest one.
    Item {
        width: root.width
        height: Math.max(weekLabel.implicitHeight, weekBoxes.implicitHeight) + Style.space(8)

        Text {
            id: weekLabel
            text: "Weeks of history"
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

    // Busiest Week Trophy color swatches; gold first (= default).
    Item {
        width: root.width
        height: Math.max(trophyLabel.implicitHeight, trophySwatches.implicitHeight) + Style.space(8)

        Text {
            id: trophyLabel
            text: "Busiest Week Trophy color"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        Row {
            id: trophySwatches
            spacing: Style.space(6)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                model: root.recordColorOptions

                Rectangle {
                    required property string modelData
                    readonly property bool chosen: modelData === root.recordColor
                    width: Style.space(16)
                    height: Style.space(16)
                    radius: Style.space(8)
                    color: modelData
                    border.color: chosen ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                    border.width: chosen ? 2 : 1

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.recordColorSelected(modelData)
                    }
                }
            }
        }
    }

    // 3-click reset: arm, confirm, execute. Mouse-leave or 3s disarms.
    // The sub-line states the blast radius: today only, history is kept.
    // The state sits in an urgent-bordered box so the destructive action
    // reads as a button, matching the week-window option boxes.
    Item {
        id: resetRow
        width: root.width
        height: Math.max(resetLabels.implicitHeight, resetBox.implicitHeight) + Style.space(8)

        property int stage: 0

        Timer {
            id: resetRevertTimer
            interval: 3000
            repeat: false
            onTriggered: resetRow.stage = 0
        }

        Column {
            id: resetLabels
            anchors.left: parent.left
            anchors.right: resetBox.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
                text: "Reset today"
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                width: parent.width
                elide: Text.ElideRight
            }

            Text {
                text: "Only today is cleared — past days are kept"
                color: root.foreground
                opacity: 0.4
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                width: parent.width
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: resetBox
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: resetState.implicitWidth + Style.space(16)
            height: resetState.implicitHeight + Style.space(8)
            radius: Style.space(4)
            color: "transparent"
            border.color: root.urgent
            border.width: 1

            Text {
                id: resetState
                text: resetRow.stage === 0 ? "RESET" : resetRow.stage === 1 ? "SURE?" : "REALLY?"
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                anchors.centerIn: parent
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (resetRow.stage >= 2) {
                    resetRow.stage = 0;
                    resetRevertTimer.stop();
                    root.resetRequested();
                } else {
                    resetRow.stage++;
                    resetRevertTimer.restart();
                }
            }
            onContainsMouseChanged: {
                if (!containsMouse && resetRow.stage > 0) {
                    resetRow.stage = 0;
                    resetRevertTimer.stop();
                }
            }
        }
    }
}
// qmllint enable unqualified
