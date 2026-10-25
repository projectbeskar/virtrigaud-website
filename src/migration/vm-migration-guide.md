<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VM Migration Guide - architecture and internals

This page is the **architectural deep dive** for VirtRigaud's `VMMigration` flow in
v0.4.0. It complements the practical [User Guide](user-guide.md) and the
field-by-field [API Reference](api-reference.md).

If you want to migrate a VM today, start with the User Guide. If you want to
understand why the controller is organised the way it is, or you are debugging a
failed migration, read on.

## Where the code lives

| Concern | Location |
|--------|----------|
| `VMMigration` CRD Go types | `api/infra.virtrigaud.io/v1beta1/vmmigration_types.go` |
| Reconciler (phase machine, validation, export, import, target creation, deletion) | `internal/controller/vmmigration_controller.go` |
| Target VM ownership (claim and UID) | `internal/controller/vmmigration_target_binding.go` |
| Staged-disk cleanup (`DeleteStagedDisk`) | `internal/controller/vmmigration_staging_cleanup.go` |
| Landed-disk cleanup (`DeleteLandedDisk`) | `internal/controller/vmmigration_landed_disk_cleanup.go` |
| Source snapshot cleanup and task polling | `internal/controller/vmmigration_snapshot_cleanup.go`, `vmmigration_snapshot_task.go` |
| Post-migration (Ready) cleanup | `internal/controller/vmmigration_ready_cleanup.go` |
| Held provider calls (`...Requested` markers) | `internal/controller/vmmigration_request_marker.go`, `provider_request_marker.go` |
| Status writes that survive conflicts | `internal/controller/vmmigration_status_write.go` |
| Source power-off gate | `internal/controller/vmmigration_source_power.go` |
| Migration into a clustered Provider | `internal/controller/vmmigration_clustered_target*.go` |
| Cross-namespace and consumer grants | `internal/controller/crossnamespace.go`, `consumergrant.go` |
| Disk-size limit | `internal/controller/disk_size_limit*.go` |
| Provider pods' migration PVC mounts | `internal/controller/provider_migration_storage.go` |
| Staging layout, URLs, SSRF host policy, image checks | `internal/storage/migration/` |
| Provider RPC implementations | `internal/providers/{vsphere,libvirt,proxmox}/` (`ExportDisk`, `ImportDisk`, `staged_disk.go`, `landed_disk.go`) |
| Manager-side gRPC client | `internal/transport/grpc/client.go` |
| gRPC contract | `proto/provider/v1/provider.proto` |
| Design records | [ADR-0006](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0006-storage-backend-agnostic-cross-hypervisor-migration.md), [ADR-0007 Addendum B](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0007-clustered-orchestrator-provider.md), [ADR-0011](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0011-migration-staging-cleanup.md), [ADR-0014](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0014-migrated-guest-network.md) |

## What was validated

The [User Guide](user-guide.md#what-virtrigaud-v040-supports) has the full tables. In
short: v0.3.11 validated every pair among vSphere, libvirt and Proxmox over S3, and
five pairs over NFS (libvirt to libvirt, libvirt and vSphere both ways, libvirt and
Proxmox both ways). The v0.4.0 release candidates re-ran many of them, added migration
**into** a clustered libvirt Provider (single-host libvirt, vSphere and Proxmox sources,
over S3 and NFS) and out of a clustered Provider to Proxmox over S3, and ran `pvc` once
(vSphere to libvirt). The rest is covered by unit, envtest and simulator tests. All
lab runs used a single Proxmox VE node, never a PVE cluster.

## High-level model

```text
                    ┌──────────────────────────────────┐
                    │      VMMigration CR (CRD)        │
                    │  spec.source / target / storage  │
                    └──────────────┬───────────────────┘
                                   │ watch + reconcile
                                   ▼
            ┌───────────────────────────────────────────────┐
            │       VMMigrationReconciler (manager)         │
            │  phase machine: switch on status.phase        │
            └───────┬───────────────────────────┬───────────┘
                    │ gRPC                      │ gRPC
                    ▼                           ▼
           Source Provider                Target Provider
           SnapshotCreate                 ImportDisk
           ExportDisk                     DeleteStagedDisk
           SnapshotDelete                 DeleteLandedDisk
                    │                           │
                    └─────────► staging ◄───────┘
                              (S3 / NFS / PVC)

        The manager creates the target VirtualMachine itself; the
        VirtualMachine controller then creates the VM on the target Provider.
```

The decisive choice of ADR-0006 (replacing the earlier PVC-only model) is that the
**transfer medium is storage-backend-agnostic**: the disk is staged on an external S3
bucket or NFS export, not on a Kubernetes PVC mounted into provider pods.

1. **No shared PVC mount required.** Source and target providers reach the staging
   backend independently, which removes the namespace co-location constraint and opens
   up cross-namespace topologies.
2. **Per-backend credentials, defined once.** S3 credentials live in a Secret the
   manager reads; NFS is network-ACL-gated. The data plane gets the S3 credentials in
   the RPC, and they are never logged or placed in status.
3. **The disk never crosses CSI.** CSI-provisioned PVCs have host-level access
   constraints; external staging backends do not.
4. **The manager never touches the backend.** Dialling tenant-chosen S3 endpoints and
   NFS servers from the manager, which holds cluster-wide RBAC, would move the SSRF
   surface into the most privileged component. Every read, write and delete of a staged
   object is done by a provider ([ADR-0011](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0011-migration-staging-cleanup.md)),
   and the manager only checks the host against its SSRF policy first.

PVC mode is retained for backward compatibility. Its constraints: it works only
between vSphere and single-host libvirt, the migration and both Providers share one
namespace, and the provider pods mount the PVC only while a live migration references
it ([User Guide](user-guide.md#pvc-staging-legacy)).

## The phase machine

Phases are defined in `vmmigration_types.go` and dispatched in `Reconcile`.

```text
                      ┌─────────┐
                      │ Pending │
                      └────┬────┘
                           ▼
                   ┌────────────────┐
                   │  Validating    │ ─── any error ──┐
                   └──────┬─────────┘                 │
                          ▼                           │
                   ┌────────────────┐                 │
                   │ Snapshotting   │ (skipped when   │
                   └──────┬─────────┘  createSnapshot │
                          ▼            is false)      │
                   ┌────────────────┐                 │
                   │   Exporting    │ ─── any error ──┤
                   └──────┬─────────┘                 │
                          ▼                           │
                   ┌────────────────┐                 │
                   │   Importing    │ ─── any error ──┤
                   └──────┬─────────┘                 │
                          ▼                           │
                   ┌────────────────┐                 │
                   │   Creating     │ ─── any error ──┤
                   └──────┬─────────┘                 │
                          ▼                           ▼
              ┌─────────────────────┐         ┌─────────┐
              │  Validating-Target  │ ── err ─│ Failed  │
              └──────┬──────────────┘         └────┬────┘
                     ▼                             │ retryPolicy set and
                ┌─────────┐                        │ retries left: wait,
                │  Ready  │                        │ then back to Pending
                └─────────┘                        ▼
```

!!! note "`Transferring` and `Converting` exist but are never entered"
    The enum has eleven phases, but the controller moves from `Exporting` straight to
    `Importing`. The export **is** the transfer, and format conversion happens inside
    the target provider's `ImportDisk`. A migration found in `Transferring` or
    `Converting` (none is created by the controller) is advanced to `Importing`.

Holds are not failures. A migration waiting for a grant, a provider, a mount, a power-off,
a placement or an operator **stays in its phase** with a `False` condition and a reason
(see the [reasons table](api-reference.md#condition-reasons)); only a failure moves it to `Failed`.

### Per-phase responsibilities

| Phase | Handler | Key actions |
|-------|---------|-------------|
| `Pending` | `handlePendingPhase` | Moves to `Validating`; clears `SourcePowerOff` so a retry gets a fresh power-off budget. |
| `Validating` | `handleValidatingPhase` | No side effect on the hypervisors until the end. Refuse `nfs` uid/gid 0; check the target-namespace grant; check the target name is free or the migration's own; read the source VM (must have a provider ID); resolve the source Provider (must be the VM's own) and the target Provider with their consumer grants; Proxmox cross-namespace refusal; both Providers Ready; for a clustered target check `supports_routed_import`; disk-size limit; backend and transfer-mode gate against both Providers' advertised capabilities; storage configuration, SSRF host check, S3 credentials readable; for `pvc` create the PVC and wait for both provider pods to mount it (5 minutes). For a clustered target, create and place the target VM. Power the source off if requested (10 minutes). Record `sourceVMUID`. |
| `Snapshotting` | `handleSnapshottingPhase` | Use `snapshotRef`, or send `SnapshotCreate` (marker first, request token with the migration UID and attempt) and poll a snapshot task every 10 s, bounded by `options.timeout` (2 h when unset). Only a snapshot confirmed complete is exported; an unconfirmed one is discarded (`SnapshotDiscarded`) and taken again. |
| `Exporting` | `handleExportingPhase` | Record `StagingCleanup=Unknown`, the staging layout and digest **before** building the URL; re-check grants and the disk-size limit; send `ExportDisk` (marker first) with the staging URL, backend type, transfer mode and non-secret options JSON; credentials travel in the RPC. |
| `Importing` | `handleImportingPhase` | Re-check the target grant and Provider (not being deleted) and the size limit; record `importTarget` and `LandedDiskCleanup=Unknown`; send `ImportDisk` (marker first) with the target VM identity, the format and, with a limit set, `max_virtual_size_bytes`. A clustered target adds `target_host_id`. |
| `Creating` | `handleCreatingPhase` | Write the claim digest, then create the target `VirtualMachine` with `spec.importedDisk` (path and format from the import). Wait for a provider ID and `Ready=True`. For a clustered target the VM exists already; the landed disk is written into it. |
| `Validating-Target` | `handleValidatingTargetPhase` | Read the target live; require `Ready=True`; set `Phase=Ready`, `Ready=True/MigrationComplete`, close `LandedDiskCleanup`, set `PostMigrationCleanup=False`; annotate the target `migration-completed`. |
| `Ready` | `handleReadyPhase` | Staged-disk delete (retried in the background), then, only for a migration this manager completed, the source snapshot and `deleteAfterMigration`. |
| `Failed` | `handleFailedPhase`, `handleTerminalFailure` | With no `retryPolicy` or no retries left: cleanup only (the source snapshot unless `Never`; the staged and landed disks only with `Always`). Otherwise wait `retryDelay x backoffMultiplier^(n-1)` (30-minute cap), delete an unbound clustered target, release a binding to a vanished target VM, and return to `Pending`. |

### Idempotency and what survives a restart

A migration drives long, non-idempotent provider calls, so the controller is built so
that a restart, a leader change or a stale cache cannot send one twice by accident.

- **In-memory guard.** `ExportDisk` and `ImportDisk` are marked in flight per
  migration UID and generation before they are sent, so a reconcile that re-enters
  before the informer cache shows the result does not send them again. The status write
  after the call is not followed by an immediate requeue for the same reason.
- **Durable request markers.** `SnapshotRequested`, `ExportRequested` and
  `ImportRequested` are written (with the object's `resourceVersion` as precondition,
  so a failed write sends nothing) before the call, and removed with the result. A
  marker with no recorded result means the call may have run: the migration is held
  (`...OutcomeUnknown`), or the call is re-sent only where the provider reports it
  re-send safe, 35 minutes later, at most 3 times. Operator confirmation is the
  annotation `virtrigaud.io/operation-outcome=not-performed@<attempt id>`. See
  [User Guide](user-guide.md#a-migration-held-with-outcomeunknown) and
  [Provider calls whose outcome was lost](https://github.com/projectbeskar/virtrigaud/blob/main/docs/provider-call-outcomes.md).
- **Results are not lost to a conflict.** A status write that loses to a concurrent
  write is re-applied to the live object (same UID and phase) rather than dropped by a
  requeue. If it cannot be written at all, the result is kept in memory for the next
  reconcile (the guard keeps this process from sending the call again). A result for a
  migration that moved on or was re-created is dropped with a Warning event
  `ProviderResultNotRecorded`; the provider's ids are in the manager log.
- **Recorded before the side effect.** The staging layout and digest, the import
  target, the claim digest and the source VM UID are all written before the action that
  depends on them, so cleanup always knows what to look for and where.
- **Identifiers in status** (snapshot ID, export and import IDs, task reference, target
  VM ID and UID) let a re-reconcile resume without repeating work.
- **Reads before commits.** Steps that commit (marking the target `migration-completed`,
  `deleteAfterMigration`, the cleanup RPCs) act on a live read of the migration or the
  target, not on the cache.

## Target VM ownership

`VMMigration` creates the target `VirtualMachine` itself, in `spec.target.namespace`, so
the name in that namespace is a trust boundary. Since v0.4.0 the migration acts only on
the VM it created:

1. At `Validating` the target name must be free, or hold a VM carrying this migration's
   claim. Anything else fails the migration `TargetVMNotOwned` before the source is
   touched.
2. Before the `Create`, the controller persists `status.targetVMClaim` (the SHA-256 digest
   of a random token) with a conflict-checked write; no `Create` is sent unless it
   succeeds. The token goes on the VM as `virtrigaud.io/migration-claim`.
3. After the `Create`, `status.targetVMUID` is the binding. Every later step (wait,
   validate, annotate, delete) uses the UID; a VM is declared "not ours" only after a
   live re-read of both objects.
4. If the binding is lost (a status write failed, a restart), the claim recovers it: the
   VM whose token hashes to the digest is the migration's.
5. A bound VM that disappears is `TargetVMGone`; a retry releases the stale binding and
   creates a new target.

The landing disk follows the same rule: it is attached in place only for the VM the
migration created. A VM with a copied `spec.importedDisk` is handled as a base image. The
chart's `ValidatingAdmissionPolicy` additionally reserves the provenance annotations for
the manager (Kubernetes 1.30+). For a granted cross-namespace migration the lookup of
the migration in the VM's own namespace finds nothing, so the disk is copied or the
create is refused, never attached in place
([Cross-namespace targets](https://github.com/projectbeskar/virtrigaud/blob/main/docs/cross-namespace-targets.md)).

## Cleanup architecture

Three kinds of artifact outlive a failed or finished migration, and each is removed by an
RPC to a **provider**, with the same pattern ([ADR-0011](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0011-migration-staging-cleanup.md)):

| Artifact | RPC | Sent to | Condition |
|----------|-----|---------|-----------|
| Staged object (`nfs`, `s3`) | `DeleteStagedDisk` | the **target** Provider | `StagingCleanup` |
| Landed disk (any backend) | `DeleteLandedDisk` | the Provider the import was sent to (and, for a clustered target, the recorded host) | `LandedDiskCleanup` |
| Source snapshot | `SnapshotDelete` | the source Provider | `SnapshotCleanup` |

The pattern:

- **Mark before the side effect.** The condition is `Unknown` (`...MayExist`) from just
  before the export or import is sent, so even a failed, partial write is cleaned up.
- **The request names an identity, never a location.** The provider derives the object
  from the migration's namespace and name (validated DNS labels), the stage, and the
  recorded layout, using the same function the manager builds the URLs with
  (`StagedObjectKey`). The landed-disk request names the target VM recorded in
  `status.storageInfo.importTarget`, never the current `spec.target`, which a tenant can
  edit. A tenant can therefore only cause the deletion of objects named like a staging or
  landing object of a migration in its own namespace.
- **A digest guards edits.** `status.storageInfo.stagingDigest` hashes the backend, its
  non-secret options and the target Provider (namespace, name, UID). The delete is sent
  only while the current spec yields the same digest; otherwise the object is recorded
  as left behind rather than aimed somewhere else.
- **Idempotent, with holds.** A missing object is success. A delete that can still
  succeed is **held**: the condition is `False/...Pending`, a constant message and one
  Warning event are written (never a path, bucket or provider answer), and it is retried
  from 15 s doubling to 5 min. A deleting `VMMigration` keeps its finalizer meanwhile,
  and a Provider with a pending cleanup cannot be deleted (ADR-0010). A delete that can
  never succeed is released with a `...LeftBehind` Warning. `virtrigaud.io/force-delete=true`
  releases a stuck deletion.
- **Capability negotiation.** The manager sends the RPC only if the provider client
  implements it and `GetCapabilities` lists it: `supported_staged_disk_delete_backends`
  for the staged disk, `supports_landed_disk_delete` for the landed disk. An older
  provider is waited for (24 hours) for the staged disk; for the landed disk it is
  recorded as left behind at once.
- **Policy.** `cleanupPolicy` decides when: see the
  [User Guide](user-guide.md#cleanup-what-is-deleted-and-when). A `Ready` migration's
  landed disk is its target VM's, so `LandedDiskCleanup` is closed in the same status
  write that sets `Phase=Ready`.
- **How each provider deletes.** S3: stat, then remove the object (the pod is the S3
  client). NFS on libvirt and vSphere: `qemu-img` over libnfs cannot unlink, so the file
  is truncated to 0 bytes. NFS on Proxmox: kernel mount, then `rm` as the migration's
  uid/gid, and the node-side import stage of the target VM is removed too. Landed disk:
  vSphere removes the landing folder (after confirming no VM uses a file in it) and, at
  import time, the transient import VM's own files; libvirt removes
  `<default pool>/<namespace>.<vm>-migrated.qcow2` if no domain uses it; Proxmox removes
  the import stage.
- **Residual risk.** A versioned or object-lock bucket keeps the data; an NFS server
  snapshot keeps it; a symbolic link planted at the staging name on a shared NFS export
  could make the libvirt or vSphere truncation hit another file on that server (use one
  export per tenant); the in-use scans see only one vCenter or libvirt host.

**Post-migration cleanup** (source snapshot and `deleteAfterMigration`) runs only for
a migration that this manager completed: the status write that sets `Phase=Ready` also
sets `PostMigrationCleanup=False`, and only that marker authorises the source deletes.
A `Ready` migration from an older release is closed without deleting anything. The
source VM is deleted with a UID precondition on `status.sourceVMUID`.

## Grants and gates

Every phase that can call a provider or create something in a namespace passes through
the same gates:

- **Consumer grants** (`gateConsumers`): a Provider or VMClass in another namespace must
  select the migration's namespace (`spec.consumerNamespaceSelector`); re-read live
  right before the export, the import and the target `Create`. Refusal is a hold
  (`ConsumerNotAllowed`).
- **Target-namespace grant** (`gateTargetNamespace`): the Namespace annotation
  `infra.virtrigaud.io/allowed-source-namespaces`. Checked at `Validating`, `Importing`,
  `Creating`, `Validating-Target` and deletion, from the cache, and live before the
  import and the `Create`. The manager watches Namespace annotation changes, so a grant
  or a revocation takes effect at once. Refusal is a hold (`TargetNamespaceNotAllowed`).
- **Provider in use** (ADR-0010): a Provider being deleted is kept while a migration
  needs it; the import is not sent through a Provider being deleted
  (`ProviderDeleting`, read live).
- **Disk-size limit:** at `Validating`, before the export and before the import, and
  enforced by the target provider on the disk it lands.
- **Capability and backend gates** (`gateMigrationStorageBackend`): both Providers must
  advertise the backend; `direct` mode is refused; a clustered source or target refuses
  `pvc`. The opt-in `--enforce-provider-capabilities` adds a live capability check
  before the export and import.

## Migration into a clustered Provider

For a target Provider with `topology: cluster`
([ADR-0007 Addendum B](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0007-clustered-orchestrator-provider.md#addendum-b-2026-10-18-migration-into-a-clustered-provider-p3-cold-path),
experimental) the order inverts, because the disk must land on the host that will run
the VM:

1. At `Validating` the migration reads the source disk's size and creates the target
   `VirtualMachine` (with the usual claim), whose `spec.importedDisk` names the migration
   and has an empty `diskID`. The VirtualMachine controller places it with the ordinary
   scheduler, filtering hosts by `allocatableStorageBytes`, and holds it
   (`WaitingForImport`). The migration waits on `TargetPlaced`.
2. `Exporting` is unchanged.
3. `Importing` records the target's pending host in `importTarget.host` before the
   marker, and sends `ImportDisk` with `target_host_id` and the target's UID. A re-send,
   and the landed-disk and NFS staged-disk deletes, go to that host only.
4. `Creating` writes the landed disk into the existing target's `spec.importedDisk`; the
   VirtualMachine controller then creates the VM on its host with the disk attached in
   place. A target whose pending host moved, or whose `importedDisk` was changed, holds
   the migration (`TargetHostMoved`, `TargetDiskMismatch`).
5. A retry or deletion before the target is created deletes the unbound target first.

Summary and limits: [Clustered libvirt](../guides/clustered-libvirt.md); every reason:
[Migration into a clustered provider](https://github.com/projectbeskar/virtrigaud/blob/main/docs/clustered-provider-inventory.md#migration-into-a-clustered-provider-addendum-b).

## Reconciler instrumentation

- `virtrigaud_manager_reconcile_total{kind="VMMigration", outcome=...}` - one sample per
  reconcile (`success`, `error` or `requeue`).
- `virtrigaud_manager_reconcile_duration_seconds{kind="VMMigration"}` - reconcile latency.
- `virtrigaud_errors_total{reason, component="manager"}` - per-reason error counter;
  the migration controller records reasons such as `get-migration`, `consumer-not-allowed`,
  `disk-size-limit` and `provider-deleting`.

Indirect signals from the provider RPCs a migration drives:

- `virtrigaud_provider_rpc_requests_total{provider_type, method, code}` and
  `virtrigaud_provider_rpc_latency_seconds{provider_type, method}` for `ExportDisk`,
  `ImportDisk`, `SnapshotCreate`, `DeleteStagedDisk`, `DeleteLandedDisk` and the rest.
- `virtrigaud_circuit_breaker_state{provider_type, provider}` - one breaker per Provider.
  A long migration issues many RPCs back to back, so it is a demanding test of the
  breaker. See
  [Resilience](../operations/resilience.md#circuitbreaker-on-the-provider-grpc-path-v036).

## Provider-side responsibilities

The migration RPCs in `proto/provider/v1/provider.proto`:

```text
rpc SnapshotCreate(SnapshotCreateRequest) returns (SnapshotCreateResponse);
rpc SnapshotDelete(SnapshotDeleteRequest) returns (TaskResponse);
rpc ExportDisk(ExportDiskRequest) returns (ExportDiskResponse);
rpc ImportDisk(ImportDiskRequest) returns (ImportDiskResponse);
rpc GetDiskInfo(GetDiskInfoRequest) returns (GetDiskInfoResponse);
rpc DeleteStagedDisk(DeleteStagedDiskRequest) returns (DeleteStagedDiskResponse);
rpc DeleteLandedDisk(DeleteLandedDiskRequest) returns (DeleteLandedDiskResponse);
```

`GetCapabilities` carries what the manager gates on: `supported_export_backends`,
`supported_import_backends`, `supported_staged_disk_delete_backends`,
`supports_landed_disk_delete`, `supports_import_size_limit`,
`resend_safe_export_backends`, `resend_safe_import_backends` and
`supports_routed_import`. A provider image older than v0.4.0 does not report the last
five; the manager then holds or records leftovers as described above, so **roll the
providers with the manager**.

| Provider | Export | Import | Backends (export / import) |
|---------|--------|--------|----------------------------|
| **vSphere** | Clones the disk to a uniquely named temporary datastore copy, streams or converts it, then removes the copy. `s3`: upload from the pod; `nfs`: `qemu-img` in the pod over libnfs. | Converts the staged disk to a streamOptimized VMDK and uploads it through an NFC lease into `[<datastore>] <namespace>_<vm>-migrated/`; removes the transient import VM's own files. | `pvc`, `s3`, `nfs` / `pvc`, `s3`, `nfs` |
| **libvirt** (single host) | Flattens the disk with `qemu-img` on the host into a private directory (a backing chain becomes a standalone qcow2), then uploads it from the pod (`s3`) or converts it onto the export in place (`nfs`). | Downloads or reads the staged object, checks its header, converts into a private directory and renames the result onto `<default pool>/<namespace>.<vm>-migrated.qcow2`. | `pvc`, `s3`, `nfs` / `pvc`, `s3`, `nfs` |
| **libvirt** (`topology: cluster`) | The same host-side export, routed to the VM's bound host. | Routed to the target VM's pending host (`target_host_id`), under a host lock and `timeout(1)`. | `s3`, `nfs` / `s3`, `nfs` |
| **Proxmox** | REST API control plane plus an SSH data plane to the PVE node: the node flattens the disk and streams it to the pod (`s3`) or writes it to the kernel-mounted export (`nfs`). | The node stages the disk in `/var/lib/virtrigaud/import-stage/<namespace>_<vm>-migrated.<format>`, and the target VM's create imports it with `qm importdisk` and removes it. | `s3`, `nfs` / `s3`, `nfs` (not `pvc`) |
| **Mock** | Stages to `pvc` only; used in tests. | | |

### Proxmox hybrid data plane

The Proxmox provider is a hybrid: a REST API control plane (API token) plus an SSH data
plane to the PVE node. The provider `Secret` must carry the API token (`token_id`,
`token_secret`) **and** SSH credentials (`ssh_user` with `ssh_password` and/or
`ssh_privatekey`) plus a pinned `known_hosts` (host-key verification is on by default); without the SSH data plane no migration
disk can be staged or cleaned up. The create of the target VM accepts only the exact
stage `/var/lib/virtrigaud/import-stage/<namespace>_<vm>-migrated.<format>` for a
`VMMigration` in the VM's own namespace, which is why a Proxmox target in another
namespace is refused up front (`ProxmoxCrossNamespaceTarget`). Run one VirtRigaud
installation per PVE node: stage names are unique within one Kubernetes cluster only.
For NFS, the node kernel-mounts the export and presents the migration's `nfs.uid` and
`nfs.gid` through `setpriv`. A stage is removed when the target VM's create consumes it;
a migration that fails between import and create has its stage removed by the
landed-disk delete (tested against a simulated node only), and
[stale stages from earlier releases](https://github.com/projectbeskar/virtrigaud/blob/main/docs/upgrading.md#stale-proxmox-import-stages)
need a periodic sweep.

### The staging URL contract

The controller and providers exchange staging references so that the manager builds the
URL and the provider verifies it:

- **S3:** `s3://<bucket>/[<prefix>/]vmmigrations/<namespace>/<name>/export.vmdk`. The
  provider resolves the endpoint and region from the options JSON, never from the URL.
- **NFS:** an `nfs://<server>/<export>[/<path>]/vmmigrations_<namespace>_<name>_export.qcow2`
  URL with the uid/gid, built by one sanitising function (`NFSURL`) that rejects `..`,
  delimiters and control characters. Proxmox maps it to its kernel mount and rejects
  traversal again.
- **PVC (legacy):** `pvc://<pvc-name>/vmmigrations/<namespace>/<name>/export.qcow2`,
  resolved beneath the PVC mount with no symbolic link followed.

For S3 and NFS the source provider writes and the target provider reads independently;
the controller does not relay bytes.

### Import-time checks

The staged object comes from a backend the tenant controls, so its header is untrusted.
Every NFS and S3 import copies it once to a local file, parses its header, refuses an
image that references any other file or is not the expected format, and imports that
same copy. Copies and downloads are bounded
(`VIRTRIGAUD_MIGRATION_IMPORT_MAX_GIB`, default 1024 GiB, lowered by the disk-size limit)
and need twice the staged size free where they are made.

## Why the migration controller is the failure-prone one

`vmmigration_controller.go` and its companions are the most complex reconcilers in the
codebase, for reasons visible in the phase machine:

- **It owns external state in two providers and a staging backend**, and must survive any
  of them failing half-way. That is why so much of v0.4.0 is about knowing what to
  clean up (markers, digests, recorded targets) and what must never be touched
  (a VM it did not create, a disk a VM uses, a source it did not validate).
- **Long-running RPCs.** Exports and imports of large disks take a long time; each call
  has a 30-minute deadline in the gRPC client. A call that ends without a known outcome
  is held, not failed.
- **Many failure modes share a surface.** "Failed" can be a credentials problem, a
  network partition, an SSH host issue, a full staging backend, a refused image, a
  format-conversion error or a taken name. Messages in status are constant and safe, so
  the cause is usually in the provider log.

## ImportedDisk vs ImageRef on the target VM

The migration does **not** set `spec.imageRef` on the target. It sets `spec.importedDisk`
(the values below are examples):

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: my-vm-libvirt
  namespace: applications
  annotations:
    virtrigaud.io/migrated-from: applications/my-vsphere-vm
    virtrigaud.io/migration: applications/my-vm-to-libvirt
    virtrigaud.io/migration-claim: <one-time token>      # set by the manager
    virtrigaud.io/imported-disk-id: applications.my-vm-libvirt-migrated
    virtrigaud.io/migration-completed: "true"            # set at Ready
    virtrigaud.io/migration-completed-at: "2026-06-21T11:14:35Z"
spec:
  providerRef:
    name: libvirt-prod
  classRef:
    name: medium-vm
    namespace: applications
  powerState: "Off"
  importedDisk:
    diskID: applications.my-vm-libvirt-migrated
    path: /var/lib/libvirt/images/applications.my-vm-libvirt-migrated.qcow2
    format: qcow2
    source: migration
    migrationRef:
      name: my-vm-to-libvirt
  networks:
    - name: corp-bridge
```

Key properties:

- `importedDisk` and `imageRef` are mutually exclusive on a `VirtualMachine`.
- `importedDisk.path` is the provider-native path the import returned
  (`status.diskInfo.targetPath`) and is what the provider attaches. The provider attaches
  it in place only when it is the VM's own verified migration disk (libvirt: the file
  named for the VM; vSphere: the VM's landing folder; Proxmox: the exact import stage).
  Any other path is confined and copied, or refused.
- `importedDisk.migrationRef` names the migration in the VM's own namespace and is part of
  that proof. The target VM keeps working after the `VMMigration` is deleted.
- `importedDisk.diskID` is empty only on a clustered target that is waiting for its
  import, while `migrationRef` is set. `source` is one of `migration`, `clone`, `import`,
  `snapshot`, `manual`; the migration sets `migration`.

## Not implemented

- **Cross-cluster migration.** Both providers must be managed by the same VirtRigaud
  manager. The staging backends would allow federated migrations; this is not validated.
- **S3 direct mode.** `transferMode: direct` is rejected for `s3` and `pvc`; `auto`
  resolves to `relay`.
- **Live migration.** Every migration is cold. Live migration within a hypervisor family
  (vMotion, libvirt `migrate`) is a separate feature, and host-to-host migration inside a
  clustered libvirt Provider is not implemented either.
- **Additional disks.** Only the primary disk is migrated.
- **Post-import validation and progress.** `options.validationChecks` and
  `status.progress` are in the schema and not used.
- **A migrated guest's network and identity.** Designed in
  [ADR-0014](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0014-migrated-guest-network.md)
  (carry the source NICs' MACs, present the source's instance-id), not implemented; see
  [The migrated guest's network](user-guide.md#the-migrated-guests-network).

## See also

- [VM Migration User Guide](user-guide.md) - practical how-to.
- [VM Migration API Reference](api-reference.md) - every spec field, status field,
  condition and reason.
- [Clustered libvirt](../guides/clustered-libvirt.md) - migrating into a clustered Provider.
- [Resilience](../operations/resilience.md) - circuit breaker behaviour during long migrations.
- [Full CRD Reference](../references/generated-crd-docs.md#vmmigration) - generated CRD documentation.
- [ADR-0006](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0006-storage-backend-agnostic-cross-hypervisor-migration.md) -
  the storage-backend-agnostic migration model.
- [ADR-0011](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0011-migration-staging-cleanup.md) -
  staged and landed disk cleanup.
