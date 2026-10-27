<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Helm-only Installation

This guide covers installing VirtRigaud v0.4.1 using only Helm (CRDs included in the chart) and verifying the installation is healthy. To upgrade an existing installation, read the [Upgrade Guide](../operations/upgrade.md) and [Automatic CRD Upgrades](helm-crd-upgrades.md) first.

## Prerequisites

- Kubernetes cluster (1.25+). The reserved-keys admission policy needs 1.30+ and is skipped on older clusters (see [Admission policy](#admission-policy-kubernetes-130)).
- Helm 3.8+ (3.14+ to use `--reset-then-reuse-values` on upgrades)
- `kubectl` configured to access your cluster
- Rights to install cluster-scoped objects: the chart creates CRDs, cluster-scoped RBAC and, on Kubernetes 1.30+, a `ValidatingAdmissionPolicy` and its binding. The installing identity needs `create` on `validatingadmissionpolicies` and `validatingadmissionpolicybindings` for that.

## Installation

### Add the Helm repository

```bash
helm repo add virtrigaud https://projectbeskar.github.io/virtrigaud
helm repo update virtrigaud
```

### Install VirtRigaud v0.4.1

```bash
helm install virtrigaud virtrigaud/virtrigaud \
  --version 0.4.1 \
  --namespace virtrigaud-system \
  --create-namespace \
  --wait \
  --timeout 10m
```

`--wait` blocks until all pods are ready. The manager's readiness probe also checks that the installed `VirtualMachine`, `Provider`, `VMClass`, `VMImage` and `VMSnapshot` CRDs carry the schema fields the manager depends on (for example `status.boundProvider` and `spec.consumerNamespaceSelector`), so a stale CRD keeps the manager unready instead of letting it run against an old schema.

The chart installs a pre-install hook Job that applies the CRDs with server-side apply (see [Automatic CRD Upgrades](helm-crd-upgrades.md)), the manager Deployment and its RBAC, and the reserved-keys admission policy. It does **not** deploy any provider pod.

!!! note "Providers are created from Provider CRs"
    Provider pods are deployed by the manager from `Provider` custom resources
    (see the [Quickstart](index.md#step-3-configure-a-provider)). The chart can
    also render standalone provider Deployments (`providers.<type>.enabled=true`),
    but they are **disabled by default** and are not the normal path. If you opt in,
    you must also set the [`providerTLS` values](#provider-tls-values), or the
    provider refuses to start (secure by default).

### Provider TLS values

Every `Provider` CR must have a `spec.runtime.service.tls` block. For chart-templated
providers, the `providerTLS` Helm values supply the TLS configuration:

```yaml
# values.yaml excerpt
providerTLS:
  secretName: "my-provider-tls-secret"   # Secret with tls.crt, tls.key, ca.crt
  allowedSANs:
    - "manager.virtrigaud-system.svc"
  insecure: false                         # true only when secretName is empty (lab only)
```

Operators managing `Provider` CRs directly add the `tls` block themselves; see
[mTLS Configuration](../providers/security/mtls.md) and the
[upgrade guide](../operations/upgrade.md#v036-v037) for the remediation steps.

### Admission policy (Kubernetes 1.30+)

On Kubernetes 1.30 and later the chart installs a `ValidatingAdmissionPolicy` and binding
(`admissionPolicy.reservedKeys.enabled`, default `true`). Only the manager's ServiceAccount
may then add or change the `virtrigaud.io/*` annotations and the `virtrigaud.io/adopted`
label that the manager alone writes on a `VirtualMachine` (migration, clone and adoption
provenance, the migration claim, `migration-completed`). The policy runs in the API server,
not as a webhook, so it works with `webhooks.enabled=false`. Annotations that users set
themselves (`virtrigaud.io/orphan-on-delete`, `virtrigaud.io/force-delete`) are not affected.

```yaml
# values.yaml excerpt
admissionPolicy:
  reservedKeys:
    enabled: true
    exemptUsernames:
      - system:serviceaccount:velero:velero   # a restore tool that re-creates VMs with their annotations
    exemptGroups: []
```

- Backup and restore tools (for example Velero) and a second VirtRigaud installation in the same cluster are rejected unless listed in `exemptUsernames` or `exemptGroups`.
- On a cluster older than 1.30 nothing is rendered. Restrict `create` and `update` on `virtualmachines` to trusted users there, or reserve the keys with Kyverno or Gatekeeper.
- It is a security control for migration, adoption and clone. Do not disable it without a replacement.
- `helm template` assumes Helm's built-in Kubernetes version; pass `--kube-version` when you render for a cluster older than 1.30.

### Admission webhooks

Admission webhooks are **off** by default (`webhooks.enabled=false`). With `webhooks.enabled=true`
the chart renders a `ValidatingWebhookConfiguration` that validates `Provider` writes (for
example, `spec.topology` against `spec.type`, and `spec.type` immutability), served by the
manager. If you also set `manager.maxDiskSize`, it adds webhooks that refuse over-limit disk sizes
on `VirtualMachine` and `VMClass` writes. The webhook serving certificate comes from
`webhooks.certificates.source`:

| `source` | Behaviour |
|---|---|
| `self-signed` (default) | The chart generates a CA and serving certificate and reuses them on upgrade. Works with `helm install/upgrade`, not with `helm template` render-then-apply (Argo CD), which regenerates them on every sync. |
| `cert-manager` | The chart renders a cert-manager `Certificate`; you provide the `Issuer` or `ClusterIssuer` (`webhooks.certificates.certManager`). Recommended for production and GitOps. |
| `manual` | You provision the Secret named by `webhooks.certificates.secretName` and set `webhooks.certificates.caBundle`. |

With `failurePolicy: Fail` (the default) the manager is on the admission path for `Provider`
writes. Run it with `manager.replicaCount: 2` when you enable webhooks.

### Skip CRDs (if already installed separately)

```bash
helm install virtrigaud virtrigaud/virtrigaud \
  --version 0.4.1 \
  --namespace virtrigaud-system \
  --create-namespace \
  --skip-crds \
  --set crdUpgrade.enabled=false \
  --wait
```

Apply the CRDs first (`kubectl apply --server-side --force-conflicts -f config/crd/bases` from a
checkout of the release tag), or the manager stays unready.

### Optional values worth knowing

| Value | Default | Effect |
|---|---|---|
| `networkPolicy.enabled` | `false` | Renders opt-in `NetworkPolicy` objects for the manager and provider pods. Needs a CNI that enforces them; see the chart README before enabling. |
| `manager.maxDiskSize` | empty | Administrator ceiling on every disk VirtRigaud creates or grows (for example `500Gi`). Empty means no ceiling beyond the CRD's 64Ti per disk. |
| `manager.providerTmpSizeLimit` | per type | `sizeLimit` of every provider pod's `/tmp` emptyDir. Defaults: vSphere `512Gi`, libvirt and Proxmox `1Gi`. A pod that writes more is evicted. |
| `manager.providerTmpSizeLimitMax` | empty | Ceiling on what a `Provider` annotation (`infra.virtrigaud.io/tmp-size-limit`) may ask for. |
| `crdUpgrade.enabled` | `true` | Applies the CRDs in a pre-install and pre-upgrade hook Job. |

The complete list is in the chart's [`values.yaml`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/charts/virtrigaud/values.yaml)
and [README](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/charts/virtrigaud/README.md).

## Verify Installation

### Check pods and Helm release

```bash
# Manager pod is running
kubectl get pods -n virtrigaud-system

# Helm release is at v0.4.1
helm list -n virtrigaud-system
# NAME         NAMESPACE          REVISION  CHART                APP VERSION
# virtrigaud   virtrigaud-system  1         virtrigaud-0.4.1     v0.4.1
```

Expected output from `helm list`:

- `CHART` column: `virtrigaud-0.4.1`
- `APP VERSION` column: `v0.4.1`

### Verify the manager image tag

```bash
kubectl get deployment virtrigaud-manager -n virtrigaud-system \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# ghcr.io/projectbeskar/virtrigaud/manager:v0.4.1
```

### Confirm metrics are available

```bash
kubectl port-forward -n virtrigaud-system svc/virtrigaud-manager 8080:8080 &
curl -s http://localhost:8080/metrics | grep '^virtrigaud_build_info'
```

Expected:

```
virtrigaud_build_info{component="manager",git_sha="<sha>",go_version="go1.26.x",version="v0.4.1"} 1
```

Metric families (seeded to 0 at boot before any Provider CRs are created):

```bash
curl -s http://localhost:8080/metrics | grep 'virtrigaud_circuit_breaker\|virtrigaud_provider_tasks_inflight'
```

Once at least one Provider CR exists you will see:

```
virtrigaud_circuit_breaker_state{provider="<name>",provider_type="<type>"} 0
virtrigaud_provider_tasks_inflight{provider="<name>",provider_type="<type>"} 0
```

For the full metrics surface see the [Metrics Catalog](../api-reference/metrics.md) and the [Observability Guide](../operations/observability.md).

### Check all 12 CRDs are installed

```bash
kubectl get crds | grep virtrigaud.io
```

Expected CRDs (12 total):

```
hostpools.infra.virtrigaud.io
hosts.infra.virtrigaud.io
providers.infra.virtrigaud.io
virtualmachines.infra.virtrigaud.io
vmclasses.infra.virtrigaud.io
vmclones.infra.virtrigaud.io
vmimages.infra.virtrigaud.io
vmmigrations.infra.virtrigaud.io
vmnetworkattachments.infra.virtrigaud.io
vmplacementpolicies.infra.virtrigaud.io
vmsets.infra.virtrigaud.io
vmsnapshots.infra.virtrigaud.io
```

`hosts` and `hostpools` describe the hypervisor hosts behind a clustered libvirt Provider and are unused otherwise. See [clustered libvirt providers](../guides/clustered/index.md).

### Check the admission policy (Kubernetes 1.30+)

```bash
kubectl get validatingadmissionpolicy,validatingadmissionpolicybinding | grep reserved-keys
```

## Verify API Version

Confirm v1beta1 is the storage version:

```bash
kubectl get crd virtualmachines.infra.virtrigaud.io \
  -o jsonpath='{.spec.versions[?(@.storage==true)].name}'
# v1beta1
```

## Troubleshooting

### Manager pod not starting or not ready

```bash
kubectl describe pod -n virtrigaud-system -l app.kubernetes.io/name=virtrigaud
kubectl logs -n virtrigaud-system deployment/virtrigaud-manager
```

Common causes: image pull failure, missing RBAC, or a CRD that lacks a field the manager requires (the pod runs but stays unready). Check the CRDs:

```bash
kubectl get crd providers.infra.virtrigaud.io \
  -o jsonpath='{.spec.versions[?(@.name=="v1beta1")].schema.openAPIV3Schema.properties.spec.properties.consumerNamespaceSelector.type}'
# object
```

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
    targetRevision: "0.4.1"
    helm:
      values: |
        manager:
          image:
            tag: v0.4.1
```

With Argo CD (`helm template` render-then-apply), use `webhooks.certificates.source: cert-manager` if you enable webhooks; the default self-signed certificate is regenerated on every sync.

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
      version: "0.4.1"
      sourceRef:
        kind: HelmRepository
        name: virtrigaud
  values:
    manager:
      image:
        tag: v0.4.1
```

## Uninstalling

Delete your `VirtualMachine`s and `Provider`s **before** uninstalling the chart. A `Provider`
carries an in-use finalizer (`provider.infra.virtrigaud.io/in-use`) that only the manager
releases; it keeps the `Provider` (and its runtime pod) while any `VirtualMachine`, `VMSnapshot`,
in-flight `VMClone` or `VMMigration` still needs it, so their hypervisor VMs are deleted through
it instead of being orphaned. One left behind after the manager is gone stays `Terminating`
until you remove its finalizer by hand.

!!! danger "Deleting a VirtualMachine deletes the VM on the hypervisor"
    To release a VM without deleting it, annotate it `virtrigaud.io/orphan-on-delete: "true"`
    before you delete the `VirtualMachine`.

```bash
# Deletes the VMs on your hypervisors (see the warning above)
kubectl delete virtualmachines -A --all
kubectl delete providers -A --all
helm uninstall virtrigaud -n virtrigaud-system

# WARNING: deletes every VirtRigaud custom resource
kubectl get crd -o name | grep '\.infra\.virtrigaud\.io$' | xargs kubectl delete
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

   !!! warning
       `kubectl delete -k` also deletes the CRDs and with them every VirtRigaud custom resource, and a `Provider` that still has VMs waits for them (ADR-0010). Do not run it on a cluster with VMs you want to keep.

3. Install via Helm:

   ```bash
   helm install virtrigaud virtrigaud/virtrigaud \
     --version 0.4.1 \
     --namespace virtrigaud-system \
     --create-namespace
   ```

4. Restore resources (the admission policy rejects annotations it reserves for the manager unless the restoring identity is exempt; see [Admission policy](#admission-policy-kubernetes-130)):

   ```bash
   kubectl apply -f virtrigaud-backup.yaml
   ```
