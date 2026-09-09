pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../../js/Model.js" as Model

// Usage-pattern rows. Rows carry kind/dir meaning, so rendering never
// parses label text to decide color or glyph.
Column {
    id: root
    required property var rows
    required property color foreground
    required property string fontFamily
    required property color accent
    required property color urgent

    readonly property var insightPalette: Model.insightColors(accent, urgent)

    width: parent.width
    spacing: Style.space(10)

    function deltaArrow(dir) {
        if (dir === "up")
            return "\u2197";
        if (dir === "down")
            return "\u2198";
        return "\u2192";
    }

    // Glyph per row kind: filled star, trend arrow, hollow star.
    function insightIcon(kind, dir) {
        if (kind === "top")
            return "\u2605";
        if (kind === "delta")
            return deltaArrow(dir);
        if (kind === "busiest")
            return "\u2606";
        return "";
    }

    function insightIconColor(kind, dir) {
        if (kind === "top")
            return root.insightPalette.star;
        if (kind === "delta") {
            if (dir === "up")
                return root.insightPalette.up;
            if (dir === "down")
                return root.insightPalette.down;
            return Qt.darker(root.foreground, 1.5);
        }
        if (kind === "busiest")
            return root.insightPalette.busiest;
        return root.foreground;
    }

    // Only the signed delta carries a color; the rest stays neutral.
    function insightValueColor(kind, dir) {
        if (kind === "delta" && (dir === "up" || dir === "down"))
            return insightIconColor(kind, dir);
        return root.foreground;
    }

    // Outer-id reads are idiomatic in delegates; muted for the linter.
    // qmllint disable unqualified
    Repeater {
        model: root.rows

        Item {
            id: rowDelegate
            required property var modelData

            readonly property string label: String(modelData.label || "")
            readonly property string value: String(modelData.value || "")
            readonly property string kind: String(modelData.kind || "")
            readonly property string dir: String(modelData.dir || "")

            width: parent.width
            height: implicitHeight
            implicitHeight: Math.max(iconText.implicitHeight, Math.max(labelText.implicitHeight, valueText.implicitHeight))

            Text {
                id: iconText
                text: root.insightIcon(rowDelegate.kind, rowDelegate.dir || null)
                color: root.insightIconColor(rowDelegate.kind, rowDelegate.dir || null)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall + 3
                width: Style.space(16)
                horizontalAlignment: Text.AlignHCenter
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                id: labelText
                text: rowDelegate.label
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.left: iconText.right
                anchors.leftMargin: Style.space(5)
                anchors.right: valueText.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
            }

            Text {
                id: valueText
                text: rowDelegate.value
                color: root.insightValueColor(rowDelegate.kind, rowDelegate.dir || null)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                width: parent.width * 0.55
                horizontalAlignment: Text.AlignRight
            }
        }
    }
    // qmllint enable unqualified
}
