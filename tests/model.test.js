"use strict"

const { test } = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../js/Model.js")

test("dayKey pads month and day", () => {
  assert.equal(Model.dayKey(new Date(2026, 7, 15)), "2026-08-15")
  assert.equal(Model.dayKey(new Date(2026, 0, 3)), "2026-01-03")
})

// fmt is the compact form used everywhere space is tight: bar label,
// donut centre, legend rows, week and month bars.
test("fmt renders compact durations", () => {
  assert.equal(Model.fmt(0), "0m")
  assert.equal(Model.fmt(45000), "45s")
  assert.equal(Model.fmt(60000), "1m")
  assert.equal(Model.fmt(1800000), "30m")
  assert.equal(Model.fmt(3600000), "1h")
  assert.equal(Model.fmt(5400000), "1h 30m")
  assert.equal(Model.fmt(-5000), "0m")
})

// fmtWords is the worded subtitle under the panel title ("Screen Time" /
// "2 HOURS 10 MINUTES"); assertions must match that rendering exactly.
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

test("canonicalApp folds Chromium web apps across profiles", () => {
  const defaultProfile = Model.canonicalApp("chrome-chatgpt.com__-Default")
  const numberedProfile = Model.canonicalApp("chrome-chatgpt.com__-Profile_2")

  assert.equal(defaultProfile, "chrome-chatgpt.com")
  assert.equal(numberedProfile, defaultProfile)
  assert.equal(
    Model.canonicalApp("chrome-music.apple.com__lv_home-Default"),
    "chrome-music.apple.com",
  )
})

test("canonicalApp normalizes Chromium-family web app keys", () => {
  assert.equal(
    Model.canonicalApp("chromium-calendar.google.com__-Profile_1"),
    "chromium-calendar.google.com",
  )
  assert.equal(
    Model.canonicalApp("brave-calendar.google.com__-Default"),
    "brave-calendar.google.com",
  )
  assert.equal(
    Model.canonicalApp("msedge-calendar.google.com__-Default"),
    "msedge-calendar.google.com",
  )
  assert.equal(
    Model.canonicalApp("vivaldi-calendar.google.com__-Default"),
    "vivaldi-calendar.google.com",
  )
})

test("displayName shortens reverse-DNS ids and passes plain names", () => {
  assert.equal(Model.displayName("com.github.user.Codium"), "codium")
  assert.equal(Model.displayName("org.mozilla.firefox"), "firefox")
  assert.equal(Model.displayName("io.github.pkruow.Cli"), "cli")
  assert.equal(Model.displayName("opencode"), "opencode")
  assert.equal(Model.displayName("google-chrome"), "google-chrome")
  assert.equal(Model.displayName(""), "")
  assert.equal(Model.displayName(null), "")
})

test("displayName extracts hostnames from Chromium-family web app keys", () => {
  assert.equal(Model.displayName("chrome-chatgpt.com__-Default"), "chatgpt.com")
  assert.equal(
    Model.displayName("chrome-music.apple.com__lv_home-Default"),
    "music.apple.com",
  )
  assert.equal(
    Model.displayName("chrome-calendar.google.com__-Profile_1"),
    "calendar.google.com",
  )
  assert.equal(
    Model.displayName("chromium-chatgpt.com__-Default"),
    "chatgpt.com",
  )
  assert.equal(Model.displayName("brave-chatgpt.com__-Default"), "chatgpt.com")
  assert.equal(Model.displayName("msedge-chatgpt.com__-Default"), "chatgpt.com")
  assert.equal(
    Model.displayName("vivaldi-chatgpt.com__-Default"),
    "chatgpt.com",
  )
  assert.equal(Model.displayName("chrome-chatgpt.com"), "chatgpt.com")
})

test("displayName keeps dotted non-reverse-DNS names intact", () => {
  assert.equal(Model.displayName("Minecraft* 26.2"), "minecraft* 26.2")
  assert.equal(Model.displayName("editor-1.2"), "editor-1.2")
})

test("displayName passes unresolved Steam ids through untouched", () => {
  // Game titles are resolved by python/resolve_app.py before storage;
  // the display layer must never touch the filesystem for a label.
  // (require()-based resolution cannot run in QML's JS engine anyway.)
  assert.equal(Model.displayName("steam_app_730"), "steam_app_730")
  assert.equal(Model.resolveSteamAppName, undefined)
})

test("sanitizeHistory keeps valid sections and rejects malformed ones", () => {
  const days = { "2026-08-21": { total: 5, apps: { zen: 5 } } }
  const months = { "2026-07": 9823400 }

  const clean = Model.sanitizeHistory(days, months)
  assert.equal(clean.days, days)
  assert.equal(clean.months, months)

  // Arrays pass typeof "object" but are not valid history containers.
  assert.deepEqual(Model.sanitizeHistory([1, 2], days).days, {})
  assert.deepEqual(Model.sanitizeHistory(days, ["x"]).months, {})
  assert.deepEqual(Model.sanitizeHistory(null, undefined).days, {})
  assert.deepEqual(Model.sanitizeHistory("{}", 42).months, {})
})

test("appList drops sub-minute apps and sorts descending", () => {
  const today = {
    total: 300000,
    apps: { editor: 120000, foot: 30000, browser: 150000 },
  }
  const list = Model.appList(today)
  assert.deepEqual(
    list.map((a) => a.app),
    ["browser", "editor"],
  )
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
    { app: "g", ms: 4000, pct: 4 },
  ]
  const out = Model.groupedApps(apps)
  assert.equal(out.length, 6)
  assert.deepEqual(
    out.map((a) => a.app),
    ["a", "b", "c", "d", "e", "Other"],
  )
  assert.equal(out[5].ms, 6000 + 4000)
})

test("groupedApps folds the tail into an Other slice with recomputed pct", () => {
  const apps = [
    { app: "a", ms: 50000, pct: 50 },
    { app: "b", ms: 30000, pct: 30 },
    { app: "c", ms: 12000, pct: 12 },
    { app: "d", ms: 5000, pct: 5 },
    { app: "e", ms: 2000, pct: 2 },
    { app: "f", ms: 1000, pct: 1 },
  ]
  const out = Model.groupedApps(apps, 4)
  assert.deepEqual(
    out.map((a) => a.app),
    ["a", "b", "c", "Other"],
  )
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
    { app: "f", ms: 1000, pct: 1 },
  ]
  const out = Model.groupedApps(apps, 6, 5)
  assert.deepEqual(
    out.map((a) => a.app),
    ["a", "b", "c", "d", "Other"],
  )
  assert.equal(out[4].ms, 2000 + 1000)
})

test("dayFor selects live today, a stored day, or null", () => {
  const today = { total: 100, apps: { a: 100 } }
  const past = { total: 50, apps: { b: 50 } }
  const days = { "2026-08-17": past }
  assert.equal(Model.dayFor(days, today, "", "2026-08-18"), today)
  assert.equal(Model.dayFor({}, today, "2026-08-18", "2026-08-18"), today)
  assert.equal(Model.dayFor(days, today, "2026-08-17", "2026-08-18"), past)
  assert.equal(Model.dayFor({}, today, "2026-01-01", "2026-08-18"), null)
})

test("prevKey handles month and year boundaries", () => {
  assert.equal(Model.prevKey("2026-08-15"), "2026-08-14")
  assert.equal(Model.prevKey("2026-03-01"), "2026-02-28")
  assert.equal(Model.prevKey("2026-01-01"), "2025-12-31")
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
    "2026-08-15": { total: 3000 },
  }
  const best = Model.busiestWeekDay(days, "2026-08-15")
  assert.equal(best.key, "2026-08-11")
  assert.equal(best.total, 9000)
  assert.equal(Model.busiestWeekDay({}, "2026-08-15").total, 0)
})

test("weekTrend returns the trailing 7 days oldest first with totals", () => {
  const days = {
    "2026-08-09": { total: 1000 },
    "2026-08-11": { total: 9000 },
    "2026-08-15": { total: 3000 },
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
    "2026-08-15": { total: 4 },
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
    apps: { browser: 1800000, editor: 1800000 },
  }
  const days = {
    "2026-08-14": { total: 7200000 },
    "2026-08-11": { total: 14400000 },
  }
  const rows = Model.insights(today, days, "2026-08-15", "2026-08-15")
  const labels = rows.map((r) => r.label)
  assert.deepEqual(labels, ["Top app", "vs Yesterday", "Busiest day (7d)"])
  assert.ok(rows[0].value.includes("browser"))
  assert.ok(rows[1].value.includes("-"))
})

test("insights renders the top app with its refined display name", () => {
  const today = {
    total: 3600000,
    apps: { "com.omarchy.agent": 3600000 },
  }
  const rows = Model.insights(today, {}, "2026-08-15", "2026-08-15")
  assert.ok(rows[0].value.includes("agent"))
  assert.ok(!rows[0].value.includes("com.omarchy"))
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
    "2026-08-14": { total: 80000 },
  }
  const rows = Model.insights(today, days, "2026-08-15", "2026-08-14")
  assert.equal(rows[0].label, "Top app Fri")
  assert.ok(rows[0].value.includes("\u00b7"))
  assert.ok(rows[1].label.startsWith("vs "))
  assert.ok(rows[1].label.includes("Thu"))
  assert.equal(rows[2].label, "Busiest day (7d)")
})

test("fmtDelta prefixes + and - correctly", () => {
  assert.equal(Model.fmtDelta(60000), "+ 1m")
  assert.equal(Model.fmtDelta(-120000), "- 2m")
})

test("weekTotal sums trend entries and tolerates junk", () => {
  assert.equal(Model.weekTotal([{ ms: 60000 }, { ms: 30000 }, {}]), 90000)
  assert.equal(Model.weekTotal(null), 0)
  assert.equal(Model.weekTotal([]), 0)
})

test("fmtWords renders singular for 1 SECOND and 1 HOUR 1 MINUTE", () => {
  assert.equal(Model.fmtWords(1000), "1 SECOND")
  assert.equal(Model.fmtWords(3660000), "1 HOUR 1 MINUTE")
})

test("formatDate returns month and day for valid keys", () => {
  assert.equal(Model.formatDate("2026-08-15"), "Aug 15")
  assert.equal(Model.formatDate("2026-01-01"), "Jan 1")
})

test("formatDate returns empty for empty or malformed keys", () => {
  assert.equal(Model.formatDate(""), "")
  assert.equal(Model.formatDate("not-a-date"), "")
})

test("arcSegments returns empty array for empty list", () => {
  assert.deepEqual(Model.arcSegments([]), [])
  assert.deepEqual(Model.arcSegments(null), [])
})

test("hexToHsl and hslToHex round-trip, with or without #", () => {
  const hex = "#e45b93"
  const hsl = Model.hexToHsl(hex)
  assert.equal(Model.hslToHex(hsl.h, hsl.s, hsl.l), "#e45b93")
  const bare = Model.hexToHsl("e45b93")
  assert.equal(Model.hslToHex(bare.h, bare.s, bare.l), "#e45b93")
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
    { app: "b", ms: 50000, pct: 50 },
  ]
  const segs = Model.arcSegments(apps)
  assert.equal(segs.length, 2)
  assert.equal(segs[0].startAngle, -90)
  const lastEnd = segs[1].startAngle + segs[1].sweepAngle
  assert.ok(Math.abs(lastEnd - 268.5) < 0.001)
  assert.ok(segs[0].sweepAngle < 180, "gap removed from first slice")
})

test("arcSegments gives a single app the full circle", () => {
  const segs = Model.arcSegments([{ app: "a", ms: 60000, pct: 100 }])
  assert.equal(segs.length, 1)
  assert.equal(segs[0].sweepAngle, 360)
})

test("browser_aliases.json is the single source of truth for canonicalApp", () => {
  const aliases = require("../js/browser_aliases.json")
  assert.equal(typeof aliases, "object")
  assert.ok(Object.keys(aliases).length > 0)
  for (const [key, target] of Object.entries(aliases)) {
    assert.equal(
      Model.canonicalApp(key),
      target,
      `canonicalApp("${key}") should return "${target}" from browser_aliases.json`,
    )
  }
})

test("QML inline browser aliases match browser_aliases.json", () => {
  // QML cannot read the JSON file synchronously (Quickshell's XHR blocks
  // local files), so Model.js mirrors the data as a literal. Fail loudly
  // if the mirror drifts from the canonical file — a silent divergence
  // would fold browsers differently under QML vs Node.
  const fs = require("fs")
  const file = JSON.parse(
    fs.readFileSync(require.resolve("../js/browser_aliases.json"), "utf8"),
  )
  const qml = Model.qmlBrowserAliases()
  assert.deepEqual(qml, file)
  assert.ok(Object.keys(qml).length > 0)
})

// ---- Data safety: pruneDays -----------------------------------------------

test("pruneDays keeps today and the window, drops the rest", () => {
  const days = {}
  for (let i = 0; i < 40; i++) {
    const d = new Date(2026, 7, 15 - i)
    days[Model.dayKey(d)] = { total: i * 1000, apps: {} }
  }
  const out = Model.pruneDays(days, "2026-08-15", 7)
  assert.equal(Object.keys(out).length, 7)
  assert.ok(out["2026-08-15"], "today must survive pruning")
  assert.equal(out["2026-07-15"], undefined)
})

test("pruneDays with keepDays of 1 keeps only today", () => {
  const days = {
    "2026-08-14": { total: 100 },
    "2026-08-15": { total: 200 },
  }
  const out = Model.pruneDays(days, "2026-08-15", 1)
  assert.deepEqual(Object.keys(out), ["2026-08-15"])
})

test("pruneDays with non-positive keepDays or null days is a no-op", () => {
  const days = { "2026-08-15": { total: 100 } }
  assert.equal(Model.pruneDays(days, "2026-08-15", 0), days)
  assert.equal(Model.pruneDays(days, "2026-08-15", -5), days)
  assert.equal(Model.pruneDays(null, "2026-08-15", 7), null)
})

test("pruneDays across year boundary keeps correct window", () => {
  const days = {
    "2025-12-30": { total: 100 },
    "2025-12-31": { total: 200 },
    "2026-01-01": { total: 300 },
    "2026-01-02": { total: 400 },
  }
  const out = Model.pruneDays(days, "2026-01-02", 3)
  assert.ok(out["2026-01-02"])
  assert.ok(out["2026-01-01"])
  assert.ok(out["2025-12-31"])
  assert.equal(out["2025-12-30"], undefined)
})

// ---- Data safety: corrupt / missing input ----------------------------------

test("firstDataYear reaches back through the month aggregates and year archive", () => {
  assert.equal(
    Model.firstDataYear({ "2026-01-01": {} }, {}, { 2024: { x: 1 } }),
    2024,
  )
  assert.equal(
    Model.firstDataYear({}, { "2025-06": 1 }, { 2024: { x: 1 } }),
    2024,
  )
  assert.equal(Model.firstDataYear({ 2026: { y: 1 } }, {}, {}), 2026)
  assert.equal(Model.firstDataYear({}, {}, {}), new Date().getFullYear())
})

test("appList returns empty for null input", () => {
  assert.deepEqual(Model.appList(null), [])
  assert.deepEqual(Model.appList(undefined), [])
  assert.deepEqual(Model.appList({}), [])
})

test("appList ignores negative and NaN durations", () => {
  const today = {
    total: 1000,
    apps: { a: -5000, b: NaN, c: 120000 },
  }
  const list = Model.appList(today)
  // a: -5000 < 60000 => dropped, b: NaN => dropped, c: 120000 => kept
  assert.equal(list.length, 1)
  assert.equal(list[0].app, "c")
})

test("groupedApps returns empty for null input", () => {
  assert.deepEqual(Model.groupedApps(null, 6, 3), [])
  assert.deepEqual(Model.groupedApps([], 6, 3), [])
})

test("groupedApps with a single app returns it as-is", () => {
  const apps = [{ app: "only", ms: 120000, pct: 100 }]
  const out = Model.groupedApps(apps, 6, 3)
  assert.equal(out.length, 1)
  assert.equal(out[0].app, "only")
})

test("insights handles null day and empty days gracefully", () => {
  const rows = Model.insights(null, {}, "2026-08-15", "2026-08-15")
  assert.equal(rows.length, 3)
  assert.ok(rows[0].value.includes("\u2014"))
  assert.ok(rows[1].value.includes("\u2014"))
  assert.ok(rows[2].value.includes("\u2014"))
})

test("insights handles day with apps but no total", () => {
  const day = { apps: { a: 60000 } }
  const rows = Model.insights(day, {}, "2026-08-15", "2026-08-15")
  assert.equal(rows.length, 3)
  // Total computed from apps: 60000
  assert.ok(rows[0].value.includes("a"))
})

test("fmt and fmtWords handle very large values", () => {
  const day = 86400000 * 365 // one year in ms
  assert.ok(Model.fmt(day).includes("h"))
  assert.ok(Model.fmtWords(day).includes("HOURS"))
})

test("dayFor with null days and empty today returns null", () => {
  assert.equal(Model.dayFor(null, null, "2026-08-15", "2026-08-15"), null)
})

test("dayKey pads local dates and rejects garbage", () => {
  assert.equal(Model.dayKey(new Date(2026, 0, 1)), "2026-01-01")
  assert.equal(Model.dayKey(new Date(2026, 11, 9)), "2026-12-09")
  assert.equal(Model.dayKey(null), "")
  assert.equal(Model.dayKey(new Date(NaN)), "")
})

// ---- weekStartMonday -----------------------------------------------------

test("weekStartMonday finds the Monday of a date", () => {
  // 2026-08-19 is Wednesday; 2026-08-16 is Sunday.
  assert.equal(Model.weekStartMonday("2026-08-19"), "2026-08-17")
  assert.equal(Model.weekStartMonday("2026-08-17"), "2026-08-17")
  assert.equal(Model.weekStartMonday("2026-08-16"), "2026-08-10")
  assert.equal(Model.weekStartMonday(""), "")
  assert.equal(Model.weekStartMonday(null), "")
})

// ---- isoWeekNumber --------------------------------------------------------

test("isoWeekNumber follows ISO weeks across year boundaries", () => {
  assert.equal(Model.isoWeekNumber("2026-08-17"), 34)
  assert.equal(Model.isoWeekNumber("2026-01-01"), 1)
  assert.equal(Model.isoWeekNumber("2025-12-29"), 1)
  assert.equal(Model.isoWeekNumber("2026-12-28"), 53)
  assert.equal(Model.isoWeekNumber(""), 0)
  assert.equal(Model.isoWeekNumber("garbage"), 0)
})

// ---- msUntilNextHour -------------------------------------------------------

test("msUntilNextHour counts down, full hour on the boundary", () => {
  assert.equal(
    Model.msUntilNextHour(new Date(2026, 7, 21, 10, 0, 0, 0).getTime()),
    3600000,
  )
  assert.equal(
    Model.msUntilNextHour(new Date(2026, 7, 21, 10, 59, 30, 500).getTime()),
    29500,
  )
  assert.equal(Model.msUntilNextHour(NaN), 60000)
})

// ---- monSunWeeks ---------------------------------------------------------

const sampleDays = {
  "2026-08-17": { total: 3600000 },
  "2026-08-18": { total: 7200000 },
  "2026-08-19": { total: 1800000 },
}

test("monSunWeeks builds Monday-first weeks around today", () => {
  const weeks = Model.monSunWeeks(sampleDays, "2026-08-19", 2)
  assert.equal(weeks.length, 2)
  const first = Model.monSunWeeks(sampleDays, "2026-08-19", 1)[0]
  assert.equal(first.days.length, 7)
  // 2026-08-17 is Monday, 2026-08-23 Sunday.
  assert.equal(first.days[0].key, "2026-08-17")
  assert.equal(first.days[0].label, "Mon")
  assert.equal(first.days[6].key, "2026-08-23")
  assert.equal(first.days[6].label, "Sun")
  const today = first.days.find((d) => d.isToday)
  assert.ok(today)
  assert.equal(today.key, "2026-08-19")
  // Thu Aug 20 - Sun Aug 23 are future.
  for (let i = 3; i < 7; i++) {
    assert.ok(first.days[i].isFuture, `Day index ${i} should be future`)
  }
  assert.equal(first.days.find((d) => d.key === "2026-08-17").ms, 3600000)
})

test("monSunWeeks labels the dominant month and rejects bad input", () => {
  // Week of Aug 31 - Sep 6: 4 days in Sep, 3 in Aug → "Sep".
  const weeks = Model.monSunWeeks(sampleDays, "2026-09-02", 1)
  assert.equal(weeks[0].month, "Sep")
  assert.deepEqual(Model.monSunWeeks({}, "", 3), [])
  assert.deepEqual(Model.monSunWeeks({}, "2026-08-19", 0), [])
})

// ---- scrollableTrendMax --------------------------------------------------

test("scrollableTrendMax returns max ms across all weeks", () => {
  const weeks = [
    {
      month: "Aug",
      days: [
        { ms: 100 },
        { ms: 500 },
        { ms: 200 },
        { ms: 0 },
        { ms: 0 },
        { ms: 0 },
        { ms: 0 },
      ],
    },
    {
      month: "Aug",
      days: [
        { ms: 300 },
        { ms: 50 },
        { ms: 0 },
        { ms: 0 },
        { ms: 0 },
        { ms: 0 },
        { ms: 0 },
      ],
    },
  ]
  assert.equal(Model.scrollableTrendMax(weeks), 500)
})

test("scrollableTrendMax returns 0 for empty weeks", () => {
  assert.equal(Model.scrollableTrendMax([]), 0)
})

// ---- weekAxisTicks -------------------------------------------------------

const HOUR_MS = 3600000

test("weekAxisTicks anchors empty and sparse weeks to the 4h reference", () => {
  assert.deepEqual(Model.weekAxisTicks(0), [0, 2 * HOUR_MS, 4 * HOUR_MS])
  assert.deepEqual(Model.weekAxisTicks(2 * HOUR_MS), [
    0,
    2 * HOUR_MS,
    4 * HOUR_MS,
  ])
  assert.deepEqual(Model.weekAxisTicks(4 * HOUR_MS), [
    0,
    2 * HOUR_MS,
    4 * HOUR_MS,
  ])
})

test("weekAxisTicks scales with the week's real maximum", () => {
  // The mid gridline label renders as whole hours, so the tick itself sits
  // on a whole hour — never 2.5h labelled "3h".
  assert.deepEqual(Model.weekAxisTicks(5 * HOUR_MS), [
    0,
    3 * HOUR_MS,
    5 * HOUR_MS,
  ])
  assert.deepEqual(Model.weekAxisTicks(9 * HOUR_MS), [
    0,
    5 * HOUR_MS,
    9 * HOUR_MS,
  ])
})

test("weekAxisTicks returns empty for junk input", () => {
  assert.deepEqual(Model.weekAxisTicks(null), [])
  assert.deepEqual(Model.weekAxisTicks(-1), [])
  assert.deepEqual(Model.weekAxisTicks(NaN), [])
})

test("fmtWholeHours renders ticks as round hour figures", () => {
  assert.equal(Model.fmtWholeHours(0), "0h")
  assert.equal(Model.fmtWholeHours(2 * HOUR_MS), "2h")
  assert.equal(Model.fmtWholeHours(2.5 * HOUR_MS), "3h")
  assert.equal(Model.fmtWholeHours(1.25 * HOUR_MS), "1h")
  assert.equal(Model.fmtWholeHours(null), "0h")
})

// ---- monthlyTotals -------------------------------------------------------

test("monthlyTotals aggregates raw days for recent months", () => {
  const days = {
    "2026-08-15": { total: 3600000 },
    "2026-08-16": { total: 1800000 },
    "2026-08-17": { total: 0 },
  }
  const totals = Model.monthlyTotals(days, {}, 2026)
  const aug = totals.find((t) => t.month === 7)
  assert.equal(aug.ms, 5400000)
})

test("monthlyTotals uses months aggregates for historical data", () => {
  const months = { "2026-03": 10000000 }
  const totals = Model.monthlyTotals({}, months, 2026)
  const mar = totals.find((t) => t.month === 2)
  assert.equal(mar.ms, 10000000)
  assert.ok(mar.hours.includes("h"))
})

test("monthlyTotals merges days and months without double counting", () => {
  // months has March data, days has April data — no overlap
  const days = { "2026-04-10": { total: 5000000 } }
  const months = { "2026-03": 3000000 }
  const totals = Model.monthlyTotals(days, months, 2026)
  const mar = totals.find((t) => t.month === 2)
  const apr = totals.find((t) => t.month === 3)
  assert.equal(mar.ms, 3000000)
  assert.equal(apr.ms, 5000000)
})

test("monthlyTotals returns 0h for months with no data", () => {
  const totals = Model.monthlyTotals({}, {}, 2026)
  const jan = totals.find((t) => t.month === 0)
  assert.equal(jan.ms, 0)
  assert.equal(jan.hours, "0h")
})

test("monthlyTotals returns 12 entries", () => {
  const totals = Model.monthlyTotals({}, {}, 2026)
  assert.equal(totals.length, 12)
})

// ---- yearTotal ------------------------------------------------------------

test("yearTotal sums raw days for the year", () => {
  const days = {
    "2026-01-01": { total: 1000000 },
    "2026-01-02": { total: 2000000 },
    "2025-12-31": { total: 9999999 },
  }
  assert.equal(Model.yearTotal(days, {}, 2026), 3000000)
})

test("yearTotal includes months aggregates", () => {
  const months = { "2026-01": 5000000, "2026-06": 8000000 }
  assert.equal(Model.yearTotal({}, months, 2026), 13000000)
})

test("yearTotal sums days and months together", () => {
  const days = { "2026-08-19": { total: 1000000 } }
  const months = { "2026-03": 2000000 }
  assert.equal(Model.yearTotal(days, months, 2026), 3000000)
})

test("yearTotal ignores different years", () => {
  const days = { "2025-08-19": { total: 9999999 } }
  const months = { "2025-01": 8888888 }
  assert.equal(Model.yearTotal(days, months, 2026), 0)
})

// ---- year archive + wrapped facts -----------------------------------------

function archiveFixture() {
  const h = HOUR_MS
  return {
    2026: {
      "2026-01-02": 2 * h,
      "2026-01-03": h,
      "2026-02-01": 3 * h,
      "2026-02-02": 3 * h,
      "2026-02-03": 3 * h,
      "2026-03-02": 8 * h,
      "2026-03-03": 8 * h,
      "2026-03-04": 5 * h,
      "2026-03-09": 11 * h,
    },
  }
}

test("yearFacts returns empty when the year has no data", () => {
  assert.deepEqual(Model.yearFacts({}, {}, {}, 2026, "2026-12-24"), [])
})

test("sanitizeHistory validates the years archive", () => {
  assert.deepEqual(
    Model.sanitizeHistory({}, {}, { 2026: { "2026-01-02": HOUR_MS } }).years,
    { 2026: { "2026-01-02": HOUR_MS } },
  )
  assert.deepEqual(
    Model.sanitizeHistory(
      {},
      {},
      { 2026: { "2026-01-02": "x", "2026-01-03": 0 } },
    ).years,
    { 2026: { "2026-01-03": 0 } },
  )
  assert.deepEqual(Model.sanitizeHistory({}, {}, { 2026: "nope" }).years, {})
})

test("rollupArchive coerces string totals to numbers", () => {
  const out = Model.rollupArchive({}, { "2026-08-01": { total: "3600" } })
  assert.deepEqual(out, { 2026: { "2026-08-01": 3600 } })
})

test("trackedDays returns 0 for a malformed todayKey", () => {
  const days = [{ date: "2026-08-19", ms: HOUR_MS }]
  assert.equal(Model.trackedDays(days, 2026, "not-a-day"), 0)
  assert.equal(Model.trackedDays(days, 2026, ""), 0)
})
test("rollupArchive keeps only per-day totals, never app maps", () => {
  const pruned = {
    "2026-08-01": { total: HOUR_MS, apps: { web: HOUR_MS } },
    "2026-08-02": { total: 0, apps: { done: 1 } },
    "2025-12-31": { total: 2 * HOUR_MS, apps: {} },
  }
  const base = { 2026: { "2026-08-03": 1000 } }
  const out = Model.rollupArchive(base, pruned)
  assert.deepEqual(out, {
    2026: { "2026-08-03": 1000, "2026-08-01": HOUR_MS },
    2025: { "2025-12-31": 2 * HOUR_MS },
  })
  assert.deepEqual(base, { 2026: { "2026-08-03": 1000 } })
})

test("yearDayTotals unions archive and live days, capped at todayKey", () => {
  const years = { 2026: { "2026-01-02": 2 * HOUR_MS, "2026-12-25": HOUR_MS } }
  const days = {
    "2026-01-03": { total: HOUR_MS, apps: {} },
    "2026-01-05": { total: 0, apps: {} },
  }
  assert.deepEqual(Model.yearDayTotals(years, days, 2026, "2026-12-24"), [
    { date: "2026-01-02", ms: 2 * HOUR_MS },
    { date: "2026-01-03", ms: HOUR_MS },
  ])
})

test("yearDayTotals walks whole years without fabricating days", () => {
  assert.deepEqual(
    Model.yearDayTotals({ 2028: {} }, {}, 2028, "2028-12-31"),
    [],
  )
  assert.deepEqual(
    Model.yearDayTotals(
      { 2026: { "2026-02-29": HOUR_MS } },
      {},
      2026,
      "2026-12-31",
    ),
    [],
  )
})

test("activeDayCount only counts days at or above the minute floor", () => {
  const days = [
    { date: "2026-01-01", ms: 59 * 1000 },
    { date: "2026-01-02", ms: 60 * 1000 },
    { date: "2026-01-03", ms: HOUR_MS },
  ]
  assert.equal(Model.activeDayCount(days, Model.MIN_ACTIVE_DAY_MS), 2)
  assert.equal(Model.activeDayCount([], Model.MIN_ACTIVE_DAY_MS), 0)
})

test("streakStats finds longest and current runs across month bounds", () => {
  const h = HOUR_MS
  const s = Model.streakStats([
    { date: "2026-01-31", ms: h },
    { date: "2026-02-01", ms: h },
    { date: "2026-02-02", ms: h },
    { date: "2026-02-10", ms: h },
    { date: "2026-02-11", ms: h },
  ])
  assert.equal(s.longest, 3)
  assert.equal(s.longestEnd, "2026-02-02")
  assert.equal(s.current, 2)
  assert.equal(s.lastActive, "2026-02-11")
})

test("streakStats handles empty and single-day inputs", () => {
  assert.deepEqual(Model.streakStats([]), {
    longest: 0,
    longestEnd: "",
    lastActive: "",
    current: 0,
  })
  const s = Model.streakStats([{ date: "2026-03-09", ms: HOUR_MS }])
  assert.equal(s.longest, 1)
  assert.equal(s.current, 1)
  assert.equal(s.lastActive, "2026-03-09")
})

test("yearFacts day cards scale from day-granular data, not month lumps", () => {
  // A month lump (from before the archive existed) counts into the year
  // share but must never move the per-day cards, which are computed
  // over real days only.
  const months = { "2026-02": 10 * HOUR_MS }
  const withLump = Model.yearFacts(
    {},
    months,
    archiveFixture(),
    2026,
    "2026-12-24",
  )
  const withoutLump = Model.yearFacts(
    {},
    {},
    archiveFixture(),
    2026,
    "2026-12-24",
  )
  for (const label of [
    "DAY COUNT",
    "AVERAGE SCREEN DAY",
    "WEEKDAY RHYTHM",
    "PEAK DAY",
    "LONGEST STREAK",
    "LONGEST BREAK",
    "BUSIEST WEEK",
    "RECHARGE MONTH",
  ]) {
    assert.equal(
      withLump.find((c) => c.label === label).value,
      withoutLump.find((c) => c.label === label).value,
      label + " ignores month lumps",
    )
  }
  // ...while the year share grows by exactly the lump: 44h + 10h.
  const share = (cards) => cards.find((c) => c.label === "SCREEN SHARE").value
  assert.ok(share(withoutLump).indexOf("44h") === 0)
  assert.ok(share(withLump).indexOf("54h") === 0)
})

test("TOP MONTHS medals months with middle dots", () => {
  const months = { "2026-03": 10 * HOUR_MS, "2026-01": 2 * HOUR_MS }
  const cards = Model.yearFacts({}, months, {}, 2026, "2026-12-24")
  assert.equal(
    cards.find((c) => c.label === "TOP MONTHS").value,
    '<font color="#FFD700"></font> Mar · <font color="#C0C0C0"></font> Jan',
  )
})

test("RECHARGE MONTH crowns the quietest tracked month, no coverage gate", () => {
  const recharge = (days, months, todayKey) =>
    Model.yearFacts(days, months, {}, 2026, todayKey).find(
      (c) => c.label === "RECHARGE MONTH",
    ).value
  // A 30min September day wins outright over older months.
  assert.match(
    recharge(
      { "2026-09-05": { total: 30 * 60000, apps: {} } },
      { "2026-03": 10 * HOUR_MS, "2026-01": 2 * HOUR_MS },
      "2026-09-06",
    ),
    /Sep · 1h/,
  )
  // A lone month takes the crown when it is all there is.
  assert.match(
    recharge({ "2026-09-05": { total: HOUR_MS, apps: {} } }, {}, "2026-09-06"),
    /Sep · 1h/,
  )
  // The current month wins fairly once it has real coverage (140min < 5h).
  const fortnight = {}
  for (let d = 1; d <= 14; d++)
    fortnight["2026-09-" + String(d).padStart(2, "0")] = {
      total: 10 * 60000,
      apps: {},
    }
  assert.match(
    recharge(fortnight, { "2026-01": 5 * HOUR_MS }, "2026-09-15"),
    /Sep · 2h/,
  )
})

test("longestBreak finds the longest offline gap", () => {
  const totals = [
    { date: "2026-03-01", ms: HOUR_MS },
    { date: "2026-03-02", ms: HOUR_MS },
    { date: "2026-03-14", ms: HOUR_MS },
  ]
  assert.deepEqual(Model.longestBreak(totals), { days: 11, end: "2026-03-14" })
})

test("longestBreak ignores single missed days and short lists", () => {
  assert.equal(
    Model.longestBreak([
      { date: "2026-03-01", ms: HOUR_MS },
      { date: "2026-03-03", ms: HOUR_MS },
    ]),
    null,
  )
  assert.equal(Model.longestBreak([{ date: "2026-03-01", ms: HOUR_MS }]), null)
  assert.equal(Model.longestBreak([]), null)
})

test("busiestSpan finds the peak Mon–Sun week", () => {
  // Aug 10–16 2026 is a real Mon–Sun week; Wed peaks at 9h.
  const totals = []
  for (let d = 10; d <= 16; d++)
    totals.push({ date: "2026-08-" + d, ms: d === 12 ? 9 * HOUR_MS : HOUR_MS })
  assert.deepEqual(Model.busiestSpan(totals), {
    start: "2026-08-10",
    end: "2026-08-16",
    ms: 15 * HOUR_MS,
  })
})

test("busiestSpan never crowns a rolling Tue–Mon window", () => {
  // Sun Aug 9 carries 9h: the rolling Aug 9–15 window totals 15h, but the
  // real Mon–Sun weeks are Aug 3–9 (9h) and Aug 10–16 (7h).
  const totals = [{ date: "2026-08-09", ms: 9 * HOUR_MS }]
  for (let d = 10; d <= 16; d++)
    totals.push({ date: "2026-08-" + d, ms: HOUR_MS })
  assert.deepEqual(Model.busiestSpan(totals), {
    start: "2026-08-03",
    end: "2026-08-09",
    ms: 9 * HOUR_MS,
  })
})

test("busiestSpan returns null without data", () => {
  assert.equal(Model.busiestSpan([]), null)
  assert.equal(Model.busiestSpan(null), null)
})

test("yearFacts shows BUSIEST WEEK for a full consecutive week", () => {
  const days = {}
  for (let d = 10; d <= 16; d++)
    days["2026-08-" + d] = { total: HOUR_MS, apps: {} }
  const cards = Model.yearFacts(days, {}, {}, 2026, "2026-08-16")
  const span = cards.find((c) => c.label === "BUSIEST WEEK")
  assert.ok(span)
  assert.match(span.value, /Aug 10–16 · 7h, your peak week/)
})

function weekEntry(hours) {
  return { days: hours.map((h) => ({ ms: h * HOUR_MS })) }
}

test("isRecordWeek needs a strict win over previous weeks", () => {
  assert.equal(
    Model.isRecordWeek([weekEntry([9, 9]), weekEntry([5, 5])], 0),
    true,
  )
  const tied = [weekEntry([9, 9]), weekEntry([9, 9]), weekEntry([1])]
  assert.equal(Model.isRecordWeek(tied, 0), false)
  assert.equal(Model.isRecordWeek([weekEntry([9])], 0), false)
  assert.equal(Model.isRecordWeek([], 0), false)
})

test("bestWeekOffset crowns the unique best at any offset", () => {
  assert.equal(
    Model.bestWeekOffset([weekEntry([3]), weekEntry([5]), weekEntry([4])]),
    1,
  )
  assert.equal(Model.bestWeekOffset([weekEntry([5]), weekEntry([3])]), 0)
  // Ties take no crown, and neither do empty or all-zero windows.
  assert.equal(Model.bestWeekOffset([weekEntry([5]), weekEntry([5])]), -1)
  assert.equal(Model.bestWeekOffset([weekEntry([0]), weekEntry([0])]), -1)
  assert.equal(Model.bestWeekOffset([]), -1)
})

test("yearSummary merges the three stores with no double counting", () => {
  const days = { "2026-08-15": { total: HOUR_MS, apps: {} } }
  const months = { "2026-07": 2 * HOUR_MS }
  const years = { 2026: { "2026-01-02": 3 * HOUR_MS } }
  const s = Model.yearSummary(days, months, years, 2026, "2026-12-24")
  assert.equal(s.total, 6 * HOUR_MS)
  assert.equal(
    s.months.reduce((a, m) => a + m.ms, 0),
    s.total,
  )
  assert.deepEqual(s.dayTotals, [
    { date: "2026-01-02", ms: 3 * HOUR_MS },
    { date: "2026-08-15", ms: HOUR_MS },
  ])
})

test("applyRetention prunes days into the archive in one step", () => {
  const days = {
    "2026-01-01": { total: HOUR_MS, apps: {} },
    "2026-08-15": { total: 2 * HOUR_MS, apps: {} },
  }
  const r = Model.applyRetention(days, {}, "2026-08-15", 95)
  assert.equal(r.pruned, true)
  assert.deepEqual(Object.keys(r.days), ["2026-08-15"])
  assert.deepEqual(r.years, { 2026: { "2026-01-01": HOUR_MS } })
})

test("applyRetention grows the archive across many calendar years", () => {
  const days = {
    "2023-02-10": { total: HOUR_MS, apps: {} },
    "2024-06-20": { total: 2 * HOUR_MS, apps: {} },
    "2026-08-15": { total: HOUR_MS, apps: {} },
  }
  const r = Model.applyRetention(days, {}, "2026-08-15", 365)
  assert.deepEqual(r.years, {
    2023: { "2023-02-10": HOUR_MS },
    2024: { "2024-06-20": 2 * HOUR_MS },
  })
})

test("applyRetention returns inputs untouched when nothing is pruned", () => {
  const days = { "2026-08-15": { total: HOUR_MS, apps: {} } }
  const years = { 2026: { "2026-01-02": HOUR_MS } }
  const r = Model.applyRetention(days, years, "2026-08-15", 95)
  assert.equal(r.pruned, false)
  assert.equal(r.days, days)
  assert.equal(r.years, years)
})

test("yearFacts degrades to month-scale cards when no day archive exists", () => {
  const months = { "2026-03": 10 * HOUR_MS, "2026-01": 2 * HOUR_MS }
  const cards = Model.yearFacts({}, months, {}, 2026, "2026-12-24")
  const labels = cards.map((c) => c.label)
  assert.ok(labels.includes("SCREEN SHARE"))
  assert.ok(labels.includes("TOP MONTHS"))
  assert.ok(labels.includes("RECHARGE MONTH"))
  assert.ok(!labels.includes("DAY COUNT"))
  assert.ok(!labels.includes("LONGEST STREAK"))
  assert.ok(!labels.includes("AVERAGE SCREEN DAY"))
  assert.ok(!labels.includes("WEEKDAY RHYTHM"))
  assert.ok(!labels.includes("PEAK DAY"))
})

test("yearFacts stays month and year scale, never names apps", () => {
  const days = {
    "2026-08-30": { total: 4 * HOUR_MS, apps: { zen: 4 * HOUR_MS } },
    "2026-08-31": { total: 2 * HOUR_MS, apps: { code: 2 * HOUR_MS } },
  }
  const cards = Model.yearFacts(days, {}, {}, 2026, "2026-08-31")
  const text = cards
    .map((c) => (c.label + c.value + c.sub).toLowerCase())
    .join(" ")
  assert.ok(!/zen|code|opencode|firefox|editor/i.test(text))
})

// ---- weekRangeLabel ------------------------------------------------------

test("weekRangeLabel shortens same-month, cross-month and cross-year weeks", () => {
  const same = Model.monSunWeeks({}, "2026-08-19", 1)
  assert.equal(Model.weekRangeLabel(same[0]), "Aug 17 – 23, 2026 · W34")
  // Reported bug: Sat Sep 5 2026 sits in the Aug 31 – Sep 6 week, which the
  // old header rendered as "Aug 2026 · W36".
  const cross = Model.monSunWeeks({}, "2026-09-05", 1)
  assert.equal(cross[0].days[0].key, "2026-08-31")
  assert.equal(Model.weekRangeLabel(cross[0]), "Aug 31 – Sep 6, 2026 · W36")
  const newYear = Model.monSunWeeks({}, "2026-01-01", 1)
  assert.equal(Model.weekRangeLabel(newYear[0]), "Dec 29, 25 – Jan 4, 26 · W1")
  assert.equal(Model.weekRangeLabel(null), "")
  assert.equal(Model.weekRangeLabel({}), "")
})

// ---- insightColors (theme-following insight glyphs) ----------------------

test("insightColors sources star and up from the theme roles", () => {
  const c = Model.insightColors("#e45b93", "#a55555")
  assert.equal(c.star, "#e45b93")
  assert.equal(c.up, "#a55555")
})

test("insightColors derives a green down and a distinct busiest", () => {
  const c = Model.insightColors("#e45b93", "#a55555")
  const downHsl = Model.hexToHsl(c.down)
  assert.ok(
    downHsl.h >= 120 && downHsl.h <= 180,
    `down should be green, got hue ${downHsl.h}`,
  )
  assert.notEqual(c.busiest, c.star)
  for (const k of ["star", "up", "down", "busiest"])
    assert.match(c[k], /^#[0-9a-f]{6}$/, `${k} should be a hex color`)
})

test("insightColors tracks theme swaps", () => {
  const a = Model.insightColors("#e45b93", "#a55555")
  const b = Model.insightColors("#4ecdc4", "#a55555")
  assert.notEqual(a.star, b.star)
  assert.notEqual(a.busiest, b.busiest)
  assert.notEqual(a.down, b.down)
  // Urgent is passed through, so up stays put when only accent changes.
  assert.equal(a.up, b.up)
})

test("insightColors stays vivid on a grayscale accent", () => {
  const c = Model.insightColors("#cacccc", "#a55555")
  assert.ok(Model.hexToHsl(c.down).s >= 40, "down should stay saturated")
  assert.ok(Model.hexToHsl(c.busiest).s >= 40, "busiest should stay saturated")
})

test("trackedDays counts the full past year, not 31 days", () => {
  const years = { 2025: { "2025-06-01": HOUR_MS } }
  const cards = Model.yearFacts({}, {}, years, 2025, "2026-01-05")
  const dayCount = cards.find((c) => c.label === "DAY COUNT")
  assert.equal(dayCount.value, "Active on 1 of 365 tracked days")
})

test("trackedDays counts 366 for a past leap year", () => {
  const years = { 2024: { "2024-06-01": HOUR_MS } }
  const cards = Model.yearFacts({}, {}, years, 2024, "2026-01-05")
  const dayCount = cards.find((c) => c.label === "DAY COUNT")
  assert.equal(dayCount.value, "Active on 1 of 366 tracked days")
})

test("pruneDays with missing keepDays returns days untouched", () => {
  const days = {
    "2026-01-01": { total: 100 },
    "2026-08-15": { total: 200 },
  }
  assert.equal(Model.pruneDays(days, "2026-08-15", undefined), days)
  assert.equal(Model.pruneDays(days, "2026-08-15", NaN), days)
})

test("monthlyTotals and yearTotal coerce string day totals", () => {
  const days = { "2026-08-15": { total: "3600000", apps: {} } }
  const totals = Model.monthlyTotals(days, {}, 2026)
  assert.equal(totals.find((t) => t.month === 7).ms, 3600000)
  assert.equal(Model.yearTotal(days, {}, 2026), 3600000)
})

test("yearDayTotals coerces string archive values", () => {
  const years = { 2026: { "2026-01-02": "7200000" } }
  assert.deepEqual(Model.yearDayTotals(years, {}, 2026, "2026-12-24"), [
    { date: "2026-01-02", ms: 7200000 },
  ])
})

test("sanitizeHistory cleans malformed day shapes", () => {
  const days = {
    "2026-08-15": { total: "not-a-number", apps: ["zen"] },
    "2026-08-16": { total: -5, apps: { zen: NaN, foot: 60000 } },
  }
  const clean = Model.sanitizeHistory(days, {}, {})
  assert.equal(clean.days["2026-08-15"].total, 0)
  assert.deepEqual(clean.days["2026-08-15"].apps, {})
  assert.equal(clean.days["2026-08-16"].total, 0)
  assert.deepEqual(clean.days["2026-08-16"].apps, { foot: 60000 })
})

test("insights busiest day follows the navigated week", () => {
  const days = {
    "2026-08-19": { total: 9 * HOUR_MS },
    "2026-09-03": { total: 1 * HOUR_MS },
  }
  const today = { total: 1 * HOUR_MS, apps: { a: 3600000 } }
  // Navigated to the Aug 17–23 week (Sunday Aug 23): busiest is Aug 19,
  // not the current week's Sep 3.
  const rows = Model.insights(
    today,
    days,
    "2026-09-05",
    "2026-09-05",
    "2026-08-23",
  )
  assert.ok(rows[2].value.includes("Wed"))
  assert.ok(rows[2].value.includes("9h"))
})

test("insights rows carry kinds for the icon routing", () => {
  const day = { total: 2 * HOUR_MS, apps: { zen: 2 * HOUR_MS } }
  const rows = Model.insights(day, {}, "2026-08-15", "2026-08-15")
  assert.deepEqual(
    rows.map((r) => r.kind),
    ["top", "delta", "busiest"],
  )
})

test("insights delta direction follows the sign", () => {
  const up = Model.insights(
    { total: 3 * HOUR_MS, apps: {} },
    { "2026-08-14": { total: HOUR_MS, apps: {} } },
    "2026-08-15",
    "2026-08-15",
  )
  assert.equal(up[1].dir, "up")
  const down = Model.insights(
    { total: HOUR_MS, apps: {} },
    { "2026-08-14": { total: 3 * HOUR_MS, apps: {} } },
    "2026-08-15",
    "2026-08-15",
  )
  assert.equal(down[1].dir, "down")
  const flat = Model.insights(
    { total: HOUR_MS, apps: {} },
    { "2026-08-14": { total: HOUR_MS, apps: {} } },
    "2026-08-15",
    "2026-08-15",
  )
  assert.equal(flat[1].dir, "flat")
})

test("insights busiest day defaults to the trailing week", () => {
  const days = { "2026-09-03": { total: 1 * HOUR_MS } }
  const today = { total: 1 * HOUR_MS, apps: { a: 3600000 } }
  const rows = Model.insights(today, days, "2026-09-05", "2026-09-05")
  assert.ok(rows[2].value.includes("Thu"))
})

test("mergeYear keeps legacy lumps and archive days side by side", () => {
  // months holds pre-archive lumps only; nothing writes it anymore, and a
  // day is deleted into exactly one store, so a lump and archive days in
  // the same month describe different days — both count, never deduped.
  const months = { "2026-06": 3600000 }
  const years = { 2026: { "2026-06-20": 3600000 } }
  const totals = Model.monthlyTotals({}, months, 2026, years, "2026-08-19")
  assert.equal(totals[5].ms, 7200000)
})

test("monthlyTotals with todayKey excludes future dates like yearFacts", () => {
  const days = {
    "2026-08-19": { total: 3600000, apps: {} },
    "2026-12-25": { total: 3600000, apps: {} }, // future relative to todayKey
  }
  const filtered = Model.monthlyTotals(days, {}, 2026, {}, "2026-08-19")
  assert.equal(filtered[7].ms, 3600000) // Aug keeps its day
  assert.equal(filtered[11].ms, 0) // Dec future day excluded
})

test("mergeYear excludes future month lumps like future days", () => {
  // A Dec lump (e.g. from a clock jump forward and back) must not inflate
  // the year total and month bars while dayTotals stays empty.
  const months = { "2026-08": 3600000, "2026-12": 10 * 3600000 }
  const totals = Model.monthlyTotals({}, months, 2026, {}, "2026-08-19")
  assert.equal(totals[7].ms, 3600000) // Aug lump kept
  assert.equal(totals[11].ms, 0) // Dec future lump excluded
  assert.equal(Model.yearTotal({}, months, 2026, {}, "2026-08-19"), 3600000)
})

test("yearFacts treats a string year exactly like a number", () => {
  // Current month (Aug) is the quietest: with no coverage gate it wins
  // for both year shapes identically.
  const days = {
    "2026-03-10": { total: 5 * 3600000, apps: {} },
    "2026-06-10": { total: 2 * 3600000, apps: {} },
    "2026-08-19": { total: 3600000, apps: {} },
  }
  const num = Model.yearFacts(days, {}, {}, 2026, "2026-08-19", "#e45b93")
  const str = Model.yearFacts(days, {}, {}, "2026", "2026-08-19", "#e45b93")
  const recharge = (cards) =>
    (cards.find((c) => c.label === "RECHARGE MONTH") || {}).value
  assert.equal(recharge(num), recharge(str))
  assert.ok(recharge(num).startsWith("Aug"))
})

test("yearFacts derives card colors from the theme accent", () => {
  const months = { "2026-03": 10 * HOUR_MS, "2026-01": 2 * HOUR_MS }
  const pink = Model.yearFacts({}, months, {}, 2026, "2026-12-24", "#e45b93")
  const teal = Model.yearFacts({}, months, {}, 2026, "2026-12-24", "#4ecdc4")
  assert.ok(pink.length > 0)
  assert.equal(pink[0].color, "#e45b93")
  assert.equal(teal[0].color, "#4ecdc4")
  assert.deepEqual(
    pink.map((c) => c.color),
    Model.sliceColors(pink.length, "#e45b93"),
  )
})

// ---- weekView / yearView ---------------------------------------------------
// One derivation per view: Panel threads selection into seven separate
// week expressions (and two year merges); the views fuse each family so
// callers reason about the week and the year, not the primitives.

const HOUR_MS_VIEW = 3600000

test("weekView selects the visible week and derives its facts", () => {
  const days = {
    "2026-08-17": { total: 1 * HOUR_MS_VIEW, apps: {} },
    "2026-08-18": { total: 2 * HOUR_MS_VIEW, apps: {} },
    "2026-08-10": { total: 4 * HOUR_MS_VIEW, apps: {} },
  }
  const view = Model.weekView(days, "2026-08-19", 2, 0)
  assert.equal(view.weeks.length, 2)
  assert.equal(view.week.days.length, 7)
  assert.equal(view.max, 2 * HOUR_MS_VIEW)
  assert.equal(view.totalMs, 3 * HOUR_MS_VIEW)
  assert.equal(view.isRecord, false) // older week (Aug 10) is bigger
  assert.equal(view.hasPrev, true)
  assert.equal(view.weekEndKey, "2026-08-23")
})

test("weekView paginates to older weeks", () => {
  const days = {
    "2026-08-17": { total: 1 * HOUR_MS_VIEW, apps: {} },
    "2026-08-10": { total: 4 * HOUR_MS_VIEW, apps: {} },
  }
  const view = Model.weekView(days, "2026-08-19", 2, 1)
  assert.equal(view.week.days[0].key, "2026-08-10")
  assert.equal(view.totalMs, 4 * HOUR_MS_VIEW)
})

test("weekView crowns the unique best once two weeks hold data", () => {
  const days = {
    "2026-08-18": { total: 2 * HOUR_MS_VIEW, apps: {} },
    "2026-08-12": { total: 1 * HOUR_MS_VIEW, apps: {} },
  }
  const view = Model.weekView(days, "2026-08-19", 2, 0)
  assert.equal(view.isRecord, true)
})

test("weekView trophy follows the best week to its page", () => {
  const days = {
    "2026-08-18": { total: 1 * HOUR_MS_VIEW, apps: {} },
    "2026-08-12": { total: 2 * HOUR_MS_VIEW, apps: {} },
  }
  assert.equal(Model.weekView(days, "2026-08-19", 2, 0).isRecord, false)
  assert.equal(Model.weekView(days, "2026-08-19", 2, 1).isRecord, true)
})

test("weekView crowns nothing with a single data week", () => {
  const days = { "2026-08-18": { total: 2 * HOUR_MS_VIEW, apps: {} } }
  assert.equal(Model.weekView(days, "2026-08-19", 2, 0).isRecord, false)
})

test("weekView tolerates an out-of-range offset", () => {
  const view = Model.weekView({}, "2026-08-19", 2, 9)
  assert.equal(view.week, null)
  assert.equal(view.max, 0)
  assert.equal(view.totalMs, 0)
  assert.equal(view.isRecord, false)
  assert.equal(view.hasPrev, false)
  assert.equal(view.weekEndKey, "")
})

test("yearFactsFromSummary builds cards from a fixed fixture", () => {
  const days = {
    "2026-03-10": { total: 5 * 3600000, apps: {} },
    "2026-08-19": { total: 3600000, apps: {} },
  }
  const summary = Model.yearSummary(days, {}, {}, 2026, "2026-08-19")
  const facts = Model.yearFactsFromSummary(
    summary,
    2026,
    "2026-08-19",
    "#e45b93",
  )
  assert.ok(facts.length > 0)
  assert.equal(facts[0].label, "SCREEN SHARE")
  assert.ok(facts[0].value.indexOf("6h on screens") === 0)
})

test("yearView labels the year total and tints its facts", () => {
  const months = { "2026-03": 10 * HOUR_MS_VIEW, "2026-01": 2 * HOUR_MS_VIEW }
  const view = Model.yearView({}, months, {}, 2026, "2026-12-24", "#e45b93")
  assert.equal(view.totalLabel, "12h")
  assert.ok(view.facts.length > 0)
  assert.equal(view.facts[0].color, "#e45b93")
})

test("yearView is empty for a year with no data", () => {
  const view = Model.yearView({}, {}, {}, 2026, "2026-12-24", "#e45b93")
  assert.equal(view.totalLabel, "0h")
  assert.deepEqual(view.facts, [])
})

test("parseIgnoredApps accepts arrays and comma strings, lowercased deduped", () => {
  assert.deepEqual(Model.parseIgnoredApps(["Zen", " zen ", "", "foot"]), [
    "zen",
    "foot",
  ])
  assert.deepEqual(Model.parseIgnoredApps("Zen, foot,, "), ["zen", "foot"])
  assert.deepEqual(Model.parseIgnoredApps(undefined), [])
  assert.deepEqual(Model.parseIgnoredApps(42), [])
})

test("isIgnoredApp matches raw, canonical and display names", () => {
  assert.equal(Model.isIgnoredApp("zen-bin", ["zen"]), true)
  assert.equal(Model.isIgnoredApp("com.github.user.Codium", ["codium"]), true)
  assert.equal(Model.isIgnoredApp("foot", ["foot"]), true)
  assert.equal(Model.isIgnoredApp("foot", ["kitty"]), false)
  assert.equal(Model.isIgnoredApp("foot", []), false)
  assert.equal(Model.isIgnoredApp("", ["foot"]), false)
})

test("parseAppAliases accepts objects and from=to strings", () => {
  assert.deepEqual(Model.parseAppAliases({ Foot: "terminal " }), {
    foot: "terminal",
  })
  assert.deepEqual(Model.parseAppAliases("foot=terminal, code=work"), {
    foot: "terminal",
    code: "work",
  })
  assert.deepEqual(Model.parseAppAliases("noequals, a="), {})
  assert.deepEqual(Model.parseAppAliases(undefined), {})
})

test("resolveAppName applies the alias before the canonical fold", () => {
  assert.equal(Model.resolveAppName("foot", { foot: "terminal" }), "terminal")
  assert.equal(Model.resolveAppName("zen-bin", {}), "zen")
  assert.equal(Model.resolveAppName("", {}), "")
})

test("filterIgnoredDay strips ignored apps and recomputes the total", () => {
  const day = { total: 70000, apps: { zen: 60000, foot: 10000 } }
  assert.equal(Model.filterIgnoredDay(day, []), day)
  assert.deepEqual(Model.filterIgnoredDay(day, ["foot"]), {
    total: 60000,
    apps: { zen: 60000 },
  })
  assert.deepEqual(Model.filterIgnoredDay(day, ["zen", "foot"]), {
    total: 0,
    apps: {},
  })
})

test("parseDailyGoalHours keeps whole hours 1-24, else off", () => {
  assert.equal(Model.parseDailyGoalHours(6), 6)
  assert.equal(Model.parseDailyGoalHours("8"), 8)
  assert.equal(Model.parseDailyGoalHours(0), 0)
  assert.equal(Model.parseDailyGoalHours(25), 0)
  assert.equal(Model.parseDailyGoalHours("lots"), 0)
  assert.equal(Model.parseDailyGoalHours(undefined), 0)
})

test("goalProgress reports pct, remaining and reached", () => {
  assert.equal(Model.goalProgress(3600000, 0), null)
  const half = Model.goalProgress(3 * 3600000, 6)
  assert.equal(half.pct, 50)
  assert.equal(half.remainingMs, 3 * 3600000)
  assert.equal(half.reached, false)
  const over = Model.goalProgress(7 * 3600000, 6)
  assert.equal(over.pct, 100)
  assert.equal(over.remainingMs, 0)
  assert.equal(over.reached, true)
})

test("parseWeekCount keeps presets, rounds legacy up, defaults to 12", () => {
  assert.equal(Model.parseWeekCount(12), 12)
  assert.equal(Model.parseWeekCount(24), 24)
  assert.equal(Model.parseWeekCount(36), 36)
  assert.equal(Model.parseWeekCount(52), 52)
  assert.equal(Model.parseWeekCount(4), 12)
  assert.equal(Model.parseWeekCount(8), 12)
  assert.equal(Model.parseWeekCount(16), 24)
  assert.equal(Model.parseWeekCount(20), 24)
  assert.equal(Model.parseWeekCount(undefined), 12)
  assert.equal(Model.parseWeekCount(0), 12)
})

test("app detail spans a full year of week-count options", () => {
  assert.ok(Model.WEEK_COUNT_OPTIONS.includes(Model.parseWeekCount(undefined)))
})

test("storageSummary counts days, months and archived entries", () => {
  const days = { "2026-08-19": { total: 3600000, apps: {} } }
  const months = { "2026-07": 7200000 }
  const years = { 2026: { "2026-06-01": 1800000 } }
  const summary = Model.storageSummary(days, months, years)
  assert.equal(summary.dayCount, 1)
  assert.equal(summary.monthCount, 1)
  assert.equal(summary.archiveDays, 1)
  assert.equal(summary.totalMs, 12600000)
  assert.equal(Model.storageLabel(summary), "1 days · 1 months · 1 archived")
  assert.equal(Model.storageLabel(null), "0 days · 0 months · 0 archived")
})

test("resolveAppName matches canonical and display names, not just raw", () => {
  assert.equal(Model.resolveAppName("zen-bin", { zen: "browser" }), "browser")
  assert.equal(
    Model.resolveAppName("com.github.user.Codium", { codium: "work" }),
    "work",
  )
})

test("resolveAppName falls back to a contained key", () => {
  assert.equal(
    Model.resolveAppName("zen-browser", { zen: "browser" }),
    "browser",
  )
  assert.equal(Model.resolveAppName("foot", { foo: "bar" }), "foot")
})

test("resolveAppName prefers exact matches over contained keys", () => {
  assert.equal(
    Model.resolveAppName("code", { code: "work", cod: "play" }),
    "work",
  )
})

test("ignoredWith appends normalized names without duplicates", () => {
  assert.deepEqual(Model.ignoredWith(["foot"], " Kitty "), ["foot", "kitty"])
  assert.deepEqual(Model.ignoredWith(["foot"], "FOOT"), ["foot"])
  assert.deepEqual(Model.ignoredWith(["foot"], "  "), ["foot"])
})

test("ignoredWithout drops one normalized name", () => {
  assert.deepEqual(Model.ignoredWithout(["foot", "kitty"], "FOOT"), ["kitty"])
  assert.deepEqual(Model.ignoredWithout(["foot"], "nope"), ["foot"])
})

test("aliasPairs round-trips through serializeAliases", () => {
  const pairs = Model.aliasPairs("foot=terminal, code=work")
  assert.deepEqual(pairs, [
    { from: "foot", to: "terminal" },
    { from: "code", to: "work" },
  ])
  assert.equal(
    Model.serializeAliases({ foot: "terminal", code: "work" }),
    "foot=terminal, code=work",
  )
})

test("aliasesWith upserts and aliasesWithout deletes", () => {
  assert.equal(Model.aliasesWith("", " Zen ", "browser"), "zen=browser")
  assert.equal(Model.aliasesWith("zen=browser", "zen", "web"), "zen=web")
  assert.equal(Model.aliasesWith("zen=browser", "", "web"), "zen=browser")
  assert.equal(
    Model.aliasesWithout("zen=browser, code=work", "ZEN"),
    "code=work",
  )
})

test("isHexColor accepts six digits with or without a hash", () => {
  assert.equal(Model.isHexColor("#FFD700"), true)
  assert.equal(Model.isHexColor("2b2b2b"), true)
  assert.equal(Model.isHexColor("#fff"), false)
  assert.equal(Model.isHexColor("gold"), false)
  assert.equal(Model.isHexColor(""), false)
  assert.equal(Model.isHexColor(null), false)
})

test("normalizeHex lowercases and hashes, else the fallback", () => {
  assert.equal(Model.normalizeHex("#FFD700", ""), "#ffd700")
  assert.equal(Model.normalizeHex("2B2B2B", ""), "#2b2b2b")
  assert.equal(Model.normalizeHex("nope", "fb"), "fb")
  assert.equal(Model.normalizeHex(undefined, "fb"), "fb")
})

test("themeSwatches leads with theme neutrals and an accent family", () => {
  const swatches = Model.themeSwatches("#ff0000", "#CACCCC", "#707880")
  assert.equal(swatches.length, 7)
  assert.equal(swatches[0], "#cacccc")
  assert.equal(swatches[1], "#707880")
  assert.equal(swatches[2], "#ff0000")
  for (const s of swatches) assert.match(s, /^#[0-9a-f]{6}$/)
})

test("themeSwatches degrades gracefully on a grayscale theme", () => {
  const swatches = Model.themeSwatches("#cacccc", "#cacccc", "#707880")
  assert.equal(swatches.length, 7)
  for (let i = 2; i < swatches.length; i++) {
    assert.ok(Model.hexToHsl(swatches[i]).s < 12)
  }
})

test("pickSwatch keeps any valid stored hex, else the default", () => {
  assert.equal(Model.pickSwatch("#FFD700", "#ffd700"), "#ffd700")
  assert.equal(Model.pickSwatch("2b2b2b", "fb"), "#2b2b2b")
  assert.equal(Model.pickSwatch("junk", "fb"), "fb")
  assert.equal(Model.pickSwatch("", "fb"), "fb")
  assert.equal(Model.pickSwatch(undefined, "fb"), "fb")
})

test("minKeepDays covers the window plus slack", () => {
  assert.equal(Model.minKeepDays(12), 95)
  assert.equal(Model.minKeepDays(24), 179)
  assert.equal(Model.minKeepDays(36), 263)
  assert.equal(Model.minKeepDays(52), 375)
  assert.equal(Model.minKeepDays(undefined), 95)
  assert.equal(Model.minKeepDays(0), 95)
})

test("refoldDay merges keys that resolve elsewhere, keeps the total", () => {
  const day = { total: 70000, apps: { zen: 60000, foot: 10000 } }
  assert.deepEqual(Model.refoldDay(day, { zen: "browser" }), {
    total: 70000,
    apps: { browser: 60000, foot: 10000 },
  })
})

test("refoldDay returns the input by identity when nothing moves", () => {
  const day = { total: 70000, apps: { zen: 60000, foot: 10000 } }
  assert.equal(Model.refoldDay(day, {}), day)
  assert.equal(Model.refoldDay(day, { code: "work" }), day)
  assert.equal(Model.refoldDay(null, { zen: "browser" }), null)
})

test("refoldDay sums into an already-tracked target", () => {
  const day = { total: 90000, apps: { zen: 60000, browser: 30000 } }
  assert.deepEqual(Model.refoldDay(day, { zen: "browser" }), {
    total: 90000,
    apps: { browser: 90000 },
  })
})

test("isDayKey accepts real padded days only", () => {
  assert.equal(Model.isDayKey("2026-08-19"), true)
  assert.equal(Model.isDayKey("2024-02-29"), true)
  assert.equal(Model.isDayKey("2026-02-29"), false)
  assert.equal(Model.isDayKey("2026-13-01"), false)
  assert.equal(Model.isDayKey("2026-8-5"), false)
  assert.equal(Model.isDayKey("garbage"), false)
  assert.equal(Model.isDayKey("__proto__"), false)
  assert.equal(Model.isDayKey(""), false)
  assert.equal(Model.isDayKey(null), false)
  // Readers funnel through the validator, so rolled-over dates surface
  // as empty everywhere downstream.
  assert.equal(Model.formatDate("2026-02-30"), "")
})

test("isMonthKey accepts real calendar months only", () => {
  assert.equal(Model.isMonthKey("2026-08"), true)
  assert.equal(Model.isMonthKey("2026-13"), false)
  assert.equal(Model.isMonthKey("2026-8"), false)
  assert.equal(Model.isMonthKey("__proto__"), false)
})

test("sanitizeHistory drops malformed keys, keeps identity when clean", () => {
  const days = { "2026-08-19": { total: 1000, apps: {} } }
  const months = { "2026-08": 1000 }
  const years = { 2026: { "2026-08-18": 1000 } }
  const clean = Model.sanitizeHistory(days, months, years)
  assert.equal(clean.days, days)
  assert.equal(clean.months, months)
  const dirty = Model.sanitizeHistory(
    { "2026-08-19": { total: 1000, apps: {} }, junk: { total: 1, apps: {} } },
    { "2026-08": 1000, nope: 5 },
    { 2026: { "2026-08-18": 1000, "2026-02-29": 5 } },
  )
  assert.deepEqual(Object.keys(dirty.days), ["2026-08-19"])
  assert.deepEqual(Object.keys(dirty.months), ["2026-08"])
  assert.deepEqual(Object.keys(dirty.years[2026]), ["2026-08-18"])
})

test("sanitizeYears drops wrong-year days and proto keys", () => {
  const out = Model.sanitizeYears({
    2026: { "2026-08-18": 1000, "2025-01-01": 5 },
    junk: { "2026-08-18": 1 },
  })
  assert.deepEqual(Object.keys(out), ["2026"])
  assert.deepEqual(Object.keys(out[2026]), ["2026-08-18"])
  const proto = JSON.parse('{"2026": {"__proto__": 5, "2026-08-18": 1}}')
  assert.deepEqual(Object.keys(Model.sanitizeYears(proto)[2026]), [
    "2026-08-18",
  ])
  assert.equal({}.polluted, undefined)
})

test("parseAppAliases never mints __proto__", () => {
  assert.deepEqual(Model.parseAppAliases("__proto__=x, a=b"), { a: "b" })
  assert.equal(Model.aliasesWith("", "__proto__", "x"), "")
  assert.equal({}.polluted, undefined)
})

test("mergeYear ignores phantom and malformed dates", () => {
  const merged = Model.mergeYear(
    {
      "2026-02-29": { total: 3600000, apps: {} },
      "2024-02-29": { total: 3600000, apps: {} },
    },
    {},
    {},
    2026,
    "2026-12-31",
  )
  assert.equal(merged.monthMs[1], 0)
  assert.deepEqual(merged.dayTotals, [])
  const leap = Model.mergeYear(
    { "2024-02-29": { total: 3600000, apps: {} } },
    {},
    {},
    2024,
    "2024-12-31",
  )
  assert.equal(leap.monthMs[1], 3600000)
})

test("rollupArchive only rolls real day keys", () => {
  const out = Model.rollupArchive(
    {},
    {
      "2026-08-18": { total: 1000, apps: {} },
      junk: { total: 5, apps: {} },
    },
  )
  assert.deepEqual(Object.keys(out["2026"]), ["2026-08-18"])
  assert.equal({}.polluted, undefined)
})

test("leap days round-trip through every key reader", () => {
  assert.equal(Model.prevKey("2024-03-01"), "2024-02-29")
  assert.equal(Model.formatDate("2024-02-29"), "Feb 29")
  assert.ok(Model.isDayKey("2024-02-29"))
  assert.equal(Model.weekdayLabel("2024-02-29"), "Thu")
  assert.equal(Model.mondayKey("2024-02-29"), "2024-02-26")
})

test("iso weeks anchor W52 and year-boundary Thursdays", () => {
  assert.equal(Model.isoWeekNumber("2025-12-28"), 52)
  assert.equal(Model.isoWeekNumber("2024-12-31"), 1)
  assert.equal(Model.isoWeekNumber("2025-12-31"), 1)
})

test("century years follow Gregorian leap rules", () => {
  assert.equal(Model.yearHours(1900), 8760)
  assert.equal(Model.yearHours(2000), 8784)
})

test("every leap-year day round-trips through keys and weeks", () => {
  const names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  var d = new Date(2024, 0, 1)
  var count = 0
  while (d.getTime() < new Date(2025, 0, 1).getTime()) {
    const key = Model.dayKey(d)
    assert.ok(Model.isDayKey(key), key)
    assert.ok(names.includes(Model.weekdayLabel(key)), key)
    assert.ok(Model.formatDate(key).length > 0, key)
    const mon = Model.mondayKey(key)
    assert.ok(Model.isDayKey(mon), mon)
    assert.equal(Model.mondayKey(mon), mon)
    const weekNo = Model.isoWeekNumber(key)
    assert.ok(weekNo >= 1 && weekNo <= 53, key)
    count++
    d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)
  }
  assert.equal(count, 366)
})

test("v1.5.0 history loads without modification", () => {
  const days = {
    "2026-08-19": { total: 490875, apps: { zen: 313349, opencode: 148706 } },
    "2026-08-18": { total: 3600000, apps: { zen: 3600000 } },
  }
  const months = { "2026-07": 9823400 }
  const years = { 2026: { "2026-06-01": 1800000 } }
  const clean = Model.sanitizeHistory(days, months, years)
  assert.equal(clean.days, days)
  assert.equal(clean.months, months)
  assert.equal(clean.years, years)
})

test("upgrading retention preserves every millisecond", () => {
  const today = new Date()
  const days = {}
  let n = 0
  for (let back = 119; back >= 0; back--) {
    const d = new Date(
      today.getFullYear(),
      today.getMonth(),
      today.getDate() - back,
    )
    const key = Model.dayKey(d)
    const total = 3600000 + back * 1000
    days[key] = { total: total, apps: { zen: total } }
    n++
  }
  assert.equal(Object.keys(days).length, 120)
  const months = { "2026-07": 9823400 }
  const todayKey = Model.dayKey(today)
  const year = today.getFullYear()
  const years = {}
  years[year] = {}
  const before =
    Object.keys(days).reduce((t, k) => t + days[k].total, 0) + months["2026-07"]
  const ret = Model.applyRetention(days, years, todayKey, 95)
  assert.equal(ret.pruned, true)
  const afterDays = Object.keys(ret.days).reduce(
    (t, k) => t + ret.days[k].total,
    0,
  )
  const afterArchive = Object.keys(ret.years[year]).reduce(
    (t, k) => t + ret.years[year][k],
    0,
  )
  assert.equal(afterDays + afterArchive + months["2026-07"], before)
  // Nothing older than the window survives as day detail.
  const cutoff = Model.dayKey(
    new Date(today.getFullYear(), today.getMonth(), today.getDate() - 94),
  )
  for (const k of Object.keys(ret.days)) assert.ok(k >= cutoff, k)
})

test("yearView counts active months for the hero caption", () => {
  const months = { "2026-03": 10 * HOUR_MS_VIEW, "2026-01": 2 * HOUR_MS_VIEW }
  assert.equal(
    Model.yearView({}, months, {}, 2026, "2026-12-24", "#e45b93").monthsActive,
    2,
  )
  assert.equal(
    Model.yearView({}, {}, {}, 2026, "2026-12-24", "#e45b93").monthsActive,
    0,
  )
})

test("refoldDay inverts through an inverse map on removal", () => {
  const day = { total: 70000, apps: { browser: 60000, foot: 10000 } }
  assert.deepEqual(Model.refoldDay(day, { browser: "zen" }), {
    total: 70000,
    apps: { zen: 60000, foot: 10000 },
  })
  const mixed = { total: 90000, apps: { browser: 60000, zen: 30000 } }
  assert.deepEqual(Model.refoldDay(mixed, { browser: "zen" }), {
    total: 90000,
    apps: { zen: 90000 },
  })
})

test("parseGoalLog keeps valid entries sorted with latest per day", () => {
  assert.deepEqual(Model.parseGoalLog(undefined), [])
  assert.deepEqual(Model.parseGoalLog("nope"), [])
  assert.deepEqual(
    Model.parseGoalLog([
      { day: "2026-09-13", hours: 8 },
      { day: "2026-09-11", hours: 6 },
      { day: "2026-09-11", hours: 4 },
      { day: "junk", hours: 6 },
      { day: "2026-09-12", hours: 99 },
    ]),
    [
      { day: "2026-09-11", hours: 4 },
      { day: "2026-09-13", hours: 8 },
    ],
  )
})

test("goalForDay returns the hours in force that day", () => {
  const log = [
    { day: "2026-09-11", hours: 6 },
    { day: "2026-09-12", hours: 0 },
    { day: "2026-09-13", hours: 8 },
  ]
  assert.equal(Model.goalForDay(log, "2026-09-10"), 0)
  assert.equal(Model.goalForDay(log, "2026-09-11"), 6)
  assert.equal(Model.goalForDay(log, "2026-09-12"), 0)
  assert.equal(Model.goalForDay(log, "2026-09-13"), 8)
  assert.equal(Model.goalForDay(log, "2026-09-20"), 8)
  assert.equal(Model.goalForDay(null, "2026-09-11"), 0)
  assert.equal(Model.goalForDay(log, ""), 0)
})

test("logGoalChange appends, replaces same-day, and caps", () => {
  assert.deepEqual(Model.logGoalChange([], "2026-09-11", 6), [
    { day: "2026-09-11", hours: 6 },
  ])
  assert.deepEqual(
    Model.logGoalChange([{ day: "2026-09-11", hours: 6 }], "2026-09-11", 8),
    [{ day: "2026-09-11", hours: 8 }],
  )
  assert.deepEqual(
    Model.logGoalChange([{ day: "2026-09-10", hours: 6 }], "2026-09-11", 0),
    [
      { day: "2026-09-10", hours: 6 },
      { day: "2026-09-11", hours: 0 },
    ],
  )
  assert.deepEqual(Model.logGoalChange([], "junk", 6), [])
  let log = []
  const months = ["2025", "2026"]
  for (const y of months) {
    for (let m = 1; m <= 12; m++) {
      for (let d = 1; d <= 28; d++) {
        const key =
          y +
          "-" +
          String(m).padStart(2, "0") +
          "-" +
          String(d).padStart(2, "0")
        log = Model.logGoalChange(log, key, 6)
      }
    }
  }
  assert.ok(log.length <= Model.GOAL_LOG_MAX)
  assert.equal(log[log.length - 1].day, "2026-12-28")
  assert.equal(log[0].day > "2025-01-01", true)
})
test("goal progress hides for days without an active goal", () => {
  const log = [
    { day: "2026-09-11", hours: 6 },
    { day: "2026-09-12", hours: 0 },
    { day: "2026-09-13", hours: 8 },
  ]
  // Huge past total, no goal then: nothing to reach.
  assert.equal(
    Model.goalProgress(12 * 3600000, Model.goalForDay(log, "2026-09-10")),
    null,
  )
  // On day: over goal reads reached.
  assert.equal(
    Model.goalProgress(7 * 3600000, Model.goalForDay(log, "2026-09-11"))
      .reached,
    true,
  )
  // Off day: silent again despite the earlier goal.
  assert.equal(
    Model.goalProgress(7 * 3600000, Model.goalForDay(log, "2026-09-12")),
    null,
  )
  // Re-activated with a different goal: judged against 8h, not 6h.
  const backOn = Model.goalProgress(
    7 * 3600000,
    Model.goalForDay(log, "2026-09-13"),
  )
  assert.equal(backOn.reached, false)
  assert.equal(backOn.remainingMs, 3600000)
})
test("weekdayNumber maps Monday to Sunday as 1 to 7", () => {
  assert.equal(Model.weekdayNumber("2026-08-17"), 1)
  assert.equal(Model.weekdayNumber("2026-08-18"), 2)
  assert.equal(Model.weekdayNumber("2026-08-19"), 3)
  assert.equal(Model.weekdayNumber("2026-08-20"), 4)
  assert.equal(Model.weekdayNumber("2026-08-21"), 5)
  assert.equal(Model.weekdayNumber("2026-08-22"), 6)
  assert.equal(Model.weekdayNumber("2026-08-23"), 7)
  assert.equal(Model.weekdayNumber("2026-02-29"), 0)
  assert.equal(Model.weekdayNumber("garbage"), 0)
  assert.equal(Model.weekdayNumber(""), 0)
  assert.equal(Model.weekdayNumber(null), 0)
})

test("appCategory sorts apps into the ten buckets plus Other", () => {
  const cases = [
    ["zen-bin", "Web Browsing"],
    ["google-chrome", "Web Browsing"],
    ["chromium-browser", "Web Browsing"],
    ["code", "Development"],
    ["opencode", "Development"],
    ["nvim", "Development"],
    ["docker", "Development"],
    ["obsidian", "Productivity"],
    ["libreoffice-writer", "Productivity"],
    ["discord", "Communication"],
    ["thunderbird", "Communication"],
    ["zoom", "Communication"],
    ["anki", "Education & Research"],
    ["evince", "Education & Research"],
    ["blender", "Creative"],
    ["krita", "Creative"],
    ["obs-studio", "Creative"],
    ["cawbird", "Social"],
    ["spotify", "Entertainment"],
    ["vlc", "Entertainment"],
    ["steam", "Gaming"],
    ["lutris", "Gaming"],
    ["nautilus", "System & Utilities"],
    ["foot", "System & Utilities"],
    ["bash", "System & Utilities"],
    ["htop", "System & Utilities"],
    ["mystery-app-xyz", "Other"],
    ["", "Other"],
    [null, "Other"],
  ]
  for (const [app, want] of cases)
    assert.equal(Model.appCategory(app), want, String(app))
})

test("categoryColor is stable per category", () => {
  const a = Model.categoryColor("Gaming", "#e45b93")
  assert.equal(a, Model.categoryColor("Gaming", "#e45b93"))
  assert.match(a, /^#[0-9a-f]{6}$/)
  assert.notEqual(a, Model.categoryColor("Development", "#e45b93"))
  assert.equal(Model.categoryColor("Nope", "#e45b93"), "#e45b93")
})

test("span validation accepts credited chunks only", () => {
  assert.equal(Model.isSpan({ app: "zen", start: 1, end: 2 }), true)
  assert.equal(Model.isSpan({ app: "zen", start: 2, end: 2 }), false)
  assert.equal(Model.isSpan({ app: "zen", start: 3, end: 2 }), false)
  assert.equal(Model.isSpan({ app: "", start: 1, end: 2 }), false)
  assert.equal(Model.isSpan({ app: "zen", start: NaN, end: 2 }), false)
  assert.equal(Model.isSpan(null), false)
  assert.equal(Model.isSpan("zen"), false)
})

test("sanitizeSpans keeps clean lists by identity and rebuilds the rest", () => {
  assert.deepEqual(Model.sanitizeSpans(undefined), {
    spans: undefined,
    changed: false,
  })
  const clean = [{ app: "zen", start: 1, end: 2 }]
  const kept = Model.sanitizeSpans(clean)
  assert.equal(kept.spans, clean)
  assert.equal(kept.changed, false)
  const dirty = Model.sanitizeSpans([
    { app: "zen", start: 1, end: 2 },
    { app: "zen", start: 5, end: 5 },
    { nope: 1 },
  ])
  assert.deepEqual(dirty.spans, [{ app: "zen", start: 1, end: 2 }])
  assert.equal(dirty.changed, true)
  assert.deepEqual(Model.sanitizeSpans("junk"), { spans: [], changed: true })
  const big = []
  for (let i = 0; i < Model.MAX_DAY_SPANS + 10; i++)
    big.push({ app: "zen", start: i * 2 + 1, end: i * 2 + 2 })
  const capped = Model.sanitizeSpans(big)
  assert.equal(capped.spans.length, Model.MAX_DAY_SPANS)
  assert.equal(capped.changed, true)
})

// Adapter sequences read by index but fail Array.isArray, which used to
// rebuild every recorded span list to [] on load. A list-like foreign
// object with length and indexed entries must normalize, never erase.
function foreignSpans(arr) {
  const o = { length: arr.length }
  for (let i = 0; i < arr.length; i++) o[i] = arr[i]
  return o
}

test("asSpanArray passes engine arrays through, copies foreign lists", () => {
  const real = [{ app: "zen", start: 1, end: 2 }]
  assert.equal(Model.asSpanArray(real), real)
  const foreign = foreignSpans(real)
  assert.equal(Array.isArray(foreign), false)
  const copied = Model.asSpanArray(foreign)
  assert.equal(Array.isArray(copied), true)
  assert.deepEqual(copied, real)
  assert.deepEqual(Model.asSpanArray(42), [])
  assert.deepEqual(Model.asSpanArray(undefined), [])
})

test("sanitizeSpans normalizes adapter sequences instead of erasing them", () => {
  const valid = [
    { app: "zen", start: 1000, end: 2000 },
    { app: "foot", start: 2000, end: 2600 },
  ]
  const fixed = Model.sanitizeSpans(foreignSpans(valid))
  assert.equal(Array.isArray(fixed.spans), true)
  assert.deepEqual(fixed.spans, valid)
  assert.equal(fixed.changed, true)
  // Genuine junk still drops: no list shape, no spans.
  assert.deepEqual(Model.sanitizeSpans(42), { spans: [], changed: true })
})

test("spanList and appendSpan read adapter sequences", () => {
  const day = {
    total: 3000,
    apps: { zen: 3000 },
    spans: foreignSpans([{ app: "zen", start: 1000, end: 2000 }]),
  }
  assert.deepEqual(Model.spanList(day), [
    { app: "zen", start: 1000, end: 2000 },
  ])
  const grown = Model.appendSpan(day, "zen", 3000, 4000)
  assert.equal(Array.isArray(grown.spans), true)
  assert.deepEqual(grown.spans, [
    { app: "zen", start: 1000, end: 2000 },
    { app: "zen", start: 3000, end: 4000 },
  ])
})

test("appendSpan coalesces exactly contiguous spans for the same app", () => {
  const day = {
    total: 0,
    apps: {},
    spans: [{ app: "zen", start: 1000, end: 2000 }],
  }
  const merged = Model.appendSpan(day, "zen", 2000, 3000)
  assert.notEqual(merged, day)
  assert.deepEqual(merged.spans, [{ app: "zen", start: 1000, end: 3000 }])
  assert.deepEqual(day.spans, [{ app: "zen", start: 1000, end: 2000 }])
})

test("appendSpan keeps non-contiguous and different-app spans separate", () => {
  const day = {
    total: 0,
    apps: {},
    spans: [{ app: "zen", start: 1000, end: 2000 }],
  }
  const gapped = Model.appendSpan(day, "zen", 2001, 3000)
  assert.equal(gapped.spans.length, 2)
  const differentApp = Model.appendSpan(day, "foot", 2000, 3000)
  assert.equal(differentApp.spans.length, 2)
})

test("appendSpan returns the input when there is nothing to record", () => {
  const day = { total: 0, apps: {} }
  assert.equal(Model.appendSpan(day, "zen", 2, 2), day)
  assert.equal(Model.appendSpan(day, "", 1, 2), day)
  assert.equal(Model.appendSpan(null, "zen", 1, 2), null)
  const full = { total: 1, apps: {}, spans: [] }
  for (let i = 0; i < Model.MAX_DAY_SPANS; i++)
    full.spans.push({ app: "zen", start: i * 2 + 1, end: i * 2 + 2 })
  assert.equal(Model.appendSpan(full, "zen", 1, 2), full)
  const continued = Model.appendSpan(
    full,
    "zen",
    full.spans[full.spans.length - 1].end,
    Model.MAX_DAY_SPANS * 2 + 2,
  )
  assert.equal(continued.spans.length, Model.MAX_DAY_SPANS)
  assert.equal(
    continued.spans[continued.spans.length - 1].end,
    Model.MAX_DAY_SPANS * 2 + 2,
  )
  assert.equal(full.spans[full.spans.length - 1].end, Model.MAX_DAY_SPANS * 2)
  const grown = Model.appendSpan(day, "zen", 1000, 2000)
  assert.notEqual(grown, day)
  assert.deepEqual(grown.spans, [{ app: "zen", start: 1000, end: 2000 }])
})

test("mergeSpans unions same-app overlaps without touching gaps", () => {
  // Write-time coalescing folds post-save growth into the tail span, so
  // the live list shares a prefix with the mirror at shifted positions.
  const united = Model.mergeSpans(
    [{ app: "zen", start: 1000, end: 61000 }],
    [{ app: "zen", start: 1000, end: 121000 }],
  )
  assert.deepEqual(united, [{ app: "zen", start: 1000, end: 121000 }])
  // Exact repeats dedupe: a repeated flush never double-counts.
  assert.deepEqual(
    Model.mergeSpans(united, [{ app: "zen", start: 1000, end: 121000 }]),
    united,
  )
  // Different apps never merge, even when adjacent; gaps stay visible.
  assert.deepEqual(
    Model.mergeSpans(
      [{ app: "zen", start: 1000, end: 2000 }],
      [{ app: "foot", start: 2000, end: 3000 }],
    ),
    [
      { app: "zen", start: 1000, end: 2000 },
      { app: "foot", start: 2000, end: 3000 },
    ],
  )
})

test("mergeSpans unions adapter sequences with engine arrays", () => {
  const united = Model.mergeSpans(
    foreignSpans([{ app: "zen", start: 1000, end: 2000 }]),
    [{ app: "zen", start: 1500, end: 3000 }],
  )
  assert.deepEqual(united, [{ app: "zen", start: 1000, end: 3000 }])
})

test("mergeSpans sorts, validates and tolerates junk", () => {
  assert.deepEqual(
    Model.mergeSpans(
      [{ app: "foot", start: 5000, end: 6000 }, { nope: 1 }],
      "junk",
    ),
    [{ app: "foot", start: 5000, end: 6000 }],
  )
  assert.deepEqual(Model.mergeSpans(undefined, undefined), [])
  assert.deepEqual(
    Model.mergeSpans(
      [{ app: "zen", start: 9000, end: 9500 }],
      [{ app: "zen", start: 1000, end: 2000 }],
    ),
    [
      { app: "zen", start: 1000, end: 2000 },
      { app: "zen", start: 9000, end: 9500 },
    ],
  )
})

test("splitSpan cuts at local midnights", () => {
  const t0 = new Date(2026, 8, 21, 23, 55, 0).getTime()
  const t1 = new Date(2026, 8, 22, 0, 5, 0).getTime()
  const parts = Model.splitSpan("zen", t0, t1)
  assert.equal(parts.length, 2)
  assert.equal(parts[0].key, "2026-09-21")
  assert.equal(parts[0].start, t0)
  assert.equal(parts[1].key, "2026-09-22")
  assert.equal(parts[1].end, t1)
  assert.equal(parts[0].end, parts[1].start)
  const single = Model.splitSpan("zen", t0, t0 + 60000)
  assert.equal(single.length, 1)
  assert.equal(single[0].key, "2026-09-21")
  assert.deepEqual(Model.splitSpan("zen", 5, 5), [])
  assert.deepEqual(Model.splitSpan("", 1, 2), [])
})

test("dayBounds resolves real days only", () => {
  const b = Model.dayBounds("2026-09-21")
  assert.equal(b.end - b.start, 86400000)
  assert.equal(new Date(b.start).getHours(), 0)
  assert.equal(Model.dayBounds("junk"), null)
  assert.equal(Model.dayBounds("2026-02-30"), null)
})

test("axisFracs thins ticks for short sessions", () => {
  assert.deepEqual(Model.axisFracs(3 * 3600000), [0, 0.25, 0.5, 0.75, 1])
  assert.deepEqual(Model.axisFracs(3600000), [0, 1 / 3, 2 / 3, 1])
  assert.deepEqual(Model.axisFracs(15 * 60000), [0, 0.5, 1])
  assert.deepEqual(Model.axisFracs(60000), [0, 1])
  assert.deepEqual(Model.axisFracs(0), [0, 1])
  assert.deepEqual(Model.axisFracs("junk"), [0, 1])
})

test("daySpanView sizes spans to the session, not midnight", () => {
  const t0 = new Date(2026, 8, 21, 7, 0, 0).getTime()
  const day = {
    total: 0,
    apps: {},
    spans: [
      { app: "zen", start: t0, end: t0 + 60000 },
      { app: "zen", start: t0 + 60000, end: t0 + 600000 },
      { app: "foot", start: t0 + 900000, end: t0 + 960000 },
    ],
  }
  const view = Model.daySpanView(day, "2026-09-21", "#e45b93")
  // Session runs 07:00–07:16: the opening span fills from the left edge.
  assert.equal(view.sessionStart, t0)
  assert.equal(view.sessionEnd, t0 + 960000)
  assert.equal(view.segments.length, 2)
  assert.equal(view.segments[0].app, "zen")
  assert.equal(view.segments[0].ms, 600000)
  assert.equal(view.segments[0].category, "Web Browsing")
  assert.equal(view.segments[0].startFrac, 0)
  assert.ok(Math.abs(view.segments[0].endFrac - 600 / 960) < 0.001)
  for (const s of view.segments) assert.match(s.color, /^#[0-9a-f]{6}$/)
  assert.equal(view.categories[0].category, "Web Browsing")
  assert.equal(view.categories[0].ms, 600000)
  assert.equal(view.axis[0].label, "07:00")
  assert.equal(view.axis[view.axis.length - 1].label, "07:16")
  // A ten-minute hop stays split; other apps never merge.
  const split = Model.daySpanView(
    {
      total: 0,
      apps: {},
      spans: [
        { app: "zen", start: t0, end: t0 + 60000 },
        { app: "zen", start: t0 + 660000, end: t0 + 720000 },
      ],
    },
    "2026-09-21",
    "#e45b93",
  )
  assert.equal(split.segments.length, 2)
  // Every span renders, down to 3s blips: the strip accounts for
  // exactly the recorded time instead of hiding blips and absorbing
  // gaps.
  const blips = Model.daySpanView(
    {
      total: 3000,
      apps: { zen: 3000 },
      spans: [{ app: "zen", start: t0, end: t0 + 3000 }],
    },
    "2026-09-21",
    "#e45b93",
  )
  assert.equal(blips.segments.length, 1)
  assert.equal(blips.segments[0].ms, 3000)
  assert.equal(blips.categories[0].ms, 3000)
  assert.deepEqual(Model.daySpanView(null, "2026-09-21", "#e45b93"), {
    segments: [],
    categories: [],
    axis: [],
    sessionStart: 0,
    sessionEnd: 0,
  })
  assert.deepEqual(
    Model.daySpanView({ total: 1, apps: {} }, "junk", "#e45b93").segments,
    [],
  )
})

test("daySpanView segments and categories sum to the recorded spans", () => {
  const t0 = new Date(2026, 8, 21, 7, 0, 0).getTime()
  const spans = [
    { app: "zen", start: t0, end: t0 + 3000 },
    { app: "zen", start: t0 + 60000, end: t0 + 120000 },
    { app: "foot", start: t0 + 120000, end: t0 + 125000 },
  ]
  const view = Model.daySpanView(
    { total: 68000, apps: { zen: 63000, foot: 5000 }, spans },
    "2026-09-21",
    "#e45b93",
  )
  // Blip, gapped session and adjacent other-app span: three bars, and
  // the untracked 57s gap between them renders as empty track.
  assert.equal(view.segments.length, 3)
  const segMs = view.segments.reduce((a, s) => a + s.ms, 0)
  assert.equal(segMs, 68000)
  const catMs = view.categories.reduce((a, c) => a + c.ms, 0)
  assert.equal(catMs, segMs)
})

test("fmtClock renders day times", () => {
  assert.equal(
    Model.fmtClock(new Date(2026, 8, 21, 7, 5, 0).getTime()),
    "07:05",
  )
  assert.equal(
    Model.fmtClock(new Date(2026, 8, 21, 0, 0, 0).getTime()),
    "00:00",
  )
  assert.equal(Model.fmtClock("junk"), "")
})

test("parseDayView prefers the explicit pick, then the retired toggle", () => {
  assert.equal(Model.parseDayView("timeline"), "timeline")
  assert.equal(Model.parseDayView("apps"), "apps")
  assert.equal(Model.parseDayView(undefined, false), "timeline")
  assert.equal(Model.parseDayView(undefined, "false"), "timeline")
  assert.equal(Model.parseDayView(undefined, true), "apps")
  assert.equal(Model.parseDayView(undefined, undefined), "apps")
  assert.equal(Model.parseDayView("junk", false), "timeline")
})

test("sanitizeDay validates spans without minting the key", () => {
  const bare = { total: 5, apps: { zen: 5 } }
  const kept = Model.sanitizeDay(bare)
  assert.equal(kept.day, bare)
  assert.equal(kept.changed, false)
  assert.ok(!("spans" in kept.day))
  const dirty = Model.sanitizeDay({
    total: 5,
    apps: { zen: 5 },
    spans: [{ app: "zen", start: 1, end: 2 }, { nope: 1 }],
  })
  assert.equal(dirty.changed, true)
  assert.deepEqual(dirty.day.spans, [{ app: "zen", start: 1, end: 2 }])
})

test("filterIgnoredDay strips ignored spans with the totals", () => {
  const day = {
    total: 3,
    apps: { zen: 2, foot: 1 },
    spans: [
      { app: "zen", start: 1, end: 3 },
      { app: "foot", start: 3, end: 4 },
    ],
  }
  const clean = Model.filterIgnoredDay(day, ["foot"])
  assert.deepEqual(clean.apps, { zen: 2 })
  assert.deepEqual(clean.spans, [{ app: "zen", start: 1, end: 3 }])
  assert.equal(Model.filterIgnoredDay(day, []), day)
})

test("refoldDay remaps span apps with the totals", () => {
  const day = {
    total: 2,
    apps: { zen: 2 },
    spans: [{ app: "zen", start: 1, end: 3 }],
  }
  const folded = Model.refoldDay(day, { zen: "browser" })
  assert.deepEqual(folded.apps, { browser: 2 })
  assert.deepEqual(folded.spans, [{ app: "browser", start: 1, end: 3 }])
  assert.equal(Model.refoldDay(day, {}), day)
})

test("heatLevel buckets rest days to zero and scales quartiles", () => {
  assert.equal(Model.heatLevel(0, 100), 0)
  assert.equal(Model.heatLevel(-5, 100), 0)
  assert.equal(Model.heatLevel(10, 0), 0)
  assert.equal(Model.heatLevel(1, 8), 1)
  assert.equal(Model.heatLevel(4, 8), 2)
  assert.equal(Model.heatLevel(6, 8), 3)
  assert.equal(Model.heatLevel(8, 8), 4)
  assert.equal(Model.heatLevel(99, 8), 4)
})

test("parseYearGraph defaults to bars", () => {
  assert.equal(Model.parseYearGraph("heatmap"), "heatmap")
  assert.equal(Model.parseYearGraph("bars"), "bars")
  assert.equal(Model.parseYearGraph(""), "bars")
  assert.equal(Model.parseYearGraph(undefined), "bars")
  assert.equal(Model.parseYearGraph(null), "bars")
})

test("yearHeatmap lays Monday-first weeks with pads and month labels", () => {
  // Jan 1 2026 is a Thursday: the first column pads Mon–Wed with nulls.
  const heat = Model.yearHeatmap(
    [
      { date: "2026-01-01", ms: 3600000 },
      { date: "2026-09-21", ms: 7200000 },
    ],
    2026,
  )
  assert.equal(heat.weeks.length, 53)
  assert.equal(heat.maxMs, 7200000)
  const first = heat.weeks[0]
  assert.equal(first.label, "Jan")
  assert.deepEqual(
    first.days.map((d) => (d ? d.date : null)),
    [null, null, null, "2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04"],
  )
  assert.equal(first.days[3].level, 2)
  const labels = heat.weeks.map((w) => w.label).filter((l) => l !== "")
  assert.deepEqual(labels, [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ])
  // Every column holds exactly seven slots.
  for (const w of heat.weeks) assert.equal(w.days.length, 7)
})

test("yearHeatmap tolerates empty and malformed input", () => {
  const empty = Model.yearHeatmap([], 2026)
  assert.equal(empty.weeks.length, 53)
  assert.equal(empty.maxMs, 0)
  assert.equal(empty.weeks[0].days[3].level, 0)
  assert.deepEqual(Model.yearHeatmap(null, 2026).weeks.length, 53)
  assert.deepEqual(Model.yearHeatmap([], "junk"), { weeks: [], maxMs: 0 })
  assert.deepEqual(Model.yearHeatmap([], 1999), { weeks: [], maxMs: 0 })
})

test("yearView shares day totals with the heatmap", () => {
  const days = { "2026-09-21": { total: 3600000, apps: { zen: 3600000 } } }
  const view = Model.yearView(days, {}, {}, 2026, "2026-09-21", "#e45b93")
  assert.deepEqual(view.days, [{ date: "2026-09-21", ms: 3600000 }])
})

test("yearHeatmap flags future days, weeks and month labels", () => {
  const heat = Model.yearHeatmap(
    [{ date: "2026-09-21", ms: 3600000 }],
    2026,
    "2026-09-21",
  )
  function find(date) {
    for (const w of heat.weeks)
      for (const d of w.days)
        if (d && d.date === date) return { day: d, week: w }
    return {}
  }
  assert.equal(find("2026-09-21").day.future, false)
  assert.equal(find("2026-09-21").day.level, 4)
  assert.equal(find("2026-09-22").day.future, true)
  assert.equal(find("2026-09-22").day.level, 0)
  assert.equal(find("2026-09-22").week.future, false)
  assert.equal(find("2026-01-05").week.future, false)
  const labels = {}
  for (const w of heat.weeks) if (w.label) labels[w.label] = w
  assert.equal(labels["Sep"].labelFuture, false)
  assert.equal(labels["Oct"].labelFuture, true)
  assert.equal(labels["Oct"].future, true)
  // Without a today key nothing is future, keeping old callers exact.
  const timeless = Model.yearHeatmap([{ date: "2026-09-21", ms: 1 }], 2026)
  assert.equal(timeless.weeks[40].days[0].future, false)
})

test("parseHeatmapPos restores only its own year", () => {
  assert.equal(Model.parseHeatmapPos("2026:38", 2026), 38)
  assert.equal(Model.parseHeatmapPos("2026:0", 2026), 0)
  assert.equal(Model.parseHeatmapPos("2025:38", 2026), -1)
  assert.equal(Model.parseHeatmapPos("2026:99", 2026), -1)
  assert.equal(Model.parseHeatmapPos("junk", 2026), -1)
  assert.equal(Model.parseHeatmapPos(undefined, 2026), -1)
  assert.equal(Model.parseHeatmapPos(null, 2026), -1)
})

test("normalizeTitle strips browser suffixes and notification noise", () => {
  assert.equal(Model.normalizeTitle("WhatsApp - Google Chrome"), "WhatsApp")
  assert.equal(Model.normalizeTitle("Inbox — Mozilla Firefox"), "Inbox")
  assert.equal(Model.normalizeTitle("(56) WhatsApp - Brave"), "WhatsApp")
  assert.equal(Model.normalizeTitle("Docs - Zen Browser"), "Docs")
  assert.equal(Model.normalizeTitle(""), "")
  assert.equal(Model.normalizeTitle(null), "")
})

test("siteForTitle matches clean rules first-win, else empty", () => {
  assert.equal(Model.siteForTitle("Facebook - Zen Browser"), "facebook.com")
  assert.equal(
    Model.siteForTitle("Quarterly Report - Google Docs - Google Chrome"),
    "docs.google.com",
  )
  assert.equal(Model.siteForTitle("Some random blog post - Firefox"), "")
  assert.equal(Model.siteForTitle("", []), "")
  assert.equal(
    Model.siteForTitle("GitHub - Chromium", [{ match: "hub", site: "x" }]),
    "x",
  )
  assert.equal(Model.siteKey("x.com"), "site:x.com")
  assert.equal(Model.siteKey(""), "")
  assert.equal(Model.isSiteKey("site:x.com"), true)
  assert.equal(Model.isSiteKey("zen"), false)
  assert.equal(Model.isBrowserApp("zen-bin"), true)
  assert.equal(Model.isBrowserApp("code"), false)
})

test("default site rules ship no adult entries", () => {
  const rules = JSON.stringify(Model.defaultSiteRules())
  assert.doesNotMatch(rules, /\b(xvideos|xnxx|pornhub|xhamster|onlyfans)\b/i)
  assert.ok(Model.defaultSiteRules().length > 20)
})

test("site buckets categorize by domain, unknown sites stay browsing", () => {
  const cases = [
    ["site:facebook.com", "Social"],
    ["site:x.com", "Social"],
    ["site:youtube.com", "Entertainment"],
    ["site:twitch.tv", "Entertainment"],
    ["site:github.com", "Development"],
    ["site:stackoverflow.com", "Development"],
    ["site:gmail.com", "Communication"],
    ["site:whatsapp.com", "Communication"],
    ["site:docs.google.com", "Productivity"],
    ["site:notion.so", "Productivity"],
    ["site:chatgpt.com", "Productivity"],
    ["site:wikipedia.org", "Education & Research"],
    ["site:figma.com", "Creative"],
    ["site:random-blog-xyz.com", "Web Browsing"],
  ]
  for (const [app, want] of cases)
    assert.equal(Model.appCategory(app), want, app)
  assert.equal(Model.displayName("site:facebook.com"), "facebook.com")
})

test("ignore entries catch site buckets by domain", () => {
  assert.equal(Model.isIgnoredApp("site:facebook.com", ["facebook"]), true)
  assert.equal(Model.isIgnoredApp("site:facebook.com", ["facebook.com"]), true)
  assert.equal(Model.isIgnoredApp("site:facebook.com", ["com"]), false)
  assert.equal(Model.isIgnoredApp("site:facebook.com", ["chrome"]), false)
  assert.equal(Model.isIgnoredApp("zen-bin", ["zen"]), true)
})
