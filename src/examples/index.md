<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VirtRigaud Examples

This directory contains examples for VirtRigaud v0.3.6. All YAML examples use the `infra.virtrigaud.io/v1beta1` API.

## Quick Start Examples

### Basic Examples
- **[complete-example.yaml](complete-example.yaml)** - Complete end-to-end example with Provider, VMClass, VMImage, and VirtualMachine
- **[vm-ubuntu-small.yaml](vm-ubuntu-small.yaml)** - Simple Ubuntu VM with graceful shutdown
- **[vmclass-small.yaml](vmclass-small.yaml)** - Basic VMClass definition

### Provider Examples
- **[provider-vsphere.yaml](provider-vsphere.yaml)** - vSphere provider configuration
- **[provider-libvirt.yaml](provider-libvirt.yaml)** - Libvirt provider configuration

### Resource Examples
- **[vmimage-ubuntu.yaml](vmimage-ubuntu.yaml)** - VM image configuration
- **[vmnetwork-app.yaml](vmnetwork-app.yaml)** - Network attachment configuration

## v0.2.1 Feature Examples

The following examples were added for v0.2.1 features and are still valid in v0.3.6:

- **[v021-feature-showcase.yaml](v021-feature-showcase.yaml)** - Graceful shutdown, lifecycle hooks, hardware version
- **[graceful-shutdown-examples.yaml](graceful-shutdown-examples.yaml)** - OffGraceful power state configurations
- **[vsphere-hardware-versions.yaml](vsphere-hardware-versions.yaml)** - Hardware version management
- **[disk-sizing-examples.yaml](disk-sizing-examples.yaml)** - Disk size configuration

### Advanced Provider Examples
- **[vsphere-advanced-example.yaml](vsphere-advanced-example.yaml)** - Advanced vSphere configuration
- **[libvirt-advanced-example.yaml](libvirt-advanced-example.yaml)** - Advanced Libvirt configuration
- **[proxmox-complete-example.yaml](proxmox-complete-example.yaml)** - Proxmox setup
- **[libvirt-complete-example.yaml](libvirt-complete-example.yaml)** - Complete Libvirt deployment
- **[multi-provider-example.yaml](multi-provider-example.yaml)** - Multiple providers in one cluster

## Migration Examples

!!! warning "Storage and migration direction constraints in v0.3.6"
    `storage.type: pvc` is the only accepted value in v0.3.6. S3, NFS, block, and live storage backends do not exist in the CRD and will be rejected by the controller. Additionally, only the vSphere → Libvirt migration direction is tested; other source/target pairs are documented but not validated in production. See [Migration User Guide](../migration/user-guide.md) for details.

- **[vmmigration-basic.yaml](vmmigration-basic.yaml)** - Basic vSphere → Libvirt migration
- **[vmmigration-advanced.yaml](vmmigration-advanced.yaml)** - Migration with storage and network mapping

## Advanced Examples

See the [advanced/](advanced/index.md) subdirectory for:

- **[advanced/vm-reconfigure-and-snapshot.yaml](advanced/vm-reconfigure-and-snapshot.yaml)** - VM reconfiguration with pre-reconfigure snapshot
- **[advanced/vsphere-clone-example.yaml](advanced/vsphere-clone-example.yaml)** - VMClone from an existing VM
- **[advanced/console-access-example.yaml](advanced/console-access-example.yaml)** - Console URL access
- **[advanced/snapshot-lifecycle.yaml](advanced/snapshot-lifecycle.yaml)** - Snapshot lifecycle management
- **[advanced/vsphere-task-tracking.yaml](advanced/vsphere-task-tracking.yaml)** - Async task tracking status

## Nested Virtualization

- **[nested-virtualization.yaml](nested-virtualization.yaml)** - VMClass with nested virtualization enabled

## Usage Patterns

### Apply an example

```bash
kubectl apply -f examples/provider-vsphere.yaml
kubectl apply -f examples/vmimage-ubuntu.yaml
kubectl apply -f examples/vm-ubuntu-small.yaml
```

### Watch VM status

```bash
kubectl get vm my-vm -w
```

### Get console URL

```bash
kubectl get vm my-vm -o jsonpath='{.status.consoleURL}'
```

### Trigger VM reconfiguration

```bash
kubectl patch virtualmachine my-vm --type='merge' \
  -p='{"spec":{"classRef":{"name":"medium"}}}'
```

## File Organization

```
src/examples/
├── index.md                           # This file
├── complete-example.yaml             # Complete setup
├── v021-feature-showcase.yaml        # v0.2.1 features
├── vm-ubuntu-small.yaml              # Simple VM
├── vmclass-small.yaml                # Basic VMClass
├── provider-vsphere.yaml             # vSphere provider
├── provider-libvirt.yaml             # Libvirt provider
├── vmimage-ubuntu.yaml               # VM image
├── vmnetwork-app.yaml                # Network attachment
├── graceful-shutdown-examples.yaml   # Graceful shutdown
├── vsphere-hardware-versions.yaml    # Hardware versions
├── disk-sizing-examples.yaml         # Disk sizing
├── vmmigration-basic.yaml            # Migration (tested)
├── vmmigration-advanced.yaml         # Migration with mapping
├── nested-virtualization.yaml        # Nested virt VMClass
├── advanced/                         # Complex scenarios
├── secrets/                          # Secret management
└── security/                         # Security configurations
```

## Version Compatibility

- **v0.3.6**: All examples in this directory
- **v0.3.x**: Examples are backward compatible within the v0.3.x line
- **v0.2.x and older**: Not supported

## See Also

- [Getting Started](../getting-started/index.md)
- [CLI Tools Reference](../references/cli-tools.md)
- [CRD Reference](../references/crds.md)
- [Upgrade Guide](../operations/upgrade.md)
