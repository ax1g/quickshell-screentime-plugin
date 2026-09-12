# Geometry tests

Headless runtime checks for `qml/`: instantiates the real components with
minimal shell stubs and asserts structural geometry (rows that must have
height, buttons that must exist with size). This catches the class of bug
no linter sees — e.g. a fill-anchored `MouseArea` collapsing an
implicit-height `Column` to zero.

This is NOT `lint/` (import stubs for `qmllint`, never hand-edited,
verbatim snapshots). `stubs/` below is hand-written test scaffolding for
execution: a 1px spacing scale and plausible font sizes, so assertions use
relative (`> 0`) thresholds, never absolute pixels.

Run: `./run.sh` (skips cleanly when Qt 6 `qmltestrunner` is absent).
Requires no display (`QT_QPA_PLATFORM=offscreen`).
