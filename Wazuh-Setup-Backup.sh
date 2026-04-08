#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
#  Wazuh-Setup-Backup.sh
#  Deploys Wazuh single-node on Docker and
#  connects n8n to the Wazuh network
# ─────────────────────────────────────────────

# ── Config — edit these before running ────────
WAZUH_VERSION="4.10.0"
WAZUH_DIR="/opt/wazuh-docker"
N8N_CONTAINER="n8n"
# ──────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Root check ─────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "Please run as root or with sudo: sudo bash $0"
fi

# ── 1. Install Docker if missing ───────────────
install_docker() {
  info "Docker not found. Installing via official convenience script..."
  if ! command -v curl &>/dev/null; then
    apt-get update -qq && apt-get install -y curl
  fi
  curl -fsSL https://get.docker.com | sh
  if [[ -n "${SUDO_USER:-}" ]]; then
    usermod -aG docker "$SUDO_USER"
    warn "User '$SUDO_USER' added to the 'docker' group."
    warn "Log out and back in (or run 'newgrp docker') for the group change to take effect."
  fi
  systemctl enable --now docker
  info "Docker installed and started."
}

if command -v docker &>/dev/null; then
  info "Docker already installed: $(docker --version)"
else
  install_docker
fi

# ── 2. Ensure docker compose plugin is available
if ! docker compose version &>/dev/null; then
  info "Installing docker compose plugin..."
  apt-get update -qq && apt-get install -y docker-compose-plugin
fi
info "Docker Compose: $(docker compose version)"

# ── 3. Check system requirements ───────────────
#    Wazuh indexer requires vm.max_map_count >= 262144
CURRENT_MAP_COUNT=$(sysctl -n vm.max_map_count)
if [[ "$CURRENT_MAP_COUNT" -lt 262144 ]]; then
  info "Setting vm.max_map_count to 262144 (required by Wazuh indexer)..."
  sysctl -w vm.max_map_count=262144
  echo "vm.max_map_count=262144" >> /etc/sysctl.conf
fi

# ── 4. Download Wazuh single-node docker config ─
if [[ -d "$WAZUH_DIR" ]]; then
  warn "$WAZUH_DIR already exists."
  read -rp "  Re-download and overwrite? [y/N]: " OVERWRITE
  if [[ "$OVERWRITE" =~ ^[Yy]$ ]]; then
    # Stop and remove existing deployment first
    if [[ -f "$WAZUH_DIR/single-node/docker-compose.yml" ]]; then
      info "Stopping existing Wazuh deployment..."
      docker compose -f "$WAZUH_DIR/single-node/docker-compose.yml" down --volumes 2>/dev/null || true
    fi
    rm -rf "$WAZUH_DIR"
  else
    info "Skipping download. Using existing files in $WAZUH_DIR."
  fi
fi

if [[ ! -d "$WAZUH_DIR" ]]; then
  info "Downloading Wazuh ${WAZUH_VERSION} docker configuration..."
  curl -fsSL "https://github.com/wazuh/wazuh-docker/archive/refs/tags/v${WAZUH_VERSION}.tar.gz" \
    | tar -xz -C /opt
  mv "/opt/wazuh-docker-${WAZUH_VERSION}" "$WAZUH_DIR"
  info "Wazuh docker files saved to $WAZUH_DIR"
fi

COMPOSE_FILE="$WAZUH_DIR/single-node/docker-compose.yml"
[[ -f "$COMPOSE_FILE" ]] || error "docker-compose.yml not found at $COMPOSE_FILE"

# ── 5. Generate certificates ───────────────────
info "Generating Wazuh certificates..."
docker compose -f "$WAZUH_DIR/single-node/generate-indexer-certs.yml" run --rm generator
info "Certificates generated."

# ── 6. Start Wazuh single-node ─────────────────
info "Starting Wazuh single-node deployment..."
docker compose -f "$COMPOSE_FILE" up -d
info "Wazuh containers started."

# ── 7. Wait for Wazuh API to be ready ──────────
info "Waiting for Wazuh API to become ready (this may take a few minutes)..."
MAX_WAIT=180
ELAPSED=0

until curl -sk -o /dev/null -w "%{http_code}" \
    -u "wazuh:wazuh" "https://localhost:55000/" | grep -q "200"; do
  sleep 5
  ELAPSED=$((ELAPSED + 5))
  echo -n "."
  if [[ $ELAPSED -ge $MAX_WAIT ]]; then
    echo ""
    warn "Wazuh API did not respond within ${MAX_WAIT}s — it may still be initializing."
    warn "Check status with: docker compose -f $COMPOSE_FILE ps"
    break
  fi
done
echo ""

# ── 8. Connect n8n to the Wazuh network ────────
#    This lets n8n reach the Wazuh manager by hostname
WAZUH_NETWORK=$(docker network ls --format '{{.Name}}' | grep -i "single-node" | head -n1 || true)

if [[ -z "$WAZUH_NETWORK" ]]; then
  warn "Could not detect the Wazuh Docker network automatically."
  warn "Run manually: docker network connect <wazuh-network> ${N8N_CONTAINER}"
else
  if docker ps --format '{{.Names}}' | grep -q "^${N8N_CONTAINER}$"; then
    # Check if already connected
    if docker inspect "$N8N_CONTAINER" \
        --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' \
        | grep -q "$WAZUH_NETWORK"; then
      info "n8n is already connected to the Wazuh network ($WAZUH_NETWORK)."
    else
      docker network connect "$WAZUH_NETWORK" "$N8N_CONTAINER"
      info "Connected n8n container to Wazuh network: $WAZUH_NETWORK"
      info "n8n can now reach the Wazuh manager at: https://wazuh.manager:55000"
    fi
  else
    warn "n8n container ('${N8N_CONTAINER}') is not running."
    warn "Once n8n is running, connect it manually:"
    warn "  docker network connect ${WAZUH_NETWORK} ${N8N_CONTAINER}"
  fi
fi

# ── 9. Done ────────────────────────────────────
HOST_IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Wazuh single-node is running!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Dashboard:    https://${HOST_IP}  (admin / SecretPassword)"
echo "  Wazuh API:    https://${HOST_IP}:55000  (wazuh / wazuh)"
echo ""
echo "  n8n → Wazuh API (via Docker network):"
echo "    URL:      https://wazuh.manager:55000"
echo "    User:     wazuh"
echo "    Password: wazuh"
echo ""
echo "  Useful commands:"
echo "    docker compose -f $COMPOSE_FILE ps"
echo "    docker compose -f $COMPOSE_FILE logs -f"
echo "    docker compose -f $COMPOSE_FILE down"
echo ""
echo -e "${YELLOW}  Change default passwords after first login!${NC}"
echo ""
