// Pure JS helpers for the screen-time plugin: day keys, time formatting,
// per-app aggregation, and the small set of usage heuristics shown as
// insights. No Qt imports here so the functions stay testable in isolation.

function pad2(n) {
  n = Math.floor(n)
  return n < 10 ? "0" + n : String(n)
}

// Canonical tracking keys for multi-process browsers. A browser launched
// from a terminal resolves to its binary name (e.g. "zen-bin"), and its
// subprocesses can leak process names (Web Content, forkserver, …). Screen
// time must fold all of those into the single per-app key, otherwise a
// browser shows up as several individual rows.
//
// Canonical copy: lib/browser_aliases.json. Node require()s it directly;
// scripts/resolve_app.py loads it at runtime. QML cannot read the file
// synchronously (Quickshell's XHR blocks local files and Qt.include() is
// deprecated), so qmlBrowserAliases() mirrors the data as a literal — a
// Node test asserts the mirror matches the JSON so the two can never
// silently drift.
var BROWSER_ALIASES = (function () {
  if (typeof module !== "undefined" && module && module.exports)
    return require("./browser_aliases.json")
  return qmlBrowserAliases()
})()

// QML mirror of lib/browser_aliases.json. Keep in sync with that file;
// tests/model.test.js fails if this lags a change.
function qmlBrowserAliases() {
  return {"zen-bin":"zen","zen_browser":"zen","zen":"zen","firefox":"firefox",
    "librewolf":"librewolf","waterfox":"waterfox","tor-browser":"tor-browser",
    "mullvad-browser":"mullvad-browser","google-chrome":"google-chrome",
    "chrome":"google-chrome","chromium":"chromium","brave":"brave",
    "brave-browser":"brave","vivaldi":"vivaldi","microsoft-edge":"microsoft-edge",
    "edge":"microsoft-edge"}
}

var CHROMIUM_WEB_APP_RE = /^((?:chrome|chromium|brave|msedge|vivaldi)-([a-z0-9](?:[a-z0-9.-]*[a-z0-9])?))(__.*-(?:Default|Profile_[0-9]+))?$/i

// Map any app name to its canonical tracking key. Unknown names pass
// through unchanged so non-browser apps keep their own identity.
function canonicalApp(name) {
  if (!name) return ""
  var key = String(name)
  if (BROWSER_ALIASES && Object.prototype.hasOwnProperty.call(BROWSER_ALIASES, key))
    return BROWSER_ALIASES[key]
  var webApp = key.match(CHROMIUM_WEB_APP_RE)
  if (webApp && webApp[3]) return webApp[1]
  return key
}

// Human-readable label for the panel. Chromium site windows are reduced
// to their hostname, reverse-DNS app IDs from the compositor (e.g.
// "com.github.user.Codium") are shortened to the last segment and
// lowercased, and plain binary names pass through unchanged.
// Steam window classes (e.g. "steam_app_730") arrive already resolved to
// game titles by scripts/resolve_app.py; unresolved ones fall through to
// the plain-name path. This layer never touches the filesystem: QML's JS
// engine has no require(), so fs-based lookups would throw at runtime.
function displayName(app) {
  if (!app) return ""
  var s = String(app)

  var webApp = s.match(CHROMIUM_WEB_APP_RE)
  if (webApp) return webApp[2].toLowerCase()

  if (!/^(?:[a-z][a-z0-9-]*\.){2,}[a-z0-9_-]+$/i.test(s))
    return s.toLowerCase()
  var last = s.split(".").pop()
  if (!last) return s.toLowerCase()
  return last.charAt(0).toLowerCase() + last.slice(1).toLowerCase()
}

// Guards against a hand-edited or corrupted history file: only plain
// objects are accepted for days/months. Arrays pass a typeof "object"
// check but are not valid history containers; anything malformed falls
// back to empty so tracking starts clean instead of failing later.
function isPlainObject(v) {
  return !!v && typeof v === "object" && !Array.isArray(v)
}

function sanitizeHistory(days, months, years) {
  var cleanDays = isPlainObject(days) ? days : {}
  var rebuilt = false
  var out = {}
  for (var k in cleanDays) {
    if (!Object.prototype.hasOwnProperty.call(cleanDays, k)) continue
    var fixed = sanitizeDay(cleanDays[k])
    out[k] = fixed.day
    if (fixed.changed) rebuilt = true
  }
  return {
    days: rebuilt ? out : cleanDays,
    months: isPlainObject(months) ? months : {},
    years: sanitizeYears(years)
  }
}

// Cleans one history day ({ total, apps }): totals become finite ms >= 0,
// app maps become plain objects of finite ms >= 0. Returns
// { day, changed } so callers can keep the original object (by identity)
// when nothing was discarded.
function sanitizeDay(d) {
  if (!isPlainObject(d)) return { day: newDay(), changed: true }
  var total = Number(d.total) || 0
  if (!isFinite(total) || total < 0) total = 0
  var apps = isPlainObject(d.apps) ? d.apps : {}
  var cleanApps = {}
  var appsChanged = apps !== d.apps
  for (var app in apps) {
    if (!Object.prototype.hasOwnProperty.call(apps, app)) continue
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
    if (!isPlainObject(years[yk])) { rebuilt = true; continue }
    var day = {}
    var dayChanged = false
    for (var dk in years[yk]) {
      if (!Object.prototype.hasOwnProperty.call(years[yk], dk)) continue
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

// Local-time calendar key, e.g. "2026-08-13".
function dayKey(date) {
  return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
}

function newDay() {
  return { total: 0, apps: {} }
}

// Compact human duration: "0m", "45s", "23m", "3h", "2h 14m".
function fmt(ms) {
  ms = Math.max(0, Math.round(Number(ms) || 0))
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
  ms = Math.max(0, Math.round(Number(ms) || 0))
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
    out.push({ app: app, ms: ms, pct: total > 0 ? Math.round(100 * ms / total) : 0 })
  }
  out.sort(function(a, b) { return b.ms - a.ms })
  return out
}

// Beyond maxSlices the tail collapses into a single "Other" slice. Any
// app below minPct percent is also folded into Other even if it would
// otherwise be within the top maxSlices. The percentage of the bucket is
// recomputed from its own accumulated ms, never by summing rounded slice
// percentages. Both params must be passed explicitly: QML's JS engine has
// no default parameters, and undefined would silently collapse every app.
var DONUT_MAX_SLICES = 6
var DONUT_MIN_PCT = 3
// Floor for the week bar-graph y-axis: sparse weeks stay legible by never
// squashing their axis below a 4-hour reference even when every day is small.
var TREND_REF_MS = 4 * 3600000
function groupedApps(apps, maxSlices, minPct) {
  var list = apps || []
  var max = typeof maxSlices === "number" ? maxSlices : DONUT_MAX_SLICES
  var floor = typeof minPct === "number" ? minPct : DONUT_MIN_PCT
  var total = 0
  for (var j = 0; j < list.length; j++) total += Number(list[j].ms) || 0
  var head = []
  var tailMs = 0
  for (var i = 0; i < list.length; i++) {
    var pct = total > 0 ? (Number(list[i].ms) || 0) / total * 100 : 0
    if (head.length < max - 1 && pct >= floor) {
      head.push(list[i])
    } else {
      tailMs += Number(list[i].ms) || 0
    }
  }
  if (tailMs > 0) {
    var other = { app: "Other", ms: tailMs, pct: total > 0 ? Math.round(100 * tailMs / total) : 0 }
    head.push(other)
  }
  return head
}

function totalFor(days, key) {
  var d = days && days[key]
  return d && d.total ? d.total : 0
}

function prevKey(key) {
  if (!key) return ""
  var parts = String(key).split("-")
  if (parts.length !== 3) return ""
  var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
  if (isNaN(d.getTime())) return ""
  d.setDate(d.getDate() - 1)
  return dayKey(d)
}

var WEEKDAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// Full date label for a dayKey, e.g. "Aug 15".
function formatDate(key) {
  if (!key) return ""
  var parts = String(key).split("-")
  if (parts.length !== 3) return ""
  var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
  if (isNaN(d.getTime())) return ""
  return MONTH_NAMES[d.getMonth()] + " " + d.getDate()
}

// Short weekday name for any key, e.g. "Mon".  Unlike relativeDayLabel
// this never returns "Today" or "Yesterday".
function weekdayLabel(key) {
  if (!key) return ""
  var parts = String(key).split("-")
  if (parts.length !== 3) return ""
  var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
  if (isNaN(d.getTime())) return ""
  return WEEKDAY_NAMES[d.getDay()]
}

// Weekday label for a dayKey relative to today: "Today", "Yesterday", or
// the short weekday name.

function relativeDayLabel(key, todayKey) {
  if (!key) return ""
  if (key === todayKey) return "Today"
  if (key === prevKey(todayKey)) return "Yesterday"
  var parts = String(key).split("-")
  if (parts.length !== 3) return ""
  var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
  if (isNaN(d.getTime())) return ""
  return WEEKDAY_NAMES[d.getDay()]
}

// Last 7 day keys ending at todayKey, oldest first.
function weekKeys(todayKey) {
  if (!todayKey) return []
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
  if (!todayKey) return []
  var keys = weekKeys(todayKey)
  var out = []
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i]
    var parts = String(key).split("-")
    out.push({
      key: key,
      ms: totalFor(days, key),
      label: WEEKDAY_NAMES[new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])).getDay()],
      isToday: key === todayKey
    })
  }
  return out
}

// Total focused time across a weekTrend list.
function weekTotal(trend) {
  var total = 0
  var list = Array.isArray(trend) ? trend : []
  for (var i = 0; i < list.length; i++) total += Number(list[i].ms) || 0
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

// Drops history older than keepDays (cutoff = todayKey - (keepDays - 1)).
// Keys are ISO "YYYY-MM-DD", so plain string comparison orders them
// correctly. Returns the original object when nothing is pruned so callers
// can avoid needless object churn on every persist.
function pruneDays(days, todayKey, keepDays) {
  if (!days || !(keepDays >= 1)) return days
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

// Ordered list of insight rows: [{ label, value, kind, dir }]. Always
// returns three rows; missing data shows "—" placeholders. kind is
// "top" | "delta" | "busiest"; dir is "up" | "down" | "flat" for deltas,
// null otherwise. weekEndKey anchors the
// "Busiest day (7d)" row: pass the visible week's Sunday so it follows week
// navigation instead of staying on the current week. Defaults to todayKey.
function insights(day, days, todayKey, activeKey, weekEndKey) {
  var key = activeKey || todayKey
  var isToday = key === todayKey
  var dayLabel = isToday ? "" : " (" + weekdayLabel(key) + ")"
  var total = day && day.total ? day.total : 0

  var apps = appList(day)
  var topApp = apps.length ? apps[0] : null
  var topLabel = topApp
    ? displayName(topApp.app) + " \u00b7 " + "(" + topApp.pct + "%)" + " \u00b7 " + fmt(topApp.ms)
    : "\u2014"
  // Rows carry kind + dir so the panel renders meaning without parsing
  // label text: kind is "top" | "delta" | "busiest", dir is
  // "up" | "down" | "flat" for deltas and null otherwise.
  var list = [{
    label: isToday ? "Top app" : "Top app " + weekdayLabel(key),
    value: topLabel,
    kind: "top",
    dir: null
  }]

  var compareKey = prevKey(key)
  var compareTotal = totalFor(days, compareKey)
  var delta = total - compareTotal
  var compareLabel = compareTotal > 0
    ? fmtDelta(delta)
    : "\u2014"
  var vsLabel = isToday ? "vs Yesterday" : "vs " + weekdayLabel(compareKey)
  list.push({
    label: vsLabel,
    value: compareLabel,
    kind: "delta",
    dir: compareTotal > 0 ? (delta > 0 ? "up" : delta < 0 ? "down" : "flat") : null
  })

  var busiest = busiestWeekDay(days, weekEndKey || todayKey)
  var busiestLabel = busiest.total > 0
    ? weekdayLabel(busiest.key) + " \u00b7 " + fmt(busiest.total)
    : "\u2014"
  list.push({ label: "Busiest day (7d)", value: busiestLabel, kind: "busiest", dir: null })

  return list
}

// ---- Donut chart helpers -----------------------------------------------

// #rrggbb -> { h: 0-360, s: 0-100, l: 0-100 }.
function hexToHsl(hex) {
  var m = /^#?([0-9a-fA-F]{6})$/.exec(String(hex || "").replace(/^\s+|\s+$/g, ""))
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
  var x = c * (1 - Math.abs((h / 60) % 2 - 1))
  var m = l - c / 2
  var r = 0
  var g = 0
  var b = 0
  if (h < 60) { r = c; g = x }
  else if (h < 120) { r = x; g = c }
  else if (h < 180) { g = c; b = x }
  else if (h < 240) { g = x; b = c }
  else if (h < 300) { r = x; b = c }
  else { r = c; b = x }
  function ch(v) {
    var t = Math.max(0, Math.min(255, Math.round((v + m) * 255)))
    return (t < 16 ? "0" : "") + t.toString(16)
  }
  return "#" + ch(r) + ch(g) + ch(b)
}

// Donut slice colors for n apps. Hue rotates away from the theme accent so
// slices stay distinguishable while the palette follows theme swaps. For a
// near-grayscale accent there is no hue to lean on, so a fixed lightness
// ramp that always fits the usable band guarantees distinct shades whether
// the accent is near-white or near-black.
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

// Glyph colors for the insights rows, derived from the theme so they track
// accent/urgent swaps: star = accent, up = urgent (theme red), down = green
// carrying the accent's saturation and lightness, busiest = accent hue + 80.
// The shell theme exposes no green role, so down is fixed at hue 155. On a
// near-grayscale accent there is no saturation to borrow, so a fixed vivid
// level keeps down and busiest distinguishable (same approach as the
// GRAY_RAMP in sliceColors).
function insightColors(accentHex, urgentHex) {
  var base = hexToHsl(accentHex)
  var upHsl = hexToHsl(urgentHex)
  var vivid = base.s < 12 ? 55 : base.s
  var level = Math.max(32, Math.min(78, base.l))
  return {
    star: hslToHex(base.h, base.s, base.l),
    up: hslToHex(upHsl.h, upHsl.s, upHsl.l),
    down: hslToHex(155, vivid, level),
    busiest: hslToHex(base.h + 80, vivid, level)
  }
}

// Donut segments for a sorted app list: [{ app, ms, pct, startAngle,
// sweepAngle }]. Angles start at 12 o'clock (sweep 0 = -90deg) and go
// clockwise; a small gap separates slices. A single app owns the full circle.
var ARC_GAP_DEG = 1.5
function arcSegments(apps) {
  var list = apps || []
  var total = 0
  for (var i = 0; i < list.length; i++) total += Number(list[i].ms) || 0
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
      sweepAngle: sweep
    })
    angle += frac * 360
  }
  return out
}

// ---- Scrollable Mon-Sun bar graph helpers --------------------------------

// Returns the Monday of the ISO week containing `key`.
function weekStartMonday(key) {
  if (!key) return ""
  var parts = String(key).split("-")
  if (parts.length !== 3) return ""
  var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
  if (isNaN(d.getTime())) return ""
  var day = d.getDay()
  var diff = (day === 0 ? -6 : 1) - day
  d.setDate(d.getDate() + diff)
  return dayKey(d)
}

// ISO-8601 week number (Mon=1 .. Sun=7 weeks, W1 holds the first Thursday).
// Returns 0 for input that does not parse as a YYYY-MM-DD key.
function isoWeekNumber(key) {
  var parts = String(key).split("-")
  if (parts.length !== 3) return 0
  var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
  if (isNaN(d.getTime())) return 0
  // Shift to the week's Thursday: ISO years are identified by that day.
  var target = new Date(d.valueOf())
  target.setDate(target.getDate() - ((d.getDay() + 6) % 7) + 3)
  // The Thursday of the week containing Jan 4 is always in ISO week 1.
  var firstThursday = new Date(target.getFullYear(), 0, 4)
  firstThursday.setDate(firstThursday.getDate() - ((firstThursday.getDay() + 6) % 7) + 3)
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
  for (var yk in (years || {})) {
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
  return (3600 - d.getMinutes() * 60 - d.getSeconds()) * 1000 - d.getMilliseconds()
}

// Mon-Sun aligned weeks for the scrollable bar graph. Returns an array of
// `weekCount` week objects, newest first. Each week:
//   { month: "Aug", days: [{ key, ms, label, isEmpty, isFuture, isToday }] }
// Mon = index 0, Sun = index 6. Future days in the current week are flagged
// so the UI can render faint stubs.
function monSunWeeks(days, todayKey, weekCount) {
  if (!todayKey || weekCount <= 0) return []
  var weeks = []
  var monStart = weekStartMonday(todayKey)
  if (!monStart) return []
  for (var w = 0; w < weekCount; w++) {
    var weekDays = []
    var monthCounts = {}
    for (var di = 0; di < 7; di++) {
      var dParts = String(monStart).split("-")
      var dObj = new Date(Number(dParts[0]), Number(dParts[1]) - 1, Number(dParts[2]) + di)
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
        isToday: dk === todayKey
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
    var mObj = new Date(Number(mParts[0]), Number(mParts[1]) - 1, Number(mParts[2]) - 7)
    monStart = dayKey(mObj)
  }
  return weeks
}

// Header label for one monSunWeeks week: its Mon–Sun date range plus the
// ISO week number, e.g. "Aug 17 – 23, 2026 · W34". Same-month weeks collapse
// the repeated month; cross-year weeks name both years. Accepts either the
// week object ({ days: [{ key } x7] }) or a bare 7-entry days array. Returns
// "" for anything else so the header stays blank instead of showing garbage.
function weekRangeLabel(week) {
  var days = week && week.days ? week.days : week
  if (!days || days.length !== 7) return ""
  var startKey = days[0] && days[0].key ? String(days[0].key) : ""
  var endKey = days[6] && days[6].key ? String(days[6].key) : ""
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
    range = MONTH_NAMES[sm] + " " + sDate.getDate() + " – " + eDate.getDate() + ", " + sy
  } else if (sy === ey) {
    range = MONTH_NAMES[sm] + " " + sDate.getDate() + " – "
      + MONTH_NAMES[em] + " " + eDate.getDate() + ", " + sy
  } else {
    range = MONTH_NAMES[sm] + " " + sDate.getDate() + ", " + sy + " – "
      + MONTH_NAMES[em] + " " + eDate.getDate() + ", " + ey
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
  for (var i = 0; i < weeks.length; i++) {
    var days = weeks[i].days
    for (var j = 0; j < days.length; j++) {
      var ms = Number(days[j].ms) || 0
      if (ms > max) max = ms
    }
  }
  return max
}

// One derivation for the paginated week trend: the week list plus every
// fact the panel threads separately today (visible week, its max and
// total, the record flag, whether older weeks hold data, and the Sunday
// key anchoring "Busiest day (7d)" to the week on screen). Returns
// { weeks, week, max, totalMs, isRecord, hasPrev, weekEndKey }; week is
// null and the facts are zeroed when offset is out of range.
function weekView(days, todayKey, weekCount, offset) {
  var weeks = monSunWeeks(days, todayKey, weekCount)
  var empty = {
    weeks: weeks, week: null, max: 0, totalMs: 0,
    isRecord: false, hasPrev: false, weekEndKey: ""
  }
  if (offset < 0 || offset >= weeks.length) return empty
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
      if ((Number(prev[j].ms) || 0) > 0) { hasPrev = true; break }
    }
    if (hasPrev) break
  }
  return {
    weeks: weeks,
    week: week,
    max: max,
    totalMs: weekTotal(wdays),
    isRecord: isRecordWeek(weeks, offset),
    hasPrev: hasPrev,
    weekEndKey: wdays.length === 7 ? String(wdays[6].key || "") : ""
  }
}

// Y-axis gridlines for the week bar graph: baseline, midpoint and the top
// of the scale. Ticks are anchored to max(weekMax, TREND_REF_MS) — the same
// value the bars scale against — so the busiest bar keeps its full height
// and never gets silently shrunk by an over-tall rounded ladder.
function weekAxisTicks(weekMax) {
  var max = Number(weekMax)
  if (weekMax === null || weekMax === "" || !(max >= 0)) return []
  var ref = Math.max(max, TREND_REF_MS)
  // The mid gridline label renders as whole hours, so the tick sits on a
  // whole hour too — never 2.5h with a "3h" label.
  var half = Math.round(ref / 2 / 3600000) * 3600000
  return [0, half, ref]
}

// Whole-hour approximation for week-axis tick labels: the ticks stay at
// exact fractions of the week's peak, but their labels render as round hour
// figures ("0h", "2h", "6h") so the axis reads cleanly at a glance. Exact
// durations remain available in tooltips and the hero.
function fmtWholeHours(ms) {
  ms = Math.max(0, Number(ms) || 0)
  return Math.round(ms / 3600000) + "h"
}

// ---- Calendar view helpers -----------------------------------------------

// Monthly totals for a given year. Returns 12 objects:
//   { month: 0-11, label: "Jan", ms: number, hours: "156h" }
// Merges raw `days` (recent data within keepDays) with persisted `months`
// aggregates (historical data beyond keepDays). The `months` object maps
// "YYYY-MM" keys to cumulative ms totals.
// Coerces a possibly hand-edited total to finite ms >= 0: string totals
// must add, never concatenate ("0" + "100" = "0100").
function numMs(v) {
  var n = Number(v)
  return isFinite(n) && n > 0 ? n : 0
}

// Single merge point for one calendar year across the three stores (raw
// `days`, legacy `months` lumps, per-day `years` archive). The stores are
// disjoint by construction: nothing writes `months` anymore, and a day is
// deleted into exactly one store, so a lump and archive days sharing a
// month always describe different days — both are kept. Returns
// { monthMs: [12 numbers], dayTotals: [{ date, ms }] } with dayTotals in
// ascending calendar order and future dates (beyond todayKey) excluded.
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
      hours: Math.round(merged.monthMs[m] / 3600000) + "h"
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

// Per-day screen-time archive: a whole calendar year of day totals kept in
// per-day aggregates ({ "YYYY": { "YYYY-MM-DD": ms } }) so retro facts — day
// counts, streaks, weekday rhythm, peak day — stay computable after the
// 95-day raw-detail window prunes the app breakdown. Retained for the current
// and previous calendar year only, and consumed as the single source of
// truth: pruned days go here instead of the month lumps.
var YEAR_HOURS = 8760
var YEAR_HOURS_LEAP = 8784
var MIN_ACTIVE_DAY_MS = 60 * 1000
// Tracked days a current month needs before it can be RECHARGE MONTH.
var MIN_RECHARGE_DAYS = 14

// Days with data in one year-month of a yearDayTotals list.
function monthCoverage(dayTotals, year, month) {
  var n = 0
  for (var i = 0; i < dayTotals.length; i++) {
    var p = String(dayTotals[i].date).split("-")
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
function pctStr(ms, divisorMs) {
  var v = Math.round(Number(ms) / divisorMs * 1000) / 10
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
  for (var i = 0; i < dayTotals.length; i++)
    if (dayTotals[i].ms >= minMs) n++
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
  for (var i = 0; i < dayTotals.length; i++) {
    var t = dayMsUtc(dayTotals[i].date)
    run = (prevMs !== null && t - prevMs === 86400000) ? run + 1 : 1
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
    lastActive: lastActive
  }
}

// Longest offline gap between tracked days: { days, end } where end is the
// return date. Single missed days don't count as a break. Null when fewer
// than two days are on record.
function longestBreak(dayTotals) {
  if (!dayTotals || dayTotals.length < 2) return null
  var best = null
  for (var i = 1; i < dayTotals.length; i++) {
    var gap = Math.round((dayMsUtc(String(dayTotals[i].date))
      - dayMsUtc(String(dayTotals[i - 1].date))) / 86400000) - 1
    if (gap >= 2 && (!best || gap > best.days))
      best = { days: gap, end: String(dayTotals[i].date) }
  }
  return best
}

// Monday key of the Mon–Sun week a "YYYY-MM-DD" date belongs to (local
// days, same week definition as the trend graph).
function mondayKey(key) {
  var p = String(key).split("-")
  var dt = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
  var mon = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate() - ((dt.getDay() + 6) % 7))
  return mon.getFullYear() + "-" + pad2(mon.getMonth() + 1) + "-" + pad2(mon.getDate())
}

// Peak Mon–Sun week: { start, end, ms } with Monday/Sunday keys. Days group
// into their real weeks, so a hot Sunday can't drag six quiet days into a
// fake rolling crown. Null without data; earliest week wins ties.
function busiestSpan(dayTotals) {
  if (!dayTotals || dayTotals.length === 0) return null
  var sums = {}
  for (var i = 0; i < dayTotals.length; i++) {
    var ms = Number(dayTotals[i].ms) || 0
    if (ms <= 0) continue
    var mon = mondayKey(String(dayTotals[i].date))
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
        end: end.getFullYear() + "-" + pad2(end.getMonth() + 1) + "-" + pad2(end.getDate()),
        ms: sums[k]
      }
    }
  }
  return best
}

// Busiest weekday and the share of total ms landing Monday-Friday.
function weekdayPattern(dayTotals, totalMs) {
  var sums = [0, 0, 0, 0, 0, 0, 0]
  var wdSum = 0
  for (var i = 0; i < dayTotals.length; i++) {
    var p = String(dayTotals[i].date).split("-")
    var day = new Date(Date.UTC(Number(p[0]), Number(p[1]) - 1, Number(p[2]))).getUTCDay()
    sums[day] += dayTotals[i].ms
    if (day >= 1 && day <= 5) wdSum += dayTotals[i].ms
  }
  var topI = 0
  for (var w = 1; w < 7; w++) if (sums[w] > sums[topI]) topI = w
  return { top: WEEKDAY_NAMES[topI], weekdayPct: Math.round(wdSum / totalMs * 100) }
}

// Honest "active on N of D days" denominator: the calendar span from the
// first recorded day to today for the ongoing year, the full year otherwise.
function trackedDays(dayTotals, year, todayKey) {
  var thisYear = todayKey ? Number(String(todayKey).split("-")[0]) : NaN
  if (Number(year) !== thisYear)
    return Math.round((Date.UTC(Number(year) + 1, 0, 1) - Date.UTC(Number(year), 0, 1)) / 86400000)
  var first = String(dayTotals[0].date)
  return Math.round((dayMsUtc(String(todayKey)) - dayMsUtc(first)) / 86400000) + 1
}

// Rolls days dropped by the retention window into the per-day archive. Only
// the total survives — the app breakdown never leaves the 95-day window.
function rollupArchive(years, prunedDays) {
  if (!prunedDays) return years || {}
  var out = Object.assign({}, years || {})
  for (var dk in prunedDays) {
    if (!Object.prototype.hasOwnProperty.call(prunedDays, dk)) continue
    var d = prunedDays[dk]
    var total = d && d.total ? d.total : 0
    if (total <= 0) continue
    var parts = String(dk).split("-")
    if (parts.length !== 3) continue
    var yearObj = out[parts[0]] ? Object.assign({}, out[parts[0]]) : {}
    yearObj[dk] = total
    out[parts[0]] = yearObj
  }
  return out
}

// Bounds the archive to the current and previous calendar year.
function pruneArchive(years, year) {
  if (!years) return {}
  var keep = {}
  var y = Number(year)
  for (var yk in years) {
    if (!Object.prototype.hasOwnProperty.call(years, yk)) continue
    var n = Number(yk)
    if (n === y || n === y - 1) keep[yk] = years[yk]
  }
  return keep
}

// Retention in one step: prune days older than keepDays and roll the
// dropped days into the per-day archive. Returns { days, years, pruned };
// when nothing is pruned the inputs come back by identity so callers can
// skip mirror churn.
function applyRetention(days, years, todayKey, keepDays, year) {
  var kept = pruneDays(days, todayKey, keepDays)
  if (kept === days) return { days: days, years: years, pruned: false }
  var pruned = {}
  for (var k in days) {
    if (Object.prototype.hasOwnProperty.call(days, k)
      && !Object.prototype.hasOwnProperty.call(kept, k)) pruned[k] = days[k]
  }
  return {
    days: kept,
    years: pruneArchive(rollupArchive(years, pruned), year),
    pruned: true
  }
}

// Scroll-of-truth yearly retro: a whole year made of real day data. Each card
// is { glyph, label, value, sub, color }. Day-scale cards only appear when
// the per-day archive (or the live window) covers the year — months-only
// years fall back to the month-scale trio.
// accentHex is the theme accent ("#rrggbb"): card glyphs take one
// sliceColors shade each, in order, so the retro follows theme swaps.
// When omitted the cards fall back to a fixed accent instead of the old
// hand-picked rainbow hexes.
function yearFacts(days, months, years, year, todayKey, accentHex) {
  // Normalize once: downstream strict compares (recharge guard, coverage)
  // must not treat "2026" as a different year from 2026.
  year = Number(year)
  return yearFactsFromSummary(
    yearSummary(days, months, years, year, todayKey), year, todayKey, accentHex)
}

// Retro cards from an already-merged yearSummary. Lets readers that
// already paid for the merge (like yearView) share it instead of each
// merging the three stores again.
function yearFactsFromSummary(summary, year, todayKey, accentHex) {
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
  top.sort(function (a, b) { return b.ms - a.ms })

  // Recharge candidates: a brand-new month trivially has the least time,
  // so the current month only counts with two weeks of tracked days behind
  // it. With no older months on record it still counts — whatever data
  // exists is all there is.
  var tk = String(todayKey || "").split("-")
  var tkYear = Number(tk[0])
  var tkMonth = Number(tk[1]) - 1
  var pool = []
  for (var q = 0; q < top.length; q++) {
    if (year !== tkYear || top[q].month !== tkMonth
      || monthCoverage(dayTotals, year, top[q].month) >= MIN_RECHARGE_DAYS)
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
    value: totalH + "h on screens \u00b7 "
      + pctStr(total, yearHours(year) * 3600000) + " of " + year,
    sub: "The year's best-selling series. Greenlit for another season."
  })

  if (top.length > 0) {
    var rank = []
    for (var r = 0; r < top.length && r < 3; r++)
      rank.push(top[r].label)
    out.push({
      glyph: "\uF0E7",
      label: "TOP MONTHS",
      value: rank.join(" \u25CF "),
      sub: "Your heavy-hitting months, ranked."
    })
  }

  if (quietest && quietest !== top[0]) {
    out.push({
      glyph: "\uF06C",
      label: "RECHARGE MONTH",
      value: quietest.label + " \u00b7 " + Math.round(quietest.ms / 3600000) + "h, the screen's break",
      sub: "Even pixels take a vacation."
    })
  }

  if (dayTotals.length > 0) {
    var active = activeDayCount(dayTotals, MIN_ACTIVE_DAY_MS)
    var streaks = streakStats(dayTotals)
    var span = trackedDays(dayTotals, year, todayKey)

    // Day-scale cards are computed over real days only ("daySum"), never the
    // year total: month lumps from before the archive kept no per-day detail,
    // so folding them in would inflate "per active day" and the weekday mix.
    var daySum = 0
    for (var l = 0; l < dayTotals.length; l++) daySum += dayTotals[l].ms

    out.push({
      glyph: "\uF0F3",
      label: "DAY COUNT",
      value: "Active on " + active + " of " + span + " tracked days",
      sub: "Day-one energy that keeps showing up."
    })

    if (streaks.longest > 1) {
      var endM = Number(String(streaks.longestEnd).split("-")[1]) - 1
      out.push({
        glyph: "\uF06D",
        label: "LONGEST STREAK",
        value: streaks.longest + " days in a row",
        sub: "Your lock-in stretch peaked in " + MONTH_NAMES[endM] + "."
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
      value: MONTH_NAMES[Number(pp[1]) - 1] + " " + Number(pp[2])
        + " \u00b7 " + fmt(peakMs) + ", the year's high",
      sub: "A new personal record. Nothing above it."
    })

    var brk = longestBreak(dayTotals)
    if (brk) {
      var endM = Number(String(brk.end).split("-")[1]) - 1
      out.push({
        glyph: "\uF04C",
        label: "LONGEST BREAK",
        value: brk.days + " days offline",
        sub: "Back on screens in " + MONTH_NAMES[endM] + ". Nature is healing."
      })
    }

    var span = busiestSpan(dayTotals)
    if (span) {
      var sp = String(span.start).split("-")
      var ep = String(span.end).split("-")
      var spanLabel = MONTH_NAMES[Number(sp[1]) - 1] + " " + Number(sp[2])
      spanLabel += Number(sp[1]) === Number(ep[1])
        ? "\u2013" + Number(ep[2])
        : " \u2013 " + MONTH_NAMES[Number(ep[1]) - 1] + " " + Number(ep[2])
      out.push({
        glyph: "\uF091",
        label: "BUSIEST WEEK",
        value: spanLabel + " \u00b7 " + fmt(span.ms) + ", your peak week",
        sub: "Rest was not on the schedule."
      })
    }

    if (active > 0) {
      out.push({
        glyph: "\uF2F1",
        label: "AVERAGE SCREEN DAY",
        value: fmt(Math.round(daySum / active)) + " per active day",
        sub: "A solid daily shift, no overtime attitude."
      })

      var wd = weekdayPattern(dayTotals, daySum)
      out.push({
        glyph: "\uF073",
        label: "WEEKDAY RHYTHM",
        value: wd.top + " leads \u00b7 " + wd.weekdayPct + "% weekdays",
        sub: "Midweek is your sweet spot."
      })
    }
  }

  var palette = sliceColors(out.length, accentHex || "#e45b93")
  for (var n = 0; n < out.length; n++) out[n].color = palette[n]

  return out
}

// One derivation for the year view: the header total and the retro cards
// share a single yearSummary merge instead of Panel paying for two (the
// old calendarYearTotal + yearFacts pair merged the three stores twice).
// Returns { totalMs, totalLabel, facts }.
function yearView(days, months, years, year, todayKey, accentHex) {
  year = Number(year)
  var summary = yearSummary(days, months, years, year, todayKey)
  var facts = yearFactsFromSummary(summary, year, todayKey, accentHex)
  return {
    totalMs: summary.total,
    totalLabel: Math.round(summary.total / 3600000) + "h",
    facts: facts
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
    yearDayTotals: yearDayTotals,
    activeDayCount: activeDayCount,
    streakStats: streakStats,
    longestBreak: longestBreak,
    busiestSpan: busiestSpan,
    rollupArchive: rollupArchive,
    pruneArchive: pruneArchive,
    yearFacts: yearFacts,
    yearFactsFromSummary: yearFactsFromSummary,
    yearView: yearView,
  }
}
