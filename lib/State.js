// State machine for the screen-time service.
//
// Pure functions: every input is passed explicitly, every output is a new
// object.  No Date.now(), no Qt, no side effects — fully testable in
// Node.js.
//
// Service.qml owns the side effects (timers, disk writes, process
// spawning); this module owns the state transitions.

// Model is imported by QML's import mechanism (global scope). For Node.js
// testing, require it explicitly. The guard avoids shadowing the QML global.
var Model = (typeof module !== "undefined" && module && module.exports)
  ? require("./Model.js")
  : (typeof Model !== "undefined" ? Model : null)

function modelFor(state) {
  return state && state.stateModel ? state.stateModel : Model
}

function isSuspendGap(now, lastTick, suspendGapMs) {
  return lastTick > 0 && (now - lastTick) > suspendGapMs
}

function accumulateBucket(today, app, dur) {
  if (!app || dur <= 0) return today
  var apps = Object.assign({}, today.apps)
  apps[app] = (apps[app] || 0) + dur
  return { total: today.total + dur, apps: apps }
}

// Closes the open bucket: accrues elapsed ms to the app that was focused
// when it started.  Handles suspend detection (drop the stale bucket) and
// midnight attribution (bucket goes to the day it started on).
function closeActiveBucket(state, activeApp, activeStart, now, todayKey, suspendGapMs, lastTick) {
  if (!activeApp || !activeStart) return state
  if (isSuspendGap(now, lastTick, suspendGapMs)) {
    return {
      today: state.today,
      days: state.days,
      todayKey: state.todayKey,
      activeApp: "",
      activeStart: 0,
      lastTick: now
    }
  }
  var dur = Math.max(0, now - activeStart)
  if (dur <= 0) return state

  var model = modelFor(state)
  var startDay = model.dayKey(new Date(activeStart))
  if (startDay === todayKey) {
    return {
      today: accumulateBucket(state.today, activeApp, dur),
      days: state.days,
      todayKey: state.todayKey,
      activeApp: "",
      activeStart: 0,
      lastTick: state.lastTick
    }
  }
  // Bucket spans midnight: split at midnight like commitElapsed — the
  // pre-midnight portion lands on the start day, the rest on today.
  var dt = new Date(now)
  var midnightMs = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate()).getTime()
  var yesterdayDur = Math.max(0, Math.min(dur, midnightMs - activeStart))
  var todayDur = dur - yesterdayDur
  var d = Object.assign({}, state.days)
  if (yesterdayDur > 0) {
    var day = d[startDay] || model.newDay()
    d[startDay] = accumulateBucket(day, activeApp, yesterdayDur)
  }
  return {
    today: todayDur > 0 ? accumulateBucket(state.today, activeApp, todayDur) : state.today,
    days: d,
    todayKey: state.todayKey,
    activeApp: "",
    activeStart: 0,
    lastTick: state.lastTick
  }
}

// Crash-safety net: folds the in-flight bucket into the correct day(s),
// then resets activeStart so a crash loses at most the current interval.
// Unlike closeActiveBucket, this does NOT clear activeApp — the bucket
// stays open for continued tracking.
function commitElapsed(state, activeApp, activeStart, now, todayKey, suspendGapMs, lastTick) {
  if (!activeApp || !activeStart) return state
  if (isSuspendGap(now, lastTick, suspendGapMs)) {
    return {
      today: state.today,
      days: state.days,
      todayKey: state.todayKey,
      activeApp: activeApp,
      activeStart: now,
      lastTick: state.lastTick
    }
  }
  var dur = Math.max(0, now - activeStart)
  if (dur <= 0) return state

  var model = modelFor(state)
  var startDay = model.dayKey(new Date(activeStart))
  if (startDay === todayKey) {
    // Entire bucket belongs to today — simple case.
    var newToday = accumulateBucket(state.today, activeApp, dur)
    return {
      today: newToday,
      days: state.days,
      todayKey: state.todayKey,
      activeApp: activeApp,
      activeStart: now,
      lastTick: state.lastTick
    }
  }
  // Bucket spans midnight: close yesterday's portion into the history
  // mirror, and leave a fresh bucket starting at midnight for today.
  // This way crash-safe commits never credit pre-midnight time to today;
  // the final closeActiveBucket will handle the full attribution.
  var dt = new Date(now)
  var midnightMs = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate()).getTime()
  var yesterdayDur = Math.max(0, midnightMs - activeStart)
  var d = Object.assign({}, state.days)
  if (yesterdayDur > 0) {
    var day = d[startDay] || model.newDay()
    d[startDay] = accumulateBucket(day, activeApp, yesterdayDur)
  }
  return {
    today: state.today,
    days: d,
    todayKey: state.todayKey,
    activeApp: activeApp,
    activeStart: midnightMs,
    lastTick: state.lastTick
  }
}

// Midnight rollover: checks if the calendar day has changed and, if so,
// returns the state transition to carry the live bucket forward.  Returns
// null when no rollover is needed (caller does nothing).
function rolloverIfNeeded(state, newKey) {
  if (newKey === state.todayKey) return null
  var model = modelFor(state)
  var prev = state.days[newKey]
  var newToday = prev && typeof prev === "object"
    ? { total: prev.total || 0, apps: Object.assign({}, prev.apps || {}) }
    : model.newDay()
  return {
    todayKey: newKey,
    today: newToday,
    activeApp: state.activeApp,
    activeStart: 0
  }
}

// Midnight in one transition: closes the open bucket onto the day it
// started (dropping it on a suspend gap), carries the live day into the
// new calendar day, and reopens a fresh bucket for the still-focused app
// so tracking continues without waiting for a focus change.  Returns null
// when no rollover is needed.  This fuses what Service.qml used to do as
// close -> patch -> reopen across three separate state applications, so
// the straddling seconds cannot be misattributed by an ordering slip.
function advanceRollover(state, now, newKey, suspendGapMs, lastTick) {
  if (newKey === state.todayKey) return null
  var app = state.activeApp
  // Close against the NEW day: the bucket started on the old day, so the
  // midnight-split branch attributes each portion exactly. (Closing against
  // the old day would dump the whole straddling bucket into the orphaned
  // today object, where the carry then loses it to the wrong date.)
  var closed = closeActiveBucket(
    state, state.activeApp, state.activeStart, now,
    newKey, suspendGapMs, lastTick
  )
  var patch = rolloverIfNeeded(closed, newKey)
  patch.activeApp = app
  patch.activeStart = app ? now : 0
  // The carry patch has no days key; the split-off yesterday portion from
  // the close must ride along or it is lost.
  patch.days = closed.days
  // The close accrued the post-midnight share into the OLD today object,
  // which the carry replaces. Fold that growth into the carried day so the
  // straddling seconds survive the transition.
  var grown = (closed.today ? closed.today.total : 0)
    - (state.today ? state.today.total : 0)
  if (grown > 0 && app) patch.today = accumulateBucket(patch.today, app, grown)
  // closeActiveBucket decides lastTick (wake time on a gap, untouched
  // otherwise); the rollover carry must not lose that decision.
  if (closed.lastTick !== undefined) patch.lastTick = closed.lastTick
  return patch
}

// Applies a terminal resolver result.  Returns null when the result
// should be ignored (focus moved mid-resolve, result belongs to a
// superseded resolve request, or name unchanged).  Returns a partial
// state patch when the resolved name opens a new bucket.  lastTick is
// forwarded so the caller can update it.
function applyResolvedApp(state, name, resolveForApp, todayKey, suspendGapMs, lastTick) {
  if (!state.resolveInFlight) return null
  // appId strings alone cannot prove freshness: switching between two
  // windows of the same terminal keeps rawApp === resolveForApp.  The
  // generation token does — it changes on every resolve request, and an
  // in-flight process spawned under an older token carries that token's
  // result.
  if (state.resolveSpawnGen !== state.resolveGeneration) return null
  if (state.rawApp !== resolveForApp) return null
  if (!name) name = state.rawApp
  name = modelFor(state).canonicalApp(name)
  if (name === state.activeApp) return null
  var now = Date.now()
  var closed = closeActiveBucket(
    state, state.activeApp, state.activeStart, now,
    todayKey, suspendGapMs, lastTick
  )
  return {
    resolveInFlight: false,
    activeApp: name,
    activeStart: name ? now : 0,
    today: closed.today,
    days: closed.days,
    lastTick: closed.lastTick
  }
}

if (typeof module !== "undefined" && module && module.exports) {
  module.exports = {
    isSuspendGap: isSuspendGap,
    accumulateBucket: accumulateBucket,
    closeActiveBucket: closeActiveBucket,
    commitElapsed: commitElapsed,
    rolloverIfNeeded: rolloverIfNeeded,
    advanceRollover: advanceRollover,
    applyResolvedApp: applyResolvedApp
  }
}
