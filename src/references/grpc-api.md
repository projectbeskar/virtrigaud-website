# Protocol Documentation
<a name="top"></a>

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
| linked | [bool](#bool) |  | Linked clone requested; honoured only by providers that report supports_linked_clones (the libvirt provider refuses it) |
| class_json | [string](#string) |  | JSON-encoded specifications for customization

VMClass overrides |
| placement_json | [string](#string) |  | Placement hints |
| customize_json | [string](#string) |  | customize_json is the JSON of the VMClone&#39;s spec.customization, in the shape of the v1beta1 VMCustomization type, but only an allow-listed subset of it: the fields providers apply (hostname, domain, userData.cloudInit.inline) or report as not applied. Fields that hold or commonly hold secret values and that no provider acts on (sysprep.productKey, sysprep.adminPassword.value, sysprep.joinDomain.password.value, sysprep.customCommands, certificates[].data, guestCommands[].command and .arguments, userData.ignition.inline) are never included. Empty for no customization. |
| source_host_id | [string](#string) |  | source_host_id is the host the source VM runs on for a clustered provider (Provider topology: cluster): the source VM&#39;s bound host (status.placement.host). It is the routing field for the clone. It is deliberately not target_host_id, which is the host where the clone lands. A clustered provider requires the two to be equal (disks are host-local and a linked clone depends on its source disk). A clustered provider requires source_host_id and rejects an empty value with InvalidArgument instead of picking a host. Single-host and thin-client providers ignore it and the manager never sends it to them. Additive and backward-compatible. |
| target_vm | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | target_vm names the Kubernetes VirtualMachine the clone will be bound to: its namespace (VMClone spec.target.namespace, defaulted to the VMClone&#39;s namespace), its name (the same as target_name) and its uid. A provider whose VM names are host-global derives the clone&#39;s name from it (libvirt: &#34;&lt;namespace&gt;.&lt;name&gt;&#34;, the same rule as Create) and returns that name as target_vm_id, which the manager records as the VM&#39;s status.id; with target_vm unset the clone is named target_name. The manager creates that VirtualMachine before the clone and sends its uid to every provider. A provider stamps the clone with the uid it receives, as Create stamps with CreateRequest.owner, and answers a Clone whose target name already holds a clone stamped with that uid with that clone (a re-sent Clone) instead of a second one; any other VM of the target name it would bind is refused with AlreadyExists. Without a uid the clone is unstamped and nothing is re-bound. A clustered provider requires the uid. A provider that does this reports GetCapabilitiesResponse.supports_owner_rebind. |
| target_host_id | [string](#string) |  | target_host_id is the host where the clone lands on a clustered provider: the target VirtualMachine&#39;s status.placement.pendingHost, recorded before the clone is sent. A clustered provider requires it to equal source_host_id (disks are host-local and a linked clone depends on its source disk) and rejects an empty or different value with InvalidArgument; it never lands a clone on a host it chose itself. Single-host and thin-client providers ignore it and the manager never sends it to them. Additive and backward-compatible. |
| source_owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | source_owner identifies the VirtualMachine being cloned: the identity CreateRequest.owner stamped on the source VM. A clustered provider reads (and copies the disk of) a source VM only when its recorded owner uid equals this uid; any other VM is reported NOT_FOUND and none of its disks or definition is read. The Proxmox provider checks it as described for PowerRequest.owner, before anything is cloned (a source config it cannot read is UNAVAILABLE with CREATE_NOT_PERFORMED and VM_OPERATION_FAILED). The other single-host and thin-client providers ignore it. The manager sets it on every clone of a source VirtualMachine that has a uid, single-host included. Additive and backward-compatible. |






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
| target_host_id | [string](#string) |  | target_host_id is the host a clustered provider (Provider topology: cluster) must create this VM on: the host chosen by the manager&#39;s scheduler. It is a field of its own and is not carried in placement_json, which holds hints for hypervisors that place VMs themselves (for example the vSphere cluster, datastore and folder). A clustered provider requires it and rejects an empty value instead of picking a host. Single-host and thin-client providers ignore it and the manager never sends it to them. Additive and backward-compatible. |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the Kubernetes VirtualMachine this create is performed for (uid, namespace and name). The libvirt, vSphere and Proxmox providers stamp the owner on the VM they create. When a VM of the requested name already exists, libvirt and vSphere treat the create as an idempotent success only if that VM carries this owner&#39;s uid, and otherwise fail with ALREADY_EXISTS instead of binding to another tenant&#39;s VM. Proxmox leaves a same-named VM that carries another stamp or none alone and creates a new VM beside it, and refuses only when it cannot tell which VM is this owner&#39;s. A provider that does not stamp ignores the field. An unset owner (a manager that predates the field) never authorizes binding to an existing VM. The manager sets it on every create from the VirtualMachine&#39;s uid, namespace and name. Additive and backward-compatible. |






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
without) a target VM that attached the disk. The manager sends it to the
migration&#39;s target provider, the one the import was sent to.

Confinement (security-critical). The provider derives the landed disk from
target_vm (namespace and name) with exactly the rule its ImportDisk names it
with (vSphere: the landing folder &#34;[&lt;datastore&gt;] &lt;ns&gt;_&lt;vm&gt;-migrated&#34;;
libvirt: &#34;&lt;default pool&gt;/&lt;ns&gt;.&lt;vm&gt;-migrated.qcow2&#34;; Proxmox: the node-side
import stage &#34;&lt;stage dir&gt;/&lt;ns&gt;_&lt;vm&gt;-migrated.&lt;ext&gt;&#34;) and validates the
identity (namespace a DNS-1123 label, name a DNS-1123 subdomain) before it
touches anything. path, when set, must be exactly that landed disk (it
chooses the vSphere datastore); any other path is InvalidArgument. Nothing
else is ever removed.

It refuses (FailedPrecondition with the ErrorInfo reason VM_DISK_IN_USE,
leaving the disk) when any VM or template on the target uses the disk (or,
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
| target_host_id | [string](#string) |  | target_host_id is the host of a clustered target provider the import landed the disk on (the recorded import target host). A clustered provider requires it (InvalidArgument when empty), removes the disk on that host only, and scans every host of the Provider for a domain that uses the file (the pool may be shared), failing closed when a host cannot be scanned. Single-host and thin-client providers ignore it. Additive. |






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
| target_host_id | [string](#string) |  | target_host_id is the host a clustered provider (Provider topology: cluster) must run this delete on: the host the VirtualMachine is bound to (status.placement.host), the same host CreateRequest.target_host_id named. A clustered provider requires it, answers an empty value with InvalidArgument and never looks up a VM&#39;s host itself. Single-host and thin-client providers ignore it and the manager never sends it to them. Additive and backward-compatible. |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the Kubernetes VirtualMachine this delete is performed for: the identity CreateRequest.owner stamped on the VM. A clustered provider deletes a VM only when its recorded owner uid equals this uid; a VM whose stamp is missing or records another owner is reported NOT_FOUND and is never destroyed, so a cleanup (for example a finalizer after an ALREADY_EXISTS create) can never remove another tenant&#39;s VM. The Proxmox provider checks it as described for PowerRequest.owner. The other single-host and thin-client providers ignore it, so a VM created before owner stamps existed stays deletable. The manager sets it on every delete of a VirtualMachine that has a uid. Additive and backward-compatible. |






<a name="provider-v1-DeleteStagedDiskRequest"></a>

### DeleteStagedDiskRequest
DeleteStagedDisk removes the staging object a VMMigration&#39;s ExportDisk wrote
to an nfs or s3 backend (a full, unencrypted copy of a tenant&#39;s disk) once
the migration no longer needs it. The manager sends it to the migration&#39;s
target provider.

Confinement (security-critical). The request carries no key, path or URL.
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
| storage_options_json | [string](#string) |  | storage_options_json is the same JSON-encoded, non-secret backend options the manager sends with ExportDisk / ImportDisk. |
| credentials | [DeleteStagedDiskRequest.CredentialsEntry](#provider-v1-DeleteStagedDiskRequest-CredentialsEntry) | repeated | credentials are the backend credentials (s3: the same keys as ExportDiskRequest.credentials). Secret material: never logged. |
| layout | [string](#string) |  | layout is the naming layout the migration&#39;s staged object was written with, recorded by the manager when the export was sent: &#34;v2&#34; is the nfs file &#34;vmmigrations_&lt;namespace&gt;_&lt;name&gt;_&lt;stage&gt;.qcow2&#34; (&#39;_&#39; appears in no namespace or name, so it is unambiguous); &#34;v1&#34; or empty is the legacy nfs file &#34;vmmigrations-&lt;namespace&gt;-&lt;name&gt;-&lt;stage&gt;.qcow2&#34; of a migration exported before v2. The s3 key is the same in both layouts. Any other value is InvalidArgument. |
| target_vm | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | target_vm is the VirtualMachine the migration&#39;s import landed a disk for (namespace and name; the same identity as ImportDiskRequest.target_vm), set only when the migration sent an import and no other in-flight migration targets the same VM. A provider whose ImportDisk keeps a provider-side copy of the disk until Create (Proxmox: the node-side import stage named after this VM) removes that copy too, confined to its own stage location. Unset: only the staged object is removed. Providers that keep no such copy ignore it. |
| target_host_id | [string](#string) |  | target_host_id is the host of a clustered target provider the migration&#39;s import was sent to (the recorded import target host). An nfs staged object is emptied by that host&#39;s qemu-img, so a clustered provider requires it for backend &#34;nfs&#34; (InvalidArgument when empty) and answers an unknown, removed or draining host with Unavailable and HOST_UNAVAILABLE. s3 objects are removed from the provider pod and ignore it. Single-host and thin-client providers ignore it. Additive. |






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
| target_host_id | [string](#string) |  | target_host_id is the host a clustered provider (Provider topology: cluster) must run this describe on: the host the VirtualMachine is bound to (status.placement.host), the same host CreateRequest.target_host_id named. A clustered provider requires it, answers an empty value with InvalidArgument and never looks up a VM&#39;s host itself. Single-host and thin-client providers ignore it and the manager never sends it to them. Additive and backward-compatible. |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the Kubernetes VirtualMachine this describe is performed for: the identity CreateRequest.owner stamped on the VM. A clustered provider reports a VM whose stamp is missing or records another owner as exists=false and returns none of its state, so a VirtualMachine can never read another tenant&#39;s VM that took over the name on its host (the manager then reports the VM as missing on its host and does not re-create it). The Proxmox provider checks it against the stamp of the VM at the VMID (VMIDs are reused): a VM stamped with another owner, or unstamped and not named like the owner, is NOT_FOUND with the google.rpc.ErrorInfo reason VM_NOT_OWNED, and a stamp that cannot be read is FAILED_PRECONDITION with OWNER_STAMP_UNREADABLE; an unstamped VM named like the owner (one created before owner stamps existed, or adopted) is described as before. A Proxmox Describe never answers exists=false for a VM that is not the owner&#39;s (the manager would create the VM again): it answers VM_NOT_OWNED and returns none of the VM&#39;s state. The other single-host and thin-client providers ignore the owner. The manager sets it on every request for a VirtualMachine that has a uid, single-host included. Additive and backward-compatible. |






<a name="provider-v1-DescribeResponse"></a>

### DescribeResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| exists | [bool](#bool) |  |  |
| power_state | [string](#string) |  |  |
| ips | [string](#string) | repeated |  |
| console_url | [string](#string) |  |  |
| provider_raw_json | [string](#string) |  | Provider-specific additional data |
| max_memory_mib | [int64](#int64) |  | max_memory_mib is the most memory, in MiB, the VM&#39;s guest can use without any action on the host: the memory it was started with, including any balloon headroom above its current allocation (libvirt&#39;s &lt;memory&gt;, the balloon maximum). 0 means the provider does not report it. Only the libvirt provider reports it. For a VM on a clustered Provider the manager records it as status.placement.memoryCeilingMiB when none is recorded yet, raises the recorded ceiling to it when it is higher, and lowers the recorded ceiling to it when the provider reports less (not while a Reconfigure is in flight or pending a restart). Additive and backward-compatible. |
| vcpus | [int32](#int32) |  | vcpus is the number of vCPUs the VM has online now: the running VM&#39;s count, or, for a VM that is off, the count it boots with. 0 means the provider does not report it. Only the libvirt provider reports it. For a VM on a clustered Provider the manager raises the VM&#39;s recorded CPU (status.currentResources) to it when it is higher, so a VM is never counted below the vCPUs it has. Additive and backward-compatible. |






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
Disk export operations for migration.

Disk bytes never traverse this gRPC channel. ExportDisk and ImportDisk move
bytes between the hypervisor host and the staging backend outside the RPC;
the RPC only orchestrates and returns identifiers and checksums.

transfer_mode selects who touches the bytes:
  - &#34;relay&#34;:  host -&gt; provider pod -&gt; backend (the provider pod stages the
              bytes through a mounted PVC or streams them to S3). The nfs
              backend ignores transfer_mode: libvirt and Proxmox run
              qemu-img against the nfs:// URL on the hypervisor host, and
              vSphere in the provider pod.
  - &#34;direct&#34;: host -&gt; backend, with no provider-pod hop. No built-in
              provider implements it; with the pvc and s3 backends a provider
              rejects a mode it does not support with InvalidArgument.
  - &#34;auto&#34;:   the manager resolves it to &#34;relay&#34; before it sends the
              request.
An empty value is treated as &#34;relay&#34;.

backend_type names the staging backend (&#34;pvc&#34; | &#34;nfs&#34; | &#34;s3&#34;); an empty value
means the pvc path, for wire compatibility with callers that predate the
field. The backends a provider supports are listed in
GetCapabilitiesResponse.supported_export_backends and
supported_import_backends. The destination_url the manager sends starts with
pvc://, s3:// or nfs:// to match.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| vm_id | [string](#string) |  | VM identifier |
| disk_id | [string](#string) |  | Disk identifier (optional, defaults to primary disk) |
| snapshot_id | [string](#string) |  | Snapshot to export from (optional) |
| destination_url | [string](#string) |  | Where to upload the disk (S3, HTTP, etc.) |
| format | [string](#string) |  | Desired export format (qcow2, vmdk, raw) |
| compress | [bool](#bool) |  | Enable compression during export |
| credentials | [ExportDiskRequest.CredentialsEntry](#provider-v1-ExportDiskRequest-CredentialsEntry) | repeated | Credentials for destination: for s3 the keys accessKeyID, secretAccessKey and optionally sessionToken. Secret material, never logged. |
| backend_type | [string](#string) |  | Staging backend: &#34;pvc&#34; | &#34;nfs&#34; | &#34;s3&#34;; empty means pvc |
| transfer_mode | [string](#string) |  | Transfer mode: &#34;relay&#34; (the manager resolves &#34;auto&#34; to &#34;relay&#34;) |
| storage_options_json | [string](#string) |  | JSON-encoded, non-secret backend options (s3: bucket, endpoint, region, prefix, usePathStyle; nfs: server, export, path, uid, gid); empty for pvc |
| target_host_id | [string](#string) |  | target_host_id is the host a clustered provider (Provider topology: cluster) must run this disk export on: the host the VirtualMachine is bound to (status.placement.host), the same host CreateRequest.target_host_id named. A clustered provider requires it, answers an empty value with InvalidArgument and never looks up a VM&#39;s host itself. Single-host and thin-client providers ignore it and the manager never sends it to them. Additive and backward-compatible. |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the VirtualMachine whose disk is exported, exactly as SnapshotCreateRequest.owner. A clustered provider exports a disk only of a VM whose recorded owner uid equals this uid; any other VM is reported NOT_FOUND and none of its disks is read. Sent and checked on single-host requests as described for SnapshotCreateRequest.owner, before any disk is read or copied. |






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
| supported_export_backends | [string](#string) | repeated | Export staging backends: &#34;pvc&#34;|&#34;nfs&#34;|&#34;s3&#34;; empty means pvc only |
| supported_import_backends | [string](#string) | repeated | Import staging backends: &#34;pvc&#34;|&#34;nfs&#34;|&#34;s3&#34;; empty means pvc only |
| supported_transfer_modes | [string](#string) | repeated | Transfer modes: &#34;relay&#34;|&#34;direct&#34;; empty means relay only. No built-in provider implements &#34;direct&#34;. |
| supports_clustering | [bool](#bool) |  | Provider fronts several hosts and implements host inventory (ListHosts/GetHostInfo) and host-targeted placement. Reported only by the libvirt provider, and only when it runs with Provider topology: cluster. |
| supports_image_artifact_identity | [bool](#bool) |  | supports_image_artifact_identity reports that ImagePrepare implements the prepared-image artifact identity contract: it accepts ImagePrepareRequest.image/source_digest/provider with an empty target_name, names and stamps artifacts from that identity, never reuses an artifact by bare name, and echoes the stamp in ImagePrepareResponse.artifact. A manager holds import-style prepares through a provider that supports image import but does not advertise this. |
| supports_honest_reconfigure | [bool](#bool) |  | supports_honest_reconfigure reports that Reconfigure implements the honest result contract: every requested change is applied to the running VM and its persistent definition, or applied to the definition only and reported with TaskResponse.restart_required, or the call fails; it never reports success for a change it did not apply. false (the default) from a provider that predates it or does not implement it. A manager holds resizes of VMs on a clustered Provider that does not advertise it (its committed-capacity accounting trusts the result); single-host Providers are resized as before. Of the built-in providers only libvirt reports it. Additive and backward-compatible. |
| supports_routed_clone | [bool](#bool) |  | supports_routed_clone reports that a clustered provider routes Clone to the source VM&#39;s bound host: it honours source_host_id, target_host_id and source_owner and stamps the clone with target_vm&#39;s uid. The manager checks it before it creates a clustered clone&#39;s target VirtualMachine. False on single-host and thin-client providers, which do not route clones (their Clone is unaffected), and on an older clustered provider. |
| supports_routed_adoption | [bool](#bool) |  | supports_routed_adoption reports that a clustered provider lists VMs across all of its hosts (every VMInfo carries its host_id and ListVMsResponse.unreachable_host_ids names every host that could not be listed) and implements TransferOwner, which re-stamps a VM on its host with the VirtualMachine that takes it over. The manager adopts from a clustered provider only when it reports it. False on single-host and thin-client providers (their ListVMs and adoption do not depend on it) and on an older clustered provider. |
| supports_list_owner_filter | [bool](#bool) |  | supports_list_owner_filter reports that ListVMs honours the owner filter (ListVMsRequest.owner_namespace / owner_name): it returns only the VMs of that VirtualMachine (the ones the provider would name for it) and marks the answer with ListVMsResponse.owner_filter_applied. The manager runs its pre-schedule uniqueness check only through a clustered provider that reports it, and holds a clustered VM&#39;s first placement otherwise. False on single-host and thin-client providers (they never schedule, and ignore the filter) and on an older clustered provider. |
| supported_staged_disk_delete_backends | [string](#string) | repeated | supported_staged_disk_delete_backends lists the staging backends (&#34;nfs&#34;, &#34;s3&#34;) whose migration staging objects DeleteStagedDisk can remove. Empty (a provider that predates the RPC, or one that stages nothing outside the cluster) means the manager never sends DeleteStagedDisk and records the staged object as left behind. |
| supports_import_size_limit | [bool](#bool) |  | supports_import_size_limit reports that ImportDisk enforces ImportDiskRequest.max_virtual_size_bytes on the disk it lands (refusing a larger one with DISK_SIZE_EXCEEDS_LIMIT, or one it cannot measure with DISK_SIZE_UNVERIFIABLE). A provider that predates the field ignores the limit, so while one applies the manager holds a migration into a Provider that does not report it. |
| supports_owner_transfer | [bool](#bool) |  | supports_owner_transfer reports that TransferOwner re-stamps a VM this provider&#39;s ListVMs reported with the VirtualMachine that adopts it, compare-and-swap, in the provider&#39;s own topology: a single-host provider addresses the VM by VMInfo.id alone (target_host_id empty). The manager&#39;s single-host adoption stamps the VMs it adopts only through a provider that reports it; through an older one it adopts them unstamped and says so in the Provider&#39;s adoption status. A clustered provider reports supports_routed_adoption for its (routed) TransferOwner; this field does not change how a clustered Provider adopts. |
| supports_owner_rebind | [bool](#bool) |  | supports_owner_rebind reports that Create and Clone stamp the VM they make with its owner (CreateRequest.owner, CloneRequest.target_vm with a uid) and that a Create or Clone sent again for the same owner returns the VM an earlier attempt made, never a second one. The manager sends a Create or Clone whose outcome is unknown again only to a provider that reports it; from any other (one that predates the field, or an older Proxmox image that ignores target_vm) it keeps the earlier behaviour and never re-sends. Field 25 is supports_owner_transfer. |
| resend_safe_export_backends | [string](#string) | repeated | resend_safe_export_backends lists the staging backends (&#34;pvc&#34;, &#34;nfs&#34;, &#34;s3&#34;) on which an ExportDisk sent again for the same destination_url, once the deadline of the earlier call has passed, replaces what the earlier call wrote and leaves nothing else behind: the destination is the only durable artifact, the earlier call&#39;s writes have stopped by its deadline (cancellation honoured, or the write is atomic), and any temporary artifact is cleaned up or uniquely named. The manager re-sends an ExportDisk whose outcome it lost (a restart or leader change between the call and the write of its result) only on a backend listed here; on any other, and to a provider image that predates the field, the VMMigration waits for an operator (reason ExportOutcomeUnknown). Additive. |
| resend_safe_import_backends | [string](#string) | repeated | resend_safe_import_backends is resend_safe_export_backends for ImportDisk: on a listed backend, an ImportDisk sent again for the same target_vm, once the earlier call&#39;s deadline has passed, lands the disk at the same deterministic name (replacing what the earlier call landed, or refusing because a VM uses it), never a second disk. |
| supports_landed_disk_delete | [bool](#bool) |  | supports_landed_disk_delete reports that DeleteLandedDisk removes the disk a migration&#39;s ImportDisk landed for a target VM that does not use it. From a provider that does not report it (one that predates the RPC) the manager never sends DeleteLandedDisk: it records the landed disk as left behind, with a Warning. Fields 27 and 28 are resend_safe_export_backends and resend_safe_import_backends. |
| supports_routed_import | [bool](#bool) |  | supports_routed_import reports that a clustered provider routes ImportDisk to ImportDiskRequest.target_host_id (with target_vm carrying the target VirtualMachine&#39;s uid), DeleteLandedDisk to DeleteLandedDiskRequest.target_host_id with a cross-host in-use scan, and the nfs DeleteStagedDisk to DeleteStagedDiskRequest.target_host_id. The manager accepts a clustered Provider as a VMMigration target only when it reports it (read from the provider at run time). False on single-host and thin-client providers (their import is not routed) and on an older clustered provider. Additive. |






<a name="provider-v1-GetDiskInfoRequest"></a>

### GetDiskInfoRequest
Get disk information for migration planning


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| vm_id | [string](#string) |  | VM identifier |
| disk_id | [string](#string) |  | Disk identifier (optional, defaults to primary disk) |
| snapshot_id | [string](#string) |  | Get info for specific snapshot (optional) |
| target_host_id | [string](#string) |  | target_host_id is the host a clustered provider (Provider topology: cluster) must run this disk-info read on: the host the VirtualMachine is bound to (status.placement.host), the same host CreateRequest.target_host_id named. A clustered provider requires it, answers an empty value with InvalidArgument and never looks up a VM&#39;s host itself. Single-host and thin-client providers ignore it and the manager never sends it to them. Additive and backward-compatible. |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the VirtualMachine whose disk is described, exactly as SnapshotCreateRequest.owner. A clustered provider describes a disk only of a VM whose recorded owner uid equals this uid; any other VM is reported NOT_FOUND and none of its disks is read. Sent and checked on single-host requests as described for SnapshotCreateRequest.owner. |






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
| disks | [DiskCapacity](#provider-v1-DiskCapacity) | repeated | disks lists every disk of the VM as it is now (its data disks, not CD-ROM or cloud-init media), each with its current virtual size, whatever disk_id and snapshot_id asked for. The manager checks them against the administrator&#39;s disk-size limit before a clone copies them. A size the provider could not read is 0, which the manager treats as unknown. A provider that leaves the list empty makes the manager fail closed: it clones nothing while a limit applies. Additive and backward-compatible. |






<a name="provider-v1-GetDiskInfoResponse-MetadataEntry"></a>

### GetDiskInfoResponse.MetadataEntry



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| key | [string](#string) |  |  |
| value | [string](#string) |  |  |






<a name="provider-v1-GetHostInfoRequest"></a>

### GetHostInfoRequest
Refresh a single host&#39;s inventory. Cheaper than a full ListHosts poll when
reconciling one Host resource. Returns a HostInfo.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| host_id | [string](#string) |  |  |






<a name="provider-v1-HardwareUpgradeRequest"></a>

### HardwareUpgradeRequest
Upgrade VM hardware version. Only the vSphere provider implements this RPC;
the other providers answer Unimplemented. The manager does not call it.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  |  |
| target_version | [int32](#int32) |  | Target hardware version (e.g., 21) |
| target_host_id | [string](#string) |  | target_host_id is the host a clustered provider would run this hardware upgrade on. The field is not used: the manager never calls HardwareUpgrade and the clustered libvirt provider answers it with Unimplemented. Single-host and thin-client providers ignore it. |






<a name="provider-v1-HostInfo"></a>

### HostInfo
HostInfo describes one hypervisor host in a clustered provider&#39;s inventory.
Each field has the same meaning on every hypervisor; how the value is
obtained depends on the hypervisor. The libvirt provider reads
`virsh nodeinfo` and `virsh domcapabilities`, and measures the free space of
the file system behind the `default` storage pool&#39;s directory with
`virsh pool-dumpxml` and `stat -f`.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | Host identifier: the name of the Host resource. |
| address | [string](#string) |  | Address of the host (the libvirt provider reports its SSH endpoint). |
| allocatable_cpu | [int32](#int32) |  | Schedulable vCPUs: the host&#39;s total logical CPUs, before overcommit and before subtracting VMs. |
| allocatable_mem_mib | [int64](#int64) |  | Schedulable memory in MiB: the host&#39;s total memory, before overcommit and before subtracting VMs. |
| allocatable_storage | [int64](#int64) |  | Storage available for VM disks, in bytes (libvirt: free space of the default pool&#39;s directory). |
| health | [HostHealth](#provider-v1-HostHealth) |  | Result of the health probe. |
| labels | [HostInfo.LabelsEntry](#provider-v1-HostInfo-LabelsEntry) | repeated | Scheduling constraints from the host&#39;s inventory (storage-pool and network visibility, zone, rack). |
| cpu_model | [string](#string) |  | Baseline CPU model. |
| cpu_features | [string](#string) | repeated | CPU feature flags. |
| machine_types | [string](#string) | repeated | Supported machine types. |
| emulator_version | [string](#string) |  | Emulator/hypervisor version. |






<a name="provider-v1-HostInfo-LabelsEntry"></a>

### HostInfo.LabelsEntry



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| key | [string](#string) |  |  |
| value | [string](#string) |  |  |






<a name="provider-v1-ImagePrepareRequest"></a>

### ImagePrepareRequest
Image preparation operations

Prepared-image artifact identity. A manager that knows the VMImage&#39;s
identity sets image, source_digest and provider, and sends an empty
target_name. The provider derives the hypervisor-side artifact name from
image.uid and source_digest (the naming rule belongs to the provider),
stamps every artifact it prepares with that identity, and reuses an
existing artifact only when its stamp carries the same image.uid and
source_digest; anything else at the derived name is refused with
AlreadyExists and is never overwritten or adopted.

A request with no image is a legacy request from a manager that predates
this contract. It must carry target_name. It is deprecated: a provider may
serve it with bare-name naming and reuse by name and no artifact echo (the
built-in providers log a warning and increment
virtrigaud_provider_image_prepare_legacy_requests_total{provider_type}), or
refuse it. A request with neither image nor target_name, or with an image
that has no uid, is InvalidArgument.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| image_json | [string](#string) |  | JSON-encoded VMImage spec |
| target_name | [string](#string) |  | target_name is the bare template/image name of a legacy (identity-less) request. Empty when image is set: the provider derives the name, and an identity request with a target_name is InvalidArgument. |
| storage_hint | [string](#string) |  | Storage location hint (datastore, pool, etc.) |
| image | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | image names the VMImage being prepared. uid is authoritative: it is part of the artifact&#39;s derived name and of its stamp, and reuse requires a stamp with the same uid. namespace and name are informational: they form the readable prefix of the artifact name and are recorded in the stamp for audit, but never authorize a reuse. Additive and backward-compatible: a provider that predates the contract ignores it (and then rejects the empty target_name). |
| source_digest | [string](#string) |  | source_digest is &#34;sha256:&#34; followed by 64 lowercase hex digits: the manager&#39;s digest of the VMImage&#39;s canonical spec.source. The provider checks only its syntax and uses it verbatim, in the derived name and in the stamp; a changed spec.source therefore gets a new artifact. Required when image is set. |
| provider | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | provider names the Provider object the prepare runs through. Informational only: it is recorded in the stamp as preparedBy and is never part of the reuse rule. |






<a name="provider-v1-ImagePrepareResponse"></a>

### ImagePrepareResponse
ImagePrepareResponse reports where the provider placed the prepared image so
the manager can create VMs from that prepared location instead of
re-resolving (and possibly re-downloading) the original source.

task stays at field 1, identical to TaskResponse.task, so the message is
wire-compatible with TaskResponse: a decoder that still expects a
TaskResponse reads field 1 (the TaskRef) unchanged and ignores the other
fields.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| task | [TaskRef](#provider-v1-TaskRef) |  | task references an async prepare operation; an empty/nil task means the prepare completed synchronously. Field 1 is intentionally identical to TaskResponse.task for wire compatibility. |
| prepared_image_id | [string](#string) |  | prepared_image_id is the provider-specific identifier of the prepared image (for example a vSphere template name or inventory path, or the name or VMID of an existing Proxmox template). The manager records it on VMImage.status and uses it as the template reference when it creates VMs. Known when the call returns, even for an asynchronous prepare. |
| prepared_image_path | [string](#string) |  | prepared_image_path is the provider-specific path of the prepared image (for example a libvirt pool path, &lt;poolPath&gt;/&lt;target&gt;.qcow2). Empty for providers that address prepared images by id or name only (vSphere, Proxmox). Known when the call returns, even for an asynchronous prepare. |
| artifact | [PreparedArtifact](#provider-v1-PreparedArtifact) |  | artifact is the provenance stamp of the artifact the provider verified (reused) or wrote (prepared) for an identity request. Unset in legacy mode and from a provider that predates the identity contract. The manager records a prepare only when artifact is set and its image.uid and source_digest equal the request&#39;s. Additive and backward-compatible: an older manager ignores it. |






<a name="provider-v1-ImportDiskRequest"></a>

### ImportDiskRequest
Disk import operations for migration.
See the ExportDiskRequest comment: disk bytes never traverse the gRPC
channel; backend_type and transfer_mode carry the same meaning for the
import (target) side.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| source_url | [string](#string) |  | Where to download the disk from (S3, HTTP, etc.) |
| storage_hint | [string](#string) |  | Target storage location (datastore, pool, etc.) |
| format | [string](#string) |  | Source disk format (qcow2, vmdk, raw) |
| target_name | [string](#string) |  | Name for the imported disk |
| verify_checksum | [bool](#bool) |  | Verify checksum after import |
| expected_checksum | [string](#string) |  | Expected checksum (SHA256) |
| credentials | [ImportDiskRequest.CredentialsEntry](#provider-v1-ImportDiskRequest-CredentialsEntry) | repeated | Credentials for source: for s3 the keys accessKeyID, secretAccessKey and optionally sessionToken. Secret material, never logged. |
| backend_type | [string](#string) |  | Staging backend: &#34;pvc&#34; | &#34;nfs&#34; | &#34;s3&#34;; empty means pvc |
| transfer_mode | [string](#string) |  | Transfer mode: &#34;relay&#34; (the manager resolves &#34;auto&#34; to &#34;relay&#34;) |
| storage_options_json | [string](#string) |  | JSON-encoded, non-secret backend options (s3: bucket, endpoint, region, prefix, usePathStyle; nfs: server, export, path, uid, gid); empty for pvc |
| target_vm | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | target_vm names the Kubernetes VirtualMachine the disk is imported for (a VMMigration&#39;s target): its namespace, name and uid. A provider that is not clustered ignores the uid, which is empty because the VirtualMachine does not exist yet. A clustered provider requires uid (a canonical UUID): the migration creates its target VirtualMachine first, and the uid classifies a domain of the same name already on the landing host; it never authorizes writing over a file in use. A provider that attaches an imported disk in place only when it carries the VM&#39;s own name derives the landing name from it with the same rule its Create uses (libvirt: &#34;&lt;namespace&gt;.&lt;name&gt;-migrated&#34;), so the provider owns the naming rule. The landing path is returned in path, which the manager hands back to the VM unchanged. vSphere and Proxmox require it and refuse an import without it (InvalidSpec); libvirt falls back to the target_name naming when it is unset. Additive and backward-compatible. |
| max_virtual_size_bytes | [int64](#int64) |  | max_virtual_size_bytes is the disk-size limit of the target Provider for this import (the manager&#39;s --max-disk-size, lowered by the Provider&#39;s infra.virtrigaud.io/max-disk-size annotation); 0 means no limit. When it is set, the provider reads the virtual size of the disk it is about to land — from the image header, in a location the tenant cannot change (a private copy or the converted output), not from the manager&#39;s earlier record — and refuses one above it with codes.FailedPrecondition and the ErrorInfo reason DISK_SIZE_EXCEEDS_LIMIT, or with DISK_SIZE_UNVERIFIABLE when it cannot read that size. Nothing is landed either way. Additive and backward-compatible: a provider that predates it ignores it. |
| target_host_id | [string](#string) |  | target_host_id is the host of a clustered provider the disk lands on: the target VirtualMachine&#39;s status.placement.pendingHost, which the scheduler chose. The value is not specific to a hypervisor; the manager never sends it to a single-host or thin-client provider (they ignore it); a clustered provider requires it, answers an empty value with InvalidArgument and never picks a host itself. An unknown, removed or draining host is Unavailable with the ErrorInfo reason HOST_UNAVAILABLE before anything runs. Sent only to a provider that reports supports_routed_import. Additive. |






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
| owner_namespace | [string](#string) |  | owner_namespace and owner_name, when both are set, ask for the VMs of one VirtualMachine only (the manager&#39;s check, before a clustered VM is scheduled, that no VM already exists for it). A provider that honours the filter advertises GetCapabilitiesResponse.supports_list_owner_filter and looks up the candidate names of that VirtualMachine only: the names it would give it (libvirt: &#34;&lt;namespace&gt;.&lt;name&gt;&#34;, returned whatever its owner stamp, and the legacy bare &#34;&lt;name&gt;&#34;, returned only when its owner stamp records that namespace and name). A VM named otherwise is not looked at, even when its owner stamp records that namespace and name: an adopted VM keeps the name it had and is not found by the filter. Each VM found is reported as in an unfiltered listing (host_id, owner_namespace and owner_name, provider_raw &#34;owner_uid&#34; and &#34;owner_stamp_state&#34;; a clustered libvirt provider also reports each VM&#39;s current size as provider_raw &#34;current_vcpus&#34; and &#34;current_memory_mib&#34;, cpu and memory_mib being its maxima), and the answer sets ListVMsResponse.owner_filter_applied. Hosts that could not be checked are listed in unreachable_host_ids, exactly as for an unfiltered listing.

Setting only one of the two is invalid (INVALID_ARGUMENT from a provider that honours the filter). A provider that does not honour it (single-host and thin-client providers, and a clustered provider that predates the filter) ignores both fields and answers the unfiltered listing without owner_filter_applied, so a caller never mistakes an unfiltered answer for a filtered one. The filter only selects VMs; it never authorizes anything. |
| owner_name | [string](#string) |  |  |






<a name="provider-v1-ListVMsResponse"></a>

### ListVMsResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| vms | [VMInfo](#provider-v1-VMInfo) | repeated |  |
| unreachable_host_ids | [string](#string) | repeated | unreachable_host_ids names every host of a clustered provider whose VMs could not be listed in this call: the host could not be reached, did not answer within its per-host deadline, or failed the listing. A caller must treat each such host as unknown, never as empty: a VM it knows on that host is not gone. A clustered provider never silently drops a host from the result. Always empty from single-host and thin-client providers, whose ListVMs either answers for their one endpoint or fails as a whole. |
| owner_filter_applied | [bool](#bool) |  | owner_filter_applied is true when the provider applied the request&#39;s owner filter (ListVMsRequest.owner_namespace and owner_name): vms holds only that VirtualMachine&#39;s candidates. False on every unfiltered listing, and from any provider that ignored the filter, which a caller that asked for it must treat as &#34;the filter is not supported&#34;, never as a filtered answer. |






<a name="provider-v1-NetworkInfo"></a>

### NetworkInfo



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| name | [string](#string) |  | Network name |
| mac | [string](#string) |  | MAC address |
| ip_address | [string](#string) |  | IP address if static |






<a name="provider-v1-ObjectIdentity"></a>

### ObjectIdentity
ObjectIdentity names a Kubernetes object on the wire: the owner of
CreateRequest and of the per-VM requests, CloneRequest.target_vm and
.source_owner, ImportDiskRequest.target_vm, ImagePrepareRequest.image and
.provider, PreparedArtifact.image, TransferOwnerRequest.owner, and the
migration and target_vm of the staged and landed disk deletes.
uid is the authoritative identity (unique for the object&#39;s whole lifetime,
never reused after deletion); namespace and name are informational (audit,
manager diagnostics, and naming the hypervisor-side object, for example the
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
| target_host_id | [string](#string) |  | target_host_id is the host a clustered provider (Provider topology: cluster) must run this power operation on: the host the VirtualMachine is bound to (status.placement.host), the same host CreateRequest.target_host_id named. A clustered provider requires it, answers an empty value with InvalidArgument and never looks up a VM&#39;s host itself. Single-host and thin-client providers ignore it and the manager never sends it to them. Additive and backward-compatible. |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the Kubernetes VirtualMachine this power operation is performed for: the identity CreateRequest.owner stamped on the VM. A clustered provider acts on a VM only when its recorded owner uid equals this uid; a VM whose stamp is missing, unreadable or records another owner is reported NOT_FOUND and is never started, stopped or rebooted. The Proxmox provider checks it against the stamp of the VM at the VMID (VMIDs are reused): a VM stamped with another owner, or unstamped and not named like the owner, is NOT_FOUND with the google.rpc.ErrorInfo reason VM_NOT_OWNED, and a stamp that cannot be read is FAILED_PRECONDITION with OWNER_STAMP_UNREADABLE; an unstamped VM named like the owner (one created before owner stamps existed, or adopted) is acted on. The other single-host and thin-client providers ignore it. The manager sets it on every request for a VirtualMachine that has a uid, single-host included. Additive and backward-compatible. |






<a name="provider-v1-PreparedArtifact"></a>

### PreparedArtifact
PreparedArtifact echoes the provenance stamp of a prepared-image artifact.
Only image.uid and source_digest are authoritative.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| name | [string](#string) |  | name is the hypervisor-side artifact name the provider derived: &#34;&lt;namespace&gt;.&lt;name&gt;&#34; (shortened to the hypervisor&#39;s length limit), a separator, and 16 hex digits of a hash over the image uid and source digest. |
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
| target_host_id | [string](#string) |  | target_host_id is the host a clustered provider (Provider topology: cluster) must run this reconfigure on: the host the VirtualMachine is bound to (status.placement.host), the same host CreateRequest.target_host_id named. A clustered provider requires it, answers an empty value with InvalidArgument and never looks up a VM&#39;s host itself. Single-host and thin-client providers ignore it and the manager never sends it to them. Additive and backward-compatible. |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the Kubernetes VirtualMachine this reconfigure is performed for: the identity CreateRequest.owner stamped on the VM. A clustered provider reconfigures a VM only when its recorded owner uid equals this uid; a VM whose stamp is missing, unreadable or records another owner is reported NOT_FOUND and none of its CPU, memory or disks is changed. The Proxmox provider checks it as described for PowerRequest.owner. The other single-host and thin-client providers ignore it. The manager sets it on every request for a VirtualMachine that has a uid, single-host included. Additive and backward-compatible. |






<a name="provider-v1-SnapshotCreateRequest"></a>

### SnapshotCreateRequest
Snapshot operations


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| vm_id | [string](#string) |  |  |
| name_hint | [string](#string) |  |  |
| include_memory | [bool](#bool) |  | Include memory state if supported |
| description | [string](#string) |  |  |
| target_host_id | [string](#string) |  | target_host_id is the host a clustered provider (Provider topology: cluster) must run this snapshot create on: the host the VirtualMachine is bound to (status.placement.host), the same host CreateRequest.target_host_id named. A clustered provider requires it, answers an empty value with InvalidArgument and never looks up a VM&#39;s host itself. Single-host and thin-client providers ignore it and the manager never sends it to them. Additive and backward-compatible. |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the Kubernetes VirtualMachine this snapshot is taken for: the identity CreateRequest.owner stamped on the VM. A clustered provider snapshots a VM only when its recorded owner uid equals this uid; a VM whose stamp is missing, unreadable or records another owner is reported NOT_FOUND and is never snapshotted. The Proxmox provider checks it as described for PowerRequest.owner. The other single-host and thin-client providers ignore it. The manager sets it on every request for a VirtualMachine that has a uid, single-host included. Additive and backward-compatible. |
| request_token | [string](#string) |  | request_token identifies the request object this snapshot is created for (the VMSnapshot&#39;s uid; for a snapshot a VMMigration takes, the VMMigration&#39;s uid with a retry suffix), so a retry of the same request can find the snapshot an earlier attempt made instead of making a second one, and a snapshot of the same name left by another request (an earlier VMSnapshot of that name) is never taken for it. Providers that do not retry snapshots by name ignore it. A clustered libvirt provider records it with the snapshot it creates and treats an existing snapshot of the requested name as this request&#39;s only when it records the same token; any other is ALREADY_EXISTS. Additive and backward-compatible. |






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
| target_host_id | [string](#string) |  | target_host_id is the host a clustered provider (Provider topology: cluster) must run this snapshot delete on: the host the VirtualMachine is bound to (status.placement.host), the same host CreateRequest.target_host_id named. A clustered provider requires it, answers an empty value with InvalidArgument and never looks up a VM&#39;s host itself. Single-host and thin-client providers ignore it and the manager never sends it to them. Additive and backward-compatible. |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the VirtualMachine the snapshot belongs to, exactly as SnapshotCreateRequest.owner. A clustered provider deletes a snapshot only of a VM whose recorded owner uid equals this uid; any other VM is reported NOT_FOUND and none of its snapshots is touched. Sent and checked on single-host requests as described for SnapshotCreateRequest.owner. |






<a name="provider-v1-SnapshotRevertRequest"></a>

### SnapshotRevertRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| vm_id | [string](#string) |  |  |
| snapshot_id | [string](#string) |  |  |
| target_host_id | [string](#string) |  | target_host_id is the host a clustered provider (Provider topology: cluster) must run this snapshot revert on: the host the VirtualMachine is bound to (status.placement.host), the same host CreateRequest.target_host_id named. A clustered provider requires it, answers an empty value with InvalidArgument and never looks up a VM&#39;s host itself. Single-host and thin-client providers ignore it and the manager never sends it to them. Additive and backward-compatible. |
| owner | [ObjectIdentity](#provider-v1-ObjectIdentity) |  | owner identifies the VirtualMachine being reverted, exactly as SnapshotCreateRequest.owner. A clustered provider reverts a VM only when its recorded owner uid equals this uid; any other VM is reported NOT_FOUND and is never reverted. Sent and checked on single-host requests as described for SnapshotCreateRequest.owner. |






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
| restart_required | [bool](#bool) |  | restart_required is set by a Reconfigure (and only by a Reconfigure) that applied at least one requested change to the VM&#39;s persistent definition only: that change takes effect at the VM&#39;s next power cycle (power off, then on; a reboot from inside the guest does not apply it), and until then the running VM keeps its previous size. Every other requested change was applied to the running VM as well. A Reconfigure that could apply a requested change in neither way fails instead; it never reports success for a change it did not apply. false (the default) is what a provider that applies all changes live, or fails, returns; a provider that answers with a task reports false and the task&#39;s outcome decides. Of the built-in providers only libvirt sets it. The manager records a restart-pending change as Reconfiguring=True with reason RestartRequired. Additive and backward-compatible. |
| honest_result | [bool](#bool) |  | honest_result is set by a provider on every Reconfigure response it gives under the honest result contract that GetCapabilitiesResponse.supports_honest_reconfigure advertises: each requested change was applied to the running VM and its persistent definition, or applied to the definition only and reported with restart_required; a success is never returned for a change that was not applied. It is the per-response proof of that contract (the capability is a snapshot the manager may keep after a provider was rolled back; this marker is not). false (unset) from a provider that does not implement the contract. Of the built-in providers only libvirt sets it. For a VM on a clustered Provider the manager treats a successful Reconfigure without it as not honest: it counts the VM at the larger of its recorded and requested size and sends the Reconfigure again until the marker is set. (A provider that does not report supports_honest_reconfigure is not asked to resize at all: Reconfiguring=False, reason ProviderLacksHonestReconfigure.) Set only on Reconfigure responses. Additive and backward-compatible. |






<a name="provider-v1-TaskStatusRequest"></a>

### TaskStatusRequest
Check async task status.

TaskStatus is not per-VM, so the request carries no target_host_id. A
clustered provider therefore encodes the host into every task reference a
routed call returns, and routes TaskStatus by it; the reference stays opaque
to the manager. A clustered provider refuses a reference it did not issue:
one that is not host-encoded, or that names a host that is not in its own
host registry, is rejected with an error and its host is never contacted.
The task references of single-host and thin-client providers are unchanged.


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
owner-checked per-VM calls accept it. On a clustered provider the VM is on
target_host_id and the call is routed there; on a single-host provider that
reports supports_owner_transfer the VM is addressed by id alone. The
manager&#39;s adoption flow uses it for a VM it listed. It changes the owner
stamp only: it never creates, moves, starts or otherwise changes the VM.

It is a compare-and-swap. The provider stamps the VM only when:
  - the VM named id (on target_host_id) is still the VM the manager listed:
    it carries expected_uuid when one is sent (required by a libvirt
    provider), and
  - every owner stamped on it is either owner itself (an idempotent retry,
    which succeeds) or listed in replaceable_owner_uids, the stamps of
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
routed errors (HOST_UNAVAILABLE, VM_OPERATION_FAILED). A provider that does
not stamp returns Unimplemented and reports neither supports_owner_transfer
nor supports_routed_adoption.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| id | [string](#string) |  | id is the VM&#39;s provider-specific identifier (VMInfo.id). |
| target_host_id | [string](#string) |  | target_host_id is the host the VM is on (VMInfo.host_id, or the VirtualMachine&#39;s recorded binding). Required by a clustered provider, which never looks a VM&#39;s host up by itself; empty for a single-host provider, which refuses one. |
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
| host_id | [string](#string) |  | host_id is the host (the Host resource name, as in HostInfo.id) a clustered provider found this VM on. On a clustered provider a VM is identified by (host_id, id), never by id or name alone: two hosts may each have a VM of the same name. Set on every VMInfo a clustered provider lists; empty from single-host and thin-client providers. |
| owner_namespace | [string](#string) |  | owner_namespace and owner_name are the namespace and name recorded in the VM&#39;s VirtRigaud owner stamp (the VirtualMachine it was created or adopted for; its uid is in provider_raw &#34;owner_uid&#34;), read from the same definition the listing reads. The manager uses them to look up previous incarnations of a VirtualMachine. Informational: never an authorization on their own (only the uid identifies an owner). Empty when the VM carries no stamp, or more than one (ambiguous). Set by a clustered provider; single-host and thin-client providers leave them empty. |
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
HostHealth is the health of a host as reported by a clustered provider. How
it is probed depends on the hypervisor (libvirt: whether `virsh nodeinfo`
answers).

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
Provider service definition.

Terms used in this file. A single-host provider is bound to one hypervisor
endpoint (Provider topology: single). A thin-client provider fronts a
hypervisor that places VMs itself (vSphere through vCenter, Proxmox through
its own cluster). A clustered provider fronts several bare hosts registered
as Host resources (Provider topology: cluster); the manager&#39;s scheduler
chooses the host and names it in target_host_id on each call. Only the
libvirt provider can run as a clustered provider.

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
| ImagePrepare | [ImagePrepareRequest](#provider-v1-ImagePrepareRequest) | [ImagePrepareResponse](#provider-v1-ImagePrepareResponse) | Image preparation and import. Returns the prepared image&#39;s provider-specific location (id/path) so the manager can create VMs from the prepared template instead of re-resolving the original source. ImagePrepareResponse is wire-compatible with the TaskResponse this RPC returned before (task at field 1). Support differs by provider: libvirt, vSphere and the mock prepare an image from a URL; the Proxmox provider only verifies a reference to an existing template and refuses a URL import as an invalid spec; a clustered libvirt provider answers Unimplemented. |
| GetCapabilities | [GetCapabilitiesRequest](#provider-v1-GetCapabilitiesRequest) | [GetCapabilitiesResponse](#provider-v1-GetCapabilitiesResponse) | Get provider capabilities |
| ExportDisk | [ExportDiskRequest](#provider-v1-ExportDiskRequest) | [ExportDiskResponse](#provider-v1-ExportDiskResponse) | Disk migration operations |
| ImportDisk | [ImportDiskRequest](#provider-v1-ImportDiskRequest) | [ImportDiskResponse](#provider-v1-ImportDiskResponse) |  |
| GetDiskInfo | [GetDiskInfoRequest](#provider-v1-GetDiskInfoRequest) | [GetDiskInfoResponse](#provider-v1-GetDiskInfoResponse) |  |
| DeleteStagedDisk | [DeleteStagedDiskRequest](#provider-v1-DeleteStagedDiskRequest) | [DeleteStagedDiskResponse](#provider-v1-DeleteStagedDiskResponse) | Remove a VMMigration&#39;s nfs / s3 staging object. Providers that cannot return Unimplemented and leave the backend out of supported_staged_disk_delete_backends. |
| DeleteLandedDisk | [DeleteLandedDiskRequest](#provider-v1-DeleteLandedDiskRequest) | [DeleteLandedDiskResponse](#provider-v1-DeleteLandedDiskResponse) | Remove the disk a VMMigration&#39;s ImportDisk landed for a target VM that does not use it. Providers that cannot return Unimplemented and do not report supports_landed_disk_delete. |
| ListVMs | [ListVMsRequest](#provider-v1-ListVMsRequest) | [ListVMsResponse](#provider-v1-ListVMsResponse) | List all VMs managed by this provider. A clustered provider lists every host it fronts, tags each VM with its host_id and names the hosts it could not list in unreachable_host_ids. |
| TransferOwner | [TransferOwnerRequest](#provider-v1-TransferOwnerRequest) | [TransferOwnerResponse](#provider-v1-TransferOwnerResponse) | Hand a VM to a VirtualMachine by re-stamping its owner, compare-and-swap. A clustered provider routes it to the VM&#39;s host and reports supports_routed_adoption; a single-host provider that stamps reports supports_owner_transfer. Providers that do neither return Unimplemented. |
| ListHosts | [ListHostsRequest](#provider-v1-ListHostsRequest) | [ListHostsResponse](#provider-v1-ListHostsResponse) | Host inventory. Clustered providers report the hosts they front so the manager can schedule across them; single-host and thin-client providers return codes.Unimplemented and advertise supports_clustering = false. GetHostInfo is the cheaper single-host refresh. |
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

