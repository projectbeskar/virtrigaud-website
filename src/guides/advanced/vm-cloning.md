<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VM Cloning (VMClone)

The **VMClone** controller lets you clone an existing, provisioned
`VirtualMachine` into a brand-new one through a declarative resource. It
shipped as an MVP in **v0.3.8**
([#179](https://github.com/projectbeskar/virtrigaud/pull/179)).

This page covers what the VMClone controller does, the scope and limits, a worked example, what the controller produces, and the cleanup / capability-gating semantics you should understand before relying on it.

**v0.3.9 update**: libvirt clone support is now fully implemented. The "libvirt does not support Clone" warning from v0.3.8 is reversed — see [Libvirt clone support](#libvirt-clone-support-v039).

!!! note "Scope — read before you build around it"
    The VMClone controller is intentionally narrow: **`source.vmRef`
    only**, **same-provider only**, and **Full / Linked clone types only**.
    Other source kinds (`snapshotRef`, `templateRef`, `imageRef`) are
    declared in the CRD but **not yet implemented** — they set the clone to
    `Phase=Failed` with a "not yet supported" message. The rest of the
    `VMClone` schema (rich customization, retry policy, performance/storage
    options, progress reporting) is present on the API for forward
    compatibility but is **not** acted on by the current controller.

## What VMClone does

Given a reference to an already-provisioned source `VirtualMachine`, the
controller asks the source VM's provider to clone the underlying VM, then
produces a **target `VirtualMachine` CR** that is bound to the freshly
cloned VM. The new CR is *adopted* — it is labeled so the VirtualMachine
controller does not try to create a second VM — and its `Status.ID` is
seeded with the provider-reported clone ID.

```
┌──────────────┐        clone        ┌──────────────────────┐
│  VMClone CR  │ ──────────────────▶ │  Provider (vSphere /  │
│              │                     │  Proxmox / Libvirt)    │
│              │                     │  Clone RPC             │
│ source.vmRef │ ◀────────────────── │  → new VM ID           │
└──────┬───────┘     target VM ID    └──────────────────────┘
       │
       │ produces + binds
       ▼
┌──────────────────────────────────────────────┐
│  target VirtualMachine CR                      │
│   labels: virtrigaud.io/adopted=true           │
│   status.id: <provider clone ID> (seeded)      │
└──────────────────────────────────────────────┘
```

## Scope and limits

| Dimension | Behavior |
|-----------|----------|
| **Source** | `source.vmRef` only. The referenced `VirtualMachine` must already be provisioned (non-empty `Status.ID`); otherwise the controller waits and requeues. |
| **Other sources** | `source.snapshotRef`, `source.templateRef`, `source.imageRef` → `Phase=Failed` with "clone source type not yet supported; use `source.vmRef`". |
| **Provider scope** | **Same-provider only.** The clone lands on the source VM's provider. Cross-provider movement uses [VM Migration](../../migration/vm-migration-guide.md). |
| **Clone types** | `FullClone` (default) and `LinkedClone`. `LinkedClone` is gated on the provider's reported `SupportsLinkedClones` capability. `InstantClone` exists in the enum but is not yet implemented. |
| **Provider support** | vSphere, Proxmox, and **libvirt** (as of v0.3.9) all support `Clone`. |
| **Customization** | The controller inherits the source VM's shape; the rich `spec.customization` block is **not** applied yet. |

## Libvirt clone support (v0.3.9)

As of v0.3.9 (#153/#208/#221), the libvirt provider fully implements the `Clone` RPC and reports `SupportsLinkedClones=true`. Both clone types work on the same provider:

| Clone type | Libvirt mechanism |
|-----------|-------------------|
| **Linked** | qcow2 overlay (`backing_file`) — fast and space-efficient; the base image is shared read-only, guest writes go to the overlay. |
| **Full** | Volume copy via `qemu-img convert` — fully independent disk with no dependency on the source. |

Clone operations are always same-provider; the source and target `VirtualMachine` must reference the same `Provider` CR.

### UEFI nvram handling

When the source VM uses UEFI firmware, the cloned domain receives its own independent `<nvram>` varstore (re-pointed by the provider at clone time, #208). Source and clone do not share EFI variables or secure-boot state. Modifying secure-boot configuration on one does not affect the other.

### Hot-add headroom preservation

If the source VM was created from a VMClass with `cpuHotAddEnabled` or `memoryHotAddEnabled`, a class-override clone preserves the headroom in the cloned domain XML (#221). The 4× vCPU ceiling and balloon maximum are recomputed from the override class (or inherited from the source class if no override is specified), not defaulted to bare-minimum values.

## Worked example

The following clones an existing, provisioned `VirtualMachine` named
`my-source-vm` into a new VM named `my-cloned-vm` on the same provider.

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClone
metadata:
  name: basic-clone
  namespace: default
spec:
  # Source: an existing VirtualMachine CR in this namespace whose
  # Status.ID is already populated (i.e. it has been provisioned).
  source:
    vmRef:
      name: my-source-vm

  # Target: the VirtualMachine CR the controller will create.
  target:
    name: my-cloned-vm
    # Optional: override the VMClass for the clone. Defaults to the
    # source VM's class when omitted.
    classRef:
      name: standard-vm
    # Optional labels applied to the produced VM. The controller always
    # also adds virtrigaud.io/adopted=true.
    labels:
      app: cloned-app

  # Optional: clone behavior. Defaults to FullClone.
  options:
    type: FullClone        # or LinkedClone (requires provider support)
```

Apply and watch it progress:

```bash
kubectl apply -f basic-clone.yaml

# The printer columns show source, target, phase, clone type, and progress.
kubectl get vmclone basic-clone -o wide

# Once the clone completes, the produced VM appears as a normal VirtualMachine.
kubectl get vm my-cloned-vm
```

### Requesting a linked clone

```yaml
spec:
  source:
    vmRef:
      name: my-source-vm
  target:
    name: my-linked-clone
  options:
    type: LinkedClone      # gated on provider SupportsLinkedClones
```

If the resolved provider does not report `SupportsLinkedClones`, the
controller refuses the request up front and sets `Phase=Failed` with the
`LinkedCloneUnsupported` reason — it does **not** silently fall back to a
full clone. See [Capability gating](#capability-gating-and-linked-clones).

## What the controller produces

On a successful clone, the controller creates a target `VirtualMachine` CR
named `spec.target.name` with:

- **`virtrigaud.io/adopted=true`** label — this tells the VirtualMachine
  controller the underlying VM already exists, so it adopts (binds to) the
  cloned VM instead of issuing a second `Create`.
- **`Status.ID` seeded** with the provider's clone ID, so the adopted VM is
  immediately bound to the real VM on the hypervisor.
- Any labels/annotations you set under `spec.target`, plus clone-provenance
  annotations.
- The class / networks / placement resolved from `spec.target` (defaulting
  to the source VM where omitted).

The VMClone's own status records the binding:

| Status field | Meaning |
|--------------|---------|
| `status.phase` | `Pending` → `Cloning` → `Ready` (or `Failed`). |
| `status.targetRef` | Reference to the produced `VirtualMachine` CR. |
| `status.targetVMID` | The provider-reported clone ID. Persisted so an async clone task can seed the target VM's `Status.ID` after the task completes. |
| `status.actualCloneType` | The clone type actually used (`FullClone` / `LinkedClone`). |
| `Ready` condition | `True` only once the target VM is created and its `Status.ID` is confirmed seeded. |

!!! info "Why `targetVMID` is on the VMClone status"
    Provider clone tasks can be asynchronous. The controller persists the
    provider clone ID on `VMClone.status.targetVMID` so that — even across a
    requeue, or a race with the VirtualMachine controller reconciling the
    freshly-created adopted CR — it can reliably seed the produced VM's
    `Status.ID` and finish the binding. This is an idempotency anchor, not
    something you set.

## Lifecycle and cleanup semantics

!!! danger "Deleting a VMClone does NOT delete the produced VM"
    The VMClone is a one-shot *operation* resource, not an owner of the
    clone. When you delete a `VMClone`, the controller simply drops its
    finalizer — the produced `VirtualMachine` CR and the underlying
    hypervisor VM are **intentionally preserved**.

    To remove the cloned VM, delete the produced `VirtualMachine` CR
    directly:

    ```bash
    kubectl delete vm my-cloned-vm
    ```

    The VirtualMachine controller then runs its normal finalizer-driven
    cleanup against the provider, as it would for any VM.

`Failed` is terminal for the MVP: once a clone fails (unsupported source,
unsupported linked clone, provider error), the controller short-circuits on
subsequent reconciles. Fix the spec and create a new VMClone rather than
editing the failed one.

## Capability gating and linked clones

Linked clones are gated on the provider's reported capabilities. The
controller reads the provider's `SupportsLinkedClones` flag (via the
capability mechanism) **before** issuing the clone:

- If the provider supports linked clones, the request proceeds and
  `status.actualCloneType` is set to `LinkedClone`.
- If it does not, the clone is failed immediately with reason
  `LinkedCloneUnsupported` — no silent fallback to a full clone.

This is consistent with VirtRigaud's broader stance on provider parity:
features that a provider cannot honor are surfaced honestly rather than
no-op'd. For the authoritative per-provider matrix, see the
[Provider Capabilities Matrix](../../providers/providers-capabilities.md).

!!! note "Capability negotiation"
    v0.3.8 added provider capability reporting on
    `Provider.status.reportedCapabilities` and an opt-in
    `--enforce-provider-capabilities` manager flag (default **off**)
    ([#176](https://github.com/projectbeskar/virtrigaud/pull/176)). The
    linked-clone pre-check above is an intrinsic correctness gate and runs
    regardless of that flag. As of v0.3.9, libvirt reports
    `SupportsLinkedClones=true`, so both linked and full clones are available
    on libvirt-backed VMs.

## Related resources

- **VMSet** — declarative management of multiple VMs. The VMSet controller
  is **not yet active** in v0.3.8; the resource exists but reports
  `Ready=False` with reason `ControllerNotImplemented`. Do not rely on
  replica management yet.
- **VMPlacementPolicy** — reference-only in v0.3.8 (no dedicated
  controller); attached via `spec.placementRef`.

## See also

- [Advanced VM Lifecycle](advanced-lifecycle.md) — reconfiguration,
  snapshots, lifecycle hooks, and the broader lifecycle surface.
- [Provider Capabilities Matrix](../../providers/providers-capabilities.md) —
  which providers support `Clone` and linked clones.
- [VM Migration](../../migration/vm-migration-guide.md) — for moving a VM
  *between* providers (VMClone is same-provider only).
- [`examples/vmclone-basic.yaml`](https://github.com/projectbeskar/virtrigaud/blob/main/examples/vmclone-basic.yaml) —
  the canonical example in the main repo.
