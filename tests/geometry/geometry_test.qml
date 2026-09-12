import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import "../../qml/components"

// Structural geometry: rows that must occupy space, buttons that must
// exist with size. Guards the collapse class (a fill-anchored MouseArea
// inside an implicit-height Column resolves to height zero). Thresholds
// stay relative so any font scale passes.
TestCase {
    name: "ConfigMenuGeometry"
    width: 340
    height: 2000

    ConfigMenu {
        id: menu
        foreground: "#ffffff"
        fontFamily: "monospace"
        accent: "#e45b93"
        urgent: "#ff5555"
        hideYearly: false
        hideDailyInsights: false
        hideYearInsights: false
        weekCount: 12
        weekOptions: [12, 24, 36, 52]
        weekTotalAsPct: false
        hideEasterEggs: false
        hideRecordTrophy: false
        recordColor: "#ffd700"
        recordColorOptions: ["#ffffff", "#e45b93"]
        recordDefaultColor: "#ffd700"
        heroColor: ""
        heroColorOptions: ["#ffffff", "#e45b93"]
        heroDefaultColor: ""
        ignoredEntries: ["launcher"]
        aliasEntries: [
            {
                from: "zen",
                to: "browser"
            }
        ]
        dailyGoalHours: 6
        dailyGoalOptions: [0, 4, 6, 8]
        storageLabel: "1 days · 2 months · 3 archived"
        pluginVersion: "1.6.0"
        hintMode: false
    }

    function collect(item, out) {
        out.push(item);
        for (var i = 0; i < item.children.length; i++)
            collect(item.children[i], out);
    }

    function findText(s) {
        var all = [];
        collect(menu, all);
        for (var i = 0; i < all.length; i++) {
            if (all[i].text !== undefined && all[i].text === s)
                return all[i];
        }
        return null;
    }

    // Every ancestor up to the menu must occupy space; a zero-height
    // ancestor hides the whole subtree (the collapse signature).
    function ancestorsOccupy(item) {
        var cur = item.parent;
        while (cur && cur !== menu) {
            if (!(cur.height > 0))
                return false;
            cur = cur.parent;
        }
        return true;
    }

    function test_hintTagsDistinct() {
        menu.hintMode = true;
        var all = [];
        collect(menu, all);
        var seen = {};
        var n = 0;
        for (var i = 0; i < all.length; i++) {
            var it = all[i];
            // Logic, not pixels: visible/width collapse headless without
            // a window, but show + label prove the registry resolves.
            if (it.label !== undefined && typeof it.label === "string" && it.show === true && it.label !== "") {
                seen[it.label] = (seen[it.label] || 0) + 1;
                n++;
            }
        }
        var distinct = 0;
        var dupes = "";
        for (var tag in seen) {
            distinct++;
            if (seen[tag] > 1)
                dupes += tag + "x" + seen[tag] + " ";
        }
        verify(n > 20, "badges rendered: " + n);
        verify(dupes === "", "duplicate badge tags: " + dupes);
        verify(distinct === n, "all tags distinct");
    }

    function test_menuHasHeight() {
        verify(menu.implicitHeight > 100, "menu height=" + Math.round(menu.implicitHeight));
    }

    function test_toggleRowOccupies() {
        var t = findText("Yearly overview");
        verify(t !== null, "toggle label exists");
        verify(t !== null && t.height > 0 && ancestorsOccupy(t), "toggle row occupies");
    }

    function test_resetButtonOccupies() {
        var reset = findText("RESET");
        verify(reset !== null, "RESET exists");
        verify(reset !== null && reset.width > 0 && reset.height > 0 && ancestorsOccupy(reset), "RESET occupies");
    }

    function test_wipeButtonOccupies() {
        var wipe = findText("WIPE ALL");
        verify(wipe !== null, "WIPE ALL exists");
        verify(wipe !== null && wipe.width > 0 && wipe.height > 0 && ancestorsOccupy(wipe), "WIPE occupies");
    }

    function test_entriesRender() {
        var ignored = findText("launcher");
        verify(ignored !== null && ignored.height > 0 && ancestorsOccupy(ignored), "ignored entry occupies");
        var alias = findText("zen → browser");
        verify(alias !== null && alias.height > 0 && ancestorsOccupy(alias), "alias entry occupies");
    }

    function test_helpRenders() {
        var help = findText("CONTRIBUTION");
        verify(help !== null && help.height > 0 && ancestorsOccupy(help), "contribution card occupies");
    }

    function test_aboutRenders() {
        var about = findText("Screen Time");
        verify(about !== null && about.height > 0 && ancestorsOccupy(about), "about card occupies");
    }
}
