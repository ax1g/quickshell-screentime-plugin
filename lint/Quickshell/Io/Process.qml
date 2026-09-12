import QtQuick

// Lint-only stand-in for Quickshell.Io.Process.
QtObject {
    id: root
    property var command: []
    // Deliberately var, not the real QVariantHash: a JS literal assigned
    // to a Hash-typed property warns (Map-vs-Hash inference), while var
    // accepts both shapes with no loss — lint-only either way.
    property var environment: ({})
    property bool running: false
    property var stdout: null
    property var stderr: null

    signal exited
}
