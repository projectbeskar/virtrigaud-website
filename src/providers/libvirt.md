<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Libvirt / KVM Provider

The Libvirt provider manages VMs on KVM/QEMU via the `libvirt` daemon, talking to it through `virsh` shelled out over SSH. It is the simplest provider to operate against and is widely deployed on-premises.

This page is aligned to **VirtRigaud v0.3.9**. Capability claims trace back to the provider's `GetCapabilities` response in `internal/providers/libvirt/server.go`.

!!! note "Implementation detail: virsh over SSH"
    Unlike most libvirt integrations that use the C `libvirt-go` bindings (which require cgo), VirtRigaud's libvirt provider shells out to the `virsh` CLI over an SSH tunnel to the remote libvirt host (`internal/providers/libvirt/virsh.go`). This keeps the provider image small (no libvirt-dev runtime) and avoids cgo entirely, at the cost of being more sensitive to SSH-host hygiene. See [Troubleshooting](#troubleshooting) for the SSH-host-issue narrative.

## Capabilities at a glance

The libvirt provider advertises the following via `GetCapabilities` (`internal/providers/libvirt/server.go`):

| Capability flag | Value | What it means |
|-----------------|-------|---------------|
| `SupportsReconfigureOnline` | **true** | Online CPU/memory changes via `virsh setvcpus/setmem --live` for VMs created with hot-add headroom (see [Online reconfigure](#online-cpu-and-memory-reconfigure-203)). VMs without the flags still require a power-cycle. |
| `SupportsDiskExpansionOnline` | **true** | Live disk grow via `virsh blockresize` + best-effort in-guest FS grow; grow-only (see [Online disk expansion](#online-disk-expansion-201)). |
| `SupportsSnapshots` | true | `virsh snapshot-create-as` against qcow2 storage. |
| `SupportsMemorySnapshots` | **true** | Full system checkpoints including RAM via `snapshot-create-as` without `--disk-only` on running VMs; stopped VMs downgrade to disk-only with a WARN (see [Memory snapshots](#memory-snapshots-202)). |
| `SupportsLinkedClones` | **true** | Clone RPC implemented: qcow2 overlay (linked) + volume copy (full), same-provider (#153). UEFI nvram re-pointed per clone (#208/#221). See [Cloning](#cloning-153208221). |
| `SupportsImageImport` | **true** | `ImagePrepare` RPC implemented: lazy VM-create-time import into a storage pool (#154). See [Image preparation](#image-preparation-154). |
| `SupportsDiskExport` | true | `ExportDisk` / `GetDiskInfo` (#177). Disk import is not supported. |
| `SupportsExportCompression` | true | `ExportDisk` honors `req.Compress` via `qemu-img -c` for qcow2 (#199). Default (Compress=false) is uncompressed. |
| `SupportedDiskTypes` | `qcow2`, `raw`, `vmdk` | QEMU-supported formats (qcow2 is the recommended default). |
| `SupportedNetworkTypes` | `virtio`, `e1000`, `rtl8139` | QEMU virtual NIC models advertised by `GetCapabilities`. |

For the full cross-provider matrix and resilience / observability narrative:

- [Provider capabilities matrix](providers-capabilities.md)
- [Operations — Resilience](../operations/resilience.md) — CircuitBreaker (G6 / v0.3.6) wraps every libvirt RPC.
- [Operations — Observability](../operations/observability.md)

## RPC support

- **Validate** — `virsh version` over the SSH connection.
- **Create** — define a libvirt domain XML, attach a qcow2 root disk, attach a NoCloud cloud-init ISO, start the domain.
- **Delete** — destroy + undefine domain, optionally remove volumes.
- **Power** — start / shutdown / destroy / reboot.
- **Describe** — domain state, VNC URL, IPs (via QEMU guest agent or DHCP lease).
- **Reconfigure** — online CPU/memory changes via `virsh setvcpus --live` / `virsh setmem --live` for VMs with hot-add headroom; disk expansion via `virsh blockresize` (see [Online reconfigure](#online-cpu-and-memory-reconfigure-203) and [Online disk expansion](#online-disk-expansion-201)).
- **SnapshotCreate / SnapshotDelete / SnapshotRevert** — `virsh snapshot-*` against qcow2 storage. Memory snapshots supported on running VMs (`spec.memory: true`). Synchronous; no `TaskRef` is returned.
- **Clone** — qcow2 overlay (linked) or volume copy (full), same-provider (#153). UEFI nvram re-pointed per clone; hot-add headroom preserved across class-override clones (#208/#221). See [Cloning](#cloning-153208221).
- **ImagePrepare** — lazy VM-create-time image import into a storage pool (#154). `VMImage.spec.prepare` controls the trigger. See [Image preparation](#image-preparation-154).
- **ExportDisk / GetDiskInfo** — disk export with accurate capability flags / formats (#177). Honors `Compress` for qcow2 (#199). Disk import is not implemented. These back the export side of cross-provider migration.
- **ConsoleUrl** — `vnc://<host>:<port>` parsed from `virsh dumpxml`.

## Prerequisites

- A libvirt host running `libvirtd` with KVM hardware acceleration (or nested virt for dev).
- SSH access from the provider pod into the libvirt host as a user that can talk to `qemu:///system` (typically a member of the `libvirt` group).
- Storage pools and networks already defined on the libvirt host. The provider does **not** create pools/networks — only consumes them.

## Authentication

The libvirt provider reads credentials from the Secret mounted at `/etc/virtrigaud/credentials` inside the provider pod. The provider also accepts `LIBVIRT_*` env vars as a secondary path (`internal/providers/libvirt/virsh.go:90-140`). **The Secret keys are read as files**; the key names matter:

| Secret key | File path | Used for |
|------------|-----------|----------|
| `username` | `/etc/virtrigaud/credentials/username` | SSH username (also injected into the URI if `qemu+ssh://`) |
| `password` | `/etc/virtrigaud/credentials/password` | Password auth (fallback; SSH key is strongly preferred) |
| `ssh-privatekey` | `/etc/virtrigaud/credentials/ssh-privatekey` | SSH private key in PEM (preferred) |

The provider needs at least one of password or ssh-privatekey set; if both are present, the SSH key takes precedence.

### Provider CR + Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: libvirt-credentials
  namespace: virtrigaud-system
type: Opaque
stringData:
  username: "virtrigaud"
  ssh-privatekey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: libvirt-lab
  namespace: virtrigaud-system
spec:
  type: libvirt
  endpoint: "qemu+ssh://virtrigaud@libvirt-host.example.com/system"
  credentialSecretRef:
    name: libvirt-credentials
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.3.9"
    service:
      port: 9090
      tls:
        enabled: true
        secretRef:
          name: provider-libvirt-tls
        insecureSkipVerify: false
```

## TLS / mTLS (v0.3.7+)

Starting in v0.3.7, the manager enforces that every Provider CR has a `spec.runtime.service.tls` block. A Provider without this block fails to reconcile and its status will show `TLSConfigured=False, Reason=TLSBlockMissing` — no Deployment is created.

For full mTLS details see [Security — mTLS](security/mtls.md).

### `spec.runtime.service.tls` fields

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | bool | Set `true` to enable mTLS. Set `false` for plaintext (dev/lab only; audit-flagged). |
| `secretRef.name` | string | Name of a `kubernetes.io/tls` or `Opaque` Secret containing `tls.crt`, `tls.key`, and `ca.crt`. |
| `insecureSkipVerify` | bool | Skip server certificate verification. Dev-only; never set in regulated environments. |

TLS material mounts at `/etc/virtrigaud/tls` inside the provider pod. Both manager and provider pin TLS 1.3. The `TLSConfigured` status condition reasons are `TLSBlockMissing`, `ExplicitlyDisabled`, `SecretRefMissing`, and `Enabled`.

## SSH host-key verification (v0.3.7+)

In v0.3.6 the provider set `no_verify=1` on the libvirt URI, skipping SSH host-key verification entirely. **In v0.3.7, host-key verification is on by default.** A missing `known_hosts` entry causes a hard-fail connection — the provider will not connect and the `ProviderAvailable` condition will report the failure.

### Adding `known_hosts` to the credentials Secret

Add a `known_hosts` key to the same Secret referenced by `spec.credentialSecretRef`. The provider reads it from `/etc/virtrigaud/credentials/known_hosts`.

Seed the file on the operator workstation:

```bash
ssh-keyscan -H <libvirt-host> >> known_hosts
```

Then include it in the Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: libvirt-credentials
  namespace: virtrigaud-system
type: Opaque
stringData:
  username: "virtrigaud"
  ssh-privatekey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
  # seed via: ssh-keyscan -H <libvirt-host> >> known_hosts
  known_hosts: |
    |1|REDACTED_HASH_1=|REDACTED_HASH_2= ssh-ed25519 REDACTED_HOST_PUBLIC_KEY
```

### Escape hatch: disable host-key verification

For labs and live-migration scenarios where host keys may change, you can disable verification via a provider env var. This is audit-flagged and not suitable for regulated/banking environments:

```yaml
spec:
  runtime:
    env:
      - name: LIBVIRT_INSECURE_SKIP_HOST_KEY_VERIFICATION
        value: "true"
```

!!! warning "Security note"
    `LIBVIRT_INSECURE_SKIP_HOST_KEY_VERIFICATION=true` removes the SSH host-key verification control. Use only in isolated lab environments or short-lived migration windows. Every use will appear in audit logs.

## Endpoint formats

| URI | Use case |
|-----|----------|
| `qemu+ssh://user@host/system` | Remote libvirt over SSH (production-typical) |
| `qemu+tls://host:16514/system` | Remote libvirt over TLS (where libvirtd is configured for TLS) |
| `qemu:///system` | Provider pod co-located with libvirtd (rare; requires socket mount) |

The CRD validates that the endpoint matches one of these schemes.

## Storage

Libvirt VMs live in **storage pools**. The provider does not create pools — they must already exist on the host. Common pool types:

- `dir` — directory on local disk (development, simple setups)
- `logical` (LVM) — LVM volume group (better performance, online resize is friendlier)
- `nfs` — shared NFS for multi-host clusters
- `rbd` — Ceph RBD (production)

Create one on the host before pointing VirtRigaud at it:

```bash
# Directory pool
virsh pool-define-as default dir --target /var/lib/libvirt/images
virsh pool-build default
virsh pool-start default
virsh pool-autostart default

# LVM pool
virsh pool-define-as lvm-pool logical --source-name vg-libvirt --target /dev/vg-libvirt
virsh pool-start lvm-pool
virsh pool-autostart lvm-pool
```

In the VMClass, point at the pool via `diskDefaults.storageClass`:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: standard
spec:
  cpu: 2
  memory: "4Gi"
  diskDefaults:
    type: qcow2
    size: "40Gi"
    storageClass: "default"     # maps to libvirt pool name
```

## Networking

Libvirt supports several network types; the provider models them via `VMNetworkAttachment`:

| Pattern | Libvirt construct | Typical use |
|---------|-------------------|-------------|
| Bridge | `<interface type='bridge'><source bridge='br0'/>` | Direct host bridge; appears on the physical LAN |
| Libvirt network | `<interface type='network'><source network='default'/>` | NAT'd virtual network |
| VLAN | `<interface type='bridge' ... ><vlan><tag id='100'/></vlan>` | Tagged on a host bridge |

Define a network on the host first:

```bash
virsh net-define /usr/share/libvirt/networks/default.xml
virsh net-start default
virsh net-autostart default
```

Then a VMNetworkAttachment that references it:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMNetworkAttachment
metadata:
  name: lan-default
spec:
  network:
    libvirt:
      networkName: default
  ipAllocation:
    type: DHCP
```

For a bridge:

```yaml
spec:
  network:
    libvirt:
      bridge: br0
      model: virtio
  ipAllocation:
    type: Static
    address: "192.168.1.100/24"
    gateway: "192.168.1.1"
    dns: ["8.8.8.8", "1.1.1.1"]
```

## Cloud-init (NoCloud ISO)

Unlike vSphere's `guestinfo` mechanism, libvirt uses the **NoCloud datasource**: the provider builds an ISO9660 image with `user-data` and `meta-data`, drops it into the storage pool, and attaches it as a virtual CD-ROM. The guest's cloud-init finds it at boot and applies it.

User-data placement, network-data for static IPs, and SSH keys all flow through this ISO — there is no per-VM out-of-band channel. Reference: `internal/providers/libvirt/cloudinit.go`.

Multi-NIC and static IPs are supported as long as the guest cloud-init understands network-config v2 (modern Ubuntu / Debian / RHEL-family cloud images do).

## VM example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-22-04
spec:
  source:
    libvirt:
      url: "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
      pool: default
      format: qcow2
  # As of v0.3.9, libvirt ImagePrepare is fully implemented (#154).
  # With prepare.onMissing: Fail, new VM creation is held with a
  # WaitingForDependencies condition until the image is available in the pool.
  # Omit this block entirely to skip the prepare gate and manage images out of band.
  prepare:
    onMissing: Fail
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: dev-workstation
spec:
  providerRef:
    name: libvirt-lab
  classRef:
    name: standard
  imageRef:
    name: ubuntu-22-04
  powerState: On
  disks:
    - name: root
      sizeGiB: 40
      type: qcow2
      storageClass: "default"
  networks:
    - name: lan
      networkRef:
        name: lan-default
  userData:
    cloudInit:
      inline: |
        #cloud-config
        hostname: dev-workstation
        users:
          - name: developer
            sudo: ALL=(ALL) NOPASSWD:ALL
            shell: /bin/bash
            ssh_authorized_keys:
              - "ssh-ed25519 AAAA..."
        packages:
          - qemu-guest-agent
          - docker.io
        runcmd:
          - systemctl enable --now qemu-guest-agent docker
```

!!! tip "Install `qemu-guest-agent` in the guest"
    Without it, the provider falls back to DHCP-lease scraping for IP discovery — slower and less reliable, and `Describe` will not report all interfaces.

## Snapshots

Libvirt snapshots are implemented via `virsh snapshot-create-as`. The provider:

1. Checks domain state.
2. Builds a snapshot name (auto-generates one if `nameHint` is empty).
3. Emits `--atomic` to ensure consistency.
4. Adds `--disk-only` only for stopped domains or when `spec.memory` is false.

Snapshots return synchronously (no `TaskRef`). All work has completed by the time the `SnapshotCreate` RPC returns.

## Memory snapshots (#202)

As of v0.3.9, libvirt supports RAM-inclusive snapshots (`SupportsMemorySnapshots=true`). Set `spec.memory: true` on a `VMSnapshot` CR:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMSnapshot
metadata:
  name: my-vm-pre-upgrade
  namespace: default
spec:
  vmRef:
    name: my-vm
  nameHint: "pre-upgrade"
  memory: true
  description: "Full checkpoint before upgrade"
```

| VM state at snapshot time | Result |
|--------------------------|--------|
| Running | Full checkpoint: disk state + RAM state captured. Restoring brings the VM back to the exact in-memory state. |
| Stopped | Disk-only snapshot; a WARN is logged. The resulting snapshot is still usable for rollback. |

A memory snapshot is significantly larger and slower than a disk-only snapshot (roughly disk size plus current RAM allocation). Storage backend must support qcow2; raw-on-LVM will fail on a running domain.

Memory snapshots are supported on all three providers — see [Memory Snapshots in the capabilities matrix](providers-capabilities.md#snapshot-operations).

## Cloning (#153/#208/#221)

As of v0.3.9, the libvirt `Clone` RPC is fully implemented (`SupportsLinkedClones=true`). Both full and linked clones are supported on the same provider.

| Clone type | Mechanism |
|-----------|-----------|
| **Linked** (default) | qcow2 overlay using `backing_file` — fast, space-efficient; guest writes go to the overlay, the base image is shared read-only. |
| **Full** | Volume copy via `qemu-img convert` — independent copy with no dependency on the source disk. |

Clone operations are same-provider only. Cross-provider movement uses [VM Migration](../migration/vm-migration-guide.md).

### Clone hardening

Clone hardening (#208/#221) provides two guarantees on top of the basic clone:

1. **UEFI nvram re-pointed**: each cloned VM receives its own independent copy of the UEFI `<nvram>` varstore. Source and clone do not share secure-boot state or EFI variables — modifying one does not affect the other.
2. **Hot-add headroom preserved**: if the source VM was created with a class that set `cpuHotAddEnabled` or `memoryHotAddEnabled`, a class-override clone preserves that headroom (the `<vcpu current=…>` ceiling and the `<memory>` balloon maximum are re-emitted in the cloned domain XML at the correct values, not defaulted).

### Creating a clone

Use the `VMClone` CR:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClone
metadata:
  name: clone-from-libvirt-vm
  namespace: default
spec:
  source:
    vmRef:
      name: my-source-vm
  target:
    name: my-cloned-vm
  options:
    type: LinkedClone    # or FullClone
```

See [VM Cloning](../guides/advanced/vm-cloning.md) for full VMClone semantics.

## Image preparation (#154)

As of v0.3.9, libvirt's `ImagePrepare` RPC is fully implemented (`SupportsImageImport=true`). `VMImage.spec.prepare` controls whether the image is fetched into a storage pool at VM-create time.

### How the prepare gate works

The prepare gate applies only to **import-style** sources — a source that must fetch a new artifact onto the provider (a libvirt `url`, a vSphere OVA, an HTTP/registry/DataVolume pull). When such a `VMImage` has a `prepare` block with `onMissing: Fail` and the image is not yet imported:

- The VM enters a `WaitingForDependencies` condition with message "image not prepared on provider".
- The controller requeues and retries once preparation completes.
- No `Create` is issued to the provider until the image is available.

A **reference-style** source — a libvirt pool-file `path`, an existing vSphere `templateName`/`contentLibrary`, or an existing Proxmox template — points at something **already present** on the provider, so there is nothing to import. As of v0.3.9 these create normally **even with `onMissing: Fail`**; the gate does not apply (a wrong path/template simply fails at `Create` time, where a missing backing artifact belongs). Likewise, a `VMImage` with **no** `prepare` block creates normally — the image must already be staged on the provider host.

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-22-04
spec:
  source:
    libvirt:
      url: "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
      pool: default
      format: qcow2
  prepare:
    onMissing: Fail   # hold VM creation until image is ready on provider
```

!!! tip "Operators staging images out of band"
    If you pre-stage base images on the libvirt host manually (outside VirtRigaud), omit the `prepare` block entirely. The provider will find the volume already in the pool and proceed with `Create` normally.

## Online CPU and memory reconfigure (#203)

As of v0.3.9, `SupportsReconfigureOnline=true` for libvirt. Online CPU/memory changes run via `virsh setvcpus --live` / `virsh setmem --live` — **no power-cycle required** — but only for VMs that were created with hot-add headroom provisioned.

### The hot-add-at-create requirement

The headroom is provisioned in the domain XML **at create time**. Set the VMClass flags before creating the VM:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: hotplug-enabled
  namespace: default
spec:
  cpu: 4
  memory: "8Gi"
  performanceProfile:
    cpuHotAddEnabled: true    # reserve headroom for live vCPU grow
    memoryHotAddEnabled: true # reserve headroom for live memory balloon grow
```

The created domain XML will contain:

```xml
<vcpu placement='static' current='4'>16</vcpu>   <!-- 4 boot online, 16 ceiling -->
<memory unit='MiB'>32768</memory>                 <!-- balloon maximum: 4× initial -->
<currentMemory unit='MiB'>8192</currentMemory>    <!-- initial guest-visible allocation -->
```

The `current=` attribute lets the guest boot with fewer vCPUs online than the ceiling; the extra slots are brought online by `setvcpus --live`. `<memory>` is the balloon maximum — `setmem --live` inflates the balloon up to this value.

### Ceilings and limits

| Resource | Ceiling formula | Hard cap |
|----------|----------------|----------|
| vCPUs | 4× initial (rounded up if needed) | 64 vCPUs |
| Memory | 4× initial | None (balloon max only; guest only uses `currentMemory` at boot) |

### When a power-cycle is still required

- The desired value exceeds the ceiling provisioned at create.
- The VM was created **without** the hot-add flags (includes all VMs created before v0.3.9).
- Any **decrease** in vCPU count or memory (shrink is never live).

The provider logs a WARN with the reason and the VirtualMachine controller falls back to a power-cycle reconfigure path.

To enable online reconfigure on an existing VM, delete and recreate it with a VMClass that has the hot-add flags set.

## Online disk expansion (#201)

As of v0.3.9, `SupportsDiskExpansionOnline=true` for libvirt. The provider can grow a running domain's primary disk **without a power-cycle** via `virsh blockresize`.

- **Grow-only**: a desired size ≤ current size is a no-op (logged at INFO).
- The primary disk target is resolved from the live domain topology (`virsh domblklist`) — naming-convention agnostic.
- After the block device is enlarged, a best-effort in-guest filesystem grow runs via the QEMU guest agent (`growpart` → `resize2fs` / `xfs_growfs /`). This step is non-fatal: the block device is already larger regardless of whether the guest agent succeeds.

### When manual filesystem grow is needed

The in-guest grow is skipped (WARN logged) when:

- The QEMU guest agent is not installed or not running.
- The guest uses a non-standard partition layout (LVM, multiple partitions, non-root XFS mount).

In these cases, finish the grow in the guest:

```bash
# inside the guest — example for a single ext4/XFS root partition
growpart /dev/vda 1
resize2fs /dev/vda1    # ext4
# or
xfs_growfs /           # XFS
```

### Triggering a disk expand

Patch `spec.disks[*].sizeGiB` to a larger value:

```bash
kubectl patch vm my-vm --type merge -p '{"spec":{"disks":[{"name":"data","sizeGiB":200,"type":"thin"}]}}'
```

The controller detects the delta and calls the provider's Reconfigure RPC with the new size.

## Console access

`Describe` populates `status.consoleURL` with a VNC URL extracted from `virsh dumpxml` (`internal/providers/libvirt/server.go`). The URL points at the libvirt host's VNC display port:

```bash
kubectl get vm dev-workstation -o jsonpath='{.status.consoleURL}'
# vnc://libvirt-host.example.com:5900
```

Connect with any VNC client (`vncviewer`, TigerVNC, RealVNC, noVNC).

!!! warning "VNC over the public internet"
    The libvirt VNC port is unauthenticated by default. Either firewall it to the operator network or front it with a TLS-terminating proxy. Do not expose 5900-590x to the open internet.

## Troubleshooting

### CircuitBreaker open on first deploy

This is the v0.3.6 G6 / I1 narrative — and it is genuinely useful.

If you see:

```promql
virtrigaud_circuit_breaker_state{provider_type="libvirt", provider="libvirt-lab"} == 2
```

immediately after a fresh `helm install`, the breaker is doing exactly what it was wired to do (G6 / PR #112): it has detected repeated RPC failures against the libvirt provider pod and has fast-failed further requests rather than spam the SSH endpoint.

The most common root cause in practice is an SSH-host issue on the libvirt side. The v0.3.6-rc1 smoke on the `vr1.lab.k8` lab cluster hit this with a `kex_exchange_identification: Connection closed by remote host` against the libvirt host — sshd was up but refusing the new connection (rate-limit / per-IP block / MaxStartups exhausted). The CircuitBreaker surfaced it immediately on `/metrics`; previous releases would have just spammed the manager log.

!!! note "Transient-SSH retry (v0.3.8, #191)"
    As of v0.3.8 the libvirt provider **retries transient SSH connection failures** — notably `kex_exchange_identification: Connection closed by remote host` — with bounded backoff before giving up. This absorbs short-lived `MaxStartups` bursts and brief `sshd` hiccups, so the breaker no longer trips on a single momentary refusal. It does **not** paper over a genuinely misconfigured host: operators must still tune the libvirt host's `sshd` `MaxStartups` and any `fail2ban` policy so the provider pod's source IP is not throttled or banned under sustained load. The retry buys resilience against blips, not against a hostile SSH policy.

**Triage steps**:

1. Open a shell on the libvirt host (out of band — don't try over the failing SSH path).
2. Inspect `sshd` logs (`journalctl -u ssh` or `/var/log/auth.log`).
3. Check for `MaxStartups` exhaustion, `fail2ban` bans on the provider pod's source IP, or AllowUsers/AllowGroups restrictions that the `virtrigaud` user does not satisfy.
4. Once SSH is healthy, the breaker self-recovers (default 30s reset; see [Resilience](../operations/resilience.md#circuitbreaker-on-the-provider-grpc-path-v036)). No manual intervention required.

### `qemu-guest-agent` not reporting IPs

`Describe` queries `virsh qemu-agent-command --domain <name> '{"execute":"guest-network-get-interfaces"}'`. If the guest does not have the agent installed and running, the provider falls back to libvirt's DHCP lease database, which is incomplete and slow.

Fix in the guest:

```bash
apt-get install qemu-guest-agent
systemctl enable --now qemu-guest-agent
```

Also confirm the VM XML includes the channel device for the agent (it should be auto-added by VirtRigaud at create time).

### "storage pool 'default' not found"

The provider does not create pools — list available pools on the host with `virsh pool-list --all`. If the VMClass's `storageClass` refers to a pool that does not exist, the provider returns `InvalidSpec` and the VM lands in `Pending` with a clear error in `status.conditions`.

### "permission denied" on the libvirt socket / SSH user can't talk to libvirt

The SSH user on the libvirt host must be in the `libvirt` group (Debian/Ubuntu) or have polkit rules granting access (RHEL/Fedora). Verify with:

```bash
ssh virtrigaud@libvirt-host virsh -c qemu:///system list
```

If that command fails, no amount of provider config will fix it.

### Snapshot fails on running domain

If the storage is not qcow2 (e.g., raw on LVM), `virsh snapshot-create-as` against a running domain may fail. Either:

- power off and snapshot offline, or
- switch the disk format to qcow2 (the recommended default in VirtRigaud's libvirt provider).

### Debug logging

```yaml
spec:
  runtime:
    logLevel: debug
    env:
      - name: LIBVIRT_DEBUG
        value: "1"
```

`LIBVIRT_DEBUG=1` enables verbose tracing of every `virsh` invocation and the SSH transport.

## Performance tips

- **virtio everywhere**: `disk.bus=virtio`, `network.model=virtio`, `vga` only when you need a console.
- **`cache=none` + `io=native` + `aio=native`** for production storage; the provider's default for qcow2 is `writeback` which is OK for dev.
- **CPU mode `host-passthrough`**: best raw performance, breaks live migration between dissimilar hosts. Use `host-model` if you need migration portability.
- **Hot-add requires at-create opt-in**: set `cpuHotAddEnabled`/`memoryHotAddEnabled` on the VMClass before creating the VM. VMs without these flags still require a power-cycle for capacity changes.

## API reference

- Full CRD field reference: [Generated CRD docs](../references/generated-crd-docs.md).
- Provider gRPC contract: [Generated gRPC docs](../references/grpc-api.md).
- Capability matrix (all providers): [Capabilities](providers-capabilities.md).

## Support

- Documentation: [VirtRigaud Docs](https://projectbeskar.github.io/virtrigaud/)
- Issues: [GitHub Issues](https://github.com/projectbeskar/virtrigaud/issues) — label `provider/libvirt`
- libvirt docs: [libvirt.org](https://libvirt.org/docs.html)
