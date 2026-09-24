"use strict"

const { test } = require("node:test")
const assert = require("node:assert/strict")
const State = require("../js/State.js")
const Model = require("../js/Model.js")

// Helper: epoch ms for a local-time date at midnight.
function localMidnight(year, month, day) {
  return new Date(year, month, day).getTime()
}
// Helper: epoch ms for a local-time date at a given hour:minute:second.
function localTime(year, month, day, h, m, s) {
  return new Date(year, month, day, h, m, s || 0).getTime()
}

// ---- accumulateBucket ----------------------------------------------------

test("accumulateBucket adds duration to new and existing apps", () => {
  const today = { total: 1000, apps: { editor: 500 } }
  const result = State.accumulateBucket(today, "browser", 3000)
  assert.equal(result.total, 4000)
  assert.equal(result.apps.browser, 3000)
  assert.equal(result.apps.editor, 500)
  const merged = State.accumulateBucket(result, "editor", 500)
  assert.equal(merged.total, 4500)
  assert.equal(merged.apps.editor, 1000)
})

test("accumulateBucket returns a new object (immutability)", () => {
  const today = { total: 1000, apps: { a: 500 } }
  const result = State.accumulateBucket(today, "b", 200)
  assert.notEqual(result, today)
  assert.notEqual(result.apps, today.apps)
})

test("accumulateBucket rejects junk bucket inputs", () => {
  const today = { total: 1000, apps: { a: 500 } }
  assert.equal(State.accumulateBucket(today, "a", 0), today)
  assert.equal(State.accumulateBucket(today, "a", -5000), today)
  assert.equal(State.accumulateBucket(today, "", 5000), today)
  assert.equal(State.accumulateBucket(today, "a", NaN), today)
  assert.equal(State.accumulateBucket(today, "a", Infinity), today)
})

// ---- closeActiveBucket ---------------------------------------------------

test("close and commit treat an empty bucket as a no-op", () => {
  const state = {
    today: { total: 100, apps: {} },
    days: {},
    todayKey: "2026-08-15",
  }
  const closed = State.closeActiveBucket(
    state,
    "",
    0,
    100000,
    "2026-08-15",
    30000,
    90000,
  )
  assert.deepEqual(closed.today, state.today)
  assert.deepEqual(closed.days, state.days)
  const committed = State.commitElapsed(
    state,
    "",
    0,
    100000,
    "2026-08-15",
    30000,
    90000,
  )
  assert.deepEqual(committed.today, state.today)
})

test("closeActiveBucket credits time to today when no midnight crossing", () => {
  const aug15 = localMidnight(2026, 7, 15)
  const startMs = aug15 + 10 * 3600000 // Aug 15 10:00:00
  const now = aug15 + 10 * 3600000 + 5000 // Aug 15 10:00:05
  const state = {
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-08-15",
  }
  const result = State.closeActiveBucket(
    state,
    "editor",
    startMs,
    now,
    "2026-08-15",
    30000,
    now - 2000,
  )
  assert.equal(result.today.total, 5000)
  assert.equal(result.today.apps.editor, 5000)
})

test("closeActiveBucket drops bucket on suspend gap", () => {
  const state = {
    today: { total: 100, apps: { a: 100 } },
    days: {},
    todayKey: "2026-08-15",
  }
  // lastTick=5000, now=100000 => gap=95000 > 30000 => suspend detected
  const result = State.closeActiveBucket(
    state,
    "editor",
    95000,
    100000,
    "2026-08-15",
    30000,
    5000,
  )
  assert.equal(result.today.total, 100)
  assert.equal(result.lastTick, 100000)
  assert.equal(result.activeApp, "")
  assert.equal(result.activeStart, 0)
})

test("closeActiveBucket splits a midnight-spanning bucket at midnight", () => {
  // Use local midnight to avoid timezone issues.
  const aug15 = localMidnight(2026, 7, 15)
  const aug16 = localMidnight(2026, 7, 16)
  const startMs = aug15 + 23 * 3600000 + 59 * 60000 + 50000 // Aug 15 23:59:50
  const now = aug16 + 5000 // Aug 16 00:00:05

  const state = {
    today: { total: 100, apps: {} },
    days: {},
    todayKey: "2026-08-16",
  }
  const result = State.closeActiveBucket(
    state,
    "editor",
    startMs,
    now,
    "2026-08-16",
    30000,
    0,
  )
  // 10s lands on 2026-08-15, 5s on today — same split as commitElapsed.
  assert.equal(result.days["2026-08-15"].apps.editor, 10000)
  assert.equal(result.today.total, 100 + 5000)
})

// ---- commitElapsed -------------------------------------------------------

test("commitElapsed accrues time into today", () => {
  const aug15 = localMidnight(2026, 7, 15)
  const startMs = aug15 + 10 * 3600000 // Aug 15 10:00:00
  const now = aug15 + 10 * 3600000 + 10000 // Aug 15 10:00:10
  const state = {
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-08-15",
  }
  const result = State.commitElapsed(
    state,
    "editor",
    startMs,
    now,
    "2026-08-15",
    30000,
    now - 2000,
  )
  assert.equal(result.today.total, 10000)
  assert.equal(result.today.apps.editor, 10000)
  assert.equal(result.activeStart, now)
  assert.equal(result.activeApp, "editor")
})

test("commitElapsed credits pre-midnight time to correct day", () => {
  const aug15 = localMidnight(2026, 7, 15)
  const aug16 = localMidnight(2026, 7, 16)
  const startMs = aug15 + 23 * 3600000 + 59 * 60000 + 50000 // Aug 15 23:59:50
  const now = aug16 + 5000 // Aug 16 00:00:05

  const state = {
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-08-16",
  }
  const result = State.commitElapsed(
    state,
    "editor",
    startMs,
    now,
    "2026-08-16",
    30000,
    0,
  )
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
  const now = aug15 + 10 * 3600000 + 95000 // 95s gap from lastTick
  const state = {
    today: { total: 100, apps: { a: 100 } },
    days: {},
    todayKey: "2026-08-15",
  }
  const result = State.commitElapsed(
    state,
    "editor",
    startMs,
    now,
    "2026-08-15",
    30000,
    startMs,
  )
  assert.equal(result.today.total, 100)
  assert.equal(result.activeStart, now)
})

// ---- rolloverIfNeeded ----------------------------------------------------

test("rolloverIfNeeded returns null when key unchanged", () => {
  const state = {
    todayKey: "2026-08-15",
    today: { total: 100, apps: {} },
    days: {},
    activeApp: "editor",
    activeStart: 1000,
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
    activeStart: 1000,
  }
  const result = State.rolloverIfNeeded(state, "2026-08-16")
  assert.ok(result)
  assert.equal(result.todayKey, "2026-08-16")
  assert.equal(result.today.total, 200)
  assert.equal(result.today.apps.b, 200)
  assert.equal(result.activeApp, "editor")
  assert.equal(result.activeStart, 0) // caller sets to Date.now()
})

test("rolloverIfNeeded carries adapter spans as engine arrays", () => {
  // Adapter sequences fail Array.isArray; the carry must normalize
  // instead of dropping them like the old slice gate did.
  const foreign = { 0: { app: "zen", start: 1000, end: 2000 }, length: 1 }
  assert.equal(Array.isArray(foreign), false)
  const state = {
    todayKey: "2026-08-15",
    today: { total: 0, apps: {} },
    days: {
      "2026-08-16": {
        total: 1000,
        apps: { zen: 1000 },
        spans: foreign,
      },
    },
    activeApp: "",
    activeStart: 0,
  }
  const result = State.rolloverIfNeeded(state, "2026-08-16")
  assert.ok(result)
  assert.equal(Array.isArray(result.today.spans), true)
  assert.deepEqual(result.today.spans, [{ app: "zen", start: 1000, end: 2000 }])
})

// ---- advanceRollover -------------------------------------------------------
// One transition owns the whole midnight moment: close the open bucket
// onto the day it started, carry the live day forward, reopen the bucket.
// Any ordering slip between those steps silently misattributes the
// straddling seconds, so the contract is pinned as a single patch.

test("dayMinus returns the unmirrored per-app remainder", () => {
  const result = State.dayMinus(
    { total: 70000, apps: { editor: 60000, browser: 10000 } },
    { total: 60000, apps: { editor: 60000 } },
  )
  assert.deepEqual(result, { total: 10000, apps: { browser: 10000 } })
})

test("dayMinus floors an over-counted mirror at zero", () => {
  assert.deepEqual(
    State.dayMinus(
      { total: 50, apps: { a: 50 } },
      { total: 100, apps: { a: 100 } },
    ),
    { total: 0, apps: {} },
  )
})

test("advanceRollover returns null when the day has not changed", () => {
  const state = {
    todayKey: "2026-08-15",
    today: { total: 100, apps: {} },
    days: {},
    activeApp: "editor",
    activeStart: 1000,
    lastTick: 5000,
  }
  assert.equal(
    State.advanceRollover(state, 2000, "2026-08-15", 30000, 5000),
    null,
  )
})

test("advanceRollover closes, carries and reopens in one patch", () => {
  // Bucket opened 10s before midnight, rollover runs 5s after.
  const before = localTime(2026, 7, 15, 23, 59, 50)
  const after = localTime(2026, 7, 16, 0, 0, 5)
  const state = {
    todayKey: "2026-08-15",
    today: { total: 1000, apps: { editor: 1000 } },
    days: {},
    activeApp: "editor",
    activeStart: before,
    lastTick: before,
  }
  const result = State.advanceRollover(
    state,
    after,
    "2026-08-16",
    30000,
    before,
  )
  assert.ok(result)
  assert.equal(result.todayKey, "2026-08-16")
  // Straddling bucket split at midnight: 10s to yesterday, 5s to today.
  // The pre-existing 1000 live ms were never mirrored, so the old day
  // keeps 11000 rather than dropping them.
  assert.equal(result.days["2026-08-15"].total, 11000)
  assert.equal(result.today.total, 5000)
  // Bucket reopened for the still-focused app at the transition moment.
  assert.equal(result.activeApp, "editor")
  assert.equal(result.activeStart, after)
})

test("advanceRollover drops the bucket on a suspend gap, still rolls", () => {
  const before = localTime(2026, 7, 15, 23, 50, 0)
  const after = localTime(2026, 7, 16, 0, 0, 5)
  const state = {
    todayKey: "2026-08-15",
    today: { total: 1000, apps: { editor: 1000 } },
    days: {},
    activeApp: "editor",
    activeStart: before,
    lastTick: before - 3600000, // gap far beyond suspendGapMs
  }
  const result = State.advanceRollover(
    state,
    after,
    "2026-08-16",
    30000,
    before - 3600000,
  )
  assert.ok(result)
  assert.equal(result.todayKey, "2026-08-16")
  // The stale bucket is dropped, but the 1000 live ms tracked before the
  // suspend are flushed into the old day instead of evaporating.
  assert.equal(result.days["2026-08-15"].total, 1000)
  assert.equal(result.today.total, 0)
  assert.equal(result.lastTick, after)
  assert.equal(result.activeApp, "editor")
})

test("advanceRollover preserves unmirrored live data in the old day", () => {
  // Live today holds 60s never mirrored into days (commit ran, persist did
  // not — e.g. blocked behind the corrupt-file backup). The carry must not
  // drop it: the old day keeps the full 60s plus the straddling 10s.
  const before = localTime(2026, 7, 15, 23, 59, 50)
  const after = localTime(2026, 7, 16, 0, 0, 5)
  const state = {
    todayKey: "2026-08-15",
    today: { total: 60000, apps: { editor: 60000 } },
    days: {},
    activeApp: "editor",
    activeStart: before,
    lastTick: before,
  }
  const result = State.advanceRollover(
    state,
    after,
    "2026-08-16",
    30000,
    before,
  )
  assert.ok(result)
  assert.equal(result.days["2026-08-15"].total, 70000)
  assert.equal(result.days["2026-08-15"].apps.editor, 70000)
  assert.equal(result.today.total, 5000)
})

test("advanceRollover unions coalesced spans instead of slicing by length", () => {
  // Mirror saved one 60s span; two more 60s commits coalesced into the
  // live tail without changing its length. Positional slicing would see
  // nothing past the mirror's count and drop 120s of spans while
  // flushing their totals — the union keeps every millisecond covered.
  const before = localTime(2026, 7, 15, 23, 59, 50)
  const after = localTime(2026, 7, 16, 0, 0, 5)
  const dayStart = localTime(2026, 7, 15, 0, 0, 0)
  const state = {
    todayKey: "2026-08-15",
    today: {
      total: 180000,
      apps: { editor: 180000 },
      spans: [{ app: "editor", start: dayStart, end: dayStart + 180000 }],
    },
    days: {
      "2026-08-15": {
        total: 60000,
        apps: { editor: 60000 },
        spans: [{ app: "editor", start: dayStart, end: dayStart + 60000 }],
      },
    },
    activeApp: "editor",
    activeStart: before,
    lastTick: before,
  }
  const result = State.advanceRollover(
    state,
    after,
    "2026-08-16",
    30000,
    before,
  )
  assert.ok(result)
  const old = result.days["2026-08-15"]
  assert.equal(old.total, 190000)
  const covered = old.spans.reduce((a, s) => a + (s.end - s.start), 0)
  assert.equal(covered, 190000)
})

test("advanceRollover with no open bucket just carries the day", () => {
  const after = localTime(2026, 7, 16, 0, 0, 5)
  const state = {
    todayKey: "2026-08-15",
    today: { total: 1000, apps: { editor: 1000 } },
    days: {},
    activeApp: "",
    activeStart: 0,
    lastTick: after - 1000,
  }
  const result = State.advanceRollover(
    state,
    after,
    "2026-08-16",
    30000,
    after - 1000,
  )
  assert.ok(result)
  assert.equal(result.todayKey, "2026-08-16")
  assert.equal(result.today.total, 0)
  assert.equal(result.activeApp, "")
  assert.equal(result.activeStart, 0)
})

test("rolloverIfNeeded starts empty when no previous day data", () => {
  const state = {
    todayKey: "2026-08-15",
    today: { total: 500, apps: { a: 500 } },
    days: {},
    activeApp: "",
    activeStart: 0,
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
  const result = State.applyResolvedApp(
    state,
    "opencode",
    "foot",
    "2026-08-15",
    30000,
    0,
  )
  assert.equal(result, null)
})

test("applyResolvedApp returns null when focus moved mid-resolve", () => {
  const state = {
    resolveInFlight: true,
    rawApp: "alacritty",
    resolveForApp: "foot",
    activeApp: "",
    activeStart: 0,
  }
  const result = State.applyResolvedApp(
    state,
    "opencode",
    "foot",
    "2026-08-15",
    30000,
    0,
  )
  assert.equal(result, null)
})

test("applyResolvedApp returns null when result is from an older resolve generation", () => {
  // foot(A) -> foot(B) mid-resolve: rawApp/resolveForApp are both "foot",
  // so only the generation token proves the in-flight result is stale.
  const state = {
    resolveInFlight: true,
    rawApp: "foot",
    resolveForApp: "foot",
    resolveSpawnGen: 1,
    resolveGeneration: 2,
    activeApp: "",
    activeStart: 0,
  }
  const result = State.applyResolvedApp(
    state,
    "opencode",
    "foot",
    "2026-08-15",
    30000,
    0,
  )
  assert.equal(result, null)
})

test("applyResolvedApp sets new app and opens bucket", () => {
  const state = {
    resolveInFlight: true,
    rawApp: "foot",
    resolveForApp: "foot",
    resolveSpawnGen: 3,
    resolveGeneration: 3,
    activeApp: "",
    activeStart: 0,
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-08-15",
    lastTick: 0,
  }
  const result = State.applyResolvedApp(
    state,
    "opencode",
    "foot",
    "2026-08-15",
    30000,
    0,
  )
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
    lastTick: 0,
  }
  const result = State.applyResolvedApp(
    state,
    "opencode",
    "foot",
    "2026-08-15",
    30000,
    0,
  )
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
    lastTick: 0,
  }
  const result = State.applyResolvedApp(
    state,
    "",
    "foot",
    "2026-08-15",
    30000,
    0,
  )
  assert.ok(result)
  assert.equal(result.activeApp, "foot")
})

// ---- Data safety: close + rollover sequence --------------------------------
// These mirror the exact call sequence in Service.qml's rolloverIfNeeded:
//   1. closeActiveBucket (accrue bucket to its start day)
//   2. rolloverIfNeeded (carry today forward into the new day)

test("close + rollover: bucket on yesterday lands in days, not today", () => {
  const aug15 = localMidnight(2026, 7, 15)
  const aug16 = localMidnight(2026, 7, 16)
  const startMs = aug15 + 23 * 3600000 // Aug 15 23:00
  const now = aug16 + 3000 // Aug 16 00:00:03

  const state = {
    today: { total: 500, apps: { a: 500 } },
    days: {},
    todayKey: "2026-08-16",
    activeApp: "editor",
    activeStart: startMs,
    lastTick: 0,
  }

  // Step 1: close the bucket (it started Aug 15, today is Aug 16)
  const closed = State.closeActiveBucket(
    state,
    "editor",
    startMs,
    now,
    "2026-08-16",
    30000,
    now - 1000,
  )
  // Split at midnight: 23:00-00:00 to Aug 15, 3s to today
  assert.equal(closed.days["2026-08-15"].apps.editor, 3600000)
  assert.equal(closed.today.total, 500 + 3000)

  // Step 2: rollover doesn't apply (already on Aug 16), but the bucket
  // was correctly attributed to Aug 15 by step 1 alone.
  const rolled = State.rolloverIfNeeded(closed, "2026-08-16")
  assert.equal(rolled, null, "no rollover needed when key is unchanged")
})

test("close + rollover: existing history for new day is preserved", () => {
  const aug16 = localMidnight(2026, 7, 16)
  const startMs = aug16 + 2000
  const now = aug16 + 5000

  const state = {
    today: { total: 1000, apps: { a: 1000 } },
    days: { "2026-08-17": { total: 3000, apps: { b: 3000 } } },
    todayKey: "2026-08-16",
    activeApp: "editor",
    activeStart: startMs,
    lastTick: 0,
  }

  const closed = State.closeActiveBucket(
    state,
    "editor",
    startMs,
    now,
    "2026-08-16",
    30000,
    now - 1000,
  )
  const rolled = State.rolloverIfNeeded(closed, "2026-08-17")
  assert.ok(rolled)
  // Aug 17 already had 3000ms from history
  assert.equal(rolled.today.total, 3000)
  assert.equal(rolled.today.apps.b, 3000)
})

// ---- Data safety: commitElapsed across midnight ----------------------------

test("commitElapsed across midnight preserves existing day data", () => {
  const aug15 = localMidnight(2026, 7, 15)
  const aug16 = localMidnight(2026, 7, 16)
  const startMs = aug15 + 23 * 3600000 // Aug 15 23:00
  const now = aug16 + 10000 // Aug 16 00:00:10

  // Aug 15 already had 2 hours from a previous app
  const state = {
    today: { total: 0, apps: {} },
    days: { "2026-08-15": { total: 7200000, apps: { vim: 7200000 } } },
    todayKey: "2026-08-16",
    activeApp: "editor",
    activeStart: startMs,
    lastTick: 0,
  }

  const result = State.commitElapsed(
    state,
    "editor",
    startMs,
    now,
    "2026-08-16",
    30000,
    0,
  )
  // 1 hour went to Aug 15
  assert.equal(result.days["2026-08-15"].apps.editor, 3600000)
  // Original 2 hours still there
  assert.equal(result.days["2026-08-15"].apps.vim, 7200000)
  // Total on Aug 15 now 3 hours
  assert.equal(result.days["2026-08-15"].total, 7200000 + 3600000)
  // Today (Aug 16) is untouched
  assert.equal(result.today.total, 0)
  // Bucket reopened from midnight
  assert.equal(result.activeStart, aug16)
})

// ---- Data safety: accumulateBucket on empty state --------------------------

test("accumulateBucket with zero total starts correctly", () => {
  const today = { total: 0, apps: {} }
  const result = State.accumulateBucket(today, "new-app", 60000)
  assert.equal(result.total, 60000)
  assert.equal(result.apps["new-app"], 60000)
})

// ---- Data safety: closeActiveBucket consecutive calls ----------------------

test("closeActiveBucket twice with same state: second call is no-op", () => {
  const aug15 = localMidnight(2026, 7, 15)
  const state = {
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-08-15",
    activeApp: "editor",
    activeStart: aug15 + 10000,
    lastTick: 0,
  }
  const first = State.closeActiveBucket(
    state,
    "editor",
    aug15 + 10000,
    aug15 + 15000,
    "2026-08-15",
    30000,
    aug15 + 12000,
  )
  assert.equal(first.today.total, 5000)

  // Second call with cleared bucket is a no-op
  const second = State.closeActiveBucket(
    first,
    first.activeApp,
    first.activeStart,
    aug15 + 20000,
    "2026-08-15",
    30000,
    aug15 + 18000,
  )
  assert.equal(second.today.total, 5000)
})

// ---- Data safety: commitElapsed then close (simulating timer + focus) ------

test("commitElapsed then close: full time is accounted for", () => {
  const aug15 = localMidnight(2026, 7, 15)
  const startMs = aug15 + 10 * 3600000
  const commitTime = aug15 + 10 * 3600000 + 30000 // 30s in
  const closeTime = aug15 + 10 * 3600000 + 45000 // 45s in

  const state = {
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-08-15",
  }

  // Commit at 30s: credits 30s, resets bucket start
  const committed = State.commitElapsed(
    state,
    "editor",
    startMs,
    commitTime,
    "2026-08-15",
    30000,
    commitTime - 5000,
  )
  assert.equal(committed.today.total, 30000)
  assert.equal(committed.activeStart, commitTime)

  // Close at 45s: credits remaining 15s from commitTime
  const closed = State.closeActiveBucket(
    committed,
    "editor",
    committed.activeStart,
    closeTime,
    "2026-08-15",
    30000,
    closeTime - 5000,
  )
  assert.equal(closed.today.total, 45000)
  assert.equal(closed.today.apps.editor, 45000)
})

// ---- Data safety: suspend during rollover ----------------------------------

test("suspend gap during close prevents stale time from landing in any day", () => {
  const aug15 = localMidnight(2026, 7, 15)
  const aug16 = localMidnight(2026, 7, 16)
  const startMs = aug15 + 23 * 3600000
  // now is way past lastTick: gap > 30s => suspend
  const now = aug16 + 60000

  const state = {
    today: { total: 500, apps: { a: 500 } },
    days: {},
    todayKey: "2026-08-16",
    activeApp: "editor",
    activeStart: startMs,
    lastTick: aug15 + 23 * 3600000,
  }

  const closed = State.closeActiveBucket(
    state,
    "editor",
    startMs,
    now,
    "2026-08-16",
    30000,
    state.lastTick,
  )
  // Bucket dropped: no time credited, just cleared
  assert.equal(closed.today.total, 500)
  assert.equal(closed.activeApp, "")
  assert.equal(closed.activeStart, 0)
  // No stale data leaked into days
  assert.equal(Object.keys(closed.days).length, 0)
})

test("applyResolvedApp renames through user aliases", () => {
  const state = {
    resolveInFlight: true,
    rawApp: "foot",
    resolveForApp: "foot",
    resolveSpawnGen: 1,
    resolveGeneration: 1,
    appAliases: { opencode: "work" },
    activeApp: "",
    activeStart: 0,
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-08-15",
    lastTick: 0,
  }
  const result = State.applyResolvedApp(
    state,
    "opencode",
    "foot",
    "2026-08-15",
    30000,
    0,
  )
  assert.ok(result)
  assert.equal(result.activeApp, "work")
})

test("closeActiveBucket rebases on backward clock jumps", () => {
  const start = localMidnight(2026, 7, 15) + 12 * 3600000
  const now = start - 60000
  const state = {
    today: { total: 1000, apps: { zen: 1000 } },
    days: {},
    todayKey: "2026-08-15",
    lastTick: start - 5000,
  }
  const result = State.closeActiveBucket(
    state,
    "zen",
    start,
    now,
    "2026-08-15",
    30000,
    state.lastTick,
  )
  assert.deepEqual(result.today, state.today)
  assert.equal(result.activeApp, "")
  assert.equal(result.activeStart, 0)
  assert.equal(result.lastTick, now)
})

test("commitElapsed rebases an open bucket on backward jumps", () => {
  const start = localMidnight(2026, 7, 15) + 12 * 3600000
  const now = start - 60000
  const state = {
    today: { total: 1000, apps: { zen: 1000 } },
    days: {},
    todayKey: "2026-08-15",
    lastTick: start - 5000,
  }
  const result = State.commitElapsed(
    state,
    "zen",
    start,
    now,
    "2026-08-15",
    30000,
    state.lastTick,
  )
  assert.deepEqual(result.today, state.today)
  assert.equal(result.activeApp, "zen")
  assert.equal(result.activeStart, now)
  assert.equal(result.lastTick, now)
})

test("close and commit split a multi-day bucket day by day", () => {
  const start = localMidnight(2026, 7, 15) + 23 * 3600000
  const now = localMidnight(2026, 7, 17) + 10000
  const setup = () => ({
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-08-17",
    lastTick: start,
  })
  const checkSplit = (result) => {
    assert.equal(result.days["2026-08-15"].total, 3600000)
    assert.equal(result.days["2026-08-16"].total, 86400000)
  }
  const closed = State.closeActiveBucket(
    setup(),
    "zen",
    start,
    now,
    "2026-08-17",
    30 * 3600000,
    start,
  )
  checkSplit(closed)
  assert.equal(closed.today.total, 10000)
  assert.deepEqual(closed.today.apps, { zen: 10000 })
  assert.equal(closed.activeApp, "")
  const committed = State.commitElapsed(
    setup(),
    "zen",
    start,
    now,
    "2026-08-17",
    30 * 3600000,
    start,
  )
  checkSplit(committed)
  assert.deepEqual(committed.today, { total: 0, apps: {} })
  assert.equal(committed.activeApp, "zen")
  assert.equal(committed.activeStart, localMidnight(2026, 7, 17))
})

test("advanceRollover ignores backward day jumps", () => {
  const now = localMidnight(2026, 7, 15) + 9 * 3600000
  const state = {
    today: { total: 3600000, apps: { zen: 3600000 } },
    days: {},
    todayKey: "2026-08-16",
    activeApp: "zen",
    activeStart: now - 60000,
    lastTick: now - 5000,
  }
  const result = State.advanceRollover(
    state,
    now,
    "2026-08-15",
    30000,
    state.lastTick,
  )
  assert.ok(result)
  assert.equal(result.todayKey, "2026-08-16")
  assert.deepEqual(result.today, state.today)
  assert.equal(result.activeApp, "")
  assert.equal(result.activeStart, 0)
  assert.equal(result.lastTick, now)
})

// ---- Day spans ------------------------------------------------------------

test("closeActiveBucket records the credited span", () => {
  const t0 = localTime(2026, 8, 21, 7, 0, 0)
  const t1 = localTime(2026, 8, 21, 7, 10, 0)
  const state = {
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-09-21",
    activeApp: "zen",
    activeStart: t0,
    lastTick: t1,
  }
  const result = State.closeActiveBucket(
    state,
    "zen",
    t0,
    t1,
    "2026-09-21",
    30000,
    t1,
  )
  assert.equal(result.today.total, 600000)
  assert.deepEqual(result.today.spans, [{ app: "zen", start: t0, end: t1 }])
})

test("browser aggregate keeps its site on the recorded span", () => {
  const t0 = localTime(2026, 8, 21, 7, 0, 0)
  const t1 = localTime(2026, 8, 21, 7, 10, 0)
  const state = {
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-09-21",
    activeApp: "zen",
    activeStart: t0,
    lastTick: t1,
  }
  const result = State.closeActiveBucket(
    state,
    "zen",
    t0,
    t1,
    "2026-09-21",
    30000,
    t1,
    "site:example.com",
  )
  assert.deepEqual(result.today.apps, { zen: 600000 })
  assert.deepEqual(result.today.spans, [
    { app: "site:example.com", start: t0, end: t1 },
  ])
})

test("closeActiveBucket drops spans with suspend gaps and clock jumps", () => {
  const t0 = localTime(2026, 8, 21, 7, 0, 0)
  const t1 = localTime(2026, 8, 21, 7, 10, 0)
  const state = {
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-09-21",
    activeApp: "zen",
    activeStart: t0,
    lastTick: t0,
  }
  const gap = State.closeActiveBucket(
    state,
    "zen",
    t0,
    t1,
    "2026-09-21",
    30000,
    t0,
  )
  assert.equal(gap.today.total, 0)
  assert.ok(!("spans" in gap.today))
  const jump = State.closeActiveBucket(
    state,
    "zen",
    t1,
    t0,
    "2026-09-21",
    30000,
    t1,
  )
  assert.ok(!("spans" in jump.today))
})

test("closeActiveBucket splits spans at midnight", () => {
  const m0 = localTime(2026, 8, 21, 23, 55, 0)
  const m1 = localTime(2026, 8, 22, 0, 5, 0)
  const midnight = localTime(2026, 8, 22, 0, 0, 0)
  const state = {
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-09-22",
    activeApp: "zen",
    activeStart: m0,
    lastTick: m1,
  }
  const result = State.closeActiveBucket(
    state,
    "zen",
    m0,
    m1,
    "2026-09-22",
    30000,
    m1,
  )
  assert.deepEqual(result.days["2026-09-21"].spans, [
    { app: "zen", start: m0, end: midnight },
  ])
  assert.deepEqual(result.today.spans, [
    { app: "zen", start: midnight, end: m1 },
  ])
})

test("commitElapsed records the chunk and keeps the bucket open", () => {
  const t0 = localTime(2026, 8, 21, 7, 0, 0)
  const t1 = localTime(2026, 8, 21, 7, 10, 0)
  const state = {
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-09-21",
    activeApp: "zen",
    activeStart: t0,
    lastTick: t1,
  }
  const result = State.commitElapsed(
    state,
    "zen",
    t0,
    t1,
    "2026-09-21",
    30000,
    t1,
  )
  assert.equal(result.today.total, 600000)
  assert.deepEqual(result.today.spans, [{ app: "zen", start: t0, end: t1 }])
  assert.equal(result.activeApp, "zen")
  assert.equal(result.activeStart, t1)
})

test("advanceRollover carries spans across midnight in order", () => {
  const m0 = localTime(2026, 8, 21, 23, 55, 0)
  const m1 = localTime(2026, 8, 22, 0, 5, 0)
  const midnight = localTime(2026, 8, 22, 0, 0, 0)
  const mirror = {
    total: 3600000,
    apps: { zen: 3600000 },
    spans: [{ app: "zen", start: m0 - 3600000, end: m0 - 1800000 }],
  }
  const live = {
    total: 5400000,
    apps: { zen: 5400000 },
    spans: mirror.spans.concat([{ app: "zen", start: m0 - 1800000, end: m0 }]),
  }
  const state = {
    today: live,
    days: { "2026-09-21": mirror },
    todayKey: "2026-09-21",
    activeApp: "zen",
    activeStart: m0,
    lastTick: m1,
  }
  const result = State.advanceRollover(state, m1, "2026-09-22", 30000, m1)
  // One continuous zen session 22:55–00:00: the union rejoins the
  // contiguous spans instead of keeping slice-position artifacts.
  assert.deepEqual(result.days["2026-09-21"].spans, [
    { app: "zen", start: m0 - 3600000, end: midnight },
  ])
  assert.deepEqual(result.today.spans, [
    { app: "zen", start: midnight, end: m1 },
  ])
  assert.equal(result.today.total, 300000)
})

test("advanceRollover preserves a site label across midnight", () => {
  const m0 = localTime(2026, 8, 21, 23, 59, 58)
  const m1 = localTime(2026, 8, 22, 0, 0, 2)
  const midnight = localTime(2026, 8, 22, 0, 0, 0)
  const state = {
    today: { total: 0, apps: {} },
    days: {},
    todayKey: "2026-09-21",
    activeApp: "zen",
    activeStart: m0,
    lastTick: m1,
  }
  const result = State.advanceRollover(
    state,
    m1,
    "2026-09-22",
    30000,
    m1,
    "site:example.com",
  )
  assert.deepEqual(result.days["2026-09-21"].apps, { zen: 2000 })
  assert.deepEqual(result.days["2026-09-21"].spans, [
    { app: "site:example.com", start: m0, end: midnight },
  ])
  assert.deepEqual(result.today.apps, { zen: 2000 })
  assert.deepEqual(result.today.spans, [
    { app: "site:example.com", start: midnight, end: m1 },
  ])
  assert.equal(result.activeSpanApp, "site:example.com")
})

test("accumulateBucket preserves spans without recording", () => {
  const day = { total: 1, apps: {}, spans: [{ app: "a", start: 1, end: 2 }] }
  const result = State.accumulateBucket(day, "b", 5)
  assert.equal(result.spans, day.spans)
  const bare = State.accumulateBucket({ total: 1, apps: {} }, "b", 5)
  assert.ok(!("spans" in bare))
})
