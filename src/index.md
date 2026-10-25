<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VirtRigaud Documentation

Welcome to the VirtRigaud documentation. VirtRigaud is a Kubernetes operator for managing virtual machines across multiple hypervisors — VMware vSphere, Libvirt/KVM, and Proxmox VE — through a single declarative API.

## What VirtRigaud is

VirtRigaud lets you declare VMs the same way you declare Deployments. A `VirtualMachine` custom resource describes the desired VM (size, image, networks, disks, power state); a small set of controllers in the manager reconcile that desire against whichever hypervisor backs the namespace's `Provider`.

Hypervisor-specific logic does **not** run inside the manager. Each provider runs as its own gRPC server pod, and the manager talks to it over a stable proto contract (`proto/provider/v1/provider.proto`). This isolates hypervisor failures, lets providers be upgraded independently, and means a misbehaving provider cannot crash the rest of the operator.

## Architecture at a glance

```
                          ┌────────────────────────┐
                          │   Kubernetes API       │
                          │  VirtualMachine,       │
                          │  Provider, VMClass,    │
                          │  VMImage, VMNetwork-   │
                          │  Attachment, VM-       │
                          │  Snapshot, VMMigration,│
                          │  VMClone, VMSet,       │
                          │  VMPlacementPolicy,    │
                          │  Host, HostPool        │
                          └───────────┬────────────┘
                                      │ watch / status
                          ┌───────────▼────────────┐
                          │   virtrigaud-manager   │
                          │  (12 reconcilers)      │
                          │                        │
                          │  per-RPC interceptors: │
                          │   1. request-sent      │
                          │   2. metrics           │
                          │   3. CircuitBreaker    │
                          └───────────┬────────────┘
                                      │ gRPC (mTLS)
        ┌─────────────────────────────┼─────────────────────────────┐
        │                             │                             │
┌───────▼──────┐             ┌────────▼─────────┐          ┌────────▼────────┐
│ provider-    │             │ provider-        │          │ provider-       │
│ vsphere      │             │ libvirt          │          │ proxmox         │
│ (govmomi)    │             │ (SSH + virsh,    │          │ (REST API)      │
│              │             │  single host or  │          │                 │
│              │             │  clustered)      │          │                 │
└──────────────┘             └──────────────────┘          └─────────────────┘
        │                             │                             │
   vCenter / ESXi              KVM / QEMU host(s)             Proxmox VE host
```

One manager binary, one manager Dockerfile (consolidated in v0.3.6), and one gRPC client per Provider CR. Each outbound RPC passes through three unary client interceptors: a request-sent interceptor (tells a call that never left the manager from one whose outcome is unknown), a metrics interceptor (per-RPC latency and status-code counter) and a CircuitBreaker interceptor (one breaker per Provider CR). Provider connections require mTLS unless the Provider CR explicitly opts out.

## Quick Navigation

### Getting Started
- [15-Minute Quickstart](getting-started/index.md) - Get up and running quickly
- [Installation Guide](getting-started/install-helm-only.md) - Helm installation instructions
- [Basic VM Example](getting-started/basic-vm-example.md) - Create your first VM
- [Helm CRD Upgrades](getting-started/helm-crd-upgrades.md) - Managing CRD updates

### Guides
- [Provider Guides](guides/index.md) - Overview and provider setup
- [Provider Capabilities Matrix](providers/providers-capabilities.md) - Feature comparison
- [Advanced Topics](guides/advanced/advanced-lifecycle.md) - Advanced VM operations

### Provider-Specific Guides
- [vSphere Provider](providers/vsphere.md) - VMware vCenter/ESXi integration
- [Libvirt Provider](providers/libvirt.md) - KVM/QEMU virtualization
- [Proxmox VE Provider](providers/proxmox.md) - Proxmox Virtual Environment
- [Provider Tutorial](providers/tutorial.md) - Build your own provider
- [Provider Versioning](providers/versioning.md) - Version management

### Advanced Topics
- [VM Lifecycle Management](guides/advanced/advanced-lifecycle.md) - Advanced VM operations
- [Nested Virtualization](guides/advanced/nested-virtualization.md) - Run hypervisors in VMs
- [Graceful Shutdown](guides/advanced/graceful-shutdown.md) - Proper VM shutdown handling
- [VM Snapshots](guides/advanced/advanced-lifecycle.md#snapshot-management) - Backup and restore
- [Remote Providers](guides/advanced/remote-providers.md) - Provider architecture

### Operations
- [Overview](operations/index.md) - Operations guide
- [Observability](operations/observability.md) - Monitoring and metrics
- [Security](operations/security.md) - Security best practices
- [Resilience](operations/resilience.md) - High availability and fault tolerance
- [Upgrade Guide](operations/upgrade.md) - Version upgrade procedures
- [vSphere Hardware Versions](operations/vsphere-hardware-version.md) - Hardware compatibility

### Security Configuration
- [Bearer Token Authentication](providers/security/bearer-token.md)
- [mTLS Configuration](providers/security/mtls.md)
- [External Secrets](providers/security/external-secrets.md)
- [Network Policies](providers/security/network-policies.md)

### References
- [Custom Resource Definitions](references/crds.md) - Complete API reference
- [CLI Tools Reference](references/cli-tools.md) - Command-line interface guide
- [CLI API Reference](api-reference/cli.md) - Detailed CLI documentation
- [Metrics Catalog](api-reference/metrics.md) - Available metrics
- [Provider Catalog](references/catalog.md) - Available providers
- [Full CRD Reference](references/generated-crd-docs.md) - Generated field-level schema
- [Provider gRPC API](references/grpc-api.md) - Manager-to-provider contract

### Development
- [Overview](development/index.md) - Development guide
- [Building Locally](development/building-locally.md) - Build from source
- [Contributing Guide](development/contributing.md) - Contribution guidelines
- [Testing Locally](development/testing-locally.md) - Local testing

### Examples Directory
- [Example README](examples/index.md) - Overview of all examples
- [Complete Examples](examples/) - Working configuration files
- [Advanced Examples](examples/advanced/) - Complex scenarios
- [Security Examples](examples/security/) - Security configurations

## Custom Resources

VirtRigaud v0.4.0 ships **12 Custom Resource Definitions** in the `infra.virtrigaud.io/v1beta1` API group:

| Kind | Purpose |
|---|---|
| `VirtualMachine` | Desired state of a single VM (image, class, networks, disks, power state). `spec.snapshot.revertToRef` reverts it to a `VMSnapshot`. |
| `Provider` | Connection details for a hypervisor (vSphere / Libvirt / Proxmox) and its provider-server Deployment. `spec.topology: cluster` (libvirt only) fronts several hosts; `spec.consumerNamespaceSelector` shares it with other namespaces. |
| `VMClass` | Reusable sizing template (CPU, memory, firmware). Can be shared with other namespaces through `spec.consumerNamespaceSelector`. |
| `VMImage` | Reference to a hypervisor template / OVA / cloud image. Can be shared with other namespaces through `spec.consumerNamespaceSelector`. |
| `VMNetworkAttachment` | Logical network the VM attaches to (resolved per-provider). |
| `VMSnapshot` | A point-in-time snapshot of a VirtualMachine. |
| `VMMigration` | Inter-provider VM migration (export → import) through S3 or NFS staging. |
| `VMSet` | Replica-set of identical VMs. CRD available; controller stub only — `Ready=False/ControllerNotImplemented` in v0.4.0. |
| `VMPlacementPolicy` | Placement / anti-affinity rules. Applied via `VirtualMachine.spec.placementRef`; the clustered libvirt scheduler uses it as its constraint language. There is no standalone controller. |
| `VMClone` | One-shot clone of an existing VM (vSphere, Proxmox and Libvirt). libvirt supports full clones only; linked clones are not supported there. |
| `Host` | One hypervisor host behind a clustered libvirt Provider, with its live capacity and health in `status`. |
| `HostPool` | A group of `Host`s under one clustered Provider, with scheduling strategy and overcommit policy. `status` counts total, ready and schedulable hosts. |

The manager also runs a `VMAdoption` reconciler (not a CRD — it reconciles `Provider` resources annotated with `virtrigaud.io/adopt-vms: "true"`, discovers VMs the hypervisor already owns, and creates `VirtualMachine` CRs labelled `virtrigaud.io/adopted=true` for them, plus an `adopted-Ncpu-Nmb` `VMClass` per unique sizing). Adoption skips templates and image artifacts, and, since v0.4.0, VMs whose owner stamp names no `VirtualMachine` in this cluster. See the [generated CRD reference](references/generated-crd-docs.md) for the full schema.

## Version Information

This documentation covers **VirtRigaud v0.4.0**.

!!! warning "Upgrading from v0.3.11"
    v0.4.0 is a security-hardening release with breaking changes (cross-namespace references need a grant, `spec.providerRef` is immutable once bound, vSphere needs a new vCenter privilege, libvirt hosts need a seed directory, and more). Read the [Upgrade Guide](operations/upgrade.md) and [Helm CRD Upgrades](getting-started/helm-crd-upgrades.md) before upgrading.

### Recent Releases

- **v0.4.0** — *Security hardening, clustered libvirt providers and snapshot revert.*
    - **Clustered libvirt providers (experimental, opt-in).** `Provider.spec.topology: cluster` fronts several libvirt hosts registered as `Host` resources in a `HostPool`. A placement scheduler (using `VMPlacementPolicy`) picks a host per VM, and every later call is routed to that VM's host and checked against its owner stamp. Create, describe, delete, power, reconfigure, snapshot, full clone and S3/NFS export work across hosts; a `VMMigration` can target a clustered Provider. Host-to-host migration is not implemented. A clustered Provider runs one replica, so a rollout is a short outage.
    - **Snapshot revert.** `VirtualMachine.spec.snapshot.revertToRef` now reverts the VM (before, the field was accepted and ignored). The VM must be powered off; progress is in `status.snapshotRevert` and the `SnapshotReverted` condition. On libvirt a revert needs a snapshot taken with the VM powered off.
    - **Security hardening.** VM ownership stamps and fail-closed ownership checks on vSphere, libvirt and Proxmox; cross-namespace `Provider`/`VMClass`/`VMImage` references need `spec.consumerNamespaceSelector`; cross-namespace clone and migration targets need a grant; a `ValidatingAdmissionPolicy` (Kubernetes 1.30+) reserves the manager-owned annotations; a `Provider` that is still in use is not deleted from under its VMs (ADR-0010); identity-safe image preparation (ADR-0009); private libvirt cloud-init seeds; a `VMMigration` acts only on the target VM it created; pod `/tmp` size limits; an opt-in administrator disk-size limit (`manager.maxDiskSize`); shell-quoted and XML-escaped libvirt commands and definitions.
    - **Behaviour changes.** `spec.providerRef` is immutable once a VM is bound (use `virtrigaud.io/orphan-on-delete: "true"` to detach); a libvirt VM without `spec.userData` gets no default login; libvirt linked clones are disabled; `powerOn` on `VMClone` and `VMMigration` is honored (default `false`); libvirt `Reconfigure` reports a change that needs a restart as such (`Reconfiguring=True/RestartRequired`); `status.ips` lists only reachable addresses; `status.phase` is set on every VM.
    - **Proxmox.** The bridge, VLAN tag, NIC model and static IP of a VM's networks are applied; the cloud-init drive is placed on the VM's disk storage; imports of a migrated disk are accepted only from the VM's own verified migration stage.
    - **Operations.** A provider call whose outcome is unknown is held for an operator instead of being re-sent blindly (`SnapshotOutcomeUnknown`, `ExportOutcomeUnknown`, `ImportOutcomeUnknown`); a delete held for an unreachable clustered host says so (`DeleteBlocked`/`HostUnreachable`); new metrics `virtrigaud_host_committed_cpu` and `virtrigaud_host_committed_memory_mib`; the gRPC contract gains host inventory (`ListHosts`, `GetHostInfo`), `TransferOwner`, `DeleteStagedDisk` and `DeleteLandedDisk` (see [Provider gRPC API](references/grpc-api.md)).
- **v0.3.11** — *NFS cross-hypervisor migration staging backend (ADR-0006 Slice 4).*
    - **Second storage-agnostic `VMMigration` backend: NFS (#236).** Alongside the S3 backend, the disk can now be staged on an **NFS export** and moved with `qemu-img`'s native transport — no PVC, no relay, no S3 credentials. Lab-validated across all three providers (vSphere, libvirt, Proxmox VE) in **both directions** against a real OpenMediaVault server.
    - **Per-provider NFS transport.** libvirt (host-side) and vSphere (pod-side) use qemu-img's `nfs://` libnfs driver; **Proxmox kernel-mounts** the export because `pve-qemu-kvm` ships no libnfs driver.
    - **`nfs.uid` / `nfs.gid` are effectively mandatory for cross-provider migrations** (AUTH_SYS authorizes by the numeric uid/gid each leg presents); set them to the export owner. The staged object is a single flat file in the export root.
    - **Proxmox now advertises `s3` *and* `nfs`** (not PVC: its disks live on the node, unreachable by a pod-mounted PVC). The full 3-hypervisor matrix is now validated in both directions over **both** staging backends. See the [VM Migration User Guide](migration/user-guide.md).
- **v0.3.9** — *Libvirt online operations + clone + image-prepare + memory snapshots on all three providers.*
    - **Libvirt online CPU/memory reconfigure (#203).** `virsh setvcpus/setmem --live` with no power-cycle for VMs created with `cpuHotAddEnabled`/`memoryHotAddEnabled` on the VMClass (4× headroom, 64-vCPU cap). Lab-proven.
    - **Libvirt online disk expansion (#201).** `virsh blockresize` + best-effort in-guest FS grow. Grow-only; no power-cycle. Lab-proven.
    - **Libvirt memory snapshots (#202).** RAM-inclusive checkpoints on running VMs. Stopped VM downgrades to disk-only with a WARN.
    - **Libvirt clone (#153) + clone hardening (#208/#221).** Full and linked (qcow2 overlay) clones, same-provider. UEFI nvram re-pointed per clone; hot-add headroom preserved across class-override clones.
    - **End-to-end image preparation (#154).** `VMImage.spec.prepare` drives lazy VM-create-time image import on libvirt, vSphere (OVA/OVF), and Proxmox. `prepare.onMissing: Fail` holds VM creation with `WaitingForDependencies` until the image is ready.
    - **Proxmox export compression (#219).** `ExportDisk` honors `Compress` for qcow2 targets.
    - **Memory snapshots on all three providers.** vSphere (#200): `CreateSnapshot(memory=true)`; libvirt (#202): `snapshot-create-as`; Proxmox: PVE-native.
- **v0.3.8** — *VMClone MVP + VMSet stub + secure-by-default chart.*
    - **VMClone controller (MVP).** Full and linked clones functional via `VMClone` CRD (vSphere and Proxmox; libvirt added in v0.3.9).
    - **VMSet: CRD defined, controller not yet active.** A `VMSet` resource is accepted but emits `Ready=False / Reason=ControllerNotImplemented`.
    - **Chart (#173): providers disabled by default.** Opt-in via `providers.<type>.enabled=true`.
- **v0.3.7** — mTLS enforcement, multi-arch images, circuit-breaker metrics.
- **v0.3.6** — Observability + supply-chain release (CircuitBreaker, G7 metrics, H1 build consolidation, Go 1.26 floor, OTel CVE fixes).
- **v0.3.5** — Observability G-track foundation (RPC metrics, error counters, reconcile metrics).
- **v0.3.3** — Changelog organisation with versioned release headers.
- **v0.2.3** — Provider feature parity: Reconfigure, Clone, TaskStatus, ConsoleURL.

See [CHANGELOG.md](https://github.com/projectbeskar/virtrigaud/blob/main/CHANGELOG.md) for the complete version history.

## Provider Status

| Provider | Status | Maturity | Documentation |
|----------|--------|----------|---------------|
| vSphere | Production Ready | Stable | [Guide](providers/vsphere.md) |
| Libvirt/KVM (single host) | Production Ready | Stable | [Guide](providers/libvirt.md) |
| Libvirt/KVM (clustered, `topology: cluster`) | Opt-in | Experimental | [Guide](providers/libvirt.md) |
| Proxmox VE | Production Ready | Beta | [Guide](providers/proxmox.md) |
| Mock | Complete | Testing | [providers/tutorial.md](providers/tutorial.md) |

## Support

- **GitHub Issues**: [github.com/projectbeskar/virtrigaud/issues](https://github.com/projectbeskar/virtrigaud/issues)
- **Discussions**: [github.com/projectbeskar/virtrigaud/discussions](https://github.com/projectbeskar/virtrigaud/discussions)

## Quick Links

- [Main README](https://github.com/projectbeskar/virtrigaud#readme) - Project overview
- [CHANGELOG](https://github.com/projectbeskar/virtrigaud/blob/main/CHANGELOG.md) - Version history
- [Contributing](https://github.com/projectbeskar/virtrigaud/blob/main/CONTRIBUTING.md) - How to contribute
- [License](https://github.com/projectbeskar/virtrigaud/blob/main/LICENSE) - Apache License 2.0
