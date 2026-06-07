<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Provider Catalog

*Last updated: 2026-06-07T00:00:00Z — aligned to v0.3.8*

The VirtRigaud Provider Catalog lists all verified providers available for the VirtRigaud virtualization management platform. Providers listed here ship as part of the main repository at `v0.3.8` and have passing conformance gates in CI.

## Provider Overview

| Provider | Description | Capabilities | Conformance | Maintainer | License |
|----------|-------------|--------------|-------------|------------|----------|
| **Mock Provider** | A mock provider for testing and demonstrations | core, snapshot, clone, image-prepare, advanced | ![Conformance](https://img.shields.io/badge/conformance-pass-green) | virtrigaud@projectbeskar.com | Apache-2.0 |
| **vSphere Provider** | VMware vSphere provider for VirtRigaud | core, snapshot, clone, advanced | ![Conformance](https://img.shields.io/badge/conformance-pass-green) | virtrigaud@projectbeskar.com | Apache-2.0 |
| **Libvirt Provider** | Libvirt/KVM provider for VirtRigaud | core, snapshot (clone: unimplemented [#153](https://github.com/projectbeskar/virtrigaud/issues/153)) | ![Conformance](https://img.shields.io/badge/conformance-partial-yellow) | virtrigaud@projectbeskar.com | Apache-2.0 |
| **Proxmox Provider** | Proxmox VE provider for VirtRigaud | core, snapshot, clone | ![Conformance](https://img.shields.io/badge/conformance-partial-yellow) | virtrigaud@projectbeskar.com | Apache-2.0 |

## Quick Start

### Installing a Provider

To install a provider in your Kubernetes cluster, use the VirtRigaud provider runtime Helm chart:

```bash
# Add the VirtRigaud Helm repository
helm repo add virtrigaud https://projectbeskar.github.io/virtrigaud
helm repo update

# Install a provider using the runtime chart
helm install my-vsphere-provider virtrigaud/virtrigaud-provider-runtime \
  --namespace vsphere-providers \
  --create-namespace \
  --set image.repository=ghcr.io/projectbeskar/virtrigaud/provider-vsphere \
  --set image.tag=v0.3.8 \
  --set env[0].name=VSPHERE_SERVER \
  --set env[0].value=vcenter.example.com
```

### Provider Discovery

Once installed, providers automatically register with the VirtRigaud manager. You can list available providers:

```bash
kubectl get providers -n virtrigaud-system
```

## Provider Details

### Mock Provider

- **Image:** `ghcr.io/projectbeskar/virtrigaud/provider-mock:v0.3.8`
- **Repository:** [https://github.com/projectbeskar/virtrigaud](https://github.com/projectbeskar/virtrigaud)
- **Maturity:** stable
- **Tags:** testing, development, demo
- **Documentation:** [https://projectbeskar.github.io/virtrigaud/providers/mock/](https://projectbeskar.github.io/virtrigaud/providers/mock/)

The mock provider is perfect for:
- Testing VirtRigaud functionality
- Development and CI/CD pipelines
- Learning provider concepts
- Demonstrating VirtRigaud capabilities

**Installation:**
```bash
helm install mock-provider virtrigaud/virtrigaud-provider-runtime \
  --namespace development \
  --create-namespace \
  --set image.repository=ghcr.io/projectbeskar/virtrigaud/provider-mock \
  --set image.tag=v0.3.8 \
  --set env[0].name=LOG_LEVEL \
  --set env[0].value=debug
```

### vSphere Provider

- **Image:** `ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.3.8`
- **Repository:** [https://github.com/projectbeskar/virtrigaud](https://github.com/projectbeskar/virtrigaud)
- **Maturity:** beta
- **Tags:** vmware, vsphere, enterprise
- **Documentation:** [https://projectbeskar.github.io/virtrigaud/providers/vsphere/](https://projectbeskar.github.io/virtrigaud/providers/vsphere/)

The vSphere provider enables VirtRigaud to manage VMware vSphere environments, including:
- VM lifecycle management (create, update, delete)
- Power operations (on, off, restart, suspend)
- Snapshot management
- VM cloning and templates
- Resource allocation and configuration

**Prerequisites:**
- VMware vSphere 6.7 or later
- vCenter Server credentials
- Network connectivity to vCenter API

**Installation:**
```bash
# Create secret for vSphere credentials
kubectl create secret generic vsphere-credentials \
  --namespace vsphere-providers \
  --from-literal=username=your-username \
  --from-literal=password=your-password

# Install provider
helm install vsphere-provider virtrigaud/virtrigaud-provider-runtime \
  --namespace vsphere-providers \
  --create-namespace \
  --set image.repository=ghcr.io/projectbeskar/virtrigaud/provider-vsphere \
  --set image.tag=v0.3.8 \
  --set env[0].name=VSPHERE_SERVER \
  --set env[0].value=vcenter.example.com \
  --set env[1].name=VSPHERE_USERNAME \
  --set env[1].valueFrom.secretKeyRef.name=vsphere-credentials \
  --set env[1].valueFrom.secretKeyRef.key=username \
  --set env[2].name=VSPHERE_PASSWORD \
  --set env[2].valueFrom.secretKeyRef.name=vsphere-credentials \
  --set env[2].valueFrom.secretKeyRef.key=password
```

### Libvirt Provider

- **Image:** `ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.3.8`
- **Repository:** [https://github.com/projectbeskar/virtrigaud](https://github.com/projectbeskar/virtrigaud)
- **Maturity:** beta
- **Tags:** libvirt, kvm, qemu, open-source
- **Documentation:** [https://projectbeskar.github.io/virtrigaud/providers/libvirt/](https://projectbeskar.github.io/virtrigaud/providers/libvirt/)

The libvirt provider manages KVM/QEMU virtual machines through libvirt, supporting:
- VM lifecycle management
- Power state control
- Snapshot operations
- Local and remote libvirt connections

!!! warning "Clone not supported"
    The libvirt Clone RPC is Unimplemented ([#153](https://github.com/projectbeskar/virtrigaud/issues/153)). VMClone resources targeting a libvirt provider will fail. The provider does not advertise `supportsLinkedClones` in its reported capabilities.

**Prerequisites:**
- Libvirt daemon running on target hosts
- SSH access for remote connections
- Shared storage for multi-host deployments

**Installation:**
```bash
helm install libvirt-provider virtrigaud/virtrigaud-provider-runtime \
  --namespace libvirt-providers \
  --create-namespace \
  --set image.repository=ghcr.io/projectbeskar/virtrigaud/provider-libvirt \
  --set image.tag=v0.3.8 \
  --set env[0].name=LIBVIRT_URI \
  --set env[0].value=qemu:///system \
  --set securityContext.runAsUser=0 \
  --set podSecurityContext.runAsUser=0
```

### Proxmox Provider

- **Image:** `ghcr.io/projectbeskar/virtrigaud/provider-proxmox:v0.3.8`
- **Repository:** [https://github.com/projectbeskar/virtrigaud](https://github.com/projectbeskar/virtrigaud)
- **Maturity:** beta
- **Tags:** proxmox, pve, kvm, open-source
- **Documentation:** [providers/proxmox.md](../providers/proxmox.md)

The Proxmox provider manages VMs on Proxmox VE through the Proxmox API, supporting:
- VM lifecycle management
- Power state control
- Snapshot operations
- VM cloning (Full and Linked clones)
- API token authentication

**Prerequisites:**
- Proxmox VE 7.0 or later
- API token with VM.Allocate and VM.Config.* permissions

**Installation:**
```bash
helm install proxmox-provider virtrigaud/virtrigaud-provider-runtime \
  --namespace proxmox-providers \
  --create-namespace \
  --set image.repository=ghcr.io/projectbeskar/virtrigaud/provider-proxmox \
  --set image.tag=v0.3.8 \
  --set env[0].name=PROXMOX_HOST \
  --set env[0].value=pve.example.com \
  --set env[1].name=PROXMOX_TOKEN_ID \
  --set env[1].valueFrom.secretKeyRef.name=proxmox-creds \
  --set env[1].valueFrom.secretKeyRef.key=token-id
```

## Reported Capabilities (v0.3.8)

Starting in v0.3.8, the manager fetches each provider's live capability set via the `GetCapabilities` gRPC RPC and surfaces the result in `Provider.status.reportedCapabilities`. A `CapabilitiesReported` status condition is also set on the Provider CR.

These reported capabilities drive two behaviors:

1. **VMClone Linked clones**: the VMClone controller checks `status.reportedCapabilities.supportsLinkedClones` before issuing a Linked clone. If the flag is `false` or unset, the clone is rejected with a clear error.
2. **Capability enforcement** (opt-in): when the manager is started with `--enforce-provider-capabilities`, snapshot and migration operations are also gated on the provider's reported capabilities. This flag is OFF by default. Enable it only after confirming your provider's capability flags are accurate — a provider that under-reports a capability will block operations it can actually perform.

To inspect reported capabilities:

```bash
kubectl get provider vsphere-prod -o jsonpath='{.status.reportedCapabilities}' | jq .
```

## Capability Profiles

VirtRigaud defines several capability profiles that providers can implement:

### Core Profile
**Required for all providers**
- `vm.create` - Create virtual machines
- `vm.read` - Get virtual machine information
- `vm.update` - Update virtual machine configuration
- `vm.delete` - Delete virtual machines
- `vm.power` - Control power state (on/off/restart)
- `vm.list` - List virtual machines

### Snapshot Profile
**Optional - for providers supporting VM snapshots**
- `vm.snapshot.create` - Create VM snapshots
- `vm.snapshot.list` - List VM snapshots
- `vm.snapshot.delete` - Delete VM snapshots
- `vm.snapshot.restore` - Restore VM from snapshot

### Clone Profile
**Optional - for providers supporting VM cloning**
- `vm.clone` - Clone virtual machines
- `vm.template` - Create and manage VM templates

### Image Prepare Profile
**Optional - for providers with image management**
- `image.prepare` - Prepare VM images
- `image.list` - List available images
- `image.upload` - Upload custom images

### Advanced Profile
**Optional - for advanced provider features**
- `vm.migrate` - Live migrate VMs between hosts
- `vm.resize` - Dynamic resource allocation
- `vm.backup` - Backup and restore operations
- `vm.monitoring` - Advanced monitoring and metrics

## Contributing a Provider

Want to add your provider to the catalog? Follow these steps:

### 1. Develop Your Provider

Use the [Provider Developer Tutorial](../providers/tutorial.md) to create your provider using the VirtRigaud SDK.

### 2. Ensure Conformance

Run the VirtRigaud Conformance Test Suite (VCTS) to verify your provider meets the requirements:

```bash
# Install the VCTS tool
go install github.com/projectbeskar/virtrigaud/cmd/vcts@latest

# Run conformance tests
vcts run --provider-endpoint=localhost:9443 --profile=core
```

### 3. Publish to Catalog

Use the `vrtg-provider publish` command to create and submit a catalog entry:

```bash
vrtg-provider publish \
  --image ghcr.io/yourorg/your-provider \
  --repo https://github.com/yourorg/your-provider \
  --maintainer your-email@example.com \
  --tag v1.0.0 \
  --license Apache-2.0
```

The `publish` command will:
1. Run VCTS conformance tests (skip with `--skip-verify`)
2. Generate a catalog entry in `providers/catalog.yaml`
3. Print next steps for opening a pull request

See [`cmd/vrtg-provider/publish.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg-provider/publish.go) for the full flag list.

!!! note "Dry-run first"
    Add `--dry-run` to see what the catalog entry would look like without writing any files.

### 4. Catalog Requirements

To be included in the catalog, providers must:

- ✅ Pass VCTS core profile tests
- ✅ Include comprehensive documentation
- ✅ Provide Helm chart for deployment
- ✅ Follow security best practices
- ✅ Include proper error handling
- ✅ Support health checks and metrics
- ✅ Have active maintenance and support

## Provider Support Matrix

| Provider | Kubernetes | VirtRigaud | Go Version | Platforms |
|----------|------------|------------|------------|-----------|
| Mock | 1.25+ | 0.3.0+ | 1.23+ | linux/amd64, linux/arm64 |
| vSphere | 1.25+ | 0.3.0+ | 1.23+ | linux/amd64, linux/arm64 |
| Libvirt | 1.25+ | 0.3.0+ | 1.23+ | linux/amd64 |
| Proxmox | 1.25+ | 0.3.0+ | 1.23+ | linux/amd64 |

## Provider Security Documentation

The following security guides apply to all providers deployed in v0.3.8:

| Guide | Path | Summary |
|-------|------|---------|
| mTLS between manager and provider | [`providers/security/mtls.md`](../providers/security/mtls.md) | Current status: mTLS is **not wired** through the Resolver in v0.3.8 (tracked as [#147](https://github.com/projectbeskar/virtrigaud/issues/147)). The guide documents the intended flow and the manual workaround. |
| Network Policies | [`providers/security/network-policies.md`](../providers/security/network-policies.md) | Kubernetes NetworkPolicy manifests to restrict provider pod egress. |
| External Secrets | [`providers/security/external-secrets.md`](../providers/security/external-secrets.md) | Integrate with External Secrets Operator to avoid storing hypervisor credentials directly in Kubernetes Secrets. |
| Bearer Token Auth | [`providers/security/bearer-token.md`](../providers/security/bearer-token.md) | Configure bearer-token-based authentication on provider gRPC endpoints. Note: provider gRPC servers do not enforce auth in v0.3.8 ([#148](https://github.com/projectbeskar/virtrigaud/issues/148)). |

## Community and Support

- **Documentation:** [VirtRigaud Provider Docs](https://projectbeskar.github.io/virtrigaud/providers/)
- **Issues:** [GitHub Issues](https://github.com/projectbeskar/virtrigaud/issues)
- **Discussions:** [GitHub Discussions](https://github.com/projectbeskar/virtrigaud/discussions)

## Versioning and Compatibility

Providers follow semantic versioning (SemVer) and maintain compatibility with VirtRigaud versions:

- **Major versions** (1.0.0 → 2.0.0): Breaking changes to APIs or behavior
- **Minor versions** (1.0.0 → 1.1.0): New features, backward compatible
- **Patch versions** (1.0.0 → 1.0.1): Bug fixes, security updates

**Compatibility Policy:**
- Current VirtRigaud version supports providers from current major version
- Providers should support at least 2 minor versions of VirtRigaud
- Breaking changes require migration documentation

## License and Legal

All providers in this catalog are open source and follow the licensing terms specified in their individual repositories. The catalog itself is maintained under the Apache 2.0 license.

**Trademark Notice:** VMware and vSphere are trademarks of VMware, Inc. KVM and QEMU are trademarks of their respective owners. All trademarks are the property of their respective owners.

