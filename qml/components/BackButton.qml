import QtQuick
import qs.Commons

// BACK corner action: glyph + label with hover highlight.
Item {
    id: action
    required property color foreground
    required property string fontFamily
    signal clicked

    width: row.implicitWidth
    height: row.implicitHeight

    Row {
        id: row
        anchors.fill: parent
        spacing: Style.space(4)

        Text {
            text: "\u25c2"
            color: actionMouse.containsMouse ? action.foreground : Qt.darker(action.foreground, 1.4)
            font.family: action.fontFamily
            font.pixelSize: Style.font.title
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: "BACK"
            color: actionMouse.containsMouse ? action.foreground : Qt.darker(action.foreground, 1.4)
            font.family: action.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: actionMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: action.clicked()
    }
}
