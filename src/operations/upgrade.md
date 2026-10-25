<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VirtRigaud Upgrade Guide

This guide covers upgrading VirtRigaud installations: the **v0.3.11 to v0.4.0**
path first, then the notes for older releases, rollback, GitOps and
troubleshooting.

!!! warning "v0.4.0 is a security-hardening release with breaking changes"
    A full security review of the codebase led to fixes that **break existing
    setups or change defaults**: cross-namespace references fail closed until
    granted, `VirtualMachine.spec.providerRef` becomes immutable once bound, vSphere
    needs a new vCenter privilege, libvirt hosts need a seed directory before the
    provider rolls, and more. Read [Breaking changes](#breaking-changes) and follow
    [Required upgrade order](#required-upgrade-order). **Do the pre-flight
    checks first**: several breaking changes are cheap to prepare for before the
    upgrade and expensive to discover after it.

    The exhaustive per-change reference (every bullet with its cause and its
    queries) is the repository's
    [`docs/upgrading.md`](https://github.com/projectbeskar/virtrigaud/blob/main/docs/upgrading.md);
    this page is the website's operating summary of it, checked against the v0.4.0
    code.

## Upgrading from v0.3.11 to v0.4.0

v0.4.0 is built from the same code as the release candidate v0.4.0-rc9. The chart
version is `0.4.0` and every image tag is `v0.4.0`
(`ghcr.io/projectbeskar/virtrigaud/manager:v0.4.0`,
`.../provider-vsphere:v0.4.0`, `.../provider-libvirt:v0.4.0`,
`.../provider-proxmox:v0.4.0`). Releases older than v0.3.11 should first follow
the [older-version notes](#older-versions) below.

What is new in this window, in one paragraph: clustered libvirt providers
(experimental; `Provider.spec.topology: cluster` and the `Host`, `HostPool` and
`VMPlacementPolicy` CRDs), VM ownership stamps and fail-closed ownership checks on
every provider, consumer grants for shared `Provider`/`VMClass`/`VMImage`, an
admission policy for manager-owned keys, identity-safe image preparation
(ADR-0009), a `Provider` in-use finalizer (ADR-0010), migration staging cleanup
(ADR-0011), snapshot revert through `spec.snapshot.revertToRef`, Proxmox network
and cloud-init-drive handling, and private libvirt cloud-init seeds. If you do not
use clustered providers, the new CRDs are installed but unused.

### Pre-flight checks

Run these **before** changing anything. They are read-only.

**1. Back up the custom resources.**

```bash
kubectl get providers,vmclasses,vmimages,vmnetworkattachments,virtualmachines,vmsnapshots,vmclones,vmmigrations,vmsets \
  -A -o yaml > virtrigaud-backup-v0.3.11.yaml
```

**2. Find cross-namespace references** (each line names an object that needs
`spec.consumerNamespaceSelector` after the CRDs are applied):

```bash
# VirtualMachines referencing another namespace's Provider, VMClass or VMImage.
kubectl get virtualmachines -A -o json | jq -r '
  .items[] | . as $vm
  | [["Provider", .spec.providerRef], ["VMClass", .spec.classRef], ["VMImage", .spec.imageRef]][]
  | select(.[1] != null and (.[1].namespace // "") != "" and .[1].namespace != $vm.metadata.namespace)
  | "\(.[0]) \(.[1].namespace)/\(.[1].name) <- \($vm.metadata.namespace)"' | sort -u

# VMMigrations whose target Provider is in another namespace.
kubectl get vmmigrations -A -o json | jq -r '
  .items[] | select((.spec.target.providerRef.namespace // "") != ""
    and .spec.target.providerRef.namespace != .metadata.namespace)
  | "Provider \(.spec.target.providerRef.namespace)/\(.spec.target.providerRef.name) <- \(.metadata.namespace)"' | sort -u
```

**3. Find cross-namespace clone and migration targets** (each target namespace
needs the grant annotation):

```bash
kubectl get vmclones,vmmigrations -A -o json | jq -r '
  .items[] | select(.spec.target.namespace != null
    and .spec.target.namespace != "" and .spec.target.namespace != .metadata.namespace)
  | "\(.kind) \(.metadata.namespace)/\(.metadata.name) -> \(.spec.target.namespace)"'
```

**4. Find VMs that will be reverted or resized on the first reconcile.**

```bash
# spec.snapshot.revertToRef was accepted and ignored before; it now reverts the VM.
# Use the full resource name: "vm" can resolve to another project's VirtualMachine.
kubectl get virtualmachines.infra.virtrigaud.io -A \
  -o jsonpath='{range .items[?(@.spec.snapshot.revertToRef)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'

# spec.resources overrides were never sent to the provider; they are now.
kubectl get virtualmachines.infra.virtrigaud.io -A -o json | jq -r '
  .items[] | select(.spec.resources != null)
  | "\(.metadata.namespace)/\(.metadata.name): \(.spec.resources)"'
```

Also check `VMSet` templates (`spec.template.spec.snapshot.revertToRef`): the VMs a
`VMSet` creates carry the field.

**5. Let in-flight migrations finish.** List them with
`kubectl get vmmigrations -A` and do not start new ones. A migration in `Creating`
or `Validating-Target` during the upgrade fails with `TargetVMNotOwned`; vSphere
and Proxmox migrations whose disk was landed or staged by the old provider before
their target VM was created are refused afterwards. See
[In-flight VMMigrations](#in-flight-vmmigrations).

**6. Provider-specific checks.**

- **libvirt:** run `virsh pool-dumpxml default | grep '<path>'` on every host;
  the `default` pool must be at `/var/lib/libvirt/images`. Before deleting any
  *pre-upgrade* VM run `virsh domblklist --details <domain>` on every domain of
  the host and look for a disk file shared between domains.
- **Proxmox:** list `VMImage`s that import from a URL; Proxmox no longer imports
  them (see [Proxmox](#proxmox)):

  ```bash
  kubectl get vmimages -A -o json | jq -r '.items[]
    | select(.spec.source.http != null and .spec.source.proxmox == null)
    | "\(.metadata.namespace)/\(.metadata.name)"'
  ```
- **vSphere:** list each `VirtualMachine`'s `status.id` and compare it with the
  templates in vCenter, so no `VirtualMachine` is bound to a template (see
  [vSphere](#vsphere)):

  ```bash
  kubectl get virtualmachine -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,PROVIDER:.spec.providerRef.name,ID:.status.id
  govc find -i / -type m -config.template true | sed 's/^VirtualMachine://'
  ```

### Required upgrade order

The order is **hosts and accounts, CRDs, grants, manager, providers**. The
manager and the CRDs depend on each other, and so do the manager and the
providers. Roll the providers promptly after the manager.

1. **Prepare hosts and hypervisor accounts** (safe to do ahead of time; the old
   release ignores them):
   - **Every libvirt host:** create the cloud-init seed directory, and grant the
     `VR_DISK_READ` sudo rule if the provider's SSH user cannot read libvirt's
     `0600` snapshot overlays. A v0.4.0 libvirt provider fails every create on a
     host without the seed directory.

     ```bash
     install -d -m 0711 -o <ssh user> -g <ssh user> /var/lib/libvirt/virtrigaud-seeds
     ```

     Details: [Libvirt host preparation](libvirt-host-prepare.md).
   - **vSphere:** grant the provider's vCenter account the privileges in
     [New required privileges and configuration](#new-required-privileges-and-configuration)
     (`VirtualMachine.Config.AdvancedConfig`, `System.Read`).
   - **Proxmox:** grant the PVE API token `VM.Config.Network`,
     `VM.Config.Cloudinit` and `SDN.Use` before you roll the Proxmox provider.

2. **Apply the CRDs.** Helm does not upgrade the `crds/` directory of a chart,
   and the chart's pre-upgrade hook applies them in the *same* `helm upgrade` that
   rolls the manager, leaving no pause for step 3. Apply them yourself first, with
   server-side apply exactly as the hook does (`--force-conflicts` takes over
   fields from earlier client-side applies):

   ```bash
   helm repo update
   helm pull virtrigaud/virtrigaud --version 0.4.0 --untar
   kubectl apply --server-side --force-conflicts -f virtrigaud/crds/
   ```

   Three new CRDs are created (`Host`, `HostPool`, `VMPlacementPolicy`) and the
   existing ones change. The new manager reads the installed `VirtualMachine`,
   `Provider`, `VMClass`, `VMImage` and `VMSnapshot` CRDs and **fails readiness**
   if they lack the new fields (it does not crash and does not stop managing
   existing VMs, but `helm upgrade --wait` times out and the rolling update does
   not proceed past the old pod). See the
   [Helm CRD upgrade guide](../getting-started/helm-crd-upgrades.md) for the
   hook and `crdUpgrade` values.

   !!! note "Two schema changes the readiness check does not verify"
       `VirtualMachine` `status.snapshotRevert` (without it a revert is never
       sent: `SnapshotReverted=False/Unsupported`) and the `VMMigration` fields
       used by migration into a clustered Provider. Always apply the **full** CRD
       set, not a subset. An older chart's CRDs applied over newer ones prune
       fields: only apply CRDs from the chart you are upgrading to.

3. **Grant consumers and remove stale requests**, before the new manager runs
   (the old manager ignores all of this, so it changes nothing until then):
   - Set `spec.consumerNamespaceSelector` on every `Provider`, `VMClass` and
     `VMImage` that other namespaces use. The field exists only after step 2.
     `{}` shares with every namespace; a label selector (for example
     `kubernetes.io/metadata.name`) names the namespaces:

     ```yaml
     spec:
       consumerNamespaceSelector:
         matchLabels:
           kubernetes.io/metadata.name: team-a
     ```

     Without this, the affected VMs stop being managed
     (`Ready=False`, reason `ConsumerNotAllowed`; nothing is deleted) as soon as
     the new manager starts.
   - Annotate every target namespace of a cross-namespace `VMClone` or
     `VMMigration`:

     ```bash
     kubectl annotate namespace <target> \
       infra.virtrigaud.io/allowed-source-namespaces=<source-ns>[,<source-ns2>...]
     ```

     The value is a comma-separated list of exact names; `*` is not a wildcard.
   - Remove `spec.snapshot.revertToRef` from every VM (and `VMSet` template) you do
     **not** want reverted (see [Stale `revertToRef`](#stale-reverttoref-on-existing-vms)).
   - Decide about `spec.resources` overrides (see
     [`spec.resources` overrides](#specresources-overrides-now-resize-vms)).

4. **Upgrade the manager with Helm.**

   ```bash
   helm upgrade virtrigaud virtrigaud/virtrigaud \
     --namespace virtrigaud-system \
     --version 0.4.0 \
     --reset-then-reuse-values \
     --wait --timeout 10m
   ```

   Use `--reset-then-reuse-values` (Helm 3.14 or later) when you carry custom
   values, **not** `--reuse-values`: `--reuse-values` keeps the *old* chart's
   defaults, including the manager image tag (the manager would stay on
   v0.3.11), and was the cause of the NetworkPolicy default problem described in
   [Chart values](#chart-values-that-changed). With Helm older than 3.14 use
   `--reset-values -f your-values.yaml`. Wait until the manager Deployment is
   Ready and the CRD check passes (see
   [Post-upgrade verification](#post-upgrade-verification-checklist)) before
   touching the providers. The manager's ClusterRole changes with the chart (see
   [Manager RBAC](#manager-rbac)); a kustomize install must reapply
   `config/rbac/role.yaml`.

   !!! note "The manager upgrade restarts every provider pod once"
       The new manager changes the provider pod template (a `sizeLimit` on `/tmp`,
       migration-PVC mounts), so every manager-run provider pod is replaced once
       when the manager rolls, with its *old* image. A clustered libvirt or a
       vSphere provider (`Recreate` strategy) is briefly down. Schedule the
       upgrade between migrations and outside provider-heavy windows.

5. **Upgrade the providers.** A `Provider` names its image in
   `spec.runtime.image`, which the chart does not change: set it on every
   `Provider` to the `v0.4.0` image of its type.

   ```bash
   kubectl patch provider <name> -n <namespace> --type merge -p \
     '{"spec":{"runtime":{"image":"ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.0"}}}'
   ```

   Do this promptly after the manager: until a provider reports
   `supportsImageArtifactIdentity` the new manager sends it no image prepare, so
   creates of import-style images through it wait (`ProviderLacksArtifactIdentity`;
   existing VMs and reference-style images are unaffected). Per-type order
   constraints:

   - **libvirt: never roll the provider ahead of the manager.** A v0.4.0 libvirt
     provider expects `CreateRequest.owner` and `ImportDiskRequest.target_vm` from
     the manager; with an older manager every libvirt-target `VMMigration` fails.
   - **libvirt: seed directory first** (step 1): a provider image that runs before
     it exists fails every create.
   - **Proxmox: never roll the provider ahead of the manager.** An older manager
     sends neither the verification flag nor `target_vm`, so every
     Proxmox-target migration is refused.
   - **vSphere:** grant the vCenter privileges first (step 1). Without
     `VirtualMachine.Config.AdvancedConfig` every `Create` and `Clone` starts
     failing the moment the new image is live.
   - **Clustered libvirt:** roll the provider right after the manager (new
     clustered VMs wait with `ProviderLacksListOwnerFilter`, and resizes with
     `ProviderLacksHonestReconfigure`, until it is upgraded), and **before you run
     a migration into it** (an older one is refused as a target,
     `ClusteredTargetUnsupported`).
   - Set new provider environment variables (for example
     `VIRTRIGAUD_LIBVIRT_IMAGE_DIRS`, `VIRTRIGAUD_VSPHERE_IMAGE_PROXY`) in the same
     patch, through `spec.runtime.env`, so the pod restarts once.

6. **Verify** with the [checklist](#post-upgrade-verification-checklist), then
   clean up [leftovers](#leftovers-from-earlier-releases).

### Breaking changes

Rows are grouped by area. "Action" is what you must do; the
[repository guide](https://github.com/projectbeskar/virtrigaud/blob/main/docs/upgrading.md#breaking-changes)
carries the full cause and the edge cases of each row.

#### Access control and API

| Change | Who is affected | Action |
|--------|-----------------|--------|
| **Cross-namespace `Provider`, `VMClass`, `VMImage` references need a grant** ([reference](https://github.com/projectbeskar/virtrigaud/blob/main/docs/cross-namespace-references.md)) | Anyone whose VMs, clones or migrations use a shared object from another namespace, for example a `Provider` in `virtrigaud-system`. They fail closed (`Ready=False`, `ConsumerNotAllowed`), including running VMs: no provider calls, no deletes. | Set `spec.consumerNamespaceSelector` on every shared object after the CRDs and before the manager (step 3). Unset means "own namespace only"; `{}` means all namespaces. To delete a VM whose Provider is refused, use `virtrigaud.io/orphan-on-delete: "true"` or `force-delete`. |
| **`VirtualMachine.spec.providerRef` is immutable once bound** (CRD CEL rule; bound = `status.id` or `status.placement.pendingHost` set) ([reference](https://github.com/projectbeskar/virtrigaud/blob/main/docs/vm-provider-binding.md)) | Tooling that edits `providerRef` after creation, and the old "re-point to a missing Provider, then delete" trick to stop managing a VM. Edits get `422 Invalid`. | Detach with the annotation `virtrigaud.io/orphan-on-delete: "true"` and delete the `VirtualMachine`: the hypervisor VM is left alone. See [orphan-on-delete](#detaching-a-vm-orphan-on-delete). Upgrade the CRDs with or before the manager. |
| **Cross-namespace `VMClone` / `VMMigration` targets need a grant** ([reference](https://github.com/projectbeskar/virtrigaud/blob/main/docs/cross-namespace-targets.md)) | Anyone whose `spec.target.namespace` differs from the object's namespace. The object waits with `TargetNamespaceNotAllowed`. | Annotate the target namespace `infra.virtrigaud.io/allowed-source-namespaces=<source-ns>[,...]` (step 3). The pinned `Provider` and `VMClass` must also select the target namespace. A `VMMigration` whose `spec.source.providerRef` names a Provider other than the source VM's Provider now fails; remove the field or fix it. |
| **`Provider.spec.type` is immutable** (CRD rule and validating webhook); `spec.topology` too | Tooling that edits `spec.type` in place. | Create a new `Provider` of the other type. Upgrade the CRDs with or before the manager. |
| **Only the manager may set manager-owned `virtrigaud.io` keys on a `VirtualMachine`** (ValidatingAdmissionPolicy, Kubernetes 1.30 or later) ([reference](https://github.com/projectbeskar/virtrigaud/blob/main/docs/admission-policy.md)) | Anything that creates or changes migration, clone or adoption markers (`virtrigaud.io/migration`, `migration-claim`, `migrated-from`, `imported-disk-id`, `clone`, `clone-uid`, `cloned-from`, `adopted-host`, `adopted-id`, the label `virtrigaud.io/adopted`, ...) under another identity: backup/restore tools such as Velero, a second VirtRigaud installation in the same cluster. | Add such identities to `admissionPolicy.reservedKeys.exemptUsernames` / `exemptGroups` before you rely on them. To opt out set `admissionPolicy.reservedKeys.enabled: false`. The installing identity needs create/update/delete on `validatingadmissionpolicies` and `validatingadmissionpolicybindings`. Below Kubernetes 1.30 nothing is rendered: restrict who can create `VirtualMachine`s. |
| **Deleting a `Provider` that is still in use waits** (finalizer `provider.infra.virtrigaud.io/in-use`, [ADR-0010](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0010-provider-in-use-finalizer.md)) | Every `Provider`. It stays `Terminating` (`DeleteBlocked=True/ProviderInUse`) while any VM, snapshot, in-flight clone or migration needs it; its runtime is kept until the last goes. | Delete VMs (and wait) **before** their `Provider` or its namespace. Release a held Provider at once with `virtrigaud.io/force-delete: "true"` (its VMs are then left unmanaged). Uninstall order: VMs and Providers first, then the manager. |
| **Deleting a `VirtualMachine` while its `Provider` is unreachable waits** | Every VM with a provider id. Before, the finalizer was released without any provider `Delete` and the hypervisor VM kept running unmanaged. Now the VM stays `Terminating` (`ProviderUnavailable`, backoff 15 s to 5 min) during every provider rollout or outage. | Expect `Terminating` during provider rollouts; automation that waits for deletion needs a longer timeout. Detach on purpose with `orphan-on-delete`, or drop the finalizer with `force-delete` (logged, `VMLeftOnHypervisor` event). |
| **Adoption is stricter** | Single-host adoption (`virtrigaud.io/adopt-vms`): a VM whose owner stamp names no `VirtualMachine` in this cluster, whose stamp cannot be read, or that is a template or prepared image is no longer adopted. | To re-adopt a VM left by `orphan-on-delete`, annotate the single-host Provider `virtrigaud.io/adopt-stamped-vms: "true"` while no other VirtRigaud installation manages the same vCenter or host, and remove it afterwards. |

#### vSphere

| Change | Who is affected | Action |
|--------|-----------------|--------|
| **Create and Clone fail closed on VM ownership** ([reference](https://github.com/projectbeskar/virtrigaud/blob/main/docs/vm-ownership.md)) | All vSphere users. | Grant `VirtualMachine.Config.AdvancedConfig` ([privileges](#new-required-privileges-and-configuration)). Rename any VirtualMachine, VMImage prepare target or bare template name matching `vm-<digits>`. Make every `VMImage.templateName` name a real vSphere template, not a regular VM. |
| **Per-VM operations refuse templates and prepared images** | A `VirtualMachine` bound to a vSphere template (for example adopted from one). `Delete`, `Power`, `Reconfigure`, `HardwareUpgrade` and the snapshot calls are refused (`VM_IS_IMAGE_ARTIFACT`); a refused delete stays `Terminating`. | Before upgrading, find VMs whose `status.id` is a template (pre-flight 6). Detach each with `virtrigaud.io/orphan-on-delete: "true"`, then delete it. Never delete it plainly: that destroyed the template. |
| **An imported disk is attached in place only when it is the VM's own verified migration disk; landing names carry the namespace** | Anyone who sets `spec.importedDisk` on vSphere by hand, and any vSphere migration in flight. Landing path is now `[<datastore>] <namespace>_<vm>-migrated/<namespace>_<vm>-migrated.vmdk`. | Finish or redo in-flight vSphere migrations around the upgrade (see [In-flight VMMigrations](#in-flight-vmmigrations)). Grant `System.Read` on the vCenter root folder. Remove old `[<datastore>] <vm>-migrated` folders by hand once unused. Run one replica of each vSphere provider. |
| **vSphere provider runs one replica with the `Recreate` strategy** | Every vSphere `Provider`. `spec.runtime.replicas` above 1 is ignored; the provider is briefly unavailable on every rollout. The chart's opt-in vSphere Deployment fails to render with `providers.vsphere.replicaCount` above 1. | Drop `replicas` above 1; schedule rollouts accordingly. |
| **Create leaves the VM powered off; the controller powers it on** | Everyone creating vSphere VMs: a VM shows `status.powerState: Off` for one reconcile. A migrated VM smaller than its VMClass `diskDefaults.size` (default `40Gi`) is now grown to it (grow only). | Set the VMClass `diskDefaults.size` of migration targets to the source disk size (or less) to keep a migrated disk's size; make sure the datastore has room. |
| **Image source rules** (identity-safe prepare, [ADR-0009](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0009-prepared-image-artifact-identity.md)) | `ovaURL` images: templates are named `<namespace>.<name>_<16 hex>` and stamped, kept in the Provider's import folder. Bare `.ovf` sources are refused; OVF file references must be root-level OVA members; sources at loopback or link-local addresses, more than 3 redirects and `https` to `http` redirects are refused; downloads ignore `HTTP_PROXY`/`HTTPS_PROXY` (opt in with `VIRTRIGAUD_VSPHERE_IMAGE_PROXY`); at most `VIRTRIGAUD_VSPHERE_IMAGE_MAX_DOWNLOAD_GIB` (default 256). | Republish bare `.ovf` images as `.ova`. Check `defaults.folder` resolves to exactly one VM folder per Provider. Expect one re-import per image and folder. Set the proxy variable through `spec.runtime.env` before rolling if image servers are reachable only through a proxy. |
| **`Reconfigure` no longer resizes the root disk; a change a running VM cannot take waits for a power-off** ([reference](https://github.com/projectbeskar/virtrigaud/blob/main/docs/reconfigure-results.md)) | VMs with `spec.disks` whose CPU or memory changes; running VMs changed without hot-add. The refusal is shown as `Reconfiguring=False/ResizePendingPowerOff` instead of retried `ProviderError`. | To apply the change set `spec.powerState: Off`, then `On`, or enable hot-add while the VM is off. Alerts on `Reconfiguring` should treat `ResizePendingPowerOff` as action-needed. |

#### libvirt

| Change | Who is affected | Action |
|--------|-----------------|--------|
| **Default cloud-init provisions no credentials** | A VM created **without** `spec.userData`: no `ubuntu` user, SSH key, password or sudo grant any more. | Always supply `spec.userData` with your own user and key. VMs already created keep the old hardcoded key and sudo grant *inside the guest*; remove it by hand if you want it gone. Rolling the provider does not touch running VMs. |
| **Seeds are built private in a seed directory that must exist on every host** | Every libvirt Provider, single-host and clustered. | `install -d -m 0711 -o <ssh user> -g <ssh user> /var/lib/libvirt/virtrigaud-seeds` on every host **before** rolling the libvirt provider ([details](libvirt-host-prepare.md#cloud-init-seed-directory)). Include migration target hosts and every host of a clustered Provider. |
| **Base images are confined to the allowed image directories and always copied** | Images outside `/var/lib/libvirt/images`, in a subdirectory, or in a non-default pool; images an earlier release attached in place. | Set `VIRTRIGAUD_LIBVIRT_IMAGE_DIRS` (comma- or colon-separated) in `Provider.spec.runtime.env` ([details](libvirt-host-prepare.md#image-directories)). An image attached in place by an earlier release is refused as a base: create a `VMImage` under a **new name**. Before deleting any pre-upgrade VM, check `virsh domblklist --details` for shared disks. |
| **`LinkedClone` is refused; use `FullClone`** | `VMClone` with `options.type: LinkedClone` through libvirt fails (`LinkedCloneUnsupported`). A full clone needs a powered-off source (it waits, `SourceMustBePoweredOff`). | Use `FullClone`. Existing linked clones keep working; their source VM cannot be deleted, reverted or snapshotted while they exist: keep those sources powered off. |
| **Delete only removes a VM's own files and is blocked while others use its disk** | Every libvirt VM. `Ready=False/DeleteBlocked` while another domain (a linked clone, a shared disk) uses a disk; a `VMSnapshot` whose provider delete fails keeps its finalizer. New disks are `0640 libvirt-qemu:kvm` (was `0777`). | The SSH user must be `root`, in `kvm`, or allowed passwordless `sudo -n qemu-img info` ([sudo rules](libvirt-host-prepare.md#sudo-rules-for-disk-reads-and-copies)), or the checks fail (retried). Delete a source VM's linked clones first. `virtrigaud.io/force-delete: "true"` releases a stuck `VMSnapshot`. Roll the manager with the libvirt provider. |
| **The `default` storage pool is never rewritten** | A host whose `default` pool is not at `/var/lib/libvirt/images`. v0.3.11 destroyed and recreated it there; now creates fail with `InvalidSpec`. | Mount the storage **at** `/var/lib/libvirt/images` (or point the pool back at the local directory) before upgrading. |
| **New domains are named `<namespace>.<name>`** | Tooling that assumes "domain name equals VirtualMachine name". Existing VMs keep their name; everything addresses a VM by `status.id`. | Read `status.id`. Upgrade the manager **before** the libvirt provider. A create that collides with a domain it does not own fails with `ProviderConflict`: adopt it or rename. |
| **Libvirt `Reconfigure` and power state are honest** | A change the domain did not take is reported (`restart_required`), not silently applied; `status.powerState` can be `Suspended` or `Unknown`. | Roll the libvirt providers and the manager together, CRDs first. Do not downgrade the `VirtualMachine` CRD while any VM is `Suspended` or `Unknown`. |
| **Snapshot rules** ([revert](https://github.com/projectbeskar/virtrigaud/blob/main/docs/vm-snapshot-revert.md), [libvirt clones](https://github.com/projectbeskar/virtrigaud/blob/main/docs/libvirt-clones.md)) | A snapshot of a powered-off VM is taken with the cloud-init CD-ROM ejected; a revert to a snapshot that stored the CD-ROM is refused; a disk-only snapshot is not deleted while a memory snapshot is stored in its overlay. | Take new snapshots, with the VM powered off, of VMs you want to revert to. Delete the memory snapshot before the disk-only one. |
| **Clone identity** | A clone boots as a new cloud-init instance (new instance-id, new SSH host keys) and gets its own seed. A clone carries its source's user-data unless the `VMClone` gives its own. | Review who may create `VMClone`s. |

#### Proxmox

| Change | Who is affected | Action |
|--------|-----------------|--------|
| **An imported disk is imported only when it is the VM's own verified migration stage; stages are named per namespace** | Anyone who sets `spec.importedDisk` on Proxmox by hand, cross-namespace migrations into Proxmox (now `ProxmoxCrossNamespaceTarget` at `Validating`), and Proxmox-target migrations in flight. Stages live in `/var/lib/virtrigaud/import-stage/` (created `0700`; keep it root-only). | Upgrade the manager before the Proxmox provider. Finish or redo in-flight Proxmox-target migrations. Re-create a granted cross-namespace migration in the target VM's own namespace. Remove leftover `/var/tmp/.virtrigaud-import-*` files by hand. Run one VirtRigaud installation per PVE node. |
| **URL image import (`source.http`) is refused** | `VMImage`s with `source.http` used by Proxmox VMs: `Ready=False/InvalidSource`, new VMs not created. It never produced a usable template. | Prepare a template on PVE (`qm importdisk` + `qm template`) and point the `VMImage` at it with `source.proxmox.templateID`. |
| **A VM gets the bridge, VLAN, model and static IP its networks name** ([reference](https://github.com/projectbeskar/virtrigaud/blob/main/docs/proxmox-networks.md)) | Proxmox VMs used `virtio` on `vmbr0` with no static IP whatever the spec said. An `ipAddress` without `prefix` and a non-IP `dns` entry are now refused on create. The manager sends only the target Provider's `proxmox` block of a `VMNetworkAttachment`. | Grant the PVE token `VM.Config.Network`, `VM.Config.Cloudinit` and `SDN.Use` ([privileges](#new-required-privileges-and-configuration)). Review each `VMNetworkAttachment` a Proxmox VM uses. Roll the manager and the Proxmox provider together. |
| **`Reconfigure` no longer resizes the root disk** | Anyone who grew a Proxmox root disk through a `spec.disks` entry (for example one named `root`). Nothing replaces it in this release. | Grow the disk in PVE. |
| **The cloud-init drive goes on the VM's own storage** | Proxmox VMs whose clones have no storage-backed disk. | Optionally set `PVE_DEFAULT_STORAGE` (or `PROVIDER_DEFAULT_STORAGE`) on the Provider ([reference](https://github.com/projectbeskar/virtrigaud/blob/main/docs/proxmox-cloud-init-storage.md)). |

#### Clones, migrations and controller behaviour

| Change | Who is affected | Action |
|--------|-----------------|--------|
| **`spec.resources` overrides are now sent to the provider** | Any VM with `spec.resources.cpu` or `memoryMiB`. The override was only recorded in `status.currentResources` and never applied; on the first reconcile after the upgrade the VM is resized to it. | See [`spec.resources` overrides](#specresources-overrides-now-resize-vms). |
| **`spec.snapshot.revertToRef` now reverts the VM** (it was a silent no-op) | Any VM carrying the field. | See [Stale `revertToRef`](#stale-reverttoref-on-existing-vms). |
| **`powerOn` is honoured** (`VMClone` `spec.options.powerOn`, `VMMigration` `spec.target.powerOn`) | Clones and migrated VMs that do not set `powerOn: true` stay powered off; before, they always came up running. `deleteAfterMigration: true` with `powerOn: false` leaves the workload running nowhere. | Set `powerOn: true` where the new VM must run. Set `spec.target.powerOn: true` on every migration that also sets `spec.source.deleteAfterMigration: true`. |
| **NFS migrations refuse `nfs.uid: 0` and `nfs.gid: 0`** (reason `NFSRootIdentityNotAllowed`, every provider type) | Migrations that set either to `0`. | Use a dedicated non-zero uid/gid that owns the export, or leave them unset; re-create the migration. |
| **A `VMMigration` acts only on the target VM it created** (`TargetVMNotOwned`) | A target name already taken by a VM the migration did not create, and migrations in `Creating`/`Validating-Target` during the upgrade. | Let migrations finish before upgrading; afterwards free the name or pick another `spec.target.name` and re-create the migration. |
| **Staged and landed migration disks are deleted** ([ADR-0011](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0011-migration-staging-cleanup.md)) | Every `nfs`/`s3` migration: the staged copy is deleted when the migration is `Ready` or deleted; a failed or deleted migration deletes the disk its import landed. Deleting such a `VMMigration` waits for it. NFS staging names changed to `vmmigrations_<namespace>_<name>_export.qcow2`. | Roll the providers with the manager. S3 credentials need `s3:GetObject` and `s3:DeleteObject` on the `vmmigrations/` prefix. Add a lifecycle rule for noncurrent versions on versioned buckets. Use `cleanupPolicy: Never` to keep a disk. Remove objects staged by earlier migrations yourself ([leftovers](#leftovers-from-earlier-releases)). |
| **`status.ips` lists routable addresses only** | Anything that parses `status.ips`: loopback, link-local and unreachable addresses are gone. On libvirt, a NAT guest shows its DHCP lease; a bridged guest needs the QEMU guest agent. | Update parsers; install `qemu-guest-agent` in guests ([reference](https://github.com/projectbeskar/virtrigaud/blob/main/docs/vm-status-ips.md)). |
| **A provider call whose outcome is unknown is held, not re-sent** ([reference](https://github.com/projectbeskar/virtrigaud/blob/main/docs/provider-call-outcomes.md)) | Create, Clone, snapshot, export and import after a lost answer: shown as `Provisioning=True/CreateRequested` or held `Ready=False` for an operator instead of repeated blindly. | Roll all providers with the manager so they report the new capabilities; otherwise the manager takes the conservative path. |
| **`VMImage` prepare state is keyed by `<namespace>/<name>`** | `status.providerStatus` and `status.availableOn` use the Provider's namespaced name; each entry records the Provider UID and a source digest; one extra `ImagePrepare` per image and Provider on the first create. | Upgrade the `VMImage` CRD before the manager. Update scripts that read these fields. Under `onMissing: Fail`/`Wait` switch to `Import` to re-validate old entries. Never write `vmimages/status` by hand. |
| **Clustered providers (experimental)** | Only `topology: cluster` Providers: placement against committed capacity, frozen size while pending, host-unreachable and restore holds, cross-host `ListVMs`. | See the [clustered libvirt guide](../guides/clustered-libvirt.md). Nothing on v0.3.11 is affected. |

#### Orphan-on-delete and force-delete

Two user-set annotations (not reserved by the admission policy) detach or release
objects without calling the provider:

- `virtrigaud.io/orphan-on-delete: "true"` on a `VirtualMachine`, then delete the
  object: the finalizer is released with **no provider call** and the hypervisor
  VM and its disks are left for you. This is the supported way to stop managing a
  VM, replacing the old trick of re-pointing `providerRef`. On a clustered
  Provider, a VM in *another* namespace than its Provider needs the Provider's
  permission (`Ready=False/OrphanOnDeleteNotAllowed` otherwise).
- `virtrigaud.io/force-delete: "true"` on a `VirtualMachine`, `VMSnapshot`,
  `VMMigration` or `Provider` drops a held finalizer (logged, with a Warning
  event). It can leave a hypervisor VM, snapshot or staged disk behind.

#### Detaching a VM (orphan-on-delete)

```bash
kubectl annotate virtualmachine <name> -n <namespace> virtrigaud.io/orphan-on-delete=true
kubectl delete virtualmachine <name> -n <namespace>
```

### New required privileges and configuration

**vSphere**

- `VirtualMachine.Config.AdvancedConfig` ("Virtual machine > Change Configuration
  > Advanced configuration") on the target VM folder and resource pool, and on the
  VMs that single-host adoption takes over (the owner stamp is written on
  adoption). Without it every `Create` and `Clone` fails.
- `System.Read` (read-only) on the vCenter **root folder, propagated**, with no
  narrower "No access" permission below it for this account. Before attaching a
  migrated disk, reusing or deleting a migration landing folder, or deleting a
  VM with a disk outside its own directory, the provider checks that no other VM
  uses the disk; vCenter silently hides VMs the account may not see, so the
  provider first verifies the privilege and fails closed otherwise
  (`VM_DISK_CHECK_FAILED`, retried).
- Optional `VIRTRIGAUD_VSPHERE_IMAGE_PROXY` and
  `VIRTRIGAUD_VSPHERE_IMAGE_MAX_DOWNLOAD_GIB` in `Provider.spec.runtime.env`.

**Proxmox**

- For a token that is not root or `Administrator`: `VM.Config.Network` (to set a
  `netN`), `VM.Config.Cloudinit` (to set `ipconfigN` and `nameserver`) and
  `SDN.Use` on `/sdn/zones/<zone>/<bridge>` (and `/<tag>` for a VLAN) for every
  bridge a VM is put on (a plain Linux bridge such as `vmbr0` is in the
  `localnetwork` zone). A narrowly scoped token that worked before can get a 403
  while the provider configures a clone, and the clone is rolled back. Treat
  these ACLs as the control over which bridges and VLANs tenants can reach.
  Details: [Proxmox networks](https://github.com/projectbeskar/virtrigaud/blob/main/docs/proxmox-networks.md#permissions-of-the-pve-token).
- The migration SSH data plane stages disks in `/var/lib/virtrigaud/import-stage/`
  on the node; the provider creates it `0700` and refuses an import if it is not
  a root-owned `0700` directory.

**libvirt** (full list in [Libvirt host preparation](libvirt-host-prepare.md))

- The seed directory on every host (`VIRTRIGAUD_LIBVIRT_SEED_DIR`, default
  `/var/lib/libvirt/virtrigaud-seeds`).
- `VIRTRIGAUD_LIBVIRT_IMAGE_DIRS` when images are outside
  `/var/lib/libvirt/images`.
- The SSH user in `kvm` (or `root`), a POSIX login shell, and the `VR_DISK_READ`
  sudo rule (sudo 1.9.10 or later) to read libvirt's `0600` snapshot overlays.
  Replace the `qemu-img info -U *` wildcard an earlier release documented: it let
  the account read any file's header as root. Never allow `qemu-img *`.
- QEMU with the CVE-2024-4467 fix before you allow `qemu-img` in sudoers.
- The pool directory writable only by `root` and the SSH user (or sticky), or
  full clones and S3/NFS exports are refused.

**Installer**

- Create/update/delete on cluster-scoped `validatingadmissionpolicies` and
  `validatingadmissionpolicybindings` (`admissionregistration.k8s.io`) for the
  reserved-keys policy (Kubernetes 1.30 or later).

#### Manager RBAC

The chart applies these with the manager. A kustomize or hand-rolled install must
reconcile `config/rbac/role.yaml`. New since v0.3.11 (from the chart's manager
ClusterRole):

- the `hosts`, `hosts/status`, `hosts/finalizers`, `hostpools`, `hostpools/status`
  and `vmplacementpolicies` resources of `infra.virtrigaud.io`;
- `get` on the `virtualmachines`, `providers`, `vmclasses`, `vmimages` and
  `vmsnapshots` CustomResourceDefinitions (the readiness check and the consumer
  grant);
- `get`, `list`, `watch` on `namespaces`, and `get` on `storageclasses`;
- `serviceaccounts` create/update/delete (a token-less ServiceAccount per Provider
  runtime);
- **`create` and `update` on `secrets`** (it was read-only): for a clustered
  Provider the manager writes one Secret it owns per Provider,
  `<provider>-hosts`, holding the host inventory and the SSH credentials of the
  hosts. RBAC cannot scope `create` to one name. The manager never deletes
  Secrets, and provider pods have no Secret access. If you add custom rules, note
  that this widens what a compromised manager can do.

### Chart values that changed

| Value | Change |
|-------|--------|
| `security.networkPolicies.*` | **Removed and ignored.** v0.3.11 shipped `enabled: true` but no template used it. Use `networkPolicy.enabled` (below). |
| `networkPolicy.enabled` and the rest of `networkPolicy.*` | **New, default `false`.** Opt-in namespaced NetworkPolicies for the manager and provider pods. Needs a CNI that enforces NetworkPolicy and deployment-specific tuning (monitoring namespace, DNS selectors and `dnsEgressCIDRs`, `providerGRPCPort`, `apiServerCIDRs`, `hypervisorEgressCIDRs`); read the chart README first. Enabling it on a release upgraded with `--reuse-values` fails the render and asks for `--reset-then-reuse-values`. |
| `admissionPolicy.reservedKeys.enabled` (default `true`), `exemptUsernames`, `exemptGroups` | **New.** The ValidatingAdmissionPolicy for manager-owned keys (rendered on Kubernetes 1.30 or later only). |
| `manager.tmpSizeLimit` (default `128Mi`) | **New.** `sizeLimit` of the manager's `/tmp` emptyDir. A pod that exceeds it is evicted. |
| `manager.providerTmpSizeLimit`, `manager.providerTmpSizeLimitMax` | **New**, default empty (per-type defaults: vSphere `512Gi`, libvirt/Proxmox/others `1Gi`; flags `--provider-tmp-size-limit`, `--provider-tmp-size-limit-max`). A `Provider` can override with the annotation `infra.virtrigaud.io/tmp-size-limit` (clamped to the maximum, `TmpSizeLimitClamped`). Raise the limit before migrating a vSphere disk larger than about 256 GiB; it bounds the pod's `/tmp` but does not reserve node storage. |
| `manager.maxDiskSize` | **New**, default empty (no limit). Administrator ceiling on every disk VirtRigaud creates or grows (flag `--max-disk-size`, for example `500Gi`). With `webhooks.enabled=true` it also renders two disk-size validating webhooks. Nothing changes unless it is set. |
| `providers.libvirt.tmpSizeLimit`, `providers.proxmox.tmpSizeLimit` (`1Gi`), `providers.vsphere.tmpSizeLimit` (`512Gi`) | **New**, for the chart-templated providers (still disabled by default). |
| `providers.vsphere.replicaCount` | Must be `1`; a larger value fails the render. |
| `webhooks.conversion`, `webhooks.mutating` | **Removed**: no Go code backs them. `webhooks.enabled` is still `false` by default; `webhooks.validating` remains. |
| `webhooks.certificates.caBundle` | **New**, required only for `source: manual`. |
| `crdUpgrade.*` | Unchanged. The release workflow sets the kubectl image tag to the release tag. |

Chart-templated providers (`providers.<type>.enabled`) stay disabled by default
(since v0.3.8); `Provider` CRs are unaffected.

### Behaviour changes that are visible but not breaking

- **Webhook and metrics servers require TLS 1.2 or later.** Transparent to the
  Kubernetes API server and Prometheus.
- **libvirt uses an in-process SSH client** (one persistent connection per host,
  no `ssh`/`sshpass`/`scp` subprocesses). `sshpass` is no longer needed; host-key
  verification and the `known_hosts` Secret key are unchanged
  ([host preparation](libvirt-host-prepare.md#ssh-host-key-verification-adr-0004)).
  Raise `MaxSessions` before raising the provider's concurrency limits.
- **New libvirt domains use `type='kvm'`** when the host exposes a readable
  `/dev/kvm` (before: always software emulation); existing domains are unchanged.
- **Guest-agent-derived fields** (IPs, time sync, in-guest filesystem grow after an
  online disk expand) now work on libvirt: the SSH commands are shell-quoted.
- **`VMClass.spec.memory` and `spec.diskDefaults.size` have CRD upper bounds**
  (below 100Ti and 1Pi).
- **`VirtualMachine.status.phase` is set on every VM**, and a power change or a
  failed power task no longer leaves a Proxmox VM at `Reconfiguring`.
- **Power is idempotent on every provider** (powering off an off VM succeeds).
- **`powerOffBeforeMigration`**: the VirtualMachine controller powers the source
  off and the migration waits (`SourcePowerOff=False/WaitingForSourcePowerOff`).
- **A single-host VM's provider id is no longer lost after a Create**, and a
  Create that fails on its host backs off.
- **`status.conditions[].message` no longer quotes resolver or transport errors**;
  the detail is in the manager and provider logs.
- **Source builds need Go 1.26.10** (`go.mod`). Binary and image consumers are
  unaffected.

### In-flight VMMigrations

Migrations are the most exposed objects during this upgrade. In short:

- Before the manager rolls, let migrations in `Creating` or `Validating-Target`
  finish (the manager upgrade also restarts provider pods that mount migration
  PVCs, which interrupts an export or import running at that moment). One caught
  mid-upgrade fails with `TargetVMNotOwned` and leaves its target VM as it is:
  check the target, delete the source yourself if you meant to
  (`deleteAfterMigration` does not run for a failed migration).
- **vSphere and Proxmox targets:** a migration whose disk was landed or staged by
  the old provider but whose target VM was not yet created is refused after the
  upgrade (`ValidationError`: "landed by a release before v0.4.0" / "staged by an
  earlier release"). Delete the target `VirtualMachine` and the `VMMigration`, run
  it again, and remove the old landing folder or stage by hand. Migrations that
  completed before the upgrade, and VMs created from them, are unaffected.
- **libvirt targets:** do not start a libvirt-target migration while the provider
  is ahead of the manager; if one is between its import and its create when you
  upgrade, re-run it afterwards.
- **Completed migrations:** a `Ready` migration from before the upgrade deletes
  nothing: it is closed with a `SourceDeletionSkippedPreUpgrade` Warning if a
  snapshot or source VM would have been deleted. Remove those source snapshots and
  (with `deleteAfterMigration`) source VMs yourself if still wanted.
- **Never grant tenants `update`/`patch` on `vmmigrations/status`**: the controller
  trusts the markers it writes there to decide what to delete.

### Stale `revertToRef` on existing VMs

`spec.snapshot.revertToRef` was accepted and ignored before v0.4.0. A VM that still
carries it is **acted on by the first reconcile of the new manager**:

- The controller sends `SnapshotRevert` only while the provider reports the VM
  `Off` **and** `spec.powerState` is `Off` or `OffGraceful` (it never powers a VM
  off for it), only to a `Ready` `VMSnapshot` taken of this VM through its
  Provider. A VM that is already powered off is reverted at once, **discarding
  what was written to its disks since the snapshot**.
- A VM that is running keeps running, but is shown `Ready=False` with the
  `SnapshotReverted` condition's reason (`WaitingForPowerOff`,
  `SnapshotNotFound`, `SnapshotNotReady`, `SnapshotForAnotherVM`, `Unsupported`)
  while the request waits. The outcome is recorded in `status.snapshotRevert`.
- Remove the field from every VM you do not want reverted **before** rolling the
  manager (pre-flight 4). Upgrade the CRDs first: a CRD that prunes
  `status.snapshotRevert` makes the manager send nothing
  (`SnapshotReverted=False/Unsupported`), and the readiness check does not catch
  it.
- On libvirt, a revert needs a snapshot taken with the VM powered off; see the
  [revert reference](https://github.com/projectbeskar/virtrigaud/blob/main/docs/vm-snapshot-revert.md).

### `spec.resources` overrides now resize VMs

Before v0.4.0 the `spec.resources` override was compared against and recorded in
`status.currentResources` but never sent in the Create or Reconfigure request, so
a VM could report a size it never had. Now the request and the status use the same
effective size (VMClass with the override applied). On the first reconcile after
the upgrade a VM whose override was never applied **goes through the normal
reconfigure path** and is resized to it. Reconfigure keeps its online/offline
rules: it applies live only when the VMClass has hot-add enabled and headroom was
provisioned at create, otherwise it is written to the offline config and takes
effect after a restart. To keep a VM at its current size, remove
`spec.resources` before upgrading. An override outside the VMClass bounds is
refused with `Reconfiguring=False/ValidationError`.

### Leftovers from earlier releases

VirtRigaud does not clean up files that earlier releases left behind. After
upgrading, look once for the following and delete only what no `VMMigration` in
flight uses. (From v0.4.0 on, new migrations no longer accumulate most of these.)

- **Staged migration objects** (full, unencrypted copies of source disks) of
  migrations that no longer exist: on S3 under
  `<prefix>/vmmigrations/<namespace>/<name>/export.vmdk`, on NFS
  `vmmigrations_<namespace>_<name>_export.qcow2` (new name) or
  `vmmigrations-<namespace>-<name>-export.qcow2` (old), plus the empty files NFS
  cleanup leaves on libvirt and vSphere targets. Objects recorded as
  `StagedDiskLeftBehind` are never retried.
- **libvirt snapshot overlay files** `<domain>-disk.<snapshot>` in the storage pool
  left by snapshots deleted before v0.4.0: check with `virsh domblklist --all` and
  `qemu-img info --backing-chain` that no domain uses them, then remove them.
- **vSphere `virtrigaud-export-*` files** in the VM folders of migration-source
  datastores. Every earlier vSphere disk export leaked a full copy of the exported
  disk (descriptor and `-flat.vmdk`). Find them with
  `find /vmfs/volumes/*/ -maxdepth 2 -name 'virtrigaud-export-*.vmdk'` on an ESXi
  host and delete the descriptor and its `-flat.vmdk` together, only when no
  `VMMigration` from that source is in phase `Exporting`.
- **Proxmox import stages** and `/var/tmp/.virtrigaud-import-*` on the PVE nodes.
  Sweep `/var/lib/virtrigaud/import-stage/` periodically (for example stages older
  than two days whose `VMMigration` is no longer in flight).
- **Landed migration disks** of migrations that failed or were deleted before
  v0.4.0 (vSphere `[<datastore>] <namespace>_<vm>-migrated/` and the older
  `[<datastore>] <vm>-migrated/`; libvirt `<pool>/<namespace>.<vm>-migrated.qcow2`
  and `<vm>-migrated.qcow2`). Check that no VM uses them first.
- **libvirt cloud-init seeds of existing VMs in `/tmp`.** Seeds built before
  v0.4.0 stay where their domains reference them
  (`/tmp/virtrigaud-cloudinit-<domain>.<random>/` or
  `/tmp/virtrigaud-cloudinit/<name>/`); the directories are listable by every local
  user and the ISO is usually `0644`. On every libvirt host, as root, remove the
  seed directories no domain references, and for the others remove `user-data` and
  `meta-data`, give the SSH user its private copy of the ISO **before** making the
  ISO private, then close the directory:

  ```bash
  SSH_USER=virtrigaud   # the provider's SSH user
  for d in /tmp/virtrigaud-cloudinit-*/ /tmp/virtrigaud-cloudinit/*/; do
    [ -f "$d/cloud-init.iso" ] || continue
    rm -f -- "$d/user-data" "$d/meta-data"
    cp -- "$d/cloud-init.iso" "$d/cloud-init.private.iso"
    chown "$SSH_USER": "$d/cloud-init.private.iso"
    chmod 600 "$d/cloud-init.private.iso" "$d/cloud-init.iso"
    chmod 711 "$d"
  done
  [ -d /tmp/virtrigaud-cloudinit ] && chmod 711 /tmp/virtrigaud-cloudinit
  ```

  A host that empties `/tmp` at boot or cleans old files in it (Ubuntu:
  `systemd-tmpfiles`, 30 days) removes these seeds and the domain then no longer
  starts: move a VM's seed into the seed directory while the VM is shut off (the
  commands are in the repository guide's
  [Leftovers section](https://github.com/projectbeskar/virtrigaud/blob/main/docs/upgrading.md#leftovers-from-earlier-releases)).
- **Bare-named prepared images** of the earlier image scheme (vSphere templates
  named after the bare `VMImage`, libvirt `<pool>/<VMImage name>.qcow2`) are left in
  place; remove them once nothing references them.

### Post-upgrade verification checklist

- [ ] `kubectl get pods -n virtrigaud-system`: the manager and provider pods are
      Ready.
- [ ] The manager's CRD-feature check passed:

  ```bash
  kubectl get crd virtualmachines.infra.virtrigaud.io \
    -o jsonpath='{.spec.versions[?(@.name=="v1beta1")].schema.openAPIV3Schema.properties.status.properties.boundProvider.type}'
  # should print: object
  kubectl get crd providers.infra.virtrigaud.io \
    -o jsonpath='{.spec.versions[?(@.name=="v1beta1")].schema.openAPIV3Schema.properties.spec.properties.consumerNamespaceSelector.type}'
  # should print: object (likewise for vmclasses and vmimages)
  ```

  or the metric `virtrigaud_manager_vm_crd_security_features` on the manager's
  `/metrics`.
- [ ] The manager is v0.4.0: `virtrigaud_build_info{version="v0.4.0"}` on
      `/metrics` (see [Observability](observability.md)).
- [ ] Every `Provider` reports `Available` and runs the v0.4.0 image:

  ```bash
  kubectl get providers -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,IMAGE:.spec.runtime.image
  ```
- [ ] No VM is unexpectedly refused for a cross-namespace reference:

  ```bash
  kubectl get virtualmachines -A -o json | jq -r '.items[]
    | select(any(.status.conditions[]?; .type=="Ready" and .reason=="ConsumerNotAllowed"))
    | "\(.metadata.namespace)/\(.metadata.name)"'
  ```

  Each line needs `spec.consumerNamespaceSelector` on the object its `Ready`
  message names.
- [ ] No `VMSnapshot` is `Ready` without a snapshot on the hypervisor. Older
      managers could mark a snapshot `Ready` without calling the provider; such
      snapshots have no `status.creationTime`. Delete and re-create each one listed:

  ```bash
  kubectl get vmsnapshots -A -o json | jq -r '.items[]
    | select(.status.phase=="Ready" and .status.creationTime==null)
    | "\(.metadata.namespace)/\(.metadata.name)"'
  ```
- [ ] Bound VMs' `providerRef` is what you expect, because the admission rule now
      locks it in. A VM bound before the upgrade gets its binding recorded from its
      **current** `providerRef` on its first reconcile (`BoundProviderRecorded`
      event); audit multi-tenant clusters beforehand with
      `kubectl get virtualmachines -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,ID:.status.id,PROVIDER_NS:.spec.providerRef.namespace,PROVIDER:.spec.providerRef.name`.
- [ ] vSphere: create (or reconcile) a test VM; it exercises the new
      `AdvancedConfig` privilege end to end.
- [ ] libvirt: on every host the seed directory exists, belongs to the SSH user and
      is private (`stat -c '%a %U' /var/lib/libvirt/virtrigaud-seeds` prints `711`
      and the SSH user), and a test VM through each Provider does not fail with
      `refusing to stage cloud-init data`. If images live outside
      `/var/lib/libvirt/images`, `VIRTRIGAUD_LIBVIRT_IMAGE_DIRS` is set and an image
      create still succeeds.
- [ ] libvirt: before deleting any pre-upgrade VM, check
      `virsh domblklist --details <domain>` for a shared legacy disk.
- [ ] Image preparation: `virtrigaud_provider_image_prepare_legacy_requests_total`
      stays `0` for every `provider_type`. A non-zero value means a manager older
      than v0.4.0 is still sending requests by bare name.
- [ ] Clustered libvirt: `kubectl get hosts -A -o custom-columns=NAME:.metadata.name,STORAGE:.status.allocatableStorageBytes`
      shows the free space of each host's `default` pool.
- [ ] If you enabled `networkPolicy.enabled=true`, render and check the objects
      before relying on them:
      `helm template virtrigaud virtrigaud/virtrigaud --set networkPolicy.enabled=true | grep -A2 'kind: NetworkPolicy'`.

### Rollback caveats

A partial rollback (providers only, or the manager only) is safer than a full one
and is enough for most issues. For a full rollback go in reverse (providers,
manager, CRDs) and expect the following. Rolling back is **not** a way to remove
the security fixes' state: some of it is recorded in the cluster.

- **The `Provider` in-use finalizer stays.** An older manager neither adds nor
  removes `provider.infra.virtrigaud.io/in-use`, so a `Provider` deleted after the
  rollback stays `Terminating`. Check that no VM uses it, then remove the finalizer:
  `kubectl patch provider <name> -n <namespace> --type=json -p '[{"op":"remove","path":"/metadata/finalizers"}]'`.
- **CRD changes are one-way in practice.** The `spec.providerRef` immutability rule
  is a CRD CEL rule, so rolling the *manager* back does not restore the ability to
  re-point a bound VM; only an older CRD does, and that also drops
  `status.boundProvider` and the other additive status fields.
- **Do not downgrade the `VirtualMachine` CRD while a VM's `status.powerState` is
  `Suspended` or `Unknown`**: the older enum rejects every status write of such a
  VM.
- **An old manager against the new CRDs silently drops the new protections**: it
  does not enforce the bound-provider check, ignores `spec.consumerNamespaceSelector`
  (re-opening unrestricted cross-namespace references) and the namespace grant
  annotation, and ignores `orphan-on-delete`. Treat that window as running without
  the defence in depth.
- **An old manager against a new provider.** A new libvirt provider serves image
  prepares in deprecated legacy mode by bare name (logged at `WARN`, counted in
  `virtrigaud_provider_image_prepare_legacy_requests_total`); a new vSphere provider
  does the same, so the cross-tenant limitation ADR-0009 closed is back while the
  manager is rolled back; a new Proxmox provider refuses URL imports.
- **Rolling a provider back** holds image prepares (`ProviderLacksArtifactIdentity`),
  stops owner stamping on single-host adoptions and Proxmox VMs, stops applying a
  Proxmox VM's networks, holds clustered resizes
  (`ProviderLacksHonestReconfigure`) and new clustered VMs
  (`ProviderLacksListOwnerFilter`), removes the cluster-wide disk guard of a clustered
  libvirt provider, and brings back the wrong-disk resize on vSphere and Proxmox (hold
  CPU/memory changes of VMs with `spec.disks` while an older image runs).
- **Seeds and domains outlive a libvirt provider rollback.** An older libvirt
  provider builds new seeds in `/tmp` again and makes clones share their source's
  identity; seeds already in the seed directory keep working but the older provider
  does not know to remove them. Domains created as `<namespace>.<name>` keep that
  name.
- **A clustered-target migration in flight** cannot be rolled back safely: an older
  manager does not know `WaitingForImport`. Finish or delete such migrations first.

### Upgrading from a release candidate

Release candidates rc1, rc2 and rc4 to rc9 were cut; **rc3 was tagged but its
release run was stopped by the image scan and no rc3 release was published**.
v0.4.0 is built from the same code as rc9, so from rc9 only the version changes: bump the
chart to `0.4.0` and the images to `v0.4.0`. From an earlier candidate apply, in
order, every step from your candidate up to rc9, then bump:

| You are on | Do, before moving on |
|------------|----------------------|
| **rc8** | Roll the libvirt providers (single-host and clustered) first, then the manager. No CRD, RBAC, chart or proto change. Until a provider is rolled, do not delete a disk-only snapshot of a VM that has a memory snapshot: the old provider destroys the memory snapshot. The rc9 delete check also reads the overlays a child snapshot or a revert recorded, so confirm the `VR_DISK_READ` grant (rc8 step). |
| **rc7** | Grant the SSH user `VR_DISK_READ` over the pool directory (and every other directory VM disks live in) where it cannot read libvirt's `0600` overlays; skip where it already can. Then the manager and the libvirt providers. Only the description of `status.ips` changed in the CRDs. |
| **rc6** | Repair any libvirt VM you reverted to a snapshot on rc6 (its CD-ROM is on a `cloud-init.<digits>` file and it does not start; follow the [repair runbook](https://github.com/projectbeskar/virtrigaud/blob/main/docs/vm-snapshot-revert.md#repairing-a-vm-broken-by-a-v040-rc6-revert)), then roll the libvirt providers, then take new snapshots (VM powered off) of the VMs you want to revert, and delete the old ones. No CRD change. |
| **rc5** | Remove `spec.snapshot.revertToRef` from VMs (and `VMSet` templates) you do not want reverted; apply the CRDs (`VirtualMachine` gains `status.snapshotRevert`, `HostPool` gains printer columns); roll the manager (its role gains `hostpools/status`); roll the clustered libvirt provider. |
| **rc4** | Grant the PVE token `VM.Config.Network`, `VM.Config.Cloudinit` and `SDN.Use` on its bridges, then roll the manager and the Proxmox provider **together**. No CRD change. |
| **rc2** | Create the seed directory on every libvirt host **first**. Apply the CRDs (`VirtualMachine`, `VMSet`, `VMMigration` changed), then the manager, then the providers (the clustered libvirt provider before you migrate into it). Review who can create `VMClone`s (clones carry their source's user-data) and any `VMPlacementPolicy` `minDiskSpacePerHost` (it now compares against the `default` pool alone). Make the seeds in `/tmp` private ([leftovers](#leftovers-from-earlier-releases)). |
| **rc1** | Apply the CRDs first (two optional status fields are new: `VMMigration` `status.storagePVCUID` and `status.storageInfo.importTarget.providerUID`; an old CRD prunes them), roll **all** providers with the manager (not only Proxmox: three capability fields are new), let migrations in `Creating`/`Validating-Target` finish, and expect the manager upgrade to restart provider pods that mount migration PVCs. |

## Older versions

Notes for releases before v0.3.11, newest first. They remain accurate for the
release they describe; a skipped release's notes still apply.

### v0.3.7 → v0.3.8

**Additive release. No breaking changes for operators.** v0.3.8 adds two new
controllers (VMClone + VMSet), a new status field on `VMClone`, the RBAC those
controllers need, and provider-side connection-resilience fixes. A standard
`helm upgrade` picks everything up. The one thing to check is the chart's
templated-provider default — see the Helm note below.

#### What's new (no operator action required)

- **VMClone + VMSet controllers** — the manager now runs two additional
  reconcilers. The Helm chart adds the RBAC for `vmclones` and `vmsets` (and
  their `/status` subresources) automatically. If you maintain a hand-rolled
  ClusterRole instead of the chart's, add read/write on
  `vmclones`/`vmclones/status` and `vmsets`/`vmsets/status` in the
  `infra.virtrigaud.io` API group.
- **New `VMClone.status.targetVMID` field** — purely additive status field
  surfacing the provider-specific ID of the clone's target VM. No spec change,
  no migration step.
- **Provider connection resilience** — the vSphere provider now keeps its
  vCenter session alive and reconnects on a real probe failure
  ([#190](https://github.com/projectbeskar/virtrigaud/pull/190)); the libvirt
  provider now retries transient SSH connection failures with bounded backoff
  ([#191](https://github.com/projectbeskar/virtrigaud/pull/191)). Both are
  provider-internal — no Provider CR change. See
  [Resilience](resilience.md#provider-side-connection-resilience-v038).
- **Migration-storage PVC safety** — the provider controller no longer deletes
  migration-storage PVCs and now watches them
  ([#184](https://github.com/projectbeskar/virtrigaud/pull/184)). No operator
  action; in-flight migrations are simply safer.

#### Helm note: templated providers are DISABLED by default ([#173](https://github.com/projectbeskar/virtrigaud/pull/173))

The chart no longer renders templated provider Deployments by default. This is a
**chart default change, not a code breaking change**:

- **If you manage providers as `Provider` CRs** (the recommended pattern, where
  the operator deploys provider workloads from the CR) — **you are unaffected.**
  Nothing changes.
- **If you relied on the chart's templated providers** (rendered directly from
  Helm values rather than from a `Provider` CR), they will no longer be created
  after the upgrade. Re-enable each one explicitly:

  ```yaml
  providers:
    vsphere:
      enabled: true
    libvirt:
      enabled: true
    proxmox:
      enabled: true
  ```

  Set only the types you actually use.

#### Helm upgrade command

```bash
helm repo update
helm upgrade -i virtrigaud virtrigaud/virtrigaud \
  --version 0.3.8 \
  --reset-values \
  -f your-values.yaml
```

If you use chart-templated providers, remember the `providers.<type>.enabled=true`
flag above must be in `your-values.yaml` or they will not be rendered.

#### Post-upgrade verification

```bash
# Confirm the manager is running v0.3.8
kubectl -n virtrigaud-system port-forward deploy/virtrigaud-manager 8080:8080 &
curl -s localhost:8080/metrics | grep '^virtrigaud_build_info'
# Expect: virtrigaud_build_info{version="v0.3.8",...} 1

# Confirm the new reconcilers are emitting (after first VMClone/VMSet activity)
curl -s localhost:8080/metrics | \
  grep -E 'virtrigaud_manager_reconcile_total\{kind="(VMClone|VMSet)"'

# All providers should still be ProviderAvailable=True
kubectl get providers -A
```

### v0.3.6 → v0.3.7

Released 2026-05-30. **Security enforcement + multi-arch release.** Two breaking
changes affect SSH libvirt providers and any Provider CR without a `tls` block.

#### Breaking changes

##### 1. mTLS now enforced on all Provider CRs (BREAKING)

The manager now **requires** a `spec.runtime.service.tls` block on every
Provider CR. A Provider that lacks the block will not reconcile — no Deployment
is created — and its status shows:

```
TLSConfigured=False, Reason=TLSBlockMissing
```

**Remediation — to enable mTLS (recommended for production):**

1. Create a TLS Secret with `tls.crt`, `tls.key`, and `ca.crt`:

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: provider-vsphere-tls
     namespace: virtrigaud-system
   type: kubernetes.io/tls
   data:
     tls.crt: <base64>
     tls.key: <base64>
   stringData:
     ca.crt: |
       -----BEGIN CERTIFICATE-----
       ...
       -----END CERTIFICATE-----
   ```

2. Add the `tls` block to your Provider CR under `spec.runtime.service`:

   ```yaml
   runtime:
     service:
       tls:
         enabled: true
         secretRef:
           name: provider-vsphere-tls
         insecureSkipVerify: false
   ```

**Remediation — to keep plaintext (dev/lab only):**

```yaml
runtime:
  service:
    tls:
      enabled: false
```

When `tls.enabled: false`, the condition reads `TLSConfigured=False,
Reason=ExplicitlyDisabled` and the Deployment proceeds. This is audit-flagged
and not suitable for regulated environments.

**Additional mTLS facts:**

- TLS 1.3 is the minimum protocol version for both manager and provider.
- Provider env `VIRTRIGAUD_PROVIDER_ALLOWED_SANS` (comma-joined) constrains
  which manager certificates are accepted. `VIRTRIGAUD_PROVIDER_INSECURE=true`
  opts out of TLS entirely on the provider side (plaintext).
- Fail-closed: no TLS material + no explicit opt-out → provider hard-exits.
- For chart-templated providers, the Helm `providerTLS` block accepts
  `secretName`, `allowedSANs` (list), and `insecure` (bool, only when
  `secretName` is empty).

##### 2. Libvirt SSH host-key verification now enforced (BREAKING for SSH libvirt)

In v0.3.6 the libvirt provider set `no_verify=1` on the SSH URI, skipping
host-key verification. **That flag is removed in v0.3.7.** Existing SSH libvirt
Providers will stop connecting after the upgrade until a `known_hosts` key is
added to the credentials Secret.

**Remediation:**

Seed `known_hosts` on the operator workstation and add it to the Secret:

```bash
ssh-keyscan -H <libvirt-host> > known_hosts
kubectl patch secret libvirt-creds -n virtrigaud-system \
  --type='json' \
  -p="[{\"op\": \"add\", \"path\": \"/stringData/known_hosts\",
         \"value\": \"$(cat known_hosts)\"}]"
```

The provider reads the key from `/etc/virtrigaud/credentials/known_hosts`.

**Escape hatch (lab/migration windows only; audit-flagged):**

```yaml
spec:
  runtime:
    env:
      - name: LIBVIRT_INSECURE_SKIP_HOST_KEY_VERIFICATION
        value: "true"
```

#### Other changes (no operator action required)

- **Multi-arch images** — all component images (`manager`, `provider-vsphere`,
  `provider-libvirt`, `provider-proxmox`) are now built for both
  `linux/amd64` and `linux/arm64`. arm64 clusters are now fully supported.
  No changes needed in Provider CRs or Helm values.

- **Manager RBAC tightened** — the manager's ClusterRole now grants read-only
  access to Secrets (was read-write in v0.3.6). If you added custom rules that
  relied on write access, re-add them via `rbac.additionalRules` in your Helm
  values. A `helm upgrade` picks up the new RBAC automatically. (v0.4.0 adds
  `create` and `update` on Secrets again, for the clustered libvirt
  `<provider>-hosts` Secret only; see [Manager RBAC](#manager-rbac).)

- **Go source-build floor raised to 1.26.3** — if you build from source, you
  need Go 1.26.3 or later. Binary and image consumers are unaffected.

#### Helm upgrade command

```bash
helm repo update
helm upgrade -i virtrigaud virtrigaud/virtrigaud \
  --version 0.3.7 \
  --reset-values \
  -f your-values.yaml
```

If you use chart-templated providers with `providerTLS.secretName`, ensure the
referenced Secret exists before the upgrade or the provider pods will not start.

#### Post-upgrade verification

```bash
# All providers should show TLSConfigured=True and ProviderAvailable=True
kubectl get providers -A

# Confirm the manager is running v0.3.7
kubectl -n virtrigaud-system port-forward deploy/virtrigaud-manager 8080:8080 &
curl -s localhost:8080/metrics | grep '^virtrigaud_build_info'
# Expect: virtrigaud_build_info{version="v0.3.7",...} 1

# Check for any providers still failing TLS negotiation
kubectl get providers -A \
  -o custom-columns=NAME:.metadata.name,TLS:.status.conditions[?(@.type=="TLSConfigured")].reason
```

### v0.3.5 → v0.3.6

Released 2026-05-25. **Headline observability + supply-chain release.** No
breaking changes for default-config users; binary consumers via released
images are unaffected.

#### Breaking changes

- **None for operators.** Source builders need **Go 1.26+** installed
  locally ([#125](https://github.com/projectbeskar/virtrigaud/pull/125),
  toolchain floor bumped 1.24.0 → 1.26.0). If you only consume the released
  manager + provider container images, this does not affect you.

#### Helm upgrade command

```bash
helm repo update
helm upgrade -i virtrigaud virtrigaud/virtrigaud \
  --version 0.3.6 \
  --reset-values
```

`--reset-values` ensures the upgrade picks up any new chart defaults rather than
carrying over stale rendered values. If you have local value overrides, pass them
via `-f your-values.yaml` after `--reset-values` (or use `--reset-then-reuse-values`,
see [Required upgrade order](#required-upgrade-order)).

#### New `/metrics` families to add to dashboards

After the rollout, the following `virtrigaud_*` families become available
(some emit immediately, some on first activity):

| Metric | Type | Labels | When it populates |
|---|---|---|---|
| `virtrigaud_circuit_breaker_state` | gauge | `provider_type`, `provider` | Immediately at boot (one row per Provider CR). Values: 0=Closed, 1=HalfOpen, 2=Open. **Alertable on `> 0`.** |
| `virtrigaud_circuit_breaker_failures_total` | counter | `provider_type`, `provider` | On first CB-counted RPC failure per Provider |
| `virtrigaud_vm_operations_total` | counter | `provider_type`, `provider`, `operation`, `outcome` | On the first VM RPC after deploy (Create/Delete/Power/Describe/Reconfigure) |
| `virtrigaud_ip_discovery_duration_seconds` | histogram | `provider_type` | On the first no-IPs → has-IPs VM transition (idempotent across manager restarts) |
| `virtrigaud_provider_tasks_inflight` | gauge | `provider_type`, `provider` | Seeded to 0 at boot, increments on the first task-creating RPC |

These slot in alongside the metrics already present since v0.3.5. The full
metric inventory after v0.3.6 is **11 of 12** `virtrigaud_*` families wired
in code; the 12th (`virtrigaud_queue_depth`) is explicitly deprecated — see
the next section.

Suggested baseline alerts:

- `max by (provider) (virtrigaud_circuit_breaker_state) > 0` for **5m** —
  fires when any Provider's circuit opens or half-opens
- `rate(virtrigaud_vm_operations_total{outcome="error"}[5m]) > 0` per
  provider/operation — surface elevated failure rates
- `histogram_quantile(0.95, sum by (le, provider_type) (rate(virtrigaud_ip_discovery_duration_seconds_bucket[5m])))` —
  P95 time from `kubectl apply` to first IP

#### Deprecation: `virtrigaud_queue_depth`

The `virtrigaud_queue_depth{kind}` gauge and the
`(*ReconcileMetrics).SetQueueDepth` helper are **deprecated in v0.3.6**
([#132](https://github.com/projectbeskar/virtrigaud/pull/132)). They are
redundant with controller-runtime's `workqueue_depth{name=<controller-name>}`,
which has been on `/metrics` since v0.3.0 and ships with 8 sibling workqueue
metrics for free.

The metric family is still registered in v0.4.0 (no breakage), and the `# HELP`
line begins with `[DEPRECATED v0.3.6 — use workqueue_depth{name} instead]` so the
deprecation surfaces on your next scrape. Removal is scheduled for a later
release; migrate dashboards now.

**Migration mapping** for the 8 reconciler kinds (also in the GoDoc on
`SetQueueDepth`):

| Reconciler                       | controller-runtime `name` label |
|----------------------------------|---------------------------------|
| `VirtualMachineReconciler`       | `virtualmachine`                |
| `ProviderReconciler`             | `provider`                      |
| `VMClassReconciler`              | `vmclass`                       |
| `VMImageReconciler`              | `vmimage`                       |
| `VMNetworkAttachmentReconciler`  | `vmnetworkattachment`           |
| `VMAdoptionReconciler`           | `vmadoption`                    |
| `VMSnapshotReconciler`           | `vmsnapshot`                    |
| `VMMigrationReconciler`          | `vmmigration`                   |

Dashboard rewrite recipe:

```
virtrigaud_queue_depth{kind="virtualmachine"}
    →    workqueue_depth{name="virtualmachine"}
```

#### CircuitBreaker behaviour change

Every outbound provider gRPC RPC is now wrapped by a per-Provider
CircuitBreaker ([#112](https://github.com/projectbeskar/virtrigaud/issues/112)),
backed by the new `virtrigaud_circuit_breaker_*` metric families above.

Defaults:

| Setting              | Default | Effect                                         |
|----------------------|---------|------------------------------------------------|
| `FailureThreshold`   | 10      | Open after 10 consecutive infra-class failures |
| `ResetTimeout`       | 60s     | Time in Open before transitioning to HalfOpen  |
| `HalfOpenMaxCalls`   | 3       | Probe calls allowed in HalfOpen state          |

**What trips the breaker** (infra-class gRPC errors):

- `Unavailable`
- `DeadlineExceeded`
- `Internal`
- `Unknown`

**What passes through** (business-class errors — no CB impact):

- `NotFound`, `AlreadyExists`, `InvalidArgument`, `FailedPrecondition`,
  `PermissionDenied`, `Unauthenticated`, etc.

!!! note "v0.4.0 excludes more infra-class answers from the breaker"
    In v0.4.0 an `Unavailable` that is scoped to one clustered host, a
    per-VM `VM_OPERATION_FAILED`, `VM_DISK_CHECK_FAILED`, an `OUTCOME_UNKNOWN_RETRY`
    answer, and image-source failures (`IMAGE_SOURCE_UNAVAILABLE`) no longer count
    toward the breaker, so one failing VM or one dead host cannot open it for the
    whole Provider. The defaults below are unchanged
    (`internal/transport/grpc/client.go`, `internal/resilience/circuitbreaker.go`).

!!! warning "Global config only — no per-Provider knob yet"
    The CB defaults come from `resilience.DefaultConfig()` and are applied
    uniformly to every Provider CR. There is **no per-Provider override
    field** in v0.3.6. If you need different thresholds for a high-latency
    provider, that work is tracked separately; for now, plan around the
    defaults above.

#### Security: OpenTelemetry CVE fixes

The OpenTelemetry Go SDK dependencies are bumped to **v1.43.0** in v0.3.6,
closing 3 HIGH-severity CVEs that were present in v0.3.5
([#143/#144](https://github.com/projectbeskar/virtrigaud/pull/144)):

| CVE              | Package                            | v0.3.5 | v0.3.6  |
|------------------|------------------------------------|--------|---------|
| CVE-2026-29181   | `go.opentelemetry.io/otel`         | v1.39.0 | v1.43.0 |
| CVE-2026-24051   | `go.opentelemetry.io/otel/sdk`     | v1.39.0 | v1.43.0 |
| CVE-2026-39883   | `go.opentelemetry.io/otel/sdk`     | v1.39.0 | v1.43.0 |

CVE-2026-24051 and CVE-2026-39883 are PATH-hijacking primitives — exactly
the class of finding regulated environments will not accept. **Upgrade
promptly** if you scan with Trivy/Grype.

#### Smoke recipe (verify your upgrade)

After the rollout completes, verify the manager is running the v0.3.6 binary
and the new metrics are present:

```bash
# Port-forward to the manager metrics endpoint
kubectl -n virtrigaud-system port-forward deploy/virtrigaud-manager 8080:8080 &

# 1. Build info must report v0.3.6 / Go 1.26.x
curl -s localhost:8080/metrics | grep '^virtrigaud_build_info'
# Expect: virtrigaud_build_info{version="v0.3.6", go_version="go1.26.x", ...} 1

# 2. Count distinct virtrigaud_* metric families on /metrics
curl -s localhost:8080/metrics | grep -E '^# HELP virtrigaud_' | wc -l
# Expect: ~9-11 families emit immediately. The remaining 2 (vm_operations_total,
# ip_discovery_duration_seconds) populate on the first relevant VM event.

# 3. Confirm the CB gauge is exposed (one row per Provider CR)
curl -s localhost:8080/metrics | grep '^virtrigaud_circuit_breaker_state'

# 4. Confirm deprecation banner on the old queue_depth gauge
curl -s localhost:8080/metrics | grep -B1 '^virtrigaud_queue_depth' | head -2
# Expect a # HELP line beginning with [DEPRECATED v0.3.6 ...]
```

If any of those checks fail, capture the manager logs
(`kubectl -n virtrigaud-system logs deploy/virtrigaud-manager`) before
rolling back.


### v0.2.0 → v0.2.1

**Changes that need a CRD update:**

- PowerState validation fixed (`OffGraceful` is now supported).
- Hardware version management added (vSphere only).
- Disk size configuration is respected.

**Required Actions:**
1. **CRD Update Required**: New powerState validation and schema changes
2. **Provider Image Update**: Ensure providers use v0.2.1+ images for new features
3. **Field Testing**: Verify OffGraceful, hardware version, and disk sizing work correctly

**Upgrade Steps:**
```bash
# 1. Backup existing resources
kubectl get virtualmachines,vmclasses,providers -A -o yaml > virtrigaud-backup-v021.yaml

# 2. Update CRDs (fixes OffGraceful validation) from the chart you are installing
helm pull virtrigaud/virtrigaud --version 0.2.1 --untar
kubectl apply --server-side --force-conflicts -f virtrigaud/crds/

# 3. Upgrade VirtRigaud
helm upgrade virtrigaud virtrigaud/virtrigaud --version 0.2.1

# 4. Verify OffGraceful works
kubectl patch virtualmachine <vm-name> --type='merge' -p='{"spec":{"powerState":"OffGraceful"}}'
```

## Rollback procedures

For the v0.3.11 to v0.4.0 caveats, read [Rollback caveats](#rollback-caveats)
first: a rollback is not symmetrical.

### Rollback to the previous version

```bash
# 1. Find the revision to return to
helm history virtrigaud -n virtrigaud-system

# 2. Roll the application back
helm rollback virtrigaud <revision> -n virtrigaud-system

# 3. Roll the Provider images back too (spec.runtime.image on each Provider CR)

# 4. Verify resources are still reconciled
kubectl get virtualmachines -A
```

`helm rollback` restores the manager and the chart templates. It does **not**
roll the CRDs back: the chart's CRD hook runs only on `pre-install` and
`pre-upgrade`. Reapplying an older CRD schema removes admission rules and prunes
fields that were already recorded (for example `status.boundProvider`), which is
not recommended after a v0.4.0 upgrade.

### Emergency recovery

```bash
# 1. Check the manager and provider logs
kubectl logs -n virtrigaud-system deployment/virtrigaud-manager
kubectl logs -n virtrigaud-system -l app.kubernetes.io/component=provider --tail=200

# 2. Restart the manager to force a fresh reconcile of everything
kubectl rollout restart -n virtrigaud-system deployment/virtrigaud-manager

# 3. Last resort: restore custom resources from your backup. Remove the
#    server-populated fields (metadata.uid, resourceVersion, status) first.
#    This restores specs only; it does not restore any hypervisor state.
kubectl apply -f virtrigaud-backup.yaml
```

## Automated upgrade with GitOps

The chart's CRD hook applies the CRDs in the same sync that rolls the manager. For
v0.3.11 to v0.4.0 you need a pause between the CRDs and the manager (the
consumer grants of step 3), so apply the CRDs and the selectors **before** you
bump the chart revision, for example from a separate Application or an earlier
sync wave.

### ArgoCD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: virtrigaud
  namespace: argocd
spec:
  project: default
  source:
    chart: virtrigaud
    repoURL: https://projectbeskar.github.io/virtrigaud
    targetRevision: "0.4.0"
  destination:
    server: https://kubernetes.default.svc
    namespace: virtrigaud-system
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true   # CRD updates
```

### Flux

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: virtrigaud
  namespace: virtrigaud-system
spec:
  interval: 10m
  chart:
    spec:
      chart: virtrigaud
      version: "0.4.0"
      sourceRef:
        kind: HelmRepository
        name: virtrigaud
  upgrade:
    crds: CreateReplace  # Ensure CRDs are updated
```

The `v2` API needs Flux 2.3 or later; earlier versions use `v2beta2`.

## Troubleshooting upgrades

### The manager is not Ready after the upgrade

`helm upgrade --wait` times out and the old pod stays. The new manager's readiness
includes a CRD-feature check (`vm-crd-security-features`). Its log line names the
missing field; apply the CRDs from the chart you are upgrading to:

```bash
kubectl logs -n virtrigaud-system deploy/virtrigaud-manager | grep -i 'crd'
kubectl apply --server-side --force-conflicts -f virtrigaud/crds/
```

### CRD validation or apply errors

```bash
# Check the CRD you are applying over
kubectl get crd virtualmachines.infra.virtrigaud.io -o yaml

# Field-ownership conflicts from earlier client-side applies
kubectl apply --server-side --force-conflicts -f virtrigaud/crds/
```

A `kubectl apply` of a field the installed CRD does not know is rejected (strict
field validation) or pruned: apply the CRDs first, then the object.

### VMs stop reconciling with `ConsumerNotAllowed`

Set `spec.consumerNamespaceSelector` on the object the `Ready` message names; the
manager re-drives the VM within seconds of each grant. Nothing was deleted.

### Provider image mismatch

```bash
# Check provider images
kubectl get providers -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,IMAGE:.spec.runtime.image

# Update provider image
kubectl patch provider <provider-name> -n <namespace> --type='merge' \
  -p '{"spec":{"runtime":{"image":"ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.0"}}}'
```

### libvirt creates fail with `refusing to stage cloud-init data`

The seed directory is missing or not private on that host. See
[Libvirt host preparation](libvirt-host-prepare.md#cloud-init-seed-directory).

### VMs stay `Terminating`

A VM waits while its `Provider` is down or rolling out
(`Ready=False/ProviderUnavailable`), and a `Provider` waits while VMs use it
(`DeleteBlocked=True/ProviderInUse`). Fix the Provider first; the cause is in the
manager log (`Cannot reach the provider to delete the VM`). To release on purpose,
see [Orphan-on-delete and force-delete](#orphan-on-delete-and-force-delete).

### Resource conflicts

```bash
# Check recent events
kubectl get events -A --sort-by=.metadata.creationTimestamp

# Restart the provider pods of one Provider (the Deployment name depends on the Provider)
kubectl rollout restart -n <namespace> deployment/<provider-deployment>
```

## Best practices

### Pre-upgrade checklist

- [ ] Back up all VirtRigaud resources.
- [ ] Read the release notes and [Breaking changes](#breaking-changes).
- [ ] Run the [pre-flight checks](#pre-flight-checks).
- [ ] Test the upgrade in a staging cluster and, for libvirt, on a non-production
      host.
- [ ] Verify provider connectivity.
- [ ] Plan the rollback strategy ([caveats](#rollback-caveats)).

### Monitoring during the upgrade

```bash
# Watch controller logs
kubectl logs -n virtrigaud-system deployment/virtrigaud-manager -f

# Monitor VM status
kubectl get virtualmachines -A --watch

# Check provider health
kubectl get providers -A
```

### Packaging the chart yourself

The chart's own `crds/` directory is generated on demand and is empty in a source
checkout. The pre-upgrade hook applies the CRDs baked into the chart **at package
time**, so a chart packaged before a CRD change **overwrites** the live CRDs and can
prune fields its schema does not know. Run `make gen-helm-crds` (or
`make helm-package`) before packaging, and `make verify-helm-crds` to check that
the chart's CRDs match `config/crd/bases`. Always upgrade with a chart built from a
matching release.

## Support and recovery

If you encounter issues during an upgrade:

1. **Check the release notes:** <https://github.com/projectbeskar/virtrigaud/releases>
2. **Review logs:** controller and provider logs for error details.
3. **Ask the community:** GitHub issues and discussions.
4. **Roll back:** use the documented procedures, partial first.

Always test upgrades in a non-production environment first.
