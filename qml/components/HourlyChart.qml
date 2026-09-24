import QtQuick
import qs.Commons

// Experimental hourly rhythm: one square bar per local hour, sized
// against the peak hour. Bars account for exactly the recorded time,
// like the strip above; missing hours simply have no bar. Peak label
// names the busiest hour. Hidden entirely without recorded spans.
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

        Text {
            id: expTag
            text: "· EXPERIMENTAL"
            color: root.accent
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.5
            anchors.verticalCenter: parent.verticalCenter
        }

        Item {
            width: parent.width - hourlyTitle.width - expTag.width - peakLabel.width
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

    Item {
        id: bars
        width: parent.width
        height: Style.space(48)

        Row {
            anchors.fill: parent
            spacing: 2

            Repeater {
                model: root.hours

                Item {
                    required property var modelData
                    width: (bars.width - 23 * 2) / 24
                    height: bars.height

                    Rectangle {
                        width: parent.width
                        height: root.maxMs > 0 ? bars.height * Number(modelData.ms || 0) / root.maxMs : 0
                        anchors.bottom: parent.bottom
                        color: root.accent
                        opacity: 0.85
                    }
                }
            }
        }
    }

    // Hour ticks centered on their bars; edge labels clamp inside.
    Item {
        id: ticks
        width: parent.width
        height: tickLabel0.implicitHeight

        Repeater {
            model: [
                {
                    frac: 0.5 / 24,
                    label: "00"
                },
                {
                    frac: 6.5 / 24,
                    label: "06"
                },
                {
                    frac: 12.5 / 24,
                    label: "12"
                },
                {
                    frac: 18.5 / 24,
                    label: "18"
                }
            ]

            Text {
                required property var modelData
                text: modelData.label
                color: root.foreground
                opacity: 0.4
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                width: implicitWidth
                x: Math.max(0, Math.min(ticks.width - width, ticks.width * Number(modelData.frac || 0) - width / 2))
            }
        }

        Text {
            id: tickLabel0
            visible: false
            text: "00"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
        }
    }
}
