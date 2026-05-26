# Security Stack Setup

## 1. Prepare Server

```bash
sudo apt update
sudo apt install -y curl uidmap dbus-user-session ufw fail2ban
sudo ufw allow OpenSSH
sudo ufw enable
```

Install Docker and enable rootless mode:

```bash
curl -fsSL https://get.docker.com | sudo sh
dockerd-rootless-setuptool.sh install
systemctl --user enable docker
systemctl --user start docker
sudo loginctl enable-linger "$USER"
docker --version
```

SonarQube requires this kernel setting:

```bash
sudo sysctl -w vm.max_map_count=524288
echo 'vm.max_map_count=524288' | sudo tee /etc/sysctl.d/99-sonarqube.conf
sudo sysctl --system
```

## 2. Start Services

```bash
cd security
docker compose up -d
docker compose ps
```

## 3. Access

| Tool | Default local URL |
|---|---|
| SonarQube | `http://<host-ip-address>:9000` |
| Nexus | `http://<host-ip-address>:8081` |

If these run on a separate EC2 server, expose them with HTTPS through a reverse proxy and restrict inbound security group rules to trusted IPs.

## 4. Stop

```bash
docker compose down
```

## 5. Backup

Back up these Docker volumes:

- `security_sonarqube-db-data`
- `security_sonarqube-data`
- `security_sonarqube-extensions`
- `security_nexus-data`
