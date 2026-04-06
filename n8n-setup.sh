#!/bin/bash
set -euo pipefail
 
# ─────────────────────────────────────────────
#  deploy-n8n.sh
#  Installs Docker (if missing) and deploys n8n
# ─────────────────────────────────────────────
 
# ── Config — edit these before running ────────
N8N_PORT=5678
N8N_DATA_DIR="$HOME/.n8n"
CONTAINER_NAME="n8n"
N8N_IMAGE="docker.n8n.io/n8nio/n8n"
# ──────────────────────────────────────────────
 
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
 
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
 
# ── Root check ─────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "Please run as root or with sudo: sudo bash $0"
fi
 
# ── 1. Install Docker if not present ───────────
install_docker() {
  info "Docker not found. Installing via official convenience script..."
 
  if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
    apt-get update -qq && apt-get install -y curl
  fi
 
  curl -fsSL https://get.docker.com | sh
 
  # Add current SUDO_USER (if set) to the docker group
  if [[ -n "${SUDO_USER:-}" ]]; then
    usermod -aG docker "$SUDO_USER"
    warn "User '$SUDO_USER' added to the 'docker' group."
    warn "Log out and back in (or run 'newgrp docker') for group change to take effect."
  fi
 
  systemctl enable --now docker
  info "Docker installed and started."
}
 
if command -v docker &>/dev/null; then
  DOCKER_VER=$(docker --version)
  info "Docker already installed: $DOCKER_VER"
else
  install_docker
fi
 
# ── 2. Pull latest n8n image ───────────────────
info "Pulling latest n8n image..."
docker pull "$N8N_IMAGE"
 
# ── 3. Remove existing container (if any) ──────
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  warn "Existing container '$CONTAINER_NAME' found. Removing..."
  docker rm -f "$CONTAINER_NAME"
fi
 
# ── 4. Create persistent data directory ────────
mkdir -p "$N8N_DATA_DIR"
 
# Fix ownership so n8n (UID 1000) can write to it
chown -R 1000:1000 "$N8N_DATA_DIR"
 
info "n8n data directory: $N8N_DATA_DIR"
 
# ── 5. Run n8n container ───────────────────────
info "Starting n8n container..."
 
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p "${N8N_PORT}:5678" \
  -v "${N8N_DATA_DIR}:/home/node/.n8n" \
  -e GENERIC_TIMEZONE="America/Denver" \
  -e TZ="America/Denver" \
  "$N8N_IMAGE"
 
# ── 6. Health check ────────────────────────────
info "Waiting for n8n to become ready..."
MAX_WAIT=60
ELAPSED=0
 
until docker exec "$CONTAINER_NAME" wget -qO- http://localhost:5678/healthz &>/dev/null; do
  sleep 2
  ELAPSED=$((ELAPSED + 2))
  if [[ $ELAPSED -ge $MAX_WAIT ]]; then
    warn "n8n did not respond within ${MAX_WAIT}s — it may still be starting."
    break
  fi
done
 
# ── 7. Done ────────────────────────────────────
HOST_IP=$(hostname -I | awk '{print $1}')
 
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  n8n is running!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Local:   http://localhost:${N8N_PORT}"
echo -e "  Network: http://${HOST_IP}:${N8N_PORT}"
echo -e "  Data:    ${N8N_DATA_DIR}"
echo -e "  Logs:    docker logs -f ${CONTAINER_NAME}"
echo -e "  Stop:    docker stop ${CONTAINER_NAME}"
echo -e "  Start:   docker start ${CONTAINER_NAME}"
echo ""
