#!/bin/bash
# ============================================================
# OpenClaude + Ollama Setup Script for Linux Mint
# Author: lht3003-rgb
# Usage: bash setup.sh
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "============================================"
echo "  OpenClaude + Ollama Full Setup for Linux"
echo "============================================"
echo ""

# ------------------------------------------------------------
# 1. System Update
# ------------------------------------------------------------
log "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# ------------------------------------------------------------
# 2. Install dependencies
# ------------------------------------------------------------
log "Installing dependencies..."
sudo apt install -y curl wget git build-essential unzip

# ------------------------------------------------------------
# 3. Install Node.js (LTS via nvm)
# ------------------------------------------------------------
log "Installing Node.js via nvm..."
if [ ! -d "$HOME/.nvm" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
else
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    warn "nvm already installed"
fi

nvm install --lts
nvm use --lts
log "Node.js $(node --version) installed"
log "npm $(npm --version) installed"

# ------------------------------------------------------------
# 4. Install Ollama
# ------------------------------------------------------------
log "Installing Ollama..."
if command -v ollama &> /dev/null; then
    warn "Ollama already installed: $(ollama --version)"
else
    curl -fsSL https://ollama.com/install.sh | sh
    log "Ollama installed: $(ollama --version)"
fi

# Start Ollama service
log "Starting Ollama service..."
sudo systemctl enable ollama 2>/dev/null || true
sudo systemctl start ollama 2>/dev/null || ollama serve &>/dev/null &
sleep 3

# ------------------------------------------------------------
# 5. Pull default models
# ------------------------------------------------------------
log "Pulling default models..."
echo "  Models to pull:"
echo "    - qwen2.5-coder:7b  (coding, ~4.7GB)"
echo ""

read -p "Pull models now? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ollama pull qwen2.5-coder:7b
    log "qwen2.5-coder:7b pulled"

    read -p "Pull more models? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Available popular models:"
        echo "  ollama pull llama3.1:8b        # General purpose"
        echo "  ollama pull deepseek-r1:8b     # Reasoning"
        echo "  ollama pull gemma3:4b          # Vision"
        echo "  ollama pull codellama:7b       # Code"
        echo "  ollama pull mistral:7b         # Fast"
        echo ""
        read -p "Enter model name to pull (or 'skip'): " MODEL
        if [ "$MODEL" != "skip" ] && [ -n "$MODEL" ]; then
            ollama pull "$MODEL"
            log "$MODEL pulled"
        fi
    fi
else
    warn "Skipped model pulling"
fi

# ------------------------------------------------------------
# 6. Install OpenClaude CLI
# ------------------------------------------------------------
log "Installing OpenClaude CLI..."
npm install -g @gitlawb/openclaude
log "OpenClaude installed: $(openclaude --version 2>/dev/null || echo 'installed')"

# ------------------------------------------------------------
# 7. Clone OpenClaude source (for Ollama integration updates)
# ------------------------------------------------------------
log "Cloning OpenClaude source..."
OPENCLAUDE_DIR="$HOME/openclaude"
if [ ! -d "$OPENCLAUDE_DIR" ]; then
    git clone https://github.com/Gitlawb/openclaude.git "$OPENCLAUDE_DIR"
    log "Source cloned to $OPENCLAUDE_DIR"
else
    warn "Source already exists at $OPENCLAUDE_DIR"
    cd "$OPENCLAUDE_DIR" && git pull
fi

# Build from source
cd "$OPENCLAUDE_DIR"
bun install 2>/dev/null || npm install
log "Dependencies installed"

# ------------------------------------------------------------
# 8. Setup OpenClaude config
# ------------------------------------------------------------
log "Setting up OpenClaude config..."
OPENCLAUDE_CONFIG="$HOME/.openclaude.json"

if [ ! -f "$OPENCLAUDE_CONFIG" ]; then
    cat > "$OPENCLAUDE_CONFIG" << 'EOF'
{
  "providerProfiles": [
    {
      "id": "ollama-local",
      "name": "Ollama Local",
      "provider": "ollama",
      "baseUrl": "http://localhost:11434/v1",
      "model": "qwen2.5-coder:7b",
      "apiKey": "ollama"
    }
  ],
  "activeProviderProfileId": "ollama-local"
}
EOF
    log "Config created at $OPENCLAUDE_CONFIG"
else
    warn "Config already exists, skipping"
fi

# ------------------------------------------------------------
# 9. Create OpenClaude settings directory
# ------------------------------------------------------------
log "Creating OpenClaude settings..."
OPENCLAUDE_DIR_CONFIG="$HOME/.openclaude"
mkdir -p "$OPENCLAUDE_DIR_CONFIG"

if [ ! -f "$OPENCLAUDE_DIR_CONFIG/settings.json" ]; then
    cat > "$OPENCLAUDE_DIR_CONFIG/settings.json" << 'EOF'
{
  "model": "qwen2.5-coder:7b",
  "effort": "high"
}
EOF
    log "Settings created"
fi

# ------------------------------------------------------------
# 10. Setup environment variables
# ------------------------------------------------------------
log "Setting up environment variables..."
SHELL_RC="$HOME/.bashrc"
[ -n "$ZSH_VERSION" ] && SHELL_RC="$HOME/.zshrc"

if ! grep -q "OLLAMA_HOST" "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" << 'EOF'

# OpenClaude + Ollama
export OLLAMA_HOST="0.0.0.0:11434"
export OLLAMA_MODELS="$HOME/.ollama/models"
export PATH="$HOME/.nvm/versions/node/$(node --version)/bin:$PATH"
EOF
    log "Environment variables added to $SHELL_RC"
fi

# ------------------------------------------------------------
# 11. Verify installation
# ------------------------------------------------------------
echo ""
echo "============================================"
echo "  Installation Complete!"
echo "============================================"
echo ""

log "Node.js: $(node --version)"
log "npm: $(npm --version)"
log "Ollama: $(ollama --version 2>/dev/null || echo 'check with: ollama --version')"
log "OpenClaude: $(openclaude --version 2>/dev/null || echo 'check with: openclaude --version')"

echo ""
echo "Installed Ollama models:"
ollama list 2>/dev/null || echo "  (start ollama first)"

echo ""
echo "Quick start:"
echo "  1. Open new terminal (or run: source $SHELL_RC)"
echo "  2. Run: openclaude"
echo "  3. Or chat with Ollama: ollama run qwen2.5-coder:7b"
echo ""
echo "To pull more models:"
echo "  ollama pull <model-name>"
echo "  Example: ollama pull llama3.1:8b"
echo ""
echo "Config file: $OPENCLAUDE_CONFIG"
echo "Settings dir: $OPENCLAUDE_DIR_CONFIG"
echo ""
