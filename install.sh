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

# Step 1: Backup existing config
BACKUP_DIR="$HOME/.mihomo-party-backup-$(date +%Y%m%d-%H%M%S)"
BACKUP_FILES=()
for f in config.yaml mihomo.yaml override.yaml; do
    [[ -f "$TARGET_DIR/$f" ]] && BACKUP_FILES+=("$f")
done
if [[ -d "$TARGET_DIR/override" ]]; then
    for f in "$TARGET_DIR/override/"*.yaml; do
        [[ -f "$f" ]] && BACKUP_FILES+=("override/$(basename "$f")")
    done
fi

if [[ ${#BACKUP_FILES[@]} -gt 0 ]]; then
    echo "==> Backing up existing config to $BACKUP_DIR/"
    if $DRY_RUN; then
        for f in "${BACKUP_FILES[@]}"; do
            echo "    would backup: $f"
        done
    else
        mkdir -p "$BACKUP_DIR/override"
        for f in "${BACKUP_FILES[@]}"; do
            cp "$TARGET_DIR/$f" "$BACKUP_DIR/$f"
            echo "    backed up: $f"
        done
    fi
    echo
fi

# Step 2: Copy config.yaml and mihomo.yaml
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
OVERRIDE_ID=$(openssl rand -hex 5)$(printf '%x' "$(date +%s)" | tail -c 1)
OVERRIDE_FILE="$OVERRIDE_ID.yaml"
OVERRIDE_NAME="Claude专用 & 下载修复"
OVERRIDE_TIMESTAMP=$(python3 -c "import time; print(int(time.time() * 1000))")

if $DRY_RUN; then
    echo "    would generate override ID: $OVERRIDE_ID"
    echo "    would copy: $SCRIPT_DIR/override/claude-and-download-fix.yaml -> $TARGET_DIR/override/$OVERRIDE_FILE"
    echo "    would write override.yaml with entry:"
    echo "      - id: $OVERRIDE_ID"
    echo "        name: $OVERRIDE_NAME"
    echo "        type: local"
    echo "        ext: yaml"
    echo "        updated: $OVERRIDE_TIMESTAMP"
else
    mkdir -p "$TARGET_DIR/override"
    cp "$SCRIPT_DIR/override/claude-and-download-fix.yaml" "$TARGET_DIR/override/$OVERRIDE_FILE"
    echo "    installed override: $OVERRIDE_FILE"

    cat > "$TARGET_DIR/override.yaml" <<EOF
items:
  - id: $OVERRIDE_ID
    name: $OVERRIDE_NAME
    type: local
    ext: yaml
    updated: $OVERRIDE_TIMESTAMP
EOF
    echo "    wrote override.yaml"
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
