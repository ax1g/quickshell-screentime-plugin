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
  assert.match(panel, /weekOptions: Model\.WEEK_COUNT_OPTIONS/)
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

test("invalid week counts round up to a preset, never shrink", () => {
  assert.match(panel, /Model\.parseWeekCount\(root\.prefs\.weekCount\)/)
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
    "heroColorSelected",
    "resetRequested",
  ]) {
    assert.match(menu, new RegExp("signal " + sig))
  }
  assert.match(menu, /required property int weekCount/)
  assert.match(menu, /required property var weekOptions/)
  assert.match(menu, /required property bool hideRecordTrophy/)
  assert.match(menu, /required property string recordColor/)
  assert.match(menu, /required property var recordColorOptions/)
  assert.match(menu, /required property string heroColor/)
  assert.match(menu, /required property var heroColorOptions/)
  assert.match(menu, /model: root\.recordColorOptions/)
  assert.match(menu, /root\.recordColorSelected\(modelData\)/)
  assert.match(menu, /model: root\.heroColorOptions/)
  assert.match(menu, /root\.heroColorSelected\(modelData\)/)
  assert.match(panel, /hostWidget\.setSetting/)
  assert.match(bar, /function setSetting\(key, value\)/)
})

test("settings writes never drop stored keys", () => {
  // Early writes (before delivery, or while the shell API is unreachable)
  // accumulate in pendingWrites and merge into every built entry, so the
  // shell never receives a partial entry that would lose the user's config.
  assert.match(bar, /property var pendingWrites/)
  assert.match(bar, /property bool settingsReady: false/)
  assert.match(bar, /for \(var p in pending\)/)
  assert.match(bar, /function flushSettings\(\)/)
  assert.match(bar, /root\.flushSettings\(\)/)
  // Own optimistic writes must not fake delivery.
  assert.match(bar, /property bool writingSettings/)
  assert.match(bar, /if \(!root\.writingSettings\)/)
  assert.match(bar, /updateEntryInline\(root\.moduleName, entry\)/)
})

test("toggles are mini shell switches in panel-styled rows", () => {
  assert.match(menu, /ToggleSwitch \{/)
  assert.match(menu, /trackHeight: 18/)
  // The row owns the click (and the switch drops its cursor-ring pad,
  // so the track aligns flush with the boxes and swatches).
  assert.match(menu, /interactive: false/)
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
  assert.match(
    panel,
    /root\.configOpen = true;\s*\n\s*root\.openCalendar\(false\)/,
  )
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
  assert.match(
    panel,
    /Model\.themeSwatches\(Color\.accent, Color\.foreground, Color\.muted\)/,
  )
  assert.match(
    panel,
    /Model\.pickSwatch\(root\.prefs\.recordColor, root\.recordDefaultColor\)/,
  )
  assert.match(panel, /function selectRecordColor\(color\)/)
  assert.match(panel, /writeSetting\("recordColor", c\)/)
  assert.match(panel, /recordColor: root\.recordColor/)
  assert.match(trend, /required property color recordColor/)
  assert.match(trend, /color: root\.recordColor/)
  assert.doesNotMatch(trend, /color: "#FFD700"/)
  // A stored pick missing from the theme set renders as a custom slot
  // instead of resetting to gold.
  assert.match(
    menu,
    /root\.recordColorOptions\.indexOf\(root\.recordColor\) === -1/,
  )
  assert.match(menu, /root\.recordColorSelected\(root\.recordColor\)/)
})

test("hero icon color overrides hourglass, yearly and config glyphs", () => {
  const drawer = qml("YearDrawer.qml")
  assert.match(
    panel,
    /Model\.themeSwatches\(Color\.accent, Color\.foreground, Color\.muted\)/,
  )
  assert.match(
    panel,
    /Model\.pickSwatch\(root\.prefs\.heroColor, root\.heroDefaultColor\)/,
  )
  assert.match(panel, /function selectHeroColor\(color\)/)
  assert.match(panel, /writeSetting\("heroColor", c\)/)
  assert.match(panel, /heroColor: root\.heroColor/)
  // Empty follows the theme foreground, so old installs keep it.
  assert.match(panel, /readonly property string heroDefaultColor: ""/)
  assert.match(hero, /required property string heroColor/)
  assert.match(hero, /heroHeader\.heroColor !== "" \? heroHeader\.heroColor/)
  assert.match(drawer, /required property string heroColor/)
  assert.match(drawer, /root\.heroColor !== "" \? root\.heroColor/)
  assert.match(menu, /signal heroColorSelected\(string color\)/)
  assert.match(menu, /root\.heroColorSelected\(modelData\)/)
  // No Auto pill: the menu offers theme circles plus a reset glyph.
  assert.doesNotMatch(menu, /text: "Auto"/)
  assert.doesNotMatch(menu, /root\.heroColorSelected\(""\)/)
  assert.match(
    menu,
    /root\.heroColorOptions\.indexOf\(root\.heroColor\) === -1/,
  )
  assert.match(menu, /root\.heroColorSelected\(root\.heroColor\)/)
})

test("tracking prefs normalize in the panel and filter the active day", () => {
  assert.match(panel, /Model\.parseIgnoredApps\(root\.prefs\.ignoredApps\)/)
  assert.match(panel, /Model\.parseAppAliases\(root\.prefs\.appAliases\)/)
  assert.match(panel, /function pushTrackingPrefs\(\)/)
  assert.match(panel, /setTrackingPrefs\(root\.ignoredList, root\.appAliases\)/)
  assert.match(panel, /Model\.filterIgnoredDay\(Model\.dayFor/)
  assert.match(menu, /required property var ignoredEntries/)
  assert.match(menu, /required property var aliasEntries/)
  assert.match(menu, /signal ignoredAdded\(string name\)/)
  assert.match(menu, /signal ignoredRemoved\(string name\)/)
  assert.match(menu, /signal aliasAdded\(string from, string to\)/)
  assert.match(menu, /signal aliasRemoved\(string from\)/)
  assert.match(menu, /root\.ignoredAdded\(ignoredInput\.text\)/)
  assert.match(menu, /root\.ignoredRemoved\(modelData\)/)
  assert.match(menu, /root\.aliasRemoved\(modelData\.from\)/)
  assert.match(panel, /function addIgnored\(name\)/)
  assert.match(panel, /function removeIgnored\(name\)/)
  assert.match(panel, /function addAlias\(from, to\)/)
  assert.match(panel, /function removeAlias\(from\)/)
  assert.match(panel, /Model\.ignoredWith\(root\.ignoredList, name\)/)
  assert.match(panel, /Model\.aliasesWith\(root\.prefs\.appAliases, from, to\)/)
  assert.match(panel, /ignoredEntries: root\.ignoredList/)
  assert.match(panel, /aliasEntries: root\.aliasEntries/)
})

test("settings group into tinted section cards with a red danger zone", () => {
  assert.match(menu, /text: "DISPLAY"/)
  assert.match(menu, /text: "COLORS"/)
  assert.match(menu, /text: "TREND & HISTORY"/)
  assert.match(menu, /text: "DAILY GOAL"/)
  assert.match(menu, /text: "TRACKING"/)
  assert.match(menu, /text: "DANGER ZONE"/)
  assert.match(menu, /id: dangerBody/)
  assert.match(menu, /root\.urgent\.r, root\.urgent\.g, root\.urgent\.b, 0\.07/)
})

test("daily goal threads from prefs to bar badge and hero bar", () => {
  assert.match(
    panel,
    /Model\.parseDailyGoalHours\(root\.prefs\.dailyGoalHours\)/,
  )
  // Each day keeps the goal it had: progress reads the log entry for
  // the viewed day, never the current pref.
  assert.match(
    panel,
    /Model\.goalProgress\(root\.dayTotal, Model\.goalForDay\(root\.goalLog, root\.activeDayKey\)\)/,
  )
  assert.match(panel, /function logGoalChange\(hours\)/)
  assert.match(panel, /writeSetting\("dailyGoalLog", Model\.logGoalChange/)
  assert.match(panel, /goalProgress: root\.goalProgress/)
  assert.match(menu, /required property int dailyGoalHours/)
  assert.match(menu, /required property var dailyGoalOptions/)
  assert.match(menu, /signal dailyGoalSelected\(int hours\)/)
  assert.match(menu, /root\.dailyGoalSelected\(modelData\)/)
  assert.match(panel, /root\.logGoalChange\(hours\)/)
  assert.match(hero, /required property var goalProgress/)
  assert.match(hero, /heroHeader\.goalProgress !== null/)
  assert.match(bar, /readonly property int dailyGoalHours/)
  assert.match(
    bar,
    /Model\.goalForDay\(Model\.parseGoalLog\(root\.setting\("dailyGoalLog", \[\]\)\)/,
  )
  assert.match(bar, /readonly property bool goalReached/)
  assert.match(bar, /root\.goalReached \? " ✓" : ""/)
  assert.match(bar, /root\.goalTooltip/)
})

test("wipe-all needs four conscious clicks and names the blast radius", () => {
  assert.match(service, /function resetAll\(\)/)
  assert.match(bar, /function resetAll\(\): void/)
  assert.match(menu, /signal wipeRequested/)
  assert.match(menu, /id: wipeRow/)
  assert.match(menu, /interval: 5000/)
  assert.match(menu, /cannot be undone/)
  assert.match(menu, /wipeRow\.stage >= 3/)
  assert.match(menu, /root\.wipeRequested\(\)/)
  assert.match(panel, /root\.service\.resetAll\(\)/)
})

test("app detail is a year and the service never keeps less than the trend", () => {
  assert.match(service, /property int keepDays: 365/)
  assert.match(service, /function setKeepDays\(days\)/)
  assert.match(service, /Math\.floor\(Number\(days\)\)/)
  // The service never keeps less than the visible trend needs, so wide
  // windows cannot show hollow weeks older than the preset.
  assert.match(panel, /Model\.minKeepDays\(root\.weekCount\)/)
  assert.match(
    panel,
    /Math\.max\(Model\.APP_DETAIL_DAYS, Model\.minKeepDays\(root\.weekCount\)\)/,
  )
  // Totals live on forever; the footprint readout stays on the menu.
  assert.match(
    panel,
    /Model\.storageSummary\(root\.days, root\.months, root\.years\)/,
  )
  assert.match(panel, /Model\.storageLabel\(root\.storageSummary\)/)
  assert.match(panel, /root\.service\.setKeepDays\(root\.effectiveKeepDays\)/)
  assert.match(menu, /required property string storageLabel/)
  assert.match(menu, /text: "Forever totals"/)
  assert.match(menu, /never deleted; nothing here deletes hours/)
  assert.doesNotMatch(menu, /keepDaysSelected/)
  assert.doesNotMatch(menu, /required property int keepDays/)
  assert.doesNotMatch(panel, /prefs\.keepDays/)
})

test("first-run onboarding shows coach marks until anything is tracked", () => {
  assert.match(panel, /readonly property bool showOnboarding/)
  assert.match(
    panel,
    /root\.storageSummary\.totalMs <= 0 && root\.dayTotal <= 0/,
  )
  assert.match(panel, /id: onboardingColumn/)
  assert.match(panel, /visible: root\.showOnboarding/)
  assert.match(panel, /No screen time yet/)
  assert.match(panel, /Terminals track what runs inside/)
  assert.match(panel, /gear for settings/)
})

test("staged rows size explicitly so a fill mousearea cannot collapse them", () => {
  assert.match(menu, /Item \{\s*\n\s*id: resetRow/)
  assert.match(
    menu,
    /height: Math\.max\(resetLabels\.implicitHeight, resetBtnRow\.height\)/,
  )
  assert.match(menu, /Item \{\s*\n\s*id: wipeRow/)
  assert.match(
    menu,
    /height: Math\.max\(wipeLabels\.implicitHeight, wipeBtnRow\.height\)/,
  )
})

test("danger buttons center vertically beside early-wrapping labels", () => {
  for (const [labels, buttons] of [
    ["resetLabels", "resetBtnRow"],
    ["wipeLabels", "wipeBtnRow"],
  ]) {
    assert.match(
      menu,
      new RegExp(
        "id: " +
          buttons +
          "\\s*\\n\\s*anchors\\.right: parent\\.right\\s*\\n\\s*anchors\\.verticalCenter: parent\\.verticalCenter",
      ),
    )
    assert.match(
      menu,
      new RegExp(
        "id: " +
          labels +
          "[\\s\\S]*?width: parent\\.width - " +
          buttons +
          "\\.width",
      ),
    )
  }
  assert.match(
    menu,
    /text: wipeRow\.stage === 0 \? "WIPE ALL"[\s\S]*?"CAN'T UNDO!"[\s\S]*?"WIPE!"/,
  )
})

test("option pills align left under their labels", () => {
  for (const id of [
    "weekBoxes",
    "goalBoxes",
    "trophySwatches",
    "heroSwatches",
  ]) {
    const row = menu.match(
      new RegExp(
        "id: " + id + "[\\s\\S]*?anchors\\.(left|right): parent\\.(left|right)",
      ),
    )
    assert(row, id + " row exists")
    assert.equal(row[1], "left", id + " aligns left")
  }
})

test("color rows offer a reset glyph at the right", () => {
  assert.match(panel, /readonly property string recordDefaultColor: "#ffd700"/)
  assert.match(panel, /readonly property string heroDefaultColor: ""/)
  assert.match(menu, /required property string recordDefaultColor/)
  assert.match(menu, /required property string heroDefaultColor/)
  assert.match(menu, /root\.recordColorSelected\(root\.recordDefaultColor\)/)
  assert.match(menu, /root\.heroColorSelected\(root\.heroDefaultColor\)/)
  assert.match(menu, /root\.recordColor === root\.recordDefaultColor/)
  assert.match(menu, /root\.heroColor === root\.heroDefaultColor/)
  assert.match(panel, /recordDefaultColor: root\.recordDefaultColor/)
  assert.match(panel, /heroDefaultColor: root\.heroDefaultColor/)
  const resets = menu.match(/text: "\\uf0e2"/g)
  assert(resets && resets.length === 2, "reset glyph in both color rows")
  assert.doesNotMatch(menu, /text: "R"/)
  // Idle glyphs use the theme foreground at reduced opacity, never a
  // darkened shade that vanishes on dark themes.
  assert.doesNotMatch(menu, /Qt\.darker\(root\.foreground, 1\.4\)/)
})

test("year scrollbar mirrors the settings idiom", () => {
  const drawer = qml("YearDrawer.qml")
  assert.match(drawer, /calendarScroll\.width - Style\.space\(8\)/)
  assert.match(drawer, /property real ratio: calendarScroll\.contentHeight > 0/)
  assert.match(
    drawer,
    /visible: calendarScroll\.contentHeight > calendarScroll\.height/,
  )
  assert.match(drawer, /anchors\.right: calendarScroll\.right/)
  assert.match(
    drawer,
    /calendarScroll\.contentY \/ \(calendarScroll\.contentHeight - calendarScroll\.height\)/,
  )
})

test("navigation celebrates through the header icons", () => {
  const drawer = qml("YearDrawer.qml")
  // Home gear sweeps a full turn as settings opens.
  assert.match(hero, /id: gearSpin/)
  assert.match(hero, /id: gearSpin[\s\S]*?to: 360/)
  assert.match(panel, /id: configGearSpin/)
  assert.match(panel, /id: configGearSpin[\s\S]*?to: 360/)
  assert.match(hero, /gearSpin\.restart\(\);/)
  // Returning home turns the hourglass a full circle.
  assert.match(hero, /function spinHourglass\(\)/)
  assert.match(hero, /heroFlip\.restart\(\)/)
  assert.match(panel, /id: heroHeader/)
  assert.match(panel, /function celebrateHome\(\)/)
  assert.match(panel, /heroHeader\.spinHourglass\(\)/)
  // The settings header gear sweeps as its drawer slides in.
  assert.match(panel, /id: configGearSpin/)
  assert.match(panel, /configGearSpin\.restart\(\)/)
  // The yearly calendar swings once on entry, pivoting at the top.
  assert.match(drawer, /transformOrigin: Item\.Top/)
  assert.match(drawer, /id: calendarSwing/)
  assert.match(drawer, /function swingCalendar\(\)/)
  assert.match(drawer, /calendarSwing\.restart\(\)/)
  assert.match(panel, /id: yearDrawer/)
  assert.match(panel, /yearDrawer\.swingCalendar\(\)/)
})

test("drawer switches never read as a return home", () => {
  // Opening one drawer closes the other; only both resting closed
  // celebrates, and dismiss closes drawers silently.
  assert.match(
    panel,
    /else if \(!root\.configOpen\)\s*\n\s*root\.celebrateHome\(\)/,
  )
  assert.match(
    panel,
    /} else if \(!root\.calendarOpen\) \{\s*\n\s*root\.celebrateHome\(\);/,
  )
  assert.match(
    panel,
    /if \(root\.opened\)\s*\n\s*heroHeader\.spinHourglass\(\)/,
  )
})

test("config opens expanded like the yearly drawer", () => {
  const fn = panel.match(/function openConfig\(open\) \{[\s\S]*?\n    \}/)
  assert(fn, "openConfig block exists")
  assert(fn[0].includes("keyCatcher.collapsedCardH = keyCatcher.height"))
  assert(fn[0].includes("root.expanded = true"))
})

test("only the danger buttons arm reset, never their labels", () => {
  for (const button of ["resetBox", "wipeBox"]) {
    assert.match(
      menu,
      new RegExp(
        "id: " +
          button +
          "[\\s\\S]*?MouseArea\\s*\\{\\s*id: \\w+\\s*\\n\\s*anchors\\.fill: parent",
      ),
    )
  }
})

test("the week window repushes retention", () => {
  assert.match(panel, /onWeekCountChanged: root\.pushTrackingPrefs\(\)/)
})

test("week pills read in weeks", () => {
  assert.match(menu, /text: modelData \+ "w"/)
})

test("trophy color carries a wrapping caption", () => {
  assert.match(menu, /text: "Color of the record-week trophy"/)
})

test("settings header icon returns to the main panel", () => {
  assert.match(
    panel,
    /id: configHeroIconMouse[\s\S]*?onClicked: root\.openConfig\(false\)/,
  )
})

test("help section links out with icons and a privacy note", () => {
  assert.match(menu, /text: "CONTRIBUTION"/)
  assert.match(menu, /Private by design/)
  assert.match(menu, /issues\/new/)
  assert.match(menu, /"Report a bug"/)
  assert.match(menu, /"Share an idea"/)
  assert.match(menu, /"Contribute"/)
  assert.match(menu, /Qt\.openUrlExternally\(modelData\.url\)/)
  assert.match(menu, /github\.com\/ax1g\/quickshell-screentime-plugin/)
})

test("playful extras mute the header spins", () => {
  const drawer = qml("YearDrawer.qml")
  assert.match(hero, /if \(heroHeader\.easterEggs\)\s*\n\s*gearSpin\.restart/)
  assert.match(hero, /if \(heroHeader\.easterEggs\)\s*\n\s*heroFlip\.restart/)
  assert.match(panel, /if \(open\) \{\s*\n\s*if \(!root\.hideEasterEggs\)/)
  assert.match(drawer, /required property bool easterEggs/)
  assert.match(drawer, /if \(root\.easterEggs\)\s*\n\s*calendarSwing\.restart/)
  assert.match(panel, /easterEggs: !root\.hideEasterEggs/)
  assert.match(menu, /Hourglass flip, sparkles and header spins/)
})

test("ipc surface routes every panel action", () => {
  for (const fn of [
    "open",
    "close",
    "show",
    "hide",
    "toggle",
    "resetToday",
    "resetAll",
    "status",
  ]) {
    assert.match(bar, new RegExp("function " + fn + "\\("), fn + " exists")
  }
  assert.match(bar, /root\.service\.resetToday\(\)/)
  assert.match(bar, /root\.service\.resetAll\(\)/)
  assert.match(bar, /root\.togglePanel\(\)/)
})

test("wiping history reveals onboarding", () => {
  const reset = service.match(/function resetAll\(\) \{[\s\S]*?\n    \}/)
  assert(reset, "resetAll block exists")
  assert(reset[0].includes("root.days = {}"))
  assert(reset[0].includes("root.months = {}"))
  assert(reset[0].includes("root.years = {}"))
  assert.match(
    panel,
    /root\.storageSummary\.totalMs <= 0 && root\.dayTotal <= 0/,
  )
})

test("about shows the manifest version", () => {
  const manifest = JSON.parse(
    require("node:fs").readFileSync(
      require("node:path").join(__dirname, "..", "manifest.json"),
      "utf8",
    ),
  )
  assert.match(
    panel,
    new RegExp(
      'readonly property string pluginVersion: "' + manifest.version + '"',
    ),
  )
  assert.match(menu, /required property string pluginVersion/)
  assert.match(panel, /pluginVersion: root\.pluginVersion/)
  assert.doesNotMatch(menu, /text: "ABOUT"/)
  assert.match(menu, /text: "Screen Time"/)
  assert.match(menu, /"v" \+ root\.pluginVersion/)
  assert.match(menu, /Know where your time goes/)
})

test("settings header reads Settings with a content subtitle", () => {
  assert.match(panel, /text: "Settings"/)
  assert.match(panel, /Display, tracking, goals & data/)
  assert.doesNotMatch(panel, /text: "Screen Time"/)
})

test("trophy needs two weeks of tracked data", () => {
  const model = fs.readFileSync(
    path.join(__dirname, "..", "js", "Model.js"),
    "utf8",
  )
  assert.match(
    model,
    /isRecord: offset === bestWeekOffset\(weeks\) && dataWeeks >= 2/,
  )
})

test("year hero opens straight into the pager without a caption", () => {
  const drawer = qml("YearDrawer.qml")
  assert.doesNotMatch(drawer, /monthsActive/)
  assert.doesNotMatch(drawer, /Tracked/)
  assert.doesNotMatch(panel, /monthsActive/)
  assert.match(drawer, /font\.letterSpacing: 2\.4/)
  assert.match(
    panel,
    /calendarYearTotal: root\.yearView \? root\.yearView\.totalLabel : "0h"/,
  )
})

test("month rows carry no trophy; ranks live in the card", () => {
  const monthRow = fs.readFileSync(
    path.join(__dirname, "..", "qml", "MonthRow.qml"),
    "utf8",
  )
  assert.doesNotMatch(monthRow, /isTop/)
  assert.doesNotMatch(monthRow, /topMonth/)
})

test("settings editors receive keys instead of panel shortcuts", () => {
  assert.match(
    menu,
    /readonly property bool editing: ignoredInput\.activeFocus \|\| aliasFromInput\.activeFocus \|\| aliasToInput\.activeFocus/,
  )
  assert.match(panel, /id: configMenu/)
  assert.match(panel, /blocked: configMenu\.editing/)
})

test("config drawer blocker stays behind the menu actions", () => {
  assert.match(
    panel,
    /id: configDrawer[\s\S]*?MouseArea\s*\{\s*z: -1\s*\n\s*anchors\.fill: parent/,
  )
})

test("alias row flows from, arrow, to, save", () => {
  assert.match(menu, /id: aliasInputRow/)
  assert.match(menu, /id: aliasArrow/)
  assert.match(menu, /text: "\\u2192"/)
})

test("alias removal needs two clicks on a left red cross", () => {
  assert.match(menu, /id: aliasEntry/)
  assert.match(menu, /property bool armed: false/)
  assert.match(menu, /text: aliasEntry\.armed \? "\?" : "\\u00D7"/)
  assert.match(
    menu,
    /color: root\.urgent\s*\n\s*opacity: aliasEntry\.armed \? 1\.0 : 0\.75/,
  )
  assert.match(menu, /if \(aliasEntry\.armed\)/)
  assert.match(menu, /root\.aliasRemoved\(modelData\.from\)/)
})

test("year cards render values as rich text for medal markup", () => {
  const card = comp("InsightCard.qml")
  assert.match(card, /textFormat: Text\.RichText/)
  assert.match(card, /text: insightCard\.stat/)
})

test("goal block breathes below the date line", () => {
  assert.match(hero, /height: visible \? Style\.space\(4\) : 0/)
})

test("settings inputs show a focus ring", () => {
  for (const id of ["ignoredInput", "aliasFromInput", "aliasToInput"]) {
    assert.match(
      menu,
      new RegExp("border\\.color: " + id + "\\.activeFocus \\? root\\.accent"),
    )
  }
})

test("removing an alias unfolds today through the inverse map", () => {
  assert.match(panel, /var to = root\.appAliases\[from\] \|\| ""/)
  assert.match(panel, /inverse\[String\(to\)\.toLowerCase\(\)\] = from/)
  assert.match(panel, /root\.service\.refoldToday\(inverse\)/)
})

test("hourglass brightens on hover like the other heroes", () => {
  assert.match(hero, /heroIconMouse\.containsMouse \? heroHeader\.foreground/)
})

test("settings inputs use Qt's real cursor, not a hand-rolled one", () => {
  // The custom delegate rendered frozen and stayed visible without focus;
  // the default caret blinks and hides with focus.
  assert.doesNotMatch(menu, /cursorDelegate/)
  assert.doesNotMatch(menu, /cursorVisible/)
})

test("settings inputs are clickable across the whole box", () => {
  const inputs = menu.match(
    /anchors\.fill: parent\s*\n\s*leftPadding: Style\.space\(8\)\s*\n\s*rightPadding: Style\.space\(8\)\s*\n\s*verticalAlignment: TextInput\.AlignVCenter/g,
  )
  assert(
    inputs && inputs.length === 3,
    "full-width hit area, no height inflation",
  )
  assert.doesNotMatch(menu, /\n\s*padding: Style\.space\(8\)/)
})

test("tab cycles through the settings inputs", () => {
  assert.match(
    menu,
    /id: ignoredInput[\s\S]*?KeyNavigation\.tab: aliasFromInput/,
  )
  assert.match(
    menu,
    /id: aliasFromInput[\s\S]*?KeyNavigation\.tab: aliasToInput/,
  )
  assert.match(menu, /id: aliasToInput[\s\S]*?KeyNavigation\.tab: ignoredInput/)
  assert.match(menu, /KeyNavigation\.backtab: ignoredInput/)
  assert.match(menu, /KeyNavigation\.backtab: aliasFromInput/)
  assert.match(menu, /KeyNavigation\.backtab: aliasToInput/)
})

test("hint mode toggles on f and routes letters", () => {
  assert.match(panel, /property bool hintMode: false/)
  assert.match(panel, /if \(t === "f" \|\| t === "F"\)/)
  assert.match(panel, /function activateHint\(tag\)/)
  for (const route of [
    'tag === "y"',
    'tag === "c"',
    'tag === "m"',
    'tag === "b"',
    'tag === "n"',
    'tag === "t"',
    'tag >= "1" && tag <= "7"',
  ]) {
    assert.match(
      panel,
      new RegExp(route.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")),
    )
  }
  assert.match(panel, /root\.hintMode = false/)
  // Esc exits hint mode instead of closing the panel.
  assert.match(panel, /if \(root\.hintMode\)\s*\n\s*root\.hintMode = false/)
})

test("hint badge contracts to zero when hidden", () => {
  const badge = comp("HintBadge.qml")
  assert.match(badge, /required property string label/)
  assert.match(badge, /required property string fontFamily/)
  assert.match(badge, /required property color accent/)
  assert.match(badge, /required property bool show/)
  assert.match(badge, /width: visible \? implicitWidth : 0/)
  assert.match(badge, /height: visible \? implicitHeight : 0/)
  // Ink follows accent lightness so the letter reads on any theme.
  assert.match(badge, /root\.accent\.hslLightness >= 0\.45/)
})

test("main surfaces badge hint letters", () => {
  const daybar = comp("WeekDayBar.qml")
  assert.match(hero, /required property bool hintMode/)
  assert.match(hero, /required property color accent/)
  assert.match(panel, /hintMode: root\.hintMode/)
  assert.match(panel, /accent: Color\.accent/)
  assert.match(trend, /required property bool hintMode/)
  for (const tag of ['label: "y"', 'label: "c"', 'label: "m"']) {
    assert.match(hero, new RegExp(tag))
  }
  for (const tag of ['label: "b"', 'label: "n"', 'label: "t"']) {
    assert.match(trend, new RegExp(tag))
  }
  assert.match(
    trend,
    /show: root\.hintMode && root\.weekOffset < root\.maxOffset && root\.hasPrevWeekData/,
  )
  assert.match(trend, /show: root\.hintMode && root\.weekOffset > 0/)
  assert.match(daybar, /required property bool hintMode/)
  assert.match(daybar, /required property int dayNumber/)
  assert.match(daybar, /show: day\.hintMode && !day\.isFuture && !day\.isEmpty/)
  assert.match(trend, /dayNumber: Model\.weekdayNumber\(modelData\.key\)/)
})

test("hint activation mirrors the click guards", () => {
  assert.match(panel, /tag === "y" && !root\.hideYearly/)
  assert.match(panel, /tag === "b" && root\.expanded/)
  assert.match(panel, /!day\.isFuture && \(Number\(day\.ms\) \|\| 0\) > 0/)
  assert.match(panel, /if \(handled\)\s*\n\s*return true;/)
  assert.match(
    panel,
    /if \(root\.activateHint\(key\)\)\s*\n\s*root\.hintMode = false;/,
  )
})

test("hint buffer resolves two-letter settings tags", () => {
  assert.match(panel, /property string hintBuffer: ""/)
  assert.match(panel, /onHintModeChanged/)
  assert.match(panel, /root\.hintBuffer \+= key/)
  assert.match(panel, /if \(root\.hintBuffer\.length >= 2\)/)
  assert.match(panel, /if \(configMenu\.activateHint\(tag\)\)/)
  assert.match(
    panel,
    /\} else \{\s*\n\s*if \(root\.activateHint\(key\)\)\s*\n\s*root\.hintMode = false;/,
  )
})

test("settings registry covers every pressable in order", () => {
  assert.match(menu, /required property bool hintMode/)
  assert.match(menu, /property var hintItems: \[\]/)
  assert.match(menu, /function buildHintItems\(\)/)
  assert.match(menu, /function hintTag\(items, kind, sub\)/)
  assert.match(menu, /function activateHint\(tag\)/)
  assert.match(menu, /onHintModeChanged/)
  assert.match(menu, /root\.buildHintItems\(\)/)
  for (const kind of [
    "back",
    "toggle",
    "trophy-swatch",
    "trophy-custom",
    "trophy-reset",
    "hero-swatch",
    "hero-custom",
    "hero-reset",
    "weeks",
    "goal",
    "field-ignored",
    "add-ignored",
    "remove-ignored",
    "field-from",
    "field-to",
    "add-alias",
    "remove-alias",
    "help",
    "reset",
    "wipe",
  ]) {
    assert.match(menu, new RegExp('"' + kind + '"'))
  }
  // Staged confirmations advance one step, never execute.
  assert.match(menu, /resetRow\.stage\+\+/)
  assert.match(menu, /wipeRow\.stage\+\+/)
  // Alias removal through hints restores outright: re-adding undoes it.
  assert.match(menu, /root\.aliasRemoved\(sub\)/)
  // Committing releases the keyboard back to shortcuts.
  assert.match(menu, /ignoredInput\.focus = false/)
  assert.match(menu, /aliasToInput\.focus = false/)
})

test("settings badges follow the registry", () => {
  assert.match(
    menu,
    /root\.hintTag\(root\.hintItems, "toggle", modelData\.kind\)/,
  )
  assert.match(menu, /root\.hintTag\(root\.hintItems, "weeks", modelData\)/)
  assert.match(
    menu,
    /root\.hintTag\(root\.hintItems, "trophy-swatch", modelData\)/,
  )
  assert.match(
    menu,
    /root\.hintTag\(root\.hintItems, "hero-swatch", modelData\)/,
  )
  assert.match(
    menu,
    /root\.hintTag\(root\.hintItems, "remove-ignored", modelData\)/,
  )
  assert.match(
    menu,
    /root\.hintTag\(root\.hintItems, "remove-alias", modelData\.from\)/,
  )
  assert.match(menu, /root\.hintTag\(root\.hintItems, "help", modelData\.url\)/)
  assert.match(menu, /root\.hintTag\(root\.hintItems, "field-ignored", 0\)/)
  assert.match(menu, /root\.hintTag\(root\.hintItems, "add-alias", 0\)/)
  assert.match(menu, /root\.hintTag\(root\.hintItems, "reset", 0\)/)
  assert.match(menu, /root\.hintTag\(root\.hintItems, "wipe", 0\)/)
})

test("settings back button floats its hint over the header", () => {
  assert.match(panel, /configMenu\.hintTag\(configMenu\.hintItems, "back", 0\)/)
  assert.match(panel, /anchors\.top: configBack\.top/)
  assert.match(panel, /anchors\.right: configBack\.right/)
  assert.match(panel, /onBackRequested: root\.openConfig\(false\)/)
  assert.match(menu, /signal backRequested/)
  assert.match(menu, /add\("back", 0\)/)
  assert.match(menu, /root\.backRequested\(\)/)
})

test("year drawer badges back and year pagers", () => {
  const drawer = qml("YearDrawer.qml")
  assert.match(drawer, /required property bool hintMode/)
  assert.match(drawer, /label: "m"/)
  assert.match(drawer, /label: "b"/)
  assert.match(drawer, /label: "n"/)
  assert.match(
    drawer,
    /show: root\.hintMode && root\.currentYear > root\.oldestDataYear/,
  )
  assert.match(drawer, /show: root\.hintMode && root\.currentYearOffset > 0/)
  assert.match(panel, /hintMode: root\.hintMode/)
  assert.match(panel, /if \(root\.calendarOpen\) \{/)
  assert.match(panel, /root\.openCalendar\(false\)/)
  assert.match(panel, /root\.currentYearOffset \+= 1/)
  assert.match(panel, /root\.currentYearOffset -= 1/)
})

test("keyboard scroll follows the visible surface", () => {
  assert.match(panel, /function scrollFlickable\(flick, dy\)/)
  assert.match(panel, /root\.scrollFlickable\(configScroll, dy\)/)
  assert.match(panel, /root\.scrollFlickable\(panelScroll, dy\)/)
  const drawer = qml("YearDrawer.qml")
  assert.match(drawer, /function scrollBy\(dy\)/)
  assert.match(drawer, /calendarScroll/)
  assert.match(panel, /yearDrawer\.scrollBy\(dy\)/)
})

test("day columns show numbers only as key hints", () => {
  const daybar = comp("WeekDayBar.qml")
  const tick = comp("WeekTick.qml")
  const badge = comp("HintBadge.qml")
  assert.match(daybar, /height: Style\.space\(80\)/)
  assert.doesNotMatch(daybar, /badgeSlot/)
  assert.match(daybar, /show: day\.hintMode/)
  assert.match(daybar, /anchors\.bottom: parent\.bottom/)
  assert.match(daybar, /anchors\.bottom: weekdayLabel\.top/)
  assert.match(trend, /height: Style\.space\(80\) \+ Style\.space\(16\)/)
  assert.match(tick, /parent\.height - Style\.space\(16\)/)
  assert.match(badge, /z: 9999999/)
})

test("hint badges only set declared props", () => {
  const badge = comp("HintBadge.qml")
  const declared = new Set(
    [...badge.matchAll(/required property \w+ (\w+)/g)].map((m) => m[1]),
  )
  assert.ok(!declared.has("foreground"), "no stale foreground prop expected")
  const files = [
    "Panel.qml",
    "WeekTrend.qml",
    "YearDrawer.qml",
    "components/HeroHeader.qml",
    "components/WeekDayBar.qml",
    "components/ConfigMenu.qml",
  ]
  for (const f of files) {
    const src = fs.readFileSync(path.join(__dirname, "..", "qml", f), "utf8")
    let i = 0
    while (true) {
      const j = src.indexOf("HintBadge {", i)
      if (j === -1) break
      let depth = 0
      let p = src.indexOf("{", j)
      const topBindings = []
      while (true) {
        const ch = src[p]
        if (ch === "{") depth++
        else if (ch === "}") {
          depth--
          if (depth === 0) break
        } else if (depth === 1) {
          const m = src.slice(p).match(/^\s*([A-Za-z_][\w.]*)\s*:/)
          if (m) {
            const lineStart = src.lastIndexOf("\n", p) + 1
            const lineEnd = src.indexOf("\n", p)
            const line = src.slice(lineStart, lineEnd)
            // Local property declarations (per-badge tag aliases)
            // are fine; only real assignments must be declared.
            if (!/\bproperty\b/.test(line)) topBindings.push(m[1])
            p += m[0].length - 1
          }
        }
        p++
      }
      for (const b of topBindings) {
        const root = b.split(".")[0]
        assert.ok(
          declared.has(root) ||
            ["anchors", "width", "height", "x", "y", "visible"].includes(root),
          f + " sets undeclared HintBadge prop: " + b,
        )
      }
      i = p + 1
    }
  }
})

test("repeater index is never read inside delegates", () => {
  // Proven headlessly: in a delegate declaring required modelData,
  // reading index yields 0 for every row, while implicit same-named
  // receipt still works. Derive from modelData (Model.weekdayNumber)
  // or pass plain values down instead.
  const files = [
    "Panel.qml",
    "WeekTrend.qml",
    "YearDrawer.qml",
    "MonthRow.qml",
    "components/HeroHeader.qml",
    "components/WeekDayBar.qml",
    "components/ConfigMenu.qml",
    "components/LegendRow.qml",
    "components/InsightCard.qml",
    "components/InsightList.qml",
    "components/CardColumn.qml",
  ]
  for (const f of files) {
    const src = fs.readFileSync(path.join(__dirname, "..", "qml", f), "utf8")
    for (const line of src.split("\n")) {
      const t = line.trim()
      if (t.startsWith("//")) continue
      if (/required property int index/.test(t)) continue
      if (/function \w+\(index/.test(t)) continue
      assert.ok(
        !/(?<![\w."])index(?![\w"':])/.test(t),
        f + " reads repeater index: " + t,
      )
    }
  }
})

test("week header nudges the next arrow after the range text", () => {
  assert.match(trend, /anchors\.right: weekTotalLabel\.left/)
  assert.match(trend, /anchors\.left: prevArrow\.right/)
  assert.match(trend, /anchors\.left: weekLabel\.right/)
  assert.match(trend, /Math\.min\(implicitWidth/)
  assert.match(trend, /id: recordTrophy/)
  assert.match(trend, /recordTrophy\.visible \? recordTrophy\.implicitWidth/)
  assert.doesNotMatch(trend, /space\(76\)/)
})
