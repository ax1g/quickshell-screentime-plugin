import QtQuick
import qs.Commons
import "../../js/Model.js" as Model

// Hourly rhythm: one column per local hour, like the week chart's day
// columns. Bars size against the peak hour with the same 64px column
// geometry (3px minimum); each column carries its hour label, dimmed
// without recorded time, and the exact total on dwell. The peak column
// takes the accent like the week's selected day. Hidden entirely
// without recorded spans.
// Outer-id reads are idiomatic in delegates; muted for the linter.
// qmllint disable unqualified

Column {
    id: root
    required property var hours
    required property double maxMs
    required property int peakHour
    required property color accent
    required property color foreground
    required property string fontFamily
    required property color tipBackground

    width: parent.width
    spacing: Style.space(8)
    visible: root.maxMs > 0

    Row {
        width: parent.width

        Text {
            id: hourlyTitle
            text: "HOURLY RHYTHM"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.5
        }

        Item {
            width: parent.width - hourlyTitle.width - peakLabel.width
            height: parent.height
        }

        Text {
            id: peakLabel
            text: root.peakHour >= 0 ? "PEAK " + (root.peakHour < 10 ? "0" : "") + root.peakHour + ":00" : ""
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
        }
    }

    Row {
        width: parent.width
        spacing: 0

        Repeater {
            model: root.hours

            Item {
                required property var modelData
                width: parent.width / 24
                height: Style.space(80)

                readonly property int hour: Number(modelData.hour || 0)
                readonly property double ms: Number(modelData.ms || 0)
                readonly property bool hasData: root.maxMs > 0 && ms > 0
                readonly property string hourText: (hour < 10 ? "0" : "") + hour
                readonly property real barPx: hasData ? Math.max(3, Style.space(64) * ms / root.maxMs) : 0

                Rectangle {
                    width: parent.width * 0.5
                    radius: Style.space(2)
                    color: hour === root.peakHour ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.9)
                    opacity: 1.0
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: hourLabel.top
                    anchors.bottomMargin: Style.space(2)
                    height: barPx

                    MouseArea {
                        id: hourMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: hasData
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }

                    // Exact total on dwell, like the week bars.
                    ScreenTip {
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        tipBackground: root.tipBackground

                        hovered: hourMouse.containsMouse
                        tipText: hourText + " \u00b7 " + Model.fmt(ms)
                    }
                }

                Text {
                    id: hourLabel
                    // Every third hour labels the columns; all 24 would
                    // collide in panel width, like weekday labels never do.
                    text: hour % 3 === 0 ? hourText : ""
                    color: root.foreground
                    opacity: hasData ? 1.0 : 0.45
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: hour === root.peakHour
                    width: parent.width
                    height: Style.space(14)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    anchors.bottom: parent.bottom
                }
            }
        }
    }
}
