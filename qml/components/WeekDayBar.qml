import QtQuick
import qs.Commons

// One week-chart day column: bar, weekday label, floating hint.
// The column is just the bar above the 14px label hugging the
// bottom, so the axis gridlines track bar bottoms in every mode.
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
    required property bool hintMode
    required property int dayNumber

    signal selected(string key)

    // Parent Row spacing is 0; one seventh of its width per day.
    width: parent.width / 7
    height: Style.space(80)

    property bool isActive: modelData.key === day.activeDayKey
    property bool isFuture: modelData.isFuture
    property bool isEmpty: !isFuture && modelData.ms <= 0
    property bool hasData: !isFuture && !isEmpty && day.axisMaxMs > 0
    property real barPx: hasData ? Math.max(3, Style.space(64) * Number(modelData.ms) / day.axisMaxMs) : 0

    Rectangle {
        width: day.width * 0.5
        radius: Style.space(2)
        color: (day.isFuture || day.isEmpty) ? Qt.rgba(day.foreground.r, day.foreground.g, day.foreground.b, 0.10) : (day.isActive ? day.accent : (barMouse.containsMouse ? Qt.lighter(day.foreground, 1.4) : Qt.rgba(day.foreground.r, day.foreground.g, day.foreground.b, 0.9)))
        opacity: 1.0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: weekdayLabel.top
        anchors.bottomMargin: Style.space(2)
        height: day.barPx

        MouseArea {
            id: barMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !day.isFuture && !day.isEmpty
            cursorShape: Qt.PointingHandCursor
            onClicked: day.selected(day.modelData.key)
        }
    }

    Text {
        id: weekdayLabel
        text: day.modelData.label
        color: day.foreground
        opacity: (day.isActive || (!day.isFuture && day.modelData.ms > 0)) ? 1.0 : 0.45
        font.family: day.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: day.isActive
        width: day.width
        height: Style.space(14)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        anchors.bottom: parent.bottom
    }

    // Number hint floats above the label, over whatever the bar
    // occupies; the column reserves no slot for it.
    HintBadge {
        label: String(day.dayNumber)
        fontFamily: day.fontFamily
        accent: day.accent
        show: day.hintMode && !day.isFuture && !day.isEmpty
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: weekdayLabel.top
        anchors.bottomMargin: Style.space(2)
    }
}
