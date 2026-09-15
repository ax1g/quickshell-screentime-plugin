// Tests for the fork's per-site browser tracking (see Model.js,
// "Per-site tracking inside browsers").
const test = require("node:test")
const assert = require("node:assert")
const M = require("../js/Model.js")

const R = [] // empty => defaultSiteRules()

test("strips the browser suffix and notification noise", () => {
  assert.equal(M.normalizeTitle("(56) WhatsApp - Google Chrome"), "WhatsApp")
  assert.equal(M.normalizeTitle("[3] Inbox — Mozilla Firefox"), "Inbox")
  assert.equal(M.normalizeTitle("Docs - Zen Browser"), "Docs")
  assert.equal(M.normalizeTitle(""), "")
  assert.equal(M.normalizeTitle(null), "")
})

test("a ticking unread counter resolves to the same site", () => {
  assert.equal(
    M.siteForTitle("(56) WhatsApp - Google Chrome", R),
    M.siteForTitle("(57) WhatsApp - Google Chrome", R),
  )
})

test("matches the sites the rules name", () => {
  const cases = {
    "(56) WhatsApp - Google Chrome": "whatsapp.com",
    "(3) Facebook - Google Chrome": "facebook.com",
    "Free Videos - XVIDEOS.COM - Google Chrome": "xvideos.com",
    "Elon Musk (@elonmusk) / X - Google Chrome": "x.com",
    "Inbox (12) - me@example.com - Gmail - Google Chrome": "gmail.com",
    "Some clip - YouTube - Google Chrome": "youtube.com",
  }
  for (const [title, site] of Object.entries(cases))
    assert.equal(M.siteForTitle(title, R), site, title)
})

test("an unmatched title stays on the browser bucket", () => {
  assert.equal(
    M.siteForTitle("Portfolio da empresa - Propostas - Google Chrome", R),
    "",
  )
  assert.equal(M.siteKey(""), "")
})

test("user rules take precedence over the defaults", () => {
  const mine = [{ match: "\\bhostmoz\\b", site: "hostmoz.net" }]
  assert.equal(
    M.siteForTitle("hostmoz - WHM - Google Chrome", mine),
    "hostmoz.net",
  )
  // WhatsApp is a default only; a non-empty user list replaces the defaults.
  assert.equal(M.siteForTitle("WhatsApp - Google Chrome", mine), "")
})

test("an invalid regex is skipped, not thrown", () => {
  const bad = [
    { match: "([unclosed", site: "nope" },
    { match: "WhatsApp", site: "ok" },
  ]
  assert.equal(M.siteForTitle("WhatsApp - Google Chrome", bad), "ok")
})

test("site keys round-trip and never collide with an appId", () => {
  const k = M.siteKey("whatsapp.com")
  assert.equal(k, "site:whatsapp.com")
  assert.ok(M.isSiteKey(k))
  assert.ok(!M.isSiteKey("google-chrome"))
  assert.equal(M.displayName(k), "whatsapp.com")
  // canonicalApp must leave site keys alone or history would be rewritten.
  assert.equal(M.canonicalApp(k), k)
  // The chromium web-app path still wins for real web-app windows.
  assert.equal(
    M.displayName("chrome-web.whatsapp.com__-Default"),
    "web.whatsapp.com",
  )
})

test("isBrowserApp covers aliases, not terminals", () => {
  assert.ok(M.isBrowserApp("google-chrome"))
  assert.ok(M.isBrowserApp("chrome"))
  assert.ok(M.isBrowserApp("zen-bin"))
  assert.ok(!M.isBrowserApp("foot"))
  assert.ok(!M.isBrowserApp("com.mitchellh.ghostty"))
  assert.ok(!M.isBrowserApp(""))
})

test("every default rule compiles and is well formed", () => {
  for (const r of M.defaultSiteRules()) {
    assert.ok(r.match && r.site, JSON.stringify(r))
    assert.doesNotThrow(() => new RegExp(r.match, "i"), r.match)
  }
})
