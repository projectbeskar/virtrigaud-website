<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Automatic CRD Upgrades in VirtRigaud Helm Chart

## Overview

The VirtRigaud Helm chart applies its CRDs on `helm install` **and** `helm upgrade` with a hook Job, so you do not manage CRDs by hand. Helm itself never upgrades CRDs from a chart's `crds/` directory; this hook closes that gap.

!!! warning "Upgrading from v0.4.1 to v0.4.2"
    v0.4.2 adds one optional `VirtualMachine` status field, `status.placement.resizeReservation`, so **the CRDs must be applied before the new manager starts**: the new manager fails readiness against the v0.4.1 CRD. The chart's pre-upgrade hook does this. Upgrade with `--reset-then-reuse-values` and override any image tag you pinned, or the manager and the hook can stay on older images. See [What changes on upgrade from v0.4.1 to v0.4.2](#what-changes-on-upgrade-from-v041-to-v042) and the [Upgrade Guide](../operations/upgrade.md#upgrading-from-v041-to-v042).

!!! info "Upgrading from v0.4.0 to v0.4.1"
    v0.4.1 has **no CRD schema change** (only the `description` texts of the CRDs differ, so `kubectl explain` shows corrected text) and no RBAC or `values.yaml` change beyond comments. The roll order is the same (CRDs, manager, providers), and `helm upgrade --version 0.4.1` re-tags the images. See [What changes on upgrade from v0.4.0 to v0.4.1](#what-changes-on-upgrade-from-v040-to-v041), and the [Upgrade Guide](../operations/upgrade.md#upgrading-from-v040-to-v041) for the actions it needs before you roll the Proxmox and libvirt providers.

!!! warning "Upgrading from v0.3.11"
    v0.4.0 has a required order (CRDs, then cross-namespace grants, then the manager, then the providers) and several breaking changes. Read the [Upgrade Guide](../operations/upgrade.md) and the [release notes](https://github.com/projectbeskar/virtrigaud/blob/v0.4.2/docs/upgrading.md) before running `helm upgrade`.

## What changes on upgrade from v0.4.1 to v0.4.2

- **CRDs:** one additive, optional status field on `VirtualMachine`, `status.placement.resizeReservation` (a `{cpu, memoryMiB}` footprint used for clustered resizes). No other schema change, and existing objects need no migration. The chart still ships all 12 CRDs.
- **Chart:** the manager Deployment passes `--client-qps` and `--client-burst` from the new values `manager.clientQPS` (default 20) and `manager.clientBurst` (default 40), the same limits as before; a zero, negative or non-numeric value fails the render. Nothing else in the templates changed.
- **kubectl image of the CRD hook:** `ghcr.io/projectbeskar/virtrigaud/kubectl:v0.4.2`, the upstream `kubectl` 1.35.10 binary on Alpine 3.24 (was 1.35.9). Its remaining scanner findings are listed in [Security](../operations/security.md#release-v042-dependency-and-image-findings).
- **Order:** the hook applies the CRDs before the manager rolls. If you apply CRDs yourself, apply the v0.4.2 CRDs first. A rollback does not run the hook, so the newer CRD stays installed; a v0.4.1 manager works with it (see [Rolling back to v0.4.1](../operations/upgrade.md#rolling-back-to-v041)).

```bash
helm get values virtrigaud -n virtrigaud-system   # look for pinned image tags first
helm upgrade virtrigaud virtrigaud/virtrigaud --version 0.4.2 \
  -n virtrigaud-system --reset-then-reuse-values
```

## What changes on upgrade from v0.4.0 to v0.4.1

- **CRDs:** no schema change. The 12 CRDs differ from v0.4.0's only in `description` texts (fields that nothing acts on now say "Accepted but not acted on in this release.", status fields no controller writes say "Not populated in this release."). One new condition reason, `RevertNotPerformed`, is a Go constant with no schema effect. Applying the CRDs is safe at any point.
- **Chart:** with `webhooks.enabled=true` the chart renders one more validating webhook entry, `vvmclone-customization.kb.io` (failure policy always `Ignore`, timeout 5s), which only returns an admission warning when a `VMClone` sets a customization field that may hold a secret. `config/webhook` for Kustomize gains it too. Nothing else in the templates changed.
- **kubectl image of the CRD hook:** updated to kubectl 1.35.9 on Alpine 3.24 (was 1.32.0 on 3.20), which cuts the HIGH and CRITICAL image-scan findings that have a fix from 37 to 6.
- **`virtrigaud-provider-runtime` chart:** deprecated and removed in the next minor release. It was never published to the Helm repository; see the [Upgrade Guide](../operations/upgrade.md#deprecated-the-virtrigaud-provider-runtime-chart).

## What changes on upgrade from v0.3.11 to v0.4.0

The CRD-upgrade hook applies these changes when you upgrade from v0.3.11 with `helm upgrade ... --version 0.4.2` (they are the changes of v0.4.0; v0.4.1 adds no schema change, and v0.4.2 adds `status.placement.resizeReservation`):

- **New CRDs:** `hosts.infra.virtrigaud.io` and `hostpools.infra.virtrigaud.io` (clustered libvirt providers). The chart now installs 12 CRDs.
- **`spec.consumerNamespaceSelector`** on `Provider`, `VMClass` and `VMImage`. A reference to one of these in another namespace is refused (`ConsumerNotAllowed`) unless this field selects the referencing namespace.
- **`VirtualMachine`:** `status.boundProvider`, `status.placement` (clustered placement), `status.snapshotRevert` (snapshot revert), the `Suspended` and `Unknown` values of `status.powerState`, and an admission rule that makes `spec.providerRef` immutable once the VM is bound.
- **`Provider`:** `spec.topology` (`single` or `cluster`), `status.reportedCapabilities.supportsHonestReconfigure` and `supportsImageArtifactIdentity`, and immutable `spec.type` and `spec.topology` (CEL rules).
- **`VMImage`:** `status.providerStatus["<namespace>/<name>"]` gains `providerUID`, `sourceDigest` and `taskRef` (prepare state is now per Provider).
- **`VMMigration`:** `status.targetVMUID`, `status.targetVMClaim`, `status.sourceVMUID`, `status.storagePVCUID`, and `status.storageInfo.importTarget`, `stagingDigest` and `stagingLayout`; `spec.importedDisk` accepts an empty `diskID` while `migrationRef` is set (migration into a clustered Provider).
- **`VMClone`:** `status.targetUID`. **`VMSnapshot`:** `status.boundProvider` and `status.vmUID`.
- New RBAC rules for the manager: `get` on the `virtualmachines`, `providers`, `vmclasses`, `vmimages` and `vmsnapshots` CRDs, `get;list;watch` on `namespaces`, and `get;patch;update` on `hostpools/status`. The chart applies them with the manager; a Kustomize install must reapply `config/rbac/role.yaml`.

No field is removed. The admission rules (`spec.providerRef` and `spec.type` immutability) can reject updates that earlier releases accepted; see the Upgrade Guide. Existing `VirtualMachine`, `Provider`, `VMSnapshot` and `VMMigration` resources are kept.

!!! danger "Order matters: set `consumerNamespaceSelector` before the new manager runs"
    The new manager fails closed on cross-namespace references. If any `VirtualMachine`,
    `VMClone` or `VMMigration` uses a `Provider`, `VMClass` or `VMImage` from another
    namespace, apply the new CRDs first, set `spec.consumerNamespaceSelector` on those objects,
    and only then roll the manager. The field does not exist until the CRDs are upgraded, and the
    helm hook applies the CRDs in the same `helm upgrade` that rolls the manager. Apply the CRDs yourself first:

    ```bash
    kubectl apply --server-side --force-conflicts -f config/crd/bases   # from the v0.4.2 release checkout
    # set spec.consumerNamespaceSelector on the shared objects, then:
    helm upgrade virtrigaud virtrigaud/virtrigaud --version 0.4.2 -n virtrigaud-system --reset-then-reuse-values
    ```

    The manager's readiness probe fails while the `VirtualMachine`, `Provider`, `VMClass` or `VMImage`
    CRD lacks a field it needs, so `helm upgrade --wait` times out instead of running against an old schema.

!!! tip "Carry custom values with `--reset-then-reuse-values`"
    `--reuse-values` reuses the **old** chart's defaults, so settings added in a newer chart are
    missing and old defaults linger. Use `--reset-then-reuse-values` (Helm 3.14+), which applies the
    new chart's defaults and then your own values.

## The Problem

By default, Helm has a limitation:
- CRDs are installed during `helm install`
- CRDs are **NOT upgraded** during `helm upgrade`

This means users had to manually apply CRD updates before upgrading, which was:
- Error-prone
- Easy to forget
- Breaks GitOps workflows
- Causes version drift between chart and CRDs

## The Solution

VirtRigaud uses **Helm Hooks** with a Kubernetes Job to automatically apply CRDs during both install and upgrade:

### kubectl Image

VirtRigaud builds and publishes its own `kubectl` image as part of the release process. This image:

- Based on Alpine Linux for minimal size (~50MB)
- Includes the kubectl binary from official Kubernetes releases (1.35.10 on Alpine 3.24 in v0.4.2; 1.35.9 in v0.4.1; 1.32.0 on Alpine 3.20 before)
- Includes bash and shell for scripting support
- Runs as non-root user (UID 65532)
- Verified with SHA256 checksums
- Signed with Cosign and includes SBOM
- Security scanned but uses official kubectl binary (vulnerabilities tracked upstream)

The image is automatically built and tagged to match each VirtRigaud release version, ensuring version consistency across all components.

**Image Location**: `ghcr.io/projectbeskar/virtrigaud/kubectl:<version>`

### How It Works

1. **Pre-Upgrade Hook**: Before the main upgrade starts, a Job is created
2. **CRD Application**: The Job applies all CRDs using `kubectl apply --server-side`
3. **Safe Upgrades**: Server-side apply handles conflicts gracefully
4. **Automatic Cleanup**: Job is deleted after successful completion

### Architecture

```
helm upgrade virtrigaud
    ↓
[Pre-Upgrade Hook -10]
    ↓
ConfigMap with CRDs created
    ↓
[Pre-Upgrade Hook -5]
    ↓
ServiceAccount + RBAC created
    ↓
[Pre-Upgrade Hook 0]
    ↓
Job applies CRDs via kubectl
    ↓
[Standard Helm Resources]
    ↓
Manager & Providers deployed
    ↓
[Hook Cleanup]
    ↓
Job & Hook resources deleted
```

## Features

### Enabled by Default

No configuration needed - just works:

```bash
helm upgrade virtrigaud virtrigaud/virtrigaud -n virtrigaud-system
```

### Server-Side Apply

Uses `kubectl apply --server-side` for:
- Safe conflict resolution
- Field management
- No ownership conflicts

### GitOps Compatible

Works seamlessly with:
- **ArgoCD**: Helm hooks execute properly
- **Flux**: Compatible with HelmRelease CRD upgrades
- **Terraform**: Helm provider handles hooks

### Configurable

Customize the upgrade behavior:

```yaml
crdUpgrade:
  enabled: true  # Enable/disable automatic upgrades
  
  image:
    repository: ghcr.io/projectbeskar/virtrigaud/kubectl  # VirtRigaud kubectl image
    tag: "v0.4.2"  # Set by the release to match the VirtRigaud version
  
  backoffLimit: 3
  ttlSecondsAfterFinished: 300
  waitSeconds: 5
  
  resources:
    limits:
      cpu: 100m
      memory: 128Mi
```

## Usage Examples

### Standard Upgrade (Automatic CRDs)

```bash
# CRDs are automatically upgraded
helm upgrade virtrigaud virtrigaud/virtrigaud \
  -n virtrigaud-system
```

### Disable Automatic CRD Upgrade

```bash
# Disable if you manage CRDs separately
helm upgrade virtrigaud virtrigaud/virtrigaud \
  -n virtrigaud-system \
  --set crdUpgrade.enabled=false
```

### Manual CRD Management

```bash
# Apply CRDs manually before upgrade
kubectl apply -f charts/virtrigaud/crds/

# Then upgrade without CRD management
helm upgrade virtrigaud virtrigaud/virtrigaud \
  -n virtrigaud-system \
  --set crdUpgrade.enabled=false
```

### Skip CRDs Entirely

```bash
# Skip CRDs during upgrade (for external CRD management)
helm upgrade virtrigaud virtrigaud/virtrigaud \
  -n virtrigaud-system \
  --skip-crds \
  --set crdUpgrade.enabled=false
```

## GitOps Integration

### ArgoCD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: virtrigaud
spec:
  source:
    chart: virtrigaud
    targetRevision: 0.4.2
    helm:
      values: |
        crdUpgrade:
          enabled: true  # Automatic upgrades work!
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**Note**: ArgoCD executes Helm hooks properly, so CRDs will be upgraded automatically.

### Flux

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: virtrigaud
spec:
  chart:
    spec:
      chart: virtrigaud
      version: 0.4.2
  values:
    crdUpgrade:
      enabled: true  # Automatic upgrades work!
  install:
    crds: CreateReplace
  upgrade:
    crds: CreateReplace
```

**Note**: Flux's `crds: CreateReplace` works alongside our hook-based upgrades for maximum compatibility.

## Troubleshooting

### Check CRD Upgrade Job

```bash
# View job status
kubectl get jobs -n virtrigaud-system -l app.kubernetes.io/component=crd-upgrade

# View job logs
kubectl logs -n virtrigaud-system -l app.kubernetes.io/component=crd-upgrade

# View job details
kubectl describe job -n virtrigaud-system -l app.kubernetes.io/component=crd-upgrade
```

### Known Issue: Empty `crds/` Directory when Building from Source

!!! danger "H2: `BackoffLimitExceeded` on the CRD-upgrade-job when installing from a source checkout"
    The `charts/virtrigaud/crds/` directory in the git repository contains only a `.gitkeep` placeholder. The actual CRD YAML files are **not committed** to git — they are generated at build time by `make gen-helm-crds`.

    **Symptom**: The CRD-upgrade-job starts, applies an empty ConfigMap, and exits without error, but `kubectl get crd` shows no VirtRigaud CRDs. Or, if the job runs before the CRDs exist at all, it may reach `BackoffLimitExceeded`.

    **Workaround**: Install from the published Helm chart rather than rebuilding from source:

    ```bash
    helm repo add virtrigaud https://projectbeskar.github.io/virtrigaud
    helm repo update
    helm install virtrigaud virtrigaud/virtrigaud \
      --version 0.4.2 \
      --namespace virtrigaud-system \
      --create-namespace
    ```

    If you must install from a source checkout, run `make gen-helm-crds` first to populate `charts/virtrigaud/crds/`:

    ```bash
    # From the virtrigaud source root
    make gen-helm-crds
    # Verify the CRD files are populated
    ls charts/virtrigaud/crds/
    # Now install or upgrade
    helm install virtrigaud ./charts/virtrigaud -n virtrigaud-system
    ```

    **Status**: Tracked as project issue H2. The published chart at `https://projectbeskar.github.io/virtrigaud` always includes the CRD files and is not affected.

### Common Issues

#### 1. RBAC Permissions

**Symptom**: Job fails with "forbidden" errors

**Solution**: Ensure the ServiceAccount has CRD permissions:

```bash
kubectl get clusterrole -l app.kubernetes.io/component=crd-upgrade
kubectl describe clusterrole <role-name>
```

#### 2. Image Pull Failures

**Symptom**: Job fails to start, ImagePullBackOff

**Solution**: Check image configuration:

```yaml
crdUpgrade:
  image:
    repository: ghcr.io/projectbeskar/virtrigaud/kubectl
    tag: "v0.4.2"  # Use matching VirtRigaud version
    pullPolicy: IfNotPresent
```

#### 3. CRD Conflicts

**Symptom**: Apply errors about field conflicts

**Solution**: Server-side apply handles this automatically, but you can force:

```bash
kubectl apply --server-side=true --force-conflicts -f charts/virtrigaud/crds/
```

#### 4. Job Not Cleaning Up

**Symptom**: Old jobs remain after upgrade

**Solution**: Adjust TTL or manually clean:

```bash
kubectl delete jobs -n virtrigaud-system -l app.kubernetes.io/component=crd-upgrade
```

### Debug Mode

Enable verbose logging:

```bash
helm upgrade virtrigaud virtrigaud/virtrigaud \
  -n virtrigaud-system \
  --debug
```

## Migration Guide

### Migrating from Manual CRD Management

If you were previously managing CRDs manually:

1. **Enable automatic upgrades**:
   ```bash
   helm upgrade virtrigaud virtrigaud/virtrigaud \
     -n virtrigaud-system \
     --set crdUpgrade.enabled=true
   ```

2. **Verify CRDs are upgraded**:
   ```bash
   kubectl get crd -l app.kubernetes.io/name=virtrigaud
   ```

3. **Remove manual steps from your upgrade process**

### Migrating to External CRD Management

If you want to manage CRDs externally (e.g., separate Helm chart):

1. **Disable automatic upgrades**:
   ```yaml
   crdUpgrade:
     enabled: false
   ```

2. **Extract CRDs**:
   ```bash
   helm show crds virtrigaud/virtrigaud > my-crds.yaml
   ```

3. **Manage CRDs separately**:
   ```bash
   kubectl apply -f my-crds.yaml
   ```

## Technical Details

### Hook Weights

The upgrade process uses weighted hooks for proper ordering:

| Weight | Resource | Purpose |
|--------|----------|---------|
| `-10` | ConfigMap | Store CRD content |
| `-5` | RBAC | Create permissions |
| `0` | Job | Apply CRDs |

### Resource Requirements

The CRD upgrade job is lightweight:

```yaml
resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 50m
    memory: 64Mi
```

### Security

- Runs as non-root user (65532)
- Read-only root filesystem
- No privilege escalation
- Minimal RBAC (only CRD permissions)
- Automatic cleanup after completion

### Compatibility

- **Kubernetes**: 1.25+
- **Helm**: 3.8+
- **kubectl**: 1.24+ (in Job image)

## Best Practices

1. **Use Automatic Upgrades**: Enable by default for best UX
2. **Monitor Job Logs**: Check logs during first upgrade
3. **Test in Dev First**: Verify upgrades in non-production
4. **Backup CRDs**: Keep backups before major upgrades
5. **Review Changelogs**: Check for breaking CRD changes

## FAQ

### Q: Will this delete my existing resources?

**A**: No. CRD upgrades are additive and preserve existing Custom Resources.

### Q: What happens if the job fails?

**A**: Helm upgrade will fail, leaving your cluster in the previous state. Fix the issue and retry.

### Q: Can I use this with ArgoCD?

**A**: Yes! ArgoCD properly executes Helm hooks.

### Q: Does this work with Flux?

**A**: Yes! Flux HelmRelease handles hooks correctly.

### Q: How do I roll back?

**A**: Use `helm rollback`. CRDs are not rolled back, and rolling the manager back has side effects (for example a `Provider` deleted afterwards keeps its in-use finalizer). Read the rollback caveats in the [Upgrade Guide](../operations/upgrade.md) first.

### Q: Can I customize the kubectl image?

**A**: Yes, via `crdUpgrade.image.repository` and `crdUpgrade.image.tag`. The default is VirtRigaud's own `ghcr.io/projectbeskar/virtrigaud/kubectl` image, whose tag the release sets to the VirtRigaud version.

## References

- [Helm Hooks Documentation](https://helm.sh/docs/topics/charts_hooks/)
- [Kubernetes CRD Documentation](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)
- [Server-Side Apply](https://kubernetes.io/docs/reference/using-api/server-side-apply/)

