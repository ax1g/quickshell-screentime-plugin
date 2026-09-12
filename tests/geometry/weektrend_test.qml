import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import "../../qml"

// Week header layout: the range label stretches between the fixed
// arrows and elides, so short and long strings alike never push the
// arrows or the week total out of place. Thresholds are relational
// (edges ordered, elision engaged), never absolute pixels.
TestCase {
    name: "WeekTrendGeometry"
    width: 220
    height: 400

    // Narrow on purpose: the long month-spanning label must elide.
    WeekTrend {
        id: trend
        width: 200
        foreground: "#ffffff"
        fontFamily: "monospace"
        tipBackground: "#101315"
        accent: "#e45b93"
        weekOffset: 1
        maxOffset: 3
        hasPrevWeekData: true
        visibleWeek: {
            "month": "Sep",
            "days": [
                { "key": "2026-08-31", "ms": 3600000, "label": "Mon", "isEmpty": false, "isFuture": false, "isToday": false },
                { "key": "2026-09-01", "ms": 3600000, "label": "Tue", "isEmpty": false, "isFuture": false, "isToday": false },
                { "key": "2026-09-02", "ms": 3600000, "label": "Wed", "isEmpty": false, "isFuture": false, "isToday": false },
                { "key": "2026-09-03", "ms": 3600000, "label": "Thu", "isEmpty": false, "isFuture": false, "isToday": false },
                { "key": "2026-09-04", "ms": 3600000, "label": "Fri", "isEmpty": false, "isFuture": false, "isToday": false },
                { "key": "2026-09-05", "ms": 0, "label": "Sat", "isEmpty": true, "isFuture": false, "isToday": false },
                { "key": "2026-09-06", "ms": 0, "label": "Sun", "isEmpty": true, "isFuture": false, "isToday": false }
            ]
        }
        recordWeek: false
        weekTotalAsPct: false
        visibleWeekTotalMs: 18000000
        axisTicks: [0, 14400000, 28800000]
        axisMaxMs: 28800000
        activeDayKey: "2026-09-04"
        recordColor: "#FFD700"
        showRecordTrophy: true
        hintMode: false
    }

    function collect(item, out) {
        out.push(item);
        for (var i = 0; i < item.children.length; i++)
            collect(item.children[i], out);
    }

    function findText(fragment) {
        var all = [];
        collect(trend, all);
        for (var i = 0; i < all.length; i++) {
            if (all[i].text !== undefined && String(all[i].text).indexOf(fragment) !== -1)
                return all[i];
        }
        return null;
    }

    function findArrows() {
        var all = [];
        collect(trend, all);
        var arrows = [];
        for (var i = 0; i < all.length; i++) {
            if (String(all[i]).indexOf("PagerArrow") !== -1)
                arrows.push(all[i]);
        }
        return arrows;
    }

    function test_longLabelElides() {
        var label = findText("W36");
        verify(label !== null, "range label exists");
        verify(label.width < label.implicitWidth, "long label elides");
    }

    function test_nextArrowHugsLabel() {
        var arrows = findArrows();
        verify(arrows.length === 2, "two pager arrows");
        var label = findText("W36");
        verify(label !== null, "range label exists");
        var next = arrows[0].x < arrows[1].x ? arrows[1] : arrows[0];
        verify(next.x >= label.x + label.width, "next arrow sits after the range text");
        verify(next.x - (label.x + label.width) <= 10, "gap matches the left arrow spacing");
    }

    function test_arrowsStayClearOfTotal() {
        var arrows = findArrows();
        verify(arrows.length === 2, "two pager arrows");
        var total = findText("5h");
        verify(total !== null, "week total exists");
        var prev = arrows[0].x < arrows[1].x ? arrows[0] : arrows[1];
        var next = arrows[0].x < arrows[1].x ? arrows[1] : arrows[0];
        verify(prev.x <= 1, "prev arrow stays left");
        verify(next.x + next.width <= total.x, "next arrow never reaches the total");
    }
}
