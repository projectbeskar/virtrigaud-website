<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# vSphere Provider

The vSphere provider manages virtual machines on VMware vSphere (vCenter Server and standalone ESXi) via the `govmomi` SDK. It is the most mature provider in the VirtRigaud tree.

This page is aligned to **VirtRigaud v0.4.1**. Capability claims trace back to the provider's `GetCapabilities` response in `internal/providers/vsphere/server.go`.

## Capabilities at a glance

The vSphere provider advertises the following via `GetCapabilities` (`internal/providers/vsphere/server.go`):

| Capability flag | Value | What it means |
|-----------------|-------|---------------|
| `SupportsReconfigureOnline` | true | CPU / memory change of a running VM, **only** where vCenter can apply it (hot-add enabled on the VM). Otherwise the change waits for a power-off (see [Reconfigure](#reconfigure)). The flag does not say which VMs can. |
| `SupportsHonestReconfigure` | **false** | The provider does not mark its `Reconfigure` answers with the honest-result marker. It refuses what it cannot apply, but a `spec.disks` entry it finds no disk for is logged and left alone while the call succeeds. |
| `SupportsDiskExpansionOnline` | true | An additional disk `Create` attached can be grown without powering off (not on a shared SCSI bus or multi-writer disk). |
| `SupportsSnapshots` | true | Standard vSphere snapshots. |
| `SupportsMemorySnapshots` | **true** | `CreateSnapshot(memory=true)`; requires the VM to be powered on. Quiesce is not requested. |
| `SupportsLinkedClones` | true | Delta-disk clones on top of a snapshot of the source. |
| `SupportsImageImport` | true | `ImagePrepare` imports an `ovaURL` as a template. `templateName` is used by reference. A `contentLibrary` item is only checked for existence: it is not deployed to a template, and the manager sends only `templateName` and `ovaURL` to `Create`, so use a template or an OVA. |
| `SupportsImageArtifactIdentity` | true | Prepared templates are named, stamped and looked up by `VMImage` identity (ADR-0009 Slice 3). |
| `SupportsOwnerTransfer`, `SupportsOwnerRebind` | true | Adoption stamps the adopted VM; `Create` and `Clone` stamp the VM and re-bind a VM an earlier attempt made. |
| `SupportsDiskExport` / `SupportsDiskImport` | true | `ExportDisk` / `ImportDisk` / `GetDiskInfo` for migration; formats `vmdk`, `qcow2`, `raw`; export compression. |
| Export / import backends | `pvc`, `s3`, `nfs` | Relay transfer mode only. |
| `SupportedDiskTypes` | `thin`, `thick`, `eager-zeroed` | Native VMDK provisioning modes. |
| `SupportedNetworkTypes` | `standard`, `distributed` | Standard vSwitch portgroups and Distributed Virtual Switch portgroups. |

For the full cross-provider matrix and resilience / observability story, see:

- [Provider capabilities matrix](providers-capabilities.md): every capability across all providers.
- [Operations — Resilience](../operations/resilience.md): the CircuitBreaker wraps every outbound RPC to this provider.
- [Operations — Observability](../operations/observability.md): metric families that surface vSphere-side state.

## Behaviour at a glance: snapshot, revert, clone, reconfigure, disks

| Area | vSphere behaviour at v0.4.1 | Code |
|------|-----------------------------|------|
| Snapshot create | `CreateSnapshot(name, description, includeMemory, quiesce=false)`; waits for the task in the call (no `TaskRef`). The snapshot id is the snapshot's managed-object id. A template or an image artifact is refused (`VM_IS_IMAGE_ARTIFACT`). | `server.go` (`SnapshotCreate`), `vm_artifact_guard.go` |
| Snapshot revert | `spec.snapshot.revertToRef`; finds the snapshot by id or name and calls `RevertToSnapshot_Task` with `suppressPowerOn=false`, waiting in the call. A snapshot taken **with memory** powers the VM on; the controller then applies `spec.powerState`. | `server.go` (`SnapshotRevert`) |
| Snapshot delete | `RemoveSnapshot_Task` with `removeChildren=false`, `consolidate=true`. | `server.go` (`SnapshotDelete`) |
| Clone | Full clone, or linked clone (delta disk on the source's latest root snapshot; a `clone-base-<timestamp>` snapshot is created on the source if it has none). Runs against a **running** source. The clone is left powered off, stamped with its target, and has a **new cloud-init instance-id**. | `server.go` (`Clone`), `clone_target.go`, `clone_identity.go` |
| Reconfigure | CPU and memory, plus grow-only additional disks `Create` attached. Refuses what a running VM cannot take (`ResizePendingPowerOff`). The root disk is never touched. | `reconfigure.go` |
| `spec.disks` | Attached at `Create` (with the optional `scsi` block). An entry added after the VM exists is **not** attached, with no condition and no event. | `server.go` (`attachAdditionalDisk`) |
| Hardware version | A separate `HardwareUpgrade` RPC; powered-off VMs only; upward only. | `server.go`, [hardware version page](../operations/vsphere-hardware-version.md) |

## RPC support

The provider implements the VM lifecycle, snapshot, clone, image and disk-migration RPCs of the gRPC contract (`proto/provider/v1/provider.proto`). `ListHosts` and `GetHostInfo` (clustered-provider inventory) are `Unimplemented`:

- **Validate**: connectivity + credential check against vCenter, with a live probe + session reconnect (see [Session resilience](#session-resilience-v038)).
- **Create**: clone from a vSphere **template**, or create from a migration's imported disk. Stamps the VM with its owner. The new VM is left **powered off**; the `VirtualMachine` controller powers it on when `spec.powerState` is `On`.
- **Delete**: power off if needed, detach (keeping the file) any disk the VM does not own, then `Destroy_Task`. Templates and image artifacts are refused.
- **Power**: On / Off / Reboot / Shutdown-Graceful, idempotent. A graceful shutdown uses VMware Tools and falls back to a hard power-off after the timeout.
- **Describe**: current state, IPs (via VMware Tools), `ConsoleUrl`, raw vSphere properties. Reports `Exists=false` only for a definite `ManagedObjectNotFound`.
- **Reconfigure**: CPU / memory / additional-disk changes, see [Reconfigure](#reconfigure).
- **SnapshotCreate / SnapshotDelete / SnapshotRevert**: see [Snapshots, revert and clone](#snapshots-revert-and-clone).
- **Clone**: full or linked.
- **HardwareUpgrade**: see [Virtual hardware version](#virtual-hardware-version).
- **TaskStatus**: polls a vCenter task. Most operations wait for their task inside the call, so few RPCs return a `TaskRef`.
- **Console URL**: `Describe` returns a vSphere web client URL with the VM's instance UUID.
- **ImagePrepare**: OVA import ([identity-safe prepared templates](#images)).
- **ExportDisk / ImportDisk / GetDiskInfo**: disk export and import for the cross-provider migration pipeline.

## Prerequisites

- vCenter Server **7.0+** or ESXi **7.0+**, reachable over HTTPS (port 443).
- A service account with rights for VM lifecycle, datastore, network and resource management. See [Service account permissions](#service-account-permissions) below.
- TLS: a valid CA-issued cert for vCenter, or `insecureSkipVerify: true` during development.
- A vSphere **template** to clone VMs from (or an OVA URL the provider can import). See [Images](#images).
- Run **one replica** of each vSphere provider runtime. The controller deploys vSphere providers with one replica and the `Recreate` strategy.

## Authentication

The vSphere provider reads credentials from a Kubernetes Secret referenced via `Provider.spec.credentialSecretRef`. The provider controller mounts that Secret read-only at `/etc/virtrigaud/credentials` inside the provider pod. **The Secret keys are read as files**, so the key names matter:

| Secret key | File path | Required |
|-----------|-----------|----------|
| `username` | `/etc/virtrigaud/credentials/username` | Yes |
| `password` | `/etc/virtrigaud/credentials/password` | Yes |

TLS verification is controlled by the `Provider.spec.insecureSkipVerify` field, which the controller exports to the pod as the `TLS_INSECURE_SKIP_VERIFY` env var. Leave it `false` in production.

### Provider CR + Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-credentials
  namespace: virtrigaud-system
type: Opaque
stringData:
  username: "virtrigaud@vsphere.local"
  password: "REPLACE_ME"
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: vsphere-prod
  namespace: virtrigaud-system
spec:
  type: vsphere
  endpoint: https://vcenter.example.com/sdk
  credentialSecretRef:
    name: vsphere-credentials
  insecureSkipVerify: false
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.1"
    service:
      port: 9443
      tls:
        enabled: true
        secretRef:
          name: provider-vsphere-tls
        insecureSkipVerify: false
```

A Provider used from other namespaces must set `spec.consumerNamespaceSelector`; see [Cross-namespace references](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/cross-namespace-references.md).

### Service account permissions

Create a dedicated vSphere user with these privileges:

- **Datastore**: AllocateSpace, Browse, FileManagement
- **Network**: Assign
- **Resource**: AssignVMToPool
- **Virtual machine**: full set (or a tailored subset covering Inventory, Interaction, Configuration, Provisioning, Snapshot management)
- **Global**: EnableMethods, DisableMethods, Licenses

Two privileges are **required since v0.4.0** and must not be left out of a tailored subset:

| Privilege | ID | Needed for |
|---|---|---|
| Virtual machine > Change Configuration > **Advanced configuration** | `VirtualMachine.Config.AdvancedConfig` | **Every** `Create` and `Clone`, and adoption. The owner stamp, and the clearing of an inherited stamp, are ExtraConfig writes. Grant it on the target VM folder and resource pool (and on the VMs adoption may take over). Without it creates fail with a vCenter permission error; they do not create an unstamped VM. The same privilege covers the image stamp of a prepared template, on the import folder. |
| **System > Read** | `System.Read` | On the vCenter **root folder, propagated** (and on every datastore scanned), with no narrower "No access" permission below it. Before a migration attaches a landed disk in place, before a migration import reuses or a failed one deletes its landing folder, and before a VM with a disk outside its own directory is deleted, the provider checks that no other VM uses the disk. vCenter silently hides VMs the account may not see, so the provider first verifies this privilege and refuses (`VM_DISK_CHECK_FAILED`, retried) otherwise. |

For prepared templates, nobody but the Provider's vCenter account should be able to create, move, rename, reconfigure or mark as template VMs in the import folder (see [Images](#images)).

## TLS / mTLS (v0.3.7+)

Starting in v0.3.7, the manager enforces that every Provider CR has a `spec.runtime.service.tls` block. A Provider without this block fails to reconcile and its status will show `TLSConfigured=False, Reason=TLSBlockMissing` — no Deployment is created.

For full mTLS details see [Security — mTLS](security/mtls.md).

### `spec.runtime.service.tls` fields

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | bool | Set `true` to enable mTLS. Set `false` for plaintext (dev/lab only; audit-flagged). |
| `secretRef.name` | string | Name of a `kubernetes.io/tls` or `Opaque` Secret containing `tls.crt`, `tls.key`, and `ca.crt`. |
| `insecureSkipVerify` | bool | Skip server certificate verification. Dev-only; never set in regulated environments. |

TLS material mounts at `/etc/virtrigaud/tls` inside the provider pod. Both manager and provider pin TLS 1.3. `tls.enabled: true` without a `secretRef` sets `TLSConfigured=False, Reason=SecretRefMissing` and the Deployment is not created. A `secretRef` that names a Secret that does not exist is not detected: `TLSConfigured` stays `True` / `Enabled` and the provider pod fails to mount the Secret and does not start.

The `TLSConfigured` status condition reasons are:

| Reason | Meaning |
|--------|---------|
| `TLSBlockMissing` | No `tls` block at all in the Provider CR. |
| `ExplicitlyDisabled` | `tls.enabled: false` — plaintext acknowledged. |
| `SecretRefMissing` | `tls.enabled: true` but `secretRef` is not set or its name is empty. A named Secret that does not exist is not checked here. |
| `Enabled` | mTLS wired; Deployment proceeds. |

### Example Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: provider-vsphere-tls
  namespace: virtrigaud-system
type: kubernetes.io/tls
data:
  tls.crt: LS0tLS1CRUdJTi...  # base64-encoded cert
  tls.key: LS0tLS1CRUdJTi...  # base64-encoded key
stringData:
  ca.crt: |
    -----BEGIN CERTIFICATE-----
    # Your CA certificate
    -----END CERTIFICATE-----
```

## Endpoint formats

| Endpoint | Use case |
|----------|----------|
| `https://vcenter.example.com/sdk` | vCenter (recommended for multi-host) |
| `https://192.0.2.10/sdk` | Direct IP, useful when DNS is the problem you are debugging |
| `https://esxi-01.example.com/sdk` | Standalone ESXi (single-host environments) |

The `Provider.spec.endpoint` is exposed to the provider pod as `PROVIDER_ENDPOINT`.

## Cloud-init on vSphere

vSphere does **not** use a NoCloud ISO. The provider injects cloud-init via VMware's `guestinfo` properties (`addCloudInitToConfigSpec` in `internal/providers/vsphere/server.go`). The keys it sets are:

| Property | Value |
|----------|-------|
| `guestinfo.userdata` | base64-encoded user-data |
| `guestinfo.userdata.encoding` | `base64` |
| `guestinfo.metadata` | base64-encoded meta-data (`instance-id: "<vm name>"` if none is given) |
| `guestinfo.metadata.encoding` | `base64` |

The guest must have a recent cloud-init that supports the VMware datasource (Ubuntu cloud images and most distro cloud images do). Writing these keys needs `VirtualMachine.Config.AdvancedConfig`.

## Datastore selection (precedence)

VirtRigaud supports four sources to choose a datastore. Precedence is strict: higher entries win:

| Priority | Source | When it applies |
|----------|--------|-----------------|
| 1 (highest) | `VirtualMachine.spec.placement.datastore` | Explicit per-VM override |
| 2 | `VirtualMachine.spec.placement.storagePod` | Per-VM Datastore Cluster (StoragePod) |
| 3 | `PROVIDER_DEFAULT_STORAGE_POD` (or `Provider.spec.defaults.storagePod`) | Provider-level Datastore Cluster default |
| 4 (lowest) | `PROVIDER_DEFAULT_DATASTORE` (or `Provider.spec.defaults.datastore`) | Provider-level fixed-datastore default |

### StoragePod (Datastore Cluster) auto-selection

When a StoragePod is configured, the provider enumerates the cluster's member datastores via the vSphere API, retrieves the `FreeSpace` summary for each, and picks the member with the most free space (`resolveDatastoreFromStoragePod` in `internal/providers/vsphere/server.go`). This is a lightweight alternative to Storage DRS and does **not** require SDRS to be enabled.

!!! info "Datastore-name resolution bug fixed in v0.3.3"
    A v0.3.3 fix (March 2026) resolves "Invalid configuration for device '0'" errors that previously surfaced when a StoragePod-selected datastore was reattached to additional disks. The fix replaces a stale `object.NewDatastore()` construction with `p.finder.Datastore(ctx, best.Name)` so the returned object carries the full inventory path. If you see this error on older versions, upgrade.

#### Configuring a default StoragePod

Via the Provider CR:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: vsphere-prod
spec:
  type: vsphere
  endpoint: https://vcenter.example.com/sdk
  credentialSecretRef:
    name: vsphere-credentials
  defaults:
    storagePod: "DatastoreCluster-SSD"
    cluster: "Compute-Cluster"
    folder: "/vm/applications"   # also the import folder for prepared templates
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.1"
    service:
      port: 9443
      tls:
        enabled: true
        secretRef:
          name: provider-vsphere-tls
```

#### Per-VM placement

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: web-application
spec:
  providerRef:
    name: vsphere-prod
  classRef:
    name: standard-vm
  # ... imageRef, networks, etc.
  placement:
    cluster: "Compute-Cluster"
    resourcePool: "Production"
    folder: "/vm/applications"
    storagePod: "DatastoreCluster-SSD"   # ignored if datastore: is set
    # datastore: "datastore-ssd"          # explicit override wins
```

## SCSI controller configuration (vSphere only)

`spec.disks[].scsi` (`SCSIControllerSpec`, since v0.3.6) selects the SCSI controller of a disk. It is vSphere-only: libvirt and Proxmox attach no `spec.disks` at all. Reference: `SCSIControllerSpec` in `api/infra.virtrigaud.io/v1beta1/virtualmachine_types.go`.

```yaml
disks:
  - name: data
    sizeGiB: 500
    type: thin
    scsi:
      controller: 1                # bus 0-3 (default: first available)
      controllerType: pvscsi       # pvscsi | lsilogic | lsilogic-sas | buslogic
      sharedBus: virtualSharing    # noSharing | virtualSharing | physicalSharing
```

When to use the `scsi` block:

- **RDM (raw device mapping) or shared cluster disks**: `pvscsi` with `sharedBus: virtualSharing` (for in-cluster shared) or `physicalSharing` (for cross-host shared).
- **More than 15 disks on a single VM**: each SCSI controller holds up to 15 devices; spread disks across multiple controllers (`controller: 0`, `controller: 1`, ...) for >15.
- **Legacy guests**: drop to `lsilogic` or `buslogic` for guests that lack the pvscsi driver.

If you do not set `scsi`, the provider creates a single `pvscsi` controller with `noSharing` and attaches every disk to it.

## VMClass

`VMClass` defines CPU/memory/firmware defaults and vSphere-specific tuning via `extraConfig`:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: standard-vm
spec:
  cpu: 4
  memory: "8Gi"
  firmware: UEFI
  diskDefaults:
    type: thin
    size: "40Gi"
  guestToolsPolicy: install
  performanceProfile:
    cpuHotAddEnabled: true
    memoryHotAddEnabled: true
    latencySensitivity: normal
  securityProfile:
    secureBoot: true
    tpmEnabled: true
  resourceLimits:
    cpuReservation: 1000             # MHz
    memoryReservation: "2Gi"
  extraConfig:
    "numvcpus.coresPerSocket": "2"   # CPU topology hint
```

`cpuHotAddEnabled` and `memoryHotAddEnabled` decide whether a running VM can be resized (see [Reconfigure](#reconfigure)). See [the full CRD reference](../references/generated-crd-docs.md#vmclass) for every field.

## Images

A vSphere `VMImage` references a **real vSphere template** or an OVA to import:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-22-04-template
spec:
  source:
    vsphere:
      # Must name an object marked as a vSphere template. A simple name is
      # matched exactly in the Provider's default datacenter; an inventory
      # path such as "/DC1/vm/templates/ubuntu-22.04" also works.
      templateName: "ubuntu-22.04-template"
```

- **`templateName` must name a real template.** A regular VM (running or powered off) is never used as a clone source: the `VMImage` gets `ValidationError` instead of cloning it. Convert the source with `govc vm.markastemplate`. A name matching more than one template is rejected: use an inventory path.
- **Names of the form `vm-<digits>` are refused** (the shape of a vCenter VM managed-object id), for VM names, for `VMImage` names used as prepare targets and for bare template names. So are names containing `/`, `\`, `%` or `:`. Names such as `vm-web` are fine.
- **Identity-safe prepared templates (ADR-0009, Slice 3).** For `source.vsphere.ovaURL`, the manager sends the `VMImage` identity and the digest of its source; the provider imports the OVA as a template named `<namespace>.<name>_<16 hex>` (at most 80 characters) in the Provider's **import folder** (`spec.defaults.folder`, else the datacenter's VM folder), stamped with `virtrigaud.image.*` ExtraConfig keys. It reuses an object only when it is a template **and** the stamp carries the request's `VMImage` UID and source digest; anything else at that name is a `Conflict`, never used, replaced or deleted. `Create` clones exactly that template, by absolute inventory path, never a same-named one elsewhere.
- **The OVA is read from the download only (security fix).** Every file reference in the OVF must be a plain file name that is a member of the OVA; a bare `.ovf` that references any file is refused (`InvalidSpec`), and the provider never reads a file on its own filesystem named by an OVF (it used to be possible to make it upload the provider's mounted credentials). The descriptor is limited to 16 MiB and 256 file references, and an OVF must describe exactly one VM.
- **The download is restricted:** loopback, link-local (which includes cloud metadata endpoints), unspecified and multicast addresses are refused, checked on every connection after DNS resolution (private RFC 1918 and unique-local addresses stay allowed, since image servers are usually internal); at most 3 redirects, never `https` to `http`; at most `VIRTRIGAUD_VSPHERE_IMAGE_MAX_DOWNLOAD_GIB` GiB (default 256) set through `spec.runtime.env`; a body that delivers less than 64 KiB in 60 seconds is abandoned. Image downloads ignore `HTTP_PROXY`/`HTTPS_PROXY`; set `VIRTRIGAUD_VSPHERE_IMAGE_PROXY` to use a proxy. Keep credentials out of `ovaURL`.
- **Give each tenant's Provider its own import folder** and scope its vCenter account to it: vCenter folder permissions propagate, and anyone who can create, rename or mark as template in the import folder can plant a matching template that is then reused.
- A manager older than ADR-0009 is still served the old way (a template named after the `VMImage`) for this release, with a warning and the counter `virtrigaud_provider_image_prepare_legacy_requests_total{provider_type="vsphere"}`; alert on it.

Full rules, failure classes and the stamp: [Image preparation](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/image-preparation.md#vsphere-identity-safe-prepared-templates).

## Complete VM example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMNetworkAttachment
metadata:
  name: app-network
spec:
  network:
    vsphere:
      portgroup: "VM Network"
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: web-application
spec:
  providerRef:
    name: vsphere-prod
  classRef:
    name: standard-vm
  imageRef:
    name: ubuntu-22-04-template
  powerState: "On"
  disks:
    - name: data
      sizeGiB: 500
      type: thin
      scsi:
        controllerType: pvscsi

  # Only the FIRST entry of spec.networks is consumed by the vSphere provider:
  # it selects the portgroup and carries the static address (pushed to the
  # guest via guestinfo.network.*, see "Static IP assignment" below).
  networks:
    - name: app
      networkRef:
        name: app-network
      ipAddress: "192.0.2.50"
      prefix: 24
      gateway: "192.0.2.1"
      dns: "192.0.2.53,198.51.100.53"

  # vSphere placement (no 'datacenter' field: datacenter is derived from the provider endpoint)
  placement:
    cluster: "Compute-Cluster"
    resourcePool: "Production"
    folder: "/vm/applications"
    storagePod: "DatastoreCluster-SSD"
  userData:
    cloudInit:
      inline: |
        #cloud-config
        hostname: web-application
        users:
          - name: ubuntu
            sudo: ALL=(ALL) NOPASSWD:ALL
            ssh_authorized_keys:
              - "ssh-ed25519 AAAA..."
        packages:
          - nginx
          - open-vm-tools
        runcmd:
          - systemctl enable --now nginx open-vm-tools
```

Quote `powerState` values (`"On"`): an unquoted `On` is a boolean in YAML 1.1 and is rejected by the API server.

## Ownership: Create and Clone fail closed

vCenter allows several VMs with one name in different folders, and the provider used to bind a `VirtualMachine` to **any** VM it found by name. Since v0.4.0 the provider never binds a `VirtualMachine` to a VM unless it can prove that `VirtualMachine` created it.

- **Owner stamp.** Every VM `Create` and `Clone` makes gets three ExtraConfig keys: `virtrigaud.owner.uid` (the only key that authorizes a bind), `virtrigaud.owner.namespace` and `virtrigaud.owner.name`. They do not use the `guestinfo.` prefix, so software in the guest cannot read them through VMware Tools. Inspect them with `govc vm.info -e <vm> | grep virtrigaud.owner`. A clone copies its source's ExtraConfig, so the provider clears an inherited stamp (and any `virtrigaud.image.*` key): a new VM never inherits a stamp or is mistaken for an image artifact. Writing them needs `VirtualMachine.Config.AdvancedConfig`.
- **Where `Create` looks.** The provider resolves the target folder (`spec.placement.folder`, else the Provider's default folder, else the datacenter's default VM folder) and compares the names of the **direct children** of that folder byte for byte. A same-named VM in any other folder is neither bound nor considered.
- **What it does with a same-named VM in that folder:**

    | VM with the requested name in the target folder | Result |
    |---|---|
    | None | Created and stamped |
    | One, stamped with the requester's UID | Idempotent success: its MOID is returned (a retried create after a lost status write) |
    | One, stamped with another UID; or unstamped (not created by VirtRigaud, or created before v0.4.0); or an unreadable stamp; or a template; or the request has no owner | **Refused** (`Conflict`, surfaced as `ProviderConflict`) |
    | More than one | **Refused** |
    | The lookup failed | Error, retried: the provider never creates or binds on an unknown answer |

- **Per-VM operations refuse templates and image artifacts.** `Delete`, `Power`, `Reconfigure`, `HardwareUpgrade` and the snapshot calls read `config.template` and `config.extraConfig` first, and refuse a template or an object carrying a `virtrigaud.image.*` key (`FailedPrecondition` + `VM_IS_IMAGE_ARTIFACT`). A refused `Delete` keeps the finalizer with `Ready=False/VMIsImageArtifact` and the template is never destroyed; detach such a `VirtualMachine` with `virtrigaud.io/orphan-on-delete: "true"`. A full clone from a template is not guarded (that is what templates are for), but a linked clone that would have to snapshot a template or image artifact is refused.
- **Adoption** (`virtrigaud.io/adopt-vms`) lists ordinary VMs only: no template, no prepared-image artifact, and no VM whose owner stamp is unreadable. A VM with a readable stamp is listed with its owner UID and skipped while that `VirtualMachine` exists. A VM adoption takes over is stamped with its adopting `VirtualMachine`.
- **Existing VMs** (created before v0.4.0) carry no stamp. VMs already bound (`status.id` set) are unaffected: every operation after `Create` uses the MOID. A create that collides with an unstamped VM fails with `ProviderConflict` instead of taking it over; adopt the VM to recover. **The protection needs the v0.4.0 vSphere provider**: an older provider ignores the owner and binds by name across the whole datacenter.

Full details: [VM ownership](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/vm-ownership.md#vsphere).

## Reconfigure

`Reconfigure` applies the desired CPU, memory and additional-disk sizes as **one** `ReconfigVM_Task`, or refuses before changing anything. It refuses what a running VM cannot take, but it does not report the honest-result marker: a `spec.disks` entry with no recorded disk is logged and skipped while the call succeeds. Outcomes:

| Outcome | When | What the VM shows |
|---------|------|-------------------|
| Applied | The VM is powered off, or the change is one vCenter can apply online | `Reconfiguring=False/ReconcileSuccess` |
| **`ResizePendingPowerOff`** | The VM is not powered off and vCenter cannot apply the change now | `Reconfiguring=False/ResizePendingPowerOff`, the VM stays `Ready`, nothing was changed |
| Failed | vCenter refused or failed the task, or could not be reached | `Reconfiguring=False/ProviderError`, retried on a per-VM backoff |

vCenter changes a powered-on VM's CPU count only with **CPU hot-add** (more vCPUs) or **CPU hot-remove** (fewer) enabled on the VM, and its memory only upwards, with **memory hot-add** enabled and within the VM's **hot-plug memory limit**. It grows a disk on a **shared SCSI bus** or with **multi-writer** sharing only while the VM is off, and changes no hardware of a suspended VM. vSphere has no pending state to stage a change for the next boot, so before a change of a VM that is not powered off the provider reads `config.cpuHotAddEnabled`, `config.cpuHotRemoveEnabled`, `config.memoryHotAddEnabled`, `config.hotPlugMemoryLimit` and the disk's controller and sharing. When the change is not possible now it refuses the whole request, everything in it, with `FailedPrecondition` and the reason `RECONFIGURE_NEEDS_POWER_OFF` (never counted toward the circuit breaker). Before v0.4.0 vCenter refused the task and the manager retried it indefinitely.

To apply such a change, set `spec.powerState: "Off"`: the manager powers the VM off, the next `Reconfigure` applies the change, then set `spec.powerState: "On"`. The manager never powers a VM off by itself. To resize running VMs, enable CPU and memory hot-add on them (VMClass `performanceProfile.cpuHotAddEnabled` / `memoryHotAddEnabled` for new VMs, or in vCenter while the VM is off). Hot-add costs a thin layer of indirection: leave it off for latency-sensitive workloads.

Other refusals before anything changes: a CPU count that is not a multiple of the VM's cores per socket (`InvalidSpec`), and a `spec.disks` shrink (`InvalidSpec`: a disk is never shrunk). A `ReconfigVM_Task` vCenter refuses to start (`TaskInProgress` during a backup snapshot, `InvalidState`, ...) or fails is answered `VM_OPERATION_FAILED` with a constant message (the fault is in the provider log) and does not trip the breaker.

**Which disk a size goes to.** `Reconfigure` **never touches the root disk**: the VMClass `diskDefaults.size` is applied by `Create` only. A `spec.disks[].sizeGiB` goes to the additional disk `Create` attached for that entry, found by the name recorded with it in the VM's ExtraConfig (`virtrigaud.disk.additional.<N>.name`), so reordering `spec.disks` never moves a size to another disk. The provider leaves a disk alone, and logs why, when no disk is recorded under the entry's name (the entry was added after the VM was created, the VM was adopted, or an earlier release attached it without a name), when the name is ambiguous, or when vCenter cannot extend it (a delta disk because the VM has snapshots or is a linked clone, or a physical-mode RDM). **A disk-size change alone does not trigger a `Reconfigure`**: the manager sends one when the effective CPU or memory changes, and the disk sizes travel with it.

Full contract: [Reconfigure results](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/reconfigure-results.md#vsphere-changes-a-running-vm-cannot-take).

## Snapshots, revert and clone

### Snapshots

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMSnapshot
metadata:
  name: pre-upgrade-snapshot
spec:
  vmRef:
    name: web-application
  snapshotConfig:
    name: "pre-upgrade"
    description: "Snapshot before application upgrade"
    includeMemory: true     # needs the VM powered on
```

The provider requests no quiesce (`quiesce=false`; the `snapshotConfig.quiesce` field is not passed through). The snapshot id the provider returns is the snapshot's managed-object id. A snapshot of a template or an image artifact is refused. `SnapshotDelete` removes with `removeChildren=false` (children are re-parented) and consolidates the delta disks. A `VMSnapshot` delete the provider refuses for good keeps its finalizer with `Ready=False/DeleteBlocked` and the provider's answer.

### Revert

Name the `VMSnapshot` in `spec.snapshot.revertToRef` of the `VirtualMachine`, with the VM powered off (`spec.powerState: "Off"`). The provider reverts with `suppressPowerOn=false`, waits for the task in the call and returns no task. A snapshot taken **with memory** leaves the VM powered on after the revert; the controller then applies `spec.powerState` (a VM whose spec says `Off` is powered off again). Watch `status.snapshotRevert` and the `SnapshotReverted` condition; the request is sent at most once, and removing and re-setting the field requests it again. The revert was exercised in the project's lab on a real vCenter during the v0.4.0 release candidates, and is covered by controller tests and the vcsim simulator. See [Reverting a VirtualMachine to a VMSnapshot](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/vm-snapshot-revert.md).

### Clone

`VMClone` clones a vSphere VM with `CloneVM_Task` on the Provider's default cluster, datastore and folder; the source may be running. `type: LinkedClone` creates a delta disk on the source's most recent root snapshot, creating a `clone-base-<timestamp>` snapshot on the source if it has none. The clone is left powered off (unless `spec.options.powerOn: true`) and is stamped with its target `VirtualMachine`; a clone request sent again finds the stamped clone instead of cloning twice.

**Clone identity.** A clone copies its source's ExtraConfig, including `guestinfo.metadata` whose `instance-id` is the source's VM name, so cloud-init would treat the clone's first boot as the same instance and keep the source's SSH host keys and hostname. The clone's `CloneVM_Task` therefore rewrites `guestinfo.metadata` with `instance-id: virtrigaud-<target VirtualMachine uid>` and the target's hostname (and a `#cloud-config` `guestinfo.userdata`'s top-level `hostname:`/`fqdn:`). cloud-init sees a new instance on first boot, regenerates the SSH host keys and re-runs every per-instance module (`runcmd`, `packages`, `users`). It does **not** regenerate `/etc/machine-id`; seal the source (`cloud-init clean --machine-id`) if clones need their own. A source with no `guestinfo.metadata` is left untouched (the VMware datasource then takes the instance-id from the BIOS UUID, which vCenter regenerates for a clone). The vSphere provider applies **only the hostname and domain** of a clone's customization: inline or Secret user-data in the `VMClone` is logged and not applied, so a clone boots with the **source's user-data**, secrets included. Treat `create` on `vmclones` as read access to the source VM's data. Details: [A clone's host identity](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/vm-ownership.md#a-clones-host-identity).

## Virtual hardware version

The provider can create VMs at a chosen virtual hardware version (the `vsphere.hardwareVersion` key of the VMClass `extraConfig`) and exposes a `HardwareUpgrade` RPC that raises a VM's `vmx-N` level, upward only and only while the VM is powered off. See [vSphere hardware version management](../operations/vsphere-hardware-version.md).

## `status.ips`

`Describe` reads `guest.ipAddress` and `guest.net` from **VMware Tools**, so a guest without Tools running shows no address. The provider skips loopback and link-local addresses of `guest.net`, and the manager then applies one filter to every provider's answer (loopback, unspecified, link-local, multicast, non-addresses and duplicates are dropped; the provider's order is kept). See [`status.ips`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/vm-status-ips.md).

## Async task tracking

vSphere operations that are long-running (clone, snapshot, reconfigure-with-large-disk-add) are awaited inside the provider call in most cases. Where a `TaskRef` is returned, the manager polls `TaskStatus` until terminal. Every in-flight task is counted by the `virtrigaud_provider_tasks_inflight{provider_type="vsphere", provider="<name>"}` gauge, seeded to `0` at boot so it appears on `/metrics` from the first scrape; useful for catching stuck tasks. See [Observability](../operations/observability.md#11-virtrigaud_provider_tasks_inflight).

## Session resilience (v0.3.8)

The vSphere provider keeps its vCenter session alive and recovers from long idle periods automatically:

- A **keepalive** runs against the govmomi session (every 5 minutes) so it does not lapse during quiet periods.
- **`Validate` performs a live probe** of the session and **reconnects** if the session has gone stale.

A provider pod that has been idle for hours no longer fails its next RPC with `NotAuthenticated` and then has to be restarted. If you previously worked around stale sessions with a periodic provider-pod restart, you can drop that workaround.

## Console access

`Describe` populates `status.consoleURL` with a vSphere web client link that includes the VM's managed-object id and instance UUID. Open it in a browser; vCenter prompts for authentication and lands you on the VM's summary.

```bash
kubectl get vm web-application -n my-app -o jsonpath='{.status.consoleURL}'
# https://vcenter.example.com/ui/#?extensionId=vsphere.core.vm.summary&objectId=urn:vmomi:VirtualMachine:vm-123:<instance-uuid>
```

## Multi-vCenter

Deploy one `Provider` CR per vCenter. Each gets its own provider pod, its own gRPC port, and its own CircuitBreaker series in metrics:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: vsphere-dc-a
  namespace: virtrigaud-system
spec:
  type: vsphere
  endpoint: https://vcenter-a.example.com/sdk
  credentialSecretRef:
    name: vsphere-credentials-a
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.1"
    service:
      port: 9443
      tls:
        enabled: true
        secretRef:
          name: provider-vsphere-a-tls
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: vsphere-dc-b
  namespace: virtrigaud-system
spec:
  type: vsphere
  endpoint: https://vcenter-b.example.com/sdk
  credentialSecretRef:
    name: vsphere-credentials-b
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.1"
    service:
      port: 9443
      tls:
        enabled: true
        secretRef:
          name: provider-vsphere-b-tls
```

## Static IP assignment (guestinfo)

When a template boots without DHCP, VirtRigaud can hand the guest a static IP by writing it into the VM's **guestinfo** properties at create time. This is the mechanism used by the vSphere provider for static addressing.

### How to request a static IP

Set the address fields **inline on the `VirtualMachine`'s `spec.networks` entry**, not on the `VMNetworkAttachment`:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: static-ip-vm
spec:
  providerRef:
    name: vsphere-prod
  classRef:
    name: standard-vm
  imageRef:
    name: ubuntu-22-04-template
  powerState: "On"
  networks:
    - name: app
      # networkRef is optional. When omitted, the template's existing NIC is
      # reused and only the guestinfo IP settings below are applied.
      networkRef:
        name: app-network
      ipAddress: "192.0.2.50"        # static IPv4 address
      prefix: 24                     # CIDR prefix length (1-32)
      gateway: "192.0.2.1"           # default gateway
      dns: "192.0.2.53,198.51.100.53" # comma-separated resolvers
```

| `spec.networks[]` field | guestinfo key written        | Notes                                        |
| ----------------------- | ---------------------------- | -------------------------------------------- |
| `ipAddress`             | `guestinfo.network.ip`       | When empty, **nothing is written** (DHCP).   |
| `prefix`                | `guestinfo.network.prefix`   | Only written when `> 0`.                      |
| `gateway`               | `guestinfo.network.gateway`  | Only written when non-empty.                  |
| `dns`                   | `guestinfo.network.dns`      | Comma-separated; only written when non-empty. |

!!! note "Only the first network entry is used"
    The provider consumes **only `spec.networks[0]`**: its `networkRef` selects the portgroup (a single network adapter) and its `ipAddress`/`prefix`/`gateway`/`dns` become the single-NIC static configuration. Further entries are ignored by the vSphere provider, including their `networkRef`. For more than one NIC, put the NICs on the template. The attachment's `vlan` block and `adapterType` have no effect either: the provider reads only the portgroup name.

!!! warning "The guest must consume the keys"
    VirtRigaud only *publishes* `guestinfo.network.*`. The values are inert unless the **template** contains a boot-time agent that reads them and configures the interface. Cloud images do not do this by default: bake the helper below (or an equivalent netplan/NetworkManager generator) into the template. If the IP never applies, this missing guest-side step is almost always the cause.

### Guest-side helper (template bake-in)

A minimal `oneshot` unit that reads the keys with `vmware-rpctool` and renders a
netplan config on first boot:

```bash
#!/usr/bin/env bash
# /usr/local/sbin/apply-guestinfo-network.sh — run before networking comes up.
set -euo pipefail

get() { vmware-rpctool "info-get guestinfo.network.$1" 2>/dev/null || true; }

IP=$(get ip); PREFIX=$(get prefix); GW=$(get gateway); DNS=$(get dns)

# No static IP published → leave DHCP/template defaults in place.
[ -n "$IP" ] || exit 0

IFACE=$(ls /sys/class/net | grep -E '^(en|eth)' | head -n1)
DNS_YAML=$(echo "$DNS" | tr ',' '\n' | sed 's/^/        - /')

cat > /etc/netplan/90-guestinfo.yaml <<EOF
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses: [${IP}/${PREFIX:-24}]
      routes:
        - to: default
          via: ${GW}
      nameservers:
        addresses:
${DNS_YAML}
EOF

netplan apply
```

```ini
# /etc/systemd/system/apply-guestinfo-network.service
[Unit]
Description=Apply static network from vSphere guestinfo
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/apply-guestinfo-network.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Enable it in the template (`systemctl enable apply-guestinfo-network.service`)
before converting the VM to a template. `open-vm-tools` must be installed so that
`vmware-rpctool` is available.

### Verifying

From a host with [`govc`](https://github.com/vmware/govmomi/tree/main/govc),
confirm the keys landed on the created VM:

```bash
govc vm.info -e static-ip-vm | grep guestinfo.network
# guestinfo.network.ip:      192.0.2.50
# guestinfo.network.prefix:  24
# guestinfo.network.gateway: 192.0.2.1
# guestinfo.network.dns:     192.0.2.53,198.51.100.53
```

If the keys are present but the guest is still on DHCP, the guest-side helper is
missing or failed — check `journalctl -u apply-guestinfo-network` inside the VM.

!!! info "Relationship to cloud-init and `VMNetworkAttachment.ipAllocation`"
    `guestinfo.network.*` is **independent** of the cloud-init guestinfo keys (`guestinfo.userdata` / `guestinfo.metadata`); a template may honour either or both. The `ipAllocation` block on `VMNetworkAttachment` is **not** wired to the vSphere static-IP path: use the inline `spec.networks[]` fields shown above.

## Troubleshooting

### CircuitBreaker open for the vSphere provider

Check `/metrics`:

```promql
virtrigaud_circuit_breaker_state{provider_type="vsphere", provider="vsphere-prod"} == 2
```

When this fires, the manager has fast-failed enough RPCs to vCenter that it has opened the breaker (defaults: 10 consecutive failures to open, 60s reset; see [Resilience](../operations/resilience.md#circuitbreaker-on-the-provider-grpc-path-v036)). Investigate the underlying vCenter (credentials, certificate, network) rather than restarting the manager. Refusals scoped to one VM or image (`VM_IS_IMAGE_ARTIFACT`, `RECONFIGURE_NEEDS_POWER_OFF`, `IMAGE_SOURCE_UNAVAILABLE`, a `Conflict`) are kept out of the breaker.

### `ProviderConflict` on create

A VM with the requested name already exists in the target folder and it is not stamped with this `VirtualMachine`'s UID. Adopt it, or rename one of them. See [Ownership](#ownership-create-and-clone-fail-closed).

### Create fails with a vCenter permission error

The account lacks `VirtualMachine.Config.AdvancedConfig` on the target folder and resource pool. See [Service account permissions](#service-account-permissions).

### `ValidationError` on a `VMImage` or `VirtualMachine`

The `templateName` points at a regular VM instead of a template, or a VM / template name has the form `vm-<digits>`. Convert the source with `govc vm.markastemplate`, or rename.

### `Reconfiguring=False/ResizePendingPowerOff`

The VM is running and vCenter cannot apply the change (no CPU or memory hot-add on the VM, or the memory hot-plug limit would be exceeded). Set `spec.powerState: "Off"`, wait for the resize, then power on. See [Reconfigure](#reconfigure).

### "Invalid configuration for device '0'" on disk attach

Older releases hit this when a StoragePod-resolved datastore was reattached to additional disks; the returned `object.Datastore` was missing its inventory path. Fixed in v0.3.3 by routing through `p.finder.Datastore(ctx, best.Name)`. Upgrade.

### "Login failed: incorrect user name or password"

The username in the `Provider.spec.credentialSecretRef` Secret must match the **principal name** expected by vCenter, usually `user@vsphere.local`, not bare `user`. Also check whether the user is locked out via Single Sign-On.

### `NotAuthenticated` after a long idle period

On releases before v0.3.8 the govmomi session could lapse during long idle windows. v0.3.8 added a session keepalive and a live-probe reconnect in `Validate`. If you still see this, confirm the provider image tag is v0.3.8 or later. See [Session resilience](#session-resilience-v038).

### Template not found

The `VMImage.spec.source.vsphere.templateName` value is resolved via the `govmomi` finder. List templates with:

```bash
govc ls /Datacenter/vm/templates/
```

If two templates share a name, reference the right one by inventory path (for example `/Datacenter/vm/templates/ubuntu-22.04`).

### Datastore issues

```bash
# Datastore capacity
govc datastore.info datastore-name

# All datastores
govc ls /Datacenter/datastore/

# StoragePod (Datastore Cluster) members
govc object.collect -s /Datacenter/datastore/DatastoreCluster-SSD childEntity
```

If a StoragePod-selected datastore exists but the create still fails, check whether the storage policy assigned to the VMClass conflicts with the member datastores in the cluster.

### Validation walkthrough with `govc`

```bash
export GOVC_URL='https://vcenter.example.com'
export GOVC_USERNAME='administrator@vsphere.local'
export GOVC_PASSWORD='password'
export GOVC_INSECURE=1        # only for dev

govc about                    # connectivity + credentials
govc ls                       # datacenters
govc ls /Datacenter/host/     # clusters & hosts
govc ls /Datacenter/datastore/
govc ls /Datacenter/network/
govc ls /Datacenter/vm/templates/
```

### Debug logging

```yaml
spec:
  runtime:
    logLevel: debug
```

`logLevel` sets the provider's `LOG_LEVEL`. Debug logs are verbose; gate them behind a maintenance window.

## Performance tips

- **Hot-add disabled for latency-sensitive VMs**: hot-add CPU/memory adds a thin layer of indirection. For real-time / VoIP / HFT workloads, set `cpuHotAddEnabled: false` and `memoryHotAddEnabled: false`.
- **Eager-zeroed thick for IOPS-heavy disks**: trade space for predictable write latency.
- **pvscsi everywhere**: unless your guest is ancient, `pvscsi` outperforms the LSI variants for any sustained I/O.
- **Multiple SCSI controllers**: spread disks across controllers (`scsi.controller: 0`, `scsi.controller: 1`, ...) to parallelise queue depth.

## API reference

- Full CRD field reference: [Generated CRD docs](../references/generated-crd-docs.md).
- Provider gRPC contract: [Generated gRPC docs](../references/grpc-api.md).
- Capability matrix (all providers): [Capabilities](providers-capabilities.md).

## Support

- Documentation: [VirtRigaud Docs](https://projectbeskar.github.io/virtrigaud/)
- Issues: [GitHub Issues](https://github.com/projectbeskar/virtrigaud/issues), label `provider/vsphere`
- govmomi reference: [`vmware/govmomi`](https://github.com/vmware/govmomi)
