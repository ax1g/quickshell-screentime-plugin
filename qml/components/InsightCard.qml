import QtQuick
import qs.Commons

// Fact card; height fits content so neighbours never stretch it.
Rectangle {
    id: insightCard
    required property var modelData
    required property color foreground
    required property string fontFamily

    readonly property string glyph: String(modelData.glyph || "")
    readonly property string label: String(modelData.label || "")
    readonly property string stat: String(modelData.value || "")
    readonly property string oneLiner: String(modelData.sub || "")
    readonly property string accent: String(modelData.color || Color.accent)

    width: parent.width
    implicitHeight: cardColumn.implicitHeight + Style.space(20)
    height: implicitHeight
    radius: Style.space(6)
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.06)
    border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
    border.width: 1

    Column {
        id: cardColumn
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.top: parent.top
        anchors.topMargin: Style.space(10)
        spacing: Style.space(2)

        Row {
            width: parent.width
            spacing: Style.space(4)

            Text {
                text: insightCard.glyph
                color: insightCard.accent
                font.family: insightCard.fontFamily
                font.pixelSize: Style.font.icon
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: insightCard.label
                color: insightCard.foreground
                opacity: 0.6
                font.family: insightCard.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                wrapMode: Text.Wrap
                width: parent.width - Style.space(18)
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            id: cardStat
            // Rich text so values can carry inline markup (the TOP
            // MONTHS medals); plain values render exactly as before.
            textFormat: Text.RichText
            text: insightCard.stat
            color: insightCard.foreground
            font.family: insightCard.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            width: parent.width
            wrapMode: Text.Wrap
        }

        Text {
            text: insightCard.oneLiner
            color: insightCard.foreground
            opacity: 0.5
            font.family: insightCard.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.Wrap
        }
    }
}
