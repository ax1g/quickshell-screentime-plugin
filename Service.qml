import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "lib/Model.js" as Model
import "lib/State.js" as State

// Long-running screen-time tracker.
//
// Watches the compositor's active toplevel (ToplevelManager) and accrues
// focused time per app into a per-day record persisted as JSON. No focused
// window means the clock is paused; idle/lock/desktop time is not counted.
//
// Persistence is a single append-only JSON file
//   ~/.config/omarchy/screen-time/history.json
// shaped as
//   { "<YYYY-MM-DD>": { "total": <ms>, "apps": { "<appId>": <ms> } } }
//
// Writes are event-driven (on focus change) and debounced through the
// adapter; a 60s commit bounds how much of an in-flight bucket can be lost
// to a crash. Data survives plugin hot-reloads because it lives on disk.
//
// State transitions live in State.js (pure, testable). This file owns the
// side effects: timers, disk I/O, process spawning, and QML property
// bindings.
Item {
  id: root

  // Injected by omarchy-shell (the generic service loader).
  property var shell: null
  // State.js receives this explicitly because QML JavaScript modules do not
  // share the Model import from this file as a global.
  readonly property var stateModel: Model

  readonly property string home: Quickshell.env("HOME")
  readonly property string dataDir: home + "/.config/omarchy/screen-time"
  readonly property string historyPath: dataDir + "/history.json"
  readonly property string resolverPath: {
    var u = Qt.resolvedUrl("scripts/resolve_app.py").toString()
    return u.startsWith("file://") ? u.slice(7) : u
  }

  // Terminals report themselves as their windowing appId, but screen time
  // should reflect what is actually running inside them (opencode, btop…).
  // When the active toplevel is one of these, Service resolves the pty's
  // foreground process group via resolve_app.py.
  readonly property var terminalAppIds: ["foot", "alacritty", "kitty", "ghostty",
    "wezterm", "konsole", "gnome-terminal", "tilix", "xfce4-terminal", "termite", "st",
    "org.omarchy.terminal"]

  // Retention window in days. History older than this is pruned on load and
  // before every write, so the append-only JSON can't grow without bound.
  // Covers the 13-week paginated trend (~91 days) plus slack for week
  // alignment; anything older is rolled into monthly aggregates.
  readonly property int keepDays: 95

  // The gap check resolves suspends down to roughly this threshold: a 5s
  // heartbeat keeps lastTick fresh, so a tick arriving more than
  // suspendGapMs after the last one means the event loop was frozen —
  // the machine was asleep (or the clock jumped).
  readonly property int suspendGapMs: 30 * 1000
  property double lastTick: 0

  // ---- Live state, exposed to the bar widget and panel. These are always
  //      REPLACED with fresh objects, never mutated in place, so QML
  //      bindings on them fire and the persistence adapter sees the change.
  property string todayKey: Model.dayKey(new Date())
  property var today: Model.newDay()
  // Full history mirror (dayKey -> day); what the adapter persists.
  property var days: ({})
  // Monthly aggregates (YYYY-MM -> ms) from before the day archive existed.
  // Read alongside the archive; persisted days land in the archive, never
  // here, so the two sources don't overlap.
  property var months: ({})
  // Per-day archive (YYYY -> per-day ms) for the current and previous
  // calendar year, keeping day-scale retro facts alive past the raw window.
  property var years: ({})

  property string activeApp: ""
  property double activeStart: 0
  // appId as reported by the compositor; activeApp is the resolved tracking
  // name (identical unless the toplevel is a terminal).
  property string rawApp: ""
  property string resolveForApp: ""
  property bool resolveInFlight: false
  // Resolve freshness tokens: every resolve request bumps resolveGeneration;
  // resolveSpawnGen snapshots it only when a process actually launches.
  // State.applyResolvedApp discards results whose tokens differ, so an
  // in-flight answer for foot(A) can never be attributed to foot(B).
  property int resolveGeneration: 0
  property int resolveSpawnGen: 0
  property bool ready: false
  property bool startupPhase: true
  // Mirrors the state of omarchy's first-party session services (omarchy.lock,
  // omarchy.idle) so screen time can pause during lock/screensaver without
  // touching the compositor or spawning helpers on the hot path. The startedAt
  // timestamps exist only to report pause durations in the debug logs.
  property bool sessionLocked: false
  property bool screensaverActive: false
  property double lockStartedAt: 0
  property double screensaverStartedAt: 0
  // Debug timing logs for lock/screensaver intervals. Off by default; flip
  // to true to trace when screen time pauses and resumes.
  property bool debugLogging: false
  property var lockService: null
  property var idleService: null
  // The shell injects the plugin API asynchronously, so the first-party
  // service lookups must re-run whenever the shell reference appears.
  onShellChanged: root.refreshShellServices()

  // ---- Public read API for the UI ----------------------------------------
  readonly property string barLabel: today ? Model.fmt(today.total) : ""
  readonly property bool hasActivity: today && today.total > 0

  function appList() { return Model.appList(root.today) }
  function fmt(ms) { return Model.fmt(ms) }
  function relativeDayLabel(key) { return Model.relativeDayLabel(key, root.todayKey) }

  // ---- State transition helpers ------------------------------------------
  // Apply a partial state patch from a State.js function to live QML
  // properties so bindings fire correctly.
  function applyState(patch) {
    if (!patch) return
    if (patch.today !== undefined) root.today = patch.today
    if (patch.days !== undefined) root.days = patch.days
    if (patch.todayKey !== undefined) root.todayKey = patch.todayKey
    if (patch.activeApp !== undefined) root.activeApp = patch.activeApp
    if (patch.activeStart !== undefined) root.activeStart = patch.activeStart
    if (patch.lastTick !== undefined) root.lastTick = patch.lastTick
    if (patch.resolveInFlight !== undefined) root.resolveInFlight = patch.resolveInFlight
  }

  // ---- Tracking ----------------------------------------------------------

  function isTerminal(appId) {
    return appId && root.terminalAppIds.indexOf(appId.toLowerCase()) !== -1
  }

  // Steam games report their AppID as the window class; the resolver turns
  // that into the game title from local manifests before it is tracked.
  function isSteamApp(appId) {
    return appId && appId.toLowerCase().indexOf("steam_app_") === 0
  }

  // Windows that are never user-facing screen time — the idle screensaver,
  // xdg desktop portal windows that steal focus. These open no bucket, so
  // they count neither as an app nor into today's total.
  function shouldTrack(appId) {
    if (!appId) return false
    var id = String(appId).toLowerCase()
    if (id === "org.omarchy.screensaver") return false
    if (id.indexOf("xdg-desktop-portal") === 0) return false
    return true
  }

  function switchActive() {
    var now = Date.now()
    applyState(State.closeActiveBucket(
      root, root.activeApp, root.activeStart, now,
      root.todayKey, root.suspendGapMs, root.lastTick))
    root.persist()
    var tl = ToplevelManager.activeToplevel
    var app = tl && tl.appId ? tl.appId : ""
    root.rawApp = app
    root.resolveInFlight = false
    // Paused (locked or screensaver up): keep the bucket closed. Toplevel
    // events and reconcile ticks still fire while the session lock is up,
    // and reopening here would resume accrual straight through the pause.
    if (root.sessionLocked || root.screensaverActive) {
      root.activeApp = ""
      root.activeStart = 0
      return
    }
    if (app && !root.shouldTrack(app)) {
      root.activeApp = ""
      root.activeStart = 0
      return
    }
    if (app && (root.isTerminal(app) || root.isSteamApp(app))) {
      root.activeApp = ""
      root.activeStart = 0
      root.beginResolve()
    } else {
      root.activeApp = Model.canonicalApp(app)
      root.activeStart = app ? now : 0
    }
  }

  // Requests a fresh foreground resolution for the focused terminal. The
  // generation is bumped on every request but snapshotted only when a
  // process actually launches; a request made while one is in flight
  // invalidates the running process's result instead of queueing a second.
  function beginResolve() {
    root.resolveForApp = root.rawApp
    root.resolveInFlight = true
    root.resolveGeneration++
    if (!resolverProc.running) {
      root.resolveSpawnGen = root.resolveGeneration
      resolverProc.running = true
    }
  }

  // Applies a resolver result. Called both for the initial focus resolve and
  // for periodic refreshes while a terminal stays focused (its foreground
  // process can change: opencode -> bash).
  function applyResolvedApp(name) {
    // Paused: discard the result and the pending resolve so an in-flight
    // resolver that lands during a lock or screensaver cannot reopen a
    // bucket through the pause. Unlock re-resolves via switchActive().
    if (root.sessionLocked || root.screensaverActive) {
      root.resolveInFlight = false
      root.resolveForApp = ""
      return
    }
    var patch = State.applyResolvedApp(
      root, name, root.resolveForApp, root.todayKey,
      root.suspendGapMs, root.lastTick)
    // Clear resolveInFlight unconditionally: the resolver process has exited.
    // State.applyResolvedApp includes it in its patch when the result is
    // acted on; when the result is discarded (no-op) the flag must still be
    // cleared so the terminal refresh timer can re-resolve after 5s instead
    // of waiting for the 10s watchdog.
    root.resolveInFlight = false
    applyState(patch)
    if (patch) root.persist()
  }

  // Bounds crash loss: folds the in-flight bucket into today, then restarts
  // the timer so a crash loses at most the current interval.
  function commitElapsed(now) {
    if (!root.ready || !root.activeApp || !root.activeStart) return
    applyState(State.commitElapsed(
      root, root.activeApp, root.activeStart, now,
      root.todayKey, root.suspendGapMs, root.lastTick))
  }

  function rolloverIfNeeded() {
    var key = Model.dayKey(new Date())
    var now = Date.now()
    // One transition owns the whole midnight moment (close + carry +
    // reopen, with straddling buckets split exactly); a single applyState
    // means no ordering slip can misattribute the crossing seconds.
    var patch = State.advanceRollover(
      root, now, key, root.suspendGapMs, root.lastTick)
    if (!patch) return
    applyState(patch)
    root.persist()
  }

  // ---- Persistence -------------------------------------------------------

  // Reassigns a fresh top-level object so the JsonAdapter's notifier fires,
  // which schedules the debounced disk write. The live in-memory day is
  // folded into the mirror first — root.today is the source of truth while
  // root.days mirrors what is on disk.
  // Blocks disk writes while the corrupt-file backup is still running, so
  // the first persist can never overwrite the file before it is moved aside.
  property bool backupPending: false
  function persist() {
    if (root.startupPhase || root.backupPending) return
    var merged = Object.assign({}, root.days)
    merged[root.todayKey] = root.today
    // Days dropped by retention roll up into the per-day archive so the
    // year retro keeps day-scale facts (streaks, day counts, peak day)
    // after raw app detail expires. Months is untouched: it only holds
    // pre-archive lumps, so archive + months never double count.
    var ret = Model.applyRetention(merged, root.years, root.todayKey,
      root.keepDays, Number(String(root.todayKey).split("-")[0]))
    if (ret.pruned) {
      root.years = ret.years
      historyAdapter.years = ret.years
    }
    root.days = ret.days
    historyAdapter.days = ret.days
  }

  // Consecutive history-save failures. Reset by any successful schedule
  // trigger (adapter update); the retry path below backs off instead.
  property int saveFailCount: 0

  function scheduleSave() {
    if (root.startupPhase || root.backupPending) return
    saveTimer.restart()
  }

  function onHistoryLoaded() {
    // sanitizeHistory rejects arrays and other non-objects that would slip
    // through a bare typeof check; identity comparison tells us whether
    // anything was discarded so the user gets one clear warning.
    var clean = Model.sanitizeHistory(historyAdapter.days, historyAdapter.months, historyAdapter.years)
    if (clean.days !== historyAdapter.days || clean.months !== historyAdapter.months || clean.years !== historyAdapter.years)
      console.warn("agx.screen-time: history.json has malformed sections; ignoring them")
    var d = clean.days
    var m = clean.months
    // Same retention as persist(): load-time drops also feed the per-day
    // archive instead of being lost.
    var ret = Model.applyRetention(d, clean.years, Model.dayKey(new Date()),
      root.keepDays, new Date().getFullYear())
    if (ret.pruned) historyAdapter.years = ret.years
    var y = ret.years
    var kept = ret.days
    root.months = m
    root.days = kept
    root.years = y
    if (!root.ready) {
      root.todayKey = Model.dayKey(new Date())
      var prev = d[root.todayKey]
      root.today = prev && typeof prev === "object"
        ? { total: prev.total || 0, apps: Object.assign({}, prev.apps || {}) }
        : Model.newDay()
      root.ready = true
      root.startupPhase = false
      root.lastTick = Date.now()
      root.switchActive()
    } else {
      // Retry after a seed: keep the live bucket, just refresh the mirror.
      var nd = Object.assign({}, root.days)
      nd[root.todayKey] = root.today
      root.days = nd
    }
  }

  function onHistoryLoadFailed() {
    // Expected on the very first run (file seeded by ensureDirProc) and on
    // a malformed file. Preserve a corrupt file before the next persist
    // overwrites it, then start empty rather than refusing to track.
    // Tracking starts immediately; only disk writes wait for the backup.
    console.warn("agx.screen-time: history load failed, starting empty")
    if (!root.backupAttempted) {
      root.backupAttempted = true
      root.backupPending = true
      backupProc.running = true
    }
    if (!root.ready) {
      root.days = {}
      root.ready = true
      root.startupPhase = false
      root.lastTick = Date.now()
      root.switchActive()
    }
  }

  FileView {
    id: historyFile
    path: root.historyPath
    printErrors: true
    atomicWrites: true
    onAdapterUpdated: {
      // Fresh data means the disk state is reachable again (or changed):
      // reset the failure streak so retries resume.
      root.saveFailCount = 0
      root.scheduleSave()
    }
    onLoaded: root.onHistoryLoaded()
    onLoadFailed: root.onHistoryLoadFailed()
    onSaveFailed: function(error) {
      // Disk didn't take the write (full disk, permissions): the data is
      // still in memory. Retry with capped exponential backoff instead of
      // hammering every 1.5s forever; after 6 straight failures suspend
      // retries until fresh data arrives (which resets the streak above).
      root.saveFailCount++
      if (root.saveFailCount > 6) {
        console.warn("agx.screen-time: history save failed ("
          + FileViewError.toString(error)
          + "), suspending retries until next change")
        return
      }
      var delay = Math.min(1500 * Math.pow(2, root.saveFailCount - 1), 60000)
      console.warn("agx.screen-time: history save failed ("
        + FileViewError.toString(error) + "), retrying in " + delay + "ms")
      saveRetryTimer.interval = delay
      saveRetryTimer.restart()
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
    environment: ({ "HOME": root.home })
    command: ["bash", "-c",
      "mkdir -p \"$HOME/.config/omarchy/screen-time\"; f=\"$HOME/.config/omarchy/screen-time/history.json\"; [[ -f \"$f\" ]] || printf '{}\\n' > \"$f\""]
    onExited: historyFile.reload()
  }

  // Safety net: catches appId-only changes and any missed activeToplevel
  // events. Cheap enough to run every 2s; real switches are event-driven.
  Timer {
    id: reconcileTimer
    interval: 2000
    repeat: true
    running: root.ready
    onTriggered: {
      var tl = ToplevelManager.activeToplevel
      var app = tl && tl.appId ? tl.appId : ""
      if (app !== root.rawApp) root.switchActive()
    }
  }

  // Preserve a corrupt history file before the next persist overwrites it.
  // Only a non-empty file that fails to parse is moved aside, so transient
  // load errors never destroy a valid history.
  property bool backupAttempted: false
  Process {
    id: backupProc
    environment: ({ "HOME": root.home })
    command: ["bash", "-c",
      "command -v python3 >/dev/null 2>&1 || exit 0; f=\"$HOME/.config/omarchy/screen-time/history.json\"; if [[ -s \"$f\" ]] && ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \"$f\" 2>/dev/null; then mv -f \"$f\" \"$f.corrupt-$(date +%s)\"; fi"]
    onExited: {
      // Unblock disk writes (see backupPending): queued in-memory state
      // persists on the next tick.
      root.backupPending = false
      root.persist()
    }
  }

  // A terminal's foreground process changes without the compositor noticing
  // (opencode exits, leaving bash). Re-resolve while a terminal is focused.
  Timer {
    id: terminalRefreshTimer
    interval: 5000
    repeat: true
    running: root.ready && root.isTerminal(root.rawApp) && !root.resolveInFlight
    onTriggered: root.beginResolve()
  }

  // If a resolver run never exits (hung hyprctl, wedged /proc read), kill it
  // and clear the in-flight flag so the refresh timer can start a fresh
  // process instead of stalling terminal tracking forever. The killed
  // process's onExited is ignored: applyResolvedApp returns early once
  // resolveInFlight is false.
  Timer {
    id: resolveWatchdog
    interval: 10000
    repeat: false
    running: root.resolveInFlight
    onTriggered: {
      root.resolveInFlight = false
      if (resolverProc.running) resolverProc.running = false
    }
  }

  // Resolves the app running in the focused terminal (see resolve_app.py).
  // An empty stdout falls back to rawApp silently by design, so stderr is
  // logged: without it a broken resolver degrades tracking invisibly.
  //
  // The sh -c wrapper guards against a missing python3: Quickshell's
  // Process exposes no spawn-failure signal, so a bare python3 command
  // that cannot start would leave resolves stalling until the watchdog.
  // sh always exists, exits 0 without output instead, and the empty
  // result falls back to tracking the raw terminal class.
  Process {
    id: resolverProc
    command: ["sh", "-c",
      "command -v python3 >/dev/null 2>&1 && exec python3 \"$1\" || exit 0",
      "sh", root.resolverPath]
    stdout: StdioCollector {
      id: resolverOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: resolverErr
      waitForEnd: true
    }
    onExited: {
      var err = resolverErr.text.trim()
      if (err) console.warn("agx.screen-time: resolver stderr:", err)
      root.applyResolvedApp(resolverOut.text.trim())
    }
  }

  // Keeps the suspend-gap baseline fresh every few seconds so the gap check
  // resolves suspends down to ~30s instead of being locked to the 60s commit
  // cadence. On a detected gap the open bucket is dropped without accrual
  // (closeActiveBucket's gap branch) and tracking restarts from wake time.
  // The Omarchy lock plugin owns the native Wayland session lock. Subscribe
  // to its state instead of polling loginctl, so lock/unlock is handled at
  // the source and screen-time does no extra process spawning.
  //
  // The shell's service registry is populated asynchronously, so the service
  // references are looked up after shell injection and retried during startup
  // until both are found; transitions are event-driven afterward.
  function refreshShellServices() {
    if (!root.shell) return
    root.lockService = root.shell.serviceFor("omarchy.lock")
    root.idleService = root.shell.serviceFor("omarchy.idle")
    if (root.lockService) {
      root.setSessionLocked(root.lockService.locked)
      // The event-driven source is authoritative once reachable; the fallback
      // watcher must not fight it (or keep a bash loop alive) any longer.
      sessionStateWatcher.running = false
    }
    if (root.idleService)
      root.setScreensaverActive(root.idleService.screensaverStartedThisCycle
        || root.idleService.screensaverWindowCount > 0)
    if (root.lockService && root.idleService) {
      serviceLookupTimer.stop()
      root.serviceLookupWarned = false
    }
  }

  function setSessionLocked(locked) {
    locked = locked === true
    if (locked === root.sessionLocked) return
    root.sessionLocked = locked
    if (locked) {
      root.lockStartedAt = Date.now()
      root.cancelResume()
      // Kill any in-flight terminal resolve: its result would otherwise
      // reopen a bucket through the pause (see applyResolvedApp).
      root.resolveInFlight = false
      root.resolveForApp = ""
      if (root.debugLogging) console.warn("agx.screen-time: lock started")
      var now = Date.now()
      applyState(State.closeActiveBucket(
        root, root.activeApp, root.activeStart, now,
        root.todayKey, root.suspendGapMs, root.lastTick))
      root.persist()
    } else {
      var endedAt = Date.now()
      var duration = root.lockStartedAt ? endedAt - root.lockStartedAt : 0
      if (root.debugLogging) console.warn("agx.screen-time: lock ended, duration=" + duration + "ms")
      root.lockStartedAt = 0
      // Defer the resume: with 10s state sources and the idle→lock signal
      // ordering, an "unpaused" reading can be stale (screensaver flag
      // clearing just before the lock engages). applyResume re-validates
      // both flags after a short grace period before reopening a bucket.
      root.scheduleResume()
    }
  }

  function setScreensaverActive(active) {
    active = active === true
    if (active === root.screensaverActive) return
    root.screensaverActive = active
    if (active) {
      root.screensaverStartedAt = Date.now()
      root.cancelResume()
      if (root.debugLogging) console.warn("agx.screen-time: screensaver started")
      var now = Date.now()
      applyState(State.closeActiveBucket(
        root, root.activeApp, root.activeStart, now,
        root.todayKey, root.suspendGapMs, root.lastTick))
      root.persist()
    } else {
      var endedAt = Date.now()
      var duration = root.screensaverStartedAt ? endedAt - root.screensaverStartedAt : 0
      if (root.debugLogging) console.warn("agx.screen-time: screensaver ended, duration=" + duration + "ms")
      root.screensaverStartedAt = 0
      if (!root.sessionLocked) root.scheduleResume()
    }
  }

  // Resume handling. Unpause signals are scheduled, not applied
  // immediately: applyResume re-checks both pause flags after a short
  // grace period, so a stale reading from one 10s state source (e.g. the
  // screensaver flag clearing just before the lock engages during the
  // idle→lock transition) cannot briefly reopen a bucket.
  property bool resumePending: false
  Timer {
    id: resumeTimer
    interval: 2000
    repeat: false
    onTriggered: root.applyResume()
  }
  function scheduleResume() {
    root.resumePending = true
    resumeTimer.restart()
  }
  function cancelResume() {
    root.resumePending = false
    resumeTimer.stop()
  }
  function applyResume() {
    if (root.sessionLocked || root.screensaverActive) {
      root.resumePending = false
      return
    }
    if (!root.resumePending) return
    root.resumePending = false
    // Rebase the accrual baseline to the actual resume instant: the pause
    // may have ended up to two seconds (grace period) ago, and the reopen
    // must not charge time from the stale pre-pause lastTick.
    var now = Date.now()
    root.lastTick = now
    root.switchActive()
  }

  property bool serviceLookupWarned: false

  Timer {
    id: serviceLookupTimer
    interval: 250
    repeat: true
    running: root.ready && (!root.lockService || !root.idleService)
    property int attempts: 0
    onTriggered: {
      root.refreshShellServices()
      attempts++
      if (attempts >= 40 && !root.serviceLookupWarned) {
        // The shell's plugin sandbox may never resolve these services
        // (scoped serviceFor only returns a plugin's own service). Say so
        // once instead of failing invisibly forever.
        root.serviceLookupWarned = true
        console.warn("agx.screen-time: omarchy.lock/omarchy.idle services unavailable after 10s; " +
          "falling back to a persistent lock watcher (~10s pause accuracy)")
      }
    }
  }

  // Fallback when the sandboxed serviceFor() lookups can't reach the
  // first-party lock/idle services: watch lock state through a single
  // persistent watcher process instead of respawning a poll command every
  // few seconds. The loop runs for the whole session, checks the lock once
  // every 10 seconds, and prints a line only when the state changes, so the
  // plugin reacts within ~10s of a lock/unlock with near-zero spawn
  // overhead. Stopped automatically if the event-driven service lookups
  // ever succeed.
  Process {
    id: sessionStateWatcher
    environment: ({ "HOME": root.home })
    command: ["bash", "-c",
      "ppid=$PPID; prev=''; while :; do " +
      // Orphan guard: a SIGKILLed shell leaves this loop running forever
      // (quickshell cannot reap children on the way out); exit once the
      // parent is gone so restarts don't accumulate watchers.
      "kill -0 $ppid 2>/dev/null || exit 0; " +
      "cur=$(omarchy-shell lock isLocked 2>/dev/null); " +
      "if [ -n \"$cur\" ] && [ \"$cur\" != \"$prev\" ]; then printf '%s\\n' \"$cur\"; prev=\"$cur\"; fi; " +
      "sleep 10; done"]
    stdout: SplitParser {
      onRead: function(line) { root.setSessionLocked(String(line).trim() === "true") }
    }
  }

  // Supervisor: (re)starts the watcher if it ever exits while the
  // first-party services remain unreachable.
  Timer {
    id: watcherSupervisorTimer
    interval: 5000
    repeat: true
    running: root.ready && !root.lockService
    onTriggered: {
      if (!root.lockService && !sessionStateWatcher.running) sessionStateWatcher.running = true
    }
  }

  // The screensaver fallback is an in-process toplevel scan (no spawning),
  // so it can simply run every 10 seconds to match the lock watcher.
  // It must only run while the idle service is unreachable — with the
  // service present, its signals below are authoritative.
  Timer {
    id: screensaverScanTimer
    interval: 10000
    repeat: true
    running: root.ready && !root.idleService
    onTriggered: root.setScreensaverActive(root.screensaverWindowVisible())
  }

  // Detects the screensaver without the idle service: omarchy launches it
  // with the fixed app id "org.omarchy.screensaver", so a scan of the
  // toplevel list is a reliable, sandbox-visible proxy for "screensaver up".
  function screensaverWindowVisible() {
    var toplevels = ToplevelManager.toplevels
    if (!toplevels || !toplevels.length) return false
    for (var i = 0; i < toplevels.length; i++) {
      var t = toplevels[i]
      if (t && t.appId && String(t.appId).toLowerCase() === "org.omarchy.screensaver") return true
    }
    return false
  }

  // Event-driven sources, used whenever the sandboxed lookups succeed.
  Connections {
    target: root.lockService
    function onLockedChanged() {
      root.setSessionLocked(root.lockService.locked)
    }
  }

  Connections {
    target: root.idleService
    function onScreensaverStartedThisCycleChanged() {
      root.setScreensaverActive(root.idleService.screensaverStartedThisCycle)
    }
    function onScreensaverWindowCountChanged() {
      root.setScreensaverActive(root.idleService.screensaverWindowCount > 0)
    }
  }

  Timer {
    id: heartbeatTimer
    interval: 5000
    repeat: true
    running: root.ready
    onTriggered: {
      var now = Date.now()
      if (State.isSuspendGap(now, root.lastTick, root.suspendGapMs)) {
        applyState(State.closeActiveBucket(
          root, root.activeApp, root.activeStart, now,
          root.todayKey, root.suspendGapMs, root.lastTick))
        // Waking across midnight must roll the day forward before the fresh
        // post-wake bucket opens, or wake-time seconds land on yesterday.
        root.rolloverIfNeeded()
        root.persist()
        root.switchActive()
      } else {
        root.rolloverIfNeeded()
        root.commitElapsed(now)
        root.persist()
      }
      root.lastTick = now
    }
  }

  Timer {
    id: commitTimer
    interval: 60000
    repeat: true
    running: root.ready
    onTriggered: {
      var now = Date.now()
      root.rolloverIfNeeded()
      root.commitElapsed(now)
      root.persist()
      root.lastTick = now
    }
  }

  Timer {
    id: saveTimer
    interval: 1500
    repeat: false
    onTriggered: historyFile.writeAdapter()
  }

  // Drives save retries with the backoff computed in onSaveFailed.
  Timer {
    id: saveRetryTimer
    repeat: false
    onTriggered: historyFile.writeAdapter()
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() {
      root.switchActive()
    }
  }

  Component.onCompleted: {
    ensureDirProc.running = true
  }
}

