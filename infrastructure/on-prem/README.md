# On-Prem HAProxy Ingress

This folder provides the on-premise ingress path for the hospital platform, replacing AWS-managed ALB infrastructure with a self-managed HAProxy edge server.

```text
Internet / Client
  -> Cloudflare Tunnel / DNS
  -> HAProxy Edge Server, ports 80/443
  -> Consul-backed dynamic HAProxy backend discovery
  -> Kubernetes worker NodePort 30080
  -> Traefik DaemonSet
  -> Gateway API HTTPRoute
  -> hospital frontend/backend services
```

## Folder Layout

| Path | Purpose |
|---|---|
| `traefik/` | Kubernetes manifests that install Traefik as a NodePort Gateway API controller. |
| `haproxy/` | Docker Compose HAProxy edge load balancer with Consul, Consul Template, and Kubernetes node auto-discovery. |

## Ingress Architecture

All public traffic enters through Cloudflare Tunnel or DNS and lands on the HAProxy load balancer on the Edge Server. In the Cloudflare Tunnel setup, the public hostname `benhvien.teamdevops.shop` points to `http://127.0.0.1:80` on the HAProxy server. HAProxy then forwards traffic to healthy Traefik NodePort backends discovered from Kubernetes nodes.

The Edge Server uses a Kubernetes discovery container to poll Ready nodes in the cluster, registers each node as a Consul service, and relies on Consul TCP health checks to keep only reachable Traefik NodePort backends in the generated HAProxy config. In a small control-plane plus worker cluster, the control-plane node may be discovered but filtered out by health checks if Traefik is only scheduled on the worker.

> [!IMPORTANT]
> The legacy AWS EKS and Terraform cloud infrastructure paths have been deprecated. This on-premises dynamic ingress architecture is the standard method for routing incoming traffic to the services.

## Deploy

1. Install Gateway API CRDs and Traefik CRDs:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.1/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml
```

2. Install Traefik as a NodePort ingress controller:

```bash
kubectl apply -k onprem/traefik
kubectl -n traefik get pods,svc
```

3. Deploy the hospital application:

```bash
kubectl apply -k k8s/overlays/prod
```

4. Apply the example Gateway and HTTPRoute:

```bash
kubectl apply -f onprem/traefik/10-app-gateway-routes.example.yaml
```

5. Run HAProxy on the Edge Server:

```bash
cd onprem/haproxy
cp .env.example .env
# Set KUBECONFIG_PATH to the read-only discovery kubeconfig on the Edge Server.
docker compose up -d
```

For the current on-prem edge host, `.env` should contain:

```env
KUBECONFIG_PATH=/etc/haproxy/edge-node-discovery.kubeconfig
TRAEFIK_NODEPORT=30080
NODE_ADDRESS_TYPE=InternalIP
```

## Requirements

| Requirement | Notes |
|---|---|
| DNS | Either point DNS to the HAProxy host public IP, or publish the hostname through Cloudflare Tunnel. |
| Cloudflare Tunnel | Public hostname `benhvien.teamdevops.shop` should target `http://127.0.0.1:80` when `cloudflared` runs on the HAProxy host. |
| HAProxy inbound | Open TCP `80` and `443` to user traffic. |
| Worker inbound | Open TCP `30080` from the HAProxy host to Kubernetes workers. |
| Kubernetes API | The Edge Server kubeconfig must reach the Kubernetes API and read nodes. |
| Worker IPs | Discovered automatically from Ready Kubernetes nodes and registered in Consul. |
| TLS | Place HAProxy PEM certificates in `onprem/haproxy/certs/`. |

## Verification

```bash
kubectl -n traefik get ds,svc,pods -o wide
kubectl get gateway,httproute -A
curl -I https://benhvien.teamdevops.shop/
curl -i https://benhvien.teamdevops.shop/api/User/test
curl -i https://benhvien.teamdevops.shop/api/Doctor
cd onprem/haproxy
docker compose logs --tail=50 k8s-discovery
docker exec haproxy-alb haproxy -c -f /usr/local/etc/haproxy/generated/haproxy.cfg
```

With Cloudflare Tunnel, Cloudflare terminates public HTTPS and forwards HTTP to HAProxy locally. HAProxy and Traefik remain HTTP-only behind Cloudflare unless `HAPROXY_TLS_CERT` is explicitly configured.
