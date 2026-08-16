import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model

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
Item {
  id: root

  // Injected by omarchy-shell (the generic service loader).
  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string dataDir: home + "/.config/omarchy/screen-time"
  readonly property string historyPath: dataDir + "/history.json"
  readonly property string resolverPath: {
    var u = Qt.resolvedUrl("resolve_app.py").toString()
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
  readonly property int keepDays: 31

  // A timer tick arriving far later than its cadence means the machine was
  // suspended (or the clock jumped); wall-clock deltas across that gap are
  // not screen time. Mirrors the lock service's suspend-gap heuristic.
  readonly property int suspendGapMs: 5 * 60 * 1000
  property double lastTick: 0

  // ---- Live state, exposed to the bar widget and panel. These are always
  //      REPLACED with fresh objects, never mutated in place, so QML
  //      bindings on them fire and the persistence adapter sees the change.
  property string todayKey: Model.dayKey(new Date())
  property var today: Model.newDay()
  // Full history mirror (dayKey -> day); what the adapter persists.
  property var days: ({})

  property string activeApp: ""
  property double activeStart: 0
  // appId as reported by the compositor; activeApp is the resolved tracking
  // name (identical unless the toplevel is a terminal).
  property string rawApp: ""
  property string resolveForApp: ""
  property bool resolveInFlight: false
  property bool ready: false
  property bool startupPhase: true

  // ---- Public read API for the UI ----------------------------------------
  readonly property string barLabel: today ? Model.fmt(today.total) : ""
  readonly property bool hasActivity: today && today.total > 0

  function appList() { return Model.appList(root.today) }
  function insights() { return Model.insights(root.today, root.days, root.todayKey) }
  function fmt(ms) { return Model.fmt(ms) }
  function relativeDayLabel(key) { return Model.relativeDayLabel(key, root.todayKey) }

  // ---- Tracking ----------------------------------------------------------

  function isTerminal(appId) {
    return appId && root.terminalAppIds.indexOf(appId.toLowerCase()) !== -1
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

  function isSuspendGap(now) {
    return root.lastTick > 0 && (now - root.lastTick) > root.suspendGapMs
  }

  function switchActive() {
    var now = Date.now()
    root.closeActiveBucket(now)
    var tl = ToplevelManager.activeToplevel
    var app = tl && tl.appId ? tl.appId : ""
    root.rawApp = app
    root.resolveInFlight = false
    if (app && !root.shouldTrack(app)) {
      root.activeApp = ""
      root.activeStart = 0
      return
    }
    if (app && root.isTerminal(app)) {
      // Open the bucket once the pty's foreground app is known.
      root.activeApp = ""
      root.activeStart = 0
      root.resolveForApp = app
      root.resolveInFlight = true
      if (!resolverProc.running) resolverProc.running = true
    } else {
      root.activeApp = Model.canonicalApp(app)
      root.activeStart = app ? now : 0
    }
  }

  // Applies a resolver result. Called both for the initial focus resolve and
  // for periodic refreshes while a terminal stays focused (its foreground
  // process can change: opencode -> bash).
  function applyResolvedApp(name) {
    if (!root.resolveInFlight) return
    root.resolveInFlight = false
    if (root.rawApp !== root.resolveForApp) return  // focus moved mid-resolve
    if (!name) name = root.rawApp
    name = Model.canonicalApp(name)
    if (name === root.activeApp) return
    var now = Date.now()
    root.closeActiveBucket(now)
    root.activeApp = name
    root.activeStart = name ? now : 0
  }

  // Closes the open bucket: accrues elapsed ms to the app that was focused
  // when it started. Safe to call with no open bucket.
  function closeActiveBucket(now) {
    if (!root.ready) return
    var app = root.activeApp
    if (!app || !root.activeStart) return
    if (root.isSuspendGap(now)) {
      // The machine was asleep; don't credit the wall-clock gap as screen
      // time. Drop the stale bucket and re-anchor the gap baseline so the
      // next bucket counts from wake time instead of looking like another
      // gap until the commit timer refreshes lastTick.
      root.activeApp = ""
      root.activeStart = 0
      root.lastTick = now
      return
    }
    var dur = Math.max(0, now - root.activeStart)
    var startMs = root.activeStart
    root.activeApp = ""
    root.activeStart = 0
    if (dur <= 0) return

    var startDay = Model.dayKey(new Date(startMs))
    if (startDay === root.todayKey) {
      var apps = Object.assign({}, root.today.apps)
      apps[app] = (apps[app] || 0) + dur
      root.today = { total: root.today.total + dur, apps: apps }
    } else {
      // Bucket spans midnight: attribute it to the day it started on.
      var d = Object.assign({}, root.days)
      var day = d[startDay] || Model.newDay()
      var dApps = Object.assign({}, day.apps || {})
      dApps[app] = (dApps[app] || 0) + dur
      d[startDay] = { total: (day.total || 0) + dur, apps: dApps }
      root.days = d
    }
    root.persist()
  }

  // Bounds crash loss: folds the in-flight bucket into today, then restarts
  // the timer so a crash loses at most the current interval.
  function commitElapsed(now) {
    if (!root.ready || !root.activeApp || !root.activeStart) return
    if (root.isSuspendGap(now)) {
      root.activeStart = now
      return
    }
    var dur = Math.max(0, now - root.activeStart)
    if (dur <= 0) return
    var apps = Object.assign({}, root.today.apps)
    apps[root.activeApp] = (apps[root.activeApp] || 0) + dur
    root.today = { total: root.today.total + dur, apps: apps }
    root.activeStart = now
    root.persist()
  }

  function rolloverIfNeeded() {
    var key = Model.dayKey(new Date())
    if (key === root.todayKey) return
    var app = root.activeApp
    root.closeActiveBucket(Date.now())
    root.todayKey = key
    // A bucket may already have been folded onto the new day before this
    // rollover ran (focus switch across midnight); carry it forward.
    var prev = root.days[key]
    root.today = prev && typeof prev === "object"
      ? { total: prev.total || 0, apps: Object.assign({}, prev.apps || {}) }
      : Model.newDay()
    // Reopen the still-focused app's bucket so tracking keeps running past
    // midnight without a focus change; the closed bucket went to the day it
    // started on.
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
    merged = Model.pruneDays(merged, root.todayKey, root.keepDays)
    root.days = merged
    historyAdapter.days = merged
  }

  function scheduleSave() {
    if (root.startupPhase) return
    saveTimer.restart()
  }

  function onHistoryLoaded() {
    var d = historyAdapter.days && typeof historyAdapter.days === "object" ? historyAdapter.days : {}
    d = Model.pruneDays(d, Model.dayKey(new Date()), root.keepDays)
    root.days = d
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
    }
  }

  Process {
    id: ensureDirProc
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
    onTriggered: {
      root.resolveForApp = root.rawApp
      root.resolveInFlight = true
      if (!resolverProc.running) resolverProc.running = true
    }
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
  Process {
    id: resolverProc
    command: ["python3", root.resolverPath]
    stdout: StdioCollector {
      id: resolverOut
      waitForEnd: true
    }
    onExited: {
      root.applyResolvedApp(resolverOut.text.trim())
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
