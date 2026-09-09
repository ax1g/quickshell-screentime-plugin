import QtQuick
import qs.Commons

// One gold sparkle; the parent triggers respawn() around the cursor.
// Outer reads are layout-parent geometry; muted file-wide like Service.
// qmllint disable unqualified

Text {
    id: sparkle
    required property int index
    required property real areaW
    required property real areaH
    required property string fontFamily
    required property bool go

    text: "\u2726"
    color: "#FFD700"
    font.family: sparkle.fontFamily
    font.pixelSize: Style.font.caption
    opacity: 0
    scale: 1

    property real drift: Style.space(8)

    function respawn(cx, cy) {
        var spreadX = sparkle.areaW * 0.22;
        var spreadY = sparkle.areaH * 0.3;
        x = Math.max(2, Math.min(sparkle.areaW - 2, cx + (Math.random() * 2 - 1) * spreadX));
        y = Math.max(sparkle.areaH * 0.2, Math.min(sparkle.areaH * 0.85, cy + (Math.random() * 2 - 1) * spreadY));
        font.pixelSize = Style.font.caption * (0.65 + Math.random() * 0.85);
        drift = Style.space(6) + Style.space(10) * Math.random();
    }

    SequentialAnimation {
        running: sparkle.go
        PauseAnimation {
            duration: sparkle.index * 80
        }
        NumberAnimation {
            target: sparkle
            property: "opacity"
            from: 0
            to: 0.85
            duration: 180
        }
        ParallelAnimation {
            NumberAnimation {
                target: sparkle
                property: "y"
                from: sparkle.y
                to: sparkle.y - sparkle.drift
                duration: 650
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: sparkle
                property: "opacity"
                from: 0.85
                to: 0
                duration: 650
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: sparkle
                property: "scale"
                from: 1
                to: 0.6
                duration: 650
            }
        }
    }
}
