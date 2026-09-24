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

test("config menu threads prefs with explicit signals", () => {
  for (const sig of [
    "yearlyToggled",
    "timelineToggled",
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
  // Option rows read live option models and report the pick back.
  assert.match(menu, /model: root\.weekOptions/)
  assert.match(menu, /root\.weekWindowSelected\(modelData\)/)
  assert.match(panel, /function selectWeekWindow\(count\)/)
  assert.match(panel, /hostWidget\.setSetting/)
  assert.match(bar, /function setSetting\(key, value\)/)
})

test("settings writes never drop stored keys", () => {
  // Early writes (before delivery, or while the shell API is unreachable)
  // accumulate in pendingWrites and merge into every built entry, so the
  // shell never receives a partial entry that would lose the user's config.
  assert.match(bar, /property var pendingWrites/)
  assert.match(bar, /property bool settingsReady: false/)
  assert.match(bar, /function flushSettings\(\)/)
  assert.match(bar, /root\.flushSettings\(\)/)
  // Own optimistic writes must not fake delivery.
  assert.match(bar, /property bool writingSettings/)
  assert.match(bar, /if \(!root\.writingSettings\)/)
  assert.match(bar, /updateEntryInline\(root\.moduleName, entry\)/)
})

test("toggles are mini shell switches in panel-styled rows", () => {
  assert.match(menu, /ToggleSwitch \{/)
  // The row owns the click (and the switch drops its cursor-ring pad,
  // so the track aligns flush with the boxes and swatches).
  assert.match(menu, /interactive: false/)
  assert.match(menu, /onToggled: root\.activate\(modelData\.kind\)/)
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

test("hero icon color overrides the hourglass and persists", () => {
  assert.match(
    panel,
    /Model\.pickSwatch\(root\.prefs\.heroColor, root\.heroDefaultColor\)/,
  )
  assert.match(panel, /function selectHeroColor\(color\)/)
  assert.match(panel, /writeSetting\("heroColor", c\)/)
  assert.match(panel, /heroColor: root\.heroColor/)
  // Empty follows the theme foreground, so old installs keep it.
  assert.match(panel, /readonly property string heroDefaultColor: ""/)
  assert.match(
    menu,
    /root\.heroColorOptions\.indexOf\(root\.heroColor\) === -1/,
  )
  assert.match(menu, /root\.heroColorSelected\(root\.heroColor\)/)
})

test("tracking prefs normalize in the panel and filter the active day", () => {
  assert.match(panel, /Model\.parseIgnoredApps\(root\.prefs\.ignoredApps\)/)
  assert.match(panel, /Model\.parseAppAliases\(root\.prefs\.appAliases\)/)
  assert.match(panel, /setTrackingPrefs\(root\.ignoredList, root\.appAliases\)/)
  assert.match(panel, /Model\.filterIgnoredDay\(Model\.dayFor/)
  for (const sig of [
    "ignoredAdded",
    "ignoredRemoved",
    "aliasAdded",
    "aliasRemoved",
  ]) {
    assert.match(menu, new RegExp("signal " + sig))
  }
})

test("settings group into section cards with a danger zone", () => {
  assert.match(menu, /text: "DANGER ZONE"/)
  assert.match(menu, /id: dangerBody/)
})

test("daily goal threads from prefs to the bar badge", () => {
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
  assert.match(panel, /writeSetting\("dailyGoalLog", Model\.logGoalChange/)
  assert.match(bar, /readonly property bool goalReached/)
})

test("icon-only glyph matches shell status icon geometry", () => {
  // Match BarIconButton: an icon canvas with the shared status-icon
  // font token.
  assert.match(bar, /id: iconCanvas/)
  assert.match(bar, /fontSize: Style\.bar\.iconFont/)
})

test("right-click cycles full, limit-left, icon-only with a limit on", () => {
  // Without a limit the click keeps flipping full and icon-only.
  assert.match(bar, /function cycleBarMode\(\)/)
  assert.match(bar, /root\.dailyGoalHours <= 0/)
  assert.match(bar, /root\.setSetting\("iconOnly", !root\.iconOnly\)/)
  // With a limit the middle stop shows the remaining time instead of
  // the accrued total, and the reached badge yields to it.
  assert.match(bar, /root\.setSetting\("limitLeft", true\)/)
  assert.match(bar, /root\.setSetting\("limitLeft", false\)/)
  assert.match(bar, /" left"/)
  assert.match(bar, /root\.displayLabel/)
  assert.match(bar, /root\.goalReached && !root\.limitLeft\) \? " !" : ""/)
})

test("wipe-all stages through the menu into the service", () => {
  assert.match(service, /function resetAll\(\)/)
  assert.match(menu, /signal wipeRequested/)
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
  assert.match(panel, /root\.service\.setKeepDays\(root\.effectiveKeepDays\)/)
  // Totals live on forever; the footprint readout stays on the menu.
  assert.match(
    panel,
    /Model\.storageSummary\(root\.days, root\.months, root\.years\)/,
  )
  assert.match(menu, /required property string storageLabel/)
})

test("first-run onboarding shows coach marks until anything is tracked", () => {
  assert.match(panel, /readonly property bool showOnboarding/)
  assert.match(
    panel,
    /root\.storageSummary\.totalMs <= 0 && root\.dayTotal <= 0/,
  )
  assert.match(panel, /visible: root\.showOnboarding/)
  assert.match(panel, /No screen time yet/)
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
  // Home gear sweeps as settings opens; returning home turns the
  // hourglass; the yearly calendar swings once on entry.
  assert.match(hero, /gearSpin\.restart\(\);/)
  assert.match(hero, /function spinHourglass\(\)/)
  assert.match(panel, /function celebrateHome\(\)/)
  assert.match(panel, /heroHeader\.spinHourglass\(\)/)
  assert.match(drawer, /function swingCalendar\(\)/)
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

test("the week window repushes retention", () => {
  assert.match(panel, /onWeekCountChanged: root\.pushTrackingPrefs\(\)/)
})

test("settings header icon returns to the main panel", () => {
  assert.match(
    panel,
    /id: configHeroIconMouse[\s\S]*?onClicked: root\.openConfig\(false\)/,
  )
})

test("help section links out to the tracker and marketplace", () => {
  assert.match(menu, /issues\/new/)
  assert.match(menu, /plugin\.html\?id=agx\.screen-time/)
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
  assert.match(menu, /"v" \+ root\.pluginVersion/)
})

test("settings header reads Settings", () => {
  assert.match(panel, /text: "Settings"/)
})

test("year hero opens straight into the pager", () => {
  const drawer = qml("YearDrawer.qml")
  assert.doesNotMatch(drawer, /monthsActive/)
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
  assert.match(panel, /id: configDrawer/)
  assert.match(panel, /z: -1/)
})

test("alias row flows from, arrow, to, save", () => {
  assert.match(menu, /id: aliasInputRow/)
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

test("settings inputs show a focus ring", () => {
  for (const id of ["ignoredInput", "aliasFromInput", "aliasToInput"]) {
    assert.match(
      menu,
      new RegExp("border\\.color: " + id + "\\.activeFocus \\? root\\.accent"),
    )
  }
})

test("removing an alias unfolds today through the inverse map", () => {
  assert.match(panel, /root\.service\.refoldToday\(inverse\)/)
})

test("settings inputs use Qt's real cursor, not a hand-rolled one", () => {
  // The custom delegate rendered frozen and stayed visible without focus;
  // the default caret blinks and hides with focus.
  assert.doesNotMatch(menu, /cursorDelegate/)
  assert.doesNotMatch(menu, /cursorVisible/)
})

test("settings inputs fill their boxes for full-width taps", () => {
  // anchors.fill must sit on the input itself: an explicit height would
  // shrink the tap target, uniform padding would inflate it.
  for (const id of ["ignoredInput", "aliasFromInput", "aliasToInput"]) {
    assert.match(
      menu,
      new RegExp(
        "id: " +
          id +
          "(?:\\s*\\n\\s*[^\\n]*){0,8}?\\s*\\n\\s*anchors\\.fill: parent",
      ),
      id + " fills its box",
    )
  }
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

test("hint mode toggles on f and routes with guards", () => {
  assert.match(panel, /property bool hintMode: false/)
  assert.match(panel, /if \(t === "f" \|\| t === "F"\)/)
  assert.match(panel, /function activateHint\(tag\)/)
  // Esc exits hint mode instead of closing the panel.
  assert.match(panel, /if \(root\.hintMode\)\s*\n\s*root\.hintMode = false/)
  // A handled tag always exits the mode.
  assert.match(panel, /if \(handled\)\s*\n\s*return true;/)
  // Guards ride on the routes: year needs its drawer, pagers need data,
  // day cells need tracked time.
  assert.match(panel, /tag === "y" && !root\.hideYearly/)
  assert.match(panel, /tag === "b" && root\.expanded/)
  assert.match(panel, /!day\.isFuture && \(Number\(day\.ms\) \|\| 0\) > 0/)
  assert.match(
    panel,
    /if \(root\.activateHint\(key\)\)\s*\n\s*root\.hintMode = false;/,
  )
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

test("main surfaces badge hint letters only when actionable", () => {
  const daybar = comp("WeekDayBar.qml")
  assert.match(hero, /required property bool hintMode/)
  assert.match(hero, /required property color accent/)
  assert.match(panel, /hintMode: root\.hintMode/)
  assert.match(panel, /accent: Color\.accent/)
  assert.match(trend, /required property bool hintMode/)
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

test("settings hint buffer resolves two-letter tags", () => {
  assert.match(panel, /property string hintBuffer: ""/)
  assert.match(panel, /root\.hintBuffer \+= key/)
  assert.match(panel, /if \(root\.hintBuffer\.length >= 2\)/)
  assert.match(panel, /if \(configMenu\.activateHint\(tag\)\)/)
})

test("settings hint commits run through the registry and release focus", () => {
  assert.match(menu, /function buildHintItems\(\)/)
  assert.match(menu, /function hintTag\(items, kind, sub\)/)
  assert.match(menu, /function activateHint\(tag\)/)
  // Alias removal through hints restores outright: re-adding undoes it.
  assert.match(menu, /root\.aliasRemoved\(sub\)/)
  // Committing releases the keyboard back to shortcuts.
  assert.match(menu, /ignoredInput\.focus = false/)
  assert.match(menu, /aliasToInput\.focus = false/)
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
  assert.match(
    drawer,
    /show: root\.hintMode && root\.currentYear > root\.oldestDataYear/,
  )
  assert.match(drawer, /show: root\.hintMode && root\.currentYearOffset > 0/)
  assert.match(panel, /hintMode: root\.hintMode/)
  assert.match(panel, /if \(root\.calendarOpen\) \{/)
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

test("week bars and pager arrows carry tooltips", () => {
  const daybar = comp("WeekDayBar.qml")
  const arrow = comp("PagerArrow.qml")
  // Day bars show exact time on dwell; the axis only renders whole hours.
  assert.match(daybar, /required property color tipBackground/)
  assert.match(
    daybar,
    /tipText: day\.modelData\.label \+ " \\u00b7 " \+ Model\.fmt\(day\.modelData\.ms\)/,
  )
  // Arrow tips are opt-in so call sites without a background stay unchanged.
  assert.match(arrow, /property string tipText: ""/)
  assert.match(
    arrow,
    /hovered: arrowMouse\.containsMouse && arrow\.tipText !== ""/,
  )
  assert.match(trend, /tipText: "Previous week"/)
  assert.match(trend, /tipText: "Next week"/)
  assert.match(trend, /tipBackground: root\.tipBackground/)
})

test("year pager, back buttons and gear carry tooltips", () => {
  const drawer = qml("YearDrawer.qml")
  const back = comp("BackButton.qml")
  // BackButton tips are opt-in like PagerArrow, so existing call sites
  // stay valid without a background.
  assert.match(back, /property string tipText: ""/)
  assert.match(
    back,
    /hovered: actionMouse\.containsMouse && action\.tipText !== ""/,
  )
  // The year drawer reuses its own panel background for tips.
  assert.match(drawer, /tipText: "Previous year"/)
  assert.match(drawer, /tipText: "Next year"/)
  assert.match(drawer, /tipText: "Back to screen time"/)
  assert.match(drawer, /tipBackground: root\.panelBackground/)
  assert.match(panel, /tipText: "Back to screen time"/)
  // The hero gear needs the bar background threaded through.
  assert.match(hero, /required property color tipBackground/)
  assert.match(hero, /tipText: "Settings"/)
  assert.match(
    panel,
    /tipBackground: root\.bar \? root\.bar\.background : Color\.background/,
  )
})
test("timeline hides completely via setting, with its icon", () => {
  assert.match(panel, /hideTimeline: root\.prefs\.hideTimeline === true/)
  assert.match(panel, /root\.hideTimeline \? "apps" : Model\.parseDayView/)
  assert.match(menu, /signal timelineToggled/)
  assert.match(panel, /writeSetting\("hideTimeline", !root\.hideTimeline\)/)
  assert.match(menu, /shown: !root\.hideTimeline/)
  assert.match(hero, /required property bool hideTimeline/)
  assert.match(hero, /visible: !heroHeader\.hideTimeline/)
})

test("browsers expand into merged site rows via setting", () => {
  assert.match(panel, /expandBrowser: root\.prefs\.expandBrowser === true/)
  // Donut and legend share one source list so they always agree.
  assert.match(panel, /Model\.expandedAppList\(root\.activeDay\)/)
  assert.match(panel, /Model\.groupedApps\(root\.listedApps/)
  assert.match(menu, /signal expandBrowserToggled/)
  assert.match(panel, /writeSetting\("expandBrowser", !root\.expandBrowser\)/)
  assert.match(menu, /shown: root\.expandBrowser/)
})

test("day view swaps the donut page and the timeline page", () => {
  // Donut by default; the retired demo toggle still opts in.
  assert.match(
    panel,
    /Model\.parseDayView\(root\.prefs\.dayView, root\.prefs\.hideDayTimeline\)/,
  )
  // The toggle lives with the settings gear at the top.
  assert.match(hero, /required property string dayView/)
  assert.match(hero, /signal dayViewToggled/)
  assert.match(hero, /id: dayToggle/)
  assert.match(panel, /dayView: root\.dayView/)
  assert.match(panel, /onDayViewToggled/)
  // One Model view call over the active day's spans, threaded down.
  assert.match(
    panel,
    /Model\.daySpanView\(root\.activeDay, root\.activeDayKey, Color\.accent\)/,
  )
  assert.match(panel, /DayTimeline \{/)
  assert.match(panel, /visible: root\.dayView === "apps"/)
  assert.match(panel, /visible: root\.dayView === "timeline"/)
  assert.match(
    panel,
    /segments: root\.daySpans \? root\.daySpans\.segments : \[\]/,
  )
  assert.match(panel, /axis: root\.daySpans \? root\.daySpans\.axis : \[\]/)
  assert.match(
    panel,
    /writeSetting\("dayView", root\.dayView === "timeline" \? "apps" : "timeline"\)/,
  )
  // The timeline page shows only the strip, its legend and the
  // hourly chart; onboarding and the week patterns stay exclusive
  // to the main panel.
  assert.match(
    panel,
    /visible: root\.showOnboarding && root\.dayView === "apps"/,
  )
  assert.match(panel, /visible: root\.expanded && root\.dayView === "apps"/)
  assert.match(panel, /Model\.dayHourlyView\(root\.activeDay, Color\.accent\)/)
  assert.match(panel, /HourlyChart \{/)
  assert.match(panel, /hours: root\.dayHours \? root\.dayHours\.hours : \[\]/)
  assert.match(panel, /peakHour: root\.dayHours \? root\.dayHours\.peakHour : -1/)
  // The hero toggle answers to d like the yearly g.
  assert.match(panel, /tag === "d"/)
})

test("year graph toggles bars and heatmap in place with a persisted mode", () => {
  const drawer = qml("YearDrawer.qml")
  const heatmap = comp("YearHeatmap.qml")
  // Anything unset renders bars like before.
  assert.match(panel, /Model\.parseYearGraph\(root\.prefs\.yearGraph\)/)
  assert.match(panel, /yearGraph: root\.yearGraph/)
  assert.match(drawer, /signal yearGraphSelected\(string mode\)/)
  assert.match(panel, /writeSetting\("yearGraph", mode\)/)
  // The toggle docks by the Back button, mirroring the main
  // panel's day toggle by the settings gear.
  assert.match(drawer, /id: graphToggle/)
  assert.match(drawer, /anchors\.right: backCorner\.left/)
  // The drawer swaps the graphs where the month bars lived.
  assert.match(drawer, /visible: root\.yearGraph === "bars"/)
  assert.match(drawer, /visible: root\.yearGraph === "heatmap"/)
  assert.match(drawer, /YearHeatmap \{/)
  // Sticky scroll is year-scoped; the mode and position persist.
  assert.match(
    panel,
    /Model\.parseHeatmapPos\(root\.prefs\.heatmapPos, root\.currentYear\)/,
  )
  assert.match(heatmap, /signal positionSaved\(int week\)/)
  assert.match(panel, /writeSetting\("heatmapPos", pos\)/)
  // Hint mode flips the graph with g inside the drawer.
  assert.match(panel, /tag === "g"/)
})

test("retro cards split by measured heights with a deferred pass", () => {
  const drawer = qml("YearDrawer.qml")
  // Greedy shortest-column masonry, not estimated line scores.
  assert.match(drawer, /function splitCards\(\)/)
  assert.match(drawer, /id: measureTimer/)
  assert.match(drawer, /measureTimer\.restart\(\)/)
  assert.match(drawer, /id: leftColumn/)
  assert.match(drawer, /id: rightColumn/)
  // Re-splits run on facts/width changes only — never on heights —
  // so layout cannot loop against itself.
  assert.doesNotMatch(drawer, /onHeightChanged/)
})

test("main panel grows with content instead of scrolling", () => {
  // No height cap: the framework still clamps to the screen, and j/k
  // keep moving contentY on short screens.
  assert.match(
    panel,
    /contentHeight: panel\.fittedContentHeight\(panelColumn\.implicitHeight\)/,
  )
  const scroll = panel.match(/id: panelScroll[\s\S]*?Column \{/)
  assert(scroll, "panelScroll block exists")
  assert(scroll[0].includes("interactive: false"))
})
