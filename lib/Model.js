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
// Single source of truth: lib/browser_aliases.json.  Both this module and
// scripts/resolve_app.py load from that file at runtime.
var BROWSER_ALIASES = (function () {
  if (typeof module !== "undefined" && module && module.exports)
    return require("./browser_aliases.json")
  // Qt.include() is deprecated in Qt 5.15+. Inline the JSON so the file
  // works with both QML's JS engine and Node.js without any deprecated APIs.
  return {"zen-bin":"zen","zen_browser":"zen","zen":"zen","firefox":"firefox",
    "librewolf":"librewolf","waterfox":"waterfox","tor-browser":"tor-browser",
    "mullvad-browser":"mullvad-browser","google-chrome":"google-chrome",
    "chrome":"google-chrome","chromium":"chromium","brave":"brave",
    "brave-browser":"brave","vivaldi":"vivaldi","microsoft-edge":"microsoft-edge",
    "edge":"microsoft-edge"}
})()

// Map any app name to its canonical tracking key. Unknown names pass
// through unchanged so non-browser apps keep their own identity.
function canonicalApp(name) {
  if (!name) return ""
  var key = String(name)
  if (BROWSER_ALIASES && Object.prototype.hasOwnProperty.call(BROWSER_ALIASES, key))
    return BROWSER_ALIASES[key]
  return key
}

// Human-readable label for the panel. Reverse-DNS app IDs from the
// compositor (e.g. "com.github.user.Codium") are shortened to the last
// segment and lowercased; plain binary names pass through unchanged.
// Steam App IDs (e.g. "steam_app_730") are resolved to game titles using
// local Steam metadata first, then cached for future lookups.
function displayName(app) {
  if (!app) return ""
  var s = String(app)

  // Resolve Steam App IDs to game titles
  if (s.indexOf("steam_app_") === 0) {
    var cached = displayName.__steamCache__ && displayName.__steamCache__[s]
    if (cached) return cached
    var title = resolveSteamAppName(s)
    // Cache the result (memoize)
    if (!displayName.__steamCache__) displayName.__steamCache__ = {}
    displayName.__steamCache__[s] = title
    return title
  }

  if (s.indexOf(".") === -1) return s.toLowerCase()
  var last = s.split(".").pop()
  if (!last) return s.toLowerCase()
  return last.charAt(0).toLowerCase() + last.slice(1).toLowerCase()
}

// Steam App ID -> game title resolution using local metadata
function resolveSteamAppName(steamKey) {
  // Extract App ID from "steam_app_APPID"
  var appIdMatch = steamKey.match(/steam_app_(\d+)/i)
  if (!appIdMatch) return steamKey
  var appId = appIdMatch[1]

  // Try local Steam metadata paths
  var pathsToTry = [
    // Path: ~/.steam/steam/appcache/appinfo_v*.acf
    function () { return findAppInAcf(appId) },
    // Path: ~/.steam/steam/steamapps/appmanifest_*.json
    function () { return findAppInManifest(appId) },
    // Fallback: try home/.steam/ or /home/<user>/.local/share/Steam/
    function () { return findAppInUserSteam(appId) }
  ]

  for (var i = 0; i < pathsToTry.length; i++) {
    var result = pathsToTry[i]()
    if (result) return result
  }

  // Could not find metadata, return the original key
  return steamKey
}

// Parse appinfo_v*.acf files for app name
function findAppInAcf(appId) {
  var home = getSteamHome()
  if (!home) return null
  var acfPath = home + "/appcache/appinfo_v7.acf"
  // Read the file and look for the app entry
  try {
    var fs = require("fs")
    var content = fs.readFileSync(acfPath, "utf8")
    // ACF format: "appbcd1234" contains "name" and "apps"
    // Look for "name" near the app ID
    var lines = content.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line.indexOf("\"name\"") !== -1) {
        // Parse name value
        var nameMatch = line.match(/"name"\s*"(.+)"/)
        if (nameMatch) return nameMatch[1].trim()
      }
    }
  } catch (e) {
    // File not readable, try next path
  }
  return null
}

// Parse appmanifest_*.json files for app name
function findAppInManifest(appId) {
  var home = getSteamHome()
  if (!home) return null
  // Find the manifest file
  try {
    var fs = require("fs")
    var manifestDir = home + "/steamapps"
    var files = fs.readdirSync(manifestDir)
    for (var i = 0; i < files.length; i++) {
      if (files[i].indexOf("appmanifest_") !== -1) {
        var content = fs.readFileSync(manifestDir + "/" + files[i], "utf8")
        var json = JSON.parse(content)
        // Manifest format: { "appid": "123456", "name": "Game Title" }
        if (json.appid === appId || json.appid == appId) {
          return json.name
        }
      }
    }
  } catch (e) {
    // Directory not readable, try next path
  }
  return null
}

// Get Steam home directory
function getSteamHome() {
  // Common Steam home locations
  var homes = [
    process.env.HOME + "/.steam",
    process.env.HOME + "/.local/share/Steam",
    "/home/" + require("os").userInfo().uid + "/.steam"
  ]
  for (var i = 0; i < homes.length; i++) {
    try {
      require("fs").accessSync(homes[i])
      return homes[i]
    } catch (e) {
      continue
    }
  }
  return null
}

// Try user Steam directory
function findAppInUserSteam(appId) {
  var home = getSteamHome()
  if (!home) return null
  try {
    var fs = require("fs")
    var steamDir = home + "/steamapps"
    var files = fs.readdirSync(steamDir)
    for (var i = 0; i < files.length; i++) {
      if (files[i].indexOf("appmanifest_") !== -1) {
        var content = fs.readFileSync(steamDir + "/" + files[i], "utf8")
        try {
          var json = JSON.parse(content)
          if (json.appid === appId || json.appid == appId) {
            return json.name
          }
        } catch (e) {
          // Not valid JSON, skip
        }
      }
    }
  } catch (e) {
    return null
  }
  return null
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

// Drops history older than keepDays (cutoff = todayKey - (keepDays - 1)).
// Keys are ISO "YYYY-MM-DD", so plain string comparison orders them
// correctly. Returns the original object when nothing is pruned so callers
// can avoid needless object churn on every persist.
function pruneDays(days, todayKey, keepDays) {
  if (!days || keepDays <= 0) return days
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

// Ordered list of insight rows: [{ label, value }]. Always returns three
// rows; missing data shows "—" placeholders.
function insights(day, days, todayKey, activeKey) {
  var key = activeKey || todayKey
  var isToday = key === todayKey
  var dayLabel = isToday ? "" : " (" + weekdayLabel(key) + ")"
  var total = day && day.total ? day.total : 0

  var apps = appList(day)
  var topApp = apps.length ? apps[0] : null
  var topLabel = topApp
    ? topApp.app + " \u00b7 " + "(" + topApp.pct + "%)" + " \u00b7 " + fmt(topApp.ms)
    : "\u2014"
  var list = [{ label: isToday ? "Top app" : "Top app " + weekdayLabel(key), value: topLabel }]

  var compareKey = prevKey(key)
  var compareTotal = totalFor(days, compareKey)
  var compareLabel = compareTotal > 0
    ? fmtDelta(total - compareTotal)
    : "\u2014"
  var vsLabel = isToday ? "vs yesterday" : "vs " + weekdayLabel(compareKey)
  list.push({ label: vsLabel, value: compareLabel })

  var busiest = busiestWeekDay(days, todayKey)
  var busiestLabel = busiest.total > 0
    ? weekdayLabel(busiest.key) + " \u00b7 " + fmt(busiest.total)
    : "\u2014"
  list.push({ label: "Busiest day (7d)", value: busiestLabel })

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

// Node-style exports only so `node --test` can drive these pure functions;
// QML's JS engine never defines `module`, so this guard is inert there.
if (typeof module !== "undefined" && module && module.exports) {
  module.exports = {
    pad2: pad2,
    canonicalApp: canonicalApp,
    displayName: displayName,
    dayFor: dayFor,
    dayKey: dayKey,
    newDay: newDay,
    fmt: fmt,
    fmtDelta: fmtDelta,
    fmtWords: fmtWords,

    appList: appList,
    totalFor: totalFor,
    prevKey: prevKey,
    relativeDayLabel: relativeDayLabel,
    weekdayLabel: weekdayLabel,
    formatDate: formatDate,
    weekKeys: weekKeys,
    busiestWeekDay: busiestWeekDay,
    weekTrend: weekTrend,
    pruneDays: pruneDays,
    insights: insights,
    groupedApps: groupedApps,
    hexToHsl: hexToHsl,
    hslToHex: hslToHex,
    sliceColors: sliceColors,
    arcSegments: arcSegments
  }
}
