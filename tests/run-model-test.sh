#!/usr/bin/env bash
# Run the JavaScript helper tests inside the same QML engine the widget uses.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
qml_runtime="${QML_RUNTIME:-/usr/sbin/qml6}"

if [ ! -x "$qml_runtime" ]; then
  echo "model tests skipped: $qml_runtime not found" >&2
  exit 0
fi

output="$(
  TZ=UTC QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES='*.debug=true' \
    "$qml_runtime" "$here/model-test.qml" 2>&1 || true
)"

printf '%s\n' "$output" | grep -a 'qml:' || true

if printf '%s\n' "$output" | grep -q 'MODEL TEST FAILURES'; then
  exit 1
fi
if ! printf '%s\n' "$output" | grep -q 'MODEL TESTS OK'; then
  echo "model tests did not run" >&2
  exit 1
fi
