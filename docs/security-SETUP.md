# Security Stack Setup

## Quick Start (One-liner)

SSH vào monitor server và chạy:

```bash
cd ~/k8s-home && chmod +x scripts/setup-security-services.sh && ./scripts/setup-security-services.sh
```

## Full Manual Setup

### 1. Prepare Server

```bash
sudo apt update
sudo apt install -y curl uidmap dbus-user-session ufw fail2ban unzip
sudo ufw allow OpenSSH
sudo ufw allow from 100.64.0.0/10
sudo ufw enable
```

Install Docker:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
docker --version
```

SonarQube kernel requirement:

```bash
sudo sysctl -w vm.max_map_count=524288
echo 'vm.max_map_count=524288' | sudo tee /etc/sysctl.d/99-sonarqube.conf
sudo sysctl --system
```

### 2. Create Environment Files

```bash
cd ~/k8s-home/services

# Root .env (Docker Compose)
cat > .env << 'EOF'
BIND_ADDRESS=0.0.0.0
SONARQUBE_PORT=9000
SONAR_POSTGRES_USER=sonar
SONAR_POSTGRES_PASSWORD=SonarDB-K8sHome-2026!
SONAR_POSTGRES_DB=sonarqube
NEXUS_PORT=8081
EOF

# SonarQube .env (after generating token)
cat > sonarqube/.env << 'EOF'
SONAR_HOST_URL=http://100.112.150.56:9000
SONAR_TOKEN=<generated-token-from-sonarqube-ui>
SONAR_PROJECT_KEY_BACKEND=k8s-home
SONAR_PROJECT_KEY_FRONTEND=hospital-frontend
EOF

# Nexus .env (after first login and password change)
cat > nexus/.env << 'EOF'
NEXUS_URL=http://100.112.150.56:8081
NEXUS_USERNAME=admin
NEXUS_PASSWORD=<changed-admin-password>
NEXUS_DOCKER_REGISTRY=100.112.150.56:8082
EOF

# Trivy .env
cat > trivy/.env << 'EOF'
TRIVY_SEVERITY=HIGH,CRITICAL
TRIVY_EXIT_CODE=1
TRIVY_IGNORE_UNFIXED=false
TRIVY_TIMEOUT=10m
EOF
```

### 3. Start Services

```bash
cd ~/k8s-home/services
docker compose up -d
docker compose ps
```

### 4. Access

| Tool | URL |
|---|---|
| SonarQube | `http://100.112.150.56:9000` |
| Nexus | `http://100.112.150.56:8081` |
| Nexus Docker Registry | `100.112.150.56:8082` |

### 5. First Login

**SonarQube:**

```bash
# Default: admin / admin
# Change password immediately after first login
# Then generate a token: Administration > Security > Users > Tokens
```

**Nexus:**

```bash
# Get initial admin password:
docker exec -it nexus cat /nexus-data/admin.password

# Login with admin + that password
# Change password, disable anonymous access
```

### 6. Create Nexus Repositories

After Nexus is running and password is changed:

```bash
# Update services/nexus/.env with real credentials first
cd ~/k8s-home
chmod +x scripts/create-nexus-repos.sh
./scripts/create-nexus-repos.sh
```

### 7. Install Trivy on Host

```bash
sudo apt-get update
sudo apt-get install -y wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install -y trivy
trivy --version
```

### 8. GitHub Actions Secrets

Add these secrets to your GitHub repository:

| Secret | Value |
|---|---|
| `SONAR_HOST_URL` | `http://100.112.150.56:9000` |
| `SONAR_TOKEN` | generated SonarQube token |
| `NEXUS_URL` | `http://100.112.150.56:8081` |
| `NEXUS_USERNAME` | Nexus CI user |
| `NEXUS_PASSWORD` | Nexus CI password |

## Stop

```bash
cd ~/k8s-home/services
docker compose down
```

## Backup

Back up these Docker volumes before upgrades:

- `services_sonarqube-db-data`
- `services_sonarqube-data`
- `services_sonarqube-extensions`
- `services_nexus-data`

## Verify

```bash
cd ~/k8s-home/services
docker compose ps
curl -s http://localhost:9000/api/system/status
curl -s http://localhost:8081/service/rest/v1/status
trivy --version
```
