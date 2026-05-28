#!/usr/bin/env bash
# ============================================================
# OpenClaude Config Restore Script for Linux Mint
# Restores providers, agents, projects, memory, and model routing
# from the Windows backup onto Linux Mint on the external SSD.
# Usage: bash restore.sh [backup-dot-openclaude-path]
# ============================================================

set -Eeuo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

copy_dir_contents() {
    local src="$1"
    local dst="$2"
    mkdir -p "$dst"
    cp -a "$src"/. "$dst"/
}

json_get() {
    local file="$1"
    local expr="$2"
    node -e "const fs=require('fs'); const p='$file'; if(fs.existsSync(p)){const j=JSON.parse(fs.readFileSync(p,'utf8')); const v=($expr); if(Array.isArray(v)) console.log(v.join(', ')); else if(v && typeof v==='object') console.log(Object.keys(v).join(', ')); else console.log(v || 'missing')}" 2>/dev/null || echo "missing"
}

json_validate() {
    local file="$1"
    node -e "JSON.parse(require('fs').readFileSync('$file', 'utf8'))" >/dev/null
}

find_backup_dir() {
    if [ -n "${1:-}" ] && [ -d "$1" ]; then
        echo "$1"
        return 0
    fi

    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"

    if [ -d "$script_dir/dot-openclaude" ]; then
        echo "$script_dir/dot-openclaude"
        return 0
    fi

    local mount_point
    for mount_point in \
        /media/"$USER"/*/openclaude-backup/dot-openclaude \
        /media/*/openclaude-backup/dot-openclaude \
        /mnt/openclaude-backup/dot-openclaude \
        /e/openclaude-backup/dot-openclaude; do
        if [ -d "$mount_point" ]; then
            echo "$mount_point"
            return 0
        fi
    done

    return 1
}

print_backup_summary() {
    local backup_dir="$1"

    log "Backup contents:"
    echo "    Agents:   $(find "$backup_dir/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l) files"
    echo "    Projects: $(find "$backup_dir/projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l) dirs"
    echo "    Memory:   $(find "$backup_dir/projects" -name '*.md' 2>/dev/null | wc -l) files"
    echo "    Settings: $([ -f "$backup_dir/settings.json" ] && echo OK || echo missing)"
    echo "    Gateway:  $([ -f "$backup_dir/gemini-gateway.mjs" ] && echo OK || echo missing)"

    if [ -f "$backup_dir/settings.json" ] && json_validate "$backup_dir/settings.json"; then
        echo "    Model:    $(json_get "$backup_dir/settings.json" "j.model")"
        echo "    Routes:   $(json_get "$backup_dir/settings.json" "j.agentRouting")"
        echo "    Models:   $(json_get "$backup_dir/settings.json" "j.agentModels")"
    fi
}

fix_windows_paths_notice() {
    local settings_file="$1"

    if [ ! -f "$settings_file" ]; then
        return 0
    fi

    if grep -Eq 'C:|C--Users-Admin|\\\\|/c/|/e/' "$settings_file"; then
        warn "settings.json may contain Windows-specific paths. Review after restore if a provider/gateway fails."
    fi
}

echo "============================================"
echo "  OpenClaude Full Restore for Linux Mint"
echo "============================================"
echo ""
echo "This restores the whole OpenClaude environment from Windows backup:"
echo "  - providers and model routing"
echo "  - custom agents"
echo "  - project contexts and memory"
echo "  - gateway/helper files"
echo ""
echo "The goal is to move the workload off the nearly-full Windows C: drive"
echo "and run it from Linux Mint on the external SSD."
echo ""

# ------------------------------------------------------------
# 1. Locate backup
# ------------------------------------------------------------
BACKUP_DIR="$(find_backup_dir "${1:-}" || true)"

if [ -z "$BACKUP_DIR" ]; then
    err "Cannot find backup directory automatically."
    echo ""
    echo "Expected: <SSD_MOUNT>/openclaude-backup/dot-openclaude/"
    read -r -p "Enter backup path manually: " BACKUP_DIR
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
[ ! -d "$BACKUP_DIR/projects" ] && MISSING+=("projects/")

if [ "${#MISSING[@]}" -gt 0 ]; then
    warn "Some expected items are missing:"
    for item in "${MISSING[@]}"; do
        echo "    - $item"
    done
    echo ""
    read -r -p "Continue anyway? (y/n): " CONTINUE
    [[ ! "$CONTINUE" =~ ^[Yy]$ ]] && exit 1
fi

if [ -f "$BACKUP_DIR/settings.json" ]; then
    if json_validate "$BACKUP_DIR/settings.json"; then
        log "Backup settings.json is valid"
    else
        warn "Backup settings.json is invalid JSON. It will be copied, but OpenClaude may ignore it."
    fi
fi

print_backup_summary "$BACKUP_DIR"
echo ""

# ------------------------------------------------------------
# 3. Backup current Linux config
# ------------------------------------------------------------
TARGET="$HOME/.openclaude"
if [ -d "$TARGET" ]; then
    CURRENT_BACKUP="$TARGET.backup.$(date +%Y%m%d_%H%M%S)"
    warn "Existing Linux config found at $TARGET"
    cp -a "$TARGET" "$CURRENT_BACKUP"
    log "Current Linux config copied to $CURRENT_BACKUP"
fi

# ------------------------------------------------------------
# 4. Restore full config
# ------------------------------------------------------------
info "Restoring full OpenClaude config..."
mkdir -p "$TARGET"
copy_dir_contents "$BACKUP_DIR" "$TARGET"
log "Config restored to $TARGET"

# ------------------------------------------------------------
# 5. Linux permissions and compatibility notices
# ------------------------------------------------------------
info "Setting Linux permissions..."
chmod 700 "$TARGET" 2>/dev/null || true
chmod 600 "$TARGET"/*.json "$TARGET"/*.secure* 2>/dev/null || true

if [ -f "$TARGET/Claude_Code-credentials.secure.dpapi" ]; then
    warn "Windows DPAPI credentials were restored but cannot be used on Linux."
    echo "    API-key providers in settings.json should still work. OAuth providers may need login again."
fi

if [ -f "$TARGET/gemini-gateway.mjs" ]; then
    log "Gemini gateway file restored"
fi

fix_windows_paths_notice "$TARGET/settings.json"

# ------------------------------------------------------------
# 6. Verify restore
# ------------------------------------------------------------
echo ""
echo "============================================"
echo "  Restore Complete"
echo "============================================"
echo ""

log "Config directory: $TARGET"
if [ -f "$TARGET/settings.json" ]; then
    log "Settings model: $(json_get "$TARGET/settings.json" "j.model")"
    info "Agent model entries: $(json_get "$TARGET/settings.json" "j.agentModels")"
    info "Agent routing entries: $(json_get "$TARGET/settings.json" "j.agentRouting")"
fi

info "Agents restored:"
for agent in "$TARGET"/agents/*.md; do
    [ -f "$agent" ] && echo "    - $(basename "$agent")"
done

info "Projects restored:"
for project in "$TARGET"/projects/*/; do
    [ -d "$project" ] && echo "    - $(basename "$project")"
done

echo ""
echo "Next steps:"
echo "  1. Open a new terminal, or run: source ~/.bashrc"
echo "  2. Run OpenClaude: openclaude"
echo "  3. Use /provider to verify restored providers/models"
echo "  4. If OAuth providers fail, login again on Linux."
echo "  5. Keep large local AI models on the Linux SSD, not Windows C:."
echo ""
