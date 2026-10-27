<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Clustered libvirt: overview and setup

A **clustered** libvirt Provider puts one VirtRigaud `Provider` in front of
several bare libvirt/KVM hosts. You register the hosts as `Host` objects,
group them in a `HostPool`, and VirtRigaud chooses a host for every new
`VirtualMachine`, then sends every later call for that VM to the host it runs
on. libvirt has no cluster manager of its own; in this mode VirtRigaud is the
one.

!!! warning "Experimental in v0.4.1"
    `topology: cluster` is **experimental**. It is opt-in, it can still change,
    and the v0.4.1 test coverage of multi-host setups is narrower than that of
    single-host libvirt, vSphere and Proxmox. Read
    [What "experimental" means here](#what-experimental-means-here) and
    [What is and is not supported](#what-is-and-is-not-supported) before
    putting workloads on it. Single-host Providers (`topology: single`, the
    default) are not affected by anything on this page.

This page covers the concepts, the host prerequisites and a complete first
setup. The other clustered pages:

| Page | Covers |
|------|--------|
| [Placement](placement.md) | The scheduler, `VMPlacementPolicy`, `status.placement`, and every `Unschedulable` reason |
| [Operations and troubleshooting](operations.md) | Routed lifecycle, a host that stops answering, cordon, the shared-storage disk guard, metrics |
| [Backup, restore and re-attach](backup-restore.md) | Restored or re-created VMs and the re-attach runbook |
| [Migrating into a clustered Provider](../../migration/clustered-target.md) | `VMMigration` with a clustered target |

## How it fits together

```mermaid
flowchart LR
  subgraph K8s["Kubernetes cluster"]
    M["Manager<br/>(VirtualMachine, Host, HostPool controllers,<br/>placement scheduler)"]
    P["Provider pod<br/>(provider-libvirt, topology: cluster)"]
    S[("Secret PROVIDER-hosts<br/>host list + SSH credentials")]
  end
  M -- "renders" --> S
  S -- "mounted read-only" --> P
  M -- "gRPC, host named on every call" --> P
  P -- "SSH + virsh" --> A["host-a"]
  P -- "SSH + virsh" --> B["host-b"]
```

The manager decides; the provider executes. The provider keeps no placement
state of its own: it learns which hosts exist from a Secret the manager
renders, and it is told which host to use on every call.

## Concepts

### Provider: `spec.topology: cluster`

`Provider.spec.topology` is `single` (the default) or `cluster`. A cluster
Provider must have `spec.type: libvirt`; no other type supports it.

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: libvirt-cluster
  namespace: virtrigaud-system
spec:
  type: libvirt
  topology: cluster
  # Required by the schema. A clustered Provider does not connect to this
  # address: each host's endpoint is on its Host object.
  endpoint: qemu+ssh://virtrigaud@placeholder.example.com/system
  credentialSecretRef:
    name: libvirt-cluster-creds
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.4.1"
    service:
      port: 9443
      tls:
        enabled: true
        secretRef:
          name: libvirt-cluster-tls
```

Things that differ from a single-host Provider:

- **`spec.topology` is immutable.** The CRD rejects any change
  (`spec.topology is immutable; create a new Provider to change it`). To
  change topology, create a new Provider.
- **One replica, `Recreate` strategy.** `spec.runtime.replicas` above 1 is
  ignored. Every rollout of a clustered provider (an image upgrade, a changed
  spec) is a short outage: its gRPC endpoint is down until the new pod is
  ready, and VM reconciles against it fail and are retried meanwhile.
- **Type restriction at admission.** Rejecting `topology: cluster` on
  `vsphere` or `proxmox` is done by the `vprovider.kb.io` validating webhook.
  The webhook is **off by default** (`webhooks.enabled: false` in the Helm
  chart) because it needs serving certificates. Without it, only the
  immutability rule above is enforced at admission.

### Host: one hypervisor

A `Host` (short name `hvh`) is admin-authored: it says which hypervisor
exists and what it offers. The operator fills `status` with live facts.

| `spec` field | Meaning |
|--------------|---------|
| `providerRef.name` | The clustered Provider that executes on this host |
| `poolRef.name` | The `HostPool` this host joins |
| `endpoint` | `qemu+ssh://[user@]host[:port]/system` (or `/session`) |
| `credentialSecretRef.name` | Optional per-host credentials; defaults to the Provider's |
| `labels` | Placement facts the scheduler reads (see [Placement labels](#first-vm-checklist)) |
| `schedulable` | Defaults to `true`. `false` cordons the host: no new VMs are placed on it, existing VMs stay |

`status` carries `health` (`Ready`, `NotReady`, `Unknown`), allocatable CPU,
memory and storage, CPU model and features, machine types, the emulator path,
`lastHeartbeatTime` and a `Ready` condition. It never carries connection
secrets. `status.boundVMs` exists in the schema but is always `0` in v0.4.1;
use the [committed-capacity metrics](operations.md#metrics-and-alerts)
instead.

`kubectl get hosts` shows `HEALTH`, `POOL`, `SCHEDULABLE` and `AGE`.

The Host controller asks the provider about each host (`GetHostInfo`) every 60
seconds after a successful sync, and every 15 seconds after a failed one.
These are the values behind `status`:

| Host fact | Where it comes from |
|-----------|---------------------|
| `allocatableCPU`, `allocatableMemoryMiB` | The host's **total** logical CPUs and memory (`virsh nodeinfo`). Overcommit and committed VMs are applied by the scheduler, not here |
| `allocatableStorageBytes` | Free space of libvirt's **`default`** storage pool directory, measured on every sync. It is `0` when the pool is inactive, is not a `dir`/`fs`/`netfs` pool, is not at `/var/lib/libvirt/images`, or cannot be measured |
| `health` | `Ready` when the connection and `virsh nodeinfo` succeed |
| `machineTypes`, `emulatorVersion` | The default machine type, and the emulator **binary path** (not a version number) |

A Host that cannot be reached is reported `NotReady`; it does not fail the
call for its siblings. Only the `default` pool counts for storage: other
pools are not summed.

### HostPool: policy for a group of hosts

A `HostPool` (short name `hp`) holds the scheduling policy.

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: HostPool
metadata:
  name: pool-a
  namespace: virtrigaud-system
spec:
  providerRef:
    name: libvirt-cluster
  strategy: Spread        # or BinPack
  overcommit:
    cpu: "2.0"            # decimal strings
    memory: "1.0"
```

| Field | Used in v0.4.1? |
|-------|-----------------|
| `providerRef` | Yes. Same namespace as the pool |
| `strategy` | Yes. `Spread` (default) or `BinPack`; see [Placement](placement.md#scoring-spread-and-binpack) |
| `overcommit.cpu`, `overcommit.memory` | Yes. Decimal strings, empty means `"1.0"`; must be greater than 0 |
| `storagePools`, `networks` | Accepted by the schema; **not read by any controller**. Per-host visibility is asserted with `Host.spec.labels` instead |
| `migration` | Accepted by the schema; **not read**. Host-to-host migration is not implemented |

**Exactly one `HostPool` per clustered Provider.** A Provider with no pool, or
with more than one, leaves its new VMs at `Provisioning=False` with reason
`NoHostPool` or `MultipleHostPools`.

`HostPool.status` is written by the HostPool controller from the pool's member
hosts:

```console
$ kubectl get hostpools -n virtrigaud-system
NAME     STRATEGY   PROVIDER          TOTAL   READY   SCHEDULABLE   AGE
pool-a   Spread     libvirt-cluster   2       2       1             3d
pool-b   Spread     libvirt-cluster   0       0       0             1h
```

| Column / field | Counts |
|----------------|--------|
| `TOTAL` (`status.totalHosts`) | Every `Host` in the pool's namespace whose `spec.poolRef.name` is this pool, including one being deleted |
| `READY` (`status.readyHosts`) | Members whose `status.health` is `Ready` |
| `SCHEDULABLE` (`status.schedulableHosts`) | Members that are `Ready`, have `spec.schedulable: true`, are not being deleted, and name the pool's Provider |

Here `pool-a` has two Ready hosts, one of them cordoned. The `Ready` condition
on a pool is:

| Status / reason | When |
|-----------------|------|
| `True` / `HostsAvailable` | `SCHEDULABLE` is greater than 0 |
| `False` / `NoMemberHosts` | No `Host` in the namespace names the pool |
| `False` / `NoSchedulableHosts` | There are members, but none is schedulable |

`Ready=True` means at least one host passes the per-host test. It does not
mean a particular VM fits: capacity, network labels and any
`VMPlacementPolicy` are checked per VM. A count of `0` is written as `0`.

### The same-namespace model

A `HostPool`, its `Host` objects, every credential `Secret` they use, and the
clustered `Provider` they name **all live in one namespace: the Provider's**.
`providerRef`, `poolRef` and `credentialSecretRef` on `Host` and `HostPool`
have no `namespace` field.

The operator enforces the same rule when it acts:

- The inventory render lists `Host` objects in the Provider's namespace only.
  A `Host` created anywhere else is ignored, so it cannot enrol in another
  team's Provider or inherit that Provider's SSH identity.
- Credential Secrets are read from the Provider's namespace only. If a
  clustered Provider's own `spec.credentialSecretRef.namespace` names a
  different namespace, that Secret is **not read**; hosts that would use it are
  skipped and the Provider gets `HostCredentialsReady=False` with reason
  `CredentialRefNamespaceRejected`.
- Placement looks up the pool and hosts in the **Provider's** namespace, not
  the VM's. A VM may live in another namespace and reference the Provider
  there (see [VMs in other namespaces](#vms-in-other-namespaces)); its
  placement still uses the Provider's pool.

The reason is that the host list carries SSH private keys and the endpoint is
handed to the hypervisor host. Letting a namespace-scoped author steer either
across namespaces would turn "can create a `Host`" into "can read another
namespace's Secrets".

### Endpoint validation

`Host.spec.endpoint` is checked by the CRD schema (1 to 512 characters, plus a
pattern) **and again by the provider** for every entry it loads, so editing
the rendered Secret by hand does not bypass admission.

| Accepted | Notes |
|----------|-------|
| `qemu+ssh://[user@]host[:port]/system` | The normal form |
| `qemu+ssh://[user@]host[:port]/session` | libvirt user session |
| `grpc://host:port` | Passes the schema but is reserved for a future host agent. The libvirt provider connects over SSH only; use `qemu+ssh://` |

`user` is `[A-Za-z0-9._-]+`; `host` is a DNS name, an IPv4 address or a
bracketed IPv6 address (`[2001:db8::1]`). Query strings, fragments,
percent-encoding and any other path are rejected. The SSH user belongs in the
endpoint; the credentials Secret's `username` key is **not** used for
clustered hosts.

### Host credentials

Each host is reached with SSH key authentication. For every host, the
operator resolves one Secret: the Host's `credentialSecretRef` if set,
otherwise the Provider's `credentialSecretRef`, both in the Provider's
namespace.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: libvirt-cluster-creds
  namespace: virtrigaud-system
type: Opaque
stringData:
  ssh-privatekey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    REDACTED
    -----END OPENSSH PRIVATE KEY-----
  # ssh-keyscan -H <host> for every host this Secret is used for
  known_hosts: |
    |1|REDACTED_HASH_1=|REDACTED_HASH_2= ssh-ed25519 REDACTED_HOST_PUBLIC_KEY
```

| Key | Required | Notes |
|-----|----------|-------|
| `ssh-privatekey` | Yes | A host whose Secret is missing or has no `ssh-privatekey` is left out of the inventory |
| `known_hosts` | Recommended | Not required to render, but the provider verifies SSH host keys and **refuses to connect** to a host with no matching entry (unless the audit-flagged insecure escape hatch is set; see [Libvirt host preparation](../../operations/libvirt-host-prepare.md#ssh-host-key-verification-adr-0004)). One Secret can hold the `known_hosts` lines for all hosts it serves |
| `username`, `password` | Not used | The user is in the endpoint; password authentication is not carried to clustered hosts |

When a host is left out, the manager does not fail the whole render. It keeps
the other hosts and reports the problem:

- the Provider condition `HostCredentialsReady` becomes `False` with reason
  `CredentialsUnresolved` (or `CredentialRefNamespaceRejected`), listing host
  names and a coarse reason;
- a `Warning` event `HostCredentialsUnresolved` is recorded on the Provider.

A host skipped for a non-credential reason (an endpoint outside the accepted
shapes, a duplicated name) produces a `Warning` event
`HostInventoryEntrySkipped` instead. Messages never contain a credential or
an endpoint.

```console
$ kubectl get provider libvirt-cluster -n virtrigaud-system \
    -o jsonpath='{range .status.conditions[?(@.type=="HostCredentialsReady")]}{.status}/{.reason}: {.message}{"\n"}{end}'
```

### The projected host-inventory Secret

The Provider controller renders the Hosts into a Secret named
**`<provider>-hosts`** (here `libvirt-cluster-hosts`) in the Provider's
namespace, owner-referenced to the Provider. It is mounted read-only in the
provider pod at `/etc/virtrigaud/hosts/` as `hosts.json`. The provider reads
that file, not the Kubernetes API, and reloads it when it changes: a new host
is dialed on first use, a removed or changed host is drained and closed only
once idle, so a reload does not interrupt a call in progress.

!!! warning "This Secret contains the SSH private keys"
    `<provider>-hosts` holds each host's id, endpoint, labels **and** its
    inlined SSH private key and `known_hosts`. Protect it like the source
    credential Secrets: restrict `get`/`list` on Secrets in the Provider's
    namespace. The keys are therefore stored twice, in the source Secret and in
    this one. The manager writes only this one Secret and never deletes
    Secrets; it is garbage-collected with the Provider.

## What "experimental" means here

- **Opt-in, no flag.** There is no feature gate and no Helm value to switch
  clustering on. The `Host`, `HostPool` and `VMPlacementPolicy` CRDs are
  installed with the chart's CRDs, and nothing happens until you create a
  Provider with `topology: cluster`. Existing single-host Providers and their
  VMs are unchanged.
- **It may change.** Field names, condition reasons and behaviour of the
  clustered path can still change in a later release. The CRDs themselves are
  `v1beta1`.
- **Narrower validation.** The clustered path was exercised on a small number
  of hosts. Several paths are covered by unit and envtest tests only, not by
  runs against real hosts; see the limits on
  [Migrating into a clustered Provider](../../migration/clustered-target.md).
- **No automatic failover.** See below.

## What is and is not supported

| Operation | Clustered libvirt in v0.4.1 |
|-----------|-----------------------------|
| Create (scheduled onto a host) | Supported |
| Describe, power on/off/reboot/graceful shutdown | Supported, routed to the VM's host and owner-checked |
| Reconfigure (CPU, memory, disk grow) | Supported, routed and owner-checked. A resize that grows the VM is admitted against the host's free capacity; see [Placement](placement.md#committed-capacity) |
| Delete | Supported, routed and owner-checked, with a cluster-wide disk check; see [Operations](operations.md#shared-storage-the-cluster-wide-disk-guard) |
| Snapshot create, delete, revert (incl. memory snapshots) | Supported, routed and owner-checked; see [VM snapshots](../vm-snapshots.md) |
| Clone | **Full clones only**, onto the source VM's own host, source powered off; see [VM cloning](../advanced/vm-cloning.md). Linked clones are refused |
| Disk export as a migration source | `s3` and `nfs` backends only. The `pvc` backend is refused |
| List and adopt existing domains | Supported across all hosts; only **unstamped** domains are adopted |
| Migration **into** a clustered Provider | Supported (experimental), `s3` and `nfs` only; see [Migrating into a clustered Provider](../../migration/clustered-target.md) |
| Image preparation (`ImagePrepare`) | **Not available.** The clustered Provider does not advertise image import; a VM is created by reference to the image on the host |
| Host-to-host (live or cold) migration | **Not implemented** |
| Moving or rescheduling an already-created VM | **Not implemented.** The scheduler runs when a VM is created; a bound VM stays where it is |
| Automatic HA / restart on another host | **Not implemented.** A dead host is reported (`NotReady`, held deletes); VMs are not restarted elsewhere, because without fencing that risks two running copies of one disk |
| Several `HostPool`s per Provider | **Not supported**: exactly one |
| Per-tenant quota | **None.** Hosts fill first come, first served. Use a Kubernetes `ResourceQuota` such as `count/virtualmachines.infra.virtrigaud.io`, or give tenants separate Providers and pools |
| Storage-pool aware placement | **Not enforced.** `storage.virtrigaud.io/pool-<name>` labels are accepted but do not affect placement |
| Changing `spec.topology` | **Rejected** (immutable) |

## Host prerequisites

Everything in [Libvirt host preparation](../../operations/libvirt-host-prepare.md)
applies to every host of a clustered Provider: packages, the SSH user and its
sudo rules, `known_hosts`, SSH rate limiting and AppArmor/SELinux. That page
is not repeated here. In addition, each host of a clustered Provider needs:

- **libvirt's `default` storage pool at `/var/lib/libvirt/images`.** VM disks
  and imported disks are created there. If the host has no `default` pool the
  provider creates one at that path on the first create; a `default` pool at
  any **other** directory is never changed and makes a create fail
  with `InvalidSpec` and a routed import be refused (`HOST_STORAGE_MISCONFIGURED`). Check with
  `virsh pool-dumpxml default | grep '<path>'`. A host whose `default` pool is
  missing, inactive or elsewhere reports `allocatableStorageBytes: 0`.
- **The cloud-init seed directory**, owned by the SSH user, mode `0711`:

    ```bash
    install -d -m 0711 -o <ssh user> -g <ssh user> /var/lib/libvirt/virtrigaud-seeds
    ```

    A host whose seed directory is missing and cannot be created, not owned by the SSH user, or
    readable or writable by group or others refuses every create (and every clone of a VM
    that has a seed), retryably, with `refusing to stage cloud-init data`. Keep
    it on a local filesystem, not on shared storage.
- **`flock` (util-linux), `timeout` (coreutils) and `qemu-img`.** The routed
  clone, export and import run their long copies under `flock` and `timeout`;
  a host without them fails those calls rather than running the copy
  unguarded.
- **Sudo rules for the copies.** Clones and exports run `qemu-img` as root
  through sudo rules; a clustered Provider needs the same rules plus the
  `timeout` lines. See [What the copies run as
  root](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/libvirt-clones.md#what-the-copies-run-as-root).
- **If hosts share storage** (an NFS export, for example): mount it **at**
  `/var/lib/libvirt/images` on every host of the Provider, at the same path,
  with NFS locking enabled (NFSv4, or NFSv3 with `lockd`/`statd`), and mount
  it on the hosts of **one** clustered Provider only. Keep the image catalog
  (`VIRTRIGAUD_LIBVIRT_IMAGE_DIRS`, set through `spec.runtime.env`) in a
  directory separate from the shared pool, or any tenant of the Provider can
  name files in the pool as a base image. See
  [Shared-storage disk guard](operations.md#shared-storage-the-cluster-wide-disk-guard).
- **A base image on every host that can be chosen.** The scheduler does not
  check whether an image is present on a host. A VM whose `VMImage` names a
  host path (`source.libvirt.path`) fails to create on a host that lacks the
  file.
- **Egress for NFS migration sources.** Hosts that may be the source of an
  `nfs` migration need network access to the NFS server (TCP 2049, and 111 for
  NFSv3).

Do not front one hypervisor with both a single-host Provider and a clustered
one, and keep one clustered Provider per host endpoint.

## Complete first setup

Everything below goes in one namespace, `virtrigaud-system`, so the same-namespace
model holds. Replace the placeholders (`*.example.com`, key material, image
path) with your own. The Provider and its credentials come first:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: libvirt-cluster-creds
  namespace: virtrigaud-system
type: Opaque
stringData:
  ssh-privatekey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    REDACTED
    -----END OPENSSH PRIVATE KEY-----
  known_hosts: |
    |1|REDACTED_HASH_1=|REDACTED_HASH_2= ssh-ed25519 REDACTED_HOST_PUBLIC_KEY
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: libvirt-cluster
  namespace: virtrigaud-system
spec:
  type: libvirt
  topology: cluster
  endpoint: qemu+ssh://virtrigaud@placeholder.example.com/system
  credentialSecretRef:
    name: libvirt-cluster-creds
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.4.1"
    service:
      port: 9443
      tls:
        enabled: true
        secretRef:
          name: libvirt-cluster-tls   # tls.crt, tls.key, ca.crt; see the mTLS page
```

The provider's TLS Secret is the same one a single-host Provider uses; see
[mTLS](../../providers/security/mtls.md). The pool and two hosts:

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
    cpu: "2.0"
    memory: "1.0"
---
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
    storage.virtrigaud.io/pool-nfs01: "true"
  schedulable: true
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: Host
metadata:
  name: host-b
  namespace: virtrigaud-system
spec:
  providerRef:
    name: libvirt-cluster
  poolRef:
    name: pool-a
  endpoint: qemu+ssh://virtrigaud@host-b.example.com/system
  labels:
    net.virtrigaud.io/default: "true"
    storage.virtrigaud.io/pool-nfs01: "true"
  schedulable: true
```

The `Host` name is also the **host id** the provider and the scheduler use.
Repo examples: [`provider-libvirt-clustered.yaml`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/examples/provider-libvirt-clustered.yaml),
[`hostpool-clustered.yaml`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/examples/hostpool-clustered.yaml) and
[`host-libvirt-clustered-first-vm.yaml`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/examples/host-libvirt-clustered-first-vm.yaml).

Check that the manager sees the hosts before creating a VM:

```bash
kubectl get provider libvirt-cluster -n virtrigaud-system
kubectl get hosts,hostpools -n virtrigaud-system
```

Within about a minute each host should show `HEALTH` `Ready` and the pool
should show `SCHEDULABLE` equal to the number of uncordoned hosts. A host that
stays `Unknown` or `NotReady` is covered in
[Operations and troubleshooting](operations.md#troubleshooting).

Then the VM's own objects: a network attachment (the one the network label
refers to), a class, an image and the VM.

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMNetworkAttachment
metadata:
  name: libvirt-default
  namespace: virtrigaud-system
spec:
  network:
    libvirt:
      networkName: "default"     # the Host label net.virtrigaud.io/default
      model: virtio
  ipAllocation:
    type: DHCP
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: small
  namespace: virtrigaud-system
spec:
  cpu: 2
  memory: "2Gi"
  firmware: BIOS
  diskDefaults:
    type: thin
    size: "20Gi"
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-22-04
  namespace: virtrigaud-system
spec:
  source:
    libvirt:
      # Must exist at this path on every host that can be chosen, directly
      # inside an allowed image directory (default /var/lib/libvirt/images).
      path: "/var/lib/libvirt/images/ubuntu-22.04-cloudimg.qcow2"
      format: qcow2
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: web-1
  namespace: virtrigaud-system
spec:
  providerRef:
    name: libvirt-cluster
  classRef:
    name: small
  imageRef:
    name: ubuntu-22-04
  networks:
    - name: libvirt-default
      networkRef:
        name: libvirt-default
  powerState: "On"
  userData:
    cloudInit:
      inline: |
        #cloud-config
        hostname: web-1
```

The scheduler picks `host-a` or `host-b`; nothing in the VM names a host. To
pin a VM or keep VMs apart, add a `VMPlacementPolicy` (see
[Placement](placement.md#vmplacementpolicy)).

## First VM checklist

If a first VM stays `Placed=False/Unschedulable`, one of these is almost always
missing. The scheduler checks exactly these things, in this order, and the
hard filters run before scoring:

1. **The `Host` is registered under the right Provider and pool.**
   `spec.providerRef` names the clustered Provider, `spec.poolRef` names its
   `HostPool`, and both are in the Provider's namespace.
2. **`status.health` is `Ready` and `spec.schedulable` is `true`.**
   `kubectl get hosts` shows both; `kubectl get hostpools` shows how many hosts
   pass this test.
3. **A `net.virtrigaud.io/<network>: "true"` label on `Host.spec.labels`
   for every network the VM uses.** `<network>` is each
   `VMNetworkAttachment`'s `spec.network.libvirt.networkName`, or, when that is
   empty, `spec.network.libvirt.bridge.name`. This is a **hard filter**: a Host
   missing even one required label is never a candidate, however much free
   capacity it has. It is the most common reason a first VM never schedules.
4. **Free capacity for the VM's `VMClass`**, after the pool's overcommit ratio
   and every VM already on the host.
5. **If the VM has `spec.placementRef`**, its hard constraints must be
   satisfiable by at least one candidate host.

!!! warning "These are `Host.spec.labels`, not Kubernetes labels"
    `kubectl label host ...` sets `metadata.labels`, which the scheduler never
    reads. Patch the spec:

    ```bash
    kubectl patch hosts.infra.virtrigaud.io host-a -n virtrigaud-system \
      --type merge -p '{"spec":{"labels":{"net.virtrigaud.io/default":"true"}}}'
    ```

    The value must be the string `"true"`. No restart is needed; the VM is
    retried on its normal backoff.

!!! note "Storage-pool labels are not on the list"
    `storage.virtrigaud.io/pool-<name>` labels are accepted on `Host.spec.labels`
    and worth setting to match your storage layout, but v0.4.1 does **not**
    enforce them: the VirtualMachine controller does not map a VM's disks to a
    storage-pool name, so a missing storage-pool label never blocks placement.
    Likewise, no machine-type requirement is derived from a VM.

When the VM is placed:

```console
$ kubectl get virtualmachine web-1 -n virtrigaud-system \
    -o jsonpath='{.status.placement.host}{"  "}{range .status.conditions[?(@.type=="Placed")]}{.status}/{.reason}{end}{"\n"}'
host-a  True/Bound
```

For what each `Placed` and `Provisioning` reason means, see
[Placement](placement.md#unschedulable-and-related-reasons).

## VMs in other namespaces

A VM may live in a different namespace than the Provider and reference it with
`spec.providerRef.namespace`. The Provider must allow that namespace through
`spec.consumerNamespaceSelector` (unset means only its own namespace; `{}`
means every namespace). A reference from a namespace the selector does not
select is refused with `Ready=False`, reason `ConsumerNotAllowed`, and no
provider call is made. Cross-namespace `VMClass` and `VMImage` references are
gated the same way. The hosts and pool are still looked up in the Provider's
namespace.

Two clustered-specific consequences for such consumer VMs:

- `virtrigaud.io/orphan-on-delete` and `virtrigaud.io/force-delete` are
  honoured only when the Provider carries the annotation
  `infra.virtrigaud.io/allow-consumer-orphan-on-delete: "true"`; see
  [Operations](operations.md#detaching-a-vm-orphan-on-delete-and-force-delete).
- All consumers share the pool's capacity with no quota (above).

See [Security model and multi-tenancy](../security-model.md) for the full
ownership and cross-namespace model.

## Next steps

- [Placement](placement.md): how a host is chosen, and what to do when none is.
- [Operations and troubleshooting](operations.md): what happens when a host
  stops answering, cordoning, and the metrics to watch.
- [Libvirt provider](../../providers/libvirt.md) for the single-host
  provider that clustered mode builds on.
- Reference: [ADR-0007](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/adr/0007-clustered-orchestrator-provider.md)
  and the full [clustered inventory reference](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/clustered-provider-inventory.md).
