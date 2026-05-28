#!/bin/bash
# ============================================================
# OpenClaude Config Restore Script for Linux Mint
# Restores config, agents, projects, memory from Windows backup
# Usage: bash restore.sh
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

echo "============================================"
echo "  OpenClaude Config Restore from Backup"
echo "============================================"
echo ""

# ------------------------------------------------------------
# 1. Auto-detect backup location
# ------------------------------------------------------------
BACKUP_DIR=""

# Check common mount points on Linux Mint
for mount_point in /media/$USER/*/openclaude-backup /media/*/openclaude-backup /mnt/openclaude-backup; do
    if [ -d "$mount_point/dot-openclaude" ]; then
        BACKUP_DIR="$mount_point/dot-openclaude"
        break
    fi
done

# Also check if running from the backup drive itself
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$SCRIPT_DIR/dot-openclaude" ]; then
    BACKUP_DIR="$SCRIPT_DIR/dot-openclaude"
fi

if [ -z "$BACKUP_DIR" ]; then
    err "Cannot find backup directory automatically."
    echo ""
    echo "  Expected location: <USB_MOUNT>/openclaude-backup/dot-openclaude/"
    echo ""
    read -p "Enter backup path manually: " BACKUP_DIR
    if [ ! -d "$BACKUP_DIR" ]; then
        err "Directory not found: $BACKUP_DIR"
        exit 1
    fi
fi

log "Backup found at: $BACKUP_DIR"
echo ""

# ------------------------------------------------------------
# 2. Verify backup contents
# ------------------------------------------------------------
info "Verifying backup contents..."

MISSING=()
[ ! -d "$BACKUP_DIR/agents" ] && MISSING+=("agents/")
[ ! -f "$BACKUP_DIR/settings.json" ] && MISSING+=("settings.json")
[ ! -f "$BACKUP_DIR/.openclaude-profile.json" ] && MISSING+=(".openclaude-profile.json")
[ ! -d "$BACKUP_DIR/projects" ] && MISSING+=("projects/")

if [ ${#MISSING[@]} -gt 0 ]; then
    warn "Some expected items missing from backup:"
    for item in "${MISSING[@]}"; do
        echo "    - $item"
    done
    echo ""
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo ""
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

log "Backup contents:"
echo "    Agents:     $(ls "$BACKUP_DIR/agents/"*.md 2>/dev/null | wc -l) files"
echo "    Projects:   $(ls -d "$BACKUP_DIR/projects/"*/ 2>/dev/null | wc -l) dirs"
echo "    Memory:     $(find "$BACKUP_DIR/projects/" -name "*.md" 2>/dev/null | wc -l) memory files"
echo "    Settings:   $([ -f "$BACKUP_DIR/settings.json" ] && echo 'OK' || echo 'missing')"
echo "    Profile:    $([ -f "$BACKUP_DIR/.openclaude-profile.json" ] && echo 'OK' || echo 'missing')"
echo ""

# ------------------------------------------------------------
# 3. Backup current config (if exists)
# ------------------------------------------------------------
TARGET="$HOME/.openclaude"

if [ -d "$TARGET" ]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_CURRENT="$TARGET.backup.$TIMESTAMP"
    warn "Existing config found at $TARGET"
    info "Backing up current config to: $BACKUP_CURRENT"
    mv "$TARGET" "$BACKUP_CURRENT"
    log "Current config backed up"
else
    info "No existing config found, fresh install"
fi
echo ""

# ------------------------------------------------------------
# 4. Restore config
# ------------------------------------------------------------
info "Restoring config from backup..."
cp -r "$BACKUP_DIR" "$TARGET"
log "Config restored to $TARGET"

# ------------------------------------------------------------
# 5. Fix permissions
# ------------------------------------------------------------
info "Setting permissions..."
chmod 600 "$TARGET"/Claude_Code-credentials.secure.dpapi 2>/dev/null || true
chmod 700 "$TARGET"

# ------------------------------------------------------------
# 6. Update settings for Linux environment
# ------------------------------------------------------------
info "Checking settings..."

# Update settings.json to work with Ollama (if installed)
if command -v ollama &> /dev/null; then
    OLLAMA_MODELS=$(ollama list 2>/dev/null | tail -n +2 | head -1 | awk '{print $1}')
    if [ -n "$OLLAMA_MODELS" ]; then
        log "Ollama detected with model: $OLLAMA_MODELS"
        echo ""
        echo "  Current settings.json model: $(cat "$TARGET/settings.json" 2>/dev/null | grep -o '"model"[^,]*' | head -1)"
        echo "  Available Ollama model:      $OLLAMA_MODELS"
        echo ""
        read -p "Switch to Ollama local model? (y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Update profile for Ollama
            cat > "$TARGET/.openclaude-profile.json" << EOF
{
  "profile": "ollama-local",
  "env": {
    "OLLAMA_HOST": "http://localhost:11434",
    "OLLAMA_MODEL": "$OLLAMA_MODELS"
  },
  "createdAt": "$(date -Iseconds)"
}
EOF
            log "Profile switched to Ollama ($OLLAMA_MODELS)"
        else
            info "Keeping original profile (opengateway)"
        fi
    else
        warn "Ollama installed but no models pulled yet"
        echo "    Run: ollama pull qwen2.5-coder:7b"
    fi
else
    warn "Ollama not installed"
    echo "    Run setup.sh first, or install manually: curl -fsSL https://ollama.com/install.sh | sh"
fi

# ------------------------------------------------------------
# 7. Verify restore
# ------------------------------------------------------------
echo ""
echo "============================================"
echo "  Restore Complete!"
echo "============================================"
echo ""

log "Config directory: $TARGET"
log "Agents restored:"
for agent in "$TARGET/agents/"*.md; do
    [ -f "$agent" ] && echo "    - $(basename "$agent")"
done

echo ""
log "Projects restored:"
for proj in "$TARGET/projects/"*/; do
    [ -d "$proj" ] && echo "    - $(basename "$proj")"
done

echo ""
echo "Next steps:"
echo "  1. Open new terminal:  source ~/.bashrc"
echo "  2. Run OpenClaude:     openclaude"
echo "  3. Check config:       cat ~/.openclaude/settings.json"
echo ""
echo "To switch back to opengateway (mimo model):"
echo "  Edit ~/.openclaude/.openclaude-profile.json"
echo ""
