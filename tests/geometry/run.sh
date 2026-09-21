#!/usr/bin/env bash
# Headless geometry tests for qml/. Skips cleanly without Qt 6.
set -u
HERE="$(dirname "$0")"
BIN="$(command -v qmltestrunner || true)"
for d in /usr/lib/qt6/bin /usr/lib/x86_64-linux-gnu/qt6/bin; do
  if [ -z "$BIN" ] && [ -x "$d/qmltestrunner" ]; then
    BIN="$d/qmltestrunner"
  fi
done
if [ -z "$BIN" ]; then
  echo "SKIP: qmltestrunner not found"
  exit 0
fi
# Every file runs even when an earlier one fails; the exit reports the
# first failure so one red suite cannot hide the rest.
FAIL=0
QT_QPA_PLATFORM=offscreen QML_IMPORT_PATH="$HERE/stubs" "$BIN" -input "$HERE/geometry_test.qml" || FAIL=$?
QT_QPA_PLATFORM=offscreen QML_IMPORT_PATH="$HERE/stubs" "$BIN" -input "$HERE/weektrend_test.qml" || FAIL=$?
QT_QPA_PLATFORM=offscreen QML_IMPORT_PATH="$HERE/stubs" "$BIN" -input "$HERE/timeline_test.qml" || FAIL=$?
QT_QPA_PLATFORM=offscreen QML_IMPORT_PATH="$HERE/stubs" "$BIN" -input "$HERE/heatmap_test.qml" || FAIL=$?
exit $FAIL
