import QtQuick
import Quickshell.Io
import qs.Ui
import qs.Commons
import "../js/Model.js" as Model

// Bar button: today's total; hosts the panel. Tracking lives in Service.
BarWidget {
    id: root
    moduleName: "agx.screen-time"

    readonly property var service: bar && bar.shell ? bar.shell.serviceFor("agx.screen-time") : null
    readonly property string label: service ? service.barLabel : ""
    readonly property bool hasActivity: service ? service.hasActivity : false

    readonly property string glyph: "󰔟"

    // Vertical mode stacks glyph + duration tokens to fit icon slots.
    readonly property var verticalLines: {
        if (!root.vertical)
            return [];
        var lines = [root.glyph];
        if (!root.iconOnly && root.label) {
            var parts = String(root.label).split(" ");
            for (var i = 0; i < parts.length; i++)
                if (parts[i])
                    lines.push(parts[i]);
        }
        return lines;
    }

    // Widget prefs persist in shell.json across restarts and slots.
    // Reads coerce to bool; writes go through setSetting to keep keys.
    function settingBool(key, fallback) {
        var v = root.setting(key, fallback);
        return v === true || v === "true";
    }

    readonly property bool iconOnly: root.settingBool("iconOnly", false)

    // Daily goal badge: progress counts the same filtered day the panel
    // shows, so ignored apps never push the goal. The goal in force is
    // the log entry for today: days before activation show nothing.
    readonly property int dailyGoalHours: Model.goalForDay(Model.parseGoalLog(root.setting("dailyGoalLog", [])), root.service ? root.service.todayKey : "")
    readonly property double goalTotal: {
        if (!root.service)
            return 0;
        var day = Model.filterIgnoredDay(root.service.today, Model.parseIgnoredApps(root.setting("ignoredApps", "")));
        return day ? (day.total || 0) : 0;
    }
    readonly property bool goalReached: root.dailyGoalHours > 0 && root.goalTotal >= root.dailyGoalHours * 3600000
    readonly property string goalTooltip: {
        if (root.dailyGoalHours <= 0)
            return "";
        var goal = Model.fmt(root.dailyGoalHours * 3600000);
        if (root.goalReached)
            return " · goal reached (" + goal + ")";
        return " · " + Model.fmt(root.dailyGoalHours * 3600000 - root.goalTotal) + " left of " + goal;
    }

    // Session cache of keys written before the shell delivers settings
    // (or while its API is unreachable). Merged into every built entry
    // and flushed on delivery, so a fast toggle can never replace the
    // stored entry with a partial one and lose the user's config.
    property var pendingWrites: ({})
    // True once the shell has delivered settings at least once. Own
    // optimistic writes set writingSettings so they never fake delivery.
    property bool settingsReady: false
    property bool writingSettings: false

    // All config-menu prefs funnel here so no key is ever dropped.
    function setSetting(key, value) {
        var pending = Object.assign({}, root.pendingWrites);
        pending[key] = value;
        root.pendingWrites = pending;
        var entry = {
            id: root.moduleName
        };
        var base = root.settings && typeof root.settings === "object" ? root.settings : {};
        for (var k in base)
            if (k !== "id")
                entry[k] = base[k];
        for (var p in pending)
            entry[p] = pending[p];
        root.writingSettings = true;
        root.settings = entry;
        root.writingSettings = false;
        if (root.settingsReady && root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
            root.pendingWrites = {};
            root.bar.shell.updateEntryInline(root.moduleName, entry);
        }
    }

    // Re-issue early writes over the delivered base so they persist.
    function flushSettings() {
        var pending = root.pendingWrites;
        root.pendingWrites = {};
        for (var k in pending)
            root.setSetting(k, pending[k]);
    }

    function toggleIconOnly() {
        root.setSetting("iconOnly", !root.iconOnly);
    }

    // Underline tracks painted label width, like omarchy.clock.
    readonly property real openPanelIndicatorWidth: {
        if (root.iconOnly && !root.vertical && iconGlyph)
            return Math.max(1, Math.round(iconGlyph.tightWidth));
        // Vertical mark takes one icon slot.
        if (root.vertical)
            return Style.bar.iconSlot;
        return button.labelWidth;
    }
    readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

    // ---- Panel shape contract for shell.summon/hide/toggle routing ---------
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

    function open() {
        if (panelLoader.item)
            panelLoader.item.open();
    }
    function close() {
        if (panelLoader.item)
            panelLoader.item.close();
    }
    function togglePanel() {
        if (panelLoader.item)
            panelLoader.item.toggle();
    }

    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

    function closeForPopoutSwitch() {
        if (panelLoader.item)
            panelLoader.item.closeForPopoutSwitch();
    }

    function injectPanel() {
        var target = panelLoader.item;
        if (!target)
            return;
        if ("bar" in target)
            target.bar = root.bar;
        if ("settings" in target)
            target.settings = root.settings;
        if ("anchorItem" in target)
            target.anchorItem = button;
        if ("hostWidget" in target)
            target.hostWidget = root;
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    onBarChanged: injectPanel()
    onSettingsChanged: {
        // Own optimistic writes must not count as delivery: only the
        // shell's arrival marks ready and flushes early writes.
        if (!root.writingSettings) {
            root.settingsReady = true;
            root.flushSettings();
        }
        root.injectPanel();
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel();
            Qt.callLater(root.injectPanel);
        }
    }

    IpcHandler {
        target: "agx.screen-time"
        function open(): void {
            root.open();
        }
        function close(): void {
            root.close();
        }
        function show(): void {
            root.open();
        }
        function hide(): void {
            root.close();
        }
        function toggle(): void {
            root.togglePanel();
        }
        function resetToday(): void {
            if (root.service)
                root.service.resetToday();
        }
        function resetAll(): void {
            if (root.service)
                root.service.resetAll();
        }
        function status(): void {
            var p = panelLoader.item;
            console.log("agx.screen-time status: opened=" + (p ? p.opened : "no-panel") + " label=" + root.label + " hasActivity=" + root.hasActivity + " apps=" + (root.service ? root.service.appList().length : "none"));
        }
    }

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        // Single label at bar size: glyph + duration render uniformly.
        // A reached daily goal appends a check badge.
        text: root.vertical ? "" : root.iconOnly ? root.glyph : root.glyph + " " + root.label + (root.goalReached ? " ✓" : "")
        labelVisible: !root.vertical && !root.iconOnly
        hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
        fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
        horizontalMargin: 8.5
        tooltipText: (root.hasActivity ? "Screen time today \u00b7 " + root.label : "Screen time \u00b7 no activity yet") + root.goalTooltip
        onPressed: function (b) {
            if (b === Qt.RightButton)
                root.toggleIconOnly();
            else
                root.togglePanel();
        }

        // OpticalGlyph centers glyph ink over the hidden label's advance.
        OpticalGlyph {
            id: iconGlyph
            visible: !root.vertical && root.iconOnly
            anchors.fill: parent
            text: root.glyph
            fontFamily: button.fontFamily
            fontSize: Style.font.title
            color: button.foreground
        }

        Column {
            visible: root.vertical
            anchors.fill: parent

            // Outer-id reads are idiomatic in delegates; muted for the linter.
            // qmllint disable unqualified
            Repeater {
                model: root.verticalLines

                OpticalGlyph {
                    required property string modelData
                    width: button.width
                    height: Style.bar.iconSlot
                    text: modelData
                    fontFamily: button.fontFamily
                    fontSize: modelData === root.glyph ? Style.font.icon : (modelData.length > 3 ? button.fontSize * 0.9 : button.fontSize)
                    color: button.foreground
                }
            }
            // qmllint enable unqualified
        }
    }
}
