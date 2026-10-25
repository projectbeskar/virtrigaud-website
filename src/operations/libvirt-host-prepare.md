<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Libvirt Host Preparation

This page is aligned to **VirtRigaud v0.4.0**. It describes what an operator
must set up on a Libvirt/KVM host so the in-tree libvirt provider
(`internal/providers/libvirt/`) can drive it over SSH, for a single-host
`Provider` and for every `Host` of a clustered (`topology: cluster`,
experimental) one.

!!! warning "Upgrading from v0.3.11: three host changes are required before the provider rolls"
    A v0.4.0 libvirt provider **fails every VM create on a host** that lacks the
    [cloud-init seed directory](#cloud-init-seed-directory), and cannot read
    libvirt's snapshot overlays without the
    [`VR_DISK_READ` sudo rule](#sudo-rules-for-disk-reads-and-copies) (unless the SSH
    user is `root`). The [default storage pool](#storage-pool-and-image-directories)
    must be at `/var/lib/libvirt/images`. See the [Upgrade Guide](upgrade.md).

## How the libvirt provider talks to the host

The provider pod does **not** link `libvirt.so`. (Its image still contains a `virsh`
binary, kept for a local-connection fallback; remote hosts do not use it.)
It opens an **in-process SSH connection** (`golang.org/x/crypto/ssh`, no `ssh`,
`scp` or `sshpass` binary) to the host and runs `virsh` and ordinary host
commands (`qemu-img`, `mktemp`, `realpath`, `stat`, `sudo`, ...) **on the host**
(`internal/providers/libvirt/virsh.go`, `sshclient.go`). Everything on this page
is therefore a property of the *host*, not of the provider image.

The libvirt endpoint is a URI such as `qemu+ssh://<user>@<host>/system`. The
provider needs only the instance path (`system` or `session`) from it; it does
not use the URI to make a second SSH connection. SSH authentication uses either
a password or a private key, both read from the Kubernetes Secret mounted at
`/etc/virtrigaud/credentials/` (`username`, `password`, `ssh-privatekey`,
`known_hosts`).

!!! note "ADR-0008: a pure-Go libvirt driver is being evaluated side by side"
    A `go-libvirt` driver for `Describe` and `ListVMs` can be run in *shadow*
    mode (`VIRTRIGAUD_LIBVIRT_NATIVE`, off by default) to compare its answers
    with `virsh`'s. The answers served are still `virsh`'s, so host
    requirements do not change. See
    [ADR-0008](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0008-libvirt-pure-go-driver-and-ssh-transport.md).

## Host prerequisites at a glance

| Prerequisite | Why | Section |
|--------------|-----|---------|
| libvirt + QEMU/KVM, `virsh` on the host | The provider runs `virsh` there | [Packages](#required-packages-on-the-libvirt-host) |
| An SSH user in the `libvirt` and `kvm` groups, with a POSIX login shell | libvirt socket access; reads VM disks; quoting | [SSH user](#ssh-user-the-provider-authenticates-as) |
| `known_hosts` entry in the credentials Secret | Host-key verification is on by default (ADR-0004) | [Host-key verification](#ssh-host-key-verification-adr-0004) |
| `default` storage pool at `/var/lib/libvirt/images` | VM disks, imported disks and prepared images live there | [Storage](#storage-pool-and-image-directories) |
| Cloud-init seed directory, owned by the SSH user, mode `0711` | Seeds are built private; **create fails without it** | [Seed directory](#cloud-init-seed-directory) |
| Sudo rules for `qemu-img` (sudo 1.9.10 or later) | Read and copy `0600` snapshot overlays | [Sudo rules](#sudo-rules-for-disk-reads-and-copies) |
| QEMU with the CVE-2024-4467 fix | The provider runs `qemu-img` as root on VM disks | [QEMU version](#qemu-version-cve-2024-4467) |
| `genisoimage`, `curl`, `wget`, `flock`, `timeout`, `sudo` | Seed ISOs, image downloads, locks and time limits | [Packages](#required-packages-on-the-libvirt-host) |
| A bridge or libvirt network the guests attach to; for clustered `Host`s a matching placement label | Guest networking and placement | [Networking](#network-configuration) |

## Required packages on the libvirt host

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y \
  qemu-kvm \
  libvirt-daemon-system \
  libvirt-clients \
  bridge-utils \
  genisoimage \
  qemu-utils \
  curl \
  wget \
  sudo

# RHEL/CentOS/Fedora
sudo dnf install -y \
  qemu-kvm \
  libvirt \
  libvirt-client \
  bridge-utils \
  genisoimage \
  qemu-img \
  curl \
  wget \
  sudo
```

What the provider uses each package for, as implemented:

- `genisoimage` builds the cloud-init NoCloud seed ISO (`cloudinit.go`); its
  `isoinfo` reads a clone source's seed (`clone_seed.go`).
- `curl` downloads `url` images for `ImagePrepare` (`image.go`); `wget` is used
  by the VM-create path when it has to fetch an image itself (`storage.go`).
- `flock` (util-linux) and `timeout` (coreutils) are required for the routed
  calls of a clustered Provider, including a migration into it; a host without
  them refuses the import rather than run it unguarded.
- `qemu-img` must support `dd` for migration imports (NFS and S3 copy the staged
  object once to a local file before importing it).
- `sshpass` is **no longer used**: password authentication is done by the
  in-process SSH client.

## Hardware virtualization sanity check

```bash
# CPU must report Intel VT-x (vmx) or AMD-V (svm)
egrep -c '(vmx|svm)' /proc/cpuinfo   # > 0

# KVM kernel modules loaded
lsmod | grep kvm                     # kvm_intel or kvm_amd
```

If either of these is empty, the host cannot run hardware-accelerated guests.
Enable VT-x/AMD-V in the BIOS first. New domains use `<domain type='kvm'>` when
the host exposes a readable `/dev/kvm` and fall back to software emulation
(`qemu`) otherwise (added after v0.3.11; existing domains are unchanged).

## SSH user the provider authenticates as

Create a dedicated SSH user for the provider. Do **not** reuse a personal
account, and prefer a non-`root` user: a `root` SSH user is not supported on a
pool directory that other accounts can write.

```bash
sudo useradd -m -s /bin/bash virtrigaud
sudo usermod -aG libvirt,kvm virtrigaud
```

- **`libvirt`** gives access to the `qemu:///system` socket.
- **`kvm`** matters since v0.4.0: every VM disk VirtRigaud creates is now
  `0640 libvirt-qemu:kvm` (it was world-writable `0777`), and the provider
  reads disks as a member of `kvm` for `GetDiskInfo`, S3/NFS exports and a full
  clone's copy. Existing disks keep their old mode. If the SSH user is neither
  `root` nor in `kvm`, the reads go through the
  [`VR_DISK_READ` sudo rule](#sudo-rules-for-disk-reads-and-copies), and the
  disk checks fail closed (retried) when they cannot read a disk.
- The login shell must be **POSIX-compatible** (`sh`, `bash`, `dash`, `zsh` or
  `ash`): the provider shell-quotes its commands with POSIX single quotes
  (#331).

### Other commands the provider runs with sudo

Besides the `qemu-img` rules below, the provider runs these as the SSH user with
`sudo` (`internal/providers/libvirt/`): `rm -f` of VM disks and of a stale UEFI
varstore, `chown -h libvirt-qemu:kvm` of new disks (best effort, logged on
failure), `restorecon` after writing files (best effort; a no-op without
SELinux), `dd` for a clone's UEFI varstore, and `mkdir -p` of the pool directory
(best effort). The project documents no confined sudoers rule for these; if the
SSH user is not `root`, how narrowly you can grant them is your decision, and
the account should be treated as host-privileged (see
[Security](security.md)). Do **not** grant `qemu-img` without the argument
patterns below.

## SSH key-based auth (preferred)

```bash
# On the operator workstation (or the cluster's secret-management host)
ssh-keygen -t ed25519 -f ./virtrigaud_libvirt -N ""

# Copy public key to the libvirt host
ssh-copy-id -i ./virtrigaud_libvirt.pub virtrigaud@<libvirt-host>

# Verify
ssh -i ./virtrigaud_libvirt virtrigaud@<libvirt-host> "virsh -c qemu:///system version"
```

Then store the private key as the `ssh-privatekey` key of the credentials Secret
that the `Provider`'s `credentialSecretRef` (or a clustered `Host`'s own
`credentialSecretRef`) names:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: libvirt-creds
  namespace: virtrigaud-system
type: Opaque
stringData:
  username: virtrigaud
  ssh-privatekey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
```

## SSH host-key verification (ADR-0004)

Host-key verification is **on by default** (since v0.3.7). The provider checks
the host key on every connection against the `known_hosts` file mounted at
`/etc/virtrigaud/credentials/known_hosts`. A missing or empty file, or an entry
for another host, is a hard failure: there is no trust-on-first-use. The error
names the problem and `ProviderAvailable` reports it. See
[ADR-0004](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0004-libvirt-ssh-host-key-verification.md).

Collect the key from a trusted network path and add it as the `known_hosts` key
of the credentials Secret. Use a placeholder in files you commit:

```bash
# Hashed form (recommended; the hostname is not stored in clear text)
ssh-keyscan -H <libvirt-host> > known_hosts
cat known_hosts    # |1|hash1|hash2 ssh-ed25519 AAAA...
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: libvirt-creds
  namespace: virtrigaud-system
type: Opaque
stringData:
  username: virtrigaud
  ssh-privatekey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
  known_hosts: |
    |1|REDACTED_HASH_1=|REDACTED_HASH_2= ssh-ed25519 REDACTED_HOST_PUBLIC_KEY
```

After changing the Secret, restart the provider pod so it re-reads the mounted
files.

**Clustered Providers.** The manager copies each `Host`'s `ssh-privatekey` and
`known_hosts` into a Provider-owned `<provider>-hosts` Secret that the provider
mounts, and the same policy applies **per host**: a host without a `known_hosts`
entry cannot be dialled. The `Host` may name its own `credentialSecretRef`;
otherwise the Provider's is used. Both must be in the Provider's namespace. See
the [clustered libvirt guide](../guides/clustered/index.md).

If you must bypass verification temporarily (lab or migration window only; the
provider logs an audit-flagged `WARN`):

```yaml
spec:
  runtime:
    env:
      - name: LIBVIRT_INSECURE_SKIP_HOST_KEY_VERIFICATION
        value: "true"
```

Only the literal value `true` (case-insensitive) turns verification off.

## SSH connection rate-limiting (`MaxStartups` / `fail2ban`)

Since ADR-0008 PR 3 (after v0.3.11) the provider keeps **one persistent in-process
SSH connection per host**, dialled on first use and re-dialled once if a cached
connection turns out to be dead. Each `virsh` or host command runs in its own
SSH *session* on that connection. These host-side limits can still bite:

- **`sshd`'s `MaxSessions`** (default 10) caps the sessions on one connection.
  The provider bounds its own concurrency: 4 concurrent control calls
  (`VIRTRIGAUD_LIBVIRT_MAX_CONCURRENT_VIRSH`) and 2 concurrent long disk streams
  (`VIRTRIGAUD_LIBVIRT_MAX_CONCURRENT_STREAM`) per host, so the defaults fit
  under the sshd default; raise `MaxSessions` before raising those.
- **`sshd`'s `MaxStartups`** caps concurrent *unauthenticated* connections. The
  default (`10:30:100`) starts randomly dropping new connections once 10 are in
  the pre-auth phase. This now matters when many providers or clustered hosts
  (re)connect at once, for example after a manager rollout. A dropped connection
  surfaces to the provider as `kex_exchange_identification: Connection closed by
  remote host`.
- **`fail2ban`** (if you run the `sshd` jail) can interpret a burst of rapid
  (re)connections from one source as an attack and temporarily ban the provider
  pod's source IP, after which *every* call to the host fails until the ban
  expires.

!!! note "The provider retries transient SSH failures, but tune the host too"
    Since v0.3.8 the libvirt provider retries transient SSH connection failures
    with bounded backoff ([#191](https://github.com/projectbeskar/virtrigaud/pull/191)).
    If the host's limits are tight, bursts can still outrun the backoff.

Recommended host-side tuning:

```bash
# /etc/ssh/sshd_config.d/10-virtrigaud.conf
# Raise the concurrent-unauthenticated ceiling for (re)connect bursts.
MaxStartups 60:30:120

# Sessions per connection: keep at least the provider's concurrency (4 + 2).
MaxSessions 10
```

```bash
sudo systemctl reload sshd
```

If you run `fail2ban`, allowlist the provider pod's source range instead of
disabling the jail:

```ini
# /etc/fail2ban/jail.d/virtrigaud.local
[sshd]
# Replace with the cluster/pod CIDR the provider connects from.
ignoreip = 127.0.0.1/8 <provider-source-cidr>
```

```bash
sudo systemctl restart fail2ban
sudo fail2ban-client status sshd   # confirm the provider IP is not banned
```

## Storage pool and image directories

### The `default` pool must be at `/var/lib/libvirt/images`

VM disks, imported migration disks and prepared images are created in libvirt's
`default` storage pool, which VirtRigaud requires to be a directory pool at
`/var/lib/libvirt/images`:

- No `default` pool: the provider creates one at that path on the first create
  or disk import.
- A `default` pool at that path: the provider starts it only if it is inactive.
- A `default` pool at **any other path**: the provider **never changes it**. The
  create or import fails with `InvalidSpec` and a constant message that does
  not name the host or the path (the provider log does). A pool whose path is a
  symbolic link to `/var/lib/libvirt/images`, or the reverse, counts as that
  directory. In v0.3.11 and earlier the provider destroyed and recreated such a
  pool, which could silently rewrite, for example, an NFS-backed `default` pool.

```bash
virsh pool-list --all                       # 'default' should be present and active
virsh pool-dumpxml default | grep '<path>'  # <path>/var/lib/libvirt/images</path>

# Create manually if missing:
virsh pool-define-as default dir --target /var/lib/libvirt/images
virsh pool-build default
virsh pool-start default
virsh pool-autostart default
```

For shared storage (for example an NFS export between the hosts of a clustered
Provider), mount it **at** `/var/lib/libvirt/images` on every host, with the
same path everywhere, instead of pointing the `default` pool somewhere else. The
Host's `status.allocatableStorageBytes` is the free space of this pool alone.

### Who may write the pool directory

The provider writes each disk in a private `.virtrigaud-write-*` directory
(`mktemp -d`, mode `0700`) inside the pool directory and renames it into place,
so the **SSH user must be able to create files in the pool directory**. No
*other* account except `root` may be able to write there unless the directory is
sticky:

```bash
stat -c '%a %U:%G' /var/lib/libvirt/images
```

The provider logs a `WARN` if another account can write the directory. A full
clone, or an S3/NFS disk export, is **refused** (`FailedPrecondition`; on a
clustered Provider `VM_OPERATION_FAILED`) when the source's image chain contains
a symbolic link, when an image of the chain lies in a directory another account
(neither `root` nor the SSH user) can write and that is not sticky, or when the
copy would write below such a directory. Fix a group- or world-writable
directory with `chmod g-w,o-w`, or set the sticky bit. A symbolic link at a
disk's final name is refused (`Conflict`).

### Image directories

A `VMImage` with `source.libvirt.path` (and a `VirtualMachine.spec.importedDisk`)
may name an image file that already exists on the host. Because those objects
are namespaced and tenant-creatable, the provider confines every such path to
the **allowed image directories**: the file's canonical path (`realpath -e`) must
sit **directly** inside one of them (subdirectories are not included), must be a
regular, non-empty file, must not be a VirtRigaud artifact (`*-disk.qcow2`,
`*-migrated.qcow2`, seed ISOs, staging files, dotfiles), must not be in use by
**any** domain on the host, and must be self-contained (no backing file or
external data file). A base image is always **copied** into the VM's own
`<domain>-disk.qcow2`; it is never attached in place.

The default is `/var/lib/libvirt/images` alone. If your images live elsewhere,
in a subdirectory, or in a non-default pool, set `VIRTRIGAUD_LIBVIRT_IMAGE_DIRS`
(a comma- or colon-separated list of absolute directories) on the provider pod
through `spec.runtime.env`:

```yaml
spec:
  runtime:
    env:
      - name: VIRTRIGAUD_LIBVIRT_IMAGE_DIRS
        value: "/var/lib/libvirt/images,/vm-pool01"
```

System directories (`/etc`, `/proc`, `/sys`, ...) are refused. Keep every
allowed image directory writable only by `root` and the SSH user. On a shared
pool, keep the image catalog apart from the pool.
`VIRTRIGAUD_LIBVIRT_IMAGE_DIRS` is for image **sources**; it does not move the
`default` pool. If you add a directory here, add it to the
[`VR_DISK_READ` sudo rule](#sudo-rules-for-disk-reads-and-copies) too.

Full rules: [Image preparation](https://github.com/projectbeskar/virtrigaud/blob/main/docs/image-preparation.md#libvirt-image-paths-sourcelibvirtpath).

### Prepared images (`ImagePrepare`)

A URL-sourced `VMImage` is downloaded **on the host** with `curl` and prepared
as `<pool dir>/<namespace>.<name>_<16 hex>.qcow2` with a stamp file next to it.
The prepared file is read-only (`0444`) and owned by the provider's SSH user, so
the pool directory must be an allowed image directory on a filesystem that
supports hard links (otherwise the prepare fails with `InvalidSource`). Providers
that share a pool directory must use the same SSH user. Downloads are bounded by
`spec.prepare.timeout` and by `VIRTRIGAUD_LIBVIRT_IMAGE_MAX_DOWNLOAD_GIB`
(default 256). The host needs free space in the pool for the largest image plus
its conversion. A **clustered** Provider does not prepare images.

## Cloud-init seed directory

A seed ISO carries the VM's user-data, which may hold passwords, keys and tokens.
Since v0.4.0 the provider builds every seed in a dedicated directory that only
the SSH user can list, and makes each seed file private. The directory **must
exist on every host that creates VMs** (every host of a clustered Provider and
the target host of a migration into libvirt), owned by the SSH user, before the
v0.4.0 libvirt provider runs:

```bash
install -d -m 0711 -o <ssh user> -g <ssh user> /var/lib/libvirt/virtrigaud-seeds
```

- **Where.** `VIRTRIGAUD_LIBVIRT_SEED_DIR` on the provider pod
  (`spec.runtime.env`), default `/var/lib/libvirt/virtrigaud-seeds`. A malformed
  value, or one in `/tmp`, `/var/tmp`, `/run`, `/dev`, `/proc` or `/sys`, fails
  provider start-up.
- **Fail closed.** The provider creates the directory itself only if its SSH
  user may (normally `root`). A directory that is missing, not owned by the SSH
  user, or readable or writable by its group or others, or below a directory
  that is not owned by `root` or the SSH user or that is group/other-writable
  without the sticky bit, is refused. Every create on that host, and every clone
  of a VM that has a seed, then fails with the retryable error `refusing to stage
  cloud-init data`, and resumes once the host is fixed. This includes a create
  without `spec.userData`: every create builds a seed (a default one when none is
  given).
- **Mode `0711`**, not `0700`, unless QEMU runs as the SSH user or `root`: the
  QEMU user must traverse the directory to open the ISO.
- **Keep it local.** Not on NFS or other shared storage: libvirt hands the ISO to
  the QEMU user with `chown`, which a root-squashed export refuses, and the
  cleanup only sees its own host's domains.
- **One directory per SSH user.** On a host shared by Providers with *different*
  SSH users, give each Provider its own directory through
  `VIRTRIGAUD_LIBVIRT_SEED_DIR` in its `spec.runtime.env`, owned by that user.
- **Keep `dynamic_ownership = 1`** in `/etc/libvirt/qemu.conf` (the default), so
  libvirt gives the `0600` ISO to the QEMU user at domain start.
- **It holds secret material.** Every seed carries its VM's user-data in
  plaintext (inside the ISO) for as long as the VM exists. Exclude the directory
  from host backups, or encrypt them, and prefer short-lived bootstrap
  credentials in user-data.
- **Existing VMs** keep their seed where it is (`/tmp/virtrigaud-cloudinit-...`
  or the older per-name directory) and `Delete` still finds it there. Hosts that
  empty `/tmp` at boot, or clean old files from it, remove those seeds and the VM
  no longer starts; the [Upgrade Guide](upgrade.md#leftovers-from-earlier-releases)
  lists the commands to make old seeds private and to move them.

Full reference:
[libvirt domain ownership: cloud-init seed directory](https://github.com/projectbeskar/virtrigaud/blob/main/docs/libvirt-domain-ownership.md#cloud-init-seed-directory).

## Sudo rules for disk reads and copies

The provider reads and copies VM disks as the SSH user, and as `root` through
`sudo -n` **only** for these exact `qemu-img` shapes (`privileged_copy.go`,
`imagepath.go`):

| Operation | Command `sudo -n` runs |
|---|---|
| Chain read: the disk in-use check (clone, export, delete, snapshots), `GetDiskInfo` | `qemu-img info -U -f <qcow2\|raw> --output=json -- <image>` |
| Full clone, single-host | `qemu-img convert -f <qcow2\|raw> -O qcow2 <source> <pool dir>/.virtrigaud-write-XXXXXXXXXX/<clone>-disk.qcow2` |
| Full clone, clustered | the same, wrapped in `timeout --kill-after=10s <N>s` |
| S3 / NFS export | `qemu-img convert -U -f <qcow2\|raw> -O qcow2 <source> <staging file or nfs:// URL>` (clustered: with `timeout`) |

`VR_DISK_READ` (the first row) is what lets the provider read libvirt's `0600`
snapshot overlays (`<domain>-disk.<snapshot>`, `<domain>-disk.<epoch>`), which
even a `kvm` member cannot read. **Without it**, after an offline snapshot or a
revert every *other* VM's snapshot, revert and delete on that host is refused
with a retryable `VM_DISK_CHECK_FAILED` (on a clustered Provider also create and
clone). Skip it only if the SSH user is `root` or already reads those overlays.
The copy rules (`VR_CLONE_COPY`, `VR_EXPORT_COPY`) are needed only to clone or
export a VM that has an external snapshot; without them those copies run as the
SSH user and fail on such a VM.

The rules can only be confined with sudo's regular-expression syntax
(`^...$`), which needs **sudo 1.9.10 or later**. With an older sudo they cannot
be confined and the project does not recommend a wildcard rule: everything works
as before except cloning or exporting a VM whose active disk is such an overlay.

For the default pool directory `/var/lib/libvirt/images`, an SSH user
`virtrigaud`, and an NFS migration export `nfs.example.com:/exports/virtrigaud`
(adjust all three, and the paths of `qemu-img` and `timeout`), exactly as in the
[libvirt clones](https://github.com/projectbeskar/virtrigaud/blob/main/docs/libvirt-clones.md#what-the-copies-run-as-root)
reference:

```
# /etc/sudoers.d/virtrigaud — edit with: visudo -f /etc/sudoers.d/virtrigaud
Cmnd_Alias VR_DISK_READ = /usr/bin/qemu-img ^info -U -f (qcow2|raw) --output=json -- /var/lib/libvirt/images/[^/ ]+$
Cmnd_Alias VR_CLONE_COPY = /usr/bin/qemu-img ^convert -f (qcow2|raw) -O qcow2 /var/lib/libvirt/images/[^/ ]+ /var/lib/libvirt/images/\.virtrigaud-write-[A-Za-z0-9]{10}/[^/ ]+\.qcow2$, \
    /usr/bin/timeout ^--kill-after=10s [0-9]+s qemu-img convert -f (qcow2|raw) -O qcow2 /var/lib/libvirt/images/[^/ ]+ /var/lib/libvirt/images/\.virtrigaud-write-[A-Za-z0-9]{10}/[^/ ]+\.qcow2$
Cmnd_Alias VR_EXPORT_COPY = /usr/bin/qemu-img ^convert -U -f (qcow2|raw) -O qcow2 /var/lib/libvirt/images/[^/ ]+ (/var/lib/libvirt/images/\.virtrigaud-write-[A-Za-z0-9]{10}/\.virtrigaud-export-[^/ ]+\.qcow2|nfs://nfs\.example\.com/exports/virtrigaud/[^?& ]+\?uid=1001&gid=1001)$, \
    /usr/bin/timeout ^--kill-after=10s [0-9]+s qemu-img convert -U -f (qcow2|raw) -O qcow2 /var/lib/libvirt/images/[^/ ]+ (/var/lib/libvirt/images/\.virtrigaud-write-[A-Za-z0-9]{10}/\.virtrigaud-export-[^/ ]+\.qcow2|nfs://nfs\.example\.com/exports/virtrigaud/[^?& ]+\?uid=1001&gid=1001)$
virtrigaud ALL=(root) NOPASSWD: VR_DISK_READ, VR_CLONE_COPY, VR_EXPORT_COPY
```

- Replace `uid=1001&gid=1001` with the SSH user's own `id -u` and `id -g`. Leave
  out `VR_EXPORT_COPY` if the host never exports disks, and leave out the
  `timeout` lines on a single-host Provider.
- **Never** allow `qemu-img *`, `qemu-img convert *` or `timeout *`: sudoers
  wildcards match across spaces, so the account could add options and files of
  its choosing and have root write anywhere. `VR_DISK_READ` replaces the
  `qemu-img info -U *` wildcard that earlier releases documented; replace it when
  you upgrade.
- **Other image directories.** The in-use check reads the chain of *every*
  domain on the host, including backing files in your other allowed image
  directories. List each directory in the rule, with the same `[^/ ]+`
  confinement (one file directly inside it), and escape every regular-expression
  metacharacter in a path with a backslash (`/srv/vm.pool+1` becomes
  `/srv/vm\.pool\+1`). For
  `VIRTRIGAUD_LIBVIRT_IMAGE_DIRS=/var/lib/libvirt/images,/vm-pool01`:

  ```
  Cmnd_Alias VR_DISK_READ = /usr/bin/qemu-img ^info -U -f (qcow2|raw) --output=json -- (/var/lib/libvirt/images|/vm-pool01)/[^/ ]+$
  ```

  Never widen it to a parent directory, a subdirectory wildcard or `.*`.
- **NFS pools.** Root reads reach a file another account owns only when the
  export does not squash root. With `root_squash` the read fails like the SSH
  user's. An export that does not squash root gives root on every client root on
  the export: dedicate it to the Provider's hosts. The NFS part of
  `VR_EXPORT_COPY` makes a root `qemu-img` connect from a reserved source port
  and present the SSH user's uid and gid: grant it only for an export meant for
  VirtRigaud, keep that export dedicated to migrations, and keep `root_squash`
  on. A migration with `nfs.uid: 0` or `nfs.gid: 0` is refused.
- Check the rule with `visudo -c`, then `sudo -l -U <ssh user> /usr/bin/qemu-img
  info -U -f qcow2 --output=json -- <file>`.

Without any rule, a `VR_DISK_READ`-less setup can instead repair each overlay by
hand (`sudo chown -h libvirt-qemu:kvm -- <file>` and `sudo chmod 0640 -- <file>`
with the VM off), which every new snapshot or revert needs again. See
[Unreadable disk images](https://github.com/projectbeskar/virtrigaud/blob/main/docs/libvirt-clones.md#unreadable-disk-images).

### QEMU version (CVE-2024-4467)

The provider runs `qemu-img info` and `qemu-img convert` as root on VM disks.
Upgrade every libvirt host to a QEMU that fixes CVE-2024-4467 (QEMU 9.0.2, 8.2.6
or 7.2.13 and later, or your distribution's backport) **before** you allow those
commands in sudoers. Unfixed versions can be made to open a file named in an
image's external data-file entry. Check with `qemu-img --version` and your
distribution's advisory. VirtRigaud also refuses a copy whose chain has a data
file and opens every disk in the format its domain definition names (qcow2 or
raw, never probed); those checks are defence in depth, not a substitute.

### Linked clones (qcow2 backing files)

Libvirt `VMClone` of type `LinkedClone` is **refused** in v0.4.0 (the clone would
read its source's live disk, and powering the source on corrupts it): use
`FullClone`. A full clone needs a powered-off source. Existing linked clones keep
working, but their source VM cannot be deleted, reverted or snapshotted while
they exist. See [libvirt clones](https://github.com/projectbeskar/virtrigaud/blob/main/docs/libvirt-clones.md).

## Network configuration

A guest attaches through a `VMNetworkAttachment` whose `spec.network.libvirt`
names either a libvirt network (`networkName`) or a host bridge (`bridge.name`).

### Bridge networking (guests on the host's network)

A bridge gives guests first-class L2 access to your physical network. The VM
gets an `<interface type='bridge'>`; the **LAN's DHCP server** answers, not
libvirt, so libvirt holds no lease for it and `status.ips` needs the QEMU guest
agent in the guest (otherwise it stays empty unless the host happens to have an
ARP entry for the guest's MAC). The provider adds the agent channel to every
domain; make sure the image or your `spec.userData` installs and starts
`qemu-guest-agent`. See
[VM status IPs](https://github.com/projectbeskar/virtrigaud/blob/main/docs/vm-status-ips.md).

The example below uses netplan on Ubuntu; consult your distribution for
alternatives.

!!! warning "Bridge creation interrupts host networking"
    The interface you bridge stops carrying IP traffic for a moment. Do this
    from a console, not over SSH on the same interface.

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

Reference the bridge from a `VMNetworkAttachment` (the bridge name is at most 15
characters):

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMNetworkAttachment
metadata:
  name: corp-bridge
  namespace: default
spec:
  network:
    libvirt:
      bridge:
        name: br0
      model: virtio
```

Alternatively declare a libvirt network on the bridge and reference it by
`networkName`:

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

### NAT (libvirt's `default` network)

If you cannot bridge, use the libvirt-managed NAT network:

```bash
virsh net-list --all
# If 'default' isn't listed:
virsh net-define /usr/share/libvirt/networks/default.xml
virsh net-start default
virsh net-autostart default
```

NAT gives guests outbound connectivity but no L2 reachability from your network
to the VM. libvirt runs the DHCP server, so the lease shows in `status.ips`
without the guest agent (v0.4.0-rc8 and later). Not suitable for guests that
must be reachable.

### Clustered `Host`s: placement labels and identical networks

On a clustered Provider every host must offer the networks a VM uses, and the
scheduler enforces it: a `Host` needs `spec.labels` containing
`net.virtrigaud.io/<network>: "true"` for **every** network the VM uses, where
`<network>` is the attachment's `spec.network.libvirt.networkName` or, when that
is empty, `spec.network.libvirt.bridge.name`. A host missing one label is never a
candidate and the VM stays `Placed=False/Unschedulable`. These are
`Host.spec.labels` (placement facts), not Kubernetes metadata labels, so
`kubectl label` does not set them. Create the same bridge or libvirt network, with
the same name, on every host you label for it:

```yaml
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
    net.virtrigaud.io/br0: "true"
  schedulable: true
```

Everything else a clustered host needs (the `HostPool`, placement policies, the
`default` pool and seed directory on each host, restore and re-attach
procedures) is in the [clustered libvirt guide](../guides/clustered/index.md).

## SELinux / AppArmor

### AppArmor (Ubuntu/Debian)

```bash
sudo aa-status | grep libvirt
```

- **Seed directory: no profile change.** `virt-aa-helper` adds every disk source
  of a domain, CD-ROMs included, to that domain's own profile, and the profile
  may read any `*.iso` file. It refuses only system paths (`/etc`, `/usr`,
  `/boot`, `/dev`, ...), which is why the default seed directory lives under
  `/var/lib/libvirt` and why a seed directory in `/tmp`-style locations is
  rejected at start-up.
- **Snapshots and reverts.** A revert that rewrites the cloud-init CD-ROM into a
  `root`-owned overlay inside the seed directory is a path QEMU's profile does
  not let it open and the VM no longer starts. Since v0.4.0-rc7 the provider
  takes snapshots of a powered-off VM with the CD-ROM ejected, and refuses to
  revert to a snapshot that stored it. Take snapshots of VMs you want to be able
  to revert with the VM powered off. See
  [VM snapshot revert](https://github.com/projectbeskar/virtrigaud/blob/main/docs/vm-snapshot-revert.md).
- If you see other denials in `journalctl -u apparmor` or the audit log, work
  out which path is blocked and add it to `/etc/apparmor.d/local/usr.sbin.libvirtd`
  rather than disabling the profile.

### SELinux (RHEL/CentOS/Fedora)

!!! warning "Not tested"
    The v0.4.0 seed directory and snapshot paths were validated on Ubuntu 24.04
    with AppArmor (libvirt 10.0). VirtRigaud has not been run with SELinux
    enforcing against them. On an SELinux host libvirt relabels a domain's disk
    sources at start; if a seeded VM does not start, look for AVC denials on the
    seed directory.

```bash
getenforce        # Enforcing | Permissive | Disabled

# If Enforcing, label the storage directories so libvirt can read/write them
sudo semanage fcontext -a -t virt_image_t "/var/lib/libvirt/images(/.*)?"
sudo restorecon -Rv /var/lib/libvirt/images
```

The provider runs `restorecon` itself (through `sudo -n`) after writing disk
files. Without SELinux, or without `restorecon`, the call is skipped or logged
and the operation proceeds.

## Verification

Run the following on the libvirt host. They are the same things the provider
checks at runtime. Replace `virtrigaud` with your SSH user.

```bash
# 1. libvirtd is up
sudo systemctl is-active libvirtd                            # active

# 2. The SSH user can use the system libvirt instance
sudo -u virtrigaud virsh -c qemu:///system list --all

# 3. Default pool is active and at the required path
sudo -u virtrigaud virsh pool-info default                   # State: running
sudo -u virtrigaud virsh pool-dumpxml default | grep '<path>'

# 4. Seed directory: owned by the SSH user, private
stat -c '%a %U' /var/lib/libvirt/virtrigaud-seeds            # 711 virtrigaud

# 5. The SSH user can create files in the pool directory
sudo -u virtrigaud mktemp -d /var/lib/libvirt/images/.vr-check-XXXXXX | xargs rmdir

# 6. Sudo rule is in place (sudo 1.9.10 or later)
sudo visudo -c
sudo -l -U virtrigaud /usr/bin/qemu-img info -U -f qcow2 --output=json -- /var/lib/libvirt/images/example.qcow2

# 7. Network is up
sudo -u virtrigaud virsh net-list                            # default | host-bridge | active

# 8. SSH from the provider's network, with the key the Secret holds
ssh -i ~/.ssh/virtrigaud_libvirt virtrigaud@<libvirt-host> "virsh -c qemu:///system list --all"
```

If all succeed and your `Provider` CR's `credentialSecretRef` points at the
Secret above, the provider reaches `Ready` after reconciliation. Then create a
test VM through each Provider and confirm it does not fail with `refusing to
stage cloud-init data`.

## Troubleshooting

### `refusing to stage cloud-init data`

Every create on the host (and every clone of a VM that has a seed) fails,
retryably, until the [seed directory](#cloud-init-seed-directory) exists, is
owned by the provider's SSH user, and is not readable or writable by group or
others. The provider log names the directory and the problem.

### `VM_DISK_CHECK_FAILED` / `permission denied reading disk image`

The disk in-use check could not read an image in some domain's chain, usually a
`0600` snapshot overlay. Grant [`VR_DISK_READ`](#sudo-rules-for-disk-reads-and-copies)
over the pool directory (and every other directory VM disks live in), or repair
the overlay by hand. The status never names the image, because it can belong to
another tenant's VM; the provider log does.

### `Permission denied` when a VM starts

Symptom: the VM fails to start and the libvirt log shows `Cannot access storage
file ... Permission denied`. VM disks created by v0.4.0 are `0640
libvirt-qemu:kvm`; disks created by earlier releases are `0777`. Common causes:

1. The disk's owner or mode was changed by hand, or the `chown` after the write
   failed (it is best effort; the provider logs it) and libvirt's dynamic
   ownership is off. Fix the file:

   ```bash
   ls -l /var/lib/libvirt/images/<domain>-disk.qcow2
   sudo chown libvirt-qemu:kvm /var/lib/libvirt/images/<domain>-disk.qcow2
   sudo chmod 0640 /var/lib/libvirt/images/<domain>-disk.qcow2
   ```

2. A directory above the disk does not let the QEMU user traverse it.
3. AppArmor or SELinux denies the path (see above).

### `storage pool 'default' is not active`

```bash
virsh pool-start default
virsh pool-autostart default
```

If `pool-start` fails with a path error, the definition points at a path that no
longer exists. VirtRigaud never destroys or redefines a pool, so fix it yourself:

```bash
virsh pool-destroy default
virsh pool-undefine default
virsh pool-define-as default dir --target /var/lib/libvirt/images
virsh pool-build default
virsh pool-start default
virsh pool-autostart default
```

### SSH connection rejected

Symptom: the provider logs `ssh: handshake failed` or a host-key error. Check in
order:

```bash
# Network reach
nc -vz <libvirt-host> 22

# Keys in the Secret match what the provider reads
kubectl -n virtrigaud-system get secret <libvirt-creds> -o jsonpath='{.data}' | \
  jq 'keys'     # expect "username" + ("ssh-privatekey" or "password"), and "known_hosts"

# The provider pod can reach the host
kubectl -n virtrigaud-system exec deploy/<provider-deployment> -- \
  nc -vz <libvirt-host> 22
```

Host-key verification is **enabled** by default: a missing `known_hosts` key,
or one without an entry for this host, makes the provider refuse to connect.
Check the provider log for `host key verification failed` and add the correct
entry as described in [SSH host-key verification](#ssh-host-key-verification-adr-0004).

If the log shows `kex_exchange_identification: Connection closed by remote
host`, especially in bursts, the host's `sshd` is rate-limiting connections or
`fail2ban` banned the provider's source IP; see
[SSH connection rate-limiting](#ssh-connection-rate-limiting-maxstartups-fail2ban).

### Cloud-init does not run

The provider builds a NoCloud `cidata` ISO on the host with `genisoimage`, in
the [seed directory](#cloud-init-seed-directory)
(`<seed dir>/virtrigaud-cloudinit-<domain>.<random>/cloud-init.iso`, `0600`, owned
by the QEMU user once the domain has started). Verify on the host:

```bash
ls -l /var/lib/libvirt/virtrigaud-seeds/virtrigaud-cloudinit-*/

# Verify the VM has the ISO attached
virsh dumpxml <domain> | grep -A 3 "device='cdrom'"

# In the guest, check cloud-init ran
ssh <user>@<vm-ip> "cloud-init status"     # should print: status: done
```

Without `spec.userData` the default cloud-init provisions **no login user, SSH
key, password or sudo grant** (v0.4.0); supply your own. For the
network-configuration defaults injected into cloud-init meta-data, see
[Providers / Libvirt](../providers/libvirt.md).

## Security checklist for production

- [ ] SSH key auth, not password auth.
- [ ] The SSH user is not `root`, is in `libvirt` and `kvm`, and its sudo grant
      for `qemu-img` is the regex rules above, never `qemu-img *`.
- [ ] sudo is 1.9.10 or later, and QEMU has the CVE-2024-4467 fix.
- [ ] The SSH user has no shell login from anywhere except the cluster network
      range (enforced at `sshd` / firewall level).
- [ ] `known_hosts` is populated and correct in every credentials Secret (a host
      without it cannot be dialled), and `LIBVIRT_INSECURE_SKIP_HOST_KEY_VERIFICATION`
      is **not** set.
- [ ] The seed directory is local, private, excluded from host backups (or the
      backups are encrypted), and one per SSH user.
- [ ] The pool and image directories are writable only by `root` and the SSH
      user (or sticky).
- [ ] `NetworkPolicy` on the libvirt provider pod locks egress to the libvirt
      hosts' IPs and port 22 (defence in depth).
- [ ] SELinux/AppArmor stays in enforcing mode. Diagnose denials by adjusting the
      profile, not by disabling it.
- [ ] Storage pool on a dedicated filesystem with quotas, so a runaway VM cannot
      fill the root partition.
- [ ] `libvirtd` logs and `journalctl -u libvirtd` ship to your central log
      aggregator.

## Cross-references

- [Providers / Libvirt](../providers/libvirt.md): provider configuration,
  capability flags and the Provider CR spec.
- [Clustered libvirt guide](../guides/clustered/index.md): `Host`, `HostPool`,
  placement and the clustered host prerequisites.
- [Upgrade Guide](upgrade.md): the order and the host changes needed for v0.4.0.
- [Operations / Security](security.md): credential flow and the STRIDE-style
  threat model.
- [mTLS Configuration](../providers/security/mtls.md) and
  [Network Policies](../providers/security/network-policies.md): defence in depth
  that complements SSH host-key verification.
