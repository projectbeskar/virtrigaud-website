<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VMMigration API Reference

This page is aligned to **VirtRigaud v0.3.8** and reflects the
`infra.virtrigaud.io/v1beta1` `VMMigration` CRD exactly as it ships. The
authoritative source is the Go type definitions at
`api/infra.virtrigaud.io/v1beta1/vmmigration_types.go`.

!!! danger "v0.3.8 reality: vSphere → Libvirt is the validated direction"
    `VMMigration` is wired across `vsphere`, `libvirt`, and `proxmox`
    providers in code, and the **direction smoke-tested end-to-end on a real
    lab cluster is vSphere → Libvirt**
    (`fieldTesting/MIGRATION_SUCCESS_v0.3.62.md`,
    `fieldTesting/MIGRATION_VERIFICATION_v0.3.62.md`). As of v0.3.8 the
    underlying disk export/import primitives are in better shape on both ends:
    the libvirt provider now supports disk export
    ([#177](https://github.com/projectbeskar/virtrigaud/pull/177)), and the
    vSphere provider's disk export/import capabilities are advertised
    accurately ([#178](https://github.com/projectbeskar/virtrigaud/pull/178)).
    Other directions (Libvirt → vSphere, vSphere → Proxmox, Proxmox → anything)
    compile and will reconcile through the phase machine, but have not been
    validated against real hypervisor pairs and **should be treated as roadmap,
    not supported**.

### Capability gating (#176): fail-close on providers lacking export/import

v0.3.8 adds an opt-in manager flag
`--enforce-provider-capabilities` ([#176](https://github.com/projectbeskar/virtrigaud/pull/176)),
**default off**. When enabled, the manager checks each migration's source
and target providers against the capabilities they advertise
(`GetCapabilities` — disk export / disk import) and **fails the migration
closed** at validation time if a provider does not support the operation the
migration requires, rather than letting it fail deep in the export/import
phase. Leave it off to preserve pre-v0.3.8 behavior; turn it on in regulated
or fleet environments where a clear up-front rejection is preferable to a
late-phase failure. Because the vSphere (#178) and libvirt (#177) capability
advertisements are now accurate, this gate produces trustworthy decisions.

!!! warning "Storage backend is PVC-only"
    Earlier drafts of the migration docs described `s3`, `http`, and `nfs`
    storage backends. **Those are still not implemented as of v0.3.8** — the
    controller validates
    `Storage.Type != "pvc" && Storage.Type != ""` and rejects the migration
    (`internal/controller/vmmigration_controller.go:1425`). The transfer
    medium is a Kubernetes PVC (`ReadWriteMany` by default) mounted into
    both provider pods during the migration. See [User
    Guide](user-guide.md#storage) for the rationale and ADR-0001 for the
    design.

## Resource overview

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMMigration
metadata:
  name: <string>
  namespace: <string>
spec:
  source:                # MigrationSource (required)
  target:                # MigrationTarget (required)
  options:               # MigrationOptions (optional)
  storage:               # MigrationStorage (optional in schema; required in practice — see below)
  metadata:              # MigrationMetadata (optional)
status:
  # ... fields below
```

### Printer columns

`kubectl get vmmigration` displays these columns (defined at
`vmmigration_types.go:546-551`):

| Column   | JSONPath                              |
|----------|---------------------------------------|
| Source   | `.spec.source.vmRef.name`             |
| Target   | `.spec.target.name`                   |
| Phase    | `.status.phase`                       |
| Progress | `.status.progress.percentage`         |
| Age      | `.metadata.creationTimestamp`         |

`vmmig` is the registered short name (`kubectl get vmmig`).

## Spec

### `spec.source` (`MigrationSource`, required)

Source location and snapshot policy.
Defined at `vmmigration_types.go:46-72`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `vmRef.name` | string | required | Name of the source `VirtualMachine` resource (in the same namespace as the `VMMigration`). |
| `providerRef` | `ObjectRef` | inferred from source VM | Explicit source-provider reference. Optional; if omitted, the controller resolves the provider from the source VM's `providerRef`. |
| `snapshotRef.name` | string | unset | Name of an existing snapshot resource to migrate from. If set, `createSnapshot` is ignored. |
| `createSnapshot` | bool | `true` | If true and `snapshotRef` is unset, the controller creates a snapshot before exporting. |
| `powerOffBeforeMigration` | bool | `false` | If true, the source VM is powered off before exporting. |
| `deleteAfterMigration` | bool | `false` | If true, the source VM is **deleted** after a successful migration. Off by default for obvious safety reasons. |

```yaml
spec:
  source:
    vmRef:
      name: my-vsphere-vm
    createSnapshot: true
    powerOffBeforeMigration: false
    deleteAfterMigration: false
```

### `spec.target` (`MigrationTarget`, required)

Where the migrated VM is created.
Defined at `vmmigration_types.go:74-126`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | required | Name for the target `VirtualMachine`. Must match `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`, max 253 chars. |
| `namespace` | string | source's namespace | Namespace for the target VM. Max 63 chars. |
| `providerRef` | `ObjectRef` | required | Reference to the target `Provider` CR. |
| `classRef.name` | string | optional | `VMClass` to apply for resource allocation on the target. |
| `imageRef.name` | string | optional | `VMImage` to reference. **Usually unset on migrations** — the imported disk replaces image-based provisioning. |
| `networks[]` | `[]VMNetworkRef` | optional | Network attachments. Up to 10. |
| `disks[]` | `[]DiskSpec` | optional | Disk overrides. Up to 20. |
| `placementRef.name` | string | optional | `VMPlacementPolicy` reference. |
| `powerOn` | bool | `false` | Whether to power on the target VM after creation. |
| `labels` | `map[string]string` | unset | Labels to apply to the target VM. Up to 50 keys. |
| `annotations` | `map[string]string` | unset | Annotations to apply to the target VM. Up to 50 keys. |

```yaml
spec:
  target:
    name: my-vm-migrated
    namespace: prod
    providerRef:
      name: libvirt-prod
      namespace: virtrigaud-system
    classRef:
      name: medium
    networks:
      - name: corp-bridge
    powerOn: true
```

### `spec.options` (`MigrationOptions`, optional)

Tuning knobs.
Defined at `vmmigration_types.go:128-163`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `diskFormat` | enum (`qcow2`, `vmdk`, `raw`) | provider native | Target disk format. The exporter / importer converts via `qemu-img` as needed. |
| `compress` | bool | `false` | Compress during transfer. |
| `verifyChecksums` | bool | `true` | SHA256 verify on import. Strongly recommended on. |
| `timeout` | `metav1.Duration` | `4h` | Hard upper bound on the entire migration. |
| `retryPolicy` | `MigrationRetryPolicy` | see below | Retry policy for individual phase failures. |
| `cleanupPolicy` | enum (`Always`, `OnSuccess`, `Never`) | `OnSuccess` | When to clean up intermediate storage. |
| `validationChecks` | `ValidationChecks` | see below | Which post-import validation checks to run. |

#### `options.retryPolicy` (`MigrationRetryPolicy`)

Defined at `vmmigration_types.go:165-185`.

| Field | Type | Default | Bounds |
|-------|------|---------|--------|
| `maxRetries` | int32 | `3` | 0–10 |
| `retryDelay` | `metav1.Duration` | `5m` | — |
| `backoffMultiplier` | int32 | `2` | 1–10 |

#### `options.validationChecks` (`ValidationChecks`)

Defined at `vmmigration_types.go:187-208`.

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `checkDiskSize` | bool | `true` | Compare source vs target disk size. |
| `checkChecksum` | bool | `true` | Compare source vs target SHA256. |
| `checkBoot` | bool | `false` | Power on the target and confirm boot. Opt-in. |
| `checkConnectivity` | bool | `false` | Network reachability test against the target. Opt-in. |

### `spec.storage` (`MigrationStorage`, required-in-practice)

Where the disk data lives between export and import.
Defined at `vmmigration_types.go:210-220`.

```yaml
spec:
  storage:
    type: pvc                  # the only allowed value (as of v0.3.8)
    pvc:
      storageClassName: nfs-client
      size: 100Gi
      accessMode: ReadWriteMany
```

| Field | Type | Default | Bounds |
|-------|------|---------|--------|
| `type` | enum (`pvc`) | `pvc` | **`pvc` is the only valid value (as of v0.3.8).** Setting anything else fails validation at `vmmigration_controller.go:1425`. |
| `pvc` | `PVCStorageConfig` | required when `type=pvc` | See below. |

#### `storage.pvc` (`PVCStorageConfig`)

Defined at `vmmigration_types.go:222-250`.

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `name` | string | unset | Name of an existing PVC to reuse. If unset, the controller creates a temporary PVC owned by the `VMMigration` (auto-cleanup on deletion). |
| `storageClassName` | string | required when `name` is unset | StorageClass for the auto-created PVC. |
| `size` | string (`100Gi`-style) | required when `name` is unset | Capacity for the auto-created PVC. Pattern: `^[0-9]+(\\.[0-9]+)?(Ei?|Pi?|Ti?|Gi?|Mi?|Ki?)$`. |
| `accessMode` | enum (`ReadWriteOnce`, `ReadWriteMany`, `ReadOnlyMany`) | `ReadWriteMany` | RWX is the default because both provider pods need to mount the PVC simultaneously. RWO works only if both providers run on the same node. |
| `mountPath` | string | `/mnt/migration-storage` | Path inside the provider pods where the PVC is mounted. The libvirt provider's `ImportDisk` decodes `pvc://<name>/...` URLs to `${mountPath}/<name>/...` (`internal/providers/libvirt/server.go:485-489`). |

The migration controller drives a PVC-aware orchestration:

1. Creates the PVC if needed.
2. Annotates **both** source and target `Provider` CRs with
   `virtrigaud.io/migration-pvc=<pvc-name>` and a reconcile-trigger
   timestamp.
3. The `ProviderReconciler` adds the PVC to each provider Deployment's
   volume mounts and rolls the pods.
4. The migration controller waits for both providers to be `Ready` again
   before transitioning out of the validation phase.

This sequence is the reason a default migration deploy adds ~30–60s of
rolling-restart overhead per provider pod.

!!! note "Provider controller no longer deletes the migration PVC (v0.3.8)"
    In v0.3.8 ([#184](https://github.com/projectbeskar/virtrigaud/pull/184)) the
    `ProviderReconciler` **no longer deletes migration-storage PVCs** during its
    reconcile, and it now **watches** them. Previously a provider reconcile could
    race the PVC's lifecycle and reclaim the transfer medium out from under an
    in-flight migration. Ownership and cleanup of the intermediate PVC stay with
    the `VMMigration` CR (see [Finalizer](#finalizer)).

### `spec.metadata` (`MigrationMetadata`, optional)

Operator-facing tagging. Does not affect controller behavior.
Defined at `vmmigration_types.go:252-278`.

| Field | Type | Allowed values | Description |
|-------|------|---------------|-------------|
| `purpose` | enum | `disaster-recovery`, `cloud-migration`, `provider-change`, `testing`, `maintenance` | Why this migration is happening. |
| `createdBy` | string (≤255) | — | Identity. |
| `project` | string (≤255) | — | Project tag. |
| `environment` | enum | `dev`, `staging`, `prod`, `test`, `qa`, `uat` | Environment tag. |
| `tags` | `map[string]string` (≤50 keys) | — | Free-form. |

## Status

Defined at `vmmigration_types.go:280-361`. All fields are optional —
the controller fills them in as it progresses.

| Field | Type | Notes |
|-------|------|-------|
| `phase` | `MigrationPhase` (enum) | See [Phase machine](#phase-machine) below. |
| `message` | string | Human-readable status detail. |
| `targetVMRef.name` | string | Name of the created target `VirtualMachine` once `phase=Ready`. |
| `snapshotRef` | string | Snapshot resource name used. |
| `snapshotID` | string | Provider-specific snapshot ID. |
| `exportID` | string | Provider export operation ID. |
| `importID` | string | Provider import operation ID. |
| `taskRef` | string | Current async task being awaited. |
| `targetVMID` | string | Provider-specific target VM ID. |
| `startTime` | `metav1.Time` | When the migration started. |
| `completionTime` | `metav1.Time` | When the migration completed (success or failure). |
| `progress` | `MigrationProgress` | See below. |
| `diskInfo` | `MigrationDiskInfo` | Source / target disk metadata + checksums. |
| `storageInfo` | `MigrationStorageInfo` | PVC URL, size, upload time, cleanup state. |
| `storagePVCName` | string | Name of the PVC created or reused for this migration. |
| `conditions` | `[]metav1.Condition` | Standard K8s condition list. See [Condition types](#condition-types). |
| `observedGeneration` | int64 | Last `spec.generation` the controller acted on. |
| `retryCount` | int32 | How many times the migration has been retried. |
| `lastRetryTime` | `metav1.Time` | Timestamp of the last retry. |
| `validationResults` | `ValidationResults` | Outcomes of the validation checks. |

### `status.progress` (`MigrationProgress`)

Defined at `vmmigration_types.go:393-422`.

| Field | Type | Notes |
|-------|------|-------|
| `currentPhase` | `MigrationPhase` | Same enum as `status.phase`. |
| `totalBytes` | int64 | Total bytes to transfer (best-effort estimate). |
| `transferredBytes` | int64 | Bytes transferred so far. |
| `percentage` | int32 (0–100) | Overall progress percentage. The printer-column field. |
| `eta` | `metav1.Duration` | Estimated time to completion. |
| `transferRate` | int64 | Current transfer rate (bytes/second). |
| `phaseStartTime` | `metav1.Time` | When the current phase started. |

### `status.diskInfo` (`MigrationDiskInfo`)

Defined at `vmmigration_types.go:424-458`.

| Field | Type | Notes |
|-------|------|-------|
| `sourceDiskID` | string | Source provider's disk identifier. |
| `sourceFormat` | string | Source format (`vmdk`, `qcow2`, `raw`). |
| `sourceSize` | `resource.Quantity` | Source disk size. |
| `targetDiskID` | string | Target provider's disk identifier (once imported). |
| `targetFormat` | string | Target format. |
| `targetSize` | `resource.Quantity` | Target disk size. |
| `checksum` | string | SHA256 of the transferred disk (legacy field). |
| `sourceChecksum` | string | SHA256 measured at source. |
| `targetChecksum` | string | SHA256 measured at target after import. |

### `status.storageInfo` (`MigrationStorageInfo`)

Defined at `vmmigration_types.go:460-477`.

| Field | Type | Notes |
|-------|------|-------|
| `url` | string | `pvc://<pvc-name>/<file>` URL the libvirt provider decodes (`internal/providers/libvirt/server.go:485-489`). |
| `size` | `resource.Quantity` | Bytes written to the intermediate PVC. |
| `uploadedAt` | `metav1.Time` | When the export finished writing. |
| `cleanedUp` | bool | Whether the intermediate file (and PVC, if owned) was deleted. |

### `status.validationResults` (`ValidationResults`)

Defined at `vmmigration_types.go:479-500`.

| Field | Type | Notes |
|-------|------|-------|
| `diskSizeMatch` | *bool | Result of `validationChecks.checkDiskSize`. |
| `checksumMatch` | *bool | Result of `validationChecks.checkChecksum`. |
| `bootSuccess` | *bool | Result of `validationChecks.checkBoot` (only set if opted in). |
| `connectivitySuccess` | *bool | Result of `validationChecks.checkConnectivity` (only set if opted in). |
| `validationErrors` | []string | Free-form error strings from validation. |

## Phase machine

`MigrationPhase` is defined at `vmmigration_types.go:363-390`. The controller
loop dispatch lives at `vmmigration_controller.go:198-218`.

```text
Pending
   │
   ▼
Validating ──────────────┐
   │                     │
   ▼                     │ (failure at any phase
Snapshotting             │  transitions here)
   │                     │
   ▼                     │
Exporting                │
   │                     │
   ▼                     │
Transferring             │
   │                     │
   ▼                     │
Converting (optional)    │
   │                     │
   ▼                     │
Importing                │
   │                     │
   ▼                     │
Creating                 │
   │                     │
   ▼                     │
Validating-Target        │
   │                     │
   ├─────────────► Failed
   ▼
Ready
```

| Phase | Constant | What's happening |
|-------|----------|------------------|
| `Pending` | `MigrationPhasePending` | Just created, awaiting first reconcile. |
| `Validating` | `MigrationPhaseValidating` | Source VM, target provider, storage config, and PVC mount validated. Provider pods are restarted with the new PVC mount before this phase exits. |
| `Snapshotting` | `MigrationPhaseSnapshotting` | Source VM snapshot is being created (unless `snapshotRef` was supplied). |
| `Exporting` | `MigrationPhaseExporting` | Source provider writes the disk to the intermediate PVC. |
| `Transferring` | `MigrationPhaseTransferring` | Data is being copied to the PVC (in PVC mode, this is part of `Exporting`; the controller may not always set this phase explicitly). |
| `Converting` | `MigrationPhaseConverting` | `qemu-img` converts between formats (`vmdk` → `qcow2`, etc.). Skipped if formats match. |
| `Importing` | `MigrationPhaseImporting` | Target provider reads the disk from the PVC and registers it. |
| `Creating` | `MigrationPhaseCreating` | Target `VirtualMachine` resource is created and the target provider creates the VM. |
| `Validating-Target` | `MigrationPhaseValidatingTarget` | Post-create validation per `validationChecks`. |
| `Ready` | `MigrationPhaseReady` | Migration successful. The target VM exists and is independent of the `VMMigration` CR. |
| `Failed` | `MigrationPhaseFailed` | Terminal failure. Retries (per `options.retryPolicy`) recycle the phase machine from `Pending`. |

### Important behavior

- **Once `Ready`, the target `VirtualMachine` is fully independent.** Deleting
  the `VMMigration` CR does **not** delete the target VM. The controller
  marks the target VM with annotations
  `virtrigaud.io/migration-completed="true"` and
  `virtrigaud.io/migration-completed-at=<RFC3339>` to make this property
  observable.
- **Failed migrations clean up their partial target VM** during finalizer
  processing. The check at `vmmigration_controller.go:1257` only deletes the
  target VM if `phase=Failed` (and the optional `phase=Creating` window where
  the target VM may exist but the migration has not yet declared itself
  ready).
- **The intermediate PVC is owned by the VMMigration CR**, so by default it
  is garbage-collected on migration deletion. The controller also explicitly
  deletes it at `vmmigration_controller.go:1222-1240` as a belt-and-braces
  cleanup.

### G3 + K5 double-count fix (v0.3.6)

PR [#106](https://github.com/projectbeskar/virtrigaud/pull/106) closed a
latent double-count bug in the migration reconciler: the previous code path
recorded a reconcile sample twice on errored migrations (one explicit error
sample plus a deferred-captured success sample), inflating the
`virtrigaud_manager_reconcile_total` counter. The fix uses named-return +
deferred outcome-inference and is the canonical pattern used across the
reconcilers since v0.3.6. See [CHANGELOG.md
2026-05-23](https://github.com/projectbeskar/virtrigaud/blob/main/CHANGELOG.md)
for the full audit note.

## Condition types

Defined at `vmmigration_types.go:502-542`. Surfaced on `status.conditions`
via `metav1.Condition`.

| Type | Reason examples | Meaning |
|------|----------------|---------|
| `Ready` | `Completed` | The migration completed. `status=True` is the terminal success state. |
| `Validating` | `Validating`, `ValidationComplete`, `ValidationFailed` | Phase 1. |
| `Snapshotting` | `SnapshotSelected`, `SnapshotComplete` | Phase 2. |
| `Exporting` | `Exporting` | Phase 3. |
| `Transferring` | `Transferring` | Disk upload to the PVC. |
| `Importing` | `Importing` | Phase 5. |
| `Failed` | `SourceNotFound`, `ProviderError`, `StorageError`, `ValidationFailed`, `Timeout` | Terminal failure. |

## Complete example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMMigration
metadata:
  name: app-vm-vsphere-to-libvirt
  namespace: applications
  labels:
    app: my-app
    env: prod
spec:
  source:
    vmRef:
      name: app-vm-vsphere
    createSnapshot: true
    powerOffBeforeMigration: true
    deleteAfterMigration: false      # keep source for rollback

  target:
    name: app-vm-libvirt
    namespace: applications
    providerRef:
      name: libvirt-prod
      namespace: virtrigaud-system
    classRef:
      name: medium-vm
    networks:
      - name: corp-bridge
    powerOn: false                   # start cold so an operator can verify

  options:
    diskFormat: qcow2
    compress: false
    verifyChecksums: true
    timeout: 4h
    retryPolicy:
      maxRetries: 3
      retryDelay: 5m
      backoffMultiplier: 2
    cleanupPolicy: OnSuccess
    validationChecks:
      checkDiskSize: true
      checkChecksum: true
      checkBoot: false
      checkConnectivity: false

  storage:
    type: pvc
    pvc:
      storageClassName: nfs-client
      size: 100Gi
      accessMode: ReadWriteMany

  metadata:
    purpose: provider-change
    createdBy: alice@example.com
    project: platform
    environment: prod
    tags:
      ticket: PLAT-1234

status:
  phase: Ready
  observedGeneration: 1
  startTime: "2026-05-23T10:00:00Z"
  completionTime: "2026-05-23T11:14:35Z"
  storagePVCName: app-vm-vsphere-to-libvirt-storage
  snapshotRef: app-vm-vsphere-migration-abc12345
  snapshotID: snap-xyz
  exportID: task-export-098
  importID: task-import-765
  targetVMRef:
    name: app-vm-libvirt
  targetVMID: lvm-domain-uuid-…
  progress:
    currentPhase: Ready
    percentage: 100
    totalBytes: 53687091200
    transferredBytes: 53687091200
  diskInfo:
    sourceDiskID: vsphere-disk-1
    sourceFormat: vmdk
    sourceSize: 50Gi
    targetDiskID: lvm-vol-app-vm-libvirt-disk
    targetFormat: qcow2
    targetSize: 50Gi
    sourceChecksum: sha256:abc...
    targetChecksum: sha256:abc...
  storageInfo:
    url: pvc://app-vm-vsphere-to-libvirt-storage/disk.qcow2
    size: 50Gi
    uploadedAt: "2026-05-23T10:45:12Z"
    cleanedUp: true
  validationResults:
    diskSizeMatch: true
    checksumMatch: true
  conditions:
    - type: Ready
      status: "True"
      reason: Completed
      message: Migration completed successfully
      lastTransitionTime: "2026-05-23T11:14:35Z"
```

## Finalizer

The controller owns the finalizer
`vmmigration.infra.virtrigaud.io/cleanup` (visible in
`metadata.finalizers`). On delete it:

1. Cleans up the intermediate PVC if not already gone
   (`vmmigration_controller.go:1222-1240`).
2. Deletes the source VM snapshot if `cleanupPolicy=Always` or the migration
   reached `Ready` and `cleanupPolicy=OnSuccess`.
3. Deletes a partial target VM **only** if the migration ended in `Failed`
   (or was caught mid-`Creating`).
4. Removes the finalizer to allow K8s garbage collection.

## RBAC required to create VMMigrations

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: vmmigration-author
rules:
  - apiGroups: ["infra.virtrigaud.io"]
    resources: ["vmmigrations"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["infra.virtrigaud.io"]
    resources: ["vmmigrations/status"]
    verbs: ["get"]
  - apiGroups: ["infra.virtrigaud.io"]
    resources: ["virtualmachines", "providers"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create", "patch"]
```

The controller itself (`virtrigaud-manager`) needs **broader** RBAC to
mutate Provider CR annotations and create PVCs; that is part of the manager
ServiceAccount baked into the Helm chart.

## See also

- [VM Migration User Guide](user-guide.md) — operator-facing how-to.
- [VM Migration Guide](vm-migration-guide.md) — architectural deep dive.
- [Full CRD Reference](../references/generated-crd-docs.md#vmmigration) —
  generated CRD field reference.
- [Resilience](../operations/resilience.md) — how the CircuitBreaker
  interacts with the many provider RPCs a migration issues.
