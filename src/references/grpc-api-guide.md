<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Provider gRPC API Guide

This page is the hand-written companion to the generated [Provider gRPC API reference](grpc-api.md). The reference lists every message, field and RPC as defined in `proto/provider/v1/provider.proto`; this page explains how the manager uses the contract and what changed in v0.4.0 and v0.4.1.

## Overview

VirtRigaud providers expose a single gRPC service (`provider.v1.Provider`) over mTLS. The manager connects via the Resolver and client created per-provider. Every outbound RPC call passes through these client interceptors before reaching the provider process (`internal/transport/grpc/client.go`):

- **`requestSentInterceptor`** — marks an RPC that failed before its request was sent (no connection, or a circuit-breaker fast-fail), so the caller can tell it from one whose outcome is unknown. In v0.4.0 this drives the "outcome unknown" handling of `SnapshotCreate`, `ExportDisk` and `ImportDisk` (see [Provider calls whose outcome was lost](#provider-call-outcomes)).
- **`providerRPCMetricsInterceptor`** — records `virtrigaud_provider_rpc_*` Prometheus metrics (call count, latency, error rate) for every RPC. See the [Metrics Catalog](../api-reference/metrics.md).
- **`providerCircuitBreakerInterceptor`** — wraps the call with a half-open circuit breaker. In the production path the circuit breaker is always active; unit tests may pass a `nil` breaker which the interceptor handles transparently. Infrastructure errors count toward the threshold; business answers (`NotFound`, `InvalidArgument`, `FailedPrecondition`, and the host- or VM-scoped reasons listed [below](#error-reasons)) do not.

Task-creating RPCs (`Create`, `Delete`, `Power`, `Reconfigure`, `SnapshotCreate`, `SnapshotDelete`, `SnapshotRevert`, `Clone`, `ImagePrepare`, `ExportDisk`, `ImportDisk`) additionally register the returned `TaskRef` with the **inflight-task tracker**. The controller polls `TaskStatus` until `done=true` or the context is cancelled.

---

## Changes in v0.4.1

**The contract has no field, number, RPC or option change.** The generated Go bindings differ from v0.4.0's only in comments, so a manager and a provider of the two versions interoperate on the wire. What changed is what `provider.proto` and the generated [reference](grpc-api.md) say:

- The comments no longer carry internal tracking references or roadmap wording, and say what each field does today.
- The disk export and import contract comment is attached to `ExportDiskRequest`, and corrects the old statement that `transfer_mode` `auto` is chosen from the providers' capabilities: **the manager resolves `auto` to `relay`**, and no built-in provider implements `direct`. An empty value is treated as `relay`; the `nfs` backend ignores `transfer_mode`.
- `CloneRequest.customize_json` is an **allow-listed subset** of `spec.customization` (`hostname`, `domain`, `userData.cloudInit.inline`, and the fields providers only report as not applied). The fields that hold or commonly hold secret values and that no provider acts on are never included, so a third-party provider no longer receives them. Do not rely on receiving them.
- `CloneRequest.linked` is honoured only by providers that report `supports_linked_clones`: libvirt refuses it, and the Proxmox provider stopped reporting it in v0.4.1 and refuses a linked request.
- `request_token`, `target_vm`, `source_owner` and the other v0.4.0 fields keep their meaning; the comments name the providers that act on each (for example `CreateRequest.owner` is stamped by libvirt, vSphere and Proxmox).

Behaviour that changed without a contract change: the manager now reads `GetCapabilities` again after a provider roll (see [Provider capabilities](../providers/providers-capabilities.md#when-the-status-is-read-v041)); the Proxmox provider answers a VMID race "not performed" (`CREATE_NOT_PERFORMED`) when it can prove it; the libvirt provider answers a clustered export failure it can prove as a definite failure; and the SDK's `gRPC request completed` log carries the `code` and the status message the caller receives. CI checks the contract with `buf breaking` against the pull request's target branch since v0.4.1.

## Changes since v0.3.11

The service has 23 RPCs in v0.4.0 and v0.4.1 (18 in v0.3.11). All changes since v0.3.11 are additive on the wire: new fields use new field numbers, and a provider or manager that does not know a field ignores it. The manager gates each new behaviour on a capability flag the provider reports in `GetCapabilitiesResponse`, so a provider image that predates a flag keeps the old behaviour (or the manager holds the operation; the flag descriptions below say which).

### New RPCs

| RPC | Purpose |
|---|---|
| `ListHosts` / `GetHostInfo` | Host inventory of a clustered provider (`HostInfo`: id, address, allocatable CPU, memory and storage, health, labels, CPU model and features, machine types, emulator version). The `Host` controller calls `GetHostInfo` to fill `Host.status`. Advertised by `supports_clustering`. Single-host providers return `Unimplemented`. |
| `TransferOwner` | Compare-and-swap re-stamp of a VM's owner when a `VirtualMachine` adopts it. Advertised by `supports_owner_transfer` (single-host) and `supports_routed_adoption` (clustered). |
| `DeleteStagedDisk` | Removes a migration's staged object (`nfs` and `s3` backends) after the migration ends. Backends listed in `supported_staged_disk_delete_backends`. |
| `DeleteLandedDisk` | Removes the disk an `ImportDisk` landed for a migration target VM that does not use it. Advertised by `supports_landed_disk_delete`. |

`ListVMs` existed before; it now takes an optional owner filter (`owner_namespace`, `owner_name`) and answers with `owner_filter_applied` and `unreachable_host_ids`, and each `VMInfo` carries `host_id` and the owner namespace and name when the provider can read the owner stamp.

### New request and response fields

- **`ObjectIdentity` (`uid`, `namespace`, `name`)** is the new message that names the Kubernetes object a call is made for. `owner` (the `VirtualMachine`) is sent on `Create`, `Delete`, `Power`, `Reconfigure`, `Describe`, `SnapshotCreate`, `SnapshotDelete`, `SnapshotRevert`, `ExportDisk`, `GetDiskInfo` and `TransferOwner`; `CloneRequest` carries `source_owner` and `target_vm`, `ImportDiskRequest` carries `target_vm`. A provider that stamps owners answers `NOT_FOUND` with reason `VM_NOT_OWNED` when the VM at the id belongs to another owner.
- **`target_host_id`** is sent on every per-VM request to a clustered provider (the VM's bound host, `VirtualMachine.status.placement.host`); a clustered provider rejects an empty value with `InvalidArgument`. `HardwareUpgradeRequest.target_host_id` is reserved: the manager has no caller for that RPC. `CloneRequest` adds `source_host_id` and `target_host_id`. Single-host providers ignore these fields.
- **`TaskResponse.restart_required` and `honest_result`**: a `Reconfigure` that changed only the persistent definition says so (`Reconfiguring=True/RestartRequired`); `honest_result` is the per-response proof of `supports_honest_reconfigure`.
- **`DescribeResponse.max_memory_mib` and `vcpus`**: the VM's memory ceiling and vCPU count, used by the clustered scheduler's committed-capacity accounting.
- **`SnapshotCreateRequest.request_token`**: carries the UID of the `VMSnapshot` the snapshot is made for. A clustered libvirt provider records it with the snapshot, so a re-sent create finds the snapshot an earlier attempt made and a same-named snapshot of another request is `ALREADY_EXISTS`; other providers ignore it.
- **`ImagePrepareRequest`** adds `image`, `source_digest` and `provider` (identity of the `VMImage` and the Provider), and `ImagePrepareResponse.artifact` (`PreparedArtifact`: name, image identity, source digest, `reused`). `target_name` may now be empty. See [ADR-0009](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/adr/0009-prepared-image-artifact-identity.md) (advertised by `supports_image_artifact_identity`).
- **`ImportDiskRequest.max_virtual_size_bytes`**: the administrator disk-size limit the provider enforces on the disk it lands (`supports_import_size_limit`).
- **`GetDiskInfoResponse.disks`** (`DiskCapacity`: disk id, path, virtual size): the size of every disk, for the disk-size limit checks.

### New capability flags

`GetCapabilitiesResponse` fields 17-30: `supports_clustering`, `supports_image_artifact_identity`, `supports_honest_reconfigure`, `supports_routed_clone`, `supports_routed_adoption`, `supports_list_owner_filter`, `supported_staged_disk_delete_backends`, `supports_import_size_limit`, `supports_owner_transfer`, `supports_owner_rebind`, `resend_safe_export_backends`, `resend_safe_import_backends`, `supports_landed_disk_delete`, `supports_routed_import`. The [capability matrix](../providers/providers-capabilities.md#provider-capability-flags-for-clustered-and-security-contracts) says which provider reports which.

<a name="error-reasons"></a>
### Error reasons

Providers attach a `google.rpc.ErrorInfo` (domain `provider.virtrigaud.io`) to answers the manager must tell apart. The constants are in `internal/providers/contracts/errors.go`.

| Reason | gRPC code | Meaning |
|---|---|---|
| `HOST_UNAVAILABLE` | `Unavailable` | One host of a clustered provider does not answer. Kept out of the circuit breaker. Shown as `Ready=False/HostUnavailable`. |
| `VM_OPERATION_FAILED` | (the call's own) | The call reached the VM's host and failed there; kept out of the circuit breaker. |
| `VM_OUTCOME_UNKNOWN_RETRY` | `Unavailable` | A clustered call may have changed the host and its outcome is unknown; safe to repeat but not "nothing done". |
| `HOST_CONNECTION_LOST` | (with `VM_OPERATION_FAILED`) | The host stopped answering part-way; the manager paces retries as for an unavailable host. |
| `HOST_STORAGE_MISCONFIGURED` | `FailedPrecondition` | The host's storage (for example the libvirt `default` pool path) is not set up as required. |
| `VM_PREVIOUS_INCARNATION` | `AlreadyExists` | A domain stamped for the same namespace and name with another UID exists; the VM is held as `RestorePending`. |
| `VM_NOT_OWNED` | `NotFound` | The VM at the id is stamped with another owner. |
| `OWNER_STAMP_UNREADABLE` | `FailedPrecondition` | The owner stamp cannot be read or names two owners; nothing was changed. |
| `VM_IS_IMAGE_ARTIFACT` | `FailedPrecondition` | The object is a template or prepared-image artifact, not a VM. |
| `VM_DISK_IN_USE` | `FailedPrecondition` | Another VM (a linked clone) depends on this VM's disk. Shown as `DeleteBlocked`. |
| `VM_DISK_CHECK_FAILED` | `Unavailable` | The provider could not verify that no other VM uses the disk; retried. |
| `VM_SOURCE_RUNNING` | `FailedPrecondition` | A libvirt clone needs its source powered off (`SourceMustBePoweredOff`). |
| `RECONFIGURE_NEEDS_POWER_OFF` | `FailedPrecondition` | The change cannot be applied to a running VM (`ResizePendingPowerOff`). |
| `DISK_SIZE_EXCEEDS_LIMIT` / `DISK_SIZE_UNVERIFIABLE` | `FailedPrecondition` | An import above the administrator disk-size limit, or one whose size cannot be read. |
| `IMAGE_ARTIFACT_IN_PROGRESS` | `Unavailable` | Another request is preparing the same image artifact. |
| `IMAGE_SOURCE_UNAVAILABLE` | `Unavailable` | The image source or its content failed; retryable and kept out of the circuit breaker. |
| `CREATE_NOT_PERFORMED` | (Proxmox) | A Proxmox `Create` or `Clone` failed before a VM existed. |

<a name="provider-call-outcomes"></a>
### Calls whose outcome is unknown

The manager records a status marker before `SnapshotCreate`, `ExportDisk`, `ImportDisk` and `SnapshotRevert`. A failure that is not a definite answer (a deadline, or a connection that dropped after the request was written) leaves the marker and holds the object (`SnapshotOutcomeUnknown`, `ExportOutcomeUnknown`, `ImportOutcomeUnknown`) instead of re-sending. A call is re-sent on its own only on a staging backend the provider lists in `resend_safe_export_backends` or `resend_safe_import_backends`. Details: [`docs/provider-call-outcomes.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/docs/provider-call-outcomes.md).

!!! note "Field-level reference"
    Messages, fields and services are in the [generated gRPC API reference](grpc-api.md), built from `proto/provider/v1/provider.proto` at the documented release with `buf generate` (see the Makefile). Field comments in the proto file are the authoritative description of each field.
