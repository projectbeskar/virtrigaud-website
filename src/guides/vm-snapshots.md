<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VM snapshots and revert

A `VMSnapshot` asks the VM's Provider to take a snapshot of one
`VirtualMachine`. Setting `spec.snapshot.revertToRef` on the VM asks the
Provider to revert the VM to it.

!!! info "What changed in v0.4.0"
    Up to v0.3.11 `spec.snapshot.revertToRef` was accepted and **ignored**: no
    controller sent the revert, the VM stayed `Ready`, and no condition or event
    said so. In v0.4.0 the `VirtualMachine` controller acts on it, under the
    rules on this page. See [the upgrade caveat](#upgrade-caveat) before you
    upgrade.

    The revert flow is covered by unit and envtest tests with a scripted
    provider. It was also run in the lab on vSphere, on Proxmox (an asynchronous
    task) and on libvirt (single-host and clustered).

## Taking a snapshot

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMSnapshot
metadata:
  name: web-server-01-pre-update
  namespace: default
spec:
  vmRef:
    name: web-server-01
  snapshotConfig:
    name: pre-system-update      # a name hint; the provider may change it
    includeMemory: false         # disk-only
    description: "Snapshot before system package updates"
  retentionPolicy:
    maxAge: "168h"
    deleteOnVMDelete: true
```

`vmRef` names a `VirtualMachine` in the same namespace. The `VMSnapshot` is
recorded against that VM's UID and Provider, so a snapshot cannot later be used
for another VM, even one re-created under the same name.

```sh
kubectl get vmsnapshot web-server-01-pre-update \
  -o jsonpath='{.status.phase}{"\t"}{.status.snapshotID}{"\n"}'
```

| `status.phase` | Meaning |
|---|---|
| `Pending`, `Creating` | The create is in progress, or waiting for the VM to be provisioned (`status.id` set) |
| `Ready` | The provider confirmed the snapshot; `status.snapshotID` is the provider's id for it |
| `Deleting` | The snapshot is being removed from the hypervisor |
| `Failed` | The create failed; the message says why. A failed snapshot is re-checked every 5 minutes |

Retention: the controller acts on `retentionPolicy.maxAge` (the `VMSnapshot` is
deleted once older than that; checked hourly) and `retentionPolicy.deleteOnVMDelete`
(the `VMSnapshot` is deleted when its VM is gone or being deleted, unless the VM
is being detached with `virtrigaud.io/orphan-on-delete`). The `schedule`,
`retentionPolicy.maxCount` and `retentionPolicy.preservePinned` fields are in the
schema but the controller does not act on them.

Deleting a `VMSnapshot` deletes the snapshot on the hypervisor, through the
finalizer. If the provider refuses (see [libvirt](#libvirt)) or cannot be
reached, the `VMSnapshot` stays in `Deleting` with `Ready=False`
(for a refusal, reason `DeleteBlocked` and a `SnapshotDeleteFailed` warning
event) and is re-checked with a backoff from 15 seconds to 5 minutes.
`virtrigaud.io/force-delete=true` on the `VMSnapshot` removes it from the
cluster and leaves the snapshot on the hypervisor. For a VM that is a consumer
of a clustered Provider in another namespace, force-delete is honoured only when
the Provider carries `infra.virtrigaud.io/allow-consumer-orphan-on-delete: "true"`.

## Reverting a VM

1. Power the VM off. VirtRigaud never powers a VM off for a revert.

    ```sh
    kubectl patch vm web-server-01 --type merge -p '{"spec":{"powerState":"Off"}}'
    ```

2. Name the `VMSnapshot`. It must be `Ready` and taken of this VM.

    ```sh
    kubectl patch vm web-server-01 --type merge \
      -p '{"spec":{"snapshot":{"revertToRef":{"name":"web-server-01-pre-update"}}}}'
    ```

3. Watch the `SnapshotReverted` condition and `status.snapshotRevert`.

    ```sh
    kubectl get vm web-server-01 \
      -o jsonpath='{.status.snapshotRevert.phase}{"\n"}{.status.conditions[?(@.type=="SnapshotReverted")].message}{"\n"}'
    ```

    It ends `Succeeded` (`SnapshotReverted=True`, reason `Reverted`) or
    `Failed`.

4. Power the VM on again if you want it running. The revert does not do that.

    ```sh
    kubectl patch vm web-server-01 --type merge -p '{"spec":{"powerState":"On"}}'
    ```

To revert to the same snapshot **again**, remove the field, wait for
`status.snapshotRevert` to disappear, then set it again:

```sh
kubectl patch vm web-server-01 --type json -p '[{"op":"remove","path":"/spec/snapshot/revertToRef"}]'
```

You can leave the field set after the revert. It does nothing more while it
names the same `VMSnapshot`.

## The rules

### The VM must be powered off

The revert is sent only when the provider reports the VM `Off` **and**
`spec.powerState` is `Off` or `OffGraceful`. Otherwise nothing is sent and
`SnapshotReverted` is `False` with reason `WaitingForPowerOff`. This holds even
when the VM happens to be off but `spec.powerState` is `On`, because the
controller would power it on.

- A VM the provider reports `Suspended` or `Unknown` is not `Off`: it waits.
- A revert requested while the VM runs stays requested. It is sent the next time
  the VM is off with `spec.powerState: Off`, however much later. To cancel it,
  remove `spec.snapshot.revertToRef`.
- After the revert the VM's power follows `spec.powerState` as usual. A snapshot
  that includes memory can leave the VM running (vSphere asks vCenter for this
  explicitly); a VM whose spec still says `Off` is then powered off again.

A revert discards the VM's current disk state, so requiring the VM to be off
also makes a revert that is sent twice (after a lost answer) safe: nothing
changes the disks of a VM that stays off between the two attempts.

### The snapshot is resolved fail-closed

The revert is sent only when all of these hold; otherwise nothing is sent and
the condition says why.

| Check | Reason when it fails |
|---|---|
| The `VMSnapshot` exists in the VM's namespace | `SnapshotNotFound` |
| Its `spec.vmRef.name` is this VM | `SnapshotForAnotherVM` |
| It is not being deleted, its `status.phase` is `Ready`, and it has `status.snapshotID` | `SnapshotNotReady` |
| It was taken of this VM: its `status.vmUID` is this VM's UID | `SnapshotForAnotherVM` |
| It was taken through this VM's Provider (`status.boundProvider`). A `VMSnapshot` that records no Provider is not refused on this check | `SnapshotForAnotherVM` |
| The Provider does not report `supportsSnapshots: false` in `status.reportedCapabilities` | `Unsupported` |

These are re-checked every 30 seconds, and at once on any change to the VM's
spec. A `VirtualMachine` deleted and re-created under the same name is another
VM (another UID): the old VM's snapshots are refused with `SnapshotForAnotherVM`.

### At most once per request

`status.snapshotRevert` records the request: the `VMSnapshot`'s name and UID,
the phase and the outcome.

- While it records `Succeeded` or `Failed` for the `VMSnapshot` the field names
  (same UID), nothing is sent again: not on later reconciles, not when another
  spec field changes, not when the same manifest is applied again.
- Removing `spec.snapshot.revertToRef` clears the record and the condition.
  Setting it again is a new request.
- Naming another `VMSnapshot`, or one deleted and re-created under the same name
  (another UID), is a new request. The record keeps only the latest request:
  naming snapshot A, then B, then A again reverts to A twice.
- A `Failed` revert is not retried on its own. Remove the field and set it
  again, unless the provider refused it for good (`FailedPrecondition`, for
  example libvirt's refusal of a snapshot it cannot revert safely). The same
  revert would be refused again, so the message ends with the provider's
  guidance instead of a retry hint.

Before the call, the controller writes `status.snapshotRevert` with phase
`Reverting` under an optimistic lock, so a stale cache never sends a second
revert. If the installed `VirtualMachine` CRD does not store
`status.snapshotRevert` (CRDs older than the manager), nothing is sent and the
condition is `Unsupported` with a message asking for the CRD upgrade.

### GitOps

A manifest that keeps `spec.snapshot.revertToRef` set is safe to apply again and
again: once the record says `Succeeded` or `Failed` for that `VMSnapshot`,
nothing is sent. Two things to know:

- To revert again to the same snapshot from Git, remove the field in one commit,
  let it sync (the record is cleared), then add it back in another.
- A `VirtualMachine` re-created from the same manifest (deleted, restored, moved
  to a new cluster) is a new VM. The field then names a `VMSnapshot` of the old
  VM, which is refused (`SnapshotForAnotherVM`), and the VM stays `Ready=False`
  until the field is removed. Do not keep the field in Git after the revert if
  VMs are re-created from it.

### Asynchronous reverts and unknown outcomes

- **A task.** A provider that answers with a task (Proxmox, the mock provider)
  has it recorded in `status.snapshotRevert.taskRef` and polled every 10
  seconds. While it runs the VM is not powered on, resized or reverted again,
  even if its spec changes, and removing `revertToRef` clears the record only
  once the task has ended. A task that ends in failure fails the revert. A task
  that has not completed after 2 hours, or whose status cannot be read for that
  long, is `Failed` with its outcome unknown, so the VM is managed again.
- **An unknown outcome.** A call that fails without a definite answer (the
  provider not reached or not answering in time, a retryable answer, a clustered
  host that stopped answering after the command was sent, or a manager restart
  between the call and the write of its answer) leaves the record `Reverting`
  with no task. The revert is sent again, because a VM that stayed off reaches
  the same state with a second revert:
    - no sooner than 6 minutes after the last attempt, doubling with each
      attempt up to 30 minutes;
    - only if a fresh `Describe` reports the VM `Off` and `spec.powerState` is
      still `Off` or `OffGraceful`. A VM seen in any other state may have run
      since the attempt, so the revert is `Failed` (`RevertFailed`, the VM may or
      may not have been reverted) and is never sent again for that request;
    - only to the same `VMSnapshot` (same UID) and while the Provider still
      reports snapshot support;
    - at most 5 calls for one request; after that the revert is `Failed`.
- **A definite failure** (a refusal, an error the provider reported, an
  unimplemented RPC) is terminal: phase `Failed`. The message is the provider's
  answer, made safe for status (one line, URL credentials removed, bounded).

There is no operator confirmation for a revert whose outcome stays unknown. If
it ends `Failed` with "may or may not have been reverted", check the VM and
request the revert again if it was not done.

## Status, condition and events

### `status.snapshotRevert`

| Field | Meaning |
|---|---|
| `snapshotName`, `snapshotUID` | The `VMSnapshot` the request is for (UID empty while it was not found) |
| `phase` | `Pending` (waiting; the condition says for what), `Reverting` (sent, outcome not known yet), `Succeeded`, `Failed` |
| `taskRef` | The provider task of an asynchronous revert, while it runs |
| `attempts` | `SnapshotRevert` calls sent for this request (more than 1 only after unknown outcomes) |
| `requestedAt`, `attemptTime`, `completionTime` | When the request was recorded, when the last call was recorded (just before it was sent), and when it ended |
| `message` | What it waits for, or how it ended |

Only the operator writes it. It is absent while `spec.snapshot.revertToRef` is
unset.

### The `SnapshotReverted` condition

Absent while `spec.snapshot.revertToRef` is unset.

| Status | Reason | Meaning and what to do |
|---|---|---|
| `False` | `WaitingForPowerOff` | The VM is not reported `Off`, or `spec.powerState` is `On`. Set `spec.powerState: Off` |
| `False` | `SnapshotNotFound` | No `VMSnapshot` of that name in the namespace |
| `False` | `SnapshotNotReady` | The `VMSnapshot` is not `Ready`, has no `status.snapshotID`, or is being deleted |
| `False` | `SnapshotForAnotherVM` | The `VMSnapshot` was not taken of this VM (another `spec.vmRef`, VM UID or Provider), or that cannot be proven |
| `False` | `Unsupported` | The Provider reports no snapshot support, answers that it does not implement `SnapshotRevert`, or the installed CRD cannot record the request |
| `False` | `Reverting` | Sent; the outcome is not known yet (a task runs, or the call is sent again after an unknown outcome) |
| `True` | `Reverted` | The provider confirmed the revert |
| `False` | `RevertFailed` | The provider failed or refused it, or its outcome stayed unknown. Remove the field and set it again to retry, except after a refusal the provider gives every time, whose message says what to do instead (for libvirt: take a new snapshot with the VM powered off) |

While `SnapshotReverted` is `False`, **`Ready` is `False`** with the same reason
and the message prefixed `Snapshot revert: `, unless `Ready` is already `False`
for another reason. A VM whose revert failed therefore stays `Ready=False` until
the field is removed. `status.phase` is not changed by a revert: it follows the
power state.

| Type | Event reason | When |
|---|---|---|
| `Normal` | `SnapshotRevertStarted` | A `SnapshotRevert` call is sent (with the attempt number) |
| `Normal` | `SnapshotRevertSucceeded` | The provider confirmed the revert |
| `Warning` | `SnapshotRevertFailed` | The revert failed, or was given up with its outcome unknown |

## Per provider

| Provider | What the revert does |
|---|---|
| vSphere | Finds the snapshot in the VM's snapshot tree by managed-object id or name and runs `RevertToSnapshot_Task` with `suppressPowerOn=false`, waiting for it in the call. A snapshot taken **with memory powers the VM on**; the controller then applies `spec.powerState`. Templates and image artifacts are refused |
| Proxmox | Checks the VM's owner, then asks PVE to roll back the snapshot. The answer is an **asynchronous task**, which the manager polls |
| libvirt (single host) | Synchronous. See [libvirt](#libvirt) |
| libvirt (clustered) | The same, routed to the VM's bound host and owner-checked: a domain this VM does not own is `NotFound` and is never reverted |

### libvirt

libvirt has the most rules, because its snapshots are files.

**What a snapshot is.** A snapshot of a VM that is off, or taken without memory,
is an **external disk-only** snapshot: libvirt adds an overlay file
`<pool>/<domain>-disk.<snapshot name>` and the VM runs on it. A snapshot with
`includeMemory: true` of a **running** VM is an **internal** snapshot, stored
inside the qcow2 file the disk is using.

**Take snapshots with the VM powered off to be able to revert them.** libvirt
reverts an external snapshot by rebuilding the VM's disks from the domain
definition the snapshot stored. That definition includes the VM's read-only
cloud-init seed CD-ROM, and a revert would rewrite it to an overlay file that
the host's AppArmor profile does not let QEMU open, so the VM would no longer
start. VirtRigaud therefore:

- takes a snapshot of a **powered-off** VM with the CD-ROMs and floppies
  **ejected** for the duration, so the stored definition has empty drives, and
  inserts them again afterwards (also when the snapshot failed);
- never ejects the media of a **running** VM. A disk-only snapshot of a running
  VM with a cloud-init CD-ROM stores the seed, so it **cannot be reverted**;
- **refuses the revert, before changing anything,** of a disk-only snapshot whose
  stored definition has a CD-ROM, floppy or read-only disk with media. That is
  every disk-only snapshot taken while the VM ran, and every one taken by
  an earlier release of a VM with a cloud-init CD-ROM. The VM gets
  `SnapshotReverted=False/RevertFailed`, and the message reads along the lines of
  `revert refused, nothing changed: take a new snapshot with the VM powered off`.
  It is not retried. Delete the `VMSnapshot`, power the VM off and create a new
  one. A snapshot of a running VM taken with memory is internal: libvirt reverts
  it in place and it is not refused;
- after a revert, puts the seed back into the CD-ROM the revert left empty, and
  reports `RevertFailed` if it cannot (the VM was reverted, but check its
  CD-ROM).

libvirt reverts external snapshots from **version 9.9**. An older libvirt
refuses and the provider's error is reported as `RevertFailed`.

A revert also refuses while another domain depends on the VM's disk (a linked
clone: `VM_DISK_IN_USE`, shown as `RevertFailed`).

**What a revert leaves in the pool.** libvirt creates a new overlay for each
disk, named after the disk's file with its extension replaced by the revert's
time in Unix seconds (`<domain>-disk.<epoch>`), and removes the overlay it
replaces. `SnapshotDelete` and VM delete recognise it as the VM's own.

If the provider or the host fails between ejecting and re-inserting the seed,
the CD-ROM stays empty until VirtRigaud's next snapshot create, snapshot
revert or start (`spec.powerState: On`, or a reboot) of that VM inserts the
recorded file again. A VM started by hand with `virsh start` in that window
boots without its seed. Only the VM's own cloud-init seed is inserted
automatically; any other medium (an installer ISO you attached) is logged and
left for you to insert.

**Delete order when memory and disk-only snapshots are mixed.** A memory snapshot
taken after a disk-only one is stored **inside the disk-only snapshot's
overlay**. Deleting the disk-only snapshot makes libvirt merge that overlay into
its base, and libvirt does not refuse this although it orphans the memory
snapshot: its data stays in the leftover overlay file, but the VM no longer runs
on it, so the snapshot cannot be used.

Since v0.4.0 the provider refuses that delete before anything changes. The
`VMSnapshot` stays in `Deleting` with `Ready=False/DeleteBlocked`, a
`SnapshotDeleteFailed` warning event, and a message that names the snapshots to
delete first:

```text
delete refused, nothing changed: delete snapshot "mem" first; it is stored in a disk file that deleting snapshot "live" would merge away, ...
```

**Delete the memory snapshot first, then the disk-only snapshot.** Deleting a
memory snapshot is never refused by this check. libvirt itself, however, deletes
a memory snapshot of a running VM only while the VM still runs on the file the
snapshot is stored in; if it does not, the provider refuses with `delete
refused, nothing changed: power the VM off and delete it again`, and you should
do that. A disk-only snapshot followed by
a second disk-only snapshot and then a memory snapshot: the first can be
deleted (the memory snapshot is in the second one's overlay), the second is
refused until the memory snapshot is deleted. If the check cannot be completed
(a snapshot or a file's header cannot be read) nothing is deleted and the
delete is retried (`VM_DISK_CHECK_FAILED`). The check is not atomic with the
delete, so do not create a snapshot of a VM while you delete another of its
snapshots.

**Overlays kept on purpose.** libvirt 10 merges an external snapshot into its
base when you delete it but leaves the overlay file. After a successful
`SnapshotDelete` the provider removes the overlay (`<domain>-disk.<snapshot>`,
or the `<domain>-disk.<epoch>` a revert created) only when it can prove it is
unused: it is in no backing chain of the VM's current disks, **no other snapshot
of the VM still references it**, it is a regular file directly inside the
storage pool, and no other domain uses it (on a clustered Provider, no domain on
any host of the Provider). If anything cannot be established the file is kept.
Overlays of additional data disks, and overlays left by snapshots deleted before
v0.4.0, are not removed: check the pool for `<domain>-disk*` files that are not
`.qcow2` after a revert or a snapshot delete.

!!! warning "Known limitation: a reused snapshot name can collide with a leftover overlay"
    The overlay of a disk-only snapshot is `<pool>/<domain>-disk.<snapshot name>`.
    If an earlier snapshot of that name left its overlay in the pool, because it
    could not be proven safe to remove (for example a memory snapshot still
    referenced it), a new disk-only snapshot with the **same name** fails in
    libvirt (`external snapshot file for disk vda already exists`).

    - On a **clustered** Provider the answer is a generic error, so the
      `VMSnapshot` never gets a phase: it stays `Ready=False/ProviderError` and
      the create is re-sent about once a minute (after ten re-sends it is held
      as `SnapshotOutcomeUnknown`).
    - On a single-host Provider the refusal is recognised as "not created" and
      the `VMSnapshot` ends `Failed`. This is from the code and was not run in
      the lab.

    **Workaround:** use a new snapshot name. Or, after you have verified that no
    domain definition and no snapshot references the file (`virsh -c "$CONN"
    dumpxml --inactive` of every domain on the host, and `virsh -c "$CONN"
    snapshot-dumpxml` of every snapshot), remove the leftover file; a
    `VMSnapshot` that is still being retried then completes on its next attempt.
    A definite refusal is planned for a later release.

!!! note "Unreadable overlay files"
    libvirt creates snapshot and revert overlays with mode `0600`, owned by root
    while the VM is off. Snapshot create, revert and delete (and VM delete) read
    the disk chain of every domain on the host first. If the provider's SSH user
    cannot read those files, the operation is refused with "permission denied
    reading a disk image". Grant the `VR_DISK_READ` sudo rule over the pool
    directory; see [Libvirt host preparation](../operations/libvirt-host-prepare.md)
    and [unreadable disk images](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/libvirt-clones.md#unreadable-disk-images).

Use an explicit connection when you inspect a host by hand: `virsh -c
qemu:///system ...` (or the Provider's or Host's `qemu+ssh://` endpoint), never a
bare `virsh`, whose default connection is often a different, empty per-user
libvirt instance.

## Upgrade caveat

!!! warning "A stale `revertToRef` is acted on after the upgrade"
    A `VirtualMachine` that already carries `spec.snapshot.revertToRef` (set
    when the field did nothing) is acted on by the first reconcile after you
    upgrade the manager: it is reverted if it is off with
    `spec.powerState: Off` and the snapshot resolves, and otherwise goes
    `Ready=False` with the reason. **Remove the field from VMs you do not want
    reverted before you upgrade the manager.**

    ```sh
    kubectl get vm -A -o json \
      | jq -r '.items[] | select(.spec.snapshot.revertToRef != null) | "\(.metadata.namespace)/\(.metadata.name)"'
    ```

Also:

- Upgrade the **CRDs before the manager**. A manager whose CRD prunes
  `status.snapshotRevert` sends no revert (`SnapshotReverted=False/Unsupported`).
- libvirt: roll the libvirt providers too, and take new snapshots with the VM
  powered off. See the [upgrade guide](../operations/upgrade.md).

## Limits

- `status.currentResources` is not changed by a revert. If the hypervisor
  restores a different CPU or memory size with the snapshot, the manager does
  not notice it.
- A `VMSet` whose template sets `revertToRef` gives every member the same
  `VMSnapshot` name; each member accepts only a snapshot of itself.
- A revert the provider definitely did not perform (for example "not performed:
  could not verify that no other domain uses its disks") is retryable and is
  therefore counted as an unknown outcome: it is sent again and, after 5
  attempts, ends `Failed` with "the VM may or may not have been reverted"
  although nothing changed. Check the VM, then remove the field and set it again.
- While a revert task runs (up to 2 hours) the VM is not powered on or resized,
  even if `revertToRef` is removed.

## See also

- [Advanced VM lifecycle](advanced/advanced-lifecycle.md) and
  [VM Cloning](advanced/vm-cloning.md)
- [Libvirt provider](../providers/libvirt.md)
- [Reverting a VirtualMachine to a VMSnapshot (reference)](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-snapshot-revert.md)
- [libvirt clones, snapshot delete and the delete order (reference)](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/libvirt-clones.md#deleting-memory-and-disk-only-snapshots-of-the-same-vm)
- Example: [`examples/advanced/snapshot-lifecycle.yaml`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/examples/advanced/snapshot-lifecycle.yaml)
