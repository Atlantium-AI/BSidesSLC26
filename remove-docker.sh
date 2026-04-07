#!/bin/bash
set -euo pipefail
 
# ─────────────────────────────────────────────
#  remove-docker.sh
#  Completely purges Docker and all associated
#  images, containers, volumes, and config data
# ─────────────────────────────────────────────
 
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
 
# ── Confirm ────────────────────────────────────
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  WARNING: This will permanently delete:${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  • All running and stopped containers"
echo "  • All Docker images"
echo "  • All volumes (persistent data)"
echo "  • All networks"
echo "  • Docker engine, CLI, and plugins"
echo "  • /var/lib/docker and /var/lib/containerd"
echo "  • /etc/docker config"
echo ""
read -rp "  Type 'yes' to confirm: " CONFIRM
echo ""
 
if [[ "$CONFIRM" != "yes" ]]; then
  info "Aborted. Nothing was changed."
  exit 0
fi
 
# ── 1. Stop and remove all containers ──────────
if command -v docker &>/dev/null; then
  CONTAINERS=$(docker ps -aq 2>/dev/null || true)
  if [[ -n "$CONTAINERS" ]]; then
    info "Stopping and removing all containers..."
    docker stop $CONTAINERS 2>/dev/null || true
    docker rm -f $CONTAINERS 2>/dev/null || true
  else
    info "No containers found."
  fi
 
  # ── 2. Remove all images ──────────────────────
  IMAGES=$(docker images -aq 2>/dev/null || true)
  if [[ -n "$IMAGES" ]]; then
    info "Removing all images..."
    docker rmi -f $IMAGES 2>/dev/null || true
  else
    info "No images found."
  fi
 
  # ── 3. Remove all volumes ─────────────────────
  VOLUMES=$(docker volume ls -q 2>/dev/null || true)
  if [[ -n "$VOLUMES" ]]; then
    info "Removing all volumes..."
    docker volume rm $VOLUMES 2>/dev/null || true
  else
    info "No volumes found."
  fi
 
  # ── 4. Remove all custom networks ─────────────
  info "Removing all custom networks..."
  docker network prune -f 2>/dev/null || true
 
  # ── 5. Final system prune ──────────────────────
  info "Running system prune..."
  docker system prune -a -f --volumes 2>/dev/null || true
else
  warn "Docker command not found — skipping container/image cleanup."
fi
 
# ── 6. Stop Docker services ────────────────────
info "Stopping Docker services..."
for svc in docker docker.socket containerd; do
  if systemctl list-units --full -all 2>/dev/null | grep -q "${svc}.service"; then
    systemctl stop "$svc"    2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
  fi
done
 
# ── 7. Uninstall Docker packages ───────────────
info "Uninstalling Docker packages..."
 
if command -v apt-get &>/dev/null; then
  apt-get purge -y \
    docker-ce \
    docker-ce-cli \
    docker-ce-rootless-extras \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    docker.io \
    docker-doc \
    docker-compose \
    podman-docker \
    2>/dev/null || true
  apt-get autoremove -y 2>/dev/null || true
  apt-get autoclean -y  2>/dev/null || true
 
elif command -v yum &>/dev/null; then
  yum remove -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-engine \
    2>/dev/null || true
 
elif command -v dnf &>/dev/null; then
  dnf remove -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    2>/dev/null || true
fi
 
# ── 8. Remove Docker data directories ──────────
info "Removing Docker data directories..."
for dir in \
  /var/lib/docker \
  /var/lib/containerd \
  /etc/docker \
  /run/docker \
  /run/containerd \
  /var/run/docker.sock \
  /usr/local/lib/docker; do
  if [[ -e "$dir" ]]; then
    rm -rf "$dir"
    info "  Removed: $dir"
  fi
done
 
# ── 9. Remove Docker apt/yum repo ──────────────
info "Removing Docker package repository..."
rm -f /etc/apt/sources.list.d/docker.list         2>/dev/null || true
rm -f /etc/apt/keyrings/docker.gpg                2>/dev/null || true
rm -f /etc/apt/keyrings/docker.asc                2>/dev/null || true
rm -f /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null || true
rm -f /etc/yum.repos.d/docker-ce.repo             2>/dev/null || true
 
if command -v apt-get &>/dev/null; then
  apt-get update -qq 2>/dev/null || true
fi
 
# ── 10. Remove docker group ────────────────────
if getent group docker &>/dev/null; then
  info "Removing docker group..."
  groupdel docker 2>/dev/null || true
fi
 
# ── Done ───────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Docker has been completely removed.${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  To verify nothing remains:"
echo "    which docker"
echo "    ls /var/lib/docker"
echo "    systemctl status docker"
echo ""
