<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Provider Capabilities Matrix

This document provides a comprehensive overview of VirtRigaud provider capabilities as of **v0.3.6**.

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
| **Clone Operations** | ✅ | ✅ | ✅ | ✅ | Full VM duplication with snapshot support |
| **Linked Clones** | ✅ | ✅[^2] | ✅ | ✅ | COW-based clones (Libvirt: via qcow2 backing files) |
| **Full Clones** | ✅ | ✅ | ✅ | ✅ | Independent copies |
| **VM Reconfiguration** | ✅ | ⚠️ Restart Required | ✅ | ✅ | Online resource modification |

[^2]: Libvirt advertises `SupportsLinkedClones=true` in `internal/providers/libvirt/server.go` GetCapabilities — the previous matrix incorrectly marked this `❌`; corrected in v0.3.6 docs alignment.

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
| **Cloud Image Download** | ⚠️[^4] | ✅ | ✅ | ✅ | Remote image fetch (vSphere: tracked but no URL-based fetch yet) |
| **Content Libraries** | ✅ | ❌ | ❌ | ✅ | Centralized image management |
| **Image Conversion** | ❌ | ✅ | ✅ | ✅ | Format transformation |
| **Image Caching** | ✅ | ✅ | ✅ | ✅ | Performance optimization |

[^4]: vSphere advertises `SupportsImageImport=true` (OVA/OVF + content library); direct cloud-image URL fetch is not yet implemented. Operators today should land cloud images in the content library out-of-band.

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
- **Web Console URLs**: Direct vSphere web client console access

### Libvirt/KVM Exclusive

- **Virsh + libssh Integration**: Command-line management over an SSH-tunnelled session
- **QEMU Guest Agent**: Advanced guest OS integration
- **KVM Optimization**: Native Linux virtualization
- **Bridge Networking**: Direct host network bridging
- **Storage Pool Flexibility**: Multiple storage backend support
- **Cloud Image Support**: Direct cloud image deployment
- **Host Device Passthrough**: Hardware device assignment
- **Reconfiguration Support**: CPU/memory/disk changes via virsh (restart required)
- **VNC Console Access**: Direct VNC console URL generation for remote viewers
- **Linked Clones via qcow2 backing**: COW-based clones with shared backing files

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

- **vSphere**: `ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.3.6`
- **Libvirt**: `ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.3.6`
- **Proxmox**: `ghcr.io/projectbeskar/virtrigaud/provider-proxmox:v0.3.6`
- **Mock**: `ghcr.io/projectbeskar/virtrigaud/provider-mock:v0.3.6`

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

- **v0.3.6**: Manager-side CircuitBreaker wired on all provider RPCs (G6); G7 metric families completed; H1 build-path consolidation. No new provider-side capabilities.
- **v0.3.5**: Observability G-track foundation — provider RPC metrics surface for every provider.
- **v0.3.3**: Changelog organisation with versioned release headers.
- **v0.2.3**: Provider feature parity — Reconfigure, Clone, TaskStatus, ConsoleURL
- **v0.2.2**: Nested virtualization, TPM support, comprehensive snapshot management
- **v0.2.1**: Critical fixes, documentation updates, VMClass disk settings
- **v0.2.0**: Production-ready vSphere and Libvirt providers
- **v0.1.0**: Initial provider framework and mock implementation

---

*This document reflects VirtRigaud v0.3.6 capabilities. For the latest updates, see the [VirtRigaud documentation](https://projectbeskar.github.io/virtrigaud/).*
