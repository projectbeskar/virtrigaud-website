<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Provider Capabilities Matrix

This document provides a comprehensive overview of VirtRigaud provider capabilities as of **v0.3.8**.

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
| **Libvirt/KVM** | Production Ready | virsh + libssh-based | Stable |
| **Proxmox VE** | Production Ready | REST API-based | Beta |
| **Mock** | Complete | In-memory simulation | Testing |

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
| **Reconfigure** | ✅ | ⚠️ | ✅ | ✅ | CPU/Memory/Disk changes (Libvirt requires restart) |
| **TaskStatus** | ✅ | N/A | ✅ | ✅ | Async operation tracking |
| **ConsoleURL** | ✅ | ✅ | ⚠️ | ✅ | Remote console access (Proxmox planned) |

### Resource Management

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **CPU Configuration** | ✅ | ✅ | ✅ | ✅ | Cores, sockets, threading |
| **Memory Allocation** | ✅ | ✅ | ✅ | ✅ | Static memory sizing |
| **Hot CPU Add** | ✅ | ❌ | ✅ | ✅ | Online CPU expansion |
| **Hot Memory Add** | ✅ | ❌ | ✅ | ✅ | Online memory expansion |
| **Resource Reservations** | ✅ | ❌ | ✅ | ✅ | Guaranteed resources |
| **Resource Limits** | ✅ | ❌ | ✅ | ✅ | Resource capping |

### Storage Operations

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Disk Creation** | ✅ | ✅ | ✅ | ✅ | Virtual disk provisioning |
| **Disk Expansion** | ✅ | ⚠️[^1] | ✅ | ✅ | Online disk growth |
| **Multiple Disks** | ✅ | ✅ | ✅ | ✅ | Multi-disk VMs |
| **Thin Provisioning** | ✅ | ✅ | ✅ | ✅ | Space-efficient disks |
| **Thick Provisioning** | ✅ | ✅ | ✅ | ✅ | Pre-allocated storage |
| **Storage Policies** | ✅ | ❌ | ✅ | ✅ | Policy-based placement |
| **Storage Pools** | ✅ | ✅ | ✅ | ✅ | Organized storage management |

[^1]: Libvirt advertises `SupportsDiskExpansionOnline=false` in its `GetCapabilities` response. Disk growth works but requires a VM power cycle.

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
| **Clone Operations** | ✅ | ❌[^2] | ✅ | ✅ | Full VM duplication (vSphere/Proxmox `Clone`; libvirt returns `Unimplemented`) |
| **Linked Clones** | ✅ | ❌[^2] | ✅ | ✅ | COW-based clones (libvirt reports `SupportsLinkedClones=false`) |
| **Full Clones** | ✅ | ❌[^2] | ✅ | ✅ | Independent copies (libvirt `Clone` is `Unimplemented`) |
| **VM Reconfiguration** | ✅ | ⚠️ Restart Required | ✅ | ✅ | Online resource modification |

[^2]: Libvirt's `Clone` RPC returns `Unimplemented` and `GetCapabilities` reports `SupportsLinkedClones=false` (`internal/providers/libvirt/server.go`, corrected by #153/#154 in v0.3.8). An earlier doc-alignment footnote claimed libvirt advertised `SupportsLinkedClones=true` and was "corrected in v0.3.6" — that claim is **reversed** as of v0.3.8: libvirt linked clones (and clones generally) are unsupported. The VMClone controller (MVP, #179) drives same-provider full/linked clones on the providers that implement `Clone` (vSphere, Proxmox).

### Snapshot Operations

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Create Snapshots** | ✅ | ✅ | ✅ | ✅ | Point-in-time captures |
| **Delete Snapshots** | ✅ | ✅ | ✅ | ✅ | Snapshot cleanup |
| **Revert Snapshots** | ✅ | ✅ | ✅ | ✅ | Restore VM state |
| **Memory Snapshots** | ❌[^3] | ❌ | ✅ | ✅ | Include RAM state |
| **Quiesced Snapshots** | ✅ | ❌ | ✅ | ✅ | Consistent filesystem |
| **Snapshot Trees** | ✅ | ✅ | ✅ | ✅ | Hierarchical snapshots |

[^3]: vSphere advertises `SupportsMemorySnapshots=false` in its `GetCapabilities` response — vSphere snapshots do not include memory state by default. The previous matrix incorrectly marked this `✅`; corrected in v0.3.6 docs alignment. Operators who need memory-state snapshots on vSphere must take them through vCenter directly today.

### Image Management

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **OVA/OVF Import** | ✅ | ❌ | ✅ | ✅ | Standard VM formats |
| **Image Import (URL)** | ⚠️[^4] | ❌[^6] | ✅ | ✅ | Remote image fetch; libvirt `ImagePrepare` returns `Unimplemented` (#153/#154); vSphere tracked but no URL-based fetch yet |
| **Content Libraries** | ✅ | ❌ | ❌ | ✅ | Centralized image management |
| **Image Conversion** | ❌ | ✅ | ✅ | ✅ | Format transformation |
| **Image Caching** | ✅ | ✅ | ✅ | ✅ | Performance optimization |

[^4]: vSphere advertises `SupportsImageImport=true` (OVA/OVF + content library); direct cloud-image URL fetch is not yet implemented. Operators today should land cloud images in the content library out-of-band.

[^6]: As of v0.3.8 (#153/#154), libvirt's `ImagePrepare` RPC returns `Unimplemented` and `GetCapabilities` reports `SupportsImageImport=false`. The earlier docs claimed libvirt fetched images from a URL into a storage pool volume; that path is not implemented. Operators must stage the base image on the libvirt host (or storage pool) out of band.

### Disk Export / Import

| Capability | vSphere | Libvirt | Proxmox | Mock | Notes |
|------------|---------|---------|---------|------|-------|
| **Disk Export** | ✅[^7] | ✅[^8] | ❌ | ✅ | `ExportDisk` / `GetDiskInfo`; vSphere also advertises export compression |
| **Disk Import** | ✅[^7] | ❌[^8] | ❌ | ✅ | `ImportDisk`; libvirt advertises export-only |
| **Export Formats** | `vmdk`, `qcow2`, `raw` | per `GetDiskInfo` | — | simulated | vSphere `GetCapabilities` advertises all three (#178) |

[^7]: As of v0.3.8 (#178), vSphere's `GetCapabilities` advertises disk **export and import** plus the `vmdk`, `qcow2`, and `raw` formats and export compression. Prior releases understated these flags (export/import reported as unsupported/zero); the cells above match the actual v0.3.8 response in `internal/providers/vsphere/server.go`.

[^8]: As of v0.3.8 (#177), libvirt implements `ExportDisk` / `GetDiskInfo` with accurate capability flags and formats, so disk **export** is supported. Disk **import** remains unsupported per libvirt's real capability flags. These cells feed the cross-provider migration pipeline (vSphere → libvirt export/convert/import).

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
- **Web Console URLs**: Direct vSphere web client console access

### Libvirt/KVM Exclusive

- **Virsh + libssh Integration**: Command-line management over an SSH-tunnelled session
- **QEMU Guest Agent**: Advanced guest OS integration
- **KVM Optimization**: Native Linux virtualization
- **Bridge Networking**: Direct host network bridging
- **Storage Pool Flexibility**: Multiple storage backend support
- **Host Device Passthrough**: Hardware device assignment
- **Reconfiguration Support**: CPU/memory/disk changes via virsh (restart required)
- **VNC Console Access**: Direct VNC console URL generation for remote viewers
- **Disk Export**: `ExportDisk` / `GetDiskInfo` (#177) — feeds cross-provider migration; import not supported

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

- **vSphere**: `ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.3.8`
- **Libvirt**: `ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.3.8`
- **Proxmox**: `ghcr.io/projectbeskar/virtrigaud/provider-proxmox:v0.3.8`

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
- Online disk expansion (currently requires power cycle)

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

- **v0.3.8**: Capability negotiation surfaced on `Provider.status.reportedCapabilities` + `CapabilitiesReported` condition, with opt-in `--enforce-provider-capabilities` (default off, fail-open) (#176); vSphere `GetCapabilities` now advertises disk export **and** import + `vmdk`/`qcow2`/`raw` formats + export compression (#178); libvirt implements `ExportDisk`/`GetDiskInfo` (#177); libvirt `Clone`/`ImagePrepare` corrected to `Unimplemented` with `SupportsLinkedClones=false` and `SupportsImageImport=false` (#153/#154); VMClone controller MVP (same-provider full/linked, vSphere+Proxmox) (#179); vSphere vCenter session keepalive + live-probe reconnect (#190); libvirt transient-SSH retry with bounded backoff (#191); Helm templated providers disabled by default (#173).
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

*This document reflects VirtRigaud v0.3.8 capabilities. For the latest updates, see the [VirtRigaud documentation](https://projectbeskar.github.io/virtrigaud/).*
