# ArgoCD Setup Guide (On-Premise)

Run these commands on the Kubernetes control plane node (node1) where `kubectl` works.

## 1. Check Cluster Access

```bash
kubectl get nodes -o wide
```

## 2. Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Wait for all pods to be ready:

```bash
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=120s
kubectl get pods -n argocd
```

## 3. Fix ArgoCD NetworkPolicy (On-Premise)

> **IMPORTANT**: ArgoCD's default NetworkPolicies block internal DNS and Redis
> communication on bare-metal clusters. Delete them immediately after install:

```bash
kubectl delete networkpolicy --all -n argocd
```

If ArgoCD pods show DNS timeout errors (`argocd-redis: i/o timeout`), restart:

```bash
kubectl rollout restart deployment -n argocd
kubectl rollout restart statefulset -n argocd
```

## 4. Expose ArgoCD UI

### Option A: Port-Forward (recommended for Tailscale access)

```bash
kubectl port-forward svc/argocd-server -n argocd 8443:443 --address 0.0.0.0 &
```

Access: `https://<tailscale-ip>:8443`

### Option B: NodePort

```bash
kubectl patch svc argocd-server -n argocd -p '{
  "spec": {
    "type": "NodePort",
    "ports": [
      {"port": 80, "targetPort": 8080, "nodePort": 31080, "name": "http"},
      {"port": 443, "targetPort": 8080, "nodePort": 30444, "name": "https"}
    ]
  }
}'
sudo ufw allow 30444/tcp
```

Access: `https://<node-ip>:30444`

> **NOTE**: If Calico cross-node routing is broken (NodePort times out),
> use port-forward instead. See k8s/SETUP.md for Calico fix.

## 5. Get Admin Password

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Login: `admin` / `<password-from-command>`

## 6. Install Gateway API CRDs

Required before syncing the hospital app:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
```

## 7. Deploy All ArgoCD Applications

```bash
# Core hospital app
kubectl apply -f argocd/hospital-traefik-app.yaml
kubectl apply -f argocd/redis-app.yaml
kubectl apply -f argocd/storage-app.yaml

# Monitoring (Prometheus + Grafana + Alertmanager)
kubectl apply -f argocd/monitoring/

# Logging (Loki + Promtail)
kubectl apply -f argocd/logging/

# Security (Kyverno, Trivy Operator, Falco, ESO)
kubectl apply -f argocd/security/
```

## 8. Verify All Apps

```bash
kubectl get application -n argocd
```

Expected: 13 applications, all `Synced` and `Healthy`.

| App | Source |
|---|---|
| hospital-traefik-app | `k8s/overlays/prod` |
| redis | `k8s/redis` |
| storage | `k8s/storage` |
| kube-prometheus-stack | Helm chart |
| monitoring-rules | `k8s/monitoring` |
| loki | Helm chart |
| promtail | Helm chart |
| logging-config | `k8s/logging` |
| kyverno | Helm chart |
| security-namespace-policies | `k8s/security` |
| external-secrets | Helm chart |
| trivy-operator | Helm chart |
| falco | Helm chart |

## 9. Verify Workloads

```bash
kubectl get pods -n hospital-prod
kubectl get pods -n monitoring
kubectl get pods -n logging
kubectl get pods -n security
kubectl get pods -n traefik
```

## 10. Access Hospital App

```bash
# Via Traefik NodePort
http://<node-ip>:30080
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| ArgoCD Redis `i/o timeout` | Delete NetworkPolicies: `kubectl delete networkpolicy --all -n argocd` |
| ArgoCD UI not accessible via NodePort | Use port-forward: `kubectl port-forward svc/argocd-server -n argocd 8443:443 --address 0.0.0.0` |
| Apps stuck on `Unknown` sync status | Wait 2-3 min for ArgoCD to reconcile, or click REFRESH in UI |
| CRD errors (ServiceMonitor, ClusterPolicy) | These auto-resolve when ArgoCD installs the Helm charts (Prometheus, Kyverno) |
| `ApplicationSet` error in logs | Safe to ignore if not using ApplicationSets |

## Notes

- Git is the source of truth. Long-term changes should be committed and pushed to GitHub.
- If a pod is deleted manually, Kubernetes recreates it through its Deployment.
- If a Deployment, Service, Gateway, or Route is deleted manually, ArgoCD recreates it when `selfHeal` is enabled.
- If a manifest is removed from Git, ArgoCD deletes the live resource when `prune` is enabled.
