# Kubernetes On-Premise Setup

## 1. Initialize Cluster (node1 - Control Plane)

```bash
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=192.168.1.24
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

## 2. Install Calico CNI

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
```

> **IMPORTANT**: If nodes use Tailscale, Calico may pick the wrong interface.
> Fix by forcing Calico to use the private LAN subnet:

```bash
kubectl set env daemonset/calico-node -n kube-system \
  IP_AUTODETECTION_METHOD="cidr=192.168.1.0/24"
```

Verify Calico is using the correct IPs:

```bash
kubectl get pods -n kube-system -l k8s-app=calico-node -o wide
```

## 3. Join Worker Nodes

On the control plane, generate the join command:

```bash
kubeadm token create --print-join-command
```

On each worker node:

```bash
sudo kubeadm join 192.168.1.24:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

## 4. Install Metrics Server

Required for HPA (Horizontal Pod Autoscaler):

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# On bare-metal, patch to skip TLS verification:
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

## 5. Install Gateway API CRDs

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
```

## 6. Configure CRI-O Insecure Registry (on ALL nodes)

If using CRI-O with an HTTP-only Nexus Docker Registry:

```bash
sudo tee /etc/containers/registries.conf.d/100-nexus.conf << 'EOF'
[[registry]]
location = "100.112.150.56:8082"
insecure = true
EOF

sudo systemctl restart crio
```

## 7. Choose Environment

Kustomize overlays are split by environment:

| Environment | Overlay Path | Namespace |
|---|---|---|
| dev | `deploy/workloads/hospital-*/overlays/dev` | `hospital-dev` |
| stag | `deploy/workloads/hospital-*/overlays/stag` | `hospital-stag` |
| prod | `deploy/workloads/hospital-*/overlays/prod` | `hospital-prod` |

## 8. Configure Enterprise Secrets Management

To maintain security and GitOps compliance, secrets are not created manually via `kubectl` or committed to Git. Instead, we use **HashiCorp Vault** as the central authority, and the **External Secrets Operator (ESO)** synchronizes them to the cluster.

### A. Create Secrets in HashiCorp Vault

Execute the following commands (or use the Vault UI/API) to create the 5 required secrets under the `secret/` path (KV v2 engine) on your Vault server.

```bash
# Enable the KV version 2 secrets engine at path secret (if not already enabled)
vault secrets enable -path=secret kv-v2

# 1. Database connection string
vault kv put secret/hospital/be-db \
  default-connection="Server=<DB_IP>;Database=HospitalDB;User Id=sa;Password=<DB_PASSWORD>;TrustServerCertificate=True"

# 2. Redis password for backend
vault kv put secret/hospital/be-redis \
  password="<REDIS_PASSWORD>"

# 3. JWT signing key
vault kv put secret/hospital/be-jwt \
  secret="<JWT_SECRET>"

# 4. Redis HA auth (used by the Redis HA Helm chart)
vault kv put secret/hospital/redis-auth \
  password="<REDIS_PASSWORD>"

# 5. Nexus image pull credentials
vault kv put secret/hospital/nexus-registry \
  username="admin" \
  password="<NEXUS_PASSWORD>"
```

### B. Sync via External Secrets Operator

When you deploy your application (via ArgoCD or Kustomize), the `ExternalSecret` custom resources will automatically be applied. ESO will pull these Vault secrets and generate the corresponding Kubernetes `Secret` resources in the workloads namespace.

Verify that the secrets have successfully synchronized:

```bash
kubectl get externalsecret -n hospital-prod
```
Look for `SecretSynced = True` under the STATUS column for all 5 secrets.

## 9. Redis HA Cache

Redis is installed by Argo CD from the Bitnami Redis Helm chart:

```bash
kubectl apply -f deploy/argocd/applications/platform/hospital-redis-ha-app.yaml
```

The production backend connects to:

```text
hospital-redis-ha:6379
```

Persistence is disabled for this cache-only Redis deployment, so no worker-node data directory is required.

## 10. Deploy (Fallback / Testing without ArgoCD)

```bash
# Platform Namespaces
kubectl apply -k deploy/platform/namespaces

# Traefik ingress
kubectl apply -k deploy/platform/ingress/traefik
kubectl apply -f deploy/platform/ingress/traefik/app-gateway-routes.example.yaml

# Redis HA cache
kubectl apply -f deploy/argocd/applications/platform/hospital-redis-ha-app.yaml

# Hospital app workloads
kubectl apply -k deploy/workloads/hospital-frontend/overlays/prod
kubectl apply -k deploy/workloads/hospital-backend/overlays/prod
```

## 11. Verify

```bash
kubectl get all -n hospital-prod
kubectl get gateway,httproute -n hospital-prod
kubectl get pods -n traefik
```

## 12. Remove

```bash
kubectl delete -k deploy/workloads/hospital-frontend/overlays/prod
kubectl delete -k deploy/workloads/hospital-backend/overlays/prod
kubectl delete -f deploy/argocd/applications/platform/hospital-redis-ha-app.yaml
kubectl delete -k deploy/platform/ingress/traefik
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| Calico cross-node DNS timeout | `kubectl set env ds/calico-node -n kube-system IP_AUTODETECTION_METHOD="cidr=192.168.1.0/24"` |
| Backend Redis timeout to `hospital-redis-ha:6379` | Set `ConnectionStrings__Redis` to `hospital-redis-ha:6379,password=$(REDIS_PASSWORD),abortConnect=false` and restart backend |
| BE `CreateContainerConfigError` | Verify all secrets exist: `kubectl get secrets -n hospital-prod` |
| BE `ImagePullBackOff` | Verify `nexus-registry-secret` exists and CRI-O insecure registry is configured |
| Metrics Server crash | Patch with `--kubelet-insecure-tls` for bare-metal |
| NodePort not accessible | Check `ufw` and `iptables` rules on the node |
