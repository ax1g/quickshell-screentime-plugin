// Pure JS helpers for the screen-time plugin: day keys, time formatting,
// per-app aggregation, and the small set of usage heuristics shown as
// insights. No Qt imports here so the functions stay testable in isolation.

function pad2(n) {
  n = Math.floor(n)
  return n < 10 ? "0" + n : String(n)
}

// Fold browser binaries and worker comms into one canonical app key.
// QML mirrors js/browser_aliases.json as a literal (no sync file reads);
// a test asserts the mirror matches, so update both together.
var BROWSER_ALIASES = (function () {
  if (typeof module !== "undefined" && module && module.exports)
    return require("./browser_aliases.json")
  return qmlBrowserAliases()
})()

// QML mirror of js/browser_aliases.json. Keep in sync with that file;
// tests/model.test.js fails if this lags a change.
function qmlBrowserAliases() {
  return {
    "zen-bin": "zen",
    zen_browser: "zen",
    zen: "zen",
    firefox: "firefox",
    librewolf: "librewolf",
    waterfox: "waterfox",
    "tor-browser": "tor-browser",
    "mullvad-browser": "mullvad-browser",
    "google-chrome": "google-chrome",
    chrome: "google-chrome",
    chromium: "chromium",
    brave: "brave",
    "brave-browser": "brave",
    vivaldi: "vivaldi",
    "microsoft-edge": "microsoft-edge",
    edge: "microsoft-edge",
  }
}

var CHROMIUM_WEB_APP_RE =
  /^((?:chrome|chromium|brave|msedge|vivaldi)-([a-z0-9](?:[a-z0-9.-]*[a-z0-9])?))(__.*-(?:Default|Profile_[0-9]+))?$/i

// Map any app name to its canonical tracking key. Unknown names pass
// through unchanged so non-browser apps keep their own identity.
function canonicalApp(name) {
  if (!name) return ""
  var key = String(name)
  if (
    BROWSER_ALIASES &&
    Object.prototype.hasOwnProperty.call(BROWSER_ALIASES, key)
  )
    return BROWSER_ALIASES[key]
  var webApp = key.match(CHROMIUM_WEB_APP_RE)
  if (webApp && webApp[3]) return webApp[1]
  return key
}

// Display label: Chromium windows fold to hostname, reverse-DNS IDs to the
// last segment, binaries pass through. Steam classes arrive pre-resolved
// by python/resolve_app.py. Never touches the filesystem.
function displayName(app) {
  if (!app) return ""
  var s = String(app)

  var webApp = s.match(CHROMIUM_WEB_APP_RE)
  if (webApp) return webApp[2].toLowerCase()

  if (!/^(?:[a-z][a-z0-9-]*\.){2,}[a-z0-9_-]+$/i.test(s)) return s.toLowerCase()
  var last = s.split(".").pop()
  if (!last) return s.toLowerCase()
  return last.charAt(0).toLowerCase() + last.slice(1).toLowerCase()
}

// User tracking prefs: ignored apps and custom aliases. Both accept the
// raw pref shapes (array or comma string; object or "from=to" string) so
// QML can store plain strings in shell.json and normalize on read.
function parseIgnoredApps(value) {
  var raw = []
  if (Array.isArray(value)) raw = value
  else if (typeof value === "string") raw = value.split(",")
  var list = []
  for (var i = 0; i < raw.length; i++) {
    var app = String(raw[i] || "")
      .trim()
      .toLowerCase()
    if (app && list.indexOf(app) === -1) list.push(app)
  }
  return list
}

// True when name matches the ignore list as raw, canonical or display
// name, so "zen-bin" is caught by an entry for "zen" and vice versa.
function isIgnoredApp(name, ignoredList) {
  if (!name || !ignoredList || ignoredList.length === 0) return false
  var candidates = [
    String(name).trim().toLowerCase(),
    String(canonicalApp(name)).toLowerCase(),
    String(displayName(name)).toLowerCase(),
  ]
  for (var i = 0; i < candidates.length; i++) {
    if (candidates[i] && ignoredList.indexOf(candidates[i]) !== -1) return true
  }
  return false
}

function parseAppAliases(value) {
  var out = {}
  function put(k, v) {
    var key = String(k === undefined || k === null ? "" : k)
      .trim()
      .toLowerCase()
    var val = String(v === undefined || v === null ? "" : v).trim()
    // Never mint "__proto__": assigning it mutates the prototype
    // instead of storing an entry.
    if (!key || !val || key === "__proto__") return
    out[key] = val
  }
  if (value && typeof value === "object" && !Array.isArray(value)) {
    for (var k in value) {
      if (Object.prototype.hasOwnProperty.call(value, k)) put(k, value[k])
    }
    return out
  }
  if (typeof value === "string") {
    var pairs = value.split(",")
    for (var i = 0; i < pairs.length; i++) {
      var eq = String(pairs[i]).indexOf("=")
      if (eq === -1) continue
      put(pairs[i].slice(0, eq), pairs[i].slice(eq + 1))
    }
  }
  return out
}

function aliasApp(name, aliases) {
  if (!name || !aliases) return name
  var key = String(name).trim().toLowerCase()
  if (Object.prototype.hasOwnProperty.call(aliases, key)) return aliases[key]
  return name
}

// User alias first, then the built-in canonical fold, so a custom rename
// is never silently re-folded back into a browser bucket. The key matches
// raw, canonical and display names, so "zen=browser" catches "zen-bin" as
// well as "zen"; exact matches win, otherwise a key matching a whole
// dash/dot/underscore segment matches ("zen" in "zen-browser", never
// "foo" in "foot"). Values fold like any name.
function resolveAppName(name, aliases) {
  if (!name) return ""
  if (aliases) {
    var candidates = [
      String(name).trim().toLowerCase(),
      String(canonicalApp(name)).toLowerCase(),
      String(displayName(name)).toLowerCase(),
    ]
    var i = 0
    var j = 0
    var s = 0
    for (i = 0; i < candidates.length; i++) {
      if (
        candidates[i] &&
        Object.prototype.hasOwnProperty.call(aliases, candidates[i])
      )
        return canonicalApp(aliases[candidates[i]])
    }
    for (var k in aliases) {
      if (!k || !Object.prototype.hasOwnProperty.call(aliases, k)) continue
      for (j = 0; j < candidates.length; j++) {
        var segments = String(candidates[j]).split(/[^a-z0-9]+/)
        for (s = 0; s < segments.length; s++) {
          if (segments[s] === k) return canonicalApp(aliases[k])
        }
      }
    }
  }
  return canonicalApp(name)
}

// Strip ignored apps from a stored day for display; the total recomputes
// so the donut, legend and insights agree on the filtered day. The input
// returns by identity when nothing is ignored.
function filterIgnoredDay(day, ignoredList) {
  if (!day || !ignoredList || ignoredList.length === 0) return day
  var apps = day.apps && typeof day.apps === "object" ? day.apps : {}
  var clean = {}
  var total = 0
  var dropped = false
  for (var app in apps) {
    if (!Object.prototype.hasOwnProperty.call(apps, app)) continue
    if (isIgnoredApp(app, ignoredList)) {
      dropped = true
      continue
    }
    var ms = Number(apps[app]) || 0
    if (ms > 0) {
      clean[app] = ms
      total += ms
    }
  }
  if (!dropped) return day
  return { total: total, apps: clean }
}

// Remap one stored day through the alias map, merging totals of keys
// that now resolve elsewhere. Used when an alias is added mid-day so
// today's earlier time folds into the new name from that point on;
// past days keep the key that was live then and are never passed here.
// Returns the input by identity when nothing resolves elsewhere.
function refoldDay(day, aliases) {
  if (!day || !aliases) return day
  var apps = day.apps && typeof day.apps === "object" ? day.apps : {}
  var out = {}
  var total = 0
  var changed = false
  for (var app in apps) {
    if (!Object.prototype.hasOwnProperty.call(apps, app)) continue
    var ms = Number(apps[app]) || 0
    if (ms <= 0) continue
    var key = resolveAppName(app, aliases)
    if (key !== app) changed = true
    out[key] = (out[key] || 0) + ms
    total += ms
  }
  if (!changed) return day
  return { total: total, apps: out }
}

// List editing for the settings menu: the prefs store comma strings while
// the menu shows one row per entry with a remove button and a save box.
function ignoredWith(list, name) {
  var out = parseIgnoredApps(list)
  var n = String(name || "")
    .trim()
    .toLowerCase()
  if (n && out.indexOf(n) === -1) out.push(n)
  return out
}

function ignoredWithout(list, name) {
  var n = String(name || "")
    .trim()
    .toLowerCase()
  var out = []
  var cur = parseIgnoredApps(list)
  for (var i = 0; i < cur.length; i++) {
    if (cur[i] !== n) out.push(cur[i])
  }
  return out
}

// Alias pairs in stored order: [{ from, to }].
function aliasPairs(value) {
  var obj = parseAppAliases(value)
  var out = []
  for (var k in obj) {
    if (Object.prototype.hasOwnProperty.call(obj, k))
      out.push({ from: k, to: obj[k] })
  }
  return out
}

function serializeAliases(obj) {
  var parts = []
  var src = obj && typeof obj === "object" ? obj : {}
  for (var k in src) {
    if (!Object.prototype.hasOwnProperty.call(src, k)) continue
    if (k === "__proto__") continue
    parts.push(k + "=" + src[k])
  }
  return parts.join(", ")
}

function aliasesWith(value, from, to) {
  var obj = parseAppAliases(value)
  var f = String(from || "")
    .trim()
    .toLowerCase()
  var t = String(to || "").trim()
  if (f && t && f !== "__proto__") obj[f] = t
  return serializeAliases(obj)
}

function aliasesWithout(value, from) {
  var obj = parseAppAliases(value)
  delete obj[
    String(from || "")
      .trim()
      .toLowerCase()
  ]
  return serializeAliases(obj)
}

// Daily screen-time goal in whole hours; 0 (or unparseable) means off.
var DAILY_GOAL_PRESETS = [0, 4, 6, 8]
function parseDailyGoalHours(value) {
  var h = Math.floor(Number(value))
  if (!isFinite(h) || h < 1 || h > 24) return 0
  return h
}

// Progress toward the daily goal: { goalMs, pct, remainingMs, reached }.
// Null when the goal is off so callers can hide goal UI entirely.
function goalProgress(totalMs, goalHours) {
  var goal = parseDailyGoalHours(goalHours)
  if (goal <= 0) return null
  var goalMs = goal * 3600000
  var total = Math.max(0, Number(totalMs) || 0)
  return {
    goalMs: goalMs,
    pct: Math.min(100, Math.round((total / goalMs) * 100)),
    remainingMs: Math.max(0, goalMs - total),
    reached: total >= goalMs,
  }
}

// App-detail window: the per-app breakdown is kept for a full year, so
// the 52-week graph stays fully detailed (the floor stretches it a
// little further). Only the app list is forgotten after this — totals
// live on as the perpetual per-day archive.
var APP_DETAIL_DAYS = 365

// Week-trend presets: 12w default reaches back a quarter; 24/36/52 for
// half-year, three-quarter and full-year pages.
var WEEK_COUNT_OPTIONS = [12, 24, 36, 52]

// Preset weeks, else round legacy stored windows up to the nearest
// preset — the graph never silently shrinks.
function parseWeekCount(value) {
  var n = Math.floor(Number(value))
  if (!isFinite(n) || n < 1) return WEEK_COUNT_OPTIONS[0]
  if (WEEK_COUNT_OPTIONS.indexOf(n) >= 0) return n
  if (n <= 12) return 12
  if (n <= 24) return 24
  if (n <= 36) return 36
  return 52
}

// Retention floor for a week-trend window: always the window plus slack
// (52 weeks plus 11 days), so the visible trend stays fully detailed no
// matter which preset is stored.
function minKeepDays(weekCount) {
  var w = Math.floor(Number(weekCount))
  if (!isFinite(w) || w < 1) return 95
  return w * 7 + 11
}

// Storage footprint over the three disjoint stores: { dayCount,
// monthCount, archiveDays, totalMs }. Pruned days already live in the
// archive, so the footprint shows the year of app detail plus the
// ever-growing day archive.
function storageSummary(days, months, years) {
  var dayCount = 0
  var totalMs = 0
  var d = days && typeof days === "object" ? days : {}
  for (var dk in d) {
    if (!Object.prototype.hasOwnProperty.call(d, dk)) continue
    dayCount++
    totalMs += Number(d[dk] && d[dk].total) || 0
  }
  var monthCount = 0
  var m = months && typeof months === "object" ? months : {}
  for (var mk in m) {
    if (!Object.prototype.hasOwnProperty.call(m, mk)) continue
    monthCount++
    totalMs += Number(m[mk]) || 0
  }
  var archiveDays = 0
  var y = years && typeof years === "object" ? years : {}
  for (var yk in y) {
    if (!Object.prototype.hasOwnProperty.call(y, yk)) continue
    var arch = y[yk] && typeof y[yk] === "object" ? y[yk] : {}
    for (var ak in arch) {
      if (!Object.prototype.hasOwnProperty.call(arch, ak)) continue
      archiveDays++
      totalMs += Number(arch[ak]) || 0
    }
  }
  return {
    dayCount: dayCount,
    monthCount: monthCount,
    archiveDays: archiveDays,
    totalMs: totalMs,
  }
}

function storageLabel(summary) {
  var s = summary || { dayCount: 0, monthCount: 0, archiveDays: 0 }
  return (
    (Number(s.dayCount) || 0) +
    " days \u00b7 " +
    (Number(s.monthCount) || 0) +
    " months \u00b7 " +
    (Number(s.archiveDays) || 0) +
    " archived"
  )
}

// True for 6-digit hex with or without a leading hash.
function isHexColor(s) {
  return /^#?[0-9a-fA-F]{6}$/.test(String(s || "").trim())
}

// Lowercase #rrggbb, or the fallback for anything unparseable.
function normalizeHex(s, fallback) {
  var t = String(s || "").trim()
  if (!isHexColor(t)) return fallback
  if (t.charAt(0) !== "#") t = "#" + t
  return t.toLowerCase()
}

// Swatch options derived from the live theme: the theme neutrals plus an
// accent family in the sliceColors idiom, so the menu harmonizes with the
// donut. Reused for both color rows; seven entries keep the row width.
function themeSwatches(accentHex, foregroundHex, mutedHex) {
  var chromatics = sliceColors(5, accentHex)
  return [
    normalizeHex(foregroundHex, "#ffffff"),
    normalizeHex(mutedHex, "#808080"),
    chromatics[0],
    chromatics[1],
    chromatics[2],
    chromatics[3],
    chromatics[4],
  ]
}

// Selection that survives theme switches: any valid stored hex stays
// selected (the menu renders an extra custom slot when it is absent from
// the theme set); garbage falls back to the default.
function pickSwatch(stored, fallback) {
  var c = normalizeHex(stored, "")
  return c || fallback
}

// Parse a day key into a local Date, or null when malformed or rolled
// over ("2026-02-30" is not a date). Every key reader below funnels
// through here instead of trusting the Date constructor's rollover.
function keyToDate(key) {
  var p = String(key || "").split("-")
  if (p.length !== 3) return null
  var y = Number(p[0])
  var m = Number(p[1])
  var d = Number(p[2])
  if (!isFinite(y) || !isFinite(m) || !isFinite(d)) return null
  var dt = new Date(y, m - 1, d)
  if (dt.getFullYear() !== y || dt.getMonth() !== m - 1 || dt.getDate() !== d)
    return null
  return dt
}

// True for real padded calendar days ("2026-08-19"). Rolled-over
// overflow ("2026-02-30", "2026-13-01") and garbage fail, so unpadded
// keys never mis-compare against padded ones downstream.
function isDayKey(key) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(key || ""))) return false
  var p = String(key).split("-")
  var y = Number(p[0])
  var m = Number(p[1])
  var d = Number(p[2])
  if (m < 1 || m > 12 || d < 1 || d > 31) return false
  var dt = new Date(y, m - 1, d)
  return dt.getFullYear() === y && dt.getMonth() === m - 1 && dt.getDate() === d
}

// True for real calendar months ("2026-08").
function isMonthKey(key) {
  return /^\d{4}-(0[1-9]|1[0-2])$/.test(String(key || ""))
}

// Goal history: [{ day: "YYYY-MM-DD", hours }] recording every change.
// The goal counts from the day it is set; earlier days never show it,
// and each day keeps the goal it had (goals may differ day to day).
function parseGoalLog(value) {
  var out = []
  var raw = Array.isArray(value) ? value : []
  for (var i = 0; i < raw.length; i++) {
    var e = raw[i] || {}
    var day = String(e.day || "")
    var h = Math.floor(Number(e.hours))
    if (!isDayKey(day) || !isFinite(h) || h < 0 || h > 24) continue
    out.push({ day: day, hours: h })
  }
  // Latest entry wins per day, chronological order.
  var byDay = {}
  for (var j = 0; j < out.length; j++) byDay[out[j].day] = out[j].hours
  var days = Object.keys(byDay).sort()
  var clean = []
  for (var k = 0; k < days.length; k++) {
    clean.push({ day: days[k], hours: byDay[days[k]] })
  }
  return clean
}

// Hours in force on key: the latest entry on or before it, else 0 (off).
function goalForDay(log, key) {
  var k = String(key || "")
  var best = ""
  var hours = 0
  var list = Array.isArray(log) ? log : []
  for (var i = 0; i < list.length; i++) {
    var e = list[i] || {}
    var day = String(e.day || "")
    if (!isDayKey(day) || day > k) continue
    var h = Math.floor(Number(e.hours))
    if (!isFinite(h) || h < 0 || h > 24) continue
    if (day >= best) {
      best = day
      hours = h
    }
  }
  return hours
}

// Record a goal change made today: replaces today's entry when the goal
// already changed today, else appends. Bounded so restless toggling
// can't grow settings without limit.
var GOAL_LOG_MAX = 500
function logGoalChange(log, todayKey, hours) {
  var h = Math.floor(Number(hours))
  if (!isFinite(h) || h < 0 || h > 24) h = 0
  var tk = isDayKey(todayKey) ? String(todayKey) : ""
  var clean = []
  var base = parseGoalLog(log)
  for (var i = 0; i < base.length; i++) {
    if (base[i].day !== tk) clean.push(base[i])
  }
  if (tk) clean.push({ day: tk, hours: h })
  clean.sort(function (a, b) {
    return a.day < b.day ? -1 : 1
  })
  while (clean.length > GOAL_LOG_MAX) clean.shift()
  return clean
}

// Malformed history sections fall back to empty; arrays are rejected.
function isPlainObject(v) {
  return !!v && typeof v === "object" && !Array.isArray(v)
}

function sanitizeHistory(days, months, years) {
  var cleanDays = isPlainObject(days) ? days : {}
  var cleanMonths = isPlainObject(months) ? months : {}
  var rebuilt = false
  var out = {}
  for (var k in cleanDays) {
    if (!Object.prototype.hasOwnProperty.call(cleanDays, k)) continue
    // Malformed keys ("junk", "__proto__", unpadded dates) never survive
    // a load; downstream lexicographic compares assume real day keys.
    if (!isDayKey(k)) {
      rebuilt = true
      continue
    }
    var fixed = sanitizeDay(cleanDays[k])
    out[k] = fixed.day
    if (fixed.changed) rebuilt = true
  }
  var mout = {}
  for (var mk in cleanMonths) {
    if (!Object.prototype.hasOwnProperty.call(cleanMonths, mk)) continue
    if (!isMonthKey(mk)) {
      rebuilt = true
      continue
    }
    mout[mk] = cleanMonths[mk]
  }
  return {
    days: rebuilt ? out : cleanDays,
    months: rebuilt ? mout : cleanMonths,
    years: sanitizeYears(years),
  }
}

// Returns { day, changed }; unchanged days keep object identity.
function sanitizeDay(d) {
  if (!isPlainObject(d)) return { day: newDay(), changed: true }
  var total = Number(d.total) || 0
  if (!isFinite(total) || total < 0) total = 0
  var apps = isPlainObject(d.apps) ? d.apps : {}
  var cleanApps = {}
  var appsChanged = apps !== d.apps
  for (var app in apps) {
    if (!Object.prototype.hasOwnProperty.call(apps, app)) continue
    if (app === "__proto__") {
      appsChanged = true
      continue
    }
    var ms = Number(apps[app])
    if (isFinite(ms) && ms >= 0) cleanApps[app] = ms
    else appsChanged = true
  }
  if (total === d.total && !appsChanged) return { day: d, changed: false }
  return { day: { total: total, apps: cleanApps }, changed: true }
}

// The year archive maps "YYYY" to { "YYYY-MM-DD": ms }. Returns the input
// untouched when nothing is discarded so callers can detect malformed data
// by identity; rebuilds a clean object when entries are dropped.
function sanitizeYears(years) {
  if (!isPlainObject(years)) return {}
  var rebuilt = false
  var out = {}
  for (var yk in years) {
    if (!Object.prototype.hasOwnProperty.call(years, yk)) continue
    if (!/^\d{4}$/.test(String(yk)) || !isPlainObject(years[yk])) {
      rebuilt = true
      continue
    }
    var day = {}
    var dayChanged = false
    for (var dk in years[yk]) {
      if (!Object.prototype.hasOwnProperty.call(years[yk], dk)) continue
      // Day keys must be real dates of their own year; anything else
      // (including "__proto__") is discarded, never assigned.
      if (!isDayKey(dk) || String(dk).slice(0, 4) !== String(yk)) {
        dayChanged = true
        continue
      }
      var v = Number(years[yk][dk])
      if (isFinite(v) && v >= 0) day[dk] = v
      else dayChanged = true
    }
    if (dayChanged) rebuilt = true
    out[yk] = day
  }
  if (!rebuilt) return years
  return out
}

// The day object to render: live today when nothing is selected (or the
// selected key is today), otherwise the stored history day.
function dayFor(days, today, key, todayKey) {
  if (!key || key === todayKey) return today
  return days && days[key] ? days[key] : null
}

// Local-time calendar key, e.g. "2026-08-13". Anything without a real
// calendar date yields "" rather than throwing.
function dayKey(date) {
  if (!date || typeof date.getTime !== "function" || isNaN(date.getTime()))
    return ""
  return (
    date.getFullYear() +
    "-" +
    pad2(date.getMonth() + 1) +
    "-" +
    pad2(date.getDate())
  )
}

function newDay() {
  return { total: 0, apps: {} }
}

// Compact human duration: "0m", "45s", "23m", "3h", "2h 14m".
// Non-finite input renders as zero rather than "Infinityh".
function fmt(ms) {
  ms = Number(ms)
  if (!isFinite(ms)) ms = 0
  ms = Math.max(0, Math.round(ms))
  if (ms <= 0) return "0m"
  if (ms < 60000) return Math.max(1, Math.round(ms / 1000)) + "s"
  var mins = Math.round(ms / 60000)
  if (mins < 60) return mins + "m"
  var h = Math.floor(mins / 60)
  var m = mins % 60
  return m === 0 ? h + "h" : h + "h " + m + "m"
}

function fmtDelta(ms) {
  return (ms < 0 ? "-" : "+") + " " + fmt(Math.abs(ms))
}

// Worded duration for the panel: "0 MINUTES", "12 MINUTES",
// "2 HOURS 14 MINUTES", "45 SECONDS".
function fmtWords(ms) {
  ms = Number(ms)
  if (!isFinite(ms)) ms = 0
  ms = Math.max(0, Math.round(ms))
  if (ms <= 0) return "0 MINUTES"
  if (ms < 60000) {
    var s = Math.max(1, Math.round(ms / 1000))
    return s + (s === 1 ? " SECOND" : " SECONDS")
  }
  var mins = Math.round(ms / 60000)
  if (mins < 60) return mins + (mins === 1 ? " MINUTE" : " MINUTES")
  var h = Math.floor(mins / 60)
  var m = mins % 60
  var part = h + (h === 1 ? " HOUR" : " HOURS")
  if (m > 0) part += " " + m + (m === 1 ? " MINUTE" : " MINUTES")
  return part
}

// Sorted per-app list for today: [{ app, ms, pct }], most-used first.
// Apps with under a minute of use are dropped so the panel only lists
// meaningful entries.
function appList(today) {
  var apps = today && today.apps ? today.apps : {}
  var total = today && today.total ? today.total : 0
  var out = []
  for (var app in apps) {
    if (!Object.prototype.hasOwnProperty.call(apps, app)) continue
    var ms = Number(apps[app]) || 0
    if (ms < 60000) continue
    out.push({
      app: app,
      ms: ms,
      pct: total > 0 ? Math.round((100 * ms) / total) : 0,
    })
  }
  out.sort(function (a, b) {
    return b.ms - a.ms
  })
  return out
}

// Tail folds into "Other" past maxSlices or below minPct. Both params are
// required: QML's JS engine has no default parameters.
var DONUT_MAX_SLICES = 6
var DONUT_MIN_PCT = 3
// Floor for the week bar-graph y-axis: sparse weeks stay legible by never
// squashing their axis below a 4-hour reference even when every day is small.
var TREND_REF_MS = 4 * 3600000
function groupedApps(apps, maxSlices, minPct) {
  var raw = Array.isArray(apps) ? apps : []
  // Malformed entries carry no time; skipping beats throwing.
  var list = []
  for (var k = 0; k < raw.length; k++) {
    if (raw[k] && typeof raw[k] === "object") list.push(raw[k])
  }
  var max = typeof maxSlices === "number" ? maxSlices : DONUT_MAX_SLICES
  var floor = typeof minPct === "number" ? minPct : DONUT_MIN_PCT
  var total = 0
  for (var j = 0; j < list.length; j++) {
    var each = Number(list[j].ms)
    total += isFinite(each) && each > 0 ? each : 0
  }
  var head = []
  var tailMs = 0
  for (var i = 0; i < list.length; i++) {
    var pct = total > 0 ? ((Number(list[i].ms) || 0) / total) * 100 : 0
    if (head.length < max - 1 && pct >= floor) {
      head.push(list[i])
    } else {
      tailMs += Number(list[i].ms) || 0
    }
  }
  if (tailMs > 0) {
    var other = {
      app: "Other",
      ms: tailMs,
      pct: total > 0 ? Math.round((100 * tailMs) / total) : 0,
    }
    head.push(other)
  }
  return head
}

function totalFor(days, key) {
  var d = days && days[key]
  return d && d.total ? d.total : 0
}

function prevKey(key) {
  var d = keyToDate(key)
  if (!d) return ""
  d.setDate(d.getDate() - 1)
  return dayKey(d)
}

var WEEKDAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTH_NAMES = [
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
]

// Full date label for a dayKey, e.g. "Aug 15".
function formatDate(key) {
  var d = keyToDate(key)
  if (!d) return ""
  return MONTH_NAMES[d.getMonth()] + " " + d.getDate()
}

// Short weekday name for any key, e.g. "Mon".  Unlike relativeDayLabel
// this never returns "Today" or "Yesterday".
function weekdayLabel(key) {
  var d = keyToDate(key)
  if (!d) return ""
  return WEEKDAY_NAMES[d.getDay()]
}

// Weekday label for a dayKey relative to today: "Today", "Yesterday", or
// the short weekday name.

function relativeDayLabel(key, todayKey) {
  if (!key) return ""
  if (key === todayKey) return "Today"
  if (key === prevKey(todayKey)) return "Yesterday"
  return weekdayLabel(key)
}

// Last 7 day keys ending at todayKey, oldest first.
function weekKeys(todayKey) {
  if (!keyToDate(todayKey)) return []
  var keys = []
  var key = todayKey
  for (var i = 0; i < 7; i++) {
    keys.unshift(key)
    key = prevKey(key)
  }
  return keys
}

// Busiest day in the trailing 7 days: { key, total }.
function busiestWeekDay(days, todayKey) {
  var keys = weekKeys(todayKey)
  if (!keys.length) return { key: "", total: 0 }
  var best = { key: keys[keys.length - 1], total: 0 }
  for (var i = 0; i < keys.length; i++) {
    var total = totalFor(days, keys[i])
    if (total > best.total) best = { key: keys[i], total: total }
  }
  return best
}

// Trailing-7-day usage for the trend strip, oldest first. Each entry:
// { key, ms, label, isToday } where label is the consistent 3-letter
// weekday; today is told apart by its full-accent bar instead.
function weekTrend(days, todayKey) {
  var keys = weekKeys(todayKey)
  if (!keys.length) return []
  var out = []
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i]
    var d = keyToDate(key)
    out.push({
      key: key,
      ms: totalFor(days, key),
      label: d ? WEEKDAY_NAMES[d.getDay()] : "",
      isToday: key === todayKey,
    })
  }
  return out
}

// Total focused time across a weekTrend list.
function weekTotal(trend) {
  var total = 0
  var list = Array.isArray(trend) ? trend : []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i] || {}
    var ms = Number(entry.ms)
    total += isFinite(ms) && ms > 0 ? ms : 0
  }
  return total
}

// True when the week at offset beats every older week in a monSunWeeks
// list (strictly: ties don't take the crown, and a lone week with no
// previous weeks has surpassed nothing).
function isRecordWeek(weeks, offset) {
  if (!weeks || offset < 0 || offset >= weeks.length) return false
  if (offset + 1 >= weeks.length) return false
  var mine = weekTotal(weeks[offset] ? weeks[offset].days : [])
  if (mine <= 0) return false
  for (var i = offset + 1; i < weeks.length; i++) {
    if (weekTotal(weeks[i] ? weeks[i].days : []) >= mine) return false
  }
  return true
}

// Offset of the unique-best week in a monSunWeeks list (newest first),
// or -1 when there is none: empty, all zero, or a tied top. Unlike
// isRecordWeek (which only looks at older weeks) this compares against
// every loaded week, so a paged-back best week still earns the crown.
function bestWeekOffset(weeks) {
  var list = Array.isArray(weeks) ? weeks : []
  var best = -1
  var bestMs = 0
  for (var i = 0; i < list.length; i++) {
    var ms = weekTotal(list[i] ? list[i].days : [])
    if (ms > bestMs) {
      bestMs = ms
      best = i
    } else if (ms > 0 && ms === bestMs) {
      best = -1
    }
  }
  return best
}

// Prune past keepDays (ISO keys compare lexicographically); unchanged
// input returns by identity. Absurd windows (Infinity) prune nothing
// instead of hanging the cutoff loop.
function pruneDays(days, todayKey, keepDays) {
  if (!days || !(keepDays >= 1) || !isFinite(keepDays)) return days
  var cutoff = todayKey
  for (var i = 1; i < keepDays; i++) cutoff = prevKey(cutoff)
  var out = {}
  var changed = false
  for (var k in days) {
    if (k >= cutoff) out[k] = days[k]
    else changed = true
  }
  return changed ? out : days
}

// Three insight rows [{ label, value, kind, dir }]; weekEndKey anchors
// the 7d row to the visible week.
function insights(day, days, todayKey, activeKey, weekEndKey) {
  var key = activeKey || todayKey
  var isToday = key === todayKey
  var dayLabel = isToday ? "" : " (" + weekdayLabel(key) + ")"
  var total = day && day.total ? day.total : 0

  var apps = appList(day)
  var topApp = apps.length ? apps[0] : null
  var topLabel = topApp
    ? displayName(topApp.app) +
      " \u00b7 " +
      "(" +
      topApp.pct +
      "%)" +
      " \u00b7 " +
      fmt(topApp.ms)
    : "\u2014"
  // Rows carry kind + dir so the panel renders meaning without parsing
  // label text: kind is "top" | "delta" | "busiest", dir is
  // "up" | "down" | "flat" for deltas and null otherwise.
  var list = [
    {
      label: isToday ? "Top app" : "Top app " + weekdayLabel(key),
      value: topLabel,
      kind: "top",
      dir: null,
    },
  ]

  var compareKey = prevKey(key)
  var compareTotal = totalFor(days, compareKey)
  var delta = total - compareTotal
  var compareLabel = compareTotal > 0 ? fmtDelta(delta) : "\u2014"
  var vsLabel = isToday ? "vs Yesterday" : "vs " + weekdayLabel(compareKey)
  list.push({
    label: vsLabel,
    value: compareLabel,
    kind: "delta",
    dir:
      compareTotal > 0
        ? delta > 0
          ? "up"
          : delta < 0
            ? "down"
            : "flat"
        : null,
  })

  var busiest = busiestWeekDay(days, weekEndKey || todayKey)
  var busiestLabel =
    busiest.total > 0
      ? weekdayLabel(busiest.key) + " \u00b7 " + fmt(busiest.total)
      : "\u2014"
  list.push({
    label: "Busiest day (7d)",
    value: busiestLabel,
    kind: "busiest",
    dir: null,
  })

  return list
}

// ---- Donut chart helpers -----------------------------------------------

// #rrggbb -> { h: 0-360, s: 0-100, l: 0-100 }.
function hexToHsl(hex) {
  var m = /^#?([0-9a-fA-F]{6})$/.exec(
    String(hex || "").replace(/^\s+|\s+$/g, ""),
  )
  if (!m) return { h: 0, s: 0, l: 60 }
  var n = parseInt(m[1], 16)
  var r = ((n >> 16) & 255) / 255
  var g = ((n >> 8) & 255) / 255
  var b = (n & 255) / 255
  var max = Math.max(r, g, b)
  var min = Math.min(r, g, b)
  var h = 0
  var s = 0
  var l = (max + min) / 2
  if (max !== min) {
    var d = max - min
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
    if (max === r) h = (g - b) / d + (g < b ? 6 : 0)
    else if (max === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h *= 60
  }
  return { h: h, s: s * 100, l: l * 100 }
}

// { h: 0-360, s: 0-100, l: 0-100 } -> #rrggbb.
function hslToHex(h, s, l) {
  h = ((h % 360) + 360) % 360
  s /= 100
  l /= 100
  var c = (1 - Math.abs(2 * l - 1)) * s
  var x = c * (1 - Math.abs(((h / 60) % 2) - 1))
  var m = l - c / 2
  var r = 0
  var g = 0
  var b = 0
  if (h < 60) {
    r = c
    g = x
  } else if (h < 120) {
    r = x
    g = c
  } else if (h < 180) {
    g = c
    b = x
  } else if (h < 240) {
    g = x
    b = c
  } else if (h < 300) {
    r = x
    b = c
  } else {
    r = c
    b = x
  }
  function ch(v) {
    var t = Math.max(0, Math.min(255, Math.round((v + m) * 255)))
    return (t < 16 ? "0" : "") + t.toString(16)
  }
  return "#" + ch(r) + ch(g) + ch(b)
}

// Per-app hues rotate off the accent; grayscale accents use a lightness ramp.
function sliceColors(count, accentHex) {
  var base = hexToHsl(accentHex)
  var GRAY_RAMP = [50, 70, 32, 82, 40, 62, 28, 76]
  var out = []
  for (var i = 0; i < count; i++) {
    var h = base.h + i * 38
    var l = base.l
    if (base.s < 12) {
      l = GRAY_RAMP[i % GRAY_RAMP.length]
    } else if (i % 2 === 1) {
      l = Math.max(32, Math.min(80, base.l - 14))
    }
    out.push(hslToHex(h, base.s, l))
  }
  return out
}

// Insight glyph colors track the theme; down is fixed at hue 155
// (the shell exposes no green role).
function insightColors(accentHex, urgentHex) {
  var base = hexToHsl(accentHex)
  var upHsl = hexToHsl(urgentHex)
  var vivid = base.s < 12 ? 55 : base.s
  var level = Math.max(32, Math.min(78, base.l))
  return {
    star: hslToHex(base.h, base.s, base.l),
    up: hslToHex(upHsl.h, upHsl.s, upHsl.l),
    down: hslToHex(155, vivid, level),
    busiest: hslToHex(base.h + 80, vivid, level),
  }
}

// Donut segments for a sorted app list: [{ app, ms, pct, startAngle,
// sweepAngle }]. Angles start at 12 o'clock (sweep 0 = -90deg) and go
// clockwise; a small gap separates slices. A single app owns the full circle.
var ARC_GAP_DEG = 1.5
function arcSegments(apps) {
  var raw = Array.isArray(apps) ? apps : []
  var list = []
  for (var k = 0; k < raw.length; k++) {
    if (raw[k] && typeof raw[k] === "object") list.push(raw[k])
  }
  var total = 0
  for (var i = 0; i < list.length; i++) {
    var each = Number(list[i].ms)
    total += isFinite(each) && each > 0 ? each : 0
  }
  var gap = list.length > 1 ? ARC_GAP_DEG : 0
  var angle = -90
  var out = []
  for (var j = 0; j < list.length; j++) {
    var frac = total > 0 ? (Number(list[j].ms) || 0) / total : 0
    var sweep = Math.max(0, frac * 360 - gap)
    out.push({
      app: list[j].app,
      ms: list[j].ms,
      pct: list[j].pct,
      startAngle: angle,
      sweepAngle: sweep,
    })
    angle += frac * 360
  }
  return out
}

// ---- Scrollable Mon-Sun bar graph helpers --------------------------------

// Returns the Monday of the ISO week containing `key`.
function weekStartMonday(key) {
  var d = keyToDate(key)
  if (!d) return ""
  var day = d.getDay()
  var diff = (day === 0 ? -6 : 1) - day
  d.setDate(d.getDate() + diff)
  return dayKey(d)
}

// ISO-8601 week number (Mon=1 .. Sun=7 weeks, W1 holds the first Thursday).
// Returns 0 for input that does not parse as a YYYY-MM-DD key.
function isoWeekNumber(key) {
  var d = keyToDate(key)
  if (!d) return 0
  // Shift to the week's Thursday: ISO years are identified by that day.
  var target = new Date(d.valueOf())
  target.setDate(target.getDate() - ((d.getDay() + 6) % 7) + 3)
  // The Thursday of the week containing Jan 4 is always in ISO week 1.
  var firstThursday = new Date(target.getFullYear(), 0, 4)
  firstThursday.setDate(
    firstThursday.getDate() - ((firstThursday.getDay() + 6) % 7) + 3,
  )
  return 1 + Math.round((target - firstThursday) / (7 * 86400000))
}

// Oldest year that has any recorded data (daily keys or monthly rollups).
// Falls back to the current year so navigation stays put on empty history.
function firstDataYear(days, months, years) {
  var min = 0
  function scan(key) {
    var y = Number(String(key).split("-")[0])
    if (y > 2000 && y < 2200 && (min === 0 || y < min)) min = y
  }
  for (var dk in days) {
    if (Object.prototype.hasOwnProperty.call(days, dk)) scan(dk)
  }
  for (var mk in months) {
    if (Object.prototype.hasOwnProperty.call(months, mk)) scan(mk)
  }
  for (var yk in years || {}) {
    if (Object.prototype.hasOwnProperty.call(years, yk)) scan(yk)
  }
  return min || new Date().getFullYear()
}

// Milliseconds from nowMs until the next full hour boundary. Used to turn
// the hero hourglass exactly on the hour. Falls back to one minute for
// input that does not parse as a timestamp.
function msUntilNextHour(nowMs) {
  var d = new Date(Number(nowMs))
  if (isNaN(d.getTime())) return 60000
  return (
    (3600 - d.getMinutes() * 60 - d.getSeconds()) * 1000 - d.getMilliseconds()
  )
}

// Mon-Sun weeks, newest first: { month, days: [{ key, ms, label, flags }] }.
// Mon = 0, Sun = 6; future days render as stubs. Absurd counts prune to
// nothing instead of hanging the generator.
function monSunWeeks(days, todayKey, weekCount) {
  var count = Math.floor(Number(weekCount))
  if (!todayKey || !(count >= 1) || !isFinite(count)) return []
  var weeks = []
  var monStart = weekStartMonday(todayKey)
  if (!monStart) return []
  for (var w = 0; w < count; w++) {
    var weekDays = []
    var monthCounts = {}
    for (var di = 0; di < 7; di++) {
      var dParts = String(monStart).split("-")
      var dObj = new Date(
        Number(dParts[0]),
        Number(dParts[1]) - 1,
        Number(dParts[2]) + di,
      )
      var dk = dayKey(dObj)
      var isFuture = dk > todayKey
      var ms = isFuture ? 0 : totalFor(days, dk)
      if (!isFuture) {
        var m = MONTH_NAMES[dObj.getMonth()]
        monthCounts[m] = (monthCounts[m] || 0) + 1
      }
      weekDays.push({
        key: dk,
        ms: ms,
        label: WEEKDAY_NAMES[dObj.getDay()],
        isEmpty: ms <= 0 && !isFuture,
        isFuture: isFuture,
        isToday: dk === todayKey,
      })
    }
    var month = ""
    var bestCount = 0
    for (var mKey in monthCounts) {
      if (monthCounts[mKey] > bestCount) {
        bestCount = monthCounts[mKey]
        month = mKey
      }
    }
    weeks.push({ month: month, days: weekDays })
    // Next week: go back 7 days from this Monday.
    var mParts = String(monStart).split("-")
    var mObj = new Date(
      Number(mParts[0]),
      Number(mParts[1]) - 1,
      Number(mParts[2]) - 7,
    )
    monStart = dayKey(mObj)
  }
  return weeks
}

// Week header label, e.g. "Aug 17 – 23, 2026 · W34"; "" when malformed.
function weekRangeLabel(week) {
  var days = week && week.days ? week.days : week
  if (!days || days.length !== 7) return ""
  var startKey = days[0] && days[0].key ? String(days[0].key) : ""
  var endKey = days[6] && days[6].key ? String(days[6].key) : ""
  if (!keyToDate(startKey) || !keyToDate(endKey)) return ""
  var sp = startKey.split("-")
  var ep = endKey.split("-")
  if (sp.length !== 3 || ep.length !== 3) return ""
  var sy = Number(sp[0])
  var sm = Number(sp[1]) - 1
  var sd = Number(sp[2])
  var ey = Number(ep[0])
  var em = Number(ep[1]) - 1
  var ed = Number(ep[2])
  var sDate = new Date(sy, sm, sd)
  var eDate = new Date(ey, em, ed)
  if (isNaN(sDate.getTime()) || isNaN(eDate.getTime())) return ""
  var range = ""
  if (sy === ey && sm === em) {
    range =
      MONTH_NAMES[sm] +
      " " +
      sDate.getDate() +
      " – " +
      eDate.getDate() +
      ", " +
      sy
  } else if (sy === ey) {
    range =
      MONTH_NAMES[sm] +
      " " +
      sDate.getDate() +
      " – " +
      MONTH_NAMES[em] +
      " " +
      eDate.getDate() +
      ", " +
      sy
  } else {
    // Cross-year weeks keep both years, abbreviated to two digits.
    range =
      MONTH_NAMES[sm] +
      " " +
      sDate.getDate() +
      ", " +
      String(sy).slice(-2) +
      " – " +
      MONTH_NAMES[em] +
      " " +
      eDate.getDate() +
      ", " +
      String(ey).slice(-2)
  }
  // Every day in a Mon–Sun week shares the ISO week number; Thursday is the
  // ISO reference day, with Monday as fallback.
  var refKey = days[3] && days[3].key ? String(days[3].key) : startKey
  var weekNo = isoWeekNumber(refKey)
  if (!weekNo) weekNo = isoWeekNumber(startKey)
  if (!weekNo) return ""
  return range + " · W" + weekNo
}

// Max ms across all days in a monSunWeeks result for consistent bar scaling.
function scrollableTrendMax(weeks) {
  var max = 0
  var list = Array.isArray(weeks) ? weeks : []
  for (var i = 0; i < list.length; i++) {
    var days = (list[i] && list[i].days) || []
    for (var j = 0; j < days.length; j++) {
      var day = days[j] || {}
      var ms = Number(day.ms)
      if (isFinite(ms) && ms > max) max = ms
    }
  }
  return max
}

// One week-trend derivation: { weeks, week, max, totalMs, isRecord,
// hasPrev, weekEndKey }; null week when offset is out of range.
function weekView(days, todayKey, weekCount, offset) {
  var weeks = monSunWeeks(days, todayKey, weekCount)
  var empty = {
    weeks: weeks,
    week: null,
    max: 0,
    totalMs: 0,
    isRecord: false,
    hasPrev: false,
    weekEndKey: "",
  }
  if (!(offset >= 0) || offset !== Math.floor(offset) || offset >= weeks.length)
    return empty
  var week = weeks[offset]
  var wdays = week && week.days ? week.days : []
  var max = 0
  var i
  for (i = 0; i < wdays.length; i++) {
    var ms = Number(wdays[i].ms) || 0
    if (ms > max) max = ms
  }
  var hasPrev = false
  for (i = offset + 1; i < weeks.length; i++) {
    var prev = weeks[i] && weeks[i].days ? weeks[i].days : []
    for (var j = 0; j < prev.length; j++) {
      if ((Number(prev[j].ms) || 0) > 0) {
        hasPrev = true
        break
      }
    }
    if (hasPrev) break
  }
  // Weeks holding any tracked time; the trophy needs at least two.
  var dataWeeks = 0
  for (i = 0; i < weeks.length; i++) {
    var scanned = weeks[i] && weeks[i].days ? weeks[i].days : []
    for (var s = 0; s < scanned.length; s++) {
      if ((Number(scanned[s].ms) || 0) > 0) {
        dataWeeks++
        break
      }
    }
  }
  return {
    weeks: weeks,
    week: week,
    max: max,
    totalMs: weekTotal(wdays),
    // The Busiest Week Trophy follows the viewed week at any page: unique best across
    // the whole loaded window, not just "current week beats older weeks".
    // It needs two weeks of tracked data: a lone first week crowns nothing.
    isRecord: offset === bestWeekOffset(weeks) && dataWeeks >= 2,
    hasPrev: hasPrev,
    weekEndKey: wdays.length === 7 ? String(wdays[6].key || "") : "",
  }
}

// Axis ticks anchor to the same max the bars scale against.
function weekAxisTicks(weekMax) {
  var max = Number(weekMax)
  if (weekMax === null || weekMax === "" || !(max >= 0) || !isFinite(max))
    return []
  var ref = Math.max(max, TREND_REF_MS)
  // The mid gridline label renders as whole hours, so the tick sits on a
  // whole hour too — never 2.5h with a "3h" label.
  var half = Math.round(ref / 2 / 3600000) * 3600000
  return [0, half, ref]
}

// Tick labels render whole hours; exact values live in tooltips.
function fmtWholeHours(ms) {
  ms = Number(ms)
  if (!isFinite(ms)) ms = 0
  ms = Math.max(0, ms)
  return Math.round(ms / 3600000) + "h"
}

// ---- Calendar view helpers -----------------------------------------------

// 12 monthly totals merging raw days, month lumps and archive.
function numMs(v) {
  var n = Number(v)
  return isFinite(n) && n > 0 ? n : 0
}

// Merge the three disjoint stores into { monthMs, dayTotals }.
function mergeYear(days, months, years, year, todayKey) {
  var y = Number(year)
  // Future dates (beyond todayKey) are excluded everywhere, not just from
  // dayTotals: month totals, the year total and the retro cards must agree.
  var tk = String(todayKey || "")
  var monthMs = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  var dayMs = {}
  function addDay(key, ms) {
    var k = String(key)
    if (tk && k > tk) return
    // Phantom dates ("2026-02-29") must not inflate month totals they
    // can never appear in as day entries.
    if (!isDayKey(k)) return
    var p = k.split("-")
    if (p.length !== 3 || Number(p[0]) !== y) return
    var m = Number(p[1]) - 1
    if (m < 0 || m > 11) return
    var v = numMs(ms)
    if (v <= 0) return
    monthMs[m] += v
    dayMs[k] = (dayMs[k] || 0) + v
  }
  for (var dk in days) {
    if (!Object.prototype.hasOwnProperty.call(days, dk)) continue
    var d = days[dk]
    if (d) addDay(dk, d.total)
  }
  for (var mk in months) {
    if (!Object.prototype.hasOwnProperty.call(months, mk)) continue
    // Month lumps use the same beyond-todayKey cutoff as days: "YYYY-MM"
    // keys compare lexicographically, so a lump from a clock jump forward
    // (e.g. Dec while today is Aug) can't inflate the year total and the
    // month bars while dayTotals stays empty.
    if (tk && String(mk) > tk.slice(0, 7)) continue
    var mParts = String(mk).split("-")
    if (mParts.length !== 2 || Number(mParts[0]) !== y) continue
    var mi = Number(mParts[1]) - 1
    if (mi >= 0 && mi <= 11) monthMs[mi] += numMs(months[mk])
  }
  var arch = years && years[y] ? years[y] : {}
  for (var ak in arch) {
    if (!Object.prototype.hasOwnProperty.call(arch, ak)) continue
    addDay(ak, arch[ak])
  }
  var out = []
  for (var m = 0; m < 12; m++) {
    var dim = new Date(Date.UTC(y, m + 1, 0)).getUTCDate()
    for (var dd = 1; dd <= dim; dd++) {
      var key = y + "-" + pad2(m + 1) + "-" + pad2(dd)
      if (tk && key > tk) continue
      if (dayMs[key] > 0) out.push({ date: key, ms: dayMs[key] })
    }
  }
  return { monthMs: monthMs, dayTotals: out }
}

// One derived view of a year for every reader: { total, months, dayTotals }.
// monthlyTotals/yearTotal/yearDayTotals are thin views over it, and yearFacts
// consumes it directly, so all of them share one merge.
function yearSummary(days, months, years, year, todayKey) {
  var merged = mergeYear(days, months, years, year, todayKey)
  var mArr = []
  var total = 0
  for (var m = 0; m < 12; m++) {
    mArr.push({
      month: m,
      label: MONTH_NAMES[m],
      ms: merged.monthMs[m],
      hours: Math.round(merged.monthMs[m] / 3600000) + "h",
    })
    total += merged.monthMs[m]
  }
  return { total: total, months: mArr, dayTotals: merged.dayTotals }
}

function monthlyTotals(days, months, year, years, todayKey) {
  return yearSummary(days, months, years, year, todayKey).months
}

// Total ms for all days in a given year. A thin view over yearSummary.
function yearTotal(days, months, year, years, todayKey) {
  return yearSummary(days, months, years, year, todayKey).total
}

// Per-day archive keeping retro facts past the raw-detail window.
var YEAR_HOURS = 8760
var YEAR_HOURS_LEAP = 8784
var MIN_ACTIVE_DAY_MS = 60 * 1000
// Tracked days a current month needs before it can be RECHARGE MONTH.
var MIN_RECHARGE_DAYS = 14

// Days with data in one year-month of a yearDayTotals list.
function monthCoverage(dayTotals, year, month) {
  var n = 0
  var list = Array.isArray(dayTotals) ? dayTotals : []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i] || {}
    var p = String(entry.date).split("-")
    if (Number(p[0]) === year && Number(p[1]) - 1 === month) n++
  }
  return n
}

function yearHours(year) {
  var y = Number(year)
  if (y % 4 !== 0) return YEAR_HOURS
  if (y % 100 !== 0) return YEAR_HOURS_LEAP
  return y % 400 === 0 ? YEAR_HOURS_LEAP : YEAR_HOURS
}

// Whole percent with one decimal, trailing ".0" trimmed: "4.1%", "8.9%".
// A non-positive divisor yields "0%" instead of "Infinity%".
function pctStr(ms, divisorMs) {
  if (!(divisorMs > 0)) return "0%"
  var v = Math.round((Number(ms) / divisorMs) * 1000) / 10
  return String(v).replace(/\.0$/, "") + "%"
}

// Millisecond epoch (UTC) for a "YYYY-MM-DD" key.
function dayMsUtc(key) {
  var p = String(key).split("-")
  return Date.UTC(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
}

// Unions the per-day archive with still-tracked raw days for the whole
// calendar year, ascending, future dates (beyond todayKey) excluded.
// A thin view over yearSummary.
function yearDayTotals(years, days, year, todayKey) {
  return yearSummary(days, {}, years, year, todayKey).dayTotals
}

// Number of active days (at or above minMs) in a dayTotals list.
function activeDayCount(dayTotals, minMs) {
  var n = 0
  var list = Array.isArray(dayTotals) ? dayTotals : []
  for (var i = 0; i < list.length; i++) {
    var ms = list[i] ? Number(list[i].ms) : NaN
    if (isFinite(ms) && ms >= minMs) n++
  }
  return n
}

// Longest and trailing streaks over an ascending dayTotals list. Consecutive
// means back-to-back calendar days (UTC), so month and year bounds chain.
function streakStats(dayTotals) {
  var longest = 0
  var longestEnd = ""
  var lastActive = ""
  var current = 0
  var run = 0
  var prevMs = null
  var list = Array.isArray(dayTotals) ? dayTotals : []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i] || {}
    var t = dayMsUtc(entry.date)
    if (!isFinite(t)) continue
    run = prevMs !== null && t - prevMs === 86400000 ? run + 1 : 1
    if (run > longest) {
      longest = run
      longestEnd = String(dayTotals[i].date)
    }
    current = run
    lastActive = String(dayTotals[i].date)
    prevMs = t
  }
  return {
    longest: longest,
    longestEnd: longestEnd,
    current: current,
    lastActive: lastActive,
  }
}

// Longest offline gap between tracked days: { days, end } where end is the
// return date. Single missed days don't count as a break. Null when fewer
// than two days are on record.
function longestBreak(dayTotals) {
  if (!Array.isArray(dayTotals) || dayTotals.length < 2) return null
  var best = null
  for (var i = 1; i < dayTotals.length; i++) {
    var cur = dayTotals[i] || {}
    var prev = dayTotals[i - 1] || {}
    var gap =
      Math.round(
        (dayMsUtc(String(cur.date)) - dayMsUtc(String(prev.date))) / 86400000,
      ) - 1
    if (gap >= 2 && (!best || gap > best.days))
      best = { days: gap, end: String(cur.date) }
  }
  return best
}

// Weekday number for a day key: Monday 1 through Sunday 7, matching
// the trend's left-to-right day columns. Zero when unparseable.
// Preferred over Repeater index, which misreads inside delegates that
// declare required modelData.
function weekdayNumber(key) {
  var d = keyToDate(key)
  if (!d) return 0
  return ((d.getDay() + 6) % 7) + 1
}

// Monday key of the Mon–Sun week a "YYYY-MM-DD" date belongs to (local
// days, same week definition as the trend graph).
function mondayKey(key) {
  var dt = keyToDate(key)
  if (!dt) return ""
  var mon = new Date(
    dt.getFullYear(),
    dt.getMonth(),
    dt.getDate() - ((dt.getDay() + 6) % 7),
  )
  return (
    mon.getFullYear() +
    "-" +
    pad2(mon.getMonth() + 1) +
    "-" +
    pad2(mon.getDate())
  )
}

// Peak Mon–Sun week: { start, end, ms } with Monday/Sunday keys. Days group
// into their real weeks, so a hot Sunday can't drag six quiet days into a
// fake rolling crown. Null without data; earliest week wins ties.
function busiestSpan(dayTotals) {
  if (!Array.isArray(dayTotals) || dayTotals.length === 0) return null
  var sums = {}
  for (var i = 0; i < dayTotals.length; i++) {
    var entry = dayTotals[i] || {}
    var ms = Number(entry.ms) || 0
    if (ms <= 0) continue
    var mon = mondayKey(String(entry.date))
    if (!mon) continue
    sums[mon] = (sums[mon] || 0) + ms
  }
  var best = null
  for (var k in sums) {
    if (!Object.prototype.hasOwnProperty.call(sums, k)) continue
    if (!best || sums[k] > best.ms) {
      var p = String(k).split("-")
      var end = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]) + 6)
      best = {
        start: k,
        end:
          end.getFullYear() +
          "-" +
          pad2(end.getMonth() + 1) +
          "-" +
          pad2(end.getDate()),
        ms: sums[k],
      }
    }
  }
  return best
}

// Busiest weekday and the share of total ms landing Monday-Friday.
function weekdayPattern(dayTotals, totalMs) {
  var sums = [0, 0, 0, 0, 0, 0, 0]
  var wdSum = 0
  var list = Array.isArray(dayTotals) ? dayTotals : []
  for (var i = 0; i < list.length; i++) {
    var item = list[i] || {}
    var p = String(item.date).split("-")
    var day = new Date(
      Date.UTC(Number(p[0]), Number(p[1]) - 1, Number(p[2])),
    ).getUTCDay()
    var each = Number(item.ms) || 0
    if (each <= 0) continue
    sums[day] += each
    if (day >= 1 && day <= 5) wdSum += each
  }
  var topI = 0
  for (var w = 1; w < 7; w++) if (sums[w] > sums[topI]) topI = w
  return {
    top: WEEKDAY_NAMES[topI],
    weekdayPct: totalMs > 0 ? Math.round((wdSum / totalMs) * 100) : 0,
  }
}

// Honest "active on N of D days" denominator: the calendar span from the
// first recorded day to today for the ongoing year, the full year otherwise.
function trackedDays(dayTotals, year, todayKey) {
  var thisYear = todayKey ? Number(String(todayKey).split("-")[0]) : NaN
  // A malformed todayKey parses to NaN, which never equals the year:
  // without the finiteness check every corrupt call would claim a full
  // past year. Unknown today falls through to the span math, which
  // yields 0 for the same reason.
  if (isFinite(thisYear) && Number(year) !== thisYear)
    return Math.round(
      (Date.UTC(Number(year) + 1, 0, 1) - Date.UTC(Number(year), 0, 1)) /
        86400000,
    )
  if (!Array.isArray(dayTotals) || dayTotals.length === 0) return 0
  var first = ""
  for (var i = 0; i < dayTotals.length; i++) {
    var cand = String((dayTotals[i] || {}).date)
    if (isFinite(dayMsUtc(cand))) {
      first = cand
      break
    }
  }
  if (!first) return 0
  // A malformed todayKey yields a NaN span; never render "of NaN days".
  var span =
    Math.round((dayMsUtc(String(todayKey)) - dayMsUtc(first)) / 86400000) + 1
  return isFinite(span) && span > 0 ? span : 0
}

// Rolls days dropped by the retention window into the perpetual per-day
// archive. Only the total survives — the app breakdown never leaves the
// 365-day detail window.
function rollupArchive(years, prunedDays) {
  if (!prunedDays) return years || {}
  var out = Object.assign({}, years || {})
  for (var dk in prunedDays) {
    if (!Object.prototype.hasOwnProperty.call(prunedDays, dk)) continue
    // Only real day keys roll up; anything else (including "__proto__")
    // would corrupt the archive object.
    if (!isDayKey(dk)) continue
    var d = prunedDays[dk]
    // String totals (from corrupt history) must archive as numbers.
    var total = numMs(d && d.total)
    if (total <= 0) continue
    var parts = String(dk).split("-")
    if (parts.length !== 3) continue
    var yearObj = out[parts[0]] ? Object.assign({}, out[parts[0]]) : {}
    yearObj[dk] = total
    out[parts[0]] = yearObj
  }
  return out
}

// Prune old days into the archive; unchanged inputs return by identity.
// The archive grows forever, so every recorded year keeps its day totals,
// month bars, year total and insights.
function applyRetention(days, years, todayKey, keepDays) {
  var kept = pruneDays(days, todayKey, keepDays)
  if (kept === days) return { days: days, years: years, pruned: false }
  var pruned = {}
  for (var k in days) {
    if (
      Object.prototype.hasOwnProperty.call(days, k) &&
      !Object.prototype.hasOwnProperty.call(kept, k)
    )
      pruned[k] = days[k]
  }
  return {
    days: kept,
    years: rollupArchive(years, pruned),
    pruned: true,
  }
}

// Yearly retro cards [{ glyph, label, value, sub, color }]; day-scale
// cards need per-day coverage, months-only years get the trio.
function yearFacts(days, months, years, year, todayKey, accentHex) {
  // Normalize once: downstream strict compares (recharge guard, coverage)
  // must not treat "2026" as a different year from 2026.
  year = Number(year)
  return yearFactsFromSummary(
    yearSummary(days, months, years, year, todayKey),
    year,
    todayKey,
    accentHex,
  )
}

// Retro cards from an already-merged yearSummary. Lets readers that
// already paid for the merge (like yearView) share it instead of each
// merging the three stores again.
function yearFactsFromSummary(summary, year, todayKey, accentHex) {
  if (!summary || typeof summary !== "object") return []
  var total = summary.total
  if (total <= 0) return []
  var mArr = summary.months
  var totalH = Math.round(total / 3600000)
  var out = []

  var dayTotals = summary.dayTotals

  var top = []
  for (var i = 0; i < mArr.length; i++) {
    if (mArr[i].ms <= 0) continue
    top.push(mArr[i])
  }
  top.sort(function (a, b) {
    return b.ms - a.ms
  })

  // The current month needs two tracked weeks to qualify as recharge.
  var tk = String(todayKey || "").split("-")
  var tkYear = Number(tk[0])
  var tkMonth = Number(tk[1]) - 1
  var pool = []
  for (var q = 0; q < top.length; q++) {
    if (
      year !== tkYear ||
      top[q].month !== tkMonth ||
      monthCoverage(dayTotals, year, top[q].month) >= MIN_RECHARGE_DAYS
    )
      pool.push(top[q])
  }
  if (pool.length === 0) pool = top
  var quietest = null
  for (q = 0; q < pool.length; q++) {
    if (!quietest || pool[q].ms < quietest.ms) quietest = pool[q]
  }

  out.push({
    glyph: "\uF017",
    label: "SCREEN SHARE",
    value:
      totalH +
      "h on screens \u00b7 " +
      pctStr(total, yearHours(year) * 3600000) +
      " of " +
      year,
    sub: "The year's best-selling series. Greenlit for another season.",
  })

  if (top.length > 0) {
    var rank = []
    // Gold, silver, bronze: one trophy per medal, months joined by the
    // same middle dot the SCREEN SHARE card divides its text with.
    var medals = ["#FFD700", "#C0C0C0", "#CD7F32"]
    for (var r = 0; r < top.length && r < 3; r++) {
      rank.push('<font color="' + medals[r] + '">\uF091</font> ' + top[r].label)
    }
    out.push({
      glyph: "\uF073",
      label: "TOP MONTHS",
      value: rank.join(" \u00B7 "),
      sub: "Your heavy-hitting months, ranked.",
    })
  }

  if (quietest && quietest !== top[0]) {
    out.push({
      glyph: "\uF06C",
      label: "RECHARGE MONTH",
      value:
        quietest.label +
        " \u00b7 " +
        Math.round(quietest.ms / 3600000) +
        "h, the screen's break",
      sub: "Even pixels take a vacation.",
    })
  }

  if (dayTotals.length > 0) {
    var active = activeDayCount(dayTotals, MIN_ACTIVE_DAY_MS)
    var streaks = streakStats(dayTotals)
    var span = trackedDays(dayTotals, year, todayKey)

    // Day-scale cards are computed over real days only ("daySum"), never the
    // year total: month lumps carry no per-day detail, so folding them in
    // would inflate "per active day" and the weekday mix.
    var daySum = 0
    for (var l = 0; l < dayTotals.length; l++) daySum += dayTotals[l].ms

    out.push({
      glyph: "\uF0F3",
      label: "DAY COUNT",
      value: "Active on " + active + " of " + span + " tracked days",
      sub: "Day-one energy that keeps showing up.",
    })

    if (streaks.longest > 1) {
      var endM = Number(String(streaks.longestEnd).split("-")[1]) - 1
      out.push({
        glyph: "\uF06D",
        label: "LONGEST STREAK",
        value: streaks.longest + " days in a row",
        sub: "Your lock-in stretch peaked in " + MONTH_NAMES[endM] + ".",
      })
    }

    var peakKey = ""
    var peakMs = 0
    for (var q = 0; q < dayTotals.length; q++)
      if (dayTotals[q].ms > peakMs) {
        peakMs = dayTotals[q].ms
        peakKey = dayTotals[q].date
      }
    var pp = String(peakKey).split("-")
    out.push({
      glyph: "\uF2D0",
      label: "PEAK DAY",
      value:
        MONTH_NAMES[Number(pp[1]) - 1] +
        " " +
        Number(pp[2]) +
        " \u00b7 " +
        fmt(peakMs) +
        ", the year's high",
      sub: "A new personal record. Nothing above it.",
    })

    var brk = longestBreak(dayTotals)
    if (brk) {
      var endM = Number(String(brk.end).split("-")[1]) - 1
      out.push({
        glyph: "\uF04C",
        label: "LONGEST BREAK",
        value: brk.days + " days offline",
        sub: "Back on screens in " + MONTH_NAMES[endM] + ". Nature is healing.",
      })
    }

    var span = busiestSpan(dayTotals)
    if (span) {
      var sp = String(span.start).split("-")
      var ep = String(span.end).split("-")
      var spanLabel = MONTH_NAMES[Number(sp[1]) - 1] + " " + Number(sp[2])
      spanLabel +=
        Number(sp[1]) === Number(ep[1])
          ? "\u2013" + Number(ep[2])
          : " \u2013 " + MONTH_NAMES[Number(ep[1]) - 1] + " " + Number(ep[2])
      out.push({
        glyph: "\uF091",
        label: "BUSIEST WEEK",
        value: spanLabel + " \u00b7 " + fmt(span.ms) + ", your peak week",
        sub: "Rest was not on the schedule.",
      })
    }

    if (active > 0) {
      out.push({
        glyph: "\uF2F1",
        label: "AVERAGE SCREEN DAY",
        value: fmt(Math.round(daySum / active)) + " per active day",
        sub: "A solid daily shift, no overtime attitude.",
      })

      var wd = weekdayPattern(dayTotals, daySum)
      out.push({
        glyph: "\uF0E7",
        label: "WEEKDAY RHYTHM",
        value: wd.top + " leads \u00b7 " + wd.weekdayPct + "% weekdays",
        sub: "Midweek is your sweet spot.",
      })
    }
  }

  var palette = sliceColors(out.length, accentHex || "#e45b93")
  for (var n = 0; n < out.length; n++) out[n].color = palette[n]

  return out
}

// Header total, month bars and retro cards share one merge.
function yearView(days, months, years, year, todayKey, accentHex) {
  year = Number(year)
  var summary = yearSummary(days, months, years, year, todayKey)
  var facts = yearFactsFromSummary(summary, year, todayKey, accentHex)
  var monthsActive = 0
  for (var m = 0; m < summary.months.length; m++) {
    if (summary.months[m].ms > 0) monthsActive++
  }
  return {
    totalMs: summary.total,
    totalLabel: Math.round(summary.total / 3600000) + "h",
    months: summary.months,
    monthsActive: monthsActive,
    facts: facts,
  }
}

// Node-style exports only so `node --test` can drive these pure functions;
// QML's JS engine never defines `module`, so this guard is inert there.
if (typeof module !== "undefined" && module && module.exports) {
  module.exports = {
    pad2: pad2,
    qmlBrowserAliases: qmlBrowserAliases,
    canonicalApp: canonicalApp,
    displayName: displayName,
    parseIgnoredApps: parseIgnoredApps,
    isIgnoredApp: isIgnoredApp,
    parseAppAliases: parseAppAliases,
    aliasApp: aliasApp,
    resolveAppName: resolveAppName,
    filterIgnoredDay: filterIgnoredDay,
    refoldDay: refoldDay,
    ignoredWith: ignoredWith,
    ignoredWithout: ignoredWithout,
    aliasPairs: aliasPairs,
    serializeAliases: serializeAliases,
    aliasesWith: aliasesWith,
    aliasesWithout: aliasesWithout,
    DAILY_GOAL_PRESETS: DAILY_GOAL_PRESETS,
    parseDailyGoalHours: parseDailyGoalHours,
    goalProgress: goalProgress,
    GOAL_LOG_MAX: GOAL_LOG_MAX,
    parseGoalLog: parseGoalLog,
    goalForDay: goalForDay,
    logGoalChange: logGoalChange,
    APP_DETAIL_DAYS: APP_DETAIL_DAYS,
    WEEK_COUNT_OPTIONS: WEEK_COUNT_OPTIONS,
    parseWeekCount: parseWeekCount,
    minKeepDays: minKeepDays,
    storageSummary: storageSummary,
    storageLabel: storageLabel,
    isHexColor: isHexColor,
    normalizeHex: normalizeHex,
    isDayKey: isDayKey,
    isMonthKey: isMonthKey,
    keyToDate: keyToDate,
    themeSwatches: themeSwatches,
    pickSwatch: pickSwatch,
    sanitizeHistory: sanitizeHistory,
    sanitizeDay: sanitizeDay,
    numMs: numMs,
    dayFor: dayFor,
    dayKey: dayKey,
    newDay: newDay,
    fmt: fmt,
    fmtDelta: fmtDelta,
    fmtWords: fmtWords,

    appList: appList,
    DONUT_MAX_SLICES: DONUT_MAX_SLICES,
    DONUT_MIN_PCT: DONUT_MIN_PCT,
    totalFor: totalFor,
    prevKey: prevKey,
    relativeDayLabel: relativeDayLabel,
    weekdayLabel: weekdayLabel,
    formatDate: formatDate,
    weekKeys: weekKeys,
    busiestWeekDay: busiestWeekDay,
    weekTrend: weekTrend,
    weekTotal: weekTotal,
    isRecordWeek: isRecordWeek,
    bestWeekOffset: bestWeekOffset,
    pruneDays: pruneDays,
    insights: insights,
    groupedApps: groupedApps,
    hexToHsl: hexToHsl,
    hslToHex: hslToHex,
    sliceColors: sliceColors,
    insightColors: insightColors,
    arcSegments: arcSegments,
    weekStartMonday: weekStartMonday,
    isoWeekNumber: isoWeekNumber,
    firstDataYear: firstDataYear,
    msUntilNextHour: msUntilNextHour,
    monSunWeeks: monSunWeeks,
    weekRangeLabel: weekRangeLabel,
    scrollableTrendMax: scrollableTrendMax,
    weekView: weekView,
    weekAxisTicks: weekAxisTicks,
    fmtWholeHours: fmtWholeHours,
    mergeYear: mergeYear,
    yearSummary: yearSummary,
    applyRetention: applyRetention,
    monthlyTotals: monthlyTotals,
    yearTotal: yearTotal,
    sanitizeYears: sanitizeYears,
    MIN_ACTIVE_DAY_MS: MIN_ACTIVE_DAY_MS,
    monthCoverage: monthCoverage,
    pctStr: pctStr,
    yearHours: yearHours,
    yearDayTotals: yearDayTotals,
    activeDayCount: activeDayCount,
    streakStats: streakStats,
    longestBreak: longestBreak,
    busiestSpan: busiestSpan,
    mondayKey: mondayKey,
    weekdayNumber: weekdayNumber,
    weekdayPattern: weekdayPattern,
    trackedDays: trackedDays,
    rollupArchive: rollupArchive,
    yearFacts: yearFacts,
    yearFactsFromSummary: yearFactsFromSummary,
    yearView: yearView,
  }
}
