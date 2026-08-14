// Pure JS helpers for the screen-time plugin: day keys, time formatting,
// per-app aggregation, and the small set of usage heuristics shown as
// insights. No Qt imports here so the functions stay testable in isolation.

function pad2(n) {
  n = Math.floor(n)
  return n < 10 ? "0" + n : String(n)
}

// Local-time calendar key, e.g. "2026-08-13".
function dayKey(date) {
  return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
}

function newDay() {
  return { total: 0, apps: {}, sessions: [] }
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
  return (ms < 0 ? "-" : "+") + fmt(Math.abs(ms))
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
  if (m > 0) part += " " + m + " MINUTES"
  return part
}

// Sorted per-app list for today: [{ app, ms, pct }], most-used first.
function appList(today) {
  var apps = today && today.apps ? today.apps : {}
  var total = today && today.total ? today.total : 0
  var out = []
  for (var app in apps) {
    if (!Object.prototype.hasOwnProperty.call(apps, app)) continue
    var ms = Number(apps[app]) || 0
    if (ms <= 0) continue
    out.push({ app: app, ms: ms, pct: total > 0 ? Math.round(100 * ms / total) : 0 })
  }
  out.sort(function(a, b) { return b.ms - a.ms })
  return out
}

function totalFor(days, key) {
  var d = days && days[key]
  return d && d.total ? d.total : 0
}

function prevKey(key) {
  var parts = String(key).split("-")
  var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
  d.setDate(d.getDate() - 1)
  return dayKey(d)
}

// Weekday label for a dayKey relative to today: "Today", "Yesterday", or
// the short weekday name.
var WEEKDAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

function relativeDayLabel(key, todayKey) {
  if (key === todayKey) return "Today"
  if (key === prevKey(todayKey)) return "Yesterday"
  var parts = String(key).split("-")
  var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
  return WEEKDAY_NAMES[d.getDay()]
}

// Last 7 day keys ending at todayKey, oldest first.
function weekKeys(todayKey) {
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
  var best = { key: keys[keys.length - 1], total: 0 }
  for (var i = 0; i < keys.length; i++) {
    var total = totalFor(days, keys[i])
    if (total > best.total) best = { key: keys[i], total: total }
  }
  return best
}

// Hour (0-23) during which the most focused time accrued today, else -1.
function peakHour(today) {
  var sessions = today && today.sessions ? today.sessions : []
  if (!sessions.length) return -1
  var hours = {}
  for (var i = 0; i < sessions.length; i++) {
    var s = sessions[i]
    if (!s || !s.start) continue
    var h = new Date(s.start).getHours()
    hours[h] = (hours[h] || 0) + (s.dur || 0)
  }
  var best = -1
  var bestMs = 0
  for (var h2 in hours) {
    if (hours[h2] > bestMs) {
      bestMs = hours[h2]
      best = Number(h2)
    }
  }
  return best
}

function longestSession(today) {
  var sessions = today && today.sessions ? today.sessions : []
  var longest = 0
  for (var i = 0; i < sessions.length; i++) {
    if (sessions[i] && sessions[i].dur > longest) longest = sessions[i].dur
  }
  return longest
}

// Ordered list of insight rows: [{ label, value }]. Empty when nothing has
// been tracked yet today.
function insights(today, days, todayKey) {
  var list = []
  var total = today && today.total ? today.total : 0
  if (total <= 0) return list

  var apps = appList(today)
  if (apps.length) {
    var top = apps[0]
    list.push({ label: "Top app", value: top.app + " \u00b7 " + fmt(top.ms) + " (" + top.pct + "%)" })
  }

  var yesterday = totalFor(days, prevKey(todayKey))
  if (yesterday > 0) list.push({ label: "vs yesterday", value: fmtDelta(total - yesterday) })

  var sessions = today.sessions || []
  if (sessions.length) list.push({ label: "Sessions", value: String(sessions.length) })

  var longest = longestSession(today)
  if (longest > 0) list.push({ label: "Longest session", value: fmt(longest) })

  var peak = peakHour(today)
  if (peak >= 0) list.push({ label: "Peak hour", value: pad2(peak) + ":00" })

  var busiest = busiestWeekDay(days, todayKey)
  if (busiest.total > 0)
    list.push({ label: "Busiest day (7d)", value: relativeDayLabel(busiest.key, todayKey) + " \u00b7 " + fmt(busiest.total) })

  return list
}
