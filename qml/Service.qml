import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../js/Model.js" as Model
import "../js/State.js" as State

// Functions and handlers cross-reference sibling ids; muted for the linter.
// qmllint disable unqualified

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
    // Shared process env (HOME for ~ expansion). Typed var so the
    // Map-vs-Hash literal inference stays in one audited place.
    readonly property var procEnv: ({
            "HOME": home
        })
    readonly property string resolverPath: {
        var u = Qt.resolvedUrl("../python/resolve_app.py").toString();
        return u.startsWith("file://") ? u.slice(7) : u;
    }

    // Terminals report the window class; resolve the pty foreground instead.
    readonly property var terminalAppIds: ["foot", "alacritty", "kitty", "ghostty", "wezterm", "konsole", "gnome-terminal", "tilix", "xfce4-terminal", "termite", "st", "org.omarchy.terminal"]

    // App-detail window in days; the panel raises it to the visible
    // week trend's floor, so wide graphs stay fully detailed. Days that
    // age past it roll their totals into the perpetual per-day archive.
    property int keepDays: 365
    function setKeepDays(days) {
        var n = Math.floor(Number(days));
        if (!isFinite(n) || n < 7 || n > 730)
            return;
        if (n === root.keepDays)
            return;
        root.keepDays = n;
        root.persist();
    }

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
    // Mirrors omarchy's first-party session services (omarchy.lock,
    // omarchy.idle) so tracking pauses during lock/screensaver without
    // touching the compositor or spawning helpers on the hot path.
    // startedAt timestamps only report pause durations in debug logs.
    property bool sessionLocked: false
    property bool screensaverActive: false
    property double lockStartedAt: 0
    property double screensaverStartedAt: 0
    // Debug timing logs for lock/screensaver intervals; off by default.
    property bool debugLogging: false
    property var lockService: null
    property var idleService: null
    // Shell injects the plugin API asynchronously; re-run lookups on change.
    onShellChanged: root.refreshShellServices()

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

    // User tracking prefs pushed from the panel (settings live in the bar
    // widget; the service itself has no settings handle). Normalized on
    // write so readers compare lowercase keys only.
    property var ignoredApps: []
    property var appAliases: ({})
    function setTrackingPrefs(ignored, aliases) {
        var nextAliases = Model.parseAppAliases(aliases);
        // Refolding is idempotent, so a serialize compare is enough to
        // notice a changed map without tracking the previous object.
        var refold = Model.serializeAliases(nextAliases) !== Model.serializeAliases(root.appAliases);
        root.ignoredApps = Model.parseIgnoredApps(ignored);
        root.appAliases = nextAliases;
        if (refold)
            root.refoldToday();
        // An app ignored mid-focus stops accruing now, not at the next
        // focus switch.
        if (root.ready && root.activeApp && Model.isIgnoredApp(root.activeApp, root.ignoredApps)) {
            var now = Date.now();
            applyState(State.closeActiveBucket(root, root.activeApp, root.activeStart, now, root.todayKey, root.suspendGapMs, root.lastTick));
            root.activeApp = "";
            root.activeStart = 0;
            root.persist();
        }
    }

    // Fold today's stored time through an alias map: adding zen=browser
    // mid-day moves today's earlier zen time onto browser and renames
    // the live bucket, so the rest of the day accrues there. Removing
    // an alias unfolds with the inverse map, restoring the original
    // name for today and the future. Past days are untouched. No-op
    // when nothing resolves elsewhere (startup, repeated pushes).
    // Defaults to the live map when the caller passes none.
    function refoldToday(aliases) {
        if (!root.ready)
            return;
        var map = aliases || root.appAliases;
        var now = Date.now();
        var previous = root.activeApp;
        // Bill in-flight time to the old name first so no seconds leak.
        if (previous)
            root.commitElapsed(now);
        var folded = Model.refoldDay(root.today, map);
        if (folded !== root.today) {
            root.today = folded;
            var nd = Object.assign({}, root.days);
            nd[root.todayKey] = root.today;
            root.days = nd;
        }
        if (previous) {
            var renamed = Model.resolveAppName(previous, map);
            if (renamed !== previous)
                root.activeApp = renamed;
            root.activeStart = now;
        }
        root.persist();
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
        if (Model.isIgnoredApp(appId, root.ignoredApps))
            return false;
        return true;
    }

    function switchActive() {
        // Pre-ready focus events open unguarded buckets (and defeat the
        // lastTick baseline); the load handlers call back once ready.
        if (!root.ready)
            return;
        var now = Date.now();
        applyState(State.closeActiveBucket(root, root.activeApp, root.activeStart, now, root.todayKey, root.suspendGapMs, root.lastTick));
        root.persist();
        var tl = ToplevelManager.activeToplevel;
        var app = tl && tl.appId ? tl.appId : "";
        root.rawApp = app;
        root.resolveInFlight = false;
        // Paused (locked or screensaver up): keep the bucket closed.
        // Toplevel events still fire under lock; reopening here would
        // accrue straight through the pause.
        if (root.sessionLocked || root.screensaverActive) {
            root.activeApp = "";
            root.activeStart = 0;
            return;
        }
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
            root.activeApp = Model.resolveAppName(app, root.appAliases);
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
        // Paused: drop the result so an in-flight resolver landing mid-lock
        // cannot reopen a bucket. Unlock re-resolves via switchActive().
        if (root.sessionLocked || root.screensaverActive) {
            root.resolveInFlight = false;
            root.resolveForApp = "";
            return;
        }
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

    // Zeroes today only: live day plus its history mirror. Archives
    // (months/years) are untouched; the focused app keeps running with
    // activeStart rebased so the next commit bills from now, not from
    // before the reset.
    function resetToday() {
        if (!root.ready)
            return;
        var now = Date.now();
        root.today = Model.newDay();
        var nd = Object.assign({}, root.days);
        nd[root.todayKey] = root.today;
        root.days = nd;
        if (root.activeApp)
            root.activeStart = now;
        root.lastTick = now;
        root.persist();
    }

    // Wipes ALL history: live day, day mirror, month lumps and the per-day
    // archive. Irreversible: no backup is kept, and the file is overwritten
    // on the next save. The focused app keeps running with activeStart
    // rebased so cleared time can't come back.
    function resetAll() {
        if (!root.ready)
            return;
        var now = Date.now();
        root.today = Model.newDay();
        root.days = {};
        root.months = {};
        root.years = {};
        // persist() only syncs days (and years when pruned), never months:
        // clear the adapters outright so stale lumps can't come back.
        historyAdapter.months = {};
        historyAdapter.years = {};
        if (root.activeApp)
            root.activeStart = now;
        root.lastTick = now;
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
        var ret = Model.applyRetention(merged, root.years, root.todayKey, root.keepDays);
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
        // Start, never restart: continuous focus flapping must not defer
        // the write indefinitely past the crash window.
        if (!saveTimer.running)
            saveTimer.start();
    }

    function onHistoryLoaded() {
        // Non-object sections are discarded with a single warning.
        var clean = Model.sanitizeHistory(historyAdapter.days, historyAdapter.months, historyAdapter.years);
        if (clean.days !== historyAdapter.days || clean.months !== historyAdapter.months || clean.years !== historyAdapter.years)
            console.warn("agx.screen-time: history.json has malformed sections; ignoring them");
        var d = clean.days;
        var m = clean.months;
        // Load-time drops feed the archive too.
        var ret = Model.applyRetention(d, clean.years, Model.dayKey(new Date()), root.keepDays);
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
            root.todayKey = Model.dayKey(new Date());
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

        // FileViewAdapter is C++-only in Quickshell: complete at runtime,
        // incomplete to the linter. Muted via the ini (UnresolvedType/
        // TypeError) instead of a scoped directive, because that directive
        // name is unknown to qmllint 6.4.
        JsonAdapter {
            id: historyAdapter
            property var days: ({})
            property var months: ({})
            property var years: ({})
        }
    }

    // QProcess::ExitStatus never loads into lint; handlers take no args.
    // Muted via the ini (BadSignalHandler/Parameters), see .qmllint.ini.
    Process {
        id: ensureDirProc
        environment: root.procEnv
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

    // Move aside non-empty files that fail to parse. The validity check
    // uses python3 when present, but the move itself never depends on
    // it: without python an unreadable file is still preserved aside
    // instead of being overwritten on the next save.
    property bool backupAttempted: false
    Process {
        id: backupProc
        environment: root.procEnv
        command: ["bash", "-c", "f=\"$HOME/.config/omarchy/screen-time/history.json\"; if [[ -s \"$f\" ]]; then if command -v python3 >/dev/null 2>&1 && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \"$f\" 2>/dev/null; then :; else mv -f \"$f\" \"$f.corrupt-$(date +%s)\"; fi; fi"]
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
    // No generation bump needed: every switchActive clears
    // resolveInFlight, and beginResolve re-syncs the tokens, so a late
    // exit only ever matches a live run of the same terminal.
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

    // ---- Session pause (lock / screensaver) ----------------------------------
    // Lock state comes from omarchy.lock at the source instead of polling
    // loginctl, so lock/unlock needs no extra process spawning. The shell's
    // service registry fills asynchronously; lookups retry until both
    // services resolve, transitions are event-driven afterward.
    function refreshShellServices() {
        if (!root.shell)
            return;
        root.lockService = root.shell.serviceFor("omarchy.lock");
        root.idleService = root.shell.serviceFor("omarchy.idle");
        if (root.lockService) {
            root.setSessionLocked(root.lockService.locked);
            // Event-driven source wins once reachable; stop the fallback
            // watcher so it can't fight it or leak a bash loop.
            sessionStateWatcher.running = false;
        }
        if (root.idleService)
            root.setScreensaverActive(root.idleService.screensaverStartedThisCycle || root.idleService.screensaverWindowCount > 0);
        if (root.lockService && root.idleService) {
            serviceLookupTimer.stop();
            root.serviceLookupWarned = false;
        }
    }

    function setSessionLocked(locked) {
        locked = locked === true;
        if (locked === root.sessionLocked)
            return;
        root.sessionLocked = locked;
        if (locked) {
            root.lockStartedAt = Date.now();
            root.cancelResume();
            // Kill in-flight terminal resolves; their results would reopen
            // a bucket through the pause (see applyResolvedApp).
            root.resolveInFlight = false;
            root.resolveForApp = "";
            if (root.debugLogging)
                console.warn("agx.screen-time: lock started");
            var now = Date.now();
            applyState(State.closeActiveBucket(root, root.activeApp, root.activeStart, now, root.todayKey, root.suspendGapMs, root.lastTick));
            root.persist();
        } else {
            var endedAt = Date.now();
            var duration = root.lockStartedAt ? endedAt - root.lockStartedAt : 0;
            if (root.debugLogging)
                console.warn("agx.screen-time: lock ended, duration=" + duration + "ms");
            root.lockStartedAt = 0;
            // Deferred: with 10s state sources an "unpaused" reading can be
            // stale (screensaver flag clearing just before lock engages).
            // applyResume re-validates both flags before reopening.
            root.scheduleResume();
        }
    }

    function setScreensaverActive(active) {
        active = active === true;
        if (active === root.screensaverActive)
            return;
        root.screensaverActive = active;
        if (active) {
            root.screensaverStartedAt = Date.now();
            root.cancelResume();
            if (root.debugLogging)
                console.warn("agx.screen-time: screensaver started");
            var now = Date.now();
            applyState(State.closeActiveBucket(root, root.activeApp, root.activeStart, now, root.todayKey, root.suspendGapMs, root.lastTick));
            root.persist();
        } else {
            var endedAt = Date.now();
            var duration = root.screensaverStartedAt ? endedAt - root.screensaverStartedAt : 0;
            if (root.debugLogging)
                console.warn("agx.screen-time: screensaver ended, duration=" + duration + "ms");
            root.screensaverStartedAt = 0;
            if (!root.sessionLocked)
                root.scheduleResume();
        }
    }

    // Unpauses schedule a resume instead of reopening immediately, so a
    // stale reading from a ~10s state source can't briefly reopen a bucket.
    property bool resumePending: false
    Timer {
        id: resumeTimer
        interval: 2000
        repeat: false
        onTriggered: root.applyResume()
    }
    function scheduleResume() {
        root.resumePending = true;
        resumeTimer.restart();
    }
    function cancelResume() {
        root.resumePending = false;
        resumeTimer.stop();
    }
    function applyResume() {
        if (root.sessionLocked || root.screensaverActive) {
            root.resumePending = false;
            return;
        }
        if (!root.resumePending)
            return;
        root.resumePending = false;
        // Rebase to the resume instant: the pause may have ended up to two
        // seconds ago, and reopening must not bill from the stale lastTick.
        var now = Date.now();
        root.lastTick = now;
        root.switchActive();
    }

    property bool serviceLookupWarned: false

    Timer {
        id: serviceLookupTimer
        interval: 250
        repeat: true
        running: root.ready && (!root.lockService || !root.idleService)
        property int attempts: 0
        onTriggered: {
            root.refreshShellServices();
            attempts++;
            if (attempts >= 40 && !root.serviceLookupWarned) {
                // Sandboxed serviceFor may never resolve these (scoped to a
                // plugin's own service). Warn once instead of failing silent.
                root.serviceLookupWarned = true;
                console.warn("agx.screen-time: omarchy.lock/omarchy.idle services unavailable after 10s; " + "falling back to a persistent lock watcher (~10s pause accuracy)");
            }
        }
    }

    // Fallback when sandboxed lookups can't reach lock/idle services: one
    // persistent watcher checking lock every 10s, printing only on change.
    // Stops automatically if event-driven lookups ever succeed.
    Process {
        id: sessionStateWatcher
        environment: root.procEnv
        command: ["bash", "-c", "ppid=$PPID; prev=''; while :; do " + "kill -0 $ppid 2>/dev/null || exit 0; " + "cur=$(omarchy-shell lock isLocked 2>/dev/null); " + "if [ -n \"$cur\" ] && [ \"$cur\" != \"$prev\" ]; then printf '%s\\n' \"$cur\"; prev=\"$cur\"; fi; " + "sleep 10; done"]
        stdout: SplitParser {
            onRead: function (line) {
                root.setSessionLocked(String(line).trim() === "true");
            }
        }
    }

    // Restarts the watcher if it exits while lock service stays unreachable.
    Timer {
        id: watcherSupervisorTimer
        interval: 5000
        repeat: true
        running: root.ready && !root.lockService
        onTriggered: {
            if (!root.lockService && !sessionStateWatcher.running)
                sessionStateWatcher.running = true;
        }
    }

    // Screensaver fallback is an in-process toplevel scan (no spawning),
    // running only while the idle service is unreachable.
    Timer {
        id: screensaverScanTimer
        interval: 10000
        repeat: true
        running: root.ready && !root.idleService
        onTriggered: root.setScreensaverActive(root.screensaverWindowVisible())
    }

    // omarchy launches the screensaver as "org.omarchy.screensaver", so a
    // toplevel scan is a reliable sandbox-visible proxy for "screensaver up".
    function screensaverWindowVisible() {
        var toplevels = ToplevelManager.toplevels;
        if (!toplevels || !toplevels.length)
            return false;
        for (var i = 0; i < toplevels.length; i++) {
            var t = toplevels[i];
            if (t && t.appId && String(t.appId).toLowerCase() === "org.omarchy.screensaver")
                return true;
        }
        return false;
    }

    // Event-driven sources, used whenever the sandboxed lookups succeed.
    Connections {
        target: root.lockService
        function onLockedChanged() {
            root.setSessionLocked(root.lockService.locked);
        }
    }

    Connections {
        target: root.idleService
        function onScreensaverStartedThisCycleChanged() {
            root.setScreensaverActive(root.idleService.screensaverStartedThisCycle);
        }
        function onScreensaverWindowCountChanged() {
            root.setScreensaverActive(root.idleService.screensaverWindowCount > 0);
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
