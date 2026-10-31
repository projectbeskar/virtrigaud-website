<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VirtRigaud Upgrade Guide

This guide covers upgrading VirtRigaud installations: the **v0.4.1 to v0.4.2**
path first (control-plane scalability, clustered admission safety and Provider
fault isolation), including the path from a v0.4.2 release candidate, then
**v0.4.0 to v0.4.1**, then the **v0.3.11 to v0.4.0** path, the notes for older
releases, rollback, GitOps and troubleshooting.

!!! info "From v0.4.0, read [Upgrading from v0.4.0 to v0.4.1](#upgrading-from-v040-to-v041)"
    v0.4.1 is a patch release with no CRD schema change and the same roll order
    (CRDs, manager, providers). It has breaking changes for **Proxmox VMs that carry
    user-data** (SSH credentials are now needed) and for **libvirt VMClasses with
    `firmware: UEFI`** (now honoured), and it asks you to rotate any secret a `VMClone`
    set in `spec.customization`. From v0.3.11, follow the v0.3.11 to v0.4.0 path
    ([below](#upgrading-from-v0311-to-v040)) and then the v0.4.1 section.

!!! warning "v0.4.0 is a security-hardening release with breaking changes"
    A full security review of the codebase led to fixes that **break existing
    setups or change defaults**: cross-namespace references fail closed until
    granted, `VirtualMachine.spec.providerRef` becomes immutable once bound, vSphere
    needs a new vCenter privilege, libvirt hosts need a seed directory before the
    provider rolls, and more. Read [Breaking changes](#breaking-changes) and follow
    [Required upgrade order](#required-upgrade-order). **Do the pre-flight
    checks first**: several breaking changes are cheap to prepare for before the
    upgrade and expensive to discover after it.

    The exhaustive per-change reference (every bullet with its cause and its
    queries) is the repository's
    [`docs/upgrading.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/upgrading.md);
    this page is the website's operating summary of it, checked against the v0.4.0
    code.

## Upgrading from v0.4.1 to v0.4.2

v0.4.2 is a patch release of v0.4.1. It makes the manager scale to large clustered Providers, closes gaps in how a clustered Provider's capacity is reserved, stops one VM's failures from blocking its Provider's other VMs, and updates `golang.org/x/net` for two security advisories. It changes the meaning of no API field and no gRPC message, but it **adds one optional `VirtualMachine` status field** (`status.placement.resizeReservation`) and **two manager flags**, and **rolling back is unsupported while a clustered VM holds a resize reservation**. The exhaustive per-change reference is the repository's [`docs/upgrading.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.2/docs/upgrading.md) and the [v0.4.2 release notes](https://github.com/projectbeskar/virtrigaud/releases/tag/v0.4.2); this section is the website's operating summary of them. If you run v0.4.2-rc1 or v0.4.2-rc2, follow [Upgrading from a v0.4.2 release candidate](#upgrading-from-a-v042-release-candidate).

The roll order is unchanged: **CRDs, then the manager, then the providers**. The gRPC contract is unchanged, so providers need no configuration change, but **roll the provider images too**: every binary is rebuilt with `golang.org/x/net` v0.62.0, and the vSphere and Proxmox providers carry fixes. **Roll the vSphere providers together with the manager**: a vSphere provider older than v0.4.2-rc2 behind a v0.4.2 manager does not renew a vCenter session it lost during an outage on its own (restart its pod if that happens; see [vSphere session keepalive](../providers/vsphere.md#session-keepalive-and-recovery)).

!!! warning "Before you upgrade, and before you roll back"
    - **Install the new CRDs before the new manager.** With the v0.4.1 CRD the new manager fails readiness, naming `status.placement.resizeReservation`, whatever the Providers' topology. The `virtrigaud` chart's pre-upgrade CRD hook does this.
    - **Check the image tags Helm will keep** (`helm get values`) and override any you pinned ([below](#helm-values-and-pinned-image-tags)).
    - **Roll each `Provider`'s `spec.runtime.image` yourself**: Helm does not change it ([below](#provider-images-specruntimeimage)).
    - **Expect a one-time re-check of inherited admissions** on clustered Providers when the manager is replaced ([below](#manager-replacement-inherited-admissions-are-re-checked)).
    - **Do not roll back while a clustered VM holds a resize reservation**, and roll the manager and the chart back together ([below](#rolling-back-to-v041)).

Single-host Providers (vSphere, Proxmox, single-host libvirt) are affected mainly by the polling, status-write, connection and circuit-breaker changes under [Behaviour changes](#behaviour-changes-that-are-visible-but-not-breaking). The admission changes apply to `topology: cluster` Providers.

### Upgrade procedure

1. **Inspect the values Helm will carry over**, and note every image tag you set yourself:

    ```bash
    helm get values virtrigaud -n virtrigaud-system
    ```

2. **Check for outstanding resize reservations** (on a first upgrade from v0.4.1 there are none; the command matters for a later rollback, see [Rolling back to v0.4.1](#rolling-back-to-v041)):

    ```bash
    kubectl get virtualmachines -A -o jsonpath='{range .items[?(@.status.placement.resizeReservation)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
    ```

3. **Upgrade the chart** with `--reset-then-reuse-values` (Helm 3.14+). Its pre-upgrade hook applies the CRDs with the `kubectl` image (`ghcr.io/projectbeskar/virtrigaud/kubectl:v0.4.2`, `kubectl` 1.35.10) before the manager rolls. Add a `--set` for each tag you pinned in step 1:

    ```bash
    helm repo update
    helm upgrade virtrigaud virtrigaud/virtrigaud --version 0.4.2 \
      -n virtrigaud-system --reset-then-reuse-values
    # only if you pinned tags, for example:
    #   --set manager.image.tag=v0.4.2 --set crdUpgrade.image.tag=v0.4.2
    ```

4. **Roll the providers** by setting `spec.runtime.image` on each `Provider` to the v0.4.2 image, the vSphere providers in the same change as the manager ([below](#provider-images-specruntimeimage)).
5. **Check the images that actually run** ([below](#check-the-images-that-actually-run)).

If you apply the CRDs yourself instead of through the chart, apply them from the v0.4.2 chart or tag first (see [Helm CRD Upgrades](../getting-started/helm-crd-upgrades.md)).

### CRDs first: `status.placement.resizeReservation`

`VirtualMachine` gains one additive, optional status field, `status.placement.resizeReservation`, a `{cpu, memoryMiB}` footprint. For a `topology: cluster` Provider, an admitted resize-up is recorded there **before** `Reconfigure` is sent, and released only once the provider has confirmed the applied size (see [Placement](../guides/clustered/placement.md#durable-resize-reservation)).

- Existing `VirtualMachine` objects need no migration: a VM without the field is counted exactly as before.
- With an older CRD the API server prunes the field. The manager reports it missing and fails readiness, and any clustered resize-up is held with `Reconfiguring=False/PlacementError` instead of being sent unreserved.
- The CRDs have no other schema change. All 12 CRDs ship in the chart (`crds/`) and are applied by its hook.

### Helm values and pinned image tags

The chart now passes `--client-qps=20 --client-burst=40` to the manager by default, so the manager Deployment changes (one rollout of the manager pod) with the same limits as before.

- **Use `--reset-then-reuse-values`, not `--reuse-values`.** `--reuse-values` reuses the v0.4.1 chart's defaults, including its image tags, so the manager stays on v0.4.1 while the chart's CRD hook still applies the new CRDs. If you do use `--reuse-values`, also set the image tags (for example `--set manager.image.tag=v0.4.2`); the manager then starts without the flags and applies its defaults (the same values).
- **Image tags you set yourself are kept by both options.** `--reset-then-reuse-values` drops only the old chart's defaults: a tag you supplied (`manager.image.tag`, `crdUpgrade.image.tag`, or a `providers.*.image.tag` for a chart-templated provider) is carried over unchanged. Override every pinned tag that still names v0.4.1, or pin the release's digests if you mirror images.
- **A later plain `helm upgrade` reuses the previous revision's values.** If you set a tag to roll back, upgrade again with `--reset-then-reuse-values` or set the tag explicitly.
- **Kustomize:** `config/manager` passes neither flag; the defaults apply.

### Provider images: `spec.runtime.image`

A provider the manager deploys from a `Provider` resource runs the image in that resource's `spec.runtime.image`. **Helm does not change it**, and the manager does not pick a new image by itself. Set it on each `Provider`, for example:

```bash
kubectl patch provider <provider-name> -n <provider-namespace> --type merge \
  -p '{"spec":{"runtime":{"image":"ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.2"}}}'
```

The images are `ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.2`, `provider-libvirt:v0.4.2` and `provider-proxmox:v0.4.2`. Changing the image rolls the provider's Deployment. A clustered Provider runs one replica, so its rollout is a short outage for its VMs' calls. Roll the vSphere providers in the same change as the manager.

### Check the images that actually run

```bash
# the manager (and any chart-templated provider)
kubectl -n virtrigaud-system get deploy \
  -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[*].image
# the providers deployed from Provider resources
kubectl get providers.infra.virtrigaud.io -A \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,IMAGE:.spec.runtime.image
# the running pods, and that the manager pod is the new one and Ready
kubectl -n virtrigaud-system get pods \
  -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[*].image,READY:.status.containerStatuses[*].ready
```

Every VirtRigaud image should end in `:v0.4.2`. To check that what runs is the published release, compare the pods' image digests (`kubectl get pod <pod> -o jsonpath='{.status.containerStatuses[*].imageID}'`) with the release's, and verify signatures as described in [Verifying release images](security.md#verifying-release-artifacts).

### Upgrading from a v0.4.2 release candidate

From v0.4.2-rc1 or v0.4.2-rc2 to v0.4.2 only the manager and provider images change: the CRDs, RBAC, the chart's templates and values and the gRPC contract are the same as both candidates', so there is nothing to migrate. Compared with rc1, v0.4.2 also changes the manager's circuit-breaker accounting, the vSphere provider's session keepalive and one Proxmox error reason ([#472](https://github.com/projectbeskar/virtrigaud/issues/472)); compared with rc2, the code is the same and the images are rebuilt from the release tag. Roll **the manager and every provider together**.

1. **Chart:** `helm upgrade` to the v0.4.2 chart with `--reset-then-reuse-values`. List the tags you pinned with `helm get values virtrigaud -n virtrigaud-system` and override each one that names a release candidate (for example `--set manager.image.tag=v0.4.2`, `crdUpgrade.image.tag`, any `providers.*.image.tag`), because both `--reuse-values` and `--reset-then-reuse-values` keep a tag you supplied.
2. **Providers:** set `spec.runtime.image` on each `Provider` to the v0.4.2 image. Include the vSphere providers in the same change as the manager.
3. **Check the images that actually run** ([above](#check-the-images-that-actually-run)): no VirtRigaud image should still end in `:v0.4.2-rc1` or `:v0.4.2-rc2`.
4. **Resize reservations** written by a release candidate are kept and keep counting; the rollback restrictions in [Rolling back to v0.4.1](#rolling-back-to-v041) apply to them too.

### Manager replacement: inherited admissions are re-checked

Replacing the manager (this upgrade, a rolling restart or any later leader change) hands the new instance pending creates, pending clone targets and resize reservations it did not admit itself. Each is checked once against its host's committed capacity before `Create`, `Clone` or `Reconfigure` is sent (a resize whose requested size the VM's recorded size already covers has nothing left to admit and is not held). One that no longer fits is **not executed**: its record is kept and keeps counting, and the VM waits with reason `InheritedAdmissionOverCapacity` (`Placed=False` for a create or clone, `Reconfiguring=False` for a resize) until the host has room. Bound VMs (describe, power, delete) are never held by this check. Nothing is cleared automatically; releasing a held admission is an administrator decision that needs positive proof; see [Operations and troubleshooting](../guides/clustered/operations.md#an-admission-held-with-inheritedadmissionovercapacity).

!!! warning "There is no provider-side fencing"
    Leader election does not stop a previous manager that is paused (not merely slow) from acting on an answer it receives when it resumes, before it notices it lost its lease. The re-check stops the *new* manager from executing an admission that no longer fits; it does not stop the old one. Restarting a provider pod does not cancel an operation it already accepted. Make sure the old manager pod is gone, not merely not leading, before you act on a held admission.

### Behaviour changes that are visible but not breaking

- **Running VMs are polled every 2 minutes** (5 minutes when powered off; a suspended VM every 2 minutes). v0.4.1 polled every VM every 10 seconds because of a defect in how the requeue interval read the provider's power state. `status.powerState` and `status.ips` of a VM changed outside VirtRigaud are refreshed on that cadence. A VM without an address, or in an unknown state, is still polled every 10 seconds. A status write that would store nothing is no longer sent.
- **A provider connection is validated once**, not before every call: a cached client is reused while its Provider's configuration, its connection and its circuit breaker are unchanged. On a single-host libvirt Provider this removes one `virsh` call to the host per VM reconcile.
- **A Provider's circuit breaker counts failures of the Provider, not of one VM** ([#472](https://github.com/projectbeskar/virtrigaud/issues/472), fixed in v0.4.2-rc2). A failure the provider's gRPC server answered with `Internal` or `Unknown` (how the providers report one VM's backend error) is not counted; failures the provider did not answer, and answers with `Unavailable` or `DeadlineExceeded`, still count, so a Provider that is down still opens the breaker. See [Resilience: circuit breaker](resilience.md#circuit-breaker).
- **The vSphere provider logs in to vCenter again on its own** after a failed re-login: its keepalive keeps trying every 5 minutes instead of stopping. See [vSphere session keepalive](../providers/vsphere.md#session-keepalive-and-recovery).
- **Proxmox: "exists elsewhere in the cluster" is VM-scoped.** That answer now also carries the `VM_OPERATION_FAILED` reason, so it no longer counts toward the Provider's breaker; its code and message are unchanged.
- **A clustered Provider is reconciled on a 60-second resync** instead of on every Host heartbeat. A change to the content of a Host credential Secret (a rotated SSH key) therefore reaches the provider pod on the next resync; see [When the Secret is re-rendered](../guides/clustered/index.md#when-the-secret-is-re-rendered).
- **A new VM is described right after its `Create`**, instead of 5 seconds later.
- **A placement is released on evidence, never on a timer alone.** An in-memory placement is dropped when the cache shows its record, the API server rejected its write, or an authoritative read resolves an ambiguous write. While a write is unresolved the VM is not placed again.
- **A resize reservation is released only on a confirmed `Reconfigure`** (`Reconfiguring=False/ReconcileSuccess` recorded after the reservation, and a `Describe` reporting the VM's vCPUs and memory maximum). Writing a reservation sets `Reconfiguring=True/ResizeReserved` (phase `Reconfiguring`) until the `Reconfigure`'s outcome is recorded, so an earlier resize's success never releases a newer reservation. See [VM Status Reference](../guides/vm-status.md#reconfiguring).
- **A placed VM whose VMClass is deleted or no longer granted** is counted from its recorded size, never at the minimum footprint of 1 vCPU and 128 MiB. If nothing records its size, every capacity admission on its Provider is refused and retried until the class or the grant is restored; the manager logs `placed VirtualMachine has no recorded size and its VMClass cannot be resolved`, naming the VM. See [Committed capacity](../guides/clustered/placement.md#committed-capacity).
- **ImagePrepare from an older manager is still served.** As in v0.4.0 and v0.4.1, an identity-less request from a manager older than v0.4.0 is served in deprecated legacy mode, logged at `WARN` and counted in `virtrigaud_provider_image_prepare_legacy_requests_total`. The refusal the v0.4.1 documentation announced for "the release after v0.4.1" is deferred to a later release, not chosen yet; the log line now ends `refused in a later release` instead of `refused from the next release`.

### Configurable Kubernetes client rate limits

The manager's client-side Kubernetes API rate limits, fixed at 20 requests per second with a burst of 40 in v0.4.1, are set by `--client-qps` and `--client-burst` (chart values `manager.clientQPS` and `manager.clientBurst`). **Nothing changes unless you set them**: the defaults are 20 and 40. They are client-side limits applied to each of the manager's REST clients, not API-server limits, and they change only at a manager restart. A zero, negative or non-numeric value fails the chart render. See [Helm values and pinned image tags](#helm-values-and-pinned-image-tags) for how the chart passes them.

See [Manager flags](../api-reference/cli.md#virtrigaud-manager-flags) and [Installation: optional values](../getting-started/install-helm-only.md#optional-values-worth-knowing). Measured once, in a disposable benchmark cluster with a fake provider, raising QPS from 20 to 100 cut the median time to `Ready` of a 100-VM burst from 20.5 s to 7.9 s, at the price of more manager CPU and some retried conflicts. It is not a recommendation for production clusters.

### Security update: `golang.org/x/net` v0.62.0 and `kubectl` 1.35.10

The Go modules move `golang.org/x/net` from v0.60.0 to v0.62.0, which fixes CVE-2026-78661 (GO-2026-6860) and CVE-2026-97045 (GO-2026-6866); the new version also moves `x/crypto`, `x/sys`, `x/term`, `x/text`, `x/sync` and `x/tools`. `govulncheck` reported both advisories at module level only: no vulnerable function is reachable from VirtRigaud code. The manager and provider images carry the updated modules, so roll the providers as well as the manager. The chart's CRD-hook image ships `kubectl` 1.35.10 (was 1.35.9). Some findings remain; see [Security: v0.4.2 dependency and image findings](security.md#release-v042-dependency-and-image-findings).

### Manager image build

The manager is now built from the `cmd/manager` package, not from the single file `cmd/manager/main.go`. This matters only if you build the image yourself from `build/Dockerfile.manager`; use the Dockerfile and `make build` of the release you build.

### Known limitations in v0.4.2

- **No provider-side fencing** (above).
- **Leader-transition window.** A `pendingHost` write that the old leader sent but never saw answered can be stored after the new leader's cache synced. Until the new leader's cache shows it, the host can be overbooked. That admission is not executed if it no longer fits.
- **A withdrawn resize can keep its reservation indefinitely.** Setting the spec back to the recorded size sends nothing, so a reservation whose last `Reconfiguring` reason is `ValidationError`, `InsufficientHostCapacity`, `InheritedAdmissionOverCapacity` or `ResizeReserved` is not released. No timer releases it, because expiring it could free room that a `Reconfigure` sent earlier may still use. It stays, and keeps counting, until the next resize the provider confirms or the VM is deleted: this over-reserves capacity, it never overbooks a host. **Do not remove it by hand** without proof that no earlier `Reconfigure` can still execute ([procedure](../guides/clustered/placement.md#a-withdrawn-resize-can-keep-its-reservation-indefinitely)). v0.4.2 has no automatic recovery for this; a safe recovery mechanism is tracked in [issue #468](https://github.com/projectbeskar/virtrigaud/issues/468).
- **A withdrawn refused resize keeps its `Reconfiguring` condition** ([issue #473](https://github.com/projectbeskar/virtrigaud/issues/473)). After a resize refused with `InsufficientHostCapacity` is withdrawn, the condition stays until the next resize. It does not mean capacity is reserved: nothing is reserved or retried, and the phase, `Ready` and the accounting are not affected. v0.4.1 behaves the same way.
- **What the circuit breaker still counts.** The breaker classifies a failure by its gRPC code. An answer with `Unavailable` or `DeadlineExceeded` still counts even when it concerns one VM, and a Provider whose gRPC server answers `Internal` or `Unknown` for every VM (an unreachable hypervisor, lost credentials) does not open the breaker. See [Resilience: what the breaker still counts](resilience.md#what-the-breaker-still-counts).
- **Future asynchronous clustered providers** must give each `Reconfigure` a recoverable operation identity and accept a repeated request idempotently before they are admitted for clustered resizes. The libvirt provider's `Reconfigure` is synchronous and declarative.
- **Clustered libvirt Providers remain experimental**; the admission and accounting changes apply to them only.
- **Placement is still serialized per Provider.** With the client rate limit raised, the per-Provider placement step was the next limit measured.
- **The client rate limits apply to every resource type alike** and change only at a restart.

### Rolling back to v0.4.1

**A `helm rollback` can succeed and still be unsafe.** Check the conditions below first; Helm does not.

- **Do not roll back while any clustered VM has an outstanding resize reservation.** A v0.4.1 manager rewrites the whole status without `status.placement.resizeReservation`, so a resize in flight (a reconfigure task, a change pending a restart, or a failed or uncertain attempt) is counted only at its recorded size again, and its host can be overbooked. This rollback is unsupported. List the VMs that still hold one, and roll back only when the command prints nothing:

    ```bash
    kubectl get virtualmachines -A -o jsonpath='{range .items[?(@.status.placement.resizeReservation)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
    ```

    Let those resizes finish and be confirmed. Setting a VM's size back in its spec does not necessarily release its reservation (see the withdrawn-resize limitation above); while one stays, rolling back remains unsupported. Do not clear a reservation by hand to make a rollback possible: that is the unsafe case this restriction exists for, unless you have the proof described in the [withdrawn-resize procedure](../guides/clustered/placement.md#a-withdrawn-resize-can-keep-its-reservation-indefinitely). If a reservation cannot be released safely, stay on v0.4.2 ([#468](https://github.com/projectbeskar/virtrigaud/issues/468)).
- **Roll back the manager and the chart together** (`helm rollback`). A v0.4.1 manager image with the v0.4.2 chart does not start: it rejects the unknown `--client-qps` and `--client-burst` flags. If you roll back the image alone, remove those flags first.
- **The newer CRD stays installed**, because the chart's CRD hook runs on install and upgrade, not on rollback. That is supported: a v0.4.1 manager works with it.
- After a rollback, a v0.4.1 manager does not re-check inherited admissions, and its circuit breaker no longer gets the v0.4.2 fault-isolation accounting.
- Rolling the providers back to v0.4.1 brings back `golang.org/x/net` v0.60.0 and the two CVEs it fixes.

## Upgrading from v0.4.0 to v0.4.1

v0.4.1 is a patch release of v0.4.0: it fixes things, makes the documentation and the API descriptions say what the code does, and finishes some tooling. It ships the code of the third release candidate, v0.4.1-rc3. The chart version is `0.4.1` and every image tag is `v0.4.1` (`ghcr.io/projectbeskar/virtrigaud/manager:v0.4.1`, `.../provider-vsphere:v0.4.1`, `.../provider-libvirt:v0.4.1`, `.../provider-proxmox:v0.4.1`). The exhaustive per-change reference is the repository's [`docs/upgrading.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/upgrading.md#upgrading-from-v040-to-v041) and its [release notes](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/release-notes/next.md); this section is the website's operating summary of them, checked against the v0.4.1 code.

!!! warning "Three changes need an action before you roll the providers"
    - **Proxmox:** a Provider whose VMs carry `spec.userData` needs SSH credentials in its Secret (and `genisoimage` and `flock` on the PVE node). Without them such a `Create` is refused. [Details](#proxmox-user-data-needs-the-ssh-data-plane).
    - **libvirt:** `firmware: UEFI` in a VMClass is honoured now (it was ignored). New VMs of such a class boot with UEFI, so the image must boot with UEFI and the host needs an OVMF package. Check your VMClasses first. [Details](#libvirt-firmware-secure-boot-and-platform-features).
    - **Secrets in a `VMClone`:** if a `VMClone` set `sysprep.productKey`, `sysprep.adminPassword.value`, `sysprep.joinDomain.password.value`, `sysprep.customCommands`, `certificates[].data`, `guestCommands` or `userData.ignition.inline` on v0.4.0 or earlier, **rotate those values**. [Details](#security-fixes-in-v041).

    Everything else is a change in what you see. libvirt hosts also need `curl` for a create from an image URL.

The roll order is the one of v0.4.0: **CRDs, then the manager, then the providers**.

- **The CRDs have no schema change.** Only their `description` texts differ (`kubectl explain` shows the corrected text), and one new condition reason, `RevertNotPerformed`, is a constant in the Go API with no schema effect. Apply them as usual; the `virtrigaud` chart's CRD hook does.
- **The `virtrigaud` chart has no RBAC or values change** (only comments in `values.yaml`). Its webhook template gains the warning-only `vvmclone-customization.kb.io` entry, rendered only with `webhooks.enabled=true`. `helm upgrade` re-tags the images, and the CRD hook uses a newer `kubectl` image (1.35.9, was 1.32.0).
- **The gRPC contract has no field, number or RPC change** (comments only), so providers of the two versions interoperate. **Roll the libvirt providers promptly after the manager:** a v0.4.1 manager reads a v0.4.0 libvirt provider's answers as they are (a single-host failed revert as a failure) and retries every "not performed" snapshot create, so until the provider is rolled a single-host overlay collision or a refusal libvirt will never accept is retried every 10 minutes instead of failing. Only a v0.4.1 provider answers them for good.

If you are upgrading from v0.3.11 or from a v0.4.0 release candidate, do the steps of the sections below them as well, in the order they give. If you run a v0.4.1 release candidate, read [Upgrading from a v0.4.1 release candidate](#upgrading-from-a-v041-release-candidate).

```bash
# Back up first (as for any upgrade)
kubectl get providers,vmclasses,vmimages,vmnetworkattachments,virtualmachines,vmsnapshots,vmclones,vmmigrations,vmsets \
  -A -o yaml > virtrigaud-backup-v0.4.0.yaml

helm repo update
helm upgrade virtrigaud virtrigaud/virtrigaud --version 0.4.1 \
  -n virtrigaud-system --reset-then-reuse-values
```

Then roll each `Provider`'s `spec.runtime.image` to `v0.4.1` (the libvirt providers first), after the actions below that apply to it.

### Security fixes in v0.4.1

- **A `VMClone`'s unused customization secrets are no longer sent to the provider.** Before, the manager sent all of `spec.customization` in the `Clone` request, including `sysprep.productKey`, `sysprep.adminPassword.value`, `sysprep.joinDomain.password.value`, `sysprep.customCommands`, `certificates[].data`, `guestCommands[].command` and `.arguments`, and `userData.ignition.inline`, which no provider acts on. The request now carries only the fields a provider applies or reports (`hostname`, `domain`, `userData.cloudInit.inline` and non-secret parts); nothing changes in what a clone gets. **If you set any of these fields on v0.4.0 or earlier, treat the values as disclosed to the provider (and, without gRPC TLS, to the network between manager and provider) and rotate them.** They are also still **stored in plaintext** in the `VMClone` (the v1beta1 API keeps the fields), so do not put a real credential in them. Clearing a field does not remove copies elsewhere: etcd backups, API-server audit logs (at `Request` level or above), the `kubectl.kubernetes.io/last-applied-configuration` annotation and your GitOps sources. When one of these fields is set, the manager records a `Warning` event (`CustomizationSecretNotSent`) once the provider accepts the clone; with `webhooks.enabled=true` the chart also renders a validating webhook, `vvmclone-customization.kb.io`, that returns one admission **warning** naming such fields on a create and on an update that changes `spec.customization`. It never refuses a write, and its `failurePolicy` is always `Ignore` (timeout 5s), so `VMClone` writes gain no admission dependency. Both name the fields, never their values. It is advisory: to forbid the fields, add your own admission policy.
- **libvirt create-from-URL no longer puts the image URL on the host's command line.** The legacy create path ran `wget <URL>` on the libvirt host, so a URL's user-info or presigned query string was visible in the host's process list and audit log, and the provider logged it in full. It now downloads the way `ImagePrepare` does: `curl -q -K -` with the URL on **standard input**, one transfer, `http`, `https` and `ftp` only, a connect timeout, the size limit (`VIRTRIGAUD_LIBVIRT_IMAGE_MAX_DOWNLOAD_GIB`) and a time limit bounded by the call's deadline. The manager gives a `Create` 5 minutes, so a download is cut off after at most about 4.5 minutes (`wget` had no limit, but the call failed after 5 minutes anyway while `wget` ran on). The same cap applies to `ImagePrepare` downloads, whatever `spec.prepare.timeout` says (the 30-minute default included). The URL is redacted in the provider and manager logs, and errors never contain it. Every image URL takes this path: an `ftp://` URL is now downloaded (before, it was looked up as a template name, which logged it and returned it in the error), and any other scheme, or a URL with spaces or control characters, is refused (`InvalidSpec`). **Failures are classified now:** an HTTP 4xx answer (except 408, 425 and 429) and the permanent `curl` failures are `InvalidArgument`, so the `VirtualMachine` gets `Ready=False/ValidationError` and is re-checked with a [backoff](#a-refused-vm-create-is-retried-with-a-backoff) instead of the generic provider error retried before. **The libvirt host needs `curl`**; if it is missing, the provider log says so.
- **Staging locations are no longer logged (R28).** See [below](#staging-locations-are-no-longer-logged-r28).
- **Provider authors:** a `CloneRequest`'s `customize_json` is an allow-listed subset of `spec.customization`. Do not rely on receiving the fields above.
- The release workflow's `prepare` job runs with `contents: read` only, and the CRD upgrade hook's `kubectl` image is updated (1.35.9 on Alpine 3.24), which cuts the HIGH and CRITICAL image-scan findings that have a fix from 37 to 6.

### Proxmox: user-data needs the SSH data plane

**Who is affected.** A Proxmox `Provider` whose `VirtualMachine`s carry `spec.userData`, or whose `VMClone`s carry `spec.customization.userData.cloudInit.inline` (or clone a VM that has a seed). A `VirtualMachine` without `spec.userData` needs nothing new. To list the VMs that carry user-data (keep the ones whose provider is a Proxmox Provider, `kubectl get providers -A`):

```bash
kubectl get virtualmachines -A -o json | jq -r '.items[]
  | select(.spec.userData != null)
  | "\(.metadata.namespace)/\(.metadata.name) provider=\(.spec.providerRef.name)"'
```

For `VMClone`s with inline user-data:

```bash
kubectl get vmclones -A -o json | jq -r '.items[]
  | select(.spec.customization.userData.cloudInit.inline != null)
  | "\(.metadata.namespace)/\(.metadata.name)"'
```

**What changed.** Up to v0.4.0 the provider read two things out of the user-data with a line scan (the first `name:` as the user, and the `ssh_authorized_keys:` block-list items as that user's keys) and dropped the rest silently, so `runcmd`, `write_files`, `packages` and a second user never reached the guest. From v0.4.1 the provider builds a NoCloud seed CD-ROM on the PVE node over SSH, and the **whole** user-data reaches cloud-init, as on libvirt and vSphere. The seed is used for a new VM (from a template or without one), for a clone that needs one and for a migration's imported disk, and not for a VM that already exists: **existing VMs keep their PVE cloud-init drive and are not converted.** → [Proxmox cloud-init](../providers/proxmox.md#cloud-init-the-nocloud-seed)

**What you must do before you roll the Proxmox provider.**

1. **Add the SSH keys to the Provider's credentials Secret** (the one `spec.credentialSecretRef` names, which already holds `token_id` and `token_secret`, or `username` and `password`):

    ```yaml
    stringData:
      token_id: "virtrigaud@pve!vrtg-token"      # unchanged: the API token
      token_secret: "<token secret>"
      ssh_user: "root"                           # must be root; "root" is the default
      ssh_privatekey: |                          # or ssh_password (if both are set, the password is used)
        -----BEGIN OPENSSH PRIVATE KEY-----
        ...
      known_hosts: "pve.example.com ssh-ed25519 AAAA..."   # ssh-keyscan -H from a trusted host
    ```

    The key is `root`'s on the PVE node that the Provider's `endpoint` names. Use a key only the provider uses, and compare the host key's fingerprint with the node's: host-key verification is on by default and has no trust on first use. The same keys are what a `VMMigration` to or from this Provider already needs. `PROXMOX_INSECURE_SKIP_HOST_KEY_VERIFICATION=true` in the Provider's `spec.runtime.env` skips verification instead; it is flagged in the provider log and not recommended.
2. **Check the node.** `genisoimage` and `flock` must be installed on the PVE node SSH reaches (`command -v genisoimage flock`; both are on every stock PVE node), and the storage the seed goes to must have the `images` content type ([how the storage is chosen](../providers/proxmox.md#seed-storage)).
3. **In a PVE cluster, set `PROVIDER_NODE_SELECTOR`** (`PVE_NODE_SELECTOR` is read too) in the Provider's `spec.runtime.env` to the node of the API endpoint's host. The VM must be on the node SSH reaches; an `endpoint` that is a load balancer in front of several nodes does not work for VMs with user-data. The selector applies to every new VM of the Provider, with or without user-data: its templates (and clone sources) must be on that node, or a template `Create` is refused (`template ... not found on node ...`).
4. **Token privileges.** The seed itself is imported and attached by `root` over SSH. A VM made **without a template** with user-data is now created first and marked ready afterwards, so the token also needs `VM.Audit` and `VM.Config.Options` on it, as it already does for clones.

**What happens without them.** A `Create` or `Clone` that needs a seed and cannot get one is refused **before anything is created** (`InvalidSpec`), with a message that names what is missing (the SSH data plane, `ssh_password` or `ssh_privatekey`, `known_hosts`, `genisoimage`, or the node selector). The user-data is never dropped in silence any more. A `VirtualMachine` shows `Ready=False/ValidationError` and is rechecked with a [backoff](#a-refused-vm-create-is-retried-with-a-backoff); it needs no cleanup, and is created on a recheck once the keys are there (a changed `Secret` is not a change of the `Provider`'s spec, so that recheck can be up to 10 minutes later). A `VMClone` ends `Failed` (`ProviderError`, "clone failed: ...") and is not retried: re-create it. The provider reads the SSH keys when it starts, so roll or restart it after you change the Secret. A node without `flock` is not refused: the seed script cannot take its lock, the VM is kept with an unknown outcome and every re-send repeats it, so check `flock` on the node first.

**Security.** The Provider now holds a root SSH credential to the PVE node. Its changes to the node's config and storage are attributed to `root@pam`, outside the API token's permissions. Restrict who can read the Secret. The user-data is stored in plaintext in the seed volume for the VM's whole life; keep long-lived secrets out of it. → [Security posture](../providers/proxmox.md#security-posture-of-the-ssh-credential)

**Behaviour you will see on the new VMs.**

- **A seed on node-local storage blocks `qm migrate`.** qemu-server refuses to migrate a VM with a local CD-ROM image other than its own PVE cloud-init drive, online or offline: HA and node evacuation cannot move such a VM. Put the VM on a shared storage with `images`, or detach and free the seed before moving it (`pvesm free <volume>`; removing only the CD-ROM leaves the volume on the storage).
- **A clone does not carry its source's user-data.** A clone of a VM that has a seed, and any `VMClone` that gives inline user-data, gets a seed of its own: `instance-id` `virtrigaud-<UID of the target VirtualMachine>`, its own hostname, the `VMClone`'s inline user-data (else a cloud-config that configures nothing) and DHCP on its own MACs. libvirt and vSphere clones re-run the source's user-data; a Proxmox clone does not. Its first boot is a new cloud-init instance (new SSH host keys; per-instance modules run again with the distribution's defaults, so on most cloud images root login is disabled and the default user is created with passwordless sudo, a locked password and no keys, while what the source's first boot wrote to its disk stays). Give the `VMClone` inline user-data that sets what the clone must have. A clone of a VM without a seed and without inline user-data is unchanged.
- **Linked clones.** A `VMClone` with `spec.options.type: LinkedClone` for a Proxmox Provider is refused with reason `LinkedCloneUnsupported`, before the provider is called. The provider never made linked clones and no longer advertises them. Use `FullClone`.
- **A clone gets the class's memory** (it kept the source's memory before, whatever the class said), so a clone's memory can differ from v0.4.0's for the same `VMClone`.
- **The boot order of a VM cloned from a template with user-data** names only its boot disk (the template's first boot disk, else its `bootdisk`, else the first disk) and no longer the cloud-init slot. Every VM that gets a seed ends with the seed out of its boot order. A `VMClone` and a template `Create` without user-data keep the template's or source's order. Prepare templates with `qm set <vmid> --boot order=<boot disk>` (for example `scsi0`).
- **A template made from a VM that has a seed** gives its clones a CD-ROM that references the template's seed. A `Create` with user-data replaces it with the VM's own seed; a `Create` without user-data detaches it, so the VM gets no cloud-init source from the template.
- **A cloud-init drive left on `local` by v0.4.0** can be moved with `qm set <vmid> --ide2 <storage>:cloudinit` on the node.
- **A VMID race is "not performed".** Two `Create`s or `Clone`s that get the same VMID from `/cluster/nextid` at the same time end with one refused by PVE (a config lock timeout, an existing config, or an outright `unable to create VM <vmid>: config file already exists`). In v0.4.0 both were answered with an unknown outcome, so a `VirtualMachine` deleted before its `Create` was sent again was held (`CreateOutcomeUnknown`). The provider now answers "not performed" when it can show the other VM is another request's, and the `Create` is sent again with a new VMID. It stays unknown when it cannot (for example another PVE user's clone, or two Providers sharing an API token). A `VirtualMachine` already held for this reason stays held after the roll: check PVE for a VM stamped with its UID, then record its id or set the `virtrigaud.io/create-outcome` annotation its message names. → [Ownership](../providers/proxmox.md#ownership-and-the-name-rule)

**Rolling back.** The v0.4.0 Proxmox provider knows nothing about a seed. A VM with a seed keeps working, but do not clone a VM that has a seed with a v0.4.0 provider: PVE's clone copies the source's CD-ROM line, so the clone would point at its source's seed volume (same identity, and a volume it does not own).

### libvirt: firmware, secure boot and platform features

These apply to VMs created after the libvirt provider is rolled. Existing domains are not redefined. → [libvirt: firmware, secure boot and platform features](../providers/libvirt.md#firmware-secure-boot-and-platform-features), [host preparation](libvirt-host-prepare.md#uefi-secure-boot-and-platform-features)

- **Secure boot works.** In v0.4.0 a VMClass with `securityProfile.secureBoot: true` produced a q35 domain with the i440fx device layout, and libvirt refused it ("The PCI controller with index='0' must be model='pcie-root' for this machine type"). The create was retried about every 30 seconds, and each retry copied the image again. The domain now uses the q35 device layout, and libvirt selects a Secure Boot OVMF build whose variable-store template has keys enrolled (no hard-coded firmware path), so Secure Boot is enforced from the first boot. **The host needs an OVMF package** (`ovmf`, `edk2-ovmf`, ...) that installs firmware descriptors in `/usr/share/qemu/firmware/`. Which keys are trusted depends on that package.
- **Behaviour change: `firmware: UEFI` is honoured** (it was ignored). New VMs of such a VMClass boot with UEFI, without Secure Boot, on q35. Their image must boot with UEFI, and their host needs an OVMF package. On a host without one, the create is refused (`ValidationError`) where v0.4.0 created a BIOS VM. On a **clustered** Provider every host that can receive such a VM needs the package: the scheduler does not consider firmware. Set `firmware: BIOS`, or leave `firmware` unset, to keep BIOS VMs. `EFI` still selects BIOS, as on vSphere. Before the upgrade, list the VMClasses this affects and decide for each:

    ```bash
    kubectl get vmclass -A -o jsonpath='{range .items[?(@.spec.firmware=="UEFI")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
    ```

- **`securityProfile.vtdEnabled` works.** The domain now has a q35 machine and an emulated Intel IOMMU device. In v0.4.0 libvirt refused the domain ("unexpected feature 'iommu'").
- **`performanceProfile.nestedVirtualization` works.** The VM gets the host CPU (`host-passthrough`). In v0.4.0 it required both `vmx` and `svm`, so it never started.
- **VMs with more than one network interface can be created.** In v0.4.0 the second interface collided with the sound card's PCI slot, and libvirt refused the domain.
- **A definition libvirt refuses is a validation error.** The `VirtualMachine` gets `Ready=False` and `Provisioning=False` with reason `ValidationError`, re-checked with a [backoff](#a-refused-vm-create-is-retried-with-a-backoff), instead of a retried provider error. The disk the attempt copied is removed, and deleting the VM is not held as `CreateOutcomeUnknown`. A host that reports no matching UEFI firmware is refused before the image is copied. Other refusals still copy the image on each re-check and then remove it.
- **Delete removes a UEFI VM's own variable store** (`virsh undefine --nvram`). Without it, libvirt refuses to undefine a UEFI domain. A store that is not named after the domain is kept.

A VM that v0.4.0 left retrying a refused create keeps its create marker after the upgrade: its delete can be held as `CreateOutcomeUnknown` for up to 10 minutes, or until you set the annotation its message names, and a disk (`<domain>-disk.qcow2`) that attempt left on the pool is removed only if a later create of the same VM removes it; remove one yourself after checking that no domain uses it.

### A refused VM create is retried with a backoff

No action is required; this changes how often a refused create is sent again.

- **What changed.** When a provider refuses a `VirtualMachine`'s `Create` as an invalid specification (`Ready=False` and `Provisioning=False` with reason `ValidationError`), the manager no longer sends it again every 30 seconds. It waits 30 seconds after the first refusal, then 1, 2, 4 and 8 minutes, then every 10 minutes. Nothing is sent to the provider while it waits: no image prepare, no placement and no `Create`. A libvirt `Create` copies the base image before libvirt refuses the definition, so a refusal that never goes away used to copy the image every 30 seconds.
- **The condition message names the next re-check.** It was `Provider rejected VM create (non-retryable; re-checking every 30s): <detail>` and is now `Provider rejected VM create (non-retryable; re-checking in 4m0s, at 2026-10-26T10:04:30Z, or at once when the VirtualMachine, its VMClass, VMImage or Provider changes): <detail>`. The reason, the provider's detail, the events and the metric are unchanged. A `Conflict` (`ProviderConflict`) keeps its fixed 2-minute re-check and its message. **An alert or script that matches the old text needs the new one.**
- **The other definite refusals are paced the same way.** A `Create` answered `NotFound`, `Unimplemented` (`NotSupported`), or a typed `Unauthorized` or `QuotaExceeded` was re-sent every 5 seconds; it now follows the same backoff and keeps reason `ProviderError` (message `Failed to create VM (non-retryable; re-checking in <wait>, at <time>, or at once when ...): <detail>`). Unchanged: an untyped `FailedPrecondition` or `PermissionDenied` (`CreateRefused`), a "not performed" answer, and every failure that may pass or whose outcome is unknown, which are still retried every 5 seconds or on their own backoff. From a remote provider only `NotFound` and `Unimplemented` are paced (the typed errors come only from the manager's own code), and none of the in-tree providers answers a `Create` with either, so this pacing is covered by unit tests and has not been run against a hypervisor. A remote provider's `Unauthenticated` and `ResourceExhausted` answers are still re-sent every 5 seconds.
- **What retries at once.** A change to the `VirtualMachine`'s spec, or to the spec of its `VMClass`, `VMImage` or `Provider` (the manager now watches those three for a VM whose create was refused), sends the create again within seconds and starts the backoff again. A change that is not a spec change of these objects (a `Secret` the provider reads or the VM's user-data `Secret`, a provider restart, a fix on the host, a `VMNetworkAttachment` edit) is picked up at the next re-check, at most 10 minutes later.
- **Manager restarts.** The backoff is kept in the manager's memory and recovered after a restart from the `Ready` or `Provisioning` message, so a restart does not send the create again early. A VM refused by a v0.4.0 manager (whose message has no next re-check) is sent once after the upgrade and then backs off.
- **A refused image source is paced the same way.** An `ImagePrepare` whose source the provider refuses (the `VMImage` gets `InvalidSource`) is sent again after 30 seconds, doubling to 10 minutes, or at once when the `VMImage`'s `spec.source` or the `Provider`'s spec changes. Before, it was sent again on every 30-second re-check of each VM that uses the image. This wait is in memory only: after a manager restart the first re-check sends the prepare again.
- **No more panic for a new Provider.** Reconciling a VM whose `Provider` had no `status.runtime` yet dereferenced a nil pointer in a log line and panicked (recovered, and retried with rate limiting). It now reports the provider as unreachable.
- **Unchanged.** A VM refused before any provider call (a `VMClass` value or a `spec.resources` override out of range) is still re-checked every 30 seconds, and is now also re-checked at once when its `VMClass` changes. A refused `Reconfigure` keeps its backoff.

### A provider's answer is no longer lost to an edit made during the call

No action is required for new calls. A `VirtualMachine` `Create`, a single-host `VMClone` `Clone` or a `VMSnapshot` `SnapshotCreate` can take minutes. If the object was edited meanwhile (a label, an annotation, a spec change, another tool's update), the status write of the provider's answer conflicted and the answer was lost. The manager now writes the answer again over the object as stored, as long as it still waits for that answer. → [VM status reference](../guides/vm-status.md#an-answer-is-not-lost-to-an-edit-made-during-the-call)

- **An object that an earlier manager already holds stays held** (v0.4.0, rc1 or rc2). The lost answer is not in its status. If a `VirtualMachine` is held as `CreateOutcomeUnknown` and the hypervisor has no VM stamped with its UID, annotate it `virtrigaud.io/create-outcome=not-created@<attempt id>` as its message says. For a `VMClone` or a `VMSnapshot`, release it as described under [Releasing a held object](../guides/vm-status.md#releasing-a-held-object).
- **New `CreateBackoff` messages.** A `Create` the provider did not perform (`CREATE_NOT_PERFORMED`) now reads `The provider answered that it did not perform the last Create sent for this VM, so that request made nothing, and that it can be retried. It is retried with a backoff of up to 5m0s; ...`. Any other `CreateBackoff` (`VM_OPERATION_FAILED`, `VM_DISK_CHECK_FAILED`) reads `The provider could not complete this VM's Create: the operation failed on the provider's host, or a check it needs could not run there. ...`. Both used to read `... it could not verify that no other VM uses its disk, or the operation failed on its host ...`, which named a cause the provider may not have had. The reason, the backoff and the phase are unchanged. The `CreateBackoff` `Warning` event now ends with `Provider answer: <the provider's answer>` (sanitized), as the `CreateRefused` event does. **An alert that matches the old text must be updated.**
- **A `Create` the provider did not perform for a reason not tied to the VM** (`CREATE_NOT_PERFORMED` alone, for example a VMID that could not be allocated) shows the provider's answer in `Provisioning` (`Failed to create VM: <answer>`) instead of "the provider could not be reached or did not answer in time".
- **Still lost:** an answer whose write fails for another reason, an answer that a manager restart cuts short, and a `VMMigration`'s failed attempt whose write conflicts (it is held until you confirm the attempt).

### Provider status after a provider roll

In v0.4.0, `Provider.status.reportedCapabilities` could keep what the previous provider image reported after a roll of `spec.runtime.image`: the manager read the capabilities over its cached connection, which a pod of the old ReplicaSet could still answer while it terminated, and nothing reconciled the `Provider` again once that pod had exited. The gates that read this status (image import and artifact identity, clustered resizes, snapshot reverts, migration backends) then acted on the old image's capabilities. The manager now reads the capabilities only once the provider Deployment's rollout is complete, over a connection opened for the read (bounded to 10 seconds); again when the Deployment changes, 45 seconds after the rollout completed, every 10 minutes while the `Provider` is healthy, and one minute after a failed read (`CapabilitiesReported=False`, reason `CapabilitiesUnavailable`; the recorded capabilities are kept). Expect `reportedCapabilities` to show the new image's answer within about a minute of the rollout completing. `status.lastHealthCheck` is refreshed at least every 10 minutes while the `Provider` is healthy.

`status.healthy` and the `ProviderAvailable` condition now follow the Deployment: with no ready pod, `ProviderAvailable` is `False` (reason `DeploymentNotReady`) and `healthy` is `false` (the field is omitted from the object when `false`, so the `HEALTHY` column of `kubectl get provider` is empty, not `false`); in v0.4.0 they stayed `True` once set. A `VMMigration` waits in validation, and `VMAdoption` waits, until the provider is available again. A vSphere or clustered `Provider` (one replica, `Recreate` strategy) is briefly not available during each of its rollouts, so an alert on `ProviderAvailable=False` can fire during a roll.

The `virtrigaud_manager_reconcile_total{kind="Provider"}` reconciles of a healthy `Provider` are now counted as `outcome="requeue"` rather than `"success"`; dashboards that chart the outcome change shape, alerts on `outcome="error"` do not.

### libvirt: snapshot and revert answers

These change what an operator sees; no action is required before the upgrade.

- **A new disk-only snapshot is refused when its overlay file is already on the host (V12).** v0.4.0 listed this as a known limitation. The provider now probes the paths before it changes anything and refuses: the `VMSnapshot` is `Failed` on single-host and clustered Providers, and the leftover file is never removed or overwritten. Use another snapshot name, or remove the file after you have checked that nothing references it. A `VMSnapshot` that v0.4.0 held for this reason **stays held** after the upgrade: delete it and create one under another name, or confirm the attempt with the `virtrigaud.io/operation-outcome` annotation its message names. → [VM snapshots](../guides/vm-snapshots.md)
- **A `VMSnapshot` create the provider did not perform is retried on a single-host Provider too.** v0.4.0 ended it `Failed`; a clustered Provider already retried it. Now it shows `Ready=False/ProviderError` with the provider's answer in a `SnapshotCreateRetrying` event, and the create is sent again after 1 minute, doubling to 10 minutes, for as long as the object exists. A cause that does not go away (for example an unreadable disk image: grant `VR_DISK_READ`) is retried every 10 minutes until you fix it or delete the `VMSnapshot`. The source snapshot of a `VMMigration` is unchanged: "not performed" fails the attempt and the retry policy decides.
- **A revert the provider did not perform is retried, not counted as an unknown outcome.** The `VirtualMachine`'s `status.snapshotRevert` goes back to `Pending` with `SnapshotReverted=False/RevertNotPerformed` and a `SnapshotRevertNotPerformed` Warning event, and the revert is sent again as a new attempt after 1 minute, doubling to 10 minutes. These answers do not count toward the 5-attempt limit and no longer end `Failed` with "the VM may or may not have been reverted". If you keep a script or alert on that message or on `status.snapshotRevert.attempts`, note that `attempts` counts since the last "not performed" answer.
- **A failed libvirt revert is answered by what the provider proves**: not performed, refused for good (`FailedPrecondition`), `NotFound`, a terminal failure, or "outcome unknown: retry". Single-host messages are constant texts that name no host path or command; the details are in the provider log.
- **On a single-host Provider, a snapshot libvirt cannot take for this VM fails for good** (`InvalidArgument`) when libvirt refuses it before executing because the VM's configuration does not support it; a busy domain or one in the wrong state is still "not performed".
- **A VM delete refreshes the `default` pool (R37)** so `virsh vol-list default` stops listing the deleted disk files (best effort; it refreshes the pool on the host that ran the delete; run `virsh pool-refresh default` on the other hosts of a clustered Provider that share the pool directory).

### libvirt: clustered disk export answers

A clustered `ExportDisk` failure the provider can prove is definite. In v0.4.0 a clustered (routed) export answered every failure on its host as an unknown outcome, so a `VMMigration` whose NFS export the server refused (`MNT3ERR_ACCES`) or whose S3 upload the service refused (`SignatureDoesNotMatch`, `AccessDenied`) was held with `Ready=False/ExportOutcomeUnknown` and re-sent only after 35 minutes. It now answers the failures a single-host Provider proves the same way, so the `VMMigration` fails at once and its retry policy applies. A flatten or convert whose connection dropped or was killed, a host that stopped answering and an upload whose completing call may have taken effect stay unknown, as before.

### Staging locations are no longer logged (R28)

A migration's staging location (an `nfs://` URL with its server, export, path and `uid`/`gid`, an S3 bucket, object key and endpoint) names the tenant's storage. In v0.4.1 it no longer appears in the provider or manager logs, nor in a provider's errors: the libvirt providers (single-host and clustered) replace every URL in host-command log lines and errors by `<redacted <scheme> URL>` (except the libvirt connection URI and `pvc://`) and the staged object's server, export, path, bucket, key and endpoint by `<staged object>`; every provider's S3 client errors and `DeleteStagedDisk` causes are redacted; the vSphere and Proxmox export and import log lines show `<scheme>://<redacted>`; the SDK's `gRPC request completed` line logs the `code` and the status message the manager receives; and the manager redacts its `Starting disk export` and `Starting disk import` lines and the provider answer that a failed `VMMigration` quotes in its status, conditions and Warning event. The cause stays readable (`MNT3ERR_ACCES`, `SignatureDoesNotMatch`). **Logs written by v0.4.0 keep the locations they contain; treat them as sensitive.** A log query or alert that matched a staging URL, bucket or server in these lines needs the new form.

### Command-line tools

- **`vcts` is stricter, and `vcts run` works.** A custom conformance specification that `vcts validate` accepted before may be rejected (unknown keys, a step resource that is not an `infra.virtrigaud.io/v1beta1` kind or names a namespace, a created object's name without `${RUN}`, a `wait` step without a resource and a condition or `validate` entries, unknown capabilities, malformed paths, variables or regular expressions, duplicate test names, names over 63 characters, and a step that touches a `Provider`). Run `vcts validate <dir>` on your specifications. `vcts run` now executes the steps (it reported every step as "not implemented" before) and creates real objects in the namespace you pass with `-n` (`default` if omitted): run it against a non-production cluster. The default `--timeout` is 3 hours (was 30 minutes).
- **`virtrigaud-loadgen` validates ranges and does real work.** A configuration whose `vmTemplate.resources` ranges are outside the `VirtualMachine` `spec.resources` bounds, accepted before because the ranges were unused, is rejected. `power`, `reconfigure`, `snapshot` and `clone` now act on VMs the run created. `vmCount` is now enforced: it is the most VMs a run keeps alive at once (default 10; below 1 is rejected), and creates and clones beyond it are skipped and recorded as skipped (a new last `Skipped` column in `results.csv`). **Size it to your datastore:** it was accepted but ignored before, so a run could fill the storage. No operation starts after the configured `duration`, and an interrupted run exits non-zero after its cleanup. Check your configurations with `--dry-run` (no API call, no kubeconfig).
- **`vrtg-provider init --type proxmox`** is new. → [CLI Tools Reference](../references/cli-tools.md)

### Provider authors: the SDK and proto Go modules are published

From v0.4.1 on, each release tags `sdk/vX.Y.Z` and `proto/vX.Y.Z` next to `vX.Y.Z` (release candidates too), and `vrtg-provider init` from a release writes a `go.mod` that requires them at its own version instead of `replace` directives to a checkout. An existing project can drop its `replace` directives and require all three modules (`github.com/projectbeskar/virtrigaud`, `.../sdk`, `.../proto`) at the same release. Releases up to v0.4.0 have no `sdk/` or `proto/` tags. `go install github.com/projectbeskar/virtrigaud/cmd/<tool>@vX.Y.Z` does not work (the root `go.mod` has `replace` directives): download the CLI binaries from the GitHub release. → [Go modules](../development/providers.md#go-modules-the-sdk-and-proto)

**The SDK's request log changed.** `sdk/provider/middleware` logs `gRPC request completed` and `gRPC stream completed` with a `code` attribute (the gRPC code the caller receives) and an `error` attribute that is the status message the caller receives as a string (or nil), where it logged the handler's `error` value, whose text can carry a cause the provider keeps off the wire (a staging location). A `slog` handler, log query or alert of a provider built on the SDK that keyed on the error value or on its full text must use the new attributes.

### Deprecated: the `virtrigaud-provider-runtime` chart

`charts/virtrigaud-provider-runtime/` is removed in the next minor release. It was never published to the Helm repository or released with the `virtrigaud` chart. It runs a provider `Deployment` outside a `Provider` resource, which the manager never connects to (the manager talks only to the provider it runs for a `Provider`, at `status.runtime.endpoint`), and it bypasses what the manager sets up for that provider: the gRPC TLS/mTLS settings, the credential `Secret` mount, a dedicated ServiceAccount and the hardened security context. If you installed it, create a `Provider` resource for each provider instead, wait until it is `Ready`, then `helm uninstall` the chart's release. The chart's README in the repository maps its values to `Provider` fields.

### Other changes

- **API and proto comments.** The descriptions in the CRDs and `provider.proto` are corrected (fields that nothing acts on say so; the two `insecureSkipVerify` switches are described as separate). No field, number, RPC or option changed. → [CRD overview](../references/crds.md#schema-changes-in-v041)
- **`providers/catalog.yaml`** now lists `v0.4.1` tags and `skip` (not run) for every conformance profile, instead of 0.1.x tags and passes nobody had run.
- **CI** checks proto compatibility with `buf breaking` on pull requests.
- **ImagePrepare from an older manager is still served.** A request without a `VMImage` identity (from a manager older than v0.4.0, ADR-0009) is served in deprecated legacy mode by v0.4.1 as it was by v0.4.0, logged at `WARN` and counted in `virtrigaud_provider_image_prepare_legacy_requests_total`. The log line says "refused from the next release": that is the release after v0.4.1. Keep an alert on the counter.

### Known limitations in v0.4.1

The limitations of v0.4.0 that this release fixes (V12, the Proxmox user-data, the "not performed" revert and snapshot answers, `vcts run` and `virtrigaud-loadgen`, the SDK and proto module tags) are gone. These are known and not fixed; each links to the page that documents it in full.

**New or changed in v0.4.1**

- **A libvirt `ImagePrepare` download is cut off after about 4.5 minutes, whatever `spec.prepare.timeout` says.** Prepare large images from a source close to the libvirt host. → [libvirt provider: Images](../providers/libvirt.md#images)
- **The `VMClone` customization secret fields are only warned about,** and only with webhooks enabled. → [VM Cloning](../guides/advanced/vm-cloning.md#customization-secrets-are-not-sent)
- **Proxmox: a VM with user-data is tied to one node and its seed to its storage;** the seed is written once, at `Create`; NICs a template has but `spec.networks` does not name are not configured; user-data given to a `VMClone` by Secret reference is not applied; the user-data is stored in plaintext in the seed volume; and the SSH credential is root on the node. → [Proxmox known limitations](../providers/proxmox.md#known-limitations-of-the-seed)
- **Proxmox: a `VMClone` and its target deleted while the clone runs leave the cloned VM on PVE,** and neither `vcts` nor `virtrigaud-loadgen` can see it. A VMID race can still end "outcome unknown"; a `VMClone` whose source is locked is held as `CloneOutcomeUnknown` until it is sent again; a `VMSnapshot` create that PVE fails is not retried. → [Proxmox known limitations](../providers/proxmox.md#known-limitations-at-v042)
- **libvirt: a leftover overlay file is never removed for you,** snapshot and revert overlays are `0600` and the disk check needs `VR_DISK_READ` to read them, a create from a `source.libvirt.path` image goes through the same check, files left by an earlier release's refused create stay, and the pool refresh of a VM delete covers the host that ran it. → [libvirt known limitations](../providers/libvirt.md#known-limitations-at-v042)
- **libvirt UEFI: no memory snapshot, and no revert of UEFI variables.** On a clustered Provider whose hosts have different OVMF packages, VMs of one VMClass can get different firmware builds, and a change to a VMClass's `firmware` or `securityProfile` does not change existing VMs. → [libvirt: Firmware](../providers/libvirt.md#firmware-secure-boot-and-platform-features)
- **A refused create is re-sent on a backoff,** and a change that is not a spec change of the VM, its `VMClass`, `VMImage` or `Provider` is picked up at the next re-check, at most 10 minutes later. A libvirt refusal that comes from the define, other than a missing UEFI firmware, still copies the image on each re-check and removes the copy. That includes a secure boot VM on a host that has a Secure Boot build of OVMF but not the one with keys enrolled. A remote provider's `Unauthenticated` and `ResourceExhausted` answers are not paced.
- **`virtrigaud-loadgen` can fill a datastore** (`vmCount` times the disk size, plus snapshots). → [CLI Tools Reference](../references/cli-tools.md#virtrigaud-loadgen)
- **A resize of a single-host `VMClone` target is ignored (also in v0.4.0).** A `VirtualMachine` bound by a single-host `VMClone` has no `status.currentResources`, and the manager sends a `Reconfigure` only when the effective size differs from a recorded one, so an edit of the target's `spec.resources` or of its `VMClass` sends nothing and the hypervisor VM keeps the size it was cloned at. Create the `VMClone` with the target `VMClass` already at the size you want, or resize the VM on the hypervisor.
- **A `VMMigration`'s failed attempt whose status write conflicts is still held** (`SnapshotOutcomeUnknown`, `ExportOutcomeUnknown`, `ImportOutcomeUnknown`) until you confirm the attempt. → [VM status reference](../guides/vm-status.md#an-answer-is-not-lost-to-an-edit-made-during-the-call)
- **A status write that conflicts with an edit is logged at `ERROR`.** The `VirtualMachine` controller's generic status write is not retried in place: when the object is edited while the reconcile runs, the write fails and the next reconcile converges. No state is lost.
- **A provider image re-pulled under the same tag is noticed within 10 minutes** (the capability read follows a change of the provider Deployment, and the 10-minute read catches the rest).
- **`vrtg snapshot`, `clone`, `diag`, `init`, `conformance` and `provider logs`** are still not implemented and exit non-zero naming the alternative.
- **Minor:** libvirt hosts keep the empty per-VM lock files `/tmp/virtrigaud-locks/{export,import,clone}-<domain>.lock` after the VM is gone; the redaction of staging locations also replaces every parent directory of an NFS export path, so an unrelated path in a clustered provider's error can read `<staged object>/libvirt/images/...`; two libvirt provider log lines mislead ("exists but no domain uses it; overwriting it" and "VM has a create in flight; sending an owner-checked delete to its pending host"); and every create logs `ERROR Command failed: sudo restorecon ...` on a host without SELinux, followed by a warning.

**Carried forward from v0.4.0** (checked against the v0.4.1 code): metrics are served over plain HTTP by default; clustered libvirt providers are experimental; a migrated guest can boot without network or with a new identity (R36, ADR-0014); part of a Proxmox network attachment is not applied; deleting a namespace that holds an in-use `Provider`; the Proxmox legacy name rule and the two-request owner check; the admission policy needs Kubernetes 1.30+; vSphere CPU or memory changes of a running VM need hot-add; a disk-size change alone does not trigger a `Reconfigure`; `spec.disks` is reported on libvirt and Proxmox but not attached; snapshot revert on libvirt needs a snapshot taken powered off and libvirt 9.9+; the check that a snapshot delete keeps the VM's other snapshots is not atomic with the delete; a libvirt guest on a host bridge needs the guest agent to show `status.ips`; held calls need an operator; remote host commands can outlive a cancelled call, and Proxmox `nfs` is not re-send safe; provider locks are per process (one replica per Provider); landed disks are not deleted in some cases; NFS staging cleanup leaves a 0-byte file on libvirt and vSphere targets; `verifyChecksums` does not checksum NFS migrations; and leftovers from earlier releases are not cleaned up automatically. They are described in the sections below and on the pages linked from them (for example [Security model](../guides/security-model.md), [VM status](../guides/vm-status.md), [Proxmox](../providers/proxmox.md#known-limitations-at-v042), [Migration](../migration/user-guide.md)), and in the repository's [v0.4.1 release notes](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/release-notes/next.md#known-limitations).

### Upgrading from a v0.4.1 release candidate

v0.4.1 ships the code of v0.4.1-rc3: from rc3 there is no code, CRD, RBAC or gRPC contract difference, so a `helm upgrade` to the new chart version only re-tags the images. A subsection applies if you are on that candidate or an earlier one: do every one that applies to you, oldest first. The roll order is the usual one (CRDs, manager, providers).

- **If you run rc1.** v0.4.1's CRDs differ from rc1's only in `description` texts. Later candidates changed the manager, the libvirt, Proxmox and vSphere providers and the SDK's log; **roll the manager first, then every provider**, because an rc1 provider does not carry the fixes above. Read the sections above that rc1 did not have: provider status after a roll, libvirt firmware, the create backoff (new condition messages an alert may match), clustered export answers, staging-location redaction and the SDK's request log. What differs for what rc1 already made:
    - **Proxmox VMs rc1 made keep their boot order.** The fix runs when a seed is attached, so only a VM made by v0.4.1 gets it. A VM with user-data that rc1 made can end with the seed's slot in its boot order (`order=scsi0;ide2`, `order=net0;ide2`). It is harmless: the seed is an ISO with no boot record. To clean one, set the order without the slot on the node, for example `qm set <vmid> --boot order=scsi0`. Find the VMs with `qm list` and `qm config <vmid> | grep -E '^boot:'`.
    - **Clones rc1 made, of a VM that has a seed, without inline user-data keep their seed.** The bare `#cloud-config` line is written once, at the clone, so `cloud-init status` in such a guest can keep reporting `degraded done` (exit 2) until the VM is re-made; it configures nothing and is otherwise harmless.
    - **Seed lock files rc1 left stay on the node.** `/run/virtrigaud/seed-stage/.lock-<vmid>` of a VM that no longer exists is an empty file on a tmpfs: remove it, or reboot the node.
    - **libvirt domains rc1 made keep their definitions** (a domain of a VMClass with `firmware: UEFI` is still BIOS). A secure boot VM that rc1 could not define was retried every 30 seconds and keeps its create marker; its delete can be held as `CreateOutcomeUnknown` for up to 10 minutes, or until you set the annotation its message names. A disk copy an rc1 attempt left on the pool (`<domain>-disk.qcow2`) is overwritten by the VM's next attempt when no domain uses it; if you delete the VM first, it stays until you remove it after checking that no domain uses it.
    - **A `VirtualMachine` rc1 refused is sent again once, then backs off.** **A `Provider`'s stale `reportedCapabilities` is corrected by the roll.**
    - **Logs, and the status, conditions and events of `VMMigration`s, written by rc1 keep the staging locations v0.4.1 redacts:** treat them as sensitive. A clustered libvirt `VMMigration` that rc1 held as `ExportOutcomeUnknown` is re-sent after 35 minutes as before.
- **If you run rc2.** v0.4.1 has no CRD, chart, `values.yaml` or gRPC change since rc2; it changes the manager and the Proxmox provider, so **roll the manager first, then the Proxmox providers**. A `VirtualMachine`, `VMClone` or `VMSnapshot` that an rc1 or rc2 manager already holds stays held, because those candidates lost the provider's answer to an edit made during the call: release it after you check the hypervisor (a `VirtualMachine` held as `CreateOutcomeUnknown` with no VM stamped with its UID there takes the `virtrigaud.io/create-outcome=not-created@<attempt id>` annotation its message names; this includes a Proxmox `VirtualMachine` held after a VMID race). The `CreateBackoff` message has new texts, and a VMID race the provider can show is another request's is retried, not held, also when PVE refuses the loser's request outright.
- **If you run rc3.** Nothing is needed beyond the image re-tag.

### Verifying the v0.4.1 upgrade

- Proxmox, a VM with user-data created after the upgrade: `qm config <vmid>` shows a CD-ROM (`ide2: <storage>:vm-<vmid>-disk-<N>,media=cdrom`; on a directory storage `<storage>:<vmid>/vm-<vmid>-disk-<N>.raw`), `qm config <vmid> | grep '^boot:'` does not list the seed's slot (for example `boot: order=scsi0`, not `order=scsi0;ide2`), and in the guest `cloud-init status --long` reports `done` with the `runcmd` and `write_files` of your user-data applied.
- A `VMClone` with `LinkedClone` for a Proxmox Provider fails with `LinkedCloneUnsupported`.
- libvirt: create a `VMSnapshot` whose name matches an existing overlay (for a test VM) and check it ends `Failed` with the "overlay file ... already exists" message and the file is untouched.
- libvirt, a VM of a VMClass with `securityProfile.secureBoot: true`: `virsh dumpxml <domain>` shows `<os firmware='efi'>` with a `<loader secure='yes' ...>` path that libvirt filled in, and in the guest `mokutil --sb-state` prints `SecureBoot enabled`. For `firmware: UEFI`, `virsh dumpxml <domain>` shows `<os firmware='efi'>` with the `<loader>` and `<nvram>` paths libvirt filled in.
- A `VirtualMachine` whose first `Create` the provider answered it did not perform, and that is deleted while it waits in `CreateBackoff`, is deleted without a `CreateOutcomeUnknown` hold, and its `Ready` condition message starts with `The provider answered that it did not perform the last Create sent for this VM` (or `The provider could not complete this VM's Create` for another failure).
- A `VirtualMachine` whose create is refused (for example a VMClass libvirt cannot define on the host) shows a condition message that names the next re-check and is not sent again before it:

    ```bash
    kubectl get virtualmachine <name> -n <namespace> -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}'
    # ... (non-retryable; re-checking in 4m0s, at <time>, or at once when ...)
    ```

- After each provider roll, once `kubectl -n <namespace> rollout status deployment/virtrigaud-provider-<namespace>-<provider name>` reports the rollout complete, `kubectl -n <namespace> get provider <provider name> -o jsonpath='{.status.reportedCapabilities}'` shows the new image's capabilities within about a minute (for a Proxmox provider, `supportsLinkedClones` is absent or `false`), and `.status.lastHealthCheck` is less than 10 minutes old.
- With webhooks enabled, `kubectl apply` of a test `VMClone` with `sysprep.productKey` set prints one admission warning naming the field, and once the clone starts the `VMClone` has one `CustomizationSecretNotSent` event; neither shows the value.

### Rolling back from v0.4.1

The CRDs have no schema change, so a v0.4.0 manager reads the same objects. The v0.4.0 Proxmox provider knows nothing about a seed: a VM with a seed keeps working under it, but do not clone a VM that has a seed with a v0.4.0 provider (see [Proxmox: user-data needs the SSH data plane](#proxmox-user-data-needs-the-ssh-data-plane)). The rollback caveats of v0.4.0 below still apply.

---

## Upgrading from v0.3.11 to v0.4.0

!!! tip "Going straight from v0.3.11 to v0.4.1"
    You do not have to stop at v0.4.0. Use `--version 0.4.1` and the `v0.4.1` image tags
    where the commands below say `0.4.0` and `v0.4.0`, follow this section, and then do the
    actions of [Upgrading from v0.4.0 to v0.4.1](#upgrading-from-v040-to-v041) (Proxmox SSH
    credentials, the libvirt `firmware: UEFI` check, rotating `VMClone` secrets). The
    commands are shown for v0.4.0, the release this section describes.

v0.4.0 is built from the same code as the release candidate v0.4.0-rc9. The chart
version is `0.4.0` and every image tag is `v0.4.0`
(`ghcr.io/projectbeskar/virtrigaud/manager:v0.4.0`,
`.../provider-vsphere:v0.4.0`, `.../provider-libvirt:v0.4.0`,
`.../provider-proxmox:v0.4.0`). Releases older than v0.3.11 should first follow
the [older-version notes](#older-versions) below.

What is new in this window, in one paragraph: clustered libvirt providers
(experimental; `Provider.spec.topology: cluster`, the new `Host` and `HostPool`
CRDs, and the scheduler that uses `VMPlacementPolicy`), VM ownership stamps and fail-closed ownership checks on
every provider, consumer grants for shared `Provider`/`VMClass`/`VMImage`, an
admission policy for manager-owned keys, identity-safe image preparation
(ADR-0009), a `Provider` in-use finalizer (ADR-0010), migration staging cleanup
(ADR-0011), snapshot revert through `spec.snapshot.revertToRef`, Proxmox network
and cloud-init-drive handling, and private libvirt cloud-init seeds. If you do not
use clustered providers, the new CRDs are installed but unused. Clustered
provider users should also read [Backup, restore and re-attach](../guides/clustered/backup-restore.md):
a restore of `VirtualMachine`s is guarded in v0.4.0 and some restores now hold VMs
until you decide.

### Pre-flight checks

Run these **before** changing anything. They are read-only.

**1. Back up the custom resources.**

```bash
kubectl get providers,vmclasses,vmimages,vmnetworkattachments,virtualmachines,vmsnapshots,vmclones,vmmigrations,vmsets \
  -A -o yaml > virtrigaud-backup-v0.3.11.yaml
```

**2. Find cross-namespace references** (each line names an object that needs
`spec.consumerNamespaceSelector` after the CRDs are applied):

```bash
# VirtualMachines referencing another namespace's Provider, VMClass or VMImage.
kubectl get virtualmachines -A -o json | jq -r '
  .items[] | . as $vm
  | [["Provider", .spec.providerRef], ["VMClass", .spec.classRef], ["VMImage", .spec.imageRef]][]
  | select(.[1] != null and (.[1].namespace // "") != "" and .[1].namespace != $vm.metadata.namespace)
  | "\(.[0]) \(.[1].namespace)/\(.[1].name) <- \($vm.metadata.namespace)"' | sort -u

# VMMigrations whose target Provider is in another namespace.
kubectl get vmmigrations -A -o json | jq -r '
  .items[] | select((.spec.target.providerRef.namespace // "") != ""
    and .spec.target.providerRef.namespace != .metadata.namespace)
  | "Provider \(.spec.target.providerRef.namespace)/\(.spec.target.providerRef.name) <- \(.metadata.namespace)"' | sort -u
```

**3. Find cross-namespace clone and migration targets** (each target namespace
needs the grant annotation):

```bash
kubectl get vmclones,vmmigrations -A -o json | jq -r '
  .items[] | select(.spec.target.namespace != null
    and .spec.target.namespace != "" and .spec.target.namespace != .metadata.namespace)
  | "\(.kind) \(.metadata.namespace)/\(.metadata.name) -> \(.spec.target.namespace)"'
```

**4. Find VMs that will be reverted or resized on the first reconcile.**

```bash
# spec.snapshot.revertToRef was accepted and ignored before; it now reverts the VM.
# Use the full resource name: "vm" can resolve to another project's VirtualMachine.
kubectl get virtualmachines.infra.virtrigaud.io -A \
  -o jsonpath='{range .items[?(@.spec.snapshot.revertToRef)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'

# spec.resources overrides were never sent to the provider; they are now.
kubectl get virtualmachines.infra.virtrigaud.io -A -o json | jq -r '
  .items[] | select(.spec.resources != null)
  | "\(.metadata.namespace)/\(.metadata.name): \(.spec.resources)"'
```

Also check `VMSet` templates (`spec.template.spec.snapshot.revertToRef`): the VMs a
`VMSet` creates carry the field.

**5. Let in-flight migrations finish.** List them with
`kubectl get vmmigrations -A` and do not start new ones. A migration in `Creating`
or `Validating-Target` during the upgrade fails with `TargetVMNotOwned`; vSphere
and Proxmox migrations whose disk was landed or staged by the old provider before
their target VM was created are refused afterwards. See
[In-flight VMMigrations](#in-flight-vmmigrations).

**6. Provider-specific checks.**

- **libvirt:** run `virsh pool-dumpxml default | grep '<path>'` on every host;
  the `default` pool must be at `/var/lib/libvirt/images`. Before deleting any
  *pre-upgrade* VM run `virsh domblklist --details <domain>` on every domain of
  the host and look for a disk file shared between domains.
- **Proxmox:** list `VMImage`s that import from a URL; Proxmox no longer imports
  them (see [Proxmox](#proxmox)):

  ```bash
  kubectl get vmimages -A -o json | jq -r '.items[]
    | select(.spec.source.http != null and .spec.source.proxmox == null)
    | "\(.metadata.namespace)/\(.metadata.name)"'
  ```
- **vSphere:** list each `VirtualMachine`'s `status.id` and compare it with the
  templates in vCenter, so no `VirtualMachine` is bound to a template (see
  [vSphere](#vsphere)):

  ```bash
  kubectl get virtualmachine -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,PROVIDER:.spec.providerRef.name,ID:.status.id
  govc find -i / -type m -config.template true | sed 's/^VirtualMachine://'
  ```

### Required upgrade order

The order is **hosts and accounts, CRDs, grants, manager, providers**. The
manager and the CRDs depend on each other, and so do the manager and the
providers. Roll the providers promptly after the manager.

1. **Prepare hosts and hypervisor accounts** (safe to do ahead of time; the old
   release ignores them):
   - **Every libvirt host:** create the cloud-init seed directory, and grant the
     `VR_DISK_READ` sudo rule if the provider's SSH user cannot read libvirt's
     `0600` snapshot overlays. A v0.4.0 libvirt provider fails every create on a
     host without the seed directory.

     ```bash
     install -d -m 0711 -o <ssh user> -g <ssh user> /var/lib/libvirt/virtrigaud-seeds
     ```

     Details: [Libvirt host preparation](libvirt-host-prepare.md).
   - **vSphere:** grant the provider's vCenter account the privileges in
     [New required privileges and configuration](#new-required-privileges-and-configuration)
     (`VirtualMachine.Config.AdvancedConfig`, `System.Read`).
   - **Proxmox:** grant the PVE API token `VM.Config.Network`,
     `VM.Config.Cloudinit` and `SDN.Use` before you roll the Proxmox provider.

2. **Apply the CRDs.** Helm does not upgrade the `crds/` directory of a chart,
   and the chart's pre-upgrade hook applies them in the *same* `helm upgrade` that
   rolls the manager, leaving no pause for step 3. Apply them yourself first, with
   server-side apply exactly as the hook does (`--force-conflicts` takes over
   fields from earlier client-side applies):

   ```bash
   helm repo update
   helm pull virtrigaud/virtrigaud --version 0.4.0 --untar
   kubectl apply --server-side --force-conflicts -f virtrigaud/crds/
   ```

   Two new CRDs are created (`Host` and `HostPool`; `VMPlacementPolicy` already
   existed in v0.3.11) and the existing ones change. The new manager reads the installed `VirtualMachine`,
   `Provider`, `VMClass`, `VMImage` and `VMSnapshot` CRDs and **fails readiness**
   if they lack the new fields (it does not crash and does not stop managing
   existing VMs, but `helm upgrade --wait` times out and the rolling update does
   not proceed past the old pod). See the
   [Helm CRD upgrade guide](../getting-started/helm-crd-upgrades.md) for the
   hook and `crdUpgrade` values.

   !!! note "Two schema changes the readiness check does not verify"
       `VirtualMachine` `status.snapshotRevert` (without it a revert is never
       sent: `SnapshotReverted=False/Unsupported`) and the `VMMigration` fields
       used by migration into a clustered Provider. Always apply the **full** CRD
       set, not a subset. An older chart's CRDs applied over newer ones prune
       fields: only apply CRDs from the chart you are upgrading to.

3. **Grant consumers and remove stale requests**, before the new manager runs
   (the old manager ignores all of this, so it changes nothing until then):
   - Set `spec.consumerNamespaceSelector` on every `Provider`, `VMClass` and
     `VMImage` that other namespaces use. The field exists only after step 2.
     `{}` shares with every namespace; a label selector (for example
     `kubernetes.io/metadata.name`) names the namespaces:

     ```yaml
     spec:
       consumerNamespaceSelector:
         matchLabels:
           kubernetes.io/metadata.name: team-a
     ```

     Without this, the affected VMs stop being managed
     (`Ready=False`, reason `ConsumerNotAllowed`; nothing is deleted) as soon as
     the new manager starts.
   - Annotate every target namespace of a cross-namespace `VMClone` or
     `VMMigration`:

     ```bash
     kubectl annotate namespace <target> \
       infra.virtrigaud.io/allowed-source-namespaces=<source-ns>[,<source-ns2>...]
     ```

     The value is a comma-separated list of exact names; `*` is not a wildcard.
   - Remove `spec.snapshot.revertToRef` from every VM (and `VMSet` template) you do
     **not** want reverted (see [Stale `revertToRef`](#stale-reverttoref-on-existing-vms)).
   - Decide about `spec.resources` overrides (see
     [`spec.resources` overrides](#specresources-overrides-now-resize-vms)).

4. **Upgrade the manager with Helm.**

   ```bash
   helm upgrade virtrigaud virtrigaud/virtrigaud \
     --namespace virtrigaud-system \
     --version 0.4.0 \
     --reset-then-reuse-values \
     --wait --timeout 10m
   ```

   Use `--reset-then-reuse-values` (Helm 3.14 or later) when you carry custom
   values, **not** `--reuse-values`: `--reuse-values` keeps the *old* chart's
   defaults, including the manager image tag (the manager would stay on
   v0.3.11), and was the cause of the NetworkPolicy default problem described in
   [Chart values](#chart-values-that-changed). With Helm older than 3.14 use
   `--reset-values -f your-values.yaml`. Wait until the manager Deployment is
   Ready and the CRD check passes (see
   [Post-upgrade verification](#post-upgrade-verification-checklist)) before
   touching the providers. The manager's ClusterRole changes with the chart (see
   [Manager RBAC](#manager-rbac)); a kustomize install must reapply
   `config/rbac/role.yaml`.

   !!! note "The manager upgrade restarts every provider pod once"
       The new manager changes the provider pod template (a `sizeLimit` on `/tmp`,
       migration-PVC mounts), so every manager-run provider pod is replaced once
       when the manager rolls, with its *old* image. A clustered libvirt or a
       vSphere provider (`Recreate` strategy) is briefly down. Schedule the
       upgrade between migrations and outside provider-heavy windows.

5. **Upgrade the providers.** A `Provider` names its image in
   `spec.runtime.image`, which the chart does not change: set it on every
   `Provider` to the `v0.4.0` image of its type.

   ```bash
   kubectl patch provider <name> -n <namespace> --type merge -p \
     '{"spec":{"runtime":{"image":"ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.0"}}}'
   ```

   Do this promptly after the manager: until a provider reports
   `supportsImageArtifactIdentity` the new manager sends it no image prepare, so
   creates of import-style images through it wait (`ProviderLacksArtifactIdentity`;
   existing VMs and reference-style images are unaffected). Per-type order
   constraints:

   - **libvirt: never roll the provider ahead of the manager.** A v0.4.0 libvirt
     provider expects `CreateRequest.owner` and `ImportDiskRequest.target_vm` from
     the manager; with an older manager every libvirt-target `VMMigration` fails.
   - **libvirt: seed directory first** (step 1): a provider image that runs before
     it exists fails every create.
   - **Proxmox: never roll the provider ahead of the manager.** An older manager
     sends neither the verification flag nor `target_vm`, so every
     Proxmox-target migration is refused.
   - **vSphere:** grant the vCenter privileges first (step 1). Without
     `VirtualMachine.Config.AdvancedConfig` every `Create` and `Clone` starts
     failing the moment the new image is live.
   - **Clustered libvirt:** roll the provider right after the manager (new
     clustered VMs wait with `ProviderLacksListOwnerFilter`, and resizes with
     `ProviderLacksHonestReconfigure`, until it is upgraded), and **before you run
     a migration into it** (an older one is refused as a target,
     `ClusteredTargetUnsupported`).
   - Set new provider environment variables (for example
     `VIRTRIGAUD_LIBVIRT_IMAGE_DIRS`, `VIRTRIGAUD_VSPHERE_IMAGE_PROXY`) in the same
     patch, through `spec.runtime.env`, so the pod restarts once.

6. **Verify** with the [checklist](#post-upgrade-verification-checklist), then
   clean up [leftovers](#leftovers-from-earlier-releases).

### Breaking changes

The [Upgrade impact](../guides/security-model.md#upgrade-impact) table in the Security Model guide lists the security-related changes from the tenant's side, with what each looks like after the upgrade.

Rows are grouped by area. "Action" is what you must do; the
[repository guide](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/upgrading.md#breaking-changes)
carries the full cause and the edge cases of each row.

#### Access control and API

| Change | Who is affected | Action |
|--------|-----------------|--------|
| **Cross-namespace `Provider`, `VMClass`, `VMImage` references need a grant** ([reference](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/cross-namespace-references.md)) | Anyone whose VMs, clones or migrations use a shared object from another namespace, for example a `Provider` in `virtrigaud-system`. They fail closed (`Ready=False`, `ConsumerNotAllowed`), including running VMs: no provider calls, no deletes. | Set `spec.consumerNamespaceSelector` on every shared object after the CRDs and before the manager (step 3). Unset means "own namespace only"; `{}` means all namespaces. To delete a VM whose Provider is refused, use `virtrigaud.io/orphan-on-delete: "true"` or `force-delete`. |
| **`VirtualMachine.spec.providerRef` is immutable once bound** (CRD CEL rule; bound = `status.id` or `status.placement.pendingHost` set) ([reference](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-provider-binding.md)) | Tooling that edits `providerRef` after creation, and the old "re-point to a missing Provider, then delete" trick to stop managing a VM. Edits get `422 Invalid`. | Detach with the annotation `virtrigaud.io/orphan-on-delete: "true"` and delete the `VirtualMachine`: the hypervisor VM is left alone. See [orphan-on-delete](#detaching-a-vm-orphan-on-delete). Upgrade the CRDs with or before the manager. |
| **Cross-namespace `VMClone` / `VMMigration` targets need a grant** ([reference](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/cross-namespace-targets.md)) | Anyone whose `spec.target.namespace` differs from the object's namespace. The object waits with `TargetNamespaceNotAllowed`. | Annotate the target namespace `infra.virtrigaud.io/allowed-source-namespaces=<source-ns>[,...]` (step 3). The pinned `Provider` and `VMClass` must also select the target namespace. A `VMMigration` whose `spec.source.providerRef` names a Provider other than the source VM's Provider now fails; remove the field or fix it. |
| **`Provider.spec.type` is immutable** (CRD rule and validating webhook); `spec.topology` too | Tooling that edits `spec.type` in place. | Create a new `Provider` of the other type. Upgrade the CRDs with or before the manager. |
| **Only the manager may set manager-owned `virtrigaud.io` keys on a `VirtualMachine`** (ValidatingAdmissionPolicy, Kubernetes 1.30 or later) ([reference](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/admission-policy.md)) | Anything that creates or changes migration, clone or adoption markers (`virtrigaud.io/migration`, `migration-claim`, `migrated-from`, `imported-disk-id`, `clone`, `clone-uid`, `cloned-from`, `adopted-host`, `adopted-id`, the label `virtrigaud.io/adopted`, ...) under another identity: backup/restore tools such as Velero, a second VirtRigaud installation in the same cluster. | Add such identities to `admissionPolicy.reservedKeys.exemptUsernames` / `exemptGroups` before you rely on them. To opt out set `admissionPolicy.reservedKeys.enabled: false`. The installing identity needs create/update/delete on `validatingadmissionpolicies` and `validatingadmissionpolicybindings`. Below Kubernetes 1.30 nothing is rendered: restrict who can create `VirtualMachine`s. |
| **Deleting a `Provider` that is still in use waits** (finalizer `provider.infra.virtrigaud.io/in-use`, [ADR-0010](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/adr/0010-provider-in-use-finalizer.md)) | Every `Provider`. It stays `Terminating` (`DeleteBlocked=True/ProviderInUse`) while any VM, snapshot, in-flight clone or migration needs it; its runtime is kept until the last goes. | Delete VMs (and wait) **before** their `Provider` or its namespace. Release a held Provider at once with `virtrigaud.io/force-delete: "true"` (its VMs are then left unmanaged). Uninstall order: VMs and Providers first, then the manager. |
| **Deleting a `VirtualMachine` while its `Provider` is unreachable waits** | Every VM with a provider id. Before, the finalizer was released without any provider `Delete` and the hypervisor VM kept running unmanaged. Now the VM stays `Terminating` (`ProviderUnavailable`, backoff 15 s to 5 min) during every provider rollout or outage. | Expect `Terminating` during provider rollouts; automation that waits for deletion needs a longer timeout. Detach on purpose with `orphan-on-delete`, or drop the finalizer with `force-delete` (logged, `VMLeftOnHypervisor` event). |
| **Adoption is stricter** | Single-host adoption (`virtrigaud.io/adopt-vms`): a VM whose owner stamp names no `VirtualMachine` in this cluster, whose stamp cannot be read, or that is a template or prepared image is no longer adopted. | To re-adopt a VM left by `orphan-on-delete`, annotate the single-host Provider `virtrigaud.io/adopt-stamped-vms: "true"` while no other VirtRigaud installation manages the same vCenter or host, and remove it afterwards. |

#### vSphere

| Change | Who is affected | Action |
|--------|-----------------|--------|
| **Create and Clone fail closed on VM ownership** ([reference](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-ownership.md)) | All vSphere users. | Grant `VirtualMachine.Config.AdvancedConfig` ([privileges](#new-required-privileges-and-configuration)). Rename any VirtualMachine, VMImage prepare target or bare template name matching `vm-<digits>`. Make every `VMImage.templateName` name a real vSphere template, not a regular VM. |
| **Per-VM operations refuse templates and prepared images** | A `VirtualMachine` bound to a vSphere template (for example adopted from one). `Delete`, `Power`, `Reconfigure`, `HardwareUpgrade` and the snapshot calls are refused (`VM_IS_IMAGE_ARTIFACT`); a refused delete stays `Terminating`. | Before upgrading, find VMs whose `status.id` is a template (pre-flight 6). Detach each with `virtrigaud.io/orphan-on-delete: "true"`, then delete it. Never delete it plainly: that destroyed the template. |
| **An imported disk is attached in place only when it is the VM's own verified migration disk; landing names carry the namespace** | Anyone who sets `spec.importedDisk` on vSphere by hand, and any vSphere migration in flight. Landing path is now `[<datastore>] <namespace>_<vm>-migrated/<namespace>_<vm>-migrated.vmdk`. | Finish or redo in-flight vSphere migrations around the upgrade (see [In-flight VMMigrations](#in-flight-vmmigrations)). Grant `System.Read` on the vCenter root folder. Remove old `[<datastore>] <vm>-migrated` folders by hand once unused. Run one replica of each vSphere provider. |
| **vSphere provider runs one replica with the `Recreate` strategy** | Every vSphere `Provider`. `spec.runtime.replicas` above 1 is ignored; the provider is briefly unavailable on every rollout. The chart's opt-in vSphere Deployment fails to render with `providers.vsphere.replicaCount` above 1. | Drop `replicas` above 1; schedule rollouts accordingly. |
| **Create leaves the VM powered off; the controller powers it on** | Everyone creating vSphere VMs: a VM shows `status.powerState: Off` for one reconcile. A migrated VM smaller than its VMClass `diskDefaults.size` (default `40Gi`) is now grown to it (grow only). | Set the VMClass `diskDefaults.size` of migration targets to the source disk size (or less) to keep a migrated disk's size; make sure the datastore has room. |
| **Image source rules** (identity-safe prepare, [ADR-0009](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/adr/0009-prepared-image-artifact-identity.md)) | `ovaURL` images: templates are named `<namespace>.<name>_<16 hex>` and stamped, kept in the Provider's import folder. Bare `.ovf` sources are refused; OVF file references must be root-level OVA members; sources at loopback or link-local addresses, more than 3 redirects and `https` to `http` redirects are refused; downloads ignore `HTTP_PROXY`/`HTTPS_PROXY` (opt in with `VIRTRIGAUD_VSPHERE_IMAGE_PROXY`); at most `VIRTRIGAUD_VSPHERE_IMAGE_MAX_DOWNLOAD_GIB` (default 256). | Republish bare `.ovf` images as `.ova`. Check `defaults.folder` resolves to exactly one VM folder per Provider. Expect one re-import per image and folder. Set the proxy variable through `spec.runtime.env` before rolling if image servers are reachable only through a proxy. |
| **`Reconfigure` no longer resizes the root disk; a change a running VM cannot take waits for a power-off** ([reference](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/reconfigure-results.md)) | VMs with `spec.disks` whose CPU or memory changes; running VMs changed without hot-add. The refusal is shown as `Reconfiguring=False/ResizePendingPowerOff` instead of retried `ProviderError`. | To apply the change set `spec.powerState: Off`, then `On`, or enable hot-add while the VM is off. Alerts on `Reconfiguring` should treat `ResizePendingPowerOff` as action-needed. |

#### libvirt

| Change | Who is affected | Action |
|--------|-----------------|--------|
| **Default cloud-init provisions no credentials** | A VM created **without** `spec.userData`: no `ubuntu` user, SSH key, password or sudo grant any more. | Always supply `spec.userData` with your own user and key. VMs already created keep the old hardcoded key and sudo grant *inside the guest*; remove it by hand if you want it gone. Rolling the provider does not touch running VMs. |
| **Seeds are built private in a seed directory that must exist on every host** | Every libvirt Provider, single-host and clustered. | `install -d -m 0711 -o <ssh user> -g <ssh user> /var/lib/libvirt/virtrigaud-seeds` on every host **before** rolling the libvirt provider ([details](libvirt-host-prepare.md#cloud-init-seed-directory)). Include migration target hosts and every host of a clustered Provider. |
| **Base images are confined to the allowed image directories and always copied** | Images outside `/var/lib/libvirt/images`, in a subdirectory, or in a non-default pool; images an earlier release attached in place. | Set `VIRTRIGAUD_LIBVIRT_IMAGE_DIRS` (comma- or colon-separated) in `Provider.spec.runtime.env` ([details](libvirt-host-prepare.md#image-directories)). An image attached in place by an earlier release is refused as a base: create a `VMImage` under a **new name**. Before deleting any pre-upgrade VM, check `virsh domblklist --details` for shared disks. |
| **`LinkedClone` is refused; use `FullClone`** | `VMClone` with `options.type: LinkedClone` through libvirt fails (`LinkedCloneUnsupported`). A full clone needs a powered-off source (it waits, `SourceMustBePoweredOff`). | Use `FullClone`. Existing linked clones keep working; their source VM cannot be deleted, reverted or snapshotted while they exist: keep those sources powered off. |
| **Delete only removes a VM's own files and is blocked while others use its disk** | Every libvirt VM. `Ready=False/DeleteBlocked` while another domain (a linked clone, a shared disk) uses a disk; a `VMSnapshot` whose provider delete fails keeps its finalizer. New disks are `0640 libvirt-qemu:kvm` (was `0777`). | The SSH user must be `root`, in `kvm`, or allowed passwordless `sudo -n qemu-img info` ([sudo rules](libvirt-host-prepare.md#sudo-rules-for-disk-reads-and-copies)), or the checks fail (retried). Delete a source VM's linked clones first. `virtrigaud.io/force-delete: "true"` releases a stuck `VMSnapshot`. Roll the manager with the libvirt provider. |
| **The `default` storage pool is never rewritten** | A host whose `default` pool is not at `/var/lib/libvirt/images`. v0.3.11 destroyed and recreated it there; now creates fail with `InvalidSpec`. | Mount the storage **at** `/var/lib/libvirt/images` (or point the pool back at the local directory) before upgrading. |
| **New domains are named `<namespace>.<name>`** | Tooling that assumes "domain name equals VirtualMachine name". Existing VMs keep their name; everything addresses a VM by `status.id`. | Read `status.id`. Upgrade the manager **before** the libvirt provider. A create that collides with a domain it does not own fails with `ProviderConflict`: adopt it or rename. |
| **Libvirt `Reconfigure` and power state are honest** | A change the domain did not take is reported (`restart_required`), not silently applied; `status.powerState` can be `Suspended` or `Unknown`. | Roll the libvirt providers and the manager together, CRDs first. Do not downgrade the `VirtualMachine` CRD while any VM is `Suspended` or `Unknown`. |
| **Snapshot rules** ([revert](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-snapshot-revert.md), [libvirt clones](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/libvirt-clones.md)) | A snapshot of a powered-off VM is taken with the cloud-init CD-ROM ejected; a revert to a snapshot that stored the CD-ROM is refused; a disk-only snapshot is not deleted while a memory snapshot is stored in its overlay. | Take new snapshots, with the VM powered off, of VMs you want to revert to. Delete the memory snapshot before the disk-only one. |
| **Clone identity** | A clone boots as a new cloud-init instance (new instance-id, new SSH host keys) and gets its own seed. A clone carries its source's user-data unless the `VMClone` gives its own. | Review who may create `VMClone`s. |

#### Proxmox

| Change | Who is affected | Action |
|--------|-----------------|--------|
| **An imported disk is imported only when it is the VM's own verified migration stage; stages are named per namespace** | Anyone who sets `spec.importedDisk` on Proxmox by hand, cross-namespace migrations into Proxmox (now `ProxmoxCrossNamespaceTarget` at `Validating`), and Proxmox-target migrations in flight. Stages live in `/var/lib/virtrigaud/import-stage/` (created `0700`; keep it root-only). | Upgrade the manager before the Proxmox provider. Finish or redo in-flight Proxmox-target migrations. Re-create a granted cross-namespace migration in the target VM's own namespace. Remove leftover `/var/tmp/.virtrigaud-import-*` files by hand. Run one VirtRigaud installation per PVE node. |
| **URL image import (`source.http`) is refused** | `VMImage`s with `source.http` used by Proxmox VMs: `Ready=False/InvalidSource`, new VMs not created. It never produced a usable template. | Prepare a template on PVE (`qm importdisk` + `qm template`) and point the `VMImage` at it with `source.proxmox.templateID`. |
| **A VM gets the bridge, VLAN, model and static IP its networks name** ([reference](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/proxmox-networks.md)) | Proxmox VMs used `virtio` on `vmbr0` with no static IP whatever the spec said. An `ipAddress` without `prefix` and a non-IP `dns` entry are now refused on create. The manager sends only the target Provider's `proxmox` block of a `VMNetworkAttachment`. | Grant the PVE token `VM.Config.Network`, `VM.Config.Cloudinit` and `SDN.Use` ([privileges](#new-required-privileges-and-configuration)). Review each `VMNetworkAttachment` a Proxmox VM uses. Roll the manager and the Proxmox provider together. |
| **`Reconfigure` no longer resizes the root disk** | Anyone who grew a Proxmox root disk through a `spec.disks` entry (for example one named `root`). Nothing replaces it in this release. | Grow the disk in PVE. |
| **The cloud-init drive goes on the VM's own storage** | Proxmox VMs whose clones have no storage-backed disk. | Optionally set `PVE_DEFAULT_STORAGE` (or `PROVIDER_DEFAULT_STORAGE`) on the Provider ([reference](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/proxmox-cloud-init-storage.md)). |

#### Clones, migrations and controller behaviour

| Change | Who is affected | Action |
|--------|-----------------|--------|
| **`spec.resources` overrides are now sent to the provider** | Any VM with `spec.resources.cpu` or `memoryMiB`. The override was only recorded in `status.currentResources` and never applied; on the first reconcile after the upgrade the VM is resized to it. | See [`spec.resources` overrides](#specresources-overrides-now-resize-vms). |
| **`spec.snapshot.revertToRef` now reverts the VM** (it was a silent no-op) | Any VM carrying the field. | See [Stale `revertToRef`](#stale-reverttoref-on-existing-vms). |
| **`powerOn` is honoured** (`VMClone` `spec.options.powerOn`, `VMMigration` `spec.target.powerOn`) | Clones and migrated VMs that do not set `powerOn: true` stay powered off; before, they always came up running. `deleteAfterMigration: true` with `powerOn: false` leaves the workload running nowhere. | Set `powerOn: true` where the new VM must run. Set `spec.target.powerOn: true` on every migration that also sets `spec.source.deleteAfterMigration: true`. |
| **NFS migrations refuse `nfs.uid: 0` and `nfs.gid: 0`** (reason `NFSRootIdentityNotAllowed`, every provider type) | Migrations that set either to `0`. | Use a dedicated non-zero uid/gid that owns the export, or leave them unset; re-create the migration. |
| **A `VMMigration` acts only on the target VM it created** (`TargetVMNotOwned`) | A target name already taken by a VM the migration did not create, and migrations in `Creating`/`Validating-Target` during the upgrade. | Let migrations finish before upgrading; afterwards free the name or pick another `spec.target.name` and re-create the migration. |
| **Staged and landed migration disks are deleted** ([ADR-0011](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/adr/0011-migration-staging-cleanup.md)) | Every `nfs`/`s3` migration: the staged copy is deleted when the migration is `Ready` or deleted; a failed or deleted migration deletes the disk its import landed. Deleting such a `VMMigration` waits for it. NFS staging names changed to `vmmigrations_<namespace>_<name>_export.qcow2`. | Roll the providers with the manager. S3 credentials need `s3:GetObject` and `s3:DeleteObject` on the `vmmigrations/` prefix. Add a lifecycle rule for noncurrent versions on versioned buckets. Use `cleanupPolicy: Never` to keep a disk. Remove objects staged by earlier migrations yourself ([leftovers](#leftovers-from-earlier-releases)). |
| **`status.ips` lists routable addresses only** | Anything that parses `status.ips`: loopback, link-local and unreachable addresses are gone. On libvirt, a NAT guest shows its DHCP lease; a bridged guest needs the QEMU guest agent. | Update parsers; install `qemu-guest-agent` in guests ([reference](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-status-ips.md)). |
| **A provider call whose outcome is unknown is held, not re-sent** ([reference](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/provider-call-outcomes.md)) | Create, Clone, snapshot, export and import after a lost answer: shown as `Provisioning=True/CreateRequested` or held `Ready=False` for an operator instead of repeated blindly. | Roll all providers with the manager so they report the new capabilities; otherwise the manager takes the conservative path. |
| **`VMImage` prepare state is keyed by `<namespace>/<name>`** | `status.providerStatus` and `status.availableOn` use the Provider's namespaced name; each entry records the Provider UID and a source digest; one extra `ImagePrepare` per image and Provider on the first create. | Upgrade the `VMImage` CRD before the manager. Update scripts that read these fields. Under `onMissing: Fail`/`Wait` switch to `Import` to re-validate old entries. Never write `vmimages/status` by hand. |
| **Clustered providers (experimental)** | Only `topology: cluster` Providers: placement against committed capacity, frozen size while pending, host-unreachable and restore holds, cross-host `ListVMs`. | See the [clustered libvirt guide](../guides/clustered/index.md). Nothing on v0.3.11 is affected. |

#### Orphan-on-delete and force-delete

Two user-set annotations (not reserved by the admission policy) detach or release
objects without calling the provider:

- `virtrigaud.io/orphan-on-delete: "true"` on a `VirtualMachine`, then delete the
  object: the finalizer is released with **no provider call** and the hypervisor
  VM and its disks are left for you. This is the supported way to stop managing a
  VM, replacing the old trick of re-pointing `providerRef`. On a clustered
  Provider, a VM in *another* namespace than its Provider needs the Provider's
  permission (`Ready=False/OrphanOnDeleteNotAllowed` otherwise).
- `virtrigaud.io/force-delete: "true"` on a `VirtualMachine`, `VMSnapshot`,
  `VMMigration` or `Provider` drops a held finalizer (logged, with a Warning
  event). It can leave a hypervisor VM, snapshot or staged disk behind.

#### Detaching a VM (orphan-on-delete)

```bash
kubectl annotate virtualmachine <name> -n <namespace> virtrigaud.io/orphan-on-delete=true
kubectl delete virtualmachine <name> -n <namespace>
```

### New required privileges and configuration

**vSphere**

- `VirtualMachine.Config.AdvancedConfig` ("Virtual machine > Change Configuration
  > Advanced configuration") on the target VM folder and resource pool, and on the
  VMs that single-host adoption takes over (the owner stamp is written on
  adoption). Without it every `Create` and `Clone` fails.
- `System.Read` (read-only) on the vCenter **root folder, propagated**, with no
  narrower "No access" permission below it for this account. Before attaching a
  migrated disk, reusing or deleting a migration landing folder, or deleting a
  VM with a disk outside its own directory, the provider checks that no other VM
  uses the disk; vCenter silently hides VMs the account may not see, so the
  provider first verifies the privilege and fails closed otherwise
  (`VM_DISK_CHECK_FAILED`, retried).
- Optional `VIRTRIGAUD_VSPHERE_IMAGE_PROXY` and
  `VIRTRIGAUD_VSPHERE_IMAGE_MAX_DOWNLOAD_GIB` in `Provider.spec.runtime.env`.

**Proxmox**

- For a token that is not root or `Administrator`: `VM.Config.Network` (to set a
  `netN`), `VM.Config.Cloudinit` (to set `ipconfigN` and `nameserver`) and
  `SDN.Use` on `/sdn/zones/<zone>/<bridge>` (and `/<tag>` for a VLAN) for every
  bridge a VM is put on (a plain Linux bridge such as `vmbr0` is in the
  `localnetwork` zone). A narrowly scoped token that worked before can get a 403
  while the provider configures a clone, and the clone is rolled back. Treat
  these ACLs as the control over which bridges and VLANs tenants can reach.
  Details: [Proxmox networks](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/proxmox-networks.md#permissions-of-the-pve-token).
- The migration SSH data plane stages disks in `/var/lib/virtrigaud/import-stage/`
  on the node; the provider creates it `0700` and refuses an import if it is not
  a root-owned `0700` directory.

**libvirt** (full list in [Libvirt host preparation](libvirt-host-prepare.md))

- The seed directory on every host (`VIRTRIGAUD_LIBVIRT_SEED_DIR`, default
  `/var/lib/libvirt/virtrigaud-seeds`).
- `VIRTRIGAUD_LIBVIRT_IMAGE_DIRS` when images are outside
  `/var/lib/libvirt/images`.
- The SSH user in `kvm` (or `root`), a POSIX login shell, and the `VR_DISK_READ`
  sudo rule (sudo 1.9.10 or later) to read libvirt's `0600` snapshot overlays.
  Replace the `qemu-img info -U *` wildcard an earlier release documented: it let
  the account read any file's header as root. Never allow `qemu-img *`.
- QEMU with the CVE-2024-4467 fix before you allow `qemu-img` in sudoers.
- The pool directory writable only by `root` and the SSH user (or sticky), or
  full clones and S3/NFS exports are refused.

**Installer**

- Create/update/delete on cluster-scoped `validatingadmissionpolicies` and
  `validatingadmissionpolicybindings` (`admissionregistration.k8s.io`) for the
  reserved-keys policy (Kubernetes 1.30 or later).

#### Manager RBAC

The chart applies these with the manager. A kustomize or hand-rolled install must
reconcile `config/rbac/role.yaml`. New since v0.3.11 (from the chart's manager
ClusterRole):

- the `hosts`, `hosts/status`, `hosts/finalizers`, `hostpools`, `hostpools/status`
  and `vmplacementpolicies` resources of `infra.virtrigaud.io`;
- `get` on the `virtualmachines`, `providers`, `vmclasses`, `vmimages` and
  `vmsnapshots` CustomResourceDefinitions (the readiness check and the consumer
  grant);
- `get`, `list`, `watch` on `namespaces`, and `get` on `storageclasses`;
- `serviceaccounts` create/update/delete (a token-less ServiceAccount per Provider
  runtime);
- **`create` and `update` on `secrets`** (it was read-only): for a clustered
  Provider the manager writes one Secret it owns per Provider,
  `<provider>-hosts`, holding the host inventory and the SSH credentials of the
  hosts. RBAC cannot scope `create` to one name. The manager never deletes
  Secrets, and provider pods have no Secret access. If you add custom rules, note
  that this widens what a compromised manager can do.

### Chart values that changed

| Value | Change |
|-------|--------|
| `security.networkPolicies.*` | **Removed and ignored.** v0.3.11 shipped `enabled: true` but no template used it. Use `networkPolicy.enabled` (below). |
| `networkPolicy.enabled` and the rest of `networkPolicy.*` | **New, default `false`.** Opt-in namespaced NetworkPolicies for the manager and provider pods. Needs a CNI that enforces NetworkPolicy and deployment-specific tuning (monitoring namespace, DNS selectors and `dnsEgressCIDRs`, `providerGRPCPort`, `apiServerCIDRs`, `hypervisorEgressCIDRs`); read the chart README first. Enabling it on a release upgraded with `--reuse-values` fails the render and asks for `--reset-then-reuse-values`. |
| `admissionPolicy.reservedKeys.enabled` (default `true`), `exemptUsernames`, `exemptGroups` | **New.** The ValidatingAdmissionPolicy for manager-owned keys (rendered on Kubernetes 1.30 or later only). |
| `manager.tmpSizeLimit` (default `128Mi`) | **New.** `sizeLimit` of the manager's `/tmp` emptyDir. A pod that exceeds it is evicted. |
| `manager.providerTmpSizeLimit`, `manager.providerTmpSizeLimitMax` | **New**, default empty (per-type defaults: vSphere `512Gi`, libvirt/Proxmox/others `1Gi`; flags `--provider-tmp-size-limit`, `--provider-tmp-size-limit-max`). A `Provider` can override with the annotation `infra.virtrigaud.io/tmp-size-limit` (clamped to the maximum, `TmpSizeLimitClamped`). Raise the limit before migrating a vSphere disk larger than about 256 GiB; it bounds the pod's `/tmp` but does not reserve node storage. |
| `manager.maxDiskSize` | **New**, default empty (no limit). Administrator ceiling on every disk VirtRigaud creates or grows (flag `--max-disk-size`, for example `500Gi`). With `webhooks.enabled=true` it also renders two disk-size validating webhooks. Nothing changes unless it is set. |
| `providers.libvirt.tmpSizeLimit`, `providers.proxmox.tmpSizeLimit` (`1Gi`), `providers.vsphere.tmpSizeLimit` (`512Gi`) | **New**, for the chart-templated providers (still disabled by default). |
| `providers.vsphere.replicaCount` | Must be `1`; a larger value fails the render. |
| `webhooks.conversion`, `webhooks.mutating` | **Removed**: no Go code backs them. `webhooks.enabled` is still `false` by default; `webhooks.validating` remains. |
| `webhooks.certificates.caBundle` | **New**, required only for `source: manual`. |
| `crdUpgrade.*` | Unchanged. The release workflow sets the kubectl image tag to the release tag. |

Chart-templated providers (`providers.<type>.enabled`) stay disabled by default
(since v0.3.8); `Provider` CRs are unaffected.

### Behaviour changes that are visible but not breaking

- **Webhook and metrics servers require TLS 1.2 or later.** Transparent to the
  Kubernetes API server and Prometheus.
- **libvirt uses an in-process SSH client** (one persistent connection per host,
  no `ssh`/`sshpass`/`scp` subprocesses). `sshpass` is no longer needed; host-key
  verification and the `known_hosts` Secret key are unchanged
  ([host preparation](libvirt-host-prepare.md#ssh-host-key-verification-adr-0004)).
  Raise `MaxSessions` before raising the provider's concurrency limits.
- **New libvirt domains use `type='kvm'`** when the host exposes a readable
  `/dev/kvm` (before: always software emulation); existing domains are unchanged.
- **Guest-agent-derived fields** (IPs, time sync, in-guest filesystem grow after an
  online disk expand) now work on libvirt: the SSH commands are shell-quoted.
- **`VMClass.spec.memory` and `spec.diskDefaults.size` have CRD upper bounds**
  (below 100Ti and 1Pi).
- **`VirtualMachine.status.phase` is set on every VM**, and a power change or a
  failed power task no longer leaves a Proxmox VM at `Reconfiguring`.
- **Power is idempotent on every provider** (powering off an off VM succeeds).
- **`powerOffBeforeMigration`**: the VirtualMachine controller powers the source
  off and the migration waits (`SourcePowerOff=False/WaitingForSourcePowerOff`).
- **A single-host VM's provider id is no longer lost after a Create**, and a
  Create that fails on its host backs off.
- **`status.conditions[].message` no longer quotes resolver or transport errors**;
  the detail is in the manager and provider logs.
- **Source builds need Go 1.26.10** (`go.mod`). Binary and image consumers are
  unaffected.

### In-flight VMMigrations

For a migration into a clustered Provider, see also the [upgrade notes](../migration/clustered-target.md#upgrade-notes).

Migrations are the most exposed objects during this upgrade. In short:

- Before the manager rolls, let migrations in `Creating` or `Validating-Target`
  finish (the manager upgrade also restarts provider pods that mount migration
  PVCs, which interrupts an export or import running at that moment). One caught
  mid-upgrade fails with `TargetVMNotOwned` and leaves its target VM as it is:
  check the target, delete the source yourself if you meant to
  (`deleteAfterMigration` does not run for a failed migration).
- **vSphere and Proxmox targets:** a migration whose disk was landed or staged by
  the old provider but whose target VM was not yet created is refused after the
  upgrade (`ValidationError`: "landed by a release before v0.4.0" / "staged by an
  earlier release"). Delete the target `VirtualMachine` and the `VMMigration`, run
  it again, and remove the old landing folder or stage by hand. Migrations that
  completed before the upgrade, and VMs created from them, are unaffected.
- **libvirt targets:** do not start a libvirt-target migration while the provider
  is ahead of the manager; if one is between its import and its create when you
  upgrade, re-run it afterwards.
- **Completed migrations:** a `Ready` migration from before the upgrade deletes
  nothing: it is closed with a `SourceDeletionSkippedPreUpgrade` Warning if a
  snapshot or source VM would have been deleted. Remove those source snapshots and
  (with `deleteAfterMigration`) source VMs yourself if still wanted.
- **Never grant tenants `update`/`patch` on `vmmigrations/status`**: the controller
  trusts the markers it writes there to decide what to delete.

### Stale `revertToRef` on existing VMs

`spec.snapshot.revertToRef` was accepted and ignored before v0.4.0. A VM that still
carries it is **acted on by the first reconcile of the new manager**:

- The controller sends `SnapshotRevert` only while the provider reports the VM
  `Off` **and** `spec.powerState` is `Off` or `OffGraceful` (it never powers a VM
  off for it), only to a `Ready` `VMSnapshot` taken of this VM through its
  Provider. A VM that is already powered off is reverted at once, **discarding
  what was written to its disks since the snapshot**.
- A VM that is running keeps running, but is shown `Ready=False` with the
  `SnapshotReverted` condition's reason (`WaitingForPowerOff`,
  `SnapshotNotFound`, `SnapshotNotReady`, `SnapshotForAnotherVM`, `Unsupported`)
  while the request waits. The outcome is recorded in `status.snapshotRevert`.
- Remove the field from every VM you do not want reverted **before** rolling the
  manager (pre-flight 4). Upgrade the CRDs first: a CRD that prunes
  `status.snapshotRevert` makes the manager send nothing
  (`SnapshotReverted=False/Unsupported`), and the readiness check does not catch
  it.
- On libvirt, a revert needs a snapshot taken with the VM powered off; see the
  [revert reference](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-snapshot-revert.md).

### `spec.resources` overrides now resize VMs

Before v0.4.0 the `spec.resources` override was compared against and recorded in
`status.currentResources` but never sent in the Create or Reconfigure request, so
a VM could report a size it never had. Now the request and the status use the same
effective size (VMClass with the override applied). On the first reconcile after
the upgrade a VM whose override was never applied **goes through the normal
reconfigure path** and is resized to it. Reconfigure keeps its online/offline
rules: it applies live only when the VMClass has hot-add enabled and headroom was
provisioned at create, otherwise it is written to the offline config and takes
effect after a restart. To keep a VM at its current size, remove
`spec.resources` before upgrading. An override outside the VMClass bounds is
refused with `Reconfiguring=False/ValidationError`.

### Leftovers from earlier releases

VirtRigaud does not clean up files that earlier releases left behind. After
upgrading, look once for the following and delete only what no `VMMigration` in
flight uses. (From v0.4.0 on, new migrations no longer accumulate most of these.)

- **Staged migration objects** (full, unencrypted copies of source disks) of
  migrations that no longer exist: on S3 under
  `<prefix>/vmmigrations/<namespace>/<name>/export.vmdk`, on NFS
  `vmmigrations_<namespace>_<name>_export.qcow2` (new name) or
  `vmmigrations-<namespace>-<name>-export.qcow2` (old), plus the empty files NFS
  cleanup leaves on libvirt and vSphere targets. Objects recorded as
  `StagedDiskLeftBehind` are never retried.
- **libvirt snapshot overlay files** `<domain>-disk.<snapshot>` in the storage pool
  left by snapshots deleted before v0.4.0: check with `virsh domblklist --all` and
  `qemu-img info --backing-chain` that no domain uses them, then remove them.
- **vSphere `virtrigaud-export-*` files** in the VM folders of migration-source
  datastores. Every earlier vSphere disk export leaked a full copy of the exported
  disk (descriptor and `-flat.vmdk`). Find them with
  `find /vmfs/volumes/*/ -maxdepth 2 -name 'virtrigaud-export-*.vmdk'` on an ESXi
  host and delete the descriptor and its `-flat.vmdk` together, only when no
  `VMMigration` from that source is in phase `Exporting`.
- **Proxmox import stages** and `/var/tmp/.virtrigaud-import-*` on the PVE nodes.
  Sweep `/var/lib/virtrigaud/import-stage/` periodically (for example stages older
  than two days whose `VMMigration` is no longer in flight).
- **Landed migration disks** of migrations that failed or were deleted before
  v0.4.0 (vSphere `[<datastore>] <namespace>_<vm>-migrated/` and the older
  `[<datastore>] <vm>-migrated/`; libvirt `<pool>/<namespace>.<vm>-migrated.qcow2`
  and `<vm>-migrated.qcow2`). Check that no VM uses them first.
- **libvirt cloud-init seeds of existing VMs in `/tmp`.** Seeds built before
  v0.4.0 stay where their domains reference them
  (`/tmp/virtrigaud-cloudinit-<domain>.<random>/` or
  `/tmp/virtrigaud-cloudinit/<name>/`); the directories are listable by every local
  user and the ISO is usually `0644`. On every libvirt host, as root, remove the
  seed directories no domain references, and for the others remove `user-data` and
  `meta-data`, give the SSH user its private copy of the ISO **before** making the
  ISO private, then close the directory:

  ```bash
  SSH_USER=virtrigaud   # the provider's SSH user
  for d in /tmp/virtrigaud-cloudinit-*/ /tmp/virtrigaud-cloudinit/*/; do
    [ -f "$d/cloud-init.iso" ] || continue
    rm -f -- "$d/user-data" "$d/meta-data"
    cp -- "$d/cloud-init.iso" "$d/cloud-init.private.iso"
    chown "$SSH_USER": "$d/cloud-init.private.iso"
    chmod 600 "$d/cloud-init.private.iso" "$d/cloud-init.iso"
    chmod 711 "$d"
  done
  [ -d /tmp/virtrigaud-cloudinit ] && chmod 711 /tmp/virtrigaud-cloudinit
  ```

  A host that empties `/tmp` at boot or cleans old files in it (Ubuntu:
  `systemd-tmpfiles`, 30 days) removes these seeds and the domain then no longer
  starts: move a VM's seed into the seed directory while the VM is shut off (the
  commands are in the repository guide's
  [Leftovers section](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/upgrading.md#leftovers-from-earlier-releases)).
- **Bare-named prepared images** of the earlier image scheme (vSphere templates
  named after the bare `VMImage`, libvirt `<pool>/<VMImage name>.qcow2`) are left in
  place; remove them once nothing references them.

### Post-upgrade verification checklist

- [ ] `kubectl get pods -n virtrigaud-system`: the manager and provider pods are
      Ready.
- [ ] The manager's CRD-feature check passed:

  ```bash
  kubectl get crd virtualmachines.infra.virtrigaud.io \
    -o jsonpath='{.spec.versions[?(@.name=="v1beta1")].schema.openAPIV3Schema.properties.status.properties.boundProvider.type}'
  # should print: object
  kubectl get crd providers.infra.virtrigaud.io \
    -o jsonpath='{.spec.versions[?(@.name=="v1beta1")].schema.openAPIV3Schema.properties.spec.properties.consumerNamespaceSelector.type}'
  # should print: object (likewise for vmclasses and vmimages)
  ```

  or the metric `virtrigaud_manager_vm_crd_security_features` on the manager's
  `/metrics`.
- [ ] The manager is v0.4.0: `virtrigaud_build_info{version="v0.4.0"}` on
      `/metrics` (see [Observability](observability.md)).
- [ ] Every `Provider` reports `Available` and runs the v0.4.0 image:

  ```bash
  kubectl get providers -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,IMAGE:.spec.runtime.image
  ```
- [ ] No VM is unexpectedly refused for a cross-namespace reference:

  ```bash
  kubectl get virtualmachines -A -o json | jq -r '.items[]
    | select(any(.status.conditions[]?; .type=="Ready" and .reason=="ConsumerNotAllowed"))
    | "\(.metadata.namespace)/\(.metadata.name)"'
  ```

  Each line needs `spec.consumerNamespaceSelector` on the object its `Ready`
  message names.
- [ ] No `VMSnapshot` is `Ready` without a snapshot on the hypervisor. Older
      managers could mark a snapshot `Ready` without calling the provider; such
      snapshots have no `status.creationTime`. Delete and re-create each one listed:

  ```bash
  kubectl get vmsnapshots -A -o json | jq -r '.items[]
    | select(.status.phase=="Ready" and .status.creationTime==null)
    | "\(.metadata.namespace)/\(.metadata.name)"'
  ```
- [ ] Bound VMs' `providerRef` is what you expect, because the admission rule now
      locks it in. A VM bound before the upgrade gets its binding recorded from its
      **current** `providerRef` on its first reconcile (`BoundProviderRecorded`
      event); audit multi-tenant clusters beforehand with
      `kubectl get virtualmachines -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,ID:.status.id,PROVIDER_NS:.spec.providerRef.namespace,PROVIDER:.spec.providerRef.name`.
- [ ] vSphere: create (or reconcile) a test VM; it exercises the new
      `AdvancedConfig` privilege end to end.
- [ ] libvirt: on every host the seed directory exists, belongs to the SSH user and
      is private (`stat -c '%a %U' /var/lib/libvirt/virtrigaud-seeds` prints `711`
      and the SSH user), and a test VM through each Provider does not fail with
      `refusing to stage cloud-init data`. If images live outside
      `/var/lib/libvirt/images`, `VIRTRIGAUD_LIBVIRT_IMAGE_DIRS` is set and an image
      create still succeeds.
- [ ] libvirt: before deleting any pre-upgrade VM, check
      `virsh domblklist --details <domain>` for a shared legacy disk.
- [ ] Image preparation: `virtrigaud_provider_image_prepare_legacy_requests_total`
      stays `0` for every `provider_type`. A non-zero value means a manager older
      than v0.4.0 is still sending requests by bare name.
- [ ] Clustered libvirt: `kubectl get hosts -A -o custom-columns=NAME:.metadata.name,STORAGE:.status.allocatableStorageBytes`
      shows the free space of each host's `default` pool.
- [ ] If you enabled `networkPolicy.enabled=true`, render and check the objects
      before relying on them:
      `helm template virtrigaud virtrigaud/virtrigaud --set networkPolicy.enabled=true | grep -A2 'kind: NetworkPolicy'`.

### Rollback caveats

A partial rollback (providers only, or the manager only) is safer than a full one
and is enough for most issues. For a full rollback go in reverse (providers,
manager, CRDs) and expect the following. Rolling back is **not** a way to remove
the security fixes' state: some of it is recorded in the cluster.

- **The `Provider` in-use finalizer stays.** An older manager neither adds nor
  removes `provider.infra.virtrigaud.io/in-use`, so a `Provider` deleted after the
  rollback stays `Terminating`. Check that no VM uses it, then remove the finalizer:
  `kubectl patch provider <name> -n <namespace> --type=json -p '[{"op":"remove","path":"/metadata/finalizers"}]'`.
- **CRD changes are one-way in practice.** The `spec.providerRef` immutability rule
  is a CRD CEL rule, so rolling the *manager* back does not restore the ability to
  re-point a bound VM; only an older CRD does, and that also drops
  `status.boundProvider` and the other additive status fields.
- **Do not downgrade the `VirtualMachine` CRD while a VM's `status.powerState` is
  `Suspended` or `Unknown`**: the older enum rejects every status write of such a
  VM.
- **An old manager against the new CRDs silently drops the new protections**: it
  does not enforce the bound-provider check, ignores `spec.consumerNamespaceSelector`
  (re-opening unrestricted cross-namespace references) and the namespace grant
  annotation, and ignores `orphan-on-delete`. Treat that window as running without
  the defence in depth.
- **An old manager against a new provider.** A new libvirt provider serves image
  prepares in deprecated legacy mode by bare name (logged at `WARN`, counted in
  `virtrigaud_provider_image_prepare_legacy_requests_total`); a new vSphere provider
  does the same, so the cross-tenant limitation ADR-0009 closed is back while the
  manager is rolled back; a new Proxmox provider refuses URL imports.
- **Rolling a provider back** holds image prepares (`ProviderLacksArtifactIdentity`),
  stops owner stamping on single-host adoptions and Proxmox VMs, stops applying a
  Proxmox VM's networks, holds clustered resizes
  (`ProviderLacksHonestReconfigure`) and new clustered VMs
  (`ProviderLacksListOwnerFilter`), removes the cluster-wide disk guard of a clustered
  libvirt provider, and brings back the wrong-disk resize on vSphere and Proxmox (hold
  CPU/memory changes of VMs with `spec.disks` while an older image runs).
- **Seeds and domains outlive a libvirt provider rollback.** An older libvirt
  provider builds new seeds in `/tmp` again and makes clones share their source's
  identity; seeds already in the seed directory keep working but the older provider
  does not know to remove them. Domains created as `<namespace>.<name>` keep that
  name.
- **A clustered-target migration in flight** cannot be rolled back safely: an older
  manager does not know `WaitingForImport`. Finish or delete such migrations first.

### Upgrading from a release candidate

Release candidates rc1, rc2 and rc4 to rc9 were cut; **rc3 was tagged but its
release run was stopped by the image scan and no rc3 release was published**.
v0.4.0 is built from the same code as rc9, so from rc9 only the version changes: bump the
chart to `0.4.0` and the images to `v0.4.0`. From an earlier candidate apply, in
order, every step from your candidate up to rc9, then bump:

| You are on | Do, before moving on |
|------------|----------------------|
| **rc8** | Roll the libvirt providers (single-host and clustered) first, then the manager. No CRD, RBAC, chart or proto change. Until a provider is rolled, do not delete a disk-only snapshot of a VM that has a memory snapshot: the old provider destroys the memory snapshot. The rc9 delete check also reads the overlays a child snapshot or a revert recorded, so confirm the `VR_DISK_READ` grant (rc8 step). |
| **rc7** | Grant the SSH user `VR_DISK_READ` over the pool directory (and every other directory VM disks live in) where it cannot read libvirt's `0600` overlays; skip where it already can. Then the manager and the libvirt providers. Only the description of `status.ips` changed in the CRDs. |
| **rc6** | Repair any libvirt VM you reverted to a snapshot on rc6 (its CD-ROM is on a `cloud-init.<digits>` file and it does not start; follow the [repair runbook](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-snapshot-revert.md#repairing-a-vm-broken-by-a-v040-rc6-revert)), then roll the libvirt providers, then take new snapshots (VM powered off) of the VMs you want to revert, and delete the old ones. No CRD change. |
| **rc5** | Remove `spec.snapshot.revertToRef` from VMs (and `VMSet` templates) you do not want reverted; apply the CRDs (`VirtualMachine` gains `status.snapshotRevert`, `HostPool` gains printer columns); roll the manager (its role gains `hostpools/status`); roll the clustered libvirt provider. |
| **rc4** | Grant the PVE token `VM.Config.Network`, `VM.Config.Cloudinit` and `SDN.Use` on its bridges, then roll the manager and the Proxmox provider **together**. No CRD change. |
| **rc2** | Create the seed directory on every libvirt host **first**. Apply the CRDs (`VirtualMachine`, `VMSet`, `VMMigration` changed), then the manager, then the providers (the clustered libvirt provider before you migrate into it). Review who can create `VMClone`s (clones carry their source's user-data) and any `VMPlacementPolicy` `minDiskSpacePerHost` (it now compares against the `default` pool alone). Make the seeds in `/tmp` private ([leftovers](#leftovers-from-earlier-releases)). |
| **rc1** | Apply the CRDs first (two optional status fields are new: `VMMigration` `status.storagePVCUID` and `status.storageInfo.importTarget.providerUID`; an old CRD prunes them), roll **all** providers with the manager (not only Proxmox: three capability fields are new), let migrations in `Creating`/`Validating-Target` finish, and expect the manager upgrade to restart provider pods that mount migration PVCs. |

## Older versions

Notes for releases before v0.3.11, newest first. They remain accurate for the
release they describe; a skipped release's notes still apply.

### v0.3.7 → v0.3.8

**Additive release. No breaking changes for operators.** v0.3.8 adds two new
controllers (VMClone + VMSet), a new status field on `VMClone`, the RBAC those
controllers need, and provider-side connection-resilience fixes. A standard
`helm upgrade` picks everything up. The one thing to check is the chart's
templated-provider default — see the Helm note below.

#### What's new (no operator action required)

- **VMClone + VMSet controllers** — the manager now runs two additional
  reconcilers. The Helm chart adds the RBAC for `vmclones` and `vmsets` (and
  their `/status` subresources) automatically. If you maintain a hand-rolled
  ClusterRole instead of the chart's, add read/write on
  `vmclones`/`vmclones/status` and `vmsets`/`vmsets/status` in the
  `infra.virtrigaud.io` API group.
- **New `VMClone.status.targetVMID` field** — purely additive status field
  surfacing the provider-specific ID of the clone's target VM. No spec change,
  no migration step.
- **Provider connection resilience** — the vSphere provider now keeps its
  vCenter session alive and reconnects on a real probe failure
  ([#190](https://github.com/projectbeskar/virtrigaud/pull/190)); the libvirt
  provider now retries transient SSH connection failures with bounded backoff
  ([#191](https://github.com/projectbeskar/virtrigaud/pull/191)). Both are
  provider-internal — no Provider CR change. See
  [Resilience](resilience.md#provider-side-connection-resilience-v038).
- **Migration-storage PVC safety** — the provider controller no longer deletes
  migration-storage PVCs and now watches them
  ([#184](https://github.com/projectbeskar/virtrigaud/pull/184)). No operator
  action; in-flight migrations are simply safer.

#### Helm note: templated providers are DISABLED by default ([#173](https://github.com/projectbeskar/virtrigaud/pull/173))

The chart no longer renders templated provider Deployments by default. This is a
**chart default change, not a code breaking change**:

- **If you manage providers as `Provider` CRs** (the recommended pattern, where
  the operator deploys provider workloads from the CR) — **you are unaffected.**
  Nothing changes.
- **If you relied on the chart's templated providers** (rendered directly from
  Helm values rather than from a `Provider` CR), they will no longer be created
  after the upgrade. Re-enable each one explicitly:

  ```yaml
  providers:
    vsphere:
      enabled: true
    libvirt:
      enabled: true
    proxmox:
      enabled: true
  ```

  Set only the types you actually use.

#### Helm upgrade command

```bash
helm repo update
helm upgrade -i virtrigaud virtrigaud/virtrigaud \
  --version 0.3.8 \
  --reset-values \
  -f your-values.yaml
```

If you use chart-templated providers, remember the `providers.<type>.enabled=true`
flag above must be in `your-values.yaml` or they will not be rendered.

#### Post-upgrade verification

```bash
# Confirm the manager is running v0.3.8
kubectl -n virtrigaud-system port-forward deploy/virtrigaud-manager 8080:8080 &
curl -s localhost:8080/metrics | grep '^virtrigaud_build_info'
# Expect: virtrigaud_build_info{version="v0.3.8",...} 1

# Confirm the new reconcilers are emitting (after first VMClone/VMSet activity)
curl -s localhost:8080/metrics | \
  grep -E 'virtrigaud_manager_reconcile_total\{kind="(VMClone|VMSet)"'

# All providers should still be ProviderAvailable=True
kubectl get providers -A
```

### v0.3.6 → v0.3.7

Released 2026-05-30. **Security enforcement + multi-arch release.** Two breaking
changes affect SSH libvirt providers and any Provider CR without a `tls` block.

#### Breaking changes

##### 1. mTLS now enforced on all Provider CRs (BREAKING)

The manager now **requires** a `spec.runtime.service.tls` block on every
Provider CR. A Provider that lacks the block will not reconcile — no Deployment
is created — and its status shows:

```
TLSConfigured=False, Reason=TLSBlockMissing
```

**Remediation — to enable mTLS (recommended for production):**

1. Create a TLS Secret with `tls.crt`, `tls.key`, and `ca.crt`:

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: provider-vsphere-tls
     namespace: virtrigaud-system
   type: kubernetes.io/tls
   data:
     tls.crt: <base64>
     tls.key: <base64>
   stringData:
     ca.crt: |
       -----BEGIN CERTIFICATE-----
       ...
       -----END CERTIFICATE-----
   ```

2. Add the `tls` block to your Provider CR under `spec.runtime.service`:

   ```yaml
   runtime:
     service:
       tls:
         enabled: true
         secretRef:
           name: provider-vsphere-tls
         insecureSkipVerify: false
   ```

**Remediation — to keep plaintext (dev/lab only):**

```yaml
runtime:
  service:
    tls:
      enabled: false
```

When `tls.enabled: false`, the condition reads `TLSConfigured=False,
Reason=ExplicitlyDisabled` and the Deployment proceeds. This is audit-flagged
and not suitable for regulated environments.

**Additional mTLS facts:**

- TLS 1.3 is the minimum protocol version for both manager and provider.
- Provider env `VIRTRIGAUD_PROVIDER_ALLOWED_SANS` (comma-joined) constrains
  which manager certificates are accepted. `VIRTRIGAUD_PROVIDER_INSECURE=true`
  opts out of TLS entirely on the provider side (plaintext).
- Fail-closed: no TLS material + no explicit opt-out → provider hard-exits.
- For chart-templated providers, the Helm `providerTLS` block accepts
  `secretName`, `allowedSANs` (list), and `insecure` (bool, only when
  `secretName` is empty).

##### 2. Libvirt SSH host-key verification now enforced (BREAKING for SSH libvirt)

In v0.3.6 the libvirt provider set `no_verify=1` on the SSH URI, skipping
host-key verification. **That flag is removed in v0.3.7.** Existing SSH libvirt
Providers will stop connecting after the upgrade until a `known_hosts` key is
added to the credentials Secret.

**Remediation:**

Seed `known_hosts` on the operator workstation and add it to the Secret:

```bash
ssh-keyscan -H <libvirt-host> > known_hosts
kubectl patch secret libvirt-creds -n virtrigaud-system \
  --type='json' \
  -p="[{\"op\": \"add\", \"path\": \"/stringData/known_hosts\",
         \"value\": \"$(cat known_hosts)\"}]"
```

The provider reads the key from `/etc/virtrigaud/credentials/known_hosts`.

**Escape hatch (lab/migration windows only; audit-flagged):**

```yaml
spec:
  runtime:
    env:
      - name: LIBVIRT_INSECURE_SKIP_HOST_KEY_VERIFICATION
        value: "true"
```

#### Other changes (no operator action required)

- **Multi-arch images** — all component images (`manager`, `provider-vsphere`,
  `provider-libvirt`, `provider-proxmox`) are now built for both
  `linux/amd64` and `linux/arm64`. arm64 clusters are now fully supported.
  No changes needed in Provider CRs or Helm values.

- **Manager RBAC tightened** — the manager's ClusterRole now grants read-only
  access to Secrets (was read-write in v0.3.6). If you added custom rules that
  relied on write access, re-add them via `rbac.additionalRules` in your Helm
  values. A `helm upgrade` picks up the new RBAC automatically. (v0.4.0 adds
  `create` and `update` on Secrets again, for the clustered libvirt
  `<provider>-hosts` Secret only; see [Manager RBAC](#manager-rbac).)

- **Go source-build floor raised to 1.26.3** — if you build from source, you
  need Go 1.26.3 or later. Binary and image consumers are unaffected.

#### Helm upgrade command

```bash
helm repo update
helm upgrade -i virtrigaud virtrigaud/virtrigaud \
  --version 0.3.7 \
  --reset-values \
  -f your-values.yaml
```

If you use chart-templated providers with `providerTLS.secretName`, ensure the
referenced Secret exists before the upgrade or the provider pods will not start.

#### Post-upgrade verification

```bash
# All providers should show TLSConfigured=True and ProviderAvailable=True
kubectl get providers -A

# Confirm the manager is running v0.3.7
kubectl -n virtrigaud-system port-forward deploy/virtrigaud-manager 8080:8080 &
curl -s localhost:8080/metrics | grep '^virtrigaud_build_info'
# Expect: virtrigaud_build_info{version="v0.3.7",...} 1

# Check for any providers still failing TLS negotiation
kubectl get providers -A \
  -o custom-columns=NAME:.metadata.name,TLS:.status.conditions[?(@.type=="TLSConfigured")].reason
```

### v0.3.5 → v0.3.6

Released 2026-05-25. **Headline observability + supply-chain release.** No
breaking changes for default-config users; binary consumers via released
images are unaffected.

#### Breaking changes

- **None for operators.** Source builders need **Go 1.26+** installed
  locally ([#125](https://github.com/projectbeskar/virtrigaud/pull/125),
  toolchain floor bumped 1.24.0 → 1.26.0). If you only consume the released
  manager + provider container images, this does not affect you.

#### Helm upgrade command

```bash
helm repo update
helm upgrade -i virtrigaud virtrigaud/virtrigaud \
  --version 0.3.6 \
  --reset-values
```

`--reset-values` ensures the upgrade picks up any new chart defaults rather than
carrying over stale rendered values. If you have local value overrides, pass them
via `-f your-values.yaml` after `--reset-values` (or use `--reset-then-reuse-values`,
see [Required upgrade order](#required-upgrade-order)).

#### New `/metrics` families to add to dashboards

After the rollout, the following `virtrigaud_*` families become available
(some emit immediately, some on first activity):

| Metric | Type | Labels | When it populates |
|---|---|---|---|
| `virtrigaud_circuit_breaker_state` | gauge | `provider_type`, `provider` | Immediately at boot (one row per Provider CR). Values: 0=Closed, 1=HalfOpen, 2=Open. **Alertable on `> 0`.** |
| `virtrigaud_circuit_breaker_failures_total` | counter | `provider_type`, `provider` | On first CB-counted RPC failure per Provider |
| `virtrigaud_vm_operations_total` | counter | `provider_type`, `provider`, `operation`, `outcome` | On the first VM RPC after deploy (Create/Delete/Power/Describe/Reconfigure) |
| `virtrigaud_ip_discovery_duration_seconds` | histogram | `provider_type` | On the first no-IPs → has-IPs VM transition (idempotent across manager restarts) |
| `virtrigaud_provider_tasks_inflight` | gauge | `provider_type`, `provider` | Seeded to 0 at boot, increments on the first task-creating RPC |

These slot in alongside the metrics already present since v0.3.5. The full
metric inventory after v0.3.6 is **11 of 12** `virtrigaud_*` families wired
in code; the 12th (`virtrigaud_queue_depth`) is explicitly deprecated — see
the next section.

Suggested baseline alerts:

- `max by (provider) (virtrigaud_circuit_breaker_state) > 0` for **5m** —
  fires when any Provider's circuit opens or half-opens
- `rate(virtrigaud_vm_operations_total{outcome="error"}[5m]) > 0` per
  provider/operation — surface elevated failure rates
- `histogram_quantile(0.95, sum by (le, provider_type) (rate(virtrigaud_ip_discovery_duration_seconds_bucket[5m])))` —
  P95 time from `kubectl apply` to first IP

#### Deprecation: `virtrigaud_queue_depth`

The `virtrigaud_queue_depth{kind}` gauge and the
`(*ReconcileMetrics).SetQueueDepth` helper are **deprecated in v0.3.6**
([#132](https://github.com/projectbeskar/virtrigaud/pull/132)). They are
redundant with controller-runtime's `workqueue_depth{name=<controller-name>}`,
which has been on `/metrics` since v0.3.0 and comes with sibling workqueue
metrics (adds, retries, queue and work durations) for free.

The metric family is still registered in v0.4.0 (no breakage), and the `# HELP`
line begins with `[DEPRECATED v0.3.6 — use workqueue_depth{name} instead]` so the
deprecation surfaces on your next scrape. Removal is scheduled for a later
release; migrate dashboards now.

**Migration mapping** for the 8 reconciler kinds (also in the GoDoc on
`SetQueueDepth`):

| Reconciler                       | controller-runtime `name` label |
|----------------------------------|---------------------------------|
| `VirtualMachineReconciler`       | `virtualmachine`                |
| `ProviderReconciler`             | `provider`                      |
| `VMClassReconciler`              | `vmclass`                       |
| `VMImageReconciler`              | `vmimage`                       |
| `VMNetworkAttachmentReconciler`  | `vmnetworkattachment`           |
| `VMAdoptionReconciler`           | `vmadoption`                    |
| `VMSnapshotReconciler`           | `vmsnapshot`                    |
| `VMMigrationReconciler`          | `vmmigration`                   |

Dashboard rewrite recipe:

```
virtrigaud_queue_depth{kind="virtualmachine"}
    →    workqueue_depth{name="virtualmachine"}
```

#### CircuitBreaker behaviour change

Every outbound provider gRPC RPC is now wrapped by a per-Provider
CircuitBreaker ([#112](https://github.com/projectbeskar/virtrigaud/issues/112)),
backed by the new `virtrigaud_circuit_breaker_*` metric families above.

Defaults:

| Setting              | Default | Effect                                         |
|----------------------|---------|------------------------------------------------|
| `FailureThreshold`   | 10      | Open after 10 consecutive infra-class failures |
| `ResetTimeout`       | 60s     | Time in Open before transitioning to HalfOpen  |
| `HalfOpenMaxCalls`   | 3       | Probe calls allowed in HalfOpen state          |

**What trips the breaker** (infra-class gRPC errors):

- `Unavailable`
- `DeadlineExceeded`
- `Internal`
- `Unknown`

**What passes through** (business-class errors — no CB impact):

- `NotFound`, `AlreadyExists`, `InvalidArgument`, `FailedPrecondition`,
  `PermissionDenied`, `Unauthenticated`, etc.

!!! note "v0.4.0 excludes more infra-class answers from the breaker"
    In v0.4.0 an `Unavailable` that is scoped to one clustered host, a
    per-VM `VM_OPERATION_FAILED`, `VM_DISK_CHECK_FAILED`, an `OUTCOME_UNKNOWN_RETRY`
    answer, and image-source failures (`IMAGE_SOURCE_UNAVAILABLE`) no longer count
    toward the breaker, so one failing VM or one dead host cannot open it for the
    whole Provider. The defaults below are unchanged
    (`internal/transport/grpc/client.go`, `internal/resilience/circuitbreaker.go`).

!!! warning "Global config only — no per-Provider knob yet"
    The CB defaults come from `resilience.DefaultConfig()` and are applied
    uniformly to every Provider CR. There is **no per-Provider override
    field** in v0.3.6. If you need different thresholds for a high-latency
    provider, that work is tracked separately; for now, plan around the
    defaults above.

#### Security: OpenTelemetry CVE fixes

The OpenTelemetry Go SDK dependencies are bumped to **v1.43.0** in v0.3.6,
closing 3 HIGH-severity CVEs that were present in v0.3.5
([#143/#144](https://github.com/projectbeskar/virtrigaud/pull/144)):

| CVE              | Package                            | v0.3.5 | v0.3.6  |
|------------------|------------------------------------|--------|---------|
| CVE-2026-29181   | `go.opentelemetry.io/otel`         | v1.39.0 | v1.43.0 |
| CVE-2026-24051   | `go.opentelemetry.io/otel/sdk`     | v1.39.0 | v1.43.0 |
| CVE-2026-39883   | `go.opentelemetry.io/otel/sdk`     | v1.39.0 | v1.43.0 |

CVE-2026-24051 and CVE-2026-39883 are PATH-hijacking primitives — exactly
the class of finding regulated environments will not accept. **Upgrade
promptly** if you scan with Trivy/Grype.

#### Smoke recipe (verify your upgrade)

After the rollout completes, verify the manager is running the v0.3.6 binary
and the new metrics are present:

```bash
# Port-forward to the manager metrics endpoint
kubectl -n virtrigaud-system port-forward deploy/virtrigaud-manager 8080:8080 &

# 1. Build info must report v0.3.6 / Go 1.26.x
curl -s localhost:8080/metrics | grep '^virtrigaud_build_info'
# Expect: virtrigaud_build_info{version="v0.3.6", go_version="go1.26.x", ...} 1

# 2. Count distinct virtrigaud_* metric families on /metrics
curl -s localhost:8080/metrics | grep -E '^# HELP virtrigaud_' | wc -l
# Expect: ~9-11 families emit immediately. The remaining 2 (vm_operations_total,
# ip_discovery_duration_seconds) populate on the first relevant VM event.

# 3. Confirm the CB gauge is exposed (one row per Provider CR)
curl -s localhost:8080/metrics | grep '^virtrigaud_circuit_breaker_state'

# 4. Confirm deprecation banner on the old queue_depth gauge
curl -s localhost:8080/metrics | grep -B1 '^virtrigaud_queue_depth' | head -2
# Expect a # HELP line beginning with [DEPRECATED v0.3.6 ...]
```

If any of those checks fail, capture the manager logs
(`kubectl -n virtrigaud-system logs deploy/virtrigaud-manager`) before
rolling back.


### v0.2.0 → v0.2.1

**Changes that need a CRD update:**

- PowerState validation fixed (`OffGraceful` is now supported).
- Hardware version management added (vSphere only).
- Disk size configuration is respected.

**Required Actions:**
1. **CRD Update Required**: New powerState validation and schema changes
2. **Provider Image Update**: Ensure providers use v0.2.1+ images for new features
3. **Field Testing**: Verify OffGraceful, hardware version, and disk sizing work correctly

**Upgrade Steps:**
```bash
# 1. Backup existing resources
kubectl get virtualmachines,vmclasses,providers -A -o yaml > virtrigaud-backup-v021.yaml

# 2. Update CRDs (fixes OffGraceful validation) from the chart you are installing
helm pull virtrigaud/virtrigaud --version 0.2.1 --untar
kubectl apply --server-side --force-conflicts -f virtrigaud/crds/

# 3. Upgrade VirtRigaud
helm upgrade virtrigaud virtrigaud/virtrigaud --version 0.2.1

# 4. Verify OffGraceful works
kubectl patch virtualmachine <vm-name> --type='merge' -p='{"spec":{"powerState":"OffGraceful"}}'
```

## Rollback procedures

For the v0.3.11 to v0.4.0 caveats, read [Rollback caveats](#rollback-caveats)
first: a rollback is not symmetrical.

### Rollback to the previous version

```bash
# 1. Find the revision to return to
helm history virtrigaud -n virtrigaud-system

# 2. Roll the application back
helm rollback virtrigaud <revision> -n virtrigaud-system

# 3. Roll the Provider images back too (spec.runtime.image on each Provider CR)

# 4. Verify resources are still reconciled
kubectl get virtualmachines -A
```

`helm rollback` restores the manager and the chart templates. It does **not**
roll the CRDs back: the chart's CRD hook runs only on `pre-install` and
`pre-upgrade`. Reapplying an older CRD schema removes admission rules and prunes
fields that were already recorded (for example `status.boundProvider`), which is
not recommended after a v0.4.0 upgrade.

### Emergency recovery

```bash
# 1. Check the manager and provider logs
kubectl logs -n virtrigaud-system deployment/virtrigaud-manager
kubectl logs -n virtrigaud-system -l app.kubernetes.io/component=provider --tail=200

# 2. Restart the manager to force a fresh reconcile of everything
kubectl rollout restart -n virtrigaud-system deployment/virtrigaud-manager

# 3. Last resort: restore custom resources from your backup. Remove the
#    server-populated fields (metadata.uid, resourceVersion, status) first.
#    This restores specs only; it does not restore any hypervisor state.
kubectl apply -f virtrigaud-backup.yaml
```

## Automated upgrade with GitOps

The chart's CRD hook applies the CRDs in the same sync that rolls the manager. For
v0.3.11 to v0.4.0 you need a pause between the CRDs and the manager (the
consumer grants of step 3), so apply the CRDs and the selectors **before** you
bump the chart revision (the CRD command of step 2 works from any workstation).

### ArgoCD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: virtrigaud
  namespace: argocd
spec:
  project: default
  source:
    chart: virtrigaud
    repoURL: https://projectbeskar.github.io/virtrigaud
    targetRevision: "0.4.0"
  destination:
    server: https://kubernetes.default.svc
    namespace: virtrigaud-system
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true   # CRD updates
```

### Flux

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: virtrigaud
  namespace: virtrigaud-system
spec:
  interval: 10m
  chart:
    spec:
      chart: virtrigaud
      version: "0.4.0"
      sourceRef:
        kind: HelmRepository
        name: virtrigaud
  upgrade:
    crds: CreateReplace  # Ensure CRDs are updated
```

The `v2` API needs Flux 2.3 or later; earlier versions use `v2beta2`.

## Troubleshooting upgrades

### The manager is not Ready after the upgrade

`helm upgrade --wait` times out and the old pod stays. The new manager's readiness
includes a CRD-feature check (`vm-crd-security-features`). Its log line names the
missing field; apply the CRDs from the chart you are upgrading to:

```bash
kubectl logs -n virtrigaud-system deploy/virtrigaud-manager | grep -i 'crd'
kubectl apply --server-side --force-conflicts -f virtrigaud/crds/
```

### CRD validation or apply errors

```bash
# Check the CRD you are applying over
kubectl get crd virtualmachines.infra.virtrigaud.io -o yaml

# Field-ownership conflicts from earlier client-side applies
kubectl apply --server-side --force-conflicts -f virtrigaud/crds/
```

A `kubectl apply` of a field the installed CRD does not know is rejected (strict
field validation) or pruned: apply the CRDs first, then the object.

### VMs stop reconciling with `ConsumerNotAllowed`

Set `spec.consumerNamespaceSelector` on the object the `Ready` message names; the
manager re-drives the VM within seconds of each grant. Nothing was deleted.

### Provider image mismatch

```bash
# Check provider images
kubectl get providers -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,IMAGE:.spec.runtime.image

# Update provider image
kubectl patch provider <provider-name> -n <namespace> --type='merge' \
  -p '{"spec":{"runtime":{"image":"ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.0"}}}'
```

### libvirt creates fail with `refusing to stage cloud-init data`

The seed directory is missing or not private on that host. See
[Libvirt host preparation](libvirt-host-prepare.md#cloud-init-seed-directory).

### VMs stay `Terminating`

A VM waits while its `Provider` is down or rolling out
(`Ready=False/ProviderUnavailable`), and a `Provider` waits while VMs use it
(`DeleteBlocked=True/ProviderInUse`). Fix the Provider first; the cause is in the
manager log (`Cannot reach the provider to delete the VM`). To release on purpose,
see [Orphan-on-delete and force-delete](#orphan-on-delete-and-force-delete).

### Resource conflicts

```bash
# Check recent events
kubectl get events -A --sort-by=.metadata.creationTimestamp

# Restart the provider pods of one Provider (the Deployment name depends on the Provider)
kubectl rollout restart -n <namespace> deployment/<provider-deployment>
```

## Best practices

### Pre-upgrade checklist

- [ ] Back up all VirtRigaud resources.
- [ ] Read the release notes and [Breaking changes](#breaking-changes).
- [ ] Run the [pre-flight checks](#pre-flight-checks).
- [ ] Test the upgrade in a staging cluster and, for libvirt, on a non-production
      host.
- [ ] Verify provider connectivity.
- [ ] Plan the rollback strategy ([caveats](#rollback-caveats)).

### Monitoring during the upgrade

```bash
# Watch controller logs
kubectl logs -n virtrigaud-system deployment/virtrigaud-manager -f

# Monitor VM status
kubectl get virtualmachines -A --watch

# Check provider health
kubectl get providers -A
```

### Packaging the chart yourself

The chart's own `crds/` directory is generated on demand and is empty in a source
checkout. The pre-upgrade hook applies the CRDs baked into the chart **at package
time**, so a chart packaged before a CRD change **overwrites** the live CRDs and can
prune fields its schema does not know. Run `make gen-helm-crds` (or
`make helm-package`) before packaging, and `make verify-helm-crds` to check that
the chart's CRDs match `config/crd/bases`. Always upgrade with a chart built from a
matching release.

## Support and recovery

If you encounter issues during an upgrade:

1. **Check the release notes:** <https://github.com/projectbeskar/virtrigaud/releases>
2. **Review logs:** controller and provider logs for error details.
3. **Ask the community:** GitHub issues and discussions.
4. **Roll back:** use the documented procedures, partial first.

Always test upgrades in a non-production environment first.
