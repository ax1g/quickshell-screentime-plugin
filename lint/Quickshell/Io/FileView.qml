import QtQuick

// Lint-only stand-in for Quickshell.Io.FileView.
QtObject {
    id: root
    property string path: ""
    property bool printErrors: false
    property bool atomicWrites: false
    default property FileViewAdapter adapter

    signal adapterUpdated
    signal loaded
    signal loadFailed
    signal saveFailed(var error)

    function reload() {
    }

    function writeAdapter() {
    }
}
