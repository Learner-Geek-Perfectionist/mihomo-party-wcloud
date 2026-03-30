#!/bin/bash
set -euo pipefail

TARGET_DIR="$HOME/Library/Application Support/mihomo-party"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check mihomo party installation
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: mihomo party not found at $TARGET_DIR"
    echo "Please install mihomo party first."
    exit 1
fi

# Step 1: Copy core config files
echo "==> Installing config files"
cp "$SCRIPT_DIR/config.yaml"  "$TARGET_DIR/config.yaml"
cp "$SCRIPT_DIR/mihomo.yaml"  "$TARGET_DIR/mihomo.yaml"
echo "    installed: config.yaml, mihomo.yaml"

# Step 2: Install override rule
echo "==> Installing override rule"
OVERRIDE_NAME="Loyalsoldier白名单 + Claude专用"

# Reuse existing ID or generate a new one
OVERRIDE_ID=$(grep -B1 "name: $OVERRIDE_NAME" "$TARGET_DIR/override.yaml" 2>/dev/null \
    | grep 'id:' | sed 's/.*id:[[:space:]]*//' | tr -d '[:space:]' || true)

if [[ -z "$OVERRIDE_ID" ]]; then
    OVERRIDE_ID=$(openssl rand -hex 5)
    echo "    new override ID: $OVERRIDE_ID"
else
    echo "    reusing override ID: $OVERRIDE_ID"
fi

mkdir -p "$TARGET_DIR/override"
cp "$SCRIPT_DIR/override/loyalsoldier-whitelist-claude.yaml" "$TARGET_DIR/override/$OVERRIDE_ID.yaml"

# Rebuild override.yaml: our entry first, then preserve others
# Write to .tmp first to avoid truncating the file before reading it
{
    echo "items:"
    echo "  - id: $OVERRIDE_ID"
    echo "    name: $OVERRIDE_NAME"
    echo "    type: local"
    echo "    ext: yaml"
    echo "    updated: $(date +%s)000"
    # Append other entries (skip ours and the "items:" header)
    if [[ -f "$TARGET_DIR/override.yaml" ]]; then
        awk -v skip_name="$OVERRIDE_NAME" '
            in_block && /^  - id:/ { if (!skip) printf "%s", block; block = $0 "\n"; skip = 0; next }
            /^  - id:/ { block = $0 "\n"; in_block = 1; skip = 0; next }
            in_block { block = block $0 "\n"; if (index($0, "name: " skip_name) > 0) skip = 1; next }
            END { if (in_block && !skip) printf "%s", block }
        ' "$TARGET_DIR/override.yaml"
    fi
} > "$TARGET_DIR/override.yaml.tmp"
mv "$TARGET_DIR/override.yaml.tmp" "$TARGET_DIR/override.yaml"
echo "    installed override: $OVERRIDE_ID.yaml"

# Step 3: Enable Wcloud subscription auto-update (every 6 hours)
echo "==> Configuring Wcloud subscription auto-update"
if [[ -f "$TARGET_DIR/profile.yaml" ]] && grep -q "name: Wcloud" "$TARGET_DIR/profile.yaml"; then
    sed -i '' '/name: Wcloud/,/^  - id:/{
        s/autoUpdate:.*/autoUpdate: true/
        s/interval:.*/interval: 360/
    }' "$TARGET_DIR/profile.yaml"
    echo "    set autoUpdate: true, interval: 360 (every 6 hours)"
else
    echo "    skipped: Wcloud subscription not found"
fi

# Done
echo
echo "==> Done! Restart mihomo party to apply changes."
