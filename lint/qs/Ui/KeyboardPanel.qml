import QtQuick

// Lint-only stand-in for the shell's keyboard-navigable panel frame.
// Covers exactly the API our Panel.qml uses; the real frame lives in
// omarchy-shell and is far richer (focus scopes, layer rules, animation).
Item {
    id: root
    property var anchorItem: null
    property var owner: null
    property QtObject bar: null
    property bool open: false
    property var focusTarget: null
    property real contentWidth: 0
    property real contentHeight: 0

    function fittedContentWidth(w) {
        return w
    }

    function fittedContentHeight(h, max) {
        return Math.min(h, max)
    }
}
