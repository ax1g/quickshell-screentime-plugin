import QtQuick
import qs.Commons
import "../../js/Model.js" as Model

// Legend row: color swatch + app name + time.
// Outer reads are layout-parent geometry; muted file-wide like Service.
// qmllint disable unqualified

Item {
    id: row
    required property var modelData
    // Repeater auto-supplies by name (like modelData); swatchColor reads it.
    required property int index
    required property bool expanded
    required property int groupedCount
    required property var sliceColors
    required property color otherColor
    required property color foreground
    required property string fontFamily
    required property color accent

    readonly property string appName: String(modelData.app || "")
    readonly property string appLabel: Model.displayName(modelData.app)
    readonly property string timeLabel: Model.fmt(modelData.ms)
    // Top apps keep the grouped palette; rows folded into
    // "Other" share that slice's color.
    readonly property color swatchColor: row.expanded && row.index >= row.groupedCount - 1 ? row.otherColor : (row.sliceColors[row.index] || row.accent)

    width: parent.width
    implicitHeight: Math.max(swatch.implicitHeight, Math.max(appNameText.implicitHeight, appTimeText.implicitHeight))

    Rectangle {
        id: swatch
        width: Style.space(7)
        height: width
        radius: width / 2
        color: row.swatchColor
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
    }

    Text {
        id: appNameText
        text: row.appLabel
        color: row.foreground
        opacity: 0.6
        font.family: row.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        width: parent.width - appTimeText.implicitWidth - Style.space(8)
        anchors.left: swatch.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
    }

    Text {
        id: appTimeText
        text: row.timeLabel
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
    }
}
