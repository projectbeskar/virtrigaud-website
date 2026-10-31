<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# vSphere Hardware Version Management

This page is aligned to **VirtRigaud v0.4.2**. It describes how the vSphere
provider's `HardwareUpgrade` gRPC RPC works, what the manager controller
currently does (and does *not*) do with it, how to set a hardware version when a
VM is created, and what an operator needs from vCenter / ESXi for it to succeed.

## What it is, in one sentence

vSphere VMs carry a virtual-hardware compatibility level (`vmx-N`, e.g.
`vmx-21`) that gates which guest features the VM can use. VirtRigaud's vSphere
provider exposes a `HardwareUpgrade` RPC that bumps a VM's `vmx-N` upward, but
only upward, and only when the VM is powered off.

## Source-of-truth references

| Concern | Where |
|--------|-----------|
| gRPC RPC declaration | `proto/provider/v1/provider.proto`: `rpc HardwareUpgrade(HardwareUpgradeRequest) returns (TaskResponse)` |
| Request message | `HardwareUpgradeRequest`: `id` (string), `target_version` (int32), `target_host_id` (string, used only by clustered providers; the vSphere provider ignores it) |
| Server implementation | `internal/providers/vsphere/server.go`: `(*Provider).HardwareUpgrade` and `isNewerHardwareVersion` |
| Template / image-artifact guard | `internal/providers/vsphere/vm_artifact_guard.go` |
| Initial hardware version at create | `internal/providers/vsphere/server.go`: the VMClass `extraConfig` key `vsphere.hardwareVersion` is parsed into the create spec and set as the config spec's `Version` (`vmx-N`) |
| vSphere client library | `github.com/vmware/govmomi` v0.52.0 (`go.mod`) |

## What the RPC does

`HardwareUpgrade(id, target_version int32)` in
`internal/providers/vsphere/server.go`:

1. Resolves the VM by `id` (a vSphere `ManagedObjectReference.Value`). The
   provider still resolves its default datacenter first, so an unresolvable
   datacenter fails the call.
2. Confirms the VM is **powered off**. Returns
   `"VM must be powered off for hardware upgrade, current state: <state>"` if
   not.
3. **Refuses a template or a VirtRigaud prepared-image artifact** (an object
   carrying a `virtrigaud.image.*` key, or one whose configuration cannot be
   read) with `FailedPrecondition` and the reason `VM_IS_IMAGE_ARTIFACT`, before
   changing anything (v0.4.0). The manager maps this to a non-retryable
   `Conflict`.
4. Reads `config.version` to get the current `vmx-N`.
5. Computes the target as `fmt.Sprintf("vmx-%d", req.TargetVersion)`.
6. If `current == target`, returns success without doing anything.
7. Otherwise calls `isNewerHardwareVersion(current, target)`. If the target is
   not strictly newer, returns
   `"target version <X> is not newer than current version <Y>"`.
   **Downgrades are not supported.** (A version string that does not parse as
   `vmx-N` counts as `0`.)
8. Calls govmomi's `vm.UpgradeVM(ctx, targetVersion)` and waits for the task.

The RPC blocks until vCenter reports the upgrade task complete.

## What the manager controller currently does with it

!!! warning "There is no operator-facing controller path that triggers `HardwareUpgrade` in v0.4.0."
    The `HardwareUpgrade` RPC is implemented end-to-end in the vSphere
    provider and reachable over gRPC, but nothing in the manager calls it (no
    controller under `internal/controller/` references it), and there is no
    `VirtualMachine.spec.hardwareVersion` field that an operator can mutate to
    drive an in-place upgrade. The proto even notes that `HardwareUpgrade` has
    no manager-side caller today.

    What *is* honored on **VM creation** is the initial hardware version,
    passed via the `VMClass` `spec.extraConfig` key `vsphere.hardwareVersion`.
    You set the version at VM creation time and it sticks.

    If you need to upgrade an already-created VM today, your options are:

    1. **Out-of-band:** upgrade the VM in vCenter directly (right-click,
       Compatibility, Upgrade VM Compatibility).
    2. **gRPC client:** dial the provider's gRPC endpoint and call
       `HardwareUpgrade` directly (the RPC and request types are in
       `proto/provider/v1/provider.proto`).

## Hardware-version compatibility matrix

The mapping between `vmx-N` and ESXi versions is **a vCenter/ESXi property,
not a VirtRigaud one**. VirtRigaud only asks vCenter to perform the upgrade;
vCenter rejects the request if the target is not supported by the ESXi host.

The rows below follow Broadcom's article
["Virtual machine hardware versions"](https://knowledge.broadcom.com/external/article/315655/virtual-machine-hardware-versions.html),
which is authoritative.

| `vmx-N` | ESXi release |
|---------|--------------|
| 13 | 6.5 |
| 14 | 6.7 |
| 15 | 6.7 U2 |
| 17 | 7.0 |
| 18 | 7.0 U1 |
| 19 | 7.0 U2 |
| 20 | 8.0 |
| 21 | 8.0 U2 |
| 22 | 9.0 |

VirtRigaud does **not** keep its own allowlist or range of `vmx-N` values: the
number is an `int32` that is formatted into `vmx-<N>`, and any value that
vCenter accepts for the host succeeds. The provider validates only that an
upgrade target is strictly newer than the current version. There is no default
version: if none is set at create time, the provider does not pass one and
vCenter chooses.

## Setting the hardware version at VM creation

Set the key `vsphere.hardwareVersion` in the `VMClass` `spec.extraConfig` map
(a flat map of strings; the key itself contains a dot). The provider parses it
as an integer when it builds the create spec and sets the config spec's version
to `vmx-<N>`:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: modern-vm-class
  namespace: default
spec:
  cpu: 4
  memory: 8Gi
  firmware: UEFI
  extraConfig:
    # A quoted string: extraConfig is a map[string]string. The provider parses
    # it as an integer; a value that is not an integer is logged and ignored.
    vsphere.hardwareVersion: "21"
  diskDefaults:
    type: thin
    size: 50Gi
```

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: modern-vm
  namespace: default
spec:
  providerRef:
    name: vsphere-provider
    namespace: virtrigaud-system
  classRef:
    name: modern-vm-class
  imageRef:
    name: ubuntu-22-04
```

!!! note "Cross-namespace references need a grant"
    A `VirtualMachine` that references a `Provider` in another namespace (as above,
    `virtrigaud-system`) only works if that `Provider` sets
    `spec.consumerNamespaceSelector` to select the VM's namespace (v0.4.0; see the
    [Upgrade Guide](upgrade.md#breaking-changes)). The `VMClass` here is in the
    VM's own namespace, so it needs none.

If `vsphere.hardwareVersion` is unset (or invalid), the provider does not pass a
`Version` and vCenter picks its default for the targeted ESXi.

!!! warning "Not verified: how vCenter treats the version on a clone from a template"
    VirtRigaud passes the version in the configuration spec of the VM it creates
    (a clone of the template, or a VM built from an imported disk). The code
    shows what is sent; whether vCenter applies it to a clone, or keeps the
    template's version, is vCenter behaviour that VirtRigaud's tests do not cover.
    Check the VM's compatibility in vCenter after the first create.

## Upgrading an existing VM out-of-band

This is the gRPC-direct path described above. Useful when you have a fleet of
existing VMs at `vmx-15` and want to bump them to a newer version without
recreating them through the manager.

Prerequisites:

1. The VM must be **powered off**: set `VirtualMachine.spec.powerState: Off`
   and wait for the reconciler to confirm `status.powerState: Off`.
2. The destination ESXi must support the target `vmx-N`.
3. You need network reach to the vSphere provider's gRPC endpoint, which is the
   `Service` the manager creates for the `Provider` (its port is
   `spec.runtime.service.port`, 9443 by default).
4. You must satisfy the provider's auth requirements at the gRPC layer.

!!! danger "Provider gRPC endpoints enforce mTLS (v0.3.7+) but not bearer auth"
    Since v0.3.7 the provider gRPC channel **requires mTLS**: a direct caller
    must present a client certificate the provider trusts (constrained by
    `VIRTRIGAUD_PROVIDER_ALLOWED_SANS`), so the plaintext example below only
    applies to a lab provider explicitly opted out of TLS. The in-tree provider
    mains still do **not** enable the SDK's `BearerTokenAuth`
    (`sdk/provider/middleware/middleware.go`), so the compensating control
    for authorization remains a `NetworkPolicy` that restricts ingress to the
    provider pod to the manager pod only (see
    [Network Policies](../providers/security/network-policies.md) and
    [Security](security.md)). If you call the provider gRPC endpoint
    directly from your own tool, **only do so from a pod that the
    NetworkPolicy permits**, and supply the mTLS client material.

Programmatic call (Go):

```go
package main

import (
    "context"
    "fmt"
    "log"

    providerv1 "github.com/projectbeskar/virtrigaud/proto/rpc/provider/v1"
    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
)

func upgradeVMHardwareVersion(endpoint, vmID string, targetVersion int32) error {
    // NOTE: since v0.3.7 the provider enforces mTLS. This insecure dial only
    // works against a lab provider explicitly opted out of TLS
    // (VIRTRIGAUD_PROVIDER_INSECURE=true). For a production provider, build
    // credentials from your client cert/key + the provider CA with
    // credentials.NewTLS(...) instead.
    conn, err := grpc.NewClient(endpoint, grpc.WithTransportCredentials(insecure.NewCredentials()))
    if err != nil {
        return fmt.Errorf("dial provider: %w", err)
    }
    defer conn.Close()

    client := providerv1.NewProviderClient(conn)

    req := &providerv1.HardwareUpgradeRequest{
        Id:            vmID,          // vSphere ManagedObjectReference.Value
        TargetVersion: targetVersion, // e.g. 21 -> "vmx-21"
    }
    resp, err := client.HardwareUpgrade(context.Background(), req)
    if err != nil {
        return fmt.Errorf("HardwareUpgrade failed: %w", err)
    }

    // The RPC blocks until vCenter completes the task.
    log.Printf("HardwareUpgrade returned: %+v", resp)
    return nil
}
```

The `vmID` is the value of `VirtualMachine.status.id` on the VirtRigaud
`VirtualMachine` CR (it mirrors the vSphere managed-object-reference value).

## Operational guidance

- **Snapshot first.** vCenter's own upgrade flow recommends a snapshot. You
  can use the [VMSnapshot](../references/generated-crd-docs.md#vmsnapshot) CR
  to create one through VirtRigaud before invoking the RPC.
- **Be conservative.** Pick the lowest `vmx-N` your guest OS and the
  destination ESXi support. Bumping to a version that older hosts in the cluster
  do not support prevents that VM from running on those hosts.
- **One-way.** Once upgraded, you cannot downgrade through this RPC. The
  vCenter UI also does not offer a downgrade path; you would need to clone the VM
  to a new VM at the lower version.
- **Templates are protected.** The provider refuses to upgrade a template or a
  prepared image (`VM_IS_IMAGE_ARTIFACT`). Upgrade a template in vCenter, or
  convert it to a VM first.
- **Verify after upgrade.** The authoritative source is `config.version` in
  vCenter. `kubectl get virtualmachine <name> -o jsonpath='{.status.provider}'`
  shows what the provider reported back.

## Troubleshooting

| Error string | Why | Fix |
|-------------|-----|-----|
| `VM must be powered off for hardware upgrade, current state: poweredOn` | Hardware upgrade can only be issued against a powered-off VM. | Set `spec.powerState: Off`, wait for reconcile, retry. |
| `VM_IS_IMAGE_ARTIFACT` (`FailedPrecondition`) | The object is a template or carries a VirtRigaud prepared-image stamp. | Upgrade it in vCenter, or use a regular VM. |
| `target version vmx-N is not newer than current version vmx-M` | The `target_version` is the same as or lower than the current version (an unparseable version counts as 0). | Pick a higher integer. Downgrades are not supported through this RPC. |
| `failed to start hardware upgrade: <govmomi error>` | vCenter rejected the upgrade, usually because the target `vmx-N` is not supported by the host or the guest OS hardware family. | Check vCenter compatibility for the host the VM is registered on. |
| `hardware upgrade failed: <govmomi error>` | The upgrade task started and failed. | Read the task error in vCenter. |
| `failed to check VM power state: ...` / `failed to get VM properties: ...` | The vSphere session has expired or `id` is wrong. | The provider keeps the vCenter session alive and reconnects on a real-probe failure (v0.3.8, [#190](https://github.com/projectbeskar/virtrigaud/pull/190)), so transient expiry should self-heal; a persistent failure means `id` is wrong or vCenter is unreachable. Re-check the VirtualMachine `status.id`; see [Resilience](resilience.md#provider-side-connection-resilience-v038). |

## Cross-references

- [Providers / vSphere](../providers/vsphere.md): overall vSphere provider
  documentation, including authentication, datastore selection and capability
  flags.
- [Provider Capabilities Matrix](../providers/providers-capabilities.md): what
  each provider can and cannot do.
- [Resilience](resilience.md): what happens when the vSphere session is
  unhealthy (the CircuitBreaker takes the provider offline cleanly).
- [Operations / Security](security.md): credential flow into the vSphere
  provider and the compensations needed because gRPC bearer auth is not wired.
- [Upgrade Guide](upgrade.md): vSphere privileges and changes in v0.4.0.
