// Tests for the fork's per-project editor tracking (see Model.js,
// "Per-project tracking inside editors").
const test = require("node:test")
const assert = require("node:assert")
const M = require("../js/Model.js")

test("recognises the editors worth splitting, and nothing else", () => {
  for (const app of [
    "code",
    "Code",
    "code-oss",
    "vscodium",
    "cursor",
    "windsurf",
  ])
    assert.equal(M.isEditorApp(app), true, app)
  for (const app of ["google-chrome", "ghostty", "nautilus", "", null])
    assert.equal(M.isEditorApp(app), false, String(app))
})

test("strips the editor suffix, dirty marker and remote decorations", () => {
  assert.equal(
    M.normalizeEditorTitle("Model.js - screen-time - Visual Studio Code"),
    "Model.js - screen-time",
  )
  assert.equal(
    M.normalizeEditorTitle("● Model.js - screen-time - Visual Studio Code"),
    "Model.js - screen-time",
  )
  assert.equal(
    M.normalizeEditorTitle("main.go - api [SSH: box] - Visual Studio Code"),
    "main.go - api",
  )
  assert.equal(M.normalizeEditorTitle("app.py - svc - Cursor"), "app.py - svc")
  assert.equal(M.normalizeEditorTitle(""), "")
  assert.equal(M.normalizeEditorTitle(null), "")
})

test("takes the workspace name, not the file", () => {
  const cases = {
    "Configurar workspaces vi… - Claude - Visual Studio Code": "Claude",
    "Model.js - screen-time - Visual Studio Code": "screen-time",
    "● index.ts - afarmo - Visual Studio Code": "afarmo",
    "main.go - api [SSH: box] - Visual Studio Code": "api",
    // No file open: the only segment is the workspace itself.
    "afarmo - Visual Studio Code": "afarmo",
  }
  for (const [title, project] of Object.entries(cases))
    assert.equal(M.projectForTitle(title), project, title)
})

test("a lone file with no workspace stays on the editor bucket", () => {
  assert.equal(M.projectForTitle("notes.md - Visual Studio Code"), "")
  assert.equal(
    M.projectForTitle("Untitled-1 - Visual Studio Code"),
    "Untitled-1",
  )
  assert.equal(M.projectForTitle(""), "")
  assert.equal(M.projectForTitle(null), "")
})

test("switching files inside a workspace resolves to the same project", () => {
  assert.equal(
    M.projectForTitle("a.ts - afarmo - Visual Studio Code"),
    M.projectForTitle("● b.ts - afarmo - Visual Studio Code"),
  )
})

test("project keys round-trip and are distinguishable from plain apps", () => {
  const k = M.projectKey("afarmo")
  assert.equal(M.isProjectKey(k), true)
  assert.equal(M.isProjectKey("code"), false)
  assert.equal(M.isProjectKey(""), false)
  assert.equal(M.projectKey(""), "")
})

test("the panel shows the project name with its case intact", () => {
  assert.equal(M.displayName(M.projectKey("AFARMO")), "AFARMO")
  assert.equal(M.displayName(M.projectKey("screen-time")), "screen-time")
  // A plain app key still lowercases, so the two never look alike.
  assert.equal(M.displayName("Code"), "code")
})
