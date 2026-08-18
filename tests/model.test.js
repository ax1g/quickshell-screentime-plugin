"use strict"

const { test } = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

test("dayKey pads month and day", () => {
  assert.equal(Model.dayKey(new Date(2026, 7, 15)), "2026-08-15")
  assert.equal(Model.dayKey(new Date(2026, 0, 3)), "2026-01-03")
})

test("fmt renders compact durations", () => {
  assert.equal(Model.fmt(0), "0m")
  assert.equal(Model.fmt(45000), "45s")
  assert.equal(Model.fmt(60000), "1m")
  assert.equal(Model.fmt(1800000), "30m")
  assert.equal(Model.fmt(3600000), "1h")
  assert.equal(Model.fmt(5400000), "1h 30m")
  assert.equal(Model.fmt(-5000), "0m")
})

test("fmtWords renders worded durations", () => {
  assert.equal(Model.fmtWords(0), "0 MINUTES")
  assert.equal(Model.fmtWords(45000), "45 SECONDS")
  assert.equal(Model.fmtWords(60000), "1 MINUTE")
  assert.equal(Model.fmtWords(7800000), "2 HOURS 10 MINUTES")
})

test("canonicalApp folds browser subprocess names", () => {
  assert.equal(Model.canonicalApp("zen-bin"), "zen")
  assert.equal(Model.canonicalApp("brave-browser"), "brave")
  assert.equal(Model.canonicalApp("foot"), "foot")
  assert.equal(Model.canonicalApp(""), "")
})

test("displayName shortens reverse-DNS ids and passes plain names", () => {
  assert.equal(Model.displayName("com.github.user.Codium"), "Codium")
  assert.equal(Model.displayName("org.mozilla.firefox"), "Firefox")
  assert.equal(Model.displayName("io.github.pkruow.Cli"), "Cli")
  assert.equal(Model.displayName("opencode"), "opencode")
  assert.equal(Model.displayName("google-chrome"), "google-chrome")
  assert.equal(Model.displayName(""), "")
  assert.equal(Model.displayName(null), "")
})

test("appList drops sub-minute apps and sorts descending", () => {
  const today = {
    total: 300000,
    apps: { editor: 120000, foot: 30000, browser: 150000 }
  }
  const list = Model.appList(today)
  assert.deepEqual(list.map(a => a.app), ["browser", "editor"])
  assert.equal(list[0].pct, 50)
  assert.equal(list[1].pct, 40)
})

test("groupedApps keeps a small list untouched", () => {
  const apps = [{ app: "a", ms: 60000, pct: 100 }]
  assert.deepEqual(Model.groupedApps(apps, 6), apps)
})

test("groupedApps defaults to DONUT_MAX_SLICES when max is missing", () => {
  const apps = [
    { app: "a", ms: 40000, pct: 40 },
    { app: "b", ms: 20000, pct: 20 },
    { app: "c", ms: 12000, pct: 12 },
    { app: "d", ms: 10000, pct: 10 },
    { app: "e", ms: 8000, pct: 8 },
    { app: "f", ms: 6000, pct: 6 },
    { app: "g", ms: 4000, pct: 4 }
  ]
  const out = Model.groupedApps(apps)
  assert.equal(out.length, 6)
  assert.deepEqual(out.map(a => a.app), ["a", "b", "c", "d", "e", "Other"])
  assert.equal(out[5].ms, 6000 + 4000)
})

test("groupedApps folds the tail into an Other slice with recomputed pct", () => {
  const apps = [
    { app: "a", ms: 50000, pct: 50 },
    { app: "b", ms: 30000, pct: 30 },
    { app: "c", ms: 12000, pct: 12 },
    { app: "d", ms: 5000, pct: 5 },
    { app: "e", ms: 2000, pct: 2 },
    { app: "f", ms: 1000, pct: 1 }
  ]
  const out = Model.groupedApps(apps, 4)
  assert.deepEqual(out.map(a => a.app), ["a", "b", "c", "Other"])
  assert.equal(out[3].ms, 5000 + 2000 + 1000)
  assert.equal(out[3].pct, 8)
  const total = out.reduce((s, a) => s + a.ms, 0)
  assert.equal(total, 100000)
})

test("groupedApps merges sub-minPct apps into Other", () => {
  const apps = [
    { app: "a", ms: 50000, pct: 50 },
    { app: "b", ms: 30000, pct: 30 },
    { app: "c", ms: 12000, pct: 12 },
    { app: "d", ms: 5000, pct: 5 },
    { app: "e", ms: 2000, pct: 2 },
    { app: "f", ms: 1000, pct: 1 }
  ]
  const out = Model.groupedApps(apps, 6, 5)
  assert.deepEqual(out.map(a => a.app), ["a", "b", "c", "d", "Other"])
  assert.equal(out[4].ms, 2000 + 1000)
})

test("dayFor returns live today when nothing is selected", () => {
  const today = { total: 100, apps: { a: 100 } }
  const days = { "2026-08-17": { total: 50, apps: { b: 50 } } }
  assert.equal(Model.dayFor(days, today, "", "2026-08-18"), today)
})

test("dayFor returns live today when today's key is selected", () => {
  const today = { total: 100, apps: { a: 100 } }
  assert.equal(Model.dayFor({}, today, "2026-08-18", "2026-08-18"), today)
})

test("dayFor returns stored day for a past key", () => {
  const today = { total: 100, apps: { a: 100 } }
  const past = { total: 50, apps: { b: 50 } }
  const days = { "2026-08-17": past }
  assert.equal(Model.dayFor(days, today, "2026-08-17", "2026-08-18"), past)
})

test("dayFor returns null for unknown keys", () => {
  const today = { total: 1, apps: {} }
  assert.equal(Model.dayFor({}, today, "2026-01-01", "2026-08-18"), null)
})

test("prevKey handles month and year boundaries", () => {
  assert.equal(Model.prevKey("2026-08-15"), "2026-08-14")
  assert.equal(Model.prevKey("2026-03-01"), "2026-02-28")
  assert.equal(Model.prevKey("2026-01-01"), "2025-12-31")
})

test("empty or malformed keys never produce garbage day keys", () => {
  assert.equal(Model.prevKey(""), "")
  assert.equal(Model.prevKey("not-a-date"), "")
  assert.deepEqual(Model.weekKeys(""), [])
  assert.deepEqual(Model.weekTrend({}, ""), [])
  assert.equal(Model.relativeDayLabel("", "2026-08-15"), "")
  assert.equal(Model.relativeDayLabel("2026-08-15", ""), "Sat")
})

test("weekKeys returns 7 keys ending today", () => {
  const keys = Model.weekKeys("2026-08-15")
  assert.equal(keys.length, 7)
  assert.equal(keys[6], "2026-08-15")
  assert.equal(keys[0], "2026-08-09")
})

test("relativeDayLabel names today and yesterday", () => {
  assert.equal(Model.relativeDayLabel("2026-08-15", "2026-08-15"), "Today")
  assert.equal(Model.relativeDayLabel("2026-08-14", "2026-08-15"), "Yesterday")
  assert.equal(Model.relativeDayLabel("2026-08-13", "2026-08-15"), "Thu")
})

test("busiestWeekDay picks the largest total in the trailing week", () => {
  const days = {
    "2026-08-09": { total: 1000 },
    "2026-08-11": { total: 9000 },
    "2026-08-15": { total: 3000 }
  }
  const best = Model.busiestWeekDay(days, "2026-08-15")
  assert.equal(best.key, "2026-08-11")
  assert.equal(best.total, 9000)
})

test("weekTrend returns the trailing 7 days oldest first with totals", () => {
  const days = {
    "2026-08-09": { total: 1000 },
    "2026-08-11": { total: 9000 },
    "2026-08-15": { total: 3000 }
  }
  const trend = Model.weekTrend(days, "2026-08-15")
  assert.equal(trend.length, 7)
  assert.equal(trend[0].key, "2026-08-09")
  assert.equal(trend[6].key, "2026-08-15")
  assert.equal(trend[6].isToday, true)
  assert.equal(trend[6].label, "Sat")
  assert.equal(trend[5].label, "Fri")
  assert.equal(trend[0].label, "Sun")
  assert.equal(trend[0].ms, 1000)
  assert.equal(trend[2].ms, 9000)
  assert.equal(trend[6].ms, 3000)
})

test("pruneDays keeps only the retention window", () => {
  const days = {
    "2026-07-15": { total: 1 },
    "2026-08-01": { total: 2 },
    "2026-08-10": { total: 3 },
    "2026-08-15": { total: 4 }
  }
  const out = Model.pruneDays(days, "2026-08-15", 7)
  assert.deepEqual(Object.keys(out), ["2026-08-10", "2026-08-15"])
})

test("pruneDays returns the same object when nothing is pruned", () => {
  const days = { "2026-08-15": { total: 3 } }
  assert.equal(Model.pruneDays(days, "2026-08-15", 31), days)
})

test("insights lists top app, delta, and busiest day", () => {
  const today = {
    total: 3600000,
    apps: { browser: 1800000, editor: 1800000 }
  }
  const days = {
    "2026-08-14": { total: 7200000 },
    "2026-08-11": { total: 14400000 }
  }
  const rows = Model.insights(today, days, "2026-08-15", "2026-08-15")
  const labels = rows.map(r => r.label)
  assert.deepEqual(labels, ["Top app", "vs yesterday", "Busiest day (7d)"])
  assert.ok(rows[0].value.includes("browser"))
  assert.ok(rows[1].value.includes("-"))
})

test("insights returns 3 rows with dashes when no activity", () => {
  const rows = Model.insights(Model.newDay(), {}, "2026-08-15", "2026-08-15")
  assert.equal(rows.length, 3)
  assert.ok(rows[0].value.includes("\u2014"))
  assert.ok(rows[1].value.includes("\u2014"))
  assert.ok(rows[2].value.includes("\u2014"))
})

test("weekdayLabel returns short weekday for valid keys", () => {
  assert.equal(Model.weekdayLabel("2026-08-15"), "Sat")
  assert.equal(Model.weekdayLabel("2026-08-10"), "Mon")
})

test("weekdayLabel handles empty and malformed keys", () => {
  assert.equal(Model.weekdayLabel(""), "")
  assert.equal(Model.weekdayLabel("not-a-date"), "")
})

test("insights shows correct labels when viewing a past day", () => {
  const today = { total: 100000, apps: { a: 100000 } }
  const days = {
    "2026-08-13": { total: 50000 },
    "2026-08-14": { total: 80000 }
  }
  const rows = Model.insights(today, days, "2026-08-15", "2026-08-14")
  assert.equal(rows[0].label, "Top app (Yesterday)")
  assert.ok(rows[1].label.startsWith("vs ("))
  assert.ok(rows[1].label.includes("Thu"))
  assert.equal(rows[2].label, "Busiest day (7d)")
})

test("fmtDelta prefixes + and - correctly", () => {
  assert.equal(Model.fmtDelta(60000), "+1m")
  assert.equal(Model.fmtDelta(-120000), "-2m")
})

test("arcSegments returns empty array for empty list", () => {
  assert.deepEqual(Model.arcSegments([]), [])
  assert.deepEqual(Model.arcSegments(null), [])
})

test("hexToHsl and hslToHex round-trip", () => {
  const hex = "#e45b93"
  const hsl = Model.hexToHsl(hex)
  assert.equal(Model.hslToHex(hsl.h, hsl.s, hsl.l), "#e45b93")
})

test("hexToHsl tolerates missing #", () => {
  const hsl = Model.hexToHsl("e45b93")
  assert.equal(Model.hslToHex(hsl.h, hsl.s, hsl.l), "#e45b93")
})

test("sliceColors returns one color per slice and rotates hue", () => {
  const colors = Model.sliceColors(5, "#e45b93")
  assert.equal(colors.length, 5)
  assert.notEqual(colors[0], colors[1])
  assert.match(colors[0], /^#[0-9a-f]{6}$/)
})

test("sliceColors handles a grayscale accent", () => {
  const colors = Model.sliceColors(3, "#ffffff")
  assert.equal(colors.length, 3)
  assert.notEqual(colors[0], colors[1])
})

test("arcSegments covers the circle with gaps", () => {
  const apps = [
    { app: "a", ms: 50000, pct: 50 },
    { app: "b", ms: 50000, pct: 50 }
  ]
  const segs = Model.arcSegments(apps)
  assert.equal(segs.length, 2)
  assert.equal(segs[0].startAngle, -90)
  const lastEnd = segs[1].startAngle + segs[1].sweepAngle
  assert.ok(Math.abs(lastEnd - 270) < 0.001)
  assert.ok(segs[0].sweepAngle < 180, "gap removed from first slice")
})

test("arcSegments gives a single app the full circle", () => {
  const segs = Model.arcSegments([{ app: "a", ms: 60000, pct: 100 }])
  assert.equal(segs.length, 1)
  assert.equal(segs[0].sweepAngle, 360)
})
