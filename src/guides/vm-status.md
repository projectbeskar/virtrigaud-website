<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VM Status Reference

This page explains what a `VirtualMachine` reports about itself in
**VirtRigaud v0.4.0**: the `kubectl get vm` columns, how `status.phase` is
derived, which conditions and reasons you can see and what to do about each,
what `status.ips` contains, and what the manager does when a provider call
fails without a definite answer.

## Reading a VM's status

```bash
kubectl get vm                                   # short name for virtualmachines
kubectl get vm web -n team-a -o yaml | yq '.status'
kubectl describe vm web -n team-a                # conditions and events
kubectl get vm web -n team-a \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
```

`kubectl get vm` prints these columns:

| Column | Source |
|---|---|
| `PHASE` | `status.phase` |
| `PROVIDER` | `spec.providerRef.name` |
| `CLASS` | `spec.classRef.name` |
| `IMAGE` | `spec.imageRef.name` |
| `IPS` | `status.ips` |
| `AGE` | `metadata.creationTimestamp` |

There is no `READY` column. The phase is a summary; the reason for anything
unusual is on the conditions (`Ready`, `Provisioning`, `Reconfiguring`,
`Placed`, ...). Every condition carries `observedGeneration`, so compare it with
`metadata.generation` to know whether the condition reflects your last edit.

!!! note "Quote `powerState` in YAML"
    `spec.powerState` takes `"On"`, `"Off"` or `"OffGraceful"`. Write `"On"`
    and `"Off"` with quotes, or a YAML 1.1 parser turns them into booleans.

## Phase

The manager sets `status.phase` on every status write of a `VirtualMachine`, as
a function of the rest of the status. It is never empty on a VM the manager
reconciles and cannot disagree with the conditions. Do not set it by hand; the
next reconcile overwrites it.

| Phase | Meaning |
|---|---|
| `Pending` | Not created. The VM waits for its `Provider`, class, image, a placement, or (for adoption and clone targets) the controller that binds it. Also a clustered VM held by a restore guard: it proceeds once the cause is gone. |
| `Provisioning` | Being created: a `Create` was requested, a task is recorded, a clustered host was chosen, or it was created and has not been described yet. |
| `Running` | Created, and the provider reports it `On`. A `Suspended` VM (paused or suspended to RAM) also shows `Running`; `Ready=False/PowerStateUnmanaged` says it is not managed. |
| `Stopped` | Created, and the provider reports it `Off`. |
| `Reconfiguring` | A resize is in flight (`Reconfiguring=True` other than `RestartRequired`, or a reconfigure task is recorded), or an asynchronous power task is running. |
| `Deleting` | The VM has a deletion timestamp, including while the delete is held. `Ready` and `DeleteBlocked` say why. |
| `Failed` | A hold that needs an operator, a create the provider refused, or a power state the provider cannot classify. |

The rule, first match wins (`derivePhase` in
[`virtualmachine_phase.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/internal/controller/virtualmachine_phase.go)):

1. Being deleted: `Deleting`.
2. `Ready=False` with one of these hold reasons: `Failed`. The reasons are
   `VMNotOwned`, `OwnerStampUnreadable`, `ProviderUnavailable`,
   `VMIsImageArtifact`, `CreateOutcomeUnknown`, `DeleteBlocked`,
   `ProviderRefMismatch`, `PlacementTopologyMismatch`, `ConsumerNotAllowed` and
   `VMMissingOnHost`.
3. No `status.id` (not created) and `Ready=False` with a failed-create reason
   (`CreateBackoff`, `CreateRefused`, `ProviderConflict`, `ValidationError`):
   `Failed`. On a VM that exists the same reasons describe a failed change to it
   and do not change its phase.
4. A clustered restore guard's hold (`RestorePending`, `OwnDomainOnAnotherHost`,
   `UniquenessCheckFailed`, `ProviderLacksListOwnerFilter`): `Pending`.
5. No `status.id` and `Placed` or `Provisioning` is `False` with
   `ImportedDiskPinned`: `Failed`.
6. No `status.id`: `Provisioning` if a create is requested, a clustered pending
   host is set, a task is recorded or `Provisioning=True` (other than
   `WaitingForDependencies`); otherwise `Pending`.
7. A resize in flight: `Reconfiguring`.
8. By `status.powerState`: `On` and `Suspended` are `Running`; `Off` is
   `Stopped`; `Unknown` is `Failed` for as long as the provider reports it. With
   no power state observed yet the VM is `Running` if `Ready=True`, else
   `Provisioning`.

A transient provider error on a VM that exists (`Ready=False/ProviderError`)
does not change the phase: it keeps the last observed power state. Neither does
a pending, running or failed snapshot revert; the phase follows the power state.
An unschedulable clustered VM stays `Pending`.

`status.powerState` is the state as the provider reports it: `On`, `Off`,
`Suspended` (libvirt: paused or suspended to RAM) or `Unknown` (a state the
provider cannot classify). While a VM is `Suspended` or `Unknown` the manager
neither powers it on nor reconfigures it.

## Conditions and reasons

Tables below are grouped by condition type. "Re-check" is how often the manager
looks again without being asked; most holds also clear immediately when you edit
the object.

### Ready

`Ready=True`, reason `ReconcileSuccess`: the VM exists, was described, and
nothing is pending. Any `Ready=False` reason:

| Reason | Meaning | What to do |
|---|---|---|
| `WaitingForDependencies` | The `Provider`, `VMClass` or `VMImage` is missing or not ready (or an image is still being prepared). | `kubectl get provider,vmclass,vmimage`; fix the missing object. If the image is held, read its conditions (see [Security model](security-model.md) for the prepare reasons). |
| `ConsumerNotAllowed` | The `Provider`, `VMClass` or `VMImage` is in another namespace and does not share itself with this one. No provider call is made, for a bound VM too. | Set `spec.consumerNamespaceSelector` on the referenced object or label the namespace. See [Security model](security-model.md). |
| `ProviderConflict` | A hypervisor VM with the same name exists and VirtRigaud cannot prove it created it. `status.id` stays empty. Re-checked every 2 minutes. | Adopt the VM, remove or rename the other one, or recreate the `VirtualMachine` under another name. |
| `ValidationError` | The provider rejected the spec as invalid: a rejected name, an imported disk path that is not this VM's own migration disk, a network setting the provider cannot apply (for example on Proxmox). Re-checked every 30 seconds. | Read the message and fix the spec. |
| `CreateBackoff` | The provider answered a `Create` with a retryable failure that did not make a VM. Retried with a backoff of 15 seconds, doubling to 5 minutes. | Usually nothing; check the provider log if it persists. |
| `CreateRefused` | The provider refused the `Create` with a precondition only an operator can satisfy (for example an imported disk that no longer exists) or a permission error. One `Warning` event carries the answer. Backoff 15 seconds to 5 minutes. | Fix the precondition or the permission on the hypervisor account. |
| `CreateOutcomeUnknown` | A `Create` was sent but its result was never recorded and the provider cannot say whether it made a VM. No second `Create` is sent. Re-checked every minute. | See [Provider call outcomes](#provider-call-outcomes) below. |
| `ProviderError` | A call to the provider failed (describe, power, reconfigure, resolving the provider). Retried every 5 seconds, longer for some failures. The phase keeps the last power state. | Check `kubectl describe provider`, the provider pod and its log. |
| `ProviderUnavailable` | The `Provider` exists but the manager has no usable client for it (runtime not `Running`, TLS or connection failure). On a delete this holds the finalizer. | Wait for the provider rollout, or fix the `Provider`. To release a delete, use `orphan-on-delete` or `force-delete`. |
| `ProviderDeleting` | The `Provider` is being deleted; nothing is created through it. | Recreate the `Provider`, or delete the VM. |
| `ProviderRefMismatch` | `spec.providerRef` no longer resolves to the `Provider` the VM is bound through. No provider call is made. Re-checked every 2 minutes. | Restore the reference, or detach with `virtrigaud.io/orphan-on-delete: "true"`. `spec.providerRef` is immutable once the VM is bound. |
| `VMNotOwned` | (Proxmox) The VM at this VMID carries another owner's stamp, or is unstamped with a different name. `status.id` is kept and no VM is created in its place. | The VM at the VMID is usually another VM: delete this `VirtualMachine` (the other VM is left alone) and create it again. See [Security model](security-model.md). |
| `OwnerStampUnreadable` | The owner stamp cannot be parsed or names more than one owner. Nothing is changed. | An administrator fixes or removes the stamp, or removes the VM. |
| `VMIsImageArtifact` | The hypervisor object is a template or a prepared image, not a VM. | Detach with `virtrigaud.io/orphan-on-delete: "true"`; the template stays. |
| `PowerStateUnmanaged` | The provider reports the VM `Suspended` or `Unknown`. The manager does not power or reconfigure it. A suspended VM with `spec.powerState: OffGraceful` is held; a hard `Off` is required. | Resume the VM on the hypervisor, or set `spec.powerState: "Off"`. |
| `DiskSizeExceedsLimit`, `DiskSizeLimitUnverifiable` | A disk the VM asks for is above the administrator's ceiling, or the limit cannot be checked. Nothing is created. | Lower the disk size, ask the administrator to raise `manager.maxDiskSize`, or fix an invalid `infra.virtrigaud.io/max-disk-size` annotation on the `Provider`. |
| `OrphanOnDeleteNotAllowed` | A VM in another namespace than its clustered `Provider` was annotated `orphan-on-delete`, and the `Provider` does not allow consumers to detach. The finalizer is kept. | Ask the `Provider`'s administrator to set `infra.virtrigaud.io/allow-consumer-orphan-on-delete: "true"`, or remove the annotation to delete the VM normally. |
| `DeleteBlocked` | A delete is held; see the `DeleteBlocked` condition below. | See below. |
| `HostUnavailable`, `VMMissingOnHost`, `RestorePending` | Clustered providers only. See [Clustered operations](clustered/operations.md) and [Backup and restore](clustered/backup-restore.md). | |
| `SnapshotNotFound`, `SnapshotNotReady`, `WaitingForPowerOff`, `Reverting`, `RevertFailed`, ... | A snapshot revert is pending or has failed; these are the reasons of `SnapshotReverted` (below). | |

### Provisioning

| Status / reason | Meaning | What to do |
|---|---|---|
| `True` / `CreateRequested` | A single-host `Create` is about to be (or was) sent. This durable marker is written before the call so a VM made by a `Create` is never lost track of. It is replaced by the outcome. | Nothing. If it stays with no `status.id`, see `CreateOutcomeUnknown`. |
| `True` / `Creating`, `TaskInProgress` | An asynchronous create task is running. | Wait. |
| `True` / `WaitingForDependencies` | The VM waits for another controller (adoption or a `VMClone`) to set its `status.id`. The VirtualMachine controller never creates a VM for it. | Wait. A clone target waits for its `VMClone`. |
| `False` / `ReconcileSuccess` | Provisioned. | |
| `False` / `ProviderError` | Checking the create task failed. | Check the provider. |
| `False` / `ProviderConflict`, `ValidationError`, `CreateRefused`, `CreateBackoff`, `ConsumerNotAllowed`, `ProviderDeleting`, `DiskSizeExceedsLimit`, `DiskSizeLimitUnverifiable` | Same meaning as under `Ready`; the provider made nothing. | |
| `False` / `WaitingForImport` | The target of a `VMMigration` into a clustered `Provider` is placed and waits for the migration to import its disk. No `Create` is sent yet. | Wait for the migration; see [Migration into a clustered Provider](../migration/clustered-target.md). |
| `False` / `MigrationNotFound` | The VM waits for an import, but the `VMMigration` it names does not exist or did not create this VM. | Delete the VM or the migration that owns it. |

### Reconfiguring

A reconfigure changes CPU, memory and disk size. It has three outcomes:
applied, restart required, or failed; a provider never reports success for a
change it did not apply.

| Status / reason | Meaning | What to do |
|---|---|---|
| `False` / `ReconcileSuccess` | The last change is applied (or none is pending). `status.currentResources` is the current size. | |
| `True` / `Updating`, `TaskInProgress` | A reconfigure (or, with the message `Adjusting power state`, an asynchronous power task) is in flight. The phase is `Reconfiguring`. | Wait. |
| `True` / `RestartRequired` | The provider applied at least one change to the persistent definition only; the new size takes effect at the next **power cycle** (power off, then on; a reboot from inside the guest is not enough). `status.currentResources` holds, per resource, the larger of the running and next-boot size. The phase follows the power state. Re-asked every 2 minutes. | Set `spec.powerState: "Off"`, wait for `Stopped`, then `"On"`. |
| `False` / `ResizePendingPowerOff` | (vSphere) The VM cannot take the change while it runs and cannot stage it for the next boot: CPU or memory hot-add (or hot-remove) is not enabled, memory is above the hot-plug limit, a shared-bus disk is being grown, or the VM is suspended. Nothing was changed, and the VM stays `Ready`. | Set `spec.powerState: "Off"`; the change is applied, then set `"On"`. To resize running VMs in future, enable hot-add on the `VMClass` `performanceProfile`. |
| `False` / `ShrinkPendingPowerOff` | (clustered) A running VM's CPU or memory shrink is applied only after power-off. The VM counts at its current size until then. | Power the VM off. |
| `False` / `InsufficientHostCapacity` | (clustered) A resize-up exceeds the free capacity of the VM's host. The VM keeps its size and the resize is retried with a backoff. | Free capacity on the host, or choose a smaller size. |
| `False` / `ProviderLacksHonestReconfigure` | (clustered) The `Provider` does not report that it tells the truth about a resize (an older provider image), so no resize is sent. Re-checked every 30 seconds. | Upgrade the provider image. |
| `False` / `ProviderError` | The reconfigure failed, or its outcome was not provable. Part of the change may be applied. Retried on a per-VM backoff (5 seconds doubling to 5 minutes), and at once after a spec change. | Read the message; check the provider. |
| `False` / `PowerTaskFailed` | An asynchronous power task ended in failure. The failure is on `Ready/ProviderError`; this settles the marker. | See the `Ready` message. |
| `False` / `ValidationError` | The manager refused to build the request: an invalid `spec.resources` override, or an invalid `VMClass` field such as `diskDefaults.size`. Nothing is sent. Re-checked every 30 seconds. | Fix the spec or the class. |

A disk-size change alone does not trigger a reconfigure: to apply a
`spec.disks` size change, the CPU or memory must change too (a known
limitation). On vSphere and Proxmox a reconfigure never touches the root disk.

### DiskSizeWithinLimit

Present only when an administrator set a disk-size ceiling
(`manager.maxDiskSize`). `False`, reason `DiskSizeExceedsLimit` or
`DiskSizeLimitUnverifiable`, means the last reconfigure applied the VM's other
changes and left a disk as it is rather than growing it beyond the limit. It is
removed by the next reconfigure that withholds nothing. See
[Security model](security-model.md).

### DisksApplied

`DisksApplied=False`, reason `NotSupportedByProvider`: the VM has a non-empty
`spec.disks` on a `Provider` of type `libvirt` or `proxmox`, which attach no
additional disks. The entries are not created or attached, at create or later.
The VM itself is fine and `Ready` is unchanged. A `Warning` event with the same
reason is recorded once per `metadata.generation`, and the validating webhook
(where installed) warns at admission. It is removed when `spec.disks` is
emptied. It is never `True`.

### Placed

Clustered (`topology: cluster`) `Provider`s only; never set on a single-host
VM. `Placed=True`, reason `Bound`, means the VM has a confirmed host. `False`
carries why per-VM calls cannot be routed yet. The reasons and their runbooks
are in [Clustered operations](clustered/operations.md) and
[Placement](clustered/placement.md):

| Reason | Meaning |
|---|---|
| `CreatePending` | The attempted host is recorded; the provider has not confirmed the `Create` there yet. |
| `HostUnavailable` | The pending host is unreachable. The VM is never re-scheduled automatically, because a domain may already exist there. |
| `Unbound` | The VM has a provider id but no confirmed host binding (for example its status was lost in a restore). No per-VM call is sent. |
| `HostExcluded`, `AllHostsExcluded` | A `Create` was refused with a name conflict on a host; the host was excluded and the VM re-scheduled, or every host is excluded. |
| `Unschedulable`, `NoHostPool`, `MultipleHostPools`, `PlacementPolicyNotFound`, `PlacementError`, `PendingSizeGrew` | The scheduler cannot place the VM, or its input is wrong. Also shown on `Provisioning=False`. |
| `RestorePending`, `OwnDomainOnAnotherHost`, `UniquenessCheckFailed`, `ProviderLacksListOwnerFilter`, `ImportedDiskPinned` | Restore and uniqueness guards. See [Backup and restore](clustered/backup-restore.md). |

### DeleteBlocked

`DeleteBlocked=True` while a delete is held because the provider could not
delete the VM safely yet; `Ready` is `False/DeleteBlocked` meanwhile. The
finalizer is kept and the delete is retried with a backoff (15 seconds doubling
to 5 minutes; every minute for dependents). A single-host VM shows the hold on
`Ready` only, with the reason itself for `ProviderUnavailable`,
`VMIsImageArtifact` and `OwnerStampUnreadable`. Only clustered VMs carry the
`DeleteBlocked` condition itself.

| Reason | Meaning | What to do |
|---|---|---|
| `DiskInUse` | Another VM (for example a libvirt linked clone made by an earlier release) uses this VM's disk. Nothing was deleted. On a single-host VM this is `Ready=False/DeleteBlocked` with a message naming the cause. | Delete the dependents first, or detach this VM with `orphan-on-delete`. |
| `HostUnreachable` | A host the delete needs, or the VM's own host, could not be reached or stopped answering. The message says whether anything may have been deleted. | It completes once the host answers. See [Clustered operations](clustered/operations.md). |
| `DiskCheckFailed` | The provider could not verify that no VM on another host uses the disk. | Wait for the hosts to answer. |
| `OwnDomainOnAnotherHost` | The VM's own domain was found on another host than the one recorded. | See [Backup and restore](clustered/backup-restore.md). |
| `ProviderUnavailable` | The manager has no usable client for the `Provider`. | Wait for the provider, or fix it. |
| `VMIsImageArtifact`, `OwnerStampUnreadable` | See `Ready` above. | |

To release a held delete deliberately: `virtrigaud.io/orphan-on-delete: "true"`
detaches the VM (no provider call, the hypervisor VM keeps running), and
`virtrigaud.io/force-delete: "true"` drops the finalizer after the delete keeps
failing. Both leave a hypervisor VM unmanaged; force-delete records a
`VMLeftOnHypervisor` `Warning` event naming the provider id. On a clustered
`Provider`, a consumer in another namespace needs the `Provider`'s permission
for both (`ForceDeleteRefused=True/ForceDeleteNotAllowed` otherwise).

### SnapshotReverted

Present only while `spec.snapshot.revertToRef` is set. While it is `False`,
`Ready` is `False` with the same reason. Progress and outcome are in
`status.snapshotRevert` (`phase`: `Pending`, `Reverting`, `Succeeded`, `Failed`).
See [Snapshots and revert](vm-snapshots.md) for the workflow.

| Reason | Meaning | What to do |
|---|---|---|
| `WaitingForPowerOff` | The VM is not powered off, or `spec.powerState` is `"On"`. A revert needs a powered-off VM. | Set `spec.powerState: "Off"`. |
| `SnapshotNotFound` | No `VMSnapshot` of that name in the VM's namespace. | Fix the name. |
| `SnapshotNotReady` | The `VMSnapshot` is not `Ready`, has no provider snapshot id, or is being deleted. | Wait, or use another snapshot. |
| `SnapshotForAnotherVM` | The `VMSnapshot` was not taken of this VM (another `vmRef`, UID or `Provider`), or that cannot be proven. | Use a snapshot of this VM. |
| `Unsupported` | The `Provider` reports no snapshot support, or does not implement revert. | Use a provider that supports snapshots. |
| `Reverting` | The revert was sent and its outcome is not known yet. | Wait. |
| `Reverted` (`True`) | The provider confirmed the revert. | Remove `spec.snapshot.revertToRef`. |
| `RevertFailed` | The provider refused or failed the revert. Not retried on its own. | Read the message, then remove `spec.snapshot.revertToRef` and set it again to retry. |

### Other conditions

| Type | Meaning |
|---|---|
| `LinkedClonesDependOnDisk` (`True`) | Other VMs on the hypervisor use this VM's disk as a backing file (libvirt linked clones made by an earlier release). A warning only: powering the VM on while those clones are shut off corrupts them. |
| `ForceDeleteRefused` (`True`, `ForceDeleteNotAllowed`) | `force-delete` is ignored because the VM is a consumer of a clustered `Provider` that does not allow it. The delete is retried as if the annotation were not set. |

## `status.ips`

`status.ips` is the `IPS` column. It lists the VM's addresses **except**
loopback (`127.0.0.0/8`, `::1`), unspecified (`0.0.0.0`, `::`), link-local
(`169.254.0.0/16`, `fe80::/10`) and multicast (`224.0.0.0/4`, `ff00::/8`)
addresses. Private (RFC 1918) addresses, IPv6 unique-local addresses and global
addresses are kept. An entry that is not a bare IP (a host name, an address with
a prefix length) is dropped, duplicates are dropped, and the order is the order
the provider reported them.

The manager applies the same filter to every provider's answer, so the list
means the same on vSphere, libvirt, Proxmox and the mock provider. For example,
a guest whose agent reports `127.0.0.1, ::1, 192.0.2.31, fe80::5054:ff:fe88:d0c1`
shows:

```yaml
status:
  ips:
    - 192.0.2.31
```

`status.ips` is absent while the provider has no reachable address to report.
Tooling that took `status.ips[0]` or matched `127.0.0.1` or `fe80::...` no
longer finds it: up to v0.4.0-rc7 a libvirt VM with a running guest agent listed
every address of every interface. The list is rewritten on the next reconcile;
no spec change is needed.

Where each provider gets addresses:

| Provider | Source | An address shows when |
|---|---|---|
| vSphere | VMware Tools (`guest.ipAddress`, `guest.net`) | Tools run in the guest |
| Proxmox | QEMU guest agent (`network-get-interfaces`) | The VM is running and the agent answers |
| libvirt | The QEMU guest agent, then libvirt's DHCP lease and the host's ARP table as fallbacks | The agent answers, or a fallback source has a row |

On **libvirt** the network decides what is visible without the guest agent:

- **libvirt's NAT `default` network (or any libvirt-managed network):** libvirt
  runs the DHCP server, so the lease is shown without the agent.
- **A host bridge** (`VMNetworkAttachment` `spec.network.libvirt.bridge`): the
  LAN's DHCP server answers, not libvirt, so there is **no lease**. The address
  is shown if the QEMU guest agent runs in the guest. Without it `status.ips` is
  empty, unless the host happens to have an ARP entry for the guest's MAC
  address (a last resort that depends on recent traffic).
- **No network attachment:** the VM gets a user-mode interface; libvirt holds no
  lease for it either, so it needs the agent too.

So the guest agent is the source that works on every network type. The default
cloud-init the libvirt provider injects installs and starts `qemu-guest-agent`
and the provider adds the agent channel to every domain it defines; an image or
`spec.userData` that does not install and start the agent has none. Up to
v0.4.0-rc7 a guest on the NAT `default` network without the agent showed no
address although libvirt had its lease.

## Provider call outcomes

Most calls to a provider can be repeated safely. A few cannot, because a second
call would duplicate something: a VM `Create`, a `Clone`, the source snapshot,
disk export and disk import of a `VMMigration`, the snapshot of a `VMSnapshot`,
and a snapshot revert. If the manager restarts, leadership moves to another
replica, or the call times out or the connection drops after the request was
written, the manager cannot tell whether the provider acted. Retrying
blindly could create a second VM or snapshot or land a second disk.

So the manager records its intention **before** it sends such a call, in a
status write that fails if anything else changed the object (nothing is sent if
that write fails), and uses it afterwards:

| Object | Call | Marker |
|---|---|---|
| `VirtualMachine` | `Create` (single-host) | `Provisioning=True/CreateRequested` |
| `VMClone` | `Clone` | `CloneRequested=True` |
| `VMMigration` | `SnapshotCreate`, `ExportDisk`, `ImportDisk` | conditions `SnapshotRequested`, `ExportRequested`, `ImportRequested` |
| `VMSnapshot` | `SnapshotCreate` | condition `SnapshotRequested` |
| `VirtualMachine` | snapshot revert | `status.snapshotRevert` with `phase: Reverting` |

The marker is removed in the same write that records the call's result or a
**definite** failure: the request never reached the provider, the provider
refused it before doing anything (invalid request, not found, not owned, a name
conflict, a disk-size refusal), or it answered that it did not perform the call.
Every other failure (a deadline, an unavailable provider after the request was
written, an error the provider did not classify) keeps the marker. The result is
an **outcome unknown**:

| Reason | On | Meaning |
|---|---|---|
| `CreateOutcomeUnknown` | `VirtualMachine` (`Ready=False`) | The `Create` may have made a VM. No second `Create` is sent unless the provider can re-bind the VM it made (it reports `supports_owner_rebind`); otherwise the VM is held. |
| `CloneOutcomeUnknown` | `VMClone` | The `Clone` may have made a VM. When the provider reports owner re-bind, it is sent again with a backoff of 15 seconds doubling to 5 minutes, because a clone is stamped with its target and a re-send re-binds it; otherwise the clone fails. |
| `CloneRetrying` | `VMClone` | Nothing was cloned; retried with the same backoff. |
| `SnapshotOutcomeUnknown` | `VMSnapshot`, `VMMigration` | The snapshot may exist. Sent again only through a clustered `Provider`, which finds the earlier snapshot by request token. Otherwise held. |
| `ExportOutcomeUnknown`, `ImportOutcomeUnknown` | `VMMigration` | The export or import may still be running or have completed. Sent again only if the provider lists the migration's staging backend as safe to re-send **and** 35 minutes have passed since the marker. Otherwise held. |

Automatic re-sends are capped (a routed snapshot create 10 times, an export or
import 3 times); after that the object is held for an operator. A snapshot
revert is the exception: it is sent again on its own only while the VM stays
powered off and the `VMSnapshot` is the same one (at most 5 calls), because a
second revert of a powered-off VM reaches the same state.

A held object writes its status once and is re-checked every minute. Its `Ready`
message is constant and names the action; the matching `Warning` event gives the
attempt id and, for a snapshot, the snapshot name that was asked for.

### Releasing a held object

First check the hypervisor for what the call may have made, and remove it:

- **Create:** look for a VM with the `VirtualMachine`'s name stamped with its UID
  (see [Security model](security-model.md) for the stamp). If it exists, record
  its id and the VM is managed (or deleted) as usual:

  ```bash
  kubectl patch virtualmachine <name> -n <ns> --subresource=status --type=merge \
    -p '{"status":{"id":"<provider id>"}}'
  ```

  The id is a Proxmox VMID, a vSphere managed object id such as `vm-1234`, or a
  libvirt domain name. If it does not exist, confirm that for this attempt. The
  attempt id is the `lastTransitionTime` of the `Provisioning` condition:

  ```bash
  ATTEMPT=$(kubectl get virtualmachine <name> -n <ns> \
    -o jsonpath='{.status.conditions[?(@.type=="Provisioning")].lastTransitionTime}')
  kubectl annotate virtualmachine <name> -n <ns> virtrigaud.io/create-outcome=not-created@$ATTEMPT
  ```

  The manager checks it against the live object, records a `Warning` event
  `CreateOutcomeConfirmed`, removes the annotation and creates the VM. A value
  naming another attempt is ignored and removed.
- **Snapshot:** look on the source VM for a snapshot with the name from the
  event, and remove it.
- **Import:** look on the target provider for the disk landed for the target
  `VirtualMachine`; its name ends in `-migrated`.
- **Export:** make sure no export of this migration is still running. The staged
  object is replaced by the next export.

Then confirm the attempt, which sends the call again. For an export:

```bash
ATTEMPT=$(kubectl get vmmigration <name> -n <ns> \
  -o jsonpath='{.status.conditions[?(@.type=="ExportRequested")].lastTransitionTime}')
kubectl annotate vmmigration <name> -n <ns> virtrigaud.io/operation-outcome=not-performed@$ATTEMPT
```

Use the `SnapshotRequested` or `ImportRequested` condition for a migration's
snapshot or import, and `vmsnapshot` with `SnapshotRequested` for a
`VMSnapshot`. The manager records a `Warning` event `OperationOutcomeConfirmed`,
removes the annotation before it sends the call (a confirmation never carries
over to a later attempt) and ignores a value that names another attempt. The API
server's audit log is the authoritative record of who set the annotation. Or
delete the object: its cleanup removes only what its status records, and
anything the lost call made is yours to remove. `virtrigaud.io/force-delete`
releases a held deleting migration at once.

!!! warning "Roll the providers right after the manager"
    Until a provider reports which staging backends are safe to re-send, an
    export or import whose outcome was lost is held for an operator instead of
    being re-sent. A provider image older than v0.4.0 also answers libvirt
    failures without a definite class, so every one of them is held.

### Which providers can re-send

A second `SnapshotCreate` of the same name behaves differently per provider, and
only the clustered libvirt provider records the request token and returns the
earlier snapshot:

| Provider | A second `SnapshotCreate` of the same name |
|---|---|
| vSphere | Creates a second snapshot with the same name |
| libvirt, single host | Refuses the name; does not return the first snapshot |
| Proxmox | Starts a task that fails because the name is taken |
| libvirt, clustered | Returns the earlier snapshot, once no job runs on the domain |

Backends for which a re-sent export or import is safe (it replaces the earlier
result rather than adding a second one):

| Provider | Export | Import |
|---|---|---|
| vSphere | `s3`, `nfs` | `s3`, `nfs` |
| libvirt, single host | `s3` | `pvc`, `s3`, `nfs` |
| libvirt, clustered | `s3`, `nfs` | `s3`, `nfs` |
| Proxmox | `s3` | `s3` |

For a clustered libvirt `Provider`, a host that stops answering part-way through a
call is classified by how far the call got (nothing done, not performed,
outcome unknown, retry). What you see on the VM, including a delete held for an
unreachable host, is in [Clustered operations](clustered/operations.md).

## Events you may see

`kubectl describe vm` lists events. The ones that point at a decision you may
need to make: `VMLeftOnHypervisor` (a force-delete released the finalizer
without a confirmed delete; the event names the provider id), `Orphaned` (a
detach left the hypervisor VM in place), `BoundProviderRecreated` (a `Provider`
was deleted and recreated under the same name and was accepted; no action
needed), `CreateOutcomeConfirmed`, `ConsumerNotAllowed`,
`NotSupportedByProvider` and `DeleteBlocked`.
