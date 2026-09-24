import QtQuick
import QtTest
import qs.Commons
import "../../qml/components"

// Year heatmap geometry: month labels crown their week columns, every
// day cell occupies space, and the Less → More key renders. Thresholds
// stay relative, never absolute pixels.
TestCase {
    name: "HeatmapGeometry"
    width: 400
    height: 300
    when: windowShown
    visible: true

    YearHeatmap {
        id: heatmap
        width: 360
        foreground: "#ffffff"
        fontFamily: "monospace"
        accent: "#e45b93"
        panelBackground: "#101315"
        currentMonth: ""
        savedWeek: -1
        weeks: [
            { label: "Aug", days: [
                { date: "2026-08-31", ms: 3600000, level: 2 },
                { date: "2026-09-01", ms: 0, level: 0 },
                null, null, null, null, null
            ] },
            { label: "", days: [
                { date: "2026-09-07", ms: 7200000, level: 4 },
                { date: "2026-09-08", ms: 1000, level: 1 },
                { date: "2026-09-09", ms: 0, level: 0 },
                { date: "2026-09-10", ms: 0, level: 0 },
                { date: "2026-09-11", ms: 0, level: 0 },
                { date: "2026-09-12", ms: 0, level: 0 },
                { date: "2026-09-13", ms: 0, level: 0 }
            ] },
            { label: "Sep", days: [
                null,
                { date: "2026-09-15", ms: 3600000, level: 3 },
                { date: "2026-09-16", ms: 0, level: 0 },
                { date: "2026-09-17", ms: 0, level: 0 },
                { date: "2026-09-18", ms: 0, level: 0 },
                { date: "2026-09-19", ms: 0, level: 0 },
                { date: "2026-09-20", ms: 0, level: 0 }
            ] }
        ]
    }

    function collect(item, out) {
        out.push(item);
        for (var i = 0; i < item.children.length; i++)
            collect(item.children[i], out);
    }

    function findText(s) {
        var all = [];
        collect(heatmap, all);
        for (var i = 0; i < all.length; i++) {
            if (all[i].text !== undefined && all[i].text === s)
                return all[i];
        }
        return null;
    }

    // Every ancestor up to the heatmap must occupy space; a zero-height
    // ancestor hides the whole subtree (the collapse signature).
    function ancestorsOccupy(item) {
        var cur = item.parent;
        while (cur && cur !== heatmap) {
            if (!(cur.height > 0))
                return false;
            cur = cur.parent;
        }
        return true;
    }

    function test_monthLabelsRender() {
        var aug = findText("Aug");
        verify(aug !== null && aug.height > 0 && ancestorsOccupy(aug), "Aug occupies");
        var sep = findText("Sep");
        verify(sep !== null && sep.height > 0 && ancestorsOccupy(sep), "Sep occupies");
    }

    function test_cellsOccupy() {
        // Three week columns of seven slots each, pads included.
        var all = [];
        collect(heatmap, all);
        var cells = 0;
        for (var i = 0; i < all.length; i++) {
            var it = all[i];
            if (it.width > 0 && it.width === it.height && it.width <= heatmap.cell + 1 && ancestorsOccupy(it))
                cells++;
        }
        verify(cells >= 21, "day cells occupy: " + cells);
    }

    function test_legendRenders() {
        var less = findText("Less");
        verify(less !== null && less.height > 0 && ancestorsOccupy(less), "Less occupies");
        var more = findText("More");
        verify(more !== null && more.height > 0 && ancestorsOccupy(more), "More occupies");
    }

    function buildYear() {
        var weeks = [];
        for (var w = 0; w < 53; w++) {
            var days = [];
            for (var d = 0; d < 7; d++)
                days.push({ date: "2026-01-01", ms: 3600000, level: 2 });
            weeks.push({ label: w === 35 ? "Sep" : "", days: days });
        }
        return weeks;
    }

    function test_opensScrolledToCurrentMonth() {
        // A full year overflows: the grid docks the current month at
        // the right end instead of opening on January.
        var wide = wideComponent.createObject(heatmap.parent, {
            width: 360,
            foreground: "#ffffff",
            fontFamily: "monospace",
            accent: "#e45b93",
            panelBackground: "#101315",
            currentMonth: "Sep",
            savedWeek: -1,
            weeks: buildYear()
        });
        verify(wide !== null, "wide heatmap instantiates");
        wide.restorePosition();
        verify(wide.canScroll, "full year overflows");
        // Sep crowns week 35 of 12px columns in a 360px viewport:
        // 35*12 leaves it one column off the right edge.
        verify(Math.abs(wide.scrollX - 72) < 1, "docks right: " + wide.scrollX);
        wide.destroy();
    }

    function test_scrollBarFloatsOverGrid() {
        // The scroll indicator overlays the grid instead of taking a
        // layout row: nested scroll chrome in the flow reads as a
        // broken page. A full year overflows, so the bar must exist.
        var wide = wideComponent.createObject(heatmap.parent, {
            width: 360,
            foreground: "#ffffff",
            fontFamily: "monospace",
            accent: "#e45b93",
            panelBackground: "#101315",
            currentMonth: "Sep",
            savedWeek: -1,
            weeks: buildYear()
        });
        verify(wide !== null && wide.canScroll, "wide fixture overflows");
        var all = [];
        collect(wide, all);
        var bar = null;
        var flick = null;
        for (var i = 0; i < all.length; i++) {
            var kind = String(all[i]);
            if (kind.indexOf("QQuickRectangle") === 0 && all[i].width > 100 && all[i].height <= 4)
                bar = all[i];
            if (kind.indexOf("QQuickFlickable") === 0)
                flick = all[i];
        }
        verify(bar !== null && flick !== null, "bar and grid exist");
        verify(bar.parent === flick.parent, "bar overlays the grid wrapper");
        verify(bar.parent !== wide, "bar takes no layout row in the column");
        verify(bar.y + bar.height <= flick.parent.height + 1, "bar sits on the grid edge");
        wide.destroy();
    }

    function test_restoresSavedWeek() {
        // A stored position beats the month default, sticky per year.
        var wide = wideComponent.createObject(heatmap.parent, {
            width: 360,
            foreground: "#ffffff",
            fontFamily: "monospace",
            accent: "#e45b93",
            panelBackground: "#101315",
            currentMonth: "Sep",
            savedWeek: 5,
            weeks: buildYear()
        });
        verify(wide !== null, "wide heatmap instantiates");
        wide.restorePosition();
        verify(Math.abs(wide.scrollX - 60) < 1, "restores week 5: " + wide.scrollX);
        wide.destroy();
    }

    Component {
        id: wideComponent
        YearHeatmap {
            foreground: "#ffffff"
            fontFamily: "monospace"
            accent: "#e45b93"
            panelBackground: "#101315"
            currentMonth: ""
            savedWeek: -1
            weeks: []
        }
    }
}
