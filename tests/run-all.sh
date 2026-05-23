#!/usr/bin/env bash
# Run the full test suite: Node tests (pure JS logic) + QML tests
# (DraggableList Loader forwarding, etc.). Run from the project root.

set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)

echo "── Node tests (logic) ────────────────────────────────────────"
cd "$ROOT"
node --test tests/*.test.mjs

echo ""
echo "── QML tests (rendering / data forwarding) ───────────────────"
QMLTESTRUNNER="${QMLTESTRUNNER:-qmltestrunner-qt6}"
if command -v "$QMLTESTRUNNER" >/dev/null 2>&1; then
    "$QMLTESTRUNNER" -input "$ROOT/tests/qml"
else
    echo "skip: $QMLTESTRUNNER not found (install qt6-qtdeclarative-devel)"
    exit 0
fi
