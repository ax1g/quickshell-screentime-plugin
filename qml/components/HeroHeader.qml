import QtQuick
import qs.Commons
import "../../js/Model.js" as Model

// ---- Hero: today's total, SHOW MORE/LESS toggle top-right ------

Item {
    id: heroHeader
    required property color foreground
    required property string fontFamily
    required property bool serviceReady
    required property bool expanded
    required property bool calendarOpen
    required property double dayTotal
    required property string activeDayKey
    required property string activeDayLabel

    signal expandToggled
    signal calendarToggled

    width: parent.width
    height: implicitHeight
    implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

    // Easter egg: the hourglass is turned exactly on the hour.
    property int lastFlipHour: -1

    Timer {
        id: hourTick
        interval: heroHeader.serviceReady ? Model.msUntilNextHour(Date.now()) : 60000
        repeat: false
        running: heroHeader.serviceReady

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
        color: heroHeader.foreground
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
            cursorShape: Qt.PointingHandCursor
            onClicked: heroHeader.calendarToggled()
            onContainsMouseChanged: if (containsMouse)
                sparkles.launch(heroIconMouse.mouseX, heroIconMouse.mouseY)
        }
    }

    // Hover sparkles: tiny stars burst around the cursor over the
    // hourglass, drift upward and fade out. Positions and sizes are
    // re-randomised on every hover-enter.
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

        // Delegate reads outer ids (idiomatic QML); silence the
        // linter for that documented pattern.
        // qmllint disable unqualified
        Repeater {
            id: sparkleRepeater
            model: 6

            Text {
                id: sp
                required property int index

                text: "\u2726"
                color: "#FFD700"
                font.family: heroHeader.fontFamily
                font.pixelSize: Style.font.caption
                opacity: 0
                scale: 1

                property real drift: Style.space(8)

                function respawn(cx, cy) {
                    var spreadX = sparkles.width * 0.22;
                    var spreadY = sparkles.height * 0.3;
                    x = Math.max(2, Math.min(sparkles.width - 2, cx + (Math.random() * 2 - 1) * spreadX));
                    y = Math.max(sparkles.height * 0.2, Math.min(sparkles.height * 0.85, cy + (Math.random() * 2 - 1) * spreadY));
                    font.pixelSize = Style.font.caption * (0.65 + Math.random() * 0.85);
                    drift = Style.space(6) + Style.space(10) * Math.random();
                }

                SequentialAnimation {
                    running: sparkles.go
                    PauseAnimation {
                        duration: sp.index * 80
                    }
                    NumberAnimation {
                        target: sp
                        property: "opacity"
                        from: 0
                        to: 0.85
                        duration: 180
                    }
                    ParallelAnimation {
                        NumberAnimation {
                            target: sp
                            property: "y"
                            from: sp.y
                            to: sp.y - sp.drift
                            duration: 650
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: sp
                            property: "opacity"
                            from: 0.85
                            to: 0
                            duration: 650
                            easing.type: Easing.InQuad
                        }
                        NumberAnimation {
                            target: sp
                            property: "scale"
                            from: 1
                            to: 0.6
                            duration: 650
                        }
                    }
                }
            }
        }
        // qmllint enable unqualified
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
        anchors.rightMargin: showMoreCorner.implicitWidth + Style.space(12)
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
