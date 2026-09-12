pragma Singleton
import QtQuick

// Minimal runtime stand-in for the shell Style singleton: identity
// spacing and plausible font sizes. Geometry assertions must stay
// relative (nonzero heights), never absolute pixels.
QtObject {
    function space(n) {
        return n;
    }

    readonly property var font: QtObject {
        readonly property int bodySmall: 13
        readonly property int caption: 11
        readonly property int title: 16
    }
}
