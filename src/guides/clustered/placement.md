<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Clustered libvirt: placement

When you create a `VirtualMachine` on a clustered libvirt Provider, the
manager chooses a host for it. This page describes how that choice is made,
what a `VMPlacementPolicy` can and cannot do, how the choice is recorded on the
VM, and what to do when no host fits.

!!! warning "Experimental in v0.4.2"
    Clustered Providers are experimental. See
    [Clustered libvirt: overview and setup](index.md). The scheduler is
    deliberately simple: it filters hosts, then ranks the survivors. It runs
    **once, when a VM is created**; it does not move a VM that is already
    placed.

## What the scheduler decides

The scheduler is a pure function in
[`internal/scheduler`](https://github.com/projectbeskar/virtrigaud/tree/v0.4.2/internal/scheduler).
The [VirtualMachine controller](https://github.com/projectbeskar/virtrigaud/blob/v0.4.2/internal/controller/virtualmachine_controller.go)
gathers its inputs on the create path:

| Input | Where it comes from |
|-------|---------------------|
| Request | The VM's CPU and memory, from its `VMClass` with any `spec.resources` override applied |
| Candidate hosts | `Host` objects in the **Provider's** namespace with `spec.poolRef` equal to the pool and `spec.providerRef` equal to the Provider; their live `status` |
| Pool policy | The Provider's one `HostPool`: `strategy` and `overcommit` |
| Required networks | One per distinct `VMNetworkAttachment` libvirt identity: `networkName`, or `bridge.name` when `networkName` is empty |
| Policy | The VM's `spec.placementRef`, a `VMPlacementPolicy` in the **VM's** namespace (optional) |
| Committed capacity | Every VM of this Provider, in any namespace, already bound or pending on a host |
| Excluded hosts | `status.placement.excludedHosts` of the VM |

It returns one host, or says why none fits. The manager then sends the
choice to the provider as the create's target host.

### Filters

Every candidate host must pass all hard filters. They run in this order and the
first one that fails is the reason reported for that host:

| # | Filter | Rule |
|---|--------|------|
| 0 | Excluded for this VM | The host is in `status.placement.excludedHosts` |
| 0b | Required host | A migration target whose disk was imported to one host may only run there |
| 1 | Health | `Host.status.health` is `Ready` |
| 2 | Cordon | `Host.spec.schedulable` is `true` (a Host being deleted counts as cordoned) |
| 3 | Policy host lists | `hard.hosts` allow-list, `hard.excludedHosts` deny-list (entries are `Host` names) |
| 4 | Policy node selector | `hard.nodeSelector` matches `Host.spec.labels` |
| 5 | Network | `net.virtrigaud.io/<network>: "true"` on `Host.spec.labels` for every required network |
| 6 | CPU features | `resourceConstraints.requiredFeatures` is a subset of `Host.status.cpuFeatures` |
| 7 | Minimum per host | `minCPUPerHost`, `minMemoryPerHost`, `minDiskSpacePerHost` against the host's **raw** allocatable CPU, memory and storage |
| 8 | Disk space | Migration targets only: `Host.status.allocatableStorageBytes` holds the source disk |
| 9 | Capacity | The request fits in the host's free CPU and free memory (below) |
| 10 | Host (anti-)affinity | `scope: strict` host affinity and host anti-affinity (below) |
| 11 | VM (anti-)affinity | Required VM affinity and anti-affinity terms (below) |

Two checks exist in the scheduler but are **never active for an ordinary VM
in v0.4.2**: a required storage pool (`storage.virtrigaud.io/pool-<name>`) and
a required machine type. The controller does not derive either from a VM, so
those labels and `Host.status.machineTypes` do not influence placement.

### Scoring: Spread and BinPack

Hosts that pass every filter are ranked, in this order of importance:

1. **Preferences.** The sum of the soft bonuses and penalties from the
   `VMPlacementPolicy` (below). A higher sum wins, before any packing
   consideration.
2. **Strategy** (`HostPool.spec.strategy`):
    - `Spread` (default) prefers the host with the most free memory, then the
      most free CPU, then the fewest of the VM's own-namespace VMs already bound.
    - `BinPack` prefers the tightest host that still fits: least free memory,
      then least free CPU, then the most own-namespace VMs.
3. **Host name**, ascending. The final tie-break, so identical inputs always
   give the same host.

"Free" is computed as described under [Committed capacity](#committed-capacity).

The decision is recorded in `status.placement.reason`, for example:

```text
selected host "host-a" via Spread strategy (boundVMs=0, preferenceScore=0) from 2 feasible of 2 candidate host(s), policy "spread-web"
```

The text carries no free-capacity figure, because those come from other
tenants' VMs.

### Committed capacity

```text
free = allocatable × overcommit ratio − committed
```

- **`allocatable`** is the host total from `Host.status.allocatableCPU` and
  `allocatableMemoryMiB` (the logical CPUs and memory of the host). A host that
  has not synced yet reports nothing and therefore fits nothing.
- **The overcommit ratio** (`HostPool.spec.overcommit`, default `1.0`) scales
  the capacity, never the committed sum. A 4-CPU host with `cpu: "2.0"` has 8
  bookable vCPUs. If you later lower a ratio below what is already committed,
  the host takes no new VM until enough VMs leave; no VM is moved.
- **`committed`** is the sum of the footprints of every VM of this Provider
  whose `status.placement.host` or `status.placement.pendingHost` names the
  host, in **every namespace**:
    - a VM being deleted counts until its VirtualMachine finalizer is gone;
    - a VM whose create is pending counts at the size it was scheduled at
      (`status.placement.pendingResources`);
    - a created VM counts at `status.currentResources` (the size the provider
      applied), falling back to its `VMClass` size;
    - a VM with an outstanding resize counts, per resource, at the larger of
      `status.placement.resizeReservation` and its applied size (see
      [Durable resize reservation](#durable-resize-reservation));
    - a VM whose class enables **memory hot-add** counts at its memory
      *ceiling*, 4 times its memory, recorded in
      `status.placement.memoryCeilingMiB` when it was scheduled;
    - a VM whose `VMClass` was deleted, or is not granted to the VM's namespace,
      sizes nothing from the class. It counts from its recorded size
      (`status.currentResources`, or `status.placement.pendingResources` while
      its create is pending) and, while no memory ceiling is recorded for it, at
      the memory hot-add ceiling of that size, because the class's hot-add
      setting is unknown. This over-counts; it never under-counts. **When
      nothing records its size** (a VM bound by a build that did not record
      it), its footprint cannot be established and every capacity admission on
      its Provider (scheduling, resizes, clones and the re-check of inherited
      admissions) is refused and retried with a backoff. The manager logs
      `placed VirtualMachine has no recorded size and its VMClass cannot be
      resolved`, naming the VM, and the hosts' committed-capacity gauges keep
      their last value. Restore the `VMClass`, or the namespace's grant to it,
      to resume. Bound VMs keep being described, powered and deleted;
    - every VM counts at least 1 vCPU and 128 MiB.
- **Not counted:** domains on the host that VirtRigaud does not manage, and the
  hypervisor's own use. To keep room for them, set a ratio below 1 (for
  example `memory: "0.9"`) or cordon the host.

Concurrent creates do not book the same capacity: each clustered create takes
a per-Provider lock, reads what is committed plus the placements other
reconciles have chosen but not yet recorded, picks a host, and records its own
pick before the lock is released. Two VMs with mutually hard anti-affinity do
not land on the same host.

A recorded pick is released only on evidence, never on a timer alone: when the
informer cache shows its `pendingHost` or `host` (for a resize, its
`resizeReservation` or a recorded size that covers it), when the API server
rejected its write, or when an authoritative read resolves a write whose answer
was lost. A pick whose write was never sent is dropped after 2 minutes (a
resize's after 5.5 minutes). One whose write was sent is kept until evidence
settles it, however long that takes, and is reported as stale. While a write is
unresolved the VM is not placed again.

**Resizing a placed VM** is checked the same way. When a `VMClass` or
`spec.resources` change would grow a clustered VM's CPU or memory, the
controller checks that the growth fits in the VM's own host. If it fits, the
admitted size is first written to `status.placement.resizeReservation` (see
[Durable resize reservation](#durable-resize-reservation)) and only then is the
resize sent. If not, nothing is sent, the VM keeps running at its current size, and it gets
`Reconfiguring=False` with reason `InsufficientHostCapacity`; the resize is
retried after 30 seconds, 1 minute, then every 2 minutes. If you withdraw such a
refused resize (set the spec back to the current size), the
`Reconfiguring=False/InsufficientHostCapacity` condition stays until the next
resize ([issue #473](https://github.com/projectbeskar/virtrigaud/issues/473)). It
is stale: nothing is reserved or retried for it, and the phase, `Ready` and the
capacity accounting are not affected. A **shrink** of a
running VM is applied only while it is powered off
(`Reconfiguring=False/ShrinkPendingPowerOff`); VirtRigaud never powers a VM off
by itself to apply one. A change the running domain cannot take is kept in the
domain definition and applies at the next power-off and power-on
(`Reconfiguring=True/RestartRequired`). A resize is sent to a clustered
Provider only if it reports `status.reportedCapabilities.supportsHonestReconfigure`;
otherwise the VM gets `Reconfiguring=False/ProviderLacksHonestReconfigure`
(upgrade the provider image).

### Durable resize reservation

A clustered resize-up is recorded **before** the `Reconfigure` is sent, so a
manager restart or a leader change can never leave a size the provider applied
counted nowhere:

1. Under the per-Provider lock the manager computes the footprint to reserve:
   per resource, the larger of what the VM holds (its recorded size with its
   memory ceiling, and any reservation still outstanding) and what it asks for.
   A change that grows one resource and shrinks the other keeps the shrinking
   one at its held size.
2. It writes that footprint to `status.placement.resizeReservation` with a
   status update checked against the object's version. The `Reconfigure` is
   sent only when the write was stored **and** the API server's answer still
   carries the field. With a CRD older than the field, the API server prunes it:
   nothing is sent and the VM gets `Reconfiguring=False/PlacementError` naming
   the field. The same write sets `Reconfiguring=True` with reason
   `ResizeReserved` (the VM's phase is `Reconfiguring`), replacing any earlier
   outcome, so a `ReconcileSuccess` left by an earlier resize can never release
   the new reservation. Only the `Reconfigure`'s own outcome replaces
   `ResizeReserved`.
3. While the field is set, the VM counts at the larger of it and its recorded
   size, per resource, in placement decisions and in the committed-capacity
   gauges. It is never lowered while set. A later request within the
   reservation goes on under it; one that grows beyond it is admitted for that
   growth only, and written again before it is sent.
4. **Settlement rule.** The reservation is cleared only in a later reconcile in
   which nothing about the VM's size is unresolved: no reconfigure needed or
   due, no reconfigure task, `Reconfiguring=False` with reason `ReconcileSuccess`
   recorded after the reservation was written (the provider confirmed a
   `Reconfigure` sent under it), and a `Describe` that reports the VM's vCPUs
   and memory maximum. Any other state keeps it: a failed, unanswered, partial,
   restart-pending or asynchronous resize; `ResizeReserved` (an outcome never
   recorded, for example because the manager stopped after sending the
   `Reconfigure`); a resize refused before it was sent (such as
   `InheritedAdmissionOverCapacity`); no condition at all; or a reason the
   manager does not know.

```yaml
status:
  placement:
    host: host-a
    resizeReservation: {cpu: 4, memoryMiB: 8192}   # present only while a resize-up is outstanding
  conditions:
    - type: Reconfiguring
      status: "True"
      reason: ResizeReserved
```

**What this guarantees, and what it does not.** A `Reconfigure` is never sent
without a stored reservation, and a reservation is released only on a
confirmation recorded after it was written. There is still no provider-side
fencing: a paused previous manager can send a `Reconfigure` it admitted before
it notices it lost its lease (see
[Admissions inherited from an earlier manager](#admissions-inherited-from-an-earlier-manager)).

#### A withdrawn resize can keep its reservation indefinitely

Setting the VM's size back in its spec withdraws a resize but does **not**
necessarily release its reservation. With the spec back at the recorded size,
nothing is sent, so nothing can confirm the reservation's outcome. It stays, and
keeps counting against the host, when the last `Reconfiguring` reason is one the
manager does not retry by itself:

- `ValidationError`, `InsufficientHostCapacity` or
  `InheritedAdmissionOverCapacity` (a later step was refused after the
  reservation was stored);
- `ResizeReserved` (the manager stopped before recording the outcome, and a new
  manager found the resize already withdrawn).

After `ProviderError` or `ResizePendingPowerOff`, the manager sends the
`Reconfigure` again by itself, so a confirmed result still releases it.

No timer releases a reservation whose outcome is unresolved, because expiring it
could free room that a `Reconfigure` sent earlier may still use. It is released
by the next resize the provider confirms, or when the VM is deleted. The cost is
over-reservation, never an overbooked host. There is **no supported way to
remove one by hand** today. Do not clear it unless you have established that
every manager and provider process that might have sent or received a
`Reconfigure` for the VM has exited, that nothing for the VM still runs on its
host, and that the domain's vCPUs and maximum memory are no more than its
recorded size. VirtRigaud cannot check this for you. A safe recovery mechanism
is tracked in
[issue #468](https://github.com/projectbeskar/virtrigaud/issues/468).

After a restart, a VM whose reservation covers its requested size has its
`Reconfigure` sent again under it without a new admission. The libvirt
provider's `Reconfigure` is synchronous and sets the domain to the requested
size, so repeating a call that already ran changes nothing.

### Admissions inherited from an earlier manager

A pending create, a pending clone target and a resize reservation are durable
admissions: whoever reconciles the VM next acts on them (`Create`, `Clone`,
`Reconfigure`). A manager instance acts at once only on an admission it
recorded or checked itself, matched exactly (VM, Provider, host, recorded size
and memory ceiling, and for a clone the clone it belongs to). Any other one,
after a restart, a leader change, or a write the previous leader sent just
before losing its lease that landed after the new leader had already placed
other VMs, is first checked again under the Provider's lock, against the same
committed capacity as every other decision (the VM's own record is not counted
twice). A bound VM is never checked this way: describing, powering, deleting
and recovering it are unaffected however full its host is, and neither is a
re-attach of a VM whose own domain already runs on the host.

If an inherited admission no longer fits, nothing is sent to the provider, the
record is **kept** and still counts against the host, and the VM gets
`Placed=False` (a create or clone) or `Reconfiguring=False` (a resize) with
reason `InheritedAdmissionOverCapacity`. The message names only the VM's own
size: no host and no capacity figure (the host is in `status.placement`, the
arithmetic in the manager log). It is re-checked with the placement backoff (30
seconds, 1 minute, then every 2 minutes) and proceeds by itself once the host
has room, for example after another VM is deleted, moved or shrunk, or the
pool's overcommit ratio is raised. VirtRigaud never clears an inherited
admission by itself. When it does not clear, see
[An admission held with `InheritedAdmissionOverCapacity`](operations.md#an-admission-held-with-inheritedadmissionovercapacity).

!!! warning "No provider-side fencing"
    The re-check stops the *new* manager from executing an admission that no
    longer fits. It does not stop a paused previous manager that resumes and
    acts on an answer it received before it noticed it lost its lease.

## VMPlacementPolicy

A `VMPlacementPolicy` (short name `vmpp`) is namespaced. A VM opts in with
`spec.placementRef.name`, and the policy must be in the **VM's own
namespace**. A missing policy is an error, not "no policy": the VM stays at
`Provisioning=False/PlacementPolicyNotFound` and is retried every 30 seconds.

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMPlacementPolicy
metadata:
  name: spread-web
  namespace: virtrigaud-system
spec:
  hard:
    excludedHosts: ["host-c"]
    nodeSelector:
      topology.virtrigaud.io/rack: "r7"
  soft:
    hosts: ["host-a"]
  antiAffinity:
    vmAntiAffinity:
      requiredDuringScheduling:
        - topologyKey: kubernetes.io/hostname   # required by the schema, ignored
          labelSelector:
            matchLabels:
              app: web
  resourceConstraints:
    minCPUPerHost: 8          # skip hosts with fewer than 8 logical CPUs
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: web-1
  namespace: virtrigaud-system
  labels:
    app: web
spec:
  providerRef:
    name: libvirt-cluster
  classRef:
    name: small
  imageRef:
    name: ubuntu-22-04
  placementRef:
    name: spread-web
  powerState: "On"
```

The VM's own `metadata.labels` are what other VMs' anti-affinity selectors
match. In this example, a second `web` VM cannot be placed on a host that
already runs one.

### What is wired and what is not

The scheduler reads a subset of the policy. Everything else in the CRD is
accepted by the schema and **has no effect** on a clustered Provider in v0.4.2.

| Field | Effect in v0.4.2 |
|-------|------------------|
| `hard.hosts`, `hard.excludedHosts` | **Hard filter.** Host names; `hosts` is an allow-list when non-empty |
| `hard.nodeSelector` | **Hard filter.** Each key/value must equal `Host.spec.labels` |
| `soft.hosts` | Score **+50** per host listed |
| `soft.excludedHosts` | Score **-50** per host listed (a preference, not a filter) |
| `soft.nodeSelector` | Score **+10** per matching entry |
| `resourceConstraints.requiredFeatures` | **Hard filter** against `Host.status.cpuFeatures` |
| `resourceConstraints.preferredFeatures` | Score **+10** per feature present |
| `resourceConstraints.minCPUPerHost`, `minMemoryPerHost`, `minDiskSpacePerHost` | **Hard filter** against the host's raw allocatable CPU, memory and free `default`-pool storage |
| `affinity.hostAffinity` | `enabled: true`: hosts in `preferredHosts` score **+100**. With `scope: strict`, hosts not in `preferredHosts` are **filtered out** |
| `antiAffinity.hostAntiAffinity` | `enabled: true`: a host at the cap (`maxVMsPerHost`, default **1**) scores **-100**. With `scope: strict` it is **filtered out** |
| `affinity.vmAffinity`, `antiAffinity.vmAntiAffinity` | `requiredDuringScheduling` terms are **hard filters**; `preferredDuringScheduling` terms add (affinity) or subtract (anti-affinity) the term's `weight` |
| `labelSelector`, `matchExpressions` in a VM term | Matched against the labels of already-placed VMs on each host. Both must match when both are set; an empty term matches every VM |
| `priority`, `weight` | **Ignored** |
| `hard.clusters`, `datastores`, `folders`, `resourcePools`, `networks`, `zones`, `regions`, `tolerations`, `excludedClusters`, `excludedDatastores` (and the same under `soft`) | **Ignored.** These are the vSphere/Proxmox vocabulary; the flat host model has no such topology. Express a rack or zone as a `Host` label and select it with `nodeSelector` |
| `affinity` / `antiAffinity` for cluster, datastore, zone, application | **Ignored** |
| `resourceConstraints.maxCPUUtilization`, `maxMemoryUtilization`, `maxDiskUtilization` | **Ignored.** `Host.status` carries no live utilization |
| `securityConstraints` (all fields) | **Ignored.** `Host.status` does not report secure boot, TPM, encryption or NUMA. Label the hosts and use `nodeSelector` |
| `status` (`usedByVMs`, `placementStats`, `validationResults`, ...) | **Never written.** No controller reconciles `VMPlacementPolicy` objects |

Details that matter:

- **`scope` is hard only when it is exactly `strict`.** Any other value,
  including unset, is a preference, so a mis-set scope cannot make every host
  infeasible. The schema allows `strict` and `preferred`.
- **VM (anti-)affinity works at host granularity.** `topologyKey` is required
  by the schema but ignored, as are `namespaces` and `namespaceSelector`. Only
  VMs in the **new VM's own namespace** are matched by VM terms and counted
  towards the host anti-affinity cap; VMs in other namespaces still take up
  capacity but their labels are never matched.
- **A policy is read when a VM is scheduled.** The VirtualMachine controller
  does not watch `VMPlacementPolicy`, `Host` or `HostPool` objects, so an
  unschedulable VM sees an edit on its next retry (up to 2 minutes), and
  editing a policy never moves a VM that is already placed.
- **`spec.placement` is not placement for a clustered Provider.** The
  `VirtualMachine.spec.placement` hints (cluster, datastore, folder) are the
  vSphere/Proxmox vocabulary and do not influence the host choice. To pin a VM
  to a host, use `hard.hosts` in a policy.
- A malformed input the scheduler cannot evaluate, an unparseable or
  non-positive overcommit ratio or a malformed label selector, is
  `Provisioning=False/PlacementError`, retried every 30 seconds, until you
  correct the pool or policy.

## Placement binding

The scheduler decides; the binding records the decision durably on the VM.

```yaml
status:
  placement:
    host: host-a                  # the Host (CR name) the VM runs on
    pool: pool-a
    lastScheduledTime: "2026-10-01T09:00:00Z"
    reason: 'selected host "host-a" via Spread strategy ...'
    # present only while a create is unconfirmed:
    pendingHost: host-a
    pendingResources: {cpu: 2, memoryMiB: 2048}
    memoryCeilingMiB: 0
    # present only while a resize-up is outstanding:
    resizeReservation: {cpu: 4, memoryMiB: 8192}
    # present only after a name conflict:
    excludedHosts: [host-b]
```

`kubectl get virtualmachine <name> -o jsonpath='{.status.placement}'` shows it.
Only the operator writes it. Never grant tenants write access to
`virtualmachines/status`: the capacity accounting trusts it.

### The sequence of a create

1. The scheduler picks a host.
2. Before any provider call, the manager writes `status.placement.pendingHost`
   (with `pool`, `reason`, `pendingResources` and `memoryCeilingMiB`) in a
   status update that is checked against the object's version. If that write
   loses a race, the reconcile requeues **without** creating anything.
3. The create is sent to `pendingHost`.
4. When the provider confirms, the host moves into `status.placement.host`,
   `pendingHost` is cleared, and `Placed` becomes `True` with reason `Bound`.
   The binding is written **only after** the provider confirms, so
   `status.placement.host` never names a host that has not accepted the VM.

A retry after a lost status write, or after a create that ran past its
deadline, **reuses `pendingHost`** and never re-runs the scheduler. It lands on
the same host, where the domain's owner stamp makes the second attempt an
idempotent success. This is also why an unreachable pending host does not cause
a re-schedule: a domain may already exist there, and creating another elsewhere
could leave two copies. The VM shows `Placed=False/HostUnavailable` and waits
for the host, or for an administrator to clear `status.placement.pendingHost`.

While `pendingHost` is set the VM counts against that host's capacity, and
the CRD locks two fields:

| Rule | Error |
|------|-------|
| `spec.classRef` and `spec.resources` cannot change while a clustered create is pending (`pendingHost` set, `status.id` empty) | `spec.classRef and spec.resources are immutable while a clustered create is pending` |
| `spec.providerRef` cannot change once the VM is bound (`status.id` or `pendingHost` is set) | `spec.providerRef is immutable once the VirtualMachine is bound` |

If the `VMClass` itself is edited while a create is pending so that the retried
create would be larger (or gain memory hot-add), the retry is **not** sent: the
VM gets `Placed=False` and `Provisioning=False` with reason `PendingSizeGrew`
and keeps its pending host until the `VMClass` is restored or the VM is
deleted.

### Excluded hosts

If a create is refused with a plain name conflict (`AlreadyExists`: a
same-named libvirt domain that this VM does not own exists on the pending host),
the provider checked that before creating anything, so this VM has nothing on
that host. The manager clears `pendingHost`, adds the host to
`status.placement.excludedHosts`, sets `Placed=False/HostExcluded`, and
schedules the VM again; the scheduler never picks an excluded host.

- The list holds at most 16 hosts; when full, the oldest entry is dropped and
  the next attempt waits 2 minutes. It is cleared when the VM is bound.
- If **every** candidate is excluded, the VM shows
  `Placed=False/AllHostsExcluded`, nothing is sent, and it is re-checked every 2
  minutes. Resolve the name conflicts (or rename the VirtualMachine), then
  clear the list:

    ```bash
    kubectl patch virtualmachines.infra.virtrigaud.io <name> -n <ns> \
      --subresource=status --type=json \
      -p '[{"op":"remove","path":"/status/placement/excludedHosts"}]'
    ```

- A conflicting domain stamped with this VM's own namespace and name under
  **another UID** is not a plain name conflict. It is a previous incarnation
  (a restore, or an earlier delete with `orphan-on-delete`); the VM is held
  with `RestorePending` instead of moved. See
  [Backup, restore and re-attach](backup-restore.md).

### Topology is immutable

`Provider.spec.topology` cannot change after creation, because VMs record where
they run under one topology and every per-VM call is routed by it. If a VM
nevertheless records a clustered placement while its Provider is not
`topology: cluster` (an object edited by hand), the manager fails it closed:
no provider call is made for it and it shows `Ready=False`,
reason `PlacementTopologyMismatch`. Its finalizer is kept unless
`virtrigaud.io/force-delete: "true"` is set.

### VMClass bounds

The sizes the scheduler works with are bounded by the schema:

| Quantity | Bound |
|----------|-------|
| `VMClass.spec.cpu` | 1 to 128 |
| `VMClass.spec.memory` | non-negative, below 10^14 bytes (about 90.9 TiB; the CRD message says 100Ti) |
| `status.placement.pendingResources` | CPU at most 128, memory at most 100 TiB (104857600 MiB) |
| `status.placement.resizeReservation` | Same bounds as `pendingResources` |
| `status.placement.memoryCeilingMiB` | 0 to 104857600 |
| Footprint of any VM in the accounting | at least 1 vCPU and 128 MiB |

A `VMClass` or `VMImage` in another namespace that the VM's namespace may not
use (no `consumerNamespaceSelector` grant) sizes nothing: another VM's
footprint is never taken from a class its owner could not have used.

## Unschedulable and related reasons

When no host fits, the VM gets `Placed=False` and `Provisioning=False`, both
with reason `Unschedulable`, and a message such as:

```text
no feasible host in pool "pool-a": no feasible host: 0 of 3 candidate host(s) passed the filters
[insufficient CPU capacity: 3]; requested 4 vCPU and 4096 MiB, which exceeds the free capacity
of every candidate host
```

The message shows how many hosts each filter eliminated and the VM's own
request. It never names a host or another VM and carries no committed or free
figure. The administrator's per-host arithmetic is in the manager log
(verbosity 1) and in the
[committed-capacity metrics](operations.md#metrics-and-alerts). The VM is
retried after 30 seconds, then 1 minute, then every 2 minutes until something
changes. Nothing watches hosts or other VMs, so a freed host is noticed within
2 minutes.

```bash
kubectl describe virtualmachine <name> -n <ns>      # Placed and Provisioning messages
kubectl get hosts,hostpools -n <provider namespace>
```

### Rejection categories

The text inside `[...]` is a rejection category and a count of hosts it
eliminated:

| Category | Cause | What to do |
|----------|-------|------------|
| `pool has no candidate hosts` | No `Host` in the pool names this Provider | Create or fix the `Host` objects (`providerRef`, `poolRef`, same namespace as the Provider) |
| `host not Ready` | `Host.status.health` is `NotReady` or `Unknown` | `kubectl describe host <name>`; see [Operations](operations.md#troubleshooting): SSH, `known_hosts`, credentials, provider pod |
| `host cordoned (schedulable=false)` | `Host.spec.schedulable` is `false`, or the Host is being deleted | Uncordon: `kubectl patch hosts.infra.virtrigaud.io <name> -n <ns> --type merge -p '{"spec":{"schedulable":true}}'` |
| `host not in hard host allow-list` | The policy's `hard.hosts` does not list the host | Fix the policy, or add the host |
| `host in hard excluded-hosts list` | The policy's `hard.excludedHosts` lists it | Fix the policy |
| `host labels do not match hard nodeSelector` | A `hard.nodeSelector` entry is not in `Host.spec.labels` | Add the label to `Host.spec.labels` (not `metadata.labels`) or fix the selector |
| `host does not have a required network` | No candidate has `net.virtrigaud.io/<network>: "true"` for a network the VM uses | Patch `Host.spec.labels`; see the [first VM checklist](index.md#first-vm-checklist). Use the `networkName` (or `bridge.name`) of the `VMNetworkAttachment` |
| `host missing a required CPU feature` | `requiredFeatures` is not a subset of `Host.status.cpuFeatures` | `kubectl get host <name> -o jsonpath='{.status.cpuFeatures}'`; fix the policy or use hosts that have the feature |
| `host below a required minimum-per-host resource` | A `min...PerHost` floor is above the host's raw allocatable | Fix the floor, or add a larger host. For `disk`, the figure is the free space of the `default` pool |
| `insufficient CPU capacity` / `insufficient memory capacity` | The request does not fit in free capacity (`allocatable × ratio − committed`) on any host | Delete or shrink VMs, add a host, raise `HostPool.spec.overcommit`, or use a smaller `VMClass` |
| `insufficient storage for the VM's disk` | Migration target only: no host reports enough free space in its `default` pool | Free space on a host; see [Migrating into a clustered Provider](../../migration/clustered-target.md) |
| `host not in the strict host-affinity set` | Strict `hostAffinity`, and the host is not in `preferredHosts` | Fix the policy |
| `host at the strict host-anti-affinity VM cap` | Strict `hostAntiAffinity`, and the host already holds `maxVMsPerHost` (default 1) of the namespace's VMs | Raise `maxVMsPerHost`, add hosts, or make the rule `preferred` |
| `host does not satisfy a required VM-affinity term` | No VM matching the term runs on the host | Fix the term or place the matching VM first |
| `host runs a strict anti-affine VM` | A VM matching a required anti-affinity term runs on the host | Fix the term, or add hosts |
| `host excluded for this VM` | The host is in `status.placement.excludedHosts` | See [Excluded hosts](#excluded-hosts) |
| `not the host the VM's disk was imported to` | A migration target must run where its disk landed | See [Migrating into a clustered Provider](../../migration/clustered-target.md) |

### Other placement reasons

These are not scheduler rejections but appear on the VM's `Provisioning` or
`Placed` condition for the same path:

| Condition / reason | Meaning | What to do |
|--------------------|---------|------------|
| `Provisioning=False/NoHostPool` | The Provider has no `HostPool` in its namespace. Retried every 30 s | Create the pool |
| `Provisioning=False/MultipleHostPools` | More than one pool names the Provider; exactly one is supported | Delete the extras |
| `Provisioning=False/PlacementPolicyNotFound` | `spec.placementRef` names a missing policy in the VM's namespace. Retried every 30 s | Create the policy or remove the reference |
| `Provisioning=False/PlacementError` | Unparseable or non-positive overcommit ratio, or a malformed label selector. Retried every 30 s | Correct the pool or policy |
| `Placed=False/CreatePending` | `pendingHost` is recorded and the provider has not confirmed the create yet | Normal and transient. If it persists, check the provider pod and `kubectl describe` for the provider error |
| `Placed=False/HostUnavailable` | The pending (or bound) host is not reachable. The VM is never re-scheduled automatically | Restore the host; see [Operations](operations.md#a-host-that-stops-answering) |
| `Placed=False/Unbound` | The VM has a provider id but no confirmed host (for example a restore dropped its status). No per-VM call is made; re-checked every 30 s | See [Backup, restore and re-attach](backup-restore.md) |
| `Placed=False/HostExcluded`, `AllHostsExcluded` | See [Excluded hosts](#excluded-hosts) | |
| `Placed=False/RestorePending`, `OwnDomainOnAnotherHost` | A previous incarnation, or the VM's own domain on another host, holds it | See [Backup, restore and re-attach](backup-restore.md) |
| `Placed=False/PendingSizeGrew` | The `VMClass` grew while the create was pending | Restore the class or delete the VM |
| `Placed=False/InheritedAdmissionOverCapacity` | A pending create or clone target recorded by an earlier manager no longer fits its host. Nothing is sent; the record is kept and keeps counting. Re-checked on the placement backoff (up to 2 minutes) | Free room on the recorded host; see [Admissions inherited from an earlier manager](#admissions-inherited-from-an-earlier-manager) |
| `Reconfiguring=False/InheritedAdmissionOverCapacity` | The same, for a resize reservation | Same |
| `Ready=False/VMMissingOnHost` | The bound host reports no domain for this VM. It is **not** re-created, on that host or elsewhere, because without fencing that could give two copies of one disk. Re-checked every 2 minutes | Restore the domain on the host, or delete and re-create the `VirtualMachine` |
| `Ready=False/PlacementTopologyMismatch` | See [Topology is immutable](#topology-is-immutable) | |

## Limits to plan around

- One `HostPool` per Provider, and the scheduler runs only at create. A bound
  VM is never moved by the scheduler, whether its host is cordoned, `NotReady`
  or gone.
- `HostPool.spec.storagePools`, `networks` and `migration`, and storage-pool and
  machine-type labels, do not influence placement.
- Capacity accounting sees only VirtRigaud-managed VMs. Other domains on a host
  take real memory the scheduler does not know about.
- There is no per-tenant quota: tenants share the pool first come, first served.
- There is no provider-side fencing of a previous manager: see
  [Admissions inherited from an earlier manager](#admissions-inherited-from-an-earlier-manager).
- A withdrawn resize can keep its reservation indefinitely, and v0.4.2 has no
  automatic recovery for it
  ([issue #468](https://github.com/projectbeskar/virtrigaud/issues/468)); see
  [above](#a-withdrawn-resize-can-keep-its-reservation-indefinitely).
- A withdrawn refused resize keeps a stale `InsufficientHostCapacity`
  condition until the next resize; it reserves nothing
  ([issue #473](https://github.com/projectbeskar/virtrigaud/issues/473)).
- Placement decisions are serialized per Provider.
- The scheduler does not consider firmware. A VMClass with `firmware: UEFI` or `securityProfile.secureBoot` needs an OVMF package on the host the VM is placed on; a VM placed on a host without one is refused (`ValidationError`) and is re-checked on that host (it keeps its pending host, and is never moved to another). Install the package on every host that can receive such a VM, or delete the VM. On a pool whose hosts have different OVMF packages, VMs of one VMClass can get different firmware builds. See [libvirt: firmware](../../providers/libvirt.md#firmware-secure-boot-and-platform-features).
