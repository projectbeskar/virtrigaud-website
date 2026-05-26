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
                          │  Snapshot, VMMigration │
                          └───────────┬────────────┘
                                      │ watch / status
                          ┌───────────▼────────────┐
                          │   virtrigaud-manager   │
                          │  (8 reconcilers)       │
                          │                        │
                          │  per-RPC interceptors: │
                          │   1. metrics (G4)      │
                          │   2. CircuitBreaker(G6)│
                          └───────────┬────────────┘
                                      │ gRPC (mTLS optional)
        ┌─────────────────────────────┼─────────────────────────────┐
        │                             │                             │
┌───────▼──────┐             ┌────────▼─────────┐          ┌────────▼────────┐
│ provider-    │             │ provider-        │          │ provider-       │
│ vsphere      │             │ libvirt          │          │ proxmox         │
│ (govmomi)    │             │ (virsh + libssh) │          │ (REST API)      │
└──────────────┘             └──────────────────┘          └─────────────────┘
        │                             │                             │
   vCenter / ESXi              KVM / QEMU host                Proxmox VE host
```

One manager binary, one manager Dockerfile (consolidated in v0.3.6 — see H1 below), and one gRPC client per Provider CR. Each outbound RPC passes through two unary interceptors: a metrics interceptor (per-RPC latency and status-code counter, G4) and a CircuitBreaker interceptor (one breaker per Provider CR, G6).

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
- [VM Snapshots](guides/advanced/advanced-lifecycle.md#snapshots) - Backup and restore
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

VirtRigaud v0.3.6 ships **10 Custom Resource Definitions** in the `infra.virtrigaud.io/v1beta1` API group:

| Kind | Purpose |
|---|---|
| `VirtualMachine` | Desired state of a single VM (image, class, networks, disks, power state). |
| `Provider` | Connection details for a hypervisor (vSphere / Libvirt / Proxmox / Mock) and its provider-server Deployment. |
| `VMClass` | Reusable sizing template (CPU, memory, firmware). |
| `VMImage` | Reference to a hypervisor template / OVA / cloud image. |
| `VMNetworkAttachment` | Logical network the VM attaches to (resolved per-provider). |
| `VMSnapshot` | A point-in-time snapshot of a VirtualMachine. |
| `VMMigration` | Inter-provider VM migration (export → import). |
| `VMSet` | Replica-set of identical VMs. |
| `VMPlacementPolicy` | Placement / anti-affinity rules. |
| `VMClone` | One-shot clone of an existing VM. |

The manager also runs a `VMAdoption` reconciler (not a CRD — it reconciles `Provider` resources annotated with `virtrigaud.io/adopt-vms: "true"`, discovers VMs the hypervisor already owns, and creates `VirtualMachine` CRs labelled `virtrigaud.io/adopted=true` for them, plus an `adopted-Ncpu-Nmb` `VMClass` per unique sizing). See the [generated CRD reference](references/generated-crd-docs.md) for the full schema.

## Version Information

This documentation covers **VirtRigaud v0.3.6**.

### Recent Releases

- **v0.3.6** — *Observability + supply-chain release.*
    - **G6 CircuitBreaker now wired on the provider gRPC RPC path.** One breaker per `Provider` CR, default thresholds `FailureThreshold=10, ResetTimeout=60s, HalfOpenMaxCalls=3`. Infrastructure-class gRPC errors (`Unavailable`, `DeadlineExceeded`, `Internal`, `Unknown`) count toward the threshold; business errors (`NotFound`, `InvalidArgument`, …) pass through unchanged. See [Resilience](operations/resilience.md).
    - **G7 metric family rollout completed.** New families: `virtrigaud_vm_operations_total` (G7.1), `virtrigaud_ip_discovery_duration_seconds` (G7.2), `virtrigaud_provider_tasks_inflight` (G7.3). `virtrigaud_queue_depth` deprecated in favour of controller-runtime's `workqueue_depth{name}` (G7.4) — removal scheduled for v0.4.0 or later.
    - **H1 build-path consolidation.** One manager entrypoint, one manager Dockerfile. `build/Dockerfile.manager` now parametrised with `BUILDER_IMAGE` / `BASE_IMAGE` / `GOPROXY` / CA-cert handling for corporate / banking deployments. Closes latent bug #113.
    - **Go toolchain floor: 1.24.0 → 1.26.0.** Source builders need Go 1.26+ installed locally; binary consumers via released images unaffected.
    - **Security: `go.opentelemetry.io/otel` v1.39.0 → v1.43.0** (closes 3 HIGH-severity CVEs, two of which are PATH-hijacking primitives).
- **v0.3.5** — Observability G-track foundation (RPC metrics, error counters, reconcile metrics).
- **v0.3.3** — Changelog organisation with versioned release headers.
- **v0.2.3** — Provider feature parity: Reconfigure, Clone, TaskStatus, ConsoleURL.

See [CHANGELOG.md](https://github.com/projectbeskar/virtrigaud/blob/main/CHANGELOG.md) for the complete version history.

## Provider Status

| Provider | Status | Maturity | Documentation |
|----------|--------|----------|---------------|
| vSphere | Production Ready | Stable | [Guide](providers/vsphere.md) |
| Libvirt/KVM | Production Ready | Stable | [Guide](providers/libvirt.md) |
| Proxmox VE | Production Ready | Beta | [Guide](providers/proxmox.md) |
| Mock | Complete | Testing | [providers/tutorial.md](providers/tutorial.md) |

## Support

- **GitHub Issues**: [github.com/projectbeskar/virtrigaud/issues](https://github.com/projectbeskar/virtrigaud/issues)
- **Discussions**: [github.com/projectbeskar/virtrigaud/discussions](https://github.com/projectbeskar/virtrigaud/discussions)
- **Slack**: #virtrigaud on Kubernetes Slack

## Quick Links

- [Main README](https://github.com/projectbeskar/virtrigaud#readme) - Project overview
- [CHANGELOG](https://github.com/projectbeskar/virtrigaud/blob/main/CHANGELOG.md) - Version history
- [Contributing](https://github.com/projectbeskar/virtrigaud/blob/main/CONTRIBUTING.md) - How to contribute
- [License](https://github.com/projectbeskar/virtrigaud/blob/main/LICENSE) - Apache License 2.0
