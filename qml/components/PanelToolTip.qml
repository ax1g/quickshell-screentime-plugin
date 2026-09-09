import QtQuick
import QtQuick.Controls
import qs.Commons

// Shared panel-styled tooltip: matches the drawer's background, foreground
// and font so popups read as part of the shell rather than platform chrome.
// Tooltip with a dwell delay: sweeping across adjacent bars restarts the
// timer on every enter, so the tip only appears after hovering one target
// for 300ms instead of flashing along the sweep.

ToolTip {
    id: panelTip
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
        running: panelTip.hovered
        onTriggered: panelTip.visible = true
    }

    onHoveredChanged: if (!hovered)
        panelTip.visible = false

    background: Rectangle {
        color: panelTip.tipBackground
        border.color: Qt.rgba(panelTip.foreground.r, panelTip.foreground.g, panelTip.foreground.b, 0.25)
        border.width: 1
        radius: Style.space(3)
    }

    contentItem: Text {
        text: panelTip.tipText
        color: panelTip.foreground
        font.family: panelTip.fontFamily
        font.pixelSize: Style.font.caption
        leftPadding: Style.space(8)
        rightPadding: Style.space(8)
        topPadding: Style.space(4)
        bottomPadding: Style.space(4)
    }
}
