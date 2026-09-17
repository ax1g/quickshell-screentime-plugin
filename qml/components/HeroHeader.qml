import QtQuick
import qs.Commons
import "../../js/Model.js" as Model

// Day total + SHOW MORE/LESS toggle + config gear.

Item {
    id: heroHeader
    required property color foreground
    required property string fontFamily
    // Override for the hourglass glyph; "" follows the foreground.
    required property string heroColor
    required property bool serviceReady
    required property bool expanded
    required property bool calendarOpen
    required property bool calendarEnabled
    required property bool easterEggs
    required property bool configOpen
    required property bool hintMode
    required property color accent
    required property color tipBackground
    required property double dayTotal
    required property string activeDayKey
    required property string activeDayLabel
    // Daily goal progress from Model.goalProgress; null when the goal is off.
    required property var goalProgress

    signal expandToggled
    signal calendarToggled
    signal configToggled

    width: parent.width
    height: implicitHeight
    implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

    // Easter egg: the hourglass is turned exactly on the hour.
    property int lastFlipHour: -1

    Timer {
        id: hourTick
        interval: heroHeader.serviceReady ? Model.msUntilNextHour(Date.now()) : 60000
        repeat: false
        running: heroHeader.serviceReady && heroHeader.easterEggs

        onTriggered: {
            var h = new Date().getHours();
            if (h !== parent.lastFlipHour) {
                parent.lastFlipHour = h;
                heroFlip.restart();
            }
            interval = Model.msUntilNextHour(Date.now());
            restart();
        }
    }

    SequentialAnimation {
        id: heroFlip

        NumberAnimation {
            target: heroIcon
            property: "rotation"
            from: 0
            to: 360
            duration: 700
            easing.type: Easing.OutBack
        }
    }

    // Return-to-main celebration: a full hourglass turn. Reuses the
    // easter-egg flip and mutes with it.
    function spinHourglass() {
        if (heroHeader.easterEggs)
            heroFlip.restart();
    }

    Text {
        id: heroIcon
        text: "󰔟"
        color: heroHeader.heroColor !== "" ? heroHeader.heroColor : (heroIconMouse.containsMouse ? heroHeader.foreground : Qt.darker(heroHeader.foreground, 1.4))
        font.family: heroHeader.fontFamily
        font.pixelSize: Style.fontPx(2.8)
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.top: parent.top
        anchors.topMargin: -Style.space(4)

        MouseArea {
            id: heroIconMouse
            anchors.fill: parent
            anchors.margins: -Style.space(6)
            hoverEnabled: true
            cursorShape: heroHeader.calendarEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (heroHeader.calendarEnabled)
                    heroHeader.calendarToggled();
            }
            onContainsMouseChanged: if (containsMouse && heroHeader.easterEggs)
                sparkles.launch(heroIconMouse.mouseX, heroIconMouse.mouseY)
        }
    }

    HintBadge {
        label: "y"
        fontFamily: heroHeader.fontFamily
        accent: heroHeader.accent
        show: heroHeader.hintMode && heroHeader.calendarEnabled
        anchors.top: heroIcon.top
        anchors.left: heroIcon.left
    }

    // Gold sparkles burst around the cursor on hover-enter.
    Item {
        id: sparkles
        anchors.centerIn: heroIcon
        width: heroIcon.width + Style.space(16)
        height: heroIcon.height + Style.space(10)
        z: 5

        property bool go: false

        function launch(mx, my) {
            var p = mapFromItem(heroIconMouse, mx, my);
            go = false;
            for (var i = 0; i < sparkleRepeater.count; i++)
                sparkleRepeater.itemAt(i).respawn(p.x, p.y);
            go = true;
        }

        // Outer-id reads are idiomatic in delegates; muted for the linter.
        // qmllint disable unqualified
        Repeater {
            id: sparkleRepeater
            model: 6

            Sparkle {
                areaW: sparkles.width
                areaH: sparkles.height
                fontFamily: heroHeader.fontFamily
                go: sparkles.go
            }
        }
        // qmllint enable unqualified
    }

    // Config gear; opens the prefs slide-over drawer.
    Text {
        id: configGear
        text: "\uf013"
        color: configGearMouse.containsMouse || heroHeader.configOpen ? heroHeader.foreground : Qt.darker(heroHeader.foreground, 1.4)
        font.family: heroHeader.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: showMoreCorner.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: showMoreCorner.verticalCenter
    }

    // Gear sweep: a full turn each time settings opens.
    NumberAnimation {
        id: gearSpin
        target: configGear
        property: "rotation"
        from: 0
        to: 360
        duration: 450
        easing.type: Easing.OutBack
    }

    MouseArea {
        id: configGearMouse
        anchors.fill: configGear
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (heroHeader.easterEggs)
                gearSpin.restart();
            heroHeader.configToggled();
        }

        // Parented to the gear's own hit area so the tip centers
        // above the icon, not above the full-width header.
        ScreenTip {
            foreground: heroHeader.foreground
            fontFamily: heroHeader.fontFamily
            tipBackground: heroHeader.tipBackground

            hovered: configGearMouse.containsMouse
            tipText: "Settings"
        }
    }

    HintBadge {
        label: "c"
        fontFamily: heroHeader.fontFamily
        accent: heroHeader.accent
        show: heroHeader.hintMode
        anchors.top: configGear.top
        anchors.right: configGear.right
    }

    Row {
        id: showMoreCorner
        spacing: Style.space(4)
        anchors.right: parent.right
        anchors.top: parent.top

        Text {
            text: heroHeader.expanded ? "SHOW LESS" : "SHOW MORE"
            color: showMoreCornerMouse.containsMouse ? heroHeader.foreground : Qt.darker(heroHeader.foreground, 1.4)
            font.family: heroHeader.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: heroHeader.expanded ? "\u25be" : "\u25b8"
            color: showMoreCornerMouse.containsMouse ? heroHeader.foreground : Qt.darker(heroHeader.foreground, 1.4)
            font.family: heroHeader.fontFamily
            font.pixelSize: Style.font.title
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: showMoreCornerMouse
        anchors.fill: showMoreCorner
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: heroHeader.expandToggled()
    }

    HintBadge {
        label: "m"
        fontFamily: heroHeader.fontFamily
        accent: heroHeader.accent
        show: heroHeader.hintMode
        anchors.top: showMoreCorner.top
        anchors.right: showMoreCorner.right
    }

    Column {
        id: heroLabels
        anchors.left: heroIcon.right
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.rightMargin: showMoreCorner.implicitWidth + configGear.implicitWidth + Style.space(24)
        anchors.top: parent.top
        spacing: 0

        Text {
            text: heroHeader.dayTotal > 0 ? Model.fmt(heroHeader.dayTotal) : "0m"
            color: heroHeader.foreground
            font.family: heroHeader.fontFamily
            font.pixelSize: Style.fontPx(1.5)
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
        }

        Text {
            text: heroHeader.activeDayKey ? heroHeader.activeDayLabel + ", " + String(heroHeader.activeDayKey).split("-")[0] : ""
            color: Qt.darker(heroHeader.foreground, 1.4)
            font.family: heroHeader.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
        }

        // Daily goal progress: thin bar plus a remaining/reached caption.
        // Hidden entirely while the goal is off (goalProgress null). The
        // spacer keeps the goal block breathing room below the date line.
        Item {
            visible: heroHeader.goalProgress !== null
            width: parent.width
            height: visible ? Style.space(4) : 0
        }

        Rectangle {
            visible: heroHeader.goalProgress !== null
            width: parent.width
            height: 3
            radius: 1.5
            color: Qt.rgba(heroHeader.foreground.r, heroHeader.foreground.g, heroHeader.foreground.b, 0.15)

            Rectangle {
                width: parent.width * (heroHeader.goalProgress ? heroHeader.goalProgress.pct / 100 : 0)
                height: parent.height
                radius: parent.radius
                color: heroHeader.goalProgress && heroHeader.goalProgress.reached ? heroHeader.foreground : Qt.rgba(heroHeader.foreground.r, heroHeader.foreground.g, heroHeader.foreground.b, 0.55)
            }
        }

        Text {
            visible: heroHeader.goalProgress !== null
            text: heroHeader.goalProgress ? (heroHeader.goalProgress.reached ? "Daily goal reached" : Model.fmt(heroHeader.goalProgress.remainingMs) + " left of " + Model.fmt(heroHeader.goalProgress.goalMs) + " goal") : ""
            color: Qt.darker(heroHeader.foreground, 1.4)
            font.family: heroHeader.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
        }
    }
}
