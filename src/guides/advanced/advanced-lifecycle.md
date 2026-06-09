<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Advanced VM Lifecycle Management

This document describes the advanced VM lifecycle features in VirtRigaud, including reconfiguration, snapshots, cloning, multi-VM sets, and placement policies.

## Overview

VirtRigaud Stage E introduces comprehensive VM lifecycle management capabilities that go beyond basic create/delete operations:

- **VM Reconfiguration**: Modify CPU, memory, and disk resources of running VMs
- **Snapshot Management**: Create, delete, and revert VM snapshots
- **VM Cloning**: Create new VMs from existing ones with linked clone support
- **Multi-VM Sets**: Manage groups of VMs with rolling updates
- **Placement Policies**: Advanced placement rules and anti-affinity constraints
- **Image Preparation**: Automated image import and preparation workflows
- **Lifecycle Hooks**: Run actions before power-off (`preStop`) or after power-on (`postStart`)

!!! warning "Feature status in v0.3.8 — read before designing around these"
    Not every resource on this page has an active controller yet. As of
    **v0.3.8**:

    - **VMClone** — MVP controller is active (`source.vmRef`-only,
      same-provider, Full/Linked clone). See the dedicated
      [VM Cloning guide](vm-cloning.md) for the authoritative scope.
    - **VMSet** — the controller is **not yet active**. The resource exists
      but reports `Ready=False` / `ControllerNotImplemented`. The
      rolling-update behavior described below is the intended design, **not**
      functional in v0.3.8.
    - **VMPlacementPolicy** — **reference-only** (no dedicated controller).
      You can attach a policy via `spec.placementRef`, but VirtRigaud does
      **not** enforce hard/soft placement or anti-affinity in v0.3.8.

    Reconfiguration, snapshots, image preparation, and lifecycle hooks are
    functional subject to provider support.

## Lifecycle Hooks

VirtRigaud supports running actions at key points in a VM's power-state transitions. Hooks execute synchronously as part of the power operation — the controller waits for them to complete before continuing.

### Supported Hooks

| Hook | When It Runs |
|------|-------------|
| `preStop` | Before the VM is powered off (after `OffGraceful` or `Off` is set) |
| `postStart` | After the VM has been powered on |

The graceful shutdown timeout is configured alongside hooks:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `gracefulShutdownTimeout` | Duration | `60s` | How long to wait for a graceful shutdown before forcing power-off |

### Action Types

Each hook (`preStop`, `postStart`) can use one of three action types:

#### `exec` — Run a Command

Executes a command inside the guest via the provider's guest-agent integration.

```yaml
lifecycle:
  postStart:
    exec:
      command: ["/usr/local/bin/register-vm.sh", "--env", "production"]
```

#### `httpGet` — HTTP Health/Notification Endpoint

Makes an HTTP GET request to an endpoint reachable from the controller.

```yaml
lifecycle:
  postStart:
    httpGet:
      scheme: HTTPS          # HTTP or HTTPS (default: HTTP)
      host: "monitoring.internal"
      port: 8443
      path: "/api/vm/registered"

  preStop:
    httpGet:
      host: "monitoring.internal"
      port: 8080
      path: "/api/vm/deregistered"
```

| Field | Type | Description |
|-------|------|-------------|
| `scheme` | string | `HTTP` or `HTTPS` |
| `host` | string | Hostname or IP to call |
| `port` | int | Port number |
| `path` | string | URL path |

#### `snapshot` — Create a Snapshot

Creates a VM snapshot at the hook point (most useful in `preStop`).

```yaml
lifecycle:
  preStop:
    snapshot:
      name: "pre-shutdown-backup"
      includeMemory: false
      description: "Automatic pre-shutdown snapshot"
```

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Snapshot name |
| `includeMemory` | bool | Include memory state in snapshot |
| `description` | string | Human-readable description |

### Full Example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: web-server
spec:
  providerRef:
    name: vsphere-prod
  classRef:
    name: standard-vm
  imageRef:
    name: ubuntu-22-04-template
  powerState: On

  lifecycle:
    gracefulShutdownTimeout: "120s"

    postStart:
      httpGet:
        host: "cmdb.internal"
        port: 8080
        path: "/api/vm/register"

    preStop:
      snapshot:
        name: "pre-shutdown"
        includeMemory: false
        description: "Automatic snapshot before shutdown"
```

### Best Practices

- **`preStop` snapshot**: Useful for stateful VMs where a pre-shutdown backup is always desirable.
- **`postStart` httpGet**: Good for notifying external systems (CMDB, monitoring) when a VM comes online.
- **`gracefulShutdownTimeout`**: Increase beyond 60 s for VMs with slow guest shutdown sequences.

---

## VM Reconfiguration

### Online vs Offline Reconfiguration

VirtRigaud supports both online (hot) and offline reconfiguration depending on provider capabilities:

**vSphere**: Supports online CPU/memory changes and hot disk expansion
**Libvirt**: Typically requires power cycle for resource changes

### Example: CPU/Memory Upgrade

```yaml
# Original VM with 2 CPU, 4GB RAM
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: web-server
spec:
  resources:
    cpu: 2
    memoryMiB: 4096

# Patch to upgrade resources
# kubectl patch vm web-server --type merge -p '{"spec":{"resources":{"cpu":4,"memoryMiB":8192}}}'
```

The controller will:
1. Detect resource changes in VM spec
2. Attempt online reconfiguration if supported
3. If offline required, orchestrate graceful power cycle:
   - Set condition `ReconfigurePendingPowerCycle=True`
   - Power off VM gracefully
   - Apply reconfiguration
   - Power on VM
   - Update `status.lastReconfigureTime`

### Disk Expansion

```yaml
spec:
  disks:
    - name: data
      sizeGiB: 100  # Expanded from 50GB
      expandPolicy: "Online"  # Try online first
```

## Snapshot Management

### Creating Snapshots

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMSnapshot
metadata:
  name: pre-maintenance-backup
spec:
  vmRef:
    name: web-server
  nameHint: "maintenance-backup"
  memory: true  # Include memory state
  description: "Backup before maintenance"
  retentionPolicy:
    maxAge: "7d"
    deleteOnVMDelete: true
```

### Snapshot Lifecycle

1. **Creating**: Snapshot creation in progress
2. **Ready**: Snapshot available for use
3. **Deleting**: Snapshot being removed
4. **Failed**: Snapshot operation failed

### Reverting to Snapshots

```yaml
# Patch VM to revert to snapshot
spec:
  snapshot:
    revertToRef:
      name: pre-maintenance-backup
```

The controller will:
1. Power off VM if running
2. Call provider's SnapshotRevert RPC
3. Power on VM
4. Clear `revertToRef` when complete

## VM Cloning

!!! tip "Dedicated guide"
    VMClone has its own focused guide:
    **[VM Cloning (VMClone)](vm-cloning.md)**. It covers the v0.3.8 MVP scope
    (vmRef-only source, same-provider, full vs linked clones), provider
    support (including libvirt `Clone` being unimplemented), what the
    controller produces, and cleanup semantics. The snippet below is the
    minimal shape; consult that guide before building around VMClone.

### Basic Cloning

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClone
metadata:
  name: web-server-clone
spec:
  source:
    vmRef:
      name: web-server          # an already-provisioned VirtualMachine
  target:
    name: web-server-test
    classRef:
      name: test-class
  options:
    type: FullClone             # or LinkedClone (requires provider support)
    powerOn: true
```

On success the controller produces an *adopted* target `VirtualMachine` CR
(labeled `virtrigaud.io/adopted=true`, with its `Status.ID` seeded from the
provider clone ID). Deleting the `VMClone` does **not** delete the produced
VM — see [VM Cloning](vm-cloning.md#lifecycle-and-cleanup-semantics).

!!! note "Clone customization is not applied by the MVP"
    The `spec.customization` block (hostname, per-network IPs, cloud-init
    overrides, etc.) exists on the CRD for forward compatibility but is
    **not** acted on by the v0.3.8 VMClone controller. The MVP inherits the
    source VM's shape. Track this limitation via the
    [VM Cloning guide](vm-cloning.md#scope-and-limits).

## Multi-VM Sets (VMSet)

!!! warning "VMSet controller is not active in v0.3.8"
    The VMSet resource exists, but its controller is a **not-yet-active
    stub**: a VMSet reports `Ready=False` with reason
    `ControllerNotImplemented`. Replica counts, rolling updates, and the
    `updateStrategy` below are the **intended design only** — VirtRigaud
    does **not** manage VMSet replicas in v0.3.8. Manage individual
    `VirtualMachine` resources (optionally via [VMClone](vm-cloning.md)) until
    the controller lands.

VMSets are intended to provide declarative management of multiple VMs with rolling updates.

### Basic VMSet

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMSet
metadata:
  name: web-tier
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-server
  template:
    metadata:
      labels:
        app: web-server
    spec:
      providerRef:
        name: vsphere-prod
      classRef:
        name: web-class
      imageRef:
        name: nginx-image
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
```

### Rolling Updates

!!! warning "Design intent, not yet implemented"
    The rolling-update flow below describes how VMSet is intended to behave
    once its controller is active. It does **not** run in v0.3.8 (see the
    VMSet warning above).

When you update the template spec, VMSet is intended to:
1. Create new VMs with updated configuration
2. Wait for new VMs to be ready
3. Delete old VMs respecting `maxUnavailable`
4. Continue until all replicas are updated

## Placement Policies

!!! warning "Reference-only in v0.3.8 — not enforced"
    `VMPlacementPolicy` has **no dedicated controller** in v0.3.8. You can
    create a policy and attach it via `spec.placementRef`, but VirtRigaud
    does **not** enforce hard/soft constraints or anti-affinity rules. The
    rules below document the schema and intended semantics, not active
    behavior.

### Advanced Placement Rules

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMPlacementPolicy
metadata:
  name: production-policy
spec:
  hard:
    clusters: ["prod-cluster-1", "prod-cluster-2"]
    datastores: ["ssd-datastore-1", "ssd-datastore-2"]
    hosts: ["esxi-01", "esxi-02", "esxi-03"]
  soft:
    folders: ["/Production/WebServers"]
    zones: ["zone-a", "zone-b"]
  antiAffinity:
    hostAntiAffinity: true      # Spread across hosts
    clusterAntiAffinity: false
    datastoreAntiAffinity: true # Spread across datastores
```

### Using Placement Policies

```yaml
spec:
  placementRef:
    name: production-policy
```

When a placement controller is implemented, the provider is intended to satisfy:
1. **Hard constraints**: Must be satisfied
2. **Soft constraints**: Best effort
3. **Anti-affinity rules**: Avoid co-location

In v0.3.8 the reference is accepted but the constraints are not enforced.

## Image Preparation

### Automated Image Import

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-22-04
spec:
  vsphere:
    ovaURL: "https://releases.ubuntu.com/22.04/ubuntu-22.04-server.ova"
    checksum: "sha256:abcd1234..."
  libvirt:
    url: "https://cloud-images.ubuntu.com/22.04/ubuntu-22.04-server.img"
    format: "qcow2"
  prepare:
    onMissing: "Import"  # Auto-import if missing
    validateChecksum: true
    timeout: "30m"
    retries: 3
    storage:
      vsphere:
        datastore: "images-datastore"
        folder: "/Templates"
        thinProvisioned: true
```

### Image Preparation Phases

1. **Pending**: Waiting to start preparation
2. **Importing**: Downloading/importing image
3. **Preparing**: Processing image (conversion, etc.)
4. **Ready**: Image ready for use
5. **Failed**: Preparation failed

## Provider Capabilities

Different providers support different features. As of **v0.3.8**
([#176](https://github.com/projectbeskar/virtrigaud/pull/176)) the manager
records what each provider reports under
`Provider.status.reportedCapabilities`:

```yaml
# Example reported capabilities (Provider status)
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
status:
  reportedCapabilities:
    supportsReconfigureOnline: true      # vSphere: true, Libvirt: false
    supportsDiskExpansionOnline: true    # vSphere: true, Libvirt: false
    supportsSnapshots: true              # Both: true
    supportsMemorySnapshots: true        # vSphere: true, Libvirt: varies
    supportsLinkedClones: true           # vSphere/Proxmox; Libvirt: no
    supportsImageImport: true            # vSphere/Proxmox; Libvirt: stub
    supportedDiskTypes: ["thin", "thick"]
    supportedNetworkTypes: ["VMXNET3", "E1000"]
```

An opt-in `--enforce-provider-capabilities` manager flag (default **off**)
makes the manager refuse operations a provider does not advertise. The
[VMClone](vm-cloning.md) linked-clone gate runs regardless of that flag.
For the authoritative per-provider matrix, see the
[Provider Capabilities Matrix](../../providers/providers-capabilities.md).

## Observability

### Metrics

New metrics for advanced lifecycle operations:

```
virtrigaud_vm_reconfigure_total{provider_type,outcome}
virtrigaud_vm_snapshot_total{action,provider_type,outcome}
virtrigaud_vm_clone_total{linked,provider_type,outcome}
virtrigaud_vm_image_prepare_total{provider_type,outcome}
```

### Events

Detailed events for lifecycle operations:

```
Normal   SnapshotCreating    Started snapshot creation
Normal   SnapshotReady       Snapshot created successfully
Normal   ReconfigureStarted  Started VM reconfiguration
Warning  ReconfigurePowerCycle  Reconfiguration requires power cycle
Normal   CloneCompleted      VM clone created successfully
```

### Conditions

Comprehensive condition reporting:

**VM Conditions**:
- `Ready`: VM is ready for use
- `Provisioning`: VM is being created
- `Reconfiguring`: VM is being reconfigured
- `ReconfigurePendingPowerCycle`: Needs power cycle for changes

**Snapshot Conditions**:
- `Ready`: Snapshot is ready
- `Creating`: Snapshot being created
- `Deleting`: Snapshot being deleted

**Clone Conditions**:
- `Ready`: Clone completed successfully
- `Cloning`: Clone operation in progress
- `Customizing`: Applying customizations

## Best Practices

### Snapshot Management

1. **Retention Policies**: Always set appropriate retention policies
2. **Memory Snapshots**: Use sparingly due to storage overhead
3. **Cleanup**: Implement automated cleanup for old snapshots
4. **Testing**: Test snapshot revert procedures regularly

### VM Reconfiguration

1. **Gradual Changes**: Make incremental resource changes
2. **Monitoring**: Monitor VM performance after changes
3. **Rollback Plan**: Have snapshots before major changes
4. **Capacity Planning**: Ensure host resources before scaling up

### Placement Policies

1. **Start Simple**: Begin with basic constraints
2. **Test Anti-Affinity**: Verify rules work as expected
3. **Monitor Placement**: Check actual VM placement matches policy
4. **Balance Performance**: Don't over-constrain placement

### Multi-VM Operations

1. **Rolling Updates**: Use appropriate `maxUnavailable` settings
2. **Health Checks**: Implement proper readiness checks
3. **Monitoring**: Monitor rollout progress
4. **Rollback Strategy**: Plan for rollback scenarios

## Troubleshooting

### Common Issues

**Reconfiguration Fails**:
- Check provider capabilities
- Verify resource availability on host
- Check for VM tools/agent issues

**Snapshot Operations Fail**:
- Verify storage backend supports snapshots
- Check available storage space
- Ensure VM is not in transitional state

**Clone Customization Issues**:
- Verify network configuration
- Check cloud-init/guest tools
- Validate IP address availability

**Placement Policy Violations**:
- Check resource availability in target locations
- Verify anti-affinity rules aren't too restrictive
- Review cluster resource distribution

### Debugging

```bash
# Check VM reconfiguration status
kubectl describe vm web-server

# Monitor snapshot progress
kubectl get vmsnapshots -w

# Check clone status
kubectl describe vmclone web-server-clone

# Review placement policy usage
kubectl describe vmplacementpolicy production-policy

# Check VMSet rollout
kubectl describe vmset web-tier
```

## Migration from Basic VMs

Existing VMs can be enhanced with advanced features:

1. **Enable Reconfiguration**: Add resource overrides
2. **Create Snapshots**: Deploy VMSnapshot resources
3. **Clone an existing VM**: Use [VMClone](vm-cloning.md) to stamp out a
   same-provider copy

The controller maintains backward compatibility with existing VM
definitions.

!!! note "Not yet available in v0.3.8"
    Two items that earlier docs listed here are not functional in v0.3.8:
    attaching a `placementRef` is accepted but **not enforced**
    (VMPlacementPolicy is reference-only), and **VMSet** has no active
    controller, so "scale with VMSets" is not yet a supported path. See the
    feature-status warning at the top of this page.
