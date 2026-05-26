# On-Premise Security Stack

![Kubernetes](https://img.shields.io/badge/Kubernetes-Runtime%20Config-326CE5?logo=kubernetes&logoColor=white)
![Kyverno](https://img.shields.io/badge/Kyverno-Policies-326CE5?logo=kubernetes&logoColor=white)
![Trivy](https://img.shields.io/badge/Trivy%20Operator-Reports-1904DA?logo=aqua&logoColor=white)
![Falco](https://img.shields.io/badge/Falco-Runtime%20Detection-00AEC7)
![Kustomize](https://img.shields.io/badge/Kustomize-Render-326CE5?logo=kubernetes&logoColor=white)

This folder contains the Kubernetes security baseline for the on-premise Kubernetes cluster.

These files are runtime configuration used after the security tools are installed by Argo CD from `argocd/security`.

```text
argocd/security = install/manage security tools
k8s/security    = configure security inside the cluster
```

## Components

| Component | Purpose |
|---|---|
| `security` namespace | Shared namespace for security tools. |
| Kyverno policies | Audit unsafe workload configuration before switching to enforce mode. |
| Kyverno | Admission policy engine. Installed by Argo CD from Helm in `argocd/security`. |
| Trivy Operator | Vulnerability and configuration reports inside the cluster. Installed by Argo CD from `argocd/security`. |
| Falco | Runtime threat detection. Installed by Argo CD from `argocd/security`. |

## Policy Model

```mermaid
flowchart LR
  manifests[Kubernetes manifests] --> api[Kubernetes API]
  api --> kyverno[Kyverno admission controller]
  policies[k8s/security policies] --> kyverno
  kyverno --> audit[Audit reports]
  kyverno -. optional Enforce mode .-> allowdeny[Allow or deny resources]
```

## Apply Namespace And Policies

Kyverno must be installed before applying the policies.

```bash
kubectl apply -k k8s/security
```

## Policy Mode

Policies start in `Audit` mode so they report issues without blocking current workloads.

After the app manifests are cleaned up, change:

```yaml
validationFailureAction: Audit
```

to:

```yaml
validationFailureAction: Enforce
```

## Useful Checks

```bash
kubectl get pods -n security
kubectl get clusterpolicy
kubectl get policyreport -A
kubectl get vulnerabilityreports -A
kubectl get configauditreports -A
kubectl logs -n security -l app.kubernetes.io/name=falco
```
