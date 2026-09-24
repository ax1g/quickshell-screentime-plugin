import QtQuick
import QtTest
import qs.Commons
import "../../qml/components"

// 24h day timeline geometry: segments sit at their day fractions, the
// hour axis renders five clamped labels, and every legend row occupies
// space. Sample segments mirror the Model.daySpanView shape.
// Thresholds stay relative, never absolute pixels.
TestCase {
    name: "TimelineGeometry"
    width: 400
    height: 400
    when: windowShown
    visible: true

    DayTimeline {
        id: timeline
        width: 360
        foreground: "#ffffff"
        fontFamily: "monospace"
        tipBackground: "#101315"
        dayTotal: 3720000
        segments: [
            { app: "zen", category: "Web Browsing", start: 25200000, end: 25800000, ms: 600000, startFrac: 0, endFrac: 0.217, color: "#e45b93" },
            { app: "foot", category: "System & Utilities", start: 26100000, end: 26160000, ms: 60000, startFrac: 0.326, endFrac: 0.348, color: "#d54b23" },
            { app: "discord", category: "Communication", start: 27000000, end: 27960000, ms: 960000, startFrac: 0.652, endFrac: 1.0, color: "#e4d15b" }
        ]
        categories: [
            { category: "Communication", ms: 960000, color: "#e4d15b" },
            { category: "Web Browsing", ms: 600000, color: "#e45b93" },
            { category: "System & Utilities", ms: 60000, color: "#d54b23" }
        ]
        axis: [
            { frac: 0, label: "07:00" },
            { frac: 0.5, label: "07:08" },
            { frac: 1, label: "07:16" }
        ]
    }

    function collect(item, out) {
        out.push(item);
        for (var i = 0; i < item.children.length; i++)
            collect(item.children[i], out);
    }

    function findText(s) {
        var all = [];
        collect(timeline, all);
        for (var i = 0; i < all.length; i++) {
            if (all[i].text !== undefined && all[i].text === s)
                return all[i];
        }
        return null;
    }

    // Every ancestor up to the strip must occupy space; a zero-height
    // ancestor hides the whole subtree (the collapse signature).
    function ancestorsOccupy(item) {
        var cur = item.parent;
        while (cur && cur !== timeline) {
            if (!(cur.height > 0))
                return false;
            cur = cur.parent;
        }
        return true;
    }

    function test_headerRenders() {
        var title = findText("DAY TIMELINE");
        verify(title !== null && title.height > 0 && ancestorsOccupy(title), "header occupies");
    }

    function test_segmentsSitAtDayFractions() {
        // The strip is the 36px rect holding the repeater; its rectangle
        // children are the segments (mouse areas are no rectangles).
        var all = [];
        collect(timeline, all);
        var strip = null;
        for (var i = 0; i < all.length; i++) {
            var it = all[i];
            if (it.height !== Style.space(36) || it.width <= 2)
                continue;
            var kids = it.children;
            for (var k = 0; k < kids.length; k++) {
                if (String(kids[k]).indexOf("QQuickRepeater") === 0)
                    strip = it;
            }
        }
        verify(strip !== null, "strip exists");
        var segs = [];
        for (var j = 0; j < strip.children.length; j++) {
            var child = strip.children[j];
            if (String(child).indexOf("QQuickRectangle") === 0)
                segs.push(child);
        }
        verify(segs.length === 3, "three segments: " + segs.length);
        segs.sort(function (a, b) {
            return a.x - b.x;
        });
        verify(segs[0].x < 5, "session starts at the left edge: " + segs[0].x);
        verify(segs[2].x > segs[1].x && segs[1].x > segs[0].x, "time order");
        verify(segs[2].width > segs[0].width, "wider span, wider bar");
        verify(Math.abs(segs[2].x + segs[2].width - 360) < 1, "session ends at the right edge");
    }

    function test_axisLabelsRender() {
        for (const label of ["07:00", "07:08", "07:16"]) {
            var t = findText(label);
            verify(t !== null && t.height > 0 && ancestorsOccupy(t), label + " occupies");
        }
    }

    function test_legendRowsOccupy() {
        for (const label of ["Communication", "Web Browsing", "System & Utilities"]) {
            var row = findText(label);
            verify(row !== null && row.height > 0 && ancestorsOccupy(row), label + " occupies");
        }
    }

    function test_hourlyBarsOccupy() {
        // The experimental chart renders one bar slot per hour; hours
        // with recorded time occupy vertical space, empty ones do not.
        var hours = [];
        for (var h = 0; h < 24; h++)
            hours.push({ hour: h, ms: h === 9 ? 3600000 : (h === 10 ? 1200000 : 0), color: "#e45b93" });
        var chart = hourlyComponent.createObject(timeline.parent, {
            width: 360,
            hours: hours,
            maxMs: 3600000,
            peakHour: 9,
            accent: "#e45b93",
            foreground: "#ffffff",
            fontFamily: "monospace"
        });
        verify(chart !== null, "hourly chart instantiates");
        var all = [];
        var stack = [chart];
        while (stack.length) {
            var it = stack.pop();
            all.push(it);
            for (var i = 0; i < it.children.length; i++)
                stack.push(it.children[i]);
        }
        var bars = 0;
        for (var j = 0; j < all.length; j++) {
            if (String(all[j]).indexOf("QQuickRectangle") === 0 && all[j].height > 0)
                bars++;
        }
        // Exactly the two nonzero hours render bars; the title, peak
        // label and ticks render text.
        verify(bars === 2, "two nonzero hours draw bars: " + bars);
        chart.destroy();
    }

    function test_emptyStateExplains() {
        var note = emptyComponent.createObject(timeline.parent, {
            width: 360,
            foreground: "#ffffff",
            fontFamily: "monospace",
            tipBackground: "#101315",
            dayTotal: 3600000,
            segments: [],
            categories: []
        });
        verify(note !== null, "empty timeline instantiates");
        var found = false;
        var all = [];
        var stack = [note];
        while (stack.length) {
            var it = stack.pop();
            all.push(it);
            for (var i = 0; i < it.children.length; i++)
                stack.push(it.children[i]);
        }
        for (var j = 0; j < all.length; j++) {
            if (all[j].text !== undefined && String(all[j].text).indexOf("totals only") !== -1)
                found = true;
        }
        verify(found, "empty state explains span-less days");
        note.destroy();
    }

    Component {
        id: emptyComponent
        DayTimeline {
            foreground: "#ffffff"
            fontFamily: "monospace"
            tipBackground: "#101315"
            dayTotal: 0
            segments: []
            categories: []
            axis: []
        }
    }

    Component {
        id: hourlyComponent
        HourlyChart {
            accent: "#e45b93"
            foreground: "#ffffff"
            fontFamily: "monospace"
            maxMs: 0
            peakHour: -1
            hours: []
        }
    }
}
