#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
#  remove-claude-code.sh
#  Completely removes Claude Code — binary,
#  config, data, and PATH entries
# ─────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Root check ─────────────────────────────────
if [[ $EUID -eq 0 ]]; then
  error "Do not run this script as root. Run it as your normal user account."
fi

# ── Confirm ────────────────────────────────────
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  WARNING: This will permanently delete:${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  • Claude Code binary (~/.local/bin/claude)"
echo "  • Claude config and data (~/.claude and ~/.claude.json)"
echo "  • Anthropic directory (~/.anthropic)"
echo "  • npm global install (if present)"
echo "  • PATH entries added to ~/.bashrc and ~/.zshrc"
echo ""
read -rp "  Type 'yes' to confirm: " CONFIRM
echo ""

if [[ "$CONFIRM" != "yes" ]]; then
  info "Aborted. Nothing was changed."
  exit 0
fi

# ── 1. Remove native binary ────────────────────
if [[ -f "$HOME/.local/bin/claude" ]]; then
  rm -f "$HOME/.local/bin/claude"
  info "Removed ~/.local/bin/claude"
else
  info "No native binary found at ~/.local/bin/claude — skipping."
fi

# ── 2. Remove npm global install (if present) ──
if command -v npm &>/dev/null; then
  OLD_NPM=$(npm list -g --depth=0 2>/dev/null | grep "@anthropic-ai/claude-code" || true)
  if [[ -n "$OLD_NPM" ]]; then
    info "Removing npm-based Claude Code install..."
    npm uninstall -g @anthropic-ai/claude-code
    info "npm install removed."
  else
    info "No npm-based install found — skipping."
  fi
fi

# ── 3. Remove config and data directories ──────
for DIR in "$HOME/.claude" "$HOME/.anthropic"; do
  if [[ -d "$DIR" ]]; then
    rm -rf "$DIR"
    info "Removed $DIR"
  else
    info "$DIR not found — skipping."
  fi
done

# ── 4. Remove .claude.json ─────────────────────
if [[ -f "$HOME/.claude.json" ]]; then
  rm -f "$HOME/.claude.json"
  info "Removed ~/.claude.json"
else
  info "~/.claude.json not found — skipping."
fi

# ── 5. Clean PATH entries from shell rc files ──
for RC_FILE in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [[ -f "$RC_FILE" ]]; then
    # Remove the comment and export line added by the installer
    sed -i '/# Added by install-claude-code.sh/d' "$RC_FILE"
    sed -i '/\.local\/bin.*PATH/d' "$RC_FILE"
    info "Cleaned PATH entries from $RC_FILE"
  fi
done

# ── 6. Verify nothing remains ──────────────────
echo ""
if command -v claude &>/dev/null; then
  warn "'claude' is still found at: $(command -v claude)"
  warn "This may be a system-level install. You may need to remove it manually."
else
  info "Verified: 'claude' is no longer on PATH."
fi

# ── Done ───────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Claude Code has been completely removed.${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Open a new terminal to ensure PATH changes take effect."
echo ""
