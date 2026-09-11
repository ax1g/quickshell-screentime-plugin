import QtQuick
import qs.Commons
import qs.Ui

// Panel config menu: prefs grouped into tinted section cards.
// Values thread in from BarWidget settings; Panel writes back on signals.
// Lives in the config slide-over drawer, which owns the title.
// Every row stacks its full-width label block above its controls, and
// hints wrap instead of eliding, so long captions stay readable.
// Ignored apps and aliases edit as entry lists with a save box.
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
    required property string heroColor
    required property var heroColorOptions
    required property var ignoredEntries
    required property var aliasEntries
    required property int dailyGoalHours
    required property var dailyGoalOptions
    required property int keepDays
    required property var keepDaysOptions
    required property string storageLabel

    signal yearlyToggled
    signal dailyInsightsToggled
    signal yearInsightsToggled
    signal weekWindowSelected(int count)
    signal weekTotalModeToggled
    signal trophyToggled
    signal easterEggsToggled
    signal recordColorSelected(string color)
    signal heroColorSelected(string color)
    signal ignoredAdded(string name)
    signal ignoredRemoved(string name)
    signal aliasAdded(string from, string to)
    signal aliasRemoved(string from)
    signal dailyGoalSelected(int hours)
    signal keepDaysSelected(int days)
    signal resetRequested
    signal wipeRequested

    width: parent.width
    spacing: Style.space(12)

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

    // ---- Display ------------------------------------------------------

    Rectangle {
        width: root.width
        height: displayBody.implicitHeight + Style.space(24)
        radius: Style.space(8)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)

        Column {
            id: displayBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(10)

            Text {
                text: "DISPLAY"
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.5
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
                    width: parent.width
                    height: Math.max(toggleLabels.implicitHeight, toggleSwitch.implicitHeight)

                    Column {
                        id: toggleLabels
                        anchors.left: parent.left
                        anchors.right: toggleSwitch.left
                        anchors.rightMargin: Style.space(12)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(2)

                        Text {
                            text: modelData.label
                            color: root.foreground
                            opacity: 0.75
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            width: parent.width
                            elide: Text.ElideRight
                        }

                        Text {
                            text: modelData.sub
                            color: root.foreground
                            opacity: 0.45
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            width: parent.width
                            wrapMode: Text.WordWrap
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
        }
    }

    // ---- Colors -------------------------------------------------------

    Rectangle {
        width: root.width
        height: colorsBody.implicitHeight + Style.space(24)
        radius: Style.space(8)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)

        Column {
            id: colorsBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(10)

            Text {
                text: "COLORS"
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.5
            }

            // Busiest Week Trophy color swatches; neutrals first, gold is default.
            Column {
                width: parent.width
                spacing: Style.space(6)

                Text {
                    text: "Busiest Week Trophy"
                    color: root.foreground
                    opacity: 0.75
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    width: parent.width
                    elide: Text.ElideRight
                }

                Row {
                    id: trophySwatches
                    spacing: Style.space(8)
                    anchors.right: parent.right

                    Repeater {
                        model: root.recordColorOptions

                        Rectangle {
                            required property string modelData
                            readonly property bool chosen: modelData === root.recordColor
                            width: Style.space(20)
                            height: Style.space(20)
                            radius: Style.space(10)
                            color: modelData
                            border.color: chosen ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                            border.width: chosen ? 3 : 1

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

            // Hero icon color for the hourglass, the yearly hero and the
            // settings glyph. Concrete circles only, starting with neutrals.
            Column {
                width: parent.width
                spacing: Style.space(6)

                Column {
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                        text: "Hero icons"
                        color: root.foreground
                        opacity: 0.75
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        width: parent.width
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "Hourglass, yearly hero and settings glyph"
                        color: root.foreground
                        opacity: 0.45
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }

                Row {
                    id: heroSwatches
                    spacing: Style.space(8)
                    anchors.right: parent.right

                    Repeater {
                        model: root.heroColorOptions

                        Rectangle {
                            required property string modelData
                            readonly property bool chosen: modelData === root.heroColor
                            width: Style.space(20)
                            height: Style.space(20)
                            radius: Style.space(10)
                            color: modelData
                            border.color: chosen ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                            border.width: chosen ? 3 : 1

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.heroColorSelected(modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Trend & history ----------------------------------------------

    Rectangle {
        width: root.width
        height: historyBody.implicitHeight + Style.space(24)
        radius: Style.space(8)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)

        Column {
            id: historyBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(10)

            Text {
                text: "TREND & HISTORY"
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.5
            }

            // Week window option boxes; retention already covers the largest one.
            Column {
                width: parent.width
                spacing: Style.space(6)

                Column {
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                        text: "Weeks of history"
                        color: root.foreground
                        opacity: 0.75
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        width: parent.width
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "Paginated Mon–Sun pages back from the current week"
                        color: root.foreground
                        opacity: 0.45
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }

                Row {
                    id: weekBoxes
                    spacing: Style.space(6)
                    anchors.right: parent.right

                    Repeater {
                        model: root.weekOptions

                        Rectangle {
                            required property int modelData
                            readonly property bool chosen: modelData === root.weekCount
                            width: Style.space(44)
                            height: Style.space(28)
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

            // Retention window in days; shrinking it archives day detail
            // instead of deleting it, and the readout shows the footprint.
            Column {
                width: parent.width
                spacing: Style.space(6)

                Column {
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                        text: "Keeps history"
                        color: root.foreground
                        opacity: 0.75
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        width: parent.width
                        elide: Text.ElideRight
                    }

                    Text {
                        text: root.storageLabel
                        color: root.foreground
                        opacity: 0.45
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }

                Row {
                    id: keepBoxes
                    spacing: Style.space(6)
                    anchors.right: parent.right

                    Repeater {
                        model: root.keepDaysOptions

                        Rectangle {
                            required property int modelData
                            readonly property bool chosen: modelData === root.keepDays
                            width: Style.space(52)
                            height: Style.space(28)
                            radius: Style.space(4)
                            color: chosen ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15) : "transparent"
                            border.color: chosen ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                            border.width: 1

                            Text {
                                text: modelData + "d"
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
                                onClicked: root.keepDaysSelected(modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Daily goal ---------------------------------------------------

    Rectangle {
        width: root.width
        height: goalBody.implicitHeight + Style.space(24)
        radius: Style.space(8)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)

        Column {
            id: goalBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(10)

            Text {
                text: "DAILY GOAL"
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.5
            }

            // Daily goal presets in hours; 0 is Off. The bar badges a check
            // and the hero shows remaining once the day reaches the goal.
            Column {
                width: parent.width
                spacing: Style.space(6)

                Column {
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                        text: "Daily screen time goal"
                        color: root.foreground
                        opacity: 0.75
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        width: parent.width
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "A check badge appears in the bar when the day reaches it"
                        color: root.foreground
                        opacity: 0.45
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }

                Row {
                    id: goalBoxes
                    spacing: Style.space(6)
                    anchors.right: parent.right

                    Repeater {
                        model: root.dailyGoalOptions

                        Rectangle {
                            required property int modelData
                            readonly property bool chosen: modelData === root.dailyGoalHours
                            width: modelData === 0 ? Style.space(52) : Style.space(44)
                            height: Style.space(28)
                            radius: Style.space(4)
                            color: chosen ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15) : "transparent"
                            border.color: chosen ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                            border.width: 1

                            Text {
                                text: modelData === 0 ? "Off" : modelData + "h"
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
                                onClicked: root.dailyGoalSelected(modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Tracking -----------------------------------------------------

    Rectangle {
        width: root.width
        height: trackingBody.implicitHeight + Style.space(24)
        radius: Style.space(8)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)

        Column {
            id: trackingBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(10)

            Text {
                text: "TRACKING"
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.5
            }

            // Ignored apps: names that are never tracked and are hidden
            // from history views. Matching is case-insensitive and covers
            // raw, canonical and display names. ADD (or Enter) appends.
            Column {
                width: parent.width
                spacing: Style.space(6)

                Column {
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                        text: "Ignored apps"
                        color: root.foreground
                        opacity: 0.75
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        width: parent.width
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "Never tracked, e.g. launcher, portal"
                        color: root.foreground
                        opacity: 0.45
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }

                Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Rectangle {
                        width: parent.width - ignoredSaveBox.width - parent.spacing
                        height: ignoredInput.implicitHeight + Style.space(14)
                        radius: Style.space(6)
                        color: "transparent"
                        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                        border.width: 1

                        TextInput {
                            id: ignoredInput
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            selectByMouse: true
                            clip: true
                            onAccepted: {
                                root.ignoredAdded(text);
                                ignoredInput.text = "";
                            }
                        }
                    }

                    Rectangle {
                        id: ignoredSaveBox
                        width: ignoredSaveLabel.implicitWidth + Style.space(20)
                        height: ignoredInput.implicitHeight + Style.space(14)
                        radius: Style.space(6)
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                        border.color: root.accent
                        border.width: 1

                        Text {
                            id: ignoredSaveLabel
                            text: "ADD"
                            color: root.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.ignoredAdded(ignoredInput.text);
                                ignoredInput.text = "";
                            }
                        }
                    }
                }

                Column {
                    id: ignoredListCol
                    width: parent.width
                    spacing: Style.space(4)

                    Text {
                        visible: root.ignoredEntries.length === 0
                        text: "Nothing ignored yet"
                        color: root.foreground
                        opacity: 0.35
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.italic: true
                    }

                    Repeater {
                        model: root.ignoredEntries

                        Item {
                            required property string modelData
                            width: ignoredListCol.width
                            height: Math.max(ignoredName.implicitHeight, ignoredRemove.implicitHeight)

                            Text {
                                id: ignoredName
                                text: modelData
                                color: root.foreground
                                opacity: 0.75
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                anchors.left: parent.left
                                anchors.right: ignoredRemove.left
                                anchors.rightMargin: Style.space(8)
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                            }

                            Text {
                                id: ignoredRemove
                                text: "×"
                                color: root.urgent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.title
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            MouseArea {
                                anchors.fill: ignoredRemove
                                anchors.margins: -Style.space(6)
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.ignoredRemoved(modelData)
                            }
                        }
                    }
                }
            }

            // Custom aliases: from=to renames applied before the built-in
            // browser fold, so terminals and odd ids get your own names.
            // Matching covers raw, canonical and display names. ADD (or
            // Enter) saves; saving an existing name updates its target.
            Column {
                width: parent.width
                spacing: Style.space(6)

                Column {
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                        text: "App names"
                        color: root.foreground
                        opacity: 0.75
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        width: parent.width
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "Rename apps, e.g. zen to browser"
                        color: root.foreground
                        opacity: 0.45
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }

                Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Rectangle {
                        width: (parent.width - aliasSaveBox.width - parent.spacing * 2) / 2
                        height: aliasFromInput.implicitHeight + Style.space(14)
                        radius: Style.space(6)
                        color: "transparent"
                        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                        border.width: 1

                        TextInput {
                            id: aliasFromInput
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            selectByMouse: true
                            clip: true
                            onAccepted: aliasToInput.forceActiveFocus()
                        }
                    }

                    Rectangle {
                        width: (parent.width - aliasSaveBox.width - parent.spacing * 2) / 2
                        height: aliasToInput.implicitHeight + Style.space(14)
                        radius: Style.space(6)
                        color: "transparent"
                        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                        border.width: 1

                        TextInput {
                            id: aliasToInput
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            selectByMouse: true
                            clip: true
                            onAccepted: {
                                root.aliasAdded(aliasFromInput.text, aliasToInput.text);
                                aliasFromInput.text = "";
                                aliasToInput.text = "";
                            }
                        }
                    }

                    Rectangle {
                        id: aliasSaveBox
                        width: aliasSaveLabel.implicitWidth + Style.space(20)
                        height: aliasToInput.implicitHeight + Style.space(14)
                        radius: Style.space(6)
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                        border.color: root.accent
                        border.width: 1

                        Text {
                            id: aliasSaveLabel
                            text: "ADD"
                            color: root.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.aliasAdded(aliasFromInput.text, aliasToInput.text);
                                aliasFromInput.text = "";
                                aliasToInput.text = "";
                            }
                        }
                    }
                }

                Column {
                    id: aliasListCol
                    width: parent.width
                    spacing: Style.space(4)

                    Text {
                        visible: root.aliasEntries.length === 0
                        text: "No renames yet"
                        color: root.foreground
                        opacity: 0.35
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.italic: true
                    }

                    Repeater {
                        model: root.aliasEntries

                        Item {
                            required property var modelData
                            width: aliasListCol.width
                            height: Math.max(aliasName.implicitHeight, aliasRemove.implicitHeight)

                            Text {
                                id: aliasName
                                text: modelData.from + " → " + modelData.to
                                color: root.foreground
                                opacity: 0.75
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                anchors.left: parent.left
                                anchors.right: aliasRemove.left
                                anchors.rightMargin: Style.space(8)
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                            }

                            Text {
                                id: aliasRemove
                                text: "×"
                                color: root.urgent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.title
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            MouseArea {
                                anchors.fill: aliasRemove
                                anchors.margins: -Style.space(6)
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.aliasRemoved(modelData.from)
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Danger zone --------------------------------------------------

    Rectangle {
        width: root.width
        height: dangerBody.implicitHeight + Style.space(24)
        radius: Style.space(8)
        color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.07)
        border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.4)
        border.width: 1

        Column {
            id: dangerBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(10)

            Text {
                text: "DANGER ZONE"
                color: root.urgent
                opacity: 0.9
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.5
            }

            // 3-click reset: arm, confirm, execute. Mouse-leave or 3s
            // disarms. The hint states the blast radius: today only,
            // history is kept.
            Column {
                id: resetRow
                width: parent.width
                spacing: Style.space(6)

                property int stage: 0

                Timer {
                    id: resetRevertTimer
                    interval: 3000
                    repeat: false
                    onTriggered: resetRow.stage = 0
                }

                Column {
                    id: resetLabels
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                        text: "Reset today"
                        color: root.foreground
                        opacity: 0.75
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        width: parent.width
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "Only today is cleared — past days are kept"
                        color: root.foreground
                        opacity: 0.45
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }

                Row {
                    anchors.right: parent.right

                    Rectangle {
                        id: resetBox
                        width: resetState.implicitWidth + Style.space(20)
                        height: resetState.implicitHeight + Style.space(10)
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

            // 4-click wipe: arm, confirm, acknowledge irreversibility,
            // execute. Mouse-leave or 5s disarms. The hint names the full
            // blast radius and the lack of undo, so the wipe is conscious.
            Column {
                id: wipeRow
                width: parent.width
                spacing: Style.space(6)

                property int stage: 0

                Timer {
                    id: wipeRevertTimer
                    interval: 5000
                    repeat: false
                    onTriggered: wipeRow.stage = 0
                }

                Column {
                    id: wipeLabels
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                        text: "Wipe all history"
                        color: root.foreground
                        opacity: 0.75
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        width: parent.width
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "Every day, month and archive — cannot be undone"
                        color: root.urgent
                        opacity: 0.8
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }

                Row {
                    anchors.right: parent.right

                    Rectangle {
                        id: wipeBox
                        width: wipeState.implicitWidth + Style.space(20)
                        height: wipeState.implicitHeight + Style.space(10)
                        radius: Style.space(4)
                        color: wipeRow.stage >= 2 ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.15) : "transparent"
                        border.color: root.urgent
                        border.width: wipeRow.stage >= 2 ? 2 : 1

                        Text {
                            id: wipeState
                            text: wipeRow.stage === 0 ? "WIPE ALL" : wipeRow.stage === 1 ? "SURE?" : wipeRow.stage === 2 ? "NO UNDO!" : "WIPE!"
                            color: root.urgent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                            anchors.centerIn: parent
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (wipeRow.stage >= 3) {
                            wipeRow.stage = 0;
                            wipeRevertTimer.stop();
                            root.wipeRequested();
                        } else {
                            wipeRow.stage++;
                            wipeRevertTimer.restart();
                        }
                    }
                    onContainsMouseChanged: {
                        if (!containsMouse && wipeRow.stage > 0) {
                            wipeRow.stage = 0;
                            wipeRevertTimer.stop();
                        }
                    }
                }
            }
        }
    }
}
// qmllint enable unqualified
