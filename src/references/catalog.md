<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Provider Catalog

*Last updated: 2026-10-27T00:00:00Z — aligned to v0.4.1*

The VirtRigaud Provider Catalog lists all verified providers available for the VirtRigaud virtualization management platform. Providers listed here ship as part of the main repository at `v0.4.1`. The release publishes images for the vSphere, libvirt and Proxmox providers; the mock provider is built from source (see [Mock Provider](#mock-provider)).

## Provider Overview

| Provider | Description | Capabilities | Maintainer | License |
|----------|-------------|--------------|------------|----------|
| **Mock Provider** | A mock provider for testing and demonstrations (built from source, no release image) | core, snapshot, clone, image-prepare, advanced | virtrigaud@projectbeskar.com | Apache-2.0 |
| **vSphere Provider** | VMware vSphere provider for VirtRigaud | core, snapshot (including memory), clone (full and linked), image-prepare, advanced | virtrigaud@projectbeskar.com | Apache-2.0 |
| **Libvirt Provider** | Libvirt/KVM provider for VirtRigaud (single host, over SSH) | core, snapshot (including memory), image-prepare, advanced; full clones (the `clone` profile is not listed: linked clones are disabled since v0.4.0) | virtrigaud@projectbeskar.com | Apache-2.0 |
| **Libvirt Provider (clustered, experimental)** | The same provider with `spec.topology: cluster`: one Provider fronts a `Host`/`HostPool` inventory of libvirt hosts (new in v0.4.0, opt-in) | core, snapshot (including memory), clone (full clones, on the source VM's host), disk export and import for migration | virtrigaud@projectbeskar.com | Apache-2.0 |
| **Proxmox Provider** | Proxmox VE provider for VirtRigaud | core, snapshot, clone, advanced (full clones only: linked clones are no longer advertised since v0.4.1); image-prepare refuses URL sources (templates only) | virtrigaud@projectbeskar.com | Apache-2.0 |

The catalog publishes no conformance results: every profile is recorded as `skip` (not run), with no report URL or date (v0.4.0 and earlier catalog entries claimed passes and test dates that nobody had run). The test suite in the repository (`vcts run`, see [Contributing a Provider](#contributing-a-provider)) is run by whoever deploys a provider; the capabilities listed are what each provider reports through `GetCapabilities`. The Proxmox entry still lists the `clone` profile, although Proxmox no longer advertises linked clones (the SDK's `clone` profile is the `linked_clones` flag).

## Quick Start

### Installing a Provider

A provider is deployed by the VirtRigaud manager from a `Provider` resource: you create the credentials Secret and a `Provider` whose `spec.runtime.image` names the provider image, and the manager creates the provider Deployment and Service. Use the provider image at the same version as the manager (`v0.4.1`). The image names are `ghcr.io/projectbeskar/virtrigaud/provider-<type>:v0.4.1` for `<type>` in `vsphere`, `libvirt` and `proxmox`; the images are published for `linux/amd64` and `linux/arm64`.

The example below installs a vSphere provider. Replace the endpoint with your vCenter and create the Secret first (see [Provider Details](#provider-details) for the credentials each provider reads):

```bash
kubectl create secret generic vsphere-credentials \
  --namespace virtrigaud-system \
  --from-literal=username=your-username \
  --from-literal=password=your-password
```

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: vsphere-prod
  namespace: virtrigaud-system
spec:
  type: vsphere
  endpoint: https://vcenter.example.com/sdk
  credentialSecretRef:
    name: vsphere-credentials
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.1"
    service:
      port: 9443
      tls:
        enabled: true
        secretRef:
          name: provider-vsphere-tls
```

Every `Provider` needs a `spec.runtime.service.tls` block: the gRPC channel between the manager and the provider uses mutual TLS by default, and a Provider without the block is not deployed. Provision the TLS Secret first; see [mTLS](../providers/security/mtls.md).

### Provider Discovery

Once installed, the manager reports each provider's state on the `Provider` resource. List them with:

```bash
kubectl get providers -A
```

## Provider Details

### Mock Provider

- **Image:** none published. Build it from source with `make build-provider-mock` (binary) or `cmd/provider-mock/Dockerfile` (image). The release workflow publishes images for the manager, the vSphere, libvirt and Proxmox providers and the `kubectl` helper only.
- **Repository:** [https://github.com/projectbeskar/virtrigaud](https://github.com/projectbeskar/virtrigaud)
- **Maturity:** stable
- **Tags:** testing, development, demo
- **Source:** [`internal/providers/mock`](https://github.com/projectbeskar/virtrigaud/tree/v0.4.1/internal/providers/mock) and [`cmd/provider-mock`](https://github.com/projectbeskar/virtrigaud/tree/v0.4.1/cmd/provider-mock) (no separate documentation page)

The mock provider is perfect for:
- Testing VirtRigaud functionality
- Development and CI/CD pipelines
- Learning provider concepts
- Demonstrating VirtRigaud capabilities

!!! note "Not selectable as a `Provider` type"
    `Provider.spec.type` accepts `vsphere`, `libvirt`, `proxmox`, `firecracker` and `qemu`; `mock` is not a value, so the manager does not deploy the mock provider from a `Provider` resource. The in-repository tests and the conformance suite use it, and the repository's deprecated `virtrigaud-provider-runtime` chart (removed in the next minor release; do not use it for new installations) carried example values for running it standalone. Build the image from `cmd/provider-mock/Dockerfile` and run it outside the manager's control.

### vSphere Provider

- **Image:** `ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.1`
- **Repository:** [https://github.com/projectbeskar/virtrigaud](https://github.com/projectbeskar/virtrigaud)
- **Maturity:** beta
- **Tags:** vmware, vsphere, enterprise
- **Documentation:** [vSphere provider](../providers/vsphere.md)

The vSphere provider enables VirtRigaud to manage VMware vSphere environments, including:
- VM lifecycle management (create, update, delete)
- Power operations (on, off, restart, suspend)
- Snapshot management, including memory snapshots of a powered-on VM
- VM cloning (full and linked) and templates
- Image preparation: an OVA/OVF source is imported into vCenter as a template, named and verified by the `VMImage` identity (since v0.4.0, [ADR-0009](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/adr/0009-prepared-image-artifact-identity.md))
- Disk export and import (`vmdk`, `qcow2`, `raw`) for cross-hypervisor migration over PVC, S3 and NFS
- Resource allocation and configuration

A vSphere provider always runs a single replica, replaced with the `Recreate` strategy.

**Prerequisites:**
- VMware vSphere 7.0 or later
- vCenter Server credentials; since v0.4.0 the account also needs `VirtualMachine.Config.AdvancedConfig` on the target VM folder and resource pool, because every create writes an owner stamp into the VM's extra configuration
- Network connectivity to vCenter API

**Installation:**
```bash
# Create secret for vSphere credentials
kubectl create secret generic vsphere-credentials \
  --namespace virtrigaud-system \
  --from-literal=username=your-username \
  --from-literal=password=your-password
```

Then create the `Provider` shown in [Installing a Provider](#installing-a-provider). The provider reads `username` and `password` as files from the Secret the manager mounts at `/etc/virtrigaud/credentials`.

### Libvirt Provider

- **Image:** `ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.4.1`
- **Repository:** [https://github.com/projectbeskar/virtrigaud](https://github.com/projectbeskar/virtrigaud)
- **Maturity:** beta (clustered topology: experimental)
- **Tags:** libvirt, kvm, qemu, open-source
- **Documentation:** [Libvirt provider](../providers/libvirt.md)

The libvirt provider manages KVM/QEMU virtual machines through libvirt over SSH (`qemu+ssh://`), supporting:
- VM lifecycle management
- Power state control
- Snapshot operations, including memory snapshots of a running VM
- Full clones
- Image preparation from a libvirt-side path or URL, with prepared images named and stamped by the `VMImage` identity (since v0.4.0)
- Disk export (`qcow2`, `raw`) and import (`qcow2`, `raw`, `vmdk`) for cross-hypervisor migration over PVC, S3 and NFS (a clustered Provider exports `qcow2` only, over S3 and NFS)
- Cloud-init seeds built private (`0600`) in a dedicated directory on the host (since v0.4.0)

!!! warning "Linked clones are disabled"
    Since v0.4.0 a `VMClone` with `type: LinkedClone` through a libvirt provider fails with `LinkedCloneUnsupported`: a linked clone reads its source VM's live disk, and powering the source on corrupts the clone. The provider reports `supportsLinkedClones: false`. Use `FullClone` (the default). Clone is implemented for full clones ([#153](https://github.com/projectbeskar/virtrigaud/issues/153)); the previous "Clone unimplemented" limitation no longer applies.

**Prerequisites:**
- A host running `libvirtd` with KVM, reachable over SSH from the provider pod
- The cloud-init seed directory on every libvirt host (default `/var/lib/libvirt/virtrigaud-seeds`, owned by the SSH user); see [Libvirt host preparation](../operations/libvirt-host-prepare.md)
- Shared storage if you want several hosts to see the same disks

**Installation:** create the credentials Secret and a `Provider` as in [Installing a Provider](#installing-a-provider), with `type: libvirt`, an `endpoint` such as `qemu+ssh://virtrigaud@libvirt-host.example.com/system` and `image: ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.4.1`. See the [Libvirt provider](../providers/libvirt.md) page for the Secret keys and `known_hosts`.

#### Clustered topology (experimental, opt-in)

New in v0.4.0: a `Provider` with `spec.topology: cluster` fronts several bare libvirt hosts registered as `Host` resources, grouped by `HostPool`, instead of one host. Only `type: libvirt` accepts it (a validating webhook rejects it on other types), `spec.topology` is immutable once set, and single-host providers are unchanged.

- The scheduler places each `VirtualMachine` on a host of the pool (filters on capacity, labels and `VMPlacementPolicy`, then scores), subtracting what every VM bound to or pending on the host already holds; the host's committed vCPU and memory are exposed on `virtrigaud_host_committed_cpu` and `virtrigaud_host_committed_memory_mib`.
- Per-VM calls are routed to the VM's host and checked against the VM's owner stamp: describe, delete, power, reconfigure, snapshots, full clones (on the source VM's own host) and host-side disk export (S3 and NFS). A VM that no host can take reports `Placed=False/Unschedulable`.
- VMs are listed across every host, and unstamped domains can be adopted, keyed on (host, domain).
- A `VMMigration` can target a clustered libvirt provider (S3 or NFS, experimental).
- A clustered provider runs a single replica with the `Recreate` strategy, so a rollout is a short outage. A delete waits while any host of the Provider is unreachable (`DeleteBlocked`); `virtrigaud.io/force-delete` and `virtrigaud.io/orphan-on-delete` still release it.
- Not yet supported on a clustered provider: linked clones, image preparation (`ImagePrepare`), and host-to-host migration.

See the example manifests `provider-libvirt-clustered.yaml`, `hostpool-clustered.yaml` and `host-libvirt-clustered-first-vm.yaml` in the [`examples/`](https://github.com/projectbeskar/virtrigaud/tree/v0.4.1/examples) directory of the main repository, and [Clustered provider inventory](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/clustered-provider-inventory.md) for the full design.

### Proxmox Provider

- **Image:** `ghcr.io/projectbeskar/virtrigaud/provider-proxmox:v0.4.1`
- **Repository:** [https://github.com/projectbeskar/virtrigaud](https://github.com/projectbeskar/virtrigaud)
- **Maturity:** beta
- **Tags:** proxmox, pve, kvm, open-source
- **Documentation:** [providers/proxmox.md](../providers/proxmox.md)

The Proxmox provider manages VMs on Proxmox VE through the Proxmox API, supporting:
- VM lifecycle management
- Power state control
- Snapshot operations
- Full clones (linked clones are not advertised since v0.4.1); a clone gets the class's CPU and memory
- API token authentication
- Network settings: since v0.4.0 a VM gets the bridge, VLAN tag, NIC model and static IP its networks name
- Cloud-init: the whole `spec.userData` through a NoCloud seed CD-ROM built on the PVE node over SSH, kept out of the boot order (since v0.4.1); a VM without user-data uses PVE's own cloud-init drive, placed on the same storage as the VM's disk (since v0.4.0)
- Disk export and import (`qcow2`, `raw`, `vmdk`) for cross-hypervisor migration over S3 and NFS

!!! warning "URL image import is not supported"
    Since v0.4.0 a `VMImage` with `source.http` is refused through a Proxmox provider (`ImagePrepare` returns `InvalidSpec`, and the `VMImage` reports `InvalidSource`). Reference a template that already exists on Proxmox VE with `source.proxmox.templateID`.

**Prerequisites:**
- Proxmox VE 7.0 or later
- API token with `VM.Allocate` and `VM.Config.*` permissions; since v0.4.0 also `VM.Config.Network` and `VM.Config.Cloudinit`, and, for a token that is not root, `SDN.Use` on every bridge a VM is put on; since v0.4.1 also `VM.Audit` and `VM.Config.Options` on a VM made without a template with user-data
- For VMs that carry `spec.userData` (and for migration): `ssh_user` (`root`), `ssh_privatekey` or `ssh_password`, and `known_hosts` in the Provider's Secret, `genisoimage` and `flock` on the PVE node, and the VM on the node SSH reaches (`PROVIDER_NODE_SELECTOR`). **Breaking for Proxmox users whose VMs carry user-data**; see the [upgrade notes](../operations/upgrade.md#proxmox-user-data-needs-the-ssh-data-plane)

**Installation:** create the credentials Secret (`token_id` and `token_secret`, or `username` and `password`, plus the SSH keys above when VMs carry user-data) and a `Provider` as in [Installing a Provider](#installing-a-provider), with `type: proxmox`, `endpoint: https://pve.example.com:8006` and `image: ghcr.io/projectbeskar/virtrigaud/provider-proxmox:v0.4.1`. See the [Proxmox provider](../providers/proxmox.md) page for the credentials the provider reads.

## Reported Capabilities (v0.4.1)

Since v0.3.8, the manager fetches each provider's live capability set via the `GetCapabilities` gRPC RPC and surfaces the result in `Provider.status.reportedCapabilities`. A `CapabilitiesReported` status condition is also set on the Provider CR.

These reported capabilities drive these behaviors:

1. **VMClone Linked clones**: the VMClone controller checks `status.reportedCapabilities.supportsLinkedClones` before issuing a Linked clone. If the flag is `false` or unset, the clone is rejected with a clear error. The libvirt provider reports `false` since v0.4.0, and the Proxmox provider no longer reports `true` since v0.4.1. (The check asks the running provider at clone time, not this status.)
2. **Capability enforcement** (opt-in): when the manager is started with `--enforce-provider-capabilities`, snapshot and migration operations are also gated on the provider's reported capabilities. This flag is OFF by default. Enable it only after confirming your provider's capability flags are accurate — a provider that under-reports a capability will block operations it can actually perform.
3. **Image preparation** (since v0.4.0): an import-style `VMImage` source (an OVA URL, a libvirt URL, an HTTP source) is sent to a provider only if it reports `supportsImageArtifactIdentity`; otherwise the VM is held with `ProviderLacksArtifactIdentity`. The vSphere, libvirt, Proxmox and mock providers report it.

`status.reportedCapabilities` is read after the provider Deployment's rollout completes, again 45 seconds later and every 10 minutes while the `Provider` is healthy, so after a provider roll expect the new image's answer within about a minute ([details](../providers/providers-capabilities.md#when-the-status-is-read-v041)). Two fields are new in `status.reportedCapabilities` in v0.4.0: `supportsImageArtifactIdentity` and `supportsHonestReconfigure` (the provider refuses or reports a reconfigure it cannot apply instead of reporting success; libvirt reports it, vSphere does not yet). The `GetCapabilities` response (`proto/provider/v1/provider.proto`) carries further flags that are not copied into `status.reportedCapabilities`: `supports_clustering`, `supports_routed_clone`, `supports_routed_adoption`, `supports_list_owner_filter`, `supports_owner_transfer` and `supports_owner_rebind`. A clustered libvirt provider reports `supports_clustering`, `supports_routed_clone` and `supports_routed_adoption`.

To inspect reported capabilities:

```bash
kubectl get provider vsphere-prod -o jsonpath='{.status.reportedCapabilities}' | jq .
```

## Capability Profiles

The provider SDK ([`sdk/provider/capabilities`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/sdk/provider/capabilities/capabilities.go)) groups its capability flags into five profiles. A profile is satisfied when the provider has **all** of its flags. The profiles are a convenience of the SDK (`Manager.SupportsProfile`); the manager reads the individual flags from `status.reportedCapabilities`, not a profile name.

| Profile | Capability flags |
|---------|------------------|
| `core` | `validate`, `create`, `delete`, `power`, `describe`, `get_capabilities` |
| `snapshot` | `snapshots` |
| `clone` | `linked_clones` |
| `image_prepare` | `image_import` |
| `advanced` | `reconfigure`, `reconfigure_online`, `disk_expansion_online` |

Flags outside any profile (for example `memory_snapshots`, `disk_export`, `disk_import`, `clustering`, `image_artifact_identity`, `honest_reconfigure`, `routed_adoption`, `owner_rebind`) are reported individually. The `clone` profile contains only `linked_clones`; full clones do not need a capability flag.

## Contributing a Provider

Want to add your provider to the catalog? Follow these steps:

### 1. Develop Your Provider

Use the [Provider Developer Tutorial](../providers/tutorial.md) to create your provider using the VirtRigaud SDK.

### 2. Ensure Conformance

The VirtRigaud Conformance Test Suite (VCTS) is meant to be run against a deployed `Provider` resource (see [`vcts`](cli-tools.md#vcts) for the flags):

```bash
# Install the VCTS tool
# `go install ...@latest` is refused (replace directives in go.mod): build from a checkout or
# download the vcts-<os>-<arch> binary from the GitHub release
git clone --branch v0.4.1 https://github.com/projectbeskar/virtrigaud.git
cd virtrigaud && go build -o vcts ./cmd/vcts

# Validate the specification files
./vcts validate test/conformance/specs/

# Run the conformance tests against a Provider resource in a throw-away namespace of a
# non-production cluster (it creates real VMs); IMAGE is a VMImage the provider can boot
./vcts run --provider my-provider -n vcts --set IMAGE=ubuntu-22
```

!!! note "`vcts run` executes the tests since v0.4.1"
    In v0.4.0 the conformance runner implemented no steps, so every selected test failed. `vcts run` now creates the test objects in the namespace given by `-n`, checks their status, reports a test whose required capability the Provider lacks as skipped, and cleans up after each test. It never creates, changes or deletes a `Provider`. The shipped tests cover create and delete, a power cycle, an offline reconfigure, a snapshot and a full clone; a snapshot or clone test is skipped for a provider that does not report the capability. See the [CLI Tools Reference](cli-tools.md#vcts).

### 3. Publish to Catalog

Use the `vrtg-provider publish` command, from inside the provider project that `vrtg-provider init` created, to write a catalog entry:

```bash
vrtg-provider publish \
  --image ghcr.io/yourorg/your-provider \
  --repo https://github.com/yourorg/your-provider \
  --maintainer your-email@example.com \
  --tag v1.0.0 \
  --license Apache-2.0
```

The `publish` command will:

1. Build the project and run its unit tests (skipped with `--skip-verify`)
2. Record the conformance profile `core` as `skip` (not run) and give the entry a "not run" badge; `publish` does not run VCTS and never records a pass
3. Add or update the entry in `providers/catalog.yaml` (found by walking up from the current directory, or named with `--catalog`)
4. Print next steps for opening a pull request

`publish` only writes the local catalog file; it does not open the pull request. See the [CLI Tools Reference](cli-tools.md#publish-publishing).

See [`cmd/vrtg-provider/publish.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/vrtg-provider/publish.go) for the full flag list.

!!! note "Dry-run first"
    Add `--dry-run` to see what the catalog entry would look like without writing any files.

### 4. Catalog Requirements

To be included in the catalog, providers must:

- ✅ Pass the VCTS tests for the profiles you claim (`vcts run`, see the [CLI Tools Reference](cli-tools.md#vcts)) and say in your pull request how you ran them; `vrtg-provider publish` records every profile as `skip` (not run) and never claims a pass
- ✅ Include comprehensive documentation
- ✅ Provide Helm chart for deployment
- ✅ Follow security best practices
- ✅ Include proper error handling
- ✅ Support health checks and metrics
- ✅ Have active maintenance and support

## Provider Support Matrix

| Provider | Kubernetes | VirtRigaud | Go Version | Platforms |
|----------|------------|------------|------------|-----------|
| Mock | 1.25+ | 0.4.1 | 1.26+ | built from source |
| vSphere | 1.25+ | 0.4.1 | 1.26+ | linux/amd64, linux/arm64 |
| Libvirt | 1.25+ | 0.4.1 | 1.26+ | linux/amd64, linux/arm64 |
| Proxmox | 1.25+ | 0.4.1 | 1.26+ | linux/amd64, linux/arm64 |

The Go version is the toolchain needed to build from source (`go 1.26.10` in `go.mod`). On Kubernetes 1.30+ the chart also renders the admission policy that reserves VirtRigaud's internal annotation keys; below 1.30 it is skipped.

Run each provider image at the same version as the manager and upgrade the manager before the providers (see the [Upgrade Guide](../operations/upgrade.md)).

## Provider Security Documentation

The following security guides apply to all providers deployed in v0.4.1:

| Guide | Path | Summary |
|-------|------|---------|
| mTLS between manager and provider | [`providers/security/mtls.md`](../providers/security/mtls.md) | Manager-to-provider gRPC is mutually authenticated TLS by default since v0.3.7 ([#147](https://github.com/projectbeskar/virtrigaud/issues/147), [#148](https://github.com/projectbeskar/virtrigaud/issues/148)); a provider pod without TLS material fails closed unless plaintext is explicitly opted into. |
| Network Policies | [`providers/security/network-policies.md`](../providers/security/network-policies.md) | Kubernetes NetworkPolicy manifests to restrict provider pod egress. |
| External Secrets | [`providers/security/external-secrets.md`](../providers/security/external-secrets.md) | Integrate with External Secrets Operator to avoid storing hypervisor credentials directly in Kubernetes Secrets. |
| Bearer Token Auth | [`providers/security/bearer-token.md`](../providers/security/bearer-token.md) | Hypervisor API tokens (Proxmox) and the SDK's optional gRPC bearer-token middleware for external providers. The in-tree manager authenticates with mTLS and does not send a bearer token. |

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

