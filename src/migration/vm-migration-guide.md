<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VM Migration Guide — architecture and internals

This page is the **architectural deep dive** for VirtRigaud's `VMMigration`
flow in v0.3.6. It complements the practical [User Guide](user-guide.md)
and the field-by-field [API Reference](api-reference.md).

If you want to migrate a VM today, start with the User Guide. If you want
to understand why the controller is organized the way it is, or you are
debugging a failed migration, read on.

## Where the code lives

| Concern | Location |
|--------|----------|
| `VMMigration` CRD Go types | `api/infra.virtrigaud.io/v1beta1/vmmigration_types.go` |
| Reconciler (~2074 LOC, the most complex in the codebase per `PROJECT_CONTEXT.md`) | `internal/controller/vmmigration_controller.go` |
| Storage validation | `internal/controller/vmmigration_controller.go:1419-1450` |
| Per-provider Export RPC implementations | `internal/providers/{vsphere,libvirt,proxmox}/server.go` — `ExportDisk` |
| Per-provider Import RPC implementations | Same files — `ImportDisk` (e.g. `internal/providers/libvirt/server.go:471-…` decodes `pvc://` URLs) |
| ADR for transport + storage design | [`docs/adr/0001-transport-grpc-and-capi-integration.md`](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0001-transport-grpc-and-capi-integration.md) |
| Field-test postmortems | `fieldTesting/MIGRATION_*.md` |

## v0.3.6 supported direction

!!! danger "vSphere → Libvirt is the only validated direction in v0.3.6"
    The migration controller and all three production providers have the
    full export / import / format-conversion code. The only direction
    smoke-tested on a real lab cluster in v0.3.6 is **vSphere → Libvirt**
    (see `fieldTesting/MIGRATION_SUCCESS_v0.3.62.md` and
    `fieldTesting/MIGRATION_VERIFICATION_v0.3.62.md`).

    Other directions (Libvirt → vSphere, Proxmox ↔ anything,
    vSphere → Proxmox) are alpha-quality in v0.3.6.

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
                │   migration.Status.Phase; vmmigration_         │
                │   controller.go:198-218)                      │
                └───────────────┬───────────────┬───────────────┘
                                │               │
              ┌─────────────────┘               └─────────────────┐
              ▼                                                   ▼
  Annotate Source + Target Provider CRs              Create / reuse intermediate PVC
   virtrigaud.io/migration-pvc=<pvc>                 (owned by VMMigration; ReadWriteMany)
              │                                                   │
              ▼                                                   │
  ProviderReconciler rolls provider Deployments                   │
  with the PVC added as a volume mount at                         │
  /mnt/migration-storage/<pvc-name>/                              │
              │                                                   │
              └───────────────┬───────────────────────────────────┘
                              ▼
                ┌──────────────────────────────────┐
                │  Migration proceeds through      │
                │  Snapshotting → Exporting →      │
                │  Transferring → Converting →     │
                │  Importing → Creating →          │
                │  Validating-Target → Ready       │
                └──────────────────────────────────┘
```

The decisive choice in v0.3.6 is that the **transfer medium is a Kubernetes
PVC**, not an external storage system. That choice is captured in
ADR-0001 ([docs/adr/0001-transport-grpc-and-capi-integration.md](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0001-transport-grpc-and-capi-integration.md))
and reflects three constraints:

1. **One credentials story.** Adding S3/HTTP/NFS would force a per-backend
   credentials/region/endpoint surface in the CRD and in every provider.
2. **K8s-native cleanup.** Owner references on the PVC make
   `kubectl delete vmmigration <name>` clean up the intermediate without
   bespoke controller logic.
3. **The operator already has a StorageClass.** Most clusters in the
   target deployment profile have RWX storage available; demanding NFS/EFS
   as a hard requirement is reasonable.

The trade-off is that **the disk has to fit in a PVC twice** (once for
the export, transiently again during format conversion). The User Guide's
sizing rule (1.5–2× source disk size) is the operational consequence.

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
| `Pending` | `handlePendingPhase` | Validates spec invariants, transitions to `Validating`. |
| `Validating` | `handleValidatingPhase` | Resolves source + target providers; validates `storage.type=pvc`; creates/reuses the PVC; **annotates both Provider CRs** to trigger a roll; waits for both providers `Ready`. (`vmmigration_controller.go:311-365`) |
| `Snapshotting` | `handleSnapshottingPhase` | If `spec.source.snapshotRef` is set, uses it. Else issues a `SnapshotCreate` RPC against the source provider. (`vmmigration_controller.go:369-…`) |
| `Exporting` | `handleExportingPhase` | Calls `ExportDisk` RPC on the source provider with a `pvc://<pvc-name>/…` destination. (`vmmigration_controller.go:469-…`) |
| `Transferring` | implicit during `Exporting` in PVC mode | In the PVC model the export *is* the transfer; the phase exists in the enum for backend models other than PVC. |
| `Converting` | `handleConvertingPhase` | If `options.diskFormat` differs from the exported format, runs `qemu-img convert` to a sibling file in the PVC. Skipped on format match. |
| `Importing` | `handleImportingPhase` | Calls `ImportDisk` RPC on the target provider with a `pvc://<pvc-name>/<file>` source. The libvirt provider decodes this at `internal/providers/libvirt/server.go:485-489`. |
| `Creating` | `handleCreatingPhase` | Creates the target `VirtualMachine` CR with `importedDisk` referencing the imported disk. |
| `Validating-Target` | `handleValidatingTargetPhase` | Runs the checks in `options.validationChecks`. `checkBoot` / `checkConnectivity` are opt-in. |
| `Ready` | terminal success | Annotates target VM `virtrigaud.io/migration-completed=true`; the migration CR can now be safely deleted without affecting the VM. |
| `Failed` | terminal failure | Bumps `status.retryCount`; if below `options.retryPolicy.maxRetries`, sets a requeue with `retryDelay * backoffMultiplier^retryCount` and resets `phase=Pending`. (`vmmigration_controller.go:1180-1190`) |

### Idempotency

Each phase handler is designed to be re-entrant. Concretely, the controller:

- Stores intermediate identifiers in `status` (snapshot ID, export task ID,
  import task ID, target VM ID) so a re-reconcile after a manager restart
  can resume without redoing work.
- Owns the PVC via owner references, so the K8s GC reclaims it on
  `VMMigration` delete even if the controller never gets a chance to run a
  cleanup pass.
- Uses K8s annotations on the Provider CRs (`virtrigaud.io/migration-pvc`,
  `virtrigaud.io/reconcile-trigger`) rather than direct state inside the
  Provider's `spec`, so re-running the same migration twice does not
  conflict with other migrations.

## Reconciler instrumentation

The reconciler is the most heavily instrumented in the codebase as of
v0.3.6:

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
  to back. The CB half-open accounting fix in PR
  [#100](https://github.com/projectbeskar/virtrigaud/pull/100) is what
  makes this reliable in v0.3.6.

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

Each in-tree provider implements these:

| Provider | Export | Import | Status |
|---------|--------|--------|--------|
| **vSphere** | `internal/providers/vsphere/server.go` — uses govmomi `NfcLease` to download the VM's disk to the PVC path. | vSphere is not a primary migration *target* in v0.3.6, but the RPC is wired. | Source side validated end-to-end. |
| **Libvirt** | Uses `virsh vol-download` (via the SSH'd `virsh` wrapper) to write the disk to the PVC. | `ImportDisk` decodes `pvc://` URLs to local PVC paths (`internal/providers/libvirt/server.go:485-489`) and uses `virsh vol-upload` (or copy + define) to register the imported volume. | Target side validated end-to-end. |
| **Proxmox** | Uses the Proxmox API to export the disk. | Uses the Proxmox API to import the disk. | Compiles; not validated in v0.3.6 lab. |
| **Mock** | No-op writes. | No-op reads. | Used in unit tests. |

The **PVC URL** is the consistent contract between the controller and the
providers. The source provider writes `pvc://<name>/disk.<fmt>` to its
mounted path; the target provider reads it from its mounted path. There is
no network transfer between providers — the data only crosses the PVC.

## Why the migration controller is the failure-prone one

Per `PROJECT_CONTEXT.md`, `vmmigration_controller.go` is the most complex
file in the codebase. The reasons are visible from the phase machine:

- **It owns external state in two providers and one PVC.** A simple VM
  reconciler owns external state in one provider. The migration controller
  has to coordinate a multi-actor dance and survive any of those actors
  failing.
- **The Provider-CR-roll step is unusual.** Most reconcilers don't modify
  *other* CRs to make their work go. The migration controller mutates both
  Provider CRs to add the PVC mount.
- **Long-running RPCs.** Exports and imports for large disks can take
  hours. The keep-alive tuning in
  [v0.3.51 (`GRPC_CONNECTION_AGE_FIX`)](https://github.com/projectbeskar/virtrigaud/blob/main/fieldTesting/GRPC_CONNECTION_AGE_FIX_v0.3.52.md)
  was a direct response to migrations failing because the SDK server was
  closing connections at 30s.
- **Many failure modes have the same surface.** "Phase=Failed, ProviderError"
  could be a credentials problem, a network partition, an SSH host issue,
  a disk-space issue on the PVC, a format-conversion error, a target VM
  with the same name already existing, etc. The reconciler tries to set
  helpful `status.conditions` but operators routinely need to consult the
  provider logs.

The fieldTesting postmortems (`fieldTesting/MIGRATION_*`) catalogue the
real-world failures the team has shipped fixes for. If your migration is
failing in a way that doesn't match the [User Guide
troubleshooting](user-guide.md#failure-modes-and-recovery), those notes
are worth reading even though they describe earlier versions.

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

The directions explicitly on the roadmap for after v0.3.6:

- **Validating the other provider directions.** Libvirt → vSphere is the
  inverse and conceptually trivial — the RPCs exist, the format conversion
  is `qcow2 → vmdk`. It is gated on a lab cycle, not new code.
- **Cross-cluster migration.** v0.3.6 assumes both providers are managed
  by the same VirtRigaud manager. Cross-cluster (federated) migrations
  would require a different transfer medium (probably S3 or HTTP) and is
  not on the v0.3.x scope.
- **Live migration.** All v0.3.x migrations are cold (snapshot-based).
  Live migration within a hypervisor family (vSphere vMotion, libvirt
  `migrate`) is a separate feature, not a `VMMigration` mode.
- **Per-Provider CircuitBreaker thresholds.** v0.3.6 uses
  `resilience.DefaultConfig()` uniformly. A long migration that legitimately
  takes hours might want a higher `FailureThreshold` than a short
  `Describe`-driven reconcile loop. Tracked on the resilience roadmap.

## See also

- [VM Migration User Guide](user-guide.md) — practical how-to.
- [VM Migration API Reference](api-reference.md) — every spec field with
  defaults and validation rules.
- [Resilience](../operations/resilience.md) — CircuitBreaker behavior
  during long migrations.
- [Full CRD Reference](../references/generated-crd-docs.md#vmmigration) —
  generated CRD documentation.
- [`docs/adr/0001-transport-grpc-and-capi-integration.md`](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0001-transport-grpc-and-capi-integration.md) — design rationale for gRPC + PVC.
- Field-test postmortems: `fieldTesting/MIGRATION_*.md` in the main repo.
