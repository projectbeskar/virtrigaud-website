<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VirtRigaud Upgrade Guide

This guide covers upgrading VirtRigaud installations, including CRD updates and breaking changes.

## Quick Upgrade

### Helm-based Upgrade (Recommended)

```bash
# 1. Update Helm repository
helm repo update

# 2. Check for breaking changes
helm diff upgrade virtrigaud virtrigaud/virtrigaud --version v0.2.1

# 3. Upgrade CRDs first (required for schema changes)
helm pull virtrigaud/virtrigaud --version v0.2.1 --untar
kubectl apply -f virtrigaud/crds/

# 4. Upgrade VirtRigaud
helm upgrade virtrigaud virtrigaud/virtrigaud \
  --namespace virtrigaud-system \
  --version v0.2.1
```

### Alternative: Direct CRD Download

```bash
# Download and apply CRDs from release
curl -L "https://github.com/projectbeskar/virtrigaud/releases/download/v0.2.1/virtrigaud-crds.yaml" | kubectl apply -f -

# Upgrade application
helm upgrade virtrigaud virtrigaud/virtrigaud --version v0.2.1
```

## Version-Specific Upgrade Notes

### v0.3.7 → v0.3.8

**Additive release. No breaking changes for operators.** v0.3.8 adds two new
controllers (VMClone + VMSet), a new status field on `VMClone`, the RBAC those
controllers need, and provider-side connection-resilience fixes. A standard
`helm upgrade` picks everything up. The one thing to check is the chart's
templated-provider default — see the Helm note below.

#### What's new (no operator action required)

- **VMClone + VMSet controllers** — the manager now runs two additional
  reconcilers. The Helm chart adds the RBAC for `vmclones` and `vmsets` (and
  their `/status` subresources) automatically. If you maintain a hand-rolled
  ClusterRole instead of the chart's, add read/write on
  `vmclones`/`vmclones/status` and `vmsets`/`vmsets/status` in the
  `infra.virtrigaud.io` API group.
- **New `VMClone.status.targetVMID` field** — purely additive status field
  surfacing the provider-specific ID of the clone's target VM. No spec change,
  no migration step.
- **Provider connection resilience** — the vSphere provider now keeps its
  vCenter session alive and reconnects on a real probe failure
  ([#190](https://github.com/projectbeskar/virtrigaud/pull/190)); the libvirt
  provider now retries transient SSH connection failures with bounded backoff
  ([#191](https://github.com/projectbeskar/virtrigaud/pull/191)). Both are
  provider-internal — no Provider CR change. See
  [Resilience](resilience.md#provider-side-connection-resilience-v038).
- **Migration-storage PVC safety** — the provider controller no longer deletes
  migration-storage PVCs and now watches them
  ([#184](https://github.com/projectbeskar/virtrigaud/pull/184)). No operator
  action; in-flight migrations are simply safer.

#### Helm note: templated providers are DISABLED by default ([#173](https://github.com/projectbeskar/virtrigaud/pull/173))

The chart no longer renders templated provider Deployments by default. This is a
**chart default change, not a code breaking change**:

- **If you manage providers as `Provider` CRs** (the recommended pattern, where
  the operator deploys provider workloads from the CR) — **you are unaffected.**
  Nothing changes.
- **If you relied on the chart's templated providers** (rendered directly from
  Helm values rather than from a `Provider` CR), they will no longer be created
  after the upgrade. Re-enable each one explicitly:

  ```yaml
  providers:
    vsphere:
      enabled: true
    libvirt:
      enabled: true
    proxmox:
      enabled: true
  ```

  Set only the types you actually use.

#### Helm upgrade command

```bash
helm repo update
helm upgrade -i virtrigaud virtrigaud/virtrigaud \
  --version 0.3.8 \
  --reset-values \
  -f your-values.yaml
```

If you use chart-templated providers, remember the `providers.<type>.enabled=true`
flag above must be in `your-values.yaml` or they will not be rendered.

#### Post-upgrade verification

```bash
# Confirm the manager is running v0.3.8
kubectl -n virtrigaud-system port-forward deploy/virtrigaud-manager 8080:8080 &
curl -s localhost:8080/metrics | grep '^virtrigaud_build_info'
# Expect: virtrigaud_build_info{version="v0.3.8",...} 1

# Confirm the new reconcilers are emitting (after first VMClone/VMSet activity)
curl -s localhost:8080/metrics | \
  grep -E 'virtrigaud_manager_reconcile_total\{kind="(VMClone|VMSet)"'

# All providers should still be ProviderAvailable=True
kubectl get providers -A
```

### v0.3.6 → v0.3.7

Released 2026-05-30. **Security enforcement + multi-arch release.** Two breaking
changes affect SSH libvirt providers and any Provider CR without a `tls` block.

#### Breaking changes

##### 1. mTLS now enforced on all Provider CRs (BREAKING)

The manager now **requires** a `spec.runtime.service.tls` block on every
Provider CR. A Provider that lacks the block will not reconcile — no Deployment
is created — and its status shows:

```
TLSConfigured=False, Reason=TLSBlockMissing
```

**Remediation — to enable mTLS (recommended for production):**

1. Create a TLS Secret with `tls.crt`, `tls.key`, and `ca.crt`:

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: provider-vsphere-tls
     namespace: virtrigaud-system
   type: kubernetes.io/tls
   data:
     tls.crt: <base64>
     tls.key: <base64>
   stringData:
     ca.crt: |
       -----BEGIN CERTIFICATE-----
       ...
       -----END CERTIFICATE-----
   ```

2. Add the `tls` block to your Provider CR under `spec.runtime.service`:

   ```yaml
   runtime:
     service:
       tls:
         enabled: true
         secretRef:
           name: provider-vsphere-tls
         insecureSkipVerify: false
   ```

**Remediation — to keep plaintext (dev/lab only):**

```yaml
runtime:
  service:
    tls:
      enabled: false
```

When `tls.enabled: false`, the condition reads `TLSConfigured=False,
Reason=ExplicitlyDisabled` and the Deployment proceeds. This is audit-flagged
and not suitable for regulated environments.

**Additional mTLS facts:**

- TLS 1.3 is the minimum protocol version for both manager and provider.
- Provider env `VIRTRIGAUD_PROVIDER_ALLOWED_SANS` (comma-joined) constrains
  which manager certificates are accepted. `VIRTRIGAUD_PROVIDER_INSECURE=true`
  opts out of TLS entirely on the provider side (plaintext).
- Fail-closed: no TLS material + no explicit opt-out → provider hard-exits.
- For chart-templated providers, the Helm `providerTLS` block accepts
  `secretName`, `allowedSANs` (list), and `insecure` (bool, only when
  `secretName` is empty).

##### 2. Libvirt SSH host-key verification now enforced (BREAKING for SSH libvirt)

In v0.3.6 the libvirt provider set `no_verify=1` on the SSH URI, skipping
host-key verification. **That flag is removed in v0.3.7.** Existing SSH libvirt
Providers will stop connecting after the upgrade until a `known_hosts` key is
added to the credentials Secret.

**Remediation:**

Seed `known_hosts` on the operator workstation and add it to the Secret:

```bash
ssh-keyscan -H <libvirt-host> > known_hosts
kubectl patch secret libvirt-creds -n virtrigaud-system \
  --type='json' \
  -p="[{\"op\": \"add\", \"path\": \"/stringData/known_hosts\",
         \"value\": \"$(cat known_hosts)\"}]"
```

The provider reads the key from `/etc/virtrigaud/credentials/known_hosts`.

**Escape hatch (lab/migration windows only; audit-flagged):**

```yaml
spec:
  runtime:
    env:
      - name: LIBVIRT_INSECURE_SKIP_HOST_KEY_VERIFICATION
        value: "true"
```

#### Other changes (no operator action required)

- **Multi-arch images** — all component images (`manager`, `provider-vsphere`,
  `provider-libvirt`, `provider-proxmox`) are now built for both
  `linux/amd64` and `linux/arm64`. arm64 clusters are now fully supported.
  No changes needed in Provider CRs or Helm values.

- **Manager RBAC tightened** — the manager's ClusterRole now grants read-only
  access to Secrets (was read-write in v0.3.6). If you added custom rules that
  relied on write access, re-add them via `rbac.additionalRules` in your Helm
  values. A `helm upgrade` picks up the new RBAC automatically.

- **Go source-build floor raised to 1.26.3** — if you build from source, you
  need Go 1.26.3 or later. Binary and image consumers are unaffected.

#### Helm upgrade command

```bash
helm repo update
helm upgrade -i virtrigaud virtrigaud/virtrigaud \
  --version 0.3.7 \
  --reset-values \
  -f your-values.yaml
```

If you use chart-templated providers with `providerTLS.secretName`, ensure the
referenced Secret exists before the upgrade or the provider pods will not start.

#### Post-upgrade verification

```bash
# All providers should show TLSConfigured=True and ProviderAvailable=True
kubectl get providers -A

# Confirm the manager is running v0.3.7
kubectl -n virtrigaud-system port-forward deploy/virtrigaud-manager 8080:8080 &
curl -s localhost:8080/metrics | grep '^virtrigaud_build_info'
# Expect: virtrigaud_build_info{version="v0.3.7",...} 1

# Check for any providers still failing TLS negotiation
kubectl get providers -A \
  -o custom-columns=NAME:.metadata.name,TLS:.status.conditions[?(@.type=="TLSConfigured")].reason
```

### v0.3.5 → v0.3.6

Released 2026-05-25. **Headline observability + supply-chain release.** No
breaking changes for default-config users; binary consumers via released
images are unaffected.

#### Breaking changes

- **None for operators.** Source builders need **Go 1.26+** installed
  locally ([#125](https://github.com/projectbeskar/virtrigaud/pull/125),
  toolchain floor bumped 1.24.0 → 1.26.0). If you only consume the released
  manager + provider container images, this does not affect you.

#### Helm upgrade command

```bash
helm repo update
helm upgrade -i virtrigaud virtrigaud/virtrigaud \
  --version 0.3.6 \
  --reset-values
```

`--reset-values` matches the established pattern used on the maintainer's
lab cluster (`vr1.lab.k8`) and ensures the upgrade picks up any new chart
defaults rather than carrying over stale rendered values. If you have local
value overrides, pass them via `-f your-values.yaml` after `--reset-values`.

#### New `/metrics` families to add to dashboards

After the rollout, the following `virtrigaud_*` families become available
(some emit immediately, some on first activity):

| Metric | Type | Labels | When it populates |
|---|---|---|---|
| `virtrigaud_circuit_breaker_state` | gauge | `provider_type`, `provider` | Immediately at boot (one row per Provider CR). Values: 0=Closed, 1=HalfOpen, 2=Open. **Alertable on `> 0`.** |
| `virtrigaud_circuit_breaker_failures_total` | counter | `provider_type`, `provider` | On first CB-counted RPC failure per Provider |
| `virtrigaud_vm_operations_total` | counter | `provider_type`, `provider`, `operation`, `outcome` | On the first VM RPC after deploy (Create/Delete/Power/Describe/Reconfigure) |
| `virtrigaud_ip_discovery_duration_seconds` | histogram | `provider_type` | On the first no-IPs → has-IPs VM transition (idempotent across manager restarts) |
| `virtrigaud_provider_tasks_inflight` | gauge | `provider_type`, `provider` | Seeded to 0 at boot, increments on the first task-creating RPC |

These slot in alongside the metrics already present since v0.3.5. The full
metric inventory after v0.3.6 is **11 of 12** `virtrigaud_*` families wired
in code; the 12th (`virtrigaud_queue_depth`) is explicitly deprecated — see
the next section.

Suggested baseline alerts:

- `max by (provider) (virtrigaud_circuit_breaker_state) > 0` for **5m** —
  fires when any Provider's circuit opens or half-opens
- `rate(virtrigaud_vm_operations_total{outcome="error"}[5m]) > 0` per
  provider/operation — surface elevated failure rates
- `histogram_quantile(0.95, sum by (le, provider_type) (rate(virtrigaud_ip_discovery_duration_seconds_bucket[5m])))` —
  P95 time from `kubectl apply` to first IP

#### Deprecation: `virtrigaud_queue_depth`

The `virtrigaud_queue_depth{kind}` gauge and the
`(*ReconcileMetrics).SetQueueDepth` helper are **deprecated in v0.3.6**
([#132](https://github.com/projectbeskar/virtrigaud/pull/132)). They are
redundant with controller-runtime's `workqueue_depth{name=<controller-name>}`,
which has been on `/metrics` since v0.3.0 and ships with 8 sibling workqueue
metrics for free.

The metric family is still registered (no breakage), but the `# HELP` line
now begins with `[DEPRECATED v0.3.6 — use workqueue_depth{name} instead]` so
the deprecation surfaces on your next scrape. Scheduled for removal in
**v0.4.0 or later**.

**Migration mapping** for the 8 reconciler kinds (also in the GoDoc on
`SetQueueDepth`):

| Reconciler                       | controller-runtime `name` label |
|----------------------------------|---------------------------------|
| `VirtualMachineReconciler`       | `virtualmachine`                |
| `ProviderReconciler`             | `provider`                      |
| `VMClassReconciler`              | `vmclass`                       |
| `VMImageReconciler`              | `vmimage`                       |
| `VMNetworkAttachmentReconciler`  | `vmnetworkattachment`           |
| `VMAdoptionReconciler`           | `vmadoption`                    |
| `VMSnapshotReconciler`           | `vmsnapshot`                    |
| `VMMigrationReconciler`          | `vmmigration`                   |

Dashboard rewrite recipe:

```
virtrigaud_queue_depth{kind="virtualmachine"}
    →    workqueue_depth{name="virtualmachine"}
```

#### CircuitBreaker behaviour change

Every outbound provider gRPC RPC is now wrapped by a per-Provider
CircuitBreaker ([#112](https://github.com/projectbeskar/virtrigaud/issues/112)),
backed by the new `virtrigaud_circuit_breaker_*` metric families above.

Defaults:

| Setting              | Default | Effect                                         |
|----------------------|---------|------------------------------------------------|
| `FailureThreshold`   | 10      | Open after 10 consecutive infra-class failures |
| `ResetTimeout`       | 60s     | Time in Open before transitioning to HalfOpen  |
| `HalfOpenMaxCalls`   | 3       | Probe calls allowed in HalfOpen state          |

**What trips the breaker** (infra-class gRPC errors):

- `Unavailable`
- `DeadlineExceeded`
- `Internal`
- `Unknown`

**What passes through** (business-class errors — no CB impact):

- `NotFound`, `AlreadyExists`, `InvalidArgument`, `FailedPrecondition`,
  `PermissionDenied`, `Unauthenticated`, etc.

!!! warning "Global config only — no per-Provider knob yet"
    The CB defaults come from `resilience.DefaultConfig()` and are applied
    uniformly to every Provider CR. There is **no per-Provider override
    field** in v0.3.6. If you need different thresholds for a high-latency
    provider, that work is tracked separately; for now, plan around the
    defaults above.

#### Security: OpenTelemetry CVE fixes

The OpenTelemetry Go SDK dependencies are bumped to **v1.43.0** in v0.3.6,
closing 3 HIGH-severity CVEs that were present in v0.3.5
([#143/#144](https://github.com/projectbeskar/virtrigaud/pull/144)):

| CVE              | Package                            | v0.3.5 | v0.3.6  |
|------------------|------------------------------------|--------|---------|
| CVE-2026-29181   | `go.opentelemetry.io/otel`         | v1.39.0 | v1.43.0 |
| CVE-2026-24051   | `go.opentelemetry.io/otel/sdk`     | v1.39.0 | v1.43.0 |
| CVE-2026-39883   | `go.opentelemetry.io/otel/sdk`     | v1.39.0 | v1.43.0 |

CVE-2026-24051 and CVE-2026-39883 are PATH-hijacking primitives — exactly
the class of finding regulated environments will not accept. **Upgrade
promptly** if you scan with Trivy/Grype.

#### Smoke recipe (verify your upgrade)

After the rollout completes, verify the manager is running the v0.3.6 binary
and the new metrics are present:

```bash
# Port-forward to the manager metrics endpoint
kubectl -n virtrigaud-system port-forward deploy/virtrigaud-manager 8080:8080 &

# 1. Build info must report v0.3.6 / Go 1.26.x
curl -s localhost:8080/metrics | grep '^virtrigaud_build_info'
# Expect: virtrigaud_build_info{version="v0.3.6", go_version="go1.26.x", ...} 1

# 2. Count distinct virtrigaud_* metric families on /metrics
curl -s localhost:8080/metrics | grep -E '^# HELP virtrigaud_' | wc -l
# Expect: ~9-11 families emit immediately. The remaining 2 (vm_operations_total,
# ip_discovery_duration_seconds) populate on the first relevant VM event.

# 3. Confirm the CB gauge is exposed (one row per Provider CR)
curl -s localhost:8080/metrics | grep '^virtrigaud_circuit_breaker_state'

# 4. Confirm deprecation banner on the old queue_depth gauge
curl -s localhost:8080/metrics | grep -B1 '^virtrigaud_queue_depth' | head -2
# Expect a # HELP line beginning with [DEPRECATED v0.3.6 ...]
```

If any of those checks fail, capture the manager logs
(`kubectl -n virtrigaud-system logs deploy/virtrigaud-manager`) before
rolling back.

### v0.2.0 → v0.2.1

**Breaking Changes:**
- ✅ PowerState validation fixed (OffGraceful now supported)
- ✅ Hardware version management added (vSphere only)
- ✅ Disk size configuration respected

**Required Actions:**
1. **CRD Update Required**: New powerState validation and schema changes
2. **Provider Image Update**: Ensure providers use v0.2.1+ images for new features
3. **Field Testing**: Verify OffGraceful, hardware version, and disk sizing work correctly

**Upgrade Steps:**
```bash
# 1. Backup existing resources
kubectl get virtualmachines,vmclasses,providers -A -o yaml > virtrigaud-backup-v021.yaml

# 2. Update CRDs (fixes OffGraceful validation)
kubectl apply -f https://github.com/projectbeskar/virtrigaud/releases/download/v0.2.1/virtrigaud-crds.yaml

# 3. Upgrade VirtRigaud
helm upgrade virtrigaud virtrigaud/virtrigaud --version v0.2.1

# 4. Verify OffGraceful works
kubectl patch virtualmachine <vm-name> --type='merge' -p='{"spec":{"powerState":"OffGraceful"}}'
```

## Rollback Procedures

### Rollback to Previous Version

```bash
# 1. Rollback application
helm rollback virtrigaud <revision>

# 2. Rollback CRDs (if schema breaking changes)
kubectl apply -f https://github.com/projectbeskar/virtrigaud/releases/download/v0.2.0/virtrigaud-crds.yaml

# 3. Verify resources still work
kubectl get virtualmachines -A
```

### Emergency Recovery

```bash
# 1. Restore from backup
kubectl apply -f virtrigaud-backup-v021.yaml

# 2. Check controller logs
kubectl logs -n virtrigaud-system deployment/virtrigaud-manager

# 3. Force reconciliation
kubectl annotate virtualmachine <vm-name> virtrigaud.io/force-sync="$(date)"
```

## Automated Upgrade with GitOps

### ArgoCD

```yaml
apiVersion: argoproj.io/v1beta1
kind: Application
metadata:
  name: virtrigaud
spec:
  source:
    chart: virtrigaud
    repoURL: https://projectbeskar.github.io/virtrigaud
    targetRevision: "0.2.1"
    helm:
      parameters:
      - name: manager.image.tag
        value: "v0.2.1"
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    - Replace=true  # Required for CRD updates
```

### Flux

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: virtrigaud
spec:
  chart:
    spec:
      chart: virtrigaud
      version: "0.2.1"
      sourceRef:
        kind: HelmRepository
        name: virtrigaud
  upgrade:
    crds: CreateReplace  # Ensure CRDs are updated
```

## Troubleshooting Upgrades

### CRD Validation Errors

```bash
# Check CRD status
kubectl get crd virtualmachines.infra.virtrigaud.io -o yaml

# Fix validation conflicts
kubectl patch crd virtualmachines.infra.virtrigaud.io --type='json' -p='[{"op": "remove", "path": "/spec/versions/0/schema/openAPIV3Schema/properties/spec/properties/powerState/allOf"}]'
```

### Provider Image Mismatch

```bash
# Check provider images
kubectl get providers -o jsonpath='{.items[*].spec.runtime.image}'

# Update provider image
kubectl patch provider <provider-name> --type='merge' -p='{"spec":{"runtime":{"image":"ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.2.1"}}}'
```

### Resource Conflicts

```bash
# Check for resource conflicts
kubectl get events --sort-by=.metadata.creationTimestamp

# Force resource refresh
kubectl delete pod -l app.kubernetes.io/name=virtrigaud -n virtrigaud-system
```

## Best Practices

### Pre-Upgrade Checklist

- [ ] Backup all VirtRigaud resources
- [ ] Check for breaking changes in release notes
- [ ] Test upgrade in staging environment
- [ ] Verify provider connectivity
- [ ] Plan rollback strategy

### Post-Upgrade Verification

- [ ] All CRDs updated successfully
- [ ] Controller manager running
- [ ] Providers healthy and responsive
- [ ] Existing VMs still manageable
- [ ] New features working (OffGraceful, hardware version, etc.)

### Monitoring During Upgrade

```bash
# Watch controller logs
kubectl logs -n virtrigaud-system deployment/virtrigaud-manager -f

# Monitor VM status
kubectl get virtualmachines -A --watch

# Check provider health
kubectl get providers -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[0].type,MESSAGE:.status.conditions[0].message
```

## Support and Recovery

If you encounter issues during upgrade:

1. **Check Release Notes**: https://github.com/projectbeskar/virtrigaud/releases
2. **Review Logs**: Controller and provider logs for error details
3. **Community Support**: GitHub issues and discussions
4. **Emergency Rollback**: Use documented rollback procedures

Remember: Always test upgrades in non-production environments first!

## Development Workflow (v0.2.1+)

### Automated CRD Synchronization

Starting with v0.2.1, VirtRigaud includes automated tooling to ensure CRDs stay in sync between development and Helm chart deployments.

#### For Developers

```bash
# Generate and sync CRDs automatically
make sync-helm-crds

# Verify CRDs are in sync
make verify-helm-crds

# Package Helm chart with latest CRDs
make helm-package
```

#### Pre-commit Hooks

Install pre-commit hooks to automatically sync CRDs:

```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# CRDs will now sync automatically on commits that modify:
# - api/**.go files
# - config/crd/**.yaml files
```

#### CI/CD Integration

The CI/CD pipeline now automatically:

1. **Validates CRD sync** on every pull request
2. **Syncs CRDs** before Helm chart packaging in releases  
3. **Fails builds** if Helm chart CRDs are out of sync

This prevents the v0.2.1-rc2 issue where OffGraceful validation failed due to stale Helm chart CRDs.

### Repository Workflow

```bash
# 1. Make API changes
vim api/infra.virtrigaud.io/v1beta1/virtualmachine_types.go

# 2. Generate and sync CRDs (automated by pre-commit)
make sync-helm-crds

# 3. Commit (hooks will verify sync)
git add .
git commit -m "feat: add new VM power states"

# 4. CI validates everything is in sync
git push origin feature-branch
```
