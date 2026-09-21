import QtQuick
import qs.Commons

// Segmented pills switching one view in place (year bars/heatmap, day
// apps/timeline). Callers persist the pick; this only renders and emits.
// One hint badge floats over the row corner when hintTag is set.
// qmllint disable unqualified

Item {
    id: root
    required property var options
    required property string current
    required property color foreground
    required property string fontFamily
    required property color accent
    required property bool hintMode
    property string hintTag: ""

    signal selected(string key)

    width: pillsRow.width
    height: pillsRow.height

    Row {
        id: pillsRow
        spacing: Style.space(6)

        Repeater {
            model: root.options

            Rectangle {
                id: pill
                required property var modelData
                readonly property bool chosen: modelData.key === root.current
                width: pillLabel.implicitWidth + Style.space(20)
                height: Style.space(28)
                radius: Style.space(4)
                color: chosen ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15) : "transparent"
                border.color: chosen ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                border.width: 1

                Text {
                    id: pillLabel
                    text: pill.modelData.label
                    color: pill.chosen ? root.accent : root.foreground
                    opacity: pill.chosen ? 1.0 : 0.6
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: pill.chosen
                    anchors.centerIn: parent
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selected(pill.modelData.key)
                }
            }
        }
    }

    HintBadge {
        label: root.hintTag
        fontFamily: root.fontFamily
        accent: root.accent
        show: root.hintMode && root.hintTag !== ""
        anchors.top: parent.top
        anchors.right: parent.right
    }
}
