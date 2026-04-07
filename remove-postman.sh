#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
#  remove-postman.sh
#  Completely removes Postman from the system
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
warn "This will completely remove Postman and all its data."
read -rp "  Are you sure? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  info "Aborted."
  exit 0
fi

REMOVED=0

# ── 1. App directory ───────────────────────────
if [[ -d "$HOME/.local/share/Postman" ]]; then
  rm -rf "$HOME/.local/share/Postman"
  info "Removed ~/.local/share/Postman"
  REMOVED=1
else
  warn "~/.local/share/Postman not found — skipping."
fi

# ── 2. Symlink ─────────────────────────────────
if [[ -L "$HOME/.local/bin/postman" ]]; then
  rm -f "$HOME/.local/bin/postman"
  info "Removed ~/.local/bin/postman symlink"
  REMOVED=1
else
  warn "~/.local/bin/postman symlink not found — skipping."
fi

# ── 3. Desktop entry ───────────────────────────
if [[ -f "$HOME/.local/share/applications/postman.desktop" ]]; then
  rm -f "$HOME/.local/share/applications/postman.desktop"
  info "Removed desktop entry"
  REMOVED=1
else
  warn "Desktop entry not found — skipping."
fi

# ── 4. App config / data ───────────────────────
for DIR in \
  "$HOME/.config/Postman" \
  "$HOME/.config/postman" \
  "$HOME/.cache/Postman" \
  "$HOME/.cache/postman"; do
  if [[ -d "$DIR" ]]; then
    rm -rf "$DIR"
    info "Removed $DIR"
    REMOVED=1
  fi
done

# ── 5. PATH line from shell rc files ───────────
for RC_FILE in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [[ -f "$RC_FILE" ]] && grep -q "Added by install-postman.sh" "$RC_FILE"; then
    # Remove the comment line and the export line that follows it
    sed -i '/# Added by install-postman.sh/{N;d}' "$RC_FILE"
    info "Removed PATH entry from $RC_FILE"
  fi
done

# ── Done ───────────────────────────────────────
echo ""
if [[ $REMOVED -eq 1 ]]; then
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  Postman has been completely removed.${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
  warn "Postman did not appear to be installed. Nothing was removed."
fi
echo ""
