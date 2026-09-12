import QtQuick
import qs.Commons

// One masonry column of retro cards.
// Outer-id reads are idiomatic in delegates; muted for the linter.
// qmllint disable unqualified
Column {
    id: column
    required property var cards
    required property color foreground
    required property string fontFamily
    spacing: Style.space(8)

    Component {
        id: cardsDelegate
        InsightCard {
            foreground: column.foreground
            fontFamily: column.fontFamily
        }
    }

    Repeater {
        model: column.cards
        delegate: cardsDelegate
    }
}
// qmllint enable unqualified
