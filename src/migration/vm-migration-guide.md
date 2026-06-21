<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VM Migration Guide — architecture and internals

This page is the **architectural deep dive** for VirtRigaud's `VMMigration`
flow in v0.3.11. It complements the practical [User Guide](user-guide.md)
and the field-by-field [API Reference](api-reference.md).

If you want to migrate a VM today, start with the User Guide. If you want
to understand why the controller is organized the way it is, or you are
debugging a failed migration, read on.

## Where the code lives

| Concern | Location |
|--------|----------|
| `VMMigration` CRD Go types | `api/infra.virtrigaud.io/v1beta1/vmmigration_types.go` |
| Reconciler (~2074 LOC, the most complex in the codebase per `PROJECT_CONTEXT.md`) | `internal/controller/vmmigration_controller.go` |
| Storage validation + SSRF gate | `internal/controller/vmmigration_controller.go:1419-1450` |
| Per-provider Export RPC implementations | `internal/providers/{vsphere,libvirt,proxmox}/server.go` — `ExportDisk` |
| Per-provider Import RPC implementations | Same files — `ImportDisk` |
| ADR for storage-backend-agnostic design | [`docs/adr/0006-storage-backend-agnostic-cross-hypervisor-migration.md`](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0006-storage-backend-agnostic-cross-hypervisor-migration.md) |
| Field-test postmortems | `fieldTesting/MIGRATION_*.md` |

## Validated direction matrix (v0.3.11)

!!! info "All three providers validated in both directions"
    As of v0.3.11 (ADR-0006 Slices 1–4,
    [#236](https://github.com/projectbeskar/virtrigaud/issues/236)), all three
    providers — **vSphere**, **Libvirt/KVM**, and **Proxmox VE** — are validated
    as both source and target, in any direction, over both S3 and NFS staging
    backends.

    | S3 (Slices 1–3) | NFS (Slice 4, 2026-06-21) |
    |----------------|--------------------------|
    | vSphere ⇄ Libvirt | libvirt ↔ libvirt |
    | vSphere ⇄ Proxmox | libvirt → vSphere |
    | Libvirt ⇄ Proxmox | vSphere → libvirt |
    |  | libvirt → Proxmox |
    |  | Proxmox → libvirt |

    NFS validation was performed against a real OpenMediaVault server. All
    listed pairs reached `Ready`.

!!! note "v0.3.8 disk-transfer improvements (still in effect)"
    The libvirt provider supports disk export
    ([#177](https://github.com/projectbeskar/virtrigaud/pull/177)), and the
    vSphere provider advertises its disk export/import capabilities accurately
    ([#178](https://github.com/projectbeskar/virtrigaud/pull/178)) so the
    optional `--enforce-provider-capabilities` gate
    ([#176](https://github.com/projectbeskar/virtrigaud/pull/176), default off)
    makes trustworthy fail-close decisions. See the
    [API Reference](api-reference.md#capability-gating-176-fail-close-on-providers-lacking-exportimport).

## High-level model

```text
                    ┌──────────────────────────────────┐
                    │      VMMigration CR (CRD)        │
                    │  spec.source / target / storage  │
                    └──────────────┬───────────────────┘
                                   │ watch + reconcile
                                   ▼
            ┌───────────────────────────────────────────────┐
            │       VMMigrationReconciler                   │
            │  (~2074 LOC, phase machine in switch on       │
            │   migration.Status.Phase;                     │
            │   vmmigration_controller.go:198-218)          │
            └───────────────┬───────────────┬───────────────┘
                            │               │
          ┌─────────────────┘               └──────────────────┐
          ▼                                                     ▼
  Annotate Source + Target Provider CRs          Validate + prepare staging backend
  virtrigaud.io/migration-pvc=<pvc>              (S3 bucket/key; NFS export/file;
  (PVC mode only)                                 or PVC for compat)
          │                                                     │
          └───────────────┬─────────────────────────────────────┘
                          ▼
            ┌──────────────────────────────────┐
            │  Migration proceeds through      │
            │  Snapshotting → Exporting →      │
            │  Transferring → Converting →     │
            │  Importing → Creating →          │
            │  Validating-Target → Ready       │
            └──────────────────────────────────┘
```

The decisive architectural choice adopted in ADR-0006 (superseding the earlier
PVC-only model) is that the **transfer medium is storage-backend-agnostic**:
the disk is staged on an external S3 bucket or NFS export, not on a Kubernetes
PVC mounted into provider pods. ADR-0006 captures the rationale:

1. **No shared PVC mount required.** Source and target providers reach the
   staging backend independently, which removes the co-location requirement
   and opens up cross-namespace and cross-cluster topologies.
2. **Per-backend credentials, done once.** S3 credentials live in a Secret;
   NFS is network-ACL-gated. Each backend's credentials story is defined once
   in the CRD, not reimplemented per provider.
3. **The disk never crosses CSI.** CSI-provisioned PVCs have host-level
   access constraints; external staging backends do not.

PVC mode is retained for backward compatibility. It is no longer the
recommended path.

!!! note "S3 and NFS remove the shared-mount co-location constraint"
    The old PVC model required both provider pods to mount the same PVC,
    which forced the `VMMigration`, source `Provider`, and target `Provider`
    to share a namespace (a pod can only mount a PVC from its own namespace).
    With S3 or NFS backends, there is no shared mount. The staging medium is
    an external server reachable by both legs independently, which removes the
    namespace co-location constraint as a transfer-medium artifact.

    Cross-namespace migrations with S3/NFS backends are supported. Cross-cluster
    migrations (source and target managed by different VirtRigaud managers) are
    not yet validated as of v0.3.11 and would require additional Secret
    propagation; consult the roadmap.

## The phase machine

Phases are defined at `vmmigration_types.go:363-390`. The reconciler
dispatches on `migration.Status.Phase` at
`vmmigration_controller.go:198-218`.

```text
                      ┌─────────┐
                      │ Pending │
                      └────┬────┘
                           │
                           ▼
                   ┌────────────────┐
                   │  Validating    │ ─── any error ──┐
                   └──────┬─────────┘                 │
                          │                           │
                          ▼                           │
                   ┌────────────────┐                 │
                   │ Snapshotting   │ ─── any error ──┤
                   └──────┬─────────┘                 │
                          │                           │
                          ▼                           │
                   ┌────────────────┐                 │
                   │   Exporting    │ ─── any error ──┤
                   └──────┬─────────┘                 │
                          │                           │
                          ▼                           │
                   ┌────────────────┐                 │
                   │  Transferring  │ ─── any error ──┤
                   └──────┬─────────┘                 │
                          │                           │
                          ▼                           │
                   ┌────────────────┐                 │
                   │  Converting    │ ─── any error ──┤
                   └──────┬─────────┘                 │
                          │                           │
                          ▼                           │
                   ┌────────────────┐                 │
                   │   Importing    │ ─── any error ──┤
                   └──────┬─────────┘                 │
                          │                           │
                          ▼                           │
                   ┌────────────────┐                 │
                   │   Creating     │ ─── any error ──┤
                   └──────┬─────────┘                 │
                          │                           │
                          ▼                           ▼
              ┌─────────────────────┐         ┌─────────┐
              │  Validating-Target  │ ────────│ Failed  │
              └──────┬──────────────┘   error └────┬────┘
                     │                             │
                     ▼                             │
                ┌─────────┐                   retry│ (per
                │  Ready  │                   loop │  options.retryPolicy)
                └─────────┘                        │
                                                   ▼
                                             ┌─────────┐
                                             │ Pending │
                                             └─────────┘
```

### Per-phase responsibilities

| Phase | Reconciler entry | Key actions |
|-------|------------------|-------------|
| `Pending` | `handlePendingPhase` | Validates spec invariants; transitions to `Validating`. |
| `Validating` | `handleValidatingPhase` | Resolves source + target providers; validates `storage.type` and backend config; SSRF-checks NFS/S3 server hostname against `--migration-storage-allowed-hosts`; for PVC mode, creates/reuses the PVC and waits for both providers to have it mounted. For S3/NFS modes, prepares the staging path (no provider pod roll required). |
| `Snapshotting` | `handleSnapshottingPhase` | If `spec.source.snapshotRef` is set, uses it. Else issues a `SnapshotCreate` RPC against the source provider. (`vmmigration_controller.go:369-…`) |
| `Exporting` | `handleExportingPhase` | Calls `ExportDisk` RPC on the source provider with the staging target (S3 URL, NFS path, or `pvc://` URL depending on backend). |
| `Transferring` | implicit during `Exporting` in S3/NFS modes | For S3 and NFS, the export IS the transfer. The phase exists in the enum for all backends. |
| `Converting` | `handleConvertingPhase` | If `options.diskFormat` differs from the exported format, the target provider converts via `qemu-img`. Skipped on format match. For NFS, conversion happens at the target leg (reads from NFS mount, writes converted output). |
| `Importing` | `handleImportingPhase` | Calls `ImportDisk` RPC on the target provider with the staging source reference. |
| `Creating` | `handleCreatingPhase` | Creates the target `VirtualMachine` CR with `importedDisk` referencing the imported disk. |
| `Validating-Target` | `handleValidatingTargetPhase` | Runs the checks in `options.validationChecks`. `checkBoot` / `checkConnectivity` are opt-in. |
| `Ready` | terminal success | Annotates target VM `virtrigaud.io/migration-completed=true`; the migration CR can now be safely deleted without affecting the VM. |
| `Failed` | terminal failure | Bumps `status.retryCount`; if below `options.retryPolicy.maxRetries`, resets `phase=Pending` with backoff. (`vmmigration_controller.go:1180-1190`) |

### Idempotency

Each phase handler is designed to be re-entrant. Concretely, the controller:

- Stores intermediate identifiers in `status` (snapshot ID, export task ID,
  import task ID, target VM ID) so a re-reconcile after a manager restart
  can resume without redoing work.
- For PVC mode, owns the PVC via owner references so the K8s GC reclaims it
  on `VMMigration` delete. As of v0.3.8, the `ProviderReconciler` no longer
  deletes migration-storage PVCs
  ([#184](https://github.com/projectbeskar/virtrigaud/pull/184)).
- For S3/NFS mode, the staged object is deleted by the controller's cleanup
  pass per `options.cleanupPolicy`, and on finalizer processing.
- Uses K8s annotations on the Provider CRs (`virtrigaud.io/migration-pvc`,
  `virtrigaud.io/reconcile-trigger`) for PVC-mode co-ordination. S3/NFS modes
  do not annotate providers.

## Reconciler instrumentation

The reconciler is the most heavily instrumented in the codebase:

- `virtrigaud_manager_reconcile_total{name="VMMigration", outcome=…}` —
  every reconcile records one sample. The
  G3 + K5 double-count fix in PR
  [#106](https://github.com/projectbeskar/virtrigaud/pull/106) made this
  accurate; earlier releases recorded two samples per errored reconcile.
- `virtrigaud_manager_reconcile_duration_seconds{name="VMMigration"}` —
  histogram of reconcile latency.
- `virtrigaud_errors_total{reason="get_migration", controller="VMMigration"}` —
  per-reason error counter.

Plus the indirect signals from the provider RPCs the migration drives:

- `virtrigaud_provider_rpc_requests_total{method=ExportDisk|ImportDisk|SnapshotCreate|…}` —
  per-RPC throughput.
- `virtrigaud_circuit_breaker_state{provider_type, provider}` — one breaker
  per Provider CR (G6 / PR
  [#112](https://github.com/projectbeskar/virtrigaud/pull/112)).
  **A long migration is the most demanding test of CircuitBreaker
  semantics** because a single migration can issue many provider RPCs back
  to back.

See [Resilience](../operations/resilience.md#circuitbreaker-on-the-provider-grpc-path-v036)
for the breaker's behavior in detail.

## Provider-side responsibilities

The proto contract for the migration-specific RPCs is in
`proto/provider/v1/provider.proto`:

```text
rpc ExportDisk(ExportDiskRequest) returns (ExportDiskResponse);   // proto.proto:296
rpc ImportDisk(ImportDiskRequest) returns (ImportDiskResponse);   // proto.proto:297
rpc GetDiskInfo(GetDiskInfoRequest) returns (GetDiskInfoResponse);// proto.proto:298
rpc SnapshotCreate(SnapshotCreateRequest) returns (SnapshotCreateResponse); // proto.proto:282
```

Each in-tree provider implements these. The staging backend determines the
transport mechanism for ExportDisk/ImportDisk:

| Provider | Export | Import | NFS transport | S3 transport | Status |
|---------|--------|--------|--------------|-------------|--------|
| **vSphere** | `internal/providers/vsphere/server.go` — uses govmomi `NfcLease` to export the VM's disk; for NFS, the provider pod runs `qemu-img` against `nfs://` via libnfs (`qemu-block-extra`). | Imports the converted disk via the vSphere API. | Pod-side `qemu-img nfs://` (libnfs) | Pod → S3 relay | Validated source and target. |
| **Libvirt** | Supports disk export ([#177](https://github.com/projectbeskar/virtrigaud/pull/177)) — uses `virsh vol-download` (via SSH). For NFS: the libvirt **host** runs `qemu-img nfs://` directly. | `ImportDisk` registers the imported volume; for NFS the host reads from the NFS mount. | Host-side `qemu-img nfs://` (libnfs) | Host → S3 relay via provider pod | Validated source and target. |
| **Proxmox** | Uses the Proxmox REST API + SSH data plane. The PVE node streams the disk via SSH to the provider pod (S3) or kernel-mounts the NFS export and runs `qemu-img` against it. | Imports via PVE API from the NFS kernel mount or from the S3 relay path. | PVE node kernel NFS mount + `qemu-img` | SSH + pod S3 relay | Validated source and target (ADR-0006 Slices 2–4). |
| **Mock** | No-op writes. | No-op reads. | — | — | Used in unit tests. |

### Proxmox hybrid data plane

The Proxmox provider is a hybrid: a REST API control plane (API token auth)
plus an SSH data plane to the PVE node. For S3 migration the node-side
`qemu-img`/`qm` streams over SSH into the provider pod (the S3 client). The
Proxmox `Provider` Secret must carry both an API token (`token_id` /
`token_secret`) AND SSH credentials (`ssh_user` + `ssh_password` and/or
`ssh_privatekey`) plus a pinned `known_hosts`. The pod reaches the node by IP
(`PROVIDER_ENDPOINT` = PVE IP) with `known_hosts` pinned to that IP because
in-cluster DNS does not resolve the PVE hostname.

For NFS migration, the PVE node kernel-mounts the export. The NFS AUTH_SYS
uid/gid presented by the Proxmox provider is controlled by `nfs.uid` / `nfs.gid`
via `setpriv` on the node — set them to the uid/gid that owns the export files.

### The staging URL contract

The controller and providers exchange staging references via:

- **S3:** `s3://<bucket>/<key>` — the provider resolves bucket + endpoint from
  the migration's S3 config.
- **NFS:** a path relative to the NFS mount (the kernel-mount or libnfs URL is
  constructed by the provider from `server`/`export`/`path`).
- **PVC (compat):** `pvc://<pvc-name>/disk.<fmt>` — the libvirt provider decodes
  this at `internal/providers/libvirt/server.go:485-489`.

For S3 and NFS backends, no data crosses a shared PVC. The source provider
writes independently to the staging backend; the target provider reads
independently. The controller does not relay bytes.

## Why the migration controller is the failure-prone one

Per `PROJECT_CONTEXT.md`, `vmmigration_controller.go` is the most complex
file in the codebase. The reasons are visible from the phase machine:

- **It owns external state in two providers and a staging backend.** A simple VM
  reconciler owns external state in one provider. The migration controller
  has to coordinate a multi-actor dance and survive any of those actors
  failing.
- **Long-running RPCs.** Exports and imports for large disks can take
  hours. The keep-alive tuning in
  [v0.3.51 (`GRPC_CONNECTION_AGE_FIX`)](https://github.com/projectbeskar/virtrigaud/blob/main/fieldTesting/GRPC_CONNECTION_AGE_FIX_v0.3.52.md)
  was a direct response to migrations failing because the SDK server was
  closing connections at 30s.
- **Many failure modes have the same surface.** "Phase=Failed, ProviderError"
  could be a credentials problem, a network partition, an SSH host issue,
  a disk-space issue on the staging backend, a format-conversion error, a
  target VM with the same name already existing, etc. The reconciler tries
  to set helpful `status.conditions` but operators routinely need to consult
  the provider logs.

The fieldTesting postmortems (`fieldTesting/MIGRATION_*`) catalogue the
real-world failures the team has shipped fixes for.

## ImportedDisk vs ImageRef on the target VM

When the migration creates the target `VirtualMachine`, it does **not** set
`spec.imageRef`. It sets `spec.importedDisk` instead:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: my-vm-libvirt
  namespace: applications
  annotations:
    virtrigaud.io/migrated-from: applications/my-vsphere-vm
    virtrigaud.io/migration: applications/my-vm-to-libvirt
    virtrigaud.io/migration-completed: "true"
    virtrigaud.io/migration-completed-at: "2026-05-23T11:14:35Z"
spec:
  providerRef:
    name: libvirt-prod
    namespace: virtrigaud-system
  classRef:
    name: medium-vm
  importedDisk:
    diskID: my-vm-libvirt-disk
    format: qcow2
    source: migration
    migrationRef:
      name: my-vm-to-libvirt
  networks:
    - name: corp-bridge
```

Key properties:

- `importedDisk` and `imageRef` are **mutually exclusive** on a
  `VirtualMachine` spec.
- `importedDisk.diskID` is the provider-specific disk identifier (e.g.
  libvirt volume name) — the provider knows how to resolve this to a path.
- `importedDisk.migrationRef` is purely audit / traceability. The target
  VM continues to function even after the `VMMigration` CR is deleted.
- `importedDisk.source` is one of `migration`, `clone`, `import`, `snapshot`,
  `manual`. The migration controller sets it to `migration`.

You can also create a `VirtualMachine` with `importedDisk` **outside the
migration flow** — useful for adopting an existing disk from a manual
import or a clone. Set `source: manual` in that case.

## Roadmap

- **Cross-cluster migration.** v0.3.11 assumes both providers are managed
  by the same VirtRigaud manager. Cross-cluster (federated) migrations over
  S3 are architecturally unblocked by ADR-0006 but not yet validated.
- **S3 direct mode.** `transferMode: direct` is a roadmap item — the source
  provider would write directly to S3 without relaying through the pod. Not
  implemented in v0.3.11; `auto` resolves to `relay`.
- **Live migration.** All v0.3.x migrations are cold (snapshot-based).
  Live migration within a hypervisor family (vSphere vMotion, libvirt
  `migrate`) is a separate feature, not a `VMMigration` mode.
- **Per-Provider CircuitBreaker thresholds.** v0.3.11 still uses
  `resilience.DefaultConfig()` uniformly. A long migration might want a
  higher `FailureThreshold` than a short `Describe`-driven reconcile.

## See also

- [VM Migration User Guide](user-guide.md) — practical how-to.
- [VM Migration API Reference](api-reference.md) — every spec field with
  defaults and validation rules.
- [Resilience](../operations/resilience.md) — CircuitBreaker behavior
  during long migrations.
- [Full CRD Reference](../references/generated-crd-docs.md#vmmigration) —
  generated CRD documentation.
- [`docs/adr/0006-storage-backend-agnostic-cross-hypervisor-migration.md`](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0006-storage-backend-agnostic-cross-hypervisor-migration.md) — design rationale for the storage-backend-agnostic migration model.
- Field-test postmortems: `fieldTesting/MIGRATION_*.md` in the main repo.
