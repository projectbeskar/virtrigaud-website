<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VMMigration API Reference

This page is aligned to **VirtRigaud v0.4.0** and reflects the
`infra.virtrigaud.io/v1beta1` `VMMigration` CRD and its controller as they ship.
The authoritative sources are the Go types at
`api/infra.virtrigaud.io/v1beta1/vmmigration_types.go` and the controller in
`internal/controller/vmmigration_*.go`. For the generated field list see the
[Full CRD Reference](../references/generated-crd-docs.md#vmmigration).

!!! info "What v0.4.0 supports"
    `VMMigration` moves a VM's **primary disk** between `vsphere`, `libvirt` and
    `proxmox` providers, staged on an `s3` or `nfs` backend (`pvc` is the legacy
    compatibility path, see [storage.pvc](#storagepvc-pvcstorageconfig-compat-only)).
    A libvirt Provider with `topology: cluster` is also a target
    (**experimental**, `s3` and `nfs` only). The
    [User Guide](user-guide.md#what-virtrigaud-v040-supports) lists which
    directions and backends were validated in a lab and which were not.

!!! warning "Fields in the schema that the v0.4.0 controller does not use"
    Several fields exist in the CRD but nothing reads or writes them in v0.4.0.
    Setting them has no effect, and the status fields stay empty:

    - **Spec:** `options.validationChecks.*` (no post-import check runs, so
      `checkBoot` and `checkConnectivity` do nothing), `target.imageRef`,
      `target.disks[]`, and `metadata.*` (labels for people and tooling only).
    - **Status:** `targetVMRef`, `snapshotRef`, `progress.*` (the `Progress` printer
      column is always empty), `validationResults.*`, `diskInfo.checksum`, and
      `storageInfo.url`, `storageInfo.size` and `storageInfo.uploadedAt`.

    They are listed below so that you can recognise them. Use `status.phase`,
    `status.message` and `status.conditions` to follow a migration.

<a id="capability-gating-176-fail-close-on-providers-lacking-exportimport"></a>

### Capability gating: fail closed on providers lacking export/import

The manager flag `--enforce-provider-capabilities` (default **off**) makes the
export and import phases check the live `GetCapabilities` answer of the source and
target provider. A provider that reports it cannot export (or import) disks fails
the migration before the RPC is sent (`Failed`, message "Source provider does not
support disk export" / "Target provider does not support disk import"). The check
fails open: a provider that does not report capabilities, or whose capability query
fails, is not blocked.

This is separate from the **backend** check that always runs at `Validating`: the
source's advertised `supportedExportBackends` and the target's
`supportedImportBackends` (in `Provider.status.reportedCapabilities`) must both list
the requested `storage.type`, otherwise the migration fails with
`storage backend "<type>" not supported by source provider ...`.

The Helm chart in v0.4.0 has no value for `--enforce-provider-capabilities` or for
`--migration-storage-allowed-hosts`. Add them to the manager Deployment's
arguments yourself (for example with a Helm post-renderer or a kustomize patch).

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
  storage:               # MigrationStorage (optional in the schema; required in practice)
  metadata:              # MigrationMetadata (optional, informational)
status:
  # ... fields below
```

`vmmig` is the registered short name (`kubectl get vmmig`). The resource is
namespaced, and every reference in `spec.source` is local to the migration's
namespace.

### Printer columns

| Column   | JSONPath                              | Note |
|----------|---------------------------------------|------|
| Source   | `.spec.source.vmRef.name`             | |
| Target   | `.spec.target.name`                   | |
| Phase    | `.status.phase`                       | |
| Progress | `.status.progress.percentage`         | Always empty in v0.4.0 (not written). |
| Age      | `.metadata.creationTimestamp`         | |

## Spec

### `spec.source` (`MigrationSource`, required)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `vmRef.name` | string | required | Name of the source `VirtualMachine`, in the migration's namespace. It must have a provider ID (`status.id`); until then `Validating` waits (`SourceVMNotReady`). |
| `providerRef` | `ObjectRef` | the source VM's Provider | Optional. **Must name the Provider the source VM runs on** (its `spec.providerRef`; an empty namespace means the VM's namespace). Any other Provider fails the migration, because it would export an unrelated VM that happens to share the source's provider ID. Leave it empty. |
| `snapshotRef.name` | string | unset | Skips snapshot creation, but only while `createSnapshot` is `true` (the default): with `createSnapshot: false` the `snapshotRef` is not read and the export has no snapshot. The controller passes this name to the source provider **as the provider-side snapshot ID**; it does not look up a `VMSnapshot` object. The migration never deletes a snapshot named here. |
| `createSnapshot` | bool | `true` | Create a snapshot of the source before exporting (the `Snapshotting` phase uses `snapshotRef` instead when it is set). Set `false` to export without a snapshot (typical with `powerOffBeforeMigration`); a `snapshotRef` is then ignored. |
| `powerOffBeforeMigration` | bool | `false` | Set the source `VirtualMachine`'s `spec.powerState` to `Off` and wait until the provider reports it `Off`. **Required for a vSphere source** (a running VM's disk is locked). The migration never powers the source back on. |
| `deleteAfterMigration` | bool | `false` | After `Ready`, delete the source `VirtualMachine` (and so, through its own finalizer, the hypervisor VM). Only the object the migration validated is deleted (UID precondition on `status.sourceVMUID`). Not run for a failed migration. |

```yaml
spec:
  source:
    vmRef:
      name: my-vsphere-vm
    createSnapshot: false
    powerOffBeforeMigration: true
    deleteAfterMigration: false
```

!!! note "Only the primary disk is migrated"
    The controller sends one `ExportDisk` with an empty disk ID, which each provider
    resolves to the VM's primary (first, bootable) disk, and records one imported
    disk on the target. Additional disks are not migrated in v0.4.0.

### `spec.target` (`MigrationTarget`, required)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | required | Name of the target `VirtualMachine`. Pattern `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`, max 253. **A VirtualMachine with this name that the migration did not create fails the migration** (`TargetVMNotOwned`), see [Target VM ownership](#target-vm-ownership). |
| `namespace` | string | the migration's namespace | Namespace of the target VM (max 63). Another namespace needs a grant: the **Namespace object** must carry the annotation `infra.virtrigaud.io/allowed-source-namespaces` listing the migration's namespace. See [Cross-namespace targets](#cross-namespace-targets). |
| `providerRef` | `ObjectRef` | required | Target `Provider`. A Provider in another namespace must allow the migration's namespace through its `spec.consumerNamespaceSelector`, otherwise the migration waits with `ConsumerNotAllowed`. |
| `classRef.name` | string | unset | `VMClass` of the target VM, looked up in the **migration's** namespace. Optional in this schema, but `VirtualMachine.spec.classRef` is required, so always set it. |
| `networks[]` | `[]VMNetworkRef` | unset | Network attachments copied to the target VM (up to 10). A vSphere target needs a `networkRef` to a `VMNetworkAttachment`, or the VM has no NIC. |
| `placementRef.name` | string | unset | `VMPlacementPolicy` copied to the target VM (used by a clustered target). |
| `powerOn` | bool | `false` | `true` creates the target with `spec.powerState: On`; the default creates it `Off` and it stays off. |
| `labels` | map | unset | Labels for the target VM (up to 50). Reserved keys (`virtrigaud.io/adopted`) are dropped with a Normal event `TargetLabelsDropped`. |
| `annotations` | map | unset | Annotations for the target VM (up to 50). Keys in the `virtrigaud.io` domain (`virtrigaud.io/...`, `*.virtrigaud.io/...`) are not copied; the controller writes its own provenance annotations. |
| `imageRef`, `disks[]` | | | **Not used** by the controller (the imported disk replaces image-based provisioning). |

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

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `diskFormat` | `qcow2`, `vmdk`, `raw` | `qcow2` | Format hint passed to the source provider's `ExportDisk`. The staged object is the source provider's native flattened format for `s3` (`vmdk` from vSphere, `qcow2` from libvirt and Proxmox) and always `qcow2` for `nfs`; the **target provider** converts on import. |
| `compress` | bool | `false` | Asks the source provider to compress the export. Honoured for `qcow2` by providers that advertise export compression. |
| `verifyChecksums` | bool | `true` | The import verifies the checksum the export reported. On `s3` that is an end-to-end SHA-256. On `nfs` no byte checksum exists (`qemu-img` computes none): integrity rests on the target's `qemu-img` check of the converted image. |
| `timeout` | duration | `4h` in the schema | In v0.4.0 it **only bounds the wait for a source snapshot task**. It is not a limit on the whole migration. The schema defaults it to `4h` whenever `options` exists; the 2 h built-in default applies only when `options` is omitted. Each `ExportDisk` and `ImportDisk` call has its own 30-minute deadline in the manager's gRPC client. |
| `retryPolicy` | `MigrationRetryPolicy` | unset | **Without a `retryPolicy` a failed migration is final.** See [Retry](#retry). |
| `cleanupPolicy` | `Always`, `OnSuccess`, `Never` | `OnSuccess` | What happens to the staged disk, the landed disk, the source snapshot and the PVC. See [Cleanup](#cleanup). |
| `validationChecks` | | | **Not used.** |

#### `options.retryPolicy` (`MigrationRetryPolicy`)

| Field | Type | Default | Bounds |
|-------|------|---------|--------|
| `maxRetries` | int32 | `3` | 0-10 |
| `retryDelay` | duration | `5m` | |
| `backoffMultiplier` | int32 | `2` | 1-10 |

The defaults apply once a `retryPolicy` object exists (`retryPolicy: {}` is enough).

### `spec.storage` (`MigrationStorage`, required in practice)

The schema marks `storage.type` as required with default `pvc`, but `spec.storage`
itself is optional. A migration without it passes `Validating` as a `pvc` migration and
then fails at `Exporting` ("storage configuration is required for migration"). Always
set it. There is no VMMigration admission webhook: the controller checks the
sub-block that matches `type` at `Validating` and fails with a message such as
`s3 configuration is required when using s3 storage type`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `type` | `pvc`, `nfs`, `s3` | `pvc` | Staging backend. Use `s3` or `nfs`. |
| `transferMode` | `auto`, `relay`, `direct` | `auto` | `auto` resolves to `relay`. For `s3` and `pvc` an explicit `direct` fails at `Validating` ("not yet implemented"). For `nfs` the field is informational (`qemu-img` moves the bytes) and is exempt from the check. |
| `pvc` | `PVCStorageConfig` | | Required when `type: pvc`. |
| `nfs` | `NFSStorageConfig` | | Required when `type: nfs`. |
| `s3` | `S3StorageConfig` | | Required when `type: s3`. |

The source provider must advertise the backend as an export backend and the target
provider as an import backend:

| Provider | Export backends | Import backends |
|----------|-----------------|-----------------|
| vSphere | `pvc`, `s3`, `nfs` | `pvc`, `s3`, `nfs` |
| libvirt (single host) | `pvc`, `s3`, `nfs` | `pvc`, `s3`, `nfs` |
| libvirt (`topology: cluster`) | `s3`, `nfs` | `s3`, `nfs` (as a target, routed to one host) |
| Proxmox | `s3`, `nfs` | `s3`, `nfs` (`pvc` is not advertised: PVE disks are on the node, out of reach of a pod-mounted PVC) |

#### `storage.nfs` (`NFSStorageConfig`)

```yaml
spec:
  storage:
    type: nfs
    nfs:
      server: nfs.example.com
      export: /export/virtrigaud
      uid: 1000
      gid: 1000
```

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `server` | string (max 253) | required | Hostname or IP of the NFS server. Checked against the SSRF policy (`--migration-storage-allowed-hosts`) at `Validating`; loopback, link-local, metadata and multicast addresses are always refused. |
| `export` | string (max 4096) | required | Exported path on the server, e.g. `/export/virtrigaud`. |
| `path` | string (max 4096) | unset | Sub-path under the export. It must already exist: NFS clients here cannot create directories. Omit to use the export root. |
| `uid` | int64 (0-4294967295) | unset | AUTH_SYS uid the data plane presents. Effectively mandatory for cross-provider migrations. **`0` is refused** (see below). |
| `gid` | int64 (0-4294967295) | unset | AUTH_SYS gid, same rules as `uid`. |
| `readOnly` | bool | `false` | Not useful for migration (the export must write). |

!!! warning "`uid: 0` and `gid: 0` are refused"
    A migration with `spec.storage.nfs.uid` or `gid` set to `0` fails at `Validating`
    for every provider type (`Validating=False`, reason
    `NFSRootIdentityNotAllowed`), before anything is read or done: on an export
    without `root_squash`, that identity is root. Use a dedicated non-zero uid/gid
    that owns the export, or leave both unset. The providers refuse `0` too.

!!! warning "uid/gid are pointers: unset is not 0"
    Unset means "present the data-plane process's own identity" (the libvirt SSH
    user, the vSphere pod's uid 65532, root on the Proxmox node). For a
    cross-provider migration that usually ends in `NFS3ERR_ACCES` on one leg.

!!! danger "NFSv3 AUTH_SYS: no Kerberos, no encryption"
    The disk bytes cross the network unencrypted and the uid/gid is asserted, not
    authenticated. Use a trusted network, keep `root_squash` on, use one export per
    tenant, and exclude the export from server-side snapshots. For encryption in
    transit use `s3` over TLS.

| Provider | How `qemu-img` reaches the export |
|----------|-----------------------------------|
| libvirt | The libvirt **host** runs `qemu-img` against `nfs://` through the libnfs driver (over SSH). |
| vSphere | The provider **pod** runs `qemu-img` against `nfs://` (the image ships Debian `qemu-block-extra`). |
| Proxmox | The PVE **node** mounts the export with its kernel NFS client (`nosymfollow,nosuid,nodev,noexec`) and runs `qemu-img` against the mount, presenting the uid/gid with `setpriv`. `pve-qemu-kvm` has no libnfs. |

**Staged object name.** A single flat file in the export root (or in `path`):

| Layout | Name | Used by |
|--------|------|---------|
| `v2` | `vmmigrations_<namespace>_<name>_export.qcow2` | every migration that stages under v0.4.0 |
| `v1` | `vmmigrations-<namespace>-<name>-export.qcow2` | a migration an older manager already staged; it keeps the name for its import and its delete |

The layout is recorded in `status.storageInfo.stagingLayout`. `v1` was ambiguous
across namespaces (namespace `team-prod` with migration `db` and namespace `team`
with migration `prod-db` named the same file), which is why `v2` uses `_`.

#### `storage.s3` (`S3StorageConfig`)

```yaml
spec:
  storage:
    type: s3
    transferMode: relay
    s3:
      bucket: virtrigaud
      endpoint: https://s3.example.com   # omit for AWS S3
      region: us-east-1
      usePathStyle: true                 # true for most non-AWS stores
      credentialsSecretRef:
        name: s3-migration-credentials
```

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `bucket` | string | required | Bucket name. |
| `endpoint` | string (max 263) | unset | Empty means the AWS default. Checked against the SSRF policy at `Validating`. |
| `region` | string | unset | Optional in the schema (empty means the SDK default). Set it for AWS. |
| `prefix` | string | unset | Key prefix. |
| `usePathStyle` | bool | `false` | `true` for MinIO, Ceph RGW and most other non-AWS stores. |
| `credentialsSecretRef.name` | string | required | A Secret **in the migration's namespace** (any `namespace` on the reference is ignored). Keys `accessKeyID` and `secretAccessKey`, optional `sessionToken`. The manager reads it; migration authors do not need `get` on Secrets. |

**Staged object key** (the same in every layout): `[<prefix>/]vmmigrations/<namespace>/<name>/export.vmdk`.
The `.vmdk` suffix is only the name; the content is the source provider's native
format. Whatever prefix is set, the key always ends with the migration's own
namespace and name. The credentials need `s3:GetObject` (for the stat) and
`s3:DeleteObject` on the `vmmigrations/` prefix, besides write access.

The provider **pod** is the S3 client: source host to source pod to bucket to target
pod to target host. `auto` resolves to `relay`, the only implemented mode.

<a id="storagepvc-pvcstorageconfig-compat-only"></a>

#### `storage.pvc` (`PVCStorageConfig`, compat-only)

Retained for vSphere and libvirt (single host) clusters that already use it. Not
supported with Proxmox, with a clustered libvirt source or target, or across
namespaces: the migration and **both Providers must be in one namespace** (a pod
mounts PVCs of its own namespace only), otherwise the migration fails at
`Validating`.

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
| `name` | string | unset | An existing PVC to use. It **must carry the label `virtrigaud.io/component=migration-storage`** and must not belong to another `VMMigration`. If unset the controller creates `<migration-name>-storage`. |
| `storageClassName` | string | required when `name` is unset | StorageClass of the auto-created PVC. |
| `size` | string | required when `name` is unset | Capacity, e.g. `100Gi`. Size it at 1.5x to 2x the source disk. |
| `accessMode` | `ReadWriteOnce`, `ReadWriteMany`, `ReadOnlyMany` | `ReadWriteMany` | RWX unless both provider pods run on one node. |
| `mountPath` | string | `/mnt/migration-storage` | Schema default; the providers mount PVCs at `/mnt/migration-storage/<pvc-name>`. |

**What the provider pods mount.** Provider pods hold hypervisor credentials, so a
PVC is mounted only when all of these hold: a `VMMigration` in the Provider's
namespace records it in `status.storagePVCName` and is still in flight; the PVC has
the label and is `Bound` (a `Pending` one only while the migration validates, on a
`WaitForFirstConsumer` StorageClass); and it is either the PVC the migration
created (identified by the UID in `status.storagePVCUID`, not by an
`ownerReference`) or the one `storage.pvc.name` names. Only the source and target
Providers of that migration mount it: the source read-write, the target
**read-only**. A mount that does not work within 5 minutes fails the migration.
The provider pods are rolled when a PVC is mounted and again when it is released
(`Ready`, final failure or deletion), which interrupts other migrations running
through the same Provider. Deleting the migration deletes only the PVC it created;
a PVC named in `storage.pvc.name` is unmounted and left for its owner (event
`MigrationPVCRetained`).

Staged files on the PVC are opened with no symbolic link followed; only a regular
file with a single hard link is read (a PVC filesystem that reports another link
count is refused). See the main repository's
[PVC staging notes](https://github.com/projectbeskar/virtrigaud/blob/main/examples/migration/README.md#pvc-staging-backend-legacy-what-the-provider-pods-mount).

### `spec.metadata` (`MigrationMetadata`, optional)

Tags for people and tooling. The controller does not read them.

| Field | Type | Allowed values |
|-------|------|---------------|
| `purpose` | enum | `disaster-recovery`, `cloud-migration`, `provider-change`, `testing`, `maintenance` |
| `createdBy` | string (max 255) | |
| `project` | string (max 255) | |
| `environment` | enum | `dev`, `staging`, `prod`, `test`, `qa`, `uat` |
| `tags` | map (max 50) | |

## Target VM ownership

A `VMMigration` acts only on the `VirtualMachine` **it created**. This is a security
control (v0.4.0, breaking): before, any VM with the target's name was taken as the
migration's own, and someone with `create` rights in the target namespace could plant
one.

- Just before creating the target, the controller writes `status.targetVMClaim` (the
  SHA-256 digest of a one-time random token); the token itself is set only on the VM
  it creates, as the annotation `virtrigaud.io/migration-claim`. No `Create` is sent
  unless that write succeeds.
- When the `Create` succeeds the controller records the UID the API server returned in
  `status.targetVMUID`. From then on only the VM with that UID is the target: waiting
  for it, validating it, marking it `migration-completed`, and deleting a partial one
  (with a UID precondition).
- If the `Create` succeeded but the UID write was lost (a conflict, a manager restart),
  the next reconcile finds the VM whose token hashes to the digest and records its UID.
- Any other VM under the target's name fails the migration at `Validating`, before the
  source is powered off, snapshotted or exported: `Phase=Failed`, `Ready=False` and
  `Failed=True` with reason `TargetVMNotOwned` and a constant message. That VM is never
  read into the status, annotated or deleted. `Creating` and `Validating-Target` check
  again against the API server.
- A target the migration created that disappears (or is being deleted) before the
  migration completes fails with `TargetVMGone`. It is not re-created under a new
  identity, because the landing disk most likely went with it. A retry releases the
  binding to a VM that no longer exists and creates a new one.
- A chart-installed `ValidatingAdmissionPolicy` (Kubernetes 1.30+) lets only the
  manager set `virtrigaud.io/migration`, `migration-claim`, `migrated-from`,
  `imported-disk-id`, `disk-checksum` and `migration-completed(-at)` on a
  `VirtualMachine`. See
  [Reserved keys and the admission policy](https://github.com/projectbeskar/virtrigaud/blob/main/docs/admission-policy.md).

To fix `TargetVMNotOwned`: delete or rename the other `VirtualMachine`, or pick
another `spec.target.name`, then create the migration again.

!!! warning "Upgrading with migrations in flight"
    A migration in `Creating` or `Validating-Target` when the manager is upgraded to
    v0.4.0 created its target without the UID and claim. It **fails closed with
    `TargetVMNotOwned`** and its target VM is left as it is. Let such migrations
    finish before the upgrade, or do not start new ones. For one that failed this way,
    check its target VM, delete the source yourself if you meant to
    (`deleteAfterMigration` does not run for a failed migration), and create the
    migration again. Migrations that failed before the upgrade do not delete their
    partly created target VM when deleted: remove it yourself.

    A leader-election overlap during the target `Create` can also fail a migration the
    same way (the new leader finds a claim it cannot match). It fails closed: delete the
    target VM it created and create the migration again.

## Cross-namespace targets

`spec.target.namespace` may name another namespace only if that **Namespace object**
carries a grant:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team-b
  annotations:
    # VMClones and VMMigrations in team-a and team-c may create VMs here.
    infra.virtrigaud.io/allowed-source-namespaces: "team-a, team-c"
```

The value is a comma-separated list of exact namespace names (no wildcards). Whoever can
`update` the target `Namespace` can grant, normally a cluster administrator. Without the
grant the migration is **held, not failed**: `Ready=False` (and `Validating=False`
while validating), reason `TargetNamespaceNotAllowed`, one Warning event, nothing
created in the target namespace, retry count unchanged. The manager watches the
annotation and resumes the migration when it appears, and re-checks every 5 minutes.
The grant is checked again before the import, before the target VM is created or
annotated, and before deletion, and read live from the API server right before the
import and the target `Create`, so **revoking a grant stops a migration in flight**.

Other rules for a target in another namespace:

- The disk is **not attached in place**: the target VM treats it as a base image
  (libvirt copies it, vSphere refuses the create).
- A **Proxmox** target Provider with a target in another namespace fails at
  `Validating` with `Validating=False`, reason `ProxmoxCrossNamespaceTarget`.
- A **clustered** target Provider with a target in another namespace fails with
  `ClusteredTargetUnsupported`.
- The target VM's `spec.providerRef` gets the migration's namespace when
  `target.providerRef.namespace` is empty.
- The pinned `Provider` and `VMClass` must allow the target namespace through their
  `spec.consumerNamespaceSelector`, otherwise the migration waits with
  `ConsumerNotAllowed`.

Details and the query that finds affected objects before an upgrade:
[Cross-namespace clone and migration targets](https://github.com/projectbeskar/virtrigaud/blob/main/docs/cross-namespace-targets.md).

## Cleanup

`options.cleanupPolicy` decides what the controller removes. The migration's
**target VM and the disk it uses are never removed** by a successful migration, and
deleting a `Ready` migration deletes neither.

| What | `OnSuccess` (default) | `Always` | `Never` |
|------|----------------------|----------|---------|
| Staged disk (`nfs`, `s3`) | deleted when the migration is `Ready`, and when the `VMMigration` is deleted. A migration that **failed for good** keeps it until the `VMMigration` is deleted. | also deleted when the migration fails for good | kept |
| Landed disk (import result on the target) | deleted when the `VMMigration` is deleted **and no VM uses it**; never after `Ready` | also deleted when the migration fails for good | kept |
| Source snapshot the migration created | deleted at `Ready`, on final failure and on deletion | same | kept |
| Migration-created PVC (`pvc`) | deleted with the `VMMigration` | same | same (deleted with the `VMMigration`) |

A migration with a retry still pending (`Failed`, not final) keeps everything: the retry
overwrites it. A user-supplied snapshot (`snapshotRef`) and a user-named PVC are never
deleted.

### Staged disk: `StagingCleanup` and `DeleteStagedDisk`

For `nfs` and `s3` the manager asks the **target** Provider to delete the staged
object with the `DeleteStagedDisk` RPC ([ADR-0011](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0011-migration-staging-cleanup.md)).
The manager never touches the backend itself. The provider derives the object from the
migration's namespace, name and stage and the recorded layout, so a tenant can only
cause the deletion of a staging object of a migration in its own namespace. Staged
files are never followed through links.

| `StagingCleanup` condition | Meaning |
|----------------------------|---------|
| `Unknown` / `StagedDiskMayExist` | An export was sent (recorded **before** it is sent), so an object may exist. |
| `False` / `StagingCleanupPending` | The delete could not be done yet. Retried with a backoff of 15 s doubling to 5 min; one Warning event; a deleting `VMMigration` keeps its finalizer. |
| `True` / `StagedDiskDeleted` | Deleted (or already gone). |
| `True` / `StagedDiskEmptied` | libvirt and vSphere targets reach NFS only through `qemu-img`, which cannot unlink: the data is truncated to 0 bytes and an empty file remains. Proxmox deletes the file. |
| `True` / `StagedDiskRetained` | `cleanupPolicy: Never`. |
| `True` / `StagedDiskLeftBehind` | It will not be deleted by VirtRigaud (one Warning event). Causes: the target Provider is gone, replaced or too old to support the RPC (held up to 24 hours first, so you can roll the provider), the provider refused the request, the S3 credentials Secret is gone, the host is denied by the SSRF policy, or `spec.storage` / `spec.target.providerRef` changed since the export. Remove it yourself. |

To delete a stuck `VMMigration` anyway, annotate it `virtrigaud.io/force-delete=true`;
the object is then left on the backend. The S3 delete removes the current version only:
in a versioned or object-lock bucket, expire noncurrent versions on `vmmigrations/`.
Exclude an NFS staging export from server snapshots. A `Ready` or terminally `Failed`
migration with a staged disk still to delete keeps its target `Provider` from being
deleted (the Provider in-use finalizer, ADR-0010).

### Landed disk: `LandedDiskCleanup` and `DeleteLandedDisk`

The disk the import lands on the target (vSphere `[<datastore>] <namespace>_<vm>-migrated/`,
libvirt `<default pool>/<namespace>.<vm>-migrated.qcow2`, the Proxmox import stage) is
deleted with the `DeleteLandedDisk` RPC when a migration fails for good or is deleted
before a VM uses it. The target VM and Provider UID (and the host, for a clustered
target) are recorded in `status.storageInfo.importTarget` **before** the import is sent.
The provider deletes only that VM's landing name and refuses a disk any VM uses.

| `LandedDiskCleanup` condition | Meaning |
|-------------------------------|---------|
| `Unknown` / `LandedDiskMayExist` | An import was sent. |
| `False` / `LandedDiskCleanupPending` | Delete held and retried (as for the staged disk); `virtrigaud.io/force-delete=true` releases a deleting migration. |
| `True` / `LandedDiskDeleted` | Deleted (or already gone). |
| `True` / `LandedDiskInUseByTarget` | The migration is `Ready`; the disk is the target VM's disk and is never deleted by the migration. Written in the same status write as `Phase=Ready`. |
| `True` / `LandedDiskInUse` | Kept: the migration's target VM, or a VM the provider reports, uses it. |
| `True` / `LandedDiskHandedOver` | Kept: another in-flight migration lands the same name for the same VM. |
| `True` / `LandedDiskRetained` | `cleanupPolicy: Never`. |
| `True` / `LandedDiskLeftBehind` | Not deleted (one Warning): the provider image is older than v0.4.0, the Provider is gone or replaced, the request was refused, the target namespace no longer grants the migration's namespace, or the import target was not recorded. Remove it yourself. |

The in-use checks see only the VMs of one vCenter or libvirt host: do not share the
landing datastore or the libvirt `default` pool directory with hypervisors the
Provider does not manage, and run one replica of each provider. Disks left by
migrations that failed before v0.4.0 are not touched: see
[Leftovers from earlier releases](https://github.com/projectbeskar/virtrigaud/blob/main/docs/upgrading.md#leftovers-from-earlier-releases).

### Source snapshot and source VM: `SnapshotCleanup`, `PostMigrationCleanup`

- A source snapshot the migration created is deleted at `Ready`, when the migration
  fails for good, and on deletion. While a delete cannot succeed the condition
  `SnapshotCleanup=False` / `SnapshotCleanupPending` holds a deleting migration (same
  backoff and `force-delete` release; the Warning event `SnapshotLeftOnHypervisor`
  names what was left). The Normal event `SourceSnapshotDeleted` records a final-failure
  delete.
- The status write that sets `Phase=Ready` also sets `PostMigrationCleanup=False`
  (`PostMigrationCleanupPending`). Only a migration carrying that marker deletes its
  source snapshot and (with `deleteAfterMigration`) its source VM, then sets it `True`
  (`PostMigrationCleanupComplete`). A migration completed by an older release is closed
  with `True` / `SourceDeletionSkippedPreUpgrade` and deletes nothing.
- A `deleteAfterMigration` that finds another VirtualMachine under the source's name
  (re-created since the export) deletes nothing and records the Warning event
  `SourceDeletionRefused`. With `powerOn: false` a deleted source leaves the workload
  running nowhere: the Warning event `SourceDeletedTargetNotStarted` says so.

!!! warning "Never grant `update` or `patch` on `vmmigrations/status`"
    The controller trusts the markers it writes there (`PostMigrationCleanup`,
    `StagingCleanup`, `LandedDiskCleanup`, `sourceVMUID`, `storageInfo.stagingLayout`,
    `stagingDigest`, `importTarget`) to decide what to delete. Check custom and
    aggregated roles.

## Provider calls whose outcome is unknown

Before `SnapshotCreate`, `ExportDisk` and `ImportDisk` are sent, the migration records
`SnapshotRequested`, `ExportRequested` or `ImportRequested` (`status: "True"`; the
`lastTransitionTime` is the **attempt id**). The write carries a `resourceVersion`
precondition: if it fails, nothing is sent. The result, or a definite failure (nothing
was done, or the provider refused), removes the marker in the same write.

A failure without a definite answer (a deadline, a connection dropped after the
request was written, an unclassified provider error) keeps the marker and **does not
fail the migration**. The same holds when the manager restarts or changes leader
between the call and the result write. The migration is held in its phase:

```text
Ready=False  reason: SnapshotOutcomeUnknown | ExportOutcomeUnknown | ImportOutcomeUnknown
```

with a constant message and one Warning event. What happens next:

- **Re-sent automatically** only where that cannot duplicate anything: a `SnapshotCreate`
  through a clustered Provider (adopted by request token; at most 10 re-sends, at least a
  minute apart), and an `ExportDisk` / `ImportDisk` on a backend the provider lists in
  `resend_safe_export_backends` / `resend_safe_import_backends`, **35 minutes** after the
  marker (the call's deadline is 30 minutes), at most 3 times.
- **Held for an operator** otherwise, including every single-host `SnapshotCreate` and
  any call through a provider image older than v0.4.0. Check what the call may have made
  (the snapshot named in the Warning event, the target's `-migrated` disk), remove it,
  then confirm the attempt:

```sh
ATTEMPT=$(kubectl get vmmigration <name> -n <ns> \
  -o jsonpath='{.status.conditions[?(@.type=="ExportRequested")].lastTransitionTime}')
kubectl annotate vmmigration <name> -n <ns> virtrigaud.io/operation-outcome=not-performed@$ATTEMPT
```

  (use `SnapshotRequested` or `ImportRequested` for the other calls), or delete the
  migration. A deleting migration with an unknown export waits 35 minutes before it
  deletes the staged object.

| Provider | Re-send safe export | Re-send safe import |
|----------|--------------------|--------------------|
| vSphere | `s3`, `nfs` | `s3`, `nfs` |
| libvirt (single host) | `s3` | `pvc`, `s3`, `nfs` |
| libvirt (clustered) | `s3`, `nfs` | `s3`, `nfs` |
| Proxmox | `s3` | `s3` (an `nfs` import copies to completion on the node after a cancelled call, so it is held) |

Remote host commands can outlive a cancelled call: single-host libvirt's flatten, `qemu-img convert` and `dd` run without `timeout(1)`, so an orphan can still be running after the 35-minute settle time.

Alert on migrations stuck in a phase and on the three `...OutcomeUnknown` reasons. Full
semantics, including which failures each provider treats as definite:
[Provider calls whose outcome was lost](https://github.com/projectbeskar/virtrigaud/blob/main/docs/provider-call-outcomes.md).

## Administrator disk-size limit

With the manager flag `--max-disk-size` (Helm `manager.maxDiskSize`), optionally
lowered per Provider by the annotation `infra.virtrigaud.io/max-disk-size`, a
migration that would create a disk above the limit is **held, not failed**, in its
current phase, and re-checked every 2 minutes:

- At `Validating` the source disk's real size (read-only `GetDiskInfo` through the
  source provider) and the target class are checked.
- Right before the export the size is checked again and recorded in
  `status.diskInfo.sourceSize`; right before the import that record is checked.
- The target provider enforces the limit itself on the disk it is about to land
  (`max_virtual_size_bytes`), so a staged object replaced between the export and the
  import cannot get past it.

The hold is `Validating=False`, `Exporting=False` or `Importing=False` with reason
`DiskSizeExceedsLimit`, or `DiskSizeLimitUnverifiable` when the size cannot be read (a
provider image older than v0.4.0, a Provider annotation that is not a valid quantity,
a migration exported before the limit was set, which you delete and run again, or a
target provider that does not report `supports_import_size_limit`). A Warning event of
the same reason accompanies it. Nothing is set unless the flag is given. An image or
template larger than its class is not covered by the limit. See the chart README
([Disk-size limit](https://github.com/projectbeskar/virtrigaud/blob/main/charts/virtrigaud/README.md#disk-size-limit)).

## Migration into a clustered libvirt Provider (experimental)

When the target Provider has `topology: cluster`, the migration creates its **target
VirtualMachine first**, at `Validating`, before the source is powered off, snapshotted
or exported. The ordinary scheduler places it on a host whose `default` pool has room
for the source disk; the disk is then exported and imported **on that host**
(`ImportDisk` carries `target_host_id`), recorded in the target's `spec.importedDisk`,
and the VM is created on that host with the disk attached in place. The host is
recorded in `status.storageInfo.importTarget.host`.

Requirements checked at `Validating` (before any side effect): the target Provider
reports `supports_routed_import` (`ClusteredTargetUnsupported` otherwise), the target
VM is in the migration's own namespace, and `storage.type` is `s3` or `nfs` set
explicitly (`pvc` is what an unset `spec.storage` means, and is refused). Every
possible host needs the `default` pool at `/var/lib/libvirt/images`, `qemu-img`,
`flock`, `timeout` and the cloud-init seed directory.

Extra conditions and reasons you can meet are in the [reasons table](#condition-reasons)
(`TargetPlaced`, `TargetHostUnavailable`, `LandingHostRefused`, `TargetDiskMismatch`,
...). The target is never moved off its host automatically: a host that fails after
placement is **waited for, not replaced**. The disk-space check is a filter, not a
reservation. Summary, prerequisites and limits: the
[clustered libvirt guide](../guides/clustered/index.md); every condition and what to
do about it:
[Migration into a clustered provider](https://github.com/projectbeskar/virtrigaud/blob/main/docs/clustered-provider-inventory.md#migration-into-a-clustered-provider-addendum-b).

## Status

All fields are optional; the controller fills them in as it progresses. "Not written"
means the v0.4.0 controller never sets the field.

| Field | Type | Notes |
|-------|------|-------|
| `phase` | `MigrationPhase` | See [Phase machine](#phase-machine). |
| `message` | string | Human-readable detail. Constant messages never name a path, bucket, host or provider answer. |
| `targetVMRef` | `LocalObjectReference` | Not written. Use `targetVMID` and the target VM's name. |
| `snapshotRef` | string | Not written. |
| `snapshotID` | string | Provider snapshot ID: the one the migration took, or `spec.source.snapshotRef.name`. Cleared after the migration deletes its own snapshot. |
| `sourceVMUID` | string | UID of the source `VirtualMachine` recorded at `Validating`. The only object `deleteAfterMigration` may delete. |
| `exportID` | string | Export operation ID. |
| `importID` | string | Import ID (the imported disk's ID). |
| `taskRef` | string | Current async task (snapshot, export or import) being awaited. |
| `targetVMID` | string | Provider ID of the target VM, set when it is ready. |
| `targetVMUID` | string | UID of the target VM this migration created. [Ownership](#target-vm-ownership). |
| `targetVMClaim` | string | SHA-256 digest of the claim token. Written by the controller only. |
| `startTime` | time | Set when the migration is first reconciled. |
| `completionTime` | time | Set on `Ready` and on every failure (a retry waits from it). |
| `progress` | `MigrationProgress` | Not written (see below). |
| `diskInfo` | `MigrationDiskInfo` | See below. |
| `storageInfo` | `MigrationStorageInfo` | See below. |
| `storagePVCName` | string | The PVC used (`pvc` only). |
| `storagePVCUID` | string | UID of the PVC the migration created (`pvc`, no `storage.pvc.name`). Only that PVC is mounted and deleted. |
| `conditions` | `[]metav1.Condition` | [Conditions](#condition-types). |
| `observedGeneration` | int64 | Set only when a hold condition is written or cleared (`TargetNamespaceNotAllowed`, `ConsumerNotAllowed`, `ProviderDeleting`). |
| `retryCount` | int32 | Retries done. |
| `lastRetryTime` | time | When the last retry started. |
| `validationResults` | `ValidationResults` | Not written. |

### `status.progress` (`MigrationProgress`)

Fields `currentPhase`, `totalBytes`, `transferredBytes`, `percentage`, `eta`,
`transferRate` and `phaseStartTime` exist in the schema. **None is written in
v0.4.0**, so the `Progress` column stays empty. The export and import are single
synchronous provider calls; follow `status.phase` and the provider log.

### `status.diskInfo` (`MigrationDiskInfo`)

| Field | Written | Notes |
|-------|---------|-------|
| `sourceDiskID` | at export | Empty: the primary disk. |
| `sourceFormat` | at export | The format requested from the source (default `qcow2`). |
| `sourceSize` | before export | Virtual size of the exported disk, when measured (always, while a disk-size limit applies). |
| `sourceChecksum` | at export | The export's checksum (`s3`); empty for `nfs`. |
| `targetDiskID` | at import | The imported disk's ID. |
| `targetFormat` | at import | The target's native format: `vmdk` for vSphere, `qcow2` for libvirt and Proxmox. |
| `targetPath` | at import | Provider-native path of the landed disk. The target VM attaches exactly this path (`spec.importedDisk.path`). |
| `targetChecksum` | at import | The import's checksum, when the provider reports one. |
| `targetSize` | | Not written. |
| `checksum` | | Not written (legacy). |

### `status.storageInfo` (`MigrationStorageInfo`)

| Field | Notes |
|-------|-------|
| `cleanedUp` | The post-migration source cleanup has run (set with `PostMigrationCleanup=True`). |
| `stagingLayout` | `v1` or `v2`: the naming layout of the staged nfs/s3 object, recorded when the export is sent. |
| `stagingDigest` | A digest of the backend, its non-secret options and the target Provider (namespace, name, UID). The staged-disk delete is sent only while the current spec yields the same digest; it carries no location. |
| `importTarget` | `{namespace, name, providerUID, host}`: the VirtualMachine the import was sent for, the Provider it was sent to, and for a clustered target the Host. The staged-disk and landed-disk deletes name only this, never the current `spec.target`. |
| `url`, `size`, `uploadedAt` | Not written. |

### `status.validationResults`

`diskSizeMatch`, `checksumMatch`, `bootSuccess`, `connectivitySuccess`,
`validationErrors`: not written.

## Phase machine

`MigrationPhase` values: `Pending`, `Validating`, `Snapshotting`, `Exporting`,
`Transferring`, `Converting`, `Importing`, `Creating`, `Validating-Target`, `Ready`,
`Failed`.

```text
Pending -> Validating -> Snapshotting* -> Exporting -> Importing -> Creating
                                                                       |
                                  Ready  <-  Validating-Target  <------+

   any phase --error--> Failed --(retryPolicy, after retryDelay)--> Pending
   (* skipped when createSnapshot is false or snapshotRef is set)
```

!!! note "`Transferring` and `Converting` are never entered"
    They are in the enum, and a migration found in either phase moves straight to
    `Importing`, but the controller never sets them. The export is the transfer, and
    format conversion happens inside the target provider's `ImportDisk` (phase
    `Importing`). Do not wait for them or alert on them.

| Phase | Controller handler | What happens |
|-------|--------------------|--------------|
| `Pending` | `handlePendingPhase` | Moves to `Validating` (`Validating=True/ValidationStarted`, event `ValidationStarted`). Clears `SourcePowerOff`, so a retry gets a fresh power-off budget. |
| `Validating` | `handleValidatingPhase` | In order: refuse `nfs` uid/gid 0; check the target-namespace grant; check the target name is free or the migration's own (`TargetVMNotOwned`); source VM has a provider ID; resolve the source Provider (must be the VM's own) and target Provider (consumer grants, Proxmox cross-namespace refusal); both Ready; clustered-target gate; disk-size limit; backend and transfer-mode gate; storage config and SSRF check, S3 credentials Secret readable (or, for `pvc`, create the PVC and wait for both providers to mount it, 5 min); for a clustered target create and place the target VM (`TargetPlaced`); power the source off when requested (10 min); record `sourceVMUID`; go to `Snapshotting`, or `Exporting` when no snapshot is wanted. |
| `Snapshotting` | `handleSnapshottingPhase` | Uses `snapshotRef`, or sends `SnapshotCreate` (marker first) and polls a snapshot task every 10 s, bounded by `options.timeout` (2 h when unset). Only a snapshot confirmed complete is exported. |
| `Exporting` | `handleExportingPhase` | Records `StagingCleanup=Unknown` (nfs/s3), re-checks grants and the disk-size limit, sends `ExportDisk` (marker first, 30-minute deadline) with the staging URL, and moves to `Importing`. |
| `Transferring`, `Converting` | | Never entered. |
| `Importing` | `handleImportingPhase` | Re-checks the target grant, Provider and size limit, records `importTarget` and `LandedDiskCleanup=Unknown`, sends `ImportDisk` (marker first, 30-minute deadline). The target provider converts the format, checks the staged image header and lands the disk. |
| `Creating` | `handleCreatingPhase` | Creates the target `VirtualMachine` (claim first) with `spec.importedDisk` and waits until it has a provider ID and `Ready=True`. For a clustered target the VM already exists: the landed disk is written into its `spec.importedDisk`. |
| `Validating-Target` | `handleValidatingTargetPhase` | Reads the target live, requires `Ready=True`, sets `Phase=Ready`, `Ready=True/MigrationComplete`, closes `LandedDiskCleanup`, sets `PostMigrationCleanup=False`, and annotates the target VM `virtrigaud.io/migration-completed=true` and `virtrigaud.io/migration-completed-at`. No other check runs (`validationChecks` is not used). |
| `Ready` | `handleReadyPhase` | Terminal success; the post-migration cleanup runs (staged disk, source snapshot, source VM). The target VM is independent of the `VMMigration`. |
| `Failed` | `handleFailedPhase` | Final if there is no `retryPolicy` or the retries are used up (only cleanup runs); otherwise waits and returns to `Pending`. See [Retry](#retry). |

### Retry

A failed migration is retried only if `spec.options.retryPolicy` exists. Retry *n*
waits `retryDelay x backoffMultiplier^(n-1)` after the failure it retries (capped at
30 minutes), then increments `retryCount`, sets `Failed=False/Retrying`, and restarts
from `Pending`. A clustered target created before the import and still unbound is
deleted before the retry and a fresh one is placed. When `retryCount` reaches
`maxRetries` the migration stays `Failed`, and cleans up its source snapshot, staged disk
and landed disk according to `cleanupPolicy`. Fix the cause and create a new
`VMMigration` to try again.

## Condition types

| Type | Meaning |
|------|---------|
| `Ready` | `True` / `MigrationComplete` at success. `False` carries the failure reason or a hold reason. |
| `Validating` | `True` / `ValidationStarted`, then `True` / `ValidationComplete`. `False` with the reason a validation is waiting or failed. |
| `Snapshotting` | `True` / `SnapshotSelected` (user snapshot), `SnapshotInProgress`, `SnapshotComplete`; `False` / `SnapshotFailed`, `SnapshotDiscarded`. |
| `Exporting` | `True` / `ExportComplete`; `False` with a disk-size reason. |
| `Importing` | `True` / `ImportComplete`; `False` with a disk-size reason or a routed-import hold. |
| `Transferring` | Defined, never set in practice. |
| `Failed` | `True` with the failure reason; `False` / `Retrying` when a retry starts. |
| `SourcePowerOff` | `False` / `WaitingForSourcePowerOff`, `True` / `SourcePoweredOff`. |
| `SnapshotRequested`, `ExportRequested`, `ImportRequested` | Markers: a provider call was sent and its result is not recorded. |
| `SnapshotCleanup`, `StagingCleanup`, `LandedDiskCleanup`, `PostMigrationCleanup` | Cleanup tracking, see [Cleanup](#cleanup). |
| `TargetPlaced` | Clustered target only: `True` / `TargetPlaced`; `False` with the target's placement reason. |

<a id="condition-reasons"></a>

### Reasons you can meet

Failure reasons (`Failed=True` and `Ready=False`, and a Warning event of the same
reason). The generic one is `MigrationFailed`; the message says why.

| Reason | Meaning |
|--------|---------|
| `MigrationFailed` | Any failure without a more specific reason: source VM or provider not found, backend or transfer mode not supported, invalid storage configuration, mount timeout, source not powered off within 10 minutes, provider call refused, export or import failed, target `Create` failed, and so on. Read `status.message`. |
| `TargetVMNotOwned` | A VM under the target name was not created by this migration. |
| `TargetVMGone` | The target VM this migration created no longer exists. |
| `ClusteredTargetUnsupported` | Clustered target Provider lacks `supports_routed_import`, or the target is in another namespace. |
| `TargetNotPending` | Clustered target: the target VM already has a provider ID or has no pending host. |
| `ImportNotPerformed` | Clustered target: the host did not perform the import for 5 minutes. |

Holds and waits (the migration stays in its phase and no failure is recorded):

| Condition / reason | Meaning |
|--------------------|---------|
| `Validating=False` / `SourceVMNotReady`, `SourceProviderNotReady`, `TargetProviderNotReady` | A prerequisite is not ready; re-checked every 30 s. |
| `Validating=False` / `WaitingForStorageMount` | `pvc` only: the provider pods have not mounted the PVC yet. |
| `Validating=False` / `WaitingForSourcePowerOff` | Waiting for the source to be observed `Off` (the VM controller powers it off; 10-minute budget). |
| `Validating=False` / `NFSRootIdentityNotAllowed` | `nfs.uid` or `gid` is 0. Final (`Failed`). |
| `Validating=False` / `ProxmoxCrossNamespaceTarget` | Proxmox target in another namespace. Final (`Failed`). |
| `Validating=False` / `TargetCapabilitiesUnknown` | Clustered target: capabilities cannot be read yet. |
| `Ready=False` (and `Validating=False`) / `TargetNamespaceNotAllowed` | The target namespace has no grant. |
| `Ready=False` (and `Validating=False`) / `ConsumerNotAllowed` | A Provider or VMClass in another namespace does not allow this namespace. |
| `Ready=False` / `ProviderDeleting` | The target Provider is being deleted; nothing is imported through it. |
| `Validating=False` / `Unbound`, `ProviderRefMismatch`, `PlacementTopologyMismatch` | The source VM has no confirmed host binding (a clustered source), or its Provider reference does not match its binding. Later phases wait with a `status.message` only. |
| `Validating`, `Exporting` or `Importing=False` / `DiskSizeExceedsLimit`, `DiskSizeLimitUnverifiable` | [Disk-size limit](#administrator-disk-size-limit). |
| `Ready=False` / `SnapshotOutcomeUnknown`, `ExportOutcomeUnknown`, `ImportOutcomeUnknown` | [Outcome unknown](#provider-calls-whose-outcome-is-unknown). |
| `TargetPlaced=False` / `WaitingForPlacement`, `Unschedulable`, `RestorePending`, `AllHostsExcluded`, ... | Clustered target: the target VM has no pending host yet. The source is untouched. |
| `TargetPlaced=False` / `SourceDiskSizeUnknown`, `TargetVMDeleting`, `TargetHostReleased` | Waiting to read the source disk size; a target from an earlier attempt is being deleted; the landing host refused and the target is placed again. |
| `Importing=False` / `TargetHostUnavailable`, `ImportTargetPreviousIncarnation`, `LandingDiskInUse`, `LandingHostRefused`, `ImportNotPerformed` | Clustered target: the landing host's answer; see the clustered guide. |
| `Ready=False` / `TargetHostMoved`, `TargetDiskMismatch` | Clustered target: the target's pending host or `spec.importedDisk` is not what the import recorded. The migration never reaches `Ready`, so `deleteAfterMigration` never runs. |

### Events

Normal events include `ValidationStarted`, `ValidationComplete`, `SnapshotComplete`, `ExportComplete`, `ImportComplete`,
`TargetVMCreated`, `TargetLabelsDropped`, `MigrationComplete`, `CleanupComplete`,
`RetryingMigration`, `StagedDiskDeleted`, `StagedDiskEmptied`, `LandedDiskDeleted`,
`SourceSnapshotDeleted`, `TargetNamespaceAllowed`, `MigrationPVCRetained`,
`TargetHostReleased` and `UnboundTargetVMDeleted`. Warning events include the failure reasons above,
`TargetNamespaceNotAllowed`, `ConsumerNotAllowed`, `ProviderDeleting`, the
`...OutcomeUnknown` reasons, `SnapshotCleanupPending`, `StagingCleanupPending`,
`LandedDiskCleanupPending`, `StagedDiskLeftBehind`, `LandedDiskLeftBehind`,
`SnapshotLeftOnHypervisor`, `SourceDeletionSkippedPreUpgrade`, `SourceDeletionRefused`,
`SourceDeletedTargetNotStarted`, `ProviderResultNotRecorded`, `UnboundTargetVMLeft`,
`DiskSizeExceedsLimit`, `DiskSizeLimitUnverifiable`.

## Annotations and labels

| Key | On | Set by | Meaning |
|-----|----|--------|---------|
| `virtrigaud.io/force-delete: "true"` | `VMMigration` | you | Release a deletion held by a cleanup that cannot succeed. The object is left on the hypervisor or backend; a Warning event says so. |
| `virtrigaud.io/operation-outcome: not-performed@<attempt id>` | `VMMigration` | you | Confirm a held provider call did nothing so it is sent again. |
| `infra.virtrigaud.io/allowed-source-namespaces` | `Namespace` | administrator | Grant for cross-namespace targets. |
| `infra.virtrigaud.io/max-disk-size` | `Provider` | Provider owner | Lowers the manager's `--max-disk-size` for that Provider. |
| `virtrigaud.io/component: migration-storage` (label) | `PersistentVolumeClaim` | you | Required on a PVC named in `storage.pvc.name`. |
| `virtrigaud.io/migration`, `migrated-from`, `imported-disk-id`, `disk-checksum`, `migration-claim` | target `VirtualMachine` | manager | Provenance. Informational only: no decision rests on them except the claim digest. |
| `virtrigaud.io/migration-completed`, `migration-completed-at` | target `VirtualMachine` | manager | A VM marked completed is never deleted with the migration. |

## Finalizer

The controller owns the finalizer `vmmigration.infra.virtrigaud.io/finalizer`. On
deletion, in this order, each step able to **hold** the deletion until it succeeds (or
`virtrigaud.io/force-delete=true` releases it):

1. Delete the source snapshot the migration created (`SnapshotCleanup`).
2. Delete the staged `nfs` / `s3` disk through the target Provider (`StagingCleanup`).
3. For a clustered target, delete the unbound target VM first.
4. Delete the landed disk unless a VM uses it (`LandedDiskCleanup`).
5. Delete the migration-created PVC (a named PVC is left for its owner).
6. If the phase is `Failed` or `Creating`, delete the partially created target VM, only
   the one the migration created (UID precondition) and never one marked
   `migration-completed`, and only with the target-namespace grant.
7. Remove the finalizer.

## Complete example (NFS)

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMMigration
metadata:
  name: app-libvirt-to-vsphere-nfs
  namespace: applications
spec:
  source:
    vmRef:
      name: app-on-libvirt
    createSnapshot: false
    powerOffBeforeMigration: true
    deleteAfterMigration: false

  target:
    name: app-on-vsphere
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
    retryPolicy:
      maxRetries: 3
      retryDelay: 5m
      backoffMultiplier: 2
    cleanupPolicy: OnSuccess

  storage:
    type: nfs
    nfs:
      server: nfs.example.com
      export: /export/virtrigaud
      uid: 1000
      gid: 1000

  metadata:
    purpose: provider-change
    environment: prod
```

A `Ready` migration then reports, among others:

```yaml
status:
  phase: Ready
  message: Migration completed successfully
  startTime: "2026-06-21T10:00:00Z"
  completionTime: "2026-06-21T10:43:12Z"
  sourceVMUID: 6f1c2f6e-0000-0000-0000-000000000001   # example value
  targetVMUID: 6f1c2f6e-0000-0000-0000-000000000002   # example value
  targetVMID: vm-1234
  importID: applications_app-on-vsphere-migrated
  storageInfo:
    stagingLayout: v2
    cleanedUp: true
  diskInfo:
    sourceFormat: qcow2
    sourceSize: 50Gi
    targetFormat: vmdk
    targetPath: "[datastore1] applications_app-on-vsphere-migrated/applications_app-on-vsphere-migrated.vmdk"
  conditions:
    - type: Ready
      status: "True"
      reason: MigrationComplete
      message: VM migration completed successfully
      lastTransitionTime: "2026-06-21T10:43:12Z"
    - type: StagingCleanup
      status: "True"
      reason: StagedDiskEmptied      # libvirt/vSphere targets empty an NFS file
      message: The migration's staged disk was emptied ...
      lastTransitionTime: "2026-06-21T10:43:14Z"
    - type: LandedDiskCleanup
      status: "True"
      reason: LandedDiskInUseByTarget
      message: The landed disk is the target VM's disk; it is never deleted by the migration.
      lastTransitionTime: "2026-06-21T10:43:12Z"
    - type: PostMigrationCleanup
      status: "True"
      reason: PostMigrationCleanupComplete
      message: The migration's source cleanup is finished.
      lastTransitionTime: "2026-06-21T10:43:15Z"
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
    powerOffBeforeMigration: true      # required for a vSphere source
    deleteAfterMigration: false

  target:
    name: app-vm-libvirt
    providerRef:
      name: libvirt-prod
    classRef:
      name: medium-vm
    networks:
      - name: corp-bridge
    powerOn: false

  options:
    diskFormat: qcow2
    verifyChecksums: true
    cleanupPolicy: OnSuccess
    retryPolicy: {}

  storage:
    type: s3
    transferMode: relay
    s3:
      bucket: virtrigaud
      endpoint: https://s3.example.com
      region: us-east-1
      usePathStyle: true
      credentialsSecretRef:
        name: s3-migration-credentials
```

The staged object is `vmmigrations/applications/app-vm-vsphere-to-libvirt/export.vmdk`
in the bucket, and is deleted through the libvirt Provider when the migration is
`Ready`.

More examples, all in the main repository: `examples/migration/` and
`examples/vmmigration-{basic,advanced,s3,nfs,proxmox-s3,into-clustered}.yaml`
(see [Examples](user-guide.md#examples-in-the-main-repository)).

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
    verbs: ["get", "list", "watch"]
```

Authors do not need access to the S3 credentials Secret: the manager reads it. Do not
grant `update` or `patch` on `vmmigrations/status`. The manager's ServiceAccount (from
the Helm chart) needs broader rights: Secrets, PVCs, Namespaces (`get`, `list`,
`watch`, to read grants), StorageClasses (`get`), and `VirtualMachine` create and
delete. Creating a `VMMigration` is also permission to read the source VM's disk into
another namespace or provider: grant it only to people trusted with that data.

## See also

- [VM Migration User Guide](user-guide.md) - operator-facing how-to.
- [VM Migration Guide](vm-migration-guide.md) - architecture and internals.
- [Full CRD Reference](../references/generated-crd-docs.md#vmmigration) - generated field reference.
- [Clustered libvirt](../guides/clustered/index.md) - migrating into a clustered Provider.
- [Resilience](../operations/resilience.md) - how the circuit breaker interacts with the many provider RPCs a migration issues.
- [ADR-0006](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0006-storage-backend-agnostic-cross-hypervisor-migration.md) - storage-backend-agnostic migration.
- [ADR-0011](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0011-migration-staging-cleanup.md) - staging and landed-disk cleanup.
- [Upgrading from v0.3.11](https://github.com/projectbeskar/virtrigaud/blob/main/docs/upgrading.md) - upgrade guide.
