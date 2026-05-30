<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Libvirt / KVM Provider

The Libvirt provider manages VMs on KVM/QEMU via the `libvirt` daemon, talking to it through `virsh` shelled out over SSH. It is the simplest provider to operate against and is widely deployed on-premises.

This page is aligned to **VirtRigaud v0.3.7**. Capability claims trace back to the provider's `GetCapabilities` response in `internal/providers/libvirt/server.go`.

!!! note "Implementation detail: virsh over SSH"
    Unlike most libvirt integrations that use the C `libvirt-go` bindings (which require cgo), VirtRigaud's libvirt provider shells out to the `virsh` CLI over an SSH tunnel to the remote libvirt host (`internal/providers/libvirt/virsh.go`). This keeps the provider image small (no libvirt-dev runtime) and avoids cgo entirely, at the cost of being more sensitive to SSH-host hygiene. See [Troubleshooting](#troubleshooting) for the SSH-host-issue narrative.

## Capabilities at a glance

The libvirt provider advertises the following via `GetCapabilities` (`internal/providers/libvirt/server.go:457-468`):

| Capability flag | Value | What it means |
|-----------------|-------|---------------|
| `SupportsReconfigureOnline` | **false** | CPU/memory changes via `virsh setvcpus`/`setmem` are applied with `--config`; full effect typically requires a power cycle. |
| `SupportsDiskExpansionOnline` | false | Disk grow requires power cycle (qemu-img resize + guest fs grow). |
| `SupportsSnapshots` | true | `virsh snapshot-create-as` against qcow2 storage. |
| `SupportsMemorySnapshots` | **false** | The capability flag is false. The code path *does* allow `--disk-only`-off snapshots on running domains, but the contract advertises no memory-snapshot support and the manager short-circuits memory-snapshot requests against this provider. |
| `SupportsLinkedClones` | **true** | Linked clones via qcow2 backing files. The matrix previously claimed `false` for this — corrected in v0.3.6 docs alignment. |
| `SupportsImageImport` | true | Image fetched from URL into a storage pool volume. |
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
- **Reconfigure** — `virsh setvcpus --config` / `virsh setmem --config`; `--live` is attempted on a best-effort basis but typically needs a restart for persistence.
- **SnapshotCreate / SnapshotDelete / SnapshotRevert** — `virsh snapshot-*` against qcow2 storage. Synchronous; no `TaskRef` is returned (libvirt operations are blocking from `virsh`'s perspective).
- **CloneCreate** — `virt-clone` for full clones; qcow2 `backing_file` linkage for linked clones.
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
    image: "ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.3.7"
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

Libvirt snapshots are implemented via `virsh snapshot-create-as` (`internal/providers/libvirt/provider_virsh.go:1381-1444`). The provider:

1. Checks domain state with `getDomainState`.
2. Builds a snapshot name (auto-generates one if `nameHint` is empty).
3. Emits `--atomic` to ensure consistency.
4. Adds `--disk-only` for stopped domains or when `includeMemory` is false.

The `SupportsMemorySnapshots=false` capability flag means the manager will not route memory-snapshot requests to this provider — operators who need memory state should snapshot through `virsh` directly out of band.

Snapshots return synchronously (no `TaskRef`). All work has completed by the time the `SnapshotCreate` RPC returns.

## Linked clones (corrected in v0.3.6)

`SupportsLinkedClones=true`. Libvirt linked clones are implemented as a new qcow2 volume with `backing_file` pointing at the source disk — the child only stores deltas. The matrix previously claimed `false` for this. The provider's `GetCapabilities` response has always reported `true`; v0.3.6 documentation now agrees.

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClone
metadata:
  name: dev-vm-02-clone
spec:
  source:
    vmRef:
      name: dev-vm-01
  target:
    name: dev-vm-02
  options:
    type: LinkedClone    # FullClone is also supported (virt-clone full pass)
```

Caveat: a linked clone's parent must remain on the same storage pool. Moving or deleting the parent breaks the child.

## Reconfigure (restart-required for full effect)

The provider attempts `virsh setvcpus --live --config` and `virsh setmem --live --config`. The `--live` flag works on a best-effort basis when the guest is running and has the virtio balloon / virtio vcpu drivers; `--config` always succeeds and persists across reboot.

The `SupportsReconfigureOnline=false` capability flag is the contract — the manager won't surprise an operator with an online reconfigure expectation against libvirt. Operators planning capacity changes against this provider should expect a power-cycle window.

Disk expansion currently requires the VM to be powered off (qemu-img resize + guest filesystem grow on next boot).

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
- **Hot-add is best-effort**: budget a power-cycle window for capacity changes.

## API reference

- Full CRD field reference: [Generated CRD docs](../references/generated-crd-docs.md).
- Provider gRPC contract: [Generated gRPC docs](../references/grpc-api.md).
- Capability matrix (all providers): [Capabilities](providers-capabilities.md).

## Support

- Documentation: [VirtRigaud Docs](https://projectbeskar.github.io/virtrigaud/)
- Issues: [GitHub Issues](https://github.com/projectbeskar/virtrigaud/issues) — label `provider/libvirt`
- libvirt docs: [libvirt.org](https://libvirt.org/docs.html)
