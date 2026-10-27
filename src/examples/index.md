<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VirtRigaud Examples

These examples mirror the `examples/` directory of the VirtRigaud repository at **v0.4.1**. All of them use the `infra.virtrigaud.io/v1beta1` API, and every `infra.virtrigaud.io` object in them was checked against the v0.4.1 CRDs with a strict server-side dry-run (CRD schema and CEL rules), so none carries an unknown field, a wrong type or an invalid enum value. The webhooks are not part of that check. Provider images are pinned to `ghcr.io/projectbeskar/virtrigaud/provider-<type>:v0.4.1`.

!!! warning "Replace the placeholders before you apply anything"
    Endpoints (`vcenter.example.com`, `pve.example.com`, `192.0.2.x`), Secret names, datastores, template names and image URLs are placeholders. Credential Secrets contain `REDACTED` values.

## Read this before applying an example

- **Every Provider needs a `runtime.service.tls` decision.** A Provider with no `tls` block fails to reconcile (`TLSConfigured=False`, reason `TLSBlockMissing`). The Provider examples set `tls.enabled: true` with a `secretRef` to a Secret holding `tls.crt`, `tls.key` and `ca.crt`; create that Secret first, or set `enabled: false` to keep plaintext in a lab.
- **Quote `powerState`.** Write `powerState: "On"` and `"Off"`: YAML 1.1, which `kubectl` uses, reads a bare `On` or `Off` as a boolean.
- **Cross-namespace references need a grant.** A `VirtualMachine` may use a Provider, VMClass or VMImage in another namespace only if that object's `spec.consumerNamespaceSelector` selects the VM's namespace; otherwise the VM reports `Ready=False` / `ConsumerNotAllowed`. A `VMClone` or `VMMigration` may create its target in another namespace only if that `Namespace` carries the `infra.virtrigaud.io/allowed-source-namespaces` annotation. [`shared-provider-consumer-namespaces.yaml`](shared-provider-consumer-namespaces.yaml) shows the first case.
- **vSphere accounts** need the `VirtualMachine.Config.AdvancedConfig` privilege: every create writes an owner stamp into the VM's ExtraConfig.

## Quick start

| File | What it shows |
|------|---------------|
| [complete-example.yaml](complete-example.yaml) | End to end on vSphere: Secret, Provider, VMClass, VMImage, VMNetworkAttachment and VirtualMachine |
| [vm-ubuntu-small.yaml](vm-ubuntu-small.yaml) | A small Ubuntu VirtualMachine (its `spec.lifecycle` block is accepted by the API but not executed in v0.4.1) |
| [vmclass-small.yaml](vmclass-small.yaml) | A VMClass (CPU, memory, disk defaults, firmware, guest-tools policy, `extraConfig`) |
| [vmimage-ubuntu.yaml](vmimage-ubuntu.yaml) | A VMImage |
| [vmnetwork-app.yaml](vmnetwork-app.yaml) | A VMNetworkAttachment |
| [vmimage-prepare-on-create.yaml](vmimage-prepare-on-create.yaml) | A libvirt VMImage with a URL source and a VirtualMachine that uses it: the provider downloads and imports the image before the VM is created (see [Image preparation](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/image-preparation.md)) |
| [cloud-init-with-metadata.yaml](cloud-init-with-metadata.yaml) | Cloud-init `userData` and `metaData` on a VirtualMachine, inline and from a Secret, and the default meta-data |

## Providers and credentials

| File | What it shows |
|------|---------------|
| [provider-vsphere.yaml](provider-vsphere.yaml) | A vSphere Provider (required vCenter privilege noted in the file) |
| [provider-libvirt.yaml](provider-libvirt.yaml) | A single-host libvirt Provider |
| [libvirt-complete-example.yaml](libvirt-complete-example.yaml) | A complete libvirt deployment, including the image-directory and seed-directory settings (`VIRTRIGAUD_LIBVIRT_IMAGE_DIRS`, `VIRTRIGAUD_LIBVIRT_SEED_DIR`) |
| [libvirt-advanced-example.yaml](libvirt-advanced-example.yaml) | A libvirt Provider with a host-resident image, a network and a VM |
| [proxmox-complete-example.yaml](proxmox-complete-example.yaml) | A complete Proxmox VE setup: credentials (including the SSH keys a VM with user-data needs since v0.4.1), Provider, classes, images, networks, VMs and snapshots |
| [multi-provider-example.yaml](multi-provider-example.yaml) | vSphere and libvirt Providers in one cluster, with shared classes |
| [shared-provider-consumer-namespaces.yaml](shared-provider-consumer-namespaces.yaml) | A Provider, VMClass and VMImage shared with other namespaces through `spec.consumerNamespaceSelector`, and a tenant VM that uses them ([cross-namespace references](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/cross-namespace-references.md)) |
| [vm-adoption-example.yaml](vm-adoption-example.yaml) | Bringing existing hypervisor VMs under management with the adoption annotations, per provider, and detaching a VM with `virtrigaud.io/orphan-on-delete` |
| [secrets/](secrets/vsphere-creds.yaml) | Credential Secrets per provider: [vSphere](secrets/vsphere-creds.yaml), [libvirt](secrets/libvirt-creds.yaml) (SSH key or password), [Proxmox](secrets/proxmox-creds.yaml) (API token or username/password, and the SSH keys for user-data and migration) |

## Clustered libvirt (experimental)

`topology: cluster` is opt-in and experimental in v0.4.1. See the [Clustered libvirt guide](../guides/clustered/index.md).

| File | What it shows |
|------|---------------|
| [provider-libvirt-clustered.yaml](provider-libvirt-clustered.yaml) | A libvirt Provider with `spec.topology: cluster`: the operator renders the `Host` objects of its namespace into a `<provider>-hosts` Secret |
| [hostpool-clustered.yaml](hostpool-clustered.yaml) | A `HostPool` and two `Host` objects, with the placement labels (`net.virtrigaud.io/<network>`, `storage.virtrigaud.io/pool-<name>`) |
| [host-libvirt-clustered-first-vm.yaml](host-libvirt-clustered-first-vm.yaml) | One `Host` labelled for the libvirt network of the first VM, with its VMNetworkAttachment. Without the label a clustered VM stays `Unschedulable` |
| [vmmigration-into-clustered.yaml](vmmigration-into-clustered.yaml) | A VMMigration into a clustered Provider: the target VM is created and placed first, the disk is imported to that host and attached in place (`s3` or `nfs` only) |

## Provider-specific and feature examples

| File | What it shows |
|------|---------------|
| [vsphere-advanced-example.yaml](vsphere-advanced-example.yaml) | A vSphere Provider with classes, networks, VMs and lifecycle settings |
| [vsphere-hardware-versions.yaml](vsphere-hardware-versions.yaml) | VM hardware version management (vSphere) |
| [vm-scsi-controllers.yaml](vm-scsi-controllers.yaml) | Disks on several SCSI controllers (vSphere only) |
| [vsphere-static-ip.yaml](vsphere-static-ip.yaml) | A static IPv4 address through `guestinfo.network.*` (vSphere; the template must contain an agent that reads the keys) |
| [disk-sizing-examples.yaml](disk-sizing-examples.yaml) | Disk sizes from the VMClass, per provider, with the cross-namespace grants the VMs need |
| [graceful-shutdown-examples.yaml](graceful-shutdown-examples.yaml) | `OffGraceful` and `Off` power states ([Graceful shutdown](../guides/advanced/graceful-shutdown.md)); the `spec.lifecycle` block is accepted but not executed |
| [libvirt-uefi-secureboot.yaml](libvirt-uefi-secureboot.yaml) | libvirt VMClasses with `firmware: UEFI` and with Secure Boot, TPM and VT-d, and a VM that uses them (the host needs an OVMF package; see [libvirt firmware](../providers/libvirt.md#firmware-secure-boot-and-platform-features)). Specific to this site: it has no counterpart in the repository's `examples/` |
| [nested-virtualization.yaml](nested-virtualization.yaml) | VMClasses and VMs with nested virtualization (see [Nested virtualization](../guides/advanced/nested-virtualization.md)) |
| [v021-feature-showcase.yaml](v021-feature-showcase.yaml) | The v0.2.1 feature set in one file (historical; kept valid against the current schema) |

## Cloning

`VMClone` clones an existing, provisioned `VirtualMachine` on the same provider. Read [VM cloning](../guides/advanced/vm-cloning.md) for the per-provider rules (a libvirt full clone needs the source powered off; libvirt linked clones are disabled).

| File | What it shows |
|------|---------------|
| [vmclone-basic.yaml](vmclone-basic.yaml) | The basic VMClone: `source.vmRef`, `target.name`, `options.type`, `options.powerOn`, and the optional cross-namespace target |
| [advanced/vsphere-clone-example.yaml](advanced/vsphere-clone-example.yaml) | Several VMs from one vSphere template, and a VMClone of an existing VM |
| [advanced/proxmox-clone-example.yaml](advanced/proxmox-clone-example.yaml) | Full and linked VMClones on Proxmox VE |

Minimal example (see `vmclone-basic.yaml` for all fields):

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClone
metadata:
  name: basic-clone
  namespace: default
spec:
  source:
    vmRef:
      name: my-source-vm      # a VirtualMachine in this namespace that is already provisioned
  target:
    name: my-cloned-vm
  options:
    type: FullClone           # or LinkedClone (vSphere, Proxmox)
    powerOn: false            # the default: the clone is left powered off
```

!!! warning "VMSet is not functional"
    `VMSet` is accepted by the API server, but its controller is a stub that sets `Ready=False` with reason `ControllerNotImplemented`. Do not use it for real workloads.

## Migration

`VMMigration` moves a VM between providers. S3 and NFS staging are the validated backends (S3 for every pair among vSphere, libvirt and Proxmox VE; NFS for all but vSphere ⇄ Proxmox VE, see the [validation tables](../migration/user-guide.md#what-virtrigaud-v040-supports)); the PVC backend is a legacy compatibility path that does not work for Proxmox or for host-resident libvirt disks. See the [Migration user guide](../migration/user-guide.md).

| File | What it shows |
|------|---------------|
| [vmmigration-s3.yaml](vmmigration-s3.yaml) | vSphere to libvirt through S3 staging (relay transfer), with the S3 credentials Secret |
| [vmmigration-proxmox-s3.yaml](vmmigration-proxmox-s3.yaml) | vSphere to Proxmox VE through S3; the same shape works for any pairing |
| [vmmigration-nfs.yaml](vmmigration-nfs.yaml) | Migration over an NFS export (`storage.nfs`, including the mandatory-in-practice `uid`/`gid`) |
| [vmmigration-basic.yaml](vmmigration-basic.yaml) | A minimal migration on the legacy PVC backend |
| [vmmigration-advanced.yaml](vmmigration-advanced.yaml) | Disk, network and option mappings (legacy PVC backend) |
| [migration/libvirt-to-vsphere.yaml](migration/libvirt-to-vsphere.yaml) | libvirt to vSphere over S3; the target needs a network attachment |
| [migration/proxmox-to-libvirt.yaml](migration/proxmox-to-libvirt.yaml) | Proxmox VE to libvirt over S3 |
| [migration/vsphere-to-proxmox.yaml](migration/vsphere-to-proxmox.yaml) | vSphere to Proxmox VE over S3 |
| [vmmigration-into-clustered.yaml](vmmigration-into-clustered.yaml) | Into a clustered libvirt Provider (experimental) |

## Advanced examples

Snapshots (including revert), reconfiguration, console access and task tracking are on the [advanced examples](advanced/index.md) page.

## Security examples

| File | What it shows |
|------|---------------|
| [security/proxmox-rbac.yaml](security/proxmox-rbac.yaml) | A ServiceAccount and minimal RBAC for a Proxmox provider pod |
| [security/proxmox-networkpolicy.yaml](security/proxmox-networkpolicy.yaml) | A NetworkPolicy that limits a Proxmox provider pod to the endpoints it needs |
| [security/proxmox-secrets.yaml](security/proxmox-secrets.yaml) | Proxmox credential Secrets (API-token and username/password forms), and an External Secrets `SecretStore` and `ExternalSecret` |
| [security/networkpolicies/strict-isolation.yaml](security/networkpolicies/strict-isolation.yaml) | Three NetworkPolicies: one for the manager pods, one for provider pods, and a default deny |
| [security/externalsecrets/vsphere-credentials.yaml](security/externalsecrets/vsphere-credentials.yaml) | An External Secrets Operator `ExternalSecret` that materializes the vSphere credentials from a secret store |

## Usage patterns

```bash
# Apply a provider, an image and a VM
kubectl apply -f examples/provider-vsphere.yaml
kubectl apply -f examples/vmimage-ubuntu.yaml
kubectl apply -f examples/vm-ubuntu-small.yaml

# Watch the VM: PHASE comes from status.phase; read the Ready condition with the jsonpath below
kubectl get vm my-vm -w

# Why is it not Ready?
kubectl get vm my-vm -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'

# Console URL
kubectl get vm my-vm -o jsonpath='{.status.consoleURL}'

# Resize: change the class
kubectl patch virtualmachine my-vm --type=merge \
  -p '{"spec":{"classRef":{"name":"medium"}}}'
```

The examples are files in this site's source tree; download the ones you need, or take them from the `examples/` directory of the [repository](https://github.com/projectbeskar/virtrigaud/tree/v0.4.1/examples).

## File organization

```
examples/
├── index.md                              # This page
├── complete-example.yaml  vm-ubuntu-small.yaml  vmclass-small.yaml
├── vmimage-ubuntu.yaml  vmimage-prepare-on-create.yaml  vmnetwork-app.yaml
├── provider-vsphere.yaml  provider-libvirt.yaml  provider-libvirt-clustered.yaml
├── hostpool-clustered.yaml  host-libvirt-clustered-first-vm.yaml
├── shared-provider-consumer-namespaces.yaml  vm-adoption-example.yaml
├── vsphere-advanced-example.yaml  vsphere-hardware-versions.yaml  vsphere-static-ip.yaml
├── libvirt-complete-example.yaml  libvirt-advanced-example.yaml
├── proxmox-complete-example.yaml  multi-provider-example.yaml
├── graceful-shutdown-examples.yaml  disk-sizing-examples.yaml
├── cloud-init-with-metadata.yaml  vm-scsi-controllers.yaml
├── nested-virtualization.yaml  v021-feature-showcase.yaml
├── vmclone-basic.yaml
├── vmmigration-{basic,advanced,s3,proxmox-s3,nfs,into-clustered}.yaml
├── advanced/                             # Snapshots, reconfigure, clones, console, task tracking
├── migration/                            # Cross-provider migrations over S3
├── secrets/                              # Per-provider credential Secrets
└── security/                             # RBAC, NetworkPolicy, ExternalSecret
```

## Version compatibility

- **v0.4.1**: every example here is valid against the v0.4.1 CRDs.
- **v0.3.x**: most examples apply unchanged, but several fields and behaviours differ (for example `VMClone` on libvirt, S3 and NFS migration, `consumerNamespaceSelector`). Use the examples of the matching release.
- **v0.2.x and older**: not supported.

## See also

- [Getting started](../getting-started/index.md)
- [CLI tools reference](../references/cli-tools.md)
- [CRD reference](../references/crds.md)
- [Upgrade guide](../operations/upgrade.md)
