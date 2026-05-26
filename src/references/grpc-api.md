# Protocol Documentation
<a name="top"></a>

## Overview

VirtRigaud providers expose a single gRPC service (`provider.v1.Provider`) over mTLS. The manager connects via the Resolver and client created per-provider. As of **v0.3.6**, every outbound RPC call passes through two mandatory interceptors before reaching the provider process:

- **`providerRPCMetricsInterceptor`** — records `virtrigaud_provider_rpc_*` Prometheus metrics (call count, latency, error rate) for every RPC. Refer to the observability reference for the full metric catalogue.
- **`providerCircuitBreakerInterceptor`** — wraps the call with a half-open circuit breaker (ref G6 / #112). In the production path the circuit breaker is always active; unit tests may pass a `nil` breaker which the interceptor handles transparently.

Task-creating RPCs (`Create`, `Delete`, `Power`, `Reconfigure`, `HardwareUpgrade`, `SnapshotCreate`, `SnapshotDelete`, `SnapshotRevert`, `Clone`, `ImagePrepare`, `ExportDisk`, `ImportDisk`) additionally register the returned `TaskRef` with the **inflight-task tracker** (ref G7.3 / #130). The controller polls `TaskStatus` until `done=true` or the context is cancelled.

---

## Table of Contents

- [provider/v1/provider.proto](#provider_v1_provider-proto)
    - [CloneRequest](#provider-v1-CloneRequest)
    - [CloneResponse](#provider-v1-CloneResponse)
    - [CreateRequest](#provider-v1-CreateRequest)
    - [CreateResponse](#provider-v1-CreateResponse)
    - [DeleteRequest](#provider-v1-DeleteRequest)
    - [DescribeRequest](#provider-v1-DescribeRequest)
    - [DescribeResponse](#provider-v1-DescribeResponse)
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
    - [HardwareUpgradeRequest](#provider-v1-HardwareUpgradeRequest)
    - [ImagePrepareRequest](#provider-v1-ImagePrepareRequest)
    - [ImportDiskRequest](#provider-v1-ImportDiskRequest)
    - [ImportDiskRequest.CredentialsEntry](#provider-v1-ImportDiskRequest-CredentialsEntry)
    - [ImportDiskResponse](#provider-v1-ImportDiskResponse)
    - [ListVMsRequest](#provider-v1-ListVMsRequest)
    - [ListVMsResponse](#provider-v1-ListVMsResponse)
    - [NetworkInfo](#provider-v1-NetworkInfo)
    - [PowerRequest](#provider-v1-PowerRequest)
    - [ReconfigureRequest](#provider-v1-ReconfigureRequest)
    - [SnapshotCreateRequest](#provider-v1-SnapshotCreateRequest)
    - [SnapshotCreateResponse](#provider-v1-SnapshotCreateResponse)
    - [SnapshotDeleteRequest](#provider-v1-SnapshotDeleteRequest)
    - [SnapshotRevertRequest](#provider-v1-SnapshotRevertRequest)
    - [TaskRef](#provider-v1-TaskRef)
    - [TaskResponse](#provider-v1-TaskResponse)
    - [TaskStatusRequest](#provider-v1-TaskStatusRequest)
    - [TaskStatusResponse](#provider-v1-TaskStatusResponse)
    - [VMInfo](#provider-v1-VMInfo)
    - [VMInfo.ProviderRawEntry](#provider-v1-VMInfo-ProviderRawEntry)
    - [ValidateRequest](#provider-v1-ValidateRequest)
    - [ValidateResponse](#provider-v1-ValidateResponse)
  
    - [PowerOp](#provider-v1-PowerOp)
  
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






<a name="provider-v1-CreateResponse"></a>

### CreateResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | Provider-specific VM identifier |
| task | [TaskRef](#provider-v1-TaskRef) |  | Optional task reference for async operations |






<a name="provider-v1-DeleteRequest"></a>

### DeleteRequest
Delete a virtual machine


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  |  |






<a name="provider-v1-DescribeRequest"></a>

### DescribeRequest
Describe virtual machine current state


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  |  |






<a name="provider-v1-DescribeResponse"></a>

### DescribeResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| exists | [bool](#bool) |  |  |
| power_state | [string](#string) |  |  |
| ips | [string](#string) | repeated |  |
| console_url | [string](#string) |  |  |
| provider_raw_json | [string](#string) |  | Provider-specific additional data |






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






<a name="provider-v1-GetDiskInfoRequest"></a>

### GetDiskInfoRequest
Get disk information for migration planning


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| vm_id | [string](#string) |  | VM identifier |
| disk_id | [string](#string) |  | Disk identifier (optional, defaults to primary disk) |
| snapshot_id | [string](#string) |  | Get info for specific snapshot (optional) |






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






<a name="provider-v1-GetDiskInfoResponse-MetadataEntry"></a>

### GetDiskInfoResponse.MetadataEntry



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| key | [string](#string) |  |  |
| value | [string](#string) |  |  |






<a name="provider-v1-HardwareUpgradeRequest"></a>

### HardwareUpgradeRequest
Upgrade VM hardware version


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  |  |
| target_version | [int32](#int32) |  | Target hardware version (e.g., 21) |






<a name="provider-v1-ImagePrepareRequest"></a>

### ImagePrepareRequest
Image preparation operations


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| image_json | [string](#string) |  | JSON-encoded VMImage spec |
| target_name | [string](#string) |  | Target template/image name |
| storage_hint | [string](#string) |  | Storage location hint (datastore, pool, etc.) |






<a name="provider-v1-ImportDiskRequest"></a>

### ImportDiskRequest
Disk import operations for migration


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| source_url | [string](#string) |  | Where to download the disk from (S3, HTTP, etc.) |
| storage_hint | [string](#string) |  | Target storage location (datastore, pool, etc.) |
| format | [string](#string) |  | Source disk format (qcow2, vmdk, raw) |
| target_name | [string](#string) |  | Name for the imported disk |
| verify_checksum | [bool](#bool) |  | Verify checksum after import |
| expected_checksum | [string](#string) |  | Expected checksum (SHA256) |
| credentials | [ImportDiskRequest.CredentialsEntry](#provider-v1-ImportDiskRequest-CredentialsEntry) | repeated | Credentials for source (access keys, tokens) |






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






<a name="provider-v1-ListVMsRequest"></a>

### ListVMsRequest
List all VMs managed by this provider






<a name="provider-v1-ListVMsResponse"></a>

### ListVMsResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| vms | [VMInfo](#provider-v1-VMInfo) | repeated |  |






<a name="provider-v1-NetworkInfo"></a>

### NetworkInfo



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| name | [string](#string) |  | Network name |
| mac | [string](#string) |  | MAC address |
| ip_address | [string](#string) |  | IP address if static |






<a name="provider-v1-PowerRequest"></a>

### PowerRequest
Power control operations


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  |  |
| op | [PowerOp](#provider-v1-PowerOp) |  |  |
| graceful_timeout_seconds | [int32](#int32) |  | Timeout for graceful operations (shutdown/reboot) |






<a name="provider-v1-ReconfigureRequest"></a>

### ReconfigureRequest
Reconfigure virtual machine resources


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  |  |
| desired_json | [string](#string) |  | JSON-encoded desired state |






<a name="provider-v1-SnapshotCreateRequest"></a>

### SnapshotCreateRequest
Snapshot operations


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| vm_id | [string](#string) |  |  |
| name_hint | [string](#string) |  |  |
| include_memory | [bool](#bool) |  | Include memory state if supported |
| description | [string](#string) |  |  |






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






<a name="provider-v1-SnapshotRevertRequest"></a>

### SnapshotRevertRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| vm_id | [string](#string) |  |  |
| snapshot_id | [string](#string) |  |  |






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






<a name="provider-v1-TaskStatusRequest"></a>

### TaskStatusRequest
Check async task status


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| task | [TaskRef](#provider-v1-TaskRef) |  |  |






<a name="provider-v1-TaskStatusResponse"></a>

### TaskStatusResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| done | [bool](#bool) |  |  |
| error | [string](#string) |  | Error message if task failed |






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
| ImagePrepare | [ImagePrepareRequest](#provider-v1-ImagePrepareRequest) | [TaskResponse](#provider-v1-TaskResponse) | Image preparation and import |
| GetCapabilities | [GetCapabilitiesRequest](#provider-v1-GetCapabilitiesRequest) | [GetCapabilitiesResponse](#provider-v1-GetCapabilitiesResponse) | Get provider capabilities |
| ExportDisk | [ExportDiskRequest](#provider-v1-ExportDiskRequest) | [ExportDiskResponse](#provider-v1-ExportDiskResponse) | Disk migration operations |
| ImportDisk | [ImportDiskRequest](#provider-v1-ImportDiskRequest) | [ImportDiskResponse](#provider-v1-ImportDiskResponse) |  |
| GetDiskInfo | [GetDiskInfoRequest](#provider-v1-GetDiskInfoRequest) | [GetDiskInfoResponse](#provider-v1-GetDiskInfoResponse) |  |
| ListVMs | [ListVMsRequest](#provider-v1-ListVMsRequest) | [ListVMsResponse](#provider-v1-ListVMsResponse) | List all VMs managed by this provider |

 



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

