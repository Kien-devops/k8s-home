# Trivy Setup

![Trivy](https://img.shields.io/badge/Trivy-Security%20Scanner-1904DA?logo=aqua&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Image%20Scan-2496ED?logo=docker&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-IaC%20Scan-326CE5?logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-Misconfig%20Scan-844FBA?logo=terraform&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-CI%20Gate-2088FF?logo=githubactions&logoColor=white)

Trivy scans container images, filesystems, dependency manifests, Kubernetes YAML, Terraform code, secrets, and common misconfigurations.

## Workflow

```mermaid
flowchart LR
  code[Repository] --> fs[Filesystem scan]
  docker[Docker image] --> image[Image scan]
  tf[Terraform] --> iac[IaC scan]
  k8s[Kubernetes manifests] --> iac
  fs --> gate[Security gate]
  image --> gate
  iac --> gate
  gate --> gha[GitHub Actions result]
```

## Policy

Local scan defaults:

```text
security/trivy/.env
security/trivy/trivy.yaml.example
```

Recommended CI gate:

| Scan | Severity | Exit |
|---|---|---|
| Filesystem/dependencies | `HIGH,CRITICAL` | fail on finding |
| Terraform/Kubernetes config | `HIGH,CRITICAL` | fail on finding |
| Container image | `HIGH,CRITICAL` | fail on finding |
| Secrets | enabled | review immediately |

## Install

Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install -y trivy
trivy --version
```

Docker alternative:

```bash
docker run --rm aquasec/trivy:latest --version
```

## Scan Repository

```bash
trivy fs --severity HIGH,CRITICAL --exit-code 1 .
```

## Scan Kubernetes Manifests

```bash
trivy config --severity HIGH,CRITICAL --exit-code 1 k8s/base
```

## Scan Terraform

```bash
trivy config --severity HIGH,CRITICAL --exit-code 1 terraform
```

## Scan Docker Images

```bash
trivy image --severity HIGH,CRITICAL --exit-code 1 <image>:<tag>
```

Examples:

```bash
trivy image --severity HIGH,CRITICAL --exit-code 1 hospital-dev-frontend:latest
trivy image --severity HIGH,CRITICAL --exit-code 1 hospital-dev-backend:latest
```

## GitHub Actions

```yaml
- name: Trivy filesystem scan
  uses: aquasecurity/trivy-action@v0.36.0
  with:
    scan-type: fs
    scan-ref: .
    severity: HIGH,CRITICAL
    exit-code: "1"

- name: Trivy IaC scan
  uses: aquasecurity/trivy-action@v0.36.0
  with:
    scan-type: config
    scan-ref: .
    severity: HIGH,CRITICAL
    exit-code: "1"
```

## Triage Workflow

```mermaid
sequenceDiagram
  participant CI as GitHub Actions
  participant T as Trivy
  participant Dev as Developer
  participant PR as Pull Request

  CI->>T: run scan
  T-->>CI: vulnerabilities or misconfigurations
  CI-->>PR: fail check if policy is violated
  Dev->>PR: patch dependency/image/config
  CI->>T: scan again
  T-->>CI: pass
```

## Security Notes

- Avoid `--ignore-unfixed` unless the risk is reviewed.
- Use `.trivyignore` only with ticket references and expiry dates.
- Scan both source code and built images.
- Keep Trivy DB updates enabled in CI.

