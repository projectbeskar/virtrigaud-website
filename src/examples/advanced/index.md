<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Advanced VirtRigaud Examples

These examples cover the operations beyond creating a VM: snapshots and reverting to them, reconfiguration, cloning, console access and task tracking. They mirror `examples/advanced/` of the repository at **v0.4.0** and are valid against the v0.4.0 CRDs. For the behaviour behind them see [Advanced VM lifecycle](../../guides/advanced/advanced-lifecycle.md) and [VM cloning](../../guides/advanced/vm-cloning.md).

!!! note "Placeholders"
    Endpoints, Secret names, datastores and templates are placeholders. Each Provider in these files has the `runtime.service.tls` block that v0.4.0 requires (see [the examples index](../index.md#read-this-before-applying-an-example)); create the TLS Secret it names or set `enabled: false` in a lab.

| File | What it shows |
|------|---------------|
| [snapshot-lifecycle.yaml](snapshot-lifecycle.yaml) | `VMSnapshot` objects with retention policies, a weekly-backup pattern, how to revert a VM to a snapshot with `spec.snapshot.revertToRef`, and a CronJob for snapshot cleanup |
| [vm-reconfigure-and-snapshot.yaml](vm-reconfigure-and-snapshot.yaml) | A VMClass with hot-add enabled, a VM, a snapshot before a resize, a `VMPlacementPolicy`, a `VMClone` and a `VMSet` (the policy only matters to clustered libvirt Providers, and `VMSet` has no controller) |
| [vm-reconfigure-patch.yaml](vm-reconfigure-patch.yaml) | A resize applied with `kubectl patch`, and the libvirt hot-add and disk-grow rules |
| [vsphere-clone-example.yaml](vsphere-clone-example.yaml) | Several VMs created from one vSphere template, and a `VMClone` of an existing VM |
| [proxmox-clone-example.yaml](proxmox-clone-example.yaml) | Full and linked `VMClone` objects on Proxmox VE |
| [vsphere-task-tracking.yaml](vsphere-task-tracking.yaml) | Following long-running vSphere operations (a large create, a reconfigure) through the VM's phase, conditions, events and the provider log |
| [console-access-example.yaml](console-access-example.yaml) | `status.consoleURL`: a vSphere Client link for a vSphere VM, and a loopback-only VNC URL (reach it through an SSH tunnel) for a libvirt VM |

For `VMClone` without a Provider around it, see [`vmclone-basic.yaml`](../vmclone-basic.yaml) in the main examples.

## Snapshots and revert

[snapshot-lifecycle.yaml](snapshot-lifecycle.yaml) takes three snapshots of one VM (with memory, disk-only, and a long-retention weekly one) and documents the revert procedure as comments:

1. Power the VM off with `spec.powerState: "Off"`. VirtRigaud never powers a VM off for a revert: until the provider reports the VM `Off` and `spec.powerState` is `Off` or `OffGraceful`, nothing is sent and the VM shows `SnapshotReverted=False` with reason `WaitingForPowerOff`.
2. Name the snapshot in `spec.snapshot.revertToRef.name`. It must be `Ready`, taken of this VM through the VM's Provider.
3. Watch `status.snapshotRevert.phase` (`Reverting`, then `Succeeded` or `Failed`) and the `SnapshotReverted` condition.
4. Power the VM on again if you want it running; the revert does not.

```yaml
spec:
  powerState: "Off"
  snapshot:
    revertToRef:
      name: web-server-01-pre-update
```

The revert is sent at most once per request. Libvirt has additional rules (a revert needs a snapshot taken while the VM was powered off, and deleting snapshots has an order when memory snapshots are involved); they are in [Advanced VM lifecycle](../../guides/advanced/advanced-lifecycle.md#reverting-to-a-snapshot) and in the repository's [snapshot revert reference](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/vm-snapshot-revert.md).

## Cloning

`VMClone` clones an existing, provisioned `VirtualMachine` on the same provider.

- `spec.source.vmRef` is the only implemented source type; `snapshotRef`, `templateRef` and `imageRef` fail the clone with `UnsupportedSource`.
- `options.type` is `FullClone` (the default) or `LinkedClone`. `LinkedClone` needs a provider that reports `SupportsLinkedClones`: vSphere and Proxmox do; libvirt does not, so a libvirt `LinkedClone` fails with `LinkedCloneUnsupported`.
- A libvirt full clone needs the source VM powered off. A running source leaves the clone `Pending` with `SourceMustBePoweredOff` until the source is off.
- A clone is left powered off unless `options.powerOn: true`.
- Deleting a `VMClone` does not delete the VM it produced.

[vsphere-clone-example.yaml](vsphere-clone-example.yaml) also shows that a `VirtualMachine` has no clone-type field: a VM created with an `imageRef` that names a vSphere template is created by cloning the template, and the full or linked choice is not exposed there.

## Reconfiguration

[vm-reconfigure-patch.yaml](vm-reconfigure-patch.yaml) changes a running VM's resources:

```bash
kubectl patch vm web-server-01 --patch-file vm-reconfigure-patch.yaml --type merge
```

- **vSphere and Proxmox** reconfigure online, subject to the platform's own limits. A vSphere resize that needs the VM powered off is reported as `ResizePendingPowerOff`.
- **libvirt** applies a CPU or memory change online only when the VM was created from a VMClass with `cpuHotAddEnabled` or `memoryHotAddEnabled` and the new value is within the headroom provisioned at create time; otherwise the change is written to the persistent definition and the VM reports `RestartRequired` until it is restarted. Disk growth is live and grow-only.

The reconfigure results are described in [Advanced VM lifecycle](../../guides/advanced/advanced-lifecycle.md#reconfiguration).

## Console access and long-running operations

- [console-access-example.yaml](console-access-example.yaml): `status.consoleURL` holds a link to the VM in the vSphere Client, or the libvirt VNC URL. The libvirt VNC display listens on `127.0.0.1` of the libvirt host only: reach it through an SSH tunnel and do not expose the port.
- [vsphere-task-tracking.yaml](vsphere-task-tracking.yaml): the vSphere provider waits for each vCenter task inside the call and reports no task progress. A slow create or reconfigure shows as `status.phase` `Provisioning` or `Reconfiguring` with the conditions, events and provider log behind it; vCenter's Tasks & Events view has the task itself.

## Getting started

```bash
# Review, edit the placeholders, then apply
cat vsphere-clone-example.yaml
kubectl apply -f vsphere-clone-example.yaml

# Watch
kubectl get vm -w
kubectl get vmclone -w
kubectl describe vm <vm-name>
kubectl get events --field-selector involvedObject.name=<vm-name>

# Console URL and IP addresses
kubectl get vm <vm-name> -o jsonpath='{.status.consoleURL}'
kubectl get vm <vm-name> -o jsonpath='{.status.ips}'
```

## Troubleshooting

| Symptom | Check |
|---------|-------|
| A `VMClone` stays `Pending` | `kubectl get vmclone <name> -o jsonpath='{.status.conditions}'`: reasons include `SourceNotFound`, `SourceMustBePoweredOff` (libvirt), `TargetNamespaceNotAllowed`, `ConsumerNotAllowed`, `CloneRetrying` and `CloneOutcomeUnknown` |
| A `VMClone` is `Failed` | The reason names it: `LinkedCloneUnsupported`, `UnsupportedSource`, `TargetConflict`, `ProviderConflict`. `Failed` is terminal: fix the spec and create a new `VMClone` |
| No console URL | The VM is created (vSphere) or powered on (libvirt); see the provider logs |
| A snapshot delete does not finish | `kubectl describe vmsnapshot <name>`: `DeleteBlocked` means the provider refused it (for example a libvirt snapshot another snapshot depends on); the message says what to delete first |

## See also

- [Examples index](../index.md)
- [vSphere provider](../../providers/vsphere.md), [Libvirt provider](../../providers/libvirt.md), [Proxmox provider](../../providers/proxmox.md)
- [Provider capabilities matrix](../../providers/providers-capabilities.md)
