# On-Premise Monitoring Stack

![Kubernetes](https://img.shields.io/badge/Kubernetes-Runtime%20Config-326CE5?logo=kubernetes&logoColor=white)
![Prometheus](https://img.shields.io/badge/PrometheusRule-Alert%20Rules-E6522C?logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-Reads%20Prometheus-F46800?logo=grafana&logoColor=white)
![Kustomize](https://img.shields.io/badge/Kustomize-Render-326CE5?logo=kubernetes&logoColor=white)

This folder contains the Kubernetes monitoring baseline for the on-premise Kubernetes cluster.

These files are runtime configuration used after the monitoring tools are installed by Argo CD from `argocd/monitoring`.

```text
argocd/monitoring = install/manage monitoring tools
k8s/monitoring    = configure monitoring inside the cluster
```

## Components

| Component | Purpose |
|---|---|
| `monitoring` namespace | Shared namespace for Prometheus, Grafana, and Alertmanager. |
| PrometheusRule | Custom workload alerts for the hospital namespaces. |
| ServiceMonitor | Scrapes custom endpoints, including Redis metrics when enabled by the Helm chart. |
| kube-prometheus-stack | Installed by Argo CD from Helm in `argocd/monitoring`. Provides Prometheus, Grafana, Alertmanager, node-exporter, and kube-state-metrics. |

## Metrics Source Model

```mermaid
flowchart LR
  node[Node metrics] --> exporter[node-exporter]
  pod[Pod/container metrics] --> kubelet[kubelet/cAdvisor]
  state[Kubernetes object state] --> ksm[kube-state-metrics]
  exporter --> prom[Prometheus]
  kubelet --> prom
  ksm --> prom
  prom --> grafana[Grafana]
  prom --> alertmanager[Alertmanager]
```

This project monitors infrastructure metrics (node, pod, container, Deployment, and Kubernetes object metrics) alongside service metrics scraped via custom ServiceMonitors, including Redis metrics when enabled.

## Apply Namespace And Rules

Install `kube-prometheus-stack` first so the `PrometheusRule` CRD exists.

```bash
kubectl apply -k k8s/monitoring
```

## Access Grafana

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Open:

```text
http://localhost:3000
```

Get the admin password:

```bash
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d
echo
```

## Useful Checks

```bash
kubectl get pods -n monitoring
kubectl get prometheus,alertmanager -n monitoring
kubectl get prometheusrule -n monitoring
kubectl get servicemonitor -A
```
