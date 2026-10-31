<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Backup, restore and re-attach of clustered VMs

This page explains what happens when a `VirtualMachine` on a **clustered**
libvirt Provider (`Provider.spec.topology: cluster`) comes back from a backup,
a GitOps re-apply or a delete-and-recreate, and how an administrator
re-attaches it to the libvirt domain that is still running.

!!! warning "Experimental in v0.4.2"
    Clustered Providers are experimental in v0.4.2. See
    [Clustered libvirt: overview and setup](index.md) for the feature as a
    whole. Single-host libvirt, vSphere and Proxmox Providers are not changed
    by the guards on this page; their recovery is in
    [Other Providers](#other-providers).

## What you will see

A clustered VM that is restored, or re-created under the same name while its
old domain still exists, is **held** instead of being created a second time:

```console
$ kubectl get virtualmachine web-1 -n tenant-a
NAME    PHASE     ...
web-1   Pending   ...

$ kubectl get virtualmachine web-1 -n tenant-a \
    -o jsonpath='{range .status.conditions[?(@.type=="Placed")]}{.status}/{.reason}{"\n"}{end}'
False/RestorePending
```

`Pending` is deliberate. The VM is held, nothing about it failed, and it
proceeds by itself once the cause is gone. No image is prepared, nothing is scheduled and no
`Create` is sent while the hold lasts.

## Why a restore needs care

A restore (Velero, or `kubectl apply` of an exported manifest) re-creates the
`VirtualMachine` with a **new UID**. By default it also comes back **without
its status**, so it has lost `status.id` and `status.placement`.

On a clustered Provider the UID is the only identity a domain's owner stamp
accepts, and every call the operator routes to a host is owner-checked against
it. Without the guards on this page, a restored VM would look new: it would be
scheduled onto another host and a second domain `<namespace>.<name>` would be
created there, while the original kept running outside VirtRigaud's
accounting (and, on a shared pool, had its disk overwritten).

The rule VirtRigaud keeps instead: **a clustered Provider holds at most one
domain per `<namespace>.<name>`.** Only domains VirtRigaud created are
counted, because they carry the namespace and name in their owner stamp. A
domain that merely has the same name but is unstamped, or stamped for another
VirtualMachine, is not counted: the create on that host is refused, the host is
excluded for this VM, and the VM is placed elsewhere.

One consequence: after `virtrigaud.io/orphan-on-delete`, a VM with the same
name can be created again on a clustered Provider only after an administrator
re-attaches or removes the old domain (see
[`orphan-on-delete`](#orphan-on-delete-then-a-re-create-of-the-same-name)).

## The four guards

| Guard | Runs in | When | What it does |
|---|---|---|---|
| **R1**, the restore marker | manager | before a VM is first placed | A VM whose `infra.virtrigaud.io/placement-uid` annotation names another UID is held (`RestorePending`). |
| **R2**, the previous-incarnation pin | provider and manager | on a `Create` or `Clone` | A domain stamped with the VM's namespace and name under another UID refuses the create (`VM_PREVIOUS_INCARNATION`). The VM stays on its pending host (`RestorePending`) and the host is not excluded. |
| **R3**, the cluster-wide disk guard | provider | when a file already exists where the disk goes, and on every `Delete` | A disk that a domain on **any** host uses is never overwritten or removed. |
| **R4**, the pre-schedule uniqueness check | manager, through the provider | before a VM is first placed | The Provider's hosts are asked for domains stamped with the VM's namespace and name. A previous incarnation holds the VM (`RestorePending`). The VM's own domain has its host recorded as `pendingHost`, and the create retry binds it. |

R3 is described with the inventory and adoption features in the
[clustered-provider inventory reference](https://github.com/projectbeskar/virtrigaud/blob/v0.4.2/docs/clustered-provider-inventory.md#shared-storage-the-cluster-wide-disk-guard-a61).

### The restore marker (R1)

The marker is the annotation `infra.virtrigaud.io/placement-uid`. Its value is
the UID under which the VirtualMachine entered placement. The manager writes
it:

- on a create, before the first `status.placement.pendingHost` write;
- on a clone's target VirtualMachine, before the target's `pendingHost` write;
- on adoption, right before the binding write;
- on a bound VM, after an owner-checked call on its host succeeds. This covers
  VMs placed before the marker existed, and restored VMs once they are
  re-attached.

Backups and exported manifests carry the marker. A VM re-created under a new
UID therefore finds that the marker names another UID. If such a VM has no
`status.id` and no `status.placement.pendingHost`, it is held:

- it gets `Placed=False` and `Provisioning=False` with reason `RestorePending`,
  and one `Warning` event;
- it is re-checked with a backoff from 15 seconds, doubling up to 5 minutes;
- deleting it makes no provider call, so its previous domain is never touched.

!!! info "The marker is untrusted input"
    Tenants can write annotations, so the marker can only *hold* the VM that
    carries it. It never names a host, never selects one, never authorizes a
    bind and never skips the scheduler or R4. A forged marker only makes the
    forger's own VM wait.

    Releasing a marker (removing it, or setting it to the VM's own UID) is safe
    **once every host of the Provider is reachable**, because R2, R3 and R4
    still run afterwards. While a host cannot be checked, a released VM is
    scheduled on the evidence of the reachable hosts only (see
    [the host with the domain is unreachable](#the-host-with-the-domain-is-unreachable)).
    Release a marker only when every `Host` of the Provider is `Ready`.

A `VMClone` or `VMMigration` target is built without this key, so it never
inherits the marker. Single-host Providers neither read nor write it.

A change to the marker does not trigger a reconcile on its own. A released VM is
picked up at its next re-check, within 5 minutes.

### The pre-schedule uniqueness check (R4)

R4 runs for a clustered VM that has never been placed (no `status.id` and no
`pendingHost`): once before its first scheduling, and again on each retry while
it is held or unschedulable. It never runs for a bound VM or for a VM whose
create is already pending. The target of a `VMClone` meets it too, before the
clone is admitted; a previous incarnation holds the `VMClone` as `Pending`,
never `Failed`.

The manager sends one `ListVMs` with an owner filter (the VM's namespace and
name). On each host the provider looks only at this VM's candidates:

- the domain it would name for the VM, `<namespace>.<name>`, whatever its stamp;
- the legacy bare name `<name>`, but only when its stamp records this
  namespace and name.

!!! warning "Candidate names only"
    A domain named otherwise is **not** looked at, even when its owner stamp
    records the VM's namespace and name. That includes every **adopted**
    domain, because adoption stamps a domain under the name it already had. If
    an adopted VM is detached with `orphan-on-delete` and a VM with its
    namespace and name is created again, R4 does not see the old domain, and
    neither does R2. Only R3 protects a shared pool. Before re-creating an
    adopted VM, find its old domain **by stamp** (runbook step 1) and
    re-attach or remove it.

| The hosts report | Result |
|---|---|
| no domain stamped with the VM's namespace and name | the VM is scheduled as usual |
| exactly one, stamped with the VM's **own** UID | its host is recorded as `pendingHost`, without scheduling and without capacity admission, because the domain already runs there. It is counted at the domain's own size. The create retry there binds it as an idempotent success and records that size in `status.currentResources`. If it differs from the spec, a resize through the usual gate converges it (a grow must fit the host, a shrink waits for power-off) |
| one stamped under **another** UID, more than one, or a candidate whose stamp cannot be read | held: `Placed=False/RestorePending`. Nothing is scheduled or created |
| only an unstamped domain, or one stamped for another VirtualMachine, that has the name | not counted. That host is excluded when the create reaches it |

**Hosts that could not be checked** (unreachable, draining, past their
deadline) do not hold the VM. It proceeds on what the reachable hosts report. A
VM whose marker names another UID is held by R1 anyway. The residual risk is a
previous incarnation on an unreachable host with a **host-local** pool, where a
second domain can still be created. On a shared pool, R3 fails the create
closed instead.

**The provider must support the filter.** R4 runs only through a clustered
provider that reports `supportsListOwnerFilter` and marks its answer as
filtered. An older provider image does not, and the VM is held with
`Placed=False/ProviderLacksListOwnerFilter` until the provider is upgraded. If
the capability query or the listing fails, the VM is held with
`Placed=False/UniquenessCheckFailed`. Both holds back off from 15 seconds to 5
minutes. Neither message names a host; the details are in the manager log.

**Cost.** One `GetCapabilities` and one filtered `ListVMs` per check. The
fan-out is that of the cross-host listing: at most 8 hosts at a time and 60
seconds per host, inside a 45-second deadline from the manager; a host not
finished by then is reported unreachable. A clean answer (every host checked,
nothing found) is reused for 3 minutes per VM, until its spec changes. An
answer with a host that could not be checked is never reused. The provider runs
at most two owner-filtered listings at once; one that gets no slot is held as
`UniquenessCheckFailed` and retried with the backoff.

**The VM's own domain on another host.** A pending create can still meet the VM's
own domain elsewhere (its host was unreachable at the first placement, the
status was restored with a different pending host, or an administrator
re-stamped a previous incarnation found on another host). The manager then runs
R4's lookup. If it finds exactly that one domain, on a `Host` of the Provider,
and no other domain for the namespace and name, it moves `pendingHost` there
and the next create retry binds the domain. Otherwise the VM stays held with
`Placed=False/OwnDomainOnAnotherHost`, and deleting it is held too.

## Conditions and what to do

| Condition / reason | Set on | Meaning | What to do |
|---|---|---|---|
| `Placed=False/RestorePending` (and `Provisioning`) | a never-placed VM | R1: the marker names another UID. Or R4: a previous incarnation, more than one domain, or an unreadable stamp exists | [Re-attach](#re-attach-runbook) the previous domain, [discard it](#discarding-the-previous-domain), or release the marker |
| `Placed=False/RestorePending` (and `Provisioning`) | a VM with `pendingHost` | R2: the create on the pending host met a previous incarnation | [Re-attach](#re-attach-runbook) or [discard](#discarding-the-previous-domain). The marker needs no change |
| `Ready=False/RestorePending` | a bound VM whose marker names another UID | its status was restored, but the domain on its host is still stamped with the old UID | [Re-stamp](#re-attach-runbook) the domain (steps 1 and 2). The marker is rewritten automatically |
| `Placed=False/OwnDomainOnAnotherHost` | a VM with `pendingHost`, or a never-placed VM | the VM's own domain is on another host, and the lookup could not move `pendingHost` there. Deleting the VM is held too (`DeleteBlocked=True/OwnDomainOnAnotherHost`) | See [Own domain found on another host](#own-domain-found-on-another-host) |
| `Placed=False/ProviderLacksListOwnerFilter` | a never-placed VM | the provider image is older than the owner filter | Upgrade the clustered provider |
| `Placed=False/UniquenessCheckFailed` | a never-placed VM | R4's query failed or was busy | Check the manager log; the check is retried |

Each hold emits one `Warning` event when it starts, and the manager counts it
under the error reason `restore-pending` (or `preschedule-check`). No message
names a host, a domain, another UID or another tenant's object. All of the
holds above leave `status.phase` at `Pending`.

## Backing up clustered VirtualMachines

- **Restore the VirtualMachine status.** With Velero, list the kind under
  `restoreStatus`:

  ```yaml
  apiVersion: velero.io/v1
  kind: Restore
  spec:
    restoreStatus:
      includedResources:
        - virtualmachines.infra.virtrigaud.io
  ```

  A restored status keeps the binding. The `spec.providerRef` lock and the
  committed-capacity count are in place from the first moment, and the owner
  checks keep the VM fail-closed until its domain is re-stamped.
- **Back up the Provider's namespace with it**: the `Provider`, `Host`,
  `HostPool` and their credential Secrets. The re-attach needs the `Host`
  objects.
- **Never run `kubectl replace --force` on a VirtualMachine.** Its delete half
  runs the finalizer, which destroys the domain.
- **Restoring into a second Kubernetes cluster** whose manager also manages the
  hosts is not supported. Fence the first cluster (scale its manager to zero)
  before you recover in the second one.
- **Exempt the restore tool from the admission policy.** The restore marker
  itself is not admission-protected, but a restore that re-creates
  VirtualMachines carrying other manager-owned `virtrigaud.io` keys is rejected
  unless the tool's identity is in the admission policy's `exemptUsernames` or
  `exemptGroups`. See
  [Reserved keys and the admission policy](https://github.com/projectbeskar/virtrigaud/blob/v0.4.2/docs/admission-policy.md).

## Scenarios

### Velero restore, status not restored (the default)

The VM comes back with the marker naming its old UID and no status. **R1 holds
it** (`Placed=False/RestorePending`). No `Create` is sent and the original
domain keeps running. Follow the [re-attach runbook](#re-attach-runbook). If the
original was deleted normally after the backup, release the marker instead: R4
finds nothing, and the VM is created as new.

### Velero restore with `restoreStatus`

- **`status.id` restored.** The VM is bound, so R1 does not hold it. Its
  owner-checked calls on the bound host find nothing, because the domain is
  stamped with the old UID. It shows `Ready=False/RestorePending` instead of
  `VMMissingOnHost`, and it is never re-created. **Re-stamp the domain** (steps
  1 and 2 of the runbook). The next reconcile's `Describe` succeeds and the
  marker is rewritten automatically.
- **Only `pendingHost` restored** (the backup was taken during a create). The
  create retry meets the domain stamped with the old UID, and R2 pins the VM to
  its pending host (`RestorePending`). Re-stamp the domain; the create retry
  then binds it. If the domain is on a different host than `pendingHost`, the
  manager moves `pendingHost` there itself.

### `kubectl apply` of an exported manifest

Same as Velero without status: `apply` ignores status, and the manifest carries
the marker. R1 holds the VM.

### GitOps re-apply

A manifest from git has no marker and no status, so **R4** asks the hosts. If a
domain stamped with the VM's namespace and name under another UID exists on a
reachable host, the VM is held (`RestorePending`). Re-attach it with the
runbook (without the marker step), or remove the old domain. If R4 finds
nothing, the VM is created as new.

!!! warning "Keep the marker out of git"
    The manager writes `infra.virtrigaud.io/placement-uid` on the live object.
    A manifest exported with `kubectl get -o yaml` carries it, and once it is in
    git, every re-apply to a new object (a re-created namespace, a new cluster,
    a deleted-and-re-synced VM) is held by R1 as a restore. Strip it when you
    export:

    ```sh
    kubectl get virtualmachines.infra.virtrigaud.io <name> -n <namespace> -o yaml \
      | yq 'del(.metadata.annotations."infra.virtrigaud.io/placement-uid") | del(.status)
            | del(.metadata.uid, .metadata.resourceVersion, .metadata.generation, .metadata.creationTimestamp, .metadata.managedFields)'
    ```

Also make the GitOps tool ignore the annotation so that it neither reports
drift nor removes it on every sync. Removing it is harmless for a bound VM (the
manager writes it back after the next successful call), but it churns.

=== "Argo CD"

    ```yaml
    # Application.spec
    ignoreDifferences:
      - group: infra.virtrigaud.io
        kind: VirtualMachine
        jsonPointers:
          - /metadata/annotations/infra.virtrigaud.io~1placement-uid
    ```

    With server-side diff or `RespectIgnoreDifferences=true` in `syncOptions`,
    a sync also leaves the field alone.

=== "Flux"

    Flux uses server-side apply and does not remove annotations it does not
    manage. Keep the annotation out of the committed manifest and Flux leaves
    the manager's value in place. Do not set
    `kustomize.toolkit.fluxcd.io/force: enabled` on VirtualMachines: it
    re-creates the object with a new UID.

### `orphan-on-delete`, then a re-create of the same name

`virtrigaud.io/orphan-on-delete` is the supported way to detach a VM without
destroying it. Set it to the exact value `true`, then delete the
`VirtualMachine`:

```sh
kubectl annotate virtualmachine web-1 -n tenant-a virtrigaud.io/orphan-on-delete=true
kubectl delete virtualmachine web-1 -n tenant-a
```

The finalizer is removed **without any provider call**. The domain is left
running on its host, stamped with the deleted VM's UID, and no longer managed;
an event records the detach. Outside clustered Providers the annotation is
honoured as above. On a clustered Provider there is one more rule: a VM in a
**different namespace** than its Provider (a consumer granted through
`spec.consumerNamespaceSelector`) is refused unless the Provider carries the
annotation `infra.virtrigaud.io/allow-consumer-orphan-on-delete: "true"`. The
refusal keeps the finalizer and shows `Ready=False/OrphanOnDeleteNotAllowed`
with a `Warning` event. The reason: an orphaned clustered VM keeps running but
leaves the committed-capacity accounting. `virtrigaud.io/force-delete` is gated
the same way.

The re-created VM, with a new UID and no marker, is then **held by R4**. This is
the accepted side effect of the one-domain rule. Decide which you want:

- **keep the running domain** and manage it again: re-attach it (runbook steps
  1 and 2). R4 then records its host and the create binds it;
- **start fresh**: [discard the old domain](#discarding-the-previous-domain).

While it waits, the VM shows `Placed=False/RestorePending` and
`status.phase: Pending`. On a shared pool, R3 also refuses to write over the old
domain's disk.

### Own domain found on another host

A domain stamped with the VM's **own** UID is the VM's own domain; only its
placement record was lost. No re-stamp is needed:

- **Before the first placement**, R4 records that host as `pendingHost`, and the
  create retry binds the domain. No administrator action is needed.
- **With a pending create elsewhere**, the manager moves `pendingHost` to the
  domain's host itself.
- **The lookup cannot tell** (`Placed=False/OwnDomainOnAnotherHost` stays). This
  happens when the provider lacks the owner filter, the host is not a `Host` of
  the Provider, or another domain for the namespace and name exists. Resolve
  the cause: upgrade the provider, restore the `Host` object, or remove the
  extra domain. As a last resort, set the pending host by hand.

!!! danger "Verify before you set `pendingHost` by hand"
    On the host, run runbook step 1: it must find exactly one domain for the
    namespace and name, and the stamp's `uid` must equal the VM's
    `metadata.uid`. A pending host that points anywhere else makes the create
    run there.

    ```sh
    # on <host>, with CONN set to that host's connection URI: uid must be the VM's UID
    virsh -c "$CONN" metadata --domain <domain uuid> --uri https://virtrigaud.io/xmlns/libvirt/owner/v1
    kubectl patch virtualmachines.infra.virtrigaud.io <name> -n <namespace> --subresource=status \
      --type=merge -p '{"status":{"placement":{"pendingHost":"<host>"}}}'
    ```

Deleting such a VM is held (`DeleteBlocked=True/OwnDomainOnAnotherHost`),
whether or not it was ever placed, because releasing it would leave its own
domain running. The hold lasts until its pending host points at the domain (the
delete then removes it), or until you set `virtrigaud.io/force-delete` or
`virtrigaud.io/orphan-on-delete` (the domain is then left for manual removal).

### Restore into a new namespace while the original runs

R1 holds the copy. A domain name is derived from the namespace, so the copy can
never re-attach to the original's domain. Release the marker to create it as a
new VM, or delete it.

### The backup is older than a normal delete

The domain is gone. R1 holds the restored VM. Release the marker: R4 finds
nothing, and the VM is created as new.

### The host with the domain is unreachable

- A VM whose marker names another UID stays held (R1), whatever the hosts
  report.
- A VM without a marker (a GitOps re-apply) is **not** held by an unreachable
  host. It is scheduled on the evidence of the reachable hosts. On a shared
  pool, R3 fails its create closed. On a **host-local** pool, a second domain
  can be created. This is the one accepted residual. Bring the host back before
  re-applying VMs whose previous incarnation it may hold.

## Re-attach runbook

Re-attaching is manual in v0.4.2. The steps need root (or the provider's SSH
user) on the hosts, and read access to VirtualMachines in all namespaces.

!!! danger "Always name the connection: `virsh -c \"$CONN\" ...`"
    Never run a bare `virsh`. libvirt's default connection URI depends on who
    runs it; for many admin accounts it is `qemu:///session`, a different,
    per-user libvirt instance from the `qemu:///system` one that VirtRigaud's
    domains run under. A bare `virsh list --all` under `qemu:///session` shows
    **no** domains and no error. It looks exactly like "the domain is gone",
    and trusting that empty list can lead you to discard or re-create a VM on
    top of a domain that is still running.

Set `CONN` once per host before running any command below. It is exported
because a couple of steps spawn `virsh` through `sh -c` via `xargs`:

```sh
export CONN=qemu:///system   # when you are logged into the host itself
# or, from elsewhere (for example a jump host), use the Host's own connection URI
# (a qemu+ssh:// endpoint):
export CONN=$(kubectl get hosts.infra.virtrigaud.io <host-name> -n <provider-namespace> -o jsonpath='{.spec.endpoint}')
# for example: qemu+ssh://virtrigaud@host-a.example.com/system
```

**0. Read the held VM's UID and marker.**

```sh
NEW_UID=$(kubectl get virtualmachines.infra.virtrigaud.io <name> -n <namespace> -o jsonpath='{.metadata.uid}')
MARKER=$(kubectl get virtualmachines.infra.virtrigaud.io <name> -n <namespace> \
  -o jsonpath='{.metadata.annotations.infra\.virtrigaud\.io/placement-uid}')
echo "uid=$NEW_UID marker=$MARKER"
```

**1. Find the previous domain by its stamp, not by its name.** A domain may be
called anything: `<namespace>.<name>`, the legacy bare `<name>`, or the name it
had before it was adopted. On **each** host of the Provider (every `Host` in the
Provider's namespace, whatever its state), list every domain whose owner stamp
records the held VM's namespace and name:

```sh
NS=<namespace>; NAME=<name>
URI=https://virtrigaud.io/xmlns/libvirt/owner/v1
# CONN is set above: the connection for THIS host, not virsh's own default.
for d in $(virsh -c "$CONN" list --all --uuid); do
  s=$(virsh -c "$CONN" metadata --domain "$d" --uri "$URI" 2>/dev/null) || continue
  if printf '%s\n' "$s" | grep -qF -e "namespace='$NS' name='$NAME'" -e "namespace=\"$NS\" name=\"$NAME\""; then
    echo "$d $(virsh -c "$CONN" domname "$d") $s"
  fi
done
```

Each line is a domain's UUID, its name and its owner stamp, for example
`<owner uid='…' namespace='<namespace>' name='<name>'/>` (libvirt may print the
attributes with double quotes). Then:

- **Stop if more than one domain, on any host, is stamped for this namespace and
  name,** or if a host could not be checked. At most one may be re-attached.
  Discard the others first.
- Check that the namespace and name in the stamp are the held VM's own.
- **For a VM held by R1** (its marker names another UID): the stamp's UID must
  **equal `$MARKER`**. The marker says which incarnation this VirtualMachine was
  backed up as. A domain stamped with any other UID is not that incarnation
  (another VM of the same name, or a marker someone edited): stop.
- Check that **no VirtualMachine with the stamp's UID exists**, in any
  namespace, terminating ones included:

  ```sh
  kubectl get virtualmachines.infra.virtrigaud.io -A \
    -o jsonpath='{range .items[*]}{.metadata.uid}{"\n"}{end}' | grep -x '<stamp uid>'
  ```

  If it prints the UID, that VirtualMachine still owns the domain. Stop.

**2. Re-stamp the domain with the held VM's UID**, keeping the namespace and
name. Address the domain by its UUID, on the same `CONN` you used to find it:

```sh
virsh -c "$CONN" metadata --domain <domain uuid> --uri https://virtrigaud.io/xmlns/libvirt/owner/v1 --key virtrigaud \
  --set "<owner uid='${NEW_UID}' namespace='<namespace>' name='<name>'/>" --config --live
# drop --live if the domain is shut off
```

This is the same write the provider's ownership transfer makes. Read the stamp
back with the command from step 1, and for a running domain also with
`virsh -c "$CONN" dumpxml --inactive <domain>`. libvirt keeps one element per
namespace URI, so the old stamp is replaced, not duplicated.

**3. Only for a VM held by R1 (never placed): release the marker.** Set it to
the held VM's UID, or remove it:

```sh
kubectl annotate virtualmachines.infra.virtrigaud.io <name> -n <namespace> \
  infra.virtrigaud.io/placement-uid="${NEW_UID}" --overwrite
# or: kubectl annotate virtualmachines.infra.virtrigaud.io <name> -n <namespace> infra.virtrigaud.io/placement-uid-
```

At its next re-check (within 5 minutes), R4 finds the domain stamped with the
VM's own UID and records its host as `pendingHost`. The create retry there binds
the VM as an idempotent success and records `status.id` and the resources as for
any create. **There is no manual status edit.**

A VM pinned by R2, or whose status was restored, needs no step 3. Its create
retry (R2), or its next `Describe` (a restored `status.id`), binds it, and the
marker is rewritten automatically.

**4. Verify.** `Placed=True/Bound`, `status.id` and `status.placement.host` are
set, the marker equals the VM's UID, and the `virtrigaud_host_committed_cpu` and
`virtrigaud_host_committed_memory_mib` metrics count the VM once on its host.

### Discarding the previous domain

To give the held VM a fresh start instead, remove the old domain and its files.

**Run step 1's checks first**: find the domain by stamp on every host, stop on
more than one, and confirm that no VirtualMachine with its stamp's UID exists.
Discarding a domain a live VirtualMachine owns destroys that VM. Then, on the
domain's host, address the domain by its **UUID** (a name may be reused), and
note its disk files before you undefine it:

```sh
D=<domain uuid>
# CONN is that domain's host's connection URI (see the top of this runbook).
virsh -c "$CONN" domblklist --domain "$D" --details    # note the Source of each 'file disk'
virsh -c "$CONN" destroy --domain "$D"                  # only if it is running
virsh -c "$CONN" undefine --domain "$D" --nvram         # --nvram for UEFI domains
```

**Before you remove a disk file, check that no domain on any host of the
Provider uses it.** A shared pool is visible from every host, and a linked clone
may use the file as its backing file. On **every** host, with `CONN` set to that
host's connection URI, for each file `F` noted above:

```sh
F=<disk file>
for d in $(virsh -c "$CONN" list --all --uuid); do
  if virsh -c "$CONN" domblklist --domain "$d" --details | awk '$1 == "file" {print $4}' | grep -qxF -- "$F"; then
    echo "IN USE by $d $(virsh -c "$CONN" domname "$d")"
  fi
done
# and no disk on the host uses it in its backing chain:
for img in $(virsh -c "$CONN" list --all --uuid | xargs -r -n1 sh -c 'virsh -c "$CONN" domblklist --domain "$0" --details' | awk '$1 == "file" && $2 == "disk" {print $4}'); do
  sudo qemu-img info -U --backing-chain "$img" 2>/dev/null | grep -qF -- "$F" && echo "BACKING of $img"
done
```

Remove the file only when neither loop prints anything on any host. The disk is
`<pool>/<namespace>.<name>-disk.qcow2`, or `-disk` for a blank volume, or
`-migrated.qcow2` for an imported disk. Also remove its cloud-init seed.
Finally, release the marker (runbook step 3) if the VM carries one. At its next
re-check, R4 finds nothing and the VM is created as new.

## Other Providers

- **Single-host libvirt and vSphere.** A restored VM keeps retrying its create,
  which is refused because the owner stamp names the old UID
  (`ProviderConflict`, re-checked every 2 minutes). Re-stamp the domain as in
  step 2, keeping the namespace and name; the create retry then binds it. On
  vSphere, the stamp is the VM's ExtraConfig key `virtrigaud.owner.uid`. No
  marker is involved.
- **Proxmox** stamps each VM it creates with the owner, in a line of the VM's
  description. A restored VM (new UID, no status) that finds a same-named VM
  stamped for the old UID is refused as a conflict, as on libvirt and vSphere.
  The description line carries a checksum, so do not edit it by hand to
  re-attach. Restore Proxmox VirtualMachines with their status, which keeps the
  binding.

## See also

- [Clustered libvirt: overview and setup](index.md)
- [Operations: routed lifecycle, host loss and troubleshooting](operations.md)
- [Security model: ownership and multi-tenancy](../security-model.md)
- [ADR-0007, the clustered orchestrator Provider](https://github.com/projectbeskar/virtrigaud/blob/v0.4.2/docs/adr/0007-clustered-orchestrator-provider.md)
  (amendment A6 is the decision record and threat model for this page)
- [Libvirt domain ownership](https://github.com/projectbeskar/virtrigaud/blob/v0.4.2/docs/libvirt-domain-ownership.md):
  the owner stamp
- [Full reference: `docs/clustered-restore.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.2/docs/clustered-restore.md)
