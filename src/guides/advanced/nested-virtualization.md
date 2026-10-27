<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Nested Virtualization Support

!!! note "Provider support differs, and none of it is covered by end-to-end tests"
    The VMClass field `spec.performanceProfile.nestedVirtualization` exists in the API. In v0.4.1 it is **applied by the vSphere and libvirt providers and ignored by the Proxmox provider** (see [the support table](#what-each-provider-does)). On libvirt it never worked before v0.4.1: the VM required both `vmx` and `svm`, so it did not start. VirtRigaud does not run end-to-end nested-virtualization scenarios (a guest that runs its own VMs) in CI or in its lab validation; on libvirt the lab checked that the domain is defined and starts. If you need it for a production workload, validate the configuration on your own hosts first.

## Overview

Nested virtualization lets a virtual machine run a hypervisor and its own virtual machines. It is useful for developing virtualization software, running Kubernetes or lab environments inside VMs, and training.

VirtRigaud exposes it through the `performanceProfile` of a `VMClass`. Every VM created from the class gets the setting; there is no per-VM switch.

## Prerequisites

These are requirements of the hypervisors, not checks VirtRigaud performs.

### vSphere

- An ESXi host with VT-x or AMD-V enabled in the BIOS.
- VM hardware version 9 or later (14 or later recommended). Set it with the `vsphere.hardwareVersion` key in the VMClass `extraConfig` (see [vSphere hardware version](../../operations/vsphere-hardware-version.md)).

### libvirt

- A KVM host whose CPU has VT-x or AMD-V, with nested virtualization enabled in the host kernel module (`kvm_intel nested=1` or `kvm_amd nested=1`; `cat /sys/module/kvm_intel/parameters/nested` prints `Y` or `1`).

### Proxmox VE

- A host CPU with nested virtualization support, enabled on the host.
- The VM's CPU type set to `host` (or a model that exposes `vmx`/`svm`). **VirtRigaud does not set the CPU type**: configure it on the template or the VM in Proxmox.

## Enabling nested virtualization

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: nested-vm-class
  namespace: default
spec:
  cpu: 4
  memory: 8Gi
  firmware: UEFI

  performanceProfile:
    nestedVirtualization: true
    virtualizationBasedSecurity: false   # may conflict with a nested hypervisor
    memoryHotAddEnabled: true

  securityProfile:
    secureBoot: false                    # may interfere with some nested hypervisors
    tpmEnabled: false
    vtdEnabled: true                     # expose an IOMMU to the guest

  diskDefaults:
    type: thin
    size: 100Gi                          # room for the nested VMs
```

!!! warning "Leave CPU hot-add off on vSphere"
    The vSphere provider skips `cpuHotAddEnabled` for a class that enables nested virtualization (CPU hot-add and nested virtualization are incompatible on vSphere) and logs a warning. Memory hot-add is applied. The complete example in the repository, [`nested-virtualization.yaml`](../../examples/nested-virtualization.yaml), sets `cpuHotAddEnabled: true` in one class; on vSphere that flag is ignored, on libvirt it provisions vCPU headroom.

## What each provider does

| `VMClass` field | vSphere | libvirt | Proxmox |
|-----------------|---------|---------|---------|
| `performanceProfile.nestedVirtualization` | Sets the `vhv.enable` and `vhv.allowNestedPageTables` ExtraConfig keys to `TRUE` at create | Gives the VM the host CPU (`<cpu mode='host-passthrough'>`), so the guest sees the host's VT-x or AMD-V (v0.4.1; it did not start before) | **Ignored** |
| `performanceProfile.virtualizationBasedSecurity` | Sets `vbs.enable` | Not applied | Ignored |
| `performanceProfile.cpuHotAddEnabled`, `memoryHotAddEnabled` | Applied (CPU hot-add skipped when nested virtualization is on) | Provision hot-plug headroom at create (see [Advanced VM lifecycle](advanced-lifecycle.md#per-provider)) | Ignored |
| `securityProfile.vtdEnabled` | Sets `vvtd.enable` | q35 machine with an emulated Intel IOMMU (v0.4.1; libvirt refused the old XML) | Ignored |
| `securityProfile.secureBoot`, `tpmEnabled` | Applied; forces UEFI firmware | Applied (secure boot uses the `q35` machine and OVMF with keys enrolled, and works since v0.4.1; the host needs an OVMF package; TPM adds an emulated TPM 2.0 and needs `swtpm`). `firmware: UEFI` is honoured since v0.4.1 | Ignored |
| `performanceProfile.latencySensitivity`, `hyperThreadingPolicy`, `resourceLimits` | Not applied | Not applied | Not applied |

!!! note "libvirt: what changed in v0.4.1"
    In v0.4.0 the libvirt provider added `vmx` and `svm` to the CPU as **required** features. A host CPU exposes only one of them (Intel `vmx`, AMD `svm`), so such a VM failed to start ("Host CPU does not provide required features"). It now uses `host-passthrough`, and the guest sees whatever the host CPU offers, provided nesting is enabled in the host's KVM module. VT-d, secure boot and `firmware: UEFI` also work now, on the `q35` machine type, and `firmware: UEFI` is honoured where it was ignored: see [libvirt: firmware, secure boot and platform features](../../providers/libvirt.md#firmware-secure-boot-and-platform-features) and check your VMClasses before you roll the libvirt provider. A VM that was created by v0.4.0 is not redefined.

## Complete example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: hypervisor-class
  namespace: default
spec:
  cpu: 8
  memory: 16Gi
  firmware: UEFI
  performanceProfile:
    nestedVirtualization: true
    memoryHotAddEnabled: true
  securityProfile:
    secureBoot: false
    vtdEnabled: true
  diskDefaults:
    type: thin
    size: 200Gi
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-server-22-04
  namespace: default
spec:
  source:
    libvirt:
      url: "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
      format: qcow2
      checksum: "sha256:REPLACE_WITH_REAL_SHA256"
      checksumType: sha256
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: nested-hypervisor
  namespace: default
spec:
  providerRef:
    name: my-provider
  classRef:
    name: hypervisor-class
  imageRef:
    name: ubuntu-server-22-04
  powerState: "On"
  userData:
    cloudInit:
      inline: |
        #cloud-config
        hostname: nested-hypervisor
        users:
          - name: ubuntu
            sudo: ALL=(ALL) NOPASSWD:ALL
            ssh_authorized_keys:
              - ssh-ed25519 AAAA... # your SSH key
        packages:
          - qemu-kvm
          - libvirt-daemon-system
          - libvirt-clients
        runcmd:
          - grep -E "(vmx|svm)" /proc/cpuinfo
          - ls -la /dev/kvm
```

The `VMImage` source above is a libvirt URL source; on vSphere or Proxmox use a template source (`source.vsphere.templateName`, or `source.proxmox.templateID`, the VMID of an existing Proxmox template).

## Provider details

### vSphere

At create, a VM from a nested class gets `vhv.enable = TRUE` and `vhv.allowNestedPageTables = TRUE` in its ExtraConfig. Consider hardware version 14 or later, UEFI firmware for modern guests, and enough CPU and memory for the nested VMs. A running VM's settings are not changed by editing the class afterwards: the keys are written at create.

### libvirt

The domain XML gets the host CPU:

```xml
<cpu mode='host-passthrough' check='none'/>
```

With `host-passthrough` the guest sees the host CPU model and its flags, including `vmx` or `svm`. Anyone who can edit a VMClass can turn nesting on; set the KVM module's `nested` parameter to `0` on hosts that must not run nested guests. With `vtdEnabled: true` the domain also gets an emulated Intel IOMMU on the `q35` machine type (the virtio devices do not go through it, so it is not DMA isolation of those devices). The host needs the `kvm_intel`/`kvm_amd` module loaded with `nested=1` (`cat /sys/module/kvm_intel/parameters/nested` prints `Y` or `1`).

### Proxmox VE

Nothing is done for `nestedVirtualization`. For a VM cloned from a template, the CPU type of the template is kept; set it to `host` there. VirtRigaud does not change a Proxmox VM's CPU type, `kvm` or NUMA settings.

## Verification

Inside a Linux guest:

```bash
grep -E "(vmx|svm)" /proc/cpuinfo      # virtualization extensions visible
ls -la /dev/kvm                        # KVM device present
virt-host-validate                     # needs libvirt-clients in the guest
```

On a Windows guest, `systeminfo | findstr /i hyper` reports whether the hypervisor requirements are met.

## Performance and operations

- Give a nested host generous CPU and memory (minimum 4 vCPUs and 8 GiB, more is better), fast storage and enough disk for the nested VMs. Disk size limits set by the administrator (`manager.maxDiskSize`) apply to the class's disk.
- On vSphere, memory hot-add can be enabled for flexibility; CPU hot-add cannot be combined with nested virtualization.
- Nested VMs add attack surface: isolate the network of nested environments, set quotas, and keep the host and guest hypervisors patched.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| The guest does not show `vmx`/`svm` | The host CPU and BIOS support virtualization; the host module has `nested=1` (libvirt); the VMClass has `nestedVirtualization: true` **and the VM was created after that** (the setting is applied at create); on vSphere the hardware version is 9 or later; on Proxmox the VM's CPU type is `host` (VirtRigaud does not set it) |
| A libvirt VM does not start after enabling nested virtualization | The host's KVM module has nesting off, or libvirt refused the definition (the VM shows `Ready=False/ValidationError` with libvirt's reason and is re-checked with a backoff). A VM created by v0.4.0 required both `vmx` and `svm` and never started: delete it and create it again |
| Poor performance in nested VMs | More CPU and memory, faster storage; on vSphere check the nested page-table setting is present |
| The class is accepted but nothing changed on Proxmox | Expected: the Proxmox provider ignores `performanceProfile` |

## Limitations

- The vSphere and libvirt settings are applied at create only; they are not retrofitted to existing VMs.
- Proxmox: no support in the provider (configure the CPU type outside VirtRigaud).
- libvirt: x86_64 only. Which flags the guest sees depends on the host CPU.
- Nested virtualization carries a performance cost that depends on the workload, and some hypervisor features are unavailable in nested guests.
- Not covered by VirtRigaud's end-to-end tests.

## Support matrix

| Provider | Applied by VirtRigaud | Host requirement | Notes |
|----------|----------------------|------------------|-------|
| vSphere | Yes (`vhv.enable`, `vhv.allowNestedPageTables`) | Hardware version 9+ (14+ recommended) | CPU hot-add is skipped for nested classes |
| libvirt | Yes (`host-passthrough` CPU, since v0.4.1) | `kvm_intel nested=1` or `kvm_amd nested=1` | The domain is defined and starts in the lab (libvirt 10.0); no nested guest was run |
| Proxmox VE | No | CPU type `host`, set outside VirtRigaud | `performanceProfile` is ignored |

For provider details see the [vSphere](../../providers/vsphere.md), [libvirt](../../providers/libvirt.md) and [Proxmox](../../providers/proxmox.md) provider pages.
