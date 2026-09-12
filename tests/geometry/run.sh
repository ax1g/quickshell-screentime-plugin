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
QT_QPA_PLATFORM=offscreen QML_IMPORT_PATH="$HERE/stubs" "$BIN" -input "$HERE/geometry_test.qml" || exit $?
QT_QPA_PLATFORM=offscreen QML_IMPORT_PATH="$HERE/stubs" "$BIN" -input "$HERE/weektrend_test.qml"
