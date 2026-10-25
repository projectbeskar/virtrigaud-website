<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Clustered libvirt: operations and troubleshooting

This page is for running a clustered libvirt Provider after it works: what the
manager does for a VM after placement, what happens when a host stops
answering, how to cordon a host, the guard that protects disks on shared
storage, how to let go of a VM, which metrics to watch, and a troubleshooting
table.

!!! warning "Experimental in v0.4.0"
    Clustered Providers are experimental; see
    [Clustered libvirt: overview and setup](index.md). VirtRigaud detects and
    reports a failed host. It does **not** restart VMs on another host.

## Routed, owner-checked lifecycle

After a VM is placed, the manager sends **every** call for it to the host in
`status.placement.host` and sends the VM's identity (UID, namespace, name) with
it. The provider checks the identity against the **owner stamp** stored in the
libvirt domain's metadata before it reads or changes anything. A domain whose
stamp is missing, unreadable or belongs to another UID is answered
`NotFound`, and the domain is not touched. Domains are named
`<namespace>.<name>` on the host. See
[Security model and multi-tenancy](../security-model.md) for the ownership
model.

What a clustered libvirt Provider routes in v0.4.0:

| Operation | Behaviour on a clustered Provider |
|-----------|-----------------------------------|
| Create | Sent to the host chosen by the scheduler (`status.placement.pendingHost`). A same-named domain there that this VM does not own is refused (`AlreadyExists`); a disk file that exists where the VM's disk goes is overwritten only if no domain on **any** host of the Provider uses it |
| Describe | Routed and owner-checked. A domain that is absent, or not this VM's, is reported as not existing, with none of its state read |
| Power (on, off, reboot, graceful shutdown) | Routed and owner-checked; addressed by the domain's UUID so a domain replaced after the check is not acted on |
| Reconfigure (CPU, memory, disk grow) | Routed and owner-checked. Online where the running domain allows it, otherwise applied at the next power cycle (`RestartRequired`) |
| Delete | Routed and owner-checked, plus a check of **every other host** of the Provider for a domain using the VM's disk files (below) |
| Snapshot create, delete, revert | Routed and owner-checked, by UUID. Memory snapshots work as on a single host. Each refuses while another domain on the host depends on one of the VM's disks (a linked clone's overlay) |
| Clone | **Full clones only**, to the source VM's own host, owner-checked on the source. Linked clones are refused. The source must be powered off; the clone gets its own seed ISO and cloud-init identity. See [VM cloning](../advanced/vm-cloning.md) |
| Disk info, disk export | Owner-checked. Export supports the host-side backends `s3` and `nfs` (used by migration); `pvc` is refused |
| List VMs | Runs on **every routable host** (8 at a time, 60 s each). Each entry carries its host. A host that could not be listed is reported as *unknown*, not empty |
| Import disk, delete landed disk, delete staged disk | Routed to the target VM's host, for migration into a clustered Provider; see [Migrating into a clustered Provider](../../migration/clustered-target.md) |
| Hardware upgrade, image preparation | `Unimplemented` |

Details that change what you see:

- **A domain stamp mismatch is "not found".** If the bound host reports the
  VM missing, or the domain there is not this VM's, the VM shows
  `Ready=False/VMMissingOnHost` and is **not re-created**, on that host or
  elsewhere. It is re-checked every 2 minutes, so a domain you restore is
  picked up. (Single-host VMs keep the historical re-create behaviour.)
- **An unbound clustered VM gets no per-VM calls.** A VM with a provider id
  but no confirmed host (for example after a restore dropped its status) shows
  `Placed=False/Unbound` and is re-checked every 30 seconds.
- **Time budgets.** `Clone`, `SnapshotCreate` and `ExportDisk` run under a
  budget that ends 15 s before the manager's deadline (5 min for clone and
  snapshot create, 30 min for export). Their long `qemu-img` steps run on the
  host under `flock` and `timeout`, so a retry while an earlier copy still runs
  is answered "the same copy is still running" (retryable) instead of starting
  a second copy. A failed or stopped clone or export leaves no partial copy of
  the tenant's disk on the host.
- **A snapshot create is idempotent per request.** The manager sends the
  `VMSnapshot` UID as a request token; a snapshot of the same name that was
  made by something else is `AlreadyExists` and is never adopted or replaced.
- **Errors in tenant-visible conditions are categorized.** They carry the
  operation and the host name, for example `failed to create snapshot on host
  "host-b"`. The cause (SSH address, virsh output, paths) is in the provider
  log only.

## A host that stops answering

Hosts fail in different ways, and the provider answers by **how far the call
got**. The manager reads these answers; you see them as conditions.

### What VirtRigaud does and does not do

- It marks the `Host` `NotReady` (or `Unknown` when the provider itself is
  unreachable) on the next heartbeat, at most about a minute later, and the
  scheduler stops placing new VMs on it.
- It keeps retrying calls for VMs on that host with a backoff.
- It does **not** restart or move VMs, and does not re-schedule a VM whose
  create is pending there. Without fencing, an unreachable host may still be
  running the domain; starting a second copy on shared storage can corrupt the
  disk.
- It keeps counting the host's VMs in its committed capacity.
- It does not let one dead host degrade the others: host-scoped failures are
  kept out of the Provider's circuit breaker. A Provider-level `Unavailable`
  (the provider pod down) does count.

### Outcomes

| How far the call got | Provider answer | What the manager treats it as |
|----------------------|-----------------|-------------------------------|
| The host is unknown, draining, cannot be dialed, or no command of the call was answered and none that could change the host was sent | `Unavailable` + `HOST_UNAVAILABLE` | Nothing was done |
| The host answered something, then stopped, and only reads had run | `Unavailable` + `VM_OPERATION_FAILED` + `HOST_CONNECTION_LOST` | Not performed |
| A command that may change the host was sent, then the host stopped answering | `Unknown` + `VM_OPERATION_FAILED` + `HOST_CONNECTION_LOST` | Outcome unknown |
| The same, for a call that is safe to send again (`SnapshotCreate` with a request token, `Clone`) | `Unavailable` + `VM_OUTCOME_UNKNOWN_RETRY` + `VM_OPERATION_FAILED` + `HOST_CONNECTION_LOST` | Retry on the same host; outcome unknown, not "nothing done" |
| The host answered, and the command failed | `VM_OPERATION_FAILED` with the historical code | An ordinary failure of that operation |

`Describe`, `GetDiskInfo` and `TaskStatus` only read, so they always answer
`HOST_UNAVAILABLE`. Waits for a host command slot, the SSH dial or an SSH
session end 5 seconds before the call's deadline and count as a host that
stopped answering. The full model, including which commands count as "may
change the host", is in
[Provider calls whose outcome was lost](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/provider-call-outcomes.md#clustered-libvirt-a-host-that-stops-answering).

### What each VM shows

| Call | While the VM's host does not answer |
|------|-------------------------------------|
| Describe, Power, Reconfigure | `Ready=False/HostUnavailable`, re-checked every 30 s. A `Reconfigure` that failed is counted at the larger of the old and requested size |
| Create | `Placed=False/HostUnavailable`, retried on the **same** pending host with a backoff (15 s doubling to 5 min). Never re-scheduled |
| Delete | The finalizer is kept. `DeleteBlocked=True/HostUnreachable` and `Ready=False/DeleteBlocked`, one `Warning` event `DeleteBlocked`, retried with a backoff (15 s doubling to 5 min). When the provider says the VM's own host is the one that failed, the message names it |
| Clone | The target stays `Pending`; retried on the same host with a backoff (`CloneRetrying`, `HostUnavailable`). A clone whose host is cordoned, `NotReady` or gone waits with `SourceHostCordoned`, `SourceHostNotReady` or `SourceHostGone` |
| Snapshot create | Retried and never failed on a lost connection; outcome-unknown answers keep the request marker |
| Snapshot delete | Finalizer kept, retried with a backoff |

When the host answers again, the next retry succeeds and the condition clears.

### A delete is held while *any* host is unreachable

A clustered `Delete` always has files to remove, and before it removes anything
the provider checks every **other** host of the Provider for a domain using
those files (see [the next section](#shared-storage-the-cluster-wide-disk-guard)).
That check fails closed: **while any host of the Provider cannot be reached
(or cannot be rendered into the inventory), deleting a clustered VM is held**,
even a VM on a healthy host. The VM shows `DeleteBlocked=True` with reason
`HostUnreachable` or `DiskCheckFailed`, and the message names no host unless
the VM's own host is the one that failed.

Ways out, in order of preference:

1. **Bring the host back.** The next retry (up to 5 minutes) completes the
   delete.
2. **Detach the VM** with `virtrigaud.io/orphan-on-delete` or release it with
   `virtrigaud.io/force-delete` (both act at once, whatever the backoff). The
   domain and its disks stay on the host for manual removal; see
   [Detaching a VM](#detaching-a-vm-orphan-on-delete-and-force-delete).
3. **Remove the dead host from the Provider**, after fencing it (below).

### If a host is gone for good

1. **Fence it first.** Power it off, or revoke its access to the shared
   export. A host that is merely unreachable *from the provider* may still run
   domains on the shared pool. Once it leaves the inventory the disk guard no
   longer looks at it, and a delete or a re-create elsewhere could remove or
   overwrite a disk it is using.
2. Release each VM bound to it: `orphan-on-delete` (or `force-delete`, which
   needs the Provider's permission for VMs in other namespaces).
3. Delete the `Host`. It cannot be deleted while any VM of the Provider names
   it in `status.placement.host` or `status.placement.pendingHost`; the Host
   shows `Ready=False/HostInUse` with the number of VMs and at most 10 of their
   names, and is re-checked every 30 seconds.
4. Re-creating a released VM under the same namespace and name is held with
   `Placed=False/RestorePending` while an old domain of that name still exists
   on a host the Provider fronts. See
   [Backup, restore and re-attach](backup-restore.md).

A VM whose create is pending on a host that is gone for good can also be
released by clearing `status.placement.pendingHost` through the status
subresource. Do this only after fencing the host: the operator never
re-schedules such a VM on its own because a domain may already exist there.

## Cordon: `spec.schedulable`

```bash
# cordon: no new VMs are placed on host-a; VMs already there stay and keep working
kubectl patch hosts.infra.virtrigaud.io host-a -n virtrigaud-system \
  --type merge -p '{"spec":{"schedulable":false}}'

# uncordon
kubectl patch hosts.infra.virtrigaud.io host-a -n virtrigaud-system \
  --type merge -p '{"spec":{"schedulable":true}}'
```

`kubectl get hosts` shows the `SCHEDULABLE` column, and the pool's
`SCHEDULABLE` count drops by one. Cordon is a scheduler filter and nothing
more:

- Existing VMs are **not** moved or stopped, and calls for them (describe,
  power, reconfigure, snapshot, delete) still go to the cordoned host.
- A create already recorded as pending on the host is retried there; it is not
  re-scheduled.
- A resize of a VM on the host is checked against the host's capacity as
  usual; the cordon does not matter, because a resize does not move the VM.
- A `VMClone` whose source VM is on the host waits (`SourceHostCordoned`),
  because a clone can only land on its source's host.
- A `Host` that is being deleted is treated as cordoned.

Because there is no host-to-host migration, "draining" a host means
shutting down or deleting its VMs and re-creating them elsewhere. Cordon the
host first so that the re-created VMs do not return to it.

## Shared storage: the cluster-wide disk guard

The hosts of one clustered Provider may mount the same storage pool (an NFS
export at `/var/lib/libvirt/images`). A disk file is then visible and writable
from every host, but each host's libvirtd knows only its own domains. Without
a guard, creating `team-a/web` on host B could overwrite the disk of a
`team-a.web` domain still running on host A (left by `orphan-on-delete`, a
force-delete, or the original of a VM restored with a new UID), and deleting a
VM on host B could remove a disk a domain on host A is using.

The provider therefore checks **every host of the Provider** before it writes
or removes a VM's disk:

| Operation | Check |
|-----------|-------|
| Create, clone | If a disk file of the VM already exists in the pool (under any name the VM's disk may have had), every host is scanned. A domain on any host stamped with the VM's namespace and name under another UID is a **previous incarnation**: the create is refused (`VM_PREVIOUS_INCARNATION`) and the VM is held at `RestorePending`. A file used by another domain is refused (`AlreadyExists`) and the host is excluded for the VM. An unused leftover is replaced |
| Create from a host-path image | Every other host is scanned for a domain using the image file. A use refuses the create; a host that cannot be checked fails it closed. So every such create waits while any host of the Provider is unreachable (creates from a URL or a template do not) |
| Delete | Before anything is destroyed, undefined or removed, every other host is scanned for a domain using one of the files. A use refuses the delete (`DeleteBlocked=True/DiskInUse`) |

What the scan can answer, and what the VM shows:

| Scan result | VM shows |
|-------------|----------|
| Previous incarnation found | `Placed=False/RestorePending`; pending host kept |
| Another domain uses the file (create) | `Placed=False/HostExcluded`; re-scheduled elsewhere |
| Another domain uses the file (delete) | `DeleteBlocked=True/DiskInUse`, re-checked every minute |
| A host could not be reached | Create: `Placed=False/HostUnavailable`. Delete: `DeleteBlocked=True/HostUnreachable` |
| A host answered but could not be scanned (unreadable definition, more than 2000 domains, provider busy) | Create: `Placed=False/CreatePending`, retried. Delete: `DeleteBlocked=True/DiskCheckFailed` |
| Nothing uses the file | The operation proceeds |

None of these counts toward the Provider's circuit breaker, and their messages
name no host, path or other domain.

Rules to keep the guard meaningful:

- **One Provider per shared pool.** The guard sees the hosts of one Provider.
  Never mount the pool on hosts of another Provider, a single-host Provider or
  anything VirtRigaud does not manage.
- **Same path, NFS locking.** Mount the pool at the **same path** on every
  host, with NFS locking enabled (NFSv4, or NFSv3 with `lockd`/`statd`). QEMU's
  image locks are what stop two running domains from opening one disk.
- **Keep the image catalog apart from the pool.** Set
  `VIRTRIGAUD_LIBVIRT_IMAGE_DIRS` (through the Provider's `spec.runtime.env`)
  to a directory that is not the pool.
- **Directories sticky or private.** A routed copy writes into the pool
  directory. If it is writable by a local user other than root and the SSH user
  and has no sticky bit, the provider logs a `WARN` once per host and
  directory. Fix it with `chmod +t <dir>`.
- **Not matched:** a host that mounts the same export under a *different* path,
  a second mount, a bind mount or a hard link, and disks without a host path
  (NBD, RBD, iSCSI). On *host-local* pools the same path on two hosts is two
  files, so a domain on another host with the same path is reported as a use;
  that is a false "in use" that fails safe.
- **Cost.** A scan reads every domain's definition on each host, so a clustered
  delete costs roughly one SSH command per domain of the Provider.

## Detaching a VM: orphan-on-delete and force-delete

To stop managing a VM but leave the domain running, annotate it and delete it:

```bash
kubectl annotate virtualmachine web-1 -n virtrigaud-system virtrigaud.io/orphan-on-delete=true
kubectl delete virtualmachine web-1 -n virtrigaud-system
```

The finalizer is removed **without** calling the Provider. The domain, its
disks and its owner stamp stay on the host; the manager records a `Normal`
event `Orphaned`. The annotation is read when the deletion is processed, so it
works on a VM that is already being deleted and held.

On a clustered Provider this has a cost you should know about: a detached VM
keeps running but **no longer counts toward its host's committed capacity**, so
the scheduler will place other VMs into capacity it still uses. Cordon the
host or lower its overcommit ratio until the leftover domain is removed. It
also means that a VM re-created under the same namespace and name is held at
`RestorePending` until the old domain is re-attached or removed (see
[Backup, restore and re-attach](backup-restore.md)).

`virtrigaud.io/force-delete: "true"` releases the finalizer when the provider
`Delete` keeps failing or is held (`HostUnreachable`, `DiskCheckFailed`,
`DiskInUse`, `OwnDomainOnAnotherHost`, `ProviderUnavailable`), or when no
delete can be routed (an unbound clustered VM, `PlacementTopologyMismatch`).
If the delete was not confirmed, the manager records a `Warning` event
`VMLeftOnHypervisor`. It is an escape hatch; to detach on purpose, use
`orphan-on-delete`.

**VMs in other namespaces need the Provider's permission.** Both annotations
leave a domain outside the accounting, so for a VM in a namespace other than
its clustered Provider's they are honoured only if the Provider carries:

```yaml
metadata:
  annotations:
    infra.virtrigaud.io/allow-consumer-orphan-on-delete: "true"
```

Without it, an `orphan-on-delete` deletion is held (`Ready=False/OrphanOnDeleteNotAllowed`,
re-checked every 2 minutes). A `force-delete` is **ignored**: the VM gets
`ForceDeleteRefused=True/ForceDeleteNotAllowed`, one `Warning` event
`ForceDeleteNotAllowed`, and the delete keeps being retried as if the annotation
were not set. A VM in the Provider's own namespace and every VM of a
single-host Provider are unaffected.

A clustered delete is also held, with `DeleteBlocked=True/ProviderUnavailable`,
when the manager cannot reach the **Provider** itself. That includes every
Provider rollout and restart, because a clustered provider runs one replica
with the `Recreate` strategy. The delete completes on the first retry after the
Provider answers.

## Listing and adopting existing domains

With the annotation `virtrigaud.io/adopt-vms: "true"` on the Provider,
VirtRigaud lists domains on every host and creates `VirtualMachine` objects for
the ones it does not manage. On a clustered Provider:

- A VM is identified by (host, domain id), so the same name on two hosts is two
  entries. Adopted `VirtualMachine`s are named after the domain plus a short
  digest of (host, id), for example `team-a-web-3f2a9c1b04`.
- **Only unstamped domains are adopted.** A domain with a VirtRigaud owner
  stamp whose VirtualMachine no longer exists is a previous incarnation; it is
  skipped and named in `Provider.status.adoption.message`, to be re-attached or
  removed.
- **Unknown is not empty.** A host that could not be listed is named in
  `status.adoption.message`; **nothing new is adopted while any host is
  unknown**, and discovery is retried after 5 minutes. Adoption never unbinds
  or deletes anything because a VM is missing from a list.
- A domain whose UUID is on more than one host, or one of whose disk paths a
  VM on another host uses, is skipped.
- Do not front one hypervisor with both a single-host and a clustered
  Provider, and keep one clustered Provider per host endpoint.

## Metrics and alerts

Scrape the manager (`/metrics`, port 8080, plain HTTP unless the manager runs
with `--metrics-secure=true`) and the provider pods. The manager's general
metrics are described in [Observability](../../operations/observability.md)
and the [metrics reference](../../api-reference/metrics.md).

| Metric | Source | Labels | Use |
|--------|--------|--------|-----|
| `virtrigaud_host_committed_cpu` | Manager | `provider` (`namespace/name`), `host` | vCPUs the scheduler counts as committed on a host |
| `virtrigaud_host_committed_memory_mib` | Manager | `provider`, `host` | MiB counted as committed on a host |
| `virtrigaud_provider_host_guard_refusals_total` | Provider | `provider_type`, `reason` (`lock_dir_unsafe`, `lock_symlink`, `target_symlink`, `unknown`) | A long routed host command was refused because a host path VirtRigaud writes to was tampered with or pre-created |
| `virtrigaud_circuit_breaker_state` | Manager | `provider_type`, `provider` | 0 closed, 1 half-open, 2 open. Host-scoped failures stay out of it |
| `virtrigaud_errors_total` | Manager | `reason`, `component` | `reason="placement"` for scheduling failures; `reason="provider-resolve"` for each retry of a delete held because the Provider is unreachable; `reason="force-delete-not-allowed"` for each refused force-delete |
| `virtrigaud_provider_rpc_requests_total` | Manager | `provider_type`, `method`, `code` | RPC error ratio per method |

The two committed-capacity gauges are refreshed by the Host controller about
once a minute and removed when the Host is deleted or moved to another
Provider. Compare them with `Host.status.allocatableCPU` and
`allocatableMemoryMiB` multiplied by the pool's overcommit ratio to see how
full a host is. They show how full each host is **across tenants**: expose
`/metrics` only to administrators, either by enabling the chart's NetworkPolicy
(`networkPolicy.enabled`, which admits scrapes only from
`networkPolicy.monitoringNamespaceSelector`) or by running the manager with
`--metrics-secure=true`.

There is no metric for `Host` health or `HostPool` counts in v0.4.0. Read the
`Host` and `HostPool` status, or export them with a custom-resource state
exporter.

Alert candidates (adjust thresholds to your environment):

```yaml
- alert: ClusteredHostGuardRefusal
  # Any increase means a host path VirtRigaud writes to was tampered with.
  expr: increase(virtrigaud_provider_host_guard_refusals_total[15m]) > 0
  labels: {severity: critical}
- alert: ClusteredPlacementErrors
  # Scheduling failures: no feasible host, no pool, a bad policy.
  expr: increase(virtrigaud_errors_total{reason="placement"}[15m]) > 0
  for: 15m
  labels: {severity: warning}
- alert: ClusteredHeldDeletes
  # Deletes retried because the Provider could not be reached.
  expr: increase(virtrigaud_errors_total{reason="provider-resolve"}[15m]) > 0
  for: 30m
  labels: {severity: warning}
```

The Helm chart's optional `PrometheusRule`
(`observability.prometheus.prometheusRule.enabled`) already includes
`VirtRigaudProviderCircuitBreakerOpen` and `VirtRigaudProviderRPCErrors`. For
host failures, the signal is in the objects: a `Host` that is not `Ready`, a
`HostPool` with `SCHEDULABLE` below `TOTAL`, or VMs with `DeleteBlocked=True`.

Events worth alerting on or watching: `HostCredentialsUnresolved` and
`HostInventoryEntrySkipped` (on the Provider), `DeleteBlocked`,
`VMLeftOnHypervisor`, `ForceDeleteNotAllowed` and `Orphaned` (on VMs). The
provider log line `ERROR ALERT host guard refused ...` accompanies the guard
metric and names the host.

## Troubleshooting

Start with:

```bash
kubectl get provider,hosts,hostpools -n <provider namespace>
kubectl describe host <name> -n <provider namespace>
kubectl describe virtualmachine <name> -n <vm namespace>
kubectl logs deploy/<provider deployment> -n <provider namespace>
```

| Symptom | Likely cause | What to do |
|---------|--------------|------------|
| VM stuck `Placed=False/Unschedulable` | No host passed the filters | Read the message; see [Placement](placement.md#unschedulable-and-related-reasons). Most often the `net.virtrigaud.io/<network>` label is missing from `Host.spec.labels` |
| `Provisioning=False/NoHostPool` or `MultipleHostPools` | Zero or more than one `HostPool` for the Provider | Exactly one pool must name the Provider in its namespace |
| `Host` `HEALTH` is `Unknown`, `Ready=False/ProviderUnavailable` | The manager cannot reach the provider pod (not `Running`, TLS, rollout) or the provider call failed | `kubectl get provider`, check the provider pod and its TLS Secret. Retried every 15 s |
| `Host` `HEALTH` is `NotReady`, `Ready=False/HostNotReady` | The provider reached its connection registry but `virsh nodeinfo` over SSH to the host failed | Check SSH reachability, the SSH user from the endpoint, `known_hosts`, and libvirtd on the host. See [Libvirt host preparation](../../operations/libvirt-host-prepare.md#troubleshooting) |
| `Host` `Ready=False/HostNotFound` | The provider's inventory has no host of that name: it was skipped when rendering | Check `HostCredentialsReady` on the Provider and the events `HostCredentialsUnresolved` / `HostInventoryEntrySkipped` |
| `Host` `Ready=False/ProviderNotClustered` | `Host.spec.providerRef` names a Provider that is not `topology: cluster` | Point it at the clustered Provider; topology cannot be changed on an existing Provider |
| Provider `HostCredentialsReady=False` | A host's credential Secret is missing, unreadable or has no `ssh-privatekey` (`CredentialsUnresolved`), or the Provider's own `credentialSecretRef` names another namespace (`CredentialRefNamespaceRejected`) | Fix the Secret, in the Provider's namespace. The host is left out of the inventory until then; other hosts keep working |
| Connection fails with a host-key error | No matching `known_hosts` entry for the host | Add the `ssh-keyscan -H` line for the host to the credentials Secret |
| Create fails with `refusing to stage cloud-init data` | The host's seed directory is missing, not owned by the SSH user, or group/world accessible | `install -d -m 0711 -o <ssh user> -g <ssh user> /var/lib/libvirt/virtrigaud-seeds` on that host |
| Create or import fails `InvalidSpec`: the `default` pool "is not at /var/lib/libvirt/images" | The host's `default` storage pool is at another directory | An administrator fixes the pool on the host; VirtRigaud never changes an existing pool. Check with `virsh pool-dumpxml default` |
| Host reports `allocatableStorageBytes: 0` | `default` pool inactive, not `dir`/`fs`/`netfs`, not at the expected path, or unmeasurable | Same as above; start the pool |
| `Placed=False/HostUnavailable` | The pending host is unreachable | Restore the host; see [a host that stops answering](#a-host-that-stops-answering) |
| `Ready=False/HostUnavailable` on a bound VM | The VM's host is unreachable | Same; re-checked every 30 s |
| `Placed=False/Unbound` | A provider id but no confirmed host | See [Backup, restore and re-attach](backup-restore.md) |
| `Placed=False/RestorePending` | A previous incarnation of this VM's domain exists, or a restore marker names another UID | See [Backup, restore and re-attach](backup-restore.md) |
| `Placed=False/HostExcluded` / `AllHostsExcluded` | A same-named foreign domain exists on a candidate host | Remove or rename the conflicting domain, or rename the VM; clear `excludedHosts` ([Placement](placement.md#excluded-hosts)) |
| `Ready=False/VMMissingOnHost` | The bound host has no domain for this VM (or its stamp is not this VM's) | Restore the domain, or delete and re-create the `VirtualMachine`. It is not re-created automatically |
| `DeleteBlocked=True/HostUnreachable` | A host of the Provider (not necessarily the VM's own) cannot be reached | Restore the host, or [detach the VM](#detaching-a-vm-orphan-on-delete-and-force-delete) |
| `DeleteBlocked=True/DiskInUse` | A domain on another host uses one of the VM's disk files | Find that domain (`virsh dumpxml` on each host) and remove the stale definition, or detach the VM |
| `DeleteBlocked=True/DiskCheckFailed` | A host answered but could not be scanned, or the provider was busy | Retried automatically. If it persists, check the provider log for the host and domain count (limit 2000 per host) |
| `DeleteBlocked=True/ProviderUnavailable` | The manager cannot reach the Provider (rollout, pod down, TLS) | Wait for the Provider; retried on a backoff |
| `DeleteBlocked=True/OwnDomainOnAnotherHost` | The VM's own domain is on a host other than its pending host | See [Backup, restore and re-attach](backup-restore.md) |
| `Ready=False/OrphanOnDeleteNotAllowed` or `ForceDeleteRefused=True` | A consumer-namespace VM, and the Provider lacks `allow-consumer-orphan-on-delete` | The Provider's administrator sets the annotation, or you remove yours |
| `Host` deletion stuck, `Ready=False/HostInUse` | A VM of the Provider still names the host | Delete or detach the listed VMs (up to 10 are named) |
| `Reconfiguring=False/InsufficientHostCapacity` | A resize does not fit in the VM's host | Free capacity on the host, or use a smaller class. Retried at 30 s, 1 min, then every 2 min |
| `Reconfiguring=False/ShrinkPendingPowerOff` | A shrink of a running clustered VM is applied only while it is off | Power the VM off (`spec.powerState: Off`); set `On` again afterwards |
| `Reconfiguring=True/RestartRequired` | The running domain cannot take the change | Power the VM off and on (a guest reboot is not enough) |
| `Reconfiguring=False/ProviderLacksHonestReconfigure` | The provider image is older than the manager | Upgrade the provider image |
| Clone stays `Pending` with `SourceHostCordoned`, `SourceHostNotReady`, `SourceHostGone` | A clone can only land on its source's host | Uncordon or restore the host |
| Clone stays `Pending` with `SourceMustBePoweredOff` | A full clone needs a powered-off source | Power the source off |
| Everything is briefly down after changing the Provider | `Recreate` strategy: the single provider pod is replaced | Expected; calls are retried when the new pod is ready |
| Creates from a host-path image wait | The image check scans every host and fails closed while any host is unreachable | Restore the host, or use a URL or template image |
| Counter `virtrigaud_provider_host_guard_refusals_total` increases | A host path VirtRigaud writes to (the lock directory, a lock file, a clone or export target) is a symlink or was pre-created | Inspect `/tmp/virtrigaud-locks` and the target on the named host. A lock directory another user created can be removed (as root) and is recreated on the next call |

For anything not covered, the manager log has the cause behind a categorized
condition message (search for the VM name), and the provider log has the SSH
and `virsh` detail. Neither the conditions nor the events contain credentials,
endpoints or other tenants' data.

## See also

- [Placement](placement.md) and [Clustered libvirt: overview and setup](index.md)
- [Backup, restore and re-attach](backup-restore.md)
- [Migrating into a clustered Provider](../../migration/clustered-target.md)
- [Provider calls whose outcome was lost](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/provider-call-outcomes.md)
- [VM provider binding and `orphan-on-delete`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-provider-binding.md)
- Full reference: [clustered inventory](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/clustered-provider-inventory.md) and [ADR-0007](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/adr/0007-clustered-orchestrator-provider.md)
