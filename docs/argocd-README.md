# Argo CD GitOps

![Argo CD](https://img.shields.io/badge/Argo%20CD-GitOps-EF7B4D?logo=argo&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-Deployments-326CE5?logo=kubernetes&logoColor=white)
![GitHub](https://img.shields.io/badge/GitHub-Source%20of%20Truth-181717?logo=github&logoColor=white)
![YAML](https://img.shields.io/badge/YAML-Manifests-CB171E?logo=yaml&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-Charts-0F1689?logo=helm&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-GitOps%20Managed-E6522C?logo=prometheus&logoColor=white)
![Loki](https://img.shields.io/badge/Loki-GitOps%20Managed-F46800?logo=grafana&logoColor=white)
![Kyverno](https://img.shields.io/badge/Kyverno-Policy%20as%20Code-326CE5?logo=kubernetes&logoColor=white)

This folder contains Argo CD `Application` manifests. These files tell Argo CD what to install or sync into the on-premise Kubernetes cluster.

Argo CD is the desired-state controller for the cluster. Git is the source of truth, and manual cluster changes may be reverted when self-heal is enabled.

![Argo CD GitOps overview](./image.png)

## Folder Responsibility

```text
deploy/argocd/    = GitOps installation and sync definitions (applications, projects, bootstrap)
deploy/platform/  = Core infrastructure and platform configuration (ingress, monitoring, security, etc.)
deploy/workloads/ = Application workload configurations (frontend, backend)
```

Examples:

| Argo CD application manifest path | What it does | Runtime / Config path |
|---|---|---|
| `deploy/argocd/applications/workloads/hospital-frontend-prod.yaml` | Syncs the frontend app (production). | `deploy/workloads/hospital-frontend/overlays/prod` |
| `deploy/argocd/applications/workloads/hospital-backend-prod.yaml` | Syncs the backend app (production). | `deploy/workloads/hospital-backend/overlays/prod` |
| `deploy/argocd/applications/platform/traefik.yaml` | Installs Traefik Ingress Controller. | `deploy/platform/ingress/traefik` |
| `deploy/argocd/applications/platform/kyverno.yaml` | Installs Kyverno policy engine from Helm. | `security` namespace |
| `deploy/argocd/applications/platform/security-config.yaml` | Syncs Kyverno cluster policies & External Secrets. | `deploy/platform/security` |
| `deploy/argocd/applications/platform/kube-prometheus-stack.yaml` | Installs Prometheus, Grafana, and Alertmanager from Helm. | `monitoring` namespace |
| `deploy/argocd/applications/platform/monitoring-config.yaml` | Syncs Prometheus alert rules. | `deploy/platform/observability/monitoring` |
| `deploy/argocd/applications/platform/loki.yaml` | Installs Loki log aggregator from Helm. | `logging` namespace |
| `deploy/argocd/applications/platform/promtail.yaml` | Installs Promtail log shipper from Helm. | `logging` namespace |
| `deploy/argocd/applications/platform/logging-config.yaml` | Syncs Loki datasource ConfigMap. | `deploy/platform/observability/logging` |

## Learning Map

| Concept | Local example |
|---|---|
| App of apps mindset | Security, monitoring, and logging are represented as separate Argo CD Applications, bootstraped by the Root App. |
| Helm through Argo CD | `deploy/argocd/applications/platform/kyverno.yaml`, `.../kube-prometheus-stack.yaml`, and `.../loki.yaml`. |
| Kustomize through Argo CD | `deploy/argocd/applications/workloads/*`, `.../security-config.yaml`, `.../monitoring-config.yaml`, and `.../logging-config.yaml`. |
| Self-healing | Application specs use `syncPolicy.automated.selfHeal`. |
| Drift control | Application specs use `syncPolicy.automated.prune`. |

## Architecture

```mermaid
flowchart LR
    git[Git repository<br/>branch main] --> app[Argo CD Application]
    app --> path[deploy/workloads/...]
    path --> sync[Automated sync]
    sync --> ns1[namespace traefik]
    sync --> ns2[namespace hospital-prod]
    ns1 --> traefik[Traefik Gateway]
    ns2 --> workloads[Frontend, backend, and Redis HA workloads]
```

## Architecture With Security And Monitoring

```mermaid
flowchart TB
    git[Git repository<br/>branch main] --> argocd[Argo CD<br/>namespace argocd]

    argocd --> appFE[hospital-frontend-prod]
    argocd --> appBE[hospital-backend-prod]
    appFE --> fePath[deploy/workloads/hospital-frontend/overlays/prod]
    appBE --> bePath[deploy/workloads/hospital-backend/overlays/prod]
    fePath --> hospitalNs[namespace hospital-prod]
    bePath --> hospitalNs
    hospitalNs --> fe[Frontend pods]
    hospitalNs --> be[Backend API pods]
    
    argocd --> redisApp[hospital-redis-ha app<br/>Helm chart]
    redisApp --> hospitalNs
    hospitalNs --> redis[Redis HA pods]

    argocd --> traefikApp[traefik app]
    traefikApp --> traefikNs[namespace traefik]
    traefikNs --> gateway[Traefik Gateway<br/>Gateway and HTTPRoute]

    argocd --> kyvernoApp[kyverno app<br/>Helm chart]
    argocd --> trivyApp[trivy-operator app<br/>Helm chart]
    argocd --> falcoApp[falco app<br/>Helm chart]
    argocd --> policyApp[security-config app]
    argocd --> promApp[kube-prometheus-stack app<br/>Helm chart]
    argocd --> ruleApp[monitoring-config app]
    argocd --> lokiApp[loki app<br/>Helm chart]
    argocd --> promtailApp[promtail app<br/>Helm chart]
    argocd --> loggingConfigApp[logging-config app]

    kyvernoApp --> securityNs[namespace security]
    trivyApp --> securityNs
    falcoApp --> securityNs
    policyApp --> securityPath[deploy/platform/security]
    securityPath --> securityNs

    securityNs --> kyverno[Kyverno<br/>admission policies]
    securityNs --> trivy[Trivy Operator<br/>vulnerability reports]
    securityNs --> falco[Falco<br/>runtime detection]

    promApp --> monitoringNs[namespace monitoring]
    ruleApp --> monitoringPath[deploy/platform/observability/monitoring]
    monitoringPath --> monitoringNs
    monitoringNs --> prometheus[Prometheus<br/>metrics and rules]
    monitoringNs --> grafana[Grafana<br/>dashboards]
    monitoringNs --> alertmanager[Alertmanager<br/>alerts]
    lokiApp --> loggingNs[namespace logging]
    promtailApp --> loggingNs
    loggingConfigApp --> loggingPath[deploy/platform/observability/logging]
    loggingPath --> monitoringNs
    loggingNs --> loki[Loki<br/>logs]
    loggingNs --> promtail[Promtail<br/>log shipper]

    kyverno -. audits / blocks unsafe manifests .-> hospitalNs
    trivy -. scans workloads and images .-> hospitalNs
    falco -. observes runtime events .-> hospitalNs
    prometheus -. scrapes cluster and workload metrics .-> hospitalNs
    prometheus -. receives Kubernetes metrics .-> traefikNs
    promtail -. ships pod logs .-> loki
    grafana -. queries logs .-> loki
    alertmanager -. routes alerts .-> prometheus
```

Runtime model:

1. GitHub Actions updates image tags in Git after build and image scanning.
2. Argo CD syncs the app manifests from `deploy/workloads/.../base` into the `hospital-prod` and `traefik` namespaces using Kustomize overlays.
3. Argo CD also installs the security tools from `deploy/argocd/applications/platform/`.
4. Kyverno checks Kubernetes resources at admission time. Policies are currently in `Audit` mode.
5. Trivy Operator scans live cluster workloads and produces vulnerability/config reports.
6. Falco watches running containers and reports suspicious runtime behavior.
7. Prometheus collects cluster metrics, Grafana visualizes them, and Alertmanager handles alerts.
8. Promtail ships pod logs to Loki, and Grafana uses Loki as a log datasource.

The important split is:

```text
deploy/argocd/applications/platform/ = install/manage tools (helm charts)
deploy/platform/                     = configure/customize those tools after they exist (policies, rules, datasources)
```

## Files

| File/Folder | Purpose |
|---|---|
| `deploy/argocd/bootstrap/` | Root bootstrap application to deploy the whole stack. |
| `deploy/argocd/applications/workloads/` | Argo CD Applications for environment-specific app workloads. |
| `deploy/argocd/applications/platform/` | Argo CD Applications that install platform tools (Traefik, Prometheus, Loki, Kyverno, etc.). |
| `deploy/platform/` | Cluster-wide platform runtime configuration (observability rules, namespaces, ingress routes). |
| `deploy/workloads/` | Application workloads manifests (frontend, backend) organized by Kustomize. |
| `argocd-SETUP.md` | Step-by-step Argo CD installation notes. |
| `images/` | Documentation images. |

## Application Configuration (Root Bootstrap)

| Setting | Value |
|---|---|
| Repository | `https://github.com/Kien-devops/k8s-home.git` |
| Target revision | `main` |
| Manifest path | `deploy/argocd/bootstrap` |
| Destination server | `https://kubernetes.default.svc` |
| Destination namespace | `argocd` |
| Automated sync | Enabled |
| Prune | Enabled |
| Self-heal | Enabled |

## Deployment Flow

```mermaid
sequenceDiagram
    participant CI as GitHub Actions
    participant Git as Git repository
    participant A as Argo CD
    participant K as Kubernetes

    CI->>Git: Commit updated image tags
    A->>Git: Poll or receive refresh
    A->>A: Compare desired state with live state
    A->>K: Apply manifests
    A->>K: Prune removed resources
    A->>K: Self-heal drift
```

## Bootstrap Order

```mermaid
flowchart TD
  k8s[On-Prem K8s ready] --> argo[Install Argo CD]
  argo --> root[Apply root-app]
  root --> platform[Platform Apps]
  root --> workloads[Workload Apps]
  platform --> traefik[traefik]
  platform --> redis[hospital-redis-ha]
  platform --> secrets[external-secrets]
  platform --> kyverno[kyverno / security-config]
  platform --> monitoring[kube-prometheus-stack / monitoring-config]
  platform --> logging[loki / promtail / logging-config]
  workloads --> fe[hospital-frontend-prod]
  workloads --> be[hospital-backend-prod]
```

## Apply the Root Application

Run on a host with cluster access to bootstrap the entire stack:

```bash
kubectl apply -f deploy/argocd/bootstrap/root-app.yaml
```

Alternatively, apply the bootstrap kustomization directly:

```bash
kubectl apply -k deploy/argocd/bootstrap/
```

## Access the Argo CD UI

Port-forward the API server:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0
```

Open:

```text
https://<server-ip>:8080
```

Get the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
```

## Verify Sync

```bash
kubectl -n argocd get applications
kubectl -n argocd describe application hospital-frontend-prod
kubectl -n argocd get application kyverno trivy-operator falco security-config
kubectl -n argocd get application kube-prometheus-stack monitoring-config
kubectl -n argocd get application loki promtail logging-config
kubectl get pods -n hospital-prod
kubectl get pods -n traefik
kubectl get pods -n security
kubectl get pods -n monitoring
kubectl get pods -n logging
kubectl get clusterpolicy
kubectl get vulnerabilityreports -A
kubectl get prometheusrule -n monitoring
kubectl get gateway,httproute -n hospital-prod
```

Access Grafana:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Open:

```text
http://localhost:3000
```

To fetch the auto-generated Grafana admin password (default credentials are user `admin` and password `prom-operator` unless changed):

```bash
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d
echo
```

If you use the Argo CD CLI:

```bash
argocd app get hospital-frontend-prod
argocd app sync hospital-frontend-prod
```

## Operational Notes

| Topic | Guidance |
|---|---|
| Manual edits | Avoid `kubectl edit` for managed resources. Commit the change to Git instead. |
| Runtime secrets | Secrets such as `be-db-secret`, `redis-auth-secret`, and `nexus-registry-secret` are securely managed via HashiCorp Vault and synced into the cluster namespaces by External Secrets Operator (ESO). |
| Image deployment | GitHub Actions updates image tags in Git, then Argo CD syncs. |
| Drift | Self-heal will bring live resources back to Git state. |
| Prune | Deleted manifests can delete live resources during sync. Review changes carefully. |

## Troubleshooting

| Symptom | Check |
|---|---|
| Application is OutOfSync | Review changed resources and sync status. |
| Application is Degraded | Inspect pod status, events, and CRD readiness. |
| Sync fails on Gateway resources | Gateway API CRDs and Traefik CRDs must exist. |
| Image pull errors after sync | Check ESO sync status for `nexus-registry-secret`, image tag, registry connectivity. |
| Manual changes disappear | Expected behavior when self-heal is enabled. |
