<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VMMigration API Reference

This page is aligned to **VirtRigaud v0.3.11** and reflects the
`infra.virtrigaud.io/v1beta1` `VMMigration` CRD exactly as it ships. The
authoritative source is the Go type definitions at
`api/infra.virtrigaud.io/v1beta1/vmmigration_types.go`.

!!! info "v0.3.11: all three providers validated in both directions"
    `VMMigration` is fully validated across `vsphere`, `libvirt`, and `proxmox`
    providers, in any direction, over both S3 and NFS staging backends (ADR-0006
    Slices 1–4, [#236](https://github.com/projectbeskar/virtrigaud/issues/236)).
    NFS staging was validated on 2026-06-21 against a real OpenMediaVault server.
    PVC mode (`storage.type: pvc`) is retained for compatibility.

### Capability gating (#176): fail-close on providers lacking export/import

v0.3.8 adds an opt-in manager flag
`--enforce-provider-capabilities` ([#176](https://github.com/projectbeskar/virtrigaud/pull/176)),
**default off**. When enabled, the manager checks each migration's source
and target providers against the capabilities they advertise
(`GetCapabilities` — disk export / disk import) and **fails the migration
closed** at validation time if a provider does not support the operation the
migration requires. Leave it off to preserve pre-v0.3.8 behavior; turn it on
in regulated or fleet environments where a clear up-front rejection is preferable
to a late-phase failure.

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
  storage:               # MigrationStorage (optional in schema; required in practice)
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
| `createSnapshot` | bool | `true` | If true and `snapshotRef` is unset, the controller creates a snapshot before exporting. Set to `false` when using NFS to avoid multi-disk/CDROM snapshot pitfalls. |
| `powerOffBeforeMigration` | bool | `false` | If true, the source VM is powered off before exporting. **Required for vSphere source** (ESXi locks a running VM's disk). |
| `deleteAfterMigration` | bool | `false` | If true, the source VM is **deleted** after a successful migration. Off by default for safety. |

```yaml
spec:
  source:
    vmRef:
      name: my-vsphere-vm
    createSnapshot: false
    powerOffBeforeMigration: true
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
| `diskFormat` | enum (`qcow2`, `vmdk`, `raw`) | provider native | Target disk format. The target provider converts via `qemu-img` as needed. |
| `compress` | bool | `false` | Compress during transfer. |
| `verifyChecksums` | bool | `true` | Integrity verification after import. For S3: SHA256 source vs target. For NFS: target-side `qemu-img check` (no in-stream checksum). Strongly recommended on. |
| `timeout` | `metav1.Duration` | `4h` | Hard upper bound on the entire migration. |
| `retryPolicy` | `MigrationRetryPolicy` | see below | Retry policy for individual phase failures. |
| `cleanupPolicy` | enum (`Always`, `OnSuccess`, `Never`) | `OnSuccess` | When to clean up intermediate staging objects/files/PVCs. |
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
| `checkChecksum` | bool | `true` | SHA256 comparison (S3) or target-side `qemu-img check` (NFS). |
| `checkBoot` | bool | `false` | Power on the target and confirm boot. Opt-in. |
| `checkConnectivity` | bool | `false` | Network reachability test against the target. Opt-in. |

### `spec.storage` (`MigrationStorage`, required-in-practice)

Where the disk data lives between export and import.
Defined at `vmmigration_types.go:210-220`.

The `type` field selects the staging backend. Exactly one of the `pvc`, `nfs`,
or `s3` sub-blocks must match the selected `type` (webhook-enforced).

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `type` | enum (`pvc`, `nfs`, `s3`) | `pvc` | Staging backend. `pvc` is the compatibility path; `nfs` and `s3` are the recommended backends as of v0.3.11. |
| `transferMode` | enum (`auto`, `relay`, `direct`) | `auto` | Transfer mode hint. For `s3`: `auto` and `relay` are equivalent (pod-side relay is the only implemented mode; `direct` is roadmap). For `nfs`: this field is informational — the transport is qemu-img, not pod-mediated; the controller exempts NFS from the relay gate. |
| `pvc` | `PVCStorageConfig` | required when `type=pvc` | See [storage.pvc](#storagepvc-pvcstorageconfig-compat-only). |
| `nfs` | `NFSStorageConfig` | required when `type=nfs` | See [storage.nfs](#storagenfs-nfsstorageconfig). |
| `s3` | `S3StorageConfig` | required when `type=s3` | See [storage.s3](#storages3-s3storageconfig). |

#### `storage.nfs` (`NFSStorageConfig`)

Defined at `vmmigration_types.go` (added in ADR-0006 Slice 4).

```yaml
spec:
  storage:
    type: nfs
    nfs:
      server: 172.16.56.13
      export: /export/virtrigaud
      uid: 1000
      gid: 1000
    transferMode: auto
```

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `server` | string | required | Hostname or IP of the NFS server. SSRF-checked against `--migration-storage-allowed-hosts`; loopback and link-local are always rejected. |
| `export` | string | required | Absolute export path on the server, e.g. `/export/virtrigaud`. |
| `path` | string | unset | Subpath under the export. Omit to use the export root (recommended — the staged object is a flat file; nested paths require the directory to exist on the server). |
| `uid` | `*int64` (0–4294967295) | unset | Numeric uid the NFS client presents via AUTH_SYS. Effectively mandatory for cross-provider migrations: each provider runs qemu-img as a different identity; set to the uid that owns the export files. |
| `gid` | `*int64` (0–4294967295) | unset | Numeric gid the NFS client presents via AUTH_SYS. Same constraint as `uid`. |
| `readOnly` | bool | `false` | Mount read-only. Not useful for migration (the source leg must write). |

!!! warning "uid/gid are pointer types — omitting them is meaningful"
    In the Go type, `uid` and `gid` are `*int64`. An unset field means "present
    the process's own uid/gid to the NFS server", not `0`. For cross-provider
    migrations where each provider runs as a different OS user, omitting both
    fields typically results in `NFS3ERR_ACCES` on at least one leg.

!!! danger "NFSv3 AUTH_SYS: no Kerberos, no encryption"
    The disk bytes travel over the network **unencrypted**. The uid/gid is
    asserted, not authenticated. Operate on a trusted network segment;
    keep `root_squash` on the export; use one export per tenant.
    For encrypted-in-transit requirements, use the S3 backend with a
    TLS-terminated endpoint.

**NFS per-provider transport mechanisms:**

| Provider | How qemu-img reaches the NFS export |
|---------|-------------------------------------|
| **libvirt** | The libvirt **host** runs `qemu-img` against `nfs://<server>/<export>/<file>` using the **libnfs** userspace driver. No kernel mount; no pod relay. |
| **vSphere** | The provider **pod** runs `qemu-img` against `nfs://` via libnfs. The vSphere provider image ships the Debian `qemu-block-extra` package which provides `block-nfs.so`. |
| **Proxmox** | The PVE **node** kernel-mounts the export (the node's native kernel NFS client, same mechanism PVE uses for NFS storage pools). `pve-qemu-kvm` has no libnfs driver — `qemu-img nfs://` fails with `Unknown protocol 'nfs'` on a PVE node. The provider uses `setpriv` to present the configured `uid`/`gid` when running `qemu-img` against the mount. |

**Staged object naming** (flat file in export root or `path` subdir):

```text
vmmigrations-<namespace>-<migration-name>-<stage>.qcow2
```

NFS cannot auto-create directories the way S3 key prefixes do. One export per
tenant keeps staged objects from colliding.

#### `storage.s3` (`S3StorageConfig`)

Defined at `vmmigration_types.go` (added in ADR-0006 Slices 1–3).

```yaml
spec:
  storage:
    type: s3
    transferMode: relay
    s3:
      bucket: virtrigaud
      endpoint: http://minio.example:9000   # omit for AWS S3
      region: us-east-1
      usePathStyle: true                    # true for MinIO/Ceph/rustfs; false for AWS
      credentialsSecretRef:
        name: s3-migration-credentials
```

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `bucket` | string | required | S3 bucket name. |
| `endpoint` | string | unset | S3 endpoint URL. Omit for AWS S3. Required for MinIO, Ceph RGW, rustfs, and other S3-compatible stores. SSRF-checked against `--migration-storage-allowed-hosts`. |
| `region` | string | required | AWS region string (e.g. `us-east-1`). Required even for non-AWS endpoints. |
| `prefix` | string | unset | Key prefix for staged objects (e.g. `migrations/`). |
| `usePathStyle` | bool | `false` | Set `true` for MinIO, Ceph RGW, rustfs, and other path-style endpoints. Set `false` for AWS S3 (virtual-hosted-style). |
| `credentialsSecretRef.name` | string | required | Name of a `Secret` in the same namespace as the `VMMigration`. Keys: `accessKeyID`, `secretAccessKey`, optional `sessionToken`. **Never inline credentials in the CR.** |

The provider pod is the S3 client. Bytes flow: source host → source pod → S3 →
target pod → target host. `transferMode: auto` resolves to `relay` (the only
implemented mode; `direct` is roadmap).

**S3 credentials Secret shape:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: s3-migration-credentials
  namespace: default
type: Opaque
stringData:
  accessKeyID: <your-access-key>
  secretAccessKey: <your-secret-key>
  # sessionToken: <optional>
```

#### `storage.pvc` (`PVCStorageConfig`, compat-only)

Retained from v0.3.8. Mounts a `ReadWriteMany` PVC into both provider pods.
No longer the recommended path. Use `nfs` or `s3` for new migrations.
Defined at `vmmigration_types.go:222-250`.

```yaml
spec:
  storage:
    type: pvc
    pvc:
      storageClassName: nfs-client
      size: 100Gi
      accessMode: ReadWriteMany
```

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `name` | string | unset | Name of an existing PVC to reuse. If unset, the controller creates a temporary PVC owned by the `VMMigration` (auto-cleanup on deletion). |
| `storageClassName` | string | required when `name` is unset | StorageClass for the auto-created PVC. |
| `size` | string (`100Gi`-style) | required when `name` is unset | Capacity for the auto-created PVC. Pattern: `^[0-9]+(\\.[0-9]+)?(Ei?|Pi?|Ti?|Gi?|Mi?|Ki?)$`. Size at **1.5×–2× the source disk** to accommodate sibling conversion files. |
| `accessMode` | enum (`ReadWriteOnce`, `ReadWriteMany`, `ReadOnlyMany`) | `ReadWriteMany` | RWX required unless both providers run on the same node. |
| `mountPath` | string | `/mnt/migration-storage` | Path inside provider pods where the PVC is mounted. |

!!! note "Provider controller no longer deletes the migration PVC (v0.3.8+)"
    Since v0.3.8 ([#184](https://github.com/projectbeskar/virtrigaud/pull/184))
    the `ProviderReconciler` **no longer deletes migration-storage PVCs** and
    watches them. Previously a provider reconcile could race the PVC's lifecycle
    and reclaim the transfer medium out from under an in-flight migration.

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
| `storageInfo` | `MigrationStorageInfo` | Staging URL, size, upload time, cleanup state. |
| `storagePVCName` | string | Name of the PVC created or reused (PVC mode only). |
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
| `sourceChecksum` | string | SHA256 measured at source (S3 backend; NFS uses target-side check). |
| `targetChecksum` | string | SHA256 measured at target after import. |

### `status.storageInfo` (`MigrationStorageInfo`)

Defined at `vmmigration_types.go:460-477`.

| Field | Type | Notes |
|-------|------|-------|
| `url` | string | Reference to the staged object. Format depends on backend: `s3://<bucket>/<key>` for S3; a path-style NFS reference for NFS; `pvc://<pvc-name>/<file>` for PVC compat mode. |
| `size` | `resource.Quantity` | Bytes written to the staging backend. |
| `uploadedAt` | `metav1.Time` | When the export finished writing. |
| `cleanedUp` | bool | Whether the intermediate staged object (and PVC if owned) was deleted. |

### `status.validationResults` (`ValidationResults`)

Defined at `vmmigration_types.go:479-500`.

| Field | Type | Notes |
|-------|------|-------|
| `diskSizeMatch` | *bool | Result of `validationChecks.checkDiskSize`. |
| `checksumMatch` | *bool | SHA256 match (S3) or target-side integrity check (NFS). |
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
| `Validating` | `MigrationPhaseValidating` | Source VM, target provider, and storage config validated. For S3/NFS: staging backend reachability checked and SSRF-gated. For PVC mode: PVC created/reused; provider pods restarted with the PVC mount. |
| `Snapshotting` | `MigrationPhaseSnapshotting` | Source VM snapshot is being created (unless `snapshotRef` was supplied). |
| `Exporting` | `MigrationPhaseExporting` | Source provider writes the disk to the staging backend. |
| `Transferring` | `MigrationPhaseTransferring` | Data is being staged. For S3/NFS this is part of `Exporting`; the controller may not always set this phase explicitly. |
| `Converting` | `MigrationPhaseConverting` | Target provider converts between formats (`vmdk` → `qcow2`, etc.). Skipped if formats match. |
| `Importing` | `MigrationPhaseImporting` | Target provider reads the staged disk and registers it. |
| `Creating` | `MigrationPhaseCreating` | Target `VirtualMachine` resource is created. |
| `Validating-Target` | `MigrationPhaseValidatingTarget` | Post-create validation per `validationChecks`. |
| `Ready` | `MigrationPhaseReady` | Migration successful. Target VM exists and is independent of the `VMMigration` CR. |
| `Failed` | `MigrationPhaseFailed` | Terminal failure. Retries (per `options.retryPolicy`) recycle the phase machine from `Pending`. |

### Important behavior

- **Once `Ready`, the target `VirtualMachine` is fully independent.** Deleting
  the `VMMigration` CR does **not** delete the target VM. The controller
  marks the target VM with annotations
  `virtrigaud.io/migration-completed="true"` and
  `virtrigaud.io/migration-completed-at=<RFC3339>`.
- **Failed migrations clean up their partial target VM** during finalizer
  processing. The check at `vmmigration_controller.go:1257` only deletes the
  target VM if `phase=Failed`.
- **Staged objects (S3/NFS) are cleaned up per `options.cleanupPolicy`.** The
  controller's cleanup pass runs at the end of a successful or failed migration.
  The finalizer (`vmmigration.infra.virtrigaud.io/cleanup`) also runs cleanup on
  CR deletion.

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
| `Transferring` | `Transferring` | Disk being staged on the backend. |
| `Importing` | `Importing` | Phase 5. |
| `Failed` | `SourceNotFound`, `ProviderError`, `StorageError`, `ValidationFailed`, `Timeout` | Terminal failure. |

## Complete example (NFS)

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMMigration
metadata:
  name: app-libvirt-to-vsphere-nfs
  namespace: applications
  labels:
    app: my-app
    env: prod
spec:
  source:
    vmRef:
      name: app-on-libvirt
    createSnapshot: false
    powerOffBeforeMigration: true
    deleteAfterMigration: false

  target:
    name: app-on-vsphere
    namespace: applications
    providerRef:
      name: vsphere-prod
      namespace: virtrigaud-system
    classRef:
      name: standard-2cpu-4gb
    networks:
      - name: primary
        networkRef:
          name: vm-network
    powerOn: false

  options:
    verifyChecksums: true
    timeout: 1h
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
    type: nfs
    nfs:
      server: 172.16.56.13
      export: /export/virtrigaud
      uid: 1000
      gid: 1000
    transferMode: auto

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
  startTime: "2026-06-21T10:00:00Z"
  completionTime: "2026-06-21T10:43:12Z"
  storageInfo:
    url: nfs://172.16.56.13/export/virtrigaud/vmmigrations-applications-app-libvirt-to-vsphere-nfs-export.qcow2
    size: 50Gi
    uploadedAt: "2026-06-21T10:38:44Z"
    cleanedUp: true
  targetVMRef:
    name: app-on-vsphere
  progress:
    currentPhase: Ready
    percentage: 100
    totalBytes: 53687091200
    transferredBytes: 53687091200
  diskInfo:
    sourceDiskID: libvirt-vol-app-on-libvirt-disk
    sourceFormat: qcow2
    sourceSize: 50Gi
    targetDiskID: vsphere-disk-1
    targetFormat: vmdk
    targetSize: 50Gi
    targetChecksum: sha256:abc...
  validationResults:
    diskSizeMatch: true
    checksumMatch: true
  conditions:
    - type: Ready
      status: "True"
      reason: Completed
      message: Migration completed successfully
      lastTransitionTime: "2026-06-21T10:43:12Z"
```

## Complete example (S3)

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMMigration
metadata:
  name: app-vm-vsphere-to-libvirt
  namespace: applications
spec:
  source:
    vmRef:
      name: app-vm-vsphere
    createSnapshot: true
    powerOffBeforeMigration: true
    deleteAfterMigration: false

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
    powerOn: false

  options:
    diskFormat: qcow2
    verifyChecksums: true
    timeout: 4h
    cleanupPolicy: OnSuccess

  storage:
    type: s3
    transferMode: relay
    s3:
      bucket: virtrigaud
      endpoint: http://minio.example:9000
      region: us-east-1
      usePathStyle: true
      credentialsSecretRef:
        name: s3-migration-credentials

status:
  phase: Ready
  storageInfo:
    url: s3://virtrigaud/vmmigrations-applications-app-vm-vsphere-to-libvirt/disk.qcow2
    size: 50Gi
    cleanedUp: true
```

## Finalizer

The controller owns the finalizer
`vmmigration.infra.virtrigaud.io/cleanup` (visible in
`metadata.finalizers`). On delete it:

1. Cleans up the staged object on S3 or NFS (or intermediate PVC for compat
   mode) if not already gone (`vmmigration_controller.go:1222-1240`).
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
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get"]                        # required to read S3 credentialsSecretRef
```

The controller itself (`virtrigaud-manager`) needs **broader** RBAC to
mutate Provider CR annotations (PVC mode) and create PVCs; that is part of
the manager ServiceAccount baked into the Helm chart.

## See also

- [VM Migration User Guide](user-guide.md) — operator-facing how-to.
- [VM Migration Guide](vm-migration-guide.md) — architectural deep dive.
- [Full CRD Reference](../references/generated-crd-docs.md#vmmigration) —
  generated CRD field reference.
- [Resilience](../operations/resilience.md) — how the CircuitBreaker
  interacts with the many provider RPCs a migration issues.
- [ADR-0006](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0006-storage-backend-agnostic-cross-hypervisor-migration.md) —
  design rationale for storage-backend-agnostic migration.
