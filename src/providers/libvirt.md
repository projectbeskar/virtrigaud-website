<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Libvirt / KVM Provider

The libvirt provider manages VMs on KVM/QEMU hosts. It runs `virsh` and a few host tools (`qemu-img`, `genisoimage`, `isoinfo`) **on the libvirt host** over SSH. It is the provider that gained the most in v0.4.0: private cloud-init seeds, VM ownership stamps, snapshot revert, clone identity, honest reconfigure results, and an experimental clustered topology.

This page is aligned to **VirtRigaud v0.4.0**. Capability claims trace back to `GetCapabilities` and `clusteredCapabilities` in `internal/providers/libvirt/server.go`.

!!! note "How the provider drives libvirt (v0.4.0)"
    Every operation that changes state, and every read the manager acts on, still goes through **`virsh` run on the hypervisor host**. The provider reaches the host with an **in-process SSH client** (`internal/providers/libvirt/sshclient.go`), one persistent connection per host, so the provider image carries no `ssh`/`sshpass` binary and no key is written to disk. There is no cgo and no `libvirt-dev` in the image.

    A pure-Go [`go-libvirt`](https://github.com/digitalocean/go-libvirt) client exists in the provider (ADR-0008) but is **dormant by default**. It can be switched on only as an opt-in **shadow** read: `VIRTRIGAUD_LIBVIRT_NATIVE=shadow:describe,shadow:list` makes the provider run `Describe` and `ListVMs` through both paths, return the `virsh` answer, and count any divergence in a metric. A `native:` mode is accepted but is downgraded to shadow at v0.4.0: **no read is served from go-libvirt**. See [Libvirt shadow-compare reads](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/libvirt-shadow-reads.md).

## Topologies: single host or cluster

A libvirt `Provider` is bound to **one host** by default (`spec.topology: single`, the default). Since v0.4.0 it can instead front a **pool of bare hosts**:

| | Single host (default) | Cluster (`spec.topology: cluster`) |
|---|---|---|
| What the Provider fronts | One libvirt host, named by `spec.endpoint` | Every `Host` custom resource that references the Provider (grouped by a `HostPool`) |
| Placement | None: the VM lands on the one host | The manager's scheduler picks a host (filters on host health, schedulability, required `net.virtrigaud.io/<network>` labels, free capacity and an optional `VMPlacementPolicy`, then scores with the pool's `Spread` or `BinPack` strategy) |
| Per-VM calls | Addressed by domain name | Routed to the VM's bound host (`status.placement`) and owner-checked there |
| Maturity | Supported | **Experimental.** Opt-in, may still change. Host-to-host migration is not implemented. |

`spec.topology` is immutable once set, and the validating webhook accepts `cluster` only on `type: libvirt`. A clustered Provider's runtime always runs as one replica with the `Recreate` strategy, whatever `spec.runtime.replicas` says, so it is briefly unavailable during a rollout.

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: libvirt-cluster
  namespace: virtrigaud-system
spec:
  type: libvirt
  topology: cluster
  endpoint: qemu+ssh://virtrigaud@libvirt-host.example.com/system
  credentialSecretRef:
    name: libvirt-cluster-creds
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.4.0"
    service:
      port: 9443
      tls:
        enabled: true
        secretRef:
          name: libvirt-cluster-tls
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: HostPool
metadata:
  name: pool-a
  namespace: virtrigaud-system
spec:
  providerRef:
    name: libvirt-cluster
  strategy: Spread
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: Host
metadata:
  name: host-a
  namespace: virtrigaud-system
spec:
  providerRef:
    name: libvirt-cluster
  poolRef:
    name: pool-a
  endpoint: qemu+ssh://virtrigaud@host-a.example.com/system
  labels:
    net.virtrigaud.io/default: "true"
```

Placement, the `Host` and `HostPool` fields, restore guards, the re-attach runbook and migration into a clustered Provider are covered in the [Clustered libvirt guide](../guides/clustered/index.md) and its pages on [placement](../guides/clustered/placement.md), [operations](../guides/clustered/operations.md) and [backup and restore](../guides/clustered/backup-restore.md); migrating a VM into one is in [Migrating into a clustered Provider](../migration/clustered-target.md). A clustered Provider serves a subset of the single-host features; the differences are marked in the tables below.

## Capabilities at a glance

The provider advertises the following via `GetCapabilities` (`internal/providers/libvirt/server.go`). A clustered Provider reports only what is routed to a host (`clusteredCapabilities`).

| Capability flag | Single host | Clustered | What it means |
|-----------------|-------------|-----------|---------------|
| `SupportsReconfigureOnline` | true | true | Online CPU/memory changes via `virsh setvcpus/setmem --live` for VMs created with hot-add headroom (see [Reconfigure](#reconfigure)). Other changes are applied to the definition and take effect at the next power cycle. |
| `SupportsHonestReconfigure` | true | true | `Reconfigure` reports *applied*, *restart required* or *failed* and never claims a change it did not make. |
| `SupportsDiskExpansionOnline` | true | true | Live disk grow via `virsh blockresize` plus a best-effort in-guest filesystem grow; grow-only. |
| `SupportsSnapshots` | true | true | `virsh snapshot-create-as`. |
| `SupportsMemorySnapshots` | true | true | RAM-inclusive snapshots of a **running** VM. |
| `SupportsLinkedClones` | **false** | **false** | Linked clones are **disabled** in v0.4.0 (see [Cloning](#cloning)). Full clones work. |
| `SupportsImageImport` | true | not reported | `ImagePrepare` for `source.libvirt.url`. A clustered Provider does not prepare images. |
| `SupportsImageArtifactIdentity` | true | not reported | Prepared images are named, stamped and published by `VMImage` identity (ADR-0009). |
| `SupportsDiskExport` | true | true | `ExportDisk` / `GetDiskInfo` (export formats: `qcow2`, `raw`; clustered: `qcow2`). |
| `SupportsDiskImport` | true | true | `ImportDisk` (`qcow2`, `raw`, `vmdk`) with the administrator size limit. |
| `SupportsExportCompression` | true | not reported | `qemu-img -c` for qcow2 exports. |
| Export / import backends | `pvc`, `s3`, `nfs` | `s3`, `nfs` | Relay transfer mode only. |
| `SupportsClustering` | false | true | The Provider answers `ListHosts` / `GetHostInfo`. |
| `SupportedDiskTypes` | `qcow2`, `raw`, `vmdk` | same | QEMU formats. VM disks VirtRigaud creates are qcow2. |
| `SupportedNetworkTypes` | `virtio`, `e1000`, `rtl8139` | same | NIC models advertised by `GetCapabilities`. |

For the cross-provider matrix and the resilience / observability narrative:

- [Provider capabilities matrix](providers-capabilities.md)
- [Operations — Resilience](../operations/resilience.md): the CircuitBreaker wraps every libvirt RPC.
- [Operations — Observability](../operations/observability.md)

## Behaviour at a glance: snapshot, revert, clone, reconfigure, disks

| Area | libvirt behaviour at v0.4.0 | Code |
|------|-----------------------------|------|
| Snapshot create | A VM that is **off**, or a request without memory, gets an **external disk-only** snapshot; a **running** VM with `snapshotConfig.includeMemory: true` gets an **internal** full-system snapshot (RAM included). `includeMemory` on an off VM is downgraded to disk-only with a warning. A shut-off VM's CD-ROMs (the cloud-init seed) are ejected for the duration of the snapshot and put back. Synchronous (no task). | `server.go` (`snapshotCreateWith`), `snapshot_media.go` |
| Snapshot revert | `spec.snapshot.revertToRef` on the `VirtualMachine`; the VM must be **powered off**; libvirt 9.9 or later for external snapshots. A disk-only snapshot taken **while the VM ran** (or by v0.3.11 or earlier) of a VM with a cloud-init CD-ROM is **refused** on revert. | `snapshot_readonly_disks.go`, `internal/controller/virtualmachine_snapshot_revert.go` |
| Snapshot delete | Refused, nothing changed, while another snapshot of the VM is stored in a file the delete would merge away: **delete memory snapshots before the disk-only snapshot they sit on.** Removes the overlay file libvirt leaves behind. | `snapshot_delete_guard.go`, `snapshot_overlay_cleanup.go` |
| Clone | **Full clone only**; the source VM must be **powered off**; the clone gets its own cloud-init identity. | `clone.go`, `clone_source_state.go`, `clone_seed.go` |
| Reconfigure | CPU and memory, plus a grow-only primary disk. Result is *applied*, *restart required* or *failed*. | `reconfigure.go`, `reconfigure_online.go` |
| `spec.disks` | **Not attached.** `DisksApplied=False/NotSupportedByProvider` is set. Only the VMClass `diskDefaults.size` (the root disk) is applied. | `internal/controller/virtualmachine_disks_applied.go` |

The sections below give the detail.

## RPC support

- **Validate**: `virsh list --all --name` over the SSH connection (the provider also runs `virsh version` once at startup). A clustered Provider checks instead that its host registry loaded at least one host; per-host reachability is reported through `ListHosts` / `GetHostInfo`.
- **Create**: names the domain `<namespace>.<name>`, stamps it with its owner, copies or creates the qcow2 root disk in the `default` pool, builds a private NoCloud seed ISO, defines the domain. The VM is left **powered off**; the `VirtualMachine` controller powers it on when `spec.powerState` is `On`.
- **Delete**: undefines the domain and removes only the files that are provably its own (see [Delete](#delete)).
- **Power**: start / shutdown / destroy / reboot, idempotent.
- **Describe**: domain state, VNC URL, IPs (see [`status.ips`](#statusips)).
- **Reconfigure**: see [Reconfigure](#reconfigure).
- **SnapshotCreate / SnapshotDelete / SnapshotRevert**: see [Snapshots](#snapshots). All synchronous; no `TaskRef` is returned.
- **Clone**: see [Cloning](#cloning).
- **ImagePrepare**: lazy import of a `source.libvirt.url` image (single-host only), see [Images](#images).
- **ExportDisk / ImportDisk / GetDiskInfo**: back the export and import sides of [cross-provider migration](../migration/user-guide.md).
- **Console URL**: `Describe` returns `vnc://<host>:<port>` parsed from `virsh dumpxml`.
- **ListHosts / GetHostInfo**: clustered topology only.

## Prerequisites

- A libvirt host running `libvirtd` with KVM acceleration (or nested virtualization for development). **libvirt 9.9 or later** if you want to revert snapshots.
- SSH access from the provider pod to the host as a user that can use `qemu:///system`, with a POSIX-compatible login shell.
- libvirt's `default` storage pool at **`/var/lib/libvirt/images`**. If the host has no `default` pool the provider creates one there; a `default` pool at any other path is never modified and creates fail with `InvalidSpec`.
- On the host: `qemu-img` (from a QEMU with the CVE-2024-4467 fix: 9.0.2, 8.2.6, 7.2.13 or later, or a backport), `genisoimage` and `isoinfo`, and for clustered or migration paths `flock` and `timeout`.
- The **cloud-init seed directory** (new in v0.4.0, below).
- Optional, for clone/export of VMs that have an external snapshot and for the disk in-use checks to read libvirt's `0600` overlays: sudo rules for the exact `qemu-img` commands (`VR_DISK_READ`, `VR_CLONE_COPY`, `VR_EXPORT_COPY`).

Host preparation (packages, SSH user, sudo grants, known_hosts, rate limits, pools) is in [Libvirt Host Preparation](../operations/libvirt-host-prepare.md). The authoritative description of the sudo rules and pool-directory permissions is [libvirt clones and the linked-clone dependency](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/libvirt-clones.md#what-the-copies-run-as-root).

!!! warning "Seed directory on every host, before you roll the v0.4.0 provider"
    New cloud-init seeds are built in `VIRTRIGAUD_LIBVIRT_SEED_DIR` (default `/var/lib/libvirt/virtrigaud-seeds`). If the directory is missing and the SSH user cannot create it, is not owned by the SSH user, or is readable or writable by group or others, **every create on that host fails** (and so does every clone of a VM that has a seed) with a retryable `refusing to stage cloud-init data`. Create it once on each host, including migration target hosts and every host of a clustered Provider:

    ```bash
    install -d -m 0711 -o virtrigaud -g virtrigaud /var/lib/libvirt/virtrigaud-seeds
    ```

    Details, including hosts shared by Providers with different SSH users: [libvirt domain ownership: cloud-init seed directory](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/libvirt-domain-ownership.md#cloud-init-seed-directory).

## Authentication

The libvirt provider reads credentials from the Secret mounted at `/etc/virtrigaud/credentials` inside the provider pod. The `LIBVIRT_USERNAME`, `LIBVIRT_PASSWORD` and `LIBVIRT_SSH_PRIVATE_KEY` environment variables are read **first**, and the mounted files are the fallback for any value they leave unset. **The Secret keys are read as files**; the key names matter:

| Secret key | File path | Used for |
|------------|-----------|----------|
| `username` | `/etc/virtrigaud/credentials/username` | SSH username (also taken from the endpoint URI) |
| `password` | `/etc/virtrigaud/credentials/password` | Password authentication |
| `ssh-privatekey` | `/etc/virtrigaud/credentials/ssh-privatekey` | SSH private key in PEM (ignored when `password` is also present, see below) |
| `known_hosts` | `/etc/virtrigaud/credentials/known_hosts` | Pinned host keys, see [SSH host-key verification](#ssh-host-key-verification) |

At least one of `password` or `ssh-privatekey` is required. **If both are present the password is used**, not the key (`sshAuthMethods` in `sshclient.go`): put only the key in the Secret unless you mean to use the password.

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
    image: "ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.4.0"
    service:
      port: 9443
      tls:
        enabled: true
        secretRef:
          name: provider-libvirt-tls
        insecureSkipVerify: false
```

A Provider in another namespace than its consumers must also set `spec.consumerNamespaceSelector`; see [Cross-namespace references](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/cross-namespace-references.md).

## TLS / mTLS (v0.3.7+)

Starting in v0.3.7, the manager enforces that every Provider CR has a `spec.runtime.service.tls` block. A Provider without this block fails to reconcile and its status will show `TLSConfigured=False, Reason=TLSBlockMissing`: no Deployment is created.

For full mTLS details see [Security — mTLS](security/mtls.md).

### `spec.runtime.service.tls` fields

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | bool | Set `true` to enable mTLS. Set `false` for plaintext (dev/lab only; audit-flagged). |
| `secretRef.name` | string | Name of a `kubernetes.io/tls` or `Opaque` Secret containing `tls.crt`, `tls.key`, and `ca.crt`. |
| `insecureSkipVerify` | bool | Skip server certificate verification. Dev-only; never set in regulated environments. |

TLS material mounts at `/etc/virtrigaud/tls` inside the provider pod. Both manager and provider pin TLS 1.3. The `TLSConfigured` status condition reasons are `TLSBlockMissing`, `ExplicitlyDisabled`, `SecretRefMissing`, and `Enabled`.

## SSH host-key verification

Host-key verification is **on by default** (since v0.3.7). A missing `known_hosts` entry is a hard failure: the provider will not connect. The failure shows in the provider pod log and as `Ready=False` / `ProviderError` on the VMs that use the Provider; `ProviderAvailable` only reflects whether the provider Deployment has a ready replica, so it stays `True`. The check runs again on every reconnect, so a rotated key is honoured on the next dial.

Seed the file on the operator workstation:

```bash
ssh-keyscan -H <libvirt-host> >> known_hosts
```

Then include it in the Secret referenced by `spec.credentialSecretRef`:

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

On a clustered Provider each `Host` can carry its own credentials and `known_hosts` through `Host.spec.credentialSecretRef`.

### Escape hatch: disable host-key verification

For labs and short migration windows you can disable verification with a provider environment variable. This is audit-flagged and not suitable for regulated environments:

```yaml
spec:
  runtime:
    env:
      - name: LIBVIRT_INSECURE_SKIP_HOST_KEY_VERIFICATION
        value: "true"
```

!!! warning "Security note"
    `LIBVIRT_INSECURE_SKIP_HOST_KEY_VERIFICATION=true` removes the SSH host-key verification control. Use only in isolated lab environments. Every use is logged.

## Endpoint formats

| URI | Use |
|-----|-----|
| `qemu+ssh://user@host/system` | The supported form. The provider runs `virsh -c qemu:///system` on the host over SSH. |
| `qemu:///system`, `qemu+tls://...`, `qemu+tcp://...` | Accepted by the CRD, but the provider then runs a **local** `virsh` in the pod. This path is not exercised by the project's tests or lab runs; do not rely on it. |

A `Host` of a clustered Provider needs a `qemu+ssh://[user@]host[:port]/system` (or `/session`) endpoint; the CRD rejects any other form.

## Storage

All VM disks, imported migration disks and prepared images live in libvirt's **`default` storage pool at `/var/lib/libvirt/images`**. The provider does not select another pool: VMClass `diskDefaults.storageClass` and `spec.disks[].storageClass` are **not** mapped to libvirt pools. A host whose `default` pool is elsewhere is refused with `InvalidSpec` and never modified; to put VM storage on shared or faster media, mount it **at** `/var/lib/libvirt/images`.

The pool directory must be writable only by `root` and the provider's SSH user (or sticky). The provider logs a warning otherwise, and a full clone or disk export from a group-writable directory is refused with `FailedPrecondition`. Check with `stat -c '%a %U:%G' /var/lib/libvirt/images`.

Every disk VirtRigaud creates is created mode `0640` and given to `libvirt-qemu:kvm`. The provider's SSH user needs to read VM disks (disk in-use checks, export, full clone): make it a member of `kvm`, or grant the `VR_DISK_READ` sudo rule from the [host preparation page](../operations/libvirt-host-prepare.md).

The root disk size comes from the VMClass:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: standard
spec:
  cpu: 2
  memory: "4Gi"
  diskDefaults:
    type: thin
    size: "40Gi"
```

`diskDefaults.size` is a floor: a disk already that large is not shrunk. Disks created from an image are qcow2 whatever the VMClass `type` says.

## Networking

The provider reads the **`libvirt` block** of a `VMNetworkAttachment` (only the block of the Provider's type is read):

| Attachment field | Libvirt construct | Notes |
|------------------|-------------------|-------|
| `spec.network.libvirt.networkName` | `<interface type='network'><source network='...'/>` | A libvirt-managed network (for example the NAT `default`). |
| `spec.network.libvirt.bridge.name` | `<interface type='bridge'><source bridge='...'/>` | A host bridge. `bridge` is an object with a `name`, not a string. Wins over `networkName` when both are set. |
| `spec.network.libvirt.model` | `<model type='...'/>` | `virtio` (default), `e1000`, `e1000e`, `rtl8139`, `pcnet`, `ne2k_pci`. |
| none of the above | `<interface type='user'>` | User-mode networking; libvirt holds no DHCP lease for it. |

Not applied on libvirt: **VLAN tags**, **static IP, gateway and DNS** (`VirtualMachine.spec.networks[].ipAddress` and friends, `VMNetworkAttachment.spec.ipAllocation`). `spec.networks[].macAddress` does not reach any provider yet: the manager drops it (ADR-0014). The generated cloud-init network configuration is DHCP on `eth0`, `ens3`, `enp0s3` and `enp1s0`. To give a libvirt guest a static address, put a `network-config` equivalent in your own `spec.userData`.

Define the network on the host first:

```bash
virsh net-define /usr/share/libvirt/networks/default.xml
virsh net-start default
virsh net-autostart default
```

A NAT network and a bridge:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMNetworkAttachment
metadata:
  name: lan-default
spec:
  network:
    libvirt:
      networkName: default
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMNetworkAttachment
metadata:
  name: lan-bridge
spec:
  network:
    libvirt:
      bridge:
        name: br0
      model: virtio
```

!!! note "Bridged networking and IP discovery"
    On a host bridge the LAN's DHCP server answers, not libvirt, so libvirt holds **no lease** and `status.ips` stays empty unless the QEMU guest agent runs in the guest. See [`status.ips`](#statusips).

On a clustered Provider, every attachment contributes a **required `Host` label** `net.virtrigaud.io/<name>: "true"`: only a host that carries it is a candidate. The label name is the attachment's `networkName`, or its bridge name when no `networkName` is set. Set only one of the two: if both are set, the NIC is attached to the bridge but the VM is scheduled by the `networkName` label.

## Cloud-init (NoCloud seed)

Unlike vSphere's `guestinfo`, libvirt uses the **NoCloud datasource**: the provider builds an ISO9660 image with `user-data` and `meta-data`, attaches it as a read-only CD-ROM and the guest's cloud-init applies it at boot. The code is in `internal/providers/libvirt/cloudinit.go`.

**Seeds are private (v0.4.0).** The user-data may carry passwords, keys and tokens, so each seed is built in its own directory inside the [seed directory](#prerequisites): the ISO is `0600` (libvirt hands it to the qemu user when the domain starts), `user-data` and `meta-data` are deleted once the ISO is built, and the SSH user keeps a private copy `cloud-init.private.iso` that clones read. Earlier releases built seeds under `/tmp` with the SSH user's umask, readable by any local user of the host. Seeds of existing VMs stay where they are; leftovers from earlier releases need the one-time fix in [Upgrading from v0.3.11](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/upgrading.md#leftovers-from-earlier-releases). The seed holds the user-data in plaintext for as long as the VM exists: exclude the seed directory from host backups or encrypt them. The model is described in [Private cloud-init seeds](../guides/security-model.md#private-cloud-init-seeds-libvirt); the host side is in [Libvirt Host Preparation](../operations/libvirt-host-prepare.md#cloud-init-seed-directory).

!!! warning "Breaking change: the default cloud-init no longer creates a user"
    A libvirt VM created **without** `spec.userData` used to get a built-in `ubuntu` user with a fixed SSH key and passwordless sudo. That is gone. The default seed now sets only the hostname and installs and starts `qemu-guest-agent`. Supply your own `spec.userData` with a user and an `ssh_authorized_keys` entry. VMs already created keep whatever the old default put in the guest: remove it by hand if you do not want it (see [Upgrading from v0.3.11](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/upgrading.md)).

User-data is passed through unchanged, with these details:

- The seed's `instance-id` is the domain name (`<namespace>.<name>`); a [clone](#clone-identity) gets `virtrigaud-<uid>`.
- `spec.userData.cloudInit.inline` and `secretRef` are resolved by the manager and merged; the provider writes the result into the seed.
- The ISO's `meta-data` carries a DHCP (IPv4 and IPv6) network configuration for the common NIC names. Static addressing is not generated (see [Networking](#networking)).

## VM example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-22-04
spec:
  source:
    libvirt:
      url: "https://cloud-images.example.com/jammy/jammy-server-cloudimg-amd64.img"
      format: qcow2
  # onMissing: Import (the default) prepares the image on the Provider when
  # the first VM needs it. Fail and Wait do not prepare: they hold new VMs
  # until something else has prepared the image.
  prepare:
    onMissing: Import
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
  powerState: "On"
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
        runcmd:
          - systemctl enable --now qemu-guest-agent
```

Quote `powerState` values (`"On"`): an unquoted `On` is a boolean in YAML 1.1 and is rejected by the API server.

!!! tip "Install `qemu-guest-agent` in the guest"
    The provider adds the guest-agent channel to every domain, but the agent has to run inside the guest. Without it, a guest on a bridge shows no address. If you supply your own `spec.userData`, install and enable the agent there.

## Domain names and ownership

A new domain is named **`<namespace>.<name>`**, so two namespaces' `web` VMs are two domains with two disks and two seeds. A name longer than 200 bytes is shortened with a hash. External tooling must read `status.id` instead of assuming "domain name equals `VirtualMachine` name"; existing VMs keep their old (bare) names.

Every domain is **stamped with its owner** (`<virtrigaud:owner uid=… namespace=… name=…/>` in the domain metadata; read it with `virsh metadata <domain> --uri https://virtrigaud.io/xmlns/libvirt/owner/v1`). The provider never binds a `VirtualMachine` to a domain unless the stamp carries that VM's UID: a create that finds a same-named domain with no stamp, another UID, or an unreadable stamp is **refused** (`AlreadyExists`/`Conflict`); a domain with the requester's UID is returned as an idempotent success. A clone never inherits its source's stamp. Names that `virsh` would resolve as a numeric ID or a UUID are refused. Full rules: [libvirt domain ownership](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/libvirt-domain-ownership.md).

## Images

A `VMImage` with `source.libvirt.path` names a **base image already on the host**; one with `source.libvirt.url` is **prepared** (downloaded, checked, converted to qcow2) by `ImagePrepare`.

- **Path images are confined and always copied.** The path is resolved on the host and must be a regular file **directly inside** an allowed image directory, not a disk or backing file of any domain, not a VirtRigaud-reserved name (`*-disk.qcow2`, `*-migrated.qcow2`, seed ISOs, dotfiles), and self-contained (no backing file or external data file). It is **copied into the VM's own disk** and never attached in place, so VMs never share a disk and deleting a VM never deletes the image. The allowed directories are `VIRTRIGAUD_LIBVIRT_IMAGE_DIRS` (a comma- or colon-separated list on the provider pod, default `/var/lib/libvirt/images`); setting it **replaces** the default:

    ```yaml
    spec:
      runtime:
        env:
          - name: VIRTRIGAUD_LIBVIRT_IMAGE_DIRS
            value: "/srv/golden-images,/var/lib/libvirt/images"
    ```

    Keep `/var/lib/libvirt/images` in the list if you use URL images. On a shared pool, keep the image catalog in a separate directory that only administrators write to.
- **URL images are prepared by identity (ADR-0009).** The prepared file is `<pool dir>/<namespace>.<name>_<16 hex>.qcow2`, read-only (`0444`), owned by the SSH user, with a stamp file; it is reused only when the stamp matches the `VMImage` UID and source digest, never by bare name. A source that fails for good (HTTP 4xx, checksum mismatch, unreadable image) shows `InvalidSource` instead of being retried. Downloads are one transfer, bounded in time (`spec.prepare.timeout`) and size (`VIRTRIGAUD_LIBVIRT_IMAGE_MAX_DOWNLOAD_GIB`, default 256). The pool directory must be an allowed image directory on a filesystem with hard links.
- **The prepare gate** applies to import-style sources only: with the default `onMissing: Import` the image is prepared when the first VM needs it; with `Fail` or `Wait` nothing is prepared and new VMs wait in `WaitingForDependencies` until the image has been prepared out of band. A reference-style source (`path`) is not gated.

Full rules, including the stamp and what is refused: [Image preparation](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/image-preparation.md#libvirt-image-paths-sourcelibvirtpath).

## Snapshots

A `VMSnapshot` names a VM and, optionally, `snapshotConfig`:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMSnapshot
metadata:
  name: my-vm-pre-upgrade
  namespace: default
spec:
  vmRef:
    name: my-vm
  snapshotConfig:
    name: pre-upgrade
    description: "Full checkpoint before upgrade"
    includeMemory: true
```

| VM state at snapshot time | `includeMemory: true` | `includeMemory: false` |
|---------------------------|-----------------------|------------------------|
| Running | **Internal** full-system checkpoint: disks and RAM. Needs qcow2 storage. | **External disk-only** snapshot. The CD-ROM is excluded, but the stored definition still holds the seed, so this snapshot **cannot be reverted** (below). |
| Off | Downgraded to disk-only with a warning (no RAM to capture). | **External disk-only** snapshot, taken with the CD-ROMs ejected. **This is the revertible kind.** |

The downgrade of `includeMemory` on an off VM is only a provider log line: no condition or event says it happened. A snapshot of a **paused** VM is disk-only without the CD-ROM ejection, so it cannot be reverted. Snapshot names are sanitised (letters, digits, `_`, `.`, `-`; at most 64 characters). A memory snapshot is larger and slower than a disk-only one.

### Revert

Name the snapshot in `spec.snapshot.revertToRef` on the `VirtualMachine`. The VM must already be **powered off** (`spec.powerState: "Off"`): VirtRigaud never powers a VM off for a revert. Watch `status.snapshotRevert` and the `SnapshotReverted` condition (`True/Reverted` on success, `False/RevertFailed` on failure, `False/WaitingForPowerOff` while it waits). The revert is sent at most once per request; to revert to the same snapshot again, remove the field, wait for `status.snapshotRevert` to disappear, then set it again. After the revert, power the VM on yourself.

```bash
kubectl patch vm my-vm --type merge -p '{"spec":{"powerState":"Off"}}'
kubectl patch vm my-vm --type merge \
  -p '{"spec":{"snapshot":{"revertToRef":{"name":"my-vm-pre-upgrade"}}}}'
kubectl get vm my-vm -o jsonpath='{.status.snapshotRevert.phase}{"\n"}'
```

libvirt-specific rules:

- **Take the snapshot with the VM powered off if you want to revert it.** libvirt reverts an external snapshot by rebuilding the disks from the definition the snapshot stored. A disk-only snapshot that stored the cloud-init CD-ROM makes libvirt rewrite the CD-ROM to an overlay QEMU cannot open (AppArmor), and the VM no longer starts. The provider therefore ejects the CD-ROMs from a **shut-off** VM's definition while it snapshots, and **refuses** to revert a snapshot that stored a CD-ROM or read-only disk with media (`RevertFailed`, nothing changed, with guidance to take a new snapshot while the VM is off). Snapshots taken while the VM ran, and every snapshot taken by v0.3.11 or earlier, fall in this group.
- **Memory snapshots** of a running VM are internal and are reverted in place; they are not refused.
- libvirt older than 9.9 cannot revert an external snapshot; the provider's error is reported as `RevertFailed`.
- A revert refused for good (`FailedPrecondition`) is not retried and its message carries the provider's guidance instead of a "set it again" hint.
- The revert re-inserts the CD-ROM (the seed) afterwards and checks that no read-only disk was moved; if it cannot, it reports `RevertFailed` ("reverted, but ...") and keeps a record so the next snapshot, revert, start or reboot of the VM repairs it. An interrupted ejection leaves the seed CD-ROM empty until then: do not start such a VM by hand with `virsh start`.
- libvirt creates the overlay of a disk-only snapshot and of a revert with mode `0600`, and the provider's disk in-use check reads every domain's disk chain. The SSH user therefore needs the `VR_DISK_READ` sudo rule over the pool directory, or the check fails closed with "permission denied reading a disk image".

Full flow, status fields, GitOps notes and the repair procedure for a VM broken by a revert on a v0.4.0 release candidate: [Reverting a VirtualMachine to a VMSnapshot](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-snapshot-revert.md#libvirt).

### Delete order with memory snapshots

A memory snapshot taken after a disk-only one is stored **inside the disk-only snapshot's overlay**. Deleting the disk-only snapshot makes libvirt merge that overlay away, and the memory snapshot's data would be lost. Since v0.4.0 the provider **refuses** that delete before anything changes, answering with the names to delete first. The `VMSnapshot` keeps its finalizer with `Ready=False/DeleteBlocked`, shows the provider's answer, and is re-checked with a backoff of up to 5 minutes. **Delete the memory snapshots first, then the disk-only snapshot.** (`virtrigaud.io/force-delete: "true"` still removes the `VMSnapshot`, leaving the snapshot on the host.) Deleting a memory snapshot is never refused by this check.

A memory snapshot that v0.3.11 or a v0.4.0 release candidate already lost keeps only metadata; the provider deletes that metadata when it can prove the data is gone, and otherwise asks you to power the VM off and delete again. The check is not atomic with the delete: do not create a snapshot of a VM while you delete another of its snapshots. See [Deleting memory and disk-only snapshots of the same VM](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/libvirt-clones.md#deleting-memory-and-disk-only-snapshots-of-the-same-vm).

`SnapshotDelete` also removes the primary disk's overlay files libvirt leaves behind (`<domain>-disk.<snapshot>` and the `<domain>-disk.<epoch>` a revert creates). Overlays of additional data disks and of snapshots deleted before v0.4.0 are not swept.

## Cloning

A `VMClone` of a libvirt VM is a **full clone**: an independent qcow2 copy of the source's primary disk, flattening any backing chain. The clone is named `<target namespace>.<target name>` and is left powered off unless `spec.options.powerOn: true`.

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
    type: FullClone
    powerOn: false
```

- **Linked clones are disabled.** A linked clone's backing file is the source's live disk and nothing freezes it; powering the source on corrupts the clone. A `VMClone` with `type: LinkedClone` fails before any provider call with `LinkedCloneUnsupported`. Recreate it as `FullClone`. Linked clones made by an earlier release keep working, and the provider refuses to delete, revert or snapshot their source while they exist (`DeleteBlocked`, `VM_DISK_IN_USE`).
- **The source must be powered off.** `qemu-img convert` cannot read a disk a running QEMU holds. A running source leaves the `VMClone` `Pending` with `Ready=False`, reason `SourceMustBePoweredOff`, re-checked on a backoff and at once when the source's power state changes. To clone a running VM, set its `spec.powerState: "Off"`, wait for the clone to become `Ready`, then power it back on. (vSphere clones running VMs; libvirt does not.)
- Clone is same-provider. On a clustered Provider it is routed to the source's host and the clone lands there. For movement between providers see [VM Migration](../migration/vm-migration-guide.md).
- A UEFI source's `<nvram>` varstore is copied per clone. A clone does not inherit the source's owner stamp; it is stamped with its target `VirtualMachine`.
- **Creating a `VMClone` is read access to the source VM's data.** The clone's disk is a full copy, its seed carries the source's user-data (which may hold secrets), and on libvirt `spec.customization.userData.cloudInit.inline` becomes the clone's user-data, run as root on first boot. Grant `create` on `vmclones` only to subjects trusted with read access to every VM in that namespace.

See [VM Cloning](../guides/advanced/vm-cloning.md) for `VMClone` semantics.

### Clone identity

A full clone copies the source's disk, including cloud-init's record of the instance it last ran as. To stop two VMs sharing SSH host keys, a clone of a VM that boots from a NoCloud seed gets a **seed of its own** (single host and clustered):

| | The clone's seed |
|---|---|
| `instance-id` | `virtrigaud-<target VirtualMachine uid>`: a new instance, identical on a retried clone |
| `local-hostname` | `spec.customization.hostname` (with `domain` as FQDN) when set, else the target VM's name |
| user-data | `spec.customization.userData.cloudInit.inline` when set; otherwise the source's, with its top-level `hostname:` and `fqdn:` rewritten |
| other files | the source's `network-config` and `vendor-data` unchanged |

cloud-init sees a new instance on first boot, regenerates the SSH host keys and re-runs every per-instance module (`runcmd`, `packages`, `users`, ...). It does **not** regenerate `/etc/machine-id` (seal the source with `cloud-init clean --machine-id` if clones need their own), and a static address in the source's network configuration is carried over. User-data keys that undo the new identity (`ssh_keys`, `ssh_deletekeys: false`, `preserve_hostname: true`, `manual_cache_clean: true`) are logged by name. A source without a seed ISO gives a clone without one. Details: [A clone's cloud-init identity](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/libvirt-clones.md#a-clones-cloud-init-identity).

## Reconfigure

`Reconfigure` changes the persistent definition **first** (`--config`), then the running domain (`--live`), and reports one of three results (`SupportsHonestReconfigure`):

| Result | Meaning | Manager records |
|--------|---------|-----------------|
| **Applied** | Every change is in the running domain and the definition (or, for a VM that is off, the definition it boots from) | `Reconfiguring=False/ReconcileSuccess` |
| **Restart required** | Persisted, but the running domain cannot take it; takes effect at the next **power cycle** (off, then on; a guest reboot is not enough) | `Reconfiguring=True/RestartRequired` |
| **Failed** | A change could be applied neither way, or the host could not be reached | `Reconfiguring=False/ProviderError`, retried on a backoff |

Per resource (`internal/providers/libvirt/reconfigure.go`):

- **vCPUs.** A count above the definition's maximum raises the maximum first. A running domain then gets `setvcpus --live`; if that is refused (a grow beyond the running maximum, or an unplug) the result is *restart required*.
- **Memory.** A grow within the running `<memory>` (a VM created with memory hot-add) moves the balloon target up: *applied*. A grow beyond it raises `<memory>` in the definition: *restart required*. A **shrink** lowers the definition and, on a running VM, is always *restart required*.
- **Disk.** Grow-only; the VMClass disk size is a floor. A running VM is grown live with `virsh blockresize` and a best-effort in-guest filesystem grow (guest agent, `growpart`, `resize2fs` or `xfs_growfs`); a stopped VM's volume is resized. A failed grow fails the call before any CPU or memory change.
- **State.** Only a running (or idle) domain is changed live and only a shut-off domain in its definition alone. A paused, suspended-to-RAM, shutting-down or unknown domain is refused with a retryable error.

Errors say what could not be done and never carry the `virsh` command line, output, a host path or an SSH endpoint.

### Hot-add headroom (set before create)

Online grow works only for VMs created with headroom. Set the VMClass flags **before** creating the VM:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: hotplug-enabled
spec:
  cpu: 4
  memory: "8Gi"
  performanceProfile:
    cpuHotAddEnabled: true    # reserve headroom for live vCPU grow
    memoryHotAddEnabled: true # reserve headroom for live memory balloon grow
```

The created domain then has a ceiling of 4x the initial value (vCPUs capped at 64; memory has no hard cap):

```xml
<vcpu placement='static' current='4'>16</vcpu>   <!-- 4 boot online, 16 ceiling -->
<memory unit='MiB'>32768</memory>                 <!-- balloon maximum: 4x initial -->
<currentMemory unit='MiB'>8192</currentMemory>    <!-- initial guest-visible allocation -->
```

A VM created without the flags (including every VM created before v0.3.9) reports *restart required* for any CPU or memory change; to get online reconfigure, recreate it with a class that has the flags. If the in-guest filesystem grow is skipped (no agent, LVM, non-root XFS), finish it in the guest: `growpart /dev/vda 1` then `resize2fs /dev/vda1` or `xfs_growfs /`.

A disk-size change alone does not trigger a `Reconfigure`: the manager sends one when the effective CPU or memory changes, and the disk sizes travel with it.

Power states reported by libvirt: `running`/`idle` is `On`; `shut off`, `in shutdown` and `crashed` are `Off`; `paused` and `pmsuspended` are `Suspended`; anything else is `Unknown`. The manager neither powers on nor reconfigures a `Suspended` or `Unknown` VM (`Ready=False/PowerStateUnmanaged`). Full contract: [Reconfigure results](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/reconfigure-results.md).

## `spec.disks` are not attached

The libvirt provider creates one root disk (sized by the VMClass) and attaches **no** `spec.disks` entries. A `VirtualMachine` with a non-empty `spec.disks` on a libvirt Provider gets `DisksApplied=False`, reason `NotSupportedByProvider`, a `Warning` event, and (where the VM validating webhook is rendered, which the chart does only with `webhooks.enabled=true` and `manager.maxDiskSize` set) an admission warning. The VM runs without the extra disks and `Ready` is unchanged. `spec.disks[].sizeGiB` is not applied by `Reconfigure` either. Remove `spec.disks` from libvirt VMs.

## Delete

Delete reads the domain definition once; if it cannot, the delete fails retryably with the domain intact. It removes only: the domain's own top-level disk files that are regular files directly inside the `default` pool or an allowed image directory (never a symlink or its target); the overlay files of its own external-snapshot chain; and its cloud-init seed directory. A base image, another VM's disk, CD-ROM media and anything outside those directories is left in place and logged. While another domain on the host uses the VM's disk (a legacy linked clone, a shared disk), the delete is refused with `Ready=False/DeleteBlocked` and re-checked every minute. `virtrigaud.io/orphan-on-delete: "true"` detaches the `VirtualMachine` without touching the domain. See [What Delete removes](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/libvirt-clones.md#what-delete-removes).

## `status.ips`

`status.ips` lists the VM's addresses, **routable only**: the manager drops loopback, unspecified, link-local and multicast addresses, entries that are not an IP address, and duplicates, for every provider. Where libvirt gets the addresses depends on the network:

| Guest network | Without the QEMU guest agent | With the agent |
|---------------|------------------------------|----------------|
| libvirt-managed network (NAT `default`) | The **DHCP lease** (`virsh domifaddr --source lease`) is shown | Shown, and replaces the lease list |
| Host bridge (`libvirt.bridge`) | **Nothing**: libvirt holds no lease. Only an ARP entry the host happens to have (`--source arp`) can fill it | Shown |
| No attachment (user-mode NIC) | Nothing | Shown |

The sources are tried in the order agent, lease, ARP, and the first with an address wins; while the domain runs, a reachable address from `guest-network-get-interfaces` replaces the list (at most 16 interfaces and 16 addresses per interface). Anything that took `status.ips[0]` before v0.4.0 and expected a loopback or link-local entry must read the first reachable address instead. See [`status.ips`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-status-ips.md).

## Console access

`Describe` populates `status.consoleURL` with a VNC URL extracted from `virsh dumpxml`. The URL points at the libvirt host's VNC display port:

```bash
kubectl get vm dev-workstation -o jsonpath='{.status.consoleURL}'
# vnc://libvirt-host.example.com:5900
```

Connect with any VNC client (`vncviewer`, TigerVNC, noVNC).

!!! warning "VNC over the public internet"
    The libvirt VNC port is unauthenticated by default. Either firewall it to the operator network or front it with a TLS-terminating proxy. Do not expose 5900-590x to the open internet.

## Troubleshooting

### CircuitBreaker open on first deploy

If you see:

```promql
virtrigaud_circuit_breaker_state{provider_type="libvirt", provider="libvirt-lab"} == 2
```

immediately after a fresh `helm install`, the breaker has seen repeated RPC failures against the provider and fast-failed further requests rather than spam the SSH endpoint. The most common root cause is an SSH-host issue on the libvirt side, for example `kex_exchange_identification: Connection closed by remote host` (`sshd` refusing new connections because of `MaxStartups` or a per-IP block).

The provider retries transient SSH connection failures with bounded backoff, which absorbs short bursts. It does not paper over a hostile SSH policy: tune the host's `MaxStartups` and any `fail2ban` policy (see [host preparation](../operations/libvirt-host-prepare.md)).

**Triage:**

1. Open a shell on the libvirt host out of band.
2. Inspect `sshd` logs (`journalctl -u ssh` or `/var/log/auth.log`).
3. Check for `MaxStartups` exhaustion, `fail2ban` bans on the provider pod's source IP, or `AllowUsers`/`AllowGroups` restrictions.
4. Once SSH is healthy the breaker self-recovers (default 60s reset after 10 consecutive failures; see [Resilience](../operations/resilience.md#circuitbreaker-on-the-provider-grpc-path-v036)).

Failures that are the VM's own problem (a refused delete, a disk in use, an unreadable disk image) carry a reason such as `VM_DISK_IN_USE` or `VM_DISK_CHECK_FAILED` and are kept out of the breaker.

### Every create fails with `refusing to stage cloud-init data`

The seed directory on that host is missing, not owned by the SSH user, or readable or writable by group or others (or sits below a directory writable by others without the sticky bit). Create it as shown in [Prerequisites](#prerequisites). The provider log names the directory and the problem. A create without `spec.userData` is refused too, because it still builds a default seed.

### `qemu-guest-agent` not reporting IPs

`Describe` asks the agent for `guest-network-get-interfaces`. Install and enable it in the guest:

```bash
apt-get install qemu-guest-agent
systemctl enable --now qemu-guest-agent
```

See [`status.ips`](#statusips) for which networks need it.

### "the libvirt storage pool "default" on the VM's host is not at /var/lib/libvirt/images"

The `default` pool must be at `/var/lib/libvirt/images` and the provider never rewrites a pool. Check with `virsh pool-dumpxml default | grep '<path>'`, then mount your storage at that path or fix the pool by hand.

### "permission denied" on the libvirt socket / SSH user can't talk to libvirt

The SSH user must be in the `libvirt` group (Debian/Ubuntu) or have polkit rules granting access (RHEL/Fedora). Verify with:

```bash
ssh virtrigaud@libvirt-host virsh -c qemu:///system list
```

### "permission denied reading a disk image"

A snapshot, revert, delete or (clustered) create/clone is refused, retryably, because the provider could not read a libvirt overlay (`0600`, owned by root while the VM is off). Grant the SSH user the `VR_DISK_READ` sudo rule over the pool directory; see [Unreadable disk images](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/libvirt-clones.md#unreadable-disk-images).

### Snapshot fails on a running domain

A memory snapshot needs qcow2 storage; raw-on-LVM fails on a running domain. Power the VM off and take a disk-only snapshot, or use qcow2.

### Debug logging

```yaml
spec:
  runtime:
    logLevel: debug
```

`logLevel` sets the provider's `LOG_LEVEL`.

## Performance tips

- **virtio everywhere**: `virtio` NIC model, `virtio` disk bus (the default for VirtRigaud-created disks).
- **CPU mode `host-passthrough`**: best raw performance but breaks live migration between dissimilar hosts; use `host-model` if you need portability.
- **Hot-add requires at-create opt-in**: set `cpuHotAddEnabled`/`memoryHotAddEnabled` on the VMClass before creating the VM.
- **Keep the pool on fast local or well-tuned shared storage mounted at `/var/lib/libvirt/images`**; the provider does not select other pools.

## API reference

- Full CRD field reference: [Generated CRD docs](../references/generated-crd-docs.md).
- Provider gRPC contract: [Generated gRPC docs](../references/grpc-api.md).
- Capability matrix (all providers): [Capabilities](providers-capabilities.md).

## Support

- Documentation: [VirtRigaud Docs](https://projectbeskar.github.io/virtrigaud/)
- Issues: [GitHub Issues](https://github.com/projectbeskar/virtrigaud/issues), label `provider/libvirt`
- libvirt docs: [libvirt.org](https://libvirt.org/docs.html)
