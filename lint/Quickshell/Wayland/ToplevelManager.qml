pragma Singleton
import QtQuick

// Lint-only stand-in for Quickshell.Wayland.ToplevelManager.
// Toplevels stay dynamically typed; this repo only reads appId off them.
QtObject {
    id: root
    property var activeToplevel: null
    property var toplevels: []

    signal activeToplevelChanged
}
