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

## 8. Configure Enterprise Secrets Management

To maintain security and GitOps compliance, secrets are not created manually via `kubectl`. Instead, we use **AWS Secrets Manager** as the central authority, and the **External Secrets Operator (ESO)** synchronizes them to the cluster.

### A. Create Secrets in AWS Secrets Manager

Execute the following commands to create the 5 required credentials in your AWS environment.

```bash
# 1. Database connection string
aws secretsmanager create-secret \
  --name hospital-be-db \
  --description "Database Connection String" \
  --secret-string '{"default-connection":"Server=<DB_IP>;Database=HospitalDB;User Id=sa;Password=<DB_PASSWORD>;TrustServerCertificate=True"}' \
  --region us-east-1

# 2. Redis password for backend
aws secretsmanager create-secret \
  --name hospital-be-redis \
  --description "Redis password for backend" \
  --secret-string '{"password":"<REDIS_PASSWORD>"}' \
  --region us-east-1

# 3. JWT signing key
aws secretsmanager create-secret \
  --name hospital-be-jwt \
  --description "JWT signing key" \
  --secret-string '{"secret":"<JWT_SECRET>"}' \
  --region us-east-1

# 4. Redis auth (used by the Redis DaemonSet)
aws secretsmanager create-secret \
  --name hospital-redis-auth \
  --description "Redis DaemonSet auth" \
  --secret-string '{"password":"<REDIS_PASSWORD>"}' \
  --region us-east-1

# 5. Nexus image pull credentials
aws secretsmanager create-secret \
  --name hospital-nexus-registry \
  --description "Nexus Docker Registry credentials for K8s ImagePullSecrets" \
  --secret-string '{"username":"admin","password":"<NEXUS_PASSWORD>"}' \
  --region us-east-1
```

### B. Sync via External Secrets Operator

When you deploy your application (via ArgoCD or Kustomize), the `ExternalSecret` custom resources will automatically be applied. ESO will pull these AWS secrets and generate the necessary Kubernetes `Secret` resources.

Verify that the secrets have successfully synchronized:

```bash
kubectl get externalsecret -n hospital-prod
```
Look for `SecretSynced = True` under the STATUS column for all 5 secrets.

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
