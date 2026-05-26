<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Libvirt Host Preparation

This page is aligned to **VirtRigaud v0.3.6**. It describes what an operator
must set up on a Libvirt/KVM host so the in-tree libvirt provider
(`internal/providers/libvirt/`) can drive it over SSH.

## How the libvirt provider talks to the host

The libvirt provider does **not** link `libvirt.so`. It runs the `virsh` CLI
as a subprocess (`internal/providers/libvirt/virsh.go`) against a libvirt URI
of the form `qemu+ssh://<user>@<host>/system?no_verify=1&no_tty=1`. SSH auth
uses either a password (via `sshpass` + `SSHPASS` env var) or an SSH private
key, both read from the K8s Secret mounted at
`/etc/virtrigaud/credentials/` (`internal/providers/libvirt/virsh.go:115-133`).

!!! danger "SSH host-key verification is disabled in v0.3.6 (#149)"
    The provider sets `no_verify=1` on the libvirt URI
    (`internal/providers/libvirt/virsh.go:167`), which instructs the libvirt
    client to **skip SSH host-key verification entirely**. This means:

    - A man-in-the-middle on the path between the provider pod and the
      libvirt host can present any SSH host key and the provider will accept it.
    - Rotating the libvirt host's SSH key will not break the provider — but
      that property is the wrong kind of "robust": it eliminates the security
      property the host key is supposed to provide.

    **You cannot rely on SSH host-key verification as a security control.**
    Until #149 lands (operator-supplied `known_hosts` enforced via a separate
    URI flag), the compensating control is:

    1. A `NetworkPolicy` that locks egress from the provider pod to the
       libvirt host's IP/port only, **and**
    2. Either a private network between cluster and libvirt host, or an
       encrypted CNI overlay (Cilium WireGuard, Calico WireGuard, IPsec).

    See [mTLS](../providers/security/mtls.md) and
    [Security](security.md#what-virtrigaud-is-not-trying-to-protect-against)
    for the broader compensating-controls posture.

## Required packages on the libvirt host

```bash
# Ubuntu/Debian (matches the host the provider has been exercised against)
sudo apt-get update
sudo apt-get install -y \
  qemu-kvm \
  libvirt-daemon-system \
  libvirt-clients \
  bridge-utils \
  cloud-utils \
  genisoimage \
  qemu-utils \
  sshpass   # required only if you use password SSH (key-based is preferred)

# RHEL/CentOS/Fedora
sudo dnf install -y \
  qemu-kvm \
  libvirt \
  libvirt-client \
  bridge-utils \
  cloud-utils \
  genisoimage \
  qemu-img
```

## Hardware virtualization sanity check

```bash
# CPU must report Intel VT-x (vmx) or AMD-V (svm)
egrep -c '(vmx|svm)' /proc/cpuinfo   # > 0

# KVM kernel modules loaded
lsmod | grep kvm                     # kvm_intel or kvm_amd
```

If either of these is empty, the host cannot run KVM guests at all and no
amount of libvirt config will help. Enable VT-x/AMD-V in the BIOS first.

## User and group setup

The libvirt provider creates VMs whose disks live in
`/var/lib/libvirt/images/` (the path is **hard-coded** at
`internal/providers/libvirt/storage.go:121` for the default pool created by
the provider's `EnsureDefaultStoragePool`). For QEMU to read those disks at
runtime, the `libvirt-qemu` user must be able to traverse and read the
directory.

```bash
# Add libvirt-qemu (the QEMU runtime user) to the libvirt group
sudo usermod -aG libvirt libvirt-qemu

# Confirm
id libvirt-qemu | tr ',' '\n' | grep libvirt

# Apply
sudo systemctl restart libvirtd
```

### SSH user the provider authenticates as

Create a dedicated SSH user for the provider. Do **not** reuse `root`.

```bash
sudo useradd -m -s /bin/bash virt-admin
sudo usermod -aG libvirt,kvm virt-admin
```

#### Sudo grant — minimal viable set

The provider invokes `sudo` for a small set of commands. The exact set is
visible by grepping the provider for the strings it sends to
`runVirshCommand("!", "sudo", ...)`:

```bash
grep -rn 'runVirshCommand[^"]*"!", "sudo"' internal/providers/libvirt/
```

For v0.3.6, the minimal sudoers grant is:

```text
# /etc/sudoers.d/virt-admin   (mode 0440, owner root:root)
virt-admin ALL=(ALL) NOPASSWD: /usr/bin/virsh, /usr/bin/qemu-img, /usr/bin/chown, /usr/bin/chmod, /usr/sbin/restorecon, /usr/bin/rm
```

`restorecon` is included because the provider calls it after writing a new
disk file (`internal/providers/libvirt/storage.go:339`). If SELinux is not
installed on the host, the call fails and the provider logs `WARN Failed to
restore SELinux context (may not be using SELinux): ...` and proceeds — that
is expected and is not an error.

### SSH key-based auth (preferred)

```bash
# On the operator workstation (or the cluster's secret-management host)
ssh-keygen -t ed25519 -f ./virtrigaud_libvirt -N ""

# Copy public key to the libvirt host
ssh-copy-id -i ./virtrigaud_libvirt.pub virt-admin@<libvirt-host>

# Verify
ssh -i ./virtrigaud_libvirt virt-admin@<libvirt-host> "virsh version"
```

Then mount the private key as the `ssh-privatekey` key on the credentials
Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: libvirt-creds
  namespace: virtrigaud-system
type: Opaque
stringData:
  username: virt-admin
  ssh-privatekey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
```

The provider reads these keys at
`internal/providers/libvirt/virsh.go:115-133`.

## Storage pool setup

### Default pool

The libvirt provider's `EnsureDefaultStoragePool`
(`internal/providers/libvirt/storage.go:76-117`) auto-creates a pool named
`default` at `/var/lib/libvirt/images` on first connect. If a pool named
`default` already exists *but points elsewhere*, the provider logs a warning
and uses what it finds — it does not relocate the pool.

To check / pre-create manually:

```bash
virsh pool-list --all                      # 'default' should be present
virsh pool-info default                    # should show Path: /var/lib/libvirt/images

# Create manually if missing:
virsh pool-define-as default dir --target /var/lib/libvirt/images
virsh pool-build default
virsh pool-start default
virsh pool-autostart default
```

Directory permissions the provider expects (and creates if missing):

```bash
ls -ld /var/lib/libvirt/images
# Should be drwxrwsrwx, owner root, with the setgid bit set so new files
# inherit the libvirt group.
```

### Linked clones (qcow2 backing files)

!!! warning "Capability flag says yes; in-tree Clone RPC is a stub in v0.3.6"
    The libvirt provider advertises `SupportsLinkedClones: true` from
    `GetCapabilities` (`internal/providers/libvirt/server.go:463`), and the
    underlying qcow2 format does support backing files (the host requirement
    that this section documents). However, the **`Clone` RPC implementation
    itself** (`internal/providers/libvirt/server.go:428-442`) currently
    returns a synthetic `vm-clone-<id>` and a synthetic task ID without
    issuing any storage or libvirt operations. The
    `StorageProvider.CloneVolume` helper exists at
    `internal/providers/libvirt/storage.go:459`, but is not yet invoked by
    the Clone RPC.

    The host preparation in this section is correct for when the Clone RPC
    starts using `CloneVolume` — it does not enable linked-clone behavior in
    v0.3.6 on its own.

The qcow2 format supports a backing file (`qcow2: backing_file=<path>`)
which lets a clone share unchanged blocks with its parent and only allocate
new blocks for writes. Required on the host to take advantage of this:

- `qemu-img` 2.x+ (any current distro ships this).
- Parent qcow2 file in the same pool that the clone will live in (cross-pool
  backing-file references are fragile).
- Sufficient inotify / fanotify budget if you plan dozens of clones from one
  parent (`/proc/sys/fs/inotify/max_user_watches`).

You can pre-create a "golden" volume manually now and reference it from a
future-style clone workflow:

```bash
# On the libvirt host, in /var/lib/libvirt/images:
sudo qemu-img create -f qcow2 -F qcow2 \
     -b /var/lib/libvirt/images/ubuntu-22.04-golden.qcow2 \
     /var/lib/libvirt/images/my-clone.qcow2 20G

sudo chown libvirt-qemu:kvm /var/lib/libvirt/images/my-clone.qcow2
sudo chmod 660           /var/lib/libvirt/images/my-clone.qcow2
```

### Custom storage location

If `/var/lib/libvirt/images` is not where you want VirtRigaud to write disks,
create a *separate* libvirt pool and reference it from your `VMClass` — do
**not** override `/var/lib/libvirt/images` itself, because the default-pool
auto-creation logic is keyed to that path.

```bash
sudo mkdir -p /vm-pool01
sudo chown root:libvirt /vm-pool01
sudo chmod 2770 /vm-pool01     # setgid so new files inherit libvirt group

virsh pool-define-as vm-pool01 dir --target /vm-pool01
virsh pool-build vm-pool01
virsh pool-start vm-pool01
virsh pool-autostart vm-pool01
```

## Image import (the `ImagePrepare` RPC)

!!! warning "ImagePrepare gRPC handler returns a task ref without issuing the import"
    The in-tree libvirt `ImagePrepare`
    (`internal/providers/libvirt/server.go:445-454`) currently returns a
    synthetic task ID and does **not** invoke the real image download path.
    The real download helper —
    `StorageProvider.DownloadCloudImage`
    (`internal/providers/libvirt/storage.go:265-363`) — exists, is correct,
    and is invoked elsewhere (notably during VM creation when an image is
    needed but missing). It is just not yet wired into the `ImagePrepare`
    RPC.

    In practical terms: if you `kubectl apply` a `VMImage` that points at a
    cloud-image URL and then create a `VirtualMachine` that references it,
    the image *will* be downloaded — by the VM-create path, not the
    ImagePrepare path.

The host requirements for the download path are:

- `wget` available in the provider pod's command-execution context (the
  provider invokes it through `virsh -c qemu+ssh://...` shells the command
  to the libvirt host, where it must be installed).
- `qemu-img` for format conversion (`apt install qemu-utils` /
  `dnf install qemu-img`).
- Enough free space in `/tmp` on the libvirt host for the largest image
  you'll be importing (image is downloaded to `/tmp/<volumeName>-temp.img`,
  then converted into the pool — see `storage.go:280`).

## Network configuration

### Bridge networking (recommended for production)

Bridge networking gives VMs first-class L2 access to your physical network.
The example below uses netplan on Ubuntu; consult your distro docs for
alternatives.

!!! warning "Bridge creation interrupts host networking"
    The interface you bridge stops carrying IP traffic for a moment. Do this
    from console / iLO / IPMI, not over SSH on the same interface.

```yaml
# /etc/netplan/01-bridge.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eno1:
      dhcp4: no
      dhcp6: no
  bridges:
    br0:
      interfaces: [eno1]
      dhcp4: yes
      dhcp6: no
      parameters:
        stp: false
        forward-delay: 0
```

```bash
sudo netplan apply
brctl show     # should show br0 with eno1 enslaved
```

Then declare a libvirt network that uses the bridge:

```bash
cat <<EOF > /tmp/host-bridge.xml
<network>
  <name>host-bridge</name>
  <forward mode='bridge'/>
  <bridge name='br0'/>
</network>
EOF

virsh net-define /tmp/host-bridge.xml
virsh net-start host-bridge
virsh net-autostart host-bridge
```

Reference it from a `VMNetworkAttachment`:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMNetworkAttachment
metadata:
  name: corp-bridge
spec:
  type: bridge
  bridgeName: host-bridge      # libvirt network name
```

### NAT (libvirt's `default` network)

If you cannot bridge — typical on a laptop or single-NIC dev host — use the
libvirt-managed NAT network:

```bash
virsh net-list --all
# If 'default' isn't listed:
virsh net-define /usr/share/libvirt/networks/default.xml
virsh net-start default
virsh net-autostart default
```

NAT gives VMs outbound connectivity but no L2 reachability from your network
to the VM. Fine for dev / build farms; not suitable for production VMs that
need to be reachable.

## SELinux / AppArmor

### SELinux (RHEL/CentOS/Fedora)

```bash
getenforce        # Enforcing | Permissive | Disabled

# If Enforcing, label the storage directories so libvirt can read/write them
sudo semanage fcontext -a -t virt_image_t "/var/lib/libvirt/images(/.*)?"
sudo restorecon -Rv /var/lib/libvirt/images

# If you created a custom pool:
sudo semanage fcontext -a -t virt_image_t "/vm-pool01(/.*)?"
sudo restorecon -Rv /vm-pool01
```

The provider invokes `restorecon` itself after writing new disk files
(`internal/providers/libvirt/storage.go:339`). If `restorecon` is not
installed, the call logs a warning and the operation proceeds.

### AppArmor (Ubuntu/Debian)

```bash
sudo aa-status | grep libvirt
```

The default Ubuntu AppArmor profile for libvirtd is permissive enough for
the provider's needs. If you see denials in `journalctl -u apparmor`, work
out which path is being blocked and add it to
`/etc/apparmor.d/local/usr.sbin.libvirtd` rather than disabling the profile.

## Verification

After everything above is in place, run the following on the libvirt host
and the answer should match. These are the same things the provider
checks at runtime.

```bash
# 1. libvirtd is up
sudo systemctl is-active libvirtd                            # active

# 2. virsh can list domains over the URI the provider will use
sudo -u virt-admin virsh -c qemu:///system list --all

# 3. libvirt-qemu can read the image dir
sudo -u libvirt-qemu test -r /var/lib/libvirt/images && echo OK
sudo -u libvirt-qemu test -w /var/lib/libvirt/images && echo OK

# 4. Default pool is active
sudo -u virt-admin virsh pool-info default                   # State: running

# 5. Network is up
sudo -u virt-admin virsh net-list                            # default | host-bridge | active

# 6. SSH from the provider's network reach
ssh -i ~/.ssh/virtrigaud_libvirt virt-admin@<libvirt-host> "virsh -c qemu:///system list --all"
```

If all six succeed and your `Provider` CR's `credentialSecretRef` points at
the Secret you created above, the provider should reach `Ready` after
reconciliation.

## Troubleshooting

### `Permission denied` on disk access

Symptom: VM fails to start, libvirt log shows
`Cannot access storage file ... Permission denied`.

Common causes (most → least common):

1. `libvirt-qemu` is not in the `libvirt` group.
2. Parent directory `/var/lib/libvirt` has mode `0750` and excludes
   `libvirt-qemu`'s group from traverse.
3. The qcow2 file's permissions are `0640` instead of `0660` (the provider
   sets `0777` itself; if you copied files in manually, fix the mode).

```bash
sudo usermod -aG libvirt libvirt-qemu
sudo systemctl restart libvirtd

# Inspect the offending file
ls -l /var/lib/libvirt/images/<vm>-disk.qcow2
sudo chown libvirt-qemu:kvm /var/lib/libvirt/images/<vm>-disk.qcow2
sudo chmod 660 /var/lib/libvirt/images/<vm>-disk.qcow2
```

### `storage pool 'default' is not active`

```bash
virsh pool-start default
virsh pool-autostart default
```

If pool-start fails with a path error, you likely have a stale pool
definition pointing at a path that no longer exists; remove and recreate it:

```bash
virsh pool-destroy default
virsh pool-undefine default
virsh pool-define-as default dir --target /var/lib/libvirt/images
virsh pool-build default
virsh pool-start default
virsh pool-autostart default
```

### SSH connection rejected

Symptom: provider logs `Failed to connect to libvirt: ssh: handshake failed`.

Check, in order:

```bash
# Network reach
nc -vz <libvirt-host> 22

# Cred filenames in the Secret match what the provider reads
kubectl -n virtrigaud-system get secret <libvirt-creds> -o jsonpath='{.data}' | \
  jq 'keys'           # expect "username" + ("ssh-privatekey" or "password")

# Provider container can reach the host
kubectl -n virtrigaud-system exec deploy/<provider-deployment> -- \
  nc -vz <libvirt-host> 22
```

Remember: host-key verification is **disabled** in v0.3.6 (#149), so a host
key mismatch is *not* what you're hitting. If `nc` works and `virsh
version` from inside the provider pod still fails, it's almost always a
credentials / sudo / group-membership issue on the libvirt side, not SSH
itself.

### Cloud-init does not run

The provider builds a cloud-init `cidata` ISO in
`internal/providers/libvirt/cloudinit.go` and uploads it to
`/var/lib/libvirt/images/cloud-init/` on the libvirt host (`cloudinit.go:208`).

Verify on the libvirt host:

```bash
ls -l /var/lib/libvirt/images/cloud-init/*-cidata.iso
# Should be readable by libvirt-qemu:kvm

# Verify the VM has the ISO attached
virsh dumpxml <vm-name> | grep -A 3 "device='cdrom'"

# In the guest, check cloud-init ran
ssh <user>@<vm-ip> "cloud-init status"     # should print: status: done
```

For the network-configuration defaults that the provider injects into
cloud-init meta-data, see the libvirt provider page at
[Providers / Libvirt](../providers/libvirt.md#cloud-init-nocloud-iso).

## Security checklist for production

- [ ] SSH key auth, not password auth. Password auth requires `sshpass` and
      makes the secret rotate-once-per-host instead of per-cluster.
- [ ] Sudo grant restricted to the exact commands above. No `ALL`.
- [ ] `virt-admin` user has no shell login from anywhere except the cluster
      network range (enforced at sshd / firewalld level).
- [ ] `NetworkPolicy` on the libvirt-provider pod that locks egress to the
      libvirt host's IP/port only (compensates for #149).
- [ ] SELinux/AppArmor on the libvirt host stays in Enforcing/enforce mode.
      Diagnose denials by adjusting the profile, not by disabling it.
- [ ] Storage pool on a dedicated filesystem with quotas, so a runaway VM
      cannot fill the root partition.
- [ ] `libvirtd` and `journalctl -u libvirtd` ship to your central log
      aggregator. K8s audit logs separately ship operator-side reconcile
      decisions.

## Cross-references

- [Providers / Libvirt](../providers/libvirt.md) — provider configuration,
  capability flags, and Provider CR spec.
- [Operations / Security](security.md) — full credential flow and the
  STRIDE-style threat model.
- [mTLS Configuration](../providers/security/mtls.md) — what is and is not
  wired in v0.3.6 (#147, #149).
- [Network Policies](../providers/security/network-policies.md) — the
  compensating control while gRPC and SSH-host-key controls are not wired.
