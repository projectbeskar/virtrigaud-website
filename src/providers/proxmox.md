<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Proxmox VE Provider

The Proxmox provider manages VMs on Proxmox Virtual Environment (PVE) via the native PVE REST API. It is the newest production-grade provider in the VirtRigaud tree and is currently maturing toward general availability.

This page is aligned to **VirtRigaud v0.3.7**. Capability claims trace back to the provider's `GetCapabilities` builder in `internal/providers/proxmox/capabilities.go` and the REST client in `internal/providers/proxmox/pveapi/`.

## Status

The Proxmox provider is listed as **Production-beta** in the [capability matrix](providers-capabilities.md). It implements the full v0.3.6 RPC surface, but ConsoleURL is web-UI-deep-link only (not a standalone VNC ticket — see below), and the production-burn-in time is shorter than for vSphere/libvirt.

## Capabilities at a glance

Built via `capabilities.NewBuilder()` in `internal/providers/proxmox/capabilities.go`:

| Capability flag | Value | What it means |
|-----------------|-------|---------------|
| Core (Create/Delete/Power/Describe) | yes | Standard VM lifecycle |
| `Snapshots` | yes | PVE snapshots via the API. |
| `MemorySnapshots` | **yes** | Wired by passing `vmstate=1` to the snapshot API (`internal/providers/proxmox/pveapi/client.go:794-828`). The only provider that truly captures RAM state in v0.3.6. |
| `LinkedClones` | yes | Native PVE linked clones (qcow2 / zfs snapshot-backed). |
| `OnlineReconfigure` | yes | Hot-plug CPU and memory via the config endpoint (guest agent / balloon driver required). |
| `OnlineDiskExpansion` | yes | Online disk grow via the config endpoint; filesystem grow inside the guest is separate. |
| `ImageImport` | yes | PVE templates + cloud-image import. |
| `DiskTypes` | `raw`, `qcow2` | Storage-type-dependent: `qcow2` only works on file-backed storage; `raw` works on LVM/ZFS/Ceph. |
| `NetworkTypes` | `bridge`, `vlan` | Linux bridges (`vmbr0`...) with optional 802.1Q tag. |

The "ConsoleURL" claim deserves nuance — see [Console access](#console-access) below.

For the full cross-provider matrix and resilience / observability story:

- [Provider capabilities matrix](providers-capabilities.md)
- [Operations — Resilience](../operations/resilience.md) — CircuitBreaker (G6 / v0.3.6) wraps every Proxmox RPC.
- [Operations — Observability](../operations/observability.md)

## RPC support

- **Validate** — `client.FindNode()` against the cluster.
- **Create** — `POST /api2/json/nodes/{node}/qemu` or clone from a template VMID. Cloud-init is attached as IDE2 cloudinit drive.
- **Delete** — `DELETE /api2/json/nodes/{node}/qemu/{vmid}`.
- **Power** — `POST /api2/json/nodes/{node}/qemu/{vmid}/status/{start|stop|reset|shutdown}`.
- **Describe** — VM state + guest-agent-derived IPs + console URL deep link + raw PVE provider details.
- **Reconfigure** — `PUT /api2/json/nodes/{node}/qemu/{vmid}/config` for hot-plug CPU/memory.
- **SnapshotCreate / SnapshotDelete / SnapshotRevert** — `/snapshot` subtree of the VMID; honours `includeMemory` via `vmstate=1`.
- **CloneCreate** — `POST /api2/json/nodes/{node}/qemu/{vmid}/clone`. Both `full=0` (linked) and `full=1` (full clone) supported.
- **TaskStatus** — polls the PVE task UPID (`internal/providers/proxmox/pveapi/`). Counts toward `virtrigaud_provider_tasks_inflight`.
- **ConsoleUrl** — web-UI deep link (see below).

## Prerequisites

- Proxmox VE **7.0 or later**, reachable from the manager / provider pod on port `8006/HTTPS`.
- Either an API token *or* a username + password.
- Storage and bridges configured on the PVE nodes — the provider does not create them.

## Authentication

The Proxmox provider reads credentials from the Secret mounted at `/etc/virtrigaud/credentials` inside the provider pod, falling back to environment variables (`internal/providers/proxmox/server.go:60-112`). **Both API tokens and username/password are supported**; tokens are strongly preferred for production.

**The Secret keys are read as files**; the key names matter:

| Secret key | File path | Auth method |
|------------|-----------|-------------|
| `token_id` | `/etc/virtrigaud/credentials/token_id` | API token (e.g. `virtrigaud@pve!vrtg-token`) |
| `token_secret` | `/etc/virtrigaud/credentials/token_secret` | API token secret value |
| `username` | `/etc/virtrigaud/credentials/username` | Username (e.g. `virtrigaud@pve`) — used only if no `token_id` |
| `password` | `/etc/virtrigaud/credentials/password` | Password — used only if no `token_id` |

If a `token_id` + `token_secret` pair is present, the provider uses token auth. Otherwise it falls back to username/password and acquires a session ticket. Mixed credentials in the same Secret are tolerated (token wins).

### API token (recommended)

Create the token in PVE:

```bash
# As root@pam on a PVE node
pveum user add virtrigaud@pve --comment "VirtRigaud"
pveum user token add virtrigaud@pve vrtg-token --privsep 1
# Grant permissions (see "Minimum permissions" below)
pveum acl modify / --users virtrigaud@pve --roles PVEVMAdmin
# Or use a tighter custom role:
# pveum role add VirtRigaud --privs "VM.Allocate,VM.Audit,VM.Config.CPU,VM.Config.Memory,VM.Config.Disk,VM.Config.Network,VM.Config.Options,VM.Monitor,VM.PowerMgmt,VM.Snapshot,VM.Clone,Datastore.AllocateSpace,Datastore.Audit"
# pveum acl modify / --users virtrigaud@pve --roles VirtRigaud
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
    image: "ghcr.io/projectbeskar/virtrigaud/provider-proxmox:v0.3.7"
    service:
      port: 9443
      tls:
        enabled: true
        secretRef:
          name: provider-proxmox-tls
        insecureSkipVerify: false
```

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

Starting in v0.3.7, the manager enforces that every Provider CR has a `spec.runtime.service.tls` block. A Provider without this block fails to reconcile and its status will show `TLSConfigured=False, Reason=TLSBlockMissing` — no Deployment is created.

For full mTLS details see [Security — mTLS](../providers/security/mtls.md).

### `spec.runtime.service.tls` fields

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | bool | Set `true` to enable mTLS. Set `false` for plaintext (dev/lab only; audit-flagged). |
| `secretRef.name` | string | Name of a `kubernetes.io/tls` or `Opaque` Secret containing `tls.crt`, `tls.key`, and `ca.crt`. |
| `insecureSkipVerify` | bool | Skip server certificate verification. Dev-only; never set in regulated environments. |

TLS material mounts at `/etc/virtrigaud/tls` inside the provider pod. Both manager and provider pin TLS 1.3. The `TLSConfigured` status condition reasons are `TLSBlockMissing`, `ExplicitlyDisabled`, `SecretRefMissing`, and `Enabled`.

## Minimum permissions

For an API token using a custom role:

| Permission | Required for |
|------------|-------------|
| `VM.Allocate` | Create VMs |
| `VM.Audit` | Read VM config (used by every `Describe`) |
| `VM.Config.CPU` | Reconfigure CPU |
| `VM.Config.Memory` | Reconfigure memory |
| `VM.Config.Disk` | Disk add / resize |
| `VM.Config.Network` | NIC modifications |
| `VM.Config.Options` | Misc config (boot order, agent, etc.) |
| `VM.Monitor` | Guest agent queries via the API |
| `VM.PowerMgmt` | Start/stop/reset/shutdown |
| `VM.Snapshot` | Snapshot operations |
| `VM.Clone` | Clone operations |
| `Datastore.AllocateSpace` | Provision VM disks |
| `Datastore.Audit` | List storage |

Apply at the path you scope (typically `/`).

## Endpoint formats

| Endpoint | Notes |
|----------|-------|
| `https://pve.example.com:8006` | Cluster-wide endpoint (recommended) — the API auto-routes to the correct node. |
| `https://pve-node-1.example.com:8006` | Single-node endpoint; loses HA if that node goes down. |

The CRD validates HTTPS scheme.

## Node selection

By default the provider selects a node automatically. To pin to specific nodes (e.g., for HA constraints or licensing), set `PROVIDER_NODE_SELECTOR`:

```yaml
spec:
  runtime:
    env:
      - name: PROVIDER_NODE_SELECTOR
        value: "pve-node-1,pve-node-2"
```

## Storage

PVE storage is referenced by ID (e.g., `local-lvm`, `local-zfs`, `cephfs-pool`). The `qcow2` disk type requires file-backed storage; `raw` works on block-backed storage (LVM, ZFS, Ceph). Mismatches return `400 Bad Request` from the PVE API — see [Troubleshooting](#troubleshooting).

In the VMImage, point at the storage by ID:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-22-template
spec:
  source:
    proxmox:
      templateName: "ubuntu-22-template"
      storage: "local-lvm"
```

## Networking

PVE networking maps to Linux bridges (`vmbr0`, `vmbr1`, ...) with optional 802.1Q VLAN tags:

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
  ipAllocation:
    type: DHCP
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
  ipAllocation:
    type: Static
    address: "10.0.100.50/24"
```

Multi-NIC, mixed DHCP/static, and per-NIC MAC pinning are all supported via cloud-init.

## Cloud-init (cicustom + per-NIC ipconfig)

PVE has a native cloud-init implementation. VirtRigaud uses two complementary paths:

1. **`cicustom`** — the provider uploads a custom user-data snippet to PVE storage and references it on the VM config (`cicustom: user=local:snippets/...`).
2. **`ipconfig0`, `ipconfig1`, ...** — for static IP configuration, generated from the `VMNetworkAttachment.ipAllocation` field. These are PVE's per-NIC cloud-init network config.

The IDE2 cloudinit drive is attached automatically at VM creation; the VM picks it up at first boot.

```yaml
spec:
  userData:
    cloudInit:
      inline: |
        #cloud-config
        hostname: web-server
        users:
          - name: ubuntu
            sudo: ALL=(ALL) NOPASSWD:ALL
            ssh_authorized_keys:
              - "ssh-ed25519 AAAA..."
        packages:
          - qemu-guest-agent
        runcmd:
          - systemctl enable --now qemu-guest-agent
```

!!! tip "Install qemu-guest-agent in the guest"
    Without it, `Describe` cannot retrieve IP addresses from the running VM. The provider falls back gracefully but the VM's `status.ips` will be empty until you install + enable the agent.

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
  diskDefaults:
    type: qcow2
    size: "20Gi"
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
  ipAllocation:
    type: DHCP
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
  powerState: On
  networks:
    - name: lan
      networkRef:
        name: lan-vmbr0
  disks:
    - name: data
      sizeGiB: 40
      type: qcow2
  userData:
    cloudInit:
      inline: |
        #cloud-config
        hostname: web-server
        packages: [nginx, qemu-guest-agent]
        runcmd:
          - systemctl enable --now nginx qemu-guest-agent
```

## Reconfiguration

The Proxmox provider supports online (hot-plug) reconfiguration via `PUT /api2/json/nodes/{node}/qemu/{vmid}/config`:

| Operation | Online? | Requirements |
|-----------|---------|--------------|
| CPU increase | yes | Guest CPU hotplug enabled; modern Linux/Windows kernels handle this |
| CPU decrease | partial | Guest cooperation required; may need power cycle for full unplug |
| Memory increase | yes | virtio balloon driver in the guest (install `qemu-guest-agent` + balloon) |
| Memory decrease | partial | May require power cycle for guests that don't release memory cleanly |
| Disk expand | yes | Filesystem grow inside the guest is separate (`resize2fs`, `xfs_growfs`, ...) |
| Disk shrink | **no** | Not supported (data-loss prevention) |

## Snapshots — including memory state

Proxmox is the only v0.3.6 provider that genuinely supports memory snapshots. The provider passes `vmstate=1` to the snapshot API when `VMSnapshot.spec.includeMemory: true` (`internal/providers/proxmox/pveapi/client.go:794-828`):

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMSnapshot
metadata:
  name: pre-upgrade
spec:
  vmRef:
    name: web-server
  description: "Snapshot before upgrade"
  includeMemory: true
```

Memory snapshots are slower (RAM contents are streamed to storage) but allow point-in-time restore of the running state including in-flight transactions.

## Cloning

Both full and linked clones are supported natively by PVE. The provider sets `full=0` for linked clones, `full=1` for full clones (default).

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClone
metadata:
  name: web-server-02
spec:
  source:
    vmRef:
      name: template-vm
  target:
    name: web-server-02
  options:
    type: LinkedClone     # FullClone for an independent copy
    powerOn: true
```

Linked clones share the parent's disk on copy-on-write storage (ZFS / Ceph / qcow2 with backing); the parent must remain available.

## Async task tracking

Every long-running PVE operation returns a UPID (Unique Process ID). The provider returns this as a proto `TaskRef`; the manager polls `TaskStatus` (which calls the PVE `/api2/json/nodes/{node}/tasks/{upid}/status` endpoint) with jittered backoff until terminal.

Since v0.3.6, in-flight tasks are tracked by the `virtrigaud_provider_tasks_inflight{provider_type="proxmox", provider="<name>"}` gauge (G7.3). See [Observability](../operations/observability.md#11-virtrigaud_provider_tasks_inflight).

## Console access

`Describe` populates `status.consoleURL` with a deep link to the PVE web UI's console view (`internal/providers/proxmox/server.go:563-569`):

```
https://pve.example.com:8006/#v1:0:=qemu/{vmid}:4:5:=console
```

This is a **web-UI deep link**, not a standalone VNC ticket. To use it:

1. Open it in a browser.
2. The PVE UI prompts for login (or single sign-on if you have it).
3. You land on the VM's noVNC console.

A first-class VNC ticket endpoint (where the provider would acquire a one-shot ticket via `POST /api2/json/nodes/{node}/qemu/{vmid}/vncproxy` and embed it in the URL) is planned for a future release — see the "Proxmox" section in the [capability matrix roadmap](providers-capabilities.md#future-roadmap). The current matrix marks this cell `⚠️` to reflect the gap.

## Troubleshooting

### CircuitBreaker open for the proxmox provider

```promql
virtrigaud_circuit_breaker_state{provider_type="proxmox", provider="proxmox-cluster"} == 2
```

The CircuitBreaker (G6 / v0.3.6) has fast-failed enough RPCs to PVE to open the breaker. Common causes:

- Expired or rotated API token.
- TLS certificate validation failure.
- PVE node down / `pveproxy` service not running.
- API rate-limit (PVE applies per-IP rate limits; verify by `curl`-ing `/version` from inside the provider pod).

The breaker self-recovers once the underlying issue is fixed; no manual reset needed.

### `storage 'qcow2' requires file-backed storage`

You set `disks.type: qcow2` against a non-file storage type (LVM, ZFS, Ceph RBD). Fix one of two ways:

- Switch the disk type to `raw`.
- Move to a file-backed storage (`local`, `nfs`, `cephfs`).

### `401 Unauthorized` from PVE

For token auth, the `Authorization` header must be `PVEAPIToken=user@realm!tokenid=secret`. Test from a debug pod:

```bash
curl -k "https://pve.example.com:8006/api2/json/version" \
  -H "Authorization: PVEAPIToken=virtrigaud@pve!vrtg-token=$SECRET"
```

If that returns 401, the token is bad or the user has no read permission at `/` — see [Minimum permissions](#minimum-permissions).

### VMID collision in a cluster

The provider derives the VMID from a hash of the VM name + a timestamp suffix. In rare cases (rapid create/delete cycles) collisions can occur. If you see `VM <vmid> already exists`, retry — the next attempt will pick a fresh VMID.

### Guest agent IPs missing

```bash
# On the PVE node:
qm config <vmid> | grep agent
# Should show: agent: enabled=1
```

If `agent:` is absent or `0`, set it via reconfigure. Inside the guest, install + enable `qemu-guest-agent`. The provider's `Describe` queries `/api2/json/nodes/{node}/qemu/{vmid}/agent/network-get-interfaces` and falls back gracefully when the agent is absent, but `status.ips` will be empty.

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

This causes the PVE REST client to log every request/response pair. Tokens / passwords are redacted (`internal/providers/proxmox/pveapi/`); the raw body is included so you can diff against the PVE API docs.

## Performance tips

- **Token auth over password auth**: avoids the session-ticket renewal cycle.
- **qcow2 + ZFS only when you need it**: ZFS does its own snapshotting; qcow2 on ZFS doubles the overhead.
- **Pin the provider pod to a host with fast connectivity to the PVE cluster**: the API is chatty (one call per VM operation, plus task polling).
- **`PROVIDER_NODE_SELECTOR` for HA pinning**: keeps related VMs on the same node where shared storage is local.

## API reference

- Full CRD field reference: [Generated CRD docs](../references/generated-crd-docs.md).
- Provider gRPC contract: [Generated gRPC docs](../references/grpc-api.md).
- Capability matrix (all providers): [Capabilities](providers-capabilities.md).
- Proxmox API reference: [Proxmox VE API](https://pve.proxmox.com/pve-docs/api-viewer/).

## Support

- Documentation: [VirtRigaud Docs](https://projectbeskar.github.io/virtrigaud/)
- Issues: [GitHub Issues](https://github.com/projectbeskar/virtrigaud/issues) — label `provider/proxmox`
