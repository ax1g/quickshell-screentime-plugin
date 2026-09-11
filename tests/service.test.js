"use strict"

const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const service = fs.readFileSync(
  path.join(__dirname, "..", "qml", "Service.qml"),
  "utf8",
)

test("service tracks lock and screensaver state", () => {
  assert.match(service, /property bool sessionLocked: false/)
  assert.match(service, /property bool screensaverActive: false/)
  assert.match(service, /serviceFor\("omarchy\.lock"\)/)
  assert.match(service, /serviceFor\("omarchy\.idle"\)/)
  assert.match(service, /function setSessionLocked\(locked\)/)
  assert.match(service, /function setScreensaverActive\(active\)/)
})

test("lock and screensaver transitions close and persist the active bucket", () => {
  assert.match(
    service,
    /function setSessionLocked[\s\S]*?State\.closeActiveBucket\([\s\S]*?root\.persist\(\)/,
  )
  assert.match(
    service,
    /function setScreensaverActive[\s\S]*?State\.closeActiveBucket\([\s\S]*?root\.persist\(\)/,
  )
})

test("screen-time debugging is opt-in", () => {
  assert.match(service, /property bool debugLogging: false/)
  assert.match(service, /if \(root\.debugLogging\)\s+console\.warn/)
})

test("pause keeps buckets closed against reopen paths", () => {
  // Focus events and reconcile ticks during lock must not reopen a bucket.
  assert.match(
    service,
    /function switchActive[\s\S]*?root\.sessionLocked \|\| root\.screensaverActive[\s\S]*?root\.activeApp = ""[\s\S]*?root\.activeStart = 0/,
  )
  // A resolver landing during the pause must not reopen a bucket either.
  assert.match(
    service,
    /function applyResolvedApp[\s\S]*?root\.sessionLocked \|\| root\.screensaverActive[\s\S]*?root\.resolveForApp = ""/,
  )
  // Locking kills any in-flight resolve.
  assert.match(
    service,
    /if \(locked\) \{[\s\S]*?root\.resolveForApp = ""[\s\S]*?lock started/,
  )
})

test("falls back to a persistent lock watcher when services are unavailable", () => {
  // Scoped plugin shells may never resolve the lock/idle services; the
  // plugin must say so once and watch instead of accruing through locks.
  assert.match(service, /property bool serviceLookupWarned: false/)
  assert.match(service, /id: sessionStateWatcher/)
  assert.match(service, /omarchy-shell lock isLocked/)
  // Exits when its parent shell dies, so restarts don't accumulate watchers.
  assert.match(service, /kill -0 \$ppid 2>\/dev\/null \|\| exit 0/)
  // Single persistent watcher (change-only output), not a respawning poll.
  assert.match(service, /SplitParser/)
  assert.match(
    service,
    /setSessionLocked\(String\(line\)\.trim\(\) === "true"\)/,
  )
  assert.doesNotMatch(service, /id: lockPollProc/)
  assert.doesNotMatch(service, /StdioCollector \{\s*\n\s*id: lockPollOut/)
  // Watcher is supervised while the lock service is unreachable, and
  // stopped the moment the event-driven path becomes available.
  assert.match(service, /id: watcherSupervisorTimer/)
  assert.match(service, /running: root\.ready && !root\.lockService/)
  assert.match(
    service,
    /if \(root\.lockService\) \{\s*\n\s*root\.setSessionLocked[\s\S]*?sessionStateWatcher\.running = false/,
  )
  // The screensaver fallback is an in-process scan, no spawning.
  assert.match(service, /id: screensaverScanTimer/)
  assert.match(service, /running: root\.ready && !root\.idleService/)
  assert.match(service, /function screensaverWindowVisible/)
  // The watcher feeds the same pause state machine; no bucket handling in
  // the watcher process block.
  const watcher = service.match(
    /Process \{\s*\n\s*id: sessionStateWatcher[\s\S]*?\n    \}/,
  )
  assert(watcher, "sessionStateWatcher block exists")
  assert(!watcher[0].includes("closeActiveBucket"))
})

test("resume after pause is deferred and re-validated", () => {
  // Unlock/screensaver-dismissal schedules a resume instead of reopening
  // immediately, so a stale reading from a ~10s state source cannot
  // briefly reopen a bucket.
  assert.match(service, /function scheduleResume/)
  assert.match(service, /function cancelResume/)
  assert.match(
    service,
    /function applyResume[\s\S]*?if \(root\.sessionLocked \|\| root\.screensaverActive\) \{[\s\S]*?return/,
  )
  assert.match(service, /root\.scheduleResume\(\)/)
  // Locking or starting the screensaver cancels any pending resume.
  const lockStart = service.match(/if \(locked\) \{[\s\S]*?\n    \}/)
  assert(lockStart && lockStart[0].includes("root.cancelResume()"))
  const ssStart = service.match(/if \(active\) \{[\s\S]*?\n    \}/)
  assert(ssStart && ssStart[0].includes("root.cancelResume()"))
})

test("warns once instead of failing silently when services never appear", () => {
  assert.match(service, /services unavailable after 10s/)
})

test("tracking prefs filter ignored apps and rename via aliases", () => {
  assert.match(service, /property var ignoredApps: \[\]/)
  assert.match(service, /property var appAliases: \(\{\}\)/)
  assert.match(service, /function setTrackingPrefs\(ignored, aliases\)/)
  assert.match(service, /Model\.parseIgnoredApps\(ignored\)/)
  assert.match(service, /Model\.parseAppAliases\(aliases\)/)
  assert.match(service, /Model\.isIgnoredApp\(appId, root\.ignoredApps\)/)
  assert.match(service, /Model\.resolveAppName\(app, root\.appAliases\)/)
})

test("resetAll wipes days, months and archive, then persists", () => {
  assert.match(service, /function resetAll\(\)/)
  const reset = service.match(/function resetAll\(\) \{[\s\S]*?\n    \}/)
  assert(reset, "resetAll block exists")
  assert(reset[0].includes("root.today = Model.newDay()"))
  assert(reset[0].includes("root.days = {}"))
  assert(reset[0].includes("root.months = {}"))
  assert(reset[0].includes("root.years = {}"))
  assert(reset[0].includes("historyAdapter.months = {}"))
  assert(reset[0].includes("historyAdapter.years = {}"))
  assert(reset[0].includes("root.persist()"))
  assert(reset[0].includes("root.activeStart = now"))
})

test("changed aliases refold today and rename the live bucket", () => {
  assert.match(service, /function refoldToday\(aliases\)/)
  const refold = service.match(
    /function refoldToday\(aliases\) \{[\s\S]*?\n    \}/,
  )
  assert(refold, "refoldToday block exists")
  assert(refold[0].includes("var map = aliases || root.appAliases"))
  assert(refold[0].includes("root.commitElapsed(now)"))
  assert(refold[0].includes("Model.refoldDay(root.today, map)"))
  assert(refold[0].includes("nd[root.todayKey] = root.today"))
  assert(refold[0].includes("Model.resolveAppName(previous, map)"))
  assert(refold[0].includes("root.persist()"))
  // setTrackingPrefs refolds only when the alias map actually changed.
  assert.match(
    service,
    /Model\.serializeAliases\(nextAliases\) !== Model\.serializeAliases\(root\.appAliases\)/,
  )
})

test("debounced saves cannot starve under focus flapping", () => {
  const schedule = service.match(/function scheduleSave\(\) \{[\s\S]*?\n    \}/)
  assert(schedule, "scheduleSave block exists")
  assert(schedule[0].includes("if (!saveTimer.running)"))
  assert(!schedule[0].includes("saveTimer.restart()"))
})

test("pre-ready focus opens no bucket and load failure re-keys today", () => {
  const sw = service.match(/function switchActive\(\) \{[\s\S]*?\n    \}/)
  assert(sw, "switchActive block exists")
  assert(sw[0].includes("if (!root.ready)"))
  const failed = service.match(
    /function onHistoryLoadFailed\(\) \{[\s\S]*?\n    \}/,
  )
  assert(failed, "onHistoryLoadFailed block exists")
  assert(failed[0].includes("root.todayKey = Model.dayKey(new Date())"))
})

test("ignoring the focused app evicts its live bucket", () => {
  const prefs = service.match(
    /function setTrackingPrefs\(ignored, aliases\) \{[\s\S]*?\n    \}/,
  )
  assert(prefs, "setTrackingPrefs block exists")
  assert(
    prefs[0].includes("Model.isIgnoredApp(root.activeApp, root.ignoredApps)"),
  )
  assert(prefs[0].includes("State.closeActiveBucket"))
  assert(prefs[0].includes('root.activeApp = ""'))
})

test("corrupt history is set aside without depending on python", () => {
  const backup = service.match(/id: backupProc[\s\S]*?\n    \}/)
  assert(backup, "backupProc block exists")
  assert(backup[0].includes("[[ -s "))
  assert(backup[0].includes(".corrupt-$(date +%s)"))
  assert(!backup[0].includes("|| exit 0"), "no early exit without python")
})
