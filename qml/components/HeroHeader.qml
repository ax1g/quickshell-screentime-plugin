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
    required property double dayTotal
    required property string activeDayKey
    required property string activeDayLabel

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

    Text {
        id: heroIcon
        text: "󰔟"
        color: heroHeader.heroColor !== "" ? heroHeader.heroColor : heroHeader.foreground
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

    MouseArea {
        id: configGearMouse
        anchors.fill: configGear
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: heroHeader.configToggled()
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
    }
}
