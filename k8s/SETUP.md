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

| Environment | Path | Namespace |
|---|---|---|
| prod | `k8s/overlays/prod` | `hospital-prod` |

## 8. Create Required Secrets

```bash
export K8S_NAMESPACE=hospital-prod

# Database connection
kubectl create secret generic be-db-secret \
  -n $K8S_NAMESPACE \
  --from-literal=default-connection='Server=<DB_IP>;Database=HospitalDB;User Id=sa;Password=<DB_PASSWORD>;TrustServerCertificate=True'

# Redis password (must match redis-auth-secret)
kubectl create secret generic be-redis-secret \
  -n $K8S_NAMESPACE \
  --from-literal=password='<REDIS_PASSWORD>'

# JWT secret
kubectl create secret generic be-jwt-secret \
  -n $K8S_NAMESPACE \
  --from-literal=secret='<JWT_SECRET>'

# Redis auth (used by redis DaemonSet)
kubectl create secret generic redis-auth-secret \
  -n $K8S_NAMESPACE \
  --from-literal=password='<REDIS_PASSWORD>'

# Nexus image pull secret
kubectl create secret docker-registry nexus-registry-secret \
  -n $K8S_NAMESPACE \
  --docker-server=100.112.150.56:8082 \
  --docker-username=admin \
  --docker-password='<NEXUS_PASSWORD>'
```

## 9. Prepare Redis Data Directory (on worker nodes)

```bash
sudo mkdir -p /var/lib/redis-data
sudo chown -R 999:999 /var/lib/redis-data
```

## 10. Deploy

```bash
# Traefik ingress
kubectl apply -k onprem/traefik
kubectl apply -f onprem/traefik/10-app-gateway-routes.example.yaml

# Hospital app
kubectl apply -k k8s/overlays/prod

# Redis
kubectl apply -k k8s/redis
```

## 11. Verify

```bash
kubectl get all -n hospital-prod
kubectl get gateway,httproute -n hospital-prod
kubectl get pods -n traefik
```

## 12. Remove

```bash
kubectl delete -k k8s/overlays/prod
kubectl delete -k k8s/redis
kubectl delete -k onprem/traefik
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| Calico cross-node DNS timeout | `kubectl set env ds/calico-node -n kube-system IP_AUTODETECTION_METHOD="cidr=192.168.1.0/24"` |
| Redis `Permission denied` on `/data` | `sudo chown -R 999:999 /var/lib/redis-data` on worker nodes |
| BE `CreateContainerConfigError` | Verify all secrets exist: `kubectl get secrets -n hospital-prod` |
| BE `ImagePullBackOff` | Verify `nexus-registry-secret` exists and CRI-O insecure registry is configured |
| Metrics Server crash | Patch with `--kubelet-insecure-tls` for bare-metal |
| NodePort not accessible | Check `ufw` and `iptables` rules on the node |
