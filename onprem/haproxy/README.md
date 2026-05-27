# HAProxy Edge Load Balancer

This folder runs HAProxy as the edge load balancer for an on-prem Kubernetes cluster. In the current deployment, Cloudflare Tunnel publishes `https://benhvien.teamdevops.shop` and forwards requests to `http://127.0.0.1:80` on the HAProxy host. HAProxy then forwards HTTP to Traefik on worker NodePort `30080`.

If Cloudflare Tunnel is not used, HAProxy can also receive traffic directly on ports `80` and `443`; TLS termination can be enabled with `HAPROXY_TLS_CERT`.

The default runtime is fully automated:

```text
Kubernetes cluster
  <- kubectl get nodes
k8s-discovery container
  -> register/deregister traefik-nodeport services
Consul local agent
  -> service catalog and TCP health checks
Consul Template
  -> render generated/haproxy.cfg and send USR2
HAProxy
  -> graceful reload with current healthy worker nodes
```

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Runs Consul, HAProxy, Consul Template, and the Kubernetes discovery loop. |
| `templates/haproxy.cfg.ctmpl` | Consul Template source that renders backend servers from service `traefik-nodeport`. |
| `consul-template/consul-template.hcl` | Watches Consul, writes `generated/haproxy.cfg`, and gracefully reloads HAProxy. |
| `scripts/k8s-node-discovery.sh` | Polls Kubernetes nodes and keeps Consul registrations in sync. |
| `generated/` | Runtime HAProxy config output. Ignored by Git. |
| `kubeconfig/` | Optional local kubeconfig mount point. Real kubeconfig files are ignored by Git. |
| `haproxy.cfg.example` | Manual HAProxy config example for fallback or troubleshooting. |
| `.env.example` | Runtime settings template. |
| `certs/` | Local HAProxy PEM certificates. Do not commit real keys. |

## Configure Edge Server

```bash
cd onprem/haproxy
cp .env.example .env
mkdir -p generated kubeconfig
```

Put a kubeconfig file with read-only node access on the Edge Server:

```bash
cp /path/to/edge-readonly-kubeconfig kubeconfig/config
chmod 600 kubeconfig/config
```

The current monitor host uses this path instead:

```bash
sudo mkdir -p /etc/haproxy
sudo mv /home/monitor/edge-node-discovery.kubeconfig /etc/haproxy/edge-node-discovery.kubeconfig
sudo chown root:monitor /etc/haproxy/edge-node-discovery.kubeconfig
sudo chmod 640 /etc/haproxy/edge-node-discovery.kubeconfig
```

The discovery container only needs permission to read nodes:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: edge-node-discovery
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: edge-node-discovery
rules:
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: edge-node-discovery
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: edge-node-discovery
subjects:
  - kind: ServiceAccount
    name: edge-node-discovery
    namespace: kube-system
```

Set these values in `.env` if your environment differs:

| Variable | Default | Purpose |
|---|---:|---|
| `KUBECONFIG_PATH` | `./kubeconfig/config` | Host path mounted into the discovery container. |
| `TRAEFIK_NODEPORT` | `30080` | NodePort exposed by `onprem/traefik/04-traefik-nodeport-service.yaml`. |
| `NODE_ADDRESS_TYPE` | `InternalIP` | Node address type registered in Consul. Use `ExternalIP` if the Edge Server cannot reach internal node IPs. |
| `DISCOVERY_INTERVAL_SECONDS` | `15` | Poll interval for `kubectl get nodes`. |

For the current monitor server:

```env
KUBECONFIG_PATH=/etc/haproxy/edge-node-discovery.kubeconfig
TRAEFIK_NODEPORT=30080
NODE_ADDRESS_TYPE=InternalIP
```

## Cloudflare Tunnel

When `cloudflared` runs on the HAProxy host, configure the public hostname as:

```text
benhvien.teamdevops.shop -> http://127.0.0.1:80
```

The hostname must match the Traefik `HTTPRoute` hostname. If the browser shows `ERR_NAME_NOT_RESOLVED` while server-side `curl` works, flush the client DNS cache or switch the client resolver to a public DNS resolver such as `1.1.1.1` or `8.8.8.8`.

## TLS

The generated HAProxy config is HTTP-only unless `HAPROXY_TLS_CERT` is set.

When you want HTTPS, put a combined PEM file under:

```text
onprem/haproxy/certs/<domain>.pem
```

Create it from a Let's Encrypt certificate:

```bash
cat /etc/letsencrypt/live/<domain>/fullchain.pem \
    /etc/letsencrypt/live/<domain>/privkey.pem \
  > certs/<domain>.pem
chmod 644 certs/<domain>.pem
```

Then set:

```bash
HAPROXY_TLS_CERT=/usr/local/etc/haproxy/certs/<domain>.pem
```

## Start

```bash
docker compose up -d
docker compose logs -f haproxy
```

If files were copied from Windows, normalize shell/config files before starting containers:

```bash
sed -i 's/\r$//' scripts/k8s-node-discovery.sh
sed -i 's/\r$//' consul-template/consul-template.hcl
sed -i 's/\r$//' templates/haproxy.cfg.ctmpl
```

The `generated/` directory must be writable by the `consul-template` container. The Compose file runs `consul-template` as root for this reason. If you still see a write-permission error in a lab environment, fix the host directory permissions:

```bash
chmod 777 generated
```

## Verify Auto-Discovery

```bash
docker compose logs -f k8s-discovery
docker compose logs -f consul-template
docker exec haproxy-alb haproxy -c -f /usr/local/etc/haproxy/generated/haproxy.cfg
docker exec haproxy-alb grep 'server ' /usr/local/etc/haproxy/generated/haproxy.cfg
curl -s http://127.0.0.1:8500/v1/catalog/service/traefik-nodeport
```

The expected flow is:

1. `k8s-discovery` reads Ready Kubernetes nodes.
2. It registers each Ready node in Consul as service `traefik-nodeport`.
3. Consul performs TCP checks to `<node-ip>:30080`.
4. Consul Template renders only healthy service entries.
5. HAProxy receives `USR2` and reloads gracefully.

The current verified backend is the Traefik worker node:

```text
server ... 192.168.1.9:30080 check
```

`node1` is a control-plane node with a `NoSchedule` taint, so Traefik is not scheduled there unless tolerations are added. It is acceptable for discovery to register `node1`; Consul health checks filter it out when `node1:30080` is not healthy.

## End-To-End Tests

Run these on the HAProxy host:

```bash
cd ~/onprem/haproxy
docker compose ps
docker exec haproxy-alb haproxy -c -f /usr/local/etc/haproxy/generated/haproxy.cfg
docker exec haproxy-alb grep 'server ' /usr/local/etc/haproxy/generated/haproxy.cfg

curl -I -H "Host: benhvien.teamdevops.shop" http://127.0.0.1/
curl -s -H "Host: benhvien.teamdevops.shop" http://127.0.0.1/ | grep -i '<title>'

curl -I https://benhvien.teamdevops.shop/
curl -i https://benhvien.teamdevops.shop/api/User/test
curl -i https://benhvien.teamdevops.shop/api/Doctor
```

Expected results:

```text
HTTP 200 for frontend
<title>kien-hospital</title>
HTTP 200 for /api/User/test
HTTP 200 with JSON data for /api/Doctor
```

Test graceful reload:

```bash
docker exec haproxy-consul-template kill -USR2 1
docker compose logs --tail=20 haproxy
curl -I -H "Host: benhvien.teamdevops.shop" http://127.0.0.1/
```

Expected HAProxy log:

```text
Reloading HAProxy
New worker ... forked
Loading success
Former worker ... exited with code 0
```

## Manual Fallback

If auto-discovery is not needed, use `haproxy.cfg.example` as a standalone HAProxy config and point `HAPROXY_CONFIG` back to that file after mounting it into the HAProxy container.

Manual reload:

```bash
docker exec haproxy-alb haproxy -c -f /usr/local/etc/haproxy/generated/haproxy.cfg
docker kill -s USR2 haproxy-alb
```

## Troubleshooting

| Symptom | Check |
|---|---|
| Browser cannot connect | DNS, HAProxy host firewall, ports 80 and 443. |
| TLS error | PEM filename/path in `haproxy.cfg` does not match the certificate file. |
| `503 Service Unavailable` | Traefik pods, NodePort `30080`, worker firewall, Consul health status. |
| No backend servers rendered | `k8s-discovery` logs, kubeconfig path, RBAC, `NODE_ADDRESS_TYPE`. |
| `set: line 2: illegal option -` | Convert CRLF line endings with `sed -i 's/\r$//' scripts/k8s-node-discovery.sh`. |
| `failed writing file: open /generated/...: permission denied` | Fix `generated/` write permissions for `consul-template`. |
| `can't kill pid 1: Operation not permitted` | Ensure `consul-template` uses `pid: "service:haproxy"` and runs as `user: "0:0"`. |
| Reload fails | Generated HAProxy syntax, template output, and container name. |
