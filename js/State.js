// Pure state machine: explicit inputs, fresh outputs, no side effects.
// Service.qml owns timers, disk and processes; this owns transitions.

// Model is imported by QML's import mechanism (global scope). For Node.js
// testing, require it explicitly. The guard avoids shadowing the QML global.
var Model =
  typeof module !== "undefined" && module && module.exports
    ? require("./Model.js")
    : typeof Model !== "undefined"
      ? Model
      : null

function modelFor(state) {
  return state && state.stateModel ? state.stateModel : Model
}

function isSuspendGap(now, lastTick, suspendGapMs) {
  return lastTick > 0 && now - lastTick > suspendGapMs
}

function accumulateBucket(today, app, dur) {
  if (!app || dur <= 0) return today
  var apps = Object.assign({}, today.apps)
  apps[app] = (apps[app] || 0) + dur
  return { total: today.total + dur, apps: apps }
}

// Unmirrored delta of live day over history mirror, floored at zero.
function dayMinus(full, base) {
  var f = full && typeof full === "object" ? full : { total: 0, apps: {} }
  var b = base && typeof base === "object" ? base : { total: 0, apps: {} }
  var fa = f.apps && typeof f.apps === "object" ? f.apps : {}
  var ba = b.apps && typeof b.apps === "object" ? b.apps : {}
  var apps = {}
  var total = 0
  for (var app in fa) {
    if (!Object.prototype.hasOwnProperty.call(fa, app)) continue
    var rest = (Number(fa[app]) || 0) - (Number(ba[app]) || 0)
    if (rest > 0) {
      apps[app] = rest
      total += rest
    }
  }
  return { total: total, apps: apps }
}

// Close the open bucket onto its start day; suspend gaps drop it.
function closeActiveBucket(
  state,
  activeApp,
  activeStart,
  now,
  todayKey,
  suspendGapMs,
  lastTick,
) {
  if (!activeApp || !activeStart) return state
  if (isSuspendGap(now, lastTick, suspendGapMs)) {
    return {
      today: state.today,
      days: state.days,
      todayKey: state.todayKey,
      activeApp: "",
      activeStart: 0,
      lastTick: now,
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
      lastTick: state.lastTick,
    }
  }
  // Bucket spans midnight: split at midnight like commitElapsed — the
  // pre-midnight portion lands on the start day, the rest on today.
  var dt = new Date(now)
  var midnightMs = new Date(
    dt.getFullYear(),
    dt.getMonth(),
    dt.getDate(),
  ).getTime()
  var yesterdayDur = Math.max(0, Math.min(dur, midnightMs - activeStart))
  var todayDur = dur - yesterdayDur
  var d = Object.assign({}, state.days)
  if (yesterdayDur > 0) {
    var day = d[startDay] || model.newDay()
    d[startDay] = accumulateBucket(day, activeApp, yesterdayDur)
  }
  return {
    today:
      todayDur > 0
        ? accumulateBucket(state.today, activeApp, todayDur)
        : state.today,
    days: d,
    todayKey: state.todayKey,
    activeApp: "",
    activeStart: 0,
    lastTick: state.lastTick,
  }
}

// Fold in-flight time in but keep the bucket open.
function commitElapsed(
  state,
  activeApp,
  activeStart,
  now,
  todayKey,
  suspendGapMs,
  lastTick,
) {
  if (!activeApp || !activeStart) return state
  if (isSuspendGap(now, lastTick, suspendGapMs)) {
    return {
      today: state.today,
      days: state.days,
      todayKey: state.todayKey,
      activeApp: activeApp,
      activeStart: now,
      lastTick: state.lastTick,
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
      lastTick: state.lastTick,
    }
  }
  // Midnight split: yesterday's share to history, fresh bucket from midnight.
  var dt = new Date(now)
  var midnightMs = new Date(
    dt.getFullYear(),
    dt.getMonth(),
    dt.getDate(),
  ).getTime()
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
    lastTick: state.lastTick,
  }
}

// Carry the live bucket into a new calendar day; null when unneeded.
function rolloverIfNeeded(state, newKey) {
  if (newKey === state.todayKey) return null
  var model = modelFor(state)
  var prev = state.days[newKey]
  var newToday =
    prev && typeof prev === "object"
      ? { total: prev.total || 0, apps: Object.assign({}, prev.apps || {}) }
      : model.newDay()
  return {
    todayKey: newKey,
    today: newToday,
    activeApp: state.activeApp,
    activeStart: 0,
  }
}

// Midnight in one transition (close+carry+reopen); null when unneeded.
function advanceRollover(state, now, newKey, suspendGapMs, lastTick) {
  if (newKey === state.todayKey) return null
  var app = state.activeApp
  // Close against the NEW day so the split attributes each portion exactly.
  var closed = closeActiveBucket(
    state,
    state.activeApp,
    state.activeStart,
    now,
    newKey,
    suspendGapMs,
    lastTick,
  )
  var patch = rolloverIfNeeded(closed, newKey)
  patch.activeApp = app
  patch.activeStart = app ? now : 0
  // Carry the split-off yesterday portion along or lose it.
  var d = Object.assign({}, closed.days)
  // Flush unmirrored data first, computed pre-growth to avoid double count.
  var delta = dayMinus(
    state.today,
    state.days ? state.days[state.todayKey] : null,
  )
  if (delta.total > 0) {
    var old =
      d[state.todayKey] && typeof d[state.todayKey] === "object"
        ? d[state.todayKey]
        : { total: 0, apps: {} }
    var apps = Object.assign({}, old.apps)
    var total = old.total || 0
    for (var dk in delta.apps) {
      if (!Object.prototype.hasOwnProperty.call(delta.apps, dk)) continue
      apps[dk] = (apps[dk] || 0) + delta.apps[dk]
      total += delta.apps[dk]
    }
    d[state.todayKey] = { total: total, apps: apps }
  }
  patch.days = d
  // Fold post-midnight growth into the carried day.
  var grown =
    (closed.today ? closed.today.total : 0) -
    (state.today ? state.today.total : 0)
  if (grown > 0 && app) patch.today = accumulateBucket(patch.today, app, grown)
  // closeActiveBucket decides lastTick (wake time on a gap, untouched
  // otherwise); the rollover carry must not lose that decision.
  if (closed.lastTick !== undefined) patch.lastTick = closed.lastTick
  return patch
}

// Apply a terminal resolve; null when stale or unchanged.
function applyResolvedApp(
  state,
  name,
  resolveForApp,
  todayKey,
  suspendGapMs,
  lastTick,
) {
  if (!state.resolveInFlight) return null
  // Same-terminal switches keep rawApp; only the generation token proves freshness.
  if (state.resolveSpawnGen !== state.resolveGeneration) return null
  if (state.rawApp !== resolveForApp) return null
  if (!name) name = state.rawApp
  name = modelFor(state).canonicalApp(name)
  if (name === state.activeApp) return null
  var now = Date.now()
  var closed = closeActiveBucket(
    state,
    state.activeApp,
    state.activeStart,
    now,
    todayKey,
    suspendGapMs,
    lastTick,
  )
  return {
    resolveInFlight: false,
    activeApp: name,
    activeStart: name ? now : 0,
    today: closed.today,
    days: closed.days,
    lastTick: closed.lastTick,
  }
}

if (typeof module !== "undefined" && module && module.exports) {
  module.exports = {
    isSuspendGap: isSuspendGap,
    accumulateBucket: accumulateBucket,
    dayMinus: dayMinus,
    closeActiveBucket: closeActiveBucket,
    commitElapsed: commitElapsed,
    rolloverIfNeeded: rolloverIfNeeded,
    advanceRollover: advanceRollover,
    applyResolvedApp: applyResolvedApp,
  }
}
