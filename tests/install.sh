#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_SCRIPT="$REPO_DIR/install.sh"

assert_ruby() {
    local description="$1"
    local yaml_file="$2"
    local ruby_code="$3"

    ruby - "$yaml_file" "$description" "$ruby_code" <<'RUBY'
yaml_file, description, ruby_code = ARGV
require "yaml"
document = YAML.load_file(yaml_file)
begin
  eval(ruby_code, binding, description)
rescue StandardError => error
  warn "FAIL: #{description}"
  warn error.message
  exit 1
end
RUBY
    echo "ok: $description"
}

run_install() {
    local target_dir="$1"
    TARGET_DIR="$target_dir" "$INSTALL_SCRIPT" >/dev/null
}

run_install_with_env() {
    local target_dir="$1"
    shift
    env "$@" TARGET_DIR="$target_dir" "$INSTALL_SCRIPT" >/dev/null
}

fixture_dir() {
    local dir
    dir="$(mktemp -d)"
    mkdir -p "$dir"
    printf '%s\n' "$dir"
}

test_missing_profile_fields_are_created() {
    local target_dir
    target_dir="$(fixture_dir)"
    cat <<'YAML' > "$target_dir/profile.yaml"
items:
  - id: foo
    name: Wcloud
    type: remote
YAML

    run_install "$target_dir"

    assert_ruby \
        "profile fields inserted for Wcloud" \
        "$target_dir/profile.yaml" \
        'item = document.fetch("items").find { |entry| entry["name"] == "Wcloud" } or raise "missing Wcloud"; raise "override not set" unless item["override"].is_a?(Array) && item["override"].size == 1; raise "autoUpdate not true" unless item["autoUpdate"] == true; raise "interval not 360" unless item["interval"] == 360'
}

test_override_name_match_is_exact() {
    local target_dir
    target_dir="$(fixture_dir)"
    cat <<'YAML' > "$target_dir/override.yaml"
meta: keep-me
items:
  - id: abcde12345
    name: Loyalsoldier白名单 + Claude专用 备份
    type: local
    ext: yaml
    updated: 1
YAML

    run_install "$target_dir"

    assert_ruby \
        "override registry keeps substring match separate" \
        "$target_dir/override.yaml" \
        'items = document.fetch("items"); names = items.map { |entry| entry["name"] }; raise "missing backup entry" unless names.include?("Loyalsoldier白名单 + Claude专用 备份"); raise "missing target entry" unless names.include?("Loyalsoldier白名单 + Claude专用"); raise "meta key dropped" unless document["meta"] == "keep-me"; target = items.find { |entry| entry["name"] == "Loyalsoldier白名单 + Claude专用" }; raise "wrong ID reused" if target["id"] == "abcde12345"'
}

test_duplicate_overrides_are_normalized_and_idempotent() {
    local target_dir
    target_dir="$(fixture_dir)"
    cat <<'YAML' > "$target_dir/override.yaml"
items:
  - id: 11111
    name: Loyalsoldier白名单 + Claude专用
    type: local
    ext: yaml
    updated: 1
  - id: 22222
    name: Loyalsoldier白名单 + Claude专用
    type: local
    ext: yaml
    updated: 2
YAML

    run_install "$target_dir"
    run_install "$target_dir"

    assert_ruby \
        "duplicate overrides collapse to one stable entry" \
        "$target_dir/override.yaml" \
        'items = document.fetch("items"); matches = items.select { |entry| entry["name"] == "Loyalsoldier白名单 + Claude专用" }; raise "expected exactly one target entry" unless matches.size == 1; raise "expected stable first ID" unless matches.first["id"] == "11111"'

    if [[ ! -f "$target_dir/override/11111.yaml" ]]; then
        echo "FAIL: override file was not copied with normalized ID" >&2
        exit 1
    fi
    echo "ok: override file copied with normalized ID"
}

test_missing_profile_does_not_fail() {
    local target_dir
    target_dir="$(fixture_dir)"

    run_install "$target_dir"

    if [[ ! -f "$target_dir/override.yaml" ]]; then
        echo "FAIL: override.yaml not created when profile.yaml is absent" >&2
        exit 1
    fi
    echo "ok: install succeeds without profile.yaml"
}

test_invalid_profile_is_noop() {
    local target_dir
    target_dir="$(fixture_dir)"
    cat <<'YAML' > "$target_dir/profile.yaml"
items: not-a-list
YAML

    if run_install "$target_dir" >/dev/null 2>&1; then
        echo "FAIL: install should reject malformed profile.yaml" >&2
        exit 1
    fi

    if [[ -f "$target_dir/config.yaml" || -f "$target_dir/mihomo.yaml" || -f "$target_dir/override.yaml" ]]; then
        echo "FAIL: malformed profile.yaml should not leave staged output behind" >&2
        exit 1
    fi
    echo "ok: malformed profile.yaml leaves target untouched"
}

test_invalid_override_is_noop() {
    local target_dir
    target_dir="$(fixture_dir)"
    cat <<'YAML' > "$target_dir/override.yaml"
items:
  - id: broken
    name: Broken
    type: local
    ext: yaml
    updated: 1
  - bad: [
YAML

    if run_install "$target_dir" >/dev/null 2>&1; then
        echo "FAIL: install should reject malformed override.yaml" >&2
        exit 1
    fi

    if [[ -f "$target_dir/config.yaml" || -f "$target_dir/mihomo.yaml" ]]; then
        echo "FAIL: malformed override.yaml should not copy config files" >&2
        exit 1
    fi
    echo "ok: malformed override.yaml leaves target untouched"
}

test_broken_ruby_fails_before_writing() {
    local target_dir tmpbin
    target_dir="$(fixture_dir)"
    tmpbin="$(mktemp -d)"

    cat <<'SH' > "$tmpbin/ruby"
#!/bin/sh
exit 127
SH
    chmod +x "$tmpbin/ruby"

    if PATH="$tmpbin:/usr/bin:/bin:/usr/sbin:/sbin" TARGET_DIR="$target_dir" "$INSTALL_SCRIPT" >/dev/null 2>&1; then
        echo "FAIL: install should fail when ruby runtime is broken" >&2
        exit 1
    fi

    if find "$target_dir" -maxdepth 1 -type f | grep -q .; then
        echo "FAIL: broken ruby should fail before any files are written" >&2
        exit 1
    fi
    echo "ok: broken ruby fails before writes"
}

test_running_app_is_stopped_and_restarted() {
    local target_dir fakebin state_dir
    target_dir="$(fixture_dir)"
    fakebin="$(mktemp -d)"
    state_dir="$(mktemp -d)"

    cat <<'YAML' > "$target_dir/profile.yaml"
items:
  - id: foo
    name: Wcloud
    type: remote
YAML

    : > "$state_dir/running"

    cat <<'SH' > "$fakebin/pgrep"
#!/bin/sh
state_dir="${TEST_STATE_DIR:?}"
if [ -f "$state_dir/running" ]; then
  echo 12345
  exit 0
fi
exit 1
SH

    cat <<'SH' > "$fakebin/osascript"
#!/bin/sh
state_dir="${TEST_STATE_DIR:?}"
echo osascript >> "$state_dir/log"
rm -f "$state_dir/running"
SH

    cat <<'SH' > "$fakebin/open"
#!/bin/sh
state_dir="${TEST_STATE_DIR:?}"
echo open >> "$state_dir/log"
touch "$state_dir/running"
SH

    chmod +x "$fakebin/pgrep" "$fakebin/osascript" "$fakebin/open"

    run_install_with_env \
        "$target_dir" \
        APP_CONTROL_MODE=always \
        TEST_STATE_DIR="$state_dir" \
        PATH="$fakebin:/usr/bin:/bin:/usr/sbin:/sbin"

    if [[ ! -f "$state_dir/log" ]]; then
        echo "FAIL: expected app control commands to run" >&2
        exit 1
    fi

    if [[ "$(tr '\n' ' ' < "$state_dir/log")" != "osascript open " ]]; then
        echo "FAIL: expected stop then restart sequence" >&2
        cat "$state_dir/log" >&2
        exit 1
    fi

    if [[ ! -f "$state_dir/running" ]]; then
        echo "FAIL: app should be running after restart" >&2
        exit 1
    fi
    echo "ok: running app is stopped before install and restarted after"
}

test_auto_mode_restarts_live_session() {
    local target_dir fakebin state_dir
    target_dir="$(fixture_dir)"
    fakebin="$(mktemp -d)"
    state_dir="$(mktemp -d)"

    cat <<'YAML' > "$target_dir/profile.yaml"
items:
  - id: foo
    name: Wcloud
    type: remote
YAML

    : > "$state_dir/running"

    cat <<'SH' > "$fakebin/pgrep"
#!/bin/sh
state_dir="${TEST_STATE_DIR:?}"
if [ -f "$state_dir/running" ]; then
  echo 12345
  exit 0
fi
exit 1
SH

    cat <<'SH' > "$fakebin/osascript"
#!/bin/sh
state_dir="${TEST_STATE_DIR:?}"
echo osascript >> "$state_dir/log"
rm -f "$state_dir/running"
SH

    cat <<'SH' > "$fakebin/open"
#!/bin/sh
state_dir="${TEST_STATE_DIR:?}"
echo open >> "$state_dir/log"
touch "$state_dir/running"
SH

    chmod +x "$fakebin/pgrep" "$fakebin/osascript" "$fakebin/open"

    run_install_with_env \
        "$target_dir" \
        APP_CONTROL_MODE=auto \
        DEFAULT_TARGET_DIR="$target_dir" \
        TEST_STATE_DIR="$state_dir" \
        PATH="$fakebin:/usr/bin:/bin:/usr/sbin:/sbin"

    if [[ "$(tr '\n' ' ' < "$state_dir/log")" != "osascript open " ]]; then
        echo "FAIL: auto mode should stop then restart a live Clash Party instance" >&2
        cat "$state_dir/log" >&2
        exit 1
    fi

    if [[ ! -f "$state_dir/running" ]]; then
        echo "FAIL: auto mode should leave the app running after restart" >&2
        exit 1
    fi
    echo "ok: auto mode restarts a live session for the default target dir"
}

test_missing_profile_fields_are_created
test_override_name_match_is_exact
test_duplicate_overrides_are_normalized_and_idempotent
test_missing_profile_does_not_fail
test_invalid_profile_is_noop
test_invalid_override_is_noop
test_broken_ruby_fails_before_writing
test_running_app_is_stopped_and_restarted
test_auto_mode_restarts_live_session
