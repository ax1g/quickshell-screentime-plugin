import QtQuick
import qs.Commons
import "../../js/Model.js" as Model

// GitHub-style year heatmap: Monday–Sunday week columns, one cell per
// day, intensity quartiles off the accent. Cells stay large enough to
// read; the grid scrolls horizontally under a thin bar, opening on the
// current month. Month labels crown the week holding the month's 1st;
// hover any cell for its exact total.
// Outer-id reads are idiomatic in delegates; muted for the linter.
// qmllint disable unqualified

Column {
    id: root
    required property var weeks
    // Short month name to reveal on open ("Sep"); "" starts at January.
    required property string currentMonth
    // Sticky scroll: leftmost week column to restore (-1 for default).
    required property int savedWeek
    required property color foreground
    required property string fontFamily
    required property color accent
    required property color panelBackground

    signal positionSaved(int week)

    width: parent.width
    spacing: Style.space(4)

    readonly property int weekCount: root.weeks.length
    readonly property real gap: Style.space(2)
    readonly property real cell: Style.space(10)
    readonly property real colStep: root.cell + root.gap
    readonly property real labelH: Style.space(14)
    readonly property real gridH: 7 * root.cell + 6 * root.gap
    // Scroll state for tests; the bar mirrors canScroll.
    readonly property real scrollX: heatScroll.contentX
    readonly property bool canScroll: heatScroll.contentWidth > heatScroll.width

    function levelColor(level, future) {
        if (future)
            return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04);
        if (level <= 0)
            return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10);
        var alphas = [0.25, 0.45, 0.7, 1.0];
        return Qt.rgba(root.accent.r, root.accent.g, root.accent.b, alphas[Math.min(3, level - 1)]);
    }

    // Sticky position wins; otherwise the current month docks at the
    // right end (past years start at January). Resizes never reset:
    // only new weeks or a new saved pick re-restore.
    function restorePosition() {
        var maxX = Math.max(0, heatScroll.contentWidth - heatScroll.width);
        var target = 0;
        if (root.savedWeek >= 0) {
            target = root.savedWeek * root.colStep;
        } else if (root.currentMonth !== "") {
            for (var i = 0; i < root.weeks.length; i++) {
                if (root.weeks[i].label === root.currentMonth) {
                    target = i * root.colStep - (heatScroll.width - root.colStep);
                    break;
                }
            }
        }
        heatScroll.contentX = Math.max(0, Math.min(target, maxX));
    }

    onWeeksChanged: restorePosition()
    onSavedWeekChanged: restorePosition()
    onCurrentMonthChanged: restorePosition()
    Component.onCompleted: Qt.callLater(restorePosition)

    Flickable {
        id: heatScroll
        width: parent.width
        height: root.labelH + root.gridH + Style.space(4)
        contentWidth: gridRow.width
        contentHeight: height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        interactive: contentWidth > width
        onMovementEnded: {
            var week = Math.round(heatScroll.contentX / root.colStep);
            var maxWeek = Math.max(0, root.weeks.length - 1);
            root.positionSaved(Math.max(0, Math.min(week, maxWeek)));
        }

        Column {
            spacing: Style.space(4)

            // Month labels ride above their week columns and scroll with
            // the grid, clipped to the row so tight neighbours never
            // paint over each other.
            Item {
                width: gridRow.width
                height: root.labelH
                clip: true

                Repeater {
                    model: root.weeks

                    Text {
                        required property var modelData
                        required property int index
                        text: modelData.label || ""
                        visible: text !== ""
                        color: root.foreground
                        opacity: modelData.labelFuture ? 0.25 : 0.45
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        x: index * root.colStep
                        width: root.colStep * 4
                        elide: Text.ElideRight
                    }
                }
            }

            Row {
                id: gridRow
                spacing: root.gap

                Repeater {
                    model: root.weeks

                    Column {
                        id: weekCol
                        required property var modelData
                        spacing: root.gap

                        Repeater {
                            model: weekCol.modelData.days

                            Rectangle {
                                id: cellBox
                                required property var modelData
                                width: root.cell
                                height: root.cell
                                radius: Math.min(2, root.cell / 3)
                                color: modelData ? root.levelColor(modelData.level, modelData.future) : "transparent"

                                MouseArea {
                                    id: cellMouse
                                    anchors.fill: parent
                                    anchors.margins: -2
                                    hoverEnabled: true
                                    enabled: cellBox.modelData !== null && cellBox.modelData.future !== true
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                }

                                ScreenTip {
                                    foreground: root.foreground
                                    fontFamily: root.fontFamily
                                    tipBackground: root.panelBackground

                                    hovered: cellMouse.containsMouse && cellBox.modelData !== null && cellBox.modelData.future !== true
                                    tipText: cellBox.modelData ? Model.formatDate(cellBox.modelData.date) + " \u00b7 " + (cellBox.modelData.ms > 0 ? Model.fmt(cellBox.modelData.ms) : "no data") : ""
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Thin horizontal bar, same idiom as the vertical scrollbars: only
    // visible while the year overflows.
    Item {
        width: parent.width
        height: Math.max(2, Style.space(2))
        visible: heatScroll.contentWidth > heatScroll.width

        Rectangle {
            property real ratio: heatScroll.contentWidth > 0 ? heatScroll.width / heatScroll.contentWidth : 0
            width: Math.max(Style.space(16), heatScroll.width * ratio)
            height: parent.height
            radius: height / 2
            color: root.foreground
            opacity: 0.25
            x: (heatScroll.width - width) * (heatScroll.contentWidth > heatScroll.width ? heatScroll.contentX / (heatScroll.contentWidth - heatScroll.width) : 0)
        }
    }

    // Less → More key, tucked right like the week total.
    Row {
        anchors.right: parent.right
        spacing: Style.space(3)

        Text {
            text: "Less"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
        }

        Repeater {
            model: 5

            Rectangle {
                required property int index
                width: root.cell
                height: root.cell
                radius: Math.min(2, root.cell / 3)
                color: root.levelColor(index, false)
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            text: "More"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
