# Logging GitOps Applications

![Argo CD](https://img.shields.io/badge/Argo%20CD-GitOps-EF7B4D?logo=argo&logoColor=white)
![Loki](https://img.shields.io/badge/Loki-Logs-F46800?logo=grafana&logoColor=white)
![Promtail](https://img.shields.io/badge/Promtail-Log%20Agent-F46800?logo=grafana&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-Explore%20Logs-F46800?logo=grafana&logoColor=white)

This folder contains Argo CD `Application` manifests for installing and managing the on-premise logging stack.

```text
argocd/logging = install/manage Loki, Promtail, and logging config
k8s/logging    = namespace and Grafana Loki datasource config
```

## Files

| File | Purpose |
|---|---|
| `10-loki-app.yaml` | Installs Loki from the Grafana Helm chart into the `logging` namespace. |
| `20-promtail-app.yaml` | Installs Promtail as a DaemonSet to ship pod logs to Loki. |
| `30-logging-config-app.yaml` | Syncs `k8s/logging`, including the Grafana datasource ConfigMap. |

## Apply Order

```bash
kubectl apply -f argocd/logging/10-loki-app.yaml
kubectl apply -f argocd/logging/20-promtail-app.yaml
kubectl apply -f argocd/logging/30-logging-config-app.yaml
```

## Verify

```bash
kubectl get applications -n argocd
kubectl get pods -n logging
kubectl get svc -n logging
kubectl get configmap -n monitoring loki-grafana-datasource
```

## Grafana Queries

Open Grafana Explore and choose the `Loki` datasource:

```logql
{namespace="hospital-prod"}
{namespace="hospital-prod", container=~".*be.*"} |= "error"
{namespace="security"} |= "falco"
{namespace="traefik"} |= "500"
```

## Object Storage Plan

The default Loki configuration uses local filesystem storage so the stack starts easily in an on-premises development cluster. For production or long-lived logs, switch Loki to S3-compatible object storage (such as MinIO or Ceph Object Gateway).

Required setup:

```text
S3-compatible buckets for chunks, ruler, and admin data
Kubernetes Secret containing MinIO access and secret keys
Loki Helm values configured to use s3-compatible storage type and internal endpoint
```

Recommended bucket settings:

```text
Buckets: loki-chunks, loki-ruler, loki-admin
Retention policy: expire old log objects after 7-30 days for dev, 30-90 days for production
```
