import QtQuick
import QtTest
import qs.Commons
import "../../qml/components"

// Day timeline demo strip: the color-coded blocks fill the track exactly
// (fractions of the strip width) and every legend row occupies space.
// Sample blocks mirror the Model.timelineView shape (category, ms, pct,
// frac, color). Thresholds stay relative, never absolute pixels.
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
        dayTotal: 12273172
        blocks: [
            { category: "Browser", ms: 8966550, pct: 74, frac: 0.74, color: "#e45b93" },
            { category: "Code", ms: 1772592, pct: 15, frac: 0.15, color: "#d54b23" },
            { category: "Terminal", ms: 1068293, pct: 9, frac: 0.09, color: "#e4d15b" },
            { category: "Other", ms: 380509, pct: 3, frac: 0.02, color: "#7dd523" }
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
        var demo = findText("DEMO");
        verify(demo !== null && demo.height > 0 && ancestorsOccupy(demo), "demo badge occupies");
    }

    function test_legendRowsOccupy() {
        var labels = ["Browser", "Code", "Terminal", "Other"];
        for (var i = 0; i < labels.length; i++) {
            var row = findText(labels[i]);
            verify(row !== null && row.height > 0 && ancestorsOccupy(row), labels[i] + " occupies");
        }
    }

    function test_blocksFillTrack() {
        // The block repeater's parent is the strip row; its item children
        // are the blocks, and the row fills the track edge to edge.
        var all = [];
        collect(timeline, all);
        var row = null;
        for (var i = 0; i < all.length; i++) {
            if (String(all[i]).indexOf("QQuickRepeater") === 0 && String(all[i].parent).indexOf("QQuickRow") === 0)
                row = all[i].parent;
        }
        verify(row !== null, "strip row exists");
        verify(row.parent.width === timeline.width, "row fills the track");
        // The repeater itself lists as a zero-size child; the blocks are
        // the children with width.
        var filled = 0;
        var blocks = 0;
        for (var j = 0; j < row.children.length; j++) {
            if (row.children[j].width > 0) {
                filled += row.children[j].width;
                blocks++;
            }
        }
        verify(blocks === 4, "four blocks: " + blocks);
        verify(Math.abs(filled - row.width) < 1, "blocks fill the track: " + filled + " of " + row.width);
    }
}
