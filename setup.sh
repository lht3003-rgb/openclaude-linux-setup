#!/usr/bin/env bash
# ============================================================
# OpenClaude Linux Mint Migration Setup
# Installs OpenClaude prerequisites and restores the full Windows
# OpenClaude environment from the external SSD backup.
# Usage: bash setup.sh [backup-dot-openclaude-path]
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

select_shell_rc() {
    if [ -n "${ZSH_VERSION:-}" ]; then
        echo "$HOME/.zshrc"
    else
        echo "$HOME/.bashrc"
    fi
}

append_if_missing() {
    local file="$1"
    local marker="$2"
    local content="$3"

    touch "$file"
    if ! grep -Fq "$marker" "$file"; then
        printf '\n%s\n' "$content" >> "$file"
        log "Added environment block to $file"
    else
        info "Environment block already exists in $file"
    fi
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

restore_openclaude_backup() {
    local backup_dir="$1"
    local target="$HOME/.openclaude"

    if [ ! -d "$backup_dir" ]; then
        err "Backup directory not found: $backup_dir"
        return 1
    fi

    info "Restoring full OpenClaude environment from: $backup_dir"

    if [ -d "$target" ]; then
        local current_backup="$target.backup.$(date +%Y%m%d_%H%M%S)"
        cp -a "$target" "$current_backup"
        warn "Existing $target copied to $current_backup"
    fi

    mkdir -p "$target"
    cp -a "$backup_dir"/. "$target"/
    chmod 700 "$target" 2>/dev/null || true
    chmod 600 "$target"/*.json "$target"/*.secure* 2>/dev/null || true

    if [ -f "$target/settings.json" ]; then
        if json_validate "$target/settings.json"; then
            log "Restored settings.json is valid"
        else
            warn "Restored settings.json is not valid JSON; OpenClaude may ignore it"
        fi
    fi

    if [ -f "$target/Claude_Code-credentials.secure.dpapi" ]; then
        warn "Windows DPAPI credential file was restored but cannot be used on Linux."
        echo "    Providers stored as API keys/settings should still work. OAuth credentials may need login again."
    fi

    log "OpenClaude config restored to $target"
}

install_ollama_optional() {
    echo ""
    read -r -p "Install Ollama/local model support too? (y/n): " INSTALL_OLLAMA
    if [[ ! "$INSTALL_OLLAMA" =~ ^[Yy]$ ]]; then
        info "Skipped Ollama. Your restored providers/models remain unchanged."
        return 0
    fi

    if command -v ollama >/dev/null 2>&1; then
        info "Ollama already installed: $(ollama --version 2>/dev/null || echo installed)"
    else
        curl -fsSL https://ollama.com/install.sh | sh
        log "Ollama installed"
    fi

    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable ollama >/dev/null 2>&1 || true
        sudo systemctl start ollama >/dev/null 2>&1 || true
    fi

    if ! curl -fsS http://localhost:11434/api/tags >/dev/null 2>&1; then
        nohup ollama serve >/tmp/ollama-openclaude.log 2>&1 &
        sleep 3
    fi

    local default_model="qwen2.5-coder:7b"
    read -r -p "Pull optional local model $default_model? (y/n): " PULL_MODEL
    if [[ "$PULL_MODEL" =~ ^[Yy]$ ]]; then
        ollama pull "$default_model"
        log "$default_model pulled"
        warn "OpenClaude settings were not overwritten. Use /provider or edit settings.json if you want Ollama as default."
    fi
}

echo "============================================"
echo "  OpenClaude Linux Mint Migration Setup"
echo "============================================"
echo ""
echo "Goal: restore your providers, agents, project memory, and model routing"
echo "from the Windows backup onto Linux Mint running on the external SSD."
echo ""

# ------------------------------------------------------------
# 1. System packages
# ------------------------------------------------------------
log "Updating apt package index..."
sudo apt update

log "Installing dependencies..."
sudo apt install -y curl wget git build-essential unzip ca-certificates jq

# ------------------------------------------------------------
# 2. Node.js LTS via nvm
# ------------------------------------------------------------
log "Installing Node.js LTS via nvm..."
export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
else
    info "nvm already installed"
fi

# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

if ! command -v nvm >/dev/null 2>&1; then
    err "nvm is not available after installation. Open a new terminal and rerun this script."
    exit 1
fi

nvm install --lts
nvm use --lts
log "Node.js $(node --version)"
log "npm $(npm --version)"

# ------------------------------------------------------------
# 3. Install OpenClaude CLI
# ------------------------------------------------------------
log "Installing OpenClaude CLI..."
npm install -g @gitlawb/openclaude
log "OpenClaude: $(openclaude --version 2>/dev/null || echo 'installed')"

# ------------------------------------------------------------
# 4. Restore full OpenClaude backup
# ------------------------------------------------------------
BACKUP_DIR="$(find_backup_dir "${1:-}" || true)"
if [ -n "$BACKUP_DIR" ]; then
    restore_openclaude_backup "$BACKUP_DIR"
else
    warn "No OpenClaude backup found automatically."
    echo "Expected path examples:"
    echo "  /media/\$USER/<drive>/openclaude-backup/dot-openclaude"
    echo "  /mnt/openclaude-backup/dot-openclaude"
    read -r -p "Enter backup path manually, or leave empty to skip restore: " MANUAL_BACKUP
    if [ -n "$MANUAL_BACKUP" ]; then
        restore_openclaude_backup "$MANUAL_BACKUP"
    else
        warn "Skipped restore. OpenClaude will start with fresh config until you run restore.sh."
    fi
fi

# ------------------------------------------------------------
# 5. Shell environment on external Linux install
# ------------------------------------------------------------
SHELL_RC="$(select_shell_rc)"
NODE_BIN_DIR="$(dirname "$(command -v node)")"
OPENCLAUDE_ENV_BLOCK="# OpenClaude Linux Mint migration\nexport PATH=\"$NODE_BIN_DIR:\$PATH\"\nexport OLLAMA_HOST=\"http://localhost:11434\"\nexport OLLAMA_MODELS=\"\$HOME/.ollama/models\""
append_if_missing "$SHELL_RC" "# OpenClaude Linux Mint migration" "$OPENCLAUDE_ENV_BLOCK"

# ------------------------------------------------------------
# 6. Optional local model support
# ------------------------------------------------------------
install_ollama_optional

# ------------------------------------------------------------
# 7. Summary
# ------------------------------------------------------------
echo ""
echo "============================================"
echo "  Migration Setup Complete"
echo "============================================"
echo ""
log "Node.js: $(node --version)"
log "npm: $(npm --version)"
log "OpenClaude: $(openclaude --version 2>/dev/null || echo 'check with: openclaude --version')"

if [ -d "$HOME/.openclaude" ]; then
    log "OpenClaude config: $HOME/.openclaude"
    echo "    Agents:   $(find "$HOME/.openclaude/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"
    echo "    Projects: $(find "$HOME/.openclaude/projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
    echo "    Memory:   $(find "$HOME/.openclaude/projects" -name '*.md' 2>/dev/null | wc -l) files"
fi

echo ""
echo "Next steps:"
echo "  1. Open a new terminal, or run: source $SHELL_RC"
echo "  2. Start OpenClaude: openclaude"
echo "  3. Use /provider to verify restored providers/models"
echo "  4. If OAuth providers fail, login again on Linux; API-key providers should remain in settings."
echo ""
