import QtQuick

// Minimal runtime stand-in: keeps geometry (track box) and the toggled
// contract; visuals don't matter for layout dumps.
Item {
    id: root
    property int trackHeight: 18
    property bool interactive: true
    property bool checked: false
    property color foreground: "white"
    property color accent: "red"

    signal toggled

    implicitWidth: 40
    implicitHeight: root.trackHeight
}
