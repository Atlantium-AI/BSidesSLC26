#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
#  install-postman.sh
#  Installs Postman on Linux via the official
#  tarball and creates a desktop entry
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

# ── 1. Check for existing install ──────────────
if [[ -d "$HOME/.local/share/Postman" ]]; then
  warn "Postman appears to be already installed at ~/.local/share/Postman"
  read -rp "  Reinstall / update anyway? [y/N]: " REINSTALL
  if [[ ! "$REINSTALL" =~ ^[Yy]$ ]]; then
    info "Skipping install."
    exit 0
  fi
fi

# ── 2. Ensure dependencies ─────────────────────
for DEP in curl tar; do
  if ! command -v "$DEP" &>/dev/null; then
    info "$DEP not found. Attempting to install..."
    if command -v apt-get &>/dev/null; then
      sudo apt-get update -qq && sudo apt-get install -y "$DEP"
    elif command -v dnf &>/dev/null; then
      sudo dnf install -y "$DEP"
    elif command -v yum &>/dev/null; then
      sudo yum install -y "$DEP"
    else
      error "$DEP is required but could not be installed automatically."
    fi
  fi
done

# ── 3. Download Postman ────────────────────────
INSTALL_DIR="$HOME/.local/share/Postman"
TMP_DIR=$(mktemp -d)
TARBALL="$TMP_DIR/postman.tar.gz"

info "Downloading Postman..."
curl -fsSL "https://dl.pstmn.io/download/latest/linux_64" -o "$TARBALL"

# ── 4. Extract ─────────────────────────────────
info "Extracting to $INSTALL_DIR..."
mkdir -p "$HOME/.local/share"
rm -rf "$INSTALL_DIR"
tar -xzf "$TARBALL" -C "$TMP_DIR"
mv "$TMP_DIR/Postman" "$INSTALL_DIR"
rm -rf "$TMP_DIR"

# ── 5. Symlink binary ──────────────────────────
mkdir -p "$HOME/.local/bin"
ln -sf "$INSTALL_DIR/Postman" "$HOME/.local/bin/postman"
info "Symlinked binary to ~/.local/bin/postman"

# ── 6. Create desktop entry ────────────────────
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_DIR/postman.desktop" <<EOF
[Desktop Entry]
Name=Postman
Comment=API Development Environment
Exec=$INSTALL_DIR/Postman
Icon=$INSTALL_DIR/app/resources/app/assets/icon.png
Terminal=false
Type=Application
Categories=Development;
EOF
info "Desktop entry created"

# ── 7. Ensure ~/.local/bin is in PATH ──────────
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
for RC_FILE in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [[ -f "$RC_FILE" ]]; then
    if ! grep -qF '$HOME/.local/bin' "$RC_FILE"; then
      echo "" >> "$RC_FILE"
      echo "# Added by install-postman.sh" >> "$RC_FILE"
      echo "$PATH_LINE" >> "$RC_FILE"
      info "Added ~/.local/bin to PATH in $RC_FILE"
    fi
  fi
done
export PATH="$HOME/.local/bin:$PATH"

# ── 8. Verify ──────────────────────────────────
if [[ -x "$INSTALL_DIR/Postman" ]]; then
  info "Postman installed successfully."
else
  error "Installation may have failed — $INSTALL_DIR/Postman not found."
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Postman is ready!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Launch options:"
echo "    - Run: postman"
echo "    - Or find it in your application menu"
echo ""
