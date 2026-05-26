# ArgoCD Setup Guide

Run these commands on the Kubernetes control server where `kubectl` already works.

## 1. Check Cluster Access

```bash
kubectl get nodes
```

## 2. Install ArgoCD

```bash
kubectl create namespace argocd
```

```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Check ArgoCD pods:

```bash
kubectl get pods -n argocd
```

## 3. Access ArgoCD UI

Run this command and keep the terminal open:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0
```

Open:

```text
https://<server-public-ip>:8080
```

## 4. Get Admin Password

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Login with:

```text
username: admin
password: <password-from-command>
```

## 5. Check Required CRDs

The project uses Kubernetes Gateway API and Traefik Middleware CRDs.

```bash
kubectl get crd gateways.gateway.networking.k8s.io
kubectl get crd middlewares.traefik.io
```

If either CRD is missing, install the required Gateway API and Traefik CRDs before syncing the app.

## 6. Create ArgoCD Application

Apply the Application manifest from this folder:

```bash
kubectl apply -f argocd/hospital-traefik-app.yaml
```

Or paste the content of `hospital-traefik-app.yaml` into the ArgoCD UI with `+ New App` using YAML mode.

## 7. Sync and Verify

Check the Application:

```bash
kubectl get application hospital-traefik-app -n argocd
```

Check application workloads:

```bash
kubectl get pods -n hospital
kubectl get pods -n traefik
kubectl get svc -n traefik
kubectl get gateway,httproute -n hospital
```

Open the hospital app:

```text
http://<server-public-ip>:30080
```

## 8. Notes

- Git is the source of truth. Long-term changes should be committed and pushed to GitHub.
- If a pod is deleted manually, Kubernetes recreates it through its Deployment.
- If a Deployment, Service, Gateway, or Route is deleted manually, ArgoCD recreates it when `selfHeal` is enabled.
- If a manifest is removed from Git, ArgoCD deletes the live resource when `prune` is enabled.

