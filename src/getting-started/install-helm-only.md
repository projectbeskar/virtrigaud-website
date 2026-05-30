<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Helm-only Installation

This guide covers installing VirtRigaud v0.3.7 using only Helm (CRDs included in the chart) and verifying the installation is healthy.

## Prerequisites

- Kubernetes cluster (1.26+)
- Helm 3.8+
- `kubectl` configured to access your cluster

## Installation

### Add the Helm repository

```bash
helm repo add virtrigaud https://projectbeskar.github.io/virtrigaud
helm repo update virtrigaud
```

### Install VirtRigaud v0.3.7

```bash
helm install virtrigaud virtrigaud/virtrigaud \
  --version 0.3.7 \
  --namespace virtrigaud-system \
  --create-namespace \
  --wait \
  --timeout 10m
```

!!! note "Multi-arch images (v0.3.7)"
    All component images are now multi-arch (`linux/amd64` + `linux/arm64`).
    arm64 clusters are fully supported — no changes to Helm values or Provider
    CRs are needed.

!!! note "mTLS required in v0.3.7"
    Every Provider CR must have a `spec.runtime.service.tls` block. For
    chart-templated providers, the `providerTLS` Helm values block supplies
    TLS configuration without editing each Provider CR directly:

    ```yaml
    # values.yaml excerpt
    providerTLS:
      secretName: "my-provider-tls-secret"   # Secret with tls.crt, tls.key, ca.crt
      allowedSANs:
        - "manager.virtrigaud-system.svc"
      insecure: false                         # set true only when secretName is empty (lab only)
    ```

    Operators managing Provider CRs directly must add the `tls` block
    themselves. See the [upgrade guide](../operations/upgrade.md#v036--v037)
    for the full remediation steps.

`--wait` blocks until all pods are ready. `--timeout 10m` matches the default provider image pull time on slow registries.

### Skip CRDs (if already installed separately)

```bash
helm install virtrigaud virtrigaud/virtrigaud \
  --version 0.3.7 \
  --namespace virtrigaud-system \
  --create-namespace \
  --skip-crds \
  --wait
```

## Verify Installation

### Check pods and Helm release

```bash
# Manager pod is running
kubectl get pods -n virtrigaud-system

# Helm release is at v0.3.7
helm list -n virtrigaud-system
# NAME         NAMESPACE          REVISION  CHART                APP VERSION
# virtrigaud   virtrigaud-system  1         virtrigaud-0.3.6     v0.3.7
```

Expected output from `helm list`:

- `CHART` column: `virtrigaud-0.3.6`
- `APP VERSION` column: `v0.3.7`

### Verify the manager image tag

```bash
kubectl get deployment virtrigaud-manager -n virtrigaud-system \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# ghcr.io/projectbeskar/virtrigaud/manager:v0.3.7
```

### Confirm v0.3.7 metrics are available

```bash
kubectl port-forward -n virtrigaud-system svc/virtrigaud-manager 8080:8080 &
curl -s http://localhost:8080/metrics | grep '^virtrigaud_build_info'
```

Expected:

```
virtrigaud_build_info{component="manager",git_sha="<sha>",go_version="go1.26.x",version="v0.3.7"} 1
```

New metric families available in v0.3.7 (seeded to 0 at boot before any Provider CRs are created):

```bash
curl -s http://localhost:8080/metrics | grep 'virtrigaud_circuit_breaker\|virtrigaud_provider_tasks_inflight'
```

Once at least one Provider CR exists you will see:

```
virtrigaud_circuit_breaker_state{provider="<name>",provider_type="<type>"} 0
virtrigaud_provider_tasks_inflight{provider="<name>",provider_type="<type>"} 0
```

For the full v0.3.7 metrics surface see the [Observability Guide](../operations/observability.md).

### Check all 10 CRDs are installed

```bash
kubectl get crds | grep virtrigaud.io
```

Expected CRDs (10 total):

```
virtualmachines.infra.virtrigaud.io
providers.infra.virtrigaud.io
vmclasses.infra.virtrigaud.io
vmimages.infra.virtrigaud.io
vmnetworkattachments.infra.virtrigaud.io
vmmigrations.infra.virtrigaud.io
vmsnapshots.infra.virtrigaud.io
vmsets.infra.virtrigaud.io
vmplacementpolicies.infra.virtrigaud.io
vmclones.infra.virtrigaud.io
```

## Verify API Version

Confirm v1beta1 is the storage version:

```bash
kubectl get crd virtualmachines.infra.virtrigaud.io \
  -o jsonpath='{.spec.versions[?(@.storage==true)].name}'
# v1beta1
```

## Troubleshooting

### Manager pod not starting

```bash
kubectl describe pod -n virtrigaud-system -l app.kubernetes.io/name=virtrigaud
kubectl logs -n virtrigaud-system deployment/virtrigaud-manager
```

Common causes: image pull failure, missing RBAC, CRD version mismatch.

### `virtrigaud_build_info` returns nothing

The manager process has not started or the metrics port is not reachable. Check:

```bash
kubectl get svc -n virtrigaud-system | grep manager
```

### Circuit breaker open on startup

If a Provider CR already existed before this install, you may see:

```
virtrigaud_circuit_breaker_state{provider="my-provider",provider_type="libvirt"} 2
```

A circuit breaker that opens on startup is the expected signal for a provider that is unreachable — it is not a bug in the installation. Verify the provider pod is running and its endpoint is reachable. See [Resilience](../operations/resilience.md) for the state-machine details and recovery path. The breaker will transition to Half-Open after 60 seconds and close once 3 consecutive RPCs succeed.

## Integration with GitOps

### ArgoCD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: virtrigaud
  namespace: argocd
spec:
  source:
    chart: virtrigaud
    repoURL: https://projectbeskar.github.io/virtrigaud
    targetRevision: "0.3.6"
    helm:
      values: |
        manager:
          image:
            tag: v0.3.7
```

### Flux HelmRelease

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: virtrigaud
  namespace: virtrigaud-system
spec:
  chart:
    spec:
      chart: virtrigaud
      version: "0.3.6"
      sourceRef:
        kind: HelmRepository
        name: virtrigaud
  values:
    manager:
      image:
        tag: v0.3.7
```

## Migration from Kustomize to Helm

1. Back up existing resources:

   ```bash
   kubectl get vms,providers,vmclasses,vmimages -A -o yaml > virtrigaud-backup.yaml
   ```

2. Remove Kustomize-managed resources (if safe to do so):

   ```bash
   kubectl delete -k config/default
   ```

3. Install via Helm:

   ```bash
   helm install virtrigaud virtrigaud/virtrigaud \
     --version 0.3.6 \
     --namespace virtrigaud-system \
     --create-namespace
   ```

4. Restore resources:

   ```bash
   kubectl apply -f virtrigaud-backup.yaml
   ```
