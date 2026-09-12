import QtQuick
import QtQuick.Controls
import qs.Commons

// Shell-styled tooltip; 300ms dwell so sweeping across bars won't flash it.

ToolTip {
    id: screenTip
    property string tipText: ""
    property bool hovered: false
    padding: 0
    visible: false

    required property color foreground
    required property string fontFamily
    required property color tipBackground

    Timer {
        id: showTimer
        interval: 300
        repeat: false
        running: screenTip.hovered
        onTriggered: screenTip.visible = true
    }

    onHoveredChanged: if (!hovered)
        screenTip.visible = false

    background: Rectangle {
        color: screenTip.tipBackground
        border.color: Qt.rgba(screenTip.foreground.r, screenTip.foreground.g, screenTip.foreground.b, 0.25)
        border.width: 1
        radius: Style.space(3)
    }

    contentItem: Text {
        text: screenTip.tipText
        color: screenTip.foreground
        font.family: screenTip.fontFamily
        font.pixelSize: Style.font.caption
        leftPadding: Style.space(8)
        rightPadding: Style.space(8)
        topPadding: Style.space(4)
        bottomPadding: Style.space(4)
    }
}
