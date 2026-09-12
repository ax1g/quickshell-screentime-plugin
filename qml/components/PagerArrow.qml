import QtQuick
import qs.Commons

// Pager glyph with hover highlight and disabled fade.
Text {
    id: arrow
    required property string glyph
    required property bool active
    required property color foreground
    required property string fontFamily
    required property int fontSize
    signal clicked

    text: arrow.glyph
    color: arrowMouse.enabled && arrowMouse.containsMouse ? arrow.foreground : Qt.darker(arrow.foreground, 1.4)
    opacity: arrowMouse.enabled ? 1.0 : 0.25
    Behavior on opacity {
        NumberAnimation {
            duration: 150
        }
    }
    font.family: arrow.fontFamily
    font.pixelSize: arrow.fontSize
    anchors.verticalCenter: parent.verticalCenter

    MouseArea {
        id: arrowMouse
        anchors.fill: parent
        anchors.margins: -Style.space(6)
        hoverEnabled: true
        enabled: arrow.active
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: arrow.clicked()
    }
}
