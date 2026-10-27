<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Provider Capabilities Matrix

This document provides a comprehensive overview of VirtRigaud provider capabilities as of **v0.4.1**.

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

Setup, placement and operations: [Clustered libvirt guide](../guides/clustered/index.md). Details: [Libvirt provider](libvirt.md) and [`clustered-provider-inventory.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/clustered-provider-inventory.md).

## Comprehensive Capability Matrix

Legend: ✅ supported through VirtRigaud CRs; ⚠️ partial (see the note in the row); ❌ not supported through VirtRigaud on that provider. A hypervisor may do more natively (HA, DRS, vMotion, Fault Tolerance, Resource Pools) but VirtRigaud does not expose it, and the matrix marks it ❌. The **Mock** column means the in-memory simulation implements the call; it has no hypervisor behind it and is a development image only. The `Libvirt` column is single-host libvirt; see [Clustered libvirt](#clustered-libvirt-experimental) for the differences.

### Core Operations

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **VM Create** | ✅ | ✅ | ✅ | ✅ | |
| **VM Delete** | ✅ | ✅ | ✅ | ✅ | With resource cleanup |
| **Power On/Off** | ✅ | ✅ | ✅ | ✅ | `spec.powerState`: `On`, `Off`, `OffGraceful` |
| **Reboot** | ❌ | ❌ | ❌ | ❌ | The provider contract has a Reboot operation, but no CR field triggers it |
| **Suspend** | ❌ | ❌ | ❌ | ❌ | There is no suspend operation. A VM found suspended is reported `status.powerState: Suspended` (phase `Running`). It is not resized or powered on; if its `spec.powerState` is `Off` it is powered off, and `OffGraceful` waits until it is resumed |
| **Describe** | ✅ | ✅ | ✅ | ✅ | VM state and properties |
| **Reconfigure** | ⚠️[^reconfigure] | ✅[^reconfigure] | ⚠️[^reconfigure] | ✅ | CPU and memory (and `spec.disks` growth on vSphere); see the footnote for what each provider applies |
| **TaskStatus** | ✅ | N/A | ✅ | ✅ | Async operation tracking; libvirt operations are synchronous |
| **ConsoleURL** | ✅ | ⚠️ | ✅ | ✅ | vSphere and Proxmox return a web-console link; libvirt returns a `vnc://` address only while the VM runs with VNC |

### Resource Management

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **CPU Configuration** | ⚠️ | ⚠️ | ⚠️ | ✅ | vCPU count only; no sockets or threading from the CR |
| **Memory Allocation** | ✅ | ✅ | ✅ | ✅ | |
| **Hot CPU Add** | ⚠️[^reconfigure] | ⚠️[^reconfigure] | ❌ | ✅ | vSphere and libvirt: only for VMs created from a `VMClass` with `performanceProfile.cpuHotAddEnabled` |
| **Hot Memory Add** | ⚠️[^reconfigure] | ⚠️[^reconfigure] | ❌ | ✅ | Same, with `memoryHotAddEnabled` |
| **Resource Reservations** | ❌ | ❌ | ❌ | ❌ | `VMClass.spec.resourceLimits` is passed to providers but none reads it |
| **Resource Limits** | ❌ | ❌ | ❌ | ❌ | Same |

### Storage Operations

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Disk Creation** | ✅ | ⚠️ | ⚠️ | ✅ | vSphere attaches `spec.disks`. libvirt and Proxmox create only the root disk (from the image or template); `spec.disks` is not attached (`DisksApplied=False/NotSupportedByProvider`) and Proxmox does not apply `diskDefaults.size` |
| **Disk Expansion** | ⚠️ | ⚠️[^diskexpand] | ❌ | ✅ | vSphere grows additional disks named in `spec.disks`, never the root disk. libvirt grows the root disk online (grow-only). Proxmox resizes no disk (grow it in PVE). A disk-size change alone sends no Reconfigure: it is applied together with a CPU or memory change |
| **Multiple Disks** | ✅ | ❌ | ❌ | ✅ | `spec.disks` (max 20) is attached on vSphere only |
| **Thin Provisioning** | ✅ | ✅ | ⚠️ | ✅ | vSphere: `spec.disks[].type`. libvirt: sparse qcow2. Proxmox: inherited from the template and storage, not selectable |
| **Thick Provisioning** | ✅ | ❌ | ❌ | ✅ | vSphere `thick` and `eagerzeroedthick` for `spec.disks` |
| **Storage Policies** | ❌ | ❌ | ❌ | ❌ | No storage-policy (SPBM) support |
| **Storage Pools** | ✅ | ✅ | ✅ | ✅ | vSphere datastore or datastore cluster, libvirt storage pool, Proxmox storage |

[^diskexpand]: As of v0.3.9 (#201), libvirt advertises `SupportsDiskExpansionOnline=true`. Online grow runs via `virsh blockresize` (grow-only; shrink is not supported) followed by a best-effort in-guest filesystem grow via the QEMU guest agent (`resize2fs` / `xfs_growfs`). If the guest agent is absent or the layout is non-standard (LVM, multiple partitions), the block device is enlarged but the guest filesystem must be grown manually. The grow is sent with a CPU or memory change.

### Network Configuration

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Basic Networking** | ✅ | ✅ | ✅ | ✅ | |
| **Multiple NICs** | ❌ | ✅ | ✅ | ✅ | vSphere uses the first entry of `spec.networks` only. libvirt could not create a VM with more than one NIC before v0.4.1 (libvirt refused the domain); it can now |
| **VLAN Support** | ⚠️ | ⚠️ | ✅ | ✅ | vSphere and libvirt: attach to a VLAN-backed port group or pre-tagged bridge; VirtRigaud sets no tag. Proxmox applies `vlanTag` |
| **Static IP** | ⚠️ | ❌ | ✅ | ✅ | vSphere: first NIC, through `guestinfo.network.*` keys the guest must consume. libvirt ignores `spec.networks[].ipAddress`. Proxmox: for a VM with user-data, the address, route and DNS go into the seed's `network-config`; for one without, `ipconfigN` (needs `prefix`; needs a PVE cloud-init drive) |
| **DHCP** | ✅ | ✅ | ✅ | ✅ | |
| **Bridge Networks** | ❌ | ✅ | ✅ | ✅ | libvirt `bridge`, Proxmox `vmbrN`. Proxmox also applies the NIC model |
| **Distributed Switches** | ✅ | ❌ | ❌ | ✅ | vSphere attaches a NIC to a port group by name and reports `standard` and `distributed` network types, so a distributed port group works. VirtRigaud does not create or manage switches |

### VM Lifecycle

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Template Deployment** | ✅ | ✅ | ✅ | ✅ | Deploy from templates or base images |
| **Clone Operations** | ✅ | ✅[^clone] | ✅ | ✅ | `VMClone`, same provider only |
| **Linked Clones** | ✅ | ❌[^clone] | ❌[^pvelinked] | ✅ | libvirt and Proxmox refuse a `VMClone` with `type: LinkedClone` (`LinkedCloneUnsupported`) |
| **Full Clones** | ✅ | ✅[^clone] | ✅ | ✅ | libvirt: source VM must be powered off |
| **VM Reconfiguration** | ⚠️ | ✅ | ⚠️ | ✅ | See Reconfigure |

[^clone]: libvirt `Clone` is implemented for **full clones** (#153/#208/#221): the per-VM UEFI `<nvram>` varstore is copied to an independent file, hot-add headroom is preserved across a class-override clone, and a clone gets its own cloud-init instance id and SSH host keys. **Linked clones are disabled since v0.4.0**: a linked clone reads its source VM's live disk, and powering the source on corrupts the clone. `GetCapabilities` reports `SupportsLinkedClones=false` and a `VMClone` with `options.type: LinkedClone` fails with `LinkedCloneUnsupported`. Linked clones made by earlier releases keep working, but their source cannot be deleted, reverted or snapshotted while they exist. Earlier documentation (including v0.3.9 footnotes) listed libvirt linked clones as supported — that is reversed in v0.4.0.

[^pvelinked]: Proxmox never made linked clones: every `Create` from a template and every `Clone` is a full clone. Before v0.4.1 the provider still advertised linked-clone support and `Clone` passed `full=0` for a linked request; since v0.4.1 it reports no linked-clone support, its `Clone` refuses a linked request, and the `VMClone` controller refuses a `LinkedClone` for it before calling the provider.

[^reconfigure]: What `Reconfigure` does per provider (`docs/reconfigure-results.md` in the main repository). **libvirt** (`SupportsHonestReconfigure=true`): each change is applied live and persisted, or persisted only and reported as restart required (`Reconfiguring=True/RestartRequired`: power-cycle the VM; a reboot inside the guest does not apply it), or the call fails. Online CPU/memory works **only on VMs created with the hot-add flags** (`VMClass.spec.performanceProfile.cpuHotAddEnabled` and/or `memoryHotAddEnabled` at create time; 4× memory ceiling, vCPU capped at 64). A memory shrink of a running VM always needs a restart. **vSphere**: CPU, memory and growth of additional disks named in `spec.disks`. It refuses a change the running VM cannot take (no hot-add, a memory decrease) before changing anything, shown as `Reconfiguring=False/ResizePendingPowerOff` until the VM is powered off; the root disk is never resized; the provider does not report the honest-result flag. **Proxmox**: CPU and memory only, no disk; a change PVE leaves pending until the next boot is reported as applied. Proxmox still advertises `SupportsReconfigureOnline` and `SupportsDiskExpansionOnline`; the ❌ cells above describe what the provider actually does.

### Snapshot Operations

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Create Snapshots** | ✅ | ✅ | ✅ | ✅ | `VMSnapshot` |
| **Delete Snapshots** | ✅ | ⚠️ | ✅ | ✅ | libvirt refuses to delete a disk-only snapshot while a memory snapshot is stored in its overlay: delete the memory snapshot first |
| **Revert Snapshots** | ⚠️ | ⚠️ | ⚠️ | ✅ | `spec.snapshot.revertToRef`, only while the VM is off. libvirt additionally needs a snapshot taken with the VM powered off, and libvirt 9.9+. See [Snapshots and revert](#snapshots-and-revert) |
| **Memory Snapshots** | ✅[^memsnap] | ⚠️[^memsnap] | ✅ | ✅ | Include RAM state |
| **Quiesced Snapshots** | ❌ | ❌ | ❌ | ❌ | `snapshotConfig.quiesce` is not sent to providers |
| **Snapshot Trees** | ⚠️ | ⚠️ | ⚠️ | ✅ | Several snapshots per VM; `status.parent` and `children` are not populated |

[^memsnap]: All three providers support RAM-inclusive snapshots. **vSphere** (#200): `CreateSnapshot(memory=true)`; requires the VM powered on. **Libvirt** (#202): `virsh snapshot-create-as` without `--disk-only`; a running VM captures disk and RAM state; a stopped VM is downgraded to a disk-only snapshot with a warning logged. **Proxmox**: PVE-native RAM-inclusive snapshots. Set `spec.snapshotConfig.includeMemory: true` on the `VMSnapshot` CR.

### Snapshots and revert

| Topic | vSphere | Libvirt | Proxmox |
|-------|---------|---------|---------|
| Memory snapshot (`snapshotConfig.includeMemory: true`) | VM must be powered on | Running VM: internal snapshot with RAM. Powered-off VM: disk-only (a warning is logged) | PVE-native |
| Revert (`VirtualMachine.spec.snapshot.revertToRef`, VM powered off) | `RevertToSnapshot_Task`; a memory snapshot powers the VM on, then `spec.powerState` is applied | External snapshots need libvirt 9.9+. Refused for a snapshot that stored the cloud-init CD-ROM: take the snapshot **with the VM powered off** to be able to revert it. Refused while a linked clone depends on the VM's disk | Rollback task, polled by the manager |
| Delete | Refuses a template or prepared-image artifact (`VM_IS_IMAGE_ARTIFACT`) | Deleting a disk-only snapshot is refused while a memory snapshot of the VM is stored in its overlay: delete the memory snapshot first (`Ready=False/DeleteBlocked`) | Refused when the VM's owner stamp cannot be read |

A revert discards what was written to the disks since the snapshot. Walkthrough, rules and troubleshooting: [VM snapshots and revert](../guides/vm-snapshots.md). The revert was accepted but ignored before v0.4.0. Full rules: [`vm-snapshot-revert.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/vm-snapshot-revert.md) and the [VM CRD reference](../references/crds.md#snapshot-revert).

### Image Management

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **OVA/OVF Import** | ✅ | ❌ | ❌ | ✅ | vSphere `source.vsphere.ovaURL`. Proxmox refuses image import |
| **Image Import (URL)** | ⚠️[^4] | ✅[^imageimport] | ❌ | ✅ | vSphere: OVA/OVF URLs only. libvirt: download, convert, publish into a storage pool. Proxmox: `source.http` is refused (ADR-0009); use a template |
| **Content Libraries** | ❌ | ❌ | ❌ | ❌ | A content-library item is verified, then refused as not yet implemented |
| **Image Conversion** | ❌ | ✅ | ❌ | ✅ | libvirt converts downloaded images to qcow2 (`qemu-img convert`). Format conversion also happens inside `VMMigration` on every provider |
| **Image Caching** | ✅ | ✅ | ❌ | ✅ | Prepared images are reused by identity (ADR-0009): vSphere stamped templates, libvirt stamped pool files |

[^4]: vSphere advertises `SupportsImageImport=true` for OVA/OVF URLs. A direct cloud-image URL (qcow2/img) and content-library items are not implemented; land cloud images as a vSphere template out-of-band and reference it with `templateName`.

[^imageimport]: libvirt's `ImagePrepare` is implemented (#154) and reports `SupportsImageImport=true` and `SupportsImageArtifactIdentity=true` (single-host only; a clustered Provider does not prepare images). `VMImage.spec.prepare` drives lazy, VM-create-time import into a libvirt storage pool. A `VMImage` with an **import-style** source (a download `url`) and `prepare.onMissing: Fail` whose image is not yet imported holds new VM creation with a `WaitingForDependencies` condition until preparation completes. Images that reference an **already-present** artifact (a libvirt pool-file `path`, an existing template) create normally. A `path` must be inside an allowed image directory (`VIRTRIGAUD_LIBVIRT_IMAGE_DIRS`) and is always copied.

### Disk Export / Import & Cross-Provider Migration

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Disk Export** | ✅[^7] | ✅[^8] | ✅ | ❌ | `ExportDisk` / `GetDiskInfo`; vSphere also advertises export compression |
| **Disk Import** | ✅[^7] | ✅[^8] | ✅ | ❌ | `ImportDisk` |
| **Export Compression** | ✅ | ✅ | ✅[^proxmoxcomp] | ❌ | vSphere and libvirt honor `req.Compress`; Proxmox (#219) |
| **Export Formats** | `vmdk`, `qcow2`, `raw` | `qcow2`, `raw` (clustered: `qcow2`) | `qcow2`, `raw`, `vmdk` | n/a | vSphere & Proxmox `GetCapabilities` advertise all three (#178 / #198) |
| **Cross-Provider Migration — S3 backend** | ✅[^migrate] | ✅[^migrate] | ✅[^migrate] | n/a | `VMMigration` over S3-compatible object storage (`relay`). Validated at v0.3.11 as source **and** target for every pair among the three providers (ADR-0006 Slices 1–3, #236); see [what was validated](../migration/user-guide.md#what-virtrigaud-v041-supports). |
| **Cross-Provider Migration — NFS backend** | ✅[^migratenfs] | ✅[^migratenfs] | ✅[^migratenfs] | n/a | `VMMigration` over an NFS export via `qemu-img` (ADR-0006 Slice 4, #236). vSphere pod-side libnfs, libvirt host-side libnfs, **Proxmox kernel-mount**. Validated at v0.3.11 for libvirt ⇄ libvirt, libvirt ⇄ vSphere and libvirt ⇄ Proxmox; **vSphere ⇄ Proxmox over NFS has not been run** ([details](../migration/user-guide.md#what-virtrigaud-v041-supports)). |

A clustered libvirt Provider is also accepted as a `VMMigration` **target** over S3 or NFS (experimental, v0.4.1): the target VM is created and placed first on a host whose `default` pool has room for the disk, and the disk is imported onto that host. It was run from single-host libvirt, vSphere and Proxmox (S3) sources. Host-to-host migration is not implemented.

This is VirtRigaud's **storage-backend-agnostic, any-direction** cross-hypervisor
migration (ADR-0006): the disk is staged on a pluggable backend (S3 or NFS) and
moved with `qemu-img` — it **never traverses a CSI PVC**. Over S3 every pair among
vSphere, Libvirt/KVM and Proxmox VE was lab-validated in both directions (v0.3.11); over NFS
five pairs were, and vSphere ⇄ Proxmox VE was not ([what was validated](../migration/user-guide.md#what-virtrigaud-v041-supports)). A legacy `pvc` staging mode remains for the vSphere/libvirt
directions but is **compat-only** — it cannot reach host-resident libvirt disks or
Proxmox node storage. Do not confuse this with the **vMotion/Migration** row in
[Advanced Features](#advanced-features) below, which is *intra-hypervisor live*
migration (vSphere vMotion, PVE live migrate), a separate hypervisor-native feature.
See the [VM Migration docs](../migration/user-guide.md) for the full guide.

[^7]: As of v0.3.8 (#178), vSphere's `GetCapabilities` advertises disk **export and import** plus the `vmdk`, `qcow2`, and `raw` formats and export compression. Prior releases understated these flags (export/import reported as unsupported/zero); the cells above match the actual v0.3.8 response in `internal/providers/vsphere/server.go`.

[^8]: libvirt implements both `ExportDisk` / `GetDiskInfo` (#177, v0.3.8) and `ImportDisk` (accepting `pvc://` sources; the pod-side import no longer accepts `file://`), and `GetCapabilities` reports `SupportsDiskExport=true` **and** `SupportsDiskImport=true`. These feed the cross-provider migration pipeline (vSphere → libvirt export/convert/import). Proxmox likewise advertises both export and import for `qcow2`/`raw`/`vmdk` (#198).

[^proxmoxcomp]: As of v0.3.9 (#219), Proxmox's `ExportDisk` honors the `Compress` field for qcow2 targets and advertises `SupportsExportCompression=true` in `GetCapabilities`.

[^migrate]: Cross-provider migration over the **S3** staging backend is validated end-to-end for every provider as both source and target, in both directions, across all pairs — vSphere ⇄ libvirt (ADR-0006 Slices 1–2) and Proxmox ⇄ libvirt / Proxmox ⇄ vSphere (Slice 3, #236). The provider **pod** is the S3 client (the universal `relay` transfer mode; `auto` resolves to `relay`, `direct` is a roadmap item), so the disk bytes flow host → pod → S3 → pod → host and never traverse a CSI PVC. The source exports its native format; the **target** owns format conversion (vmdk ↔ qcow2). For Proxmox and libvirt the bytes are read/written on the hypervisor node/host and streamed over SSH into the provider pod, so the Proxmox/libvirt **Provider** Secret must also carry SSH credentials and a pinned `known_hosts`.

[^migratenfs]: As of v0.3.11 (ADR-0006 Slice 4, #236), the **NFS** staging backend was validated for libvirt ⇄ libvirt, libvirt ⇄ vSphere and libvirt ⇄ Proxmox, against a real NFS server (vSphere ⇄ Proxmox over NFS was not run). Instead of an object store, the disk is staged on an NFS export and moved with `qemu-img`'s native transport (no PVC, no pod relay, no S3 credentials). **libvirt** (host-side) and **vSphere** (pod-side) use qemu-img's `nfs://` libnfs driver directly; the vSphere image bakes in the Debian `qemu-block-extra` package. **Proxmox uses a kernel NFS mount** — `pve-qemu-kvm` ships no libnfs driver (qemu-img rejects `nfs://` with `Unknown protocol 'nfs'`), so the node mounts the export the way PVE's native NFS storage does and runs qemu-img against the mount. `nfs.uid`/`nfs.gid` are effectively mandatory for cross-provider migrations (AUTH_SYS authorizes by the numeric uid/gid presented, and each leg runs as a different identity) — set them to the export owner. See the [VM Migration User Guide](../migration/user-guide.md#nfs-staging).

### Virtual Platform (VMClass)

Settings of the `VMClass` that choose the VM's firmware and virtual hardware. They take effect when a VM is created; a change to a VMClass does not change existing VMs.

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **UEFI firmware** (`firmware: UEFI`) | ✅ | ✅ | ❌ | ❌ | libvirt honours it since v0.4.1 (q35 machine, OVMF; the host needs an OVMF package). `BIOS`, `EFI` and an unset value select BIOS. Proxmox keeps the template's firmware |
| **Secure Boot** (`securityProfile.secureBoot`) | ✅ | ✅ | ❌ | ❌ | libvirt: works since v0.4.1, with Secure Boot enforced from the first boot; which keys the guest trusts depends on the host's OVMF package |
| **VT-d / IOMMU** (`securityProfile.vtdEnabled`) | ✅ | ⚠️ | ❌ | ❌ | libvirt: an emulated Intel IOMMU on q35 since v0.4.1; the virtio devices do not go through it, so it is not DMA isolation |
| **Nested virtualization** (`performanceProfile.nestedVirtualization`) | ✅ | ✅ | ❌ | ❌ | libvirt: works since v0.4.1 (`host-passthrough`); nesting must be enabled in the host's KVM module |
| **TPM** (`securityProfile.tpmEnabled`) | ✅ | ✅ | ❌ | ❌ | libvirt: an emulated TPM 2.0 (`swtpm` on the host) |

libvirt details, host prerequisites and the secure boot trust model: [libvirt firmware](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/libvirt-firmware.md) and the [libvirt provider page](libvirt.md#firmware-secure-boot-and-platform-features). On a clustered libvirt Provider every host that can receive a UEFI or secure boot VM needs the OVMF package: the scheduler does not consider firmware.

### Guest Operating System

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Cloud-Init** | ✅ | ✅ | ✅ | ✅ | vSphere guestinfo, libvirt NoCloud ISO (private, in the host seed directory), Proxmox NoCloud seed CD-ROM built over SSH (since v0.4.1; the whole user-data applies, and it needs SSH credentials in the Provider's Secret) |
| **Cloud-Init on clone** | ✅ | ✅ | ⚠️ | N/A | vSphere and libvirt clones re-run the source's user-data. A Proxmox clone does not: it gets a seed of its own with the `VMClone`'s inline user-data (else one that configures nothing) |
| **Guest Tools** | ❌ | ❌ | ❌ | ❌ | `VMClass.spec.guestToolsPolicy` is passed to providers but none acts on it; install tools through cloud-init |
| **Guest Agent** | ✅ | ✅ | ✅ | ✅ | VMware Tools (vSphere) or the QEMU guest agent report IPs |
| **Guest Customization** | ⚠️ | ⚠️ | ❌ | ✅ | `VMClone` applies hostname, domain and inline cloud-init only (vSphere, libvirt); sysprep, networks and time zone are not applied. Proxmox clone ignores customization |
| **Guest Monitoring** | ⚠️ | ⚠️ | ❌ | ✅ | Point-in-time values in `status.provider`; no metrics series |

### Advanced Features

VirtRigaud does not expose the hypervisors' cluster features. They are listed so the matrix is explicit.

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **High Availability** | ❌ | ❌ | ❌ | ❌ | |
| **DRS/Load Balancing** | ❌ | ❌ | ❌ | ❌ | Clustered libvirt places a VM at create time (`Spread`/`BinPack`); it never moves a running VM |
| **Fault Tolerance** | ❌ | ❌ | ❌ | ❌ | |
| **vMotion/Migration** | ❌ | ❌ | ❌ | ❌ | `VMMigration` is a cold cross-provider disk move; there is no live migration and no host-to-host migration |
| **Resource Pools** | ❌ | ❌ | ❌ | ❌ | vSphere VMs always go to the cluster's root pool |
| **Affinity Rules** | ❌ | ⚠️ | ❌ | ❌ | Clustered libvirt only: `VMPlacementPolicy` host and VM (anti-)affinity in the scheduler |

### Monitoring & Observability

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Performance Metrics** | ⚠️ | ⚠️ | ❌ | ✅ | Point-in-time `status.provider` values, no per-VM metric series |
| **Event Logging** | ✅ | ✅ | ✅ | ✅ | Kubernetes events and operation metrics, provider-agnostic |
| **Health Checks** | ⚠️ | ⚠️ | ⚠️ | ⚠️ | Provider health and VM conditions; no guest health probe |
| **Alerting** | ⚠️ | ⚠️ | ⚠️ | ⚠️ | Opt-in `PrometheusRule` for manager and provider health, not per-VM thresholds |
| **Historical Data** | ❌ | ❌ | ❌ | ❌ | |
| **Console URL Generation** | ✅ | ⚠️ | ✅ | ✅ | See ConsoleURL |
| **Guest Agent Integration** | ✅ | ✅ | ✅ | ✅ | IP detection and guest info |
| **CircuitBreaker (manager-side)** | ✅ | ✅ | ✅ | ✅ | One CB per Provider CR. See [Resilience](../operations/resilience.md). |

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

#### When the status is read (v0.4.1)

In v0.4.0, `status.reportedCapabilities` could keep what the previous provider image reported after a roll of `spec.runtime.image`: the manager read it over its cached connection, which a terminating pod of the old ReplicaSet could still answer, and nothing read it again. The gates that read it (image import, clustered resizes, snapshot reverts, migration backends) then acted on the old image's answer. Since v0.4.1 the manager reads the capabilities:

- only once the provider Deployment's rollout is complete, over a connection opened for the read (a read gives up after 10 seconds);
- again when the Deployment changes, once more 45 seconds after the rollout completed, every 10 minutes while the `Provider` is healthy, and one minute after a failed read (`CapabilitiesReported=False`, reason `CapabilitiesUnavailable`; the recorded capabilities are kept).

Expect the new image's answer within about a minute of the rollout completing. A provider image re-pulled under the same tag is caught by the 10-minute read. While a rollout is stuck, the capabilities of the old pods are kept.

`status.healthy` and the `ProviderAvailable` condition follow the Deployment's ready replicas: a `Provider` without a ready pod is `ProviderAvailable=False` (reason `DeploymentNotReady`) and `healthy: false`. Both stayed `True` once set before v0.4.1. The field `healthy` is omitted from the object when it is `false`, so the `HEALTHY` column of `kubectl get provider` is empty, not `false`. A vSphere or clustered `Provider` (one replica, `Recreate` strategy) is briefly unavailable during each of its rollouts, so an alert on these can fire during a roll.

### Opt-in enforcement: `--enforce-provider-capabilities` (v0.3.8, #176)

A new manager flag **`--enforce-provider-capabilities`** gates snapshot and migration operations on the reported capabilities:

- **Default: OFF (fail-open).** With the flag unset, the manager behaves as before — it surfaces capabilities but does **not** block operations on them. This preserves backward compatibility for existing clusters.
- **When ON**, the manager refuses to dispatch snapshot/migration work to a provider whose `reportedCapabilities` do not advertise support, returning a clear `NotSupported`-style failure on the relevant CR instead of letting it fail deep in the hypervisor.

```yaml
# manager Deployment args: patch the manager Deployment's container args
# (the chart has no value for this flag)
args:
  - --enforce-provider-capabilities
```

Enable enforcement once you have confirmed (via `status.reportedCapabilities`) that your providers advertise the operations your workloads depend on.

### Provider capability flags for clustered and security contracts

Beyond the flags shown on `Provider.status.reportedCapabilities`, `GetCapabilities` carries flags the manager reads at runtime to decide whether it may send a call or must hold an operation. The table shows what each provider reports in v0.4.1 (source: each provider's `GetCapabilities`). A manager holds the matching operation when the flag is missing, rather than sending a call the provider would not honour.

| Flag | vSphere | Libvirt (single) | Libvirt (clustered) | Proxmox | Mock |
|------|:---:|:---:|:---:|:---:|:---:|
| `supports_clustering` | no | no | **yes** | no | no |
| `supports_linked_clones` (the `VMClone` controller refuses `LinkedClone` without it) | yes | no | no | no (not advertised since v0.4.1) | yes |
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

`resend_safe_*` lists the staging backends on which the manager may send an `ExportDisk` or `ImportDisk` again on its own after its outcome was lost; on any other backend the `VMMigration` waits for an operator (`ExportOutcomeUnknown`, `ImportOutcomeUnknown`). The flags are defined in [Provider gRPC API](../references/grpc-api-guide.md#changes-since-v0311).

### Adding a capability

The capability builder lives at `sdk/provider/capabilities/` in the main repo and is the source of truth for what flags exist. Adding a new capability requires:

1. A new constant in `sdk/provider/capabilities/capabilities.go`.
2. A new field on `GetCapabilitiesResponse` in `proto/provider/v1/provider.proto`.
3. Per-provider registration in each provider's `capabilities.go` (or inline `GetCapabilities` for the older vSphere/Libvirt servers).

## Provider-Specific Features

These are the features VirtRigaud exposes for each provider. Hypervisor-native features that VirtRigaud does not expose (vMotion, DRS, HA, vSAN, NSX, ZFS, Ceph, LXC, backups) are not listed.

### vSphere

- **vCenter and ESXi** through govmomi, with session keepalive and live-probe reconnect.
- **Templates and OVA/OVF import**: `VMImage.source.vsphere.templateName` (a real template) or `ovaURL`; prepared templates are stamped and reused by identity.
- **Reconfigure**: CPU and memory (online with hot-add enabled on the VM), growth of additional disks; refuses a change a running VM cannot take until it is powered off.
- **Clones**: full and linked, with automatic snapshot handling. Template and prepared-image artifacts are never deleted, powered, resized or snapshotted through a `VirtualMachine`.
- **Datastore cluster (StoragePod) selection** and SCSI controller specs. The `HardwareUpgrade` RPC exists but no controller calls it (see [vSphere hardware version](../operations/vsphere-hardware-version.md)).
- **Memory snapshots** (VM powered on) and **snapshot revert**.
- **Disk export/import** (`vmdk`, `qcow2`, `raw`) and cross-provider migration over **S3 and NFS**. Disk I/O streams through the provider pod; the image bundles `qemu-img` and the libnfs driver. Imports land per namespace at `[<datastore>] <namespace>_<vm name>-migrated/...`.
- **Required privileges** include `VirtualMachine.Config.AdvancedConfig` (owner stamps) and `System.Read` on the root folder. One replica, `Recreate` strategy.

### Libvirt/KVM

- **Virsh over an SSH session** (in-process SSH client with host-key verification).
- **Guest agent**: IP discovery, time sync, in-guest filesystem grow.
- **Online reconfiguration** (#203) for VMs created with the hot-add flags, reported honestly (live, restart required, or failed).
- **Online disk expansion** (#201): grow-only, root disk.
- **Full clones** (#153/#208/#221), same provider, source powered off. **Linked clones are disabled.**
- **Platform features** (v0.4.1): UEFI (`firmware: UEFI`), Secure Boot, an emulated IOMMU (VT-d), nested virtualization and VMs with several network interfaces define and start on libvirt 10.
- **Image preparation** (#154): `VMImage` `url` sources downloaded, converted and published in a storage pool; `path` sources copied from allowed directories.
- **Snapshots**: memory snapshots on running VMs; snapshot revert for snapshots taken powered off; delete-order protection for memory snapshots.
- **Private cloud-init seeds** in a dedicated host directory (`/var/lib/libvirt/virtrigaud-seeds`, mode `0711`).
- **VNC console address** while the VM runs.
- **Disk export/import** and cross-provider migration over **S3 and NFS**: host-side `qemu-img`; NFS uses the libnfs driver against the export, S3 streams over SSH into the pod.
- **Clustered topology** (experimental): see [above](#clustered-libvirt-experimental) and the [Clustered libvirt guide](../guides/clustered/index.md).

### Proxmox VE

- **REST API** with an API token (`token_id`, `token_secret`) or username/password; an SSH data plane for migration and for the cloud-init seed.
- **Templates**: `VMImage.source.proxmox` (`templateID` or `templateName`); URL import is refused.
- **Networks**: bridge, VLAN tag, NIC model and static IP are applied (token needs `VM.Config.Network`, `VM.Config.Cloudinit` and `SDN.Use`).
- **Cloud-init**: the whole `spec.userData` through a NoCloud seed CD-ROM built on the node over SSH (since v0.4.1), kept out of the boot order. Needs SSH credentials in the Provider's Secret; a VM without user-data uses PVE's own cloud-init drive, placed on the storage of the VM's disk.
- **Full clones only**: linked clones are not advertised since v0.4.1.
- **Guest agent IP detection** and a console link to the PVE web UI.
- **Reconfigure**: CPU and memory only.
- **Memory snapshots** (PVE-native) and **snapshot revert** (rollback task).
- **Cross-provider migration** over **S3 and NFS**: node-side over SSH; NFS is kernel-mounted on the node (PVE's `qemu-img` has no libnfs). The Provider Secret needs SSH credentials and a pinned `known_hosts` in addition to the API token. Only the VM's own verified migration stage is imported.

### Mock Provider Features

- **Testing Scenarios**: Configurable failure modes
- **Performance Simulation**: Controllable operation delays
- **Development Support**: In-memory implementation of the core RPCs for testing; it has no disk export/import or NFS/S3 staging, and is not published under release tags.

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

- **vSphere**: `ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.1`
- **Libvirt**: `ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.4.1`
- **Proxmox**: `ghcr.io/projectbeskar/virtrigaud/provider-proxmox:v0.4.1`

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
- You want VMs created from vSphere templates or OVA/OVF images
- You attach VMs to standard or distributed port groups
- You need centralized management (vCenter)

### Use Libvirt/KVM When:
- You want open-source virtualization
- You're running on Linux hosts
- You need cost-effective virtualization
- You want direct host integration

### Use Proxmox VE When:
- You need both VMs and containers
- You want to drive VMs through the Proxmox API with API tokens
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

## Support Matrix

| Feature Category | vSphere | Libvirt | Proxmox | Mock |
|-----------------|---------|---------|---------|------|
| **Production Ready** | ✅ | ✅ | ✅ Beta | ✅ Testing |
| **Documentation** | Complete | Complete | Complete | Complete |

Support is best-effort and there is no long-term-support line; see [Versioning](versioning.md) for which releases receive fixes.

## Version History

- **v0.4.1**: **Proxmox** builds a NoCloud seed over SSH so the whole `spec.userData` reaches the guest (breaking for VMs that carry user-data: SSH credentials in the Provider's Secret), keeps the seed out of the boot order, answers a VMID race "not performed", gives a clone the class's memory, and **no longer advertises linked clones**. **libvirt** secure boot, `firmware: UEFI` (now honoured: a behaviour change), VT-d, nested virtualization and multi-NIC VMs work; a snapshot whose overlay file already exists is refused for good and "not performed" snapshot and revert answers are retried. The manager retries a refused create on a backoff, keeps a provider's answer across a status-write conflict, re-reads `status.reportedCapabilities` after a provider roll and follows the ready replicas in `status.healthy` and `ProviderAvailable`. `vcts run`, `virtrigaud-loadgen` and `vrtg-provider init --type proxmox` work. See the [upgrade notes](../operations/upgrade.md#upgrading-from-v040-to-v041).
- **v0.4.0**: **Clustered libvirt providers (experimental)** — `topology: cluster` with `Host`/`HostPool`, a placement scheduler and routed per-host calls; libvirt reports `SupportsHonestReconfigure` (a change that only reaches the persistent definition is reported `RestartRequired`); **libvirt linked clones are disabled** (`SupportsLinkedClones=false`, `LinkedCloneUnsupported`); **snapshot revert** (`spec.snapshot.revertToRef`) on all providers; `spec.disks` is reported as not attached on libvirt and Proxmox (`DisksApplied=False`); Proxmox applies bridge, VLAN, NIC model and static IP and places the cloud-init drive on the VM's storage; identity-safe image preparation (`SupportsImageArtifactIdentity`) on vSphere, libvirt and Proxmox; the owner-stamp, staged/landed disk delete, resend-safe backend and import size-limit flags (see [Provider capability flags](#provider-capability-flags-for-clustered-and-security-contracts)).
- **v0.3.11**: **NFS cross-hypervisor migration staging backend (ADR-0006 Slice 4, #236)** — a second storage-agnostic `VMMigration` backend alongside S3, lab-validated against a real NFS server for libvirt ⇄ libvirt, libvirt ⇄ vSphere and libvirt ⇄ Proxmox VE (vSphere ⇄ Proxmox VE over NFS was not run). The disk is staged on an NFS export and moved with `qemu-img`'s native transport (no PVC, no relay, no S3 credentials): libvirt (host-side) and vSphere (pod-side) use the `nfs://` libnfs driver; **Proxmox kernel-mounts** the export (`pve-qemu-kvm` ships no libnfs). `nfs.uid`/`nfs.gid` are effectively mandatory for cross-provider migrations (AUTH_SYS identity). With the S3 matrix (Slices 1–3) this delivered #236's backend-agnostic design. Proxmox now advertises **s3 and nfs** (not PVC).
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

*This document reflects VirtRigaud v0.4.1 capabilities. For the latest updates, see the [VirtRigaud documentation](https://projectbeskar.github.io/virtrigaud/).*
