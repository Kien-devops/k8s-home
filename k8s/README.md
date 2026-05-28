# Kubernetes Manifests

![Kubernetes](https://img.shields.io/badge/Kubernetes-Manifests-326CE5?logo=kubernetes&logoColor=white)
![Kustomize](https://img.shields.io/badge/Kustomize-Overlays-326CE5?logo=kubernetes&logoColor=white)
![Argo CD](https://img.shields.io/badge/Argo%20CD-GitOps-EF7B4D?logo=argo&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Images-2496ED?logo=docker&logoColor=white)
![NetworkPolicy](https://img.shields.io/badge/NetworkPolicy-Zero%20Trust-326CE5?logo=kubernetes&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-Rules-E6522C?logo=prometheus&logoColor=white)
![Loki](https://img.shields.io/badge/Loki-Logs-F46800?logo=grafana&logoColor=white)
![Kyverno](https://img.shields.io/badge/Kyverno-Policies-326CE5?logo=kubernetes&logoColor=white)

This folder contains the Kubernetes runtime manifests deployed by Argo CD.

The `k8s/` folder is the runtime layer. It contains resources that run in, or configure things inside, the Kubernetes cluster. Argo CD Application manifests live in `argocd/`.

![Kubernetes runtime overview](./image.png)

## Learning Map

| Topic | Where it appears |
|---|---|
| Application runtime | `k8s/base` |
| Redis HA cache operations | `k8s/redis` |
| Environment overlays | `k8s/overlays/dev`, `k8s/overlays/stag`, `k8s/overlays/prod` |
| Cluster security configuration | `k8s/security` |
| Cluster monitoring configuration | `k8s/monitoring` |
| Cluster logging configuration | `k8s/logging` |
| GitOps installer layer | `argocd/` |

## Architecture

```mermaid
flowchart TB
  argocd[Argo CD] --> kustomize[kustomize build k8s/overlays/env]
  kustomize --> ns[hospital-dev/stag/prod namespace]
  ns --> fe[Frontend Deployment]
  ns --> be[Backend Deployment]
  fe --> fesvc[Frontend Service]
  be --> besvc[Backend Service]
  be --> secret[be-db-secret]
  ns --> np[Network Policies]
  ingress[Traefik/Gateway] --> fesvc
  ingress --> besvc
```

## Deployment Workflow

```mermaid
sequenceDiagram
  participant Git
  participant Argo as Argo CD
  participant K8s as Kubernetes API
  participant Pods as Hospital Pods

  Git->>Argo: manifests changed
  Argo->>Argo: render kustomize overlay
  Argo->>K8s: apply desired resources
  K8s->>Pods: rollout deployments
  Argo->>K8s: prune/self-heal drift when enabled
```

## Structure

```text
k8s/
  base/
    kustomization.yaml
    05-fe-deployment.yaml
    06-fe-service.yaml
    07-be-deployment.yaml
    08-be-service.yaml
    10-network-policy.yaml
  redis/                  # Redis HA cache notes and secret examples
    README.md
    redis-auth-secret.example.yaml
    backend-redis-secret.example.yaml
  overlays/
    dev/
      namespace.yaml
      kustomization.yaml
    stag/
      namespace.yaml
      kustomization.yaml
    prod/
      namespace.yaml
      kustomization.yaml
  secrets/
    default-connection.txt.example
  security/
    namespace.yaml
    policies/
  monitoring/
    namespace.yaml
    rules/
  logging/
    namespace.yaml
    grafana-loki-datasource.yaml
```

## Runtime Responsibility

| Path | Purpose | Installed or synced by |
|---|---|---|
| `k8s/base` | Hospital frontend/backend runtime resources. | `argocd/hospital-traefik-app.yaml` |
| `k8s/redis` | Redis HA cache notes, troubleshooting, and secret examples. | `argocd/hospital-redis-ha-app.yaml` |
| `k8s/overlays/*` | Environment-specific replica/image overrides. | Manual apply or future environment-specific Argo CD apps. |
| `k8s/security` | Kyverno policies and security namespace. | `argocd/security/00-security-namespace-policies-app.yaml` |
| `k8s/monitoring` | Prometheus rules and monitoring namespace. | `argocd/monitoring/20-monitoring-rules-app.yaml` |
| `k8s/logging` | Logging namespace and Grafana Loki datasource. | `argocd/logging/30-logging-config-app.yaml` |

## Environments

| Environment | Path | Namespace | Replicas |
|---|---|---|---|
| dev | `k8s/overlays/dev` | `hospital-dev` | 1 frontend, 1 backend |
| stag | `k8s/overlays/stag` | `hospital-stag` | 2 frontend, 2 backend |
| prod | `k8s/overlays/prod` | `hospital-prod` | 3 frontend, 3 backend |

## Apply Manually

```bash
kubectl apply -k k8s/overlays/dev
kubectl apply -k k8s/overlays/stag
kubectl apply -k k8s/overlays/prod
```

## Required Secrets

Create these before deploying the backend:

```bash
cp k8s/secrets/default-connection.txt.example k8s/secrets/default-connection.txt
vi k8s/secrets/default-connection.txt

# Create namespace
kubectl apply -f k8s/overlays/dev/namespace.yaml

# Create database connection secret
kubectl -n hospital-dev create secret generic be-db-secret \
  --from-file=default-connection=k8s/secrets/default-connection.txt \
  --dry-run=client -o yaml | kubectl apply -f -

# Create Redis password secrets
kubectl -n hospital-dev create secret generic redis-auth-secret \
  --from-literal=password='<strong-redis-password>' \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n hospital-dev create secret generic be-redis-secret \
  --from-literal=password='<strong-redis-password>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

`k8s/secrets/default-connection.txt` is ignored by Git. Keep the real host, database name, user, and password only in that local file or in your cluster secret manager.

Create the image pull secret to authenticate against the internal Nexus Docker Registry:

```bash
kubectl -n hospital-dev create secret docker-registry nexus-registry-secret \
  --docker-server=100.114.175.75:8082 \
  --docker-username=<nexus-username> \
  --docker-password=<nexus-password>
```

## Verify

```bash
kubectl get pods,svc -n hospital-dev
kubectl describe deploy be-deployment-v1 -n hospital-dev
kubectl describe deploy fe-deployment-v1 -n hospital-dev
```
