<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# vSphere Hardware Version Management

This page is aligned to **VirtRigaud v0.3.6**. It describes how the vSphere
provider's `HardwareUpgrade` gRPC RPC works, what the manager controller
currently does (and does *not*) do with it, and what an operator needs from
vCenter / ESXi for it to succeed.

## What it is, in one sentence

vSphere VMs carry a virtual-hardware compatibility level (`vmx-N`, e.g.
`vmx-21`) that gates which guest features the VM can use. VirtRigaud's vSphere
provider exposes a `HardwareUpgrade` RPC that bumps a VM's `vmx-N` upward, but
only upward — and only when the VM is powered off.

## Source-of-truth references

| Concern | File:Line |
|--------|-----------|
| gRPC RPC declaration | `proto/provider/v1/provider.proto:273` (`rpc HardwareUpgrade(HardwareUpgradeRequest) returns (TaskResponse)`) |
| Request message | `proto/provider/v1/provider.proto:68-71` (`id string`, `target_version int32`) |
| Server implementation | `internal/providers/vsphere/server.go:955-1042` |
| Version-comparator | `internal/providers/vsphere/server.go:1048-1063` (`isNewerHardwareVersion`) |
| Initial-create hardware version | `internal/providers/vsphere/server.go:2347` (Create-time path uses `spec.HardwareVersion`); `internal/providers/vsphere/server.go:2019` (`extraConfig: vsphere.hardwareVersion`) |
| govmomi version | `go.mod:24` — `github.com/vmware/govmomi v0.52.0` |

## What the RPC does

`HardwareUpgrade(id, target_version int32)` in
`internal/providers/vsphere/server.go:966`:

1. Resolves the VM by `id` (a vSphere `ManagedObjectReference.Value`).
2. Confirms the VM is **powered off**. Returns
   `"VM must be powered off for hardware upgrade, current state: <state>"` if
   not (`server.go:994-996`).
3. Reads `config.version` to get the current `vmx-N` (`server.go:1000-1005`).
4. Computes the target as `fmt.Sprintf("vmx-%d", req.TargetVersion)`
   (`server.go:1006`).
5. If `current == target`, returns success without doing anything
   (`server.go:1013-1017`).
6. Otherwise calls `isNewerHardwareVersion(current, target)`. If target is not
   strictly newer, returns
   `"target version <X> is not newer than current version <Y>"`
   (`server.go:1020-1022`). **Downgrades are not supported.**
7. Calls govmomi's `vm.UpgradeVM(ctx, targetVersion)` and waits for the task
   (`server.go:1025-1034`).

The RPC blocks until vCenter reports the upgrade task complete.

## What the manager controller currently does with it

!!! warning "There is no operator-facing controller path that triggers `HardwareUpgrade` in v0.3.6."
    The `HardwareUpgrade` RPC is implemented end-to-end in the vSphere
    provider and reachable over gRPC, but the `VirtualMachineReconciler` in
    `internal/controller/virtualmachine_controller.go` does **not** call it as
    part of normal reconciliation. There is no `VirtualMachine.spec.hardwareVersion`
    field that an operator can mutate to drive an in-place upgrade.

    What *is* honored on **VM creation** is the initial hardware version,
    passed via `VMClass.spec.extraConfig.vsphere.hardwareVersion` and consumed
    at `internal/providers/vsphere/server.go:2019`. You set the version at VM
    creation time and it sticks.

    If you need to upgrade an already-created VM today, your options are:

    1. **Out-of-band:** upgrade the VM in vCenter directly (right-click → Compatibility → Upgrade VM Compatibility).
    2. **gRPC client:** dial the provider's gRPC endpoint and call `HardwareUpgrade` directly (the RPC and request types are stable per `proto/provider/v1/provider.proto`).

    A controller-driven path (a CRD field plus a reconciler call) is on the
    roadmap.

## Hardware-version compatibility matrix

The mapping between `vmx-N` and ESXi versions is **a vCenter/ESXi property,
not a VirtRigaud one**. VirtRigaud only asks vCenter to perform the upgrade;
vCenter rejects the request if the target is not supported by the ESXi host.

A conservative subset of the matrix below — the rows VirtRigaud has been
exercised against — is informative; the [official VMware
compatibility matrix](https://kb.vmware.com/s/article/1003746) is
authoritative.

| `vmx-N` | ESXi version | Notes |
|---------|--------------|-------|
| 13 | 6.5 | Pre-supported baseline. Hardware features comparable to mid-2010s servers. |
| 14 | 6.7 | Persistent memory exposure, vTPM. |
| 15 | 6.7 U2 | Higher vCPU ceiling. |
| 17 | 7.0 | TPM 2.0 across the board. |
| 18 | 7.0 U1 | Enhanced VMXNET3 features. |
| 19 | 7.0 U2 | PTP precision time, vSphere Bitfusion. |
| 20 | 7.0 U3 | Wider vGPU support. |
| 21 | 8.0 | DPU passthrough, current GA at time of v0.3.6. |

VirtRigaud does **not** keep its own allowlist of `vmx-N` values — any integer
that the underlying govmomi `vm.UpgradeVM` call accepts will succeed.

## Setting the hardware version at VM creation

Set `extraConfig.vsphere.hardwareVersion` on the `VMClass`. The provider reads
it at create time (`internal/providers/vsphere/server.go:2019`):

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: modern-vm-class
spec:
  cpu: 4
  memoryMiB: 8192
  firmware: UEFI
  extraConfig:
    # Quoted string — the provider parses it as an integer internally.
    vsphere.hardwareVersion: "21"
  diskDefaults:
    type: thin
    sizeGiB: 50
```

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: modern-vm
spec:
  providerRef:
    name: vsphere-provider
    namespace: virtrigaud-system
  classRef:
    name: modern-vm-class
  imageRef:
    name: ubuntu-22-04
```

If `extraConfig.vsphere.hardwareVersion` is unset, the provider does not pass a
`Version` to govmomi and vCenter picks its default for the targeted ESXi.

## Upgrading an existing VM out-of-band (workaround for v0.3.6)

This is the gRPC-direct path described above. Useful when you have a fleet of
existing VMs at `vmx-15` and want to bump them to `vmx-21` without recreating
them through the manager.

Prerequisites:

1. The VM must be **powered off** — set
   `VirtualMachine.spec.powerState: Off` and wait for the reconciler to
   confirm `status.powerState: Off`.
2. The destination ESXi must support the target `vmx-N`.
3. You need network reach to the vSphere provider's gRPC endpoint
   (typically `provider-vsphere.virtrigaud-system.svc:9090` cluster-internally,
   or whatever the chart exposes).
4. You must satisfy the provider's auth requirements at the gRPC layer.

!!! danger "Provider gRPC servers do not enforce auth in v0.3.6 (#148)"
    The in-tree provider mains do not enable `Auth.RequireTLS` or
    `BearerTokenAuth` from the SDK middleware (`sdk/provider/middleware/middleware.go:81-94`).
    The compensating control is a `NetworkPolicy` that restricts ingress to
    the provider pod to the manager pod only (see
    [Network Policies](../providers/security/network-policies.md) and
    [Security](security.md)). If you call the provider gRPC endpoint
    directly from your own tool, **only do so from a pod that the
    NetworkPolicy permits**.

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
    // v0.3.6: gRPC channel is plaintext. mTLS not wired (#147).
    conn, err := grpc.NewClient(endpoint, grpc.WithTransportCredentials(insecure.NewCredentials()))
    if err != nil {
        return fmt.Errorf("dial provider: %w", err)
    }
    defer conn.Close()

    client := providerv1.NewProviderClient(conn)

    req := &providerv1.HardwareUpgradeRequest{
        Id:            vmID,                  // vSphere ManagedObjectReference.Value
        TargetVersion: targetVersion,         // e.g. 21 → "vmx-21"
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

The `vmID` is the value of
`VirtualMachine.status.id` on the VirtRigaud `VirtualMachine` CR (it
mirrors the vSphere managed-object-reference value).

## Operational guidance

- **Snapshot first.** vCenter's own upgrade flow recommends a snapshot. You
  can use the [VMSnapshot](../references/generated-crd-docs.md#vmsnapshot) CR
  to create one through VirtRigaud before invoking the RPC.
- **Be conservative.** Pick the lowest `vmx-N` your guest OS and the
  destination ESXi support. Bumping to `vmx-21` on a cluster that still has
  some 7.0 ESXi hosts will prevent that VM from running on the older hosts.
- **One-way.** Once upgraded, you cannot downgrade through this RPC. The
  vCenter UI also does not offer a downgrade path; you'd need to clone the VM
  to a new VM at the lower version.
- **Verify after upgrade.** `kubectl get vm <name> -o jsonpath='{.status.provider}'`
  surfaces what the provider reported back. The authoritative source is
  `config.version` in vCenter.

## Troubleshooting

| Error string | Why | Fix |
|-------------|-----|-----|
| `VM must be powered off for hardware upgrade, current state: poweredOn` (`server.go:995`) | Hardware upgrade can only be issued against a powered-off VM. | Set `spec.powerState: Off`, wait for reconcile, retry. |
| `target version vmx-N is not newer than current version vmx-M` (`server.go:1021`) | The `target_version` is the same as or lower than the current version. | Pick a higher integer. Downgrades are not supported through this RPC. |
| `failed to start hardware upgrade: <govmomi error>` (`server.go:1027`) | vCenter rejected the upgrade — usually because the target `vmx-N` is not supported by the host or by the guest OS hardware family. | Check vCenter compatibility for the host the VM is registered on. |
| `failed to check VM power state: ...` / `failed to get VM properties: ...` | The vSphere session has expired or `id` is wrong. | Check the [Resilience](resilience.md) page; the CircuitBreaker will surface the underlying session failure. Re-check the VirtualMachine `status.id`. |

## Cross-references

- [Providers / vSphere](../providers/vsphere.md) — overall vSphere provider
  documentation, including authentication, datastore selection, and
  capability flags.
- [Provider Capabilities Matrix](../providers/providers-capabilities.md) —
  what each provider can and cannot do.
- [Resilience](resilience.md) — what happens when the vSphere session is
  unhealthy (the CircuitBreaker takes the provider offline cleanly).
- [Operations / Security](security.md) — credential flow into the vSphere
  provider and what compensations are needed because gRPC auth is not wired.
