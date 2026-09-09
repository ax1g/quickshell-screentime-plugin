import QtQuick
import qs.Commons
import "../../js/Model.js" as Model

// Swatch rows for the donut; fixed height keeps the panel size stable.
Item {
    id: legend
    required property var rows
    required property bool expanded
    required property int groupedCount
    required property var sliceColors
    required property color otherColor
    required property color foreground
    required property string fontFamily
    required property color accent
    required property real maxHeight

    width: parent.width
    height: maxHeight

    // Restart at the top when the model swaps.
    onExpandedChanged: legendScroll.contentY = 0

    Flickable {
        id: legendScroll
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: legendList.implicitHeight
        height: legend.maxHeight
        interactive: contentHeight > height
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: legendList
            width: parent.width - Style.space(8)
            spacing: Style.space(5)
            // Center short lists; long lists scroll from top.
            y: Math.max(0, (legendScroll.height - implicitHeight) / 2)

            Text {
                visible: legend.groupedCount === 0
                text: "No data"
                color: legend.foreground
                opacity: 0.4
                font.family: legend.fontFamily
                font.pixelSize: Style.font.bodySmall
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }

            // Outer-id reads are idiomatic in delegates; muted for the linter.
            // qmllint disable unqualified
            Repeater {
                model: legend.rows

                Item {
                    id: rowDelegate
                    required property var modelData
                    required property int index

                    readonly property string appName: String(modelData.app || "")
                    readonly property string appLabel: Model.displayName(modelData.app)
                    readonly property string timeLabel: Model.fmt(modelData.ms)
                    // Top apps keep the grouped palette; rows folded into
                    // "Other" share that slice's color.
                    readonly property color swatchColor: legend.expanded && rowDelegate.index >= legend.groupedCount - 1 ? legend.otherColor : (legend.sliceColors[rowDelegate.index] || legend.accent)

                    width: parent.width
                    implicitHeight: Math.max(swatch.implicitHeight, Math.max(appNameText.implicitHeight, appTimeText.implicitHeight))

                    Rectangle {
                        id: swatch
                        width: Style.space(7)
                        height: width
                        radius: width / 2
                        color: rowDelegate.swatchColor
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        id: appNameText
                        text: rowDelegate.appLabel
                        color: legend.foreground
                        opacity: 0.6
                        font.family: legend.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                        width: parent.width - appTimeText.implicitWidth - Style.space(8)
                        anchors.left: swatch.right
                        anchors.leftMargin: Style.space(6)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        id: appTimeText
                        text: rowDelegate.timeLabel
                        color: legend.foreground
                        font.family: legend.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                    }
                }
            }
            // qmllint enable unqualified
        }
    }

    // Thin scrollbar indicator on the right edge.
    Rectangle {
        property real ratio: legendScroll.contentHeight > 0 ? legendScroll.height / legendScroll.contentHeight : 0
        visible: legendScroll.contentHeight > legendScroll.height
        width: 2
        height: Math.max(Style.space(16), legendScroll.height * ratio)
        radius: width / 2
        color: legend.foreground
        opacity: 0.25
        anchors.right: legendScroll.right
        y: legendScroll.y + (legendScroll.height - height) * (legendScroll.contentHeight > legendScroll.height ? legendScroll.contentY / (legendScroll.contentHeight - legendScroll.height) : 0)
    }
}
