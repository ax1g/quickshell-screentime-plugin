"use strict"

const { test } = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../lib/Model.js")

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
    "chrome-music.apple.com"
  )
})

test("canonicalApp normalizes Chromium-family web app keys", () => {
  assert.equal(
    Model.canonicalApp("chromium-calendar.google.com__-Profile_1"),
    "chromium-calendar.google.com"
  )
  assert.equal(
    Model.canonicalApp("brave-calendar.google.com__-Default"),
    "brave-calendar.google.com"
  )
  assert.equal(
    Model.canonicalApp("msedge-calendar.google.com__-Default"),
    "msedge-calendar.google.com"
  )
  assert.equal(
    Model.canonicalApp("vivaldi-calendar.google.com__-Default"),
    "vivaldi-calendar.google.com"
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
    "music.apple.com"
  )
  assert.equal(
    Model.displayName("chrome-calendar.google.com__-Profile_1"),
    "calendar.google.com"
  )
  assert.equal(Model.displayName("chromium-chatgpt.com__-Default"), "chatgpt.com")
  assert.equal(Model.displayName("brave-chatgpt.com__-Default"), "chatgpt.com")
  assert.equal(Model.displayName("msedge-chatgpt.com__-Default"), "chatgpt.com")
  assert.equal(
    Model.displayName("vivaldi-chatgpt.com__-Default"),
    "chatgpt.com"
  )
  assert.equal(Model.displayName("chrome-chatgpt.com"), "chatgpt.com")
})

test("displayName keeps dotted non-reverse-DNS names intact", () => {
  assert.equal(Model.displayName("Minecraft* 26.2"), "minecraft* 26.2")
  assert.equal(Model.displayName("editor-1.2"), "editor-1.2")
})

test("displayName passes unresolved Steam ids through untouched", () => {
  // Game titles are resolved by scripts/resolve_app.py before storage;
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
  assert.deepEqual(labels, ["Top app", "vs Yesterday", "Busiest day (7d)"])
  assert.ok(rows[0].value.includes("browser"))
  assert.ok(rows[1].value.includes("-"))
})

test("insights renders the top app with its refined display name", () => {
  const today = {
    total: 3600000,
    apps: { "com.omarchy.agent": 3600000 }
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
    "2026-08-14": { total: 80000 }
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

test("busiestWeekDay returns zero total when all days are empty", () => {
  const days = {
    "2026-08-13": { total: 0 },
    "2026-08-14": { total: 0 },
    "2026-08-15": { total: 0 }
  }
  const best = Model.busiestWeekDay(days, "2026-08-15")
  assert.equal(best.total, 0)
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
  assert.ok(Math.abs(lastEnd - 268.5) < 0.001)
  assert.ok(segs[0].sweepAngle < 180, "gap removed from first slice")
})

test("arcSegments gives a single app the full circle", () => {
  const segs = Model.arcSegments([{ app: "a", ms: 60000, pct: 100 }])
  assert.equal(segs.length, 1)
  assert.equal(segs[0].sweepAngle, 360)
})

test("browser_aliases.json is the single source of truth for canonicalApp", () => {
  const aliases = require("../lib/browser_aliases.json")
  assert.equal(typeof aliases, "object")
  assert.ok(Object.keys(aliases).length > 0)
  for (const [key, target] of Object.entries(aliases)) {
    assert.equal(Model.canonicalApp(key), target,
      `canonicalApp("${key}") should return "${target}" from browser_aliases.json`)
  }
})

test("QML inline browser aliases match browser_aliases.json", () => {
  // QML cannot read the JSON file synchronously (Quickshell's XHR blocks
  // local files), so Model.js mirrors the data as a literal. Fail loudly
  // if the mirror drifts from the canonical file — a silent divergence
  // would fold browsers differently under QML vs Node.
  const fs = require("fs")
  const file = JSON.parse(
    fs.readFileSync(require.resolve("../lib/browser_aliases.json"), "utf8"))
  const qml = Model.qmlBrowserAliases()
  assert.deepEqual(qml, file)
  assert.ok(Object.keys(qml).length > 0)
})

// ---- Data safety: pruneDays -----------------------------------------------

test("pruneDays never removes todayKey", () => {
  const days = {}
  for (let i = 0; i < 40; i++) {
    const d = new Date(2026, 7, 15 - i)
    days[Model.dayKey(d)] = { total: i * 1000, apps: {} }
  }
  const out = Model.pruneDays(days, "2026-08-15", 7)
  assert.ok(out["2026-08-15"], "today must survive pruning")
})

test("pruneDays never removes days within the retention window", () => {
  const days = {
    "2026-08-09": { total: 100 },
    "2026-08-10": { total: 200 },
    "2026-08-11": { total: 300 },
    "2026-08-12": { total: 400 },
    "2026-08-13": { total: 500 },
    "2026-08-14": { total: 600 },
    "2026-08-15": { total: 700 }
  }
  const out = Model.pruneDays(days, "2026-08-15", 7)
  // All 7 days should survive
  assert.equal(Object.keys(out).length, 7)
})

test("pruneDays with keepDays of 1 keeps only today", () => {
  const days = {
    "2026-08-14": { total: 100 },
    "2026-08-15": { total: 200 }
  }
  const out = Model.pruneDays(days, "2026-08-15", 1)
  assert.deepEqual(Object.keys(out), ["2026-08-15"])
})

test("pruneDays with keepDays of 0 returns original (no-op)", () => {
  const days = { "2026-08-15": { total: 100 } }
  const out = Model.pruneDays(days, "2026-08-15", 0)
  assert.equal(out, days)
})

test("pruneDays with negative keepDays returns original (no-op)", () => {
  const days = { "2026-08-15": { total: 100 } }
  const out = Model.pruneDays(days, "2026-08-15", -5)
  assert.equal(out, days)
})

test("pruneDays with null days returns original", () => {
  assert.equal(Model.pruneDays(null, "2026-08-15", 7), null)
})

test("pruneDays across year boundary keeps correct window", () => {
  const days = {
    "2025-12-30": { total: 100 },
    "2025-12-31": { total: 200 },
    "2026-01-01": { total: 300 },
    "2026-01-02": { total: 400 }
  }
  const out = Model.pruneDays(days, "2026-01-02", 3)
  assert.ok(out["2026-01-02"])
  assert.ok(out["2026-01-01"])
  assert.ok(out["2025-12-31"])
  assert.equal(out["2025-12-30"], undefined)
})

// ---- Data safety: corrupt / missing input ----------------------------------

test("firstDataYear reaches back through the month aggregates and year archive", () => {
  assert.equal(Model.firstDataYear({ "2026-01-01": {} }, {}, { 2024: { x: 1 } }), 2024)
  assert.equal(Model.firstDataYear({}, { "2025-06": 1 }, { 2024: { x: 1 } }), 2024)
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
    apps: { a: -5000, b: NaN, c: 120000 }
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
  const day = 86400000 * 365  // one year in ms
  assert.ok(Model.fmt(day).includes("h"))
  assert.ok(Model.fmtWords(day).includes("HOURS"))
})

test("dayFor with null days and empty today returns null", () => {
  assert.equal(Model.dayFor(null, null, "2026-08-15", "2026-08-15"), null)
})

test("dayKey produces consistent keys across Date object reuse", () => {
  const d = new Date(2026, 0, 1)
  const k1 = Model.dayKey(d)
  const k2 = Model.dayKey(d)
  assert.equal(k1, k2)
  assert.equal(k1, "2026-01-01")
})


// ---- weekStartMonday -----------------------------------------------------

test("weekStartMonday returns Monday for mid-week date", () => {
  // 2026-08-19 is Wednesday; Monday is 2026-08-17
  assert.equal(Model.weekStartMonday("2026-08-19"), "2026-08-17")
})

test("weekStartMonday returns same day when already Monday", () => {
  assert.equal(Model.weekStartMonday("2026-08-17"), "2026-08-17")
})

test("weekStartMonday wraps to previous week on Sunday", () => {
  // 2026-08-16 is Sunday; Monday is 2026-08-10
  assert.equal(Model.weekStartMonday("2026-08-16"), "2026-08-10")
})

test("weekStartMonday returns empty for bad input", () => {
  assert.equal(Model.weekStartMonday(""), "")
  assert.equal(Model.weekStartMonday(null), "")
})

// ---- isoWeekNumber --------------------------------------------------------

test("isoWeekNumber returns ISO week for a Monday", () => {
  assert.equal(Model.isoWeekNumber("2026-08-17"), 34)
})

test("isoWeekNumber is consistent across the week", () => {
  assert.equal(Model.isoWeekNumber("2026-08-21"), 34)
})

test("isoWeekNumber handles year start", () => {
  assert.equal(Model.isoWeekNumber("2026-01-01"), 1)
  assert.equal(Model.isoWeekNumber("2025-12-29"), 1)
})

test("isoWeekNumber handles 53-week years", () => {
  assert.equal(Model.isoWeekNumber("2026-12-28"), 53)
  assert.equal(Model.isoWeekNumber("2027-01-03"), 53)
})

test("isoWeekNumber handles leap-year week boundary", () => {
  assert.equal(Model.isoWeekNumber("2024-12-30"), 1)
})

test("isoWeekNumber returns 0 for bad input", () => {
  assert.equal(Model.isoWeekNumber(""), 0)
  assert.equal(Model.isoWeekNumber("garbage"), 0)
})

// ---- msUntilNextHour -------------------------------------------------------

test("msUntilNextHour returns full hour at exact boundary", () => {
  assert.equal(Model.msUntilNextHour(new Date(2026, 7, 21, 10, 0, 0, 0).getTime()), 3600000)
})

test("msUntilNextHour counts down to the next hour", () => {
  assert.equal(Model.msUntilNextHour(new Date(2026, 7, 21, 10, 59, 30, 500).getTime()), 29500)
})

test("msUntilNextHour includes milliseconds", () => {
  assert.equal(Model.msUntilNextHour(new Date(2026, 7, 21, 10, 0, 0, 250).getTime()), 3599750)
})

test("msUntilNextHour falls back to one minute for bad input", () => {
  assert.equal(Model.msUntilNextHour(NaN), 60000)
})

// ---- monSunWeeks ---------------------------------------------------------

const sampleDays = {
  "2026-08-17": { total: 3600000 },
  "2026-08-18": { total: 7200000 },
  "2026-08-19": { total: 1800000 }
}

test("monSunWeeks returns correct week count", () => {
  const weeks = Model.monSunWeeks(sampleDays, "2026-08-19", 2)
  assert.equal(weeks.length, 2)
})

test("monSunWeeks first week has 7 day entries", () => {
  const weeks = Model.monSunWeeks(sampleDays, "2026-08-19", 1)
  assert.equal(weeks[0].days.length, 7)
})

test("monSunWeeks weeks start on Monday", () => {
  const weeks = Model.monSunWeeks(sampleDays, "2026-08-19", 1)
  // 2026-08-17 is Monday
  assert.equal(weeks[0].days[0].key, "2026-08-17")
  assert.equal(weeks[0].days[0].label, "Mon")
})

test("monSunWeeks weeks end on Sunday", () => {
  const weeks = Model.monSunWeeks(sampleDays, "2026-08-19", 1)
  assert.equal(weeks[0].days[6].key, "2026-08-23")
  assert.equal(weeks[0].days[6].label, "Sun")
})

test("monSunWeeks marks today correctly", () => {
  const weeks = Model.monSunWeeks(sampleDays, "2026-08-19", 1)
  const today = weeks[0].days.find(d => d.isToday)
  assert.ok(today)
  assert.equal(today.key, "2026-08-19")
})

test("monSunWeeks marks future days in current week", () => {
  const weeks = Model.monSunWeeks(sampleDays, "2026-08-19", 1)
  // Thu Aug 20 - Sun Aug 23 are future
  for (let i = 3; i < 7; i++) {
    assert.ok(weeks[0].days[i].isFuture, `Day index ${i} should be future`)
  }
})

test("monSunWeeks returns empty for bad input", () => {
  assert.deepEqual(Model.monSunWeeks({}, "", 3), [])
  assert.deepEqual(Model.monSunWeeks({}, "2026-08-19", 0), [])
})

test("monSunWeeks week labels show dominant month", () => {
  // Week starting Aug 31 - Sep 6: Mon Aug 31, Tue Sep 1...
  // 4 days in Sep, 3 in Aug → month should be "Sep"
  const weeks = Model.monSunWeeks(sampleDays, "2026-09-02", 1)
  assert.equal(weeks[0].month, "Sep")
})

test("monSunWeeks populates ms from days data", () => {
  const weeks = Model.monSunWeeks(sampleDays, "2026-08-19", 1)
  const mon = weeks[0].days.find(d => d.key === "2026-08-17")
  assert.equal(mon.ms, 3600000)
})

// ---- scrollableTrendMax --------------------------------------------------

test("scrollableTrendMax returns max ms across all weeks", () => {
  const weeks = [
    { month: "Aug", days: [
      { ms: 100 }, { ms: 500 }, { ms: 200 }, { ms: 0 },
      { ms: 0 }, { ms: 0 }, { ms: 0 }
    ]},
    { month: "Aug", days: [
      { ms: 300 }, { ms: 50 }, { ms: 0 }, { ms: 0 },
      { ms: 0 }, { ms: 0 }, { ms: 0 }
    ]}
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
  assert.deepEqual(Model.weekAxisTicks(2 * HOUR_MS), [0, 2 * HOUR_MS, 4 * HOUR_MS])
  assert.deepEqual(Model.weekAxisTicks(4 * HOUR_MS), [0, 2 * HOUR_MS, 4 * HOUR_MS])
})

test("weekAxisTicks scales with the week's real maximum", () => {
  assert.deepEqual(Model.weekAxisTicks(5 * HOUR_MS), [0, 2.5 * HOUR_MS, 5 * HOUR_MS])
  assert.deepEqual(Model.weekAxisTicks(9 * HOUR_MS), [0, 4.5 * HOUR_MS, 9 * HOUR_MS])
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
    "2026-08-17": { total: 0 }
  }
  const totals = Model.monthlyTotals(days, {}, 2026)
  const aug = totals.find(t => t.month === 7)
  assert.equal(aug.ms, 5400000)
})

test("monthlyTotals uses months aggregates for historical data", () => {
  const months = { "2026-03": 10000000 }
  const totals = Model.monthlyTotals({}, months, 2026)
  const mar = totals.find(t => t.month === 2)
  assert.equal(mar.ms, 10000000)
  assert.ok(mar.hours.includes("h"))
})

test("monthlyTotals merges days and months without double counting", () => {
  // months has March data, days has April data — no overlap
  const days = { "2026-04-10": { total: 5000000 } }
  const months = { "2026-03": 3000000 }
  const totals = Model.monthlyTotals(days, months, 2026)
  const mar = totals.find(t => t.month === 2)
  const apr = totals.find(t => t.month === 3)
  assert.equal(mar.ms, 3000000)
  assert.equal(apr.ms, 5000000)
})

test("monthlyTotals returns 0h for months with no data", () => {
  const totals = Model.monthlyTotals({}, {}, 2026)
  const jan = totals.find(t => t.month === 0)
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
    "2025-12-31": { total: 9999999 }
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
  return { 2026: {
    "2026-01-02": 2 * h,
    "2026-01-03": h,
    "2026-02-01": 3 * h,
    "2026-02-02": 3 * h,
    "2026-02-03": 3 * h,
    "2026-03-02": 8 * h,
    "2026-03-03": 8 * h,
    "2026-03-04": 5 * h,
    "2026-03-09": 11 * h
  } }
}

test("yearFacts returns empty when the year has no data", () => {
  assert.deepEqual(Model.yearFacts({}, {}, {}, 2026, "2026-12-24"), [])
})

test("sanitizeHistory validates the years archive", () => {
  assert.deepEqual(
    Model.sanitizeHistory({}, {}, { 2026: { "2026-01-02": HOUR_MS } }).years,
    { 2026: { "2026-01-02": HOUR_MS } })
  assert.deepEqual(
    Model.sanitizeHistory({}, {}, { 2026: { "2026-01-02": "x", "2026-01-03": 0 } }).years,
    { 2026: { "2026-01-03": 0 } })
  assert.deepEqual(Model.sanitizeHistory({}, {}, { 2026: "nope" }).years, {})
})

test("rollupArchive keeps only per-day totals, never app maps", () => {
  const pruned = {
    "2026-08-01": { total: HOUR_MS, apps: { web: HOUR_MS } },
    "2026-08-02": { total: 0, apps: { done: 1 } },
    "2025-12-31": { total: 2 * HOUR_MS, apps: {} }
  }
  const base = { 2026: { "2026-08-03": 1000 } }
  const out = Model.rollupArchive(base, pruned)
  assert.deepEqual(out, {
    2026: { "2026-08-03": 1000, "2026-08-01": HOUR_MS },
    2025: { "2025-12-31": 2 * HOUR_MS }
  })
  assert.deepEqual(base, { 2026: { "2026-08-03": 1000 } })
})

test("pruneArchive keeps the current and previous calendar year", () => {
  const years = { 2024: { a: 1 }, 2025: { b: 2 }, 2026: { c: 3 } }
  assert.deepEqual(Model.pruneArchive(years, 2026), { 2025: { b: 2 }, 2026: { c: 3 } })
  assert.deepEqual(Model.pruneArchive({}, 2026), {})
})

test("yearDayTotals unions archive and live days, capped at todayKey", () => {
  const years = { 2026: { "2026-01-02": 2 * HOUR_MS, "2026-12-25": HOUR_MS } }
  const days = {
    "2026-01-03": { total: HOUR_MS, apps: {} },
    "2026-01-05": { total: 0, apps: {} }
  }
  assert.deepEqual(Model.yearDayTotals(years, days, 2026, "2026-12-24"), [
    { date: "2026-01-02", ms: 2 * HOUR_MS },
    { date: "2026-01-03", ms: HOUR_MS }
  ])
})

test("yearDayTotals walks whole years without fabricating days", () => {
  assert.deepEqual(Model.yearDayTotals({ 2028: {} }, {}, 2028, "2028-12-31"), [])
  assert.deepEqual(Model.yearDayTotals({ 2026: { "2026-02-29": HOUR_MS } }, {}, 2026, "2026-12-31"), [])
})

test("activeDayCount only counts days at or above the minute floor", () => {
  const days = [
    { date: "2026-01-01", ms: 59 * 1000 },
    { date: "2026-01-02", ms: 60 * 1000 },
    { date: "2026-01-03", ms: HOUR_MS }
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
    { date: "2026-02-11", ms: h }
  ])
  assert.equal(s.longest, 3)
  assert.equal(s.longestEnd, "2026-02-02")
  assert.equal(s.current, 2)
  assert.equal(s.lastActive, "2026-02-11")
})

test("streakStats handles empty and single-day inputs", () => {
  assert.deepEqual(Model.streakStats([]), {
    longest: 0, longestEnd: "", lastActive: "", current: 0
  })
  const s = Model.streakStats([{ date: "2026-03-09", ms: HOUR_MS }])
  assert.equal(s.longest, 1)
  assert.equal(s.current, 1)
  assert.equal(s.lastActive, "2026-03-09")
})

test("yearFacts day cards scale from day-granular data, not month lumps", () => {
  // A month lump (from before the archive existed) has no per-day detail, so
  // it must count into the year share but never inflate "per active day" or
  // the weekday rhythm, which are computed over real days only.
  const months = { "2026-02": 10 * HOUR_MS }
  const cards = Model.yearFacts({}, months, archiveFixture(), 2026, "2026-12-24")
  const find = label => cards.find(c => c.label === label)
  assert.match(find("SCREEN SHARE").value, /54h on screens/)
  assert.equal(find("DAY COUNT").value, "Active on 9 of 357 tracked days")
  assert.match(find("AVERAGE SCREEN DAY").value, /4h 53m per active day/)
  assert.match(find("WEEKDAY RHYTHM").value, /Mon leads · 91% weekdays/)
})

test("yearFacts builds the wrapped summary for a full archived year", () => {
  const cards = Model.yearFacts({}, {}, archiveFixture(), 2026, "2026-12-24")
  const find = label => cards.find(c => c.label === label)
  assert.match(find("SCREEN SHARE").value, /44h on screens · 0\.5% of 2026/)
  assert.match(find("DAY COUNT").value, /Active on 9 of 357 tracked days/)
  assert.match(find("LONGEST STREAK").value, /3 days in a row/)
  assert.match(find("LONGEST STREAK").sub, /Feb/)
  assert.match(find("TOP MONTHS").value, /1\. Mar · 2\. Feb · 3\. Jan/)
  assert.match(find("AVERAGE SCREEN DAY").value, /4h 53m per active day/)
  assert.match(find("WEEKDAY RHYTHM").value, /Mon leads · 91% weekdays/)
  assert.match(find("PEAK DAY").value, /Mar 9 · 11h, the year's high/)
  assert.match(find("RECHARGE MONTH").value, /Jan · 3h, the screen's break/)
  assert.equal(cards.length, 8)
  for (const c of cards)
    assert.ok(c.glyph && c.label && c.value && c.sub && c.color)
})

test("yearFacts degrades to month-scale cards when no day archive exists", () => {
  const months = { "2026-03": 10 * HOUR_MS, "2026-01": 2 * HOUR_MS }
  const cards = Model.yearFacts({}, months, {}, 2026, "2026-12-24")
  const labels = cards.map(c => c.label)
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
    "2026-08-31": { total: 2 * HOUR_MS, apps: { code: 2 * HOUR_MS } }
  }
  const cards = Model.yearFacts(days, {}, {}, 2026, "2026-08-31")
  const text = cards.map(c => (c.label + c.value + c.sub).toLowerCase()).join(" ")
  assert.ok(!/zen|code|opencode|firefox|editor/i.test(text))
})

// ---- rollupPrunedDays ----------------------------------------------------

test("rollupPrunedDays merges day totals into months", () => {
  const pruned = {
    "2026-06-01": { total: 3600000 },
    "2026-06-15": { total: 7200000 }
  }
  const result = Model.rollupPrunedDays({}, pruned)
  assert.equal(result["2026-06"], 10800000)
})

test("rollupPrunedDays accumulates onto existing months", () => {
  const months = { "2026-06": 5000000 }
  const pruned = { "2026-06-20": { total: 3000000 } }
  const result = Model.rollupPrunedDays(months, pruned)
  assert.equal(result["2026-06"], 8000000)
})

test("rollupPrunedDays returns original months when nothing to prune", () => {
  const months = { "2026-05": 1000000 }
  const result = Model.rollupPrunedDays(months, {})
  assert.deepEqual(result, { "2026-05": 1000000 })
})

test("rollupPrunedDays skips days with zero total", () => {
  const pruned = { "2026-07-01": { total: 0 } }
  const result = Model.rollupPrunedDays({}, pruned)
  assert.deepEqual(result, {})
})

test("rollupPrunedDays handles null months input", () => {
  const pruned = { "2026-04-05": { total: 1000000 } }
  const result = Model.rollupPrunedDays(null, pruned)
  assert.equal(result["2026-04"], 1000000)
})
