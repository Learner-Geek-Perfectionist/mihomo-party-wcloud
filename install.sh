#!/bin/bash
set -euo pipefail

TARGET_DIR="$HOME/Library/Application Support/mihomo-party"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "[DRY RUN] Previewing actions without making changes"
    echo
fi

# Check mihomo party installation
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: mihomo party data directory not found at:"
    echo "  $TARGET_DIR"
    echo "Please install mihomo party first."
    exit 1
fi

echo "mihomo party directory: $TARGET_DIR"
echo

# Step 1: Copy config.yaml and mihomo.yaml
echo "==> Installing config files"
for f in config.yaml mihomo.yaml; do
    if $DRY_RUN; then
        echo "    would copy: $SCRIPT_DIR/$f -> $TARGET_DIR/$f"
    else
        cp "$SCRIPT_DIR/$f" "$TARGET_DIR/$f"
        echo "    installed: $f"
    fi
done
echo

# Step 3: Install override
echo "==> Installing override rule"
OVERRIDE_NAME="Claude专用 & 下载修复"
OVERRIDE_TIMESTAMP=$(python3 -c "import time; print(int(time.time() * 1000))")

EXISTING_ID=""
if [[ -f "$TARGET_DIR/override.yaml" ]]; then
    EXISTING_ID=$(grep -B1 "name: $OVERRIDE_NAME" "$TARGET_DIR/override.yaml" \
        | grep 'id:' | sed 's/.*id:[[:space:]]*//' | tr -d '[:space:]' || true)
fi

if [[ -n "$EXISTING_ID" ]]; then
    OVERRIDE_ID="$EXISTING_ID"
    echo "    reusing existing override ID: $OVERRIDE_ID"
else
    OVERRIDE_ID=$(openssl rand -hex 5)$(printf '%x' "$(date +%s)" | tail -c 1)
    echo "    generated new override ID: $OVERRIDE_ID"
fi
OVERRIDE_FILE="$OVERRIDE_ID.yaml"

if $DRY_RUN; then
    echo "    would copy: $SCRIPT_DIR/override/claude-and-download-fix.yaml -> $TARGET_DIR/override/$OVERRIDE_FILE"
    echo "    would write override.yaml with entry:"
    echo "      - id: $OVERRIDE_ID"
    echo "        name: $OVERRIDE_NAME"
    echo "        type: local"
    echo "        ext: yaml"
    echo "        updated: $OVERRIDE_TIMESTAMP"
else
    mkdir -p "$TARGET_DIR/override"

    # Collect IDs of stale copies (same content, different ID) before overwriting
    SRC_HASH=$(shasum -a 256 "$SCRIPT_DIR/override/claude-and-download-fix.yaml" | cut -d' ' -f1)
    STALE_IDS=()
    for f in "$TARGET_DIR/override/"*.yaml; do
        [[ -f "$f" ]] || continue
        fid=$(basename "$f" .yaml)
        [[ "$fid" == "$OVERRIDE_ID" ]] && continue
        fhash=$(shasum -a 256 "$f" | cut -d' ' -f1)
        [[ "$fhash" == "$SRC_HASH" ]] && STALE_IDS+=("$fid")
    done

    cp "$SCRIPT_DIR/override/claude-and-download-fix.yaml" "$TARGET_DIR/override/$OVERRIDE_FILE"
    echo "    installed override: $OVERRIDE_FILE"

    # Rebuild override.yaml: our entry first, then preserve others
    {
        echo "items:"
        echo "  - id: $OVERRIDE_ID"
        echo "    name: $OVERRIDE_NAME"
        echo "    type: local"
        echo "    ext: yaml"
        echo "    updated: $OVERRIDE_TIMESTAMP"
    } > "$TARGET_DIR/override.yaml.tmp"

    # Append other existing override entries (skip ours by name)
    if [[ -f "$TARGET_DIR/override.yaml" ]]; then
        python3 -c "
import re, sys
text = open('$TARGET_DIR/override.yaml').read()
blocks = re.split(r'(?=  - id:)', text)
for block in blocks:
    block = block.strip()
    if not block.startswith('- id:'):
        continue
    if 'name: $OVERRIDE_NAME' in block:
        continue
    print('  ' + block)
" >> "$TARGET_DIR/override.yaml.tmp" 2>/dev/null || true
    fi
    mv "$TARGET_DIR/override.yaml.tmp" "$TARGET_DIR/override.yaml"
    echo "    wrote override.yaml (preserved other overrides)"

    # Fix profile associations: replace stale override IDs with current one
    if [[ -f "$TARGET_DIR/profile.yaml" && ${#STALE_IDS[@]} -gt 0 ]]; then
        for stale_id in "${STALE_IDS[@]}"; do
            if grep -q "$stale_id" "$TARGET_DIR/profile.yaml"; then
                sed -i '' "s/$stale_id/$OVERRIDE_ID/g" "$TARGET_DIR/profile.yaml"
                echo "    updated profile association: $stale_id -> $OVERRIDE_ID"
            fi
            rm -f "$TARGET_DIR/override/$stale_id.yaml"
            echo "    removed stale override: $stale_id.yaml"
        done
    fi
fi
echo

# Step 4: Enable auto-update for Wcloud subscription (every 6 hours)
echo "==> Configuring Wcloud subscription auto-update"
if [[ -f "$TARGET_DIR/profile.yaml" ]]; then
    if grep -q "name: Wcloud" "$TARGET_DIR/profile.yaml"; then
        if $DRY_RUN; then
            echo "    would set: autoUpdate: true, interval: 360 (6 hours)"
        else
            python3 -c "
import re
text = open('$TARGET_DIR/profile.yaml').read()
lines = text.split('\n')
in_wcloud = False
result = []
for line in lines:
    if 'name: Wcloud' in line:
        in_wcloud = True
    elif re.match(r'  - id:', line):
        in_wcloud = False
    if in_wcloud:
        if 'autoUpdate:' in line:
            line = re.sub(r'autoUpdate:.*', 'autoUpdate: true', line)
        elif 'interval:' in line:
            line = re.sub(r'interval:.*', 'interval: 360', line)
    result.append(line)
open('$TARGET_DIR/profile.yaml', 'w').write('\n'.join(result))
"
            echo "    set autoUpdate: true, interval: 360 (every 6 hours)"
        fi
    else
        echo "    skipped: Wcloud subscription not found (add it first)"
    fi
else
    echo "    skipped: profile.yaml not found (add subscription first)"
fi
echo

# Done
echo "==> Done!"
echo
echo "Next steps:"
echo "  1. Restart mihomo party"
echo "  2. Add your Wcloud subscription: Profile -> Import -> paste URL"
echo "  3. Enable override: Override -> toggle on \"Claude专用 & 下载修复\""
echo "  4. Associate: Profile -> Wcloud profile -> Override -> check it"
