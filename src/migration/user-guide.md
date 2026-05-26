<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VM Migration User Guide

This page is aligned to **VirtRigaud v0.3.6**. It is the practical
"how do I move a VM?" guide. For the field-by-field CRD reference see
[API Reference](api-reference.md); for the architectural model see
[VM Migration Guide](vm-migration-guide.md).

## What VirtRigaud v0.3.6 actually supports

!!! danger "Read this before you plan a migration"
    **The only provider direction smoke-tested end-to-end on a real lab in
    v0.3.6 is vSphere → Libvirt** (see
    `fieldTesting/MIGRATION_SUCCESS_v0.3.62.md` and
    `fieldTesting/MIGRATION_VERIFICATION_v0.3.62.md`). The migration
    controller, the exporter/importer code paths in each provider, and the
    PVC orchestration are all in place for the other directions, but they
    have **not been validated in v0.3.6**.

    If you need a different direction (Libvirt → vSphere, vSphere →
    Proxmox, Proxmox → Libvirt, etc.) you should:

    1. Treat it as **alpha** for v0.3.6.
    2. Smoke-test it in non-production first.
    3. Be prepared to file issues — the team has been catching real bugs in
       the migration controller every release (`fieldTesting/MIGRATION_*`).

!!! warning "Storage transfer is a Kubernetes PVC, not S3/HTTP/NFS"
    The earlier draft of this page described `s3`, `http`, and `nfs` storage
    backends. **Those are not implemented in v0.3.6.** The migration
    controller validates `storage.type != "pvc" && storage.type != ""` and
    rejects the migration with
    `unsupported storage type: <X> (only 'pvc' is supported)`
    (`internal/controller/vmmigration_controller.go:1425`). The intermediate
    storage is a `ReadWriteMany` PVC mounted into both provider pods. See
    [Storage](#storage) below for sizing guidance.

## Concept in one diagram

```text
┌──────────────────────────┐        ┌──────────────────────────┐
│   Source Provider Pod    │        │   Target Provider Pod    │
│   (e.g. provider-vsphere)│        │   (e.g. provider-libvirt)│
│                          │        │                          │
│  /mnt/migration-storage  │        │  /mnt/migration-storage  │
│       ↘                  │        │                ↙         │
│        write disk        │        │        read disk         │
│             ↓            │        │             ↑            │
└─────────────│────────────┘        └─────────────│────────────┘
              ▼                                   ▼
        ╔═══════════════════════════════════════════════════╗
        ║      Migration PVC (ReadWriteMany, e.g. NFS)      ║
        ║  Owned by the VMMigration CR — auto-cleanup on    ║
        ║  deletion. Created or reused by the controller.   ║
        ╚═══════════════════════════════════════════════════╝
                      │
                      │ orchestrated by
                      ▼
                ┌────────────────────────────────┐
                │  VMMigration controller        │
                │  (vmmigration_controller.go,   │
                │  ~2074 LOC; phase machine)     │
                └────────────────────────────────┘
```

Three things happen in sequence, all driven by the migration controller:

1. **Validate + mount.** Source and target providers get the migration PVC
   added to their Deployment volume mounts and roll. (One-time per
   migration; adds ~30–60s of rolling-restart latency per provider pod.)
2. **Export → PVC.** The source provider snapshots (if requested), then
   writes the disk to `/mnt/migration-storage/<pvc-name>/...`.
3. **Import → target.** The target provider reads the disk back from the
   PVC, optionally converts format via `qemu-img`, and creates the target
   VM.

## Quick start: vSphere → Libvirt

This is the path that v0.3.6 actually exercises end-to-end. The other
directions follow the same shape but should be considered alpha.

### Prerequisites

- A working VirtRigaud install on the cluster (manager + both providers
  `Ready`).
- A source `VirtualMachine` already managed by the vSphere provider.
- A target `Provider` CR for Libvirt that points at a prepared host
  (see [Libvirt Host Preparation](../operations/libvirt-host-prepare.md)).
- A StorageClass on the cluster that can provision `ReadWriteMany` volumes
  (NFS, EFS, Longhorn-RWX, CephFS, etc.).
- Free PVC capacity ≥ **2× the source disk size**: the disk lives in the
  PVC during transfer and the target provider may also write a converted
  copy alongside.

### Minimal VMMigration

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMMigration
metadata:
  name: my-vm-to-libvirt
  namespace: applications
spec:
  source:
    vmRef:
      name: my-vsphere-vm
    createSnapshot: true
    powerOffBeforeMigration: true     # safer; cold-migration
    deleteAfterMigration: false       # keep source for rollback

  target:
    name: my-vm-libvirt
    providerRef:
      name: libvirt-prod
      namespace: virtrigaud-system
    classRef:
      name: medium-vm                 # VMClass on the target
    networks:
      - name: corp-bridge             # VMNetworkAttachment on the target
    powerOn: false                    # start cold; operator powers on after verify

  options:
    diskFormat: qcow2                 # libvirt-native target format
    verifyChecksums: true             # default; SHA256 verify after import
    timeout: 4h

  storage:
    type: pvc                         # the only valid value in v0.3.6
    pvc:
      storageClassName: nfs-client
      size: 100Gi
      accessMode: ReadWriteMany
```

Apply and watch:

```bash
kubectl apply -f my-vm-to-libvirt.yaml

# Watch phase progression
kubectl get vmmigration my-vm-to-libvirt -w

# Detailed status (conditions, events, intermediate PVC name)
kubectl describe vmmigration my-vm-to-libvirt
```

A successful run progresses Pending → Validating → Snapshotting → Exporting
→ Transferring → Converting → Importing → Creating → Validating-Target →
Ready. End-to-end time depends on disk size + storage throughput.

## Storage

### Why PVC, not S3/HTTP/NFS

The design rationale is captured in
`fieldTesting/ADR-0001-transport-grpc-and-capi-integration.md`. Briefly:

- The PVC model treats the intermediate as a first-class K8s resource:
  owned by the `VMMigration` CR, garbage-collected on delete, observable in
  `kubectl get pvc`.
- It avoids inventing a new credentials story per backend (the S3/HTTP/NFS
  variant would need credentials secrets, region/endpoint fields, and a
  client per backend in every provider).
- It uses the same StorageClass capabilities the operator already has
  (NFS/CSI/whatever).

### Sizing the PVC

The conservative formula is:

```text
PVC size  ≥  source_disk_size_GiB
             + headroom_for_format_conversion (~0.1 × source on average)
             + safety_margin (10–20 %)
```

In practice, **size the PVC at 1.5× to 2× the source disk size** for
v0.3.6. The provider writes the export, then (in the conversion phase, if
formats differ) `qemu-img convert` writes a sibling file *before* the
original is deleted.

If you reuse an existing PVC (`storage.pvc.name`), you are responsible for
its capacity — the controller does not resize it.

### AccessMode trade-offs

| AccessMode | Works when… | Tradeoff |
|------------|------------|----------|
| `ReadWriteMany` (default) | Source provider pod and target provider pod live on **different nodes**. | Requires an RWX-capable StorageClass (NFS, EFS, Longhorn-RWX, CephFS). |
| `ReadWriteOnce` | Both provider pods schedule onto the **same node**, OR the migration is intra-provider (same provider type, same node). | RWO is far more universally available, but the scheduler isn't guaranteed to co-locate the pods. Use only with a pod-anti-affinity-aware setup or a single-node test cluster. |

In v0.3.6 the controller orchestrates a rolling restart of both providers
to add the PVC mount; if you pick `ReadWriteOnce` and the pods land on
different nodes after the restart, the migration will fail at the validation
phase with a volume-attach error. RWX is the default for a reason.

## What happens to the source VM

| `spec.source` setting | Behavior |
|-----------------------|----------|
| `deleteAfterMigration: false` (default) | Source VM **stays** after migration completes. Recommended for production migrations — use it as a rollback. |
| `deleteAfterMigration: true` | Source VM is **deleted** after `phase=Ready`. Only use after you have validated the target. |
| `createSnapshot: true` (default), `snapshotRef` unset | Controller creates a fresh snapshot of the source VM before exporting. Snapshot is cleaned up per `options.cleanupPolicy`. |
| `snapshotRef: { name: my-snap }`, `createSnapshot: false` | Controller migrates from `my-snap` instead of taking a fresh snapshot. The snapshot is **not** deleted automatically. |
| `powerOffBeforeMigration: true` | Source VM is powered off before exporting. Recommended for filesystem consistency. |
| `powerOffBeforeMigration: false` (default) | Source VM runs throughout — but you are still doing a *cold* migration from a snapshot, so guest state at the time of snapshot is what crosses over. There is no live-migration support in v0.3.6. |

## What happens to the target VM

On `phase=Ready`:

- The target `VirtualMachine` resource exists and is **independent** of the
  `VMMigration` CR. Deleting the `VMMigration` does not delete the target.
- The target VM is annotated `virtrigaud.io/migration-completed=true` and
  `virtrigaud.io/migration-completed-at=<RFC3339>`.
- The target's `spec` references the imported disk via `importedDisk`
  rather than `imageRef`. This is the production-ready VM you can manage,
  scale, snapshot, etc. independently.

On `phase=Failed`:

- A partially-created target VM is cleaned up by the finalizer
  (`vmmigration_controller.go:1257`). The PVC and any provider snapshots
  are also cleaned up per `options.cleanupPolicy`.

## Failure modes and recovery

The migration controller is the most complex reconciler in the codebase
(~2074 LOC, `vmmigration_controller.go`). It has had **several real bugs
caught in v0.3.5 / v0.3.6** — they are worth knowing about because the
class of failure repeats:

| Class | Notes |
|-------|-------|
| **Reconcile double-count** ([#105](https://github.com/projectbeskar/virtrigaud/issues/105), fixed in PR [#106](https://github.com/projectbeskar/virtrigaud/pull/106) / G3 + K5) | Pre-v0.3.6 the reconciler used `defer timer.Finish(metrics.OutcomeSuccess)` alongside explicit error finishes, recording two samples per errored migration. The fix uses named-return + deferred outcome-inference. No operator action required if you're already on v0.3.6. |
| **CircuitBreaker half-open accounting** ([#100](https://github.com/projectbeskar/virtrigaud/issues/100), fixed pre-v0.3.6) | Migration RPCs are gRPC calls and go through the per-Provider CircuitBreaker. Half-open semantics were off; once fixed, Half-Open admits exactly `HalfOpenMaxCalls=3` trial calls and all three must succeed to close the breaker. See [Resilience](../operations/resilience.md). |
| **SSH host-key bypass on libvirt** (#149) | Documented openly in v0.3.6. If your libvirt host migration is failing with a TLS-ish error and you're behind a proxy, this is unlikely the cause — but the compensating-controls posture from [Libvirt Host Prep](../operations/libvirt-host-prepare.md) applies. |

For a recent postmortem catalogue:

```bash
ls fieldTesting/MIGRATION_*.md
```

### Common operator-visible failures

| Symptom | Likely cause | First steps |
|---------|--------------|------------|
| `phase=Failed`, `message="unsupported storage type: s3"` | You set `storage.type: s3` (or http/nfs). | Change to `storage.type: pvc`. |
| `phase=Validating` for >5 min, then `Failed` | Provider pod did not become `Ready` after PVC mount roll. | `kubectl describe pod -n virtrigaud-system <provider-pod>`; usually a volume-attach error from a `ReadWriteOnce` PVC landing on a different node than the other provider. Use RWX. |
| `phase=Exporting` stuck for >30 min on a small disk | gRPC RPC went over the deadline. v0.3.6 has aggressive keep-alives but a misconfigured PVC (e.g. wrong export-path) keeps the RPC blocked. | Check provider logs for the export RPC; check `virtrigaud_circuit_breaker_state{provider=<source>}` — if Open, the source provider has flapped. |
| `phase=Importing` fails with `source disk file not found locally` | The target provider couldn't find the file under `/mnt/migration-storage/<pvc-name>/`. | Re-check the export wrote successfully (`status.storageInfo.url`). Confirm both providers are mounting the same PVC at the same path. |
| `phase=Ready` but target VM never powers on | `spec.target.powerOn: false` (default). | Manually power on via `kubectl patch vm <target> --type=merge -p '{"spec":{"powerState":"On"}}'`. |
| `phase=Failed`, retries exhausted (`retryCount` ≥ `options.retryPolicy.maxRetries`) | Underlying issue keeps recurring. | Delete the `VMMigration` (it will clean up its PVC), fix the root cause, recreate. |

### Forcing a retry without waiting

Migrations retry per `options.retryPolicy.retryDelay` with exponential
backoff. If you have fixed the root cause and want to retry immediately:

```bash
# Trigger an immediate reconcile by touching an annotation
kubectl annotate vmmigration my-vm-to-libvirt \
    virtrigaud.io/reconcile-trigger="$(date +%s)" --overwrite
```

### Reading migration progress

```bash
# Phase + percentage
kubectl get vmmigration my-vm-to-libvirt \
  -o jsonpath='{.status.phase}{"\t"}{.status.progress.percentage}{"\n"}'

# Conditions
kubectl get vmmigration my-vm-to-libvirt -o yaml | yq .status.conditions

# Live progress watch (1s interval, jq-formatted)
watch -n 1 'kubectl get vmmigration my-vm-to-libvirt \
  -o json | jq "{phase:.status.phase, pct:.status.progress.percentage, msg:.status.message}"'
```

## Cleanup policies

`options.cleanupPolicy` controls what happens to intermediate state after
the migration finishes:

| Value | PVC | Source snapshot |
|-------|-----|-----------------|
| `OnSuccess` (default) | Cleaned up only if migration reached `Ready`. | Cleaned up only if migration reached `Ready`. |
| `Always` | Always cleaned up, including on `Failed`. | Always cleaned up. |
| `Never` | Never cleaned up automatically. You delete the PVC + snapshot by hand. | Never cleaned up. |

The intermediate PVC is **owned** by the `VMMigration` CR, so
`kubectl delete vmmigration <name>` will garbage-collect the PVC regardless
of `cleanupPolicy`. The policy controls the in-controller "delete the
intermediate during the reconcile loop" behavior, not the K8s-GC fallback.

## Performance guidance

| Variable | Knob |
|----------|------|
| Disk transfer speed | StorageClass throughput. NFS over 1GbE caps at ~100 MB/s; CephFS / Longhorn-RWX over 10GbE will comfortably exceed 500 MB/s. |
| Format conversion overhead | `options.diskFormat` matched to the target's native format means no conversion. vSphere → Libvirt needs `vmdk → qcow2`, which adds ~0.1× the disk size in temp space and ~10–30 % wall time. |
| Compression overhead | `options.compress: true` trades CPU for bandwidth. Only worth it on slow networks. Off by default. |
| Provider-pod roll on PVC mount | One-time ~30–60 s per provider pod when the migration starts. Unavoidable in v0.3.6. |
| `options.timeout` | Hard wall-clock limit on the entire migration. 4h default. Bump for very large VMs. |

## Multi-disk VMs

The controller handles multi-disk VMs by processing each disk through the
export → transfer → import pipeline. You do not need to specify each disk
explicitly in `spec.target.disks[]` for the migration to handle them — that
field is only for overriding target-side disk parameters (size, storage
hint).

Sizing the PVC for multi-disk VMs: sum the source disk sizes, then apply
the 1.5–2× safety factor. The conversion step needs headroom for the
largest single disk, not the sum.

## Cross-namespace migrations

```yaml
spec:
  source:
    vmRef:
      name: vm-in-prod
    providerRef:
      name: vsphere-provider
      namespace: infrastructure       # cross-namespace OK
  target:
    name: vm-in-staging
    namespace: staging                 # target lives in 'staging'
    providerRef:
      name: libvirt-provider
      namespace: infrastructure
```

The migration resource itself can live in either the source or target
namespace; the target VM is created in `spec.target.namespace` regardless.
The intermediate PVC is created in the same namespace as the `VMMigration`.

## Examples directory

The in-tree example YAMLs are under
[`examples/migration/`](https://github.com/projectbeskar/virtrigaud/tree/main/examples/migration)
in the main repository. The ones that match the v0.3.6 reality (PVC-only
storage) are:

- `vmmigration-basic.yaml`
- `vmmigration-cross-namespace.yaml`

If you see example files that reference `s3`, `http`, or `nfs` `storage.type`,
those reflect an earlier in-development design and should not be used
against a v0.3.6 cluster.

## See also

- [VM Migration API Reference](api-reference.md) — every field, every
  default, every validation rule.
- [VM Migration Guide](vm-migration-guide.md) — architectural deep dive
  (phase machine, controller orchestration, PVC sequencing).
- [Resilience](../operations/resilience.md) — what happens when the source
  or target provider flaps during a long migration.
- [Libvirt Host Preparation](../operations/libvirt-host-prepare.md) — host
  setup for the target side of the validated direction.
