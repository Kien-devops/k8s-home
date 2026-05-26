# On-Prem HAProxy Ingress

This folder provides the on-premise ingress path for the hospital platform, replacing AWS-managed ALB infrastructure with a self-managed HAProxy edge server.

```text
Internet / Client
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

All traffic enters the network through the HAProxy load balancer on the Edge Server. The Edge Server uses a Kubernetes discovery container to poll active nodes in the cluster, dynamically registers them as backends, and passes traffic to the Traefik NodePort.

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
# Place a kubeconfig with node discovery permissions (get/list/watch nodes) at kubeconfig/config.
docker compose up -d
```

## Requirements

| Requirement | Notes |
|---|---|
| DNS | Point your domain to the HAProxy host public IP. |
| HAProxy inbound | Open TCP `80` and `443` to user traffic. |
| Worker inbound | Open TCP `30080` from the HAProxy host to Kubernetes workers. |
| Kubernetes API | The Edge Server kubeconfig must reach the Kubernetes API and read nodes. |
| Worker IPs | Discovered automatically from Ready Kubernetes nodes and registered in Consul. |
| TLS | Place HAProxy PEM certificates in `onprem/haproxy/certs/`. |

## Verification

```bash
kubectl -n traefik get ds,svc,pods -o wide
kubectl get gateway,httproute -A
curl -I http://<your-domain>
curl -IL https://<your-domain>
docker compose -f onprem/haproxy/docker-compose.yml logs k8s-discovery
docker exec haproxy-alb haproxy -c -f /usr/local/etc/haproxy/generated/haproxy.cfg
```

HAProxy handles SSL termination and redirects HTTP to HTTPS. Traefik remains HTTP-only behind HAProxy.
