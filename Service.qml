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
  // Monthly aggregates (YYYY-MM -> ms). Days dropped by the retention window
  // are rolled up here so calendar year/month totals survive pruning.
  property var months: ({})

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

  // ---- Public read API for the UI ----------------------------------------
  readonly property string barLabel: today ? Model.fmt(today.total) : ""
  readonly property bool hasActivity: today && today.total > 0

  function appList() { return Model.appList(root.today) }
  function insights() { return Model.insights(root.today, root.days, root.todayKey) }
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
    var patch = State.rolloverIfNeeded(root, key)
    if (!patch) return
    var now = Date.now()
    var app = root.activeApp

    // Close the open bucket first so its elapsed time lands on the day it
    // started (the bucket may still be on yesterday). rolloverIfNeeded's
    // patch then carries the live today into the new calendar day. We close
    // and reopen rather than leaving the bucket straddling midnight because
    // commitElapsed already handles mid-commit splits conservatively; this
    // path is the authoritative midnight transition where attribution must
    // be exact.
    applyState(State.closeActiveBucket(
      root, root.activeApp, root.activeStart, now,
      root.todayKey, root.suspendGapMs, root.lastTick))
    applyState(patch)

    // Reopen a fresh bucket for the still-focused app so tracking continues
    // past midnight without waiting for a focus change.
    root.activeApp = app
    root.activeStart = app ? Date.now() : 0
    root.persist()
  }

  // ---- Persistence -------------------------------------------------------

  // Reassigns a fresh top-level object so the JsonAdapter's notifier fires,
  // which schedules the debounced disk write. The live in-memory day is
  // folded into the mirror first — root.today is the source of truth while
  // root.days mirrors what is on disk.
  function persist() {
    if (root.startupPhase) return
    var merged = Object.assign({}, root.days)
    merged[root.todayKey] = root.today
    var kept = Model.pruneDays(merged, root.todayKey, root.keepDays)
    if (kept !== merged) {
      // Days dropped by retention roll up into monthly aggregates so the
      // calendar view keeps year-scale totals after raw days expire.
      var pruned = {}
      for (var k in merged) {
        if (Object.prototype.hasOwnProperty.call(merged, k) && !Object.prototype.hasOwnProperty.call(kept, k)) pruned[k] = merged[k]
      }
      root.months = Model.rollupPrunedDays(root.months, pruned)
      historyAdapter.months = root.months
    }
    root.days = kept
    historyAdapter.days = kept
  }

  function scheduleSave() {
    if (root.startupPhase) return
    saveTimer.restart()
  }

  function onHistoryLoaded() {
    var d = historyAdapter.days && typeof historyAdapter.days === "object" ? historyAdapter.days : {}
    var m = historyAdapter.months && typeof historyAdapter.months === "object" ? historyAdapter.months : {}
    var kept = Model.pruneDays(d, Model.dayKey(new Date()), root.keepDays)
    if (kept !== d) {
      // Same rollup as persist(): load-time retention drops also feed the
      // monthly aggregates instead of being lost.
      var pruned = {}
      for (var k in d) {
        if (Object.prototype.hasOwnProperty.call(d, k) && !Object.prototype.hasOwnProperty.call(kept, k)) pruned[k] = d[k]
      }
      m = Model.rollupPrunedDays(m, pruned)
      historyAdapter.months = m
    }
    root.months = m
    root.days = kept
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
    console.warn("agx.screen-time: history load failed, starting empty")
    if (!root.backupAttempted) {
      root.backupAttempted = true
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
    onAdapterUpdated: root.scheduleSave()
    onLoaded: root.onHistoryLoaded()
    onLoadFailed: root.onHistoryLoadFailed()

    JsonAdapter {
      id: historyAdapter
      property var days: ({})
      property var months: ({})
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
      "f=\"$HOME/.config/omarchy/screen-time/history.json\"; if [[ -s \"$f\" ]] && ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \"$f\" 2>/dev/null; then mv -f \"$f\" \"$f.corrupt-$(date +%s)\"; fi"]
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
  Process {
    id: resolverProc
    command: ["python3", root.resolverPath]
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
