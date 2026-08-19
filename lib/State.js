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

  var startDay = Model.dayKey(new Date(activeStart))
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
  // Bucket spans midnight: attribute to the day it started on.
  var d = Object.assign({}, state.days)
  var day = d[startDay] || Model.newDay()
  d[startDay] = accumulateBucket(day, activeApp, dur)
  return {
    today: state.today,
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

  var startDay = Model.dayKey(new Date(activeStart))
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
  var d = new Date(now)
  var midnightMs = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
  var yesterdayDur = Math.max(0, midnightMs - activeStart)
  var d = Object.assign({}, state.days)
  if (yesterdayDur > 0) {
    var day = d[startDay] || Model.newDay()
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
  var prev = state.days[newKey]
  var newToday = prev && typeof prev === "object"
    ? { total: prev.total || 0, apps: Object.assign({}, prev.apps || {}) }
    : Model.newDay()
  return {
    todayKey: newKey,
    today: newToday,
    activeApp: state.activeApp,
    activeStart: 0
  }
}

// Applies a terminal resolver result.  Returns null when the result
// should be ignored (focus moved mid-resolve or name unchanged).
// Returns a partial state patch when the resolved name opens a new
// bucket.  lastTick is forwarded so the caller can update it.
function applyResolvedApp(state, name, resolveForApp, todayKey, suspendGapMs, lastTick) {
  if (!state.resolveInFlight) return null
  if (state.rawApp !== resolveForApp) return null
  if (!name) name = state.rawApp
  name = Model.canonicalApp(name)
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
    applyResolvedApp: applyResolvedApp
  }
}
