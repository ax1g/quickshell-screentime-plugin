"use strict"

const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const service = fs.readFileSync(
  path.join(__dirname, "..", "Service.qml"),
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
  assert.match(service, /if \(root\.debugLogging\) console\.warn/)
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
  assert.match(service, /setSessionLocked\(String\(line\)\.trim\(\) === "true"\)/)
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
  const watcher = service.match(/Process \{\s*\n\s*id: sessionStateWatcher[\s\S]*?\n  \}/)
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
