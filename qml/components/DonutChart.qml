import QtQuick
import qs.Commons
import "../../js/Model.js" as Model

// Donut ring with hover cross-highlight and center readout.
// Canvas because Shape won't host a Repeater; Panel resets hover on close.
Item {
    id: donutChart
    required property var segments
    required property var sliceColors
    required property real ringSize
    required property string activeDayLabel
    required property double dayTotal
    required property color foreground
    required property string fontFamily
    required property color accent

    // Radius fits the base stroke inside Canvas bounds.
    readonly property real ringBaseWidth: Style.space(14)
    readonly property real ringRadius: ringSize / 2 - ringBaseWidth / 2

    // Hovered slice (-1 = none) + center readout override.
    property int hoverSlice: -1
    property string hoverApp: ""
    property double hoverMs: 0
    readonly property bool sliceHovered: hoverSlice >= 0 && hoverSlice < segments.length && hoverApp !== ""

    width: ringSize
    height: ringSize

    // Slice color at the given alpha; falls back to accent on bad hex.
    function sliceColor(index, alpha) {
        var hex = String(sliceColors[index] || accent).replace(/[#\s]/g, "");
        if (!/^[0-9a-fA-F]{6}$/.test(hex))
            return Qt.rgba(accent.r, accent.g, accent.b, alpha);
        var r = parseInt(hex.substr(0, 2), 16) / 255;
        var g = parseInt(hex.substr(2, 2), 16) / 255;
        var b = parseInt(hex.substr(4, 2), 16) / 255;
        return Qt.rgba(r, g, b, alpha);
    }

    function setSliceHover(slice, appName, ms) {
        hoverSlice = slice;
        hoverApp = appName;
        hoverMs = ms;
    }

    function clearHover() {
        hoverSlice = -1;
        hoverApp = "";
        hoverMs = 0;
    }

    // Ring hit-test in item coordinates. Angles are degrees clockwise
    // from 12 o'clock (arcSegments' convention).
    function sliceAt(x, y) {
        var segs = segments;
        if (!segs || segs.length === 0)
            return -1;
        var dx = x - width / 2;
        var dy = y - height / 2;
        var r = Math.sqrt(dx * dx + dy * dy);
        var inner = ringRadius - ringBaseWidth / 2 - Style.space(3);
        var outer = ringRadius + ringBaseWidth / 2 + Style.space(3);
        if (r < inner || r > outer)
            return -1;
        var deg = Math.atan2(dy, dx) * 180 / Math.PI;
        if (deg < -90)
            deg += 360;
        for (var i = 0; i < segs.length; i++) {
            var start = segs[i].startAngle;
            var end = start + segs[i].sweepAngle;
            if (end <= 360 ? (deg >= start && deg <= end) : (deg >= start || deg <= end - 360))
                return i;
        }
        return -1;
    }

    Canvas {
        id: donutCanvas
        anchors.fill: parent
        onWidthChanged: donutCanvas.requestPaint()

        Connections {
            target: donutChart
            function onSegmentsChanged() {
                donutCanvas.requestPaint();
            }
            function onSliceColorsChanged() {
                donutCanvas.requestPaint();
            }
            function onHoverSliceChanged() {
                donutCanvas.requestPaint();
            }
            function onForegroundChanged() {
                donutCanvas.requestPaint();
            }
        }

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var segs = donutChart.segments;
            var size = width;
            var cx = size / 2;
            var cy = size / 2;
            var rad = donutChart.ringRadius;
            var toRad = Math.PI / 180;

            if (!segs || segs.length === 0) {
                ctx.lineWidth = donutChart.ringBaseWidth;
                ctx.strokeStyle = Qt.rgba(donutChart.foreground.r, donutChart.foreground.g, donutChart.foreground.b, 0.1);
                ctx.beginPath();
                ctx.arc(cx, cy, rad, 0, Math.PI * 2, false);
                ctx.stroke();
                return;
            }

            for (var i = 0; i < segs.length; i++) {
                var seg = segs[i];
                ctx.lineWidth = donutChart.ringBaseWidth;
                ctx.strokeStyle = donutChart.sliceColor(i, donutChart.hoverSlice < 0 || i === donutChart.hoverSlice ? 1.0 : 0.25);
                ctx.beginPath();
                ctx.arc(cx, cy, rad, seg.startAngle * toRad, (seg.startAngle + seg.sweepAngle) * toRad, false);
                ctx.stroke();
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.ArrowCursor
        onPositionChanged: function (mouse) {
            var i = donutChart.sliceAt(mouse.x, mouse.y);
            if (i >= 0) {
                var seg = donutChart.segments[i];
                donutChart.setSliceHover(i, Model.displayName(seg.app), seg.ms || 0);
            } else {
                donutChart.clearHover();
            }
        }
        onContainsMouseChanged: if (!containsMouse)
            donutChart.clearHover()
    }

    // Center readout swaps to the hovered slice's app.
    Column {
        anchors.centerIn: parent
        width: parent.width * 0.6
        spacing: Style.space(1)

        Text {
            text: donutChart.sliceHovered ? donutChart.hoverApp : donutChart.activeDayLabel
            color: donutChart.foreground
            font.family: donutChart.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            text: Model.fmt(donutChart.sliceHovered ? donutChart.hoverMs : donutChart.dayTotal)
            color: Qt.darker(donutChart.foreground, 1.4)
            font.family: donutChart.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
