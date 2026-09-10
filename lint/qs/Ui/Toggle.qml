import QtQuick
import qs.Commons

// Lint-only stand-in for the shell's labeled toggle row.
// Covers exactly the API our ConfigMenu uses; visuals, focus handling
// and the sliding switch live in omarchy-shell.
Item {
    id: root
    property string label: ""
    property string description: ""
    property bool checked: false
    property color foreground: Color.foreground
    property color accent: Color.accent
    property string fontFamily: ""
    property real titleSize: 14
    property real descriptionSize: 12

    signal clicked
}
