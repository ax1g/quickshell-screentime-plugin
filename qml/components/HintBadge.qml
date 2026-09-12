import QtQuick
import qs.Commons

// Hint-mode key badge: solid accent box with ink picked from the
// accent's own lightness, so the letter reads on any theme (white
// vanishes on gold). Zero-size while hidden so panel geometry never
// shifts under it. Positioned by the parent, near its pressable's
// corner; it floats above siblings (top z) and owns no MouseArea,
// so clicks pass straight through.
Item {
    id: root
    required property string label
    required property string fontFamily
    required property color accent
    required property bool show

    z: 9999999
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
            color: root.accent.hslLightness >= 0.45 ? "#232323" : "#f2f2f2"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.centerIn: parent
        }
    }
}
