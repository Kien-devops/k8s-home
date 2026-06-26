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
argocd/ = GitOps installation and sync definitions
k8s/    = Kubernetes resources that run in the cluster
```

Examples:

| Argo CD path | What it does | Runtime path |
|---|---|---|
| `hospital-traefik-app.yaml` | Syncs the hospital app. | `k8s/base` |
| `security/10-kyverno-app.yaml` | Installs Kyverno from Helm. | `security` namespace |
| `security/00-security-namespace-policies-app.yaml` | Syncs Kyverno policies. | `k8s/security` |
| `monitoring/10-kube-prometheus-stack-app.yaml` | Installs Prometheus, Grafana, and Alertmanager from Helm. | `monitoring` namespace |
| `monitoring/20-monitoring-rules-app.yaml` | Syncs Prometheus alert rules. | `k8s/monitoring` |
| `logging/10-loki-app.yaml` | Installs Loki from Helm. | `logging` namespace |
| `logging/20-promtail-app.yaml` | Installs Promtail from Helm. | `logging` namespace |
| `logging/30-logging-config-app.yaml` | Syncs Loki datasource config. | `k8s/logging` |

## Learning Map

| Concept | Local example |
|---|---|
| App of apps mindset | Security, monitoring, and logging are represented as separate Argo CD Applications. |
| Helm through Argo CD | `security/*-app.yaml`, `monitoring/10-kube-prometheus-stack-app.yaml`, and `logging/*-app.yaml`. |
| Kustomize through Argo CD | `hospital-traefik-app.yaml`, `security-namespace-policies`, `monitoring-rules`, and `logging-config`. |
| Self-healing | Application specs use `syncPolicy.automated.selfHeal`. |
| Drift control | Application specs use `syncPolicy.automated.prune`. |

## Architecture

```mermaid
flowchart LR
    git[Git repository<br/>branch devops] --> app[Argo CD Application]
    app --> path[k8s/overlays/prod]
    path --> sync[Automated sync]
    sync --> ns1[namespace traefik]
    sync --> ns2[namespace hospital-prod]
    ns1 --> traefik[Traefik Gateway]
    ns2 --> workloads[Frontend, backend, and Redis workloads]
```

## Architecture With Security And Monitoring

```mermaid
flowchart TB
    git[Git repository<br/>branch devops] --> argocd[Argo CD<br/>namespace argocd]

    argocd --> app[hospital-traefik-app]
    app --> appPath[k8s/overlays/prod]
    appPath --> hospitalNs[namespace hospital-prod]
    appPath --> traefikNs[namespace traefik]
    hospitalNs --> fe[Frontend pods]
    hospitalNs --> be[Backend API pods]
    hospitalNs --> redis[Redis DaemonSet pods]
    traefikNs --> gateway[Traefik Gateway<br/>Gateway and HTTPRoute]

    argocd --> kyvernoApp[kyverno app<br/>Helm chart]
    argocd --> trivyApp[trivy-operator app<br/>Helm chart]
    argocd --> falcoApp[falco app<br/>Helm chart]
    argocd --> policyApp[security-namespace-policies app]
    argocd --> promApp[kube-prometheus-stack app<br/>Helm chart]
    argocd --> ruleApp[monitoring-rules app]
    argocd --> lokiApp[loki app<br/>Helm chart]
    argocd --> promtailApp[promtail app<br/>Helm chart]
    argocd --> loggingConfigApp[logging-config app]

    kyvernoApp --> securityNs[namespace security]
    trivyApp --> securityNs
    falcoApp --> securityNs
    policyApp --> securityPath[k8s/security]
    securityPath --> securityNs

    securityNs --> kyverno[Kyverno<br/>admission policies]
    securityNs --> trivy[Trivy Operator<br/>vulnerability reports]
    securityNs --> falco[Falco<br/>runtime detection]

    promApp --> monitoringNs[namespace monitoring]
    ruleApp --> monitoringPath[k8s/monitoring]
    monitoringPath --> monitoringNs
    monitoringNs --> prometheus[Prometheus<br/>metrics and rules]
    monitoringNs --> grafana[Grafana<br/>dashboards]
    monitoringNs --> alertmanager[Alertmanager<br/>alerts]
    lokiApp --> loggingNs[namespace logging]
    promtailApp --> loggingNs
    loggingConfigApp --> loggingPath[k8s/logging]
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
2. Argo CD syncs the app manifests from `k8s/base` into the `hospital-prod` and `traefik` namespaces.
3. Argo CD also installs the security tools from `argocd/security`.
4. Kyverno checks Kubernetes resources at admission time. Policies are currently in `Audit` mode.
5. Trivy Operator scans live cluster workloads and produces vulnerability/config reports.
6. Falco watches running containers and reports suspicious runtime behavior.
7. Prometheus collects cluster metrics, Grafana visualizes them, and Alertmanager handles alerts.
8. Promtail ships pod logs to Loki, and Grafana uses Loki as a log datasource.

The important split is:

```text
argocd/security, argocd/monitoring, and argocd/logging = install/manage tools
k8s/security, k8s/monitoring, and k8s/logging          = configure those tools after they exist
```

## Files

| File | Purpose |
|---|---|
| `hospital-traefik-app.yaml` | Argo CD Application that syncs the Hospital Kubernetes stack from `k8s/base`. |
| `security/` | Argo CD Applications that install security tools and sync security config from `k8s/security`. |
| `monitoring/` | Argo CD Applications that install monitoring tools and sync monitoring config from `k8s/monitoring`. |
| `logging/` | Argo CD Applications that install logging tools and sync logging config from `k8s/logging`. |
| `SETUP.md` | Step-by-step Argo CD installation notes. |
| `images/` | Documentation images. |

## Application Configuration

| Setting | Value |
|---|---|
| Repository | `https://github.com/Kien-devops/k8s-home.git` |
| Target revision | `devops` |
| Manifest path | `k8s/overlays/prod` |
| Destination server | `https://kubernetes.default.svc` |
| Destination namespace | `hospital-prod` |
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
flowchart LR
  k8s[On-Prem K8s ready] --> argo[Install Argo CD]
  argo --> app[Apply hospital-traefik-app]
  argo --> kyverno[Apply Kyverno app]
  kyverno --> policies[Apply security policies app]
  argo --> trivy[Apply Trivy Operator app]
  argo --> falco[Apply Falco app]
  argo --> prom[Apply kube-prometheus-stack app]
  prom --> rules[Apply monitoring-rules app]
  argo --> loki[Apply Loki app]
  loki --> promtail[Apply Promtail app]
  promtail --> logcfg[Apply logging-config app]
```

## Apply the Application

Run on a host with cluster access:

```bash
kubectl apply -f argocd/hospital-traefik-app.yaml
```

Apply the security Applications:

```bash
kubectl apply -f argocd/security/10-kyverno-app.yaml
kubectl apply -f argocd/security/00-security-namespace-policies-app.yaml
kubectl apply -f argocd/security/20-trivy-operator-app.yaml
kubectl apply -f argocd/security/30-falco-app.yaml
```

Apply the monitoring Applications:

```bash
kubectl apply -f argocd/monitoring/10-kube-prometheus-stack-app.yaml
kubectl apply -f argocd/monitoring/20-monitoring-rules-app.yaml
```

Apply the logging Applications:

```bash
kubectl apply -f argocd/logging/10-loki-app.yaml
kubectl apply -f argocd/logging/20-promtail-app.yaml
kubectl apply -f argocd/logging/30-logging-config-app.yaml
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
kubectl -n argocd describe application hospital-traefik-app
kubectl -n argocd get application kyverno trivy-operator falco security-namespace-policies
kubectl -n argocd get application kube-prometheus-stack monitoring-rules
kubectl -n argocd get application loki promtail logging-config
kubectl get pods,daemonset -n hospital-prod
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

If you use the Argo CD CLI:

```bash
argocd app get hospital-traefik-app
argocd app sync hospital-traefik-app
```

## Operational Notes

| Topic | Guidance |
|---|---|
| Manual edits | Avoid `kubectl edit` for managed resources. Commit the change to Git instead. |
| Runtime secrets | Secrets such as `be-db-secret`, `redis-auth-secret`, and `nexus-registry-secret` are securely managed via AWS Secrets Manager and synced by External Secrets Operator (ESO). |
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
