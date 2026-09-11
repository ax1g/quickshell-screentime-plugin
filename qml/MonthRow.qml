import QtQuick
import qs.Commons
import "components"
import "../js/Model.js" as Model

// One year-overview month row: label, share bar, hour total.

Item {
    id: month
    required property int index
    required property var months
    required property double maxMs
    required property var monthShort
    required property var monthLong
    required property bool isThisYear
    required property int nowMonth
    required property real gridWidth
    required property real hoursW
    required property color foreground
    required property string fontFamily
    required property color panelBackground
    required property color accent

    readonly property real labelW: Style.space(26)
    readonly property real labelGap: Style.space(4)
    readonly property bool isCurrentMonth: month.isThisYear && month.index === month.nowMonth
    readonly property real availW: month.gridWidth - month.labelW - month.labelGap - month.hoursW - month.labelGap
    readonly property real ratio: month.maxMs > 0 ? (month.months[month.index] ? month.months[month.index].ms / month.maxMs : 0) : 0

    width: month.gridWidth
    height: Style.space(12)

    Text {
        text: month.monthShort[month.index]
        color: month.foreground
        opacity: month.isCurrentMonth ? 1.0 : 0.55
        font.family: month.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: month.isCurrentMonth
        width: month.labelW
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
    }

    // Bars float on the drawer background with no track: a faint full
    // row behind a partial bar reads as loading, not progress.
    Rectangle {
        id: monthBar
        x: month.labelW + month.labelGap
        width: Math.max(0, month.availW * month.ratio)
        height: parent.height
        radius: Style.space(2)
        color: month.isCurrentMonth ? month.accent : Qt.rgba(month.foreground.r, month.foreground.g, month.foreground.b, 0.8)

        MouseArea {
            id: monthBarMouse
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
        }

        ScreenTip {
            foreground: month.foreground
            fontFamily: month.fontFamily
            tipBackground: month.panelBackground

            hovered: monthBarMouse.containsMouse
            tipText: {
                var m = month.months[month.index];
                return month.monthLong[month.index] + " \u00b7 " + (m ? Model.fmt(m.ms) : "0h");
            }
        }
    }

    Text {
        text: {
            var m = month.months[month.index];
            return m ? m.hours : "0h";
        }
        color: month.foreground
        opacity: month.isCurrentMonth ? 1.0 : 0.55
        font.family: month.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: month.isCurrentMonth
        horizontalAlignment: Text.AlignRight
        width: month.hoursW
        elide: Text.ElideRight
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
    }
}
