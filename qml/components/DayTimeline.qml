import QtQuick
import qs.Commons
import "../../js/Model.js" as Model

// Session timeline: one bar per focus span at its position in the user
// session (first span to last), colored by category, with session ticks
// and exact times on hover. Bars size relative to the session: the first
// span fills the strip and earlier spans shrink as later usage extends
// it. Gaps are honest: lock and untracked time leave the track empty.
// Spans record from this version on, so older days keep totals only.
// Outer-id reads are idiomatic in delegates; muted for the linter.
// qmllint disable unqualified

Column {
    id: root
    required property var segments
    required property var categories
    required property var axis
    required property double dayTotal
    required property color foreground
    required property string fontFamily
    required property color tipBackground

    width: parent.width
    spacing: Style.space(8)

    Row {
        width: parent.width

        Text {
            id: timelineTitle
            text: "DAY TIMELINE"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.5
        }

        Item {
            width: parent.width - timelineTitle.width - dayTotalLabel.width
            height: parent.height
        }

        Text {
            id: dayTotalLabel
            text: Model.fmt(root.dayTotal)
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
        }
    }

    Rectangle {
        id: strip
        width: parent.width
        height: Style.space(36)
        // Square track by design: the strip spans the full session width,
        // so rounded ends would fake padding where time is recorded.
        radius: 0
        clip: true
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

        Repeater {
            model: root.segments

            Rectangle {
                id: segment
                required property var modelData
                x: strip.width * Number(modelData.startFrac || 0)
                width: Math.max(2, strip.width * (Number(modelData.endFrac || 0) - Number(modelData.startFrac || 0)))
                height: strip.height
                color: modelData.color || "transparent"

                MouseArea {
                    id: segmentMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                }

                // Exact app and clock range on dwell.
                ScreenTip {
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    tipBackground: root.tipBackground

                    hovered: segmentMouse.containsMouse
                    tipText: segment.modelData.category + " \u00b7 " + Model.displayName(segment.modelData.app) + " \u00b7 " + Model.fmtClock(segment.modelData.start) + "\u2013" + Model.fmtClock(segment.modelData.end) + " \u00b7 " + Model.fmt(segment.modelData.ms)
                }
            }
        }
    }

    // Session axis under the track; edge labels clamp inside.
    Item {
        id: axis
        width: parent.width
        height: axisLabel0.implicitHeight

        Repeater {
            model: root.axis

            Text {
                id: axisLabel
                required property var modelData
                text: modelData.label
                color: root.foreground
                opacity: 0.4
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                width: implicitWidth
                x: Math.max(0, Math.min(axis.width - width, axis.width * Number(modelData.frac || 0) - width / 2))
            }
        }

        // Named for the axis height above; hidden, never painted.
        Text {
            id: axisLabel0
            visible: false
            text: "00:00"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
        }
    }

    // One row per category present in the spans, most-used first.
    Column {
        width: parent.width
        spacing: Style.space(4)
        visible: root.categories.length > 0

        Repeater {
            model: root.categories

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
                    text: Model.fmt(legendRow.modelData.ms)
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

    // Span-less days (older history, empty days) keep totals only.
    Text {
        visible: root.categories.length === 0
        text: "Timeline records from here on — earlier time keeps totals only"
        color: root.foreground
        opacity: 0.4
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        width: parent.width
        wrapMode: Text.WordWrap
    }
}
