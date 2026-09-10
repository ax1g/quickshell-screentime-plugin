"use strict"

// Structural tests for the v1.6.0 config menu: week window, hide flags,
// settings plumbing and today reset. QML can't run under node, so these
// assert the wiring (props, signals, derivations) by source shape, the
// same approach as tests/service.test.js.

const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

function qml(name) {
  return fs.readFileSync(path.join(__dirname, "..", "qml", name), "utf8")
}

function comp(name) {
  return fs.readFileSync(
    path.join(__dirname, "..", "qml", "components", name),
    "utf8",
  )
}

const panel = qml("Panel.qml")
const bar = qml("BarWidget.qml")
const service = qml("Service.qml")
const trend = qml("WeekTrend.qml")
const hero = comp("HeroHeader.qml")
const menu = comp("ConfigMenu.qml")

test("week window is configurable, never hardcoded", () => {
  assert.match(panel, /weekOptions: \[4, 8, 12\]/)
  assert.match(
    panel,
    /Model\.weekView\(root\.days, root\.todayKey, root\.weekCount/,
  )
  assert.match(panel, /Math\.min\(root\.maxWeekOffset, root\.weekOffset \+ 1\)/)
  assert.match(trend, /required property int maxOffset/)
  assert.match(trend, /root\.weekOffset < root\.maxOffset/)
  assert.doesNotMatch(panel, /Math\.min\(12,/)
  assert.doesNotMatch(trend, /weekOffset < 12/)
})

test("invalid week counts fall back to 12, stored 13 keeps max", () => {
  assert.match(panel, /weekOptions\.indexOf\(n\) >= 0 \? n : 12/)
  assert.match(panel, /if \(n === 13\)\s*\n\s*return 12/)
})

test("year drawer hides completely via setting", () => {
  assert.match(panel, /hideYearly/)
  assert.match(panel, /serviceReady && !root\.hideYearly \? Model\.yearView/)
  assert.match(hero, /required property bool calendarEnabled/)
  assert.match(hero, /if \(heroHeader\.calendarEnabled\)/)
})

test("daily insights hide via setting", () => {
  assert.match(panel, /hideDailyInsights/)
  assert.match(menu, /signal dailyInsightsToggled/)
  assert.doesNotMatch(panel, /hideInsights[^I]/)
})

test("yearly insights hide via setting, month bars stay", () => {
  const drawer = qml("YearDrawer.qml")
  assert.match(panel, /hideYearInsights/)
  assert.match(menu, /signal yearInsightsToggled/)
  assert.match(drawer, /required property bool hideYearInsights/)
  assert.match(
    drawer,
    /visible: !root\.hideYearInsights && root\.yearFacts\.length > 0/,
  )
})

test("config menu threads prefs with explicit props and signals", () => {
  for (const sig of [
    "yearlyToggled",
    "dailyInsightsToggled",
    "yearInsightsToggled",
    "weekWindowSelected",
    "weekTotalModeToggled",
    "trophyToggled",
    "easterEggsToggled",
    "recordColorSelected",
    "resetRequested",
  ]) {
    assert.match(menu, new RegExp("signal " + sig))
  }
  assert.match(menu, /required property int weekCount/)
  assert.match(menu, /required property var weekOptions/)
  assert.match(menu, /required property bool hideRecordTrophy/)
  assert.match(menu, /required property string recordColor/)
  assert.match(menu, /required property var recordColorOptions/)
  assert.match(menu, /model: root\.recordColorOptions/)
  assert.match(menu, /root\.recordColorSelected\(modelData\)/)
  assert.match(panel, /hostWidget\.setSetting/)
  assert.match(bar, /function setSetting\(key, value\)/)
})

test("toggles are mini shell switches in panel-styled rows", () => {
  assert.match(menu, /ToggleSwitch \{/)
  assert.match(menu, /trackHeight: 18/)
  assert.match(menu, /onToggled: root\.activate\(modelData\.kind\)/)
  assert.match(menu, /model: root\.weekOptions/)
  assert.match(menu, /root\.weekWindowSelected\(modelData\)/)
  assert.match(panel, /function selectWeekWindow\(count\)/)
})

test("resetToday zeroes today only, archives untouched", () => {
  assert.match(service, /function resetToday\(\)/)
  const reset = service.match(/function resetToday\(\) \{[\s\S]*?\n    \}/)
  assert(reset, "resetToday block exists")
  assert(reset[0].includes("root.today = Model.newDay()"))
  assert(reset[0].includes("nd[root.todayKey] = root.today"))
  assert(reset[0].includes("root.persist()"))
  assert(!reset[0].includes("months"), "must not touch month lumps")
  assert(!reset[0].includes("years"), "must not touch the archive")
})

test("config lives in its own slide-over drawer", () => {
  assert.match(panel, /id: configDrawer/)
  assert.match(panel, /id: configScroll/)
  assert.match(panel, /function openConfig\(open\)/)
  assert.match(panel, /x: root\.configOpen \? 0 : keyCatcher\.drawerWidth/)
  assert.match(panel, /onConfigToggled: root\.openConfig\(!root\.configOpen\)/)
  // The two drawers never overlap: opening one closes the other.
  assert.match(panel, /if \(open\)\s+root\.configOpen = false/)
  assert.match(panel, /if \(open\)\s+root\.openCalendar\(false\)/)
})

test("busiest week trophy follows the best week at any page", () => {
  assert.match(panel, /readonly property bool recordWeek/)
  assert.match(panel, /root\.weekView \? root\.weekView\.isRecord/)
  assert.doesNotMatch(panel, /weekOffset === 0 && serviceReady/)
  assert.match(trend, /visible: root\.recordWeek && root\.showRecordTrophy/)
})

test("busiest week trophy hides via setting", () => {
  assert.match(
    panel,
    /hideRecordTrophy: root\.prefs\.hideRecordTrophy === true/,
  )
  assert.match(
    panel,
    /writeSetting\("hideRecordTrophy", !root\.hideRecordTrophy\)/,
  )
  assert.match(panel, /showRecordTrophy: !root\.hideRecordTrophy/)
  assert.match(menu, /signal trophyToggled/)
  assert.match(menu, /shown: !root\.hideRecordTrophy/)
  assert.match(menu, /label: "Busiest Week Trophy"/)
  assert.match(trend, /required property bool showRecordTrophy/)
})

test("week total mode persists instead of resetting on dismiss", () => {
  assert.match(panel, /writeSetting\("weekTotalAsPct", !root\.weekTotalAsPct\)/)
  assert.doesNotMatch(panel, /root\.weekTotalAsPct = false/)
})

test("busiest week trophy color defaults to gold and persists via setting", () => {
  assert.match(panel, /recordColorOptions: \["#FFD700"/)
  assert.match(panel, /root\.prefs\.recordColor/)
  assert.match(panel, /function selectRecordColor\(color\)/)
  assert.match(panel, /writeSetting\("recordColor", color\)/)
  assert.match(panel, /recordColor: root\.recordColor/)
  assert.match(trend, /required property color recordColor/)
  assert.match(trend, /color: root\.recordColor/)
  assert.doesNotMatch(trend, /color: "#FFD700"/)
})
