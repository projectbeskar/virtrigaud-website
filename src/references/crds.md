<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Custom Resource Definitions (CRDs)

This document describes all Custom Resource Definitions provided by VirtRigaud.

API group: `infra.virtrigaud.io` / Version: `v1beta1`

VirtRigaud ships **12 CRDs** at v0.4.0. For the full auto-generated field reference, see [generated-crd-docs.md](generated-crd-docs.md).

**Controller status at v0.4.0:**

| CRD | Controller status |
|-----|-------------------|
| `VirtualMachine` | Active |
| `Provider` | Active |
| `VMClass` | Active |
| `VMImage` | Active |
| `VMNetworkAttachment` | Active |
| `VMMigration` | Active |
| `VMSnapshot` | Active |
| `VMClone` | Active (`source.vmRef` only, same-provider, full clones) |
| `VMSet` | Stub — `Ready=False / ControllerNotImplemented`; no replica management |
| `VMPlacementPolicy` | Reference-only — no standalone controller; consumed via `VirtualMachine.spec.placementRef` (and by the clustered libvirt scheduler) |
| `Host` | Active — inventory is synced from the clustered Provider (clustered libvirt only) |
| `HostPool` | Active — `status` counts member hosts (clustered libvirt only) |

`VMAdoption` is a **controller** (in `internal/controller/`), not a CRD.

## Schema changes since v0.3.11

Nothing was removed. Apply the CRDs before the manager (see [Helm CRD Upgrades](../getting-started/helm-crd-upgrades.md)); the manager reports not-ready while the `VirtualMachine`, `Provider`, `VMClass` or `VMImage` CRD lacks a field it needs.

| CRD | Change |
|-----|--------|
| `Host`, `HostPool` | New CRDs (clustered libvirt providers) |
| `Provider` | New `spec.topology` (`single` default, `cluster`), `spec.consumerNamespaceSelector`; `status.reportedCapabilities.supportsHonestReconfigure` and `supportsImageArtifactIdentity`; `spec.type` and `spec.topology` are immutable |
| `VMClass`, `VMImage` | New `spec.consumerNamespaceSelector`. `VMImage.status.providerStatus[]` gains `providerUID`, `sourceDigest`, `taskRef` |
| `VirtualMachine` | New `status.boundProvider`, `status.placement`, `status.snapshotRevert`; `status.powerState` also accepts `Suspended` and `Unknown`; `spec.providerRef` is immutable once the VM is bound |
| `VMMigration` | New `status.targetVMUID`, `targetVMClaim`, `sourceVMUID`, `storagePVCUID`, `storageInfo.importTarget`, `stagingDigest`, `stagingLayout` |
| `VMClone` | New `status.targetUID` |
| `VMSnapshot` | New `status.boundProvider`, `status.vmUID` |

---

## VirtualMachine

The `VirtualMachine` CRD represents a virtual machine instance managed by a provider.

Full schema: [generated-crd-docs.md#virtualmachine](generated-crd-docs.md#virtualmachine)

### Spec

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `providerRef` | `ObjectRef` | Yes | Reference to the Provider resource. **Immutable once the VM is bound** (`status.id` or `status.placement.pendingHost` is set); detach a VM with the annotation `virtrigaud.io/orphan-on-delete: "true"` instead of re-pointing it. A Provider in another namespace needs its `spec.consumerNamespaceSelector` to select this namespace |
| `classRef` | `ObjectRef` | Yes | Reference to the VMClass resource (same cross-namespace rule as `providerRef`) |
| `imageRef` | `ObjectRef` | No\* | Reference to the VMImage resource (same cross-namespace rule as `providerRef`) |
| `importedDisk` | `ImportedDiskRef` | No\* | Pre-imported disk from migration/adoption |
| `networks` | `[]VMNetworkRef` | No | Network attachments (max 10) |
| `disks` | `[]DiskSpec` | No | Additional data disks (max 20). Attached on vSphere only; on libvirt and Proxmox they are not attached and the VM shows `DisksApplied=False/NotSupportedByProvider` |
| `userData` | `UserData` | No | Cloud-init or Ignition configuration |
| `metaData` | `MetaData` | No | Cloud-init metadata |
| `placement` | `Placement` | No | Inline placement hints |
| `placementRef` | `LocalObjectReference` | No | Reference to a VMPlacementPolicy |
| `powerState` | `PowerState` | No | Desired power state: `On`, `Off`, `OffGraceful` |
| `resources` | `VirtualMachineResources` | No | Per-VM resource overrides (CPU, memory, GPU) |
| `tags` | `[]string` | No | Tags for organization (max 50) |
| `snapshot` | `VMSnapshotOperation` | No | `revertToRef`: name of a `Ready` `VMSnapshot` of this VM to revert to (see [Snapshot revert](#snapshot-revert)) |
| `lifecycle` | `VirtualMachineLifecycle` | No | Lifecycle hooks |

\* `imageRef` and `importedDisk` are mutually exclusive. One is typically required to create a VM.

### Status

| Field | Type | Description |
|-------|------|-------------|
| `id` | `string` | Provider-specific VM identifier |
| `powerState` | `PowerState` | Power state as the provider reports it: `On`, `Off`, `OffGraceful`, `Suspended`, `Unknown`. A `Suspended` or `Unknown` VM is not resized or powered on |
| `phase` | `VirtualMachinePhase` | `Pending`, `Provisioning`, `Running`, `Stopped`, `Reconfiguring`, `Deleting`, `Failed`. Set on every status write, so never empty. A VM held by a clustered restore guard is `Pending`, not `Failed` |
| `ips` | `[]string` | Reachable addresses only: loopback, unspecified, link-local, multicast and non-IP entries are dropped and the rest are written in canonical form |
| `consoleURL` | `string` | Console access URL |
| `conditions` | `[]Condition` | Status conditions (see below) |
| `observedGeneration` | `int64` | Last observed generation |
| `boundProvider` | `BoundProviderRef` | The Provider object (`name`, `namespace`, `uid`) the VM is bound through. Written only by the operator |
| `placement` | `VMPlacementStatus` | Clustered Providers only: `host`, `pool`, `pendingHost`, `pendingResources`, `memoryCeilingMiB`, `excludedHosts`, `lastScheduledTime`, `reason` |
| `snapshotRevert` | `SnapshotRevertStatus` | State of a `spec.snapshot.revertToRef` request: `snapshotName`, `snapshotUID`, `phase` (`Pending`, `Reverting`, `Succeeded`, `Failed`), `attempts`, `taskRef`, `message` and timestamps |
| `lastTaskRef` | `string` | Reference to last async task |
| `reconfigureTaskRef` | `string` | Reconfiguration task tracker |
| `lastReconfigureTime` | `Time` | When last reconfiguration occurred |
| `currentResources` | `VirtualMachineResources` | Currently applied resources |
| `snapshots` | `[]VMSnapshotInfo` | Available snapshots |
| `provider` | `map[string]string` | Provider-specific details |
| `message` | `string` | Additional state details |

**Conditions.** `Ready` summarizes the VM and carries the reason for a hold. Others:

| Condition | Meaning |
|-----------|---------|
| `Provisioning` | The create, or why it waits (`WaitingForDependencies`, `Unschedulable`, ...) |
| `Reconfiguring` | A resize in flight. `True/RestartRequired` means the change is saved in the persistent definition and applies at the next power cycle (power off, then on; a reboot inside the guest does not apply it). `False/ResizePendingPowerOff`, `ShrinkPendingPowerOff` and `InsufficientHostCapacity` say why a resize waits |
| `SnapshotReverted` | A `revertToRef` request: `False/WaitingForPowerOff`, `SnapshotNotFound`, `SnapshotNotReady`, `SnapshotForAnotherVM`, `Unsupported`, `Reverting`, `RevertFailed`; `True/Reverted` |
| `Placed` | Clustered Providers: `True` when the VM has a host; `False` with `Unschedulable`, `RestorePending`, `OwnDomainOnAnotherHost`, `UniquenessCheckFailed`, `ProviderLacksListOwnerFilter`, ... |
| `DeleteBlocked` | Clustered VMs: a delete is held for `HostUnreachable`, `DiskCheckFailed`, `DiskInUse` (a linked clone depends on the disk), `OwnDomainOnAnotherHost` or `ProviderUnavailable`; `Ready` is `False/DeleteBlocked` meanwhile and the delete is retried with a 15 s to 5 min backoff. `virtrigaud.io/force-delete` and `orphan-on-delete` release it. A refused `VMSnapshot` delete shows the same reason on the `VMSnapshot` |
| `DisksApplied` | `False/NotSupportedByProvider` when `spec.disks` is set on a libvirt or Proxmox Provider. Never `True`; does not change `Ready` |
| `DiskSizeWithinLimit` | `False/DiskSizeExceedsLimit` when a resize withheld a disk growth because of `manager.maxDiskSize` |
| `LinkedClonesDependOnDisk` | Warning: libvirt linked clones made by an earlier release use this VM's disk as backing file |

Reasons that mean a hold needing an operator (phase `Failed`): `ConsumerNotAllowed`, `VMNotOwned`, `OwnerStampUnreadable`, `ProviderUnavailable`, `VMIsImageArtifact`, `CreateOutcomeUnknown`, `DeleteBlocked`, `ProviderRefMismatch`, `PlacementTopologyMismatch`, `VMMissingOnHost`. See [`vm-status-phase.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-status-phase.md) for the rule.

**Annotations you set on a `VirtualMachine`:**

| Annotation | Effect |
|------------|--------|
| `virtrigaud.io/orphan-on-delete: "true"` | Deleting the `VirtualMachine` releases it without deleting the VM on the hypervisor |
| `virtrigaud.io/force-delete: "true"` | Releases a held delete at once (a consumer in another namespace of a clustered Provider needs the Provider's `infra.virtrigaud.io/allow-consumer-orphan-on-delete: "true"`) |
| `virtrigaud.io/create-outcome` | Confirms the outcome of a create whose result was lost (`CreateOutcomeUnknown`) |

Other `virtrigaud.io/*` annotations and the `virtrigaud.io/adopted` label (migration, clone and adoption provenance) are written only by the manager; on Kubernetes 1.30+ a `ValidatingAdmissionPolicy` rejects other writers.

!!! note "Double-create guard (v0.3.8)"
    The VM controller skips the provider `Create` RPC for any VirtualMachine that carries the label `virtrigaud.io/adopted=true` **and** has an empty `Status.ID`. This guard prevents a duplicate create for VMs produced by VMClone or the VMAdoption controller, which seed `Status.ID` at bind time.

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
  powerState: "On"
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

### Snapshot revert

`spec.snapshot.revertToRef` names a `VMSnapshot` (same namespace) to revert the VM to. The snapshot must be `Ready` and taken of this VM. **A revert discards what was written to the VM's disks since the snapshot.** The revert is sent only while the provider reports the VM `Off` and `spec.powerState` is `Off` or `OffGraceful`; VirtRigaud never powers a VM off for a revert and does not power it on afterwards. It is sent at most once per request; to revert to the same snapshot again, remove the field, wait for `status.snapshotRevert` to disappear, and set it again. In v0.4.0-rc5 and earlier the field was accepted and ignored.

```bash
kubectl patch vm web-server --type merge -p '{"spec":{"powerState":"Off"}}'
kubectl patch vm web-server --type merge \
  -p '{"spec":{"snapshot":{"revertToRef":{"name":"web-server-snap-pre-upgrade"}}}}'
kubectl get vm web-server -o jsonpath='{.status.snapshotRevert.phase}'
```

While `SnapshotReverted` is `False`, `Ready` is `False` with the same reason. Per-provider behaviour is in the [capability matrix](../providers/providers-capabilities.md#snapshots-and-revert). Details: [`vm-snapshot-revert.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-snapshot-revert.md).

---

## VMClass

The `VMClass` CRD defines resource allocation and hardware profile for virtual machines.

Full schema: [generated-crd-docs.md#vmclass](generated-crd-docs.md#vmclass)

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
| `consumerNamespaceSelector` | `LabelSelector` | No | unset | Namespaces, other than this one, whose VirtualMachines may use this class. Unset: own namespace only; `{}`: every namespace |

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

Full schema: [generated-crd-docs.md#vmimage](generated-crd-docs.md#vmimage)

### Spec

| Field | Type | Description |
|-------|------|-------------|
| `source` | `ImageSource` | Provider-specific image source (see below) |
| `prepare` | `ImagePrepare` | Image preparation options (`onMissing`, `validateChecksum`, `timeout`, `retries`) |
| `metadata` | `ImageMetadata` | Display name, description, version, architecture, tags |
| `distribution` | `DistributionInfo` | OS family, name, version, variant |
| `consumerNamespaceSelector` | `LabelSelector` | Namespaces, other than this one, whose VirtualMachines may use this image. Unset: own namespace only; `{}`: every namespace |

**ImageSource sub-fields** (provider-specific):

| Field | Description |
|-------|-------------|
| `vsphere` | `templateName`, `contentLibrary`, `ovaURL`, `checksum` |
| `libvirt` | `path`, `url`, `format` (default `qcow2`), `checksum`, `storagePool` |
| `proxmox` | `templateID`, `templateName`, `storage`, `node`, `format`, `fullClone` |
| `http` | `url`, `headers`, `checksum`, `authentication` |
| `registry` | `image`, `pullSecretRef`, `format` |
| `dataVolume` | DataVolume-based image configuration |

- **Prepare state is per Provider.** `status.providerStatus["<namespace>/<name>"]` records, for each Provider that prepared the image, its `providerUID`, `sourceDigest` and prepare `taskRef`; `status.availableOn` lists the same keys. A VM uses only the entry of its own Provider.
- **libvirt `path`** must name a regular file directly inside an allowed image directory (default `/var/lib/libvirt/images`, set `VIRTRIGAUD_LIBVIRT_IMAGE_DIRS` through `Provider.spec.runtime.env` to change it); the provider always copies it, never attaches it in place.
- **Proxmox** imports from a template (`templateID` or `templateName`); URL import through `source.http` is refused.
- **vSphere** `templateName` must name a real template, not a regular VM.

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

Full schema: [generated-crd-docs.md#vmnetworkattachment](generated-crd-docs.md#vmnetworkattachment)

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

Full schema: [generated-crd-docs.md#provider](generated-crd-docs.md#provider)

### Spec

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | `ProviderType` | Yes | `vsphere`, `libvirt`, `proxmox`, `firecracker`, `qemu`. **Immutable** once set (only `vsphere`, `libvirt` and `proxmox` have a provider implementation) |
| `endpoint` | `string` | Yes | Provider endpoint URI |
| `credentialSecretRef` | `ObjectRef` | Yes | Secret containing credentials |
| `insecureSkipVerify` | `bool` | No | Disable TLS verification (development only) |
| `defaults` | `ProviderDefaults` | No | Default placement settings |
| `rateLimit` | `RateLimit` | No | API rate limiting (qps, burst) |
| `runtime` | `ProviderRuntimeSpec` | Yes | How the provider is executed |
| `healthCheck` | `ProviderHealthCheck` | No | Health check configuration |
| `connectionPooling` | `ConnectionPooling` | No | Connection pool settings |
| `topology` | `string` | No | `single` (default): one provider process bound to one host. `cluster`: the provider fronts several hosts registered as `Host` resources in a `HostPool`; accepted only on `type: libvirt`, experimental. **Immutable** |
| `consumerNamespaceSelector` | `LabelSelector` | No | Namespaces, other than this one, whose VMs, `VMClone`s, `VMMigration`s and `VMSnapshot`s may use this Provider. Unset: own namespace only; `{}`: every namespace. Sharing a Provider shares everything its credentials can reach |

### ProviderDefaults

| Field | Type | Description |
|-------|------|-------------|
| `datastore` | `string` | Default datastore (mutually exclusive with `storagePod`) |
| `storagePod` | `string` | Default vSphere Datastore Cluster for auto-selection |
| `cluster` | `string` | Default compute cluster |
| `folder` | `string` | Default VM folder |
| `resourcePool` | `string` | Default resource pool |
| `network` | `string` | Default network |

### Status

| Field | Type | Description |
|-------|------|-------------|
| `conditions` | `[]Condition` | Status conditions, including `CapabilitiesReported` (added v0.3.8) |
| `reportedCapabilities` | `ReportedCapabilities` | Provider's self-reported capability set, fetched from `GetCapabilities` RPC (added v0.3.8) |
| `capabilities` | `[]ProviderCapability` | Legacy capability list |
| `healthy` | `bool` | Health-check result |
| `runtime` | `ProviderRuntimeStatus` | Provider pod state: `phase` (`Pending`, `Starting`, `Running`, `Stopping`, `Failed`), `endpoint`, `readyReplicas`, `availableReplicas`, `serviceRef`, `message` |
| `adoption` | `ProviderAdoptionStatus` | Counts for `virtrigaud.io/adopt-vms`: `discoveredVMs`, `adoptedVMs`, `failedAdoptions`, `lastDiscoveryTime`, `message` |
| `version` | `string` | Provider binary version |
| `connectedVMs` | `int32` | VMs currently managed by this provider |
| `observedGeneration` | `int64` | Last observed generation |

#### ReportedCapabilities

The manager calls the provider's `GetCapabilities` RPC after each successful connect and writes the result into `status.reportedCapabilities`. A `CapabilitiesReported` condition is also set (`True` on success, `False` with reason `Unavailable` if the RPC fails or the provider is unreachable).

| Field | Type | Description |
|-------|------|-------------|
| `supportsReconfigureOnline` | `bool` | Online CPU/memory reconfigure |
| `supportsDiskExpansionOnline` | `bool` | Online disk expansion |
| `supportsSnapshots` | `bool` | VM snapshot support |
| `supportsMemorySnapshots` | `bool` | Memory-inclusive snapshots |
| `supportsLinkedClones` | `bool` | Linked (copy-on-write) clone support |
| `supportsImageImport` | `bool` | Image import/preparation |
| `supportedDiskTypes` | `[]string` | Supported disk formats |
| `supportedNetworkTypes` | `[]string` | Supported NIC models |
| `supportsDiskExport` | `bool` | Disk export (migration source) |
| `supportsDiskImport` | `bool` | Disk import (migration target) |
| `supportedExportFormats` | `[]string` | Supported export formats |
| `supportedImportFormats` | `[]string` | Supported import formats |
| `supportsExportCompression` | `bool` | Compression during export |
| `supportedExportBackends` | `[]string` | Staging backends for export: `pvc`, `nfs`, `s3` |
| `supportedImportBackends` | `[]string` | Staging backends for import: `pvc`, `nfs`, `s3` |
| `supportedTransferModes` | `[]string` | `relay`, `direct` |
| `supportsImageArtifactIdentity` | `bool` | `ImagePrepare` implements the prepared-image identity contract (ADR-0009). A provider that imports images without it is held: creates that need a prepare wait (`ProviderLacksArtifactIdentity`) |
| `supportsHonestReconfigure` | `bool` | `Reconfigure` never reports success for a change it did not apply. A clustered Provider without it has its resizes held (`ProviderLacksHonestReconfigure`) |

Clustering and routing flags (`supports_clustering`, `supports_routed_clone`, `supports_routed_adoption`, `supports_list_owner_filter`, `supports_routed_import`, ...) are part of the gRPC `GetCapabilities` answer and are read at runtime; they are not copied into the CRD status. See [Provider gRPC API](grpc-api.md).

Full schema: [generated-crd-docs.md#provider](generated-crd-docs.md#provider)

### ProviderRuntimeSpec

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `mode` | `string` | `Remote` | Always `Remote` |
| `image` | `string` | — | Provider container image (required) |
| `imagePullPolicy` | `string` | `IfNotPresent` | `Always`, `Never`, `IfNotPresent` |
| `imagePullSecrets` | `[]LocalObjectReference` | — | Image pull secrets (max 10) |
| `replicas` | `int32` | `1` | Provider instances (1–10). A clustered Provider (`topology: cluster`) and a vSphere Provider always run one replica with the `Recreate` strategy (a rollout is a short outage); a larger value is ignored |
| `service` | `ProviderServiceSpec` | — | gRPC service config: `port` (default `9443`, 1024-65535) and the required `tls` block (`enabled`, `secretRef`, `insecureSkipVerify`) |
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
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.0"
    service:
      port: 9443
      tls:
        enabled: true
        secretRef:
          name: provider-vsphere-tls   # Secret with tls.crt, tls.key, ca.crt
```

A `spec.runtime.service.tls` block is required (`TLSConfigured=False/TLSBlockMissing` without it).

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
| `networkRef` | `ObjectRef` | No | Reference to a VMNetworkAttachment. Without it, vSphere and Proxmox use the template's network adapter; a libvirt VM gets a user-mode interface |
| `ipAddress` | `string` | No | Optional static IPv4 address (needs `prefix` on Proxmox) |
| `prefix` | `int32` | No | Network prefix length (1-32) |
| `gateway` | `string` | No | Default gateway (IPv4) |
| `dns` | `string` | No | DNS servers, comma-separated IPs |
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

---

## Host

!!! note "Clustered libvirt only"
    `Host` and `HostPool` are used only by a libvirt Provider with `spec.topology: cluster` (experimental, opt-in). Single-host Providers do not use them. See [ADR-0007](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/adr/0007-clustered-orchestrator-provider.md) and [`clustered-provider-inventory.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/clustered-provider-inventory.md).

A `Host` registers one hypervisor host behind a clustered Provider. The operator fills `status` from the provider's `ListHosts`/`GetHostInfo` answers. A `Host` and its `HostPool` and Provider must be in the same namespace. A `Host` cannot be deleted while a VirtualMachine is bound to it; fence the host (power it off or revoke its access to shared storage) before you delete one to release held deletes.

Full schema: [generated-crd-docs.md#host](generated-crd-docs.md#host). Short name: `hvh`.

### Spec

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `providerRef` | `LocalObjectReference` | Yes | The clustered Provider that fronts this host |
| `poolRef` | `LocalObjectReference` | Yes | The `HostPool` this host belongs to |
| `endpoint` | `string` | Yes | `qemu+ssh://[user@]host[:port]/system` (or `/session`), or `grpc://host:port` |
| `credentialSecretRef` | `LocalObjectReference` | No | Secret with this host's SSH credentials; defaults to the Provider's |
| `labels` | `map[string]string` | No | Scheduling labels (storage pool and network visibility, rack, zone) |
| `schedulable` | `bool` | No | Default `true`. `false` cordons the host: nothing new is scheduled on it |

### Status

| Field | Type | Description |
|-------|------|-------------|
| `health` | `string` | `Ready`, `NotReady`, `Unknown` |
| `allocatableCPU` | `int32` | Allocatable vCPUs |
| `allocatableMemoryMiB` | `int64` | Allocatable memory in MiB |
| `allocatableStorageBytes` | `int64` | Free space of the host's `default` storage pool, measured fresh |
| `boundVMs` | `int32` | VirtualMachines bound to this host |
| `cpuModel`, `cpuFeatures`, `machineTypes`, `emulatorVersion` | | Facts reported by the host |
| `lastHeartbeatTime`, `conditions`, `observedGeneration` | | Inventory sync state |

### Example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Host
metadata:
  name: host-a
  namespace: virtrigaud-system
spec:
  providerRef:
    name: libvirt-cluster
  poolRef:
    name: pool-a
  endpoint: qemu+ssh://virtrigaud@host-a.example.com/system
  labels:
    net.virtrigaud.io/default: "true"
  schedulable: true
```

---

## HostPool

A `HostPool` groups the `Host`s of one clustered Provider and carries the scheduling policy. The scheduler picks a host from the pool's schedulable members, subtracts what each host already holds (every VM bound, pending or being deleted on it, in any namespace) and applies the VM's `VMPlacementPolicy`. A VM no host can take shows `Placed=False/Unschedulable` and is retried with a backoff of up to 2 minutes.

Full schema: [generated-crd-docs.md#hostpool](generated-crd-docs.md#hostpool). Short name: `hp`.

### Spec

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `providerRef` | `LocalObjectReference` | Yes | The clustered Provider that owns the pool (same namespace) |
| `strategy` | `string` | No | `Spread` (default) or `BinPack` |
| `overcommit` | `OvercommitSpec` | No | `cpu` and `memory` ratios as decimal strings (for example `"4.0"`) |
| `storagePools` | `[]` | No | Named storage pools available in the pool (`name`) |
| `networks` | `[]` | No | Named networks available in the pool (`name`) |
| `migration` | `MigrationPolicy` | No | Default migration policy: `defaultLive`, `defaultStorageMode`, `requireTLS`, `bandwidthMbps`, `maxDowntimeMs`. Host-to-host migration is not implemented in v0.4.0 |

### Status

| Field | Description |
|-------|-------------|
| `totalHosts` | Every member `Host` |
| `readyHosts` | Member hosts whose `status.health` is `Ready` |
| `schedulableHosts` | Member hosts the scheduler can place a VM on (Ready, `schedulable: true`, not being deleted, fronted by the pool's Provider) |
| `conditions` | `Ready`: `True/HostsAvailable`, `False/NoMemberHosts`, `False/NoSchedulableHosts` |

`kubectl get hostpools` shows the counts.

### Example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: HostPool
metadata:
  name: pool-a
  namespace: virtrigaud-system
spec:
  providerRef:
    name: libvirt-cluster
  strategy: Spread
  overcommit:
    cpu: "4.0"
    memory: "1.0"
```

A clustered Provider is an ordinary `Provider` with `spec.topology: cluster`, `type: libvirt` and, as its `endpoint`, a placeholder (hosts come from the `Host` resources). See `examples/provider-libvirt-clustered.yaml` and `examples/hostpool-clustered.yaml` in the main repository.

---

## VMMigration

The `VMMigration` CRD migrates a virtual machine's disk from one provider to another (snapshot, export to staging storage, import, create the target VM). Disks are staged through **S3** or **NFS** (`pvc` is kept for compatibility). The S3 and NFS paths are validated across vSphere, libvirt and Proxmox VE in both directions; a clustered libvirt Provider is also a valid target (experimental). Other combinations are unverified. See the [Migration API reference](../migration/api-reference.md) for every field.

Full schema: [generated-crd-docs.md#vmmigration](generated-crd-docs.md#vmmigration)

### Spec summary

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `source.vmRef` | `LocalObjectReference` | Yes | Source VirtualMachine (same namespace) |
| `source.providerRef` | `ObjectRef` | No | Source Provider override |
| `source.createSnapshot`, `powerOffBeforeMigration`, `deleteAfterMigration` | `bool` | No | Defaults `true`, `false`, `false` |
| `target.name` | `string` | Yes | Name of the VirtualMachine the migration creates |
| `target.providerRef` | `ObjectRef` | Yes | Destination Provider |
| `target.classRef` / `imageRef` / `networks` / `disks` / `placementRef` | | No | Target VM configuration |
| `target.namespace` | `string` | No | Another namespace needs a grant on that namespace (`infra.virtrigaud.io/allowed-source-namespaces`); a Proxmox target must stay in the migration's namespace |
| `target.powerOn` | `bool` | No | Default `false`: the migrated VM stays powered off unless `true` |
| `storage.type` | `string` | Yes | `s3`, `nfs`, `pvc` |
| `storage.transferMode` | `string` | No | `auto`, `relay`, `direct` (`direct` is rejected; `auto` resolves to `relay`) |
| `storage.s3` / `nfs` / `pvc` | | | Backend settings; NFS needs `uid` and `gid` for cross-provider migrations |
| `options` | `MigrationOptions` | No | `diskFormat`, `compress`, `verifyChecksums`, `timeout` (default `4h`), `cleanupPolicy`, `retryPolicy`, `validationChecks` |

The migration creates its target VM and acts only on that VM (`status.targetVMUID`, `status.targetVMClaim`); a same-named VM it did not create fails the migration with `TargetVMNotOwned`. A call whose outcome is unknown (`SnapshotCreate`, `ExportDisk`, `ImportDisk`) holds the migration (`Ready=False/SnapshotOutcomeUnknown`, `ExportOutcomeUnknown` or `ImportOutcomeUnknown`) for an operator instead of being re-sent blindly.

### Example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMMigration
metadata:
  name: web-server-migration
  namespace: default
spec:
  source:
    vmRef:
      name: web-server
  target:
    name: web-server-migrated
    providerRef:
      name: libvirt-dev
    classRef:
      name: small
  storage:
    type: nfs
    nfs:
      server: nfs.example.com
      export: /export/virtrigaud
      uid: 1000
      gid: 1000
  options:
    verifyChecksums: true
```

---

## VMSnapshot

The `VMSnapshot` CRD represents a point-in-time snapshot of a VirtualMachine. Creating a `VMSnapshot` triggers the provider's snapshot RPC. A `VMSnapshot` is `Ready` only after the provider confirmed a snapshot. To revert a VM to one, see [Snapshot revert](#snapshot-revert). Memory snapshots are supported by all three providers; see the [capability matrix](../providers/providers-capabilities.md#snapshots-and-revert).

Full schema: [generated-crd-docs.md#vmsnapshot](generated-crd-docs.md#vmsnapshot)

### Spec summary

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `vmRef` | `LocalObjectReference` | Yes | Target VirtualMachine (same namespace) |
| `snapshotConfig.name` | `string` | No | Name hint (the provider may modify it) |
| `snapshotConfig.description` | `string` | No | Human-readable description (max 1024) |
| `snapshotConfig.includeMemory` | `bool` | No | Capture memory state (default `false`) |
| `snapshotConfig.quiesce` | `bool` | No | Quiesce the file system (default `true`) |
| `retentionPolicy` | `SnapshotRetentionPolicy` | No | `maxAge`, `maxCount`, `deleteOnVMDelete` (default `true`), `preservePinned`, `gracePeriod` |
| `schedule` | `SnapshotSchedule` | No | Cron schedule fields (`enabled`, `cronSpec`, ...) |
| `metadata` | `SnapshotMetadata` | No | Labels such as `purpose`, `environment`, `pinned` |

### Status

`phase` is `Pending`, `Creating`, `Ready`, `Deleting`, `Failed` or `Expired`. `status.snapshotID` is the provider's snapshot id, `status.vmUID` the UID of the VM it was taken of, and `status.boundProvider` the Provider it was taken through. A `VMSnapshot` whose provider delete fails keeps its finalizer and is retried (`Ready=False/DeleteBlocked` when the provider refuses); the annotation `virtrigaud.io/force-delete` drops it.

### Example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMSnapshot
metadata:
  name: web-server-snap-pre-upgrade
spec:
  vmRef:
    name: web-server
  snapshotConfig:
    name: pre-upgrade
    description: "Before OS upgrade"
    includeMemory: false
```

---

## VMSet

!!! warning "Not functional in v0.4.0"
    The `VMSet` CRD is defined and accepted by the API server, but the controller is a stub. Every VMSet resource receives a `Ready=False` condition with reason `ControllerNotImplemented` and message `"VMSet has no active controller in this release (#179)"`. No replica management, scaling, or VM creation occurs. Do not use VMSet in production.

The `VMSet` CRD is intended to manage a fleet of identically-configured VirtualMachines (analogous to a ReplicaSet for VMs). The controller has not yet been implemented.

Full schema: [generated-crd-docs.md#vmset](generated-crd-docs.md#vmset)

### Spec summary

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `replicas` | `int32` | No | Desired instance count, default `1` (not yet acted on) |
| `selector` | `LabelSelector` | Yes | Matches VMs managed by this set |
| `template` | `VMSetTemplate` | Yes | VirtualMachine spec template (`spec`) |
| `updateStrategy` | `VMSetUpdateStrategy` | No | Rollout strategy |

### Example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMSet
metadata:
  name: web-workers
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-worker
  template:
    spec:
      providerRef:
        name: vsphere-prod
      classRef:
        name: small
      imageRef:
        name: ubuntu-22-template
      powerState: "On"
```

---

## VMPlacementPolicy

!!! note "Reference-only object"
    `VMPlacementPolicy` has no standalone controller. It is a data-carrier read when a VM sets `spec.placementRef`. Creating one on its own has no effect. On a clustered libvirt Provider the scheduler uses it as its constraint language; on other providers the VM's placement is passed to the provider as hints.

The `VMPlacementPolicy` CRD defines hard and soft placement constraints and affinity rules. VirtualMachines reference a policy in their own namespace via `spec.placementRef`.

Full schema: [generated-crd-docs.md#vmplacementpolicy](generated-crd-docs.md#vmplacementpolicy)

### Spec summary

| Field | Type | Description |
|-------|------|-------------|
| `hard` | `PlacementConstraints` | Must be satisfied: `hosts`, `excludedHosts`, `nodeSelector`, and the vSphere vocabulary (`clusters`, `datastores`, `networks`, `zones`, ...) |
| `soft` | `PlacementConstraints` | Preferences (scored, not enforced) |
| `affinity` / `antiAffinity` | `AffinityRules` | Host, VM, cluster, datastore, zone and application rules |
| `resourceConstraints` | `ResourceConstraints` | `requiredFeatures`, `preferredFeatures`, `minCPUPerHost`, `minMemoryPerHost`, `minDiskSpacePerHost`, utilization caps |
| `securityConstraints` | `SecurityConstraints` | Secure boot, TPM, isolation and trust level |
| `priority`, `weight` | `int32` | Policy priority (0-1000) and weight (1-100) |

On a clustered Provider the scheduler honors `hard.hosts`, `hard.excludedHosts`, `hard.nodeSelector` (matched against `Host` labels), `resourceConstraints.requiredFeatures` and `min*PerHost`, strict host and VM (anti-)affinity as hard filters, and the `soft` fields and preferred affinity as scores. The vSphere-style topology fields (`clusters`, `datastores`, `zones`, ...) have no meaning for the flat host model and are not applied.

### Example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMPlacementPolicy
metadata:
  name: spread-web-workers
spec:
  antiAffinity:
    hostAntiAffinity:
      enabled: true
      maxVMsPerHost: 1
```

---

## VMClone

The `VMClone` CRD manages a clone operation: it creates a new VirtualMachine from a source VM and is active on vSphere, Proxmox and libvirt. See limitations below.

Full schema: [generated-crd-docs.md#vmclone](generated-crd-docs.md#vmclone)

### Limitations

- **Source**: only `source.vmRef` (clone from a VM in the same namespace) is supported. `source.snapshotRef`, `source.templateRef` and `source.imageRef` set the VMClone to `Failed` with message `"clone source type not yet supported; use source.vmRef"`.
- **Same-provider only**: the target is created on the source VM's Provider.
- **Linked clones**: issued only when the provider reports `supportsLinkedClones`. vSphere and Proxmox do. On libvirt linked clones are disabled (`Ready=False/LinkedCloneUnsupported`); use `FullClone`. A libvirt full clone needs its source VM powered off (the clone waits with `SourceMustBePoweredOff`).
- **Power**: the target stays powered off unless `options.powerOn: true`.
- **Identity**: a libvirt clone gets its own cloud-init instance id and SSH host keys. `create` on `VMClone` is read access to the source's data.
- **Cross-namespace targets**: `target.namespace` other than the VMClone's needs the grant annotation `infra.virtrigaud.io/allowed-source-namespaces` on the target namespace.
- **Clustered Providers**: a clone is admitted against its source host's free capacity and never moves to another host.
- **Produced VM**: the controller creates a target `VirtualMachine` labeled `virtrigaud.io/adopted=true` with `status.id` seeded to the cloned VM's provider ID. Deleting a VMClone does **not** delete the produced VirtualMachine.

### Spec summary

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `source` | `CloneSource` | Yes | `vmRef` only (see limitations above) |
| `target` | `VMCloneTarget` | Yes | Destination `name` (required), `namespace`, `classRef`, `networks`, `disks`, `placementRef`, labels and annotations |
| `options` | `CloneOptions` | No | `type`: `FullClone` (default) or `LinkedClone`; `powerOn` (default `false`); `timeout` (default `30m`) |
| `customization` | `VMCustomization` | No | Cloud-init or Ignition customization for the target VM |
| `metadata` | `CloneMetadata` | No | Labels/annotations for clone audit |

### Status

| Field | Type | Description |
|-------|------|-------------|
| `phase` | `VMClonePhase` | `Pending`, `Preparing`, `Cloning`, `Customizing`, `Powering-On`, `Ready`, `Failed` |
| `targetVMID` | `string` | Provider-specific identifier of the cloned VM |
| `targetUID` | `string` | UID of the target VirtualMachine the clone created |
| `actualCloneType` | `string` | The clone type performed |
| `conditions` | `[]Condition` | Status conditions |
| `observedGeneration` | `int64` | Last observed generation |

### Example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClone
metadata:
  name: web-server-clone
spec:
  source:
    vmRef:
      name: web-server
  target:
    name: web-server-staging
    classRef:
      name: small
  options:
    type: FullClone
    powerOn: false
```

---

## CRD count at v0.4.0

The 12 CRDs in `infra.virtrigaud.io/v1beta1`: `VirtualMachine`, `Provider`, `VMClass`, `VMImage`, `VMNetworkAttachment`, `VMMigration`, `VMSnapshot`, `VMSet`, `VMPlacementPolicy`, `VMClone`, `Host`, `HostPool`.

`VMAdoption` is a **controller** (in `internal/controller/`), not a CRD. There is no `VMAdoption` resource in the API group.

For the full machine-generated field reference, see [generated-crd-docs.md](generated-crd-docs.md).
