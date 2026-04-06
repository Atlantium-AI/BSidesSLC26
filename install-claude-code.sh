#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
#  install-claude-code.sh
#  Installs Claude Code via the official native
#  installer (no Node.js required)
# ─────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Root check ─────────────────────────────────
# Claude Code should NOT be installed as root —
# the native installer installs to the user's home.
if [[ $EUID -eq 0 ]]; then
  error "Do not run this script as root. Run it as your normal user account."
fi

# ── 1. Check for existing install ──────────────
if command -v claude &>/dev/null; then
  CURRENT_VER=$(claude --version 2>/dev/null || echo "unknown")
  warn "Claude Code is already installed: $CURRENT_VER"
  read -rp "  Reinstall / update anyway? [y/N]: " REINSTALL
  if [[ ! "$REINSTALL" =~ ^[Yy]$ ]]; then
    info "Skipping install. Run 'claude --version' to confirm your version."
    exit 0
  fi
fi

# ── 2. Ensure curl is available ────────────────
if ! command -v curl &>/dev/null; then
  info "curl not found. Attempting to install..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y curl
  elif command -v yum &>/dev/null; then
    sudo yum install -y curl
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y curl
  else
    error "curl is required but could not be installed automatically. Please install it and re-run."
  fi
fi

# ── 3. Alpine/musl dependency check ────────────
#    Native binary requires libgcc, libstdc++, ripgrep on Alpine.
if [[ -f /etc/alpine-release ]]; then
  info "Alpine Linux detected. Installing required dependencies..."
  apk add --no-cache libgcc libstdc++ ripgrep
  export USE_BUILTIN_RIPGREP=0
fi

# ── 4. Remove old npm-based install if present ─
if command -v npm &>/dev/null; then
  OLD_NPM=$(npm list -g --depth=0 2>/dev/null | grep "@anthropic-ai/claude-code" || true)
  if [[ -n "$OLD_NPM" ]]; then
    warn "Old npm-based Claude Code install detected. Removing..."
    npm uninstall -g @anthropic-ai/claude-code
    info "Old npm install removed."
  fi
fi

# ── 5. Run the official native installer ────────
info "Downloading and running the official Claude Code installer..."
echo ""
curl -fsSL https://claude.ai/install.sh | bash
echo ""

# ── 6. Inject PATH into shell rc files ─────────
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

for RC_FILE in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [[ -f "$RC_FILE" ]]; then
    if ! grep -qF '$HOME/.local/bin' "$RC_FILE"; then
      echo "" >> "$RC_FILE"
      echo "# Added by install-claude-code.sh" >> "$RC_FILE"
      echo "$PATH_LINE" >> "$RC_FILE"
      info "Added ~/.local/bin to PATH in $RC_FILE"
    else
      info "~/.local/bin already in $RC_FILE — skipping."
    fi
  fi
done

# Apply to the current session immediately
export PATH="$HOME/.local/bin:$PATH"

# ── 7. Verify installation ──────────────────────
if command -v claude &>/dev/null; then
  VERSION=$(claude --version 2>/dev/null || echo "installed")
  info "Claude Code installed successfully: $VERSION"
else
  warn "The installer completed, but 'claude' is still not found."
  warn "Try opening a new terminal and running: claude --version"
fi

# ── 7. Auth reminder ───────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Claude Code is ready!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Next steps:"
echo "    1. Open a new terminal (or run: source ~/.bashrc)"
echo "    2. Navigate to a project directory"
echo "    3. Run: claude"
echo "       → Follow the auth prompt to connect your Anthropic account"
echo ""
echo "  Useful commands:"
echo "    claude --version        Check installed version"
echo "    claude doctor           Diagnose installation issues"
echo "    claude --help           Full command reference"
echo ""
echo "  Docs: https://docs.anthropic.com/en/docs/claude-code/overview"
echo ""
