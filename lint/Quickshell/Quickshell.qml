pragma Singleton
import QtQuick

// Lint-only stand-in for Quickshell's application singleton.
// Covers exactly what this repo (and the vendored shell files) use:
// environment lookup. `screens` exists on the real object; nothing here
// reads past it, so it stays dynamically typed.
QtObject {
    id: root
    property var screens: []

    function env(name) {
        return ""
    }
}
