<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# vSphere Provider

The vSphere provider manages virtual machines on VMware vSphere (vCenter Server and standalone ESXi) via the `govmomi` SDK. It is the most mature provider in the VirtRigaud tree and powers production deployments.

This page is aligned to **VirtRigaud v0.3.8**. Capability claims trace back to the provider's `GetCapabilities` response in `internal/providers/vsphere/server.go`.

## Capabilities at a glance

The vSphere provider advertises the following via `GetCapabilities` (`internal/providers/vsphere/server.go:372-383`):

| Capability flag | Value | What it means |
|-----------------|-------|---------------|
| `SupportsReconfigureOnline` | true | Hot-add CPU / memory when the guest supports it; falls back to offline otherwise. |
| `SupportsDiskExpansionOnline` | true | Disks can be grown without powering off. |
| `SupportsSnapshots` | true | Standard vSphere snapshots (disk state + config). |
| `SupportsMemorySnapshots` | **false** | vSphere snapshots in this provider do **not** capture RAM state. Memory snapshots must be taken through vCenter directly. |
| `SupportsLinkedClones` | true | Delta-disk clones sharing a parent VMDK. |
| `SupportsImageImport` | true | OVF/OVA import + content library deploy. Direct URL-based cloud-image fetch is not yet implemented as of v0.3.8 — see the [capability matrix](providers-capabilities.md). |
| `SupportsDiskExport` | **true** | `ExportDisk` / `GetDiskInfo` (#178). Advertises export compression. |
| `SupportsDiskImport` | **true** | `ImportDisk` (#178). Feeds the cross-provider migration pipeline. |
| `SupportedDiskTypes` | `thin`, `thick`, `eager-zeroed` | Native VMDK provisioning modes. |
| `SupportedExportFormats` | `vmdk`, `qcow2`, `raw` | Disk export/import formats advertised by `GetCapabilities` as of v0.3.8 (#178); prior releases understated these. |
| `SupportedNetworkTypes` | `standard`, `distributed` | Standard vSwitch portgroups and Distributed Virtual Switch portgroups. |

!!! warning "Memory snapshots on vSphere"
    The matrix and prior docs incorrectly claimed memory snapshots worked. v0.3.6 docs are corrected: `SupportsMemorySnapshots=false` is the source of truth. Operators who need a memory-state snapshot must capture it through vCenter directly today.

For the full cross-provider matrix and resilience / observability story, see:

- [Provider capabilities matrix](providers-capabilities.md) — every capability across all providers.
- [Operations — Resilience](../operations/resilience.md) — the v0.3.6 CircuitBreaker wraps every outbound RPC to this provider.
- [Operations — Observability](../operations/observability.md) — metric families that surface vSphere-side state.

## RPC support

The provider implements the full gRPC contract (`proto/provider/v1/provider.proto`):

- **Validate** — connectivity + credential check against vCenter, with a live probe + session reconnect (see [Session resilience](#session-resilience-v038)).
- **Create** — clone from a template/VM **or** import disk via OVF/OVA.
- **Delete** — VM teardown with disk cleanup.
- **Power** — On / Off / Reboot / Shutdown-Graceful.
- **Describe** — current state, IPs (via VMware Tools), `ConsoleUrl`, raw vSphere properties.
- **Reconfigure** — CPU / memory / disk changes (hot when possible).
- **SnapshotCreate / SnapshotDelete / SnapshotRevert** — disk-only.
- **CloneCreate** — full or linked.
- **TaskStatus** — polls the underlying govmomi `Task` until terminal. Counts toward the `virtrigaud_provider_tasks_inflight` gauge.
- **ConsoleUrl** — vSphere web client URL with VM instance UUID.
- **ImagePrepare** — OVF/OVA import and content-library deploy.
- **ExportDisk / ImportDisk / GetDiskInfo** — disk export and import advertising `vmdk` / `qcow2` / `raw` plus export compression (#178). These back the cross-provider migration pipeline.

## Prerequisites

- vCenter Server **7.0+** or ESXi **7.0+**, reachable over HTTPS (port 443).
- A service account or API session token with rights for VM lifecycle, datastore, network, and resource management. See [Service account permissions](#service-account-permissions) below.
- TLS: a valid CA-issued cert for vCenter, or `insecureSkipVerify: true` during development.

## Authentication

The vSphere provider reads credentials from a Kubernetes Secret referenced via `Provider.spec.credentialSecretRef`. The provider controller mounts that Secret read-only at `/etc/virtrigaud/credentials` inside the provider pod. **The Secret keys are read as files** (`internal/providers/vsphere/server.go:129-140`), so the key names matter:

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
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.3.8"
    service:
      port: 9443
      tls:
        enabled: true
        secretRef:
          name: provider-vsphere-tls
        insecureSkipVerify: false
```

### Service account permissions

Create a dedicated vSphere user with these privileges:

- **Datastore**: AllocateSpace, Browse, FileManagement
- **Network**: Assign
- **Resource**: AssignVMToPool
- **Virtual machine**: full set (or a tailored subset covering Inventory, Interaction, Configuration, Provisioning, Snapshot management)
- **Global**: EnableMethods, DisableMethods, Licenses

## TLS / mTLS (v0.3.7+)

Starting in v0.3.7, the manager enforces that every Provider CR has a `spec.runtime.service.tls` block. A Provider without this block fails to reconcile and its status will show `TLSConfigured=False, Reason=TLSBlockMissing` — no Deployment is created.

For full mTLS details see [Security — mTLS](../providers/security/mtls.md).

### `spec.runtime.service.tls` fields

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | bool | Set `true` to enable mTLS. Set `false` for plaintext (dev/lab only; audit-flagged). |
| `secretRef.name` | string | Name of a `kubernetes.io/tls` or `Opaque` Secret containing `tls.crt`, `tls.key`, and `ca.crt`. |
| `insecureSkipVerify` | bool | Skip server certificate verification. Dev-only; never set in regulated environments. |

TLS material mounts at `/etc/virtrigaud/tls` inside the provider pod. Both manager and provider pin TLS 1.3. A missing Secret with `tls.enabled: true` sets `TLSConfigured=False, Reason=SecretRefMissing`.

The `TLSConfigured` status condition reasons are:

| Reason | Meaning |
|--------|---------|
| `TLSBlockMissing` | No `tls` block at all in the Provider CR. |
| `ExplicitlyDisabled` | `tls.enabled: false` — plaintext acknowledged. |
| `SecretRefMissing` | `tls.enabled: true` but `secretRef.name` not specified or Secret not found. |
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
| `https://192.168.1.10/sdk` | Direct IP, useful when DNS is the problem you are debugging |
| `https://esxi-01.example.com/sdk` | Standalone ESXi (single-host environments) |

The `Provider.spec.endpoint` is exposed to the provider pod as `PROVIDER_ENDPOINT`.

## Cloud-init on vSphere

vSphere does **not** use a NoCloud ISO. The provider injects cloud-init via VMware's `guestinfo` OVF properties (`internal/providers/vsphere/server.go:1321-1380`). The keys it sets are:

| Property | Value |
|----------|-------|
| `guestinfo.userdata` | base64-encoded user-data |
| `guestinfo.userdata.encoding` | `base64` |
| `guestinfo.metadata` | base64-encoded meta-data (or a sensible fallback) |
| `guestinfo.metadata.encoding` | `base64` |

The guest must have a recent cloud-init that supports the VMware datasource (Ubuntu cloud images and most distro cloud images do).

## Datastore selection (precedence)

VirtRigaud supports three ways to choose a datastore. Precedence is strict — higher entries win:

| Priority | Source | When it applies |
|----------|--------|-----------------|
| 1 (highest) | `VirtualMachine.spec.placement.datastore` | Explicit per-VM override |
| 2 | `VirtualMachine.spec.placement.storagePod` | Per-VM Datastore Cluster (StoragePod) |
| 3 | `PROVIDER_DEFAULT_STORAGE_POD` (or `Provider.spec.defaults.storagePod`) | Provider-level Datastore Cluster default |
| 4 (lowest) | `PROVIDER_DEFAULT_DATASTORE` (or `Provider.spec.defaults.datastore`) | Provider-level fixed-datastore default |

### StoragePod (Datastore Cluster) auto-selection

When a StoragePod is configured, the provider enumerates the cluster's member datastores via the vSphere API, retrieves the `FreeSpace` summary for each, and picks the member with the most free space (`internal/providers/vsphere/server.go:205-262`, `resolveDatastoreFromStoragePod`). This is a lightweight alternative to Storage DRS and does **not** require SDRS to be enabled.

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
    folder: "/vm/applications"
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
  # ... classRef, imageRef, networks, etc.
  placement:
    cluster: "Compute-Cluster"
    resourcePool: "Production"
    folder: "/vm/applications"
    storagePod: "DatastoreCluster-SSD"   # ignored if datastore: is set
    # datastore: "datastore-ssd"          # explicit override wins
```

## SCSI controller configuration (vSphere only)

v0.3.6 ships an explicit `SCSIControllerSpec` on each disk entry. It is vSphere-only — libvirt and proxmox ignore it. Reference: `api/infra.virtrigaud.io/v1beta1/virtualmachine_types.go:422-442`.

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

See [the full CRD reference](../references/generated-crd-docs.md#vmclass) for every field.

## VMImage

Reference vSphere templates, content library items, or OVF/OVA:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-22-04-template
spec:
  source:
    template: "ubuntu-22.04-template"
    folder: "/vm/templates"
  guestOS: "ubuntu64Guest"
```

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
  ipAllocation:
    type: Static
    address: "192.168.100.50/24"
    gateway: "192.168.100.1"
    dns: ["192.168.1.10", "8.8.8.8"]
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
  powerState: On
  disks:
    - name: data
      sizeGiB: 500
      type: thin
      scsi:
        controllerType: pvscsi
  networks:
    - name: app
      networkRef:
        name: app-network
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

## Async task tracking

vSphere operations that are long-running (clone, snapshot, reconfigure-with-large-disk-add) return a `govmomi.Task` reference. VirtRigaud wraps that as a proto `TaskRef` in the gRPC response and the manager polls `TaskStatus` until terminal.

Since v0.3.6, every in-flight task is counted by the `virtrigaud_provider_tasks_inflight{provider_type="vsphere", provider="<name>"}` gauge (G7.3 / PR #130). The gauge is seeded to `0` at boot so it appears on `/metrics` from the first scrape; useful for catching stuck tasks. See [Observability](../operations/observability.md#11-virtrigaud_provider_tasks_inflight).

## Session resilience (v0.3.8)

As of v0.3.8 (#190), the vSphere provider keeps its vCenter session alive and recovers from long idle periods automatically:

- A **keepalive** runs against the govmomi session so it does not lapse during quiet periods.
- **`Validate` performs a live probe** of the session and **reconnects** if the session has gone stale.

The practical effect: a provider pod that has been idle for hours (overnight, between batch runs) no longer fails its next RPC with a `NotAuthenticated` / `session is not authenticated` error and then has to be restarted. The breaker stays closed across idle windows.

If you previously worked around stale sessions with a periodic provider-pod restart (CronJob, etc.), you can drop that workaround on v0.3.8.

## Console access

`Describe` populates `status.consoleURL` with a vSphere web client deep link that includes the VM's instance UUID. Open it in a browser; vCenter prompts for authentication and lands you on the VM's summary tab.

```bash
kubectl get vm web-application -n my-app -o jsonpath='{.status.consoleURL}'
# https://vcenter.example.com/ui/app/vm;nav=h/urn:vmomi:VirtualMachine:vm-123:xxxxx/summary
```

## Multi-vCenter

Deploy one `Provider` CR per vCenter. Each gets its own provider pod, its own gRPC port, and its own CircuitBreaker series in metrics:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: vsphere-dc-a
spec:
  type: vsphere
  endpoint: https://vcenter-a.example.com/sdk
  credentialSecretRef:
    name: vsphere-credentials-a
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: vsphere-dc-b
spec:
  type: vsphere
  endpoint: https://vcenter-b.example.com/sdk
  credentialSecretRef:
    name: vsphere-credentials-b
```

## Troubleshooting

### CircuitBreaker open for the vSphere provider

Check `/metrics`:

```promql
virtrigaud_circuit_breaker_state{provider_type="vsphere", provider="vsphere-prod"} == 2
```

When this fires, the manager has fast-failed enough RPCs to the vCenter that it has opened the breaker (default 5 consecutive failures with 30s reset; see [Resilience](../operations/resilience.md#circuitbreaker-on-the-provider-grpc-path-v036)). Investigate the underlying vCenter — credentials, certificate, network — rather than restarting the manager.

### "Invalid configuration for device '0'" on disk attach

Older releases hit this when a StoragePod-resolved datastore was reattached to additional disks; the returned `object.Datastore` was missing its inventory path. Fixed in v0.3.3 by routing through `p.finder.Datastore(ctx, best.Name)`. Upgrade.

### "Login failed: incorrect user name or password"

The username in `Provider.spec.credentialSecretRef` Secret must match the **principal name** expected by vCenter — usually `user@vsphere.local`, not bare `user`. Also check whether the user is locked out via Single Sign-On.

### `NotAuthenticated` after a long idle period

On releases before v0.3.8 the govmomi session could lapse during long idle windows, and the next RPC would fail with `NotAuthenticated` / `session is not authenticated` until the provider pod was restarted. v0.3.8 (#190) adds a session keepalive and a live-probe reconnect in `Validate`, so the session self-heals. If you still see this, upgrade to v0.3.8 and confirm the provider image tag is `:v0.3.8`. See [Session resilience](#session-resilience-v038).

### Template not found

The `VMImage.spec.source.template` value is resolved via the `govmomi` finder. List templates with:

```bash
govc ls /Datacenter/vm/templates/
```

If the template lives in a sub-folder, set `VMImage.spec.source.folder` to the inventory path of the parent folder.

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
# in Provider.spec.runtime
runtime:
  logLevel: debug
  env:
    - name: GOVMOMI_DEBUG
      value: "true"
```

`GOVMOMI_DEBUG=true` dumps every SOAP/REST exchange against vCenter — useful for diagnosing permission errors and unexpected task failures, but verbose; gate it behind a maintenance window.

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
- Issues: [GitHub Issues](https://github.com/projectbeskar/virtrigaud/issues) — label `provider/vsphere`
- govmomi reference: [`vmware/govmomi`](https://github.com/vmware/govmomi)
