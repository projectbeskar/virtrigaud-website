<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Security Model and Multi-Tenancy

This page describes what VirtRigaud **v0.4.1** enforces when several teams
(namespaces) share a cluster, a `Provider` or a hypervisor, and what you have
to configure for it. It covers VM ownership, cross-namespace references, the
admission policy, the `Provider` in-use finalizer, prepared-image identity,
private cloud-init seeds, migration storage mounts and the disk-size limit. A
table at the end lists what can break an existing setup when you upgrade from
v0.3.11.

!!! note "Out of scope"
    Transport security between the manager and the providers (mTLS, bearer
    tokens, network policies), credentials handling, RBAC and container
    hardening are covered in [Security](../operations/security.md) and in the
    pages under *Providers > Security* ([mTLS](../providers/security/mtls.md),
    [bearer token](../providers/security/bearer-token.md),
    [network policies](../providers/security/network-policies.md)). This page does
    not repeat them.

!!! warning "Trust boundaries stay with you"
    VirtRigaud's checks are only as strong as the permissions around them. The
    manager has cluster-wide RBAC, so the checks below are what stop a tenant
    from driving another tenant's objects. They assume tenants can write
    objects in their own namespaces and nothing cluster-scoped, and that
    `status` subresources of `VirtualMachine` and `VMMigration` stay writable
    by the manager and platform administrators only.

## What is enforced, and where

| Concern | Enforced by | Section |
|---|---|---|
| A VM is bound to a hypervisor VM only if VirtRigaud created (or adopted) it | The providers, with an owner stamp on the hypervisor VM | [VM ownership](#vm-ownership) |
| A namespace uses another namespace's `Provider`, `VMClass`, `VMImage` only if it is granted | The controllers (`spec.consumerNamespaceSelector`) | [Cross-namespace references](#cross-namespace-references) |
| A clone or migration creates a VM in another namespace only if that namespace allows it | The controllers (a `Namespace` annotation) | [Cross-namespace targets](#cross-namespace-clone-and-migration-targets) |
| Only the manager writes the `virtrigaud.io` markers on a `VirtualMachine` | A `ValidatingAdmissionPolicy` in the API server | [Admission policy](#admission-policy-reserved-keys) |
| A `Provider` that VMs still use is not deleted from under them | A finalizer on the `Provider` ([ADR-0010](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/adr/0010-provider-in-use-finalizer.md)) | [Provider in-use finalizer](#provider-in-use-finalizer) |
| A prepared image belongs to the `VMImage` and source it was prepared for | The providers, with an image stamp ([ADR-0009](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/adr/0009-prepared-image-artifact-identity.md)) | [Identity-safe image preparation](#identity-safe-image-preparation) |
| A VM's cloud-init user-data is not readable by other local users of a libvirt host | The libvirt provider, with a private seed directory | [Private cloud-init seeds](#private-cloud-init-seeds-libvirt) |
| Provider pods mount only the migration storage a live migration needs | The manager | [Migration storage](#migration-storage) |
| No disk above an administrator's ceiling is created or grown | The manager (`manager.maxDiskSize`) | [Disk-size limit](#disk-size-limit) |

## VM ownership

A hypervisor identifies a VM by a name or an id that other tenants can also
ask for: two `VirtualMachine`s called `web` in different namespaces want the
same vSphere name, a Proxmox VMID can be handed to an unrelated VM after the
original is removed, and a VM can exist for reasons that have nothing to do
with VirtRigaud. Binding by name or id alone would let one tenant power off,
resize or delete another tenant's VM.

The rule, followed by the vSphere, libvirt and Proxmox providers:

**VirtRigaud never binds a `VirtualMachine` to an existing hypervisor VM unless
it can prove that this `VirtualMachine` created (or adopted) it.**

### How it works

1. **The owner travels with every call.** The manager sends the
   `VirtualMachine`'s UID, namespace and name as `owner` on `Create`.
   Only the UID authorizes anything; namespace and name are for audit.
2. **The owner is stamped on the hypervisor VM** when it is created.
3. **A create that finds a VM with the requested name fails closed.** It binds
   to it (and succeeds idempotently) only if the stamp carries the requester's
   UID; this covers a create retried because the manager lost its `status.id`
   write. In every other case the create is refused with a non-retryable
   `Conflict`.

Where the stamp lives:

| Provider | Stamp | Inspect it |
|---|---|---|
| vSphere | ExtraConfig keys `virtrigaud.owner.uid`, `virtrigaud.owner.namespace`, `virtrigaud.owner.name` (no `guestinfo.` prefix, so the guest cannot read them) | `govc vm.info -e <vm> \| grep virtrigaud.owner` |
| libvirt (single-host and clustered) | A `<virtrigaud:owner uid=… namespace=… name=…/>` element in the domain `<metadata>`, namespace URI `https://virtrigaud.io/xmlns/libvirt/owner/v1` | `virsh metadata <domain> --uri https://virtrigaud.io/xmlns/libvirt/owner/v1` |
| Proxmox | One line in the VM description (the "Notes" field): `virtrigaud.owner v1 uid=… namespace=… name=… phase=creating\|ready sum=…` | `qm config <vmid> \| grep virtrigaud.owner` |

New libvirt domains are named `<namespace>.<name>` on the host (VM `web` in
`team-a` becomes domain `team-a.web`), so two namespaces' VMs no longer collide.
Existing domains keep their names, and every operation after `Create` uses
`status.id`. Scripts that assumed "domain name equals `VirtualMachine` name"
must read `status.id` instead.

### Which calls are owner-checked

| Provider | `Create` / `Clone` | Per-VM calls (`Describe`, `Power`, `Reconfigure`, snapshots, disk read and export, `Delete`) |
|---|---|---|
| vSphere | Stamped; fails closed on a same-named VM in the target folder. Only real templates are clone sources. | Not owner-checked. `Delete`, `Power`, `Reconfigure`, `HardwareUpgrade` and the snapshot calls refuse a template or an image artifact (`VM_IS_IMAGE_ARTIFACT`). |
| libvirt, single-host | Stamped; fails closed on a same-named domain. | Not owner-checked. |
| libvirt, clustered | Stamped; fails closed. | Every routed call is owner-checked. See [Clustered operations](clustered/operations.md). |
| Proxmox | Stamped; a re-sent `Create` or `Clone` re-binds the VM it made earlier instead of making a second VMID. | Owner-checked on every call, so a reused VMID is never read, powered, resized, snapshotted, exported or deleted as if it were the `VirtualMachine`'s. |

The protection needs **both** the manager and the provider image of v0.4.1. A
request without an owner (an older manager) or a provider that ignores it
behaves as before. Roll the providers right after the manager.

### What you see when a check refuses

| Condition | Reason | Meaning | What to do |
|---|---|---|---|
| `Ready=False`, `Provisioning=False` | `ProviderConflict` | A VM with that name exists and VirtRigaud cannot prove it owns it. `status.id` stays empty, so deleting the `VirtualMachine` never touches the other VM. Re-checked every 2 minutes. | Adopt the VM (below), remove or rename the other VM, or recreate the `VirtualMachine` under another name. |
| `Ready=False`, `Provisioning=False` | `ValidationError` | The provider rejected the request as invalid. For ownership this means a name its tooling could resolve as something else: on vSphere `vm-<digits>` (the shape of a vCenter object id) or a name containing `/`, `\`, `%` or `:`. Re-checked every 30 seconds. | Rename the `VirtualMachine`. |
| `Ready=False` | `VMNotOwned` | (Proxmox) The VM at this VMID is not this `VirtualMachine`'s. `status.id` is kept and no VM is created in its place. | See [VM status](vm-status.md). |
| `Ready=False` | `OwnerStampUnreadable` | The stamp cannot be parsed or names more than one owner. Nothing is changed. | An administrator fixes or removes the stamp, or detaches the VM. |
| `Ready=False` | `VMIsImageArtifact` | The hypervisor object is a template or a prepared image, not a VM. | Detach with `virtrigaud.io/orphan-on-delete: "true"`. |

The messages name only the requested VM. They never say which namespace or
`VirtualMachine` owns the other one; the provider log has those details.
`virtrigaud_errors_total{reason="provider-create-rejected"}` counts refused
creates.

### Adoption stamps what it adopts

With `virtrigaud.io/adopt-vms` on a `Provider`, VirtRigaud creates a
`VirtualMachine` for each hypervisor VM that no `VirtualMachine` manages, and
**stamps the VM with that new `VirtualMachine`'s identity** before binding it.
So the owner-checked calls accept it, and another `Provider` object fronting
the same endpoint sees it as owned.

Adoption never takes:

- a VM already bound to a `VirtualMachine`, in any namespace or under any
  `Provider` object;
- a VM stamped with the UID of a `VirtualMachine` that exists;
- a template, an image artifact, or a VM whose stamp is unreadable.

A VM stamped **only** with UIDs of no `VirtualMachine` in this cluster is not
adopted either, because the stamp may belong to another VirtRigaud installation
managing the same vCenter or host. To adopt such VMs on purpose (for example
after detaching VMs with `orphan-on-delete`), on a single-host `Provider`:

```yaml
metadata:
  annotations:
    virtrigaud.io/adopt-vms: "true"
    virtrigaud.io/adopt-stamped-vms: "true"   # remove again afterwards
```

Set `adopt-stamped-vms` only when no other installation manages the same
endpoint. A clustered `Provider` never adopts a stamped VM; it reports it as a
previous incarnation (see [Backup and restore](clustered/backup-restore.md)).

To stop managing a VM without deleting it, annotate and delete the
`VirtualMachine`:

```bash
kubectl annotate virtualmachine <vm> -n <ns> virtrigaud.io/orphan-on-delete=true
kubectl delete virtualmachine <vm> -n <ns>
```

No provider call is made; the hypervisor VM keeps running. Pointing
`spec.providerRef` at a missing `Provider` no longer works for this: the field
is immutable once the VM is bound. On a clustered `Provider`, a VM in another
namespace than the `Provider` may only be detached or force-deleted if the
`Provider` carries `infra.virtrigaud.io/allow-consumer-orphan-on-delete: "true"`,
because a detached domain keeps running outside the capacity accounting.

### Limits to know

- **Proxmox, unstamped VMs.** A Proxmox VM created before owner stamps is
  treated as the `VirtualMachine`'s own while its PVE name equals the
  `VirtualMachine`'s name (or the name adoption would give it). Anyone who can
  create a VM at a freed VMID (`VM.Allocate` on a shared pool or an inherited
  path) can exploit that. Do not grant `VM.Allocate` where VirtRigaud's VMs
  live to anyone but the provider's own tokens and your administrators.
  [ADR-0012](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/adr/0012-proxmox-legacy-unstamped-name-rule.md)
  describes how the rule is to be retired; none of that is in v0.4.1.
- **A stamp is tamper-evident, not tamper-proof.** Whoever can edit the VM
  configuration on the hypervisor (vSphere `AdvancedConfig`, libvirt metadata,
  Proxmox `VM.Config.Options`) can rewrite the stamp. The hypervisor's ACLs are
  the trust boundary.
- **Give each Proxmox `Provider` its own API token**, so in-flight create
  tracking and audit trails are per `Provider`.
- **`create` on `vmclones` is read access to the source VM.** A clone is a full
  copy of the source disk and boots cloud-init user-data as root; on libvirt
  the `VMClone`'s own inline user-data runs as root on the copy. Grant `create`
  on `vmclones` only to subjects trusted with that VM's data. See
  [VM cloning](advanced/vm-cloning.md).
- **vSphere needs one more privilege.** Every `Create`, `Clone` and adoption
  writes ExtraConfig, so the vCenter account needs
  `VirtualMachine.Config.AdvancedConfig` (*Virtual machine > Change
  Configuration > Advanced configuration*) on the target folder and resource
  pool.

## Cross-namespace references

A `VirtualMachine` names its `Provider`, `VMClass` and `VMImage` with
`spec.providerRef`, `spec.classRef` and `spec.imageRef`, each of which can set
a `namespace`. Without a check, anyone allowed to create a `VirtualMachine` in
`team-a` could drive `team-b`'s `Provider` and its hypervisor credentials,
clone from `team-b`'s images, or use its classes.

**A reference to another namespace's `Provider`, `VMClass` or `VMImage` is
refused unless that object shares itself with the referencing namespace.**
These three kinds have an optional `spec.consumerNamespaceSelector` (a
standard label selector):

| `spec.consumerNamespaceSelector` | Who may reference the object |
|---|---|
| unset (default) | Only its own namespace |
| `{}` | Every namespace |
| `matchLabels` / `matchExpressions` | Its own namespace plus every namespace whose labels match |

A reference with no `namespace`, or naming the object's own namespace, always
works. The selector is matched against the `Namespace` object's labels; the API
server sets `kubernetes.io/metadata.name: <name>` on every namespace, so you can
name namespaces explicitly. Each object grants for itself: sharing a `Provider`
does not share its classes or images.

A `Provider` shared with two namespaces by name:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: vsphere-shared
  namespace: virtrigaud-system
spec:
  type: vsphere
  endpoint: https://vcenter.example.com/sdk
  credentialSecretRef:
    name: vsphere-creds
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.1"
    service:
      port: 9090
  consumerNamespaceSelector:
    matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: In
        values: ["team-a", "team-b"]
```

A `VMClass` every namespace may use:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: shared-small
  namespace: virtrigaud-system
spec:
  cpu: 2
  memory: "4Gi"
  consumerNamespaceSelector: {}
```

A `VMImage` shared with namespaces labelled `virtrigaud.io/tenant=gold`:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-22-golden
  namespace: virtrigaud-system
spec:
  source:
    vsphere:
      templateName: "ubuntu-22.04-cloudimg"
  prepare:
    onMissing: Fail
  consumerNamespaceSelector:
    matchLabels:
      virtrigaud.io/tenant: gold
```

A tenant VM that uses all three, from `team-a` (labelled
`virtrigaud.io/tenant: gold`):

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: web-01
  namespace: team-a
spec:
  providerRef: {name: vsphere-shared, namespace: virtrigaud-system}
  classRef:    {name: shared-small,   namespace: virtrigaud-system}
  imageRef:    {name: ubuntu-22-golden, namespace: virtrigaud-system}
  powerState: "On"
```

The complete example, applied together, is
[`examples/shared-provider-consumer-namespaces.yaml`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/examples/shared-provider-consumer-namespaces.yaml).

Points that catch people out:

- **Any selector with no requirements selects every namespace.** `{}`,
  `matchLabels: {}` and `matchExpressions: []` all mean "every namespace". Only
  an unset field means "own namespace only".
- **Negative selectors match namespaces created later.** `NotIn` and
  `DoesNotExist` select every new namespace that lacks the excluded label.
  Prefer positive selectors.
- **Sharing a `Provider` shares everything its credentials can reach.** A
  tenant allowed to use it can write its own `VMImage` (no grant needed in its
  own namespace) naming any template or image file the `Provider`'s account can
  read. Share a `Provider` only with namespaces trusted with that, and scope the
  hypervisor account accordingly.
- **Who can grant.** Whoever can edit the object sets its selector, and whoever
  can label a `Namespace` decides whether that namespace matches. On a plain
  cluster the second is a cluster administrator. Self-service platforms
  (Capsule, HNC, Rancher projects) may let a namespace owner edit their own
  namespace's labels; there, use `kubernetes.io/metadata.name` selectors or
  restrict the labels with a Kyverno or Gatekeeper rule.
- **Selectors match names and labels, not identities.** A namespace deleted and
  recreated under the same name matches again.

### When a reference is refused

The object reports `Ready=False`, reason `ConsumerNotAllowed`, with a message
naming the referenced kind, namespace and name and the field that would grant
access, plus one `Warning` event. No provider call is made through the refused
reference. For a `VirtualMachine` this is a hold that reports
`status.phase: Failed`, including for a VM that is running (see the
[VM status reference](vm-status.md)); a `VMClone` or `VMMigration` already in
flight waits instead of failing. The message is the same whether the
referenced object does not exist or exists without a grant, so a refusal tells
a tenant nothing about another namespace.

What is checked for a `VirtualMachine` that already exists:

| Operation on a bound VM | `Provider` grant | `VMClass` grant | `VMImage` grant |
|---|---|---|---|
| describe, power on/off | needed | no | no |
| reconfigure to the class | needed | needed | no |
| re-create a VM missing on its hypervisor | needed | needed | needed |

So revoking a `Provider` share stops everything for the VMs through it (they
keep their `status.id` and their hypervisor VM; nothing is deleted), while
revoking an image share never stops VMs created from the image. A VM that is not
bound yet needs all three grants before anything is created. `VMSnapshot`,
`VMClone` and `VMMigration` check the `Provider` (and, for a clone or migration,
the target's `Provider` and `VMClass`) the same way.

To lift a refusal, widen the selector or label the namespace so an existing
selector matches. The manager watches both and re-runs the affected objects
within seconds; a refused object is also re-checked every 5 minutes.

**Deleting a VM whose `Provider` is refused keeps the finalizer**: the manager
never deletes a hypervisor VM through a `Provider` the namespace may not use.
Restore access, or set `virtrigaud.io/orphan-on-delete: "true"` (detach, no
provider call), or `virtrigaud.io/force-delete: "true"` (drop the finalizer).

There is no admission webhook for this check. The controllers enforce it on
every reconcile, so a `VirtualMachine` that references something it may not use
is accepted by the API server and then reported as above.

## Cross-namespace clone and migration targets

A `VMClone` or `VMMigration` creates a `VirtualMachine`, by default in its own
namespace. `spec.target.namespace` can name a different one. That needs the
**target** namespace to allow it, with an annotation listing the source
namespaces:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team-b
  annotations:
    # VMClones / VMMigrations in team-a and team-c may create VMs here.
    infra.virtrigaud.io/allowed-source-namespaces: "team-a, team-c"
```

```bash
kubectl annotate namespace team-b \
  infra.virtrigaud.io/allowed-source-namespaces=team-a
```

The value is a comma-separated list of exact namespace names. `*`, prefixes and
a different case do not match. Whoever can update the target `Namespace` can
grant, so keep `update`/`patch` on `namespaces` limited, and restrict the
annotation with a tenant policy on self-service platforms. Grants match names:
if a listed namespace is deleted and recreated, the new one inherits the grant.

Without the grant the object reports `Ready=False`, reason
`TargetNamespaceNotAllowed`, and the manager does nothing in the target
namespace. The `Provider` and `VMClass` pinned onto the target VM must also
select the target namespace (`consumerNamespaceSelector`, above), otherwise the
clone or migration waits with `ConsumerNotAllowed`. The grant is checked again
before every step that touches the target namespace, so revoking it stops the
next step without changing what already exists.

More rules that apply to cross-namespace targets:

- A libvirt **linked** clone into another namespace is refused
  (`LinkedCloneCrossNamespace`); use a full clone.
- A migration into another namespace through a **Proxmox** target `Provider` is
  refused at `Validating` (`ProxmoxCrossNamespaceTarget`), and through a
  **clustered** target `Provider` also (`ClusteredTargetUnsupported`).
- A migration acts only on the target `VirtualMachine` it created itself. A
  `VirtualMachine` created under the target name by someone else fails the
  migration with `TargetVMNotOwned`; the other VM is never read, annotated or
  deleted. Delete or rename it, or choose another `spec.target.name`.
- `VMMigration.spec.source.providerRef` must name the `Provider` the source VM
  runs on. A mismatch fails the migration.
- A clone carries the source's cloud-init user-data (on libvirt unless the
  `VMClone` gives its own), provisioning secrets included. Grant a target
  namespace only to people who may see that user-data.

## Admission policy (reserved keys)

The manager writes some annotations and labels on the `VirtualMachine`s it
creates or adopts: where a migrated VM came from, which `VMClone` produced it,
that it was adopted. Some controllers decide which `VirtualMachine` a
hypervisor VM is bound to from these markers. Without a guard, anyone who can
create `VirtualMachine`s in the `Provider`'s or the clone target's namespace
could forge them.

The chart installs a `ValidatingAdmissionPolicy` that lets **only the manager's
ServiceAccount** add or change them. It runs inside the API server (not a
webhook), so it does not need `webhooks.enabled` and keeps working while the
manager is down.

It rejects a `create` of a `VirtualMachine` carrying a reserved key, and an
`update` that adds a reserved key or gives one a new value, from any identity
other than the manager. It does not reject updates that leave the reserved keys
as they are (`kubectl edit` of `spec.powerState`, an `apply` of an exported
manifest), removing a reserved key, deleting, or status updates. A rejected
request fails with `Forbidden` and names the keys:

```text
... ValidatingAdmissionPolicy 'virtrigaud-reserved-keys' with binding
'virtrigaud-reserved-keys' denied request: annotation(s) virtrigaud.io/migration
are reserved for the VirtRigaud manager and cannot be added or changed
```

Reserved annotations: `virtrigaud.io/migration`,
`virtrigaud.io/migration-claim`, `virtrigaud.io/migrated-from`,
`virtrigaud.io/imported-disk-id`, `virtrigaud.io/disk-checksum`,
`virtrigaud.io/migration-completed`, `virtrigaud.io/migration-completed-at`,
`virtrigaud.io/clone`, `virtrigaud.io/clone-uid`, `virtrigaud.io/cloned-from`,
`virtrigaud.io/adopted-host`, `virtrigaud.io/adopted-id`. Reserved label:
`virtrigaud.io/adopted`.

Keys users set themselves are **not** reserved: `virtrigaud.io/orphan-on-delete`,
`virtrigaud.io/force-delete`, `virtrigaud.io/create-outcome` and
`infra.virtrigaud.io/placement-uid`. A `VMClone` and a `VMMigration` also drop
`virtrigaud.io` keys from their `spec.target.annotations` (and the reserved
label from `spec.target.labels`) instead of copying them to the target VM.

### Chart values

```yaml
admissionPolicy:
  reservedKeys:
    enabled: true          # default
    exemptUsernames: []    # e.g. ["system:serviceaccount:velero:velero"]
    exemptGroups: []       # e.g. ["platform-break-glass"]
```

- **Kubernetes 1.30 or later** is required. On an older cluster the chart
  renders nothing, and the adoption and clone markers can be forged by anyone
  who can create `VirtualMachine`s in those namespaces; restrict `create` and
  `update` on `virtualmachines` there, or reserve the keys with Kyverno or
  Gatekeeper. With `helm template`, pass `--kube-version` when you render for an
  older cluster.
- **Installing it needs cluster-scoped rights** (`validatingadmissionpolicies`
  and `validatingadmissionpolicybindings`) for the identity that runs
  `helm install` or `helm upgrade`.
- **Backup and restore tools** (Velero, for example) recreate `VirtualMachine`s
  with their annotations and are rejected. Add the tool's identity to
  `exemptUsernames` before you restore.
- **More than one VirtRigaud installation in a cluster:** each installation's
  policy exempts only its own manager. Add the other managers'
  ServiceAccounts (`system:serviceaccount:<namespace>:<name>`) to
  `exemptUsernames`.
- **Cluster administrators are not exempt** by default, `system:masters`
  included. List a break-glass group in `exemptGroups` if you need one.
- Do not set `reservedKeys.enabled: false` unless another admission control
  reserves the same keys.

The kustomize deployment installs the same policy from `config/admission-policy/`.

Check it:

```bash
kubectl get validatingadmissionpolicy,validatingadmissionpolicybinding | grep reserved-keys

# As a tenant: must be refused.
kubectl -n team-a annotate virtualmachine web virtrigaud.io/migration=team-a/forged
```

The policy and binding are named `<release fullname>-reserved-keys`, for
example `virtrigaud-reserved-keys`.

## Provider in-use finalizer

Every `Provider` carries the finalizer `provider.infra.virtrigaud.io/in-use`.
The manager adds it to existing `Provider`s on the first reconcile after the
upgrade. Deleting a `Provider` that is still needed does not remove it; the
`Provider` waits with its runtime (Deployment, Service, ServiceAccount) still
up, so the objects that use it can still be deleted through it. Before this
change, deleting a `Provider` released every `VirtualMachine` that used it on
its next delete and left the hypervisor VMs running unmanaged.

What holds a `Provider`:

| Object | Holds it while |
|---|---|
| `VirtualMachine` | It is bound through the `Provider` (or has something on the hypervisor: a `status.id`, a pending host, or the `CreateRequested` marker) and still carries the VM finalizer. A VM that never got that far holds nothing. VMs in another namespace count only if the `Provider` still allows that namespace. |
| `VMSnapshot` | Its delete still has to call `SnapshotDelete` through the `Provider`. |
| `VMClone` | In flight (not `Ready` or `Failed`) from a source VM that holds it. |
| `VMMigration` | In flight or being deleted, from a source VM that holds it or into this `Provider`. |

What you see:

```bash
kubectl get provider <name> -n <ns> -o jsonpath='{.status.conditions[?(@.type=="DeleteBlocked")]}'
```

`DeleteBlocked=True`, reason `ProviderInUse`, with a message giving the number
of objects of each kind and the namespaces they are in (at most 10 namespaces,
never an object name), and one `Warning` event `ProviderDeleteBlocked`. The
`Provider` is released as soon as the last holder goes.

To release it deliberately:

- **Delete the VMs first** (the normal path), or
- annotate the `Provider` `virtrigaud.io/force-delete: "true"`. The runtime is
  removed and the finalizer released at once, with a `Warning` event
  `ProviderForceDeleted` recording what still used it. The objects are not
  touched; VMs in the `Provider`'s namespace are then released without a
  provider call on their next delete, and the hypervisor VMs stay running,
  unmanaged. VMs in other namespaces stay held until each is annotated
  `orphan-on-delete` or `force-delete`.

!!! warning "Deleting a namespace that contains a Provider"
    Kubernetes deletes the provider's pods together with everything else in the
    namespace, and a finalizer cannot stop that. VMs whose delete arrives after
    the pod is gone are held (`ProviderUnavailable`), not orphaned, and the
    `Provider` shows `DeleteBlocked=True` with reason
    `ProviderInUseRuntimeNotKept`; the namespace stays `Terminating` until you
    act. **Delete the VMs, and wait for them to go, before deleting their
    namespace.** A `Provider` deleted with `--cascade=foreground` has the same
    limit; use the default cascade.

Automation that deletes a `Provider` and waits for it to disappear must now
delete its VMs first, or wait longer. Uninstall the manager only after the
`Provider`s and VMs are gone; without a manager nothing releases the finalizer.
After a rollback to a manager without this change, remove it by hand once no VM
uses the `Provider`:

```bash
kubectl patch provider <name> -n <namespace> --type=json \
  -p '[{"op":"remove","path":"/metadata/finalizers"}]'
```

Also, nothing is created through a `Provider` that is being deleted: right
before every `Create`, `Clone` and `ImportDisk` the manager re-reads the
`Provider` from the API server and holds the object with
`Ready=False/ProviderDeleting` if it is going away.

## Identity-safe image preparation

A prepared image is an artifact on the hypervisor: a vSphere template, a libvirt
pool file. It used to be named after the `VMImage` alone and accepted as "already
prepared" if anything of that name existed, so two same-named `VMImage`s in
different namespaces collided, and a tenant allowed to use a shared `Provider`
could pre-create the artifact another tenant's VMs are cloned from
([ADR-0009](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/adr/0009-prepared-image-artifact-identity.md)).

Now every prepare carries the `VMImage`'s UID, namespace, name and a digest of
its `spec.source`, and:

- the provider names the artifact from that identity, for example
  `team-a.ubuntu-22.04_3c9e1f0a7b2d4e61` (vSphere template, or
  `<pool dir>/team-a.ubuntu-22.04_3c9e1f0a7b2d4e61.qcow2` on libvirt),
  stamps it with the identity, and **reuses an existing artifact only if its
  stamp carries the same UID and digest**;
- the manager records a prepare only when the provider's answer echoes the
  stamp it asked for;
- prepare state is kept **per `Provider`**: `VMImage.status.providerStatus` is
  keyed by `<namespace>/<name>`, so a `Provider` named `vsphere` in `team-b`
  never satisfies a VM on `team-a/vsphere`.

Where the stamp lives:

| Provider | Stamp |
|---|---|
| vSphere | ExtraConfig `virtrigaud.image.stampversion`, `virtrigaud.image.uid`, `virtrigaud.image.sourcedigest`, plus `namespace`, `name`, `preparedby`, `preparedat`. Inspect with `govc vm.info -e <template> \| grep virtrigaud.image`. VMs made from the template never carry it. |
| libvirt | A JSON stamp file `.<namespace>.<name>_<hash>.virtrigaud-image.json` next to the artifact in the pool directory, recording UID, digest, and the artifact's inode and size. |
| Proxmox | Nothing is prepared: URL import (`source.http`) is refused. Use `source.proxmox.templateID` with an existing template. |

!!! note "Source changes and re-created images"
    A changed `spec.source` or a re-created `VMImage` (new UID) gets a new
    artifact; the old one is left in place. The first VM create after the
    upgrade prepares each image once more under its new name; artifacts from
    earlier releases (bare names) are never reused, renamed or deleted.

### When the provider refuses

The `VMImage` (and the VM, as `WaitingForDependencies`) reports one of these
reasons. The create is held, not failed.

| Reason | Meaning | What to do |
|---|---|---|
| `ProviderLacksArtifactIdentity` | The `Provider` imports images but does not report `supportsImageArtifactIdentity` (an older provider image). Nothing is sent. Retried every 30 seconds. | Upgrade the provider image. |
| `ArtifactNotConfirmed` | The provider's answer did not echo the requested stamp. Retried with a backoff from 30 seconds to 5 minutes. | Upgrade the provider image; check the provider log. |
| `ArtifactConflict` | An artifact exists at the derived name with a stamp that does not match (or none). VirtRigaud never adopts, overwrites or deletes it. Retried every 5 minutes. | Investigate and remove the artifact by hand. |
| `ArtifactPrepareStalled` | Another request has been importing the same artifact for longer than `max(2 × spec.prepare.timeout, 2h)`. | Check the other `Provider` sharing the image location. |
| `InvalidSource` | The source is rejected (bad URL or checksum mismatch, an OVF the provider refuses, Proxmox URL import). Not retried until the source changes. | Fix `spec.source`. |
| `ImportFailed` | An asynchronous import failed. Retried after 1 minute, doubling to 30 minutes. | Fix the source or wait. |
| `SourceDigestMissing`, `ProviderUIDMissing` | With `onMissing: Fail` or `Wait`, a recorded entry cannot be matched to the current source or `Provider`, and those settings forbid the prepare that would re-validate it. | Switch the image to `onMissing: Import`. |

`virtrigaud_image_prepare_artifact_total{provider_type,outcome}` counts
prepares by `created`, `reused`, `in_progress` and `conflict`; alert on a rising
`conflict`.

!!! warning "Who may write the image location"
    The stamp proves provenance only against principals who cannot write the
    image location. Providers that resolve to the same location (the same
    vSphere import folder, libvirt pool directory) share one artifact per image
    and source. Give each tenant's `Provider` its own import location
    (`spec.defaults.folder` on vSphere) and scope its hypervisor account to
    it, and let nobody else write there.

Reference-style sources (`templateName`, a libvirt `path`, a Proxmox template ID)
name an existing object and are used as written; they reach whatever the
`Provider`'s account can read. libvirt `path` sources are confined: the file
must sit directly in an allowed image directory
(`VIRTRIGAUD_LIBVIRT_IMAGE_DIRS`, default `/var/lib/libvirt/images`), must not
be in use by any domain, and is always **copied** into the VM's own disk, never
attached in place. vSphere `templateName` must name a real template. Details:
[Image preparation](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/image-preparation.md).

## Private cloud-init seeds (libvirt)

A libvirt VM's cloud-init seed ISO carries its user-data, which may hold
passwords, keys and tokens. Earlier releases built it under the world-listable
`/tmp` at the SSH user's umask. Since v0.4.0 seeds are built in a dedicated
directory that only the provider's SSH user can list:

- **Where:** `VIRTRIGAUD_LIBVIRT_SEED_DIR` on the provider pod (set it in the
  `Provider`'s `spec.runtime.env`), default `/var/lib/libvirt/virtrigaud-seeds`.
  One absolute directory, applied to every host of a clustered `Provider`. It
  must not be in `/tmp`, `/var/tmp`, `/run`, `/dev`, `/proc` or `/sys`.
- **Permissions:** the ISO is `0600` (libvirt gives it to the qemu user when the
  domain starts), `user-data` and `meta-data` are removed once the ISO is built,
  and the SSH user keeps a private `cloud-init.private.iso` that clones read.
  The directory must be owned by the SSH user with no group or other read/write
  bit (mode `0711` so the qemu user can traverse it; `0700` if qemu runs as the
  SSH user), and every parent must not be writable by others unless sticky.
- **Fail closed:** if the directory is missing and cannot be created, is
  owned by someone else, or is readable or writable by group or others, **every
  create on that host fails**, and so does every clone of a VM that has a seed,
  with a retryable `refusing to stage cloud-init data`, until you fix it.
- **Every host needs it**: each single-host libvirt host, each host of a
  clustered `Provider`, and the target host of a migration into libvirt.

Prepare each host once, as root (replace `virtrigaud` with the SSH user):

```bash
install -d -m 0711 -o virtrigaud -g virtrigaud /var/lib/libvirt/virtrigaud-seeds
```

Host preparation as a whole is in [Libvirt host preparation](../operations/libvirt-host-prepare.md).

Operational notes: keep the directory on a local filesystem (not NFS); on a host
shared by several `Provider`s with **different** SSH users, give each its own
directory through the environment variable; exclude it from host backups or
encrypt and restrict those backups, because every seed holds its VM's user-data
in plaintext for as long as the VM exists; and prefer short-lived bootstrap
credentials in user-data. SELinux hosts are not tested. If you change the
variable later, existing VMs keep their seed in the old directory and `Delete`
no longer removes it there.

Seeds left in `/tmp/virtrigaud-cloudinit/` by earlier releases may still hold
user-data. Remove the ones no domain references (compare with
`virsh domblklist --details <domain>`).

## Cloud-init seeds on Proxmox

Since v0.4.1 a Proxmox VM that carries `spec.userData` gets the whole user-data
through a NoCloud seed CD-ROM that the provider builds on the PVE node over SSH.
That changes what the Provider's credentials are worth:

- **The Provider holds a root SSH credential to the PVE node.** The seed's
  `qm importdisk` and `qm set` run as `root@pam` over SSH, outside the API token's
  permissions, and PVE attributes the changes to root. Restrict who can read the
  Provider's Secret (`ssh_user` must be `root`, `ssh_privatekey` or
  `ssh_password`, `known_hosts`), and use a key that only this provider uses.
  Host-key verification is on by default and has no trust on first use.
- **The user-data is stored in plaintext in the seed volume** on the VM's storage
  for the VM's whole life, as in PVE's own cloud-init drive and libvirt's seed.
  Keep long-lived secrets out of it.
- **The seed never reaches a command line or a log.** The three files travel as a
  tar archive on the standard input of one SSH session, are built in a root-only
  directory on a tmpfs on the node under a per-VM lock, and are removed after the
  build. The provider logs the VM, node, storage, slot and the size of the
  user-data, never its content.

See [Proxmox provider: cloud-init](../providers/proxmox.md#cloud-init-the-nocloud-seed).

## Customization secrets of a `VMClone`

A `VMClone`'s `spec.customization` has fields that can hold a credential and that
no provider acts on (`sysprep.productKey`, `sysprep.adminPassword.value`,
`sysprep.joinDomain.password.value`, `sysprep.customCommands`,
`certificates[].data`, `guestCommands[].command` and `.arguments`,
`userData.ignition.inline`). Since v0.4.1 the manager does not send them to the
provider; the `Clone` request carries an allow-list of what providers apply or
report as not applied. The v1beta1 API still stores them in plaintext in the
`VMClone`, so **do not put a real credential in them, and rotate any value you set
on v0.4.0 or earlier**. See [VM Cloning](advanced/vm-cloning.md#customization-secrets-are-not-sent).

## Logs and staging locations

Since v0.4.1 a migration's staging location (an NFS server, export, path and
`uid`/`gid`; an S3 bucket, key and endpoint) and every image URL are redacted from
the provider and manager logs, from provider errors, and from the status, conditions
and Warning event of a failed `VMMigration`. The cause stays readable
(`MNT3ERR_ACCES`, `SignatureDoesNotMatch`). Logs written by earlier releases keep
what they contain: treat them as sensitive. A libvirt create from an image URL no
longer puts the URL on the host's command line.

## Migration storage

Provider pods hold hypervisor credentials, so what is mounted into them is a
trust decision. Since v0.4.0, a `VMMigration` with `spec.storage.type: pvc` gets
its storage mounted like this:

- A PVC is mounted into the source and target `Provider` pods only while a
  `VMMigration` in that namespace records it in `status.storagePVCName` and is
  still in flight. The target mounts it **read-only**.
- The PVC must carry the label `virtrigaud.io/component=migration-storage`, be
  `Bound`, and be either the PVC the migration created (identified by the UID
  it recorded in `status.storagePVCUID`) or the PVC named in
  `spec.storage.pvc.name`. Before, any PVC in the namespace with that label was
  mounted read-write into every provider pod.
- For a PVC you name yourself, label it first:

  ```bash
  kubectl label pvc <name> virtrigaud.io/component=migration-storage
  ```

  A migration fails at `Validating` if the named PVC lacks the label or belongs
  to another `VMMigration`.
- Deleting a `VMMigration` deletes only the PVC it created. A PVC you named is
  unmounted and left for you (`MigrationPVCRetained` event).
- Provider pods roll once when a PVC is added or dropped, which interrupts an
  export or import running at that moment. Upgrade between migrations.

Other migration rules that matter in a shared environment:

- NFS migrations refuse `spec.storage.nfs.uid` and `gid` of `0` (reason
  `NFSRootIdentityNotAllowed`), because the client chooses the identity it
  presents and uid 0 is root on an export without `root_squash`. Use a
  dedicated non-zero uid and gid that owns the export.
- A disk landed by a migration is attached **in place** only to the
  `VirtualMachine` the migration created (its `spec.importedDisk.migrationRef`
  names a `VMMigration` in the VM's own namespace). Any other imported-disk
  path is treated as a base image: confined and copied on libvirt, refused on
  vSphere and Proxmox (`ValidationError`).
- A failed or deleted `VMMigration` deletes the disk its import landed on the
  target, unless the disk is in use (`spec.options.cleanupPolicy` decides when:
  `OnSuccess` (default), `Always`, `Never`).

See [Migration user guide](../migration/user-guide.md) for the migration
workflow itself.

## Disk-size limit

By default the only bound on a VM disk is the CRD's 64Ti per disk. A tenant who
owns a namespace can ask for that much and fill a shared datastore or pool. The
administrator's ceiling is opt-in and **tenants cannot raise it**:

```yaml
# values.yaml
manager:
  maxDiskSize: "500Gi"   # whole number of bytes, 1Gi to 64Pi; empty = no ceiling
```

Use binary units (`Gi`, `Ti`): `500G` is only about `465.7Gi`. With it set:

- A VM whose `VMClass` `spec.diskDefaults.size` (on libvirt, 20Gi when the class
  sets none) or any `spec.disks[].sizeGiB` is above the ceiling is **not
  created**: it waits with `Ready=False`, reason `DiskSizeExceedsLimit`, and a
  `Warning` event, and is created once its sizes fit.
- A `Reconfigure` never grows a disk beyond it. The VM's other changes apply,
  the over-limit disk is left as it is, and the VM reports
  `DiskSizeWithinLimit=False` (reason `DiskSizeExceedsLimit`).
- A `VMClone` or `VMMigration` is checked against the **real** sizes of the
  source's disks as its provider reports them, and the target provider enforces
  the limit again when it lands a migrated disk. A size that cannot be read
  refuses the operation (`DiskSizeLimitUnverifiable`).
- VMs that already have larger disks keep running and are never shrunk.

A `Provider`'s owner can lower the ceiling for that `Provider` (never raise it)
with an annotation:

```yaml
metadata:
  annotations:
    infra.virtrigaud.io/max-disk-size: "200Gi"
```

An invalid annotation value is refused by the `Provider` webhook; if one is
stored anyway, nothing is created or grown through that `Provider`
(`DiskSizeLimitUnverifiable`) until it is fixed. With `webhooks.enabled=true`
and `manager.maxDiskSize` set, the chart also renders validating webhooks
(`vvirtualmachine-disksize.kb.io`, `vvmclass-disksize.kb.io`) that refuse a
larger size at `kubectl apply` time; they check the manager's ceiling only. The
controllers enforce the limit whether or not webhooks are on.

What the limit does not cover: it bounds the sizes VirtRigaud asks for, per
disk. A primary disk that comes from an image already larger than the limit is
not checked, and totals per VM or namespace are not limited; use hypervisor
storage quotas for those. The clone and migration checks need provider images
of v0.4.1: an older image does not report disk sizes, so while a limit applies
clones through it are refused.

## Upgrade impact

Read [Upgrading](../operations/upgrade.md) for the full procedure and order. These
are the changes from this page that can break an existing setup.

| Change | Who is affected | What happens after the upgrade | Action |
|---|---|---|---|
| Cross-namespace `Provider`/`VMClass`/`VMImage` references need a grant | Any VM, clone or migration referencing an object in another namespace | The VM fails closed with `Ready=False/ConsumerNotAllowed`, including running VMs: no provider calls, no deletes, until granted | After applying the new CRDs and **before** rolling the manager, set `spec.consumerNamespaceSelector` on every shared object |
| Cross-namespace clone and migration targets need a grant | `VMClone`/`VMMigration` with `spec.target.namespace` set to another namespace, including ones in flight | Waits with `TargetNamespaceNotAllowed` | Annotate the target namespace with `infra.virtrigaud.io/allowed-source-namespaces` |
| `spec.providerRef` is immutable once the VM is bound | Tooling that edits it; the old "re-point then delete" un-adopt trick | The edit is rejected (`422`) | Use `virtrigaud.io/orphan-on-delete` |
| `Provider.spec.type` is immutable | Tooling that edits it | The edit is rejected | Create a new `Provider` |
| vSphere create and clone need `VirtualMachine.Config.AdvancedConfig` | All vSphere users | Creates fail with a vCenter permission error | Grant the privilege |
| `Create` fails closed on a same-named VM it does not own | A create retried after the manager lost `status.id`, for a VM created before owner stamps; any collision with an unstamped VM | `ProviderConflict`; VMs already bound (`status.id` set) are unaffected | Adopt the VM, or remove it |
| New libvirt domains are named `<namespace>.<name>` | Scripts and monitoring keyed on the domain name | Existing VMs keep their names | Read `status.id` |
| libvirt default cloud-init no longer provisions credentials | libvirt VMs created without `spec.userData` | No default `ubuntu` user, key or sudo | Supply your own `spec.userData` |
| libvirt base images are confined and always copied | Images outside `/var/lib/libvirt/images`, or attached in place by an earlier release | Such images are refused as a base | Set `VIRTRIGAUD_LIBVIRT_IMAGE_DIRS`; create a `VMImage` under a new name for a fresh copy |
| Seed directory must exist on every libvirt host | Every libvirt `Provider` | Creates and clones fail with `refusing to stage cloud-init data` until the directory is prepared | Run the `install -d` command above on each host |
| Image prepares carry the `VMImage` identity | Every import-style image (`ovaURL`, libvirt `url`) | One re-import per image and location; a provider image without the capability is held (`ProviderLacksArtifactIdentity`); Proxmox URL import is refused | Roll provider images with the manager; use a Proxmox `templateID` |
| Reserved keys policy | Backup tools that restore VMs with annotations; a second VirtRigaud installation | Their writes are rejected with `Forbidden` (Kubernetes 1.30+) | Add them to `admissionPolicy.reservedKeys.exemptUsernames` |
| Deleting a `Provider` that is in use waits | Automation that deletes a `Provider` and expects it to disappear | `DeleteBlocked=True/ProviderInUse` | Delete the VMs first, or force-delete the `Provider` |
| Provider pods mount only referenced migration PVCs | `pvc` migrations; PVCs labelled `virtrigaud.io/component=migration-storage` | Provider pods roll once; unreferenced labelled PVCs are no longer mounted | Label a PVC before naming it in `spec.storage.pvc.name`; delete your named PVC yourself |
| NFS migrations refuse uid/gid 0 | `VMMigration` with `nfs.uid: 0` or `nfs.gid: 0` | Fails at `Validating` | Use a non-zero uid/gid |
| Linked clones fail closed | `VMClone` with `options.type: LinkedClone` | libvirt linked clones are refused; a libvirt linked clone into another namespace is refused | Use a full clone |
| The disk-size limit | Nobody, unless `manager.maxDiskSize` is set | No change when unset | Set it if you need it |

Changes of v0.4.1 that touch the security model (from v0.4.0; the full list is in the [upgrade notes](../operations/upgrade.md#upgrading-from-v040-to-v041)):

| Change | Who is affected | Action |
|---|---|---|
| A `VMClone`'s unused customization secrets are no longer sent to the provider | Anyone who set `sysprep.productKey`, `sysprep.adminPassword.value`, `sysprep.joinDomain.password.value`, `sysprep.customCommands`, `certificates[].data`, `guestCommands` or `userData.ignition.inline` on v0.4.0 or earlier | Rotate those values; they were sent, and they are still stored in plaintext in the `VMClone` |
| Proxmox VMs with user-data need a root SSH credential in the Provider's Secret | Proxmox Providers whose VMs carry `spec.userData` | Add `ssh_user`, `ssh_privatekey` or `ssh_password` and `known_hosts` before rolling the provider; restrict who can read the Secret |
| Staging locations and image URLs are redacted from logs | Log queries and alerts that matched them | Update them; treat logs from earlier releases as sensitive |

Roll the providers promptly after the manager. Most of the checks above need a
v0.4.0 (or later) provider image as well as the manager, and a manager ahead of its
providers holds some operations (for example, image prepares are held on a
provider that does not report artifact identity, and a `Create` whose outcome
is unknown is not sent again to a provider that does not report owner re-bind).

## Further reading

The reference documents in the main repository carry the full detail, including
every edge case:
[VM ownership](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/vm-ownership.md),
[libvirt domain ownership](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/libvirt-domain-ownership.md),
[cross-namespace references](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/cross-namespace-references.md),
[cross-namespace targets](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/cross-namespace-targets.md),
[admission policy](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/admission-policy.md),
[image preparation](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/image-preparation.md) and
[upgrading from v0.3.11](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/upgrading.md).
For what each condition reason means on a `VirtualMachine`, see
[VM status reference](vm-status.md).
