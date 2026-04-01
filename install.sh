#!/bin/bash
set -euo pipefail

TARGET_DIR_WAS_SET=false
if [[ -n "${TARGET_DIR:-}" ]]; then
    TARGET_DIR_WAS_SET=true
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OVERRIDE_NAME="MetaCubeX GEOSITE + Claude专用"
OVERRIDE_SOURCE="$SCRIPT_DIR/override/geosite-whitelist-claude.yaml"
STATE_SCRIPT="$SCRIPT_DIR/sync_install_state.rb"
STAGE_DIR=""
APP_CONTROL_MODE="${APP_CONTROL_MODE:-auto}"
APP_WAS_RUNNING=false

HOST_OS="$(uname -s)"
APP_LAUNCH_CMD="${APP_LAUNCH_CMD:-}"
APP_SUPPORTS_CONTROL=false
case "$HOST_OS" in
    Darwin)
        _DEFAULT_DIR="$HOME/Library/Application Support/mihomo-party"
        APP_SUPPORTS_CONTROL=true
        APP_NAME="${APP_NAME:-Clash Party}"
        APP_PROCESS_MATCH="${APP_PROCESS_MATCH:-/Applications/Clash Party.app/Contents/Resources/sidecar/mihomo}"
        ;;
    Linux)
        _DEFAULT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mihomo-party"
        APP_SUPPORTS_CONTROL=true
        APP_NAME="${APP_NAME:-mihomo-party}"
        APP_PROCESS_MATCH="${APP_PROCESS_MATCH:-}"
        APP_LAUNCH_CMD="${APP_LAUNCH_CMD:-mihomo-party}"
        ;;
    *)
        if [[ -z "${TARGET_DIR:-}" ]]; then
            echo "Error: install.sh currently supports macOS and Linux only." >&2
            echo "Set TARGET_DIR manually if you are running tests against a fixture directory." >&2
            exit 1
        fi
        _DEFAULT_DIR=""
        APP_NAME="${APP_NAME:-mihomo-party}"
        APP_PROCESS_MATCH="${APP_PROCESS_MATCH:-}"
        ;;
esac

TARGET_DIR="${TARGET_DIR:-$_DEFAULT_DIR}"
DEFAULT_TARGET_DIR="${DEFAULT_TARGET_DIR:-$_DEFAULT_DIR}"
STYLE_RESET=""
STYLE_BOLD=""
COLOR_STEP=""
COLOR_INFO=""
COLOR_OK=""
COLOR_WARN=""
COLOR_DONE=""
LOG_SECTION_INDEX=0

if [[ -z "${NO_COLOR:-}" ]]; then
    STYLE_RESET=$'\033[0m'
    STYLE_BOLD=$'\033[1m'
    COLOR_STEP=$'\033[38;5;39m'
    COLOR_INFO=$'\033[38;5;45m'
    COLOR_OK=$'\033[38;5;42m'
    COLOR_WARN=$'\033[38;5;220m'
    COLOR_DONE=$'\033[38;5;50m'
fi

log_section() {
    local title="$1"

    LOG_SECTION_INDEX=$((LOG_SECTION_INDEX + 1))
    if (( LOG_SECTION_INDEX > 1 )); then
        printf '\n'
    fi

    printf '%b[%02d]%b %b%s%b\n' \
        "${COLOR_STEP}${STYLE_BOLD}" \
        "$LOG_SECTION_INDEX" \
        "$STYLE_RESET" \
        "$STYLE_BOLD" \
        "$title" \
        "$STYLE_RESET"
}

log_step() {
    local label="$1"
    shift

    printf '     %b%-12s%b %s\n' \
        "${COLOR_INFO}${STYLE_BOLD}" \
        "$label" \
        "$STYLE_RESET" \
        "$*"
}

log_success() {
    local label="$1"
    shift

    printf '     %b%-12s%b %s\n' \
        "${COLOR_OK}${STYLE_BOLD}" \
        "$label" \
        "$STYLE_RESET" \
        "$*"
}

log_warn() {
    local label="$1"
    shift

    printf '     %b%-12s%b %s\n' \
        "${COLOR_WARN}${STYLE_BOLD}" \
        "$label" \
        "$STYLE_RESET" \
        "$*"
}

log_done() {
    local message="$1"

    printf '\n%b[done]%b %b%s%b\n' \
        "${COLOR_DONE}${STYLE_BOLD}" \
        "$STYLE_RESET" \
        "$STYLE_BOLD" \
        "$message" \
        "$STYLE_RESET"
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
    if [[ "$APP_SUPPORTS_CONTROL" != "true" ]]; then
        return 1
    fi

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

app_matches_process() {
    if [[ -z "$APP_PROCESS_MATCH" ]]; then
        return 1
    fi

    pgrep -f "$APP_PROCESS_MATCH" >/dev/null 2>&1
}

app_is_running() {
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || app_matches_process
}

app_is_ready() {
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        return 1
    fi

    if [[ -z "$APP_PROCESS_MATCH" ]]; then
        return 0
    fi

    app_matches_process
}

stop_app_if_running() {
    if ! app_control_enabled; then
        return 0
    fi

    if ! app_is_running; then
        return 0
    fi

    APP_WAS_RUNNING=true
    log_section "Stopping $APP_NAME"
    case "$HOST_OS" in
        Darwin)
            osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
            ;;
        Linux)
            pkill -TERM -x "$APP_NAME" >/dev/null 2>&1 || true
            ;;
    esac

    for _ in $(seq 1 30); do
        if ! app_is_running; then
            log_success "status" "stopped $APP_NAME"
            return 0
        fi
        sleep 1
    done

    pkill -TERM -x "$APP_NAME" >/dev/null 2>&1 || true
    if [[ -n "$APP_PROCESS_MATCH" ]]; then
        pkill -TERM -f "$APP_PROCESS_MATCH" >/dev/null 2>&1 || true
    fi

    for _ in $(seq 1 10); do
        if ! app_is_running; then
            log_success "status" "stopped $APP_NAME after TERM"
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

    log_section "Restarting $APP_NAME"
    case "$HOST_OS" in
        Darwin)
            open -a "$APP_NAME"
            ;;
        Linux)
            nohup "$APP_LAUNCH_CMD" >/dev/null 2>&1 &
            ;;
    esac

    for _ in $(seq 1 45); do
        if app_is_ready; then
            log_success "status" "restarted $APP_NAME"
            return 0
        fi
        sleep 1
    done

    echo "Error: failed to restart $APP_NAME after installation." >&2
    exit 1
}

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

log_section "Staging config files"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mihomo-party-install.XXXXXX")"
mkdir -p "$STAGE_DIR/override"
cp "$SCRIPT_DIR/config.yaml" "$STAGE_DIR/config.yaml"
cp "$SCRIPT_DIR/mihomo.yaml" "$STAGE_DIR/mihomo.yaml"
log_success "staged" "config.yaml, mihomo.yaml"

log_section "Installing override rule"
SYNC_OUTPUT="$(ruby "$STATE_SCRIPT" "$TARGET_DIR" "$STAGE_DIR" "$OVERRIDE_NAME")"
OVERRIDE_ID="$(printf '%s\n' "$SYNC_OUTPUT" | sed -n '1p')"
PROFILE_STATUS="$(printf '%s\n' "$SYNC_OUTPUT" | sed -n '2p')"

cp "$OVERRIDE_SOURCE" "$STAGE_DIR/override/$OVERRIDE_ID.yaml"
log_step "override" "$OVERRIDE_NAME"
log_success "file" "$OVERRIDE_ID.yaml"

stop_app_if_running

log_section "Installing to target"
mkdir -p "$TARGET_DIR/override"
copy_atomically "$STAGE_DIR/config.yaml" "$TARGET_DIR/config.yaml"
copy_atomically "$STAGE_DIR/mihomo.yaml" "$TARGET_DIR/mihomo.yaml"
copy_atomically "$STAGE_DIR/override/$OVERRIDE_ID.yaml" "$TARGET_DIR/override/$OVERRIDE_ID.yaml"
copy_atomically "$STAGE_DIR/override.yaml" "$TARGET_DIR/override.yaml"
if [[ "$PROFILE_STATUS" == "updated" ]]; then
    copy_atomically "$STAGE_DIR/profile.yaml" "$TARGET_DIR/profile.yaml"
fi
log_success "installed" "config.yaml, mihomo.yaml"
log_success "override" "$OVERRIDE_ID.yaml"

log_section "Configuring Wcloud subscription"
if [[ "$PROFILE_STATUS" == "updated" ]]; then
    log_success "linked" "override $OVERRIDE_ID to Wcloud"
    log_success "auto-update" "enabled, fixed every 1 hour"
else
    log_warn "skipped" "Wcloud subscription not found (add it first, then re-run)"
fi

restart_app_if_needed

if [[ "$APP_WAS_RUNNING" == "true" ]]; then
    log_done "$APP_NAME has been restarted and changes are active."
else
    log_done "Restart $APP_NAME to apply changes immediately."
fi
