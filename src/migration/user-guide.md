<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VM Migration User Guide

This page is aligned to **VirtRigaud v0.3.11**. It is the practical
"how do I move a VM?" guide. For the field-by-field CRD reference see
[API Reference](api-reference.md); for the architectural model see
[VM Migration Guide](vm-migration-guide.md).

## What VirtRigaud v0.3.11 supports

!!! info "Validated matrix as of v0.3.11"
    All three providers — **vSphere**, **Libvirt/KVM**, and **Proxmox VE** — are
    validated as both source and target, in either direction, over both staging
    backends (S3 and NFS). The original vSphere → Libvirt path remains the
    most-exercised direction; Proxmox and the remaining directions were
    validated during ADR-0006 Slices 1–4 (tracked in
    [#236](https://github.com/projectbeskar/virtrigaud/issues/236)).

    NFS staging (Slice 4) was validated on 2026-06-21 against a real
    OpenMediaVault server: libvirt ↔ libvirt, libvirt → vSphere,
    vSphere → libvirt, libvirt → Proxmox, and Proxmox → libvirt all reached
    `Ready`.

The transfer medium is now **storage-backend-agnostic** (ADR-0006). The disk
is staged on either an S3-compatible object store or an NFS export and never
traverses a Kubernetes CSI PVC. PVC mode is retained for compatibility only.

!!! tip "Capability gating (v0.3.8+, opt-in)"
    The manager flag `--enforce-provider-capabilities`
    ([#176](https://github.com/projectbeskar/virtrigaud/pull/176), **default
    off**) makes the manager reject a migration up front if the source or target
    provider does not advertise the required disk export/import capability.
    Because the vSphere (#178) and libvirt (#177) capability advertisements are
    accurate, enabling this gate gives trustworthy fail-close rejections. See the
    [API Reference](api-reference.md#capability-gating-176-fail-close-on-providers-lacking-exportimport).

## Concept in one diagram

```text
┌──────────────────────────┐        ┌──────────────────────────┐
│   Source Provider        │        │   Target Provider        │
│   (vsphere / libvirt /   │        │   (vsphere / libvirt /   │
│    proxmox)              │        │    proxmox)              │
│                          │        │                          │
│  export disk             │        │  import disk             │
│  (native format)    ─────┼──────► │  (format convert        │
│                          │        │   via qemu-img)          │
└──────────────────────────┘        └──────────────────────────┘
              │                                   ▲
              └───────────────┬───────────────────┘
                              │ staged on
                              ▼
              ┌───────────────────────────────────┐
              │   Staging backend (one of):       │
              │   • S3 (bucket/prefix)            │
              │   • NFS (export, flat object)     │
              │   • PVC  ← compat-only            │
              └───────────────────────────────────┘
                              │
                        orchestrated by
                              ▼
                ┌────────────────────────────────┐
                │  VMMigration controller        │
                │  (vmmigration_controller.go,   │
                │  phase machine)                │
                └────────────────────────────────┘
```

Three things happen in sequence, all driven by the migration controller:

1. **Validate.** Source and target providers are resolved; storage config is
   validated; the staging object/path is prepared.
2. **Export.** The source provider writes the disk to the staging backend in its
   native format.
3. **Import.** The target provider reads the staged disk, converts format via
   `qemu-img` if needed, and creates the target VM.

## Quick start: libvirt → vSphere over NFS

NFS is the newest validated path (Slice 4, 2026-06-21). This example migrates a
VM from a Libvirt host to vSphere, staging the disk on an NFS export.

### Prerequisites

- A working VirtRigaud install on the cluster (manager + both providers
  `Ready`).
- A source `VirtualMachine` already managed by the Libvirt provider.
- A target `Provider` CR for vSphere.
- An NFS export accessible by both provider pods and (for Proxmox) by the PVE
  node. Recommended: one export per tenant (the staged object lives in the
  export root as a flat file).
- The NFS export **owned** by a known uid/gid that both provider legs will
  present. See [Storage — NFS](#nfs-staging-new-in-slice-4) for why this
  matters.

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
    powerOffBeforeMigration: true   # required for vSphere target; ESXi locks running disks
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
      server: 172.16.56.13
      export: /export/virtrigaud
      uid: 1000     # uid that owns the export files — all legs must match
      gid: 1000     # gid that owns the export files — all legs must match
    transferMode: auto    # informational for NFS; qemu-img handles transport
  options:
    cleanupPolicy: OnSuccess
    verifyChecksums: true
    timeout: 1h
```

Apply and watch:

```bash
kubectl apply -f app-libvirt-to-vsphere-nfs.yaml

# Watch phase progression
kubectl get vmmigration app-libvirt-to-vsphere-nfs -w

# Detailed status (conditions, events, storageInfo)
kubectl describe vmmigration app-libvirt-to-vsphere-nfs
```

A successful run progresses Pending → Validating → Snapshotting → Exporting
→ Transferring → Converting → Importing → Creating → Validating-Target →
Ready. End-to-end time depends on disk size + network throughput to the NFS
server.

## Quick start: vSphere → Libvirt over S3

S3 is the relay-based path (Slices 1–3). The provider pod acts as the S3
client; bytes flow: host → pod → S3 bucket → pod → host. `transferMode: auto`
resolves to `relay` (the only implemented mode; `direct` is roadmap).

### Prerequisites

- An S3-compatible bucket (AWS S3, MinIO, Ceph RGW, rustfs, etc.).
- A `Secret` in the migration namespace carrying S3 credentials.
- Source VM managed by vSphere, target `Provider` CR for Libvirt.

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
    powerOffBeforeMigration: true
    deleteAfterMigration: false   # keep source for rollback

  target:
    name: my-vm-libvirt
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

  storage:
    type: s3
    transferMode: relay       # relay (implemented); auto → relay
    s3:
      bucket: virtrigaud
      endpoint: http://minio.example:9000   # omit for AWS S3
      region: us-east-1
      usePathStyle: true                    # true for MinIO/Ceph/rustfs; false for AWS
      credentialsSecretRef:
        name: s3-migration-credentials
```

Apply and watch:

```bash
kubectl apply -f my-vm-to-libvirt.yaml
kubectl get vmmigration my-vm-to-libvirt -w
```

## Storage

### S3 staging

The S3 backend is the primary staging path for fleet migrations. The provider
pod is the S3 client — **no CSI PVC is involved**. The source exports the disk
in its native format; the target owns format conversion (vmdk → qcow2, etc.)
on import.

Key configuration fields under `spec.storage.s3`:

| Field | Required | Notes |
|-------|----------|-------|
| `bucket` | yes | S3 bucket name. |
| `endpoint` | no | Omit for AWS S3; set for MinIO/Ceph RGW/rustfs. |
| `region` | yes | AWS region string (e.g. `us-east-1`). |
| `prefix` | no | Key prefix (e.g. `migrations/`). The staged object is flat under this prefix. |
| `usePathStyle` | yes | `true` for MinIO/Ceph/rustfs; `false` for AWS. |
| `credentialsSecretRef.name` | yes | Name of a `Secret` in the same namespace; keys: `accessKeyID`, `secretAccessKey`, optional `sessionToken`. Never inline credentials in the CR. |

The S3 server hostname is SSRF-checked against the manager flag
`--migration-storage-allowed-hosts`. Loopback and link-local targets are always
rejected.

### NFS staging (new in Slice 4)

NFS staging is the second validated backend. The disk is moved using
`qemu-img`'s native NFS support — not a PVC, and not a pod relay. Per-provider
transport detail:

| Provider | NFS transport mechanism |
|---------|------------------------|
| **libvirt** | The libvirt **host** runs `qemu-img` against an `nfs://` URL using the **libnfs** driver. No pod relay. |
| **vSphere** | The provider **pod** runs `qemu-img` against `nfs://` via libnfs. The vSphere provider image ships the Debian `qemu-block-extra` package (provides `block-nfs.so`). |
| **Proxmox** | Uses a **kernel NFS mount** on the PVE node, NOT libnfs. `pve-qemu-kvm` ships no libnfs driver (`qemu-img` rejects `nfs://` with `Unknown protocol 'nfs'`), so the Proxmox provider mounts the export with the node's kernel NFS client and runs `qemu-img` against the mount — exactly how PVE's native NFS storage works. |

#### The uid/gid requirement

!!! warning "Set uid/gid for cross-provider migrations"
    AUTH_SYS (NFSv3) authorizes by the **numeric uid/gid** the client presents.
    Each provider's `qemu-img` runs as a different identity: the libvirt SSH
    user; the vSphere pod's uid `65532`; the Proxmox node's `root`. If the
    export files are owned by `1000:1000`, set `nfs.uid: 1000` and
    `nfs.gid: 1000` so every leg can read and write the same staged object.

    Wrong or omitted uid/gid → `NFS3ERR_ACCES`. Omitting them is safe only
    when every provider leg already presents a uid the export trusts — which
    is uncommon in cross-provider migrations.

    Proxmox presents the configured uid/gid via `setpriv`; libvirt and vSphere
    pass them in the libnfs URL.

#### Flat-file layout

The staged object is a **single flat file** in the export root:

```text
<export root>/vmmigrations-<namespace>-<name>-<stage>.qcow2
```

NFS cannot auto-create directories the way S3 key prefixes do. A nested
`spec.storage.nfs.path` (subpath below the export) is supported but the flat
file must exist at that path — the controller will not `mkdir` it. For
simplicity, omit `path` and use the export root with one export per tenant to
avoid collisions.

#### Integrity model

`qemu-img` over NFS emits no in-stream byte checksum, so the dual-checksum
model (source SHA256 vs target SHA256) degrades to a target-side
`qemu-img check` / post-import uuid query rather than a full SHA256 match.
`options.verifyChecksums: true` is still recommended — it triggers the
target-side check.

#### Security and hardening (ADR-0006 C6)

!!! danger "AUTH_SYS over NFSv3 is cleartext — harden accordingly"
    NFS AUTH_SYS presents uid/gid as an assertion, not an authenticated
    identity. The disk bytes are **not encrypted in transit** over NFS.

    Operators must:

    - Run the NFS export on a **trusted network segment** (same VLAN / private
      subnet as your provider nodes).
    - Keep **`root_squash` ON** on the export.
    - Use **one export per tenant** to isolate staged objects.
    - Prefer **narrow per-client export ACLs** (list of provider IPs) over
      broad subnet grants.

    If your compliance posture requires encryption in transit, use the S3
    backend with TLS-terminated endpoint instead.

Key configuration fields under `spec.storage.nfs`:

| Field | Required | Notes |
|-------|----------|-------|
| `server` | yes | Hostname or IP of the NFS server. SSRF-checked against `--migration-storage-allowed-hosts`. |
| `export` | yes | Absolute export path on the server, e.g. `/export/virtrigaud`. |
| `path` | no | Subpath under the export. Omit to use the export root (recommended for flat-file layout). |
| `uid` | no (mandatory in practice) | Numeric uid the NFS client presents. Set to the uid owning the export files. |
| `gid` | no (mandatory in practice) | Numeric gid the NFS client presents. |
| `readOnly` | no | Default `false`. |

The NFS server hostname is SSRF-checked by the same manager flag as S3:
`--migration-storage-allowed-hosts`. Loopback and link-local targets are always
rejected.

### PVC staging (compatibility only)

PVC mode (`storage.type: pvc`) mounts a `ReadWriteMany` PVC into both provider
pods and is retained for clusters that already use it. It is no longer the
recommended path for new migrations.

Sizing guidance (still relevant for PVC users): size the PVC at **1.5×–2× the
source disk size** to accommodate both the export and any sibling conversion
file (`qemu-img convert` writes a sibling before deleting the original).

See [API Reference — storage.pvc](api-reference.md#storagepvc-pvcstorageconfig-compat-only)
for field-level detail.

## What happens to the source VM

| `spec.source` setting | Behavior |
|-----------------------|----------|
| `deleteAfterMigration: false` (default) | Source VM **stays** after migration completes. Recommended for production migrations — use it as a rollback. |
| `deleteAfterMigration: true` | Source VM is **deleted** after `phase=Ready`. Only use after you have validated the target. |
| `createSnapshot: true` (default), `snapshotRef` unset | Controller creates a fresh snapshot of the source VM before exporting. Snapshot is cleaned up per `options.cleanupPolicy`. |
| `snapshotRef: { name: my-snap }`, `createSnapshot: false` | Controller migrates from `my-snap` instead of taking a fresh snapshot. The snapshot is **not** deleted automatically. |
| `powerOffBeforeMigration: true` | Source VM is powered off before exporting. **Required for vSphere source** (ESXi locks a running VM's disk). Recommended for filesystem consistency in all cases. |
| `powerOffBeforeMigration: false` (default) | Source VM runs throughout — migration is still cold (snapshot-based). There is no live-migration support in v0.3.11. |

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
  (`vmmigration_controller.go:1257`). The intermediate storage and any provider
  snapshots are also cleaned up per `options.cleanupPolicy`.

## Failure modes and recovery

The migration controller is the most complex reconciler in the codebase
(~2074 LOC, `vmmigration_controller.go`). Known failure classes:

| Class | Notes |
|-------|-------|
| **Reconcile double-count** ([#105](https://github.com/projectbeskar/virtrigaud/issues/105), fixed in PR [#106](https://github.com/projectbeskar/virtrigaud/pull/106) / G3 + K5) | Pre-v0.3.6 the reconciler used `defer timer.Finish(metrics.OutcomeSuccess)` alongside explicit error finishes, recording two samples per errored migration. The fix uses named-return + deferred outcome-inference. No operator action required if you're already on v0.3.6. |
| **CircuitBreaker half-open accounting** ([#100](https://github.com/projectbeskar/virtrigaud/issues/100), fixed pre-v0.3.6) | Migration RPCs are gRPC calls and go through the per-Provider CircuitBreaker. Half-open semantics were off; once fixed, Half-Open admits exactly `HalfOpenMaxCalls=3` trial calls and all three must succeed to close the breaker. See [Resilience](../operations/resilience.md). |
| **Transient SSH connection failures on libvirt** ([#191](https://github.com/projectbeskar/virtrigaud/pull/191), v0.3.8) | A migration drives many back-to-back `virsh`-over-SSH calls; bursts can trip the host's `sshd` `MaxStartups` or `fail2ban`. v0.3.8 retries these with bounded backoff, but tight host limits can still fail a migration. Raise `MaxStartups` / allowlist the provider source per [Libvirt Host Prep](../operations/libvirt-host-prepare.md#ssh-connection-rate-limiting-maxstartups-fail2ban). |
| **Migration PVC reclaimed mid-flight** ([#184](https://github.com/projectbeskar/virtrigaud/pull/184), fixed in v0.3.8) | Previously a provider reconcile could delete the migration-storage PVC out from under an in-flight migration. In v0.3.8 the provider controller no longer deletes those PVCs and watches them. No operator action on v0.3.8+. |

For a recent postmortem catalogue:

```bash
ls fieldTesting/MIGRATION_*.md
```

### Common operator-visible failures

| Symptom | Likely cause | First steps |
|---------|--------------|------------|
| `phase=Failed`, `message="NFS3ERR_ACCES"` | The NFS client presented a uid/gid the export denies. | Set `nfs.uid` / `nfs.gid` to the uid/gid that owns the export files. |
| `phase=Failed`, `message` contains `MNT3ERR_NOENT` | A nested `nfs.path` was specified but the subdirectory does not exist on the server. | Remove `nfs.path` to use the export root, or create the subdirectory on the server. |
| `phase=Failed`, `message` contains `not in allowed hosts` | The NFS/S3 server hostname is blocked by `--migration-storage-allowed-hosts`. | Add the server to the allowlist or check for a typo. Loopback and link-local are always blocked. |
| `phase=Validating` for >5 min, then `Failed` (PVC mode) | Provider pod did not become `Ready` after PVC mount roll. | `kubectl describe pod -n virtrigaud-system <provider-pod>`; usually a volume-attach error from a `ReadWriteOnce` PVC landing on a different node. Use RWX. |
| `phase=Exporting` stuck for >30 min on a small disk | gRPC RPC went over the deadline. A misconfigured NFS export or unreachable S3 endpoint keeps the RPC blocked. | Check provider logs for the export RPC; check `virtrigaud_circuit_breaker_state{provider=<source>}` — if Open, the source provider has flapped. |
| `phase=Ready` but target VM never powers on | `spec.target.powerOn: false` (default). | Manually power on via `kubectl patch vm <target> --type=merge -p '{"spec":{"powerState":"On"}}'`. |
| `phase=Failed`, retries exhausted (`retryCount` ≥ `options.retryPolicy.maxRetries`) | Underlying issue keeps recurring. | Fix the root cause, then delete and recreate the `VMMigration`. |

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

| Value | Intermediate storage | Source snapshot |
|-------|---------------------|-----------------|
| `OnSuccess` (default) | Cleaned up only if migration reached `Ready`. | Cleaned up only if migration reached `Ready`. |
| `Always` | Always cleaned up, including on `Failed`. | Always cleaned up. |
| `Never` | Never cleaned up automatically. You delete staging objects by hand. | Never cleaned up. |

For S3: "cleaned up" means the staged object is deleted from the bucket.
For NFS: "cleaned up" means the flat file is deleted from the export.
For PVC: the PVC is owned by the `VMMigration` CR; `kubectl delete vmmigration
<name>` garbage-collects it regardless of `cleanupPolicy`. The policy controls
the in-controller cleanup pass, not the K8s-GC fallback.

## Performance guidance

| Variable | Knob |
|----------|------|
| Disk transfer speed (S3) | S3 endpoint throughput. MinIO on a local 10GbE network exceeds 500 MB/s. AWS S3 is limited by inter-region bandwidth. |
| Disk transfer speed (NFS) | NFS server throughput. 1GbE caps at ~100 MB/s; 10GbE NFS easily exceeds 500 MB/s. |
| Format conversion overhead | `options.diskFormat` matched to the target's native format means no conversion. vSphere → Libvirt needs `vmdk → qcow2`, which adds ~10–30 % wall time. |
| Compression overhead | `options.compress: true` trades CPU for bandwidth. Only worth it on slow networks. Off by default. |
| `options.timeout` | Hard wall-clock limit on the entire migration. 4h default. Bump for very large VMs. |

## Multi-disk VMs

The controller handles multi-disk VMs by processing each disk through the
export → transfer → import pipeline. You do not need to specify each disk
explicitly in `spec.target.disks[]` for the migration to handle them — that
field is only for overriding target-side disk parameters (size, storage
hint).

For NFS migrations the staged object is a single flat file in the export root,
named `vmmigrations-<ns>-<name>-<stage>.qcow2` (the `<stage>` segment, e.g.
`export`, distinguishes the staging phase). Keep one export per tenant so
concurrent migrations do not collide on the export root.

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

!!! note "S3 and NFS remove the shared-mount co-location constraint"
    With PVC staging, both provider pods had to mount the same PVC, which
    imposed a same-namespace requirement. With S3 and NFS backends there is
    no shared mount — the staging medium is an external server reachable by
    both legs independently. Cross-namespace and cross-cluster configurations
    are no longer blocked by the transfer medium. (Cross-cluster is not yet
    validated as of v0.3.11 and would require additional Secret propagation;
    consult the roadmap.)

The migration resource itself can live in either the source or target
namespace; the target VM is created in `spec.target.namespace` regardless.
For PVC mode, the intermediate PVC is created in the same namespace as the
`VMMigration`.

## Examples directory

The in-tree example YAMLs are under
[`examples/migration/`](https://github.com/projectbeskar/virtrigaud/tree/main/examples/migration)
in the main repository. The recommended starting points for v0.3.11:

- `vmmigration-nfs.yaml` — NFS staging (Slice 4, validated)
- `vmmigration-s3.yaml` — S3 staging (Slices 1–3, validated)

PVC examples (`vmmigration-basic.yaml`, `vmmigration-cross-namespace.yaml`) are
retained for compatibility but are no longer the recommended path.

## See also

- [VM Migration API Reference](api-reference.md) — every field, every
  default, every validation rule.
- [VM Migration Guide](vm-migration-guide.md) — architectural deep dive
  (phase machine, controller orchestration, storage sequencing).
- [Resilience](../operations/resilience.md) — what happens when the source
  or target provider flaps during a long migration.
- [Libvirt Host Preparation](../operations/libvirt-host-prepare.md) — host
  setup for Libvirt migrations.
- [ADR-0006](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0006-storage-backend-agnostic-cross-hypervisor-migration.md) —
  design rationale for storage-backend-agnostic migration.
