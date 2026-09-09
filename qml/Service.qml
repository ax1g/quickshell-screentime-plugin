// Functions and handlers cross-reference sibling ids; muted for the linter.
// qmllint disable unqualified
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../js/Model.js" as Model
import "../js/State.js" as State

// Screen-time tracker: accrues focused time per app into per-day records.
// Persisted as { "<YYYY-MM-DD>": { total, apps } }; 60s commits bound
// crash loss. Transitions live in State.js; this file owns timers,
// disk I/O, processes and bindings.
Item {
    id: root

    // Injected by omarchy-shell.
    property var shell: null
    // Passed explicitly; QML JS modules don't share imports.
    readonly property var stateModel: Model

    readonly property string home: Quickshell.env("HOME")
    readonly property string dataDir: home + "/.config/omarchy/screen-time"
    readonly property string historyPath: dataDir + "/history.json"
    readonly property string resolverPath: {
        var u = Qt.resolvedUrl("../python/resolve_app.py").toString();
        return u.startsWith("file://") ? u.slice(7) : u;
    }

    // Terminals report the window class; resolve the pty foreground instead.
    readonly property var terminalAppIds: ["foot", "alacritty", "kitty", "ghostty", "wezterm", "konsole", "gnome-terminal", "tilix", "xfce4-terminal", "termite", "st", "org.omarchy.terminal"]

    // Pruned past keepDays; sized for the 13-week trend plus slack.
    readonly property int keepDays: 95

    // A tick later than this means the loop froze: suspend or clock jump.
    readonly property int suspendGapMs: 30 * 1000
    property double lastTick: 0

    // Live state: always REPLACED, never mutated, so bindings fire.
    property string todayKey: Model.dayKey(new Date())
    property var today: Model.newDay()
    // Disk mirror; root.today is the source of truth.
    property var days: ({})
    // Pre-archive monthly lumps; never overlaps the day archive.
    property var months: ({})
    // Per-day archive keeping retro facts past the raw window.
    property var years: ({})

    property string activeApp: ""
    property double activeStart: 0
    // Raw compositor appId; activeApp is the resolved name.
    property string rawApp: ""
    property string resolveForApp: ""
    property bool resolveInFlight: false
    // Generation tokens stop stale terminal resolves misattributing.
    property int resolveGeneration: 0
    property int resolveSpawnGen: 0
    property bool ready: false
    property bool startupPhase: true

    // ---- Public read API for the UI ----------------------------------------
    readonly property string barLabel: today ? Model.fmt(today.total) : ""
    readonly property bool hasActivity: today && today.total > 0

    function appList() {
        return Model.appList(root.today);
    }
    function fmt(ms) {
        return Model.fmt(ms);
    }
    function relativeDayLabel(key) {
        return Model.relativeDayLabel(key, root.todayKey);
    }

    // ---- State transition helpers ------------------------------------------
    // Spread a State.js patch onto live props so bindings fire.
    function applyState(patch) {
        if (!patch)
            return;
        if (patch.today !== undefined)
            root.today = patch.today;
        if (patch.days !== undefined)
            root.days = patch.days;
        if (patch.todayKey !== undefined)
            root.todayKey = patch.todayKey;
        if (patch.activeApp !== undefined)
            root.activeApp = patch.activeApp;
        if (patch.activeStart !== undefined)
            root.activeStart = patch.activeStart;
        if (patch.lastTick !== undefined)
            root.lastTick = patch.lastTick;
        if (patch.resolveInFlight !== undefined)
            root.resolveInFlight = patch.resolveInFlight;
    }

    // ---- Tracking ----------------------------------------------------------

    function isTerminal(appId) {
        return appId && root.terminalAppIds.indexOf(appId.toLowerCase()) !== -1;
    }

    // steam_app_<id> resolves to the game title via local manifests.
    function isSteamApp(appId) {
        return appId && appId.toLowerCase().indexOf("steam_app_") === 0;
    }

    // Screensaver/portal windows open no bucket.
    function shouldTrack(appId) {
        if (!appId)
            return false;
        var id = String(appId).toLowerCase();
        if (id === "org.omarchy.screensaver")
            return false;
        if (id.indexOf("xdg-desktop-portal") === 0)
            return false;
        return true;
    }

    function switchActive() {
        var now = Date.now();
        applyState(State.closeActiveBucket(root, root.activeApp, root.activeStart, now, root.todayKey, root.suspendGapMs, root.lastTick));
        root.persist();
        var tl = ToplevelManager.activeToplevel;
        var app = tl && tl.appId ? tl.appId : "";
        root.rawApp = app;
        root.resolveInFlight = false;
        if (app && !root.shouldTrack(app)) {
            root.activeApp = "";
            root.activeStart = 0;
            return;
        }
        if (app && (root.isTerminal(app) || root.isSteamApp(app))) {
            root.activeApp = "";
            root.activeStart = 0;
            root.beginResolve();
        } else {
            root.activeApp = Model.canonicalApp(app);
            root.activeStart = app ? now : 0;
        }
    }

    // Re-resolve the focused terminal; a new request invalidates the running one.
    function beginResolve() {
        root.resolveForApp = root.rawApp;
        root.resolveInFlight = true;
        root.resolveGeneration++;
        if (!resolverProc.running) {
            root.resolveSpawnGen = root.resolveGeneration;
            resolverProc.running = true;
        }
    }

    // Refreshes terminals whose foreground changed mid-focus.
    function applyResolvedApp(name) {
        var patch = State.applyResolvedApp(root, name, root.resolveForApp, root.todayKey, root.suspendGapMs, root.lastTick);
        // Always clear, even on no-op, so refresh isn't watchdog-gated.
        root.resolveInFlight = false;
        applyState(patch);
        if (patch)
            root.persist();
    }

    // Fold the in-flight bucket in; a crash loses at most one interval.
    function commitElapsed(now) {
        if (!root.ready || !root.activeApp || !root.activeStart)
            return;
        applyState(State.commitElapsed(root, root.activeApp, root.activeStart, now, root.todayKey, root.suspendGapMs, root.lastTick));
    }

    function rolloverIfNeeded() {
        var key = Model.dayKey(new Date());
        var now = Date.now();
        // One transition owns midnight (close+carry+reopen); no ordering slip.
        var patch = State.advanceRollover(root, now, key, root.suspendGapMs, root.lastTick);
        if (!patch)
            return;
        applyState(patch);
        root.persist();
    }

    // ---- Persistence -------------------------------------------------------

    // Fold today into a fresh mirror object so the adapter notifier fires.
    // Writes wait while the corrupt-file backup runs.
    property bool backupPending: false
    function persist() {
        if (root.startupPhase || root.backupPending)
            return;
        var merged = Object.assign({}, root.days);
        merged[root.todayKey] = root.today;
        // Pruned days roll into the per-day archive; months lumps stay untouched.
        var ret = Model.applyRetention(merged, root.years, root.todayKey, root.keepDays, Number(String(root.todayKey).split("-")[0]));
        if (ret.pruned) {
            root.years = ret.years;
            historyAdapter.years = ret.years;
        }
        root.days = ret.days;
        historyAdapter.days = ret.days;
    }

    // Failure streak; any scheduled save resets it.
    property int saveFailCount: 0

    function scheduleSave() {
        if (root.startupPhase || root.backupPending)
            return;
        saveTimer.restart();
    }

    function onHistoryLoaded() {
        // Non-object sections are discarded with a single warning.
        var clean = Model.sanitizeHistory(historyAdapter.days, historyAdapter.months, historyAdapter.years);
        if (clean.days !== historyAdapter.days || clean.months !== historyAdapter.months || clean.years !== historyAdapter.years)
            console.warn("agx.screen-time: history.json has malformed sections; ignoring them");
        var d = clean.days;
        var m = clean.months;
        // Load-time drops feed the archive too.
        var ret = Model.applyRetention(d, clean.years, Model.dayKey(new Date()), root.keepDays, new Date().getFullYear());
        if (ret.pruned)
            historyAdapter.years = ret.years;
        var y = ret.years;
        var kept = ret.days;
        root.months = m;
        root.days = kept;
        root.years = y;
        if (!root.ready) {
            root.todayKey = Model.dayKey(new Date());
            var prev = d[root.todayKey];
            root.today = prev && typeof prev === "object" ? {
                total: prev.total || 0,
                apps: Object.assign({}, prev.apps || {})
            } : Model.newDay();
            root.ready = true;
            root.startupPhase = false;
            root.lastTick = Date.now();
            root.switchActive();
        } else {
            // Retry keeps the live bucket; refresh the mirror only.
            var nd = Object.assign({}, root.days);
            nd[root.todayKey] = root.today;
            root.days = nd;
        }
    }

    function onHistoryLoadFailed() {
        // Corrupt files are preserved aside; tracking starts empty immediately.
        console.warn("agx.screen-time: history load failed, starting empty");
        if (!root.backupAttempted) {
            root.backupAttempted = true;
            root.backupPending = true;
            backupProc.running = true;
        }
        if (!root.ready) {
            root.days = {};
            root.ready = true;
            root.startupPhase = false;
            root.lastTick = Date.now();
            root.switchActive();
        }
    }

    FileView {
        id: historyFile
        path: root.historyPath
        printErrors: true
        atomicWrites: true
        onAdapterUpdated: {
            // Fresh data resets the failure streak.
            root.saveFailCount = 0;
            root.scheduleSave();
        }
        onLoaded: root.onHistoryLoaded()
        onLoadFailed: root.onHistoryLoadFailed()
        onSaveFailed: function (error) {
            // Retry with capped backoff; suspend after 6 straight failures.
            root.saveFailCount++;
            if (root.saveFailCount > 6) {
                console.warn("agx.screen-time: history save failed (" + FileViewError.toString(error) + "), suspending retries until next change");
                return;
            }
            var delay = Math.min(1500 * Math.pow(2, root.saveFailCount - 1), 60000);
            console.warn("agx.screen-time: history save failed (" + FileViewError.toString(error) + "), retrying in " + delay + "ms");
            saveRetryTimer.interval = delay;
            saveRetryTimer.restart();
        }

        JsonAdapter {
            id: historyAdapter
            property var days: ({})
            property var months: ({})
            property var years: ({})
        }
    }

    Process {
        id: ensureDirProc
        environment: ({
                "HOME": root.home
            })
        command: ["bash", "-c", "mkdir -p \"$HOME/.config/omarchy/screen-time\"; f=\"$HOME/.config/omarchy/screen-time/history.json\"; [[ -f \"$f\" ]] || printf '{}\\n' > \"$f\""]
        onExited: historyFile.reload()
    }

    // Polls for missed focus events; real switches are event-driven.
    Timer {
        id: reconcileTimer
        interval: 2000
        repeat: true
        running: root.ready
        onTriggered: {
            var tl = ToplevelManager.activeToplevel;
            var app = tl && tl.appId ? tl.appId : "";
            if (app !== root.rawApp)
                root.switchActive();
        }
    }

    // Move aside only non-empty files that fail to parse.
    property bool backupAttempted: false
    Process {
        id: backupProc
        environment: ({
                "HOME": root.home
            })
        command: ["bash", "-c", "command -v python3 >/dev/null 2>&1 || exit 0; f=\"$HOME/.config/omarchy/screen-time/history.json\"; if [[ -s \"$f\" ]] && ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \"$f\" 2>/dev/null; then mv -f \"$f\" \"$f.corrupt-$(date +%s)\"; fi"]
        onExited: {
            // Unblock writes; queued state persists on the next tick.
            root.backupPending = false;
            root.persist();
        }
    }

    // Foreground can change without compositor notice; re-resolve live.
    Timer {
        id: terminalRefreshTimer
        interval: 5000
        repeat: true
        running: root.ready && root.isTerminal(root.rawApp) && !root.resolveInFlight
        onTriggered: root.beginResolve()
    }

    // Kill hung resolvers so refresh can start a fresh process.
    Timer {
        id: resolveWatchdog
        interval: 10000
        repeat: false
        running: root.resolveInFlight
        onTriggered: {
            root.resolveInFlight = false;
            if (resolverProc.running)
                resolverProc.running = false;
        }
    }

    // Empty stdout falls back to rawApp; stderr is logged so breakage is visible.
    // sh wrapper: missing python3 still exits 0 instead of stalling to watchdog.
    Process {
        id: resolverProc
        command: ["sh", "-c", "command -v python3 >/dev/null 2>&1 && exec python3 \"$1\" || exit 0", "sh", root.resolverPath]
        stdout: StdioCollector {
            id: resolverOut
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: resolverErr
            waitForEnd: true
        }
        onExited: {
            var err = resolverErr.text.trim();
            if (err)
                console.warn("agx.screen-time: resolver stderr:", err);
            root.applyResolvedApp(resolverOut.text.trim());
        }
    }

    // Fresh baseline resolves suspends down to ~30s.
    Timer {
        id: heartbeatTimer
        interval: 5000
        repeat: true
        running: root.ready
        onTriggered: {
            var now = Date.now();
            if (State.isSuspendGap(now, root.lastTick, root.suspendGapMs)) {
                applyState(State.closeActiveBucket(root, root.activeApp, root.activeStart, now, root.todayKey, root.suspendGapMs, root.lastTick));
                // Roll past midnight before reopening, or wake seconds land on yesterday.
                root.rolloverIfNeeded();
                root.persist();
                root.switchActive();
            } else {
                root.rolloverIfNeeded();
                root.commitElapsed(now);
                root.persist();
            }
            root.lastTick = now;
        }
    }

    Timer {
        id: commitTimer
        interval: 60000
        repeat: true
        running: root.ready
        onTriggered: {
            var now = Date.now();
            root.rolloverIfNeeded();
            root.commitElapsed(now);
            root.persist();
            root.lastTick = now;
        }
    }

    Timer {
        id: saveTimer
        interval: 1500
        repeat: false
        onTriggered: historyFile.writeAdapter()
    }

    // Save-retry driver (backoff computed in onSaveFailed).
    Timer {
        id: saveRetryTimer
        repeat: false
        onTriggered: historyFile.writeAdapter()
    }

    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            root.switchActive();
        }
    }

    Component.onCompleted: {
        ensureDirProc.running = true;
    }
}
