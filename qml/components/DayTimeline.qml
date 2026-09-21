import QtQuick
import qs.Commons
import "../../js/Model.js" as Model

// Day timeline demo strip (v2.0 preview): color-coded category blocks for
// the active day, below the donut. Proportional demo: widths are each
// category's share of the day (history stores totals, no timestamps yet).
// Blocks carry their own color, so delegates pair nothing by position.
// Outer-id reads are idiomatic in delegates; muted for the linter.
// qmllint disable unqualified

Column {
    id: root
    required property var blocks
    required property color foreground
    required property string fontFamily
    required property color tipBackground
    required property double dayTotal

    width: parent.width
    spacing: Style.space(8)

    Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
            text: "DAY TIMELINE"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.5
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: demoLabel.implicitWidth + Style.space(12)
            height: demoLabel.implicitHeight + Style.space(4)
            radius: Style.space(4)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

            Text {
                id: demoLabel
                text: "DEMO"
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.centerIn: parent
            }
        }
    }

    Rectangle {
        id: strip
        width: parent.width
        height: Style.space(14)
        radius: Style.space(7)
        clip: true
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

        Row {
            anchors.fill: parent
            spacing: 0

            Repeater {
                model: root.blocks

                Rectangle {
                    id: block
                    required property var modelData
                    width: Math.max(0, strip.width * Number(modelData.frac || 0))
                    height: strip.height
                    color: modelData.color || "transparent"

                    MouseArea {
                        id: blockMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: Number(block.modelData.ms || 0) > 0
                    }

                    // Exact time on dwell, like the week bars.
                    ScreenTip {
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        tipBackground: root.tipBackground

                        hovered: blockMouse.containsMouse
                        tipText: block.modelData.category + " \u00b7 " + Model.fmt(block.modelData.ms) + " (" + block.modelData.pct + "%)"
                    }
                }
            }
        }
    }

    Column {
        width: parent.width
        spacing: Style.space(4)

        Repeater {
            model: root.blocks

            Item {
                id: legendRow
                required property var modelData
                width: parent.width
                height: Math.max(dot.height, legendLabel.implicitHeight)

                Rectangle {
                    id: dot
                    width: Style.space(8)
                    height: Style.space(8)
                    radius: Style.space(4)
                    color: legendRow.modelData.color || "transparent"
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    id: legendLabel
                    text: legendRow.modelData.category
                    color: root.foreground
                    opacity: 0.75
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    anchors.left: dot.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: legendTime.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                }

                Text {
                    id: legendTime
                    text: Model.fmt(legendRow.modelData.ms) + " \u00b7 " + legendRow.modelData.pct + "%"
                    color: root.foreground
                    opacity: 0.45
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
