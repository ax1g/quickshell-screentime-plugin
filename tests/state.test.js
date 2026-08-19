"use strict"

const { test } = require("node:test")
const assert = require("node:assert/strict")
const State = require("../lib/State.js")
const Model = require("../lib/Model.js")

// Helper: epoch ms for a local-time date at midnight.
function localMidnight(year, month, day) {
  return new Date(year, month, day).getTime()
}
// Helper: epoch ms for a local-time date at a given hour:minute:second.
function localTime(year, month, day, h, m, s) {
  return new Date(year, month, day, h, m, s || 0).getTime()
}

// ---- isSuspendGap --------------------------------------------------------

test("isSuspendGap returns false when lastTick is 0", () => {
  assert.equal(State.isSuspendGap(1000, 0, 30000), false)
})

test("isSuspendGap returns false when gap is under threshold", () => {
  assert.equal(State.isSuspendGap(10000, 5000, 30000), false)
})

test("isSuspendGap returns false when gap equals threshold", () => {
  assert.equal(State.isSuspendGap(30000, 0, 30000), false)
})

test("isSuspendGap returns true when gap exceeds threshold", () => {
  assert.equal(State.isSuspendGap(100000, 50000, 30000), true)
})

// ---- accumulateBucket ----------------------------------------------------

test("accumulateBucket adds duration to the correct app", () => {
  const today = { total: 1000, apps: { editor: 500 } }
  const result = State.accumulateBucket(today, "browser", 3000)
  assert.equal(result.total, 4000)
  assert.equal(result.apps.browser, 3000)
  assert.equal(result.apps.editor, 500)
})

test("accumulateBucket merges with existing app time", () => {
  const today = { total: 1000, apps: { editor: 500 } }
  const result = State.accumulateBucket(today, "editor", 500)
  assert.equal(result.total, 1500)
  assert.equal(result.apps.editor, 1000)
})

test("accumulateBucket returns a new object (immutability)", () => {
  const today = { total: 1000, apps: { a: 500 } }
  const result = State.accumulateBucket(today, "b", 200)
  assert.notEqual(result, today)
  assert.notEqual(result.apps, today.apps)
})

test("accumulateBucket returns original when dur is zero", () => {
  const today = { total: 1000, apps: { a: 500 } }
  assert.equal(State.accumulateBucket(today, "a", 0), today)
})

test("accumulateBucket returns original when app is empty", () => {
  const today = { total: 1000, apps: { a: 500 } }
  assert.equal(State.accumulateBucket(today, "", 5000), today)
})

// ---- closeActiveBucket ---------------------------------------------------

test("closeActiveBucket returns original state when no bucket open", () => {
  const state = { today: { total: 100, apps: {} }, days: {}, todayKey: "2026-08-15" }
  const result = State.closeActiveBucket(state, "", 0, 100000, "2026-08-15", 30000, 90000)
  assert.deepEqual(result.today, state.today)
  assert.deepEqual(result.days, state.days)
})

test("closeActiveBucket credits time to today when no midnight crossing", () => {
  const aug15 = localMidnight(2026, 7, 15)
  const startMs = aug15 + 10 * 3600000          // Aug 15 10:00:00
  const now = aug15 + 10 * 3600000 + 5000       // Aug 15 10:00:05
  const state = {
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-08-15"
  }
  const result = State.closeActiveBucket(state, "editor", startMs, now, "2026-08-15", 30000, now - 2000)
  assert.equal(result.today.total, 5000)
  assert.equal(result.today.apps.editor, 5000)
})

test("closeActiveBucket drops bucket on suspend gap", () => {
  const state = {
    today: { total: 100, apps: { a: 100 } },
    days: {},
    todayKey: "2026-08-15"
  }
  // lastTick=5000, now=100000 => gap=95000 > 30000 => suspend detected
  const result = State.closeActiveBucket(state, "editor", 95000, 100000, "2026-08-15", 30000, 5000)
  assert.equal(result.today.total, 100)
  assert.equal(result.lastTick, 100000)
  assert.equal(result.activeApp, "")
  assert.equal(result.activeStart, 0)
})

test("closeActiveBucket attributes to yesterday when bucket spans midnight", () => {
  // Use local midnight to avoid timezone issues.
  const aug15 = localMidnight(2026, 7, 15)
  const aug16 = localMidnight(2026, 7, 16)
  const startMs = aug15 + 23 * 3600000 + 59 * 60000 + 50000  // Aug 15 23:59:50
  const now = aug16 + 5000                                      // Aug 16 00:00:05

  const state = {
    today: { total: 100, apps: {} },
    days: {},
    todayKey: "2026-08-16"
  }
  const result = State.closeActiveBucket(state, "editor", startMs, now, "2026-08-16", 30000, 0)
  // Bucket goes to 2026-08-15, not today
  assert.equal(result.today.total, 100)
  assert.ok(result.days["2026-08-15"])
  assert.equal(result.days["2026-08-15"].apps.editor, 15000)
})

test("closeActiveBucket returns new object (immutability)", () => {
  const aug15 = localMidnight(2026, 7, 15)
  const state = {
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-08-15"
  }
  const result = State.closeActiveBucket(state, "editor", aug15 + 10000, aug15 + 15000, "2026-08-15", 30000, aug15 + 12000)
  assert.notEqual(result, state)
  assert.notEqual(result.today, state.today)
})

// ---- commitElapsed -------------------------------------------------------

test("commitElapsed returns original state when no bucket open", () => {
  const state = { today: { total: 100, apps: {} }, days: {}, todayKey: "2026-08-15" }
  const result = State.commitElapsed(state, "", 0, 100000, "2026-08-15", 30000, 90000)
  assert.deepEqual(result.today, state.today)
})

test("commitElapsed accrues time into today", () => {
  const aug15 = localMidnight(2026, 7, 15)
  const startMs = aug15 + 10 * 3600000          // Aug 15 10:00:00
  const now = aug15 + 10 * 3600000 + 10000      // Aug 15 10:00:10
  const state = {
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-08-15"
  }
  const result = State.commitElapsed(state, "editor", startMs, now, "2026-08-15", 30000, now - 2000)
  assert.equal(result.today.total, 10000)
  assert.equal(result.today.apps.editor, 10000)
  assert.equal(result.activeStart, now)
  assert.equal(result.activeApp, "editor")
})

test("commitElapsed credits pre-midnight time to correct day", () => {
  const aug15 = localMidnight(2026, 7, 15)
  const aug16 = localMidnight(2026, 7, 16)
  const startMs = aug15 + 23 * 3600000 + 59 * 60000 + 50000  // Aug 15 23:59:50
  const now = aug16 + 5000                                      // Aug 16 00:00:05

  const state = {
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-08-16"
  }
  const result = State.commitElapsed(state, "editor", startMs, now, "2026-08-16", 30000, 0)
  // 10s belongs to Aug 15 (from start to midnight), 5s to Aug 16
  assert.equal(result.today.total, 0)
  assert.equal(result.today.apps.editor, undefined)
  assert.ok(result.days["2026-08-15"])
  assert.equal(result.days["2026-08-15"].apps.editor, 10000)
  assert.equal(result.activeStart, aug16) // fresh bucket from midnight
})

test("commitElapsed drops bucket on suspend gap", () => {
  const aug15 = localMidnight(2026, 7, 15)
  const startMs = aug15 + 10 * 3600000
  const now = aug15 + 10 * 3600000 + 95000     // 95s gap from lastTick
  const state = {
    today: { total: 100, apps: { a: 100 } },
    days: {},
    todayKey: "2026-08-15"
  }
  const result = State.commitElapsed(state, "editor", startMs, now, "2026-08-15", 30000, startMs)
  assert.equal(result.today.total, 100)
  assert.equal(result.activeStart, now)
})

test("commitElapsed returns new object (immutability)", () => {
  const aug15 = localMidnight(2026, 7, 15)
  const state = {
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-08-15"
  }
  const result = State.commitElapsed(state, "editor", aug15 + 10000, aug15 + 20000, "2026-08-15", 30000, aug15 + 18000)
  assert.notEqual(result, state)
  assert.notEqual(result.today, state.today)
})

// ---- rolloverIfNeeded ----------------------------------------------------

test("rolloverIfNeeded returns null when key unchanged", () => {
  const state = {
    todayKey: "2026-08-15",
    today: { total: 100, apps: {} },
    days: {},
    activeApp: "editor",
    activeStart: 1000
  }
  const result = State.rolloverIfNeeded(state, "2026-08-15")
  assert.equal(result, null)
})

test("rolloverIfNeeded carries previous day data into today", () => {
  const state = {
    todayKey: "2026-08-15",
    today: { total: 500, apps: { a: 500 } },
    days: { "2026-08-16": { total: 200, apps: { b: 200 } } },
    activeApp: "editor",
    activeStart: 1000
  }
  const result = State.rolloverIfNeeded(state, "2026-08-16")
  assert.ok(result)
  assert.equal(result.todayKey, "2026-08-16")
  assert.equal(result.today.total, 200)
  assert.equal(result.today.apps.b, 200)
  assert.equal(result.activeApp, "editor")
  assert.equal(result.activeStart, 0) // caller sets to Date.now()
})

test("rolloverIfNeeded starts empty when no previous day data", () => {
  const state = {
    todayKey: "2026-08-15",
    today: { total: 500, apps: { a: 500 } },
    days: {},
    activeApp: "",
    activeStart: 0
  }
  const result = State.rolloverIfNeeded(state, "2026-08-16")
  assert.ok(result)
  assert.equal(result.todayKey, "2026-08-16")
  assert.equal(result.today.total, 0)
  assert.deepEqual(result.today.apps, {})
})

// ---- applyResolvedApp ----------------------------------------------------

test("applyResolvedApp returns null when resolveInFlight is false", () => {
  const state = { resolveInFlight: false }
  const result = State.applyResolvedApp(state, "opencode", "foot", "2026-08-15", 30000, 0)
  assert.equal(result, null)
})

test("applyResolvedApp returns null when focus moved mid-resolve", () => {
  const state = {
    resolveInFlight: true,
    rawApp: "alacritty",
    resolveForApp: "foot",
    activeApp: "",
    activeStart: 0
  }
  const result = State.applyResolvedApp(state, "opencode", "foot", "2026-08-15", 30000, 0)
  assert.equal(result, null)
})

test("applyResolvedApp sets new app and opens bucket", () => {
  const state = {
    resolveInFlight: true,
    rawApp: "foot",
    resolveForApp: "foot",
    activeApp: "",
    activeStart: 0,
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-08-15",
    lastTick: 0
  }
  const result = State.applyResolvedApp(state, "opencode", "foot", "2026-08-15", 30000, 0)
  assert.ok(result)
  assert.equal(result.resolveInFlight, false)
  assert.equal(result.activeApp, "opencode")
  assert.ok(result.activeStart > 0)
})

test("applyResolvedApp returns null when resolved name matches current", () => {
  const state = {
    resolveInFlight: true,
    rawApp: "foot",
    resolveForApp: "foot",
    activeApp: "opencode",
    activeStart: 5000,
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-08-15",
    lastTick: 0
  }
  const result = State.applyResolvedApp(state, "opencode", "foot", "2026-08-15", 30000, 0)
  assert.equal(result, null)
})

test("applyResolvedApp falls back to rawApp when name is empty", () => {
  const state = {
    resolveInFlight: true,
    rawApp: "foot",
    resolveForApp: "foot",
    activeApp: "",
    activeStart: 0,
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-08-15",
    lastTick: 0
  }
  const result = State.applyResolvedApp(state, "", "foot", "2026-08-15", 30000, 0)
  assert.ok(result)
  assert.equal(result.activeApp, "foot")
})
