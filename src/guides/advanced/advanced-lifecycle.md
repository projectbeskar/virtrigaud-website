<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Advanced VM Lifecycle Management

This page describes how a `VirtualMachine` moves through its lifecycle in VirtRigaud **v0.4.0** beyond create and delete: phases and conditions, reconfiguration, snapshots and snapshot revert, cloning, image preparation, detaching and adopting VMs, and the resources that are not (or only partly) functional.

## What is functional in v0.4.0

| Area | Status in v0.4.0 |
|------|------------------|
| `status.phase` | Set on every status write of the VirtualMachine controller ([phases](#phases)) |
| Reconfiguration (CPU, memory, disk growth) | Functional; result is one of *applied*, *restart required* or *failed* ([details](#reconfiguration)) |
| Snapshots (`VMSnapshot`) | Functional, subject to provider support; `maxAge` and `deleteOnVMDelete` retention are enforced ([details](#snapshot-management)) |
| Snapshot revert (`spec.snapshot.revertToRef`) | Functional in v0.4.0 (v0.3.11 accepted the field and ignored it); run in the lab on vSphere, Proxmox and libvirt (single-host and clustered) ([details](#reverting-to-a-snapshot)) |
| `VMClone` | Functional: `source.vmRef` only, same provider ([VM cloning](vm-cloning.md)) |
| Image preparation (`VMImage.spec.prepare`) | Functional, lazily on first VM create ([details](#image-preparation)) |
| VM adoption, `orphan-on-delete` | Functional ([details](#detaching-and-adopting-vms)) |
| `spec.lifecycle` hooks (`preStop`, `postStart`) | **Accepted by the API, not executed.** See [Lifecycle hooks](#lifecycle-hooks) |
| `VMSet` | **No controller.** A `VMSet` reports `Ready=False` / `ControllerNotImplemented` |
| `VMPlacementPolicy` | Used by the scheduler of **clustered libvirt** Providers only. Not enforced for single-host, vSphere or Proxmox Providers |

## Phases

`kubectl get vm` shows `status.phase` in its `PHASE` column. The manager derives it from the rest of the status on every status write, so it is never empty on a VM the manager reconciles and never disagrees with the conditions. Do not set it by hand. The [VM status reference](../vm-status.md) lists every phase, condition and reason.

| Phase | Meaning |
|-------|---------|
| `Pending` | Not created. The VM waits for its Provider, class, image, a placement, or the controller that binds it (adoption). Also a clustered VM held by a restore guard (`RestorePending`, `OwnDomainOnAnotherHost`, `UniquenessCheckFailed`, `ProviderLacksListOwnerFilter`): it waits and proceeds once the cause is gone |
| `Provisioning` | Being created: a `Create` is requested, a task is recorded, a clustered host was chosen for it, or it was created and has not been described yet |
| `Running` | Created and the provider reports it `On`. A suspended VM still reports `Running`, with `Ready=False` / `PowerStateUnmanaged` |
| `Stopped` | Created and the provider reports it `Off` |
| `Reconfiguring` | A resize is in flight, or an asynchronous power task runs. A resize applied only to the persistent definition (`RestartRequired`) leaves the phase to the power state |
| `Deleting` | The VM has a deletion timestamp, including while the delete is held |
| `Failed` | A hold that needs an operator (`VMNotOwned`, `OwnerStampUnreadable`, `ProviderUnavailable`, `VMIsImageArtifact`, `CreateOutcomeUnknown`, `DeleteBlocked`, `ProviderRefMismatch`, `PlacementTopologyMismatch`, `ConsumerNotAllowed`, `VMMissingOnHost`), a create that was refused (`CreateBackoff`, `CreateRefused`, `ProviderConflict`, `ValidationError`), or a power state the provider cannot classify |

A transient provider error (`Ready=False` / `ProviderError`) on a VM that exists does not change the phase, and neither does a snapshot revert: the phase follows the power state. The full rule is in [`vm-status-phase.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-status-phase.md).

### Conditions

| Condition | Meaning |
|-----------|---------|
| `Ready` | The VM is usable. When `False`, its reason says why (for example `ProviderError`, `PowerStateUnmanaged`, `DeleteBlocked`, `ConsumerNotAllowed`) |
| `Provisioning` | The create is in flight or waiting (`WaitingForDependencies`, `CreateRequested`, ...) |
| `Reconfiguring` | A resize is in flight (`Updating`), pending a restart (`RestartRequired`), or settled (`ReconcileSuccess`); failure reasons include `ProviderError`, `ResizePendingPowerOff`, `ProviderLacksHonestReconfigure` |
| `Deleting` | The delete is in progress |
| `SnapshotReverted` | Present only while `spec.snapshot.revertToRef` is set ([below](#reverting-to-a-snapshot)) |
| `DisksApplied` | `False` / `NotSupportedByProvider` when `spec.disks` is set on a libvirt or Proxmox Provider ([below](#additional-disks-specdisks)) |
| `Placed`, `DeleteBlocked`, `ForceDeleteRefused` | Clustered libvirt Providers: placement, a held delete, and a refused force-delete ([clustered guide](../clustered/index.md)) |
| `LinkedClonesDependOnDisk` | libvirt: other VMs use this VM's disk as a backing file (linked clones made by an earlier release); see [VM cloning](vm-cloning.md#linked-clones-and-the-source-vm) |

## Lifecycle hooks

`spec.lifecycle` accepts `preStop`, `postStart` and `gracefulShutdownTimeout`, with the actions `exec`, `httpGet` and `snapshot`:

```yaml
spec:
  lifecycle:
    gracefulShutdownTimeout: "120s"
    postStart:
      httpGet: {host: cmdb.example.com, port: 8080, path: /api/vm/register}
    preStop:
      snapshot: {name: pre-shutdown, includeMemory: false}
```

!!! warning "The hooks are not executed in v0.4.0"
    The CRD stores these fields, but no controller or provider reads them: a `preStop` action does not run before a power-off, a `postStart` action does not run after a power-on, and `gracefulShutdownTimeout` is not passed to the provider. The manager always sends a graceful-shutdown timeout of 60 seconds (`internal/transport/grpc/client.go`). Do not rely on these fields; take a snapshot with a `VMSnapshot` and run guest-side commands with cloud-init or your own tooling. See [Graceful shutdown](graceful-shutdown.md) for what `OffGraceful` does.

## Reconfiguration

A change to the effective CPU or memory (the VMClass values with any `spec.resources` override applied) makes the manager send a `Reconfigure` to the provider. A `Reconfigure` has exactly three outcomes, and a provider never reports success for a change it did not apply:

| Outcome | What the manager records |
|---------|--------------------------|
| **Applied**: every change applied to the running VM and to its persistent definition (or to the definition a stopped VM boots from) | `status.currentResources` = the new size; `Reconfiguring=False`, reason `ReconcileSuccess` |
| **Restart required**: at least one change reached the persistent definition only, because the running VM cannot take it. It takes effect at the next power cycle (power off, then on; a reboot from inside the guest is not enough) | `Reconfiguring=True`, reason `RestartRequired`. The manager asks again every 2 minutes and clears the condition once the VM has been power cycled |
| **Failed**: the change could be applied neither way, or the provider could not tell | `Reconfiguring=False`, reason `ProviderError`, with a message; retried on a per-VM backoff (5 s doubling to 5 min) |

```bash
# Resize by changing the class, or override with spec.resources
kubectl patch vm web-server --type merge \
  -p '{"spec":{"resources":{"cpu":4,"memoryMiB":8192}}}'
kubectl get vm web-server -o jsonpath='{.status.conditions[?(@.type=="Reconfiguring")]}{"\n"}'
```

The manager **never powers a VM off by itself** to apply a resize. If a change needs the VM off, set `spec.powerState: Off`, wait for the resize, then set `On` again.

!!! note "A disk-size change alone does not trigger a Reconfigure"
    The manager sends a `Reconfigure` when the effective CPU or memory changes; disk sizes travel with it. To apply a `spec.disks` size change, or a growth that was skipped earlier, the VM's CPU or memory must change too (known limitation).

### Per provider

| Provider | Behaviour |
|----------|-----------|
| **vSphere** | One `ReconfigVM_Task`. A powered-on VM takes a CPU change only with CPU hot-add (more vCPUs) or hot-remove (fewer) enabled, and memory only upwards with memory hot-add within the hot-plug limit. vSphere has no pending state, so a change the running VM cannot take is **refused before anything changes**: `Reconfiguring=False`, reason `ResizePendingPowerOff` (wire reason `RECONFIGURE_NEEDS_POWER_OFF`, not counted by the circuit breaker); the VM stays `Ready`. Set `spec.powerState: Off` to apply it. A CPU count that is not a multiple of the cores per socket is refused (`InvalidSpec`). To resize running VMs, enable hot-add: VMClass `performanceProfile.cpuHotAddEnabled` / `memoryHotAddEnabled` for new VMs, or in vCenter while the VM is off. `Reconfigure` never touches the root disk |
| **libvirt** | Changes the persistent definition first (`--config`), then the running domain (`--live`). A grow within the headroom provisioned at create time (VMClass hot-add flags, ceiling min(4x initial, 64) vCPUs, 4x memory) is applied live; anything else, and every memory **shrink** of a running VM, is *restart required*. The primary disk grows live (`blockresize`, grow-only; a best-effort in-guest filesystem grow needs the guest agent). A domain that is paused, suspended, shutting down or in an unknown state is refused with a retryable error before anything changes |
| **Proxmox** | Reports `restart_required: false`. A CPU or memory change that PVE stores as *pending* (hot-plug not enabled for it) is currently reported as applied; detecting it is a follow-up. Validated against an in-repo PVE fake for this path, not a real PVE |

Clustered libvirt Providers additionally hold a running VM's **shrink** until the VM is powered off (`ShrinkPendingPowerOff`) and refuse to resize anything while the Provider lacks the honest-reconfigure capability (`ProviderLacksHonestReconfigure`). `status.currentResources` always records, per resource, the larger of the size the VM runs with and the size it boots with next. The full contract is in [`reconfigure-results.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/reconfigure-results.md).

### Power states

`spec.powerState` is `On`, `Off` (hard) or `OffGraceful` (guest shutdown through guest tools with a fallback to hard power-off; see [Graceful shutdown](graceful-shutdown.md)). The observed `status.powerState` can also be `Suspended` (a paused or suspended-to-RAM libvirt domain) or `Unknown`. While a VM is `Suspended` or `Unknown` the manager neither powers it on nor reconfigures it (`Ready=False`, reason `PowerStateUnmanaged`); a suspended VM whose spec says `Off` is powered off, and one whose spec says `OffGraceful` is held with a message asking for a hard `Off`.

A power operation that returns a task (Proxmox) shows `Reconfiguring=True` with the message `Adjusting power state` while the task runs, and a failed power task is retried on a 5 s to 5 min backoff (`Reconfiguring=False`, reason `PowerTaskFailed`).

### Additional disks (`spec.disks`)

`spec.disks` entries are attached by the **vSphere** provider at create time. The **libvirt and Proxmox providers attach no `spec.disks`**. A VirtualMachine with a non-empty `spec.disks` on such a Provider is not refused, but reports:

- `DisksApplied=False`, reason `NotSupportedByProvider`, with the number of entries and the Provider type (it never becomes `True` and does not change `Ready`);
- a `Warning` event with the same reason, once per `metadata.generation`;
- an admission warning from the VirtualMachine webhook, where the chart renders it (`webhooks.enabled=true` and a disk-size limit set).

On vSphere, a size change of an additional disk grows the disk `Create` attached for that entry (found by the name recorded in the VM's ExtraConfig); a smaller size is refused, and a disk is never shrunk. The VMClass `spec.diskDefaults.size` of the root disk is applied at create (and, on libvirt, grown by `Reconfigure`), not by vSphere's `Reconfigure`.

## Snapshot management

This section is a summary. The full guide, with the per-provider rules, the unknown-outcome handling and the upgrade caveat, is [VM snapshots and revert](../vm-snapshots.md).

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMSnapshot
metadata:
  name: pre-maintenance-backup
  namespace: default
spec:
  vmRef:
    name: web-server
  snapshotConfig:
    name: "maintenance-backup"     # a name hint; the provider may change it
    includeMemory: true
    description: "Backup before maintenance"
  retentionPolicy:
    maxAge: "720h"
    deleteOnVMDelete: true
```

- `status.phase` goes `Pending`, `Creating`, `Ready` (or `Failed`), then `Deleting` / `Expired`. The controller never reports a snapshot `Ready` without a `SnapshotCreate` call that the provider answered.
- `status.snapshotID` is the provider's id; `status.vmUID` and `status.boundProvider` record which VM (UID) and Provider the snapshot was taken through. A snapshot is deleted, retained or reverted to only through that same VM and Provider.
- **Retention:** `retentionPolicy.maxAge` and `deleteOnVMDelete` are enforced (checked about hourly). `maxCount` and `spec.schedule` are accepted by the API but are **not** acted on: create one `VMSnapshot` per snapshot, for example from a CronJob that renders a fresh name per run (`snapshotConfig.name` accepts only a literal string).
- A refused or failed provider delete **keeps the finalizer**: the `VMSnapshot` stays, `Ready=False` with reason `DeleteBlocked` (the provider refused for a reason that needs an action, for example libvirt below) or `ProviderError`, and the delete is retried with a growing delay (15 s to 5 min). `virtrigaud.io/force-delete: "true"` removes the object and leaves the snapshot on the hypervisor (a `SnapshotLeftOnHypervisor` warning event names it).

### Provider notes

- **vSphere** supports memory snapshots (they need the VM powered on). `snapshotConfig.quiesce` is accepted but not passed on: the vSphere provider always takes the snapshot without quiescing the guest file system.
- **libvirt:** a snapshot of a powered-off VM, or without memory, is an external disk-only snapshot; a memory snapshot of a running VM is internal. `SnapshotCreate` of a **powered-off** VM briefly ejects the CD-ROMs (including the cloud-init seed) so the snapshot does not store them; a running VM is never ejected.
- **libvirt, delete order with memory snapshots:** a memory snapshot taken after a disk-only snapshot is stored inside the disk-only snapshot's overlay. Deleting the disk-only snapshot first would destroy the memory snapshot's data, so in v0.4.0 the provider refuses (`DeleteBlocked`, naming the snapshots to delete first). **Delete the memory snapshots first, then the disk-only one.**
- **libvirt:** while another domain uses the VM's disk (a linked clone made by an earlier release), snapshot create, delete and revert of that VM are refused (`VM_DISK_IN_USE`).
- **Proxmox:** a snapshot revert is owner-checked and returns a task, which the manager polls.

See [libvirt clones and the linked-clone dependency](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/libvirt-clones.md#deleting-memory-and-disk-only-snapshots-of-the-same-vm) for the delete rules and the manual cleanup of a memory snapshot whose data an earlier release already destroyed.

### Reverting to a snapshot

`spec.snapshot.revertToRef` on the `VirtualMachine` reverts it to a `VMSnapshot`. In v0.3.11 the field was accepted and ignored; in v0.4.0 the controller acts on it.

1. Power the VM off. VirtRigaud never powers a VM off for a revert:

    ```bash
    kubectl patch vm web-server --type merge -p '{"spec":{"powerState":"Off"}}'
    ```

2. Name the snapshot. It must be `Ready` and taken of this VM through this VM's Provider:

    ```bash
    kubectl patch vm web-server --type merge \
      -p '{"spec":{"snapshot":{"revertToRef":{"name":"pre-maintenance-backup"}}}}'
    ```

3. Watch `status.snapshotRevert.phase` (`Pending`, `Reverting`, `Succeeded`, `Failed`) and the `SnapshotReverted` condition (`True` / `Reverted`, or `False` with the reason `WaitingForPowerOff`, `SnapshotNotFound`, `SnapshotNotReady`, `SnapshotForAnotherVM`, `Unsupported`, `Reverting`, `RevertFailed`). While `SnapshotReverted` is `False`, `Ready` is `False` with the same reason. Events: `SnapshotRevertStarted`, `SnapshotRevertSucceeded`, `SnapshotRevertFailed`.
4. Power the VM on again if you want it running. The revert does not (a snapshot taken with memory can leave a VM running; a spec that still says `Off` powers it off again).

Rules:

- **Once per request.** While `status.snapshotRevert` records `Succeeded` or `Failed` for the named `VMSnapshot` (same UID), nothing is sent again, so a manifest that keeps `revertToRef` set is safe to re-apply. To revert to the same snapshot again, remove the field, wait for `status.snapshotRevert` to disappear, then set it again. Naming another `VMSnapshot`, or one re-created under the same name, is a new request.
- **A failed revert is not retried by itself.** Remove the field and set it again, except for a refusal the provider repeats every time (`FailedPrecondition`), whose message says what to do instead.
- **Unknown outcomes** (a lost answer, a clustered host that stopped answering) are re-sent on a backoff (no sooner than 6 minutes, up to 5 calls) only while the VM is still seen `Off`; otherwise the revert ends `Failed` with a message that the VM may or may not have been reverted. A revert task that has not ended after 2 hours also ends `Failed`.
- **GitOps:** a `VirtualMachine` re-created from the same manifest is a new VM; the field then names a snapshot of the old VM and is refused (`SnapshotForAnotherVM`). Do not keep `revertToRef` in Git after the revert if VMs are re-created from it.
- **libvirt:** a revert needs a snapshot that does not store the cloud-init CD-ROM. A disk-only snapshot taken while the VM was **running**, or by v0.3.11 or earlier, is refused with `RevertFailed` and nothing changes: take the snapshot with the VM powered off. libvirt 9.9 or later is needed for external snapshots.
- `status.currentResources` is not changed by a revert.

!!! note "Validation status"
    The revert flow is covered by controller unit and envtest tests that drive a scripted provider fake, and was run in the lab on vSphere, on Proxmox and on libvirt (single-host and clustered; the libvirt run found the cloud-init CD-ROM problem described above, which v0.4.0 handles). Other versions of those hypervisors are untested. Read [`vm-snapshot-revert.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-snapshot-revert.md) before relying on it.

## Cloning

`VMClone` clones an existing, provisioned `VirtualMachine` on the same provider. The scope, per-provider behaviour (libvirt full clones need the source powered off; libvirt linked clones are disabled), clone identity and cross-namespace targets are in **[VM cloning](vm-cloning.md)**.

## Image preparation

A `VMImage` describes where an image comes from. For providers that import images (libvirt URL sources, vSphere OVA/OVF URL sources), the VirtualMachine controller prepares the image **lazily, right before the first create**, and only when the Provider advertises `status.reportedCapabilities.supportsImageImport`; otherwise the VM is created by reference and preparation is skipped. Proxmox clones a template that already exists (`source.proxmox.templateID`); its URL import (`source.http`) is not supported in v0.4.0 and is refused with `InvalidSource`. Example: [`vmimage-prepare-on-create.yaml`](../../examples/vmimage-prepare-on-create.yaml).

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-jammy-cloud
spec:
  source:
    libvirt:
      url: "https://images.example.com/ubuntu/jammy-server-cloudimg-amd64.qcow2"
      format: qcow2
      checksum: "sha256:REPLACE_WITH_REAL_SHA256"
      checksumType: sha256
  prepare:
    onMissing: Import         # Import (default) | Fail | Wait
    validateChecksum: true
```

- `spec.prepare.onMissing`: `Import` prepares the image on the Provider; `Fail` and `Wait` never prepare and hold the VM until the image is prepared out of band.
- Prepare state is recorded **per Provider** in `status.providerStatus["<namespace>/<name>"]` and `status.availableOn`; a VM consults only the entry of the Provider it uses. `status.phase` is one of `Pending`, `Downloading`, `Importing`, `Converting`, `Optimizing`, `Ready`, `Failed`.
- Prepared images carry an identity stamp (ADR-0009): a prepared image is reused only if it was stamped for the same `spec.source`; a provider that imports images but does not report artifact identity is held. libvirt image paths (`source.libvirt.path`) must resolve to a regular file directly inside an allowed image directory (`VIRTRIGAUD_LIBVIRT_IMAGE_DIRS`, default `/var/lib/libvirt/images`).
- Reference: [`image-preparation.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/image-preparation.md).

## IP addresses (`status.ips`)

`status.ips` is shown in the `IPs` column. The manager filters every provider's answer the same way: loopback, unspecified, IPv4 and IPv6 link-local and multicast addresses are dropped; private, unique-local and global addresses are kept, in canonical form and in the provider's order. The list is empty while the provider has no reachable address.

| Provider | Source |
|----------|--------|
| vSphere | VMware Tools (`guest.ipAddress`, `guest.net`) |
| Proxmox | QEMU guest agent (`network-get-interfaces`) |
| libvirt | The guest agent, with `virsh domifaddr` (`--source agent`, then `lease`, then `arp`) as the fallback |

On libvirt, a guest on libvirt's NAT `default` network shows its DHCP lease without the guest agent. A guest on a **host bridge** (`VMNetworkAttachment` `spec.network.libvirt.bridge`) has no libvirt lease: its address shows only if the QEMU guest agent runs in the guest (or the host happens to hold an ARP entry for the guest's MAC). The cloud-init the provider injects by default installs and starts `qemu-guest-agent`; an image or `spec.userData` that does not has none. In v0.3.11, libvirt listed loopback and link-local addresses and dropped lease rows; tooling that took `status.ips[0]` should expect the filtered list. Reference: [`vm-status-ips.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-status-ips.md).

## Detaching and adopting VMs

### `spec.providerRef` is immutable once bound

Once a VM is bound to a hypervisor VM (`status.id`, or a clustered `status.placement.pendingHost`, is set), `spec.providerRef` can no longer be changed: the API server rejects the update (a CEL rule on the CRD). Before binding it stays editable, for example to fix a typo after a failed create. The operator also records the Provider it bound through in `status.boundProvider` and makes no provider call for the VM unless `spec.providerRef` still resolves to it; a mismatch shows `Ready=False` / `ProviderRefMismatch`. See [`vm-provider-binding.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-provider-binding.md).

### Stop managing a VM without destroying it

Re-pointing `providerRef` at a missing Provider no longer works. Use the `orphan-on-delete` annotation, then delete the VirtualMachine:

```bash
kubectl annotate virtualmachine legacy-db -n default virtrigaud.io/orphan-on-delete=true
kubectl delete virtualmachine legacy-db -n default
```

The finalizer is removed **without any provider call**; the hypervisor VM, its disks and any owner stamp are left untouched, and a `Normal` event `Orphaned` names what was left. Only the value `"true"` counts. A VM in another namespace than its **clustered** Provider is detached only if the Provider carries `infra.virtrigaud.io/allow-consumer-orphan-on-delete: "true"`; otherwise the delete is held with `Ready=False` / `OrphanOnDeleteNotAllowed`.

`virtrigaud.io/force-delete: "true"` is the escape hatch for a delete that keeps failing (an unreachable Provider, for example): it also removes the finalizer without a confirmed delete, and records a `VMLeftOnHypervisor` warning event. The same permission gate applies to consumers of a clustered Provider (`ForceDeleteRefused` / `ForceDeleteNotAllowed`).

### A held delete

If the provider refuses to delete a VM because other domains depend on its disk (a libvirt linked clone), or a clustered host cannot be reached, the VirtualMachine keeps its finalizer with `Ready=False` and reason `DeleteBlocked` and a `Warning` event; it is re-checked every minute (clustered VMs also carry a `DeleteBlocked` condition) and completes on its own once the cause is gone.

### Adoption

Adoption brings existing hypervisor VMs under management. It is a controller in the manager, not a CRD, triggered by annotations on the **Provider**: `virtrigaud.io/adopt-vms: "true"`, an optional `virtrigaud.io/adopt-filter` (JSON with `namePattern`, `powerState`, `minCPU`, `minMemoryMiB`, ...) and, on a single-host Provider, `virtrigaud.io/adopt-stamped-vms: "true"` to take VMs whose owner stamp names only VirtualMachines that are not in this cluster. Creating a VirtualMachine whose name matches an existing hypervisor VM does **not** bind to it: the provider binds only a VM stamped with that VirtualMachine's own UID, and otherwise the create fails with `Ready=False` / `ProviderConflict`. An adopted VM is stamped with its new VirtualMachine before it is bound. See [`vm-adoption-example.yaml`](../../examples/vm-adoption-example.yaml) and [`vm-ownership.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-ownership.md).

## Placement and sets

!!! warning "VMSet has no controller"
    `VMSet` is accepted by the API server, but its controller is a stub: it reports `Ready=False` with reason `ControllerNotImplemented` and manages no replicas. Manage individual `VirtualMachine` resources, optionally created with [VMClone](vm-cloning.md).

**VMPlacementPolicy.** Attach a policy with `spec.placementRef`. It is **used by the scheduler of clustered libvirt Providers** (`topology: cluster`) as its input: hard host filters (`hard.hosts`, `hard.excludedHosts`, `hard.nodeSelector`, resource constraints, strict host and VM (anti-)affinity) and soft scores. A `placementRef` that names a missing policy leaves the VM `Provisioning=False` with reason `PlacementPolicyNotFound`. The vSphere-style constructs (`clusters`, `datastores`, `folders`, `resourcePools`, zone and datastore anti-affinity) are documented as deferred and **not enforced**, and a policy attached to a single-host, vSphere or Proxmox VM is not enforced at all. See the [clustered libvirt guide](../clustered/index.md).

## Provider capabilities

The manager records what each provider reports under `Provider.status.reportedCapabilities`:

```bash
kubectl get provider vsphere-prod -o jsonpath='{.status.reportedCapabilities}{"\n"}'
```

The fields include `supportsReconfigureOnline`, `supportsDiskExpansionOnline`, `supportsSnapshots`, `supportsMemorySnapshots`, `supportsLinkedClones`, `supportsImageImport`, `supportedDiskTypes`, `supportedNetworkTypes`, and the disk export/import fields used by migration. An opt-in `--enforce-provider-capabilities` manager flag (default off) makes the manager refuse operations a provider does not advertise; the linked-clone gate and the snapshot-revert `Unsupported` check do not depend on it. The per-provider matrix is in the [Provider capabilities matrix](../../providers/providers-capabilities.md).

## Observability

Metrics, from `internal/obs/metrics` (see [Observability](../../operations/observability.md)):

| Metric | Use |
|--------|-----|
| `virtrigaud_vm_operations_total{operation,provider_type,provider,outcome}` | VM operations by outcome |
| `virtrigaud_provider_rpc_requests_total`, `virtrigaud_provider_rpc_latency_seconds` | Provider RPCs by method and code |
| `virtrigaud_provider_tasks_inflight` | Asynchronous provider tasks in flight |
| `virtrigaud_errors_total{reason,component}` | Controller errors by reason (for example `provider-ref-mismatch`, `force-delete-not-allowed`) |
| `virtrigaud_ip_discovery_duration_seconds` | Time until a VM shows an address |

Events you will see on a VM: `SnapshotRevertStarted`, `SnapshotRevertSucceeded`, `SnapshotRevertFailed`, `Orphaned`, `VMLeftOnHypervisor`, `DeleteBlocked`, `NotSupportedByProvider`, `ProviderRefMismatch`, `ConsumerNotAllowed`, `CreateOutcomeUnknown`. On a `VMSnapshot`: `SnapshotReady`, `SnapshotFailed`, `SnapshotDeleting`, `SnapshotDeleted`, `SnapshotDeleteFailed`.

## Best practices

- **Snapshots:** set a `maxAge`, use memory snapshots sparingly, take libvirt snapshots you may want to revert to with the VM powered off, and test the revert procedure before you need it.
- **Reconfiguration:** make incremental changes, enable hot-add in the VMClass for VMs that must resize without a restart, and take a snapshot before a major change.
- **Calls whose outcome is unknown:** when a provider call's answer is lost, the manager holds the object (`CreateOutcomeUnknown`, `CloneOutcomeUnknown`) instead of repeating a call that could duplicate a VM. See [`provider-call-outcomes.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/provider-call-outcomes.md).

## Troubleshooting

| Symptom | Where to look |
|---------|---------------|
| VM `Ready=False` | `kubectl get vm <name> -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'` |
| Resize does nothing on vSphere | `Reconfiguring=False` / `ResizePendingPowerOff`: enable hot-add or power the VM off |
| Resize pending on libvirt | `Reconfiguring=True` / `RestartRequired`: power cycle the VM (off, then on) |
| `spec.disks` has no effect | `DisksApplied=False` / `NotSupportedByProvider`: libvirt and Proxmox attach no `spec.disks` |
| Revert does nothing | `SnapshotReverted` reason: usually `WaitingForPowerOff` (set `spec.powerState: Off`) |
| Snapshot delete stuck | `kubectl describe vmsnapshot <name>`: `DeleteBlocked` message names what to delete first (libvirt memory snapshots) |
| VM delete stuck | `Ready=False` / `DeleteBlocked`, or `ProviderUnavailable`: fix the cause, or use `orphan-on-delete` / `force-delete` knowing the hypervisor VM is left behind |
| Empty `IPs` | Guest agent or VMware Tools not running; libvirt bridge networks need the guest agent |

```bash
kubectl describe vm web-server
kubectl get vmsnapshots -w
kubectl describe vmclone web-server-clone
kubectl get events --field-selector involvedObject.name=web-server
```
