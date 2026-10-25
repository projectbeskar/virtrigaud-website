<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Provider Capabilities Matrix

This document provides a comprehensive overview of VirtRigaud provider capabilities as of **v0.4.0**.

Cells marked ✅ / ❌ in this matrix are cross-referenced against each provider's `GetCapabilities` gRPC response (`internal/providers/{vsphere,libvirt,proxmox}/server.go`) and the capability builder registrations in `internal/providers/{proxmox}/capabilities.go` / `sdk/provider/capabilities/`. Where a feature is implemented in code but not yet exposed through the capability flag (or vice versa), the cell carries a footnote rather than being silently changed.

## Overview

VirtRigaud supports multiple hypervisor platforms through a provider architecture. Each provider runs as its own gRPC server pod, implements the proto contract in `proto/provider/v1/provider.proto`, and advertises its feature set through the `GetCapabilities` RPC. The manager negotiates per-Provider rather than assuming uniform support.

## Core Provider Interface

All providers implement these core operations:

- **Validate**: Test provider connectivity and credentials
- **Create**: Create new virtual machines
- **Delete**: Remove virtual machines and cleanup resources
- **Power**: Control VM power state (On/Off/Reboot/Shutdown-Graceful)
- **Describe**: Query VM state and properties
- **GetCapabilities**: Report provider-specific capabilities (the source of truth for the matrix below)
- **TaskStatus**: Poll for completion of async operations
- **ListVMs**: Enumerate provider-side VMs (used by the VMAdoption controller)

## Provider Status

| Provider | Status | Implementation | Maturity |
|----------|--------|---------------|----------|
| **vSphere** | Production Ready | govmomi-based | Stable |
| **Libvirt/KVM** (single host) | Production Ready | virsh over SSH | Stable |
| **Libvirt/KVM** (clustered, `topology: cluster`) | Opt-in, experimental | virsh over SSH to N hosts, placement in the operator | Experimental |
| **Proxmox VE** | Production Ready | REST API-based | Beta |
| **Mock** | Complete | In-memory simulation | Testing |

## Clustered libvirt (experimental)

A libvirt `Provider` with `spec.topology: cluster` fronts several libvirt hosts registered as `Host` resources in a `HostPool`. The matrix below describes the single-host libvirt provider. A clustered Provider differs as follows (from its `GetCapabilities` answer, `internal/providers/libvirt/server.go`):

| Area | Clustered libvirt |
|------|-------------------|
| Create, delete, power, reconfigure, describe | Yes, routed to the VM's host and checked against its owner stamp |
| Online CPU/memory reconfigure, disk expansion | Yes (same as single host). Shrinking a running VM waits until it is powered off (`ShrinkPendingPowerOff`) |
| Snapshots (including memory) and revert | Yes, routed to the VM's host |
| Full clone | Yes, onto the source VM's own host, admitted against that host's free capacity. Linked clones: no |
| `ImagePrepare` (`VMImage` with a download `url`) | **No** (not implemented; image import and artifact identity are not reported). Use a `path` image present on the hosts |
| Disk export | Yes, host-side, `s3` and `nfs` only, `qcow2` only |
| Disk import (migration target) | Yes, `s3` and `nfs`; a clustered Provider is accepted as a `VMMigration` target only when it reports `supports_routed_import` (experimental) |
| Adoption (`virtrigaud.io/adopt-vms`) | Yes, keyed on (host, domain); a domain left by a deleted or restored VM is not adopted |
| Host-to-host (live or offline) migration | **Not implemented** |
| Replicas | One, with the `Recreate` strategy: a rollout is a short outage |

Details: [Libvirt provider](libvirt.md) and [`clustered-provider-inventory.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/clustered-provider-inventory.md).

## Comprehensive Capability Matrix

### Core Operations

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **VM Create** | ✅ | ✅ | ✅ | ✅ | All providers support VM creation |
| **VM Delete** | ✅ | ✅ | ✅ | ✅ | With resource cleanup |
| **Power On/Off** | ✅ | ✅ | ✅ | ✅ | Basic power management |
| **Reboot** | ✅ | ✅ | ✅ | ✅ | Graceful and forced restart |
| **Suspend** | ✅ | ❌ | ✅ | ✅ | Memory state preservation |
| **Describe** | ✅ | ✅ | ✅ | ✅ | VM state and properties |
| **Reconfigure** | ✅ | ✅[^reconfigure] | ✅ | ✅ | CPU/Memory/Disk changes; libvirt online with hot-add headroom (see note) |
| **TaskStatus** | ✅ | N/A | ✅ | ✅ | Async operation tracking |
| **ConsoleURL** | ✅ | ✅ | ⚠️ | ✅ | Remote console access (Proxmox planned) |

### Resource Management

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **CPU Configuration** | ✅ | ✅ | ✅ | ✅ | Cores, sockets, threading |
| **Memory Allocation** | ✅ | ✅ | ✅ | ✅ | Static memory sizing |
| **Hot CPU Add** | ✅ | ✅[^reconfigure] | ✅ | ✅ | Online CPU expansion |
| **Hot Memory Add** | ✅ | ✅[^reconfigure] | ✅ | ✅ | Online memory expansion |
| **Resource Reservations** | ✅ | ❌ | ✅ | ✅ | Guaranteed resources |
| **Resource Limits** | ✅ | ❌ | ✅ | ✅ | Resource capping |

### Storage Operations

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Disk Creation** | ✅ | ✅ | ✅ | ✅ | Virtual disk provisioning |
| **Disk Expansion** | ✅ | ✅[^diskexpand] | ✅ | ✅ | Online disk growth |
| **Multiple Disks** | ✅ | ✅ | ✅ | ✅ | Multi-disk VMs |
| **Thin Provisioning** | ✅ | ✅ | ✅ | ✅ | Space-efficient disks |
| **Thick Provisioning** | ✅ | ✅ | ✅ | ✅ | Pre-allocated storage |
| **Storage Policies** | ✅ | ❌ | ✅ | ✅ | Policy-based placement |
| **Storage Pools** | ✅ | ✅ | ✅ | ✅ | Organized storage management |

[^diskexpand]: As of v0.3.9 (#201), libvirt advertises `SupportsDiskExpansionOnline=true`. Online grow runs via `virsh blockresize` (grow-only; shrink is not supported) followed by a best-effort in-guest filesystem grow via the QEMU guest agent (`resize2fs` / `xfs_growfs`). If the guest agent is absent or the layout is non-standard (LVM, multiple partitions), the block device is enlarged but the guest filesystem must be grown manually. Lab-verified: `blockresize … 20G` succeeded live on a running guest.

### Network Configuration

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Basic Networking** | ✅ | ✅ | ✅ | ✅ | Single network interface |
| **Multiple NICs** | ✅ | ✅ | ✅ | ✅ | Multi-interface VMs |
| **VLAN Support** | ✅ | ✅ | ✅ | ✅ | Network segmentation |
| **Static IP** | ✅ | ✅ | ✅ | ✅ | Via cloud-init network-config |
| **DHCP** | ✅ | ✅ | ✅ | ✅ | Dynamic IP assignment |
| **Bridge Networks** | ❌ | ✅ | ✅ | ✅ | Direct host bridging |
| **Distributed Switches** | ✅ | ❌ | ❌ | ✅ | Advanced vSphere networking |

### VM Lifecycle

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Template Deployment** | ✅ | ✅ | ✅ | ✅ | Deploy from templates |
| **Clone Operations** | ✅ | ✅[^clone] | ✅ | ✅ | Full VM duplication through `VMClone`; same provider only |
| **Linked Clones** | ✅ | ❌[^clone] | ✅ | ✅ | COW-based clones; disabled on libvirt since v0.4.0 |
| **Full Clones** | ✅ | ✅[^clone] | ✅ | ✅ | Independent copies; libvirt: full volume copy, source VM must be powered off |
| **VM Reconfiguration** | ✅ | ✅[^reconfigure] | ✅ | ✅ | Online resource modification |

[^clone]: libvirt `Clone` is implemented for **full clones** (#153/#208/#221): the per-VM UEFI `<nvram>` varstore is copied to an independent file, hot-add headroom is preserved across a class-override clone, and a clone gets its own cloud-init instance id and SSH host keys. **Linked clones are disabled since v0.4.0**: a linked clone reads its source VM's live disk, and powering the source on corrupts the clone. `GetCapabilities` reports `SupportsLinkedClones=false` and a `VMClone` with `options.type: LinkedClone` fails with `LinkedCloneUnsupported`. Linked clones made by earlier releases keep working, but their source cannot be deleted, reverted or snapshotted while they exist. A libvirt full clone needs its source VM powered off. Earlier documentation (including v0.3.9 footnotes) listed libvirt linked clones as supported — that is reversed in v0.4.0.

[^reconfigure]: As of v0.3.9 (#203), libvirt advertises `SupportsReconfigureOnline=true`. Online CPU/memory reconfigure via `virsh setvcpus --live` / `virsh setmem --live` works **only on VMs created with the hot-add flags** (`VMClass.spec.performanceProfile.cpuHotAddEnabled` and/or `memoryHotAddEnabled` set at create time). Headroom is provisioned at create (4× ceiling, vCPU hard-capped at 64). VMs created without these flags — including all pre-v0.3.9 VMs — still require a power-cycle for CPU/memory changes. Lab-verified: `virsh setvcpus … 4 --live` and `virsh setmem … --live` both succeeded with no power-cycle on a properly configured UEFI VM.

### Snapshot Operations

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Create Snapshots** | ✅ | ✅ | ✅ | ✅ | Point-in-time captures |
| **Delete Snapshots** | ✅ | ✅ | ✅ | ✅ | Snapshot cleanup |
| **Revert Snapshots** | ✅ | ✅ | ✅ | ✅ | Restore VM state |
| **Memory Snapshots** | ✅[^memsnap] | ✅[^memsnap] | ✅ | ✅ | Include RAM state |
| **Quiesced Snapshots** | ✅ | ❌ | ✅ | ✅ | Consistent filesystem |
| **Snapshot Trees** | ✅ | ✅ | ✅ | ✅ | Hierarchical snapshots |

[^memsnap]: All three providers support RAM-inclusive snapshots as of v0.3.9. **vSphere** (#200): `CreateSnapshot(memory=true)`; requires the VM powered on (vSphere rejects memory snapshots of a powered-off VM). **Libvirt** (#202): `virsh snapshot-create-as` without `--disk-only`; running VM captures disk + RAM state; stopped VM honestly downgrades to disk-only with a WARN logged. **Proxmox**: PVE-native RAM-inclusive snapshots. Set `spec.memory: true` on the `VMSnapshot` CR to request a memory snapshot. An earlier v0.3.6/v0.3.8 footnote stated vSphere and libvirt both advertised `SupportsMemorySnapshots=false` — that is reversed in v0.3.9 for both providers.

### Snapshots and revert

| Topic | vSphere | Libvirt | Proxmox |
|-------|---------|---------|---------|
| Memory snapshot (`snapshotConfig.includeMemory: true`) | VM must be powered on | Running VM: internal snapshot with RAM. Powered-off VM: disk-only (a warning is logged) | PVE-native |
| Revert (`VirtualMachine.spec.snapshot.revertToRef`, VM powered off) | `RevertToSnapshot_Task`; a memory snapshot powers the VM on, then `spec.powerState` is applied | External snapshots need libvirt 9.9+. Refused for a snapshot that stored the cloud-init CD-ROM: take the snapshot **with the VM powered off** to be able to revert it. Refused while a linked clone depends on the VM's disk | Rollback task, polled by the manager |
| Delete | Refuses a template or prepared-image artifact (`VM_IS_IMAGE_ARTIFACT`) | Deleting a disk-only snapshot is refused while a memory snapshot of the VM is stored in its overlay: delete the memory snapshot first (`Ready=False/DeleteBlocked`) | Refused when the VM's owner stamp cannot be read |

A revert discards what was written to the disks since the snapshot. The revert was accepted but ignored in v0.4.0-rc5 and earlier. Full rules: [`vm-snapshot-revert.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-snapshot-revert.md) and the [VM CRD reference](../references/crds.md#snapshot-revert).

### Image Management

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **OVA/OVF Import** | ✅ | ❌ | ✅ | ✅ | Standard VM formats |
| **Image Import (URL)** | ⚠️[^4] | ✅[^imageimport] | ✅ | ✅ | Remote image fetch; libvirt `ImagePrepare` implemented (#154); vSphere: OVA/OVF + content library only |
| **Content Libraries** | ✅ | ❌ | ❌ | ✅ | Centralized image management |
| **Image Conversion** | ❌ | ✅ | ✅ | ✅ | Format transformation |
| **Image Caching** | ✅ | ✅ | ✅ | ✅ | Performance optimization |

[^4]: vSphere advertises `SupportsImageImport=true` (OVA/OVF + content library); direct cloud-image URL fetch is not yet implemented. Operators today should land cloud images in the content library out-of-band.

[^imageimport]: As of v0.3.9 (#154), libvirt's `ImagePrepare` RPC is fully implemented and `GetCapabilities` reports `SupportsImageImport=true`. `VMImage.spec.prepare` drives lazy, VM-create-time image import into a libvirt storage pool. A `VMImage` with an **import-style** source (a download `url`/OVA) and `prepare.onMissing: Fail` whose image is not yet imported will hold new VM creation with a `WaitingForDependencies` condition ("image not prepared on provider") until preparation completes. Images that reference an **already-present** artifact (a libvirt pool-file `path`, an existing template) — or that have no `prepare` block — create normally. Earlier v0.3.8 documentation stated `ImagePrepare` was `Unimplemented` — that is reversed in v0.3.9.

### Disk Export / Import & Cross-Provider Migration

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Disk Export** | ✅[^7] | ✅[^8] | ✅ | ✅ | `ExportDisk` / `GetDiskInfo`; vSphere also advertises export compression |
| **Disk Import** | ✅[^7] | ✅[^8] | ✅ | ✅ | `ImportDisk`; libvirt: `pvc://` / `file://` sources |
| **Export Compression** | ✅ | ✅ | ✅[^proxmoxcomp] | simulated | vSphere and libvirt honor `req.Compress`; Proxmox (#219) |
| **Export Formats** | `vmdk`, `qcow2`, `raw` | per `GetDiskInfo` | `qcow2`, `raw`, `vmdk` | simulated | vSphere & Proxmox `GetCapabilities` advertise all three (#178 / #198) |
| **Cross-Provider Migration — S3 backend** | ✅[^migrate] | ✅[^migrate] | ✅[^migrate] | n/a | `VMMigration` over S3-compatible object storage (`relay`). Validated as source **and** target, both directions, all pairs (ADR-0006 Slices 1–3, #236). |
| **Cross-Provider Migration — NFS backend** | ✅[^migratenfs] | ✅[^migratenfs] | ✅[^migratenfs] | n/a | `VMMigration` over an NFS export via `qemu-img` (ADR-0006 Slice 4, #236). vSphere pod-side libnfs, libvirt host-side libnfs, **Proxmox kernel-mount**. Validated both directions across all three. |

This is VirtRigaud's **storage-backend-agnostic, any-direction** cross-hypervisor
migration (ADR-0006): the disk is staged on a pluggable backend (S3 or NFS) and
moved with `qemu-img` — it **never traverses a CSI PVC**. The whole 3-hypervisor
matrix (vSphere ⇄ Libvirt/KVM ⇄ Proxmox VE) is lab-validated in both directions
over **both** backends. A legacy `pvc` staging mode remains for the vSphere/libvirt
directions but is **compat-only** — it cannot reach host-resident libvirt disks or
Proxmox node storage. Do not confuse this with the **vMotion/Migration** row in
[Advanced Features](#advanced-features) below, which is *intra-hypervisor live*
migration (vSphere vMotion, PVE live migrate), a separate hypervisor-native feature.
See the [VM Migration docs](../migration/user-guide.md) for the full guide.

[^7]: As of v0.3.8 (#178), vSphere's `GetCapabilities` advertises disk **export and import** plus the `vmdk`, `qcow2`, and `raw` formats and export compression. Prior releases understated these flags (export/import reported as unsupported/zero); the cells above match the actual v0.3.8 response in `internal/providers/vsphere/server.go`.

[^8]: libvirt implements both `ExportDisk` / `GetDiskInfo` (#177, v0.3.8) and `ImportDisk` (accepting `pvc://` and `file://` sources), and `GetCapabilities` reports `SupportsDiskExport=true` **and** `SupportsDiskImport=true`. These feed the cross-provider migration pipeline (vSphere → libvirt export/convert/import). Proxmox likewise advertises both export and import for `qcow2`/`raw`/`vmdk` (#198).

[^proxmoxcomp]: As of v0.3.9 (#219), Proxmox's `ExportDisk` honors the `Compress` field for qcow2 targets and advertises `SupportsExportCompression=true` in `GetCapabilities`.

[^migrate]: Cross-provider migration over the **S3** staging backend is validated end-to-end for every provider as both source and target, in both directions, across all pairs — vSphere ⇄ libvirt (ADR-0006 Slices 1–2) and Proxmox ⇄ libvirt / Proxmox ⇄ vSphere (Slice 3, #236). The provider **pod** is the S3 client (the universal `relay` transfer mode; `auto` resolves to `relay`, `direct` is a roadmap item), so the disk bytes flow host → pod → S3 → pod → host and never traverse a CSI PVC. The source exports its native format; the **target** owns format conversion (vmdk ↔ qcow2). For Proxmox and libvirt the bytes are read/written on the hypervisor node/host and streamed over SSH into the provider pod, so the Proxmox/libvirt **Provider** Secret must also carry SSH credentials and a pinned `known_hosts`.

[^migratenfs]: As of v0.3.11 (ADR-0006 Slice 4, #236), the same any-direction matrix is also validated over an **NFS** staging backend, against a real OpenMediaVault server. Instead of an object store, the disk is staged on an NFS export and moved with `qemu-img`'s native transport (no PVC, no pod relay, no S3 credentials). **libvirt** (host-side) and **vSphere** (pod-side) use qemu-img's `nfs://` libnfs driver directly; the vSphere image bakes in the Debian `qemu-block-extra` package. **Proxmox uses a kernel NFS mount** — `pve-qemu-kvm` ships no libnfs driver (qemu-img rejects `nfs://` with `Unknown protocol 'nfs'`), so the node mounts the export the way PVE's native NFS storage does and runs qemu-img against the mount. `nfs.uid`/`nfs.gid` are effectively mandatory for cross-provider migrations (AUTH_SYS authorizes by the numeric uid/gid presented, and each leg runs as a different identity) — set them to the export owner. See the [VM Migration User Guide](../migration/user-guide.md#nfs-staging-new-in-slice-4).

### Guest Operating System

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Cloud-Init** | ✅ | ✅ | ✅ | ✅ | Guest initialization |
| **Guest Tools** | ✅ | ✅ | ✅ | ✅ | Enhanced guest integration |
| **Guest Agent** | ✅ | ✅ | ✅ | ✅ | Runtime guest communication |
| **Guest Customization** | ✅ | ✅ | ✅ | ✅ | OS-specific customization |
| **Guest Monitoring** | ✅ | ✅ | ✅ | ✅ | Resource usage tracking |

### Advanced Features

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **High Availability** | ✅ | ❌ | ✅ | ✅ | Automatic failover |
| **DRS/Load Balancing** | ✅ | ❌ | ❌ | ✅ | Resource optimization |
| **Fault Tolerance** | ✅ | ❌ | ❌ | ✅ | Zero-downtime protection |
| **vMotion/Migration** | ✅ | ❌ | ✅ | ✅ | Live VM migration |
| **Resource Pools** | ✅ | ❌ | ✅ | ✅ | Hierarchical resource mgmt |
| **Affinity Rules** | ✅ | ❌ | ✅ | ✅ | VM placement policies |

### Monitoring & Observability

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Performance Metrics** | ✅ | ✅ | ✅ | ✅ | CPU, memory, disk, network |
| **Event Logging** | ✅ | ✅ | ✅ | ✅ | Operation audit trail |
| **Health Checks** | ✅ | ✅ | ✅ | ✅ | VM and guest health |
| **Alerting** | ✅ | ❌ | ✅ | ✅ | Threshold-based notifications |
| **Historical Data** | ✅ | ❌ | ✅ | ✅ | Performance history |
| **Console URL Generation** | ✅ | ✅ | ⚠️ | ✅ | Web/VNC console access (Proxmox planned) |
| **Guest Agent Integration** | ✅ | ✅ | ✅ | ✅ | IP detection and guest info |
| **CircuitBreaker (manager-side)** | ✅ | ✅ | ✅ | ✅ | One CB per Provider CR (v0.3.6 / G6). See [Resilience](../operations/resilience.md). |

## Capability Negotiation (manager side)

Every provider implements `GetCapabilities`, which returns a `GetCapabilitiesResponse` containing the boolean flags exposed in the matrix above. The manager calls this RPC at provider connection time and short-circuits unsupported operations rather than letting them fail at the hypervisor — operators see a `NotSupported` condition on the relevant CR rather than a noisy provider error.

### Reported capabilities on the Provider status (v0.3.8, #176)

As of **v0.3.8**, the manager fetches each provider's `GetCapabilities` during reconciliation and **surfaces the result on the Provider CR itself**:

- The negotiated capability set is written to **`Provider.status.reportedCapabilities`** — operators can read exactly what a live provider pod advertised, without grepping logs or source.
- A **`CapabilitiesReported`** status condition is set once the fetch succeeds (and reflects failures otherwise), so `kubectl wait`/automation can gate on it.

```bash
kubectl get provider vsphere-prod -n virtrigaud-system \
  -o jsonpath='{.status.reportedCapabilities}'

kubectl get provider vsphere-prod -n virtrigaud-system \
  -o jsonpath='{.status.conditions[?(@.type=="CapabilitiesReported")]}'
```

### Opt-in enforcement: `--enforce-provider-capabilities` (v0.3.8, #176)

A new manager flag **`--enforce-provider-capabilities`** gates snapshot and migration operations on the reported capabilities:

- **Default: OFF (fail-open).** With the flag unset, the manager behaves as before — it surfaces capabilities but does **not** block operations on them. This preserves backward compatibility for existing clusters.
- **When ON**, the manager refuses to dispatch snapshot/migration work to a provider whose `reportedCapabilities` do not advertise support, returning a clear `NotSupported`-style failure on the relevant CR instead of letting it fail deep in the hypervisor.

```yaml
# manager Deployment args (Helm values: manager.extraArgs)
args:
  - --enforce-provider-capabilities
```

Enable enforcement once you have confirmed (via `status.reportedCapabilities`) that your providers advertise the operations your workloads depend on.

### Provider capability flags for clustered and security contracts

Beyond the flags shown on `Provider.status.reportedCapabilities`, `GetCapabilities` carries flags the manager reads at runtime to decide whether it may send a call or must hold an operation. The table shows what each provider reports in v0.4.0 (source: each provider's `GetCapabilities`). A manager holds the matching operation when the flag is missing, rather than sending a call the provider would not honour.

| Flag | vSphere | Libvirt (single) | Libvirt (clustered) | Proxmox | Mock |
|------|:---:|:---:|:---:|:---:|:---:|
| `supports_clustering` | no | no | **yes** | no | no |
| `supports_image_artifact_identity` (ADR-0009; import-style `ImagePrepare` is held without it) | yes | yes | no | yes | yes |
| `supports_honest_reconfigure` (a clustered Provider's resizes are held without it) | no | yes | yes | no | no |
| `supports_routed_clone`, `supports_routed_adoption`, `supports_list_owner_filter`, `supports_routed_import` | no | no | **yes** | no | no |
| `supports_owner_transfer` (single-host adoption stamps the VM) | yes | yes | no (uses routed adoption) | yes | yes |
| `supports_owner_rebind` (a re-sent Create/Clone returns the earlier VM) | yes | yes | yes | yes | yes |
| `supports_import_size_limit` (enforces `manager.maxDiskSize` at import) | yes | yes | yes | yes | no |
| `supports_landed_disk_delete` | yes | yes | yes | yes | no |
| `supported_staged_disk_delete_backends` | s3, nfs | s3, nfs | s3, nfs | s3, nfs | none |
| `resend_safe_export_backends` | s3, nfs | s3 | s3, nfs | s3 | none |
| `resend_safe_import_backends` | s3, nfs | pvc, s3, nfs | s3, nfs | s3 | none |
| `supported_export_backends` / `supported_import_backends` | pvc, s3, nfs | pvc, s3, nfs | s3, nfs | s3, nfs | pvc |

`resend_safe_*` lists the staging backends on which the manager may send an `ExportDisk` or `ImportDisk` again on its own after its outcome was lost; on any other backend the `VMMigration` waits for an operator (`ExportOutcomeUnknown`, `ImportOutcomeUnknown`). The flags are defined in [Provider gRPC API](../references/grpc-api.md#changes-since-v0311).

### Adding a capability

The capability builder lives at `sdk/provider/capabilities/` in the main repo and is the source of truth for what flags exist. Adding a new capability requires:

1. A new constant in `sdk/provider/capabilities/capabilities.go`.
2. A new field on `GetCapabilitiesResponse` in `proto/provider/v1/provider.proto`.
3. Per-provider registration in each provider's `capabilities.go` (or inline `GetCapabilities` for the older vSphere/Libvirt servers).

## Provider-Specific Features

### vSphere Exclusive

- **vCenter Integration**: Full vCenter Server and ESXi support
- **Content Library**: Centralized template and ISO management
- **Distributed Resource Scheduler (DRS)**: Automatic load balancing
- **vMotion**: Live migration between hosts
- **High Availability (HA)**: Automatic VM restart on host failure
- **Fault Tolerance**: Zero-downtime VM protection
- **Storage vMotion**: Live storage migration
- **vSAN Integration**: Hyper-converged storage
- **NSX Integration**: Software-defined networking
- **Hot Reconfiguration**: Online CPU/memory/disk changes with hot-add support
- **TaskStatus Tracking**: Real-time async operation monitoring via govmomi
- **Clone Operations**: Full and linked clones with automatic snapshot handling
- **Disk Export/Import**: `ExportDisk` / `ImportDisk` advertising `vmdk` / `qcow2` / `raw` + export compression (#178)
- **Cross-Provider Migration**: full source and target over **S3 and NFS**, both directions (ADR-0006). Disk I/O streams through the provider **pod** (vCenter API for S3; qemu-img `nfs://` libnfs in-pod for NFS); the image bundles `qemu-img` + the `qemu-block-extra` libnfs driver.
- **Web Console URLs**: Direct vSphere web client console access

### Libvirt/KVM Exclusive

- **Virsh + libssh Integration**: Command-line management over an SSH-tunnelled session
- **QEMU Guest Agent**: Advanced guest OS integration
- **KVM Optimization**: Native Linux virtualization
- **Bridge Networking**: Direct host network bridging
- **Storage Pool Flexibility**: Multiple storage backend support
- **Host Device Passthrough**: Hardware device assignment
- **Online Reconfiguration** (#203): Live CPU/memory changes via `virsh setvcpus/setmem --live` for VMs created with `cpuHotAddEnabled`/`memoryHotAddEnabled` on the VMClass (headroom provisioned at create, 4× ceiling, vCPU max 64). Power-cycle required for VMs without the flags.
- **Online Disk Expansion** (#201): Live grow via `virsh blockresize` + best-effort in-guest FS grow. Grow-only.
- **Clone Support** (#153/#208/#221): Full clones, same-provider (linked clones are disabled since v0.4.0). UEFI nvram re-pointed per clone; hot-add headroom preserved across class-override clones; a clone gets its own cloud-init identity and SSH host keys. The source VM must be powered off.
- **Image Preparation** (#154): `VMImage.spec.prepare` drives lazy VM-create-time image import into a storage pool.
- **Memory Snapshots** (#202): RAM-inclusive checkpoints on running VMs; disk-only downgrade with WARN for stopped VMs.
- **VNC Console Access**: Direct VNC console URL generation for remote viewers
- **Disk Export / Import**: `ExportDisk` / `GetDiskInfo` (#177) + `ImportDisk` (`pvc://` / `file://` sources) — feeds the cross-provider migration pipeline
- **Cross-Provider Migration**: full source and target over **S3 and NFS**, both directions (ADR-0006). Disk I/O runs **host-side**: S3 streams over SSH into the pod (the S3 client); NFS uses the host's qemu-img `nfs://` libnfs driver directly against the export.

### Proxmox VE Exclusive

- **Web UI Integration**: Built-in management interface
- **Container Support**: LXC container management
- **Backup Integration**: Built-in backup and restore
- **Cluster Management**: Multi-node cluster support
- **ZFS Integration**: Advanced filesystem features
- **Ceph Integration**: Distributed storage
- **Guest Agent IP Detection**: Accurate IP address extraction via QEMU guest agent
- **Hot-plug Reconfiguration**: Online CPU/memory/disk modifications
- **Memory snapshots**: PVE-style snapshots that include RAM state
- **Cross-Provider Migration**: full source and target over **S3 and NFS**, both directions (ADR-0006). Disk I/O runs **node-side** over the provider's SSH data plane: S3 streams the node-side `qemu-img` over SSH into the pod (the S3 client); NFS **kernel-mounts** the export on the node (PVE's `qemu-img` has no libnfs) and runs qemu-img against the mount. Requires the Provider Secret to carry SSH credentials + a pinned `known_hosts` in addition to the API token.

### Mock Provider Features

- **Testing Scenarios**: Configurable failure modes
- **Performance Simulation**: Controllable operation delays
- **Sample Data**: Pre-populated demonstration VMs
- **Development Support**: Full API coverage for testing

## Supported Disk Types

Reflects each provider's `GetCapabilities.SupportedDiskTypes` response.

| Provider | Disk Formats | Notes |
|----------|-------------|--------|
| **vSphere** | `thin`, `thick`, `eager-zeroed` | vSphere native formats |
| **Libvirt** | `qcow2`, `raw`, `vmdk` | QEMU-supported formats |
| **Proxmox** | `raw`, `qcow2` | Proxmox storage formats |
| **Mock** | `thin`, `thick`, `raw`, `qcow2` | Simulated formats |

## Supported Network Types

Reflects each provider's `GetCapabilities.SupportedNetworkTypes` response.

| Provider | Network Types | Notes |
|----------|--------------|--------|
| **vSphere** | `standard`, `distributed` | Standard vSwitch and distributed virtual switch port groups |
| **Libvirt** | `virtio`, `e1000`, `rtl8139` | QEMU virtual NIC models |
| **Proxmox** | `bridge`, `vlan` | Proxmox network topology |
| **Mock** | `bridge`, `nat`, `distributed` | Simulated network types |

## Provider Images

All provider images are available from the GitHub Container Registry:

- **vSphere**: `ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.0`
- **Libvirt**: `ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.4.0`
- **Proxmox**: `ghcr.io/projectbeskar/virtrigaud/provider-proxmox:v0.4.0`

The mock provider (`provider-mock`) is a development/conformance-testing image only.
It is **not** published under release tags and is **not** part of the multi-arch
release set above.

### Image architectures

Starting with v0.3.7, all images are multi-arch manifests:

| Component | `linux/amd64` | `linux/arm64` |
|-----------|:---:|:---:|
| manager | ✅ | ✅ |
| provider-vsphere | ✅ | ✅ |
| provider-libvirt | ✅ | ✅ |
| provider-proxmox | ✅ | ✅ |
| kubectl | ✅ | ✅ |

arm64 clusters (Apple Silicon nodes, AWS Graviton, Ampere) are fully supported
from v0.3.7 onward. No changes to Provider CRs or Helm values are required —
the container runtime selects the correct layer automatically.

## Choosing a Provider

### Use vSphere When:
- You have existing VMware infrastructure
- You need enterprise features (HA, DRS, vMotion)
- You require advanced networking (NSX, distributed switches)
- You need centralized management (vCenter)

### Use Libvirt/KVM When:
- You want open-source virtualization
- You're running on Linux hosts
- You need cost-effective virtualization
- You want direct host integration

### Use Proxmox VE When:
- You need both VMs and containers
- You want integrated backup solutions
- You need cluster management
- You want web-based management

### Use Mock Provider When:
- You're developing or testing VirtRigaud
- You need to simulate VM operations
- You're creating demos or training materials
- You're testing VirtRigaud without hypervisors

## Performance Considerations

### vSphere
- **Best for**: Large-scale enterprise deployments
- **Scalability**: Hundreds to thousands of VMs
- **Overhead**: Higher due to feature richness
- **Resource Efficiency**: Excellent with DRS

### Libvirt/KVM
- **Best for**: Linux-based deployments
- **Scalability**: Moderate to large deployments
- **Overhead**: Low, near-native performance
- **Resource Efficiency**: Good with proper tuning

### Proxmox VE
- **Best for**: SMB and mixed workloads
- **Scalability**: Small to medium deployments
- **Overhead**: Moderate
- **Resource Efficiency**: Good with clustering

## Future Roadmap

### Planned Enhancements

#### vSphere
- vSphere 8.0 support
- Enhanced NSX integration
- GPU passthrough support
- vSAN policy automation
- URL-based cloud-image import (currently OVA/OVF + content library only)

#### Libvirt
- Live migration support
- SR-IOV networking
- NUMA topology optimization
- Enhanced performance monitoring

#### Proxmox
- HA configuration
- Storage replication
- ConsoleURL implementation
- Performance optimizations

## Support Matrix

| Feature Category | vSphere | Libvirt | Proxmox | Mock |
|-----------------|---------|---------|---------|------|
| **Production Ready** | ✅ | ✅ | ✅ Beta | ✅ Testing |
| **Documentation** | Complete | Complete | Complete | Complete |
| **Community Support** | Active | Active | Growing | N/A |
| **Enterprise Support** | Available | Available | Available | N/A |

## Version History

- **v0.4.0**: **Clustered libvirt providers (experimental)** — `topology: cluster` with `Host`/`HostPool`, a placement scheduler and routed per-host calls; libvirt reports `SupportsHonestReconfigure` (a change that only reaches the persistent definition is reported `RestartRequired`); **libvirt linked clones are disabled** (`SupportsLinkedClones=false`, `LinkedCloneUnsupported`); **snapshot revert** (`spec.snapshot.revertToRef`) on all providers; `spec.disks` is reported as not attached on libvirt and Proxmox (`DisksApplied=False`); Proxmox applies bridge, VLAN, NIC model and static IP and places the cloud-init drive on the VM's storage; identity-safe image preparation (`SupportsImageArtifactIdentity`) on vSphere, libvirt and Proxmox; the owner-stamp, staged/landed disk delete, resend-safe backend and import size-limit flags (see [Provider capability flags](#provider-capability-flags-for-clustered-and-security-contracts)).
- **v0.3.11**: **NFS cross-hypervisor migration staging backend (ADR-0006 Slice 4, #236)** — a second storage-agnostic `VMMigration` backend alongside S3, lab-validated across all three providers (vSphere, libvirt, Proxmox VE) in both directions against a real OpenMediaVault server. The disk is staged on an NFS export and moved with `qemu-img`'s native transport (no PVC, no relay, no S3 credentials): libvirt (host-side) and vSphere (pod-side) use the `nfs://` libnfs driver; **Proxmox kernel-mounts** the export (`pve-qemu-kvm` ships no libnfs). `nfs.uid`/`nfs.gid` are effectively mandatory for cross-provider migrations (AUTH_SYS identity). With the S3 matrix (Slices 1–3) this completes #236's backend-agnostic, any-direction goal. Proxmox now advertises **s3 and nfs** (not PVC).
- **v0.3.9**: Libvirt online CPU/memory reconfigure (#203) — `SupportsReconfigureOnline=true`; hot-add headroom provisioned at create via VMClass flags; lab-verified live. Libvirt online disk expansion (#201) — `SupportsDiskExpansionOnline=true`; `virsh blockresize` + best-effort in-guest FS grow; lab-verified. Libvirt memory snapshots (#202) — `SupportsMemorySnapshots=true`; RAM-inclusive checkpoints on running VMs. Libvirt Clone (#153) — `SupportsLinkedClones=true`; qcow2 overlay (linked) + full copy, same-provider. Libvirt clone hardening (#208/#221) — UEFI nvram re-pointed per clone; hot-add headroom preserved across class-override clones. End-to-end image preparation (#154) — `SupportsImageImport=true`; `VMImage.spec.prepare` drives lazy import on libvirt/vSphere/Proxmox. Proxmox export compression (#219) — honors `Compress` for qcow2 targets. vSphere memory snapshots (#200) — `SupportsMemorySnapshots=true`; `CreateSnapshot(memory=true)`.
- **v0.3.8**: Capability negotiation surfaced on `Provider.status.reportedCapabilities` + `CapabilitiesReported` condition, with opt-in `--enforce-provider-capabilities` (default off, fail-open) (#176); vSphere `GetCapabilities` now advertises disk export **and** import + `vmdk`/`qcow2`/`raw` formats + export compression (#178); libvirt implements `ExportDisk`/`GetDiskInfo` (#177); VMClone controller MVP (same-provider full/linked, vSphere+Proxmox) (#179); vSphere vCenter session keepalive + live-probe reconnect (#190); libvirt transient-SSH retry with bounded backoff (#191); Helm templated providers disabled by default (#173).
- **v0.3.7**: mTLS enforced on all Provider CRs (`TLSConfigured` condition); libvirt SSH host-key verification on by default; multi-arch images (amd64+arm64); manager RBAC tightened.
- **v0.3.6**: Manager-side CircuitBreaker wired on all provider RPCs (G6); G7 metric families completed; H1 build-path consolidation. No new provider-side capabilities.
- **v0.3.5**: Observability G-track foundation — provider RPC metrics surface for every provider.
- **v0.3.3**: Changelog organisation with versioned release headers.
- **v0.2.3**: Provider feature parity — Reconfigure, Clone, TaskStatus, ConsoleURL
- **v0.2.2**: Nested virtualization, TPM support, comprehensive snapshot management
- **v0.2.1**: Critical fixes, documentation updates, VMClass disk settings
- **v0.2.0**: Production-ready vSphere and Libvirt providers
- **v0.1.0**: Initial provider framework and mock implementation

---

*This document reflects VirtRigaud v0.4.0 capabilities. For the latest updates, see the [VirtRigaud documentation](https://projectbeskar.github.io/virtrigaud/).*
