<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VM Migration User Guide

This page is aligned to **VirtRigaud v0.4.0**. It is the practical "how do I move a
VM?" guide. For the field-by-field CRD reference see
[API Reference](api-reference.md); for the architectural model see
[VM Migration Guide](vm-migration-guide.md).

## What VirtRigaud v0.4.0 supports

A `VMMigration` is a **cold, single-disk copy**: it moves the primary disk of a VM from
one Provider to another through a staging backend, then creates a new
`VirtualMachine` that uses the copied disk. It is not live migration, and it does not
move the VM's additional disks.

| Backend (`spec.storage.type`) | Status in v0.4.0 |
|-------------------------------|------------------|
| `s3` | Recommended. All three providers, as source and target. The provider **pod** is the S3 client (`relay`; `direct` is not implemented). |
| `nfs` | Recommended. All three providers. libvirt and vSphere use `qemu-img`'s libnfs driver; Proxmox mounts the export on the node. Needs `nfs.uid`/`nfs.gid` for cross-provider moves. |
| `pvc` | Legacy, compatibility only. vSphere and single-host libvirt only; not Proxmox, not a clustered libvirt Provider, not across namespaces. |

Targets: `vsphere`, `libvirt` (single host), `proxmox`, and a libvirt Provider with
`topology: cluster` (**experimental**, `s3` and `nfs` only, see
[below](#migration-into-a-clustered-libvirt-provider-experimental)).

!!! info "What was validated in a lab, and what was not"
    "Validated" here means the migration reached `Ready` on real hypervisors. Anything
    not listed was covered only by unit, envtest and simulator tests.

    **v0.3.11 (ADR-0006 Slices 1-4, [#236](https://github.com/projectbeskar/virtrigaud/issues/236))**
    validated these pairs on real hypervisors. The code was reworked afterwards.

    | S3 | NFS |
    |----|-----|
    | vSphere <-> libvirt | libvirt <-> libvirt |
    | vSphere <-> Proxmox | libvirt -> vSphere |
    | libvirt <-> Proxmox | vSphere -> libvirt |
    | | libvirt -> Proxmox |
    | | Proxmox -> libvirt |

    **Repeated on v0.4.0 release candidates** (the lab runs recorded in the release
    notes), single-node Proxmox VE 9.2, vCenter and libvirt 10.0:

    | Run | Backend | Direction |
    |-----|---------|-----------|
    | rc2 | `s3` | libvirt -> vSphere |
    | rc2 | `pvc` | vSphere -> libvirt |
    | rc4 | `s3` | vSphere <-> Proxmox; libvirt <-> Proxmox; Proxmox -> clustered libvirt; vSphere -> clustered libvirt |
    | rc4 | `nfs` | libvirt -> Proxmox; Proxmox -> libvirt |
    | rc5 | `s3` | clustered libvirt -> Proxmox |
    | rc5 | `nfs` | Proxmox -> clustered libvirt; vSphere -> clustered libvirt |
    | rc7 | `s3` | vSphere -> clustered libvirt, onto a bridged network |
    | after rc2 (build `main-73e08e8`) | `s3`, `nfs` | single-host libvirt -> clustered libvirt (two hosts, shared NFS pool) |

    **Not repeated on a v0.4.0 build in a recorded lab run:** vSphere <-> libvirt and
    libvirt <-> libvirt over NFS, and vSphere <-> Proxmox over NFS (never validated at
    all). **Never run:** a Proxmox cluster of more than one node, and migration between
    two Kubernetes clusters (the staging backends would allow it; it is not
    validated). The Proxmox import-stage delete of a failed migration, staged-disk
    deletion after a fault, landed-disk deletion after a failed import (apart from the
    clustered-target lab case), held calls after a manager restart (apart from the
    clustered-target lab case), and the `pvc` link refusals are covered by unit and
    envtest tests only. The release notes record no separate lab check of the
    staged-disk delete: look at `StagingCleanup` after your first migration.

!!! warning "What changed since v0.3.11"
    Read [Upgrading with migrations in flight](#upgrading-with-migrations-in-flight)
    before you upgrade. In short: a migration accepts only the target VM it created;
    cross-namespace targets need a grant; `nfs.uid: 0` is refused; failed and deleted
    migrations now delete the staged and landed disks; provider pods mount only the
    PVCs a live migration references; a call whose result is lost is held, not re-sent
    blindly; a failed migration is retried only if you set a `retryPolicy`; a clone or
    migrated VM stays powered off unless `powerOn: true`.

!!! tip "Capability gating (opt-in)"
    The manager flag `--enforce-provider-capabilities` (default off) makes the manager
    refuse an export or import up front when a provider reports it cannot do it. See
    the [API Reference](api-reference.md#capability-gating-176-fail-close-on-providers-lacking-exportimport).
    Whether it is on or off, the requested `storage.type` must be advertised by both
    providers (`Provider.status.reportedCapabilities`).

## Concept in one diagram

```text
┌──────────────────────────┐        ┌──────────────────────────┐
│   Source Provider        │        │   Target Provider        │
│   (vsphere / libvirt /   │        │   (vsphere / libvirt /   │
│    proxmox)              │        │    proxmox)              │
│                          │        │                          │
│  export primary disk     │        │  import disk             │
│  (native format)    ─────┼──────► │  (check image, convert   │
│                          │        │   with qemu-img)         │
└──────────────────────────┘        └──────────────────────────┘
              │                                   ▲  │
              └───────────────┬───────────────────┘  │ delete staged
                              │ staged on            │ object when done
                              ▼                      │ (DeleteStagedDisk)
              ┌───────────────────────────────────┐  │
              │   Staging backend (one of):       │◄─┘
              │   • S3 (bucket/prefix)            │
              │   • NFS (export, flat file)       │
              │   • PVC  ← legacy                 │
              └───────────────────────────────────┘
                              │
                        orchestrated by
                              ▼
                ┌────────────────────────────────┐
                │  VMMigration controller        │
                │  (phase machine, in the        │
                │   manager)                     │
                └────────────────────────────────┘
```

In order, all driven by the migration controller:

1. **Validate.** Providers, grants, target name, storage configuration and (if set)
   the disk-size limit are checked. The source is powered off if you asked for it.
   Nothing is changed on the hypervisors before this passes.
2. **Snapshot** (optional). A snapshot of the source is taken, or the one you named is used.
3. **Export.** The source provider writes the primary disk to the staging backend.
4. **Import.** The target provider reads the staged object, checks its header, converts
   the format with `qemu-img` if needed and lands the disk.
5. **Create.** The controller creates the target `VirtualMachine` that uses the landed
   disk, and waits for it to be `Ready`.
6. **Clean up.** The staged object, the source snapshot and (if requested) the source VM
   are removed. The target VM and its disk stay.

## Before you migrate

- The source `VirtualMachine` is `Ready` and has a provider ID. For a vSphere source,
  set `powerOffBeforeMigration: true`.
- Source and target `Provider`s are `Ready`, and advertise your staging backend.
- The target needs a `VMClass` (`spec.target.classRef`; the target `VirtualMachine`
  requires one) in the migration's namespace, and, for a vSphere target, a
  `VMNetworkAttachment` in `spec.target.networks` or the VM has no NIC.
- **Plan for the guest's network** (see [The migrated guest's network](#the-migrated-guests-network)).
- Nothing else is called the target's name in the target namespace.
- The staging backend is reachable from **both** providers' data planes and passes the
  manager's host policy (`--migration-storage-allowed-hosts`; an empty list allows
  everything except loopback, link-local, metadata and multicast addresses; entries are
  IPs or CIDRs).
- A target Provider in another namespace than the migration allows it through
  `spec.consumerNamespaceSelector`.
- Set `options.retryPolicy` if you want automatic retries.
- Think about the disk size: each `ExportDisk` and `ImportDisk` call has a **30-minute
  deadline** in the manager's gRPC client. A disk whose export or import cannot finish
  within it is not migrated in v0.4.0: the call ends without a known outcome and the
  migration is held (see [Held provider calls](#a-migration-held-with-outcomeunknown)).
  This is derived from the code, not a measured limit; test with a representative disk.

## Quick start: libvirt to vSphere over NFS

This migrates a VM from a Libvirt host to vSphere, staging the disk on an NFS export.

### Prerequisites

- A working VirtRigaud install (manager and both providers `Ready`).
- A source `VirtualMachine` managed by the Libvirt provider.
- A `Provider` for vSphere and a `VMClass` and `VMNetworkAttachment` for the target.
- An NFS export reachable by the libvirt **host**, the vSphere provider **pod** and, for
  Proxmox, the PVE node, with an ACL that allows those client addresses.
- The export owned by a known **non-zero** uid/gid that every provider leg will
  present. See [NFS staging](#nfs-staging).

### NFS VMMigration

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMMigration
metadata:
  name: app-libvirt-to-vsphere-nfs
  namespace: default
spec:
  source:
    vmRef:
      name: app-on-libvirt
    createSnapshot: false
    powerOffBeforeMigration: true   # required for a vSphere source; a clean cold copy otherwise
  target:
    name: app-on-vsphere
    providerRef:
      name: vsphere-prod
    classRef:
      name: standard-2cpu-4gb
    networks:
      - name: primary
        networkRef:
          name: vm-network
    powerOn: false
  storage:
    type: nfs
    nfs:
      server: nfs.example.com
      export: /export/virtrigaud
      uid: 1000     # uid that owns the export's files; 0 is refused
      gid: 1000
    transferMode: auto    # informational for NFS
  options:
    cleanupPolicy: OnSuccess
    verifyChecksums: true
    retryPolicy: {}       # defaults: 3 retries, 5m delay, x2 backoff
```

Apply and watch:

```bash
kubectl apply -f app-libvirt-to-vsphere-nfs.yaml

# Phase progression
kubectl get vmmigration app-libvirt-to-vsphere-nfs -w

# Conditions, events, and status
kubectl describe vmmigration app-libvirt-to-vsphere-nfs
```

A successful run goes `Pending` -> `Validating` -> (`Snapshotting` if a snapshot is
taken) -> `Exporting` -> `Importing` -> `Creating` -> `Validating-Target` -> `Ready`.
The `Transferring` and `Converting` phases in the enum are never entered.
The `Progress` column stays empty: the export and import are single synchronous
provider calls.

## Quick start: vSphere to libvirt over S3

S3 is the relay path. The provider **pod** is the S3 client: bytes flow host -> pod ->
bucket -> pod -> host. `transferMode: auto` resolves to `relay`.

### Prerequisites

- An S3-compatible bucket and a `Secret` **in the migration's namespace** with its
  credentials. The migration author does not need to read the Secret: the manager does.
- A source VM managed by vSphere and a target `Provider` for Libvirt.

### S3 credentials Secret

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
  # sessionToken: <optional, for temporary credentials>
```

### S3 VMMigration

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMMigration
metadata:
  name: my-vm-to-libvirt
  namespace: default
spec:
  source:
    vmRef:
      name: my-vsphere-vm
    createSnapshot: true
    powerOffBeforeMigration: true   # required for a vSphere source
    deleteAfterMigration: false     # keep the source for rollback

  target:
    name: my-vm-libvirt
    providerRef:
      name: libvirt-prod
      namespace: virtrigaud-system  # needs spec.consumerNamespaceSelector to select "default"
    classRef:
      name: medium-vm
    networks:
      - name: corp-bridge
    powerOn: false

  options:
    diskFormat: qcow2
    verifyChecksums: true
    retryPolicy: {}

  storage:
    type: s3
    transferMode: relay
    s3:
      bucket: virtrigaud
      endpoint: https://s3.example.com   # omit for AWS S3
      region: us-east-1
      usePathStyle: true                 # true for MinIO/Ceph; false for AWS
      credentialsSecretRef:
        name: s3-migration-credentials
```

```bash
kubectl apply -f my-vm-to-libvirt.yaml
kubectl get vmmigration my-vm-to-libvirt -w
```

## Storage

### S3 staging

The provider pod is the S3 client; **no PVC is involved**. The source exports the disk
in its native format and the **target** converts on import. Fields under
`spec.storage.s3`:

| Field | Required | Notes |
|-------|----------|-------|
| `bucket` | yes | Bucket name. |
| `endpoint` | no | Omit for AWS S3; set for MinIO, Ceph RGW and similar. SSRF-checked. |
| `region` | no | Empty uses the SDK default; set it for AWS. |
| `prefix` | no | Key prefix. |
| `usePathStyle` | no, default `false` | `true` for most non-AWS stores. |
| `credentialsSecretRef.name` | yes | Secret in the migration's namespace: `accessKeyID`, `secretAccessKey`, optional `sessionToken`. Never inline credentials. |

The staged object is `[<prefix>/]vmmigrations/<namespace>/<name>/export.vmdk` (the suffix
is only the name; the content is the source's native format). The S3 credentials need
`s3:GetObject` and `s3:DeleteObject` on `vmmigrations/`, besides write access, because
the delete after the migration uses the same credentials. Use TLS: this is the backend
to choose when you need encryption in transit.

<a id="nfs-staging-new-in-slice-4"></a>

### NFS staging

NFS stages the disk on an export and moves it with `qemu-img`'s own NFS support. There
is no PVC and no pod relay.

| Provider | NFS transport |
|---------|----------------|
| **libvirt** | The libvirt **host** runs `qemu-img` against an `nfs://` URL (libnfs), over SSH. |
| **vSphere** | The provider **pod** runs `qemu-img` against `nfs://` (libnfs). The image ships Debian `qemu-block-extra`. |
| **Proxmox** | The PVE **node** mounts the export with its kernel NFS client (`nosymfollow,nosuid,nodev,noexec`) and runs `qemu-img` against the mount. `pve-qemu-kvm` ships no libnfs. |

#### The uid/gid requirement

!!! warning "Set a non-zero uid/gid for cross-provider migrations"
    AUTH_SYS (NFSv3) authorizes by the **numeric uid/gid** the client presents, and
    each provider's `qemu-img` runs as a different identity: the libvirt SSH user, the
    vSphere pod's uid `65532`, `root` on the Proxmox node. Set `nfs.uid` and `nfs.gid`
    to the identity that **owns the export's files** so every leg can read and write
    the same staged object. Omitted or wrong values end in `NFS3ERR_ACCES` (in the
    provider log) on at least one leg.

    **`uid: 0` and `gid: 0` are refused** for every provider type: the migration fails
    at `Validating` with reason `NFSRootIdentityNotAllowed`, because on an export
    without `root_squash` that identity is root. Proxmox presents the identity with
    `setpriv`; libvirt and vSphere put it in the libnfs URL.

#### Flat-file layout

The staged object is a **single flat file**:

```text
<export root>/vmmigrations_<namespace>_<name>_export.qcow2
```

NFS cannot auto-create directories. If you set `nfs.path`, that directory must already
exist; otherwise omit it and use one export per tenant. A migration an older release
already staged keeps the old name `vmmigrations-<namespace>-<name>-export.qcow2` for its
import and delete (`status.storageInfo.stagingLayout: v1`). The old name was ambiguous
across namespaces, hence the underscores.

#### Integrity model

`qemu-img` over NFS computes no byte checksum, so `verifyChecksums` does not give an
end-to-end SHA-256 comparison on `nfs`: integrity rests on the target's `qemu-img` check
of the converted image. Use `s3` when you need the checksum comparison.

Every NFS and S3 import also checks the staged image before using it: it is copied once
to a local file, its header is parsed, and an image that references any other file
(backing file, data file, extent) or is not the expected format is refused
(`InvalidArgument`). Copies are bounded by `VIRTRIGAUD_MIGRATION_IMPORT_MAX_GIB`
(provider environment, default 1024 GiB), and the free space must hold twice the staged
size (`ResourceExhausted`, retried). A VMDK whose grain directory is at the end of the
file (a VMware-native streamOptimized export) is refused; VirtRigaud's own vSphere
export is not affected. A refused image must be exported again.

#### Security and hardening (ADR-0006 C6)

!!! danger "AUTH_SYS over NFSv3 is cleartext - harden accordingly"
    The uid/gid is an assertion, not an authenticated identity, and the disk bytes are
    **not encrypted in transit**. Run the export on a **trusted network segment**, keep
    **`root_squash` on**, use **one export per tenant**, prefer narrow per-client ACLs,
    and exclude the export from server-side snapshots (a snapshot keeps a staged file
    after it is deleted). If your compliance posture requires encryption in transit,
    use `s3` over TLS.

Fields under `spec.storage.nfs`:

| Field | Required | Notes |
|-------|----------|-------|
| `server` | yes | Hostname or IP. SSRF-checked at `Validating` (and again before each delete). |
| `export` | yes | Absolute export path, e.g. `/export/virtrigaud`. |
| `path` | no | Existing sub-path under the export. Omit to use the export root. |
| `uid`, `gid` | no (effectively required) | Non-zero numeric identity presented to the server. |
| `readOnly` | no | Default `false`; not useful for migration. |

### PVC staging (legacy)

`storage.type: pvc` stages the disk on a PVC that is mounted into the source and target
provider pods. It is kept for clusters that already use it. It does not work with
Proxmox or a clustered libvirt Provider, and the migration and **both Providers must be
in the same namespace**.

What the provider pods mount (changed in v0.4.0, security):

- A PVC is mounted only into the source and target Provider of a `VMMigration` that
  records it in `status.storagePVCName` and is still in flight. The target mounts it
  **read-only**, the source read-write.
- The PVC must be the one the migration created (identified by its UID in
  `status.storagePVCUID`; an `ownerReference` proves nothing), or the one
  `spec.storage.pvc.name` names. A named PVC must carry the label
  `virtrigaud.io/component=migration-storage`, and must not belong to another
  migration: `kubectl -n <namespace> label pvc <name> virtrigaud.io/component=migration-storage`.
- A PVC that is not `Bound` is not mounted (a `Pending` one only while the migration
  validates, on a `WaitForFirstConsumer` StorageClass). The migration fails if the mount
  has not worked after 5 minutes.
- **Deleting the migration deletes only the PVC it created.** A PVC named in
  `spec.storage.pvc.name` is unmounted and left for its owner (event
  `MigrationPVCRetained`); the staged disk stays under
  `vmmigrations/<namespace>/<migration-name>/` for you to remove.
- Provider pods are rolled when the PVC is mounted and again when it is released
  (`Ready`, final failure, deletion), which interrupts other migrations on the same
  Provider.
- Staged files are opened with no symbolic link followed; a link, special file or
  hard-linked file in the PVC fails the migration (`refused the staged file`), as does a
  filesystem that reports a link count other than 1.

Size an auto-created PVC at 1.5x to 2x the source disk. Field detail:
[API Reference - storage.pvc](api-reference.md#storagepvc-pvcstorageconfig-compat-only).

## What happens to the source VM

| `spec.source` setting | Behavior |
|-----------------------|----------|
| `deleteAfterMigration: false` (default) | The source VM **stays**. Use it as a rollback. |
| `deleteAfterMigration: true` | After `Ready`, the source `VirtualMachine` is **deleted** (and with it the hypervisor VM). Only the object the migration validated (UID in `status.sourceVMUID`) is deleted; a VM re-created under the same name is kept (Warning `SourceDeletionRefused`). It does not run for a failed migration. With `powerOn: false` the workload then runs nowhere until you power the target on (Warning `SourceDeletedTargetNotStarted`). |
| `createSnapshot: true` (default), `snapshotRef` unset | A snapshot of the source is taken first (a task-backed snapshot on vSphere or Proxmox is polled until it finishes) and exported. The migration deletes it at `Ready`, on final failure and on deletion unless `cleanupPolicy: Never`. |
| `createSnapshot: false` | Export without a snapshot. Typical with `powerOffBeforeMigration`. |
| `snapshotRef: { name: ... }` | Skips the snapshot step. The name is passed to the source provider as the provider-side snapshot ID (no `VMSnapshot` is looked up). The migration never deletes it. |
| `powerOffBeforeMigration: true` | The migration sets the source VM's `spec.powerState` to `Off` and **waits** (condition `SourcePowerOff`) up to 10 minutes until the provider reports it `Off`; a longer wait fails the migration. Required for a vSphere source. The source is **not** powered back on. |
| `powerOffBeforeMigration: false` (default) | The source runs throughout. The migration is still cold (it copies a snapshot of a running disk, or the disk as it is). There is no live migration. |

## What happens to the target VM

The controller creates a `VirtualMachine` named `spec.target.name`, with
`spec.importedDisk` (`diskID`, `path`, `format`, `source: migration`, `migrationRef`),
the provider, `classRef`, `networks`, `placementRef`, your labels and annotations, and
`spec.powerState` `On` only if `powerOn: true`. It never sets `imageRef`.

!!! note "A migration accepts only the target VM it created"
    Before the target is created the controller records a claim
    (`status.targetVMClaim`, the digest of a one-time token that goes on the VM as the
    annotation `virtrigaud.io/migration-claim`); once the `Create` succeeds it records the
    VM's UID in `status.targetVMUID`. From then on only that VM is the migration's
    target: waiting for it, validating it, marking it completed, and deleting a partial
    one. **Any other `VirtualMachine` under the target's name fails the migration at
    `Validating`**, before the source is touched, with reason `TargetVMNotOwned`; that
    VM is never read, annotated or deleted. To fix: delete or rename the other VM, or
    choose another `spec.target.name`, then create the migration again. A target the
    migration created that disappears before completion fails with `TargetVMGone`. The
    chart's admission policy (Kubernetes 1.30+) stops anyone but the manager from
    setting the provenance annotations. Details:
    [Target VM ownership](api-reference.md#target-vm-ownership).

On `phase=Ready`:

- The target VM is **independent** of the `VMMigration`; deleting the migration does not
  delete it.
- It carries `virtrigaud.io/migration-completed=true` and
  `virtrigaud.io/migration-completed-at=<RFC3339>`, and is never deleted with the
  migration.
- With `powerOn: false` it is off. Power it on with
  `kubectl patch vm <target> --type=merge -p '{"spec":{"powerState":"On"}}'`.

On `phase=Failed` and deletion: a partially created target VM is deleted with the
migration only if the migration is `Failed` or `Creating`, it is the VM the migration
created, and it is not marked completed.

## Cleanup: what is deleted, and when

`options.cleanupPolicy` (`OnSuccess` default, `Always`, `Never`) controls the artifacts
a migration creates. In v0.4.0 an `nfs` or `s3` migration cleans up after itself; before,
nothing was deleted.

| Artifact | `OnSuccess` (default) | `Always` | `Never` |
|----------|----------------------|----------|---------|
| Staged disk (`nfs`, `s3`) | At `Ready` and when the `VMMigration` is deleted. Kept after a final failure until you delete the migration. | Also after a final failure. | Kept. |
| Landed disk on the target | When the `VMMigration` is deleted, if no VM uses it. A `Ready` migration's disk is the target VM's and is never deleted. | Also after a final failure. | Kept. |
| Source snapshot the migration took | At `Ready`, at final failure, on deletion. | Same. | Kept. |
| Migration-created PVC | With the `VMMigration`. | Same. | Same. |

While a retry is pending nothing is deleted: the retry overwrites the artifacts.

### Staged disk (`StagingCleanup`)

The manager asks the **target** Provider to delete the staged object (RPC
`DeleteStagedDisk`, [ADR-0011](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0011-migration-staging-cleanup.md)).
The manager never opens the backend. Watch it:

```bash
kubectl get vmmigration <name> -o jsonpath='{range .status.conditions[*]}{.type}={.status}/{.reason}{"\n"}{end}'
```

- `StagingCleanup=Unknown/StagedDiskMayExist` from the moment the export is sent.
- `True/StagedDiskDeleted` when done; `True/StagedDiskEmptied` on **libvirt and vSphere
  NFS targets**, which can only truncate the file to 0 bytes (a 0-byte file with the
  staging name stays on the export; Proxmox deletes it).
- `False/StagingCleanupPending` when the delete cannot be done yet: retried with a
  backoff from 15 s to 5 min, and **a deleting `VMMigration` stays until it succeeds**.
  Annotate it `virtrigaud.io/force-delete=true` to release it and leave the object.
- `True/StagedDiskLeftBehind` (Warning) when VirtRigaud will not delete it: the target
  Provider is gone or replaced, the provider refused, the S3 Secret is gone, or
  `spec.storage` / `spec.target.providerRef` changed since the export. Remove it by hand.
- A target provider image older than v0.4.0 cannot delete: the manager holds the delete
  for 24 hours, so **roll the providers right after the manager**, then records
  `StagedDiskLeftBehind`.

!!! warning "Versioned buckets and server snapshots keep the data"
    The S3 delete removes the current version only. In a versioned or object-lock
    bucket, expire noncurrent versions on `vmmigrations/`; exclude the NFS staging
    export from snapshots. The staged object is a full, unencrypted copy of the disk.

### Landed disk (`LandedDiskCleanup`)

The disk `ImportDisk` landed on the target (vSphere `[<datastore>] <namespace>_<vm>-migrated/`,
libvirt `<default pool>/<namespace>.<vm>-migrated.qcow2`, the Proxmox import stage) is
deleted with `DeleteLandedDisk` when the migration fails for good or is deleted before
a VM uses it. `LandedDiskCleanup` is `Unknown/LandedDiskMayExist` from just before the
import, then `True` with `LandedDiskInUseByTarget` (migration `Ready`: the disk is the
target's), `LandedDiskDeleted`, `LandedDiskInUse`, `LandedDiskHandedOver`,
`LandedDiskRetained` or `LandedDiskLeftBehind`, or `False/LandedDiskCleanupPending`
while held. The provider refuses to delete a disk any VM uses. Do not share the landing
datastore or libvirt `default` pool directory with hypervisors the Provider does not
manage, and run one replica of each provider. Disks left by migrations before v0.4.0
are not touched; remove them as described in
[Leftovers from earlier releases](https://github.com/projectbeskar/virtrigaud/blob/main/docs/upgrading.md#leftovers-from-earlier-releases).

<a id="a-migration-held-with-outcomeunknown"></a>

## A migration held with `...OutcomeUnknown`

Before `SnapshotCreate`, `ExportDisk` and `ImportDisk` are sent the migration records
`SnapshotRequested`, `ExportRequested` or `ImportRequested`. If the manager restarts
after the call but before its result is written, or the call fails without a definite
answer (a deadline, a dropped connection), the migration is **not failed and the call is
not blindly re-sent**. It is held:

```text
Ready=False  reason: SnapshotOutcomeUnknown | ExportOutcomeUnknown | ImportOutcomeUnknown
```

- An `ExportDisk` or `ImportDisk` on a backend the provider lists as re-send safe is sent
  again **35 minutes** after the marker (the call's deadline is 30 minutes), at most 3
  times. So a manager restart during an import costs about 35 minutes, as documented.
  A `SnapshotCreate` through a clustered Provider is re-sent after a minute.
- Everything else is held for you (every single-host `SnapshotCreate`, a Proxmox `nfs`
  import, and any call through a provider image older than v0.4.0). Look at what the call
  may have made (the snapshot named in the Warning event, the target's `-migrated` disk),
  remove it, then confirm the attempt:

```bash
ATTEMPT=$(kubectl get vmmigration <name> -n <ns> \
  -o jsonpath='{.status.conditions[?(@.type=="ExportRequested")].lastTransitionTime}')
kubectl annotate vmmigration <name> -n <ns> virtrigaud.io/operation-outcome=not-performed@$ATTEMPT
```

  Use `SnapshotRequested` or `ImportRequested` for the other calls. Or delete the
  migration (anything the call made that was not recorded is left for you).

Alert on migrations stuck in a phase and on the three `...OutcomeUnknown` reasons. The
full rules, including which failures each provider treats as definite, are in
[Provider calls whose outcome was lost](https://github.com/projectbeskar/virtrigaud/blob/main/docs/provider-call-outcomes.md).

## Failure modes and recovery

### Failure classes

| Class | What it looks like | Notes |
|-------|--------------------|-------|
| Transient SSH failures on libvirt | `Failed` during export or import, or `ImportNotPerformed` | A migration drives many back-to-back `virsh`-over-SSH calls; bursts can trip the host's `sshd` `MaxStartups` or `fail2ban`. The provider retries with a bounded backoff, but tight host limits can still fail a migration. Raise `MaxStartups` and allowlist the provider, see [Libvirt Host Preparation](../operations/libvirt-host-prepare.md#ssh-connection-rate-limiting-maxstartups-fail2ban). |
| Provider circuit breaker | Calls refused while a Provider is flapping | Each Provider has its own breaker; a long migration issues many RPCs. See [Resilience](../operations/resilience.md). |
| Lost call result | `...OutcomeUnknown` | See above. |
| Target name taken | `Failed`, `TargetVMNotOwned` | See above. |

### Common operator-visible failures

`status.message` and events carry constant, safe text; the provider's own error is in
the **provider log** and the manager log.

| Symptom | Likely cause | First steps |
|---------|--------------|------------|
| `Failed`, `Validating=False/NFSRootIdentityNotAllowed` | `nfs.uid` or `nfs.gid` is `0`. | Use the non-zero uid/gid that owns the export (or leave both unset), create the migration again. |
| `Failed`, "nfs server not permitted" / "s3 endpoint not permitted" | The staging host is loopback/link-local/metadata, or outside `--migration-storage-allowed-hosts`, or does not resolve. | Fix the host, or add its network to the allowlist. |
| `Failed`, "storage backend ... not supported by source/target provider" | The provider does not advertise the backend (Proxmox: no `pvc`; a clustered source or target: no `pvc`). | Use `s3` or `nfs`. |
| `Failed`, "transfer mode "direct" is not yet implemented" | `transferMode: direct` with `s3` or `pvc`. | Use `auto` or `relay`. |
| `Failed` during `Exporting`/`Importing`, provider log shows `NFS3ERR_ACCES` | The identity presented is not allowed on the export. | Set `nfs.uid`/`nfs.gid` to the owner of the export's files. |
| provider log shows `MNT3ERR_NOENT` | `nfs.path` names a directory that does not exist. | Create it, or omit `path`. |
| `Failed`, `TargetVMNotOwned` | A VirtualMachine with the target name exists that this migration did not create. | Delete or rename it, or pick another name, then create the migration again. |
| `Failed`, "The source VM's provider refused it" | The VM at the source's provider ID is not that VirtualMachine's (an ID reused after the VM was removed outside VirtRigaud), or its owner stamp cannot be read. Nothing was exported. | Check the source `VirtualMachine`'s `Ready` condition. |
| `Failed`, source VM "was not observed powered off within 10m0s" | The source VM controller could not power it off. | Look at the source VM's `Ready` condition and events. |
| `Failed`, import refused (`InvalidArgument`) | The staged image references another file, is not the expected format, or exceeds the size limit. | Export again; check `VIRTRIGAUD_MIGRATION_IMPORT_MAX_GIB`. |
| Stuck in `Validating` | Read the `Validating` condition: `SourceVMNotReady`, `SourceProviderNotReady`, `TargetProviderNotReady`, `WaitingForStorageMount` (`pvc`), `WaitingForSourcePowerOff`, `TargetNamespaceNotAllowed`, `ConsumerNotAllowed`, `DiskSizeExceedsLimit`, `TargetPlaced=False` (clustered target). | Each is a hold, not a failure; fix the cause named by the reason. |
| `Ready=False/TargetNamespaceNotAllowed` | The target Namespace has no grant for the migration's namespace. | An administrator annotates it, see [Cross-namespace migrations](#cross-namespace-migrations). |
| `Ready=False/ConsumerNotAllowed` | A Provider or VMClass in another namespace does not select this namespace. | Set its `spec.consumerNamespaceSelector`. |
| `Ready=False/ProviderDeleting` | The target Provider is being deleted. | Nothing is imported through it; wait for it to be recreated or point the migration elsewhere. |
| `Exporting` or `Importing` for more than 30 minutes | A call past its deadline, held as outcome unknown. | See above; check the provider logs and `virtrigaud_circuit_breaker_state{provider=<name>}`. |
| `Ready` but the target does not run | `powerOn: false` (default). | Patch `spec.powerState` to `On`. |
| `Ready` but the guest has no network | See [The migrated guest's network](#the-migrated-guests-network). | |
| `Failed`, retries used up (`retryCount` = `maxRetries`) | The cause keeps recurring. | Fix it, then create a new `VMMigration`. |
| `Failed` and never retried | No `options.retryPolicy`. | Set one (`retryPolicy: {}` gives the defaults). |
| Deleting a `VMMigration` hangs | A cleanup cannot succeed yet (`SnapshotCleanup`, `StagingCleanup` or `LandedDiskCleanup` is `False/...Pending`): the provider cannot be reached. | Restore the provider, or annotate `virtrigaud.io/force-delete=true` to leave the artifact behind. |

### Retry

A failed migration is retried only if `spec.options.retryPolicy` is set. Retry *n* waits
`retryDelay x backoffMultiplier^(n-1)` after the failure (capped at 30 minutes), then
restarts from `Pending`. Touching the object (for example with an annotation) does not
shorten the wait; to retry sooner, create a new `VMMigration`. A migration with no `retryPolicy`, or whose retries are used up, stays
`Failed` and only runs its cleanup.

### Reading migration progress

```bash
# Phase and message
kubectl get vmmigration my-vm-to-libvirt \
  -o jsonpath='{.status.phase}{"\t"}{.status.message}{"\n"}'

# All conditions
kubectl get vmmigration my-vm-to-libvirt \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}/{.reason}{"\n"}{end}'

# Events
kubectl get events --field-selector involvedObject.name=my-vm-to-libvirt
```

`status.progress` is not populated in v0.4.0.

## Performance guidance

| Variable | Notes |
|----------|-------|
| Transfer speed | Bounded by the staging backend and the network between each provider's data plane and it. For `s3` the bytes pass through the provider pods; for `nfs` they go host-to-export (libvirt, Proxmox) or pod-to-export (vSphere). |
| Format conversion | The target converts with `qemu-img` on import (for example `vmdk` to `qcow2`). The import needs scratch space: the Proxmox stage directory, the libvirt pool directory or the vSphere pod's `/tmp` must hold about twice the staged size. |
| vSphere pod `/tmp` | An import stages about twice the disk in the pod's `/tmp`, which has an `emptyDir` `sizeLimit` (512Gi by default for vSphere providers). A pod that writes more is evicted. See the chart README. |
| Per-call deadline | 30 minutes per `ExportDisk` and per `ImportDisk` call. |
| `options.compress` | Asks the source to compress a `qcow2` export. Only worth it on slow networks. |
| `options.timeout` | In v0.4.0 it bounds only the wait for a source snapshot task (2 hours when unset), not the migration. |

## Disk-size limit

If an administrator set `manager.maxDiskSize` (the manager flag `--max-disk-size`), or
lowered it for a Provider with the annotation `infra.virtrigaud.io/max-disk-size`, a
migration whose source disk is larger is **held** in its phase (reason
`DiskSizeExceedsLimit`, or `DiskSizeLimitUnverifiable` when the size cannot be read),
not failed. The size is read from the source provider at `Validating`, checked again
before the export and the import, and the target provider enforces the limit on the
disk it lands. Nothing changes unless the limit is set. See
[Disk-size limit](api-reference.md#administrator-disk-size-limit).

## Cross-namespace migrations

```yaml
spec:
  source:
    vmRef:
      name: vm-in-prod              # always in the migration's namespace
  target:
    name: vm-in-staging
    namespace: staging              # needs a grant on the "staging" Namespace
    providerRef:
      name: libvirt-provider
      namespace: infrastructure     # needs spec.consumerNamespaceSelector
```

- **The target namespace must grant the migration's namespace.** The Namespace
  `staging` needs the annotation
  `infra.virtrigaud.io/allowed-source-namespaces: "<migration namespace>"` (a
  comma-separated list of exact names). Whoever can `update` that Namespace can grant
  (normally a cluster administrator). Without it the migration is **held** with
  `Ready=False/TargetNamespaceNotAllowed` and nothing is created there; it resumes when
  the annotation appears. Revoking the grant stops a migration in flight.
- **The pinned Provider and VMClass must allow the target namespace** through
  `spec.consumerNamespaceSelector`, or the migration waits with `ConsumerNotAllowed`.
- The source VM is always in the migration's namespace, and
  `spec.source.providerRef`, if set, must be the Provider the source VM runs on.
- A granted migration's disk is **not attached in place**: the target VM treats it as a
  base image (libvirt copies it; a vSphere create is refused). A Proxmox target in
  another namespace fails at `Validating` (`ProxmoxCrossNamespaceTarget`), and so does
  a clustered libvirt target (`ClusteredTargetUnsupported`).
- With `s3` and `nfs` there is no shared mount, so the migration, source Provider and
  target Provider need not share a namespace. With `pvc` they must.
- The S3 credentials Secret is always read from the **migration's** namespace.

Details and the pre-upgrade query:
[Cross-namespace clone and migration targets](https://github.com/projectbeskar/virtrigaud/blob/main/docs/cross-namespace-targets.md).

## Migration into a clustered libvirt Provider (experimental)

A `VMMigration` whose target Provider has `topology: cluster` works differently from the
other directions. The migration creates its **target VirtualMachine first**, at
`Validating`; the clustered scheduler places it on a host whose `default` pool has room
for the disk; and only then is the source powered off, exported and imported. The import
lands on that host and the VM is created there with the disk attached in place. While it
waits for placement the migration shows the condition `TargetPlaced`, and
`status.storageInfo.importTarget.host` records the host.

What you need:

- `storage.type` of `s3` or `nfs`, set explicitly (`pvc`, which is what an unset
  `spec.storage` means, is refused).
- A target Provider that reports `supports_routed_import` (roll the clustered provider
  first), otherwise `Failed` with `ClusteredTargetUnsupported` before anything is
  touched. The target VM must be in the migration's own namespace.
- On every host: the `default` pool at `/var/lib/libvirt/images` (active, with room),
  `qemu-img`, `flock`, `timeout` and the cloud-init seed directory.

Limits: the disk-space check is a filter, not a reservation; the source disk's size is
read once; a host that fails after placement is **waited for, not replaced**; two
Providers whose hosts mount one pool are not serialised; and a waiting target's
`spec.importedDisk` can be edited by whoever may edit the VM (a swap is detected as
`TargetDiskMismatch`, not prevented). It was run in a lab from a single-host libvirt, a
vSphere (over S3 and NFS), and a Proxmox source; see the validation tables above. A host
made unreachable after the disk landed, a retry after an import and a held target of a
previous incarnation were not run in the lab.

Full guide: [Clustered libvirt](../guides/clustered-libvirt.md). Prerequisites, every
condition and how to clear it: [Migration into a clustered
provider](https://github.com/projectbeskar/virtrigaud/blob/main/docs/clustered-provider-inventory.md#migration-into-a-clustered-provider-addendum-b).
Example: [`examples/vmmigration-into-clustered.yaml`](https://github.com/projectbeskar/virtrigaud/blob/main/examples/vmmigration-into-clustered.yaml).

## The migrated guest's network

A migration copies the disk, not the NIC. What the guest does on first boot depends on
the target ([ADR-0014](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0014-migrated-guest-network.md),
**known limitation R36, not fixed in v0.4.0**):

| Target | Result with a Linux cloud-image guest whose netplan matches the NIC by MAC address (Ubuntu cloud images do) |
|--------|---------|
| **vSphere**, **Proxmox** | The guest can boot with **no network**. The target NIC has a new MAC, and cloud-init does not run again. The guest keeps its identity (by accident). |
| **libvirt** (single-host and clustered) | The network works only because the guest gets a **new cloud-init identity**: a new instance-id, hostname and SSH host keys, and per-instance modules run again. |

In the lab, vSphere <-> Proxmox migrations and a clustered libvirt -> Proxmox migration
produced guests with **no network**; the other combinations that were run (including
single-host libvirt <-> Proxmox and the migrations into a clustered libvirt Provider)
were reachable. What a guest does depends on how its image configures the network. The
accepted design (carry the source
NICs' MACs and present the source's instance-id, with a planned
`spec.options.guestIdentity: Preserve|Fresh`) is **not implemented**; only the Proxmox
network plumbing (bridge, VLAN, model, static IP) is. The manager also drops
`spec.networks[].macAddress` before every provider. Windows guests are outside the
design beyond carrying the MAC.

Until then: before you migrate, make the guest's netplan match its NIC by name or driver
instead of `macaddress`, or use a guest image that already does; and after a migrated
guest comes up without network, fix its network configuration from the console. Attach
the target to a network (`spec.target.networks`); a vSphere target needs a
`VMNetworkAttachment`.

## Multi-disk VMs

Only the **primary disk** is migrated. The controller sends one export with an empty disk
ID (each provider resolves it to the first, bootable disk) and records a single imported
disk on the target. Additional disks are not copied, and `spec.target.disks[]` is not
read. Move the data of other disks yourself.

## Upgrading with migrations in flight

From v0.3.11, follow the [upgrade guide](https://github.com/projectbeskar/virtrigaud/blob/main/docs/upgrading.md)
(and [Upgrade](../operations/upgrade.md)): CRDs first, then the manager, then the
providers promptly. Specific to migrations:

- **Let migrations in `Creating` or `Validating-Target` finish before the upgrade.** They
  created their target without the new UID and claim, so they **fail closed with
  `TargetVMNotOwned`** and their target VM is left as it is. For one that failed this
  way: check the target VM, delete the source yourself if you meant to
  (`deleteAfterMigration` does not run for a failed migration), and create the
  migration again.
- **Cross-namespace targets need a grant first.** List the affected objects before you
  upgrade (the query is in the cross-namespace document) and annotate each target
  namespace you want to keep allowing.
- **A Proxmox-target or vSphere-target migration that landed its disk before the
  upgrade and has no target VM yet must be run again**: stage and landing names now
  carry the namespace.
- **A provider pod that mounts migration PVCs is rolled once on the upgrade**, which
  interrupts an export or import running at that moment. Upgrade between migrations.
- **Roll the providers with the manager** so `DeleteStagedDisk` and `DeleteLandedDisk`
  are reported. Until then staged disks are held (24 hours) and landed disks are
  recorded as left behind.
- **An `nfs` migration with `uid: 0` or `gid: 0` now fails** at `Validating`.
- Migrations that were `Ready` before the upgrade delete nothing at their next
  reconcile (`SourceDeletionSkippedPreUpgrade`): remove their source snapshots and
  source VMs yourself if still wanted.
- A migration deleted after the upgrade does **not** clean up staged objects and landed
  disks left by migrations from earlier releases. See the leftovers list linked above.

## Examples in the main repository

Example manifests are in the main repository, in
[`examples/migration/`](https://github.com/projectbeskar/virtrigaud/tree/main/examples/migration)
(a README with the details, plus `libvirt-to-vsphere.yaml`, `vsphere-to-proxmox.yaml` and
`proxmox-to-libvirt.yaml`) and `examples/vmmigration-*.yaml`:

- [`vmmigration-s3.yaml`](https://github.com/projectbeskar/virtrigaud/blob/main/examples/vmmigration-s3.yaml) - S3 staging, vSphere to libvirt
- [`vmmigration-nfs.yaml`](https://github.com/projectbeskar/virtrigaud/blob/main/examples/vmmigration-nfs.yaml) - NFS staging
- [`vmmigration-proxmox-s3.yaml`](https://github.com/projectbeskar/virtrigaud/blob/main/examples/vmmigration-proxmox-s3.yaml) - Proxmox over S3
- [`vmmigration-into-clustered.yaml`](https://github.com/projectbeskar/virtrigaud/blob/main/examples/vmmigration-into-clustered.yaml) - into a clustered libvirt Provider (experimental)
- [`vmmigration-basic.yaml`](https://github.com/projectbeskar/virtrigaud/blob/main/examples/vmmigration-basic.yaml) and [`vmmigration-advanced.yaml`](https://github.com/projectbeskar/virtrigaud/blob/main/examples/vmmigration-advanced.yaml) - `pvc` staging, kept for compatibility

## See also

- [VM Migration API Reference](api-reference.md) - every field, status field, condition
  and reason.
- [VM Migration Guide](vm-migration-guide.md) - architectural deep dive (phase machine,
  controller orchestration, storage sequencing).
- [Clustered libvirt](../guides/clustered-libvirt.md) - migrating into a clustered Provider.
- [Resilience](../operations/resilience.md) - what happens when a provider flaps during a long migration.
- [Libvirt Host Preparation](../operations/libvirt-host-prepare.md) - host setup for libvirt migrations.
- [ADR-0006](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0006-storage-backend-agnostic-cross-hypervisor-migration.md) -
  storage-backend-agnostic migration.
- [ADR-0011](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0011-migration-staging-cleanup.md) -
  staged and landed disk cleanup.
- [ADR-0014](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0014-migrated-guest-network.md) -
  the migrated guest's identity and network.
