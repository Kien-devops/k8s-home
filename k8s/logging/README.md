# Kubernetes Logging Stack

![Kubernetes](https://img.shields.io/badge/Kubernetes-Runtime%20Config-326CE5?logo=kubernetes&logoColor=white)
![Loki](https://img.shields.io/badge/Loki-Log%20Store-F46800?logo=grafana&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-Log%20Explore-F46800?logo=grafana&logoColor=white)

This folder contains runtime logging configuration for a Kubernetes cluster after Loki and Promtail are installed by Argo CD from `argocd/logging`.

```text
argocd/logging = install/manage logging tools
k8s/logging    = configure logging inside the cluster
```

## Components

| Component | Purpose |
|---|---|
| `logging` namespace | Shared namespace for Loki and Promtail. |
| Loki datasource ConfigMap | Lets Grafana discover Loki as a datasource. |
| Loki | Stores and indexes Kubernetes logs. |
| Promtail | Collects pod stdout/stderr from every node and ships it to Loki. |

## Deploy To Kubernetes

If Argo CD is already installed in the cluster, apply the logging Applications from the repo root:

```bash
kubectl apply -f argocd/logging/10-loki-app.yaml
kubectl apply -f argocd/logging/20-promtail-app.yaml
kubectl apply -f argocd/logging/30-logging-config-app.yaml
```

This creates or syncs:

```text
logging namespace
Loki
Promtail DaemonSet
Grafana Loki datasource ConfigMap
```

The default values are tuned for a small Kubernetes cluster:

```text
Loki request: 50m CPU, 128Mi memory
Promtail request per node: 25m CPU, 64Mi memory
Loki persistence: disabled
Loki canary: disabled
Loki chunks/results cache: disabled
```

If pods stay `Pending`, check node capacity and events:

```bash
kubectl get pods -n logging
kubectl describe pod -n logging -l app.kubernetes.io/name=loki
kubectl describe pod -n logging -l app.kubernetes.io/name=promtail
kubectl top nodes
```

If you are not using Argo CD, install the same stack with Helm and then apply this folder:

```bash
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install loki grafana-community/loki \
  --namespace logging \
  --create-namespace \
  --values <values-from-argocd/logging/10-loki-app.yaml>

helm upgrade --install promtail grafana/promtail \
  --namespace logging \
  --values <values-from-argocd/logging/20-promtail-app.yaml>

kubectl apply -k k8s/logging
```

## Log Flow

```text
Pod stdout/stderr
-> node log files
-> Promtail DaemonSet
-> Loki
-> Grafana Explore
```

## Useful Checks

```bash
kubectl get pods -n logging
kubectl get svc -n logging
kubectl logs -n logging -l app.kubernetes.io/name=promtail --tail=100
kubectl logs -n logging -l app.kubernetes.io/name=loki --tail=100
```

## Useful LogQL

```logql
{namespace="hospital-prod"}
{namespace="hospital-prod"} |= "error"
{namespace="hospital-prod", pod=~".*be.*"}
{namespace="security"} |= "falco"
```

## Object Storage Plan

Use filesystem storage only for dev or demos. For persistent logs, configure Loki with an on-premises S3-compatible object storage service (such as MinIO or Ceph Object Gateway).

On-premises persistent logging flow:

```text
Loki
-> S3-compatible object storage (MinIO)
-> Grafana queries Loki
```

For on-premises Kubernetes, configure Loki with connection credentials pointing to the internal S3 endpoint.

Example values file configuration for Loki using MinIO:

```yaml
loki:
  storage:
    type: s3
    bucketNames:
      chunks: loki-chunks
      ruler: loki-ruler
      admin: loki-admin
    s3:
      endpoint: http://100.114.175.75:9000
      s3ForcePathStyle: true
      insecure: true
  storage_config:
    aws:
      endpoint: http://100.114.175.75:9000
      s3forcepathstyle: true
      bucketnames: loki-chunks
  schemaConfig:
    configs:
      - from: "2024-01-01"
        store: tsdb
        object_store: s3
        schema: v13
        index:
          prefix: loki_index_
          period: 24h
```

Pass the authentication credentials via a Kubernetes Secret containing the MinIO Access Key and Secret Key, and ensure the corresponding environment variables (`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`) are injected into the Loki pods.
