import QtQuick
import qs.Commons
import "../../js/Model.js" as Model

// Week-chart axis tick: gridline + whole-hour label.
// Outer reads are layout-parent geometry; muted file-wide like Service.
// qmllint disable unqualified

Item {
    id: tick
    required property double modelData
    required property double axisMaxMs
    required property color foreground
    required property string fontFamily

    width: parent.width
    height: 1
    z: 1
    // Bottom offset mirrors the day delegate's stack below the bars:
    // badge slot 20 + number 12 + weekday label 14 + 2px bar gap.
    y: tick.axisMaxMs > 0 ? (parent.height - Style.space(16) - Style.space(64) * Number(tick.modelData) / tick.axisMaxMs) : parent.height

    // Gridlines stop before the y-axis labels.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: Style.space(26)
        height: 1
        color: Qt.rgba(tick.foreground.r, tick.foreground.g, tick.foreground.b, 0.06)
    }

    Text {
        text: Model.fmtWholeHours(tick.modelData)
        color: Qt.darker(tick.foreground, 1.35)
        font.family: tick.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: false
        width: Style.space(20)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(2)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
    }
}
