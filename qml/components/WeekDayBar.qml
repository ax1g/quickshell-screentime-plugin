import QtQuick
import qs.Commons
import "../../js/Model.js" as Model

// One week-chart day column: bar + weekday label.
// Outer reads are layout-parent geometry; muted file-wide like Service.
// qmllint disable unqualified

Item {
    id: day
    required property var modelData
    required property string activeDayKey
    required property double axisMaxMs
    required property color foreground
    required property color accent
    required property string fontFamily

    signal selected(string key)

    width: (parent.width - parent.spacing * 6) / 7
    height: Style.space(80)

    property bool isActive: modelData.key === day.activeDayKey
    property bool isFuture: modelData.isFuture
    property bool isEmpty: !isFuture && modelData.ms <= 0
    property bool hasData: !isFuture && !isEmpty && day.axisMaxMs > 0
    property real barPx: hasData ? Math.max(3, Style.space(64) * Number(modelData.ms) / day.axisMaxMs) : 0

    Rectangle {
        width: parent.width * 0.5
        radius: Style.space(2)
        color: (parent.isFuture || parent.isEmpty) ? Qt.rgba(day.foreground.r, day.foreground.g, day.foreground.b, 0.10) : (parent.isActive ? day.accent : (barMouse.containsMouse ? Qt.lighter(day.foreground, 1.4) : Qt.rgba(day.foreground.r, day.foreground.g, day.foreground.b, 0.9)))
        opacity: 1.0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(14)
        height: parent.barPx

        MouseArea {
            id: barMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !parent.parent.isFuture && !parent.parent.isEmpty
            cursorShape: Qt.PointingHandCursor
            onClicked: day.selected(day.modelData.key)
        }
    }

    Text {
        text: day.modelData.label
        color: day.foreground
        opacity: (parent.isActive || (!parent.isFuture && day.modelData.ms > 0)) ? 1.0 : 0.45
        font.family: day.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: parent.isActive
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        anchors.bottom: parent.bottom
    }
}
