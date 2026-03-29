<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Custom Resource Definitions (CRDs)

This document describes all Custom Resource Definitions provided by VirtRigaud.

API group: `infra.virtrigaud.io` / Version: `v1beta1`

---

## VirtualMachine

The `VirtualMachine` CRD represents a virtual machine instance managed by a provider.

### Spec

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `providerRef` | `ObjectRef` | Yes | Reference to the Provider resource |
| `classRef` | `ObjectRef` | Yes | Reference to the VMClass resource |
| `imageRef` | `ObjectRef` | No\* | Reference to the VMImage resource |
| `importedDisk` | `ImportedDiskRef` | No\* | Pre-imported disk from migration/adoption |
| `networks` | `[]VMNetworkRef` | No | Network attachments (max 10) |
| `disks` | `[]DiskSpec` | No | Additional data disks (max 20) |
| `userData` | `UserData` | No | Cloud-init or Ignition configuration |
| `metaData` | `MetaData` | No | Cloud-init metadata |
| `placement` | `Placement` | No | Inline placement hints |
| `placementRef` | `LocalObjectReference` | No | Reference to a VMPlacementPolicy |
| `powerState` | `PowerState` | No | Desired power state: `On`, `Off`, `OffGraceful` |
| `resources` | `VirtualMachineResources` | No | Per-VM resource overrides (CPU, memory, GPU) |
| `tags` | `[]string` | No | Tags for organization (max 50) |
| `snapshot` | `VMSnapshotOperation` | No | Snapshot revert operation |
| `lifecycle` | `VirtualMachineLifecycle` | No | Lifecycle hooks |

\* `imageRef` and `importedDisk` are mutually exclusive. One is typically required to create a VM.

### Status

| Field | Type | Description |
|-------|------|-------------|
| `id` | `string` | Provider-specific VM identifier |
| `powerState` | `PowerState` | Current power state |
| `phase` | `VirtualMachinePhase` | Current phase: `Pending`, `Provisioning`, `Running`, `Stopped`, `Reconfiguring`, `Deleting`, `Failed` |
| `ips` | `[]string` | Assigned IP addresses |
| `consoleURL` | `string` | Console access URL |
| `conditions` | `[]Condition` | Status conditions |
| `observedGeneration` | `int64` | Last observed generation |
| `lastTaskRef` | `string` | Reference to last async task |
| `reconfigureTaskRef` | `string` | Reconfiguration task tracker |
| `lastReconfigureTime` | `Time` | When last reconfiguration occurred |
| `currentResources` | `VirtualMachineResources` | Currently applied resources |
| `snapshots` | `[]VMSnapshotInfo` | Available snapshots |
| `provider` | `map[string]string` | Provider-specific details |
| `message` | `string` | Additional state details |

### Example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: web-server
spec:
  providerRef:
    name: vsphere-prod
  classRef:
    name: small
  imageRef:
    name: ubuntu-22-template
  powerState: On
  placement:
    cluster: Compute-Cluster
    resourcePool: Production
    folder: /vm/web
    storagePod: DatastoreCluster-SSD   # auto-selects datastore with most free space
  networks:
    - name: app-net
      networkRef:
        name: app-network-attachment
  disks:
    - name: data
      sizeGiB: 100
      type: thin
  lifecycle:
    gracefulShutdownTimeout: "120s"
    preStop:
      snapshot:
        name: "pre-shutdown"
        includeMemory: false
```

---

## VMClass

The `VMClass` CRD defines resource allocation and hardware profile for virtual machines.

### Spec

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `cpu` | `int32` | Yes | — | Number of virtual CPUs (1–128) |
| `memory` | `resource.Quantity` | Yes | — | Memory allocation (e.g. `4Gi`, `8192Mi`) |
| `firmware` | `FirmwareType` | No | `BIOS` | `BIOS`, `UEFI`, or `EFI` |
| `diskDefaults` | `DiskDefaults` | No | — | Default disk settings for VMs using this class |
| `guestToolsPolicy` | `string` | No | `install` | `install`, `skip`, `upgrade`, `uninstall` |
| `resourceLimits` | `VMResourceLimits` | No | — | CPU/memory limits and reservations |
| `performanceProfile` | `PerformanceProfile` | No | — | CPU hot-add, NUMA, latency sensitivity |
| `securityProfile` | `SecurityProfile` | No | — | Secure boot, TPM, encryption |
| `extraConfig` | `map[string]string` | No | — | Provider-specific configuration (max 50 keys) |

### DiskDefaults

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `type` | `DiskType` | `thin` | `thin`, `thick`, `eagerzeroedthick`, `ssd`, `hdd`, `nvme` |
| `size` | `resource.Quantity` | `40Gi` | Default root disk size |
| `iops` | `int32` | — | Default IOPS limit (100–100000) |
| `storageClass` | `string` | — | Default storage class |

### Example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: small
spec:
  cpu: 2
  memory: "4Gi"
  firmware: UEFI
  diskDefaults:
    type: thin
    size: "40Gi"
  guestToolsPolicy: install
```

---

## VMImage

The `VMImage` CRD defines base templates or images for virtual machines.

### Spec

| Field | Type | Description |
|-------|------|-------------|
| `source` | `ImageSource` | Provider-specific image source (see below) |
| `prepare` | `ImagePrepare` | Image preparation options (`onMissing`, `validateChecksum`, `timeout`, `retries`) |
| `metadata` | `ImageMetadata` | Display name, description, version, architecture, tags |
| `distribution` | `DistributionInfo` | OS family, name, version, variant |

**ImageSource sub-fields** (provider-specific):

| Field | Description |
|-------|-------------|
| `vsphere` | `templateName`, `contentLibrary`, `ovaURL`, `checksum` |
| `libvirt` | `path`, `url`, `format` (default `qcow2`), `checksum`, `storagePool` |
| `proxmox` | `templateID`, `templateName`, `storage`, `node`, `format`, `fullClone` |
| `http` | `url`, `headers`, `checksum`, `authentication` |
| `registry` | `image`, `pullSecretRef`, `format` |

### Example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-22-template
spec:
  source:
    vsphere:
      templateName: "tmpl-ubuntu-22.04-cloudimg"
    libvirt:
      url: "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
      format: qcow2
```

---

## VMNetworkAttachment

The `VMNetworkAttachment` CRD defines provider-specific network configurations that VMs reference.

### Spec

| Field | Type | Description |
|-------|------|-------------|
| `network` | `NetworkConfig` | Underlying network config (provider-specific sub-fields) |
| `ipAllocation` | `IPAllocationConfig` | IP allocation: `DHCP`, `Static`, `Pool`, `None` |
| `security` | `NetworkSecurityConfig` | Firewall, isolation, encryption settings |
| `qos` | `NetworkQoSConfig` | Ingress/egress limits, priority, DSCP |
| `metadata` | `NetworkMetadata` | Display name, description, tags |

**Provider-specific `network` sub-fields:**

| Provider | Fields |
|----------|--------|
| `vsphere` | `portgroup`, `distributedSwitch`, `vlan` (type, vlanID, trunkVlanIDs), security, trafficShaping |
| `libvirt` | `networkName`, `bridge`, `model` (virtio/e1000/e1000e/rtl8139), `driver`, `filterRef` |
| `proxmox` | `bridge` (vmbr0–N), `model` (virtio/e1000/rtl8139/vmxnet3), `vlanTag`, `firewall`, `rateLimit`, `mtu` |

### Example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMNetworkAttachment
metadata:
  name: app-network
spec:
  network:
    vsphere:
      portgroup: "PG-App-VLAN100"
    proxmox:
      bridge: vmbr0
      vlanTag: 100
  ipAllocation:
    type: DHCP
```

VMs reference network attachments via `spec.networks[].networkRef`:

```yaml
spec:
  networks:
    - name: app-net
      networkRef:
        name: app-network
```

---

## Provider

The `Provider` CRD configures hypervisor connection details and the provider runtime.

### Spec

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | `ProviderType` | Yes | `vsphere`, `libvirt`, `proxmox`, `firecracker`, `qemu` |
| `endpoint` | `string` | Yes | Provider endpoint URI |
| `credentialSecretRef` | `ObjectRef` | Yes | Secret containing credentials |
| `insecureSkipVerify` | `bool` | No | Disable TLS verification (development only) |
| `defaults` | `ProviderDefaults` | No | Default placement settings |
| `rateLimit` | `RateLimit` | No | API rate limiting (qps, burst) |
| `runtime` | `ProviderRuntimeSpec` | Yes | How the provider is executed |
| `healthCheck` | `ProviderHealthCheck` | No | Health check configuration |
| `connectionPooling` | `ConnectionPooling` | No | Connection pool settings |

### ProviderDefaults

| Field | Type | Description |
|-------|------|-------------|
| `datastore` | `string` | Default datastore (mutually exclusive with `storagePod`) |
| `storagePod` | `string` | Default vSphere Datastore Cluster for auto-selection |
| `cluster` | `string` | Default compute cluster |
| `folder` | `string` | Default VM folder |
| `resourcePool` | `string` | Default resource pool |
| `network` | `string` | Default network |

### ProviderRuntimeSpec

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `mode` | `string` | `Remote` | Always `Remote` |
| `image` | `string` | — | Provider container image (required) |
| `imagePullPolicy` | `string` | `IfNotPresent` | `Always`, `Never`, `IfNotPresent` |
| `imagePullSecrets` | `[]LocalObjectReference` | — | Image pull secrets (max 10) |
| `replicas` | `int32` | `1` | Provider instances (1–10) |
| `service` | `ProviderServiceSpec` | — | gRPC service config (default port `9443`) |
| `resources` | `ResourceRequirements` | — | Pod resource requirements |
| `nodeSelector` | `map[string]string` | — | Node selector |
| `tolerations` | `[]Toleration` | — | Pod tolerations (max 20) |
| `logLevel` | `string` | `info` | `debug`, `info`, `warn`, `error` |
| `logFormat` | `string` | `text` | `text` or `json` |
| `env` | `[]EnvVar` | — | Additional environment variables (max 50) |

### Example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: vsphere-prod
spec:
  type: vsphere
  endpoint: https://vcenter.example.com/sdk
  credentialSecretRef:
    name: vsphere-creds
  defaults:
    cluster: Compute-Cluster
    storagePod: DatastoreCluster-SSD   # auto-selects datastore with most free space
  runtime:
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.3.3"
    service:
      port: 9443
```

---

## Common Types

### ObjectRef

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | `string` | Yes | Object name |
| `namespace` | `string` | No | Object namespace |

### Placement

Inline placement hints on a VirtualMachine. All fields are optional.

| Field | Type | Description |
|-------|------|-------------|
| `cluster` | `string` | Target compute cluster |
| `host` | `string` | Target host (pin to specific host) |
| `datastore` | `string` | Target datastore (mutually exclusive with `storagePod`) |
| `storagePod` | `string` | vSphere Datastore Cluster — auto-selects member with most free space |
| `folder` | `string` | VM folder path |
| `resourcePool` | `string` | Target resource pool |

### DiskSpec

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | `string` | Yes | — | Disk identifier (lowercase alphanumeric, max 63) |
| `sizeGiB` | `int32` | Yes | — | Disk size in GiB (1–65536) |
| `type` | `string` | No | `thin` | `thin`, `thick`, `eagerzeroedthick`, `ssd`, `hdd` |
| `expandPolicy` | `string` | No | `Offline` | `Online` or `Offline` |
| `storageClass` | `string` | No | — | Storage class override |
| `scsi` | `SCSIControllerSpec` | No | — | SCSI controller config (vSphere only) |

### VMNetworkRef

References a VMNetworkAttachment from a VirtualMachine.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | `string` | Yes | Name of this network attachment (max 63) |
| `networkRef` | `ObjectRef` | Yes | Reference to a VMNetworkAttachment resource |
| `ipAddress` | `string` | No | Optional static IP address |
| `macAddress` | `string` | No | Optional static MAC address |

### VirtualMachineLifecycle

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `preStop` | `LifecycleHandler` | — | Actions to run before the VM is powered off |
| `postStart` | `LifecycleHandler` | — | Actions to run after the VM is powered on |
| `gracefulShutdownTimeout` | `Duration` | `60s` | Time to wait for graceful shutdown |

### LifecycleHandler (action types — pick one)

| Field | Type | Description |
|-------|------|-------------|
| `exec` | `ExecAction` | Run a command: `command: []string` |
| `httpGet` | `HTTPGetAction` | HTTP GET: `host`, `port`, `path`, `scheme` (HTTP/HTTPS) |
| `snapshot` | `SnapshotAction` | Create snapshot: `name`, `includeMemory`, `description` |

### UserData

| Field | Type | Description |
|-------|------|-------------|
| `cloudInit` | `CloudInit` | Cloud-init config (`inline` string or `secretRef`) |
| `ignition` | `Ignition` | Ignition config (`inline` string or `secretRef`) |

### ImportedDiskRef

Used for adopted or migrated VMs instead of `imageRef`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `diskID` | `string` | — | Provider-specific disk identifier (required) |
| `path` | `string` | — | Optional disk path on provider |
| `format` | `string` | `qcow2` | `qcow2`, `vmdk`, `raw`, `vdi`, `vhdx` |
| `source` | `string` | — | Origin: `migration`, `clone`, `import`, `snapshot`, `manual` |
| `sizeGiB` | `int32` | — | Expected disk size |
| `migrationRef` | `LocalObjectReference` | — | VMMigration audit trail |
