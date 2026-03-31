#!/bin/bash
set -euo pipefail

TARGET_DIR_WAS_SET=false
if [[ -n "${TARGET_DIR:-}" ]]; then
    TARGET_DIR_WAS_SET=true
fi

TARGET_DIR="${TARGET_DIR:-$HOME/Library/Application Support/mihomo-party}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OVERRIDE_NAME="Loyalsoldier白名单 + Claude专用"
OVERRIDE_SOURCE="$SCRIPT_DIR/override/loyalsoldier-whitelist-claude.yaml"
STATE_SCRIPT="$SCRIPT_DIR/sync_install_state.rb"
STAGE_DIR=""
DEFAULT_TARGET_DIR="${DEFAULT_TARGET_DIR:-$HOME/Library/Application Support/mihomo-party}"
APP_CONTROL_MODE="${APP_CONTROL_MODE:-auto}"
APP_NAME="Clash Party"
APP_PROCESS_MATCH="/Applications/Clash Party.app/Contents/Resources/sidecar/mihomo"
APP_WAS_RUNNING=false
log_step() {
    echo "    $*"
}

require_command() {
    local command_name="$1"
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Error: required command not found: $command_name" >&2
        exit 1
    fi
}

copy_atomically() {
    local source_file="$1"
    local target_file="$2"
    local tmp_file

    tmp_file="$(mktemp "${target_file}.tmp.XXXXXX")"
    cp "$source_file" "$tmp_file"
    mv "$tmp_file" "$target_file"
}

cleanup() {
    if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
        rm -rf "$STAGE_DIR"
    fi
}

trap cleanup EXIT

app_control_enabled() {
    case "$APP_CONTROL_MODE" in
        always)
            return 0
            ;;
        never)
            return 1
            ;;
        auto)
            [[ "${TARGET_DIR%/}" == "${DEFAULT_TARGET_DIR%/}" ]]
            return
            ;;
        *)
            echo "Error: invalid APP_CONTROL_MODE: $APP_CONTROL_MODE" >&2
            exit 1
            ;;
    esac
}

app_is_running() {
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || pgrep -f "$APP_PROCESS_MATCH" >/dev/null 2>&1
}

app_is_ready() {
    pgrep -x "$APP_NAME" >/dev/null 2>&1 && pgrep -f "$APP_PROCESS_MATCH" >/dev/null 2>&1
}

stop_app_if_running() {
    if ! app_control_enabled; then
        return 0
    fi

    if ! app_is_running; then
        return 0
    fi

    APP_WAS_RUNNING=true
    echo "==> Stopping Clash Party"
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true

    for _ in $(seq 1 30); do
        if ! app_is_running; then
            log_step "stopped $APP_NAME"
            return 0
        fi
        sleep 1
    done

    pkill -TERM -x "$APP_NAME" >/dev/null 2>&1 || true
    pkill -TERM -f "$APP_PROCESS_MATCH" >/dev/null 2>&1 || true

    for _ in $(seq 1 10); do
        if ! app_is_running; then
            log_step "stopped $APP_NAME after TERM"
            return 0
        fi
        sleep 1
    done

    echo "Error: failed to stop $APP_NAME before installing files." >&2
    exit 1
}

restart_app_if_needed() {
    if ! app_control_enabled || [[ "$APP_WAS_RUNNING" != "true" ]]; then
        return 0
    fi

    echo "==> Restarting Clash Party"
    open -a "$APP_NAME"

    for _ in $(seq 1 45); do
        if app_is_ready; then
            log_step "restarted $APP_NAME"
            return 0
        fi
        sleep 1
    done

    echo "Error: failed to restart $APP_NAME after installation." >&2
    exit 1
}

if [[ "$(uname -s)" != "Darwin" && "$TARGET_DIR_WAS_SET" != "true" ]]; then
    echo "Error: install.sh currently supports macOS only." >&2
    echo "Set TARGET_DIR manually if you are running tests against a fixture directory." >&2
    exit 1
fi

require_command ruby

if ! ruby -e 'require "securerandom"; require "yaml"' >/dev/null 2>&1; then
    echo "Error: ruby is installed but missing required runtime support (yaml/securerandom)." >&2
    exit 1
fi

for required_file in \
    "$SCRIPT_DIR/config.yaml" \
    "$SCRIPT_DIR/mihomo.yaml" \
    "$OVERRIDE_SOURCE" \
    "$STATE_SCRIPT"
do
    if [[ ! -f "$required_file" ]]; then
        echo "Error: required file not found: $required_file" >&2
        exit 1
    fi
done

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: mihomo party not found at $TARGET_DIR" >&2
    echo "Please install mihomo party first." >&2
    exit 1
fi

echo "==> Staging config files"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mihomo-party-install.XXXXXX")"
mkdir -p "$STAGE_DIR/override"
cp "$SCRIPT_DIR/config.yaml" "$STAGE_DIR/config.yaml"
cp "$SCRIPT_DIR/mihomo.yaml" "$STAGE_DIR/mihomo.yaml"
log_step "staged: config.yaml, mihomo.yaml"

echo "==> Installing override rule"
SYNC_OUTPUT="$(ruby "$STATE_SCRIPT" "$TARGET_DIR" "$STAGE_DIR" "$OVERRIDE_NAME")"
OVERRIDE_ID="$(printf '%s\n' "$SYNC_OUTPUT" | sed -n '1p')"
PROFILE_STATUS="$(printf '%s\n' "$SYNC_OUTPUT" | sed -n '2p')"

cp "$OVERRIDE_SOURCE" "$STAGE_DIR/override/$OVERRIDE_ID.yaml"

stop_app_if_running

echo "==> Installing to target"
mkdir -p "$TARGET_DIR/override"
copy_atomically "$STAGE_DIR/config.yaml" "$TARGET_DIR/config.yaml"
copy_atomically "$STAGE_DIR/mihomo.yaml" "$TARGET_DIR/mihomo.yaml"
copy_atomically "$STAGE_DIR/override/$OVERRIDE_ID.yaml" "$TARGET_DIR/override/$OVERRIDE_ID.yaml"
copy_atomically "$STAGE_DIR/override.yaml" "$TARGET_DIR/override.yaml"
if [[ "$PROFILE_STATUS" == "updated" ]]; then
    copy_atomically "$STAGE_DIR/profile.yaml" "$TARGET_DIR/profile.yaml"
fi
log_step "installed: config.yaml, mihomo.yaml"
log_step "installed override: $OVERRIDE_ID.yaml"

echo "==> Configuring Wcloud subscription"
if [[ "$PROFILE_STATUS" == "updated" ]]; then
    echo "    linked override $OVERRIDE_ID to Wcloud"
    echo "    set autoUpdate: true, interval: 360 (every 6 hours)"
else
    echo "    skipped: Wcloud subscription not found (add it first, then re-run)"
fi

restart_app_if_needed

echo
if [[ "$APP_WAS_RUNNING" == "true" ]]; then
    echo "==> Done! Clash Party has been restarted."
else
    echo "==> Done! Restart Clash Party if you want to apply changes immediately."
fi
