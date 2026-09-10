import QtQuick
import qs.Commons

// Lint-only stand-in for the shell's bare on/off switch.
// Covers exactly the API our ConfigMenu uses; track, knob, cursor ring
// and theme rounding live in omarchy-shell.
Item {
    id: root
    property bool checked: false
    property color foreground: Color.foreground
    property color accent: Color.accent
    property int trackHeight: 22

    signal toggled
}
