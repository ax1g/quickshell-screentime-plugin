import QtQuick
import qs.Commons

// Hint-mode key badge in the selected-pill idiom: solid accent box with
// a bold letter. Zero-size while hidden so panel geometry never shifts
// under it. Positioned by the parent, near its pressable's corner; it
// owns no MouseArea so clicks pass straight through.
Item {
    id: root
    required property string label
    required property string fontFamily
    required property color accent
    required property color foreground
    required property bool show

    visible: root.show
    implicitWidth: hintLabel.implicitWidth + Style.space(10)
    implicitHeight: hintLabel.implicitHeight + Style.space(4)
    width: visible ? implicitWidth : 0
    height: visible ? implicitHeight : 0

    Rectangle {
        anchors.fill: parent
        radius: Style.space(3)
        color: root.accent

        Text {
            id: hintLabel
            text: root.label
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.centerIn: parent
        }
    }
}
