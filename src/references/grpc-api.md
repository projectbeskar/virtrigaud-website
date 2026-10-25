# Protocol Documentation
<a name="top"></a>

## Overview

VirtRigaud providers expose a single gRPC service (`provider.v1.Provider`) over mTLS. The manager connects via the Resolver and client created per-provider. Every outbound RPC call passes through these client interceptors before reaching the provider process (`internal/transport/grpc/client.go`):

- **`requestSentInterceptor`** — marks an RPC that failed before its request was sent (no connection, or a circuit-breaker fast-fail), so the caller can tell it from one whose outcome is unknown. Since v0.4.0-rc2 this drives the "outcome unknown" handling of `SnapshotCreate`, `ExportDisk` and `ImportDisk` (see [Provider calls whose outcome was lost](#provider-call-outcomes)).
- **`providerRPCMetricsInterceptor`** — records `virtrigaud_provider_rpc_*` Prometheus metrics (call count, latency, error rate) for every RPC. See the [Metrics Catalog](../api-reference/metrics.md).
- **`providerCircuitBreakerInterceptor`** — wraps the call with a half-open circuit breaker. In the production path the circuit breaker is always active; unit tests may pass a `nil` breaker which the interceptor handles transparently. Infrastructure errors count toward the threshold; business answers (`NotFound`, `InvalidArgument`, `FailedPrecondition`, and the host- or VM-scoped reasons listed [below](#error-reasons)) do not.

Task-creating RPCs (`Create`, `Delete`, `Power`, `Reconfigure`, `HardwareUpgrade`, `SnapshotCreate`, `SnapshotDelete`, `SnapshotRevert`, `Clone`, `ImagePrepare`, `ExportDisk`, `ImportDisk`) additionally register the returned `TaskRef` with the **inflight-task tracker**. The controller polls `TaskStatus` until `done=true` or the context is cancelled.

---

## Changes since v0.3.11

The service has 23 RPCs in v0.4.0 (18 in v0.3.11). All changes since v0.3.11 are additive on the wire: new fields use new field numbers, and a provider or manager that does not know a field ignores it. The manager gates each new behaviour on a capability flag the provider reports in `GetCapabilitiesResponse`, so a provider image that predates a flag keeps the old behaviour (or the manager holds the operation; the flag descriptions below say which).

### New RPCs

| RPC | Purpose |
|---|---|
| `ListHosts` / `GetHostInfo` | Host inventory of a clustered provider (`HostInfo`: id, address, allocatable CPU, memory and storage, health, labels, CPU model and features, machine types, emulator version). Used by the `Host` and `HostPool` controllers. Advertised by `supports_clustering`. Single-host providers return `Unimplemented`. |
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
- **`ImagePrepareRequest`** adds `image`, `source_digest` and `provider` (identity of the `VMImage` and the Provider), and `ImagePrepareResponse.artifact` (`PreparedArtifact`: name, image identity, source digest, `reused`). `target_name` may now be empty. See [ADR-0009](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/adr/0009-prepared-image-artifact-identity.md) (advertised by `supports_image_artifact_identity`).
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

The manager records a status marker before `SnapshotCreate`, `ExportDisk`, `ImportDisk` and `SnapshotRevert`. A failure that is not a definite answer (a deadline, or a connection that dropped after the request was written) leaves the marker and holds the object (`SnapshotOutcomeUnknown`, `ExportOutcomeUnknown`, `ImportOutcomeUnknown`) instead of re-sending. A call is re-sent on its own only on a staging backend the provider lists in `resend_safe_export_backends` or `resend_safe_import_backends`. Details: [`docs/provider-call-outcomes.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/provider-call-outcomes.md).

!!! note "Generated reference"
    The message and service tables below are generated from `proto/provider/v1/provider.proto` at v0.4.0 with `buf generate` (see the Makefile). Field comments in the proto file are the authoritative description of each field.

---

## Table of Contents

- [provider/v1/provider.proto](#provider_v1_provider-proto)
    - [CloneRequest](#provider-v1-CloneRequest)
    - [CloneResponse](#provider-v1-CloneResponse)
    - [CreateRequest](#provider-v1-CreateRequest)
    - [CreateResponse](#provider-v1-CreateResponse)
    - [DeleteLandedDiskRequest](#provider-v1-DeleteLandedDiskRequest)
    - [DeleteLandedDiskResponse](#provider-v1-DeleteLandedDiskResponse)
    - [DeleteRequest](#provider-v1-DeleteRequest)
    - [DeleteStagedDiskRequest](#provider-v1-DeleteStagedDiskRequest)
    - [DeleteStagedDiskRequest.CredentialsEntry](#provider-v1-DeleteStagedDiskRequest-CredentialsEntry)
    - [DeleteStagedDiskResponse](#provider-v1-DeleteStagedDiskResponse)
    - [DescribeRequest](#provider-v1-DescribeRequest)
    - [DescribeResponse](#provider-v1-DescribeResponse)
    - [DiskCapacity](#provider-v1-DiskCapacity)
    - [DiskInfo](#provider-v1-DiskInfo)
    - [Empty](#provider-v1-Empty)
    - [ExportDiskRequest](#provider-v1-ExportDiskRequest)
    - [ExportDiskRequest.CredentialsEntry](#provider-v1-ExportDiskRequest-CredentialsEntry)
    - [ExportDiskResponse](#provider-v1-ExportDiskResponse)
    - [GetCapabilitiesRequest](#provider-v1-GetCapabilitiesRequest)
    - [GetCapabilitiesResponse](#provider-v1-GetCapabilitiesResponse)
    - [GetDiskInfoRequest](#provider-v1-GetDiskInfoRequest)
    - [GetDiskInfoResponse](#provider-v1-GetDiskInfoResponse)
    - [GetDiskInfoResponse.MetadataEntry](#provider-v1-GetDiskInfoResponse-MetadataEntry)
    - [GetHostInfoRequest](#provider-v1-GetHostInfoRequest)
    - [HardwareUpgradeRequest](#provider-v1-HardwareUpgradeRequest)
    - [HostInfo](#provider-v1-HostInfo)
    - [HostInfo.LabelsEntry](#provider-v1-HostInfo-LabelsEntry)
    - [ImagePrepareRequest](#provider-v1-ImagePrepareRequest)
    - [ImagePrepareResponse](#provider-v1-ImagePrepareResponse)
    - [ImportDiskRequest](#provider-v1-ImportDiskRequest)
    - [ImportDiskRequest.CredentialsEntry](#provider-v1-ImportDiskRequest-CredentialsEntry)
    - [ImportDiskResponse](#provider-v1-ImportDiskResponse)
    - [ListHostsRequest](#provider-v1-ListHostsRequest)
    - [ListHostsResponse](#provider-v1-ListHostsResponse)
    - [ListVMsRequest](#provider-v1-ListVMsRequest)
    - [ListVMsResponse](#provider-v1-ListVMsResponse)
    - [NetworkInfo](#provider-v1-NetworkInfo)
    - [ObjectIdentity](#provider-v1-ObjectIdentity)
    - [PowerRequest](#provider-v1-PowerRequest)
    - [PreparedArtifact](#provider-v1-PreparedArtifact)
    - [ReconfigureRequest](#provider-v1-ReconfigureRequest)
    - [SnapshotCreateRequest](#provider-v1-SnapshotCreateRequest)
    - [SnapshotCreateResponse](#provider-v1-SnapshotCreateResponse)
    - [SnapshotDeleteRequest](#provider-v1-SnapshotDeleteRequest)
    - [SnapshotRevertRequest](#provider-v1-SnapshotRevertRequest)
    - [TaskRef](#provider-v1-TaskRef)
    - [TaskResponse](#provider-v1-TaskResponse)
    - [TaskStatusRequest](#provider-v1-TaskStatusRequest)
    - [TaskStatusResponse](#provider-v1-TaskStatusResponse)
    - [TransferOwnerRequest](#provider-v1-TransferOwnerRequest)
    - [TransferOwnerResponse](#provider-v1-TransferOwnerResponse)
    - [VMInfo](#provider-v1-VMInfo)
    - [VMInfo.ProviderRawEntry](#provider-v1-VMInfo-ProviderRawEntry)
    - [ValidateRequest](#provider-v1-ValidateRequest)
    - [ValidateResponse](#provider-v1-ValidateResponse)
  
    - [HostHealth](#provider-v1-HostHealth)
    - [LandedDiskDeleteOutcome](#provider-v1-LandedDiskDeleteOutcome)
    - [PowerOp](#provider-v1-PowerOp)
    - [StagedDiskDeleteOutcome](#provider-v1-StagedDiskDeleteOutcome)
  
    - [Provider](#provider-v1-Provider)
  
- [Scalar Value Types](#scalar-value-types)



<a name="provider_v1_provider-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## provider/v1/provider.proto



<a name="provider-v1-CloneRequest"></a>

### CloneRequest
Clone operations


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| source_vm_id | [string](#string) |  |  |
| target_name | [string](#string) |  |  |
| linked | [bool](#bool) |  | Best-effort linked clone |
| class_json | [string](#string) |  | JSON-encoded specifications for customization

VMClass overrides |
| placement_json | [string](#string) |  | Placement hints |
| customize_json | [string](#string) |  | Customization spec |
| source_host_id | [string](#string) |  | source_host_id names the host the SOURCE VM runs on for a clustered (&#34;brain-in-operator&#34;) provider (ADR-0007 Addendum A, A1): the source VM&#39;s confirmed binding (status.placement.host). It is the routing field for the clone. It is deliberately NOT target_host_id, which keeps the meaning the main ADR gives it: the host where the clone lands. In v1 a clustered provider requires the two to be equal (disks are host-local and a linked clone depends on its source disk). AGNOSTIC. Additive and backward-compatible: single-host and thin-client providers ignore it, and the operator never sends it to them; a clustered provider REQUIRES it and rejects an empty value with InvalidArgument rather than defaulting to some host. |
| target_vm | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | target_vm names the Kubernetes VirtualMachine the clone will be bound to: its namespace (VMClone spec.target.namespace, defaulted to the VMClone&#39;s namespace) and its name (== target_name). A provider whose VM names are host-global names the clone from it (the libvirt provider: &#34;&lt;namespace&gt;.&lt;name&gt;&#34;, the same rule as Create) and returns that name as target_vm_id, which the operator records as the VM&#39;s status.id; an unset value keeps the legacy target_name naming. The operator creates that VirtualMachine before the clone and sends its uid on every topology (rc2 R4; a manager older than rc2 sent no uid to a single-host provider). A provider stamps the clone with a uid it receives, as Create stamps with CreateRequest.owner, and answers a Clone whose target name already holds a clone stamped with that uid with that clone (a re-sent Clone) instead of a second one; any other VM of the target name it would bind is refused with AlreadyExists. Without a uid the clone is unstamped and nothing is re-bound, as before. A clustered provider requires the uid. |
| target_host_id | [string](#string) |  | target_host_id names the host where the clone LANDS on a clustered (&#34;brain-in-operator&#34;) provider (ADR-0007 Addendum A, A1, slice 3): the target VirtualMachine&#39;s status.placement.pendingHost, recorded before the clone is sent. AGNOSTIC. Additive and backward-compatible: single-host and thin-client providers ignore it, and the operator never sends it to them. In v1 a clustered provider REQUIRES it to equal source_host_id (disks are host-local and a linked clone depends on its source disk) and rejects an empty or different value with InvalidArgument; it never lands a clone on a host it chose itself. |
| source_owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | source_owner identifies the VirtualMachine being cloned — the identity CreateRequest.owner stamps onto the source VM (ADR-0007 Addendum A, slice 3). AGNOSTIC. Additive and backward-compatible. A clustered provider reads (and copies the disk of) a source VM ONLY when its recorded owner uid equals this uid; any other VM is reported NOT_FOUND and none of its disks or definition is read. The operator sends it on every clone of a source VirtualMachine with a UID, single-host included; a single-host Proxmox provider checks it as described for PowerRequest.owner, before anything is cloned (a source config it cannot read is UNAVAILABLE with CREATE_NOT_PERFORMED and VM_OPERATION_FAILED). Other single-host providers ignore it. |






<a name="provider-v1-CloneResponse"></a>

### CloneResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| target_vm_id | [string](#string) |  |  |
| task | [TaskRef](#provider-v1-TaskRef) |  |  |






<a name="provider-v1-CreateRequest"></a>

### CreateRequest
Create a new virtual machine


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| name | [string](#string) |  |  |
| user_data | [bytes](#bytes) |  | Already rendered cloud-init/ignition data |
| meta_data | [bytes](#bytes) |  | Cloud-init metadata (YAML format) |
| class_json | [string](#string) |  | JSON-encoded provider-agnostic specifications

VMClass |
| image_json | [string](#string) |  | VMImage |
| networks_json | [string](#string) |  | []NetworkAttachment |
| disks_json | [string](#string) |  | []DiskSpec |
| placement_json | [string](#string) |  | Placement |
| tags | [string](#string) | repeated | Tags |
| target_host_id | [string](#string) |  | target_host_id names the specific host a clustered (&#34;brain-in-operator&#34;) provider must create this VM on (ADR-0007 P1, D4). It is the operator scheduler&#39;s binding on the wire — an EXPLICIT field, deliberately NOT buried in placement_json (which stays for external-orchestrator hints such as vSphere cluster/datastore/folder). AGNOSTIC. Additive and backward-compatible: single-host and thin-client providers ignore it, and never receive it; a clustered provider REQUIRES it and rejects an empty value rather than silently defaulting to some host (honesty-first, D9). The operator sets it only when creating a VM whose Provider has topology: cluster. |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the Kubernetes object (the VirtualMachine) this create is performed for. A provider that keys hypervisor VMs by a name that is NOT unique across tenants (libvirt: the bare VirtualMachine name, no namespace) stamps it onto the VM it creates and, when a VM of the requested name already exists, treats the create as an idempotent success ONLY if that VM carries this owner&#39;s uid — otherwise it fails closed with ALREADY_EXISTS rather than silently binding to another tenant&#39;s VM. AGNOSTIC. Additive and backward-compatible: providers that do not key by a shared name ignore it; an unset owner (an older manager) never authorizes binding to an existing VM. The operator sets it on every create from vm.UID/namespace/name. |






<a name="provider-v1-CreateResponse"></a>

### CreateResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | Provider-specific VM identifier |
| task | [TaskRef](#provider-v1-TaskRef) |  | Optional task reference for async operations |






<a name="provider-v1-DeleteLandedDiskRequest"></a>

### DeleteLandedDiskRequest
DeleteLandedDisk removes the disk a VMMigration&#39;s ImportDisk landed on this
(target) provider for target_vm, when the migration ended without a VM that
uses it: it failed for good, or the VMMigration was deleted before (or
without) a target VM that attached the disk (rc2 R7). The manager sends it to
the migration&#39;s TARGET provider, the one the import was sent to.

CONFINEMENT (security-critical). The provider derives the landed disk from
target_vm (namespace and name) with exactly the rule its ImportDisk names it
with — vSphere: the landing folder &#34;[&lt;datastore&gt;] &lt;ns&gt;_&lt;vm&gt;-migrated&#34;;
libvirt: &#34;&lt;default pool&gt;/&lt;ns&gt;.&lt;vm&gt;-migrated.qcow2&#34;; Proxmox: the node-side
import stage &#34;&lt;stage dir&gt;/&lt;ns&gt;_&lt;vm&gt;-migrated.&lt;ext&gt;&#34; — and validates the
identity (namespace a DNS-1123 label, name a DNS-1123 subdomain) before it
touches anything. path, when set, must be exactly that landed disk (it
chooses the vSphere datastore); any other path is InvalidArgument. Nothing
else is ever removed.

It refuses — FailedPrecondition with the ErrorInfo reason VM_DISK_IN_USE,
leaving the disk — when any VM or template on the target uses the disk (or,
on vSphere, any file of its landing folder), and fails closed (a retryable
error, VM_DISK_CHECK_FAILED where it applies) when that cannot be
established.

Idempotent: a disk that does not exist is a success with outcome NOT_FOUND.
A provider answers NOT_FOUND only after it looked: one that cannot look
(Proxmox without its migration SSH data plane) answers FailedPrecondition
without an ErrorInfo reason, which the manager treats like InvalidArgument.
InvalidArgument: a request that can never succeed (a bad identity or path,
or something other than a regular file at the landing name).
Unimplemented: a provider that does not report supports_landed_disk_delete.
Unavailable while an import of the same landing name runs in the provider.
Any other error is retryable.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| migration | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | migration is the VMMigration whose import landed the disk; informational (audit, logs). |
| target_vm | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | target_vm is the VirtualMachine the import landed the disk for (namespace and name; the same identity as ImportDiskRequest.target_vm). Required. |
| path | [string](#string) |  | path is the landing path ImportDisk returned (ImportDiskResponse.path), as the manager recorded it, or empty when no import result was recorded. |
| target_host_id | [string](#string) |  | target_host_id is the host of a CLUSTERED target provider the import landed the disk on (the recorded import target host; ADR-0007 Addendum B, B4). A clustered provider requires it (InvalidArgument when empty), removes the disk on that host only, and scans EVERY host of the Provider for a domain that uses the file (the pool may be shared), failing closed when a host cannot be scanned. Single-host and thin-client providers ignore it. Additive. |






<a name="provider-v1-DeleteLandedDiskResponse"></a>

### DeleteLandedDiskResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| outcome | [LandedDiskDeleteOutcome](#provider-v1-LandedDiskDeleteOutcome) |  |  |






<a name="provider-v1-DeleteRequest"></a>

### DeleteRequest
Delete a virtual machine


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  |  |
| target_host_id | [string](#string) |  | target_host_id names the host a clustered (&#34;brain-in-operator&#34;) provider must run this delete on (ADR-0007 Addendum A, A1): the operator&#39;s confirmed binding (VirtualMachine status.placement.host), threaded on the wire exactly like CreateRequest.target_host_id. AGNOSTIC. Additive and backward-compatible: single-host and thin-client providers ignore it, and the operator never sends it to them; a clustered provider REQUIRES it and rejects an empty value with InvalidArgument rather than defaulting to some host (honesty-first, D9). The provider never looks a VM&#39;s host up by itself (D1). |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the Kubernetes object (the VirtualMachine) this delete is performed for: the same identity CreateRequest.owner stamps onto the VM it creates (ADR-0007 Addendum A, A2). AGNOSTIC. Additive and backward-compatible: single-host and thin-client providers other than Proxmox ignore it (their Delete behavior is unchanged, so a legacy unstamped VM stays deletable). A clustered provider deletes a VM ONLY when its recorded owner uid equals this uid; a VM whose stamp is missing or records a different owner is reported NOT_FOUND and is NEVER destroyed, so a cleanup (e.g. a finalizer after an ALREADY_EXISTS create) can never remove another tenant&#39;s VM. The operator sets it, from vm.UID/namespace/name, on every delete of a VirtualMachine with a UID; a single-host Proxmox provider checks it as described for PowerRequest.owner. |






<a name="provider-v1-DeleteStagedDiskRequest"></a>

### DeleteStagedDiskRequest
DeleteStagedDisk removes the staging object a VMMigration&#39;s ExportDisk wrote
to an nfs or s3 backend — a full, unencrypted copy of a tenant&#39;s disk —
once the migration no longer needs it (ADR-0011). The manager sends it to the
migration&#39;s TARGET provider.

CONFINEMENT (security-critical). The request carries no key, path or URL.
The provider derives the object from migration.namespace, migration.name and
stage with the same layout function the manager uses to build the
ExportDisk/ImportDisk URLs, and validates them (namespace a DNS-1123 label,
name a DNS-1123 subdomain, stage in an allowlist) before it touches the
backend. It therefore can only remove an object named like a VirtRigaud
staging object of that migration, on the backend the request&#39;s
storage_options_json names, with the request&#39;s credentials.

Idempotent: an object that does not exist is a success with outcome
NOT_FOUND. InvalidArgument: a request that can never succeed (a bad identity,
stage, backend or options). Unimplemented: a backend the provider cannot
delete from (it does not list it in supported_staged_disk_delete_backends).
Any other error is retryable.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| migration | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | migration identifies the VMMigration whose staged object is removed. Its namespace and name name the object (see above); uid is informational (audit, logs). |
| stage | [string](#string) |  | stage is the staging stage whose object is removed: &#34;export&#34;, the only stage a migration stages today. |
| backend_type | [string](#string) |  | backend_type is the staging backend: &#34;nfs&#34; or &#34;s3&#34;. |
| storage_options_json | [string](#string) |  | storage_options_json is the same JSON-encoded, non-secret backend options the manager sends with ExportDisk / ImportDisk (ADR-0006). |
| credentials | [DeleteStagedDiskRequest.CredentialsEntry](#provider-v1-DeleteStagedDiskRequest-CredentialsEntry) | repeated | credentials are the backend credentials (s3: the same keys as ExportDiskRequest.credentials). Secret material: never logged. |
| layout | [string](#string) |  | layout is the naming layout the migration&#39;s staged object was written with (ADR-0011 D5), recorded by the manager when the export was sent: &#34;v2&#34; — the nfs file &#34;vmmigrations_&lt;namespace&gt;_&lt;name&gt;_&lt;stage&gt;.qcow2&#34; (&#39;_&#39; appears in no namespace or name, so it is unambiguous); &#34;v1&#34; or empty — the legacy nfs file &#34;vmmigrations-&lt;namespace&gt;-&lt;name&gt;-&lt;stage&gt;.qcow2&#34; of a migration exported before v2. The s3 key is the same in both layouts. Any other value is InvalidArgument. |
| target_vm | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | target_vm is the VirtualMachine the migration&#39;s import landed a disk for (namespace and name; the same identity as ImportDiskRequest.target_vm), set only when the migration sent an import and no other in-flight migration targets the same VM. A provider whose ImportDisk keeps a provider-side copy of the disk until Create (Proxmox: the node-side import stage named after this VM) removes that copy too, confined to its own stage location. Unset: only the staged object is removed. Providers that keep no such copy ignore it. |
| target_host_id | [string](#string) |  | target_host_id is the host of a CLUSTERED target provider the migration&#39;s import was sent to (the recorded import target host; ADR-0007 Addendum B, B4). An nfs staged object is emptied by that host&#39;s qemu-img, so a clustered provider requires it for backend &#34;nfs&#34; (InvalidArgument when empty) and answers an unknown, removed or draining host with Unavailable &#43; HOST_UNAVAILABLE. s3 objects are removed from the provider pod and ignore it. Single-host and thin-client providers ignore it. Additive. |






<a name="provider-v1-DeleteStagedDiskRequest-CredentialsEntry"></a>

### DeleteStagedDiskRequest.CredentialsEntry



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| key | [string](#string) |  |  |
| value | [string](#string) |  |  |






<a name="provider-v1-DeleteStagedDiskResponse"></a>

### DeleteStagedDiskResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| outcome | [StagedDiskDeleteOutcome](#provider-v1-StagedDiskDeleteOutcome) |  |  |






<a name="provider-v1-DescribeRequest"></a>

### DescribeRequest
Describe virtual machine current state


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  |  |
| target_host_id | [string](#string) |  | target_host_id names the host a clustered (&#34;brain-in-operator&#34;) provider must run this describe on (ADR-0007 Addendum A, A1): the operator&#39;s confirmed binding (VirtualMachine status.placement.host), threaded on the wire exactly like CreateRequest.target_host_id. AGNOSTIC. Additive and backward-compatible: single-host and thin-client providers ignore it, and the operator never sends it to them; a clustered provider REQUIRES it and rejects an empty value with InvalidArgument rather than defaulting to some host (honesty-first, D9). The provider never looks a VM&#39;s host up by itself (D1). |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the Kubernetes object (the VirtualMachine) this describe is performed for — the identity CreateRequest.owner stamps onto the VM (ADR-0007 Addendum A). AGNOSTIC. Additive and backward-compatible. A clustered provider reports a VM whose stamp is missing or records a different owner as exists=false and returns none of its state, so a VirtualMachine can never read another tenant&#39;s VM that took over the name on its host (the operator then applies its no-recreate rule). The operator sends it on every request for a VirtualMachine with a UID, single-host included. A single-host Proxmox provider checks it the same way against the stamp of the VM at the VMID (VMIDs are reused): a VM stamped with another owner, or unstamped and not named like the owner, is NOT_FOUND with the google.rpc.ErrorInfo reason VM_NOT_OWNED, and a stamp that cannot be read is FAILED_PRECONDITION with OWNER_STAMP_UNREADABLE; an unstamped VM named like the owner (one created before owner stamps, or adopted) is acted on as before. Other single-host providers ignore it. A single-host Describe never answers exists=false for a VM that is not the owner&#39;s (the operator would create the VM again): it answers VM_NOT_OWNED and returns none of the VM&#39;s state. |






<a name="provider-v1-DescribeResponse"></a>

### DescribeResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| exists | [bool](#bool) |  |  |
| power_state | [string](#string) |  |  |
| ips | [string](#string) | repeated |  |
| console_url | [string](#string) |  |  |
| provider_raw_json | [string](#string) |  | Provider-specific additional data |
| max_memory_mib | [int64](#int64) |  | max_memory_mib is the most memory, in MiB, the VM&#39;s guest can use without any action on the host: the memory it was started with, including any balloon headroom above its current allocation (libvirt&#39;s &lt;memory&gt;, the balloon maximum). 0 means the provider does not report it. Additive and backward-compatible. The clustered scheduler records it once as status.placement.memoryCeilingMiB for a VM scheduled before that field existed, raises a recorded ceiling to it when it is higher, and lowers a recorded ceiling to it once the provider reports less (ADR-0007 Addendum A, scheduler-accuracy amendment). |
| vcpus | [int32](#int32) |  | vcpus is the number of vCPUs the VM has online now: the running VM&#39;s count, or, for a VM that is off, the count it boots with. 0 means the provider does not report it. Additive and backward-compatible. The clustered scheduler raises a VM&#39;s recorded CPU (status.currentResources) to it when it is higher, so a VM is never counted below the vCPUs it has (ADR-0007 Addendum A, scheduler-accuracy amendment). |






<a name="provider-v1-DiskCapacity"></a>

### DiskCapacity
DiskCapacity is one disk of a VM and its current virtual size (capacity).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| disk_id | [string](#string) |  | Provider-specific disk identifier |
| path | [string](#string) |  | Path or location, when the provider has one |
| virtual_size_bytes | [int64](#int64) |  | Virtual size (capacity); 0 = not read |






<a name="provider-v1-DiskInfo"></a>

### DiskInfo



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | Disk identifier |
| path | [string](#string) |  | Disk path |
| size_gib | [int32](#int32) |  | Disk size in GiB |
| format | [string](#string) |  | Disk format (qcow2, vmdk, raw, etc.) |






<a name="provider-v1-Empty"></a>

### Empty
Empty message for operations with no parameters






<a name="provider-v1-ExportDiskRequest"></a>

### ExportDiskRequest
Disk export operations for migration


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| vm_id | [string](#string) |  | VM identifier |
| disk_id | [string](#string) |  | Disk identifier (optional, defaults to primary disk) |
| snapshot_id | [string](#string) |  | Snapshot to export from (optional) |
| destination_url | [string](#string) |  | Where to upload the disk (S3, HTTP, etc.) |
| format | [string](#string) |  | Desired export format (qcow2, vmdk, raw) |
| compress | [bool](#bool) |  | Enable compression during export |
| credentials | [ExportDiskRequest.CredentialsEntry](#provider-v1-ExportDiskRequest-CredentialsEntry) | repeated | Credentials for destination (access keys, tokens) |
| backend_type | [string](#string) |  | Staging backend: &#34;pvc&#34; | &#34;nfs&#34; | &#34;s3&#34;; empty == legacy pvc (ADR-0006) |
| transfer_mode | [string](#string) |  | Transfer mode: &#34;auto&#34; | &#34;relay&#34; | &#34;direct&#34; (ADR-0006) |
| storage_options_json | [string](#string) |  | JSON-encoded backend-specific options (ADR-0006; empty in Slice 0) |
| target_host_id | [string](#string) |  | target_host_id names the host a clustered (&#34;brain-in-operator&#34;) provider must run this disk export on (ADR-0007 Addendum A, A1): the operator&#39;s confirmed binding (VirtualMachine status.placement.host), threaded on the wire exactly like CreateRequest.target_host_id. AGNOSTIC. Additive and backward-compatible: single-host and thin-client providers ignore it, and the operator never sends it to them; a clustered provider REQUIRES it and rejects an empty value with InvalidArgument rather than defaulting to some host (honesty-first, D9). The provider never looks a VM&#39;s host up by itself (D1). |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the VirtualMachine whose disk is exported (ADR-0007 Addendum A, slice 3), exactly as SnapshotCreateRequest.owner. A clustered provider exports a disk ONLY of a VM whose recorded owner uid equals this uid; any other VM is reported NOT_FOUND and none of its disks is read. Sent and checked on single-host requests as SnapshotCreateRequest.owner, before any disk is read or copied. |






<a name="provider-v1-ExportDiskRequest-CredentialsEntry"></a>

### ExportDiskRequest.CredentialsEntry



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| key | [string](#string) |  |  |
| value | [string](#string) |  |  |






<a name="provider-v1-ExportDiskResponse"></a>

### ExportDiskResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| export_id | [string](#string) |  | Export operation identifier |
| task | [TaskRef](#provider-v1-TaskRef) |  | Task reference for async tracking |
| estimated_size_bytes | [int64](#int64) |  | Estimated size of export |
| checksum | [string](#string) |  | Checksum of exported disk (SHA256) |






<a name="provider-v1-GetCapabilitiesRequest"></a>

### GetCapabilitiesRequest
Capability check - what features does this provider support






<a name="provider-v1-GetCapabilitiesResponse"></a>

### GetCapabilitiesResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| supports_reconfigure_online | [bool](#bool) |  |  |
| supports_disk_expansion_online | [bool](#bool) |  |  |
| supports_snapshots | [bool](#bool) |  |  |
| supports_memory_snapshots | [bool](#bool) |  |  |
| supports_linked_clones | [bool](#bool) |  |  |
| supports_image_import | [bool](#bool) |  |  |
| supported_disk_types | [string](#string) | repeated |  |
| supported_network_types | [string](#string) | repeated |  |
| supports_disk_export | [bool](#bool) |  | Can export disks for migration |
| supports_disk_import | [bool](#bool) |  | Can import disks from external sources |
| supported_export_formats | [string](#string) | repeated | Supported export formats (qcow2, vmdk, raw) |
| supported_import_formats | [string](#string) | repeated | Supported import formats |
| supports_export_compression | [bool](#bool) |  | Supports compression during export |
| supported_export_backends | [string](#string) | repeated | Export staging backends: &#34;pvc&#34;|&#34;nfs&#34;|&#34;s3&#34; (ADR-0006; empty == pvc-only) |
| supported_import_backends | [string](#string) | repeated | Import staging backends: &#34;pvc&#34;|&#34;nfs&#34;|&#34;s3&#34; (ADR-0006; empty == pvc-only) |
| supported_transfer_modes | [string](#string) | repeated | Transfer modes: &#34;relay&#34;|&#34;direct&#34; (ADR-0006; empty == relay-only) |
| supports_clustering | [bool](#bool) |  | Provider fronts multiple hosts and implements host inventory (ListHosts/GetHostInfo) &#43; host-targeted placement (ADR-0007 P1, D7). The remaining clustering flags (live/block migration, host evacuation, storage modes) are added by the migration slice. |
| supports_image_artifact_identity | [bool](#bool) |  | supports_image_artifact_identity reports that ImagePrepare implements the prepared-image artifact identity contract (ADR-0009 D7): it accepts ImagePrepareRequest.image/source_digest/provider with an empty target_name, names and stamps artifacts from that identity, never reuses an artifact by bare name, and echoes the stamp in ImagePrepareResponse.artifact. A manager holds import-style prepares through a provider that supports image import but does not advertise this. |
| supports_honest_reconfigure | [bool](#bool) |  | supports_honest_reconfigure reports that Reconfigure implements the honest result contract: every requested change is applied to the running VM and its persistent definition, or applied to the definition only and reported with TaskResponse.restart_required, or the call fails — it never reports success for a change it did not apply. Additive and backward-compatible: false (the default) from a provider that predates it or does not implement it. A manager holds resizes of VMs on a clustered Provider that does not advertise it (its committed-capacity accounting trusts the result); single-host Providers are resized as before. |
| supports_routed_clone | [bool](#bool) |  | supports_routed_clone reports that a clustered (&#34;brain-in-operator&#34;) provider routes Clone to the source VM&#39;s bound host (ADR-0007 Addendum A, slice 3): it honours source_host_id, target_host_id and source_owner and stamps the clone with target_vm&#39;s uid. The manager checks it BEFORE it creates a clustered clone&#39;s target VirtualMachine. False on single-host and thin-client providers, which do not route clones (their Clone is unaffected), and on a clustered provider older than slice 3. |
| supports_routed_adoption | [bool](#bool) |  | supports_routed_adoption reports that a clustered (&#34;brain-in-operator&#34;) provider lists VMs across all of its hosts — every VMInfo carries its host_id and ListVMsResponse.unreachable_host_ids names every host that could not be listed — and implements TransferOwner, which re-stamps a VM on its host with the VirtualMachine that takes it over (ADR-0007 Addendum A, A3 / slice 4). The manager adopts from a clustered provider only when it reports it. False on single-host and thin-client providers (their ListVMs and adoption do not depend on it) and on a clustered provider older than slice 4. |
| supports_list_owner_filter | [bool](#bool) |  | supports_list_owner_filter reports that ListVMs honours the owner filter (ListVMsRequest.owner_namespace / owner_name): it returns only the VMs of that VirtualMachine — the ones the provider would name for it, or whose owner stamp records its namespace and name — and marks the answer with ListVMsResponse.owner_filter_applied (ADR-0007 A6.2, R4). The manager runs its pre-schedule uniqueness check only through a clustered provider that reports it, and holds a clustered VM&#39;s first placement otherwise. False on single-host and thin-client providers (they never schedule, and ignore the filter) and on a clustered provider older than A6.2. |
| supported_staged_disk_delete_backends | [string](#string) | repeated | supported_staged_disk_delete_backends lists the staging backends (&#34;nfs&#34;, &#34;s3&#34;) whose migration staging objects DeleteStagedDisk can remove (ADR-0011 D7). Empty — a provider that predates it, or one that stages nothing outside the cluster — means the manager never sends DeleteStagedDisk and records the staged object as left behind. |
| supports_import_size_limit | [bool](#bool) |  | supports_import_size_limit reports that ImportDisk enforces ImportDiskRequest.max_virtual_size_bytes on the disk it lands (refusing a larger one with DISK_SIZE_EXCEEDS_LIMIT, or one it cannot measure with DISK_SIZE_UNVERIFIABLE). A provider that predates the field ignores the limit, so while one applies the manager holds a migration into a Provider that does not report it. |
| supports_owner_transfer | [bool](#bool) |  | supports_owner_transfer reports that TransferOwner re-stamps a VM this provider&#39;s ListVMs reported with the VirtualMachine that adopts it, compare-and-swap, in the provider&#39;s own topology: a single-host provider addresses the VM by VMInfo.id alone (target_host_id empty). The manager&#39;s single-host adoption stamps the VMs it adopts only through a provider that reports it; through an older one it adopts them unstamped, as before, and says so in the Provider&#39;s adoption status. A clustered provider reports supports_routed_adoption for its (routed) TransferOwner; this field does not change how a clustered Provider adopts. |
| supports_owner_rebind | [bool](#bool) |  | supports_owner_rebind reports that Create and Clone stamp the VM they make with its owner (CreateRequest.owner, CloneRequest.target_vm with a uid) and that a Create or Clone sent again for the same owner returns the VM an earlier attempt made — never a second one (rc2 R4). The manager sends a Create or Clone whose outcome is unknown again only to a provider that reports it; from any other (one that predates the field, or an older Proxmox image that ignores target_vm) it keeps the earlier behaviour and never re-sends. Field 25 is taken by supports_owner_transfer (PR #392). |
| resend_safe_export_backends | [string](#string) | repeated | resend_safe_export_backends lists the staging backends (&#34;pvc&#34;, &#34;nfs&#34;, &#34;s3&#34;) on which an ExportDisk sent again for the same destination_url, once the deadline of the earlier call has passed, replaces what the earlier call wrote and leaves nothing else behind: the destination is the only durable artifact, the earlier call&#39;s writes have stopped by its deadline (cancellation honoured, or the write is atomic), and any temporary artifact is cleaned up or uniquely named (rc2 R6). The manager re-sends an ExportDisk whose outcome it lost (a restart or leader change between the call and the write of its result) only on a backend listed here; on any other — and to a provider image that predates the field — the VMMigration waits for an operator (ExportOutcomeUnknown). Additive. |
| resend_safe_import_backends | [string](#string) | repeated | resend_safe_import_backends is resend_safe_export_backends for ImportDisk: on a listed backend, an ImportDisk sent again for the same target_vm, once the earlier call&#39;s deadline has passed, lands the disk at the same deterministic name (replacing what the earlier call landed, or refusing because a VM uses it) — never a second disk (rc2 R6). |
| supports_landed_disk_delete | [bool](#bool) |  | supports_landed_disk_delete reports that DeleteLandedDisk removes the disk a migration&#39;s ImportDisk landed for a target VM that does not use it (rc2 R7). From a provider that does not report it (one that predates the field) the manager never sends DeleteLandedDisk: it records the landed disk as left behind, with a Warning. Fields 27 and 28 are taken by resend_safe_export_backends / resend_safe_import_backends (PR #402). |
| supports_routed_import | [bool](#bool) |  | supports_routed_import reports that a CLUSTERED provider routes ImportDisk to ImportDiskRequest.target_host_id (with target_vm carrying the target VirtualMachine&#39;s uid), DeleteLandedDisk to DeleteLandedDiskRequest.target_host_id with a cross-host in-use scan, and the nfs DeleteStagedDisk to DeleteStagedDiskRequest.target_host_id (ADR-0007 Addendum B, B5). The manager accepts a clustered Provider as a VMMigration target only when it reports it (read at runtime, the D7 double gate). False on single-host and thin-client providers (their import is not routed) and on a clustered provider older than Addendum B. Additive. |






<a name="provider-v1-GetDiskInfoRequest"></a>

### GetDiskInfoRequest
Get disk information for migration planning


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| vm_id | [string](#string) |  | VM identifier |
| disk_id | [string](#string) |  | Disk identifier (optional, defaults to primary disk) |
| snapshot_id | [string](#string) |  | Get info for specific snapshot (optional) |
| target_host_id | [string](#string) |  | target_host_id names the host a clustered (&#34;brain-in-operator&#34;) provider must run this disk-info read on (ADR-0007 Addendum A, A1): the operator&#39;s confirmed binding (VirtualMachine status.placement.host), threaded on the wire exactly like CreateRequest.target_host_id. AGNOSTIC. Additive and backward-compatible: single-host and thin-client providers ignore it, and the operator never sends it to them; a clustered provider REQUIRES it and rejects an empty value with InvalidArgument rather than defaulting to some host (honesty-first, D9). The provider never looks a VM&#39;s host up by itself (D1). |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the VirtualMachine whose disk is described (ADR-0007 Addendum A, slice 3), exactly as SnapshotCreateRequest.owner. A clustered provider describes a disk ONLY of a VM whose recorded owner uid equals this uid; any other VM is reported NOT_FOUND and none of its disks is read. Sent and checked on single-host requests as SnapshotCreateRequest.owner. |






<a name="provider-v1-GetDiskInfoResponse"></a>

### GetDiskInfoResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| disk_id | [string](#string) |  | Disk identifier |
| format | [string](#string) |  | Disk format (qcow2, vmdk, raw) |
| virtual_size_bytes | [int64](#int64) |  | Virtual size (capacity) |
| actual_size_bytes | [int64](#int64) |  | Actual size (allocated) |
| path | [string](#string) |  | Path or location |
| is_bootable | [bool](#bool) |  | Is this a boot disk |
| snapshots | [string](#string) | repeated | Available snapshots |
| backing_file | [string](#string) |  | Backing file (for linked clones) |
| metadata | [GetDiskInfoResponse.MetadataEntry](#provider-v1-GetDiskInfoResponse-MetadataEntry) | repeated | Additional provider-specific metadata |
| disks | [DiskCapacity](#provider-v1-DiskCapacity) | repeated | disks lists EVERY disk of the VM as it is now — its data disks, not CD-ROM or cloud-init media — each with its current virtual size, whatever disk_id and snapshot_id asked for. The manager checks them against the administrator&#39;s disk-size limit before a clone copies them. A size the provider could not read is 0, which the manager treats as unknown. A provider that predates the field leaves it empty, and the manager then fails closed (it clones nothing through it while a limit applies). Additive and backward-compatible. |






<a name="provider-v1-GetDiskInfoResponse-MetadataEntry"></a>

### GetDiskInfoResponse.MetadataEntry



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| key | [string](#string) |  |  |
| value | [string](#string) |  |  |






<a name="provider-v1-GetHostInfoRequest"></a>

### GetHostInfoRequest
Refresh a single host&#39;s inventory — cheaper than a full ListHosts poll when
reconciling one Host CR. Returns a HostInfo.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| host_id | [string](#string) |  |  |






<a name="provider-v1-HardwareUpgradeRequest"></a>

### HardwareUpgradeRequest
Upgrade VM hardware version


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  |  |
| target_version | [int32](#int32) |  | Target hardware version (e.g., 21) |
| target_host_id | [string](#string) |  | target_host_id names the host a clustered (&#34;brain-in-operator&#34;) provider must run this hardware upgrade on (ADR-0007 Addendum A, A1): the operator&#39;s confirmed binding (VirtualMachine status.placement.host), threaded on the wire exactly like CreateRequest.target_host_id. AGNOSTIC. Additive and backward-compatible: single-host and thin-client providers ignore it, and the operator never sends it to them; a clustered provider REQUIRES it and rejects an empty value with InvalidArgument rather than defaulting to some host (honesty-first, D9). The provider never looks a VM&#39;s host up by itself (D1). HardwareUpgrade has no manager-side caller today; the field is reserved on the wire so a later slice can route it without another proto change. |






<a name="provider-v1-HostInfo"></a>

### HostInfo
HostInfo describes one hypervisor host in a clustered provider&#39;s inventory.
The shape is hypervisor-AGNOSTIC; the SOURCE of each value is per-hypervisor
(e.g. libvirt reads `virsh nodeinfo` / `domcapabilities`, and statvfs of the
`default` pool&#39;s directory via `virsh pool-dumpxml` &#43; `stat -f`). See
ADR-0007 for the full agnostic-vs-per-hypervisor breakdown.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | Operator-assigned host id (== Host CR name). AGNOSTIC. |
| address | [string](#string) |  | SSH endpoint / agent address. AGNOSTIC. |
| allocatable_cpu | [int32](#int32) |  | Allocatable vCPUs. AGNOSTIC shape; per-HV source. |
| allocatable_mem_mib | [int64](#int64) |  | Allocatable memory in MiB. AGNOSTIC shape; per-HV source. |
| allocatable_storage | [int64](#int64) |  | Allocatable storage in bytes. Per-HV (per-pool vs host-fs). |
| health | [HostHealth](#provider-v1-HostHealth) |  | Health probe result. AGNOSTIC enum; per-HV probe. |
| labels | [HostInfo.LabelsEntry](#provider-v1-HostInfo-LabelsEntry) | repeated | Scheduling constraints (storage-pool/network visibility, zone/rack). AGNOSTIC. |
| cpu_model | [string](#string) |  | Baseline CPU model. Per-HV interpretation. |
| cpu_features | [string](#string) | repeated | CPU feature flags. Per-HV. |
| machine_types | [string](#string) | repeated | Supported machine types. Per-HV. |
| emulator_version | [string](#string) |  | Emulator/hypervisor version. Per-HV. |






<a name="provider-v1-HostInfo-LabelsEntry"></a>

### HostInfo.LabelsEntry



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| key | [string](#string) |  |  |
| value | [string](#string) |  |  |






<a name="provider-v1-ImagePrepareRequest"></a>

### ImagePrepareRequest
Image preparation operations

Prepared-image artifact identity (ADR-0009). A manager that knows the
VMImage&#39;s identity sets image, source_digest and provider, and sends an EMPTY
target_name. The provider derives the hypervisor-side artifact name from
image.uid and source_digest (ADR-0009 D1; the naming rule belongs to the
provider), stamps every artifact it prepares with that identity (D3), and
reuses an existing artifact only when its stamp carries the same image.uid
and source_digest; anything else at the derived name is refused with
AlreadyExists and is never overwritten or adopted (D4).

A request with no image is a request from an older manager. It must carry
target_name and is served in deprecated legacy mode (bare-name naming and
reuse by name, no artifact echo) for one release only; the provider logs a
warning and increments
virtrigaud_provider_image_prepare_legacy_requests_total{provider_type}. The
next release refuses it with FailedPrecondition. A request with neither
image nor target_name, or with an image that has no uid, is InvalidArgument.

A provider advertises that it implements this contract with
GetCapabilitiesResponse.supports_image_artifact_identity. Every provider
that predates it rejects an empty target_name, so a new manager whose request
reaches an old provider is refused rather than served under a bare name.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| image_json | [string](#string) |  | JSON-encoded VMImage spec |
| target_name | [string](#string) |  | target_name is the bare template/image name of a legacy (identity-less) request. EMPTY when image is set: the provider derives the name (ADR-0009 D1, D7), and an identity request with a target_name is InvalidArgument. |
| storage_hint | [string](#string) |  | Storage location hint (datastore, pool, etc.) |
| image | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | image names the VMImage being prepared. uid is authoritative: it is part of the artifact&#39;s derived name and of its stamp, and reuse requires a stamp with the same uid (ADR-0009 D1, D4). namespace and name are informational: they form the readable prefix of the artifact name and are recorded in the stamp for audit, but never authorize a reuse. Additive and backward-compatible: an older provider ignores it (and then rejects the empty target_name). |
| source_digest | [string](#string) |  | source_digest is &#34;sha256:&#34; followed by 64 lowercase hex digits: the manager&#39;s digest of the VMImage&#39;s canonical spec.source (ADR-0009 D2). The provider checks only its syntax and uses it verbatim, in the derived name and in the stamp; a changed spec.source therefore gets a new artifact. Required when image is set. |
| provider | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | provider names the Provider object the prepare runs through. Informational only: it is recorded in the stamp as preparedBy and is never part of the reuse rule (ADR-0009 D3, D5). |






<a name="provider-v1-ImagePrepareResponse"></a>

### ImagePrepareResponse
ImagePrepareResponse reports where the provider placed the prepared image so
the manager can later create VMs from that prepared location instead of
re-resolving (and possibly re-downloading) the original source (issue #154,
PR-6 / #214).

It mirrors the CloneResponse precedent: `task` stays at field 1 so this
message is wire-compatible with the TaskResponse it replaces — a manager that
still decodes a TaskResponse reads field 1 (the TaskRef) unchanged, and the
new id/path fields are simply ignored by older decoders. The change is
therefore additive and non-breaking.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| task | [TaskRef](#provider-v1-TaskRef) |  | task references an async prepare operation; an empty/nil task means the prepare completed synchronously. Field 1 is intentionally identical to TaskResponse.task for wire compatibility. |
| prepared_image_id | [string](#string) |  | prepared_image_id is the provider-specific identifier of the prepared image — e.g. a vSphere template name / MoRef value, or a Proxmox template name/VMID. The manager stamps this onto VMImage.status and uses it as the template ref at create time. Known at trigger time even for async prepares. |
| prepared_image_path | [string](#string) |  | prepared_image_path is the provider-specific path of the prepared image — e.g. a libvirt pool path (&lt;poolPath&gt;/&lt;target&gt;.qcow2). Empty for providers that address prepared images by id/name only (vSphere, Proxmox). Known at trigger time even for async prepares. |
| artifact | [PreparedArtifact](#provider-v1-PreparedArtifact) |  | artifact is the provenance stamp of the artifact the provider verified (reused) or wrote (prepared) for an identity request (ADR-0009 D3, D7). Unset from an older provider and in deprecated legacy mode. The manager records a prepare only when artifact is set and its image.uid and source_digest equal the request&#39;s. Additive and backward-compatible: an older manager ignores it. |






<a name="provider-v1-ImportDiskRequest"></a>

### ImportDiskRequest
Disk import operations for migration.
See the ExportDiskRequest host-vs-pod execution contract above: disk bytes
never traverse the gRPC channel; backend_type/transfer_mode carry the same
meaning for the import (target) side (ADR-0006).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| source_url | [string](#string) |  | Where to download the disk from (S3, HTTP, etc.) |
| storage_hint | [string](#string) |  | Target storage location (datastore, pool, etc.) |
| format | [string](#string) |  | Source disk format (qcow2, vmdk, raw) |
| target_name | [string](#string) |  | Name for the imported disk |
| verify_checksum | [bool](#bool) |  | Verify checksum after import |
| expected_checksum | [string](#string) |  | Expected checksum (SHA256) |
| credentials | [ImportDiskRequest.CredentialsEntry](#provider-v1-ImportDiskRequest-CredentialsEntry) | repeated | Credentials for source (access keys, tokens) |
| backend_type | [string](#string) |  | Staging backend: &#34;pvc&#34; | &#34;nfs&#34; | &#34;s3&#34;; empty == legacy pvc (ADR-0006) |
| transfer_mode | [string](#string) |  | Transfer mode: &#34;auto&#34; | &#34;relay&#34; | &#34;direct&#34; (ADR-0006) |
| storage_options_json | [string](#string) |  | JSON-encoded backend-specific options (ADR-0006; empty in Slice 0) |
| target_vm | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | target_vm names the Kubernetes VirtualMachine the disk is imported for (a VMMigration&#39;s target): its namespace and name. On a single-host or thin-client provider uid is empty (the VirtualMachine does not exist yet) and ignored. A CLUSTERED provider requires uid (a canonical UUID; ADR-0007 Addendum B, B2): the migration creates its target VirtualMachine first, and the uid classifies a domain of the same name already on the landing host; it never authorizes writing over a file in use. A provider that attaches an imported disk in place only when it carries the VM&#39;s own name derives the landing name from it with the same rule its Create uses (the libvirt provider: &#34;&lt;namespace&gt;.&lt;name&gt;-migrated&#34;), so the naming rule has one owner, the provider. The landing path is returned in path, which the operator hands back to the VM unchanged. Additive and backward-compatible: other providers ignore it, and an unset value keeps the legacy target_name naming. |
| max_virtual_size_bytes | [int64](#int64) |  | max_virtual_size_bytes is the disk-size limit of the target Provider for this import (the manager&#39;s --max-disk-size, lowered by the Provider&#39;s infra.virtrigaud.io/max-disk-size annotation); 0 means no limit. When it is set, the provider reads the virtual size of the disk it is about to land — from the image header, in a location the tenant cannot change (a private copy or the converted output), not from the manager&#39;s earlier record — and refuses one above it with codes.FailedPrecondition and the ErrorInfo reason DISK_SIZE_EXCEEDS_LIMIT, or with DISK_SIZE_UNVERIFIABLE when it cannot read that size. Nothing is landed either way. Additive and backward-compatible: a provider that predates it ignores it. |
| target_host_id | [string](#string) |  | target_host_id names the host of a CLUSTERED provider the disk lands on: the target VirtualMachine&#39;s status.placement.pendingHost, which the ordinary scheduler chose (ADR-0007 Addendum B, B1/B2). It carries A1&#39;s rules: the value is agnostic to the provider; the manager never sends it to a single-host or thin-client provider (they ignore it); a clustered provider requires it and answers an empty value with InvalidArgument; it never picks a host itself. An unknown, removed or draining host is Unavailable &#43; HOST_UNAVAILABLE before anything runs. Sent only to a provider that reports supports_routed_import. Additive. |






<a name="provider-v1-ImportDiskRequest-CredentialsEntry"></a>

### ImportDiskRequest.CredentialsEntry



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| key | [string](#string) |  |  |
| value | [string](#string) |  |  |






<a name="provider-v1-ImportDiskResponse"></a>

### ImportDiskResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| disk_id | [string](#string) |  | Imported disk identifier |
| path | [string](#string) |  | Path to imported disk |
| task | [TaskRef](#provider-v1-TaskRef) |  | Task reference for async tracking |
| actual_size_bytes | [int64](#int64) |  | Actual size of imported disk |
| checksum | [string](#string) |  | Checksum of imported disk (SHA256) |






<a name="provider-v1-ListHostsRequest"></a>

### ListHostsRequest
List every host a clustered provider fronts






<a name="provider-v1-ListHostsResponse"></a>

### ListHostsResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| hosts | [HostInfo](#provider-v1-HostInfo) | repeated |  |






<a name="provider-v1-ListVMsRequest"></a>

### ListVMsRequest
List all VMs managed by this provider


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| owner_namespace | [string](#string) |  | owner_namespace and owner_name, when both are set, ask for the VMs of ONE VirtualMachine only (ADR-0007 A6, R4: the pre-schedule uniqueness check). A provider that honours the filter advertises GetCapabilitiesResponse.supports_list_owner_filter and looks up the CANDIDATE NAMES of that VirtualMachine only — the names it would give it (libvirt: &#34;&lt;namespace&gt;.&lt;name&gt;&#34;, returned whatever its owner stamp, and the legacy bare &#34;&lt;name&gt;&#34;, returned only when its owner stamp records that namespace and name). A VM named otherwise is NOT looked at, even when its owner stamp records that namespace and name: an adopted VM keeps the name it had and is not found by the filter. Each VM found is reported as in an unfiltered listing (host_id, owner_namespace/owner_name, provider_raw &#34;owner_uid&#34; / &#34;owner_stamp_state&#34;; a clustered libvirt provider also reports each VM&#39;s current size as provider_raw &#34;current_vcpus&#34; and &#34;current_memory_mib&#34;, cpu and memory_mib being its maxima), and the answer sets ListVMsResponse.owner_filter_applied. Hosts that could not be checked are in unreachable_host_ids, exactly as for an unfiltered listing.

Setting only one of the two is invalid (INVALID_ARGUMENT from a provider that honours the filter). A provider that does not honour it (single-host and thin-client providers, and a clustered provider older than ADR-0007 A6.2) ignores both fields and answers the unfiltered listing WITHOUT owner_filter_applied, so a caller never mistakes an unfiltered answer for a filtered one. AGNOSTIC. Informational identity only: the filter selects, it never authorizes anything. |
| owner_name | [string](#string) |  |  |






<a name="provider-v1-ListVMsResponse"></a>

### ListVMsResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| vms | [VMInfo](#provider-v1-VMInfo) | repeated |  |
| unreachable_host_ids | [string](#string) | repeated | unreachable_host_ids names every host of a clustered (&#34;brain-in-operator&#34;) provider whose VMs could not be listed in this call — the host could not be reached, did not answer within its per-host deadline, or failed the listing (ADR-0007 Addendum A, A3 / slice 4). A caller must treat each such host as UNKNOWN, never as empty: a VM it knows on that host is not gone. A clustered provider never silently drops a host from the result. AGNOSTIC. Always empty from single-host and thin-client providers, whose ListVMs either answers for their one endpoint or fails as a whole. |
| owner_filter_applied | [bool](#bool) |  | owner_filter_applied is true when the provider applied the request&#39;s owner filter (ListVMsRequest.owner_namespace / owner_name): vms holds only that VirtualMachine&#39;s candidates. False on every unfiltered listing, and from any provider that ignored the filter — which a caller that asked for it must treat as &#34;the filter is not supported&#34; (ADR-0007 A6.2), never as a filtered answer. AGNOSTIC. |






<a name="provider-v1-NetworkInfo"></a>

### NetworkInfo



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| name | [string](#string) |  | Network name |
| mac | [string](#string) |  | MAC address |
| ip_address | [string](#string) |  | IP address if static |






<a name="provider-v1-ObjectIdentity"></a>

### ObjectIdentity
ObjectIdentity names a Kubernetes object on the wire (CreateRequest.owner,
the owner of the routed per-VM requests, CloneRequest.target_vm and
.source_owner, ImportDiskRequest.target_vm, ImagePrepareRequest.image and
.provider, PreparedArtifact.image, TransferOwnerRequest.owner).
uid is the authoritative identity (unique for the object&#39;s whole lifetime,
never reused after deletion); namespace and name are informational (audit,
operator diagnostics, and naming the hypervisor-side object — e.g. the
libvirt provider names a new domain &#34;&lt;namespace&gt;.&lt;name&gt;&#34;) and must never be
used for authorization on their own.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| uid | [string](#string) |  |  |
| namespace | [string](#string) |  |  |
| name | [string](#string) |  |  |






<a name="provider-v1-PowerRequest"></a>

### PowerRequest
Power control operations


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  |  |
| op | [PowerOp](#provider-v1-PowerOp) |  |  |
| graceful_timeout_seconds | [int32](#int32) |  | Timeout for graceful operations (shutdown/reboot) |
| target_host_id | [string](#string) |  | target_host_id names the host a clustered (&#34;brain-in-operator&#34;) provider must run this power operation on (ADR-0007 Addendum A, A1): the operator&#39;s confirmed binding (VirtualMachine status.placement.host), threaded on the wire exactly like CreateRequest.target_host_id. AGNOSTIC. Additive and backward-compatible: single-host and thin-client providers ignore it, and the operator never sends it to them; a clustered provider REQUIRES it and rejects an empty value with InvalidArgument rather than defaulting to some host (honesty-first, D9). The provider never looks a VM&#39;s host up by itself (D1). |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the Kubernetes object (the VirtualMachine) this power operation is performed for — the identity CreateRequest.owner stamps onto the VM (ADR-0007 Addendum A, slice 2). AGNOSTIC. Additive and backward-compatible. A clustered provider powers a VM ONLY when its recorded owner uid equals this uid; a VM whose stamp is missing, unreadable or records a different owner is reported NOT_FOUND and is never started, stopped or rebooted. The operator sends it on every request for a VirtualMachine with a UID, single-host included. A single-host Proxmox provider checks it the same way against the stamp of the VM at the VMID (VMIDs are reused): a VM stamped with another owner, or unstamped and not named like the owner, is NOT_FOUND with the google.rpc.ErrorInfo reason VM_NOT_OWNED, and a stamp that cannot be read is FAILED_PRECONDITION with OWNER_STAMP_UNREADABLE; an unstamped VM named like the owner (one created before owner stamps, or adopted) is acted on as before. Other single-host providers ignore it. |






<a name="provider-v1-PreparedArtifact"></a>

### PreparedArtifact
PreparedArtifact echoes the provenance stamp of a prepared-image artifact
(ADR-0009 D3, D7). Only image.uid and source_digest are authoritative.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| name | [string](#string) |  | name is the hypervisor-side artifact name the provider derived (ADR-0009 D1): &#34;&lt;namespace&gt;.&lt;name&gt;&#34; (shortened to the hypervisor&#39;s budget), a separator, and 16 hex digits of a hash over the image uid and source digest. |
| image | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | image is the VMImage identity recorded in the stamp. |
| source_digest | [string](#string) |  | source_digest is the source digest recorded in the stamp. |
| reused | [bool](#bool) |  | reused is true when an existing artifact with a matching stamp was reused, false when this call (or the task it returned) prepared it. |






<a name="provider-v1-ReconfigureRequest"></a>

### ReconfigureRequest
Reconfigure virtual machine resources


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  |  |
| desired_json | [string](#string) |  | JSON-encoded desired state |
| target_host_id | [string](#string) |  | target_host_id names the host a clustered (&#34;brain-in-operator&#34;) provider must run this reconfigure on (ADR-0007 Addendum A, A1): the operator&#39;s confirmed binding (VirtualMachine status.placement.host), threaded on the wire exactly like CreateRequest.target_host_id. AGNOSTIC. Additive and backward-compatible: single-host and thin-client providers ignore it, and the operator never sends it to them; a clustered provider REQUIRES it and rejects an empty value with InvalidArgument rather than defaulting to some host (honesty-first, D9). The provider never looks a VM&#39;s host up by itself (D1). |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the Kubernetes object (the VirtualMachine) this reconfigure is performed for — the identity CreateRequest.owner stamps onto the VM (ADR-0007 Addendum A, slice 2). AGNOSTIC. Additive and backward-compatible. A clustered provider reconfigures a VM ONLY when its recorded owner uid equals this uid; a VM whose stamp is missing, unreadable or records a different owner is reported NOT_FOUND and none of its CPU, memory or disks is changed. The operator sends it on every request for a VirtualMachine with a UID, single-host included. A single-host Proxmox provider checks it the same way against the stamp of the VM at the VMID (VMIDs are reused): a VM stamped with another owner, or unstamped and not named like the owner, is NOT_FOUND with the google.rpc.ErrorInfo reason VM_NOT_OWNED, and a stamp that cannot be read is FAILED_PRECONDITION with OWNER_STAMP_UNREADABLE; an unstamped VM named like the owner (one created before owner stamps, or adopted) is acted on as before. Other single-host providers ignore it. |






<a name="provider-v1-SnapshotCreateRequest"></a>

### SnapshotCreateRequest
Snapshot operations


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| vm_id | [string](#string) |  |  |
| name_hint | [string](#string) |  |  |
| include_memory | [bool](#bool) |  | Include memory state if supported |
| description | [string](#string) |  |  |
| target_host_id | [string](#string) |  | target_host_id names the host a clustered (&#34;brain-in-operator&#34;) provider must run this snapshot create on (ADR-0007 Addendum A, A1): the operator&#39;s confirmed binding (VirtualMachine status.placement.host), threaded on the wire exactly like CreateRequest.target_host_id. AGNOSTIC. Additive and backward-compatible: single-host and thin-client providers ignore it, and the operator never sends it to them; a clustered provider REQUIRES it and rejects an empty value with InvalidArgument rather than defaulting to some host (honesty-first, D9). The provider never looks a VM&#39;s host up by itself (D1). |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the Kubernetes object (the VirtualMachine) this snapshot is taken for — the identity CreateRequest.owner stamps onto the VM (ADR-0007 Addendum A, slice 3). AGNOSTIC. Additive and backward-compatible. A clustered provider snapshots a VM ONLY when its recorded owner uid equals this uid; a VM whose stamp is missing, unreadable or records a different owner is reported NOT_FOUND and is never snapshotted. The operator sends it on every request for a VirtualMachine with a UID, single-host included. A single-host Proxmox provider checks it the same way against the stamp of the VM at the VMID (VMIDs are reused): a VM stamped with another owner, or unstamped and not named like the owner, is NOT_FOUND with the google.rpc.ErrorInfo reason VM_NOT_OWNED, and a stamp that cannot be read is FAILED_PRECONDITION with OWNER_STAMP_UNREADABLE; an unstamped VM named like the owner (one created before owner stamps, or adopted) is acted on as before. Other single-host providers ignore it. |
| request_token | [string](#string) |  | request_token identifies the request object this snapshot is created for (the VMSnapshot&#39;s uid), so a retry of the SAME request can find the snapshot an earlier attempt made instead of making a second one, and a snapshot of the same name left by ANOTHER request (an earlier VMSnapshot of that name) is never taken for it. AGNOSTIC. Additive and backward-compatible: providers that do not retry snapshots by name ignore it. A clustered libvirt provider records it with the snapshot it creates and treats an existing snapshot of the requested name as this request&#39;s only when it records the same token; any other is ALREADY_EXISTS. |






<a name="provider-v1-SnapshotCreateResponse"></a>

### SnapshotCreateResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| snapshot_id | [string](#string) |  |  |
| task | [TaskRef](#provider-v1-TaskRef) |  |  |






<a name="provider-v1-SnapshotDeleteRequest"></a>

### SnapshotDeleteRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| vm_id | [string](#string) |  |  |
| snapshot_id | [string](#string) |  |  |
| target_host_id | [string](#string) |  | target_host_id names the host a clustered (&#34;brain-in-operator&#34;) provider must run this snapshot delete on (ADR-0007 Addendum A, A1): the operator&#39;s confirmed binding (VirtualMachine status.placement.host), threaded on the wire exactly like CreateRequest.target_host_id. AGNOSTIC. Additive and backward-compatible: single-host and thin-client providers ignore it, and the operator never sends it to them; a clustered provider REQUIRES it and rejects an empty value with InvalidArgument rather than defaulting to some host (honesty-first, D9). The provider never looks a VM&#39;s host up by itself (D1). |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the VirtualMachine the snapshot belongs to (ADR-0007 Addendum A, slice 3), exactly as SnapshotCreateRequest.owner. A clustered provider deletes a snapshot ONLY of a VM whose recorded owner uid equals this uid; any other VM is reported NOT_FOUND and none of its snapshots is touched. Sent and checked on single-host requests as SnapshotCreateRequest.owner. |






<a name="provider-v1-SnapshotRevertRequest"></a>

### SnapshotRevertRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| vm_id | [string](#string) |  |  |
| snapshot_id | [string](#string) |  |  |
| target_host_id | [string](#string) |  | target_host_id names the host a clustered (&#34;brain-in-operator&#34;) provider must run this snapshot revert on (ADR-0007 Addendum A, A1): the operator&#39;s confirmed binding (VirtualMachine status.placement.host), threaded on the wire exactly like CreateRequest.target_host_id. AGNOSTIC. Additive and backward-compatible: single-host and thin-client providers ignore it, and the operator never sends it to them; a clustered provider REQUIRES it and rejects an empty value with InvalidArgument rather than defaulting to some host (honesty-first, D9). The provider never looks a VM&#39;s host up by itself (D1). |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the VirtualMachine being reverted (ADR-0007 Addendum A, slice 3), exactly as SnapshotCreateRequest.owner. A clustered provider reverts a VM ONLY when its recorded owner uid equals this uid; any other VM is reported NOT_FOUND and is never reverted. Sent and checked on single-host requests as SnapshotCreateRequest.owner. |






<a name="provider-v1-TaskRef"></a>

### TaskRef
Task reference for async operations


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  |  |






<a name="provider-v1-TaskResponse"></a>

### TaskResponse
Generic task response for async operations


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| task | [TaskRef](#provider-v1-TaskRef) |  |  |
| restart_required | [bool](#bool) |  | restart_required is set by a Reconfigure (and only by a Reconfigure) that applied at least one requested change to the VM&#39;s persistent definition only: the change takes effect at the VM&#39;s next power cycle (power off, then on — a reboot from inside the guest does not apply it), and until then the running VM keeps its previous size. Every other requested change was applied to the running VM as well. A Reconfigure that could apply a requested change neither way fails instead; it never reports success for a change in none of these states. Additive and backward-compatible: false (the default) is what every provider that applies all changes live, or fails, returns; a provider that answers with a task reports false and the task&#39;s outcome decides. The manager records a restart-pending change as Reconfiguring=True with reason RestartRequired. |
| honest_result | [bool](#bool) |  | honest_result is set by a provider on EVERY Reconfigure response it gives under the honest result contract (the contract GetCapabilitiesResponse. supports_honest_reconfigure advertises): each requested change was applied to the running VM and its persistent definition, or applied to the definition only and reported with restart_required — a success is never returned for a change it did not apply. It is the per-response proof of that contract: the capability is a snapshot the manager may hold after a provider was rolled back, the marker is not. Additive and backward-compatible: false (unset) from a provider that predates or does not implement the contract. The manager treats a successful Reconfigure of a VM on a clustered Provider without it as not honest: it counts the VM at the larger of its recorded and requested size and holds further resizes (Reconfiguring=False/ProviderLacksHonestReconfigure). Set only on Reconfigure responses. |






<a name="provider-v1-TaskStatusRequest"></a>

### TaskStatusRequest
Check async task status.

TaskStatus is not per-VM, so it carries no target_host_id. A clustered
(&#34;brain-in-operator&#34;) provider therefore encodes the host into every task
reference a routed call returns, and routes TaskStatus by it (ADR-0007
Addendum A, A1, slice 3); the reference stays opaque to the operator. A
clustered provider refuses a reference it did not issue: one that is not
host-encoded, or that names a host not in its own host registry, is
rejected and never dialed. Single-host and thin-client providers&#39; task
references are unchanged.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| task | [TaskRef](#provider-v1-TaskRef) |  |  |






<a name="provider-v1-TaskStatusResponse"></a>

### TaskStatusResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| done | [bool](#bool) |  |  |
| error | [string](#string) |  | Error message if task failed |






<a name="provider-v1-TransferOwnerRequest"></a>

### TransferOwnerRequest
TransferOwner hands one VM to a VirtualMachine: it re-stamps the VM with
that VirtualMachine&#39;s identity (owner), after which the provider&#39;s
owner-checked per-VM calls accept it. On a clustered (&#34;brain-in-operator&#34;)
provider the VM is on target_host_id and the call is routed there (ADR-0007
Addendum A, slice 4); on a single-host provider that reports
supports_owner_transfer the VM is addressed by id alone. The adoption flow
uses it for a VM it listed; restoring a VirtualMachine from a backup, which
gives it a new uid, can use it the same way (A6). It changes the owner stamp
only: it never creates, moves, starts or otherwise changes the VM.

It is a compare-and-swap. The provider stamps the VM ONLY when:
  - the VM named id (on target_host_id) is still the VM the manager listed:
    it carries expected_uuid when one is sent (required by a libvirt
    provider), and
  - every owner stamped on it is either owner itself (an idempotent retry,
    which succeeds) or listed in replaceable_owner_uids — the stamps of
    VirtualMachines the manager has verified no longer exist. An unstamped
    VM may be taken over.
The check and the write are atomic where the hypervisor allows it (vSphere:
the config changeVersion; Proxmox: the config digest) and serialized in the
provider process otherwise (libvirt). A VM stamped for anyone else, with
more than one stamp, or whose stamp cannot be read, and a template or image
artifact, is refused (ALREADY_EXISTS) and left untouched; a VM that is gone
or was replaced since it was listed is NOT_FOUND; a concurrent change is a
retryable error. The stamp is read back before the call succeeds. Refusal
messages never name another owner. A clustered provider&#39;s failures are
routed errors (HOST_UNAVAILABLE, VM_OPERATION_FAILED). Providers that do not
stamp return Unimplemented and report neither supports_owner_transfer nor
supports_routed_adoption.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | id is the VM&#39;s provider-specific identifier (VMInfo.id). |
| target_host_id | [string](#string) |  | target_host_id is the host the VM is on (VMInfo.host_id, or the VirtualMachine&#39;s recorded binding). Required by a clustered provider, which never looks a VM&#39;s host up by itself; empty for a single-host provider, which refuses one. AGNOSTIC. |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner is the identity of the VirtualMachine that takes the VM over; uid is required, and the provider stamps uid, namespace and name (see ObjectIdentity). |
| replaceable_owner_uids | [string](#string) | repeated | replaceable_owner_uids are owner UIDs recorded on the VM (VMInfo provider_raw &#34;owner_uid&#34;) that the manager verified belong to no existing VirtualMachine (for example one deleted with orphan-on-delete). Only these stamps may be replaced. Empty takes over only an unstamped VM. |
| expected_uuid | [string](#string) |  | expected_uuid is the provider&#39;s immutable identifier of the VM (libvirt: the domain UUID, VMInfo provider_raw &#34;uuid&#34;). Required by a libvirt provider (clustered or single-host), which answers NOT_FOUND when the VM named id now carries another, so a VM replaced since it was listed is never stamped. vSphere (whose MOIDs are never reused) compares it with the VM&#39;s instance UUID when it is sent; Proxmox, whose listing reports none, requires instead that the VM&#39;s PVE name is the owner&#39;s (as an unstamped VM&#39;s Delete does), so a reused VMID is never stamped. |






<a name="provider-v1-TransferOwnerResponse"></a>

### TransferOwnerResponse







<a name="provider-v1-VMInfo"></a>

### VMInfo



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | Provider-specific VM identifier |
| name | [string](#string) |  | VM name |
| power_state | [string](#string) |  | Current power state |
| ips | [string](#string) | repeated | IP addresses |
| cpu | [int32](#int32) |  | Number of virtual CPUs |
| memory_mib | [int64](#int64) |  | Memory in MiB |
| disks | [DiskInfo](#provider-v1-DiskInfo) | repeated | Disk information |
| networks | [NetworkInfo](#provider-v1-NetworkInfo) | repeated | Network information |
| provider_raw | [VMInfo.ProviderRawEntry](#provider-v1-VMInfo-ProviderRawEntry) | repeated | Provider-specific metadata |
| host_id | [string](#string) |  | host_id is the host (the Host CR name, as in HostInfo.id) a clustered (&#34;brain-in-operator&#34;) provider found this VM on (ADR-0007 Addendum A, A3 / slice 4). On a clustered provider a VM is identified by (host_id, id), never by id or name alone: two hosts may each have a VM of the same name. Set on every VMInfo a clustered provider lists; empty from single-host and thin-client providers. AGNOSTIC. |
| owner_namespace | [string](#string) |  | owner_namespace and owner_name are the namespace and name recorded in the VM&#39;s VirtRigaud owner stamp (the VirtualMachine it was created or adopted for; its uid is in provider_raw &#34;owner_uid&#34;), read from the same definition the listing reads (ADR-0007 Addendum A, slice 4; A6&#39;s R4 uniqueness check looks previous incarnations up by them). Informational: never an authorization on their own (only the uid identifies an owner). Empty when the VM carries no stamp, or more than one (ambiguous). Set by a clustered provider; single-host and thin-client providers leave them empty. |
| owner_name | [string](#string) |  |  |






<a name="provider-v1-VMInfo-ProviderRawEntry"></a>

### VMInfo.ProviderRawEntry



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| key | [string](#string) |  |  |
| value | [string](#string) |  |  |






<a name="provider-v1-ValidateRequest"></a>

### ValidateRequest
Validate provider connectivity and configuration






<a name="provider-v1-ValidateResponse"></a>

### ValidateResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| ok | [bool](#bool) |  |  |
| message | [string](#string) |  |  |





 


<a name="provider-v1-HostHealth"></a>

### HostHealth
HostHealth is the AGNOSTIC health enum for a host; the probe that produces it
is per-hypervisor (e.g. libvirtd reachability).

| Name | Number | Description |
| ---- | ------ | ----------- |
| HOST_HEALTH_UNSPECIFIED | 0 |  |
| HOST_HEALTH_READY | 1 |  |
| HOST_HEALTH_NOT_READY | 2 |  |



<a name="provider-v1-LandedDiskDeleteOutcome"></a>

### LandedDiskDeleteOutcome
LandedDiskDeleteOutcome is what DeleteLandedDisk did.

| Name | Number | Description |
| ---- | ------ | ----------- |
| LANDED_DISK_DELETE_OUTCOME_UNSPECIFIED | 0 |  |
| LANDED_DISK_DELETE_OUTCOME_DELETED | 1 | The landed disk existed and was removed. |
| LANDED_DISK_DELETE_OUTCOME_NOT_FOUND | 2 | No landed disk existed (already removed, consumed, or never landed). |



<a name="provider-v1-PowerOp"></a>

### PowerOp
Power operations enum

| Name | Number | Description |
| ---- | ------ | ----------- |
| POWER_OP_UNSPECIFIED | 0 |  |
| POWER_OP_ON | 1 |  |
| POWER_OP_OFF | 2 |  |
| POWER_OP_REBOOT | 3 |  |
| POWER_OP_SHUTDOWN_GRACEFUL | 4 | Graceful shutdown using guest tools |



<a name="provider-v1-StagedDiskDeleteOutcome"></a>

### StagedDiskDeleteOutcome
StagedDiskDeleteOutcome is what DeleteStagedDisk did.

| Name | Number | Description |
| ---- | ------ | ----------- |
| STAGED_DISK_DELETE_OUTCOME_UNSPECIFIED | 0 |  |
| STAGED_DISK_DELETE_OUTCOME_DELETED | 1 | The object existed and was removed. |
| STAGED_DISK_DELETE_OUTCOME_NOT_FOUND | 2 | No object existed (already removed, or never written). |
| STAGED_DISK_DELETE_OUTCOME_EMPTIED | 3 | The provider cannot unlink on this backend (libnfs through qemu-img) and truncated the object to zero bytes instead: its data is gone, and an empty file with the staging name remains. |


 

 


<a name="provider-v1-Provider"></a>

### Provider
Provider service definition

| Method Name | Request Type | Response Type | Description |
| ----------- | ------------ | ------------- | ------------|
| Validate | [ValidateRequest](#provider-v1-ValidateRequest) | [ValidateResponse](#provider-v1-ValidateResponse) | Validate provider configuration and connectivity |
| Create | [CreateRequest](#provider-v1-CreateRequest) | [CreateResponse](#provider-v1-CreateResponse) | Create a new virtual machine |
| Delete | [DeleteRequest](#provider-v1-DeleteRequest) | [TaskResponse](#provider-v1-TaskResponse) | Delete a virtual machine |
| Power | [PowerRequest](#provider-v1-PowerRequest) | [TaskResponse](#provider-v1-TaskResponse) | Perform power operations on a virtual machine |
| Reconfigure | [ReconfigureRequest](#provider-v1-ReconfigureRequest) | [TaskResponse](#provider-v1-TaskResponse) | Reconfigure virtual machine resources |
| HardwareUpgrade | [HardwareUpgradeRequest](#provider-v1-HardwareUpgradeRequest) | [TaskResponse](#provider-v1-TaskResponse) | Upgrade VM hardware version |
| Describe | [DescribeRequest](#provider-v1-DescribeRequest) | [DescribeResponse](#provider-v1-DescribeResponse) | Describe current virtual machine state |
| TaskStatus | [TaskStatusRequest](#provider-v1-TaskStatusRequest) | [TaskStatusResponse](#provider-v1-TaskStatusResponse) | Check the status of an async task |
| SnapshotCreate | [SnapshotCreateRequest](#provider-v1-SnapshotCreateRequest) | [SnapshotCreateResponse](#provider-v1-SnapshotCreateResponse) | Snapshot operations |
| SnapshotDelete | [SnapshotDeleteRequest](#provider-v1-SnapshotDeleteRequest) | [TaskResponse](#provider-v1-TaskResponse) |  |
| SnapshotRevert | [SnapshotRevertRequest](#provider-v1-SnapshotRevertRequest) | [TaskResponse](#provider-v1-TaskResponse) |  |
| Clone | [CloneRequest](#provider-v1-CloneRequest) | [CloneResponse](#provider-v1-CloneResponse) | Clone operations |
| ImagePrepare | [ImagePrepareRequest](#provider-v1-ImagePrepareRequest) | [ImagePrepareResponse](#provider-v1-ImagePrepareResponse) | Image preparation and import. Returns the prepared image&#39;s provider-specific location (id/path) so the manager can later create VMs from the prepared template instead of re-resolving the original source. ImagePrepareResponse is wire-compatible with the TaskResponse this previously returned (task at field 1), so the change is non-breaking (issue #154, PR-6 / #214). |
| GetCapabilities | [GetCapabilitiesRequest](#provider-v1-GetCapabilitiesRequest) | [GetCapabilitiesResponse](#provider-v1-GetCapabilitiesResponse) | Get provider capabilities |
| ExportDisk | [ExportDiskRequest](#provider-v1-ExportDiskRequest) | [ExportDiskResponse](#provider-v1-ExportDiskResponse) | Disk migration operations |
| ImportDisk | [ImportDiskRequest](#provider-v1-ImportDiskRequest) | [ImportDiskResponse](#provider-v1-ImportDiskResponse) |  |
| GetDiskInfo | [GetDiskInfoRequest](#provider-v1-GetDiskInfoRequest) | [GetDiskInfoResponse](#provider-v1-GetDiskInfoResponse) |  |
| DeleteStagedDisk | [DeleteStagedDiskRequest](#provider-v1-DeleteStagedDiskRequest) | [DeleteStagedDiskResponse](#provider-v1-DeleteStagedDiskResponse) | Remove a VMMigration&#39;s nfs / s3 staging object (ADR-0011). Providers that cannot return Unimplemented and leave the backend out of supported_staged_disk_delete_backends. |
| DeleteLandedDisk | [DeleteLandedDiskRequest](#provider-v1-DeleteLandedDiskRequest) | [DeleteLandedDiskResponse](#provider-v1-DeleteLandedDiskResponse) | Remove the disk a VMMigration&#39;s ImportDisk landed for a target VM that does not use it (rc2 R7). Providers that cannot return Unimplemented and do not report supports_landed_disk_delete. |
| ListVMs | [ListVMsRequest](#provider-v1-ListVMsRequest) | [ListVMsResponse](#provider-v1-ListVMsResponse) | List all VMs managed by this provider. A clustered provider lists every host it fronts, tags each VM with its host_id and names the hosts it could not list in unreachable_host_ids (ADR-0007 Addendum A, A3). |
| TransferOwner | [TransferOwnerRequest](#provider-v1-TransferOwnerRequest) | [TransferOwnerResponse](#provider-v1-TransferOwnerResponse) | Hand a VM to a VirtualMachine by re-stamping its owner, compare-and-swap (ADR-0007 Addendum A, slice 4; single-host adoption). A clustered provider routes it to the VM&#39;s host and reports supports_routed_adoption; a single-host provider that stamps reports supports_owner_transfer. Providers that do neither return Unimplemented. |
| ListHosts | [ListHostsRequest](#provider-v1-ListHostsRequest) | [ListHostsResponse](#provider-v1-ListHostsResponse) | Host inventory (ADR-0007 P1). Clustered providers report the hosts they front so the operator can schedule across them; single-host and thin-client providers return codes.Unimplemented and advertise supports_clustering = false. GetHostInfo is the cheaper single-host refresh. |
| GetHostInfo | [GetHostInfoRequest](#provider-v1-GetHostInfoRequest) | [HostInfo](#provider-v1-HostInfo) |  |

 



## Scalar Value Types

| .proto Type | Notes | C++ | Java | Python | Go | C# | PHP | Ruby |
| ----------- | ----- | --- | ---- | ------ | -- | -- | --- | ---- |
| <a name="double" /> double |  | double | double | float | float64 | double | float | Float |
| <a name="float" /> float |  | float | float | float | float32 | float | float | Float |
| <a name="int32" /> int32 | Uses variable-length encoding. Inefficient for encoding negative numbers – if your field is likely to have negative values, use sint32 instead. | int32 | int | int | int32 | int | integer | Bignum or Fixnum (as required) |
| <a name="int64" /> int64 | Uses variable-length encoding. Inefficient for encoding negative numbers – if your field is likely to have negative values, use sint64 instead. | int64 | long | int/long | int64 | long | integer/string | Bignum |
| <a name="uint32" /> uint32 | Uses variable-length encoding. | uint32 | int | int/long | uint32 | uint | integer | Bignum or Fixnum (as required) |
| <a name="uint64" /> uint64 | Uses variable-length encoding. | uint64 | long | int/long | uint64 | ulong | integer/string | Bignum or Fixnum (as required) |
| <a name="sint32" /> sint32 | Uses variable-length encoding. Signed int value. These more efficiently encode negative numbers than regular int32s. | int32 | int | int | int32 | int | integer | Bignum or Fixnum (as required) |
| <a name="sint64" /> sint64 | Uses variable-length encoding. Signed int value. These more efficiently encode negative numbers than regular int64s. | int64 | long | int/long | int64 | long | integer/string | Bignum |
| <a name="fixed32" /> fixed32 | Always four bytes. More efficient than uint32 if values are often greater than 2^28. | uint32 | int | int | uint32 | uint | integer | Bignum or Fixnum (as required) |
| <a name="fixed64" /> fixed64 | Always eight bytes. More efficient than uint64 if values are often greater than 2^56. | uint64 | long | int/long | uint64 | ulong | integer/string | Bignum |
| <a name="sfixed32" /> sfixed32 | Always four bytes. | int32 | int | int | int32 | int | integer | Bignum or Fixnum (as required) |
| <a name="sfixed64" /> sfixed64 | Always eight bytes. | int64 | long | int/long | int64 | long | integer/string | Bignum |
| <a name="bool" /> bool |  | bool | boolean | boolean | bool | bool | boolean | TrueClass/FalseClass |
| <a name="string" /> string | A string must always contain UTF-8 encoded or 7-bit ASCII text. | string | String | str/unicode | string | string | string | String (UTF-8) |
| <a name="bytes" /> bytes | May contain any arbitrary sequence of bytes. | string | ByteString | str | []byte | ByteString | string | String (ASCII-8BIT) |

