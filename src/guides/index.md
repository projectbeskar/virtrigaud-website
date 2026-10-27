<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VirtRigaud Guides

This section holds the guides for working with VirtRigaud **v0.4.1**: setting up providers, running a clustered libvirt Provider, and the advanced lifecycle topics (snapshots and revert, reconfiguration, cloning, graceful shutdown, nested virtualization, provider internals).

## What is a Provider?

A **Provider** is VirtRigaud's connection to your hypervisor infrastructure. It bridges Kubernetes and your virtualization platform (vSphere, libvirt/KVM or Proxmox VE), translating Kubernetes resources into virtual machines. Each provider:

- authenticates with the hypervisor with the credentials you give it;
- translates VirtRigaud resources into platform-specific operations;
- manages the VM lifecycle (create, delete, power, reconfigure, snapshot, clone, image preparation);
- reports VM status back to Kubernetes.

## Provider architecture

Each `Provider` resource gets its own provider pod, created and managed by the manager. The manager talks to it over **gRPC with mutual TLS**, which is on by default since v0.3.7: a Provider must carry an explicit `runtime.service.tls` decision or it is not deployed.

```
┌─────────────────────────────────────────┐
│         Kubernetes cluster              │
│  ┌──────────────────────────────────┐   │
│  │   VirtRigaud manager             │   │
│  │   (controllers)                  │   │
│  └─────────┬────────────────────────┘   │
│            │ gRPC over mTLS             │
│  ┌─────────▼────────────────────────┐   │
│  │   Provider pod                   │   │
│  │   (vSphere / libvirt / Proxmox)  │   │
│  └─────────┬────────────────────────┘   │
└────────────┼────────────────────────────┘
             │ hypervisor API / SSH
        ┌────▼─────┐
        │Hypervisor│
        └──────────┘
```

- **Isolation:** a provider failure does not crash the manager, and provider pods run without a Kubernetes API token.
- **Credentials:** hypervisor credentials are mounted into the provider pod only.
- **Independent rollout:** providers are pinned by `spec.runtime.image`; keep them on the same release as the manager.

See [Provider Architecture](advanced/remote-providers.md) for the details.

## Supported providers

| Provider | Setup guide | Notes |
|----------|-------------|-------|
| **vSphere** | [vSphere provider](../providers/vsphere.md) | VMware vSphere through govmomi |
| **libvirt** | [Libvirt provider](../providers/libvirt.md) | KVM/QEMU over SSH; single host, or a [clustered Provider](clustered/index.md) (experimental) |
| **Proxmox VE** | [Proxmox provider](../providers/proxmox.md) | PVE REST API plus SSH for disk transfer |

Each setup guide covers prerequisites, credentials, the Provider configuration, a first VM and troubleshooting. Not all providers support the same features: see the [Provider capabilities matrix](../providers/providers-capabilities.md) for the authoritative comparison.

## Guides in this section

| Guide | Covers |
|-------|--------|
| [Clustered libvirt](clustered/index.md) | `topology: cluster`: one Provider in front of several libvirt hosts, with `Host` and `HostPool`, a placement scheduler and routed per-host lifecycle (experimental in v0.4.1). Continues with [placement](clustered/placement.md), [operations and troubleshooting](clustered/operations.md) and [backup, restore and re-attach](clustered/backup-restore.md) |
| [VM snapshots and revert](vm-snapshots.md) | `VMSnapshot`, `spec.snapshot.revertToRef`, `status.snapshotRevert`, the `SnapshotReverted` condition, and the per-provider rules |
| [VM status reference](vm-status.md) | Phases, conditions and their reasons, `status.ips`, and how to read and release a held (outcome unknown) provider call |
| [Security model and multi-tenancy](security-model.md) | VM ownership, cross-namespace references, admission policy, the Provider in-use finalizer, identity-safe image preparation, private cloud-init seeds, migration storage, the disk-size limit, and what to check on upgrade |
| [Advanced VM lifecycle](advanced/advanced-lifecycle.md) | Phases and conditions, reconfiguration results (`RestartRequired`, `ResizePendingPowerOff`), snapshots and `spec.snapshot.revertToRef`, `spec.disks` and `DisksApplied`, `status.ips`, image preparation, `orphan-on-delete`, adoption, `providerRef` immutability |
| [VM cloning](advanced/vm-cloning.md) | `VMClone`: scope, per-provider rules (libvirt full clones need a powered-off source; libvirt linked clones are disabled), new cloud-init identity, owner stamping, cross-namespace targets |
| [Graceful shutdown](advanced/graceful-shutdown.md) | `powerState: OffGraceful`: what each provider does and how it falls back |
| [Nested virtualization](advanced/nested-virtualization.md) | `performanceProfile.nestedVirtualization`: what vSphere and libvirt apply, and that Proxmox ignores it |
| [Provider architecture](advanced/remote-providers.md) | What the manager creates for a Provider, TLS, `consumerNamespaceSelector`, `topology`, the in-use finalizer, security model |

## Multi-provider deployments

VirtRigaud manages several providers at once; each VM picks its provider with `spec.providerRef`:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: vsphere-prod
  namespace: virtrigaud-system
spec:
  type: vsphere
  # endpoint, credentialSecretRef, runtime (image, service.tls) ...
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: libvirt-dev
  namespace: virtrigaud-system
spec:
  type: libvirt
  # endpoint, credentialSecretRef, runtime ...
```

A VM may use a Provider, VMClass or VMImage in another namespace only if that object's `spec.consumerNamespaceSelector` selects the VM's namespace (see [Provider architecture](advanced/remote-providers.md#sharing-a-provider-with-other-namespaces-consumernamespaceselector)). A complete multi-provider file is in the [examples](../examples/index.md).

## Developing custom providers

- [Provider development tutorial](../providers/tutorial.md)
- [Provider versioning](../providers/versioning.md)

## Security considerations

- **Credentials:** use Kubernetes Secrets, never inline credentials; consider the [External Secrets Operator](../providers/security/external-secrets.md).
- **TLS:** every Provider needs a `runtime.service.tls` block. Use `tls.enabled: true` with a Secret (`tls.crt`, `tls.key`, `ca.crt`); `enabled: false` is a plaintext opt-out for labs and is reported as `TLSConfigured=False` / `ExplicitlyDisabled`.
- **Least privilege:** give the hypervisor account only the privileges VirtRigaud needs (on vSphere this includes `VirtualMachine.Config.AdvancedConfig`, because every create writes an owner stamp).
- **Tenants:** `create` on `vmclones` is read access to the source VM's data; sharing a Provider with another namespace shares everything its credentials can reach. The [Security model](security-model.md) explains what is enforced and where.
- **Network:** restrict who can reach provider pods with the chart's `networkPolicy.*` (opt-in); see [Network Policies](../providers/security/network-policies.md).

See the [Security guide](../operations/security.md) for the full recommendations.

## Getting help

- [Provider documentation](../providers/vsphere.md): [vSphere](../providers/vsphere.md), [Libvirt](../providers/libvirt.md), [Proxmox](../providers/proxmox.md)
- [Troubleshooting](../getting-started/index.md#troubleshooting)
- [Examples](../examples/index.md): working configurations, validated against the v0.4.1 CRDs
- [GitHub issues](https://github.com/projectbeskar/virtrigaud/issues)

## Next steps

1. Choose your provider and follow its setup guide.
2. Create your [first VM](../getting-started/basic-vm-example.md).
3. Explore [advanced lifecycle features](advanced/advanced-lifecycle.md), [snapshots and revert](vm-snapshots.md) and the [VM status reference](vm-status.md).
4. Before sharing a Provider across namespaces or running multiple tenants, read the [Security model](security-model.md).
