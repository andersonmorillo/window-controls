#!/usr/bin/env bash
set -euo pipefail

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_runtime=$(mktemp -d)
trap 'rm -rf -- "$test_runtime"' EXIT
mkdir -p "$test_runtime/runtime" "$test_runtime/cache" "$test_runtime/state" "$test_runtime/data" "$test_runtime/config"
chmod 700 "$test_runtime/runtime"
test_wayland_display=${WAYLAND_DISPLAY:?A running Wayland session is required}
if [[ "$test_wayland_display" != /* ]]; then
    test_wayland_display="${XDG_RUNTIME_DIR:?}/$test_wayland_display"
fi
cp -- "$test_dir/../Panel.qml" "$test_dir/../ControlButton.qml" "$test_dir/../Controls.js" "$test_dir/../State.js" \
    "$test_dir/../Service.qml" "$test_dir/../BarWidget.qml" "$test_dir/../BarModel.js" "$test_runtime/config/"
sed 's#import ".." as Plugin#import "." as Plugin#' "$test_dir/Smoke.qml" > "$test_runtime/config/Smoke.qml"

QT_QPA_PLATFORM=wayland WAYLAND_DISPLAY="$test_wayland_display" QT_QPA_PLATFORMTHEME=basic \
QT_QUICK_CONTROLS_STYLE=Basic QT_QUICK_BACKEND=software \
XDG_RUNTIME_DIR="$test_runtime/runtime" XDG_CACHE_HOME="$test_runtime/cache" \
XDG_STATE_HOME="$test_runtime/state" XDG_DATA_HOME="$test_runtime/data" \
timeout 20s quickshell --no-color -p "$test_runtime/config/Smoke.qml"
