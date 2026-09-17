import QtQuick
import qs.Commons

// BACK corner action: glyph + label with hover highlight.
Item {
    id: action
    required property color foreground
    required property string fontFamily
    // Empty text means no tip; same opt-in idiom as PagerArrow.
    property string tipText: ""
    property color tipBackground: "transparent"
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

    ScreenTip {
        foreground: action.foreground
        fontFamily: action.fontFamily
        tipBackground: action.tipBackground

        hovered: actionMouse.containsMouse && action.tipText !== ""
        tipText: action.tipText
    }
}
