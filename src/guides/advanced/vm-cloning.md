<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VM Cloning (VMClone)

The **VMClone** controller clones an existing, provisioned `VirtualMachine` into a new one through a declarative resource. It shipped in **v0.3.8** and gained libvirt support in v0.3.9; v0.4.0 adds a new cloud-init identity for every clone, owner stamping and idempotent re-sends, the cross-namespace target grant, and, on libvirt, a powered-off source requirement and the disabling of linked clones. v0.4.1 makes Proxmox clones carry a seed of their own, stops advertising Proxmox linked clones, and stops sending a `VMClone`'s unused customization secrets to the provider.

This page covers the scope and limits, the per-provider rules, what a clone boots with, what the controller produces, the cross-namespace rules, and clean-up.

!!! note "Scope"
    **`source.vmRef` only, same provider only.** `source.snapshotRef`, `source.templateRef` and `source.imageRef` are declared in the CRD but not implemented: they fail the clone with reason `UnsupportedSource`. Of the rest of the `VMClone` schema, the controller uses `spec.source.vmRef`, `spec.target.{name,namespace,classRef,labels,annotations,networks,placementRef}`, `spec.options.{type,powerOn}` and `spec.customization` (an allow-listed part of it is passed to the provider, which applies only part of that, see [below](#a-clones-identity) and [Customization secrets are not sent](#customization-secrets-are-not-sent)). The retry policy, performance and storage options, `includeSnapshots`, `target.providerRef` and `target.disks` are accepted but not acted on.

## What VMClone does

Given a reference to a provisioned source `VirtualMachine` in the same namespace, the controller:

1. creates the **target `VirtualMachine`** first (so the clone can be stamped with the target's UID), records its UID in `status.targetUID`, and keeps it without `status.id` until the clone is bound;
2. asks the source VM's Provider to clone the hypervisor VM (`Clone` RPC), sending the target's namespace, name and UID;
3. when the provider answers, seeds the target's `status.id` with the clone's id and labels the target `virtrigaud.io/adopted=true`, so the VirtualMachine controller adopts the clone instead of creating a second VM.

```
┌──────────────┐        Clone        ┌────────────────────────┐
│  VMClone CR  │ ──────────────────▶ │ Provider (vSphere /     │
│ source.vmRef │  + target identity  │  Proxmox / libvirt)     │
│              │ ◀────────────────── │  new VM id, stamped     │
└──────┬───────┘     clone id        └────────────────────────┘
       │ creates first, binds after
       ▼
┌──────────────────────────────────────────────┐
│ target VirtualMachine CR                       │
│  labels: virtrigaud.io/adopted=true            │
│  status.id: <provider clone id> (seeded)       │
└──────────────────────────────────────────────┘
```

## Scope and limits

| Dimension | Behaviour |
|-----------|-----------|
| **Source** | `source.vmRef` in the VMClone's namespace. The VM must be provisioned (non-empty `status.id`); otherwise the clone waits (`SourceNotFound` or the VM's own state) |
| **Provider** | The target lands on the source VM's Provider. Cross-provider movement uses [VM migration](../../migration/vm-migration-guide.md). The Provider must report `Clone` support (the optional Cloner capability), otherwise the clone fails with `Unsupported` |
| **Clone types** | `FullClone` (default) and `LinkedClone`. `InstantClone` is in the enum but not implemented |
| **Power** | The produced VM's `spec.powerState` is `On` when `options.powerOn: true`, otherwise `Off` (the default). Every provider leaves a clone powered off; the VirtualMachine controller powers it on when its spec says so |
| **Owner check** | The provider must be able to prove the source hypervisor VM is the source `VirtualMachine`'s (a reused VM id is not): otherwise the clone fails with reason `VMNotOwned` or `OwnerStampUnreadable` and nothing is copied |
| **Clustered Providers** | A clone lands on the source VM's own host and is admitted against that host's free capacity; a cordoned, unready or missing source host holds it (`SourceHostCordoned`, `SourceHostNotReady`, `SourceHostGone`). See [Clustered libvirt: operations](../clustered/operations.md#troubleshooting) |
| **Disk-size limit** | A clone never creates a disk above the administrator's disk-size limit (`manager.maxDiskSize`): the source's disks and the target class are checked before the `Clone` is sent, and the clone is held if one exceeds it |

### Per provider

| | vSphere | Proxmox | libvirt (single host) | libvirt (clustered, experimental) |
|---|---|---|---|---|
| **Full clone** | Yes. A running source can be cloned | Yes | Yes. **The source must be powered off** | Yes. Same rules as single host; lands on the **source VM's own host** |
| **Linked clone** | Yes (needs the provider to report `supportsLinkedClones`) | **Refused since v0.4.1**: `LinkedCloneUnsupported` (it never made linked clones) | **Disabled**: `LinkedCloneUnsupported` | **Not offered**: `LinkedCloneUnsupported` |
| **New cloud-init identity** | Yes (rewritten in `CloneVM_Task`) | Yes: a clone of a VM that has a seed, or with inline user-data, gets a seed of its own; otherwise PVE regenerates its cloud-init drive | Yes (clone gets its own NoCloud seed ISO) | Yes |
| **`spec.customization` applied** | Hostname/domain in the cloud-init meta-data; other fields logged, not applied | `hostname`, `domain` and `userData.cloudInit.inline`, when the clone gets a seed (since v0.4.1); nothing otherwise | `hostname`, `domain`, `userData.cloudInit.inline`; other fields logged, not applied | Same as single host |

!!! note "Proxmox: full clones only, and a clone gets the class's memory"
    A Proxmox `VMClone` is always a full clone. `spec.options.type: LinkedClone` fails with `LinkedCloneUnsupported` before the provider is called (v0.4.0 passed `full=0` and left the outcome to PVE). A clone also gets the VMClass's memory since v0.4.1: the controller sends the class as a `VMClassSpec` (CPU and a memory quantity), and the provider read only a `memoryMiB` field, so a clone kept its source's memory before. The lab validation of v0.4.1 covered Proxmox full clones, with and without a seed.

## libvirt full clones

### The source must be powered off

A libvirt full clone copies the source's disk chain with `qemu-img convert`, which cannot open an image a running QEMU holds, and a copy of a disk a running guest writes would not be consistent anyway. The provider reads the source's state **before copying anything** and refuses any state but "shut off" with `FailedPrecondition` (reason `VM_SOURCE_RUNNING`). The VMClone is **not failed**:

- it stays `Pending` with `Ready=False` and reason **`SourceMustBePoweredOff`**, and one `Warning` event;
- it is re-checked with a backoff (15 s doubling to 5 min) and immediately whenever the source's observed `status.powerState` changes, so it proceeds as soon as the source is off;
- a waiting clone shows no `startTime` and never `Phase=Cloning`.

To clone a running VM: set the source's `spec.powerState: Off`, wait for the clone to become `Ready`, then power the source back on. vSphere clones running VMs.

### Linked clones are disabled on libvirt

A libvirt linked clone's backing file is the source VM's **live** disk, and nothing freezes it. If the source is powered on while a linked clone of it exists, the source's writes corrupt the clone. So the libvirt provider reports `supportsLinkedClones: false`, and a `VMClone` with `options.type: LinkedClone` fails before any provider call: `Phase=Failed`, `Ready=False`, reason `LinkedCloneUnsupported`, message naming `spec.options.type: FullClone`. Recreate it as a full clone. A libvirt linked clone into **another namespace** is refused too (`LinkedCloneCrossNamespace`).

### Linked clones and the source VM

Linked clones made by an earlier release keep working, and the provider protects them. While another domain on the host uses the source VM's disk as a backing file, the provider **refuses** delete, snapshot create, snapshot delete and snapshot revert of the source (`VM_DISK_IN_USE`), and a `VMMigration` of the source fails at its snapshot step. A refused VM delete keeps the finalizer with `Ready=False` / `DeleteBlocked` and completes by itself once the clones are gone; delete the linked clones first. Powering the source on is never refused, but the `VirtualMachine` then gets the condition `LinkedClonesDependOnDisk=True` and a `Warning` event: powering it on while its linked clones are shut off corrupts them. Keep the source of an existing linked clone powered off. Reference: [libvirt clones and the linked-clone dependency](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/libvirt-clones.md).

### Other libvirt details

- The clone is named `<target namespace>.<target name>` on the host and its disk is always **qcow2**, a standalone copy that flattens the source's whole image chain (a source with external snapshots clones to one disk without them).
- A UEFI source's clone gets its **own** `<nvram>` varstore; source and clone do not share EFI variables.
- Hot-add headroom is preserved: if the source's class has `cpuHotAddEnabled` / `memoryHotAddEnabled`, the clone keeps the headroom, recomputed from the override class if the clone sets `target.classRef`.
- On a **clustered** Provider a clone is a full clone only, of a source with a single writable disk, on the source's host (no cross-host clone).
- The copy runs `qemu-img convert` through passwordless `sudo` where the host allows it (needed to read the `0600` overlay of a VM that has an external snapshot). The sudoers rule and the pool-directory requirements (a pool directory other accounts can write, and not sticky, makes clones fail with `FailedPrecondition`) are in [libvirt host preparation](../../operations/libvirt-host-prepare.md#sudo-rules-for-disk-reads-and-copies) and in the [repository reference](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/libvirt-clones.md#what-the-copies-run-as-root).

## A clone's identity

A full clone copies the source's disk, and with it cloud-init's record of the instance the source last booted as. If the clone presented the source's `instance-id`, cloud-init would treat its first boot as a reboot of the same instance and keep the source's **SSH host keys** and hostname. So every provider gives a clone a new identity:

| Provider | What the clone boots with | How |
|----------|--------------------------|-----|
| libvirt (single host and clustered) | `instance-id: virtrigaud-<target VirtualMachine uid>`; `local-hostname` = `spec.customization.hostname` (with `.domain`, the FQDN) or the target VM's name | The clone gets its **own** NoCloud seed ISO. Without `spec.customization.userData.cloudInit.inline`, the source's user-data is carried with its top-level `hostname:` / `fqdn:` keys rewritten. A source without a seed ISO gives a clone without one |
| vSphere | The same `instance-id` and hostname | The clone's `guestinfo.metadata` (and a `#cloud-config` `guestinfo.userdata`'s `hostname:` / `fqdn:`) are rewritten in the same `CloneVM_Task` |
| Proxmox | A new instance-id (`virtrigaud-<target VirtualMachine uid>`), the customization's hostname (with `domain`) or the target's name as hostname, and DHCP on the clone's own MACs | **A VM with a seed** (or a `VMClone` with inline user-data): the provider builds a seed of its own for the clone. It does **not** carry the source's user-data (libvirt and vSphere clones re-run it): the user-data is the `VMClone`'s inline user-data, else a cloud-config that configures nothing. A VM without a seed: PVE regenerates the cloud-init drive from the clone's own config. See [Proxmox: cloning](../../providers/proxmox.md#cloning) |

On the new instance, cloud-init regenerates the SSH host keys (`ssh_deletekeys` defaults to `true`) and **re-runs every per-instance module** of the user-data (`runcmd`, `packages`, `users`, `write_files`). It does **not** change:

- **`/etc/machine-id`**: a clone of a VM whose machine-id is populated keeps it, and anything derived from it (the DHCP client identifier of systemd-networkd, for example). Seal the source (`cloud-init clean --machine-id` before it is shut down for cloning) if clones must have their own.
- **Static network configuration** in the source's meta-data or `network-config`: a clone of a VM with a static address claims the same address.
- **User-data that pins the identity.** `ssh_keys`, `ssh_deletekeys: false`, `preserve_hostname: true` and `manual_cache_clean: true` undo the new instance. The libvirt and vSphere providers log a `WARN` naming such keys (never their values). Remove them from the source's user-data, or give the clone its own with `spec.customization.userData.cloudInit.inline` (libvirt).
- **Customization fields the provider does not apply.** The libvirt provider applies `hostname`, `domain` and `userData.cloudInit.inline` only (`networks`, `timeZone`, `guestCommands`, `sysprep`, `certificates`, `tags`, `userData.ignition` are logged and ignored; user-data from a `secretRef` is not resolved, the clone keeps the source's). vSphere applies the hostname/domain to the meta-data and ignores the rest. Proxmox applies `hostname`, `domain` and `userData.cloudInit.inline` when the clone gets a seed (user-data given by a Secret reference cannot be resolved and is not applied), and nothing otherwise.

Clones of VMs that do not use cloud-init are unaffected, and clones made before v0.4.0 keep the identity they booted with.

!!! warning "`create` on `vmclones` is read access to the source VM's data"
    A clone is a full copy of the source's disk, and it runs cloud-init user-data as **root** on its first boot. On libvirt that user-data can be the `VMClone`'s `spec.customization.userData.cloudInit.inline`; on every provider the clone also re-runs the source's own user-data, which may carry secrets. Anyone who can `create` a `VMClone` of a VM can run commands as root on a copy of that VM's disk and read everything on it. Grant `create` on `vmclones` in a namespace only to subjects trusted with read access to every VM's data in that namespace. See [Security model](../security-model.md#limits-to-know).

## Worked example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClone
metadata:
  name: basic-clone
  namespace: default
spec:
  source:
    vmRef:
      name: my-source-vm          # a provisioned VirtualMachine in this namespace
  target:
    name: my-cloned-vm
    classRef:
      name: standard-vm           # optional: defaults to the source VM's class
    labels:
      app: cloned-app
  options:
    type: FullClone               # or LinkedClone (vSphere only)
    powerOn: false                # the default
```

```bash
kubectl apply -f basic-clone.yaml
kubectl get vmclone basic-clone -o wide     # source, target, phase, clone type
kubectl get vm my-cloned-vm                 # the produced VirtualMachine
```

The canonical file is [`examples/vmclone-basic.yaml`](../../examples/vmclone-basic.yaml); Proxmox and vSphere variants are in [Advanced examples](../../examples/advanced/index.md).

If the provider does not report `SupportsLinkedClones`, the controller refuses a `LinkedClone` request up front (`Failed`, `LinkedCloneUnsupported`); it never falls back to a full clone. A provider that reports no capabilities at all is refused the same way (fail closed), and a failed capability query makes the clone wait.

## What the controller produces

The target `VirtualMachine` named `spec.target.name` has:

- **`providerRef`** = the source VM's `providerRef` and **`classRef`** = `spec.target.classRef` or the source's class;
- **`spec.powerState`** from `options.powerOn` (`On`, else `Off`);
- the labels and annotations you set under `spec.target`, **plus `virtrigaud.io/adopted=true`** and clone-provenance annotations. Keys in the operator's reserved `virtrigaud.io` domain are not copied from `spec.target.annotations`, so a clone cannot carry `virtrigaud.io/orphan-on-delete` or `force-delete` from the VMClone;
- `spec.networks` and `spec.placementRef` when set under `spec.target`;
- **`status.id`** seeded with the provider's clone id, and `status.boundProvider` recording the Provider the clone ran on.

The VMClone's status:

| Field | Meaning |
|-------|---------|
| `status.phase` | The API accepts `Pending`, `Preparing`, `Cloning`, `Customizing`, `Powering-On`, `Ready` and `Failed`. The controller sets only `Pending`, `Cloning`, `Ready` and `Failed` |
| `status.targetRef` | The produced `VirtualMachine` |
| `status.targetUID` | The UID of the target the clone created before the `Clone`; the stamp the provider writes |
| `status.targetVMID` | The provider's clone id; persisted so an asynchronous clone task can seed the target after it completes |
| `status.actualCloneType` | `FullClone` or `LinkedClone` |
| `Ready` condition | `True` only once the target exists and its `status.id` is seeded |

### Stamping and re-sends

The provider stamps each clone with its **target** VirtualMachine's identity (namespace, name, UID): vSphere in ExtraConfig, libvirt in the domain metadata, Proxmox in the VM description. A clone never claims the source's owner stamp. So a `Clone` sent again for the same target (the manager restarted, or an answer was lost) **returns the clone an earlier attempt made instead of making a second one**; a VM of the clone's name that is not provably the target's is refused (`AlreadyExists`). The manager only re-sends to a provider that reports `supportsOwnerRebind`; for an older provider image an unknown outcome fails the clone rather than risk a second VM.

While a clone is held, the VMClone is `Pending` with `Ready=False` and one of these reasons: `CloneRetrying` (nothing was done; retried 15 s doubling to 5 min), `CloneOutcomeUnknown` (the answer was lost; the `Clone` is sent again), `SourceMustBePoweredOff` (libvirt). On a clustered Provider a clone also waits (re-checked every 2 minutes) while the source VM's host cannot take it: `SourceHostGone`, `SourceHostNotReady`, `SourceHostCordoned` or `SourceHostExcluded`. Terminal failures are `Failed`: `ProviderConflict` (the provider refused a first attempt with `AlreadyExists`), `TargetConflict`, `LinkedCloneUnsupported`, `UnsupportedSource`, `Unsupported`, `ProviderError`. Details: [Provider calls whose outcome was lost](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/provider-call-outcomes.md).

## Customization secrets are not sent

Before v0.4.1 the manager sent all of `spec.customization` in the `Clone` request, including plaintext values that no provider acts on: `sysprep.productKey`, `sysprep.adminPassword.value`, `sysprep.joinDomain.password.value`, `sysprep.customCommands`, `certificates[].data`, `guestCommands[].command` and `.arguments`, and `userData.ignition.inline`. The request now carries only an allow-list of what providers apply (`hostname`, `domain`, `userData.cloudInit.inline`) or report as not applied; nothing changes in what a clone gets.

- **Rotate any such value you set on v0.4.0 or earlier.** It was sent to the provider and, without gRPC TLS, over the network between the manager and the provider. It also stays in plaintext in the object, in etcd backups, in API-server audit logs (at `Request` level or above), in the `kubectl.kubernetes.io/last-applied-configuration` annotation and in your GitOps sources.
- **The fields are still stored in plaintext in the `VMClone`**: the v1beta1 API keeps them. Do not put a real password, key or other credential in them.
- When one of these fields is set, the manager records a `Warning` event (`CustomizationSecretNotSent`) once the provider accepts the clone, and with `webhooks.enabled=true` a warning-only webhook (`vvmclone-customization.kb.io`, failure policy always `Ignore`) returns one admission warning on create and on an update that changes `spec.customization`. Both name the fields, never their values. The warning is advisory: to forbid the fields, add your own admission policy.
- Provider authors: a `CloneRequest`'s `customize_json` is an allow-listed subset of `spec.customization`; do not rely on receiving the fields above.

## Cross-namespace targets

`spec.target.namespace` can name another namespace; the default is the VMClone's own, which needs nothing. For another namespace, **two grants** are required:

1. **The target `Namespace` must allow the VMClone's namespace.** It must carry the annotation `infra.virtrigaud.io/allowed-source-namespaces` whose comma-separated value lists the source namespace (exact names; no wildcards):

    ```bash
    kubectl annotate namespace team-b infra.virtrigaud.io/allowed-source-namespaces=default
    ```

    Whoever can update the target `Namespace` can grant this (normally a cluster administrator). Without it the clone waits `Pending` with `Ready=False`, reason `TargetNamespaceNotAllowed`, and nothing is created, read or bound in the target namespace. The refusal is not a failure: granting the annotation, or changing the field, resumes it. The grant is re-checked before every step that touches the target namespace, so revoking it stops a clone already in flight; what already exists is not touched.
2. **The Provider and VMClass the target uses must share themselves with the target namespace.** They live in the source namespace, so their `spec.consumerNamespaceSelector` must select the target namespace; otherwise the clone waits with `Ready=False` / `ConsumerNotAllowed`. The controller pins the namespace of `providerRef` and `classRef` on the target when it differs from the source's.

A libvirt **linked** clone into another namespace is refused (it would keep reading the source's disk indefinitely); use a full clone. Reference: [Cross-namespace clone and migration targets](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/cross-namespace-targets.md) and [cross-namespace references](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/cross-namespace-references.md).

## Lifecycle and clean-up

!!! danger "Deleting a VMClone does NOT delete the produced VM"
    A `VMClone` is a one-shot operation, not the owner of its clone. Deleting it drops its finalizer; the produced `VirtualMachine` and the hypervisor VM are preserved. To remove the clone, delete the produced `VirtualMachine`:

    ```bash
    kubectl delete vm my-cloned-vm
    ```

`Failed` is terminal: fix the spec and create a new `VMClone` rather than editing the failed one. When a clone fails for good, the controller removes, once, the **unbound** target `VirtualMachine` it created (a target whose clone the provider made or may have made is kept so an administrator can bind or delete it), and records the decision in the `TargetCleanup` condition.

## Related resources

- **VMSet** has no controller in v0.4.1 (it reports `ControllerNotImplemented`); see [Advanced VM lifecycle](advanced-lifecycle.md#placement-and-sets).
- **VMPlacementPolicy** is used by the scheduler of clustered libvirt Providers; `spec.target.placementRef` is copied onto the target VM.

## See also

- [Advanced VM lifecycle](advanced-lifecycle.md): reconfiguration, snapshots and revert, detaching VMs.
- [VM status reference](../vm-status.md): the `CloneRetrying`, `CloneOutcomeUnknown` and other reasons a held clone shows, and how to read them.
- [Clustered libvirt: operations](../clustered/operations.md#routed-owner-checked-lifecycle): clone routing, `SourceHostCordoned` and the other clustered clone holds.
- [Security model](../security-model.md): who may clone, cross-namespace targets and ownership stamps.
- [Provider capabilities matrix](../../providers/providers-capabilities.md): which providers support `Clone` and linked clones.
- [VM migration](../../migration/vm-migration-guide.md): moving a VM between providers.
- [`examples/vmclone-basic.yaml`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/examples/vmclone-basic.yaml): the canonical example in the main repository.
