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
    height: menu.height
    when: windowShown
    visible: true

    ConfigMenu {
        id: menu
        width: parent.width
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

    SignalSpy {
        id: resetSpy
        target: menu
        signalName: "resetRequested"
    }

    SignalSpy {
        id: wipeSpy
        target: menu
        signalName: "wipeRequested"
    }

    function test_confirmationClicks_data() {
        return [
            {
                tag: "reset",
                labels: ["RESET", "SURE?", "REALLY?"],
                spy: resetSpy
            },
            {
                tag: "wipe",
                labels: ["WIPE ALL", "SURE?", "CAN'T UNDO!", "WIPE!"],
                spy: wipeSpy
            }
        ];
    }

    function test_confirmationClicks(data) {
        data.spy.clear();
        for (var i = 0; i < data.labels.length; i++) {
            var label = findText(data.labels[i]);
            verify(label !== null, "confirmation label " + data.labels[i]);
            compare(data.spy.count, 0, "no destructive signal before final confirmation");
            mouseClick(label.parent, label.parent.width - 2, label.parent.height / 2);
        }
        compare(data.spy.count, 1, "final click emits exactly once");
        verify(findText(data.labels[0]) !== null, "confirmation returns to idle");
    }

    function test_dangerButtonsWarnOnHover() {
        mouseMove(menu, 0, 0);
        wait(1);
        var labels = ["RESET", "WIPE ALL"];
        for (var i = 0; i < labels.length; i++) {
            var label = labels[i];
            var button = findText(label);
            verify(button !== null, label + " exists");
            verify(!button.parent.warning, label + " is neutral while idle");
            mouseMove(button.parent, button.parent.width / 2, button.parent.height / 2);
            verify(button.parent.warning, label + " warns on hover");
        }
        mouseMove(menu, 0, 0);
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
