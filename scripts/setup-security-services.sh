#!/usr/bin/env bash
# =============================================================================
# Security Stack — Full Automated Setup
# Server: monitor@monitor (100.112.150.56)
# Path:   ~/k8s-home/security
#
# Usage:
#   cd ~/k8s-home/security
#   chmod +x setup.sh
#   ./setup.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAILSCALE_IP="100.112.150.56"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }
info() { echo -e "${CYAN}[→]${NC} $1"; }

# =============================================================================
# 1. System Prerequisites
# =============================================================================
info "Step 1/8 — Checking system prerequisites..."

if ! command -v docker &>/dev/null; then
  err "Docker is not installed. Install it first:"
  echo "  curl -fsSL https://get.docker.com | sudo sh"
  echo "  sudo usermod -aG docker \$USER"
  echo "  newgrp docker"
  exit 1
fi
log "Docker $(docker --version | awk '{print $3}') found"

if ! docker compose version &>/dev/null; then
  err "Docker Compose plugin not found."
  exit 1
fi
log "Docker Compose $(docker compose version --short) found"

# =============================================================================
# 2. Kernel Tuning (SonarQube requirement)
# =============================================================================
info "Step 2/8 — Kernel tuning for SonarQube..."

CURRENT_MAP_COUNT=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
if [ "$CURRENT_MAP_COUNT" -lt 524288 ]; then
  warn "vm.max_map_count=$CURRENT_MAP_COUNT (need 524288). Applying..."
  sudo sysctl -w vm.max_map_count=524288
  echo 'vm.max_map_count=524288' | sudo tee /etc/sysctl.d/99-sonarqube.conf >/dev/null
  sudo sysctl --system >/dev/null
  log "vm.max_map_count set to 524288"
else
  log "vm.max_map_count=$CURRENT_MAP_COUNT (OK)"
fi

# =============================================================================
# 3. Firewall (UFW)
# =============================================================================
info "Step 3/8 — Configuring firewall..."

if command -v ufw &>/dev/null; then
  if sudo ufw status | grep -q "inactive"; then
    warn "UFW is inactive. Enabling with SSH + Tailscale rules..."
    sudo ufw --force enable
  fi
  sudo ufw allow OpenSSH >/dev/null 2>&1 || true
  # Allow Tailscale subnet
  sudo ufw allow from 100.64.0.0/10 >/dev/null 2>&1 || true
  log "UFW configured: SSH + Tailscale subnet allowed"
else
  warn "UFW not installed. Skipping firewall setup."
fi

# =============================================================================
# 4. Environment Files
# =============================================================================
info "Step 4/8 — Checking environment files..."

if [ ! -f "${SCRIPT_DIR}/.env" ]; then
  err ".env file not found!"
  echo ""
  echo "  Create it first by copying .env.example:"
  echo "    cp .env.example .env"
  echo "    nano .env  # fill in SONAR_POSTGRES_PASSWORD"
  echo ""
  echo "  Or run the env creation commands from the README."
  exit 1
fi
log ".env file found"

# Validate required vars
source "${SCRIPT_DIR}/.env"
if [ -z "${SONAR_POSTGRES_PASSWORD:-}" ]; then
  err "SONAR_POSTGRES_PASSWORD is empty in .env"
  exit 1
fi
log "Required environment variables validated"

# =============================================================================
# 5. Docker Compose Up
# =============================================================================
info "Step 5/8 — Starting services..."

cd "${SCRIPT_DIR}"
docker compose up -d
log "Docker Compose started"

# =============================================================================
# 6. Health Checks
# =============================================================================
info "Step 6/8 — Waiting for services to be healthy..."

echo -n "  PostgreSQL: "
for i in $(seq 1 30); do
  if docker compose exec -T sonarqube-db pg_isready -U "${SONAR_POSTGRES_USER:-sonar}" &>/dev/null; then
    echo -e "${GREEN}ready${NC}"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo -e "${RED}timeout${NC}"
    err "PostgreSQL failed to start. Check: docker compose logs sonarqube-db"
    exit 1
  fi
  echo -n "."
  sleep 2
done

echo -n "  SonarQube:  "
for i in $(seq 1 60); do
  STATUS=$(curl -sf http://localhost:${SONARQUBE_PORT:-9000}/api/system/status 2>/dev/null | grep -oP '"status":"\K[^"]+' || true)
  if [ "$STATUS" = "UP" ]; then
    echo -e "${GREEN}UP${NC}"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo -e "${YELLOW}still starting (this is normal on first run, may take 2-3 min)${NC}"
  fi
  echo -n "."
  sleep 3
done

echo -n "  Nexus:      "
for i in $(seq 1 60); do
  if curl -sf http://localhost:${NEXUS_PORT:-8081}/service/rest/v1/status &>/dev/null; then
    echo -e "${GREEN}ready${NC}"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo -e "${YELLOW}still starting (Nexus takes 1-2 min on first run)${NC}"
  fi
  echo -n "."
  sleep 3
done

# =============================================================================
# 7. Install Trivy on Host
# =============================================================================
info "Step 7/8 — Installing Trivy scanner..."

if command -v trivy &>/dev/null; then
  log "Trivy $(trivy --version 2>/dev/null | head -1 | awk '{print $2}') already installed"
else
  warn "Installing Trivy..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq wget apt-transport-https gnupg lsb-release
  wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg 2>/dev/null
  echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq trivy
  log "Trivy $(trivy --version 2>/dev/null | head -1 | awk '{print $2}') installed"
fi

# =============================================================================
# 8. Summary
# =============================================================================
info "Step 8/8 — Setup complete!"

echo ""
echo "============================================="
echo "  Security Stack — Monitor Server"
echo "============================================="
echo ""
echo "  Services:"
echo "    SonarQube:  http://${TAILSCALE_IP}:${SONARQUBE_PORT:-9000}"
echo "    Nexus:      http://${TAILSCALE_IP}:${NEXUS_PORT:-8081}"
echo "    Nexus Docker Registry: ${TAILSCALE_IP}:8082"
echo ""
echo "  First-time steps:"
echo "    1. SonarQube: Login admin/admin → change password → generate token"
echo "    2. Nexus:     docker exec -it nexus cat /nexus-data/admin.password"
echo "                  Login → change password → disable anonymous access"
echo "    3. Nexus repos: ./create-nexus-repos.sh"
echo "    4. GitHub Actions: Add secrets SONAR_HOST_URL, SONAR_TOKEN,"
echo "                       NEXUS_URL, NEXUS_USERNAME, NEXUS_PASSWORD"
echo ""
echo "  Verify:"
echo "    docker compose ps"
echo "    trivy --version"
echo "    curl -s http://localhost:${SONARQUBE_PORT:-9000}/api/system/status"
echo "    curl -s http://localhost:${NEXUS_PORT:-8081}/service/rest/v1/status"
echo "============================================="
