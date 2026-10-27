<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Proxmox VE Provider

The Proxmox provider manages VMs on Proxmox Virtual Environment (PVE) via the native PVE REST API, plus an SSH data plane to the PVE node. The SSH data plane moves disks for cross-hypervisor migration and, since v0.4.1, builds the cloud-init seed of every VM that carries `spec.userData`.

This page is aligned to **VirtRigaud v0.4.1**. Capability claims trace back to `internal/providers/proxmox/capabilities.go` and the REST client in `internal/providers/proxmox/pveapi/`.

## Status

The Proxmox provider is listed as **Beta** in the [capability matrix](providers-capabilities.md). It implements the VM lifecycle, snapshot, clone, image and disk-migration RPCs (not `HardwareUpgrade`, `ListHosts` or `GetHostInfo`), but it has had the least production burn-in of the three providers, and part of its behaviour is limited:

- Most of the Proxmox logic (owner stamps, re-bind, in-flight guards, clone and create error classes, the cloud-init seed) is covered by tests against an in-repo PVE fake. The v0.4.0 and v0.4.1 release candidates were also run in the project's lab on a **single** Proxmox VE 9.2 node (cloud-init seed, boot order, VMID races, network settings, snapshot revert, migration); behaviour that needs a multi-node PVE cluster has not been exercised.
- Since v0.4.1 it applies the **whole** `spec.userData`, through a NoCloud seed built over SSH. That needs SSH credentials in the Provider's Secret and is breaking for Proxmox users whose VMs carry user-data (see [Cloud-init](#cloud-init-the-nocloud-seed) and the [upgrade notes](../operations/upgrade.md#proxmox-user-data-needs-the-ssh-data-plane)).
- It attaches no `spec.disks`, resizes no disk, and does not import images from a URL.
- `ConsoleURL` is a web-UI deep link, not a standalone VNC ticket.

## Capabilities at a glance

Built via `capabilities.NewBuilder()` in `internal/providers/proxmox/capabilities.go`:

| Capability flag | Value | What it means |
|-----------------|-------|---------------|
| Core (Create/Delete/Power/Describe) | yes | Standard VM lifecycle. |
| `Snapshots` | yes | PVE snapshots via the API. |
| `MemorySnapshots` | yes | `vmstate=1` is passed when `snapshotConfig.includeMemory` is true. |
| `LinkedClones` | **no** (since v0.4.1) | Not advertised: the provider never made linked clones (every clone is a full clone) and `Clone` refuses a linked request. A `VMClone` with `type: LinkedClone` fails with `LinkedCloneUnsupported` before the provider is called. |
| `OnlineReconfigure` | yes | CPU and memory are written with the config endpoint; see [Reconfigure](#reconfigure) for what is and is not reported. |
| `OnlineDiskExpansion` | advertised | **Not implemented by `Reconfigure`**: the provider applies no disk size (see [Disks](#disks)). The flag is advertised but no disk is resized. |
| `ImageImport` | advertised | Routes import-style sources to `ImagePrepare`, which **refuses `source.http`** with `InvalidSpec`. Use an existing template (see [Images](#images)). |
| `ImageArtifactIdentity` | yes | The provider never reuses a prepared image by bare name. |
| Disk export / import | `qcow2`, `raw`, `vmdk` | Back cross-hypervisor migration. Export compression for qcow2. |
| Export / import backends | `s3`, `nfs` | Never `pvc`. Relay transfer mode. |
| `DiskTypes` | `raw`, `qcow2` | Advertised only; the provider keeps the template's disks. |
| `NetworkTypes` | `bridge`, `vlan` | Linux bridges with an optional 802.1Q tag. |

For the full cross-provider matrix and resilience / observability story:

- [Provider capabilities matrix](providers-capabilities.md)
- [Operations — Resilience](../operations/resilience.md): the CircuitBreaker wraps every Proxmox RPC.
- [Operations — Observability](../operations/observability.md)

## Behaviour at a glance: snapshot, revert, clone, reconfigure, disks

| Area | Proxmox behaviour at v0.4.1 | Code |
|------|-----------------------------|------|
| Snapshot create | `POST .../qemu/{vmid}/snapshot`; `snapshotConfig.includeMemory: true` sends `vmstate=1`. The snapshot id is the snapshot name (the name hint, or `snapshot-<unix time>`). Returns a PVE task the manager polls. | `server.go` (`SnapshotCreate`), `pveapi/client.go` (`CreateSnapshot`) |
| Snapshot delete | Owner-checked on the VM's actual node. A snapshot that is provably absent is answered `NotFound`, so the delete is idempotent. | `server.go` (`SnapshotDelete`) |
| Snapshot revert | `spec.snapshot.revertToRef`; `POST .../snapshot/{name}/rollback` after an owner check; returns a task. The VM must be powered off in the controller's flow, like every provider. | `server.go` (`SnapshotRevert`) |
| Clone | `POST .../qemu/{vmid}/clone` with `full=1`: always a full clone (a linked request is refused). The source is owner-checked first; the VMClass sizing override (CPU **and memory**, since v0.4.1) is applied after the clone. A source that has a seed, or a `VMClone` with inline user-data, gives the clone a seed of its own (see [Cloning](#cloning)). | `server.go` (`Clone`), `seed_create.go` |
| Create from a template | Always a **full clone** (`full=1`) of `source.proxmox.templateID`; `source.proxmox.fullClone: false` is not honoured. With `spec.userData` the VM gets a NoCloud seed (see [Cloud-init](#cloud-init-the-nocloud-seed)). | `server.go` (`Create`), `seed_create.go` |
| Reconfigure | **CPU and memory only.** No disk is resized. A change PVE stores as *pending* is reported as applied. | `reconfigure.go` |
| `spec.disks` | **Not attached.** `DisksApplied=False/NotSupportedByProvider`. | `internal/controller/virtualmachine_disks_applied.go` |

## RPC support

- **Validate**: checks that the default storage setting is a valid storage ID, then finds a node. Without `PROVIDER_NODE_SELECTOR` that is a `GET /nodes` call, which exercises the credentials; with a selector set, the first entry is used without contacting PVE.
- **Create**: clones a PVE template (by VMID), or builds a bare VM, or builds a VM from a migration's staged disk. Stamps the VM with its owner. When the request carries user-data, builds and attaches the cloud-init seed over SSH.
- **Delete**: stops the VM if it is running, then destroys it with `purge=1` and waits for the task. Never destroys a template.
- **Power**: `start` / `stop` / `shutdown` / `reboot`, idempotent; returns a task.
- **Describe**: VM state, guest-agent IPs, console deep link, raw PVE details.
- **Reconfigure**: `PUT .../config` for CPU and memory.
- **SnapshotCreate / SnapshotDelete / SnapshotRevert**: the `/snapshot` subtree of the VMID.
- **Clone**: `POST .../clone` (full clone only).
- **TaskStatus**: polls the PVE task UPID. In-flight tasks count toward `virtrigaud_provider_tasks_inflight`.
- **ExportDisk / ImportDisk / GetDiskInfo**: migration data plane, see [Cross-hypervisor migration](#cross-hypervisor-migration).
- **Console URL**: `Describe` returns a web-UI deep link.

A VM is identified by its VMID. On the provider's default node the id is the bare VMID; on any other node it is `<node>:<vmid>`.

## Prerequisites

- Proxmox VE **7.0 or later**, reachable from the provider pod on port `8006/HTTPS`.
- Either an API token *or* a username + password.
- Storage and bridges configured on the PVE nodes: the provider does not create them.
- For migration, and for every VM that carries `spec.userData` (since v0.4.1): SSH from the provider pod to the PVE node as `root`, with `genisoimage` and `flock` installed there (see [The SSH data plane](#the-ssh-data-plane-migration-and-user-data)).
- A **template** (a VM converted with `qm template`) to clone VMs from. See [Images](#images).

## Authentication

The Proxmox provider reads credentials from the Secret mounted at `/etc/virtrigaud/credentials` inside the provider pod, falling back to the `PROVIDER_*` / `PVE_*` environment variables (`internal/providers/proxmox/server.go`, `New`). **Both API tokens and username/password are supported**; tokens are strongly preferred for production.

**The Secret keys are read as files**; the key names matter:

| Secret key | File path | Auth method |
|------------|-----------|-------------|
| `token_id` | `/etc/virtrigaud/credentials/token_id` | API token (e.g. `virtrigaud@pve!vrtg-token`) |
| `token_secret` | `/etc/virtrigaud/credentials/token_secret` | API token secret value |
| `username` | `/etc/virtrigaud/credentials/username` | Username (e.g. `virtrigaud@pve`), used only if no `token_id` |
| `password` | `/etc/virtrigaud/credentials/password` | Password, used only if no `token_id` |

The SSH keys of the [SSH data plane](#the-ssh-data-plane-migration-and-user-data) (`ssh_user`, `ssh_privatekey` or `ssh_password`, `known_hosts`) live in the same Secret.

If a `token_id` + `token_secret` pair is present, the provider uses token auth. Otherwise it falls back to username/password and acquires a session ticket. Mixed credentials in the same Secret are tolerated (token wins).

**Give each Proxmox Provider its own API token.** The provider tells its own clone and create tasks from other users' by the PVE user that ran them; Providers (or replicas) that share a token hold each other's creates while a clone runs.

### API token (recommended)

Create the token in PVE:

```bash
# As root@pam on a PVE node
pveum user add virtrigaud@pve --comment "VirtRigaud"
pveum user token add virtrigaud@pve vrtg-token --privsep 1
# With --privsep 1 a token gets only the permissions that BOTH the user and the
# token itself hold (PVE docs), so grant the role to the user and to the token:
pveum acl modify / --users virtrigaud@pve --roles PVEVMAdmin
pveum acl modify / --tokens 'virtrigaud@pve!vrtg-token' --roles PVEVMAdmin
# PVEVMAdmin does not include Datastore.AllocateSpace (PVE docs): also grant
# Datastore.AllocateSpace and Datastore.Audit on the storages VMs and cloud-init
# drives are created on (for example with the built-in PVEDatastoreUser role),
# again to the user and to the token.
# Or use a tighter custom role (the privilege list is in "PVE privileges"):
# pveum role add VirtRigaud --privs "VM.Allocate,VM.Audit,..."
# pveum acl modify / --users virtrigaud@pve --roles VirtRigaud
# pveum acl modify / --tokens 'virtrigaud@pve!vrtg-token' --roles VirtRigaud
```

Provider CR + Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: proxmox-credentials
  namespace: virtrigaud-system
type: Opaque
stringData:
  token_id: "virtrigaud@pve!vrtg-token"
  token_secret: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: proxmox-cluster
  namespace: virtrigaud-system
spec:
  type: proxmox
  endpoint: "https://pve.example.com:8006"
  credentialSecretRef:
    name: proxmox-credentials
  insecureSkipVerify: false
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-proxmox:v0.4.1"
    service:
      port: 9443
      tls:
        enabled: true
        secretRef:
          name: provider-proxmox-tls
        insecureSkipVerify: false
```

A Provider used from other namespaces must set `spec.consumerNamespaceSelector`; see [Cross-namespace references](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/cross-namespace-references.md).

### Username / password

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: proxmox-credentials
type: Opaque
stringData:
  username: "virtrigaud@pve"
  password: "REPLACE_ME"
```

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

## PVE privileges

VirtRigaud does not publish a complete, tested PVE role. What the v0.4.1 documentation and code establish is below; anything marked *PVE docs* comes from the Proxmox API documentation and is **not exercised by the project's tests**, so confirm it with a restricted token before you rely on it.

| Privilege | Needed for | Source |
|-----------|------------|--------|
| `VM.Allocate` | Create, clone and destroy VMs | PVE docs |
| `VM.Clone` | Cloning a template or VM | PVE docs |
| `VM.Audit` | Reading VM config (every `Describe`, every owner check) | PVE docs |
| `VM.PowerMgmt` | Start / stop / shutdown / reboot | PVE docs |
| `VM.Config.CPU`, `VM.Config.Memory` | `Reconfigure` and the VMClass sizing applied at create | PVE docs |
| `VM.Config.Options` | The **owner stamp** (VM description / Notes) on every create, clone and adopted VM; the boot order of a VM that gets a seed | VirtRigaud docs (the stamp); PVE docs (boot order); `PVEVMAdmin` includes it |
| `VM.Config.Network` | Setting a VM's `netN` (new VM's NICs, a clone's named NICs) | VirtRigaud docs |
| `VM.Config.Cloudinit` | `ipconfigN` and `nameserver` (static IP and DNS) of a VM that has no seed. A VM with a seed gets its addresses through the seed's network-config, and the provider writes no `ipconfigN`, `nameserver`, `ciuser` or `sshkeys` for it | VirtRigaud docs |
| `VM.Audit` and `VM.Config.Options` on the new VM | A VM made **without a template** with user-data is created first and marked ready after its seed is attached (its config is read and its description written), as a clone already was (since v0.4.1) | VirtRigaud docs |
| `SDN.Use` on `/sdn/zones/<zone>/<bridge>` (and `/<bridge>/<tag>` for a VLAN) | Every bridge a VM is put on, for any token that is not root. A plain Linux bridge such as `vmbr0` is in the `localnetwork` zone | VirtRigaud docs |
| `VM.Config.Disk`, `Datastore.AllocateSpace` | The cloud-init drive and disks on the target storage | PVE docs |
| `Datastore.Audit` | Reading storage | PVE docs |
| `VM.Snapshot`, `VM.Snapshot.Rollback` | Snapshot create/delete, and revert | PVE docs |
| `VM.Monitor` (newer PVE releases may use a guest-agent privilege instead) | Guest-agent queries for `status.ips` | PVE docs |

The seed's own `qm importdisk` and `qm set` run as `root@pam` over SSH, outside the token's permissions (see [Security posture](#security-posture-of-the-ssh-credential)). A token with the `Administrator` role, or `root@pam`, needs none of the table above. A token that worked on v0.3.11 can start getting `403` while the provider configures a clone: network and cloud-init settings are now written (`VM.Config.Network`, `VM.Config.Cloudinit`, `SDN.Use`), and the VM that fails to configure is rolled back. Grant them **before** rolling the provider.

!!! warning "Treat `VM.Config.Options` and `VM.Allocate` as the ownership boundary"
    The owner stamp is a line in the VM's Notes. Anyone with `VM.Config.Options` on a VM can rewrite it, and (for the legacy unstamped-name rule below) anyone with `VM.Allocate` where VirtRigaud's VMs live can create a VM that a `VirtualMachine` will treat as its own. Grant both on those pools and paths to no one but VirtRigaud's Provider tokens and your administrators, including inherited grants on `/vms` or `/`. `VM.Audit` lets a user read the stamps, which name each VM's namespace and `VirtualMachine`. Use `SDN.Use` ACLs to decide which bridges and VLANs the tenants of a namespace can reach: the provider applies whatever bridge and tag the manager sends, as the token allows.

## Endpoint formats

| Endpoint | Notes |
|----------|-------|
| `https://pve.example.com:8006` | Cluster-wide endpoint (recommended): any node answers the API for the whole cluster. The provider still places VMs on one default node (see below). |
| `https://pve-node-1.example.com:8006` | Single-node endpoint; loses HA if that node goes down. |

The CRD validates the endpoint pattern. For migration the endpoint host is also the SSH host (see below).

## Node selection

The provider uses **one default node** for `Create`, `Clone`, snapshot create/revert and for VM ids that are a bare VMID. It is the **first entry** of `PROVIDER_NODE_SELECTOR`, or, when unset, the alphabetically first node of the cluster (`GET /nodes`). The template must be on that node, or `Create` fails with "template N not found on node". Further selector entries only widen the scope of `ListVMs`; `source.proxmox.node` is read but not used for placement. To choose the node, put it first:

```yaml
spec:
  runtime:
    env:
      - name: PROVIDER_NODE_SELECTOR
        value: "pve-node-1,pve-node-2"
```

`PVE_NODE_SELECTOR` is read as well, when `PROVIDER_NODE_SELECTOR` is unset.

!!! warning "A VM with user-data must be on the node SSH reaches"
    The seed is built and attached on the node of the API endpoint's host. In a PVE cluster, set the selector to that node: a `Create` or `Clone` with user-data that would put the VM on another node is refused (`InvalidSpec`), and an `endpoint` that is a load balancer in front of several nodes does not work for such VMs. The selector applies to every new VM of the Provider, with or without user-data, so the templates (and clone sources) must be on that node too, or a template `Create` is refused (`template ... not found on node ...`).

## Storage

PVE storage is referenced by ID (for example `local-lvm`, `local-zfs`, `cephfs-pool`). The provider keeps the **template's disks** as they are; it sets no disk format and applies neither the VMClass `diskDefaults.size` nor `spec.disks`. Storage matters in two places:

- **The cloud-init seed.** See [Seed storage](#seed-storage).
- **Migration.** A migrated disk is imported into the storage given by `PROVIDER_DEFAULT_STORAGE` (or `PVE_DEFAULT_STORAGE`), which must allow the `images` content type. A directory storage is a valid target.

Set the default storage through `spec.runtime.env`:

```yaml
spec:
  runtime:
    env:
      - name: PVE_DEFAULT_STORAGE
        value: local-lvm   # a storage with the "images" content type
```

The value must be a valid PVE storage ID (letters, digits, `-`, `_`, `.`); an invalid value makes `Validate` fail.

## Images

A Proxmox VM is created from an **existing PVE template**, referenced by VMID:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-22-template
spec:
  source:
    proxmox:
      templateID: 9000   # an existing PVE template (VMID 100 or higher)
```

- `source.proxmox.templateID` is the supported reference. Nothing is prepared: the VM is a full clone of that template.
- `source.proxmox.templateName` is accepted by the CRD, but `Create` clones **only by numeric VMID**: a name that is not a number fails at create time with `InvalidSpec` ("invalid template ID"). Use `templateID`.
- **URL image import is refused** (ADR-0009 D10). `source.http` makes `ImagePrepare` return `InvalidSpec` ("Proxmox URL image import (source.http) is not supported in this release ..."); the `VMImage` shows `phase: Failed` and `Ready=False/InvalidSource`, and no VM is created. The earlier import only downloaded the file and never produced a usable template, and it reported any same-named template as "already prepared", whoever made it. To prepare an image yourself, import the cloud image into a VM disk on the node (for example `qm importdisk`), convert the VM to a template (`qm template <vmid>`), and put that VMID in `templateID`.
- A reference-style source reaches **every template the Provider's PVE account can read**. Give each tenant its own templates, or a PVE pool that only its Provider's account can read.

See [Image preparation](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/image-preparation.md#proxmox-image-sources).

## Networking

The manager sends one network per `spec.networks[]` entry. The bridge, model and VLAN come from the attachment's **`proxmox` block only** (the `vsphere` and `libvirt` blocks of the same attachment are ignored), and the static IP, gateway and DNS come from the entry on the **`VirtualMachine`**:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMNetworkAttachment
metadata:
  name: lan-vmbr0
spec:
  network:
    proxmox:
      bridge: vmbr0
      model: virtio
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMNetworkAttachment
metadata:
  name: dmz-vlan100
spec:
  network:
    proxmox:
      bridge: vmbr1
      vlanTag: 100
      model: virtio
```

and, on the `VirtualMachine`:

```yaml
spec:
  networks:
    - name: dmz
      networkRef:
        name: dmz-vlan100
      ipAddress: "192.0.2.50"
      prefix: 24
      gateway: "192.0.2.1"
      dns: "192.0.2.53"
```

| What | Behaviour |
|------|-----------|
| New VM (not cloned from a template) | One NIC per entry, `net0`, `net1`, ...: `<model>,bridge=<bridge>[,tag=<vlan>]`. Empty model or bridge default to `virtio` and `vmbr0`; no networks at all gives one `virtio` NIC on `vmbr0`. |
| Clone of a template | The clone keeps the template's NICs (with a new MAC each). An entry that names a bridge, model or VLAN is merged into the template NIC **at the same index** (entry 0 into `net0`, ...): the model is the entry's, the MAC and other options are kept, and a named bridge replaces the template's bridge and VLAN. An entry with no `networkRef` leaves its NIC as the template made it. An entry with no NIC at its index adds one; a template NIC no entry maps to is left alone, so a clone has at least the template's NICs. |
| Model default | The attachment CRD defaults `model` to `virtio`, so an attachment that names only a bridge still turns an `e1000` template NIC into `virtio`. Set `model` on the attachment to the template's model to keep it. |
| IP settings | Each entry becomes `ipconfigN`: `ip=<address>/<prefix>[,gw=<gateway>]` for a static IP, `ip=dhcp` otherwise (a new VM gets it on every NIC; a clone only when the request carries user-data or SSH keys). The DNS servers of all entries become the VM's single `nameserver` (PVE has no per-NIC DNS); `searchdomain` is not set. A static IP takes effect only when the VM has a cloud-init drive. |
| Refused as `InvalidSpec` | A bridge that is not a Linux bridge name; a model PVE does not know; a VLAN outside 1-4094; a MAC that is not unicast and non-zero; a static IP that is not unicast or has **no prefix length** (the CRD allows it, PVE's `ip=` needs it); a gateway of another family; a `dns` entry that is not an IP address (the list is comma-separated); more than 32 entries. |

Not applied on Proxmox: the attachment's `firewall`, `rateLimit` and `mtu`; `VMNetworkAttachment.spec.ipAllocation` (put static settings on the VM's entry); `spec.networks[].macAddress` (the manager drops it, ADR-0014 slice 0b); IPv6 (the CRD patterns are IPv4-only). The attachment CRD restricts a Proxmox `bridge` to `vmbrN`, so an SDN VNet is not reachable through it yet. `Describe` reports no NICs; `ListVMs` reports each NIC's bridge and MAC.

VMs that relied on the accidental `vmbr0` default change on their next create or clone; a VM that already exists is not modified. Full rules: [Proxmox networks](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/proxmox-networks.md).

!!! warning "Migrated guests (R36)"
    A Linux cloud-image guest whose netplan matches its NIC by MAC address (Ubuntu cloud images do) can boot **without network** on a Proxmox target, because the target NIC has a new MAC and cloud-init does not run again. The fix is designed ([ADR-0014](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/adr/0014-migrated-guest-network.md)) and planned after GA; only its Proxmox network plumbing is in v0.4.1. Until then, make the guest's netplan match its NIC by name or driver before you migrate, or fix its network from the console. See the [migration guide](../migration/user-guide.md).

## Cloud-init: the NoCloud seed

A `VirtualMachine` that carries `spec.userData` on a Proxmox Provider gets the **whole** user-data document in the guest, as on libvirt and vSphere: `users` with their own keys and `sudo`, `write_files`, `packages`, `runcmd`, `chpasswd`, `hostname` and every other cloud-config key reach cloud-init unchanged. Since v0.4.1 the provider does this with a **NoCloud seed** it builds on the PVE node over SSH. A VM **without** `spec.userData` keeps PVE's own cloud-init handling and opens no SSH session, with one exception: a seed CD-ROM inherited from a template made from a VM that has a seed is detached (see [Lifecycle](#lifecycle)).

```yaml
spec:
  userData:
    cloudInit:
      inline: |
        #cloud-config
        users:
          - name: ubuntu
            ssh_authorized_keys:
              - "ssh-ed25519 AAAA..."
        packages:
          - qemu-guest-agent
        runcmd:
          - systemctl enable --now qemu-guest-agent
```

In v0.4.0 and earlier the provider read two things out of the user-data with a line scan (the first `name:` as PVE's `ciuser`, and the `ssh_authorized_keys:` block-list items as `sshkeys`) and dropped the rest silently, so `runcmd`, `write_files`, `packages` and a second user never reached the guest. That is no longer so, and the provider sets no `ciuser`, `sshkeys`, `ipconfigN` or `nameserver` on a VM that has a seed.

!!! danger "Breaking for Proxmox VMs that carry user-data"
    A Proxmox Provider whose VMs carry `spec.userData` now needs SSH credentials in its Secret and `genisoimage` and `flock` on the node. Without them a `Create` is refused before anything is created. **Add the keys before you roll the provider.** The steps are in the [upgrade notes](../operations/upgrade.md#proxmox-user-data-needs-the-ssh-data-plane).

### What the seed holds

The seed is an ISO9660 image with the volume label `cidata`, imported into the VM's own storage and attached as a CD-ROM (`ide2` unless the VM's PVE cloud-init drive or another slot says otherwise).

| File | Content |
|---|---|
| `user-data` | `spec.userData`, byte for byte. The provider does not parse it. |
| `meta-data` | Rendered by the provider: `instance-id` `virtrigaud-<UID of the VirtualMachine>`, `local-hostname` the VM name, and the other keys of `spec.metaData` when set (a `spec.metaData` that is not a YAML mapping is refused with `InvalidSpec`). `spec.metaData` without `spec.userData` is not applied. |
| `network-config` | Version 2, one entry per `spec.networks` entry, matched by the MAC PVE gave the NIC and named `eth<N>`: DHCP, or the static address, default route and DNS. Absent when no NIC can be matched; cloud-init then falls back to DHCP on the first NIC. |

A re-sent `Create` of the same `VirtualMachine` keeps its `instance-id`; a new `VirtualMachine` with the same name gets a new one.

### Seed prerequisites

| Needed | Detail |
|---|---|
| SSH credentials in the Provider's Secret | `ssh_user` (use `root`, the default; the seed script runs `qm`, so another user fails at the seed step, not at validation), `ssh_privatekey` or `ssh_password`, and `known_hosts`. See [The SSH data plane](#the-ssh-data-plane-migration-and-user-data). |
| `genisoimage` and `flock` on the PVE node | Both are on a stock PVE node (`genisoimage` is a dependency of `qemu-server`). A node without `flock` is not refused: the build cannot take its lock, the VM is kept with an unknown outcome and every re-send repeats it, so check `command -v genisoimage flock` first. |
| The VM on the node SSH reaches | The API endpoint's host. In a cluster, set `PROVIDER_NODE_SELECTOR` (or `PVE_NODE_SELECTOR`) to that node. |
| A storage with the `images` content type | See [Seed storage](#seed-storage). |
| Token privileges `VM.Audit` and `VM.Config.Options` | Only for a VM made **without a template** with user-data. |

A `Create` or `Clone` that needs a seed and cannot get one is refused **before anything is created**, as `InvalidSpec`, with a message that names what is missing (the SSH data plane, `ssh_password` or `ssh_privatekey`, `known_hosts`, `genisoimage`, or the node selector). A `VirtualMachine` shows `Ready=False/ValidationError` and is re-checked with a [backoff](../operations/upgrade.md#a-refused-vm-create-is-retried-with-a-backoff): 30 seconds doubling to 10 minutes, or at once when the VM, its VMClass, VMImage or Provider spec changes. A changed Secret is not such a change, so the re-check that picks it up can be up to 10 minutes later. A `VMClone` ends `Failed` (`ProviderError`): re-create it after you fix the Secret and roll the provider, which reads the SSH keys when it starts.

### Security posture of the SSH credential

Before v0.4.1 the VM lifecycle needed only the PVE API token; SSH was used only by migrations. A Provider whose VMs carry user-data now holds a **root SSH credential** to the PVE node. The seed's `qm importdisk` and `qm set` run as `root@pam` over SSH: PVE attributes those config and storage changes to root, not to the token, and its permission checks do not apply to them. Treat the Provider's credentials Secret as root on the node: restrict who can read it, and use a key that only this provider uses.

The user-data is stored in **plaintext** in the seed volume, on the VM's storage, for the VM's whole life (anyone who can read that storage, and root in the guest, can read it), as in PVE's own cloud-init drive and libvirt's seed. Keep long-lived secrets out of user-data and fetch them at first boot instead. The provider sends the three files as a tar archive on the standard input of one SSH session, never on a command line, and never writes them to a log, an event or a status. It logs one line per seed build (VM, node, storage, slot, size of the user-data).

### Failure handling

- **Definite failures clean up.** No SSH data plane, no credentials, no `known_hosts`, no `genisoimage`, a VM on another node than the one SSH reaches, user-data or meta-data over 1 MiB, and meta-data that is not a YAML mapping are `InvalidSpec` before anything is created. The same refusals found after the VM was made (for example no free CD-ROM slot) remove it.
- **An unknown outcome keeps the VM.** When the seed build's SSH session broke, or another build or `qm importdisk` of the VM was still running, the VM is kept and the re-sent `Create` finishes it. Any other failure rolls the VM back. A re-sent `Create` never attaches a second seed.
- **Delete removes the seed** with the VM, and the seed's lock file on the node (`/run/virtrigaud/seed-stage/.lock-<vmid>`, best effort, at most 10 seconds, never failing the call).

### Lifecycle

- **Existing VMs are not converted.** A VM made before v0.4.1 keeps its PVE cloud-init drive. A cloud-init drive left on `local` by v0.4.0 can be moved with `qm set <vmid> --ide2 <storage>:cloudinit` on the node.
- **The seed is written once, at `Create`.** A later change to `spec.userData` does not rebuild it.
- **A clone gets a seed of its own** and does not carry its source's user-data. See [Cloning](#cloning).
- **A template made from a VM with a seed.** Its clones would reference the template's seed volume. A `Create` with user-data replaces it with the VM's own seed; a `Create` without user-data detaches it, so the VM gets no cloud-init source from the template. The template's volume is never freed.
- **A migration import** with user-data gets a seed on the storage the disk was imported to; one without user-data gets no cloud-init source, as before.

### Boot order

The seed is kept out of the boot order of every VM that gets one. cloud-init finds the seed by its filesystem label, and nothing boots from it. PVE appends a CD-ROM that a config update attaches to a non-empty `order=` list, which would leave `order=scsi0;ide2`. The provider therefore takes the seed's slot out of the order in a config update of its own after it attaches the seed, on every path that attaches one (a template `Create`, a `Create` without a template, an imported-disk `Create` and a `VMClone`), also when a re-sent request finds the seed already attached. The update carries the config's digest, so a concurrent change is never overwritten; if it still fails, the VM is kept and the re-sent request finishes the step.

A VM cloned from a template with user-data boots from its boot disk only: the template's own first boot disk, else its `bootdisk`, else the first disk. In v0.4.0 the order named the cloud-init slot as well, and a device the VM lacked made PVE refuse the update, so such a `Create` failed and was rolled back. A `VMClone` and a template `Create` **without** user-data keep the template's or source's order. Prepare templates with `qm set <vmid> --boot order=<boot disk>` (for example `scsi0`).

### Seed storage

The seed goes to the storage a PVE cloud-init drive would use, and PVE refuses an image volume on a storage without the `images` content type. On a stock PVE install `local` is a directory storage that does **not** have it (an LVM-thin storage such as `local-lvm` does). For a VM cloned from a template, the provider reads the new VM's config once the clone task has ended and picks the first of these that applies:

1. A storage the request names (the image JSON's `storage`, or `source.proxmox.storage`). The manager's `Create` does not carry one today, so this has no effect on a `VirtualMachine` yet.
2. **The storage the clone's primary disk lives on** (the first non-CD-ROM drive, scanning `virtio`, `scsi`, `sata`, `ide`).
3. `PROVIDER_DEFAULT_STORAGE`, else `PVE_DEFAULT_STORAGE`. Used for a clone whose config shows no storage-backed disk, for a VM made without a template, and for migration.
4. `local`, with a warning, only when nothing above applies.

The seed CD-ROM goes to the slot of another VM's seed that the clone's config references (it is replaced), else to the slot of the VM's PVE cloud-init drive (it is replaced), else to the first free slot of `ide2`, `ide0`, `ide1`, `ide3`, `sata0` to `sata5`. When none is free the VM is removed and the `Create` is refused. A storage ID must have the syntax of a PVE storage ID, or the `Create` is refused as an invalid spec. Full detail: [Proxmox cloud-init: the NoCloud seed and its storage](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/proxmox-cloud-init-storage.md).

!!! tip "Install qemu-guest-agent in the guest"
    Without it, `Describe` cannot retrieve IP addresses from the running VM and `status.ips` stays empty. With the seed you can install it from the user-data (`packages: [qemu-guest-agent]`); baking it into the template works too.

### Known limitations of the seed

- **A seed on node-local storage blocks moving the VM to another node.** qemu-server refuses `qm migrate` for a VM with a local CD-ROM image other than its own PVE cloud-init drive, online or offline, so HA and node evacuation cannot move such a VM. Put the VM on a shared storage with the `images` content type, or detach and free the seed first (`pvesm free <volume>`; removing only the CD-ROM with `qm set --delete` leaves the volume on the storage).
- **The VM must be on the node SSH reaches**, and a `Create` or `Clone` that would put it elsewhere is refused.
- **NICs a template has but `spec.networks` does not name** get no entry in the seed's network-config, so cloud-init does not configure them (a template's own `ipconfigN` is not used). Name every NIC that needs an address.
- **User-data a `VMClone` gives by Secret reference** cannot be resolved by the provider and is not applied (logged).
- **Existing VMs, and `spec.userData` edits after create,** are not touched (see Lifecycle above).
- **The SSH credential is root on the node** (see above).

## VM example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: small
spec:
  cpu: 2
  memory: "4Gi"
  firmware: UEFI
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-22-template
spec:
  source:
    proxmox:
      templateID: 9000
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMNetworkAttachment
metadata:
  name: lan-vmbr0
spec:
  network:
    proxmox:
      bridge: vmbr0
      model: virtio
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: web-server
spec:
  providerRef:
    name: proxmox-cluster
  classRef:
    name: small
  imageRef:
    name: ubuntu-22-template
  powerState: "On"
  networks:
    - name: lan
      networkRef:
        name: lan-vmbr0
  userData:
    cloudInit:
      inline: |
        #cloud-config
        users:
          - name: ubuntu
            ssh_authorized_keys:
              - "ssh-ed25519 AAAA..."
```

Quote `powerState` values (`"On"`): an unquoted `On` is a boolean in YAML 1.1 and is rejected by the API server. The VMClass sets CPU and memory on the clone; the root disk keeps the template's size.

This VM carries `spec.userData`, so the Provider's Secret needs the SSH keys and the node needs `genisoimage` (see [Seed prerequisites](#seed-prerequisites)). Without `userData` the VM needs none of that. `firmware: UEFI` in the VMClass is a vSphere/libvirt setting: the Proxmox provider keeps the template's firmware.

## Ownership and the name rule

Proxmox VMIDs are cluster-wide and reused, and PVE does not keep VM names unique, so the provider proves which VM belongs to which `VirtualMachine`:

- **Owner stamp.** Every VM `Create` makes, every clone made for a target `VirtualMachine` with a UID, and every VM adoption takes over gets one line in its Notes: `virtrigaud.owner v1 uid=<uid> namespace=<ns> name=<name> phase=<creating|ready> sum=<16 hex>`. Read it with `qm config <vmid> | grep virtrigaud.owner`. The line is reserved: the provider replaces any line that mentions `virtrigaud.owner`, and a hand-edited one makes the stamp unreadable, which fails closed. The checksum catches accidents, not forgery.
- **Re-bind.** A `Create` or `Clone` sent again after an unknown outcome returns the VM already stamped with the `VirtualMachine`'s UID, anywhere in the cluster, instead of making a second one. While PVE is still cloning (the VM has no name or description yet), the provider answers outcome-unknown rather than start another. One `Create`/`Clone` runs per owner at a time.
- **Owner check on every per-VM call.** The manager sends the `VirtualMachine`'s identity with `Describe`, `Power`, `Reconfigure`, `SnapshotCreate/Delete/Revert`, `GetDiskInfo`, `ExportDisk`, `Delete` and the source of a `Clone`. The provider reads the VM's config and checks the stamp **before** it reads or changes anything else:

    | The VM at that VMID | Result |
    |---|---|
    | Stamped with the request's UID | The call goes on |
    | Unstamped **and** named like the owner (the owner's name, or the name adoption gave it): the **legacy unstamped-name rule** | The call goes on, as before |
    | Unstamped with any other name, or stamped with another UID (its VMID was reused) | `NotFound` + `VM_NOT_OWNED`; the VM is neither read nor changed |
    | Unreadable or multiple stamp | `FailedPrecondition` + `OWNER_STAMP_UNREADABLE`; nothing is done |

    The VM controller shows these as `Ready=False/VMNotOwned` and `Ready=False/OwnerStampUnreadable` (phase `Failed`). `status.id` is kept and no VM is created in its place. A `VMMigration` or `VMClone` whose source fails the check fails with a constant message and copies nothing. A `Delete` additionally refuses templates outright (`VM_IS_IMAGE_ARTIFACT`). Every checked call except `Reconfigure` and `GetDiskInfo` costs one extra `GET .../config`.
- **Known limits at v0.4.1.** The legacy name rule can be claimed by anyone who can create a VM at a freed VMID (grant `VM.Allocate` carefully, above). [ADR-0012](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/adr/0012-proxmox-legacy-unstamped-name-rule.md) plans to retire it in stages; none of that is in v0.4.1. A stamp can be copied by someone who knows the UID and holds `VM.Config.Options`. The owner check and the call are two requests, so a VMID freed and reused between them is not caught: do not delete VirtRigaud-managed VMs outside VirtRigaud; delete the `VirtualMachine`, or detach it with `virtrigaud.io/orphan-on-delete: "true"`. A VM adopted by an earlier release that still carries a previous owner's stamp is held `VMNotOwned` until you remove the stale `virtrigaud.owner` line.

- **A VMID race is "not performed", not an unknown outcome (since v0.4.1).** The VMID comes from PVE's `/cluster/nextid`, so two `Create`s or `Clone`s of one Provider can get the same one. The loser's clone task ends on a config lock timeout, finds the new VMID's config already there, or PVE refuses its request outright (HTTP 5xx `unable to create VM <vmid>: config file already exists`). The provider now answers "not performed" (`CREATE_NOT_PERFORMED`) when it can show the VM at that VMID is another request's: a task it recorded for another owner is making it, and every other clone or create task of the provider's PVE user on the node is one it recorded for another owner too. The `Create` is then sent again and gets a new VMID, and the other request's VM is not touched. It stays an **unknown outcome** when the provider cannot show that (a temporary config with no known maker, such as another PVE user's clone; a task it did not record for another owner, such as one started before a provider restart or by another Provider that shares the API token; or a task list or config it cannot read). A `VirtualMachine` deleted at that point needs the `virtrigaud.io/create-outcome` annotation its message names. The provider asks PVE for up to 100000 active tasks (PVE lists 50 by default), so a busy node does not hide one of its own tasks.

Full rules and the `Create`/`Clone` error classes: [VM ownership](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/vm-ownership.md#proxmox) and [ADR-0012](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/adr/0012-proxmox-legacy-unstamped-name-rule.md).

## Reconfigure

`Reconfigure` writes **CPU and memory** from the VMClass with `PUT .../qemu/{vmid}/config`, after the owner check, and returns a PVE task.

| Operation | At v0.4.1 |
|-----------|-----------|
| CPU / memory change | Sent to PVE. If PVE accepts it but stores it as *pending* (hot-plug not enabled for it), the provider **still reports it as applied**: it does not read PVE's `pending` config and never reports *restart required*. Check `qm config <vmid>` / `qm pending <vmid>` if a change does not take effect, and power-cycle the VM. |
| Disk size | **Not applied.** `Reconfigure` resizes no disk: neither the VMClass `diskDefaults.size` nor `spec.disks[].sizeGiB` goes to a disk. The entries are logged. |
| Failure | A config update PVE fails is answered `VM_OPERATION_FAILED` with a constant message (kept out of the circuit breaker) and retried on a per-VM backoff. |

The provider does not report `supportsHonestReconfigure`. Hot-plug of CPU and memory is up to PVE and the guest (virtio balloon, hot-plug enabled on the VM). A disk-size change alone never triggers a `Reconfigure`; the manager sends one when the effective CPU or memory changes. See [Reconfigure results](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/reconfigure-results.md#other-providers).

## Disks

The Proxmox `Create` keeps the template's disks. It attaches no `spec.disks`, and no `Reconfigure` resizes one, so a `VirtualMachine` with a non-empty `spec.disks` on a Proxmox Provider gets `DisksApplied=False`, reason `NotSupportedByProvider`, and a `Warning` event (and an admission warning where the VM validating webhook is rendered: `webhooks.enabled=true` with `manager.maxDiskSize` set). The VM itself runs; `Ready` is unchanged. Size the root disk in the template.

## Snapshots, revert and clone

### Snapshots, including memory state

The provider passes `vmstate=1` to the snapshot API when `snapshotConfig.includeMemory` is true:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMSnapshot
metadata:
  name: pre-upgrade
spec:
  vmRef:
    name: web-server
  snapshotConfig:
    name: pre-upgrade
    description: "Snapshot before upgrade"
    includeMemory: true
```

Memory snapshots are slower (RAM is streamed to storage) but allow point-in-time restore of the running state. A snapshot is a PVE task the manager polls; the snapshot id is its name.

### Revert

Set `spec.snapshot.revertToRef` on the `VirtualMachine` (the VM must be powered off: `spec.powerState: "Off"`). The provider checks the owner and calls `POST .../snapshot/{name}/rollback`, which returns a task recorded in `status.snapshotRevert.taskRef` and polled every 10 seconds; a task that has not completed after 2 hours fails the revert with its outcome unknown. The result is in the `SnapshotReverted` condition. The revert was exercised on a real PVE node during the v0.4.0 release candidates and is covered by controller tests and the in-repo PVE fake. Flow, status fields and GitOps notes: [Reverting a VirtualMachine to a VMSnapshot](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/vm-snapshot-revert.md).

### Cloning

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClone
metadata:
  name: web-server-02
spec:
  source:
    vmRef:
      name: web-server
  target:
    name: web-server-02
  options:
    type: FullClone     # LinkedClone is refused for Proxmox (LinkedCloneUnsupported)
    powerOn: true
```

- **Full clones only.** A `VMClone` with `spec.options.type: LinkedClone` for a Proxmox Provider is refused before the provider is called, with reason `LinkedCloneUnsupported`. The provider never made linked clones, and since v0.4.1 it no longer advertises them. A vSphere `VMClone` is not affected.
- The source is owner-checked before anything is cloned (`VMClone` fails with `VMNotOwned` if the source's VMID was reused). The target is stamped with its `VirtualMachine`'s UID, so a re-sent clone finds the clone instead of making another.
- The clone keeps the source's Notes minus any owner stamp, and gets the VMClass sizing override: since v0.4.1 both **CPU and memory** (a clone kept its source's memory before, whatever the class said).
- **A clone does not carry its source's user-data.** A clone of a VM that has a seed, and any `VMClone` with inline `spec.customization.userData.cloudInit.inline`, gets a seed of its own: `instance-id` `virtrigaud-<UID of the target VirtualMachine>`, its own hostname, the `VMClone`'s inline user-data (else a cloud-config whose body is an empty mapping, which configures nothing) and DHCP on its own MACs. libvirt and vSphere clones re-run the source's user-data; a Proxmox clone does not. A clone of a VM **without** a seed and without inline user-data is unchanged: PVE regenerates its own cloud-init drive.
- **The clone's first boot is a new cloud-init instance**: new SSH host keys, and per-instance modules run again with the distribution's defaults where the user-data is empty. On most cloud images that means `disable_root: true` and the distribution's default user created with passwordless sudo, a locked password and no keys, while what the source's first boot wrote to its disk (its users' sudo rules, for example) stays. Give the `VMClone` inline user-data that sets the users, keys and sudo rules the clone must have:

  ```yaml
  spec:
    customization:
      userData:
        cloudInit:
          inline: |
            #cloud-config
            users:
              - default
              - name: ops
                shell: /bin/bash
                ssh_authorized_keys:
                  - ssh-ed25519 AAAA... ops@example.com
  ```

- A clone that needs a seed is refused before anything is cloned when the provider cannot build one (see the [prerequisites](#seed-prerequisites)). A `VMClone` ends `Failed` and is not retried: fix the cause and re-create it.
- **Do not delete a `VMClone` or its target while it is still cloning.** The manager keeps the VM PVE finishes on purpose (it logs that the cloned VM is not bound), and neither `vcts` nor `virtrigaud-loadgen` can see it, so their cleanup reports success. Find it by the target name and the owner stamp in its Notes, then adopt or destroy it.

## Async tasks, power and phase

Every long-running PVE operation returns a UPID. The provider returns it as a `TaskRef`; the manager polls `TaskStatus` (`/api2/json/nodes/{node}/tasks/{upid}/status`) with jittered backoff until terminal. In-flight tasks are counted by `virtrigaud_provider_tasks_inflight{provider_type="proxmox", provider="<name>"}` ([Observability](../operations/observability.md#11-virtrigaud_provider_tasks_inflight)).

**A power change returns a task**, so `status.phase` shows `Reconfiguring` (`Reconfiguring=True`, reason `Updating`, message "Adjusting power state") while the task runs, then settles to `Running` or `Stopped`. A failed power task is forgotten and shown as `Ready=False/ProviderError` with "Power state change failed: ..."; the power operation is sent again on a per-VM backoff (5 seconds doubling to 5 minutes). A VM whose power was changed on v0.3.11 or a v0.4.0 release candidate stayed in `Reconfiguring` with `Ready=True`; the first reconcile after the upgrade settles it. A task-status query that fails for a transient reason keeps the task recorded; one PVE rejects as malformed or unknown ends it with an error. Power is idempotent: a start of a running VM, or a stop of a stopped one, is success with no task. A suspended or paused guest is reported `On`. See [`status.phase`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/vm-status-phase.md#a-power-change-that-returns-a-task).

**Delete** stops a running VM, destroys it with `purge=1` and waits for the destroy task, so a successful delete means the VM is gone. A VM that is missing from the node asked is treated as deleted only when no node of the cluster has the VMID.

## `status.ips`

`Describe` asks the QEMU guest agent (`/agent/network-get-interfaces`) of a **running** VM, skips `lo` and loopback, link-local (`169.254.`, `fe80:`) addresses, and the manager then applies the common filter (loopback, unspecified, link-local, multicast, non-addresses and duplicates are dropped). If the agent is not installed or not running, `status.ips` is empty. See [`status.ips`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/vm-status-ips.md).

## Cross-hypervisor migration

Proxmox participates in VirtRigaud's storage-backend-agnostic, any-direction cross-hypervisor migration (ADR-0006). Lab-validated as both a **source** and a **target** against vSphere and libvirt over **S3** (v0.3.11), and against libvirt over **NFS**; Proxmox with vSphere over NFS was not run. See the [migration user guide](../migration/user-guide.md#what-virtrigaud-v041-supports) for the full matrix. The disk is staged on the backend and moved with `qemu-img`; it **never traverses a CSI PVC**.

!!! info "Proxmox advertises `s3` and `nfs`, never `pvc`"
    A Proxmox VM's disk lives on PVE node storage, which a Kubernetes pod-mounted PVC can never reach. A `storage.type: pvc` migration with a Proxmox source or target is rejected at capability validation.

### The SSH data plane (migration and user-data)

The Proxmox provider is a **hybrid**: an API-token control plane (the REST API) plus an SSH data plane to the PVE node. The disk of a migration is read and written on the node with node-side tools (`qemu-img`, `qm`, `pvesm`), and the cloud-init seed of a VM with user-data is built there (`genisoimage`, `qm importdisk`, `qm set`), so both need the provider pod to reach the PVE node over SSH. The pod reaches the node **by the API endpoint's host**, with `known_hosts` pinned to it, because in-cluster DNS typically does not resolve the PVE hostname (use the node IP in the endpoint when that is the case).

The Provider Secret must carry SSH credentials in addition to the API token when you intend to migrate **or** your VMs carry `spec.userData`:

```yaml
stringData:
  token_id: "virtrigaud@pve!vrtg-token"     # the API token, unchanged
  token_secret: "<token secret>"
  ssh_user: "root"                           # must be root; "root" is the default
  ssh_privatekey: |                          # or ssh_password
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
  known_hosts: "pve.example.com ssh-ed25519 AAAA..."   # from ssh-keyscan on a trusted host
```

| Secret key | Purpose |
|------------|---------|
| `ssh_user` | SSH username on the PVE node (default `root`). The seed script runs `qm importdisk` and `qm set` and owns a root-only build directory, so a non-root user does not work for user-data. |
| `ssh_privatekey` *or* `ssh_password` | The PEM private key of `root` on the node (use a key only this provider uses), or a password. If both are set, the password is used. |
| `known_hosts` | Pinned SSH host key for the node (`ssh-keyscan -H <node host> > known_hosts` from a trusted machine; compare the fingerprint with the node's). Host-key verification is on by default and has no trust on first use. `PROXMOX_INSECURE_SKIP_HOST_KEY_VERIFICATION=true` in `spec.runtime.env` skips it instead; it is flagged in the provider log and not recommended. |

The provider reads the keys when it starts, so roll or restart it after you change the Secret. Without these keys, control-plane operations still work, but a migration with a Proxmox endpoint fails when it opens the SSH data plane, and a `Create` or `Clone` that needs a seed is refused.

### How each backend moves the disk

- **S3**: the node-side `qemu-img convert -U -O qcow2` streams the disk over SSH into the provider pod, which is the S3 client (`relay` mode: node to pod to S3 to pod to node). `-U` lets the export read a disk whose VM may still be running. `ImportDisk` stages the object on the node as `/var/lib/virtrigaud/import-stage/<namespace>_<vm>-migrated.<format>` (a root-owned `0700` directory; the file is renamed into place and never shared across tenants), runs `qemu-img check` and the size limit; the target VM's `Create` then makes a diskless shell VM, attaches the stage with `qm importdisk` + `qm set`, and removes the stage. The import target storage is `PROVIDER_DEFAULT_STORAGE` / `PVE_DEFAULT_STORAGE`, not hardcoded.
- **NFS**: uses a **kernel NFS mount on the node**, not libnfs, because `pve-qemu-kvm` is built without the libnfs block driver (`qemu-img` rejects `nfs://` with `Unknown protocol 'nfs'`). The export must be written as the migration's `nfs.uid`/`nfs.gid` while `qemu-img` must run as root to read the root-owned source, so the export is two-stage: `qemu-img` (as root) flattens the source to a local temp, then the temp is copied onto the export as `nfs.uid`/`nfs.gid` via `setpriv`.

!!! warning "Set `nfs.uid` / `nfs.gid` to the export owner"
    NFS AUTH_SYS authorizes by the numeric uid/gid the client presents, and the Proxmox node presents the migration's `nfs.uid`/`nfs.gid`. Set them to the uid/gid that **owns the export's files**, or the staged-object read/write fails with `NFS3ERR_ACCES`. `uid: 0` and `gid: 0` are refused at `Validating` for every `VMMigration`. The staged disk is a single **flat** file in the export root (`vmmigrations_<ns>_<name>_export.qcow2`; a migration staged by an older manager keeps the old `vmmigrations-<ns>-<name>-export.qcow2` name): NFS cannot auto-create directories, so use one export per tenant. AUTH_SYS over NFSv3 is cleartext with no Kerberos; run the export on a trusted network with `root_squash` on. See the [VM Migration User Guide](../migration/user-guide.md#nfs-staging) and the [`vmmigration-nfs.yaml`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/examples/vmmigration-nfs.yaml) example.

Run one VirtRigaud installation per PVE node: import-stage names are unique within one Kubernetes cluster only. A `VMMigration` into Proxmox leaves the guest's network to the limitation in [Networking](#networking) (R36). The Proxmox provider is not a clustered provider: it ignores `target_host_id`.

## Known limitations at v0.4.1

- **A `VMClone` whose source is locked is held as `CloneOutcomeUnknown` until it is sent again.** When PVE refuses a clone at once because its source is locked (for example while a snapshot of the source runs, `HTTP 500 VM is locked (snapshot)`), the provider answers "outcome unknown" although PVE started nothing. The `VMClone` is `Pending` with `Ready=False/CloneOutcomeUnknown` and is sent again after the manager's backoff (15 seconds doubling to 5 minutes); it completes on a re-send that finds the lock gone.
- **A `VMSnapshot` create that PVE fails is not retried.** A failed snapshot task (for example a configuration lock timeout because another snapshot of the same VM was running) is answered as a plain failure and the `VMSnapshot` ends `Failed`. libvirt answers a busy domain "not performed", which is retried; Proxmox does not. Create a new `VMSnapshot`.
- **A VMID race can still end "outcome unknown"** where the provider cannot show the other VM is another request's (see [Ownership](#ownership-and-the-name-rule)).
- **A new VM with user-data on node-local storage cannot be moved to another node** while its seed is attached, and a VM with user-data is tied to the node SSH reaches (see [Known limitations of the seed](#known-limitations-of-the-seed)).
- **The SSH credential is root on the node.** Restrict who can read the Provider's Secret.
- **Networks:** `firewall`, `rateLimit` and `mtu` of the `proxmox` block, `VMNetworkAttachment.spec.ipAllocation` and `spec.networks[].macAddress` have no effect; `Describe` reports no NICs. For a VM without user-data a static IP takes effect only when the VM has a PVE cloud-init drive (one its template has); a VM with user-data gets its addresses through the seed's network-config.
- **Cloning:** do not delete a `VMClone` or its target while it is cloning (see [Cloning](#cloning)).
- A `spec.disks` entry is not attached and no disk is resized (see [Disks](#disks)).

## Console access

`Describe` populates `status.consoleURL` with a deep link to the PVE web UI's console view:

```
https://pve.example.com:8006/#v1:0:=qemu/{vmid}:4:5:=console
```

This is a **web-UI deep link**, not a standalone VNC ticket. Open it in a browser; the PVE UI prompts for login and lands on the VM's noVNC console. A first-class VNC ticket (a one-shot ticket from `.../vncproxy` embedded in the URL) is not implemented; the capability matrix marks this cell accordingly.

## Troubleshooting

### CircuitBreaker open for the proxmox provider

```promql
virtrigaud_circuit_breaker_state{provider_type="proxmox", provider="proxmox-cluster"} == 2
```

The CircuitBreaker has fast-failed enough RPCs to PVE to open. Common causes:

- Expired or rotated API token.
- TLS certificate validation failure.
- PVE node down / `pveproxy` service not running.
- API rate-limit (PVE applies per-IP rate limits; verify by `curl`-ing `/version` from inside the provider pod).

The breaker self-recovers once the underlying issue is fixed. Failures scoped to one VM (`VM_OPERATION_FAILED`, `VM_NOT_OWNED`, a refused request) are kept out of the breaker.

### `Ready=False/ValidationError` on a VM with user-data

The provider refused the `Create` before anything was made, and the message names what is missing: the SSH data plane, `ssh_password` or `ssh_privatekey`, `known_hosts`, the `genisoimage` package, or the node selector. Fix the Provider's Secret (and roll the provider, which reads the keys at start), install `genisoimage` and `flock` on the node, or set `PROVIDER_NODE_SELECTOR` to the node SSH reaches. The VM is re-checked with a backoff (up to 10 minutes), or at once when the VM, its VMClass, VMImage or Provider spec changes. See [Seed prerequisites](#seed-prerequisites).

### `storage 'local' does not support content-type 'images'`

The VM has a cloud-init drive or a seed on a storage that does not allow `images` content (the stock `local` directory storage). Set `PVE_DEFAULT_STORAGE` on the Provider to a storage that allows `images` (for example `local-lvm`), or move a PVE cloud-init drive with `qm set <vmid> --ide2 <storage>:cloudinit`. See [Seed storage](#seed-storage).

### `403` while the provider configures a clone

The token lacks `VM.Config.Network`, `VM.Config.Cloudinit` or `SDN.Use` on the bridge. See [PVE privileges](#pve-privileges). The clone is rolled back and the `VirtualMachine` shows PVE's error.

### `Ready=False/VMNotOwned`

The VM at the VMID is not this `VirtualMachine`'s (a reused VMID, a VM renamed in PVE, or a stale stamp from an adoption). If it really is another VM, delete the `VirtualMachine` (the other VM is left alone) and create it again. If it is this VM renamed in PVE, rename it back. To remove a stale stamp, delete the `virtrigaud.owner` line from the VM's Notes. See [Ownership and the name rule](#ownership-and-the-name-rule).

### `401 Unauthorized` from PVE

For token auth, the `Authorization` header must be `PVEAPIToken=user@realm!tokenid=secret`. Test from a debug pod:

```bash
curl -k "https://pve.example.com:8006/api2/json/version" \
  -H "Authorization: PVEAPIToken=virtrigaud@pve!vrtg-token=$SECRET"
```

If that returns 401, the token is bad or the user has no read permission at `/`; see [PVE privileges](#pve-privileges).

### VMID allocation

The VMID comes from PVE's `/cluster/nextid`; the provider no longer falls back to a time-derived id. If the allocation fails, the create is answered "not performed" and retried. If you see `VM <vmid> already exists` or `config file already exists`, another request got the same VMID: the provider answers "not performed" when it can show that, and the retry gets a fresh VMID (see [Ownership and the name rule](#ownership-and-the-name-rule)).

### Guest agent IPs missing

```bash
# On the PVE node:
qm config <vmid> | grep agent
# Should show: agent: enabled=1
```

If `agent:` is absent or `0`, enable it on the VM. Inside the guest, install and enable `qemu-guest-agent`, from the user-data (`packages`) or baked into the template.

### Validation walkthrough

```bash
# 1. Network reachability
curl -k https://pve.example.com:8006/api2/json/version

# 2. Token works
curl -k "https://pve.example.com:8006/api2/json/nodes" \
  -H "Authorization: PVEAPIToken=virtrigaud@pve!vrtg-token=$SECRET"

# 3. Cluster status
curl -k "https://pve.example.com:8006/api2/json/cluster/status" \
  -H "Authorization: PVEAPIToken=virtrigaud@pve!vrtg-token=$SECRET"
```

### Debug logging

```yaml
spec:
  runtime:
    logLevel: debug
```

`logLevel` sets the provider's `LOG_LEVEL`. Tokens and passwords are not written to logs; PVE's error text for a failed request is logged by the provider but only its category reaches a status.

## Performance tips

- **Token auth over password auth**: avoids the session-ticket renewal cycle.
- **Pin the provider pod to a host with fast connectivity to the PVE cluster**: the API is chatty (one call per VM operation, one extra config read per owner-checked call, plus task polling). Size PVE's API rate limits for it.
- **`PROVIDER_NODE_SELECTOR`**: its first entry is where new VMs land, so keep the templates on that node (or on shared storage it can reach). For VMs with user-data it must be the node SSH reaches.

## API reference

- Full CRD field reference: [Generated CRD docs](../references/generated-crd-docs.md).
- Provider gRPC contract: [Generated gRPC docs](../references/grpc-api.md).
- Capability matrix (all providers): [Capabilities](providers-capabilities.md).
- Proxmox API reference: [Proxmox VE API](https://pve.proxmox.com/pve-docs/api-viewer/).

## Support

- Documentation: [VirtRigaud Docs](https://projectbeskar.github.io/virtrigaud/)
- Issues: [GitHub Issues](https://github.com/projectbeskar/virtrigaud/issues), label `provider/proxmox`
