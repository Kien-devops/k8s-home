# Traefik Gateway API Ingress

This folder installs Traefik as the in-cluster Gateway API controller for the on-prem Hospital deployment. HAProxy forwards traffic to Traefik through the NodePort service on port `30080`.

## Runtime Path

```text
Cloudflare Tunnel / Client
  -> HAProxy on monitor server
  -> Kubernetes worker NodePort 30080
  -> Traefik DaemonSet
  -> Gateway API HTTPRoute
  -> fe-service-v1 or be-service-v1
```

## Files

| File | Purpose |
|---|---|
| `00-namespace.yaml` | Creates the `traefik` namespace. |
| `01-traefik-rbac.yaml` | ServiceAccount, ClusterRole, and ClusterRoleBinding for Traefik. |
| `02-traefik-gatewayclass.yaml` | GatewayClass controlled by Traefik. |
| `03-traefik-daemonset.yaml` | Traefik DaemonSet. |
| `04-traefik-nodeport-service.yaml` | NodePort service exposing Traefik on `30080`. |
| `10-app-gateway-routes.example.yaml` | Example Gateway and HTTPRoute for `benhvien.teamdevops.shop`. |
| `kustomization.yaml` | Kustomize entrypoint for Traefik manifests. |

## Deploy

Install Gateway API CRDs first if they are not installed:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
```

Apply Traefik:

```bash
kubectl apply -k onprem/traefik
kubectl rollout status ds/traefik -n traefik
```

Apply the application Gateway and route:

```bash
kubectl apply -f onprem/traefik/10-app-gateway-routes.example.yaml
```

## Current Routing

The public hostname is:

```text
benhvien.teamdevops.shop
```

The route splits traffic by path:

```text
/api/* -> be-service-v1:80
/*     -> fe-service-v1:80
```

The backend API does not expose a root `/api` endpoint. Use real API paths for tests:

```bash
curl -i https://benhvien.teamdevops.shop/api/User/test
curl -i https://benhvien.teamdevops.shop/api/Doctor
curl -i https://benhvien.teamdevops.shop/api/Branch
```

## Verify

```bash
kubectl get gatewayclass
kubectl get gateway,httproute -n hospital-prod
kubectl get pods -n traefik -o wide
kubectl get svc -n traefik
```

Expected status:

```text
GatewayClass traefik ACCEPTED True
Gateway hospital-web-gateway PROGRAMMED True
Traefik NodePort 80:30080/TCP
```

Test Traefik directly from a cluster node:

```bash
curl -I -H "Host: benhvien.teamdevops.shop" http://192.168.1.9:30080/
curl -s -H "Host: benhvien.teamdevops.shop" http://192.168.1.9:30080/ | grep -i '<title>'
curl -i -H "Host: benhvien.teamdevops.shop" http://192.168.1.9:30080/api/User/test
```

Expected results:

```text
HTTP 200
<title>kien-hospital</title>
{"roles":[]}
```

## Control-Plane Nodes

In the current two-node lab, `node1` is the control-plane node and has this taint:

```text
node-role.kubernetes.io/control-plane:NoSchedule
```

Traefik does not run on `node1` unless a matching toleration is added to the DaemonSet. This is acceptable: HAProxy/Consul health checks keep only healthy Traefik NodePort targets in the generated HAProxy backend.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `GatewayClass ACCEPTED Unknown` | Traefik controller cannot reconcile Gateway API resources. | Check Traefik logs and RBAC. |
| Log says `secrets is forbidden` | Traefik lacks secret read permissions. | Ensure `01-traefik-rbac.yaml` grants `get/list/watch` on `secrets`. |
| `Gateway PROGRAMMED Unknown` | Gateway controller has not accepted/programmed the route. | Check `kubectl describe gateway -n hospital-prod hospital-web-gateway`. |
| `node1:30080` fails | Traefik is not scheduled on control-plane node. | Route to healthy worker nodes or add toleration intentionally. |
| `/api` returns `404` | Backend has no root `/api` endpoint. | Test `/api/User/test` or a real controller route. |
