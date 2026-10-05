#!/usr/bin/env bash
set -euo pipefail

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_runtime=$(mktemp -d)
trap 'rm -rf -- "$test_runtime"' EXIT
mkdir -p "$test_runtime/runtime" "$test_runtime/cache" "$test_runtime/state" "$test_runtime/data" "$test_runtime/config"
chmod 700 "$test_runtime/runtime"
cp -- "$test_dir/../Controls.js" "$test_dir/../State.js" "$test_runtime/config/"
sed 's#import "../State.js" as WindowState#import "State.js" as WindowState#' "$test_dir/Persistence.qml" > "$test_runtime/config/Persistence.qml"

run_phase() {
    local test_phase=$1
    local test_log="$test_runtime/$test_phase.log"
    if ! env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY \
        WINDOW_CONTROLS_PERSISTENCE_PHASE="$test_phase" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=basic \
        QT_QUICK_CONTROLS_STYLE=Basic QT_QUICK_BACKEND=software \
        XDG_RUNTIME_DIR="$test_runtime/runtime" XDG_CACHE_HOME="$test_runtime/cache" \
        XDG_STATE_HOME="$test_runtime/state" XDG_DATA_HOME="$test_runtime/data" \
        XDG_CONFIG_HOME="$test_runtime/config" \
        timeout 15s quickshell --no-color -p "$test_runtime/config/Persistence.qml" > "$test_log" 2>&1; then
        cat -- "$test_log" >&2
        return 1
    fi
    if ! rg -q "window-controls persistence $test_phase passed" "$test_log"; then
        cat -- "$test_log" >&2
        return 1
    fi
}

run_phase write
run_phase read
printf '%s\n' 'Settings persistence passed across two isolated Quickshell processes'
