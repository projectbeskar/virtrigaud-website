<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# API Reference

## Packages
- [infra.virtrigaud.io/v1beta1](#infravirtrigaudiov1beta1)


## infra.virtrigaud.io/v1beta1

Package v1beta1 contains API Schema definitions for the infra.virtrigaud.io v1beta1 API group

### Resource Types
- [Host](#host)
- [HostList](#hostlist)
- [HostPool](#hostpool)
- [HostPoolList](#hostpoollist)
- [Provider](#provider)
- [ProviderList](#providerlist)
- [VMClass](#vmclass)
- [VMClassList](#vmclasslist)
- [VMClone](#vmclone)
- [VMCloneList](#vmclonelist)
- [VMImage](#vmimage)
- [VMImageList](#vmimagelist)
- [VMMigration](#vmmigration)
- [VMMigrationList](#vmmigrationlist)
- [VMNetworkAttachment](#vmnetworkattachment)
- [VMNetworkAttachmentList](#vmnetworkattachmentlist)
- [VMPlacementPolicy](#vmplacementpolicy)
- [VMPlacementPolicyList](#vmplacementpolicylist)
- [VMSet](#vmset)
- [VMSetList](#vmsetlist)
- [VMSnapshot](#vmsnapshot)
- [VMSnapshotList](#vmsnapshotlist)
- [VirtualMachine](#virtualmachine)
- [VirtualMachineList](#virtualmachinelist)



#### AffinityRules



AffinityRules defines affinity placement rules. The scheduler acts on
hostAffinity and vmAffinity; the other rules are accepted but not acted on
in this release.



_Appears in:_
- [VMPlacementPolicySpec](#vmplacementpolicyspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `vmAffinity` _[VMAffinity](#vmaffinity)_ | VMAffinity defines affinity rules between VMs. |  | Optional: \{\} <br /> |
| `hostAffinity` _[HostAffinityRule](#hostaffinityrule)_ | HostAffinity prefers, or requires, the listed Hosts. |  | Optional: \{\} <br /> |
| `clusterAffinity` _[ClusterAffinityRule](#clusteraffinityrule)_ | ClusterAffinity encourages VMs to be placed in the same cluster. Accepted<br />but not acted on in this release. |  | Optional: \{\} <br /> |
| `datastoreAffinity` _[DatastoreAffinityRule](#datastoreaffinityrule)_ | DatastoreAffinity encourages VMs to be placed on the same datastore.<br />Accepted but not acted on in this release. |  | Optional: \{\} <br /> |
| `zoneAffinity` _[ZoneAffinityRule](#zoneaffinityrule)_ | ZoneAffinity encourages VMs to be placed in the same zone. Accepted but<br />not acted on in this release. |  | Optional: \{\} <br /> |
| `applicationAffinity` _[ApplicationAffinityRule](#applicationaffinityrule)_ | ApplicationAffinity encourages VMs from the same application to be<br />co-located. Accepted but not acted on in this release. |  | Optional: \{\} <br /> |


#### AntiAffinityRules



AntiAffinityRules defines anti-affinity placement rules. The scheduler acts
on hostAntiAffinity and vmAntiAffinity; the other rules are accepted but
not acted on in this release.



_Appears in:_
- [VMPlacementPolicySpec](#vmplacementpolicyspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `vmAntiAffinity` _[VMAntiAffinity](#vmantiaffinity)_ | VMAntiAffinity defines anti-affinity rules between VMs. |  | Optional: \{\} <br /> |
| `hostAntiAffinity` _[HostAntiAffinityRule](#hostantiaffinityrule)_ | HostAntiAffinity limits the number of VMs on one Host. |  | Optional: \{\} <br /> |
| `clusterAntiAffinity` _[ClusterAntiAffinityRule](#clusterantiaffinityrule)_ | ClusterAntiAffinity prevents VMs from being placed in the same cluster.<br />Accepted but not acted on in this release. |  | Optional: \{\} <br /> |
| `datastoreAntiAffinity` _[DatastoreAntiAffinityRule](#datastoreantiaffinityrule)_ | DatastoreAntiAffinity prevents VMs from being placed on the same<br />datastore. Accepted but not acted on in this release. |  | Optional: \{\} <br /> |
| `zoneAntiAffinity` _[ZoneAntiAffinityRule](#zoneantiaffinityrule)_ | ZoneAntiAffinity prevents VMs from being placed in the same zone. Accepted<br />but not acted on in this release. |  | Optional: \{\} <br /> |
| `applicationAntiAffinity` _[ApplicationAntiAffinityRule](#applicationantiaffinityrule)_ | ApplicationAntiAffinity prevents VMs from different applications being<br />co-located. Accepted but not acted on in this release. |  | Optional: \{\} <br /> |


#### ApplicationAffinityRule



ApplicationAffinityRule defines application affinity rules. Accepted but
not acted on in this release.



_Appears in:_
- [AffinityRules](#affinityrules)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled indicates if application affinity is enabled. Accepted but not<br />acted on in this release. |  |  |
| `applicationLabel` _string_ | ApplicationLabel specifies the label key used to identify applications.<br />Accepted but not acted on in this release. | app | Optional: \{\} <br /> |
| `scope` _string_ | Scope defines the scope of the affinity rule. Accepted but not acted on in<br />this release. |  | Enum: [strict preferred] <br />Optional: \{\} <br /> |


#### ApplicationAntiAffinityRule



ApplicationAntiAffinityRule defines application anti-affinity rules.
Accepted but not acted on in this release.



_Appears in:_
- [AntiAffinityRules](#antiaffinityrules)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled indicates if application anti-affinity is enabled. Accepted but<br />not acted on in this release. |  |  |
| `applicationLabel` _string_ | ApplicationLabel specifies the label key used to identify applications.<br />Accepted but not acted on in this release. | app | Optional: \{\} <br /> |
| `scope` _string_ | Scope defines the scope of the anti-affinity rule. Accepted but not acted<br />on in this release. |  | Enum: [strict preferred] <br />Optional: \{\} <br /> |


#### BasicAuthConfig



BasicAuthConfig defines basic authentication configuration. Accepted but not
acted on in this release.



_Appears in:_
- [HTTPAuthentication](#httpauthentication)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `secretRef` _[LocalObjectReference](#localobjectreference)_ | SecretRef references a secret containing username and password. Accepted<br />but not acted on in this release. |  |  |
| `usernameKey` _string_ | UsernameKey is the key in the secret containing the username (default:<br />username). Accepted but not acted on in this release. | username | Optional: \{\} <br /> |
| `passwordKey` _string_ | PasswordKey is the key in the secret containing the password (default:<br />password). Accepted but not acted on in this release. | password | Optional: \{\} <br /> |


#### BearerTokenConfig



BearerTokenConfig defines bearer token authentication configuration. Accepted
but not acted on in this release.



_Appears in:_
- [HTTPAuthentication](#httpauthentication)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `secretRef` _[LocalObjectReference](#localobjectreference)_ | SecretRef references a secret containing the bearer token. Accepted but<br />not acted on in this release. |  |  |
| `tokenKey` _string_ | TokenKey is the key in the secret containing the token (default: token).<br />Accepted but not acted on in this release. | token | Optional: \{\} <br /> |


#### BoundProviderRef



BoundProviderRef identifies the Provider object a VirtualMachine is bound
through (status.boundProvider). It is written only by the operator.



_Appears in:_
- [VMSnapshotStatus](#vmsnapshotstatus)
- [VirtualMachineStatus](#virtualmachinestatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `namespace` _string_ | Namespace of the Provider. |  | MaxLength: 63 <br /> |
| `name` _string_ | Name of the Provider. |  | MaxLength: 253 <br /> |
| `uid` _string_ | UID of the Provider object at bind time. Empty when it was not known<br />(never for a VM bound by this operator version). A Provider deleted and<br />re-created under the same name has a new UID and is not accepted in its<br />place. |  | MaxLength: 128 <br />Optional: \{\} <br /> |


#### BridgeConfig



BridgeConfig defines bridge configuration. Only name is acted on; stp and
delay are accepted but not acted on in this release.



_Appears in:_
- [LibvirtNetworkConfig](#libvirtnetworkconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the name of the host bridge that the NIC attaches to. |  | MaxLength: 15 <br />Pattern: `^[^<>&'"/\x00-\x1f]+$` <br /> |
| `stp` _boolean_ | STP enables Spanning Tree Protocol. Accepted but not acted on in this<br />release. | false | Optional: \{\} <br /> |
| `delay` _integer_ | Delay is the STP forwarding delay. Accepted but not acted on in this<br />release. |  | Maximum: 30 <br />Minimum: 0 <br />Optional: \{\} <br /> |


#### CertificateSpec



CertificateSpec defines a certificate to install. Accepted but not acted
on in this release.



_Appears in:_
- [VMCustomization](#vmcustomization)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the certificate name. Accepted but not acted on in this<br />release. |  | MaxLength: 255 <br /> |
| `data` _string_ | Data contains the certificate data (PEM format). Accepted but not acted<br />on in this release.<br />WARNING: a value set here is stored in plaintext in the VMClone (etcd,<br />backups, anyone who can read the object). It is accepted but not acted<br />on in this release and is not sent to the provider; do not put a real<br />certificate private key here. |  | Optional: \{\} <br /> |
| `secretRef` _[LocalObjectReference](#localobjectreference)_ | SecretRef references a secret containing the certificate. Accepted but<br />not acted on in this release. |  | Optional: \{\} <br /> |
| `secretKey` _string_ | SecretKey is the key in the secret containing the certificate. Accepted<br />but not acted on in this release. | tls.crt | Optional: \{\} <br /> |
| `store` _string_ | Store specifies the certificate store. Accepted but not acted on in<br />this release. | root | Enum: [root ca my trust] <br />Optional: \{\} <br /> |


#### ChecksumType

_Underlying type:_ _string_

ChecksumType represents the checksum algorithm. The vSphere and libvirt
providers verify an image's checksum with it when they prepare the image.

_Validation:_
- Enum: [md5 sha1 sha256 sha512]

_Appears in:_
- [HTTPImageSource](#httpimagesource)
- [LibvirtImageSource](#libvirtimagesource)
- [VSphereImageSource](#vsphereimagesource)

| Field | Description |
| --- | --- |
| `md5` | ChecksumTypeMD5 indicates MD5 checksum<br /> |
| `sha1` | ChecksumTypeSHA1 indicates SHA1 checksum<br /> |
| `sha256` | ChecksumTypeSHA256 indicates SHA256 checksum<br /> |
| `sha512` | ChecksumTypeSHA512 indicates SHA512 checksum<br /> |


#### ClientCertConfig



ClientCertConfig defines client certificate authentication configuration.
Accepted but not acted on in this release.



_Appears in:_
- [HTTPAuthentication](#httpauthentication)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `secretRef` _[LocalObjectReference](#localobjectreference)_ | SecretRef references a secret containing the client certificate and key.<br />Accepted but not acted on in this release. |  |  |
| `certKey` _string_ | CertKey is the key in the secret containing the certificate (default:<br />tls.crt). Accepted but not acted on in this release. | tls.crt | Optional: \{\} <br /> |
| `keyKey` _string_ | KeyKey is the key in the secret containing the private key (default:<br />tls.key). Accepted but not acted on in this release. | tls.key | Optional: \{\} <br /> |


#### CloneMetadata



CloneMetadata contains clone operation metadata. Accepted but not acted
on in this release. No controller or provider reads it.



_Appears in:_
- [VMCloneSpec](#vmclonespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `purpose` _string_ | Purpose describes the purpose of the clone. Accepted but not acted on<br />in this release. |  | Enum: [backup testing migration development production staging] <br />Optional: \{\} <br /> |
| `createdBy` _string_ | CreatedBy identifies who or what created the clone. Accepted but not<br />acted on in this release. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `project` _string_ | Project identifies the project this clone belongs to. Accepted but not<br />acted on in this release. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `environment` _string_ | Environment specifies the environment. Accepted but not acted on in<br />this release. |  | Enum: [dev staging prod test qa uat] <br />Optional: \{\} <br /> |
| `tags` _object (keys:string, values:string)_ | Tags are key-value pairs for categorizing the clone. Accepted but not<br />acted on in this release. |  | MaxProperties: 50 <br />Optional: \{\} <br /> |


#### CloneOptions



CloneOptions defines cloning options. Only type and powerOn are acted on;
every other option is accepted but not acted on in this release.



_Appears in:_
- [VMCloneSpec](#vmclonespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `type` _[CloneType](#clonetype)_ | Type specifies the clone type. FullClone (the default) copies the<br />disks. LinkedClone makes a copy-on-write clone that keeps depending on<br />the source's disk; it is sent only to a Provider that reports<br />linked-clone support (vSphere and Proxmox; the mock provider accepts it<br />too). On Proxmox a linked clone needs a source that is a template. On<br />libvirt the VMClone fails with reason LinkedCloneUnsupported (or<br />LinkedCloneCrossNamespace when the target is in another namespace).<br />InstantClone is accepted but not acted on in this release: a full clone<br />is made. status.actualCloneType reports what was made. | FullClone | Enum: [FullClone LinkedClone InstantClone] <br />Optional: \{\} <br /> |
| `powerOn` _boolean_ | PowerOn indicates whether to power on the target VirtualMachine after<br />the clone. The clone itself is made powered off; the target<br />VirtualMachine is created with spec.powerState On (true) or Off (false,<br />the default), and the VirtualMachine controller powers it on. | false | Optional: \{\} <br /> |
| `includeSnapshots` _boolean_ | IncludeSnapshots indicates whether to include snapshots in the clone.<br />Accepted but not acted on in this release. | false | Optional: \{\} <br /> |
| `parallel` _boolean_ | Parallel enables parallel disk cloning. Accepted but not acted on in<br />this release. | false | Optional: \{\} <br /> |
| `timeout` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | Timeout defines the maximum time to wait for clone completion. Accepted<br />but not acted on in this release. The default is not enforced. | 30m | Optional: \{\} <br /> |
| `retryPolicy` _[CloneRetryPolicy](#cloneretrypolicy)_ | RetryPolicy defines retry behavior for failed clones. Accepted but not<br />acted on in this release. The controller re-sends a Clone with a built-in<br />backoff (15 seconds doubling to 5 minutes) when the provider reports that<br />it did nothing, or when the outcome is unknown and the provider recognises<br />a clone it already made. It waits, without failing, for a running source<br />or a blocked host. Any other failure fails the clone, and Failed is<br />terminal. |  | Optional: \{\} <br /> |
| `storage` _[CloneStorageOptions](#clonestorageoptions)_ | Storage defines storage-specific clone options. Accepted but not acted<br />on in this release. The provider decides where the clone is stored. |  | Optional: \{\} <br /> |
| `performance` _[ClonePerformanceOptions](#cloneperformanceoptions)_ | Performance defines performance-related clone options. Accepted but not<br />acted on in this release. |  | Optional: \{\} <br /> |


#### ClonePerformanceOptions



ClonePerformanceOptions defines performance-related clone options.
Accepted but not acted on in this release.



_Appears in:_
- [CloneOptions](#cloneoptions)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `priority` _string_ | Priority specifies the clone operation priority. Accepted but not acted<br />on in this release. | Normal | Enum: [Low Normal High] <br />Optional: \{\} <br /> |
| `ioThrottling` _boolean_ | IOThrottling enables I/O throttling during clone operations. Accepted<br />but not acted on in this release. | false | Optional: \{\} <br /> |
| `maxIOPS` _integer_ | MaxIOPS limits the maximum IOPS during clone operations. Accepted but<br />not acted on in this release. |  | Maximum: 100000 <br />Minimum: 100 <br />Optional: \{\} <br /> |
| `concurrentDisks` _integer_ | ConcurrentDisks limits the number of disks cloned concurrently.<br />Accepted but not acted on in this release. | 2 | Maximum: 10 <br />Minimum: 1 <br />Optional: \{\} <br /> |


#### ClonePhase

_Underlying type:_ _string_

ClonePhase represents the phase of a clone operation.

_Validation:_
- Enum: [Pending Preparing Cloning Customizing Powering-On Ready Failed]

_Appears in:_
- [VMCloneStatus](#vmclonestatus)

| Field | Description |
| --- | --- |
| `Pending` | ClonePhasePending indicates the clone is waiting for a prerequisite,<br />such as its source VirtualMachine, its Provider or a source that must<br />be powered off. The Ready condition's reason and message say which.<br /> |
| `Preparing` | ClonePhasePreparing is never set in this release.<br /> |
| `Cloning` | ClonePhaseCloning indicates the provider accepted the Clone call and<br />the target VirtualMachine is not bound to the cloned machine yet.<br /> |
| `Customizing` | ClonePhaseCustomizing is never set in this release.<br /> |
| `Powering-On` | ClonePhasePoweringOn is never set in this release.<br /> |
| `Ready` | ClonePhaseReady indicates the clone is complete and the target<br />VirtualMachine is bound to the cloned machine.<br /> |
| `Failed` | ClonePhaseFailed indicates the clone failed. It is terminal.<br /> |


#### CloneProgress



CloneProgress shows the clone operation progress. Not populated in this
release.



_Appears in:_
- [VMCloneStatus](#vmclonestatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `totalDisks` _integer_ | TotalDisks is the total number of disks to clone. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `completedDisks` _integer_ | CompletedDisks is the number of disks completed. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `currentDisk` _[DiskCloneProgress](#diskcloneprogress)_ | CurrentDisk shows progress of the current disk being cloned. Not<br />populated in this release. |  | Optional: \{\} <br /> |
| `overallPercentage` _integer_ | OverallPercentage is the overall completion percentage (0-100). Not<br />populated in this release. |  | Maximum: 100 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `eta` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | ETA is the estimated time to completion. Not populated in this release. |  | Optional: \{\} <br /> |


#### CloneRetryPolicy



CloneRetryPolicy defines retry behavior for failed clones. Accepted but
not acted on in this release.



_Appears in:_
- [CloneOptions](#cloneoptions)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `maxRetries` _integer_ | MaxRetries is the maximum number of retry attempts. Accepted but not<br />acted on in this release. | 3 | Maximum: 10 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `retryDelay` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | RetryDelay is the delay between retry attempts. Accepted but not acted<br />on in this release. | 5m | Optional: \{\} <br /> |
| `backoffMultiplier` _integer_ | BackoffMultiplier is the multiplier for exponential backoff. Accepted<br />but not acted on in this release. | 2 | Optional: \{\} <br /> |


#### CloneSource



CloneSource defines the VirtualMachine to clone. Only vmRef is supported:
a VMClone without vmRef fails with reason UnsupportedSource. snapshotRef,
templateRef and imageRef are accepted but not acted on in this release.



_Appears in:_
- [VMCloneSpec](#vmclonespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `vmRef` _[LocalObjectReference](#localobjectreference)_ | VMRef names the VirtualMachine to clone, in the VMClone's namespace.<br />The clone waits (Pending) until that VirtualMachine exists and has been<br />created on its Provider, and is made on that Provider. |  | Optional: \{\} <br /> |
| `snapshotRef` _[LocalObjectReference](#localobjectreference)_ | SnapshotRef references a snapshot to clone from. Accepted but not acted<br />on in this release. |  | Optional: \{\} <br /> |
| `templateRef` _[ObjectRef](#objectref)_ | TemplateRef references a VM template to clone from. Accepted but not<br />acted on in this release. |  | Optional: \{\} <br /> |
| `imageRef` _[ObjectRef](#objectref)_ | ImageRef references a VM image to clone from. Accepted but not acted on<br />in this release. |  | Optional: \{\} <br /> |


#### CloneStorageOptions



CloneStorageOptions defines storage-specific clone options. Accepted but
not acted on in this release.



_Appears in:_
- [CloneOptions](#cloneoptions)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `preferThinProvisioning` _boolean_ | PreferThinProvisioning prefers thin provisioning for cloned disks.<br />Accepted but not acted on in this release. | true | Optional: \{\} <br /> |
| `diskFormat` _[DiskType](#disktype)_ | DiskFormat specifies the preferred disk format for cloned disks.<br />Accepted but not acted on in this release. |  | Enum: [thin thick eagerzeroedthick ssd hdd nvme] <br />Optional: \{\} <br /> |
| `storageClass` _string_ | StorageClass specifies the storage class for cloned disks. Accepted but<br />not acted on in this release. |  | MaxLength: 253 <br />Optional: \{\} <br /> |
| `datastore` _string_ | Datastore specifies the target datastore for cloned disks. Accepted but<br />not acted on in this release. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `folder` _string_ | Folder specifies the target folder for the cloned VM. Accepted but not<br />acted on in this release. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `enableCompression` _boolean_ | EnableCompression enables compression during clone operations. Accepted<br />but not acted on in this release. | false | Optional: \{\} <br /> |


#### CloneType

_Underlying type:_ _string_

CloneType represents the type of clone operation. FullClone and
LinkedClone are acted on; InstantClone is accepted but made as a full
clone.

_Validation:_
- Enum: [FullClone LinkedClone InstantClone]

_Appears in:_
- [CloneOptions](#cloneoptions)
- [VMCloneStatus](#vmclonestatus)

| Field | Description |
| --- | --- |
| `FullClone` | CloneTypeFullClone creates a full independent copy of the source's<br />disks.<br /> |
| `LinkedClone` | CloneTypeLinkedClone creates a copy-on-write clone that depends on the<br />source's disk. The vSphere and Proxmox providers support it (Proxmox from<br />a template source only); libvirt does not.<br /> |
| `InstantClone` | CloneTypeInstantClone is accepted but not acted on in this release: a<br />full clone is made.<br /> |


#### CloudInit



CloudInit defines cloud-init configuration



_Appears in:_
- [UserData](#userdata)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `inline` _string_ | Inline contains inline cloud-init data |  | Optional: \{\} <br /> |
| `secretRef` _[LocalObjectReference](#localobjectreference)_ | SecretRef references a Secret containing cloud-init data |  | Optional: \{\} <br /> |


#### CloudInitMetaData



CloudInitMetaData defines cloud-init metadata configuration



_Appears in:_
- [MetaData](#metadata)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `inline` _string_ | Inline contains inline cloud-init metadata in YAML format |  | Optional: \{\} <br /> |
| `secretRef` _[LocalObjectReference](#localobjectreference)_ | SecretRef references a Secret containing cloud-init metadata |  | Optional: \{\} <br /> |


#### ClusterAffinityRule



ClusterAffinityRule defines cluster affinity rules. Accepted but not acted
on in this release.



_Appears in:_
- [AffinityRules](#affinityrules)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled indicates if cluster affinity is enabled. Accepted but not acted<br />on in this release. |  |  |
| `preferredClusters` _string array_ | PreferredClusters lists preferred clusters. Accepted but not acted on in<br />this release. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `scope` _string_ | Scope defines the scope of the affinity rule. Accepted but not acted on in<br />this release. |  | Enum: [strict preferred] <br />Optional: \{\} <br /> |


#### ClusterAntiAffinityRule



ClusterAntiAffinityRule defines cluster anti-affinity rules. Accepted but
not acted on in this release.



_Appears in:_
- [AntiAffinityRules](#antiaffinityrules)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled indicates if cluster anti-affinity is enabled. Accepted but not<br />acted on in this release. |  |  |
| `maxVMsPerCluster` _integer_ | MaxVMsPerCluster limits the number of VMs per cluster. Accepted but not<br />acted on in this release. |  | Maximum: 10000 <br />Minimum: 1 <br />Optional: \{\} <br /> |
| `scope` _string_ | Scope defines the scope of the anti-affinity rule. Accepted but not acted<br />on in this release. |  | Enum: [strict preferred] <br />Optional: \{\} <br /> |


#### ConnectionPooling



ConnectionPooling defines connection pooling settings. Accepted but not acted
on in this release.



_Appears in:_
- [ProviderSpec](#providerspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `maxConnections` _integer_ | MaxConnections is the maximum number of connections to maintain | 10 | Maximum: 100 <br />Minimum: 1 <br />Optional: \{\} <br /> |
| `maxIdleConnections` _integer_ | MaxIdleConnections is the maximum number of idle connections | 5 | Minimum: 1 <br />Optional: \{\} <br /> |
| `connectionTimeout` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | ConnectionTimeout is the timeout for establishing connections | 30s | Optional: \{\} <br /> |
| `idleTimeout` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | IdleTimeout is the timeout for idle connections | 5m | Optional: \{\} <br /> |


#### ContentLibraryRef



ContentLibraryRef references a vSphere content library item. Accepted but not
acted on in this release (see VSphereImageSource.ContentLibrary).



_Appears in:_
- [VSphereImageSource](#vsphereimagesource)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `library` _string_ | Library is the name of the content library. Accepted but not acted on in<br />this release. |  | MaxLength: 255 <br /> |
| `item` _string_ | Item is the name of the library item. Accepted but not acted on in this<br />release. |  | MaxLength: 255 <br /> |
| `version` _string_ | Version specifies the item version (optional). Accepted but not acted on<br />in this release. |  | Optional: \{\} <br /> |


#### CustomizationStatus



CustomizationStatus contains customization operation status. Not
populated in this release.



_Appears in:_
- [VMCloneStatus](#vmclonestatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `started` _boolean_ | Started indicates if customization has started. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `completed` _boolean_ | Completed indicates if customization has completed. Not populated in<br />this release. |  | Optional: \{\} <br /> |
| `completedSteps` _string array_ | CompletedSteps lists completed customization steps. Not populated in<br />this release. |  | Optional: \{\} <br /> |
| `failedSteps` _string array_ | FailedSteps lists failed customization steps. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `currentStep` _string_ | CurrentStep is the current customization step. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `message` _string_ | Message provides customization status details. Not populated in this<br />release. |  | Optional: \{\} <br /> |


#### DHCPConfig



DHCPConfig defines DHCP configuration. Accepted but not acted on in this
release.



_Appears in:_
- [IPAllocationConfig](#ipallocationconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `clientID` _string_ | ClientID specifies the DHCP client ID. Accepted but not acted on in this<br />release. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `hostname` _string_ | Hostname specifies the hostname to request. Accepted but not acted on in<br />this release. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `options` _object (keys:string, values:string)_ | Options contains DHCP options. Accepted but not acted on in this release. |  | MaxProperties: 20 <br />Optional: \{\} <br /> |


#### DNSConfig



DNSConfig defines DNS configuration. Accepted but not acted on in this
release.



_Appears in:_
- [IPAllocationConfig](#ipallocationconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `servers` _string array_ | Servers contains DNS server addresses. Accepted but not acted on in this<br />release. |  | MaxItems: 10 <br />Optional: \{\} <br /> |
| `searchDomains` _string array_ | SearchDomains contains DNS search domains. Accepted but not acted on in<br />this release. |  | MaxItems: 10 <br />Optional: \{\} <br /> |
| `options` _object (keys:string, values:string)_ | Options contains DNS resolver options. Accepted but not acted on in this<br />release. |  | MaxProperties: 10 <br />Optional: \{\} <br /> |


#### DataVolumeImageSource



DataVolumeImageSource defines DataVolume-based image configuration. Accepted
but not acted on in this release: no controller or provider reads a
DataVolume.



_Appears in:_
- [ImageSource](#imagesource)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the name of the DataVolume. Accepted but not acted on in this<br />release. |  | MaxLength: 253 <br />Pattern: `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$` <br /> |
| `namespace` _string_ | Namespace is the namespace of the DataVolume (defaults to the image's<br />namespace). Accepted but not acted on in this release. |  | MaxLength: 63 <br />Pattern: `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$` <br />Optional: \{\} <br /> |


#### DatastoreAffinityRule



DatastoreAffinityRule defines datastore affinity rules. Accepted but not
acted on in this release.



_Appears in:_
- [AffinityRules](#affinityrules)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled indicates if datastore affinity is enabled. Accepted but not acted<br />on in this release. |  |  |
| `preferredDatastores` _string array_ | PreferredDatastores lists preferred datastores. Accepted but not acted on<br />in this release. |  | MaxItems: 50 <br />Optional: \{\} <br /> |
| `scope` _string_ | Scope defines the scope of the affinity rule. Accepted but not acted on in<br />this release. |  | Enum: [strict preferred] <br />Optional: \{\} <br /> |


#### DatastoreAntiAffinityRule



DatastoreAntiAffinityRule defines datastore anti-affinity rules. Accepted
but not acted on in this release.



_Appears in:_
- [AntiAffinityRules](#antiaffinityrules)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled indicates if datastore anti-affinity is enabled. Accepted but not<br />acted on in this release. |  |  |
| `maxVMsPerDatastore` _integer_ | MaxVMsPerDatastore limits the number of VMs per datastore. Accepted but<br />not acted on in this release. |  | Maximum: 10000 <br />Minimum: 1 <br />Optional: \{\} <br /> |
| `scope` _string_ | Scope defines the scope of the anti-affinity rule. Accepted but not acted<br />on in this release. |  | Enum: [strict preferred] <br />Optional: \{\} <br /> |


#### DiskCloneProgress



DiskCloneProgress shows the progress of cloning a single disk. Not
populated in this release.



_Appears in:_
- [CloneProgress](#cloneprogress)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the disk name. Not populated in this release. |  |  |
| `totalBytes` _integer_ | TotalBytes is the total size of the disk. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `completedBytes` _integer_ | CompletedBytes is the number of bytes completed. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `percentage` _integer_ | Percentage is the completion percentage (0-100). Not populated in this<br />release. |  | Maximum: 100 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `transferRate` _integer_ | TransferRate is the current transfer rate in bytes per second. Not<br />populated in this release. |  | Optional: \{\} <br /> |


#### DiskDefaults



DiskDefaults provides default disk settings. See VMClassSpec.DiskDefaults
for which fields are acted on.



_Appears in:_
- [VMClassSpec](#vmclassspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `type` _[DiskType](#disktype)_ | Type specifies the default disk type. Accepted but not acted on in this<br />release. | thin | Enum: [thin thick eagerzeroedthick ssd hdd nvme] <br />Optional: \{\} <br /> |
| `size` _[Quantity](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#quantity-resource-api)_ | Size specifies the default root disk size. libvirt sizes the root disk<br />to it (a disk grown from an image is never shrunk) and vSphere grows the<br />root disk to it after creation (it never shrinks a disk); Proxmox and mock<br />ignore it. It must be<br />non-negative and below 1Pi: every value below 900Ti written in bytes,<br />k/Ki, M/Mi, G/Gi or T/Ti is accepted, and nothing at or above 1Pi is.<br />That is more than ten times the largest single virtual disk vSphere<br />supports (62 TB), and keeps the GiB value the provider contract carries<br />far inside its int32 range. The rules bound the number of integer<br />digits per unit suffix with core CEL only (no quantity library, which<br />Kubernetes < 1.29 lacks), so they are enforced on every supported<br />Kubernetes version. | 40Gi | Optional: \{\} <br /> |
| `iops` _integer_ | IOPS specifies the default IOPS limit. Accepted but not acted on in<br />this release. |  | Maximum: 100000 <br />Minimum: 100 <br />Optional: \{\} <br /> |
| `storageClass` _string_ | StorageClass specifies the default storage class. Accepted but not<br />acted on in this release. |  | MaxLength: 253 <br />Optional: \{\} <br /> |




#### DiskSpec



DiskSpec defines a disk configuration



_Appears in:_
- [MigrationTarget](#migrationtarget)
- [VMCloneTarget](#vmclonetarget)
- [VirtualMachineSpec](#virtualmachinespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the disk identifier |  | MaxLength: 63 <br />Pattern: `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$` <br /> |
| `sizeGiB` _integer_ | SizeGiB is the size of the disk in GiB |  | Maximum: 65536 <br />Minimum: 1 <br /> |
| `type` _string_ | Type specifies the disk type (provider-specific) | thin | Enum: [thin thick eagerzeroedthick ssd hdd] <br />Optional: \{\} <br /> |
| `expandPolicy` _string_ | ExpandPolicy defines how the disk can be expanded. Accepted but not acted on<br />in this release: it is not sent to the provider. | Offline | Enum: [Online Offline] <br />Optional: \{\} <br /> |
| `storageClass` _string_ | StorageClass specifies the storage class (optional). Accepted but not acted<br />on in this release: it is not sent to the provider. |  | Optional: \{\} <br /> |
| `scsi` _[SCSIControllerSpec](#scsicontrollerspec)_ | SCSI specifies SCSI controller configuration (vSphere only). Accepted but not<br />acted on in this release: the manager sends only the disk's name, sizeGiB<br />and type to the provider. |  | Optional: \{\} <br /> |


#### DiskType

_Underlying type:_ _string_

DiskType represents the type of disk provisioning

_Validation:_
- Enum: [thin thick eagerzeroedthick ssd hdd nvme]

_Appears in:_
- [CloneStorageOptions](#clonestorageoptions)
- [DiskDefaults](#diskdefaults)

| Field | Description |
| --- | --- |
| `thin` | DiskTypeThin indicates thin provisioned disks<br /> |
| `thick` | DiskTypeThick indicates thick provisioned disks<br /> |
| `eagerzeroedthick` | DiskTypeEagerZeroedThick indicates eager zeroed thick provisioned disks<br /> |
| `ssd` | DiskTypeSSD indicates SSD storage<br /> |
| `hdd` | DiskTypeHDD indicates HDD storage<br /> |
| `nvme` | DiskTypeNVMe indicates NVMe storage<br /> |


#### DistributedSwitchConfig



DistributedSwitchConfig defines distributed virtual switch configuration.
Accepted but not acted on in this release.



_Appears in:_
- [VSphereNetworkConfig](#vspherenetworkconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the name of the distributed switch. Accepted but not acted on in<br />this release. |  | MaxLength: 255 <br /> |
| `uuid` _string_ | UUID is the UUID of the distributed switch (optional). Accepted but not<br />acted on in this release. |  | Optional: \{\} <br /> |
| `portgroupType` _string_ | PortgroupType specifies the type of portgroup. Accepted but not acted on<br />in this release. |  | Enum: [ephemeral distributed] <br />Optional: \{\} <br /> |


#### DomainJoinSpec



DomainJoinSpec defines domain join configuration. Accepted but not acted
on in this release.



_Appears in:_
- [SysprepCustomization](#sysprepcustomization)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `domain` _string_ | Domain is the domain name to join. Accepted but not acted on in this<br />release. |  | MaxLength: 255 <br /> |
| `username` _string_ | Username is the domain join username. Accepted but not acted on in this<br />release. |  | MaxLength: 255 <br /> |
| `password` _[PasswordSpec](#passwordspec)_ | Password is the domain join password. Accepted but not acted on in this<br />release. |  |  |
| `organizationalUnit` _string_ | OrganizationalUnit specifies the OU for the computer account. Accepted<br />but not acted on in this release. |  | MaxLength: 500 <br />Optional: \{\} <br /> |


#### EncryptionPolicy



EncryptionPolicy defines VM encryption settings. Accepted but not acted
on in this release.



_Appears in:_
- [SecurityProfile](#securityprofile)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled indicates if encryption should be used. Accepted but not acted<br />on in this release. | false |  |
| `keyProvider` _string_ | KeyProvider specifies the encryption key provider. Accepted but not<br />acted on in this release. |  | Enum: [standard hardware external] <br />Optional: \{\} <br /> |
| `requireEncryption` _boolean_ | RequireEncryption mandates encryption (fails if not available).<br />Accepted but not acted on in this release. | false | Optional: \{\} <br /> |


#### ExecAction



ExecAction describes a command to be executed



_Appears in:_
- [LifecycleHandler](#lifecyclehandler)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `command` _string array_ | Command is the command line to execute |  | MinItems: 1 <br /> |


#### FirewallConfig



FirewallConfig defines firewall configuration. Accepted but not acted on in
this release.



_Appears in:_
- [NetworkSecurityConfig](#networksecurityconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled indicates if firewall is enabled. Accepted but not acted on in<br />this release. | false | Optional: \{\} <br /> |
| `defaultPolicy` _string_ | DefaultPolicy specifies the default firewall policy. Accepted but not<br />acted on in this release. | ACCEPT | Enum: [ACCEPT DROP REJECT] <br />Optional: \{\} <br /> |
| `rules` _[FirewallRule](#firewallrule) array_ | Rules contains firewall rules. Accepted but not acted on in this release. |  | MaxItems: 100 <br />Optional: \{\} <br /> |


#### FirewallRule



FirewallRule defines a firewall rule. Accepted but not acted on in this
release.



_Appears in:_
- [FirewallConfig](#firewallconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the rule name. Accepted but not acted on in this release. |  | MaxLength: 255 <br /> |
| `action` _string_ | Action specifies the rule action. Accepted but not acted on in this<br />release. |  | Enum: [ACCEPT DROP REJECT] <br /> |
| `direction` _string_ | Direction specifies the traffic direction. Accepted but not acted on in<br />this release. |  | Enum: [in out inout] <br /> |
| `protocol` _string_ | Protocol specifies the protocol. Accepted but not acted on in this<br />release. |  | Enum: [tcp udp icmp all] <br />Optional: \{\} <br /> |
| `sourceCIDR` _string_ | SourceCIDR specifies the source CIDR. Accepted but not acted on in this<br />release. |  | Optional: \{\} <br /> |
| `destinationCIDR` _string_ | DestinationCIDR specifies the destination CIDR. Accepted but not acted on<br />in this release. |  | Optional: \{\} <br /> |
| `ports` _[PortRange](#portrange)_ | Ports specifies the port range. Accepted but not acted on in this release. |  | Optional: \{\} <br /> |
| `priority` _integer_ | Priority specifies the rule priority. Accepted but not acted on in this<br />release. |  | Maximum: 1000 <br />Minimum: 1 <br />Optional: \{\} <br /> |


#### FirmwareType

_Underlying type:_ _string_

FirmwareType represents the firmware type for VMs. See
VMClassSpec.Firmware for which providers read it.

_Validation:_
- Enum: [BIOS UEFI EFI]

_Appears in:_
- [VMClassSpec](#vmclassspec)

| Field | Description |
| --- | --- |
| `BIOS` | FirmwareTypeBIOS indicates BIOS firmware<br /> |
| `UEFI` | FirmwareTypeUEFI indicates UEFI firmware<br /> |
| `EFI` | FirmwareTypeEFI is accepted by the schema, but the vSphere and libvirt<br />providers recognise only UEFI: there, EFI selects BIOS firmware (unless<br />secure boot — or, on vSphere, a TPM — forces EFI).<br /> |


#### GPUConfig



GPUConfig defines GPU configuration for a VM. Accepted but not acted on in
this release.



_Appears in:_
- [VirtualMachineResources](#virtualmachineresources)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `count` _integer_ | Count specifies the number of GPUs to assign |  | Maximum: 8 <br />Minimum: 1 <br /> |
| `type` _string_ | Type specifies the GPU type (provider-specific) |  | Pattern: `^[a-zA-Z0-9-_]+$` <br />Optional: \{\} <br /> |
| `memory` _integer_ | Memory specifies GPU memory in MiB |  | Minimum: 512 <br />Optional: \{\} <br /> |


#### GuestCommand



GuestCommand defines a command to run in the guest OS. Accepted but not
acted on in this release.



_Appears in:_
- [VMCustomization](#vmcustomization)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `command` _string_ | Command is the command to execute. Accepted but not acted on in this<br />release, and not sent to the provider. It is stored in plaintext in the<br />VMClone: do not put a credential in it. |  | MaxLength: 1000 <br /> |
| `arguments` _string array_ | Arguments contains command arguments. Accepted but not acted on in this<br />release, and not sent to the provider. They are stored in plaintext in<br />the VMClone: do not put a credential in them. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `workingDirectory` _string_ | WorkingDirectory specifies the working directory. Accepted but not<br />acted on in this release. |  | MaxLength: 500 <br />Optional: \{\} <br /> |
| `runAsUser` _string_ | RunAsUser specifies the user to run the command as. Accepted but not<br />acted on in this release. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `timeout` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | Timeout specifies the command timeout. Accepted but not acted on in<br />this release. | 5m | Optional: \{\} <br /> |
| `stage` _string_ | Stage specifies when to run the command. Accepted but not acted on in<br />this release. | post-customization | Enum: [pre-customization post-customization first-boot] <br />Optional: \{\} <br /> |


#### GuestToolsPolicy

_Underlying type:_ _string_

GuestToolsPolicy represents the guest tools installation policy. Accepted
but not acted on in this release.

_Validation:_
- Enum: [install skip upgrade uninstall]

_Appears in:_
- [VMClassSpec](#vmclassspec)

| Field | Description |
| --- | --- |
| `install` | GuestToolsPolicyInstall installs guest tools if not present<br /> |
| `skip` | GuestToolsPolicySkip skips guest tools installation<br /> |
| `upgrade` | GuestToolsPolicyUpgrade upgrades guest tools if present<br /> |
| `uninstall` | GuestToolsPolicyUninstall removes guest tools if present<br /> |


#### HTTPAuthentication



HTTPAuthentication defines HTTP authentication options. Accepted but not
acted on in this release: the referenced Secrets are never read.



_Appears in:_
- [HTTPImageSource](#httpimagesource)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `basicAuth` _[BasicAuthConfig](#basicauthconfig)_ | BasicAuth contains basic authentication configuration. Accepted but not<br />acted on in this release. |  | Optional: \{\} <br /> |
| `bearer` _[BearerTokenConfig](#bearertokenconfig)_ | Bearer contains bearer token authentication. Accepted but not acted on in<br />this release. |  | Optional: \{\} <br /> |
| `clientCert` _[ClientCertConfig](#clientcertconfig)_ | ClientCert contains client certificate authentication. Accepted but not<br />acted on in this release. |  | Optional: \{\} <br /> |


#### HTTPGetAction



HTTPGetAction describes an HTTP GET request



_Appears in:_
- [LifecycleHandler](#lifecyclehandler)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `path` _string_ | Path is the HTTP path to access |  |  |
| `port` _integer_ | Port is the port to access |  | Maximum: 65535 <br />Minimum: 1 <br /> |
| `host` _string_ | Host name to connect to (defaults to VM IP) |  | Optional: \{\} <br /> |
| `scheme` _string_ | Scheme to use for connecting (HTTP or HTTPS) | HTTP | Enum: [HTTP HTTPS] <br />Optional: \{\} <br /> |


#### HTTPImageSource



HTTPImageSource defines HTTP/HTTPS download configuration. Accepted but not
acted on in this release: no provider downloads from an http source, and none
of its fields is read (the Proxmox provider reads url only to refuse it).



_Appears in:_
- [ImageSource](#imagesource)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `url` _string_ | URL is the HTTP/HTTPS URL to download the image. Accepted but not acted on<br />in this release. |  | Pattern: `^https?://.*` <br /> |
| `headers` _object (keys:string, values:string)_ | Headers contains HTTP headers to include in the request. Accepted but not<br />acted on in this release. |  | MaxProperties: 20 <br />Optional: \{\} <br /> |
| `checksum` _string_ | Checksum provides expected checksum for verification. Accepted but not<br />acted on in this release. |  | Optional: \{\} <br /> |
| `checksumType` _[ChecksumType](#checksumtype)_ | ChecksumType specifies the checksum algorithm. Accepted but not acted on<br />in this release. | sha256 | Enum: [md5 sha1 sha256 sha512] <br />Optional: \{\} <br /> |
| `authentication` _[HTTPAuthentication](#httpauthentication)_ | Authentication contains authentication configuration. Accepted but not<br />acted on in this release: no credentials are read or sent. |  | Optional: \{\} <br /> |
| `timeout` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | Timeout specifies the download timeout. Accepted but not acted on in this<br />release. | 30m | Optional: \{\} <br /> |


#### Host



Host is the Schema for the hosts API: one bare hypervisor host registered into
a clustered Provider's HostPool. It does not affect single-host
(spec.topology=single) providers.



_Appears in:_
- [HostList](#hostlist)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `Host` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[HostSpec](#hostspec)_ |  |  |  |
| `status` _[HostStatus](#hoststatus)_ |  |  |  |


#### HostAffinityRule



HostAffinityRule prefers, or requires, the listed Hosts.



_Appears in:_
- [AffinityRules](#affinityrules)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled turns the rule on. A rule that is not enabled is ignored. |  |  |
| `preferredHosts` _string array_ | PreferredHosts lists Hosts by resource name. |  | MaxItems: 50 <br />Optional: \{\} <br /> |
| `scope` _string_ | Scope defines how the rule is applied. With strict, only the listed Hosts<br />are candidates. With preferred or no value, a listed Host ranks higher. |  | Enum: [strict preferred] <br />Optional: \{\} <br /> |


#### HostAntiAffinityRule



HostAntiAffinityRule limits the number of VMs on one Host. Only VMs in the
namespace of the VM being placed are counted.



_Appears in:_
- [AntiAffinityRules](#antiaffinityrules)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled turns the rule on. A rule that is not enabled is ignored. |  |  |
| `maxVMsPerHost` _integer_ | MaxVMsPerHost is the number of VMs a Host may run under the rule. A Host<br />that already runs this many is at the limit. The scheduler uses 1 when it<br />is not set. |  | Maximum: 1000 <br />Minimum: 1 <br />Optional: \{\} <br /> |
| `scope` _string_ | Scope defines how the rule is applied. With strict, a Host at the limit is<br />not a candidate. With preferred or no value, a Host at the limit ranks<br />lower. |  | Enum: [strict preferred] <br />Optional: \{\} <br /> |


#### HostHealth

_Underlying type:_ _string_

HostHealth is the live health of a Host, observed by the operator's inventory
sync from the clustered provider (the ListHosts and GetHostInfo calls).

_Validation:_
- Enum: [Ready NotReady Unknown]

_Appears in:_
- [HostStatus](#hoststatus)

| Field | Description |
| --- | --- |
| `Ready` | HostHealthReady indicates the host is reachable and the provider could<br />read its inventory (for libvirt, a virsh nodeinfo over SSH succeeded).<br /> |
| `NotReady` | HostHealthNotReady indicates the host was probed but is not currently<br />usable for placement or migration.<br /> |
| `Unknown` | HostHealthUnknown indicates the host's health has not yet been determined<br />(e.g. before the first successful heartbeat).<br /> |


#### HostList



HostList contains a list of Host.





| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `HostList` | | |
| `metadata` _[ListMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#listmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `items` _[Host](#host) array_ |  |  |  |


#### HostPool



HostPool is the Schema for the hostpools API: a named group of Hosts under one
clustered Provider, carrying cluster scheduling and migration policy. It does
not affect single-host (spec.topology=single) providers.



_Appears in:_
- [HostPoolList](#hostpoollist)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `HostPool` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[HostPoolSpec](#hostpoolspec)_ |  |  |  |
| `status` _[HostPoolStatus](#hostpoolstatus)_ |  |  |  |


#### HostPoolList



HostPoolList contains a list of HostPool.





| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `HostPoolList` | | |
| `metadata` _[ListMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#listmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `items` _[HostPool](#hostpool) array_ |  |  |  |


#### HostPoolSpec



HostPoolSpec is admin-authored cluster policy for a named group of Hosts under
one clustered Provider: scheduling strategy, overcommit, storage/network
references, and the default migration policy. Only strategy and overcommit
affect placement in this release.

Same-namespace model (security): a HostPool lives in its clustered Provider's
namespace, alongside that Provider's Hosts, so ProviderRef is a
LocalObjectReference (see HostSpec).



_Appears in:_
- [HostPool](#hostpool)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `providerRef` _[LocalObjectReference](#localobjectreference)_ | ProviderRef is the clustered Provider that owns this pool. It must be in<br />the HostPool's own namespace (no cross-namespace pool injection). |  |  |
| `strategy` _string_ | Strategy is the scheduling strategy for VMs placed in this pool: Spread<br />balances VMs across the hosts, BinPack fills the fewest hosts first.<br />Defaults to Spread. | Spread | Enum: [Spread BinPack] <br />Optional: \{\} <br /> |
| `overcommit` _[OvercommitRatios](#overcommitratios)_ | Overcommit ratios the scheduler applies to each host's CPU and memory when<br />it checks whether a new VM fits. |  | Optional: \{\} <br /> |
| `storagePools` _[StoragePoolRef](#storagepoolref) array_ | StoragePools are the named shared/local storage pools available in this<br />pool. Per-host visibility is asserted via Host.spec.labels. Consumed, not<br />deployed, by VirtRigaud. Descriptive: no controller reads this list. |  | Optional: \{\} <br /> |
| `networks` _[PoolNetworkRef](#poolnetworkref) array_ | Networks are the named networks (bridge/VLAN/overlay) available in this<br />pool; per-host presence is asserted via Host.spec.labels. Descriptive: no<br />controller reads this list. |  | Optional: \{\} <br /> |
| `migration` _[PoolMigrationPolicy](#poolmigrationpolicy)_ | Migration is the default migration policy for VMs in this pool. Accepted but<br />not acted on in this release. |  | Optional: \{\} <br /> |


#### HostPoolStatus



HostPoolStatus aggregates member-host counts and readiness for the pool. The
HostPool controller writes it whenever a member Host joins, leaves, or
changes health, schedulability, providerRef or deletion state. Its Ready
condition is True when SchedulableHosts > 0.

A count of 0 (an empty pool, or no schedulable host) is written as 0 rather
than omitted, so it shows in the status and in the kubectl get columns.



_Appears in:_
- [HostPool](#hostpool)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `totalHosts` _integer_ | TotalHosts is the number of Hosts whose spec.poolRef points at this pool.<br />Only Hosts in the pool's own namespace are members (the same-namespace<br />model); a Host being deleted is counted until it is gone. |  | Optional: \{\} <br /> |
| `readyHosts` _integer_ | ReadyHosts is the number of member Hosts reporting Health=Ready. |  | Optional: \{\} <br /> |
| `schedulableHosts` _integer_ | SchedulableHosts is the number of member Hosts that are both Health=Ready<br />and spec.schedulable=true, and that the scheduler can therefore place a<br />new VM on: a Host being deleted, or one whose spec.providerRef is not the<br />pool's Provider, is never a placement target and is not counted. |  | Optional: \{\} <br /> |
| `observedGeneration` _integer_ | ObservedGeneration reflects the generation of the HostPool spec observed by<br />the controller. |  | Optional: \{\} <br /> |
| `conditions` _[Condition](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#condition-v1-meta) array_ | Conditions represent the latest available observations of the pool's state. |  | Optional: \{\} <br /> |


#### HostSpec



HostSpec is admin-authored desired inventory: one bare hypervisor host that a
clustered Provider (spec.topology=cluster) executes on. The admin
declares which hosts exist; the provider reports what they can do right now
(see HostStatus).

Same-namespace model (security): a Host, its HostPool, its optional credential
Secret, and the clustered Provider it names all live in ONE namespace — the
Provider's. Every reference on this spec is therefore a LocalObjectReference
(no namespace field). A Host in another namespace can neither enrol itself
into a Provider's inventory nor point the operator at a credential Secret in
a namespace its author does not control: the inventory render lists Hosts and
resolves credential Secrets in the Provider's namespace only.



_Appears in:_
- [Host](#host)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `providerRef` _[LocalObjectReference](#localobjectreference)_ | ProviderRef is the clustered Provider that executes on this host. It must<br />be in the Host's own namespace: a Host can only be fronted by a Provider in<br />the same namespace (no cross-namespace inventory injection). |  |  |
| `poolRef` _[LocalObjectReference](#localobjectreference)_ | PoolRef is the HostPool this host belongs to. Membership is declared by the<br />host itself (Host.spec.poolRef names the HostPool), not by the pool. |  |  |
| `endpoint` _string_ | Endpoint is the host connection URI. Only these shapes are accepted:<br />qemu+ssh://[user@]host[:port]/system, qemu+ssh://[user@]host[:port]/session,<br />and grpc://host:port. The host is a DNS name, an IPv4 address, or a<br />bracketed IPv6 address. No query string, fragment, percent-encoding, or<br />other path is allowed.<br />The only clustered provider type today is libvirt, and it connects to a<br />host over SSH with the qemu+ssh:// form only (the user, port and<br />system\|session instance come from the URI; the SSH key and known_hosts<br />come from the credentials Secret). A grpc://host:port value passes<br />validation but the libvirt provider refuses to connect to it, so the host<br />cannot become Ready and is never used for placement; use qemu+ssh://. |  | MaxLength: 512 <br />MinLength: 1 <br />Pattern: `^(qemu\+ssh://([A-Za-z0-9._-]+@)?([A-Za-z0-9]([A-Za-z0-9-]\{0,61\}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]\{0,61\}[A-Za-z0-9])?)*\|\[[0-9A-Fa-f:.]+\])(:[0-9]\{1,5\})?/(system\|session)\|grpc://([A-Za-z0-9]([A-Za-z0-9-]\{0,61\}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]\{0,61\}[A-Za-z0-9])?)*\|\[[0-9A-Fa-f:.]+\]):[0-9]\{1,5\})$` <br /> |
| `credentialSecretRef` _[LocalObjectReference](#localobjectreference)_ | CredentialSecretRef optionally overrides the Provider's credentials for<br />this host (SSH key / known_hosts material). Defaults to the Provider's.<br />The Secret must be in the Host's (= the Provider's) namespace: the operator<br />never reads a credential Secret from another namespace on a Host's behalf,<br />so a Host author cannot exfiltrate a Secret they cannot already read. |  | Optional: \{\} <br /> |
| `labels` _object (keys:string, values:string)_ | Labels are placement facts: storage-pool visibility, network/bridge<br />visibility, zone/rack, e.g. \{"storage.virtrigaud.io/pool-nfs01":"true",<br />"net.virtrigaud.io/br-vlan100":"true","topology.virtrigaud.io/rack":"r7"\}.<br />The scheduler treats them as hard constraints: a host is a candidate for a<br />VM only if it carries net.virtrigaud.io/<network>="true" for every<br />network the VM's VMNetworkAttachments name (<network> is the attachment's<br />libvirt networkName, or its bridge name when networkName is empty), and<br />the labels the VM's VMPlacementPolicy hard nodeSelector requires.<br />storage.virtrigaud.io/pool-<name> labels are accepted, but a VM create is<br />not checked against them. |  | Optional: \{\} <br /> |
| `schedulable` _boolean_ | Schedulable, when false, cordons the host: no new VM is placed on it, and<br />VMs already on it stay where they are (VirtRigaud does not move or<br />evacuate them). Defaults true. | true | Optional: \{\} <br /> |


#### HostStatus



HostStatus is operator-synced observed state from the provider's ListHosts and
GetHostInfo calls. It carries capacity and health only, never connection
secrets.



_Appears in:_
- [Host](#host)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `health` _[HostHealth](#hosthealth)_ | Health is the live host health as last observed by the inventory sync<br />(for libvirt, whether a virsh nodeinfo over SSH succeeded). Only Ready<br />hosts are placement candidates. |  | Enum: [Ready NotReady Unknown] <br />Optional: \{\} <br /> |
| `allocatableCPU` _integer_ | AllocatableCPU is the schedulable vCPU capacity the provider reports live. |  | Optional: \{\} <br /> |
| `allocatableMemoryMiB` _integer_ | AllocatableMemoryMiB is the schedulable memory in MiB the provider reports<br />live. |  | Optional: \{\} <br /> |
| `allocatableStorageBytes` _integer_ | AllocatableStorageBytes is the free storage in bytes the provider reports<br />live for new VM disks: for libvirt, the space available to non-root users<br />in the default storage pool's directory (statvfs, measured on every<br />sync), and 0 when it cannot be measured. |  | Optional: \{\} <br /> |
| `cpuModel` _string_ | CPUModel is the host CPU baseline model as the provider reports it.<br />Informational: no controller reads it. |  | Optional: \{\} <br /> |
| `cpuFeatures` _string array_ | CPUFeatures are the host CPU features as the provider reports them. The<br />scheduler matches a VMPlacementPolicy's required CPU features against them. |  | Optional: \{\} <br /> |
| `machineTypes` _string array_ | MachineTypes are the machine types the host supports, as the provider<br />reports them. |  | Optional: \{\} <br /> |
| `emulatorVersion` _string_ | EmulatorVersion is the host emulator version as the provider reports it.<br />Informational: no controller reads it. |  | Optional: \{\} <br /> |
| `boundVMs` _integer_ | BoundVMs is reserved for the count of VMs bound to this host. It is not<br />populated in this release and stays 0 (omitted); count the VirtualMachines<br />whose status.placement.host names this Host instead. |  | Optional: \{\} <br /> |
| `lastHeartbeatTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LastHeartbeatTime is when the operator last successfully synced this host. |  | Optional: \{\} <br /> |
| `observedGeneration` _integer_ | ObservedGeneration reflects the generation of the Host spec observed by the<br />controller. |  | Optional: \{\} <br /> |
| `conditions` _[Condition](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#condition-v1-meta) array_ | Conditions represent the latest available observations of the host's state. |  | Optional: \{\} <br /> |


#### IPAllocation



IPAllocation represents an IP allocation. Not populated in this release.



_Appears in:_
- [VMNetworkAttachmentStatus](#vmnetworkattachmentstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `vm` _string_ | VM is the VM name that has the IP allocated. Not populated in this<br />release. |  |  |
| `ip` _string_ | IP is the allocated IP address. Not populated in this release. |  |  |
| `mac` _string_ | MAC is the allocated MAC address. Not populated in this release. |  | Optional: \{\} <br /> |
| `allocatedAt` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | AllocatedAt is when the IP was allocated. Not populated in this release. |  | Optional: \{\} <br /> |
| `leaseExpiry` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LeaseExpiry is when the IP lease expires (for DHCP). Not populated in this<br />release. |  | Optional: \{\} <br /> |


#### IPAllocationConfig



IPAllocationConfig defines IP address allocation settings. Accepted but not
acted on in this release.



_Appears in:_
- [VMNetworkAttachmentSpec](#vmnetworkattachmentspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `type` _[IPAllocationType](#ipallocationtype)_ | Type specifies the IP allocation type. Accepted but not acted on in this<br />release. | DHCP | Enum: [DHCP Static Pool None] <br />Optional: \{\} <br /> |
| `staticConfig` _[StaticIPConfig](#staticipconfig)_ | StaticConfig contains static IP configuration. Accepted but not acted on<br />in this release. |  | Optional: \{\} <br /> |
| `poolConfig` _[IPPoolConfig](#ippoolconfig)_ | PoolConfig contains IP pool configuration. Accepted but not acted on in<br />this release. |  | Optional: \{\} <br /> |
| `dhcpConfig` _[DHCPConfig](#dhcpconfig)_ | DHCPConfig contains DHCP configuration. Accepted but not acted on in this<br />release. |  | Optional: \{\} <br /> |
| `dnsConfig` _[DNSConfig](#dnsconfig)_ | DNSConfig contains DNS configuration. Accepted but not acted on in this<br />release. |  | Optional: \{\} <br /> |


#### IPAllocationType

_Underlying type:_ _string_

IPAllocationType represents the type of IP allocation. Accepted but not
acted on in this release.

_Validation:_
- Enum: [DHCP Static Pool None]

_Appears in:_
- [IPAllocationConfig](#ipallocationconfig)

| Field | Description |
| --- | --- |
| `DHCP` | IPAllocationTypeDHCP uses DHCP for IP allocation<br /> |
| `Static` | IPAllocationTypeStatic uses static IP allocation<br /> |
| `Pool` | IPAllocationTypePool uses an IP pool for allocation<br /> |
| `None` | IPAllocationTypeNone disables IP allocation<br /> |


#### IPPoolConfig



IPPoolConfig defines IP pool configuration. Accepted but not acted on in
this release.



_Appears in:_
- [IPAllocationConfig](#ipallocationconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `poolRef` _[LocalObjectReference](#localobjectreference)_ | PoolRef references an IP pool resource. Accepted but not acted on in this<br />release. |  |  |
| `preferredIP` _string_ | PreferredIP requests a preferred IP from the pool. Accepted but not acted<br />on in this release. |  | Pattern: `^((25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)\.)\{3\}(25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)$` <br />Optional: \{\} <br /> |


#### Ignition



Ignition defines Ignition configuration. Accepted but not acted on in this
release.



_Appears in:_
- [UserData](#userdata)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `inline` _string_ | Inline contains inline Ignition data |  | Optional: \{\} <br /> |
| `secretRef` _[LocalObjectReference](#localobjectreference)_ | SecretRef references a Secret containing Ignition data |  | Optional: \{\} <br /> |


#### ImageFormat

_Underlying type:_ _string_

ImageFormat represents the format of a VM image. The values are descriptive
in this release: no provider acts on an image format declared in a VMImage.

_Validation:_
- Enum: [qcow2 raw vmdk vhd vhdx iso ova ovf]

_Appears in:_
- [ImageOptimization](#imageoptimization)
- [LibvirtImageSource](#libvirtimagesource)
- [RegistryImageSource](#registryimagesource)
- [StoragePrepareOptions](#storageprepareoptions)
- [VMImageStatus](#vmimagestatus)

| Field | Description |
| --- | --- |
| `qcow2` | ImageFormatQCOW2 indicates QEMU QCOW2 format<br /> |
| `raw` | ImageFormatRaw indicates raw disk format<br /> |
| `vmdk` | ImageFormatVMDK indicates VMware VMDK format<br /> |
| `vhd` | ImageFormatVHD indicates Microsoft VHD format<br /> |
| `vhdx` | ImageFormatVHDX indicates Microsoft VHDX format<br /> |
| `iso` | ImageFormatISO indicates ISO format<br /> |
| `ova` | ImageFormatOVA indicates OVA format<br /> |
| `ovf` | ImageFormatOVF indicates OVF format<br /> |


#### ImageImportProgress



ImageImportProgress tracks the progress of image import operations. Not
populated in this release.



_Appears in:_
- [VMImageStatus](#vmimagestatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `totalBytes` _integer_ | TotalBytes is the total size of the image being imported. Not populated in<br />this release. |  | Optional: \{\} <br /> |
| `transferredBytes` _integer_ | TransferredBytes is the number of bytes transferred so far. Not populated<br />in this release. |  | Optional: \{\} <br /> |
| `percentage` _integer_ | Percentage is the completion percentage (0-100). Not populated in this<br />release. |  | Maximum: 100 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `transferRate` _integer_ | TransferRate is the current transfer rate in bytes per second. Not<br />populated in this release. |  | Optional: \{\} <br /> |
| `eta` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | ETA is the estimated time to completion. Not populated in this release. |  | Optional: \{\} <br /> |
| `startTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | StartTime is when the import started. Not populated in this release. |  | Optional: \{\} <br /> |


#### ImageMetadata



ImageMetadata contains image metadata and annotations. Descriptive: no
controller or provider reads any field of it.



_Appears in:_
- [VMImageSpec](#vmimagespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `displayName` _string_ | DisplayName is a human-readable name for the image. Descriptive: no<br />controller reads it. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `description` _string_ | Description provides a description of the image. Descriptive: no<br />controller reads it. |  | MaxLength: 1024 <br />Optional: \{\} <br /> |
| `version` _string_ | Version specifies the image version. Descriptive: no controller reads it. |  | MaxLength: 100 <br />Optional: \{\} <br /> |
| `architecture` _string_ | Architecture specifies the CPU architecture. Descriptive: no controller or<br />provider checks it against the hypervisor. | amd64 | Enum: [amd64 arm64 x86_64 aarch64] <br />Optional: \{\} <br /> |
| `tags` _object (keys:string, values:string)_ | Tags are key-value pairs for categorizing the image. Descriptive: no<br />controller reads them. |  | MaxProperties: 50 <br />Optional: \{\} <br /> |
| `annotations` _object (keys:string, values:string)_ | Annotations are additional metadata annotations. Descriptive: no<br />controller reads them, and they are not copied to the image on the<br />hypervisor. |  | MaxProperties: 50 <br />Optional: \{\} <br /> |


#### ImageMissingAction

_Underlying type:_ _string_

ImageMissingAction defines actions to take when an image is not yet prepared
on the Provider of the VM being created.

_Validation:_
- Enum: [Import Fail Wait]

_Appears in:_
- [ImagePrepare](#imageprepare)

| Field | Description |
| --- | --- |
| `Import` | ImageMissingActionImport prepares the image on the Provider, then creates<br />the VM<br /> |
| `Fail` | ImageMissingActionFail does not prepare the image: the VMImage reports<br />Ready=False with phase Failed and the VM is held until the image is prepared<br />out of band<br /> |
| `Wait` | ImageMissingActionWait does not prepare the image: the VMImage reports<br />Ready=False with phase Pending and the VM is held until the image becomes<br />available out of band<br /> |


#### ImageOptimization



ImageOptimization defines image optimization options. Accepted but not acted
on in this release: no controller or provider reads any field of it.



_Appears in:_
- [ImagePrepare](#imageprepare)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enableCompression` _boolean_ | EnableCompression enables image compression. Accepted but not acted on in<br />this release. | false | Optional: \{\} <br /> |
| `removeUnusedSpace` _boolean_ | RemoveUnusedSpace removes unused space from the image. Accepted but not<br />acted on in this release. | false | Optional: \{\} <br /> |
| `convertFormat` _[ImageFormat](#imageformat)_ | ConvertFormat converts the image to a more optimal format. Accepted but not<br />acted on in this release. |  | Enum: [qcow2 raw vmdk vhd vhdx iso ova ovf] <br />Optional: \{\} <br /> |
| `enableDeltaSync` _boolean_ | EnableDeltaSync enables delta synchronization for updates. Accepted but<br />not acted on in this release. | false | Optional: \{\} <br /> |


#### ImagePhase

_Underlying type:_ _string_

ImagePhase represents the phase of image preparation. The controller sets
Pending, Importing, Ready and Failed; Downloading, Converting and Optimizing
are never set in this release.

_Validation:_
- Enum: [Pending Downloading Importing Converting Optimizing Ready Failed]

_Appears in:_
- [VMImageStatus](#vmimagestatus)

| Field | Description |
| --- | --- |
| `Pending` | ImagePhasePending indicates the image is waiting to be processed<br /> |
| `Downloading` | ImagePhaseDownloading is never set in this release<br /> |
| `Importing` | ImagePhaseImporting indicates the image is being imported<br /> |
| `Converting` | ImagePhaseConverting is never set in this release<br /> |
| `Optimizing` | ImagePhaseOptimizing is never set in this release<br /> |
| `Ready` | ImagePhaseReady indicates the image is ready for use<br /> |
| `Failed` | ImagePhaseFailed indicates the image preparation failed<br /> |


#### ImagePrepare



ImagePrepare defines optional image preparation steps. Only onMissing and
timeout are acted on. validateChecksum, retries, force, storage and
optimization are accepted but not acted on in this release.



_Appears in:_
- [VMImageSpec](#vmimagespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `onMissing` _[ImageMissingAction](#imagemissingaction)_ | OnMissing defines the action to take when the image is not yet prepared<br />on the Provider of the VM being created. Import (the default) prepares<br />it, then creates the VM. Fail and Wait never prepare: the VM is held, and<br />the VMImage is marked Failed or Pending. It applies only to a source that<br />must be imported (a vSphere ovaURL, a libvirt url); an image that names<br />something already on the hypervisor is used as written whatever this says. | Import | Enum: [Import Fail Wait] <br />Optional: \{\} <br /> |
| `validateChecksum` _boolean_ | ValidateChecksum validates the image checksum. Accepted but not acted on<br />in this release: the vSphere and libvirt providers verify the checksum of<br />an image they prepare whenever source.*.checksum is set. | true | Optional: \{\} <br /> |
| `timeout` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | Timeout defines the maximum time to wait for preparation. The libvirt<br />provider uses it as the time limit of the download. The manager and the<br />vSphere and libvirt providers also use twice this value, with a floor of<br />two hours, as the time after which a prepare started by another request<br />that has not finished is treated as abandoned (stalled). The libvirt and<br />vSphere providers cap the value at 7 days. | 30m | Optional: \{\} <br /> |
| `retries` _integer_ | Retries defines the number of retry attempts for failed operations.<br />Accepted but not acted on in this release: the manager retries a failed<br />prepare on its own schedule. | 3 | Maximum: 10 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `force` _boolean_ | Force forces re-import even if image exists. Accepted but not acted on in<br />this release: an existing prepared image for the same source is reused. |  | Optional: \{\} <br /> |
| `storage` _[StoragePrepareOptions](#storageprepareoptions)_ | Storage defines storage-specific preparation options. Accepted but not<br />acted on in this release: the libvirt storage pool comes from<br />source.libvirt.storagePool, and the vSphere import folder from the<br />Provider's spec.defaults.folder. |  | Optional: \{\} <br /> |
| `optimization` _[ImageOptimization](#imageoptimization)_ | Optimization defines image optimization options. Accepted but not acted on<br />in this release. |  | Optional: \{\} <br /> |


#### ImageSource



ImageSource defines the source of the VM image. The vsphere, libvirt and
proxmox sources are acted on by the provider of that kind. The http, registry
and dataVolume sources are accepted but not acted on in this release: no
provider downloads from them, so the vSphere, libvirt and Proxmox providers
refuse to prepare an image that has only such a source (the VMImage reports
reason InvalidSource and VMs that use it are not created). To import from a
URL, use vsphere.ovaURL or libvirt.url.



_Appears in:_
- [VMImageSpec](#vmimagespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `vsphere` _[VSphereImageSource](#vsphereimagesource)_ | VSphere contains vSphere-specific image configuration. It is acted on by<br />the vSphere provider. |  | Optional: \{\} <br /> |
| `libvirt` _[LibvirtImageSource](#libvirtimagesource)_ | Libvirt contains Libvirt-specific image configuration. It is acted on by<br />the libvirt provider. |  | Optional: \{\} <br /> |
| `http` _[HTTPImageSource](#httpimagesource)_ | HTTP contains HTTP/HTTPS download configuration. Accepted but not acted<br />on in this release: no provider downloads from an http source. (The<br />Proxmox provider reads http.url only to refuse it.) |  | Optional: \{\} <br /> |
| `registry` _[RegistryImageSource](#registryimagesource)_ | Registry contains container registry image configuration. Accepted but<br />not acted on in this release. |  | Optional: \{\} <br /> |
| `dataVolume` _[DataVolumeImageSource](#datavolumeimagesource)_ | DataVolume contains DataVolume-based image configuration. Accepted but<br />not acted on in this release. |  | Optional: \{\} <br /> |
| `proxmox` _[ProxmoxImageSource](#proxmoximagesource)_ | Proxmox contains Proxmox VE-specific image configuration. It is acted on<br />by the Proxmox provider. |  | Optional: \{\} <br /> |


#### ImportedDiskRef



ImportedDiskRef references a disk that was imported via migration or other means.
This allows VMs to be created from pre-existing disk images rather than templates.

DiskID may be empty only while MigrationRef is set: the target
VirtualMachine a VMMigration into a clustered Provider creates BEFORE its
import. Such a VM is placed but never
created ("waiting for import") until the migration records the landed disk
in DiskID, Path and Format.



_Appears in:_
- [VirtualMachineSpec](#virtualmachinespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `diskID` _string_ | DiskID is the provider-specific disk identifier.<br />For libvirt, this is typically the volume name. Empty only on a<br />migration's target VirtualMachine that waits for its import<br />(MigrationRef set). |  | MaxLength: 253 <br />Required: \{\} <br /> |
| `path` _string_ | Path is the optional disk path on the provider (e.g., /var/lib/libvirt/images/disk.qcow2).<br />If not specified, the provider will determine the path based on DiskID. |  | Optional: \{\} <br /> |
| `format` _string_ | Format specifies the disk format (qcow2, vmdk, raw, etc.). | qcow2 | Enum: [qcow2 vmdk raw vdi vhdx] <br />Optional: \{\} <br /> |
| `source` _string_ | Source indicates where the disk came from. |  | Enum: [migration clone import snapshot manual] <br />Optional: \{\} <br /> |
| `migrationRef` _[LocalObjectReference](#localobjectreference)_ | MigrationRef references the VMMigration that imported this disk.<br />This provides traceability and audit trail for migrated disks. |  | Optional: \{\} <br /> |
| `sizeGiB` _integer_ | SizeGiB specifies the expected disk size in GiB.<br />Used for validation and capacity planning. |  | Minimum: 1 <br />Optional: \{\} <br /> |


#### KernelInfo



KernelInfo contains kernel information. Descriptive: no controller reads it.



_Appears in:_
- [OSDistribution](#osdistribution)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `version` _string_ | Version is the kernel version. Descriptive: no controller reads it. |  | Optional: \{\} <br /> |
| `type` _string_ | Type is the kernel type. Descriptive: no controller reads it. |  | Enum: [linux windows freebsd other] <br />Optional: \{\} <br /> |


#### LibvirtImageSource



LibvirtImageSource defines Libvirt-specific image configuration. Set path (an
image already on the libvirt host, used as written) or url (an image the
provider downloads and prepares), not both.



_Appears in:_
- [ImageSource](#imagesource)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `path` _string_ | Path is the absolute path of an existing base image file on the libvirt<br />host. It is used by reference: it is never downloaded or prepared, so<br />checksum is not checked for it. The provider copies it into the VM's own<br />disk; it is never attached in place. For security the provider resolves the path on the host<br />(following symlinks) and accepts it only if the result is a regular file<br />directly inside one of the provider's allowed image directories<br />(VIRTRIGAUD_LIBVIRT_IMAGE_DIRS, default /var/lib/libvirt/images), is not<br />a disk of any existing VM, does not use a VirtRigaud-reserved name<br />(*-disk.qcow2, *-migrated.qcow2, dotfiles), and has no backing file or<br />external data file. |  | MaxLength: 4096 <br />Pattern: `^(/+([^/.\x00-\x1f\x7f-\x9f-][^/\x00-\x1f\x7f-\x9f]*\|\.([^/.\x00-\x1f\x7f-\x9f][^/\x00-\x1f\x7f-\x9f]*)?\|\.\.[^/\x00-\x1f\x7f-\x9f]+))+$` <br />Optional: \{\} <br /> |
| `url` _string_ | URL is the location of an image the libvirt provider downloads, on the<br />hypervisor host, when the first VM that uses the image is created (scheme<br />http, https or ftp). The provider converts it to qcow2 and publishes it in<br />the storage pool; every VM created from it gets its own copy. Keep<br />credentials out of the URL. Set url or path, not both. |  | Pattern: `^(https?\|ftp)://.*` <br />Optional: \{\} <br /> |
| `format` _[ImageFormat](#imageformat)_ | Format specifies the image format. Accepted but not acted on in this<br />release: the provider detects the format of the file itself, and converts<br />a downloaded image to qcow2. | qcow2 | Enum: [qcow2 raw vmdk vhd vhdx iso ova ovf] <br />Optional: \{\} <br /> |
| `checksum` _string_ | Checksum is the expected checksum of the downloaded image: the hex digest<br />only, without an algorithm prefix, compared case-insensitively. It is<br />checked when a url image is prepared and a mismatch fails the prepare. It<br />is not checked for a path. Empty disables the check. |  | Optional: \{\} <br /> |
| `checksumType` _[ChecksumType](#checksumtype)_ | ChecksumType specifies the checksum algorithm: md5, sha1, sha256 or sha512. | sha256 | Enum: [md5 sha1 sha256 sha512] <br />Optional: \{\} <br /> |
| `storagePool` _string_ | StoragePool is the libvirt storage pool a prepared (url) image is<br />published in. When empty the pool "default" is used. The pool must exist<br />and its directory must be one of the provider's allowed image directories.<br />It is not used for a path image. |  | MaxLength: 255 <br />Optional: \{\} <br /> |


#### LibvirtNetworkConfig



LibvirtNetworkConfig defines libvirt-specific network settings. Only
networkName, bridge.name and model are acted on; driver, filterRef,
bridge.stp and bridge.delay are accepted but not acted on in this release.
On a clustered Provider (spec.topology: cluster) the scheduler also
requires a Host whose spec.labels carry net.virtrigaud.io/<name> set to
"true", where <name> is networkName, or bridge.name when networkName is
empty.



_Appears in:_
- [NetworkConfig](#networkconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `networkName` _string_ | NetworkName is the name of the libvirt network (for example default) that<br />the NIC attaches to. It is used only when bridge is not set: a bridge<br />takes precedence. |  | MaxLength: 255 <br />Pattern: `^[^<>&'"/\x00-\x1f]+$` <br />Optional: \{\} <br /> |
| `bridge` _[BridgeConfig](#bridgeconfig)_ | Bridge attaches the NIC to a host bridge instead of a libvirt network.<br />Only bridge.name is acted on. Set either bridge or networkName: when both<br />are set, the libvirt provider uses the bridge. |  | Optional: \{\} <br /> |
| `model` _string_ | Model is the NIC model of the libvirt interface. The libvirt provider uses<br />virtio when it is empty. | virtio | Enum: [virtio e1000 e1000e rtl8139 pcnet ne2k_pci] <br />Optional: \{\} <br /> |
| `driver` _[NetworkDriverConfig](#networkdriverconfig)_ | Driver specifies the network driver configuration. Accepted but not acted<br />on in this release. This applies to every field below it. |  | Optional: \{\} <br /> |
| `filterRef` _[NetworkFilterRef](#networkfilterref)_ | FilterRef specifies network filter configuration. Accepted but not acted<br />on in this release. This applies to every field below it. |  | Optional: \{\} <br /> |


#### LibvirtStorageOptions



LibvirtStorageOptions defines Libvirt storage preparation options. Accepted
but not acted on in this release.



_Appears in:_
- [StoragePrepareOptions](#storageprepareoptions)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `storagePool` _string_ | StoragePool specifies the target storage pool for import. Accepted but not<br />acted on in this release: use source.libvirt.storagePool. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `allocationPolicy` _string_ | AllocationPolicy defines how storage is allocated. Accepted but not acted<br />on in this release. |  | Enum: [eager lazy] <br />Optional: \{\} <br /> |
| `preallocation` _string_ | Preallocation specifies preallocation mode. Accepted but not acted on in<br />this release. |  | Enum: [off metadata falloc full] <br />Optional: \{\} <br /> |


#### LifecycleHandler



LifecycleHandler defines a specific action that should be taken



_Appears in:_
- [VirtualMachineLifecycle](#virtualmachinelifecycle)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `exec` _[ExecAction](#execaction)_ | Exec specifies a command to execute |  | Optional: \{\} <br /> |
| `httpGet` _[HTTPGetAction](#httpgetaction)_ | HTTPGet specifies an HTTP GET request |  | Optional: \{\} <br /> |
| `snapshot` _[SnapshotAction](#snapshotaction)_ | Snapshot specifies a snapshot to create |  | Optional: \{\} <br /> |


#### LocalObjectReference



LocalObjectReference represents a reference to an object in the same namespace



_Appears in:_
- [BasicAuthConfig](#basicauthconfig)
- [BearerTokenConfig](#bearertokenconfig)
- [CertificateSpec](#certificatespec)
- [ClientCertConfig](#clientcertconfig)
- [CloneSource](#clonesource)
- [CloudInit](#cloudinit)
- [CloudInitMetaData](#cloudinitmetadata)
- [HostPoolSpec](#hostpoolspec)
- [HostSpec](#hostspec)
- [IPPoolConfig](#ippoolconfig)
- [Ignition](#ignition)
- [ImportedDiskRef](#importeddiskref)
- [MigrationSource](#migrationsource)
- [MigrationTarget](#migrationtarget)
- [NetworkEncryptionConfig](#networkencryptionconfig)
- [PasswordSpec](#passwordspec)
- [RegistryImageSource](#registryimagesource)
- [SnapshotEncryption](#snapshotencryption)
- [VMCloneStatus](#vmclonestatus)
- [VMCloneTarget](#vmclonetarget)
- [VMMigrationStatus](#vmmigrationstatus)
- [VMPlacementPolicyStatus](#vmplacementpolicystatus)
- [VMSnapshotOperation](#vmsnapshotoperation)
- [VMSnapshotSpec](#vmsnapshotspec)
- [VSphereImageSource](#vsphereimagesource)
- [VirtualMachineSpec](#virtualmachinespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name of the referenced object |  | MaxLength: 253 <br />Pattern: `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$` <br /> |


#### MetaData



MetaData defines cloud-init metadata configuration



_Appears in:_
- [VirtualMachineSpec](#virtualmachinespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `cloudInit` _[CloudInitMetaData](#cloudinitmetadata)_ | CloudInit contains cloud-init metadata configuration |  | Optional: \{\} <br /> |


#### MigrationDiskInfo



MigrationDiskInfo contains information about the migrated disk



_Appears in:_
- [VMMigrationStatus](#vmmigrationstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `sourceDiskID` _string_ | SourceDiskID is the source disk identifier |  |  |
| `sourceFormat` _string_ | SourceFormat is the source disk format |  |  |
| `sourceSize` _[Quantity](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#quantity-resource-api)_ | SourceSize is the source disk size in bytes |  |  |
| `targetDiskID` _string_ | TargetDiskID is the target disk identifier |  | Optional: \{\} <br /> |
| `targetFormat` _string_ | TargetFormat is the target disk format |  | Optional: \{\} <br /> |
| `targetPath` _string_ | TargetPath is the provider-native path of the imported disk as returned by<br />the target provider's ImportDisk (e.g. "[datastore1] disk-id/disk-id.vmdk"<br />for vSphere, "/var/lib/libvirt/images/disk-id.qcow2" for libvirt). It is<br />the authoritative location the created target VirtualMachine attaches; the<br />controller copies it into the target VirtualMachine's<br />spec.importedDisk.path. Empty until the import completes. |  | Optional: \{\} <br /> |
| `targetSize` _[Quantity](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#quantity-resource-api)_ | TargetSize is the target disk size in bytes. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `checksum` _string_ | Checksum is the SHA256 checksum of the disk. Not populated in this release;<br />see sourceChecksum and targetChecksum. |  | Optional: \{\} <br /> |
| `sourceChecksum` _string_ | SourceChecksum is the SHA256 checksum of the source disk |  | Optional: \{\} <br /> |
| `targetChecksum` _string_ | TargetChecksum is the SHA256 checksum of the target disk |  | Optional: \{\} <br /> |


#### MigrationImportTarget



MigrationImportTarget is the namespace and name of the VirtualMachine a
migration's import was sent for, and the Provider it was sent to.



_Appears in:_
- [MigrationStorageInfo](#migrationstorageinfo)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `namespace` _string_ | Namespace is the target VirtualMachine's namespace. |  | MaxLength: 63 <br /> |
| `name` _string_ | Name is the target VirtualMachine's name. |  | MaxLength: 253 <br /> |
| `providerUID` _string_ | ProviderUID is the UID of the target Provider the import was sent to. The<br />landed-disk delete is sent only to that Provider: after<br />spec.target.providerRef changed, or the Provider was replaced, the<br />landed disk is recorded as left behind instead. Empty for an import<br />recorded by an older manager. |  | MaxLength: 36 <br />Optional: \{\} <br /> |
| `host` _string_ | Host is the Host of a clustered target Provider the import was routed<br />to: the target VirtualMachine's pending host, recorded with ProviderUID<br />before the import is sent. A re-sent import<br />and the landed-disk and nfs staged-disk deletes go to this host only.<br />Empty unless the target Provider is clustered (topology: cluster). Written by<br />the controller only. |  | MaxLength: 253 <br />Optional: \{\} <br /> |


#### MigrationMetadata



MigrationMetadata contains migration metadata. Descriptive only: no controller
reads it.



_Appears in:_
- [VMMigrationSpec](#vmmigrationspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `purpose` _string_ | Purpose describes the purpose of the migration |  | Enum: [disaster-recovery cloud-migration provider-change testing maintenance] <br />Optional: \{\} <br /> |
| `createdBy` _string_ | CreatedBy identifies who or what created the migration |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `project` _string_ | Project identifies the project this migration belongs to |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `environment` _string_ | Environment specifies the environment |  | Enum: [dev staging prod test qa uat] <br />Optional: \{\} <br /> |
| `tags` _object (keys:string, values:string)_ | Tags are key-value pairs for categorizing the migration |  | MaxProperties: 50 <br />Optional: \{\} <br /> |


#### MigrationOptions



MigrationOptions defines migration options



_Appears in:_
- [VMMigrationSpec](#vmmigrationspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `diskFormat` _string_ | DiskFormat specifies the disk format requested for the export and, with the<br />pvc storage backend, for the import (default qcow2). With the s3 and nfs<br />backends the format of the staged object is not taken from this field: s3<br />stages the source provider's native format (vmdk from vSphere, qcow2<br />otherwise) and nfs stages qcow2; the target provider converts on import. |  | Enum: [qcow2 vmdk raw] <br />Optional: \{\} <br /> |
| `compress` _boolean_ | Compress asks the source provider to compress the exported disk. It is<br />sent with the export request and a provider may ignore it: it has no<br />effect on the libvirt s3 and nfs exports, on vSphere exports or on the<br />Proxmox nfs export; the Proxmox s3 export honours it. | false | Optional: \{\} <br /> |
| `verifyChecksums` _boolean_ | VerifyChecksums asks the target provider to verify a pvc import against<br />the checksum the source export reported (default true). Setting it to<br />false only disables that pvc check: s3 imports always verify when the<br />export reported a checksum, and nfs carries no checksum. | true | Optional: \{\} <br /> |
| `timeout` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | Timeout bounds how long the migration waits for the source snapshot task<br />to finish (default 4h; 2h when options is unset). It is not applied to the<br />other phases in this release: a disk export call has a fixed limit of one<br />hour. | 4h | Optional: \{\} <br /> |
| `retryPolicy` _[MigrationRetryPolicy](#migrationretrypolicy)_ | RetryPolicy defines retry behavior for a failed migration. Without it a<br />failed migration is not retried. A retry restarts the migration from the<br />Pending phase. |  | Optional: \{\} <br /> |
| `cleanupPolicy` _string_ | CleanupPolicy decides when the artifacts the migration created are removed.<br />The source snapshot the migration took is deleted when the migration<br />reaches Ready, and when it fails for good, unless the policy is Never. The<br />staged disk of an nfs or s3 migration is deleted, with OnSuccess (the<br />default), when the migration reaches Ready and when the VMMigration is<br />deleted; a migration that failed for good keeps it until the VMMigration<br />is deleted. Always also deletes it when the migration fails for good. The<br />disk a failed import landed on the target is deleted when the VMMigration<br />is deleted (OnSuccess) or also when the migration fails for good (Always);<br />the disk of a migration that reached Ready belongs to the target VM and is<br />never deleted. Never keeps the snapshot, the staged disk and the landed<br />disk. The PVC a pvc migration created is deleted with the VMMigration<br />whatever the policy. A migration fails for good when it has no<br />retryPolicy, or its retries are used up. | OnSuccess | Enum: [Always OnSuccess Never] <br />Optional: \{\} <br /> |
| `validationChecks` _[ValidationChecks](#validationchecks)_ | ValidationChecks defines validation checks to perform. Accepted but not<br />acted on in this release: no check listed here runs. |  | Optional: \{\} <br /> |


#### MigrationPhase

_Underlying type:_ _string_

MigrationPhase represents the phase of a migration operation

_Validation:_
- Enum: [Pending Validating Snapshotting Exporting Transferring Converting Importing Creating Validating-Target Ready Failed]

_Appears in:_
- [MigrationProgress](#migrationprogress)
- [VMMigrationStatus](#vmmigrationstatus)

| Field | Description |
| --- | --- |
| `Pending` | MigrationPhasePending indicates the migration is waiting to be processed<br /> |
| `Validating` | MigrationPhaseValidating indicates the migration is being validated<br /> |
| `Snapshotting` | MigrationPhaseSnapshotting indicates a snapshot is being created<br /> |
| `Exporting` | MigrationPhaseExporting indicates the disk is being exported<br /> |
| `Transferring` | MigrationPhaseTransferring indicates the disk is being transferred<br /> |
| `Converting` | MigrationPhaseConverting indicates the disk format is being converted<br /> |
| `Importing` | MigrationPhaseImporting indicates the disk is being imported<br /> |
| `Creating` | MigrationPhaseCreating indicates the target VM is being created<br /> |
| `Validating-Target` | MigrationPhaseValidatingTarget indicates the target VM is being validated<br /> |
| `Ready` | MigrationPhaseReady indicates the migration is complete<br /> |
| `Failed` | MigrationPhaseFailed indicates the migration failed<br /> |


#### MigrationProgress



MigrationProgress shows the migration operation progress. Not populated in
this release.



_Appears in:_
- [VMMigrationStatus](#vmmigrationstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `currentPhase` _[MigrationPhase](#migrationphase)_ | CurrentPhase is the current phase being executed |  | Enum: [Pending Validating Snapshotting Exporting Transferring Converting Importing Creating Validating-Target Ready Failed] <br /> |
| `totalBytes` _integer_ | TotalBytes is the total bytes to transfer |  | Optional: \{\} <br /> |
| `transferredBytes` _integer_ | TransferredBytes is the bytes transferred so far |  | Optional: \{\} <br /> |
| `percentage` _integer_ | Percentage is the overall completion percentage (0-100) |  | Maximum: 100 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `eta` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | ETA is the estimated time to completion |  | Optional: \{\} <br /> |
| `transferRate` _integer_ | TransferRate is the current transfer rate in bytes per second |  | Optional: \{\} <br /> |
| `phaseStartTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | PhaseStartTime is when the current phase started |  | Optional: \{\} <br /> |


#### MigrationRetryPolicy



MigrationRetryPolicy defines retry behavior for a failed migration.



_Appears in:_
- [MigrationOptions](#migrationoptions)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `maxRetries` _integer_ | MaxRetries is the maximum number of retry attempts (default 3). | 3 | Maximum: 10 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `retryDelay` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | RetryDelay is the delay before the first retry (default 5m). Each later<br />retry waits retryDelay multiplied by backoffMultiplier once more, up to a<br />maximum of 30 minutes. | 5m | Optional: \{\} <br /> |
| `backoffMultiplier` _integer_ | BackoffMultiplier is the multiplier applied to the delay between retries<br />(default 2). | 2 | Maximum: 10 <br />Minimum: 1 <br />Optional: \{\} <br /> |


#### MigrationSource



MigrationSource defines the source VM for migration



_Appears in:_
- [VMMigrationSpec](#vmmigrationspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `vmRef` _[LocalObjectReference](#localobjectreference)_ | VMRef references the source virtual machine |  |  |
| `providerRef` _[ObjectRef](#objectref)_ | ProviderRef optionally names the source provider. It must be the Provider<br />the source VM runs on (the VM's spec.providerRef, with an empty namespace<br />meaning the VM's namespace); a migration naming any other Provider fails,<br />because that Provider would export an unrelated VM that happens to share<br />the source VM's provider ID. Leave it empty to use the source VM's<br />Provider. |  | Optional: \{\} <br /> |
| `snapshotRef` _[LocalObjectReference](#localobjectreference)_ | SnapshotRef names an existing snapshot to export from instead of taking a<br />new one. The name is used as the provider's snapshot identifier (no<br />VMSnapshot object is looked up), and the migration never deletes it. It<br />is read only while createSnapshot is true; with createSnapshot false no<br />snapshot is used and this field is ignored. |  | Optional: \{\} <br /> |
| `createSnapshot` _boolean_ | CreateSnapshot indicates whether to snapshot the source VM before<br />exporting its disk (default true). A snapshot the migration took is deleted<br />after the migration succeeds, after it fails for good, and when the<br />VMMigration is deleted, unless options.cleanupPolicy is Never. When false<br />the Snapshotting phase is skipped and the disk is exported without a<br />snapshot. | true | Optional: \{\} <br /> |
| `powerOffBeforeMigration` _boolean_ | PowerOffBeforeMigration sets the source VirtualMachine's spec.powerState to<br />Off and waits, up to 10 minutes, until the provider reports it Off before<br />the snapshot and export; the migration fails if it is not. A vSphere<br />source should be powered off, since exporting a running vSphere VM fails<br />(its disk is locked). The migration does not power the source on again;<br />its spec.powerState stays Off. | false | Optional: \{\} <br /> |
| `deleteAfterMigration` _boolean_ | DeleteAfterMigration deletes the source VirtualMachine after the migration<br />reaches Ready. Only the VirtualMachine the migration validated (recorded in<br />status.sourceVMUID) is deleted, with a UID precondition: a VM re-created<br />under the same name is kept. | false | Optional: \{\} <br /> |


#### MigrationStorage



MigrationStorage defines storage backend configuration



_Appears in:_
- [VMMigrationSpec](#vmmigrationspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `type` _string_ | Type specifies the storage backend used to stage the transferred disk<br />between the source and target providers: "pvc" (a PersistentVolumeClaim<br />the provider pods mount), "nfs" (an NFS export) or "s3" (an S3-compatible<br />bucket). Both the source provider's status.reportedCapabilities<br />supportedExportBackends and the target provider's supportedImportBackends<br />must list the backend, or the migration fails at the Validating phase.<br />The pvc backend is not supported when the source or the target Provider is<br />clustered (topology: cluster); use nfs or s3 there. It also requires the<br />VMMigration and both Providers to be in one namespace, because the PVC is<br />mounted into both provider pods. | pvc | Enum: [pvc nfs s3] <br /> |
| `transferMode` _string_ | TransferMode selects how disk bytes travel to and from a pvc or s3<br />staging backend. "relay" routes the bytes through the provider pod; "auto"<br />(the default) resolves to "relay". "direct" (host to backend, without the<br />provider pod) is not implemented: a migration that asks for it fails at<br />the Validating phase. The nfs backend ignores this field: the data moves<br />over NFS with qemu-img on the hypervisor host (libvirt, Proxmox) or in the<br />provider pod (vSphere). | auto | Enum: [auto relay direct] <br />Optional: \{\} <br /> |
| `pvc` _[PVCStorageConfig](#pvcstorageconfig)_ | PVC specifies PVC-based storage configuration |  | Optional: \{\} <br /> |
| `nfs` _[NFSStorageConfig](#nfsstorageconfig)_ | NFS specifies NFS-based staging configuration. Required when type is nfs. |  | Optional: \{\} <br /> |
| `s3` _[S3StorageConfig](#s3storageconfig)_ | S3 specifies S3-compatible object-storage staging configuration. Required<br />when type is s3. |  | Optional: \{\} <br /> |


#### MigrationStorageInfo



MigrationStorageInfo contains information about intermediate storage



_Appears in:_
- [VMMigrationStatus](#vmmigrationstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `url` _string_ | URL is the intermediate storage URL. Not populated in this release. |  | Optional: \{\} <br /> |
| `size` _[Quantity](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#quantity-resource-api)_ | Size is the size of data in intermediate storage. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `uploadedAt` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | UploadedAt is when the data was uploaded. Not populated in this release. |  | Optional: \{\} <br /> |
| `cleanedUp` _boolean_ | CleanedUp is set once the post-migration cleanup (deleting the source<br />snapshot and, when requested, the source VM) has run for a migration that<br />reached Ready. It is also set, with nothing deleted, for a migration that<br />reached Ready under an earlier release. |  | Optional: \{\} <br /> |
| `stagingLayout` _string_ | StagingLayout is the naming layout of the migration's nfs / s3 staged<br />object, recorded by the controller when the export is sent. The import<br />and the staged-disk delete use it, so a migration keeps the name it was<br />exported under. "v2" (new migrations): nfs file<br />"vmmigrations_<namespace>_<name>_<stage>.qcow2". "v1" or empty (exported<br />before v2): "vmmigrations-<namespace>-<name>-<stage>.qcow2". The s3 key is<br />the same in both. Written by the controller only. |  | Enum: [v1 v2] <br />Optional: \{\} <br /> |
| `stagingDigest` _string_ | StagingDigest is a digest of where the last export staged the object —<br />the staging backend and its non-secret options, and the target Provider<br />(namespace, name, UID) that will delete it — recorded by the controller<br />when the export is sent. The staged-disk delete is sent only<br />while the migration's current spec still yields this digest: after<br />spec.storage or spec.target.providerRef changed, the object is recorded<br />as left behind instead of being looked for somewhere else. It carries no<br />location. Written by the controller only. |  | MaxLength: 80 <br />Optional: \{\} <br /> |
| `importTarget` _[MigrationImportTarget](#migrationimporttarget)_ | ImportTarget is the VirtualMachine a migration's ImportDisk was sent<br />for, recorded by the controller just before the import is sent (for every<br />storage backend). The staged-disk delete and the<br />landed-disk delete name only this VM, never the current spec.target<br />(which may have been edited since), so a target provider removes only<br />the copy it landed for that VM. Written by the controller only. |  | Optional: \{\} <br /> |


#### MigrationTarget



MigrationTarget defines the target provider and VM configuration



_Appears in:_
- [VMMigrationSpec](#vmmigrationspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the name for the target VM |  | MaxLength: 253 <br />Pattern: `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$` <br /> |
| `namespace` _string_ | Namespace is the namespace for the target VM (defaults to the<br />VMMigration's namespace, which is also the source VM's). A different<br />namespace is allowed only when that Namespace object carries the<br />annotation infra.virtrigaud.io/allowed-source-namespaces and its<br />comma-separated value lists the VMMigration's namespace (exact names, no<br />wildcards). Whoever can update the target Namespace can grant this<br />(normally a cluster administrator, since Namespaces are cluster-scoped).<br />A granted migration's disk is not attached in place: the target VM<br />treats it as a base image. Without the grant the migration is held<br />before any side effect (Ready=False, reason TargetNamespaceNotAllowed);<br />the grant is re-checked before the disk import, the target VM creation<br />and the cleanup, so revoking it stops a migration in flight. Granting the<br />annotation or changing this field resumes it. |  | MaxLength: 63 <br />Pattern: `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$` <br />Optional: \{\} <br /> |
| `providerRef` _[ObjectRef](#objectref)_ | ProviderRef references the target provider |  |  |
| `classRef` _[LocalObjectReference](#localobjectreference)_ | ClassRef references the VMClass (in the VMMigration's namespace) of the<br />target VirtualMachine. It becomes the target VM's spec.classRef. The<br />target VirtualMachine requires a class, so set it. |  | Optional: \{\} <br /> |
| `imageRef` _[LocalObjectReference](#localobjectreference)_ | ImageRef references the VM image. Accepted but not acted on in this<br />release: the target VM is created from the migrated disk, not from an<br />image. |  | Optional: \{\} <br /> |
| `networks` _[VMNetworkRef](#vmnetworkref) array_ | Networks defines network configuration for target VM. Copied to the target<br />VirtualMachine's spec.networks. |  | MaxItems: 10 <br />Optional: \{\} <br /> |
| `disks` _[DiskSpec](#diskspec) array_ | Disks defines disk configuration overrides. Accepted but not acted on in<br />this release: the target VirtualMachine gets only the migrated disk. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `placementRef` _[LocalObjectReference](#localobjectreference)_ | PlacementRef references the VMPlacementPolicy for the target VM. Copied to<br />the target VirtualMachine's spec.placementRef. |  | Optional: \{\} <br /> |
| `powerOn` _boolean_ | PowerOn indicates whether the target VM's desired power state is On (true)<br />or Off (false, the default) once it is created. | false | Optional: \{\} <br /> |
| `labels` _object (keys:string, values:string)_ | Labels defines labels to apply to the target VM. The label<br />virtrigaud.io/adopted is reserved for the manager and is not copied (a<br />Normal event, TargetLabelsDropped, names it); every other label is. |  | MaxProperties: 50 <br />Optional: \{\} <br /> |
| `annotations` _object (keys:string, values:string)_ | Annotations defines annotations to apply to the target VM. Keys in the<br />operator's reserved virtrigaud.io domain (virtrigaud.io/... and<br />*.virtrigaud.io/...), such as virtrigaud.io/orphan-on-delete or the<br />provenance annotations, are not copied; the controller sets its own<br />provenance annotations. |  | MaxProperties: 50 <br />Optional: \{\} <br /> |


#### NFSStorageConfig



NFSStorageConfig defines NFS-based staging configuration used to stage a
migration's transferred disk.



_Appears in:_
- [MigrationStorage](#migrationstorage)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `server` _string_ | Server is the NFS server hostname or IP exporting the share. The host is<br />checked by the controller before it is used, as for the S3 endpoint. |  | MaxLength: 253 <br /> |
| `export` _string_ | Export is the exported NFS path on the server (e.g. "/exports/migrations"). |  | MaxLength: 4096 <br /> |
| `path` _string_ | Path is an optional sub-path within the export for this migration's data. |  | MaxLength: 4096 <br />Optional: \{\} <br /> |
| `readOnly` _boolean_ | ReadOnly mounts the export read-only. Accepted but not acted on in this<br />release: it is not sent to the providers, and staging needs a writable<br />export. | false | Optional: \{\} <br /> |
| `uid` _integer_ | UID is the AUTH_SYS user ID presented to the NFS server. The export's<br />squash policy is the real authorization boundary; this lets an operator<br />align the client identity with the export. 0 (root) is refused. Unset =<br />the data-plane process identity (the provider pod or SSH user). |  | Maximum: 4.294967295e+09 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `gid` _integer_ | GID is the AUTH_SYS group ID presented to the NFS server. 0 (root) is<br />refused. Unset = the data-plane process identity. |  | Maximum: 4.294967295e+09 <br />Minimum: 0 <br />Optional: \{\} <br /> |


#### NetworkAttachmentPhase

_Underlying type:_ _string_

NetworkAttachmentPhase represents the phase of network attachment. No
controller sets it in this release.

_Validation:_
- Enum: [Pending Configuring Ready Failed]

_Appears in:_
- [VMNetworkAttachmentStatus](#vmnetworkattachmentstatus)

| Field | Description |
| --- | --- |
| `Pending` | NetworkAttachmentPhasePending indicates the network is being prepared<br /> |
| `Configuring` | NetworkAttachmentPhaseConfiguring indicates the network is being configured<br /> |
| `Ready` | NetworkAttachmentPhaseReady indicates the network is ready<br /> |
| `Failed` | NetworkAttachmentPhaseFailed indicates the network configuration failed<br /> |


#### NetworkConfig



NetworkConfig holds the per-hypervisor network settings. The manager reads
only the block that matches the type of the VM's Provider.



_Appears in:_
- [VMNetworkAttachmentSpec](#vmnetworkattachmentspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `vsphere` _[VSphereNetworkConfig](#vspherenetworkconfig)_ | VSphere contains the settings used when the VM's Provider is a vSphere<br />Provider. Only portgroup is acted on. |  | Optional: \{\} <br /> |
| `libvirt` _[LibvirtNetworkConfig](#libvirtnetworkconfig)_ | Libvirt contains the settings used when the VM's Provider is a libvirt<br />Provider. Only networkName, bridge.name and model are acted on. |  | Optional: \{\} <br /> |
| `proxmox` _[ProxmoxNetworkConfig](#proxmoxnetworkconfig)_ | Proxmox contains the settings used when the VM's Provider is a Proxmox VE<br />Provider. Only bridge, model and vlanTag are acted on. |  | Optional: \{\} <br /> |
| `type` _[NetworkType](#networktype)_ | Type specifies the network type. Accepted but not acted on in this<br />release. The network a VM joins is set by the provider block (portgroup,<br />networkName or bridge). | bridged | Enum: [bridged nat isolated host-only external] <br />Optional: \{\} <br /> |
| `mtu` _integer_ | MTU specifies the Maximum Transmission Unit. Accepted but not acted on in<br />this release (nor is proxmox.mtu). | 1500 | Maximum: 9000 <br />Minimum: 68 <br />Optional: \{\} <br /> |


#### NetworkCustomization



NetworkCustomization defines network-specific customization. Accepted but
not acted on in this release.



_Appears in:_
- [VMCustomization](#vmcustomization)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name identifies the network to customize. Accepted but not acted on in<br />this release. |  | MaxLength: 255 <br /> |
| `ipAddress` _string_ | IPAddress sets a static IP address. Accepted but not acted on in this<br />release. |  | Pattern: `^((25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)\.)\{3\}(25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)$` <br />Optional: \{\} <br /> |
| `subnetMask` _string_ | SubnetMask sets the subnet mask. Accepted but not acted on in this<br />release. |  | Pattern: `^((25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)\.)\{3\}(25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)$` <br />Optional: \{\} <br /> |
| `gateway` _string_ | Gateway sets the network gateway. Accepted but not acted on in this<br />release. |  | Pattern: `^((25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)\.)\{3\}(25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)$` <br />Optional: \{\} <br /> |
| `dns` _string array_ | DNS sets DNS servers. Accepted but not acted on in this release. |  | MaxItems: 5 <br />Optional: \{\} <br /> |
| `macAddress` _string_ | MACAddress sets a custom MAC address. Accepted but not acted on in this<br />release. |  | Pattern: `^([0-9A-Fa-f]\{2\}[:-])\{5\}([0-9A-Fa-f]\{2\})$` <br />Optional: \{\} <br /> |
| `dhcp` _boolean_ | DHCP enables DHCP for this network. Accepted but not acted on in this<br />release. |  | Optional: \{\} <br /> |


#### NetworkDriverConfig



NetworkDriverConfig defines network driver configuration. Accepted but not
acted on in this release.



_Appears in:_
- [LibvirtNetworkConfig](#libvirtnetworkconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the driver name. Accepted but not acted on in this release. |  | Enum: [kvm vfio uio] <br />Optional: \{\} <br /> |
| `queues` _integer_ | Queues specifies the number of queues. Accepted but not acted on in this<br />release. |  | Maximum: 16 <br />Minimum: 1 <br />Optional: \{\} <br /> |
| `txMode` _string_ | TxMode specifies the TX mode. Accepted but not acted on in this release. |  | Enum: [iothread timer] <br />Optional: \{\} <br /> |
| `ioEventFD` _boolean_ | IOEventFD enables IO event file descriptor. Accepted but not acted on in<br />this release. |  | Optional: \{\} <br /> |
| `eventIDX` _boolean_ | EventIDX enables event index. Accepted but not acted on in this release. |  | Optional: \{\} <br /> |


#### NetworkEncryptionConfig



NetworkEncryptionConfig defines network encryption settings. Accepted but
not acted on in this release.



_Appears in:_
- [NetworkSecurityConfig](#networksecurityconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled indicates if encryption is enabled. Accepted but not acted on in<br />this release. | false | Optional: \{\} <br /> |
| `protocol` _string_ | Protocol specifies the encryption protocol. Accepted but not acted on in<br />this release. |  | Enum: [ipsec wireguard openvpn] <br />Optional: \{\} <br /> |
| `keyRef` _[LocalObjectReference](#localobjectreference)_ | KeyRef references encryption keys. Accepted but not acted on in this<br />release. |  | Optional: \{\} <br /> |


#### NetworkFilterRef



NetworkFilterRef references a network filter. Accepted but not acted on in
this release.



_Appears in:_
- [LibvirtNetworkConfig](#libvirtnetworkconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `filter` _string_ | Filter is the filter name. Accepted but not acted on in this release. |  | MaxLength: 255 <br /> |
| `parameters` _object (keys:string, values:string)_ | Parameters contains filter parameters. Accepted but not acted on in this<br />release. |  | MaxProperties: 20 <br />Optional: \{\} <br /> |


#### NetworkIsolationConfig



NetworkIsolationConfig defines network isolation settings. Accepted but not
acted on in this release.



_Appears in:_
- [NetworkSecurityConfig](#networksecurityconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `mode` _string_ | Mode specifies the isolation mode. Accepted but not acted on in this<br />release. |  | Enum: [none strict custom] <br />Optional: \{\} <br /> |
| `allowedNetworks` _string array_ | AllowedNetworks contains allowed network CIDRs. Accepted but not acted on<br />in this release. |  | MaxItems: 50 <br />Optional: \{\} <br /> |
| `deniedNetworks` _string array_ | DeniedNetworks contains denied network CIDRs. Accepted but not acted on in<br />this release. |  | MaxItems: 50 <br />Optional: \{\} <br /> |


#### NetworkMetadata



NetworkMetadata contains network metadata and labels. Accepted but not
acted on in this release.



_Appears in:_
- [VMNetworkAttachmentSpec](#vmnetworkattachmentspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `displayName` _string_ | DisplayName is a human-readable name. Accepted but not acted on in this<br />release. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `description` _string_ | Description provides a description. Accepted but not acted on in this<br />release. |  | MaxLength: 1024 <br />Optional: \{\} <br /> |
| `environment` _string_ | Environment specifies the environment (dev, staging, prod, qa, uat).<br />Accepted but not acted on in this release. |  | Enum: [dev staging prod test qa uat] <br />Optional: \{\} <br /> |
| `tags` _object (keys:string, values:string)_ | Tags are key-value pairs for categorizing. Accepted but not acted on in<br />this release. |  | MaxProperties: 50 <br />Optional: \{\} <br /> |


#### NetworkQoSConfig



NetworkQoSConfig defines Quality of Service settings. Accepted but not
acted on in this release.



_Appears in:_
- [VMNetworkAttachmentSpec](#vmnetworkattachmentspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `ingressLimit` _integer_ | IngressLimit limits inbound traffic in bits per second. Accepted but not<br />acted on in this release. |  | Minimum: 1000 <br />Optional: \{\} <br /> |
| `egressLimit` _integer_ | EgressLimit limits outbound traffic in bits per second. Accepted but not<br />acted on in this release. |  | Minimum: 1000 <br />Optional: \{\} <br /> |
| `priority` _integer_ | Priority specifies traffic priority. Accepted but not acted on in this<br />release. |  | Maximum: 7 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `dscp` _integer_ | DSCP specifies DSCP marking. Accepted but not acted on in this release. |  | Maximum: 63 <br />Minimum: 0 <br />Optional: \{\} <br /> |


#### NetworkSecurityConfig



NetworkSecurityConfig defines network security settings. Accepted but not
acted on in this release.



_Appears in:_
- [VMNetworkAttachmentSpec](#vmnetworkattachmentspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `firewall` _[FirewallConfig](#firewallconfig)_ | Firewall contains firewall configuration. Accepted but not acted on in<br />this release. |  | Optional: \{\} <br /> |
| `isolation` _[NetworkIsolationConfig](#networkisolationconfig)_ | Isolation contains network isolation settings. Accepted but not acted on<br />in this release. |  | Optional: \{\} <br /> |
| `encryption` _[NetworkEncryptionConfig](#networkencryptionconfig)_ | Encryption contains network encryption settings. Accepted but not acted on<br />in this release. |  | Optional: \{\} <br /> |


#### NetworkType

_Underlying type:_ _string_

NetworkType represents the type of network. Accepted but not acted on in
this release.

_Validation:_
- Enum: [bridged nat isolated host-only external]

_Appears in:_
- [NetworkConfig](#networkconfig)

| Field | Description |
| --- | --- |
| `bridged` | NetworkTypeBridged indicates a bridged network<br /> |
| `nat` | NetworkTypeNAT indicates a NAT network<br /> |
| `isolated` | NetworkTypeIsolated indicates an isolated network<br /> |
| `host-only` | NetworkTypeHostOnly indicates a host-only network<br /> |
| `external` | NetworkTypeExternal indicates an external network<br /> |


#### NetworkUsageStats



NetworkUsageStats represents network usage statistics



_Appears in:_
- [ProviderResourceUsage](#providerresourceusage)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `bytesReceived` _integer_ | BytesReceived is the total bytes received |  | Optional: \{\} <br /> |
| `bytesSent` _integer_ | BytesSent is the total bytes sent |  | Optional: \{\} <br /> |
| `packetsReceived` _integer_ | PacketsReceived is the total packets received |  | Optional: \{\} <br /> |
| `packetsSent` _integer_ | PacketsSent is the total packets sent |  | Optional: \{\} <br /> |


#### OSDistribution



OSDistribution contains OS distribution information. Descriptive: no
controller or provider reads any field of it.



_Appears in:_
- [VMImageSpec](#vmimagespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the OS distribution name. Descriptive: no controller reads it. |  | Enum: [ubuntu centos rhel fedora debian suse windows freebsd coreos other] <br />Optional: \{\} <br /> |
| `version` _string_ | Version is the distribution version. Descriptive: no controller reads it. |  | MaxLength: 100 <br />Optional: \{\} <br /> |
| `variant` _string_ | Variant is the distribution variant (e.g., server, desktop). Descriptive:<br />no controller reads it. |  | MaxLength: 100 <br />Optional: \{\} <br /> |
| `family` _string_ | Family is the OS family. Descriptive: no controller reads it. |  | Enum: [linux windows bsd other] <br />Optional: \{\} <br /> |
| `kernel` _[KernelInfo](#kernelinfo)_ | Kernel specifies kernel information. Descriptive: no controller reads it. |  | Optional: \{\} <br /> |


#### ObjectRef



ObjectRef represents a reference to another object



_Appears in:_
- [CloneSource](#clonesource)
- [MigrationSource](#migrationsource)
- [MigrationTarget](#migrationtarget)
- [ProviderSpec](#providerspec)
- [S3StorageConfig](#s3storageconfig)
- [VMCloneTarget](#vmclonetarget)
- [VMNetworkRef](#vmnetworkref)
- [VirtualMachineSpec](#virtualmachinespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name of the referenced object |  | MaxLength: 253 <br />Pattern: `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$` <br /> |
| `namespace` _string_ | Namespace of the referenced object (defaults to current namespace) |  | MaxLength: 63 <br />Pattern: `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$` <br />Optional: \{\} <br /> |


#### ObservedPowerState

_Underlying type:_ _string_

ObservedPowerState is a VM's power state as its provider reports it
(status.powerState). It is a superset of PowerState: a desired state is only
ever On, Off or OffGraceful, but an observed one can also be Suspended or
Unknown. OffGraceful stays valid so a status written by an older manager
still validates.

_Validation:_
- Enum: [On Off OffGraceful Suspended Unknown]

_Appears in:_
- [VirtualMachineStatus](#virtualmachinestatus)

| Field | Description |
| --- | --- |
| `On` | ObservedPowerStateOn is a running VM.<br /> |
| `Off` | ObservedPowerStateOff is a powered-off VM.<br /> |
| `Suspended` | ObservedPowerStateSuspended is a VM that is paused or suspended to RAM:<br />still active on its host (it resumes at the size it has), not powered<br />off.<br /> |
| `Unknown` | ObservedPowerStateUnknown is a VM whose provider reports a state it<br />cannot classify.<br /> |


#### OvercommitRatios



OvercommitRatios are the CPU and memory overcommit ratios applied when
computing a pool's allocatable capacity. Ratios are expressed as decimal
strings (e.g. "4.0") to keep floating-point values out of the API surface.



_Appears in:_
- [HostPoolSpec](#hostpoolspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `cpu` _string_ | CPU is the vCPU overcommit ratio (e.g. "4.0" = up to 4 vCPU per physical<br />core). Empty means no CPU overcommit ("1.0"). |  | Optional: \{\} <br /> |
| `memory` _string_ | Memory is the memory overcommit ratio (e.g. "1.0" = no memory overcommit).<br />Empty means no memory overcommit ("1.0"). |  | Optional: \{\} <br /> |


#### PVCStorageConfig



PVCStorageConfig defines PVC storage configuration



_Appears in:_
- [MigrationStorage](#migrationstorage)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name of an existing PVC, in the VMMigration's namespace, to use for<br />migration storage. The PVC must carry the label<br />virtrigaud.io/component=migration-storage, which is how its owner agrees<br />to its use; the controller refuses an unlabelled PVC. If not specified,<br />the controller creates a labelled PVC for the migration and deletes it with<br />the VMMigration (a PVC named here is left for its owner). |  | Optional: \{\} <br /> |
| `storageClassName` _string_ | StorageClassName for auto-created PVC<br />Required if Name is not specified |  | Optional: \{\} <br /> |
| `size` _string_ | Size for auto-created PVC (e.g., "100Gi")<br />Required if Name is not specified |  | Pattern: `^[0-9]+(\.[0-9]+)?(Ei?\|Pi?\|Ti?\|Gi?\|Mi?\|Ki?)$` <br />Optional: \{\} <br /> |
| `accessMode` _string_ | AccessMode for auto-created PVC | ReadWriteMany | Enum: [ReadWriteOnce ReadWriteMany ReadOnlyMany] <br />Optional: \{\} <br /> |
| `mountPath` _string_ | MountPath within pods where PVC is mounted. Accepted but not acted on in<br />this release: provider pods always mount the PVC at<br />/mnt/migration-storage/<pvc-name>. | /mnt/migration-storage | Optional: \{\} <br /> |


#### PasswordSpec



PasswordSpec defines password configuration. Accepted but not acted on in
this release.



_Appears in:_
- [DomainJoinSpec](#domainjoinspec)
- [SysprepCustomization](#sysprepcustomization)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `value` _string_ | Value is the plaintext password (not recommended for production).<br />Accepted but not acted on in this release.<br />WARNING: a value set here is stored in plaintext in the VMClone (etcd,<br />backups, anyone who can read the object). It is accepted but not acted<br />on in this release and is not sent to the provider; do not put a real<br />password here. |  | Optional: \{\} <br /> |
| `secretRef` _[LocalObjectReference](#localobjectreference)_ | SecretRef references a secret containing the password. Accepted but not<br />acted on in this release. |  | Optional: \{\} <br /> |
| `secretKey` _string_ | SecretKey is the key in the secret containing the password. Accepted<br />but not acted on in this release. | password | Optional: \{\} <br /> |


#### PerformanceProfile



PerformanceProfile defines performance-related settings. See
VMClassSpec.PerformanceProfile for which fields are acted on.



_Appears in:_
- [VMClassSpec](#vmclassspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `latencySensitivity` _string_ | LatencySensitivity configures latency sensitivity. Accepted but not<br />acted on in this release. | normal | Enum: [low normal high] <br />Optional: \{\} <br /> |
| `cpuHotAddEnabled` _boolean_ | CPUHotAddEnabled allows adding CPUs while the VM is running. libvirt<br />provisions headroom for live vCPU growth; vSphere enables CPU hot-add,<br />except when nestedVirtualization is also set (the combination is not<br />supported there, and hot-add is skipped). Proxmox and mock ignore it. | false | Optional: \{\} <br /> |
| `memoryHotAddEnabled` _boolean_ | MemoryHotAddEnabled allows adding memory while the VM is running.<br />libvirt provisions a memory ceiling above the initial memory for live<br />growth; vSphere enables memory hot-add. On a clustered Provider the<br />scheduler also reserves that headroom on the host. Proxmox and mock<br />ignore it. | false | Optional: \{\} <br /> |
| `virtualizationBasedSecurity` _boolean_ | VirtualizationBasedSecurity enables VBS features. Only the vSphere<br />provider acts on it; libvirt, Proxmox and mock ignore it. | false | Optional: \{\} <br /> |
| `nestedVirtualization` _boolean_ | NestedVirtualization enables nested virtualization. It is acted on by<br />vSphere and libvirt; on libvirt the host CPU is passed through<br />(host-passthrough), and the guest sees VT-x or AMD-V only when the<br />host's kvm_intel or kvm_amd module has nesting enabled. Proxmox and mock<br />ignore it. | false | Optional: \{\} <br /> |
| `hyperThreadingPolicy` _string_ | HyperThreadingPolicy controls hyperthreading usage. Accepted but not<br />acted on in this release. | auto | Enum: [auto prefer avoid require] <br />Optional: \{\} <br /> |


#### PersistentVolumeClaimRetentionPolicyType

_Underlying type:_ _string_

PersistentVolumeClaimRetentionPolicyType defines the retention policy type.
Accepted but not acted on in this release.

_Validation:_
- Enum: [Retain Delete]

_Appears in:_
- [VMSetPersistentVolumeClaimRetentionPolicy](#vmsetpersistentvolumeclaimretentionpolicy)

| Field | Description |
| --- | --- |
| `Retain` | RetainPersistentVolumeClaimRetentionPolicyType retains PVCs<br /> |
| `Delete` | DeletePersistentVolumeClaimRetentionPolicyType deletes PVCs<br /> |




#### PersistentVolumeClaimTemplate



PersistentVolumeClaimTemplate describes a PVC template for VMSet VMs.
Accepted but not acted on in this release.



_Appears in:_
- [VMSetSpec](#vmsetspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  | Optional: \{\} <br /> |
| `spec` _[PersistentVolumeClaimSpec](#persistentvolumeclaimspec)_ | Spec is the desired characteristics of the volume. Accepted but not acted<br />on in this release. |  |  |


#### Placement



Placement provides hints for VM placement. See VirtualMachineSpec.Placement
for which fields are used.



_Appears in:_
- [VirtualMachineSpec](#virtualmachinespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `cluster` _string_ | Cluster specifies the target cluster |  | Optional: \{\} <br /> |
| `host` _string_ | Host specifies the target host. Accepted but not acted on in this release. |  | Optional: \{\} <br /> |
| `datastore` _string_ | Datastore specifies the target datastore.<br />Mutually exclusive with StoragePod; Datastore takes precedence if both are set. |  | Optional: \{\} <br /> |
| `storagePod` _string_ | StoragePod specifies a vSphere Datastore Cluster (StoragePod) to use for automatic<br />datastore selection. The provider will pick the datastore within the cluster that<br />has the most free space. Ignored when Datastore is also set. |  | Optional: \{\} <br /> |
| `folder` _string_ | Folder specifies the target folder |  | Optional: \{\} <br /> |
| `resourcePool` _string_ | ResourcePool specifies the target resource pool. Accepted but not acted on<br />in this release. |  | Optional: \{\} <br /> |


#### PlacementConstraints



PlacementConstraints defines placement constraints on Hosts. The scheduler
acts on hosts, excludedHosts and nodeSelector, in hard or soft form; the
other fields are accepted but not acted on in this release.



_Appears in:_
- [VMPlacementPolicySpec](#vmplacementpolicyspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `clusters` _string array_ | Clusters specifies allowed clusters for VM placement. Accepted but not<br />acted on in this release. |  | MaxItems: 50 <br />Optional: \{\} <br /> |
| `datastores` _string array_ | Datastores specifies allowed datastores for VM placement. Accepted but not<br />acted on in this release. |  | MaxItems: 100 <br />Optional: \{\} <br /> |
| `hosts` _string array_ | Hosts lists Hosts by resource name. In hard, only the listed Hosts are<br />candidates. In soft, a listed Host ranks higher. |  | MaxItems: 200 <br />Optional: \{\} <br /> |
| `folders` _string array_ | Folders specifies allowed folders for VM placement. Accepted but not acted<br />on in this release. |  | MaxItems: 50 <br />Optional: \{\} <br /> |
| `resourcePools` _string array_ | ResourcePools specifies allowed resource pools for VM placement. Accepted<br />but not acted on in this release. |  | MaxItems: 100 <br />Optional: \{\} <br /> |
| `networks` _string array_ | Networks specifies allowed networks for VM placement. Accepted but not<br />acted on in this release. |  | MaxItems: 50 <br />Optional: \{\} <br /> |
| `zones` _string array_ | Zones specifies allowed availability zones. Accepted but not acted on in<br />this release. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `regions` _string array_ | Regions specifies allowed regions. Accepted but not acted on in this<br />release. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `nodeSelector` _object (keys:string, values:string)_ | NodeSelector is a set of label key/value pairs matched against the labels<br />in Host.spec.labels. In hard, a Host must carry every pair. In soft, a<br />Host ranks higher for each pair it carries. |  | MaxProperties: 20 <br />Optional: \{\} <br /> |
| `tolerations` _[VMToleration](#vmtoleration) array_ | Tolerations specifies tolerations for node placement. Accepted but not<br />acted on in this release. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `excludedClusters` _string array_ | ExcludedClusters specifies clusters to exclude from placement. Accepted<br />but not acted on in this release. |  | MaxItems: 50 <br />Optional: \{\} <br /> |
| `excludedHosts` _string array_ | ExcludedHosts lists Hosts by resource name. In hard, a listed Host is not<br />a candidate. In soft, a listed Host ranks lower. |  | MaxItems: 200 <br />Optional: \{\} <br /> |
| `excludedDatastores` _string array_ | ExcludedDatastores specifies datastores to exclude from placement.<br />Accepted but not acted on in this release. |  | MaxItems: 100 <br />Optional: \{\} <br /> |


#### PlacementResources



PlacementResources is a CPU/memory size recorded by the clustered scheduler
(status.placement.pendingResources).



_Appears in:_
- [PlacementStatus](#placementstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `cpu` _integer_ | CPU is the number of vCPUs (at most the VMClass maximum, 128). |  | Maximum: 128 <br />Minimum: 0 <br /> |
| `memoryMiB` _integer_ | MemoryMiB is the memory in MiB (at most the VMClass maximum, 100 TiB). |  | Maximum: 1.048576e+08 <br />Minimum: 0 <br /> |


#### PlacementStatistics



PlacementStatistics provides statistics about VM placements. Not populated
in this release.



_Appears in:_
- [VMPlacementPolicyStatus](#vmplacementpolicystatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `totalPlacements` _integer_ | TotalPlacements is the total number of VM placements using this policy.<br />Not populated in this release. |  | Optional: \{\} <br /> |
| `successfulPlacements` _integer_ | SuccessfulPlacements is the number of successful placements. Not populated<br />in this release. |  | Optional: \{\} <br /> |
| `failedPlacements` _integer_ | FailedPlacements is the number of failed placements. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `averagePlacementTime` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | AveragePlacementTime is the average time for VM placement. Not populated<br />in this release. |  | Optional: \{\} <br /> |
| `constraintViolations` _integer_ | ConstraintViolations is the number of constraint violations. Not populated<br />in this release. |  | Optional: \{\} <br /> |
| `lastPlacementTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LastPlacementTime is when the last VM was placed using this policy. Not<br />populated in this release. |  | Optional: \{\} <br /> |
| `placementDistribution` _object (keys:string, values:integer)_ | PlacementDistribution shows how VMs are distributed across hosts/clusters.<br />Not populated in this release. |  | Optional: \{\} <br /> |


#### PlacementStatus



PlacementStatus is the operator scheduler's binding for a VM on a clustered
provider: the durable record of which HostPool host runs the VM, plus the
decision trace. Host is written only after the provider confirms placement
(create success), so it never claims a host the provider has not accepted the
VM on; PendingHost records, separately, the host an unconfirmed Create is
aimed at.



_Appears in:_
- [VirtualMachineStatus](#virtualmachinestatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `host` _string_ | Host is the Host (CR name) this VM is bound to run on — the durable<br />placement record. Written only after the provider confirms.<br />Every per-VM provider call for the VM is routed to this host. |  | Optional: \{\} <br /> |
| `pendingHost` _string_ | PendingHost is the Host (CR name) an in-flight, not yet confirmed Create is<br />aimed at. The operator writes it, with Pool,<br />through a resourceVersion-checked status update BEFORE calling Create, so<br />a retry after a lost write or a Create that ran past its deadline lands on<br />the SAME host instead of being scheduled onto another one (which could<br />leave a second domain of the same name behind). When Create succeeds it is<br />moved into Host and cleared. It is used only to route the Create retry and<br />the finalizer's owner-checked cleanup; it is never a binding. An<br />administrator may clear it to release a VM whose pending host is gone for<br />good (the operator never re-schedules such a VM on its own). |  | Optional: \{\} <br /> |
| `excludedHosts` _string array_ | ExcludedHosts are Hosts (CR names) the scheduler must not choose for this<br />VM. A Host is added when a Create on<br />it was refused with a name conflict (ALREADY_EXISTS: a same-named domain<br />this VM does not own is there), which proves this VM has no domain on it<br />and that this attempt created nothing there (an earlier failed attempt<br />may have left disk or cloud-init files, which no owner-checked cleanup<br />could remove either); its pendingHost is then cleared and the VM is<br />re-scheduled onto another Host. The list is bounded (the oldest entry is<br />dropped when it is full) and is cleared when the VM is bound. If every<br />candidate Host is<br />excluded the VM stays unplaced (Placed=False/AllHostsExcluded) until an<br />administrator resolves the name conflicts and clears this list. |  | MaxItems: 16 <br />items:MaxLength: 253 <br />Optional: \{\} <br /> |
| `pendingResources` _[PlacementResources](#placementresources)_ | PendingResources is the size the scheduler admitted a pending Create at.<br />The operator writes<br />it with PendingHost, in the same checked status update, and clears it when<br />the VM is bound or the pending host is released. While a create is<br />pending, the VM counts at this size against its host's capacity, and a<br />retry of the Create whose size has grown beyond it (its VMClass was<br />changed in the meantime) is not sent. |  | Optional: \{\} <br /> |
| `memoryCeilingMiB` _integer_ | MemoryCeilingMiB is the memory the VM's domain may reach on its host<br />beyond its current allocation, recorded when its create was scheduled: the<br />balloon maximum provisioned for a VMClass with memory hot-add (4× the<br />initial memory), or 0 when none was provisioned. A guest can deflate its balloon up to it, so<br />the clustered accounting counts the VM's memory at the larger of this and<br />its current size. It is kept when the VM is bound. Unset means unknown (a<br />VM scheduled by an older manager): the VMClass's hot-add setting is used<br />until the VM's first Describe reports its domain's actual memory maximum,<br />which is then recorded once. A recorded value is raised when the<br />provider reports more, and lowered when it reports less (after a<br />confirmed memory shrink). At most the VMClass memory maximum (100 TiB). |  | Maximum: 1.048576e+08 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `pool` _string_ | Pool is the HostPool the VM was scheduled into. |  | Optional: \{\} <br /> |
| `lastScheduledTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LastScheduledTime is when the scheduler last (re)bound this VM to Host. |  | Optional: \{\} <br /> |
| `reason` _string_ | Reason records why this host was chosen — the scheduler's decision trace<br />(e.g. the winning score or the constraint that narrowed the candidates). |  | Optional: \{\} <br /> |


#### PolicyConflict



PolicyConflict represents a conflict between policies. Not populated in
this release.



_Appears in:_
- [VMPlacementPolicyStatus](#vmplacementpolicystatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `policyName` _string_ | PolicyName is the name of the conflicting policy. Not populated in this<br />release. |  |  |
| `conflictType` _string_ | ConflictType describes the type of conflict. Not populated in this<br />release. |  | Enum: [hard soft resource security affinity] <br /> |
| `description` _string_ | Description provides details about the conflict. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `severity` _string_ | Severity indicates the severity of the conflict. Not populated in this<br />release. |  | Enum: [low medium high critical] <br />Optional: \{\} <br /> |
| `resolutionSuggestion` _string_ | ResolutionSuggestion provides suggestions for resolving the conflict. Not<br />populated in this release. |  | Optional: \{\} <br /> |


#### PolicyValidationResult



PolicyValidationResult represents a validation result for a provider. Not
populated in this release.



_Appears in:_
- [VMPlacementPolicyStatus](#vmplacementpolicystatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `valid` _boolean_ | Valid indicates if the policy is valid for the provider. Not populated in<br />this release. |  |  |
| `message` _string_ | Message provides details about the validation result. Not populated in<br />this release. |  | Optional: \{\} <br /> |
| `warnings` _string array_ | Warnings lists any validation warnings. Not populated in this release. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `errors` _string array_ | Errors lists any validation errors. Not populated in this release. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `supportedFeatures` _string array_ | SupportedFeatures lists features supported by the provider. Not populated<br />in this release. |  | MaxItems: 50 <br />Optional: \{\} <br /> |
| `unsupportedFeatures` _string array_ | UnsupportedFeatures lists features not supported by the provider. Not<br />populated in this release. |  | MaxItems: 50 <br />Optional: \{\} <br /> |
| `lastValidated` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LastValidated is when this validation was last performed. Not populated in<br />this release. |  | Optional: \{\} <br /> |


#### PoolMigrationPolicy



PoolMigrationPolicy is the default migration policy for VMs in a HostPool.
The API records it, but no controller reads it in this release: there is no
live migration between the hosts of a pool, so none of these fields has an
effect.



_Appears in:_
- [HostPoolSpec](#hostpoolspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `defaultLive` _boolean_ | DefaultLive requests live (RAM-transfer) migration by default. When false,<br />migrations tolerate downtime and may fall back to stage_copy. Defaults<br />true. Accepted but not acted on in this release. | true | Optional: \{\} <br /> |
| `defaultStorageMode` _string_ | DefaultStorageMode selects the intra-cluster data path. Defaults to shared.<br />Accepted but not acted on in this release. | shared | Enum: [shared block_all block_inc stage_copy] <br />Optional: \{\} <br /> |
| `requireTLS` _boolean_ | RequireTLS would force QEMU-native --tls on the migration data path.<br />Defaults false. Accepted but not acted on in this release. | false | Optional: \{\} <br /> |
| `bandwidthMbps` _integer_ | BandwidthMbps optionally caps migration bandwidth in Mbps. Accepted but not<br />acted on in this release. |  | Minimum: 1 <br />Optional: \{\} <br /> |
| `maxDowntimeMs` _integer_ | MaxDowntimeMs optionally caps the tolerated switchover downtime in<br />milliseconds. Accepted but not acted on in this release. |  | Minimum: 1 <br />Optional: \{\} <br /> |


#### PoolNetworkRef



PoolNetworkRef names a network (bridge / VLAN / overlay) available in a
HostPool. Per-host presence is asserted via Host.spec.labels. The list is
descriptive in this release: no controller reads it.



_Appears in:_
- [HostPoolSpec](#hostpoolspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the network name (e.g. the bridge name shared across the pool). A<br />matching Host.spec.labels entry asserts per-host presence. |  | MaxLength: 253 <br />MinLength: 1 <br /> |


#### PortRange



PortRange defines a port range. Accepted but not acted on in this release.



_Appears in:_
- [FirewallRule](#firewallrule)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `start` _integer_ | Start is the starting port. Accepted but not acted on in this release. |  | Maximum: 65535 <br />Minimum: 1 <br /> |
| `end` _integer_ | End is the ending port (optional, defaults to start). Accepted but not<br />acted on in this release. |  | Maximum: 65535 <br />Minimum: 1 <br />Optional: \{\} <br /> |


#### PortgroupSecurityConfig



PortgroupSecurityConfig defines portgroup security settings. Accepted but
not acted on in this release.



_Appears in:_
- [VSphereNetworkConfig](#vspherenetworkconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `allowPromiscuous` _boolean_ | AllowPromiscuous allows promiscuous mode. Accepted but not acted on in<br />this release. | false | Optional: \{\} <br /> |
| `allowMACChanges` _boolean_ | AllowMACChanges allows MAC address changes. Accepted but not acted on in<br />this release. | true | Optional: \{\} <br /> |
| `allowForgedTransmits` _boolean_ | AllowForgedTransmits allows forged transmits. Accepted but not acted on in<br />this release. | true | Optional: \{\} <br /> |


#### PowerState

_Underlying type:_ _string_

PowerState represents the desired power state of a VM

_Validation:_
- Enum: [On Off OffGraceful]

_Appears in:_
- [VirtualMachineSpec](#virtualmachinespec)

| Field | Description |
| --- | --- |
| `On` | PowerStateOn indicates the VM should be powered on<br /> |
| `Off` | PowerStateOff indicates the VM should be powered off<br /> |
| `OffGraceful` | PowerStateOffGraceful indicates the VM should be gracefully shut down<br /> |


#### Provider



Provider is the Schema for the providers API



_Appears in:_
- [ProviderList](#providerlist)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `Provider` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[ProviderSpec](#providerspec)_ |  |  |  |
| `status` _[ProviderStatus](#providerstatus)_ |  |  |  |


#### ProviderAdoptionStatus



ProviderAdoptionStatus tracks VM adoption progress



_Appears in:_
- [ProviderStatus](#providerstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `lastDiscoveryTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LastDiscoveryTime is when VMs were last discovered |  | Optional: \{\} <br /> |
| `discoveredVMs` _integer_ | DiscoveredVMs is the count of VMs found in provider |  | Optional: \{\} <br /> |
| `adoptedVMs` _integer_ | AdoptedVMs is the count of VMs successfully adopted |  | Optional: \{\} <br /> |
| `failedAdoptions` _integer_ | FailedAdoptions is the count of failed adoption attempts |  | Optional: \{\} <br /> |
| `message` _string_ | Message provides details about adoption status |  | Optional: \{\} <br /> |


#### ProviderCapability

_Underlying type:_ _string_

ProviderCapability represents a provider capability

_Validation:_
- Enum: [VirtualMachines Snapshots Cloning LiveMigration ConsoleAccess DiskManagement NetworkManagement GPUPassthrough HighAvailability Backup Templates]

_Appears in:_
- [ProviderStatus](#providerstatus)

| Field | Description |
| --- | --- |
| `VirtualMachines` | ProviderCapabilityVirtualMachines indicates basic VM management<br /> |
| `Snapshots` | ProviderCapabilitySnapshots indicates snapshot support<br /> |
| `Cloning` | ProviderCapabilityCloning indicates VM cloning support<br /> |
| `LiveMigration` | ProviderCapabilityLiveMigration indicates live migration support<br /> |
| `ConsoleAccess` | ProviderCapabilityConsoleAccess indicates console access support<br /> |
| `DiskManagement` | ProviderCapabilityDiskManagement indicates disk management support<br /> |
| `NetworkManagement` | ProviderCapabilityNetworkManagement indicates network management support<br /> |
| `GPUPassthrough` | ProviderCapabilityGPUPassthrough indicates GPU passthrough support<br /> |
| `HighAvailability` | ProviderCapabilityHighAvailability indicates HA support<br /> |
| `Backup` | ProviderCapabilityBackup indicates backup support<br /> |
| `Templates` | ProviderCapabilityTemplates indicates template management support<br /> |




#### ProviderDefaults



ProviderDefaults provides default settings for VMs



_Appears in:_
- [ProviderSpec](#providerspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `datastore` _string_ | Datastore specifies the default datastore.<br />Mutually exclusive with StoragePod; Datastore takes precedence if both are set. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `storagePod` _string_ | StoragePod specifies a vSphere Datastore Cluster (StoragePod) used as the default<br />for automatic datastore selection when no explicit Datastore is specified. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `cluster` _string_ | Cluster specifies the default cluster |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `folder` _string_ | Folder specifies the default folder |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `resourcePool` _string_ | ResourcePool specifies the default resource pool |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `network` _string_ | Network specifies the default network |  | MaxLength: 255 <br />Optional: \{\} <br /> |


#### ProviderHealthCheck



ProviderHealthCheck defines health checking configuration. Accepted but not
acted on in this release.



_Appears in:_
- [ProviderSpec](#providerspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled indicates whether health checking is enabled. Defaults to true.<br />Accepted but not acted on in this release. | true | Optional: \{\} <br /> |
| `interval` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | Interval defines how often to check provider health | 30s | Optional: \{\} <br /> |
| `timeout` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | Timeout defines the timeout for health checks | 10s | Optional: \{\} <br /> |
| `failureThreshold` _integer_ | FailureThreshold is the number of consecutive failures before marking unhealthy | 3 | Maximum: 10 <br />Minimum: 1 <br />Optional: \{\} <br /> |
| `successThreshold` _integer_ | SuccessThreshold is the number of consecutive successes before marking healthy | 1 | Maximum: 10 <br />Minimum: 1 <br />Optional: \{\} <br /> |


#### ProviderImageStatus



ProviderImageStatus is the prepare state of an image on one Provider (an
entry of VMImageStatus.ProviderStatus).



_Appears in:_
- [VMImageStatus](#vmimagestatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `available` _boolean_ | Available indicates if the image is available on this provider |  |  |
| `providerUID` _string_ | ProviderUID is the UID of the Provider object this entry was recorded<br />through. A VirtualMachine uses the entry only when it equals its<br />Provider's current UID. An entry with another UID (the Provider was<br />deleted and re-created under the same namespace and name) or with none<br />(an entry from an earlier release) is re-validated: the idempotent<br />prepare is issued again through the current Provider, which confirms (or<br />re-creates) the prepared image, and its UID is recorded. When<br />spec.prepare.onMissing forbids preparing (Fail, Wait), an available<br />entry recorded through a previous object of the same Provider is<br />accepted as is, with a warning, and the current UID recorded; an entry<br />with no UID is never used and VM creates wait (reason<br />ProviderUIDMissing) until this field is set. The prepare runs only<br />before a VM is created, never for a VM that exists. |  | Optional: \{\} <br /> |
| `taskRef` _string_ | TaskRef is the provider task of an in-flight asynchronous prepare on<br />this Provider. It is polled only through this Provider, and only while<br />ProviderUID is the Provider's current UID; it is cleared when the<br />prepare completes. |  | Optional: \{\} <br /> |
| `sourceDigest` _string_ | SourceDigest is the digest of the spec.source this entry was prepared<br />for ("sha256:" and 64 lowercase hex digits), as confirmed by the<br />provider's stamp on the prepared artifact. A VirtualMachine is<br />created from the entry only while it equals the digest of the current<br />spec.source; an entry without it (recorded by an earlier release) or with<br />another digest is not used, and the image is prepared again for the<br />current source when spec.prepare.onMissing allows it. |  | MaxLength: 71 <br />Pattern: `^sha256:[0-9a-f]\{64\}$` <br />Optional: \{\} <br /> |
| `id` _string_ | ID is the provider-specific identifier of the prepared image (on vSphere,<br />the template's absolute inventory path). |  | Optional: \{\} <br /> |
| `path` _string_ | Path is the provider-specific location of the prepared image (on libvirt,<br />the file in the storage pool). |  | Optional: \{\} <br /> |
| `size` _[Quantity](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#quantity-resource-api)_ | Size is the image size on this provider. Not populated in this release. |  | Optional: \{\} <br /> |
| `lastUpdated` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LastUpdated is when this entry was last updated |  | Optional: \{\} <br /> |
| `message` _string_ | Message provides provider-specific status information, for example why<br />the image was held or refused on this Provider |  | Optional: \{\} <br /> |


#### ProviderList



ProviderList contains a list of Provider





| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `ProviderList` | | |
| `metadata` _[ListMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#listmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `items` _[Provider](#provider) array_ |  |  |  |


#### ProviderNetworkStatus



ProviderNetworkStatus contains provider-specific network status. Not
populated in this release.



_Appears in:_
- [VMNetworkAttachmentStatus](#vmnetworkattachmentstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `available` _boolean_ | Available indicates if the network is available on this provider. Not<br />populated in this release. |  |  |
| `id` _string_ | ID is the provider-specific network identifier. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `state` _string_ | State is the provider-specific network state. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `lastUpdated` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LastUpdated is when the status was last updated. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `message` _string_ | Message provides provider-specific status information. Not populated in<br />this release. |  | Optional: \{\} <br /> |


#### ProviderResourceUsage



ProviderResourceUsage provides resource usage statistics



_Appears in:_
- [ProviderStatus](#providerstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `cpu` _[ResourceUsageStats](#resourceusagestats)_ | CPU usage statistics |  | Optional: \{\} <br /> |
| `memory` _[ResourceUsageStats](#resourceusagestats)_ | Memory usage statistics |  | Optional: \{\} <br /> |
| `storage` _[ResourceUsageStats](#resourceusagestats)_ | Storage usage statistics |  | Optional: \{\} <br /> |
| `network` _[NetworkUsageStats](#networkusagestats)_ | Network usage statistics |  | Optional: \{\} <br /> |


#### ProviderRuntimeMode

_Underlying type:_ _string_

ProviderRuntimeMode specifies how the provider is executed

_Validation:_
- Enum: [Remote]

_Appears in:_
- [ProviderRuntimeSpec](#providerruntimespec)
- [ProviderRuntimeStatus](#providerruntimestatus)

| Field | Description |
| --- | --- |
| `Remote` | RuntimeModeRemote runs the provider as a separate deployment<br /> |


#### ProviderRuntimePhase

_Underlying type:_ _string_

ProviderRuntimePhase represents the phase of provider runtime

_Validation:_
- Enum: [Pending Starting Running Stopping Failed]

_Appears in:_
- [ProviderRuntimeStatus](#providerruntimestatus)

| Field | Description |
| --- | --- |
| `Pending` | ProviderRuntimePhasePending indicates the runtime is being prepared<br /> |
| `Starting` | ProviderRuntimePhaseStarting indicates the runtime is starting<br /> |
| `Running` | ProviderRuntimePhaseRunning indicates the runtime is operational<br /> |
| `Stopping` | ProviderRuntimePhaseStopping indicates the runtime is stopping<br /> |
| `Failed` | ProviderRuntimePhaseFailed indicates the runtime has failed<br /> |


#### ProviderRuntimeSpec



ProviderRuntimeSpec defines the runtime configuration for providers



_Appears in:_
- [ProviderSpec](#providerspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `mode` _[ProviderRuntimeMode](#providerruntimemode)_ | Mode specifies the runtime mode (always Remote) | Remote | Enum: [Remote] <br />Optional: \{\} <br /> |
| `image` _string_ | Image is the container image for remote providers (required)<br />Supports formats: image:tag, image@digest, or image:tag@digest |  | Pattern: `^[a-zA-Z0-9._/-]+(:[a-zA-Z0-9._-]+)?(@[a-zA-Z0-9]+:[a-fA-F0-9]\{64\})?$` <br /> |
| `imagePullPolicy` _[PullPolicy](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#pullpolicy-v1-core)_ | ImagePullPolicy defines the image pull policy | IfNotPresent | Enum: [Always Never IfNotPresent] <br />Optional: \{\} <br /> |
| `imagePullSecrets` _[LocalObjectReference](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#localobjectreference-v1-core) array_ | ImagePullSecrets are references to secrets for pulling images. Accepted but<br />not acted on in this release: the manager does not add them to the provider<br />pod. |  | MaxItems: 10 <br />Optional: \{\} <br /> |
| `replicas` _integer_ | Replicas is the number of provider instances (default 1). A clustered<br />Provider (topology: cluster) and a vSphere Provider always run one<br />replica, replaced with the Recreate strategy; for them a larger value is<br />ignored. | 1 | Maximum: 10 <br />Minimum: 1 <br />Optional: \{\} <br /> |
| `service` _[ProviderServiceSpec](#providerservicespec)_ | Service defines the service configuration |  | Optional: \{\} <br /> |
| `resources` _[ResourceRequirements](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#resourcerequirements-v1-core)_ | Resources defines resource requirements for provider pods |  | Optional: \{\} <br /> |
| `nodeSelector` _object (keys:string, values:string)_ | NodeSelector is a selector which must be true for the pod to fit on a node |  | Optional: \{\} <br /> |
| `tolerations` _[Toleration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#toleration-v1-core) array_ | Tolerations allow pods to schedule onto nodes with matching taints |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `affinity` _[Affinity](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#affinity-v1-core)_ | Affinity defines scheduling constraints |  | Optional: \{\} <br /> |
| `securityContext` _[SecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#securitycontext-v1-core)_ | SecurityContext defines security context for provider pods |  | Optional: \{\} <br /> |
| `logLevel` _string_ | LogLevel sets the log level for provider pods<br />Defaults to the controller's log level if not specified | info | Enum: [debug info warn error] <br />Optional: \{\} <br /> |
| `logFormat` _string_ | LogFormat sets the log format for provider pods | text | Enum: [text json] <br />Optional: \{\} <br /> |
| `env` _[EnvVar](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#envvar-v1-core) array_ | Env defines additional environment variables for provider pods |  | MaxItems: 50 <br />Optional: \{\} <br /> |
| `livenessProbe` _[Probe](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#probe-v1-core)_ | LivenessProbe defines the liveness probe for provider pods. Accepted but not<br />acted on in this release: the manager always uses its built-in probe (HTTP<br />GET /healthz on port 8080). |  | Optional: \{\} <br /> |
| `readinessProbe` _[Probe](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#probe-v1-core)_ | ReadinessProbe defines the readiness probe for provider pods. Accepted but<br />not acted on in this release: the manager always uses its built-in probe<br />(HTTP GET /healthz on port 8080). |  | Optional: \{\} <br /> |


#### ProviderRuntimeStatus



ProviderRuntimeStatus defines the runtime status for providers



_Appears in:_
- [ProviderStatus](#providerstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `mode` _[ProviderRuntimeMode](#providerruntimemode)_ | Mode indicates the current runtime mode |  | Enum: [Remote] <br />Optional: \{\} <br /> |
| `endpoint` _string_ | Endpoint is the gRPC endpoint (host:port) for remote providers |  | Optional: \{\} <br /> |
| `serviceRef` _[LocalObjectReference](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#localobjectreference-v1-core)_ | ServiceRef references the Kubernetes service for remote providers |  | Optional: \{\} <br /> |
| `phase` _[ProviderRuntimePhase](#providerruntimephase)_ | Phase indicates the runtime phase |  | Enum: [Pending Starting Running Stopping Failed] <br />Optional: \{\} <br /> |
| `message` _string_ | Message provides additional details about the runtime status |  | Optional: \{\} <br /> |
| `readyReplicas` _integer_ | ReadyReplicas is the number of ready provider replicas. Not populated in<br />this release; see the provider Deployment's status instead. |  | Optional: \{\} <br /> |
| `availableReplicas` _integer_ | AvailableReplicas is the number of available provider replicas. Not<br />populated in this release; see the provider Deployment's status instead. |  | Optional: \{\} <br /> |


#### ProviderServiceSpec



ProviderServiceSpec defines the service configuration for remote providers



_Appears in:_
- [ProviderRuntimeSpec](#providerruntimespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `port` _integer_ | Port is the gRPC service port | 9443 | Maximum: 65535 <br />Minimum: 1024 <br />Optional: \{\} <br /> |
| `tls` _[ProviderTLSSpec](#providertlsspec)_ | TLS defines TLS configuration for the service. Leaving it unset is not an<br />implicit plaintext choice: a Provider without a tls block is not deployed<br />(condition TLSConfigured=False, reason TLSBlockMissing). Set tls.enabled to<br />false to opt out of TLS explicitly. |  | Optional: \{\} <br /> |


#### ProviderSnapshotStatus



ProviderSnapshotStatus contains provider-specific snapshot status. Not
populated in this release.



_Appears in:_
- [VMSnapshotStatus](#vmsnapshotstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `available` _boolean_ | Available indicates if the snapshot is available on this provider |  |  |
| `id` _string_ | ID is the provider-specific snapshot identifier |  | Optional: \{\} <br /> |
| `path` _string_ | Path is the provider-specific snapshot path |  | Optional: \{\} <br /> |
| `state` _string_ | State is the provider-specific snapshot state |  | Optional: \{\} <br /> |
| `lastUpdated` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LastUpdated is when the status was last updated |  | Optional: \{\} <br /> |
| `message` _string_ | Message provides provider-specific status information |  | Optional: \{\} <br /> |


#### ProviderSpec



ProviderSpec defines the desired state of Provider



_Appears in:_
- [Provider](#provider)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `type` _[ProviderType](#providertype)_ | Type specifies the provider type.<br />Type is IMMUTABLE once set: the controllers decide type-specific safety<br />rules from it (for example, a libvirt linked clone into another namespace<br />is refused), and the VMs a Provider manages were created by, and are<br />addressed with, the provider implementation of this type. To change it,<br />create a new Provider. |  | Enum: [vsphere libvirt firecracker qemu proxmox] <br /> |
| `topology` _string_ | Topology selects the provider's deployment topology:<br />  - "single" (default): one gRPC process bound to one host. There is no<br />    scheduler, no host inventory and no projected host Secret.<br />  - "cluster": the provider fronts N bare hosts registered as Host CRs under<br />    a HostPool. The operator owns inventory and placement, and renders the<br />    pool's Host CRs into a Secret mounted into the provider pod; the<br />    provider reads that mounted file, never the Kubernetes API.<br />Only meaningful for hypervisors with no native cluster manager: the<br />validating webhook accepts "cluster" for type libvirt only and rejects it<br />for the other types. An empty value is defaulted to "single".<br />Topology is IMMUTABLE once set: VMs record where they<br />run (status.placement) under one topology, and every per-VM call is routed<br />and owner-checked by it, so flipping it would send a placed VM's calls down<br />the wrong path. To change it, create a new Provider. The apiserver compares<br />the defaulted values, so an object created before this field existed (read<br />back as "single") keeps accepting ordinary updates. | single | Enum: [single cluster] <br />Optional: \{\} <br /> |
| `endpoint` _string_ | Endpoint is the URI of the hypervisor the provider manages: for vSphere the<br />vCenter SDK URL (https://vcenter.example.com/sdk), for Proxmox the API URL<br />(https://pve.example.com:8006), for libvirt a connection URI (qemu://,<br />qemu+ssh://, qemu+tcp:// or qemu+tls://). The schema also accepts<br />http(s)://, tcp:// and grpc:// URIs. The manager passes it to the provider<br />pod as PROVIDER_ENDPOINT. For a clustered libvirt Provider (topology:<br />cluster) the hosts are given by Host.spec.endpoint instead. |  | Pattern: `^((https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?\|(tcp\|grpc)://[a-zA-Z0-9.-]+:[0-9]+(/.*)?)\|qemu(\+ssh\|\+tcp\|\+tls)?://([a-zA-Z0-9@.-]+(:[0-9]+)?)?(/.*))$` <br /> |
| `credentialSecretRef` _[ObjectRef](#objectref)_ | CredentialSecretRef references the Secret containing the credentials the<br />provider uses to reach the hypervisor. The manager mounts it into the<br />provider pod; the provider reads it from the mounted files. |  |  |
| `insecureSkipVerify` _boolean_ | InsecureSkipVerify makes the provider pod skip verification of the TLS<br />certificate of the hypervisor management endpoint (vCenter for vSphere, the<br />Proxmox VE API for Proxmox). The manager passes it to the provider pod as<br />the TLS_INSECURE_SKIP_VERIFY environment variable, and only the vSphere and<br />Proxmox providers read it; the libvirt provider ignores it (for libvirt SSH<br />hosts see the LIBVIRT_INSECURE_SKIP_HOST_KEY_VERIFICATION environment<br />variable). Defaults to false.<br />It is not the same setting as spec.runtime.service.tls.insecureSkipVerify,<br />which controls the manager's verification of the provider's own gRPC server<br />certificate; setting one does not affect the other. It is an insecure<br />escape hatch: with it set, a network attacker can impersonate the<br />hypervisor endpoint and capture the credentials the provider sends to it. | false | Optional: \{\} <br /> |
| `defaults` _[ProviderDefaults](#providerdefaults)_ | Defaults provides default placement settings. Only the vSphere provider<br />uses them, and only datastore, storagePod, cluster and folder are passed to<br />it (as PROVIDER_DEFAULT_* environment variables); resourcePool and network<br />are accepted but not acted on in this release. libvirt and Proxmox ignore<br />this block. |  | Optional: \{\} <br /> |
| `rateLimit` _[RateLimit](#ratelimit)_ | RateLimit configures API rate limiting. Accepted but not acted on in this<br />release. |  | Optional: \{\} <br /> |
| `runtime` _[ProviderRuntimeSpec](#providerruntimespec)_ | Runtime defines how the provider is executed (required) |  |  |
| `healthCheck` _[ProviderHealthCheck](#providerhealthcheck)_ | HealthCheck defines health checking configuration. Accepted but not acted<br />on in this release: status.healthy follows the readiness of the provider<br />Deployment, whatever these settings say. |  | Optional: \{\} <br /> |
| `connectionPooling` _[ConnectionPooling](#connectionpooling)_ | ConnectionPooling defines connection pooling settings. Accepted but not<br />acted on in this release. |  | Optional: \{\} <br /> |
| `consumerNamespaceSelector` _[LabelSelector](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#labelselector-v1-meta)_ | ConsumerNamespaceSelector selects the namespaces, other than this<br />Provider's own, that may use it: VirtualMachines there may name it in<br />spec.providerRef, and VMClones, VMMigrations and VMSnapshots there may act<br />on VMs through it. A reference from the Provider's own namespace is<br />always allowed.<br />  - unset (the default): only its own namespace may use it.<br />  - \{\} (an empty selector): every namespace may use it.<br />  - matchLabels / matchExpressions: the namespaces whose labels match. The<br />    kubernetes.io/metadata.name label names a namespace explicitly.<br />A reference from a namespace it does not select is refused with<br />Ready=False, reason ConsumerNotAllowed, and no provider call is made for<br />it. The selector is matched against Namespace labels, so whoever can label<br />a namespace can widen what that namespace may use (see<br />docs/cross-namespace-references.md). The selector is operator-side policy:<br />it is never sent to a provider. |  | Optional: \{\} <br /> |


#### ProviderStatus



ProviderStatus defines the observed state of Provider



_Appears in:_
- [Provider](#provider)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `healthy` _boolean_ | Healthy is true while the provider Deployment reports a ready replica<br />(the ProviderAvailable condition is True) and false when it reports<br />none, as last observed from the Deployment: a reconcile that fails<br />before it reaches the Deployment leaves it as it was. |  | Optional: \{\} <br /> |
| `lastHealthCheck` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LastHealthCheck is the time of the last reconcile that found the provider<br />healthy. |  | Optional: \{\} <br /> |
| `runtime` _[ProviderRuntimeStatus](#providerruntimestatus)_ | Runtime provides runtime status information |  | Optional: \{\} <br /> |
| `conditions` _[Condition](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#condition-v1-meta) array_ | Conditions represent the latest available observations |  | Optional: \{\} <br /> |
| `observedGeneration` _integer_ | ObservedGeneration reflects the generation observed by the controller |  | Optional: \{\} <br /> |
| `capabilities` _[ProviderCapability](#providercapability) array_ | Capabilities lists the provider's supported capabilities. Not populated in<br />this release; see reportedCapabilities. |  | Enum: [VirtualMachines Snapshots Cloning LiveMigration ConsoleAccess DiskManagement NetworkManagement GPUPassthrough HighAvailability Backup Templates] <br />Optional: \{\} <br /> |
| `reportedCapabilities` _[ReportedCapabilities](#reportedcapabilities)_ | ReportedCapabilities is the provider's self-reported capability set,<br />fetched from the provider GetCapabilities RPC. It reflects what the running<br />provider advertises and is consumed by the manager to surface features and<br />(when capability enforcement is enabled) to gate capability-dependent<br />operations. It is read once a rollout of the provider runtime is complete,<br />again after the old pods' termination grace period, and every 10 minutes<br />while the provider is healthy and no pod of an older rollout is left. |  | Optional: \{\} <br /> |
| `version` _string_ | Version reports the provider version. Not populated in this release. |  | Optional: \{\} <br /> |
| `connectedVMs` _integer_ | ConnectedVMs is the number of VirtualMachines, in any namespace, whose<br />spec.providerRef names this Provider. |  | Optional: \{\} <br /> |
| `resourceUsage` _[ProviderResourceUsage](#providerresourceusage)_ | ResourceUsage provides resource usage statistics. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `adoption` _[ProviderAdoptionStatus](#provideradoptionstatus)_ | Adoption tracks VM adoption status |  | Optional: \{\} <br /> |


#### ProviderTLSSpec



ProviderTLSSpec defines TLS configuration for provider communication



_Appears in:_
- [ProviderServiceSpec](#providerservicespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled determines if TLS is enabled for the connection between the<br />manager and the provider pod. Defaults to true. With true, secretRef is<br />required: a Provider with tls.enabled=true and no secretRef is not<br />deployed (condition TLSConfigured=False, reason SecretRefMissing). Setting<br />it to false is an explicit opt-out that runs the provider gRPC server<br />without TLS, recorded as TLSConfigured=False, reason ExplicitlyDisabled. | true | Optional: \{\} <br /> |
| `secretRef` _[LocalObjectReference](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#localobjectreference-v1-core)_ | SecretRef references a Secret in the Provider's namespace containing<br />tls.crt, tls.key and ca.crt. The manager presents tls.crt/tls.key as its<br />client certificate and verifies the provider's server certificate against<br />ca.crt; the provider pod mounts the same Secret. |  | Optional: \{\} <br /> |
| `insecureSkipVerify` _boolean_ | InsecureSkipVerify makes the manager skip verification of the provider's<br />gRPC server certificate when it connects to the provider pod (the manager<br />still presents its client certificate). It is read only by the manager,<br />when it builds its TLS client config for this Provider from SecretRef, and<br />only while tls.enabled is true.<br />It does not change anything on the provider pod and has no effect on the<br />connection from the provider to the hypervisor; that is the separate<br />spec.insecureSkipVerify. Defaults to false.<br />This is an insecure escape hatch for first bootstrap and labs: with it the<br />manager cannot tell the real provider from an impostor, which defeats the<br />server-authentication half of mutual TLS. The manager logs a warning each<br />time it opens a new connection to the provider while this is true. | false | Optional: \{\} <br /> |


#### ProviderType

_Underlying type:_ _string_

ProviderType represents the type of virtualization provider

_Validation:_
- Enum: [vsphere libvirt firecracker qemu proxmox]

_Appears in:_
- [ProviderSpec](#providerspec)

| Field | Description |
| --- | --- |
| `vsphere` | ProviderTypeVSphere indicates a VMware vSphere provider<br /> |
| `libvirt` | ProviderTypeLibvirt indicates a libvirt provider<br /> |
| `firecracker` | ProviderTypeFirecracker names a Firecracker provider. The schema accepts<br />it, but VirtRigaud ships no Firecracker provider implementation.<br /> |
| `qemu` | ProviderTypeQEMU names a QEMU provider. The schema accepts it, but<br />VirtRigaud ships no QEMU provider implementation.<br /> |
| `proxmox` | ProviderTypeProxmox indicates a Proxmox VE provider<br /> |


#### ProxmoxImageSource



ProxmoxImageSource defines Proxmox VE-specific image configuration. It
references a template that already exists on Proxmox VE; VirtRigaud does not
import images into Proxmox in this release. Only templateID (or a templateName
that is a VMID) is acted on; storage, node, format and fullClone are accepted
but not acted on in this release.



_Appears in:_
- [ImageSource](#imagesource)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `templateID` _integer_ | TemplateID specifies an existing Proxmox template VMID. A VM is cloned from<br />it with a full clone. Nothing is prepared for this source. |  | Maximum: 9.99999999e+08 <br />Minimum: 100 <br />Optional: \{\} <br /> |
| `templateName` _string_ | TemplateName specifies an existing Proxmox template. The clone is made by<br />VMID only, so the value must be the template's VMID as a number; any other<br />name makes the VM create fail with InvalidSpec. Use templateID. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `storage` _string_ | Storage specifies the Proxmox storage for cloning, for example "local-lvm".<br />Accepted but not acted on in this release. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `node` _string_ | Node specifies the Proxmox node where the template exists. Accepted but not<br />acted on in this release. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `format` _string_ | Format specifies the disk format. Accepted but not acted on in this<br />release. | qcow2 | Enum: [raw qcow2 vmdk] <br />Optional: \{\} <br /> |
| `fullClone` _boolean_ | FullClone determines if this should be a full clone (default) or linked<br />clone. Accepted but not acted on in this release: the provider always makes<br />a full clone. | true | Optional: \{\} <br /> |


#### ProxmoxNetworkConfig



ProxmoxNetworkConfig defines Proxmox VE-specific network settings. bridge,
model and vlanTag are acted on; firewall,
rateLimit and mtu are accepted but not acted on in this release.



_Appears in:_
- [NetworkConfig](#networkconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `bridge` _string_ | Bridge is the Linux bridge the NIC attaches to, for example vmbr0 or<br />vmbr1. The CRD accepts names of the form vmbr<N> only, although the<br />Proxmox provider accepts any Linux bridge name. When it is empty a new VM<br />gets vmbr0 and a VM cloned from a template keeps the template's bridge. |  | MaxLength: 15 <br />Pattern: `^vmbr[0-9]+$` <br />Optional: \{\} <br /> |
| `model` _string_ | Model is the NIC model. It defaults to virtio. | virtio | Enum: [virtio e1000 rtl8139 vmxnet3] <br />Optional: \{\} <br /> |
| `vlanTag` _integer_ | VLANTag is the VLAN tag set on the NIC. When bridge is also set, the NIC<br />gets exactly this tag, or none when it is empty. |  | Maximum: 4094 <br />Minimum: 1 <br />Optional: \{\} <br /> |
| `firewall` _boolean_ | Firewall enables the Proxmox firewall for this interface. Accepted but not<br />acted on in this release. | false | Optional: \{\} <br /> |
| `rateLimit` _integer_ | RateLimit specifies the bandwidth limit in MB/s. Accepted but not acted on<br />in this release. |  | Minimum: 1 <br />Optional: \{\} <br /> |
| `mtu` _integer_ | MTU specifies the Maximum Transmission Unit. Accepted but not acted on in<br />this release. |  | Maximum: 65520 <br />Minimum: 68 <br />Optional: \{\} <br /> |


#### RateLimit



RateLimit configures API rate limiting. Accepted but not acted on in this
release.



_Appears in:_
- [ProviderSpec](#providerspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `qps` _integer_ | QPS specifies queries per second | 10 | Maximum: 1000 <br />Minimum: 1 <br />Optional: \{\} <br /> |
| `burst` _integer_ | Burst specifies the burst capacity | 20 | Maximum: 2000 <br />Minimum: 1 <br />Optional: \{\} <br /> |


#### RegistryImageSource



RegistryImageSource defines container registry image configuration. Accepted
but not acted on in this release: no provider pulls from a registry, and none
of its fields is read.



_Appears in:_
- [ImageSource](#imagesource)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `image` _string_ | Image is the container image reference. Accepted but not acted on in this<br />release. |  | Pattern: `^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$` <br /> |
| `pullSecretRef` _[LocalObjectReference](#localobjectreference)_ | PullSecretRef references a secret for pulling the image. Accepted but not<br />acted on in this release: the Secret is never read. |  | Optional: \{\} <br /> |
| `format` _[ImageFormat](#imageformat)_ | Format specifies the expected image format. Accepted but not acted on in<br />this release. | qcow2 | Enum: [qcow2 raw vmdk vhd vhdx iso ova ovf] <br />Optional: \{\} <br /> |


#### ReportedCapabilities



ReportedCapabilities mirrors the provider.v1 GetCapabilitiesResponse — the
capability set a provider advertises at runtime via the GetCapabilities RPC.
All fields are optional and default to the zero value when a
provider does not advertise them.



_Appears in:_
- [ProviderStatus](#providerstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `supportsReconfigureOnline` _boolean_ | SupportsReconfigureOnline reports online CPU/memory reconfigure support. |  | Optional: \{\} <br /> |
| `supportsDiskExpansionOnline` _boolean_ | SupportsDiskExpansionOnline reports online disk expansion support. |  | Optional: \{\} <br /> |
| `supportsSnapshots` _boolean_ | SupportsSnapshots reports VM snapshot support. |  | Optional: \{\} <br /> |
| `supportsMemorySnapshots` _boolean_ | SupportsMemorySnapshots reports memory-inclusive snapshot support. |  | Optional: \{\} <br /> |
| `supportsLinkedClones` _boolean_ | SupportsLinkedClones reports linked (copy-on-write) clone support. |  | Optional: \{\} <br /> |
| `supportsImageImport` _boolean_ | SupportsImageImport reports image import/preparation support. |  | Optional: \{\} <br /> |
| `supportedDiskTypes` _string array_ | SupportedDiskTypes lists supported disk formats. |  | Optional: \{\} <br /> |
| `supportedNetworkTypes` _string array_ | SupportedNetworkTypes lists supported NIC models. |  | Optional: \{\} <br /> |
| `supportsDiskExport` _boolean_ | SupportsDiskExport reports disk export (migration source) support. |  | Optional: \{\} <br /> |
| `supportsDiskImport` _boolean_ | SupportsDiskImport reports disk import (migration target) support. |  | Optional: \{\} <br /> |
| `supportedExportFormats` _string array_ | SupportedExportFormats lists supported export formats. |  | Optional: \{\} <br /> |
| `supportedImportFormats` _string array_ | SupportedImportFormats lists supported import formats. |  | Optional: \{\} <br /> |
| `supportsExportCompression` _boolean_ | SupportsExportCompression reports export compression support. |  | Optional: \{\} <br /> |
| `supportedExportBackends` _string array_ | SupportedExportBackends lists the storage backends the provider can export<br />disks to (e.g. "pvc", "nfs", "s3"). Empty/absent means pvc-only, the<br />behavior of a provider that predates the other backends. |  | Optional: \{\} <br /> |
| `supportedImportBackends` _string array_ | SupportedImportBackends lists the storage backends the provider can import<br />disks from (e.g. "pvc", "nfs", "s3"). Empty/absent means pvc-only. |  | Optional: \{\} <br /> |
| `supportedTransferModes` _string array_ | SupportedTransferModes lists the disk-transfer modes the provider supports<br />(e.g. "relay", "direct"). Empty/absent means relay-only, the pod-side path<br />through the provider pod. |  | Optional: \{\} <br /> |
| `supportsImageArtifactIdentity` _boolean_ | SupportsImageArtifactIdentity reports that the provider's image prepare<br />names, stamps and verifies each prepared-image artifact by the VMImage's<br />UID and source digest, and never reuses an artifact by bare name.<br />Import-style images are not prepared through a provider that<br />supports image import but does not report this: VM creates wait until<br />the provider is upgraded. |  | Optional: \{\} <br /> |
| `supportsHonestReconfigure` _boolean_ | SupportsHonestReconfigure reports that the provider's Reconfigure never<br />reports success for a change it did not apply: each change is applied<br />to the running VM and its persistent definition, or to the definition<br />only and reported as restart-required, or the call fails. A VM on a<br />clustered Provider that does not report this is not resized<br />(Reconfiguring=False/ProviderLacksHonestReconfigure): its<br />committed-capacity accounting trusts the result. |  | Optional: \{\} <br /> |


#### ResourceConstraints



ResourceConstraints defines placement constraints on the resources and CPU
features of a Host. The scheduler acts on minCPUPerHost, minMemoryPerHost,
minDiskSpacePerHost, requiredFeatures and preferredFeatures. The
utilization limits are accepted but not acted on in this release.



_Appears in:_
- [VMPlacementPolicySpec](#vmplacementpolicyspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `minCPUPerHost` _integer_ | MinCPUPerHost is the minimum number of CPUs a Host must have<br />(Host.status.allocatableCPU, before overcommit). A Host below it is not a<br />candidate. |  | Minimum: 1 <br />Optional: \{\} <br /> |
| `minMemoryPerHost` _[Quantity](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#quantity-resource-api)_ | MinMemoryPerHost is the minimum memory a Host must have<br />(Host.status.allocatableMemoryMiB, before overcommit). A Host below it is<br />not a candidate. |  | Optional: \{\} <br /> |
| `minDiskSpacePerHost` _[Quantity](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#quantity-resource-api)_ | MinDiskSpacePerHost is the minimum allocatable storage a Host must report<br />(Host.status.allocatableStorageBytes). A Host below it, or one that<br />reports none, is not a candidate. |  | Optional: \{\} <br /> |
| `maxCPUUtilization` _integer_ | MaxCPUUtilization specifies maximum allowed CPU utilization. Accepted but<br />not acted on in this release. |  | Maximum: 100 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `maxMemoryUtilization` _integer_ | MaxMemoryUtilization specifies maximum allowed memory utilization.<br />Accepted but not acted on in this release. |  | Maximum: 100 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `maxDiskUtilization` _integer_ | MaxDiskUtilization specifies maximum allowed disk utilization. Accepted<br />but not acted on in this release. |  | Maximum: 100 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `requiredFeatures` _string array_ | RequiredFeatures lists CPU features that a Host must report in<br />Host.status.cpuFeatures. A Host that lacks one is not a candidate. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `preferredFeatures` _string array_ | PreferredFeatures lists CPU features that rank a Host higher when it<br />reports them in Host.status.cpuFeatures. |  | MaxItems: 20 <br />Optional: \{\} <br /> |


#### ResourceUsageStats



ResourceUsageStats represents usage statistics for a resource



_Appears in:_
- [ProviderResourceUsage](#providerresourceusage)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `total` _integer_ | Total available capacity |  | Optional: \{\} <br /> |
| `used` _integer_ | Used capacity |  | Optional: \{\} <br /> |
| `available` _integer_ | Available capacity |  | Optional: \{\} <br /> |
| `usagePercent` _integer_ | Usage percentage (0-100) |  | Optional: \{\} <br /> |


#### RollingUpdateVMSetStrategy



RollingUpdateVMSetStrategy defines parameters for rolling updates. Accepted
but not acted on in this release.



_Appears in:_
- [VMSetUpdateStrategy](#vmsetupdatestrategy)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `maxUnavailable` _[IntOrString](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#intorstring-intstr-util)_ | MaxUnavailable is the maximum number of VMs that can be unavailable during<br />update. Accepted but not acted on in this release. | 25% | Optional: \{\} <br /> |
| `maxSurge` _[IntOrString](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#intorstring-intstr-util)_ | MaxSurge is the maximum number of VMs that can be created above desired<br />replica count. Accepted but not acted on in this release. | 25% | Optional: \{\} <br /> |
| `partition` _integer_ | Partition indicates the ordinal at which the VMSet should be partitioned<br />for updates. Accepted but not acted on in this release. |  | Minimum: 0 <br />Optional: \{\} <br /> |
| `podManagementPolicy` _[VMSetPodManagementPolicyType](#vmsetpodmanagementpolicytype)_ | PodManagementPolicy controls how VMs are created during initial scale up,<br />when replacing VMs on nodes, or when scaling down. Accepted but not acted<br />on in this release. | OrderedReady | Enum: [OrderedReady Parallel] <br />Optional: \{\} <br /> |


#### S3StorageConfig



S3StorageConfig defines S3-compatible object-storage configuration used to
stage a migration's transferred disk.



_Appears in:_
- [MigrationStorage](#migrationstorage)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `bucket` _string_ | Bucket is the S3 bucket for the transfer object. |  |  |
| `endpoint` _string_ | Endpoint overrides the S3 endpoint (empty = AWS default; set for MinIO/Ceph RGW).<br />The host is checked by the controller before it is used: loopback,<br />link-local (including the 169.254.169.254 cloud-metadata address),<br />unspecified and multicast addresses are refused, and the operator can<br />restrict the allowed hosts further. |  | MaxLength: 263 <br />Optional: \{\} <br /> |
| `region` _string_ | Region is the S3 region for the bucket (empty = provider/SDK default). |  | Optional: \{\} <br /> |
| `prefix` _string_ | Prefix is the key prefix for this migration's objects. |  | Optional: \{\} <br /> |
| `credentialsSecretRef` _[ObjectRef](#objectref)_ | CredentialsSecretRef references a Secret, in the VMMigration's namespace,<br />holding the S3 credentials under the keys accessKeyID and secretAccessKey<br />and, optionally, sessionToken. Credentials are never given inline. |  |  |
| `usePathStyle` _boolean_ | UsePathStyle selects path-style addressing (needed by most non-AWS S3). | false | Optional: \{\} <br /> |


#### SCSIControllerSpec



SCSIControllerSpec defines SCSI controller configuration for vSphere.
Accepted but not acted on in this release.



_Appears in:_
- [DiskSpec](#diskspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `controller` _integer_ | Controller specifies the SCSI controller bus number (0-3)<br />If not specified, uses the first available controller |  | Maximum: 3 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `sharedBus` _string_ | SharedBus specifies the SCSI bus sharing mode | noSharing | Enum: [noSharing virtualSharing physicalSharing] <br />Optional: \{\} <br /> |
| `controllerType` _string_ | ControllerType specifies the SCSI controller type | pvscsi | Enum: [lsilogic buslogic lsilogic-sas pvscsi] <br />Optional: \{\} <br /> |


#### SecurityConstraints



SecurityConstraints defines security-based placement constraints. Accepted
but not acted on in this release.



_Appears in:_
- [VMPlacementPolicySpec](#vmplacementpolicyspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `requireSecureBoot` _boolean_ | RequireSecureBoot requires hosts that support secure boot. Accepted but<br />not acted on in this release. |  | Optional: \{\} <br /> |
| `requireTPM` _boolean_ | RequireTPM requires hosts that support TPM. Accepted but not acted on in<br />this release. |  | Optional: \{\} <br /> |
| `requireEncryptedStorage` _boolean_ | RequireEncryptedStorage requires hosts that support encrypted storage.<br />Accepted but not acted on in this release. |  | Optional: \{\} <br /> |
| `requireNUMATopology` _boolean_ | RequireNUMATopology requires hosts that support NUMA topology. Accepted<br />but not acted on in this release. |  | Optional: \{\} <br /> |
| `allowedSecurityGroups` _string array_ | AllowedSecurityGroups lists allowed security groups. Accepted but not<br />acted on in this release. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `deniedSecurityGroups` _string array_ | DeniedSecurityGroups lists denied security groups. Accepted but not acted<br />on in this release. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `isolationLevel` _string_ | IsolationLevel specifies the required isolation level. Accepted but not<br />acted on in this release. |  | Enum: [none basic strict maximum] <br />Optional: \{\} <br /> |
| `trustLevel` _string_ | TrustLevel specifies the required trust level. Accepted but not acted on<br />in this release. |  | Enum: [untrusted basic trusted highly-trusted] <br />Optional: \{\} <br /> |


#### SecurityProfile



SecurityProfile defines security-related settings. See
VMClassSpec.SecurityProfile for which fields are acted on.



_Appears in:_
- [VMClassSpec](#vmclassspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `secureBoot` _boolean_ | SecureBoot enables secure boot. vSphere forces EFI firmware and enables<br />secure boot; libvirt has libvirt select a Secure Boot OVMF build whose<br />variable-store template has keys enrolled, with SMM, on the q35 machine<br />type (the host needs an OVMF package; docs/libvirt-firmware.md). Proxmox<br />and mock ignore it. | false | Optional: \{\} <br /> |
| `tpmEnabled` _boolean_ | TPMEnabled enables TPM (Trusted Platform Module). vSphere adds a<br />virtual TPM and forces EFI firmware; libvirt adds an emulated TPM.<br />Proxmox and mock ignore it. | false | Optional: \{\} <br /> |
| `tpmVersion` _string_ | TPMVersion specifies the TPM version. Accepted but not acted on in this<br />release. libvirt always emulates TPM 2.0, and vSphere adds its virtual<br />TPM, whatever is set here. |  | Enum: [1.2 2] <br />Optional: \{\} <br /> |
| `vtdEnabled` _boolean_ | VTDEnabled enables Intel VT-d or AMD-Vi. vSphere sets vvtd.enable;<br />libvirt adds an emulated Intel IOMMU with interrupt remapping, which<br />needs the q35 machine type (the virtio devices do not go through it).<br />Proxmox and mock ignore it. | false | Optional: \{\} <br /> |
| `encryptionPolicy` _[EncryptionPolicy](#encryptionpolicy)_ | EncryptionPolicy defines VM encryption settings. Accepted but not acted<br />on in this release. |  | Optional: \{\} <br /> |


#### SnapshotAction



SnapshotAction describes a snapshot operation



_Appears in:_
- [LifecycleHandler](#lifecyclehandler)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the name hint for the snapshot |  |  |
| `includeMemory` _boolean_ | IncludeMemory indicates whether to include memory state |  | Optional: \{\} <br /> |
| `description` _string_ | Description provides context for the snapshot |  | Optional: \{\} <br /> |


#### SnapshotConfig



SnapshotConfig defines snapshot configuration options. Name, description and
includeMemory are sent to the provider. The other fields (quiesce, type,
compression, encryption, consistencyLevel) are accepted but not acted on in
this release.



_Appears in:_
- [VMSnapshotSpec](#vmsnapshotspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name provides a name hint for the snapshot. It defaults to the<br />VMSnapshot's name. The provider may change it: the libvirt provider<br />replaces characters other than letters, digits, "_", "." and "-" with "-"<br />and truncates the name to 64 characters; the vSphere and Proxmox providers<br />use it as given. The provider's own identifier for the snapshot is in<br />status.snapshotID. |  | MaxLength: 255 <br />Pattern: `^[a-zA-Z0-9]([a-zA-Z0-9\-_]*[a-zA-Z0-9])?$` <br />Optional: \{\} <br /> |
| `description` _string_ | Description is a free-text description stored with the snapshot by the<br />vSphere, libvirt and Proxmox providers. |  | MaxLength: 1024 <br />Optional: \{\} <br /> |
| `includeMemory` _boolean_ | IncludeMemory indicates whether to include the VM's memory state in the<br />snapshot. libvirt takes a memory snapshot of a running domain and falls back<br />to a disk-only snapshot when the domain is not running; Proxmox saves the<br />VM state; vSphere asks for the memory state whatever the power state and<br />may refuse it for a powered-off VM. When the manager runs with<br />--enforce-provider-capabilities and the Provider reports that it does not<br />support memory snapshots, the VMSnapshot goes Failed with reason<br />UnsupportedByProvider and no snapshot is attempted. | false | Optional: \{\} <br /> |
| `quiesce` _boolean_ | Quiesce indicates whether to quiesce the file system before snapshotting.<br />Accepted but not acted on in this release: the setting is not sent to any<br />provider. The vSphere provider never quiesces; the libvirt and Proxmox<br />providers take the snapshot without a guest quiesce step. | true | Optional: \{\} <br /> |
| `type` _[SnapshotType](#snapshottype)_ | Type specifies the snapshot type. Accepted but not acted on in this<br />release. | Standard | Enum: [Standard Crash Application] <br />Optional: \{\} <br /> |
| `compression` _boolean_ | Compression enables snapshot compression. Accepted but not acted on in<br />this release. | false | Optional: \{\} <br /> |
| `encryption` _[SnapshotEncryption](#snapshotencryption)_ | Encryption enables snapshot encryption. Accepted but not acted on in this<br />release: no snapshot is encrypted, whatever this block says. |  | Optional: \{\} <br /> |
| `consistencyLevel` _string_ | ConsistencyLevel defines the consistency level required. Accepted but not<br />acted on in this release. | FilesystemConsistent | Enum: [CrashConsistent FilesystemConsistent ApplicationConsistent] <br />Optional: \{\} <br /> |


#### SnapshotEncryption



SnapshotEncryption defines snapshot encryption settings. Accepted but not
acted on in this release.



_Appears in:_
- [SnapshotConfig](#snapshotconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled indicates if encryption should be used. Accepted but not acted on<br />in this release. | false |  |
| `keyProvider` _string_ | KeyProvider specifies the encryption key provider. Accepted but not acted<br />on in this release. |  | Enum: [standard hardware external] <br />Optional: \{\} <br /> |
| `keyRef` _[LocalObjectReference](#localobjectreference)_ | KeyRef references encryption keys. Accepted but not acted on in this<br />release: the referenced object is never read. |  | Optional: \{\} <br /> |


#### SnapshotMetadata



SnapshotMetadata contains snapshot metadata. Accepted but not acted on in
this release: no controller or provider reads any field of it. It is
descriptive only.



_Appears in:_
- [VMSnapshotSpec](#vmsnapshotspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `tags` _object (keys:string, values:string)_ | Tags are key-value pairs for categorizing the snapshot. Descriptive: no<br />controller reads them. |  | MaxProperties: 50 <br />Optional: \{\} <br /> |
| `pinned` _boolean_ | Pinned indicates whether the snapshot is pinned (protected from automatic<br />deletion). Accepted but not acted on in this release: a pinned snapshot is<br />still deleted by retentionPolicy.maxAge or deleteOnVMDelete. | false | Optional: \{\} <br /> |
| `application` _string_ | Application specifies the application that created the snapshot.<br />Descriptive: no controller reads it. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `purpose` _string_ | Purpose describes the purpose of the snapshot. Descriptive: no controller<br />reads it. |  | Enum: [backup testing migration restore-point update other] <br />Optional: \{\} <br /> |
| `environment` _string_ | Environment specifies the environment the snapshot belongs to.<br />Descriptive: no controller reads it. |  | Enum: [dev staging prod test qa uat] <br />Optional: \{\} <br /> |


#### SnapshotPhase

_Underlying type:_ _string_

SnapshotPhase represents the phase of a snapshot. The controller sets
Creating, Ready, Failed and Deleting; Pending and Expired are never set in
this release.

_Validation:_
- Enum: [Pending Creating Ready Deleting Failed Expired]

_Appears in:_
- [VMSnapshotStatus](#vmsnapshotstatus)

| Field | Description |
| --- | --- |
| `Pending` | SnapshotPhasePending is never set in this release: a VMSnapshot whose create<br />has not been issued yet has an empty phase<br /> |
| `Creating` | SnapshotPhaseCreating indicates the snapshot is being created<br /> |
| `Ready` | SnapshotPhaseReady indicates the snapshot is ready for use<br /> |
| `Deleting` | SnapshotPhaseDeleting indicates the snapshot is being deleted<br /> |
| `Failed` | SnapshotPhaseFailed indicates the snapshot operation failed<br /> |
| `Expired` | SnapshotPhaseExpired is never set in this release: an expired snapshot is<br />deleted, not marked<br /> |


#### SnapshotProgress



SnapshotProgress shows the snapshot creation progress. Not populated in this
release.



_Appears in:_
- [VMSnapshotStatus](#vmsnapshotstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `totalBytes` _integer_ | TotalBytes is the total number of bytes to snapshot |  | Optional: \{\} <br /> |
| `completedBytes` _integer_ | CompletedBytes is the number of bytes completed |  | Optional: \{\} <br /> |
| `percentage` _integer_ | Percentage is the completion percentage (0-100) |  | Maximum: 100 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `startTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | StartTime is when the snapshot creation started |  | Optional: \{\} <br /> |
| `eta` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | ETA is the estimated time to completion |  | Optional: \{\} <br /> |


#### SnapshotRef



SnapshotRef references a snapshot. It is used by status.parent and
status.children, which are not populated in this release.



_Appears in:_
- [VMSnapshotStatus](#vmsnapshotstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the snapshot name |  |  |
| `namespace` _string_ | Namespace is the snapshot namespace |  | Optional: \{\} <br /> |
| `uid` _string_ | UID is the snapshot UID |  | Optional: \{\} <br /> |


#### SnapshotRetentionPolicy



SnapshotRetentionPolicy defines snapshot retention rules. The controller acts
on maxAge and deleteOnVMDelete only, and only once the snapshot is Ready; it
checks them about once an hour. When a rule applies it deletes the
VMSnapshot, and the VMSnapshot's finalizer deletes the provider snapshot.
maxCount, preservePinned and gracePeriod are accepted but not acted on in
this release.



_Appears in:_
- [VMSnapshotSpec](#vmsnapshotspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `maxAge` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | MaxAge is the maximum age of a Ready snapshot, counted from<br />status.creationTime. Once the snapshot is older (checked about once an<br />hour), the VMSnapshot is deleted, whatever the state of its VM. |  | Optional: \{\} <br /> |
| `maxCount` _integer_ | MaxCount is the maximum number of snapshots to retain. Accepted but not<br />acted on in this release: no snapshots are removed because of a count. |  | Maximum: 100 <br />Minimum: 1 <br />Optional: \{\} <br /> |
| `deleteOnVMDelete` _boolean_ | DeleteOnVMDelete indicates whether to delete the snapshot when its<br />VirtualMachine is deleted (or no longer exists, or exists only as another VM<br />of the same name). It defaults to true when retentionPolicy is set. A VM<br />deleted with the annotation virtrigaud.io/orphan-on-delete=true is left<br />running on the hypervisor and its snapshots are not deleted with it. | true | Optional: \{\} <br /> |
| `preservePinned` _boolean_ | PreservePinned indicates whether to preserve pinned snapshots. Accepted<br />but not acted on in this release (see also metadata.pinned). | true | Optional: \{\} <br /> |
| `gracePeriod` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | GracePeriod is the grace period before deletion. Accepted but not acted on<br />in this release: a snapshot is deleted as soon as maxAge or deleteOnVMDelete<br />applies. | 24h | Optional: \{\} <br /> |


#### SnapshotRevertPhase

_Underlying type:_ _string_

SnapshotRevertPhase is the phase of the revert spec.snapshot.revertToRef
requests (status.snapshotRevert.phase).

_Validation:_
- Enum: [Pending Reverting Succeeded Failed]

_Appears in:_
- [SnapshotRevertStatus](#snapshotrevertstatus)

| Field | Description |
| --- | --- |
| `Pending` | SnapshotRevertPhasePending: the revert is requested and not done: not<br />sent yet, or sent and answered by the provider that it did not perform<br />it (reason RevertNotPerformed: it is sent again after a backoff). The<br />SnapshotReverted condition's reason says what it waits for.<br /> |
| `Reverting` | SnapshotRevertPhaseReverting: the revert was sent (recorded before the<br />call) and its outcome is not known yet.<br /> |
| `Succeeded` | SnapshotRevertPhaseSucceeded: the provider confirmed the revert.<br /> |
| `Failed` | SnapshotRevertPhaseFailed: the revert failed; it is not retried until<br />spec.snapshot.revertToRef is removed and set again.<br /> |


#### SnapshotRevertStatus



SnapshotRevertStatus records the revert spec.snapshot.revertToRef requests
(status.snapshotRevert). It is written only by the operator, and cleared
when spec.snapshot.revertToRef is removed.



_Appears in:_
- [VirtualMachineStatus](#virtualmachinestatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `snapshotName` _string_ | SnapshotName is the VMSnapshot the revert is for (spec.snapshot.<br />revertToRef.name when it was recorded). |  | MaxLength: 253 <br /> |
| `snapshotUID` _string_ | SnapshotUID is the UID of that VMSnapshot. A VMSnapshot of the same<br />name with another UID is a new request. Empty while the VMSnapshot was<br />not found. |  | MaxLength: 128 <br />Optional: \{\} <br /> |
| `phase` _[SnapshotRevertPhase](#snapshotrevertphase)_ | Phase is Pending, Reverting, Succeeded or Failed. |  | Enum: [Pending Reverting Succeeded Failed] <br /> |
| `taskRef` _string_ | TaskRef is the provider task of a revert the provider runs<br />asynchronously, polled until it completes. |  | MaxLength: 512 <br />Optional: \{\} <br /> |
| `attempts` _integer_ | Attempts counts the SnapshotRevert calls sent for this request since<br />the provider last answered that it did not perform one: more than one<br />only when an earlier call's outcome was not known (a lost answer, a<br />deadline) and the call was sent again on the powered-off VM. |  | Minimum: 0 <br />Optional: \{\} <br /> |
| `requestedAt` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | RequestedAt is when the operator first recorded this request. |  | Optional: \{\} <br /> |
| `attemptTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | AttemptTime is when the last SnapshotRevert call was recorded, just<br />before it was sent. |  | Optional: \{\} <br /> |
| `completionTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | CompletionTime is when the revert succeeded or failed. |  | Optional: \{\} <br /> |
| `message` _string_ | Message says what the revert waits for, or how it ended. |  | MaxLength: 1024 <br />Optional: \{\} <br /> |


#### SnapshotSchedule



SnapshotSchedule defines automated snapshot scheduling. Accepted but not
acted on in this release: no controller reads any field of it and no snapshot
is taken on a schedule.



_Appears in:_
- [VMSnapshotSpec](#vmsnapshotspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled indicates if scheduled snapshots are enabled. Accepted but not<br />acted on in this release. | false |  |
| `cronSpec` _string_ | CronSpec defines the schedule in cron format. Accepted but not acted on in<br />this release. |  | Pattern: `^(@(annually\|yearly\|monthly\|weekly\|daily\|hourly\|reboot))\|(@every (\d+(ns\|us\|µs\|ms\|s\|m\|h))+)\|((((\d+,)+\d+\|(\d+(\/\|-)\d+)\|\d+\|\*) ?)\{5,7\})$` <br />Optional: \{\} <br /> |
| `timezone` _string_ | Timezone specifies the timezone for the schedule. Accepted but not acted<br />on in this release. | UTC | Optional: \{\} <br /> |
| `suspend` _boolean_ | Suspend indicates whether to suspend scheduled snapshots. Accepted but not<br />acted on in this release. | false | Optional: \{\} <br /> |
| `concurrencyPolicy` _string_ | ConcurrencyPolicy specifies how to handle concurrent snapshot jobs.<br />Accepted but not acted on in this release. | Forbid | Enum: [Allow Forbid Replace] <br />Optional: \{\} <br /> |
| `successfulJobsHistoryLimit` _integer_ | SuccessfulJobsHistoryLimit limits retained successful jobs. Accepted but<br />not acted on in this release. | 3 | Maximum: 100 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `failedJobsHistoryLimit` _integer_ | FailedJobsHistoryLimit limits retained failed jobs. Accepted but not acted<br />on in this release. | 1 | Maximum: 100 <br />Minimum: 0 <br />Optional: \{\} <br /> |


#### SnapshotType

_Underlying type:_ _string_

SnapshotType represents the type of snapshot. Accepted but not acted on in
this release (see SnapshotConfig.Type).

_Validation:_
- Enum: [Standard Crash Application]

_Appears in:_
- [SnapshotConfig](#snapshotconfig)

| Field | Description |
| --- | --- |
| `Standard` | SnapshotTypeStandard is the default snapshot type<br /> |
| `Crash` | SnapshotTypeCrash names a crash-consistent snapshot<br /> |
| `Application` | SnapshotTypeApplication names an application-consistent snapshot<br /> |


#### StaticIPConfig



StaticIPConfig defines static IP configuration. Accepted but not acted on
in this release.



_Appears in:_
- [IPAllocationConfig](#ipallocationconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `address` _string_ | Address is the static IP address (CIDR notation). Accepted but not acted<br />on in this release. |  | Pattern: `^((25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)\.)\{3\}(25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)/([0-9]\|[1-2][0-9]\|3[0-2])$` <br /> |
| `gateway` _string_ | Gateway is the default gateway. Accepted but not acted on in this release. |  | Pattern: `^((25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)\.)\{3\}(25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)$` <br />Optional: \{\} <br /> |
| `routes` _[StaticRoute](#staticroute) array_ | Routes contains static routes. Accepted but not acted on in this release. |  | MaxItems: 20 <br />Optional: \{\} <br /> |


#### StaticRoute



StaticRoute defines a static route. Accepted but not acted on in this
release.



_Appears in:_
- [StaticIPConfig](#staticipconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `destination` _string_ | Destination is the destination network (CIDR notation). Accepted but not<br />acted on in this release. |  | Pattern: `^((25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)\.)\{3\}(25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)/([0-9]\|[1-2][0-9]\|3[0-2])$` <br /> |
| `gateway` _string_ | Gateway is the route gateway. Accepted but not acted on in this release. |  | Pattern: `^((25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)\.)\{3\}(25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)$` <br /> |
| `metric` _integer_ | Metric is the route metric. Accepted but not acted on in this release. |  | Maximum: 65535 <br />Minimum: 0 <br />Optional: \{\} <br /> |


#### StoragePoolRef



StoragePoolRef names a shared or local storage pool available in a HostPool.
Per-host visibility is asserted via Host.spec.labels. VirtRigaud consumes
pre-set-up storage; it does not deploy it. The list is descriptive in this
release: no controller reads it.



_Appears in:_
- [HostPoolSpec](#hostpoolspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the storage pool name (e.g. a libvirt pool name or an NFS export<br />identifier). A matching Host.spec.labels entry asserts per-host visibility. |  | MaxLength: 253 <br />MinLength: 1 <br /> |


#### StoragePrepareOptions



StoragePrepareOptions defines storage-specific preparation options. Accepted
but not acted on in this release: no controller or provider reads any field
of it.



_Appears in:_
- [ImagePrepare](#imageprepare)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `vsphere` _[VSphereStorageOptions](#vspherestorageoptions)_ | VSphere storage options. Accepted but not acted on in this release. |  | Optional: \{\} <br /> |
| `libvirt` _[LibvirtStorageOptions](#libvirtstorageoptions)_ | Libvirt storage options. Accepted but not acted on in this release. |  | Optional: \{\} <br /> |
| `preferredFormat` _[ImageFormat](#imageformat)_ | PreferredFormat specifies the preferred target format. Accepted but not<br />acted on in this release. |  | Enum: [qcow2 raw vmdk vhd vhdx iso ova ovf] <br />Optional: \{\} <br /> |
| `compression` _boolean_ | Compression enables compression during import. Accepted but not acted on<br />in this release. | false | Optional: \{\} <br /> |


#### SysprepCustomization



SysprepCustomization defines Windows sysprep customization. Accepted but
not acted on in this release.



_Appears in:_
- [VMCustomization](#vmcustomization)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled indicates if sysprep should be run. Accepted but not acted on<br />in this release. | false |  |
| `productKey` _string_ | ProductKey specifies the Windows product key. Accepted but not acted on<br />in this release.<br />WARNING: a value set here is stored in plaintext in the VMClone (etcd,<br />backups, anyone who can read the object). It is accepted but not acted<br />on in this release and is not sent to the provider; do not put a real<br />product key here. |  | Optional: \{\} <br /> |
| `organization` _string_ | Organization specifies the organization name. Accepted but not acted on<br />in this release. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `owner` _string_ | Owner specifies the owner name. Accepted but not acted on in this<br />release. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `adminPassword` _[PasswordSpec](#passwordspec)_ | AdminPassword specifies the administrator password. Accepted but not<br />acted on in this release. |  | Optional: \{\} <br /> |
| `joinDomain` _[DomainJoinSpec](#domainjoinspec)_ | JoinDomain specifies domain join configuration. Accepted but not acted<br />on in this release. |  | Optional: \{\} <br /> |
| `customCommands` _string array_ | CustomCommands specifies custom commands to run during sysprep.<br />Accepted but not acted on in this release, and not sent to the<br />provider. They are stored in plaintext in the VMClone: do not put a<br />credential in them. |  | MaxItems: 20 <br />Optional: \{\} <br /> |


#### TrafficShapingConfig



TrafficShapingConfig defines traffic shaping settings. Accepted but not
acted on in this release.



_Appears in:_
- [VSphereNetworkConfig](#vspherenetworkconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled indicates if traffic shaping is enabled. Accepted but not acted on<br />in this release. | false | Optional: \{\} <br /> |
| `averageBandwidth` _integer_ | AverageBandwidth is the average bandwidth in bits per second. Accepted but<br />not acted on in this release. |  | Minimum: 1000 <br />Optional: \{\} <br /> |
| `peakBandwidth` _integer_ | PeakBandwidth is the peak bandwidth in bits per second. Accepted but not<br />acted on in this release. |  | Minimum: 1000 <br />Optional: \{\} <br /> |
| `burstSize` _integer_ | BurstSize is the burst size in bytes. Accepted but not acted on in this<br />release. |  | Minimum: 1024 <br />Optional: \{\} <br /> |






#### UserData



UserData defines cloud-init configuration



_Appears in:_
- [VMCustomization](#vmcustomization)
- [VirtualMachineSpec](#virtualmachinespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `cloudInit` _[CloudInit](#cloudinit)_ | CloudInit contains cloud-init configuration |  | Optional: \{\} <br /> |
| `ignition` _[Ignition](#ignition)_ | Ignition contains Ignition configuration for CoreOS/RHEL. Accepted but not<br />acted on in this release: only cloudInit is sent to the provider. |  | Optional: \{\} <br /> |


#### VLANConfig



VLANConfig defines VLAN configuration. Accepted but not acted on in this
release.



_Appears in:_
- [VSphereNetworkConfig](#vspherenetworkconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `type` _string_ | Type specifies the VLAN type. Accepted but not acted on in this release. | none | Enum: [none vlan pvlan trunk] <br />Optional: \{\} <br /> |
| `vlanID` _integer_ | VlanID specifies the VLAN ID for VLAN type. Accepted but not acted on in<br />this release. The manager forwards it, but the vSphere provider ignores<br />it. |  | Maximum: 4094 <br />Minimum: 1 <br />Optional: \{\} <br /> |
| `trunkVlanIDs` _integer array_ | TrunkVlanIDs specifies VLAN IDs for trunk type. Accepted but not acted on<br />in this release. |  | MaxItems: 100 <br />Optional: \{\} <br /> |
| `primaryVlanID` _integer_ | PrimaryVlanID specifies the primary VLAN ID for PVLAN. Accepted but not<br />acted on in this release. |  | Maximum: 4094 <br />Minimum: 1 <br />Optional: \{\} <br /> |
| `secondaryVlanID` _integer_ | SecondaryVlanID specifies the secondary VLAN ID for PVLAN. Accepted but<br />not acted on in this release. |  | Maximum: 4094 <br />Minimum: 1 <br />Optional: \{\} <br /> |


#### VMAffinity



VMAffinity defines affinity rules between VMs, evaluated against the other
VMs in the namespace of the VM being placed. A Host counts as matching a
term when a VM on it has labels that satisfy the term.



_Appears in:_
- [AffinityRules](#affinityrules)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `requiredDuringScheduling` _[VMAffinityTerm](#vmaffinityterm) array_ | RequiredDuringScheduling specifies hard affinity rules: a Host is a<br />candidate only if, for every term, it runs a VM that matches the term. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `preferredDuringScheduling` _[WeightedVMAffinityTerm](#weightedvmaffinityterm) array_ | PreferredDuringScheduling specifies soft affinity rules: a Host that runs<br />a VM matching a term ranks higher by that term's weight. |  | MaxItems: 20 <br />Optional: \{\} <br /> |


#### VMAffinityTerm



VMAffinityTerm defines a VM affinity term. A VM matches the term when its
labels satisfy both labelSelector and matchExpressions; a term with neither
matches every VM. The scheduler treats every term as host-level:
topologyKey, namespaces and namespaceSelector are not acted on in this
release.



_Appears in:_
- [VMAffinity](#vmaffinity)
- [VMAntiAffinity](#vmantiaffinity)
- [WeightedVMAffinityTerm](#weightedvmaffinityterm)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `labelSelector` _[LabelSelector](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#labelselector-v1-meta)_ | LabelSelector selects VMs by their labels. |  | Optional: \{\} <br /> |
| `namespaces` _string array_ | Namespaces specifies which namespaces to consider. Accepted but not acted<br />on in this release. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `namespaceSelector` _[LabelSelector](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#labelselector-v1-meta)_ | NamespaceSelector selects namespaces using label selectors. Accepted but<br />not acted on in this release. |  | Optional: \{\} <br /> |
| `topologyKey` _string_ | TopologyKey specifies the topology domain for the rule. It is required but<br />not acted on in this release: every term is evaluated per Host. |  | MaxLength: 253 <br /> |
| `matchExpressions` _[VMSelectorRequirement](#vmselectorrequirement) array_ | MatchExpressions is a list of VM selector requirements on the VM's labels.<br />All of them must hold, together with labelSelector. |  | MaxItems: 20 <br />Optional: \{\} <br /> |


#### VMAntiAffinity



VMAntiAffinity defines anti-affinity rules between VMs, evaluated against
the other VMs in the namespace of the VM being placed. A Host counts as
matching a term when a VM on it has labels that satisfy the term.



_Appears in:_
- [AntiAffinityRules](#antiaffinityrules)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `requiredDuringScheduling` _[VMAffinityTerm](#vmaffinityterm) array_ | RequiredDuringScheduling specifies hard anti-affinity rules: a Host that<br />runs a VM matching any term is not a candidate. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `preferredDuringScheduling` _[WeightedVMAffinityTerm](#weightedvmaffinityterm) array_ | PreferredDuringScheduling specifies soft anti-affinity rules: a Host that<br />runs a VM matching a term ranks lower by that term's weight. |  | MaxItems: 20 <br />Optional: \{\} <br /> |


#### VMClass



VMClass is a reusable hardware profile for VirtualMachines: vCPU count,
memory, firmware and optional disk, performance and security settings. A
VirtualMachine names it in spec.classRef.



_Appears in:_
- [VMClassList](#vmclasslist)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VMClass` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[VMClassSpec](#vmclassspec)_ |  |  |  |
| `status` _[VMClassStatus](#vmclassstatus)_ |  |  |  |




#### VMClassList



VMClassList contains a list of VMClass





| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VMClassList` | | |
| `metadata` _[ListMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#listmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `items` _[VMClass](#vmclass) array_ |  |  |  |


#### VMClassSpec



VMClassSpec defines the desired state of VMClass. A VMClass is a reusable
hardware profile that VirtualMachines name in spec.classRef. cpu and
memory are acted on by the vSphere, libvirt and Proxmox providers (the mock
provider ignores the class); the other fields are acted on only
by the providers named in their descriptions, and some are accepted but
not acted on in this release.



_Appears in:_
- [VMClass](#vmclass)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `cpu` _integer_ | CPU specifies the number of virtual CPUs. A VirtualMachine's<br />spec.resources.cpu overrides it for that VirtualMachine. On a clustered<br />Provider it is also the CPU the VirtualMachine takes from its host. |  | Maximum: 128 <br />Minimum: 1 <br /> |
| `memory` _[Quantity](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#quantity-resource-api)_ | Memory specifies memory allocation using Kubernetes resource<br />quantities. A VirtualMachine's spec.resources.memoryMiB overrides it<br />for that VirtualMachine. It must be non-negative and below 100Ti: every<br />value below 90Ti written in bytes, k/Ki, M/Mi, G/Gi or T/Ti is<br />accepted, and nothing at or above 100Ti is. That is more than three<br />times the largest VM any supported hypervisor runs (24 TB on vSphere<br />8), and keeps the MiB value the provider contract carries far inside<br />its int32 range. The rules bound the number of integer digits per unit<br />suffix with core CEL only (no quantity library, which Kubernetes < 1.29<br />lacks), so they are enforced on every supported Kubernetes version. |  |  |
| `firmware` _[FirmwareType](#firmwaretype)_ | Firmware specifies the firmware type: BIOS (the default) or UEFI. The<br />vSphere and libvirt providers read it: UEFI selects EFI firmware and any<br />other value (EFI included) selects BIOS, except that<br />securityProfile.secureBoot (and, on vSphere, tpmEnabled) force EFI<br />firmware. On libvirt, UEFI is OVMF without Secure Boot on the q35<br />machine type, chosen by libvirt from the host's installed firmware<br />(docs/libvirt-firmware.md). Proxmox and mock ignore this field. | BIOS | Enum: [BIOS UEFI EFI] <br />Optional: \{\} <br /> |
| `diskDefaults` _[DiskDefaults](#diskdefaults)_ | DiskDefaults provides default disk settings. Only size is acted on:<br />libvirt sizes the root disk to it (20GiB when diskDefaults is unset; a<br />disk grown from an image is never shrunk, and libvirt also grows the root<br />disk to it on a later reconfigure) and vSphere grows the root disk to it<br />after creation (it never shrinks a disk). type, iops and storageClass are<br />accepted but not acted on in this release. Proxmox and mock ignore the block. |  | Optional: \{\} <br /> |
| `guestToolsPolicy` _[GuestToolsPolicy](#guesttoolspolicy)_ | GuestToolsPolicy specifies guest tools installation policy. Accepted<br />but not acted on in this release. The value is sent to the provider,<br />but no provider acts on it. | install | Enum: [install skip upgrade uninstall] <br />Optional: \{\} <br /> |
| `extraConfig` _object (keys:string, values:string)_ | ExtraConfig contains provider-specific extra configuration. Only the<br />vSphere provider reads it, and only the key vsphere.hardwareVersion<br />(the VM hardware version, for example 21). Any other key, and every key<br />on libvirt, Proxmox and mock, is accepted but not acted on in this<br />release. |  | MaxProperties: 50 <br />Optional: \{\} <br /> |
| `resourceLimits` _[VMResourceLimits](#vmresourcelimits)_ | ResourceLimits defines resource limits and reservations. Accepted but<br />not acted on in this release. The values are sent to the provider, but<br />no provider applies them. |  | Optional: \{\} <br /> |
| `performanceProfile` _[PerformanceProfile](#performanceprofile)_ | PerformanceProfile defines performance-related settings.<br />nestedVirtualization, cpuHotAddEnabled and memoryHotAddEnabled are<br />acted on by vSphere and libvirt, and virtualizationBasedSecurity by<br />vSphere only; latencySensitivity and hyperThreadingPolicy are accepted<br />but not acted on in this release. Proxmox and mock ignore the block. |  | Optional: \{\} <br /> |
| `securityProfile` _[SecurityProfile](#securityprofile)_ | SecurityProfile defines security-related settings. secureBoot,<br />tpmEnabled and vtdEnabled are acted on by vSphere and libvirt;<br />tpmVersion and encryptionPolicy are accepted but not acted on in this<br />release. Proxmox and mock ignore the block. |  | Optional: \{\} <br /> |
| `consumerNamespaceSelector` _[LabelSelector](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#labelselector-v1-meta)_ | ConsumerNamespaceSelector selects the namespaces, other than this<br />VMClass's own, that may use it: VirtualMachines there may name it in<br />spec.classRef. A reference from the VMClass's own namespace is always<br />allowed.<br />  - unset (the default): only its own namespace may use it.<br />  - \{\} (an empty selector): every namespace may use it.<br />  - matchLabels / matchExpressions: the namespaces whose labels match. The<br />    kubernetes.io/metadata.name label names a namespace explicitly.<br />A reference from a namespace it does not select is refused with<br />Ready=False, reason ConsumerNotAllowed, and no provider call is made for<br />it. The selector is matched against Namespace labels, so whoever can label<br />a namespace can widen what that namespace may use (see<br />docs/cross-namespace-references.md). The selector is operator-side policy:<br />it is never sent to a provider. |  | Optional: \{\} <br /> |


#### VMClassStatus



VMClassStatus defines the observed state of VMClass. Not populated in
this release. No controller writes the status of a VMClass.



_Appears in:_
- [VMClass](#vmclass)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `conditions` _[Condition](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#condition-v1-meta) array_ | Conditions represent the latest available observations. Not populated<br />in this release. |  | Optional: \{\} <br /> |
| `observedGeneration` _integer_ | ObservedGeneration reflects the generation observed by the controller.<br />Not populated in this release. |  | Optional: \{\} <br /> |
| `usedByVMs` _integer_ | UsedByVMs is the number of VMs currently using this class. Not<br />populated in this release. |  | Optional: \{\} <br /> |
| `supportedProviders` _string array_ | SupportedProviders lists the providers that support this class. Not<br />populated in this release. |  | Optional: \{\} <br /> |
| `validationResults` _object (keys:string, values:[ValidationResult](#validationresult))_ | ValidationResults contains validation results for different providers.<br />Not populated in this release. |  | Optional: \{\} <br /> |


#### VMClone



VMClone is the Schema for the vmclones API. It clones an existing
VirtualMachine (spec.source.vmRef) into a new VirtualMachine on the same
Provider, and binds the new VirtualMachine to the cloned machine.
Deleting a VMClone does not delete the VirtualMachine it produced.



_Appears in:_
- [VMCloneList](#vmclonelist)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VMClone` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[VMCloneSpec](#vmclonespec)_ |  |  |  |
| `status` _[VMCloneStatus](#vmclonestatus)_ |  |  |  |




#### VMCloneList



VMCloneList contains a list of VMClone





| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VMCloneList` | | |
| `metadata` _[ListMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#listmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `items` _[VMClone](#vmclone) array_ |  |  |  |


#### VMCloneSpec



VMCloneSpec defines the desired state of VMClone. Fields that are
accepted by the schema but not acted on in this release are marked as
such.



_Appears in:_
- [VMClone](#vmclone)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `source` _[CloneSource](#clonesource)_ | Source defines the VirtualMachine to clone. Only vmRef is supported. |  |  |
| `target` _[VMCloneTarget](#vmclonetarget)_ | Target defines the VirtualMachine the clone produces. The controller<br />creates it before it asks the Provider to clone, and binds it to the<br />cloned machine once the clone is made. |  |  |
| `options` _[CloneOptions](#cloneoptions)_ | Options defines cloning options. Only type and powerOn are acted on;<br />every other option is accepted but not acted on in this release. |  | Optional: \{\} <br /> |
| `customization` _[VMCustomization](#vmcustomization)_ | Customization defines how the cloned machine is customized. Only<br />hostname, domain and userData.cloudInit.inline are acted on, and only<br />by some providers and only for a source VM that carries cloud-init data<br />(a NoCloud seed on libvirt, cloud-init guestinfo keys on vSphere); see<br />the field descriptions. Every other field of the block is accepted but<br />not acted on in this release. The fields among them that hold, or<br />commonly hold, secret values (sysprep.productKey,<br />sysprep.adminPassword.value, sysprep.joinDomain.password.value,<br />sysprep.customCommands, certificates[].data, guestCommands[].command<br />and .arguments, userData.ignition.inline) are never sent to the<br />provider, but are stored in plaintext in the VMClone: do not put real<br />credentials there. |  | Optional: \{\} <br /> |
| `metadata` _[CloneMetadata](#clonemetadata)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  | Optional: \{\} <br /> |


#### VMCloneStatus



VMCloneStatus defines the observed state of VMClone. Fields that the
controller does not write are marked as not populated.



_Appears in:_
- [VMClone](#vmclone)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `targetRef` _[LocalObjectReference](#localobjectreference)_ | TargetRef references the target VirtualMachine. It is set when the<br />clone is Ready. |  | Optional: \{\} <br /> |
| `targetVMID` _string_ | TargetVMID is the provider's identifier of the cloned machine, as<br />returned by the Clone call. The controller records it before it binds<br />the target VirtualMachine, so an interrupted clone resumes the binding<br />instead of cloning again, and writes it to the target VirtualMachine's<br />status.id. |  | Optional: \{\} <br /> |
| `targetUID` _string_ | TargetUID is the uid of the target VirtualMachine this clone created<br />before it asked the Provider to clone. Only that object is ever used as<br />the clone's target or removed when the clone fails: a VirtualMachine<br />re-created later under the target name, even one carrying a copied<br />virtrigaud.io/clone-uid annotation, is never touched. |  | MaxLength: 128 <br />Optional: \{\} <br /> |
| `phase` _[ClonePhase](#clonephase)_ | Phase represents the current phase of the clone operation: Pending<br />(waiting for a prerequisite; the Ready condition says which), Cloning,<br />Ready or Failed. Failed is terminal: the clone is not retried, so<br />create a new VMClone to try again. Preparing, Customizing and<br />Powering-On are accepted by the schema but never set in this release. |  | Enum: [Pending Preparing Cloning Customizing Powering-On Ready Failed] <br />Optional: \{\} <br /> |
| `message` _string_ | Message provides additional details about the current phase. |  | Optional: \{\} <br /> |
| `taskRef` _string_ | TaskRef is the provider's task reference for an asynchronous Clone call<br />that has not finished. It is empty otherwise, and providers that clone<br />synchronously never set it. |  | Optional: \{\} <br /> |
| `startTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | StartTime is when the Clone call, which the provider then accepted, was<br />sent. |  | Optional: \{\} <br /> |
| `completionTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | CompletionTime is when the clone became Ready. It is not set when the<br />clone fails. |  | Optional: \{\} <br /> |
| `actualCloneType` _[CloneType](#clonetype)_ | ActualCloneType indicates the clone type that was made, FullClone or<br />LinkedClone. It is set when the provider accepts the Clone call; a<br />requested InstantClone is reported as FullClone. |  | Enum: [FullClone LinkedClone InstantClone] <br />Optional: \{\} <br /> |
| `progress` _[CloneProgress](#cloneprogress)_ | Progress shows the clone operation progress. Not populated in this<br />release. (The Progress printer column is therefore empty.) |  | Optional: \{\} <br /> |
| `conditions` _[Condition](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#condition-v1-meta) array_ | Conditions represent the latest observations of the clone. The<br />controller sets Ready, Cloning and Failed, TargetCleanup (what was done<br />with the target VirtualMachine of a failed clone) and CloneRequested (a<br />Clone call was sent and its outcome is not recorded yet). Customizing<br />is never set. |  | Optional: \{\} <br /> |
| `observedGeneration` _integer_ | ObservedGeneration is the generation of the VMClone last processed by<br />the controller. |  | Optional: \{\} <br /> |
| `retryCount` _integer_ | RetryCount is the number of times the clone has been retried. Not<br />populated in this release. |  | Optional: \{\} <br /> |
| `lastRetryTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LastRetryTime is when the clone was last retried. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `customizationStatus` _[CustomizationStatus](#customizationstatus)_ | CustomizationStatus contains customization operation status. Not<br />populated in this release. |  | Optional: \{\} <br /> |


#### VMCloneTarget



VMCloneTarget defines the VirtualMachine a clone produces.



_Appears in:_
- [VMCloneSpec](#vmclonespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the name of the target VirtualMachine. |  | MaxLength: 253 <br />Pattern: `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$` <br /> |
| `namespace` _string_ | Namespace is the namespace for the target VM (defaults to the VMClone's<br />namespace, which is also the source VM's). A different namespace is<br />allowed only when that Namespace object carries the annotation<br />infra.virtrigaud.io/allowed-source-namespaces and its comma-separated<br />value lists the VMClone's namespace (exact names, no wildcards).<br />Whoever can update the target Namespace can grant this (normally a<br />cluster administrator, since Namespaces are cluster-scoped). Without it<br />the clone is refused (Ready=False, reason TargetNamespaceNotAllowed) and<br />nothing is created in, read from or bound in the target namespace;<br />granting the annotation or changing this field resumes it. |  | MaxLength: 63 <br />Pattern: `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$` <br />Optional: \{\} <br /> |
| `providerRef` _[ObjectRef](#objectref)_ | ProviderRef references the target provider. Accepted but not acted on<br />in this release. The target VirtualMachine always uses the source<br />VirtualMachine's Provider: a clone is made on the Provider its source<br />runs on. |  | Optional: \{\} <br /> |
| `classRef` _[LocalObjectReference](#localobjectreference)_ | ClassRef names the VMClass of the target VirtualMachine, in the<br />VMClone's namespace. When unset, the target uses the source<br />VirtualMachine's class. The class's CPU and memory are also sent with<br />the Clone call: libvirt applies them, Proxmox applies only the CPU<br />count, and vSphere ignores them at clone time. |  | Optional: \{\} <br /> |
| `placementRef` _[LocalObjectReference](#localobjectreference)_ | PlacementRef is copied to the target VirtualMachine's<br />spec.placementRef. It does not place the clone: the clone is made on<br />the source VirtualMachine's Provider (on a clustered Provider, on the<br />source's host), and no provider acts on it at clone time. |  | Optional: \{\} <br /> |
| `networks` _[VMNetworkRef](#vmnetworkref) array_ | Networks is copied to the target VirtualMachine's spec.networks. It is<br />not applied to the cloned machine at clone time: no provider changes<br />the network devices the clone inherits from its source. |  | MaxItems: 10 <br />Optional: \{\} <br /> |
| `disks` _[DiskSpec](#diskspec) array_ | Disks defines disk configuration overrides. Accepted but not acted on<br />in this release. The cloned machine keeps the source's disks. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `labels` _object (keys:string, values:string)_ | Labels defines labels to apply to the target VirtualMachine. The<br />controller always sets virtrigaud.io/adopted=true on it, replacing any<br />value given here. |  | MaxProperties: 50 <br />Optional: \{\} <br /> |
| `annotations` _object (keys:string, values:string)_ | Annotations defines annotations to apply to the target VM. Keys in the<br />operator's reserved virtrigaud.io domain (virtrigaud.io/... and<br />*.virtrigaud.io/...), such as virtrigaud.io/orphan-on-delete or the<br />provenance annotations, are not copied; the controller sets its own<br />provenance annotations. |  | MaxProperties: 50 <br />Optional: \{\} <br /> |


#### VMCustomization



VMCustomization defines how the cloned machine is customized. Only
hostname, domain and userData.cloudInit.inline are acted on. Every other
field is accepted but not acted on in this release; the libvirt and
vSphere providers log the customization fields they do not apply. The
manager sends the provider only the fields a provider reads or reports:
the secret values (sysprep.productKey, sysprep.adminPassword.value,
sysprep.joinDomain.password.value, certificates[].data), the commands
(sysprep.customCommands, guestCommands[].command and .arguments) and
userData.ignition.inline are never sent.



_Appears in:_
- [VMCloneSpec](#vmclonespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `hostname` _string_ | Hostname sets the hostname of the cloned machine, through the clone's<br />cloud-init identity. It is applied by libvirt (when the source boots<br />from a NoCloud seed) and vSphere (when the source carries cloud-init<br />guestinfo metadata, or a hostname in its guestinfo user-data); Proxmox and<br />mock do not apply it. When unset, the<br />hostname is the target VirtualMachine's name. |  | MaxLength: 255 <br />Pattern: `^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?$` <br />Optional: \{\} <br /> |
| `domain` _string_ | Domain sets the domain name; with the hostname it forms the clone's<br />FQDN. It is applied by libvirt and vSphere on the same terms as<br />hostname; Proxmox and mock do not apply it. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `timeZone` _string_ | TimeZone sets the timezone. Accepted but not acted on in this release. |  | MaxLength: 100 <br />Optional: \{\} <br /> |
| `networks` _[NetworkCustomization](#networkcustomization) array_ | Networks defines network customization. Accepted but not acted on in<br />this release. |  | MaxItems: 10 <br />Optional: \{\} <br /> |
| `userData` _[UserData](#userdata)_ | UserData provides cloud-init user-data for the clone. Only<br />cloudInit.inline is applied, and only by libvirt: it replaces the<br />source's user-data in the clone's cloud-init seed (the source must have<br />one). cloudInit.secretRef is not resolved, so the clone keeps the<br />source's user-data, and ignition is not applied. vSphere, Proxmox and<br />mock do not apply user-data. |  | Optional: \{\} <br /> |
| `sysprep` _[SysprepCustomization](#sysprepcustomization)_ | Sysprep provides Windows sysprep customization. Accepted but not acted<br />on in this release. |  | Optional: \{\} <br /> |
| `tags` _string array_ | Tags defines additional tags for the cloned VM. Accepted but not acted<br />on in this release. |  | MaxItems: 50 <br />Optional: \{\} <br /> |
| `guestCommands` _[GuestCommand](#guestcommand) array_ | GuestCommands defines commands to run in the guest OS. Accepted but not<br />acted on in this release. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `certificates` _[CertificateSpec](#certificatespec) array_ | Certificates defines certificates to install. Accepted but not acted on<br />in this release. |  | MaxItems: 10 <br />Optional: \{\} <br /> |


#### VMImage



VMImage describes where a VM image comes from and records where it has been
prepared. VirtualMachines use it through spec.imageRef. An image that must be
imported (a vSphere ovaURL, a libvirt url) is prepared on a Provider when the
first VM that uses it on that Provider is created; an image that names
something already on the hypervisor (a template, a libvirt path) is used as
written.



_Appears in:_
- [VMImageList](#vmimagelist)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VMImage` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[VMImageSpec](#vmimagespec)_ |  |  |  |
| `status` _[VMImageStatus](#vmimagestatus)_ |  |  |  |


#### VMImageList



VMImageList contains a list of VMImage





| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VMImageList` | | |
| `metadata` _[ListMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#listmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `items` _[VMImage](#vmimage) array_ |  |  |  |


#### VMImageSpec



VMImageSpec defines the desired state of VMImage. Source says where the image
comes from; prepare.onMissing and prepare.timeout steer how it is prepared on a
Provider. metadata and distribution are descriptive. Several other fields are
accepted but not acted on in this release; each says so.



_Appears in:_
- [VMImage](#vmimage)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `source` _[ImageSource](#imagesource)_ | Source defines where the image comes from. Set the block for one kind of<br />source: vsphere, libvirt and proxmox are acted on; http, registry and<br />dataVolume are accepted but not acted on in this release. Nothing checks<br />that only one block is set. |  |  |
| `prepare` _[ImagePrepare](#imageprepare)_ | Prepare contains optional image preparation steps. Only onMissing and<br />timeout are acted on; the other fields are accepted but not acted on in<br />this release. Preparation applies only to sources that must be imported (a<br />vSphere ovaURL, a libvirt url); an image that names something already on<br />the hypervisor (a template, a libvirt path) is never prepared. |  | Optional: \{\} <br /> |
| `metadata` _[ImageMetadata](#imagemetadata)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  | Optional: \{\} <br /> |
| `distribution` _[OSDistribution](#osdistribution)_ | Distribution contains OS distribution information. Descriptive: no<br />controller or provider reads it. |  | Optional: \{\} <br /> |
| `consumerNamespaceSelector` _[LabelSelector](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#labelselector-v1-meta)_ | ConsumerNamespaceSelector selects the namespaces, other than this<br />VMImage's own, that may use it: VirtualMachines there may name it in<br />spec.imageRef (which prepares it on, and creates VMs from it through,<br />their Provider). A reference from the VMImage's own namespace is always<br />allowed.<br />  - unset (the default): only its own namespace may use it.<br />  - \{\} (an empty selector): every namespace may use it.<br />  - matchLabels / matchExpressions: the namespaces whose labels match. The<br />    kubernetes.io/metadata.name label names a namespace explicitly.<br />A reference from a namespace it does not select is refused with<br />Ready=False, reason ConsumerNotAllowed, and no provider call is made for<br />it. The selector is matched against Namespace labels, so whoever can label<br />a namespace can widen what that namespace may use (see<br />docs/cross-namespace-references.md). The selector is operator-side policy:<br />it is never sent to a provider. |  | Optional: \{\} <br /> |


#### VMImageStatus



VMImageStatus defines the observed state of VMImage. It is written only by the
operator's VirtualMachine controller, when it prepares the image for a VM, so
an image that needs no preparation (it names a template or a libvirt path
already on the hypervisor) has no status. size, checksum, format and
importProgress are not populated in this release.



_Appears in:_
- [VMImage](#vmimage)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `ready` _boolean_ | Ready is true once the image is prepared on at least one Provider (see<br />providerStatus for the state on each). It can turn false again while a<br />VirtualMachine on another Provider is held by prepare.onMissing Fail or<br />Wait. |  | Optional: \{\} <br /> |
| `phase` _[ImagePhase](#imagephase)_ | Phase represents the current phase of image preparation: Pending,<br />Importing, Ready or Failed. Downloading, Converting and Optimizing are<br />never set in this release. |  | Enum: [Pending Downloading Importing Converting Optimizing Ready Failed] <br />Optional: \{\} <br /> |
| `message` _string_ | Message provides additional details about the current state, for example<br />why a prepare is held or failed. |  | Optional: \{\} <br /> |
| `availableOn` _string array_ | AvailableOn lists the Providers the image is available on, each as<br />"<namespace>/<name>" (the ProviderStatus keys whose entry is available).<br />It is informational: creating a VM consults ProviderStatus only. |  | Optional: \{\} <br /> |
| `conditions` _[Condition](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#condition-v1-meta) array_ | Conditions represent the latest available observations. The Ready and<br />Importing conditions are set; Downloading and Validated are never set in<br />this release. |  | Optional: \{\} <br /> |
| `observedGeneration` _integer_ | ObservedGeneration is not populated in this release; each condition<br />carries its own observedGeneration. |  | Optional: \{\} <br /> |
| `lastPrepareTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LastPrepareTime records when a prepare was last started (an asynchronous<br />prepare in flight) or completed. |  | Optional: \{\} <br /> |
| `prepareTaskRef` _string_ | PrepareTaskRef is deprecated and no longer written. An in-flight<br />prepare task is recorded per Provider, in<br />ProviderStatus["<namespace>/<name>"].taskRef, and polled only through<br />that Provider. A value left by an earlier release cannot be attributed<br />to a Provider: the controller clears it without polling it and issues<br />the prepare again (it is idempotent on every provider). |  | Optional: \{\} <br /> |
| `importProgress` _[ImageImportProgress](#imageimportprogress)_ | ImportProgress shows the progress of image import operations. Not<br />populated in this release. |  | Optional: \{\} <br /> |
| `size` _[Quantity](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#quantity-resource-api)_ | Size is the size of the prepared image. Not populated in this release, so<br />the Size column of kubectl get is empty. |  | Optional: \{\} <br /> |
| `checksum` _string_ | Checksum is the actual checksum of the prepared image. Not populated in<br />this release. |  | Optional: \{\} <br /> |
| `format` _[ImageFormat](#imageformat)_ | Format is the actual format of the prepared image. Not populated in this<br />release. |  | Enum: [qcow2 raw vmdk vhd vhdx iso ova ovf] <br />Optional: \{\} <br /> |
| `providerStatus` _object (keys:string, values:[ProviderImageStatus](#providerimagestatus))_ | ProviderStatus is the per-Provider prepare state, keyed by the<br />Provider's identity "<namespace>/<name>" (for example "team-a/vsphere"),<br />so two Providers with the same name in different namespaces never share<br />an entry. A VirtualMachine consults only the entry of the Provider it<br />uses, and trusts it only when the entry's providerUID is that Provider's<br />current UID.<br />Entries written by an earlier release are keyed by the bare Provider<br />name. On the first prepare reconcile such an entry is re-keyed to<br />"<this VMImage's namespace>/<name>" when that Provider exists, and is<br />dropped otherwise. A re-keyed entry has no providerUID, so it is<br />re-validated through its Provider before a VM is created from it. |  | Optional: \{\} <br /> |


#### VMMigration



VMMigration is the Schema for the vmmigrations API



_Appears in:_
- [VMMigrationList](#vmmigrationlist)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VMMigration` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[VMMigrationSpec](#vmmigrationspec)_ |  |  |  |
| `status` _[VMMigrationStatus](#vmmigrationstatus)_ |  |  |  |


#### VMMigrationList



VMMigrationList contains a list of VMMigration





| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VMMigrationList` | | |
| `metadata` _[ListMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#listmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `items` _[VMMigration](#vmmigration) array_ |  |  |  |


#### VMMigrationSpec



VMMigrationSpec defines the desired state of VMMigration



_Appears in:_
- [VMMigration](#vmmigration)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `source` _[MigrationSource](#migrationsource)_ | Source defines the source VM to migrate from |  |  |
| `target` _[MigrationTarget](#migrationtarget)_ | Target defines the target provider and configuration |  |  |
| `options` _[MigrationOptions](#migrationoptions)_ | Options defines migration options |  | Optional: \{\} <br /> |
| `storage` _[MigrationStorage](#migrationstorage)_ | Storage defines storage backend configuration for transfer |  | Optional: \{\} <br /> |
| `metadata` _[MigrationMetadata](#migrationmetadata)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  | Optional: \{\} <br /> |


#### VMMigrationStatus



VMMigrationStatus defines the observed state of VMMigration



_Appears in:_
- [VMMigration](#vmmigration)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `phase` _[MigrationPhase](#migrationphase)_ | Phase represents the current phase of the migration. A migration goes<br />Pending, Validating, Snapshotting (when createSnapshot is true), Exporting,<br />Importing, Creating, Validating-Target and Ready, or Failed. The<br />Transferring and Converting phases exist in the enum but a migration does<br />not enter them in this release: the disk is moved during Exporting and<br />Importing, and the target provider converts the format on import. |  | Enum: [Pending Validating Snapshotting Exporting Transferring Converting Importing Creating Validating-Target Ready Failed] <br />Optional: \{\} <br /> |
| `message` _string_ | Message provides additional details about the current state |  | Optional: \{\} <br /> |
| `targetVMRef` _[LocalObjectReference](#localobjectreference)_ | TargetVMRef references the created target VM. Not populated in this<br />release; see targetVMUID and spec.target.name. |  | Optional: \{\} <br /> |
| `snapshotRef` _string_ | SnapshotRef references the source snapshot used for migration |  | Optional: \{\} <br /> |
| `snapshotID` _string_ | SnapshotID is the provider-specific snapshot identifier |  | Optional: \{\} <br /> |
| `sourceVMUID` _string_ | SourceVMUID is the UID of the source VirtualMachine the migration<br />validated and exported, recorded at Validating. With<br />spec.source.deleteAfterMigration the controller deletes only that<br />object (a UID precondition): a source VirtualMachine re-created under the<br />same name is never deleted. Written by the controller only. |  | MaxLength: 128 <br />Optional: \{\} <br /> |
| `exportID` _string_ | ExportID is the export operation identifier the source provider returned. |  | Optional: \{\} <br /> |
| `importID` _string_ | ImportID is the disk identifier the target provider returned for the<br />imported disk. |  | Optional: \{\} <br /> |
| `taskRef` _string_ | TaskRef is the current task reference for async operations |  | Optional: \{\} <br /> |
| `targetVMID` _string_ | TargetVMID is the provider-specific target VM identifier |  | Optional: \{\} <br /> |
| `targetVMUID` _string_ | TargetVMUID is the UID of the target VirtualMachine this migration<br />created, recorded from the response of its own Create (or, when that<br />record was lost, from the VirtualMachine that carries this migration's<br />claim, see targetVMClaim). Every later step — waiting for the target,<br />validating it, marking it migration-completed, deleting a partial one —<br />acts only on the VirtualMachine with this UID: another VirtualMachine<br />under the target's name (one created by someone else, before or after<br />the migration's own) fails the migration and is never touched. Written<br />by the controller only. |  | MaxLength: 128 <br />Optional: \{\} <br /> |
| `targetVMClaim` _string_ | TargetVMClaim is the hex SHA-256 digest of the one-time random token<br />the controller writes, as the virtrigaud.io/migration-claim annotation,<br />on the target VirtualMachine it creates. It is recorded BEFORE that<br />Create, so a Create that succeeded but whose targetVMUID was never<br />recorded (a lost status write, a manager restart) is still recognized<br />as this migration's: a VirtualMachine whose claim token hashes to this<br />digest. Only the digest is stored here; the token cannot be derived<br />from it. Written by the controller only. |  | MaxLength: 64 <br />Optional: \{\} <br /> |
| `startTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | StartTime is when the migration started |  | Optional: \{\} <br /> |
| `completionTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | CompletionTime is when the migration completed |  | Optional: \{\} <br /> |
| `progress` _[MigrationProgress](#migrationprogress)_ | Progress shows the migration operation progress. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `diskInfo` _[MigrationDiskInfo](#migrationdiskinfo)_ | DiskInfo contains information about the migrated disk, recorded when the<br />ExportDisk and ImportDisk calls return (which can be before an<br />asynchronous task finishes). |  | Optional: \{\} <br /> |
| `storageInfo` _[MigrationStorageInfo](#migrationstorageinfo)_ | StorageInfo contains information about intermediate storage. The controller<br />records cleanedUp, stagingLayout, stagingDigest and importTarget; url, size<br />and uploadedAt are not populated in this release. |  | Optional: \{\} <br /> |
| `storagePVCName` _string_ | StoragePVCName is the name of the PVC used for migration storage |  | Optional: \{\} <br /> |
| `storagePVCUID` _string_ | StoragePVCUID is the UID of the migration PVC this migration created<br />(pvc backend, no spec.storage.pvc.name), taken from the API server's<br />answer to its create. Only the PVC with this UID is mounted into the<br />provider pods and deleted with the migration: a PVC of the same name<br />that anyone else created — even one carrying an ownerReference to this<br />migration — is refused. Empty for a PVC named in spec.storage.pvc.name.<br />Written by the controller only. |  | MaxLength: 128 <br />Optional: \{\} <br /> |
| `conditions` _[Condition](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#condition-v1-meta) array_ | Conditions represent the current service state |  | Optional: \{\} <br /> |
| `observedGeneration` _integer_ | ObservedGeneration reflects the generation observed by the controller |  | Optional: \{\} <br /> |
| `retryCount` _integer_ | RetryCount is the number of times the migration has been retried |  | Optional: \{\} <br /> |
| `lastRetryTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LastRetryTime is when the migration was last retried |  | Optional: \{\} <br /> |
| `validationResults` _[ValidationResults](#validationresults)_ | ValidationResults contains results of validation checks. Not populated in<br />this release. |  | Optional: \{\} <br /> |


#### VMNetworkAttachment



VMNetworkAttachment describes a network that VirtualMachines attach to
through spec.networks[].networkRef. The manager reads spec.network when it
creates a VM; no controller acts on the rest of the resource, and its
status is not populated, so the Ready, Connected VMs and Providers columns
are empty.



_Appears in:_
- [VMNetworkAttachmentList](#vmnetworkattachmentlist)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VMNetworkAttachment` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[VMNetworkAttachmentSpec](#vmnetworkattachmentspec)_ |  |  |  |
| `status` _[VMNetworkAttachmentStatus](#vmnetworkattachmentstatus)_ |  |  |  |


#### VMNetworkAttachmentList



VMNetworkAttachmentList contains a list of VMNetworkAttachment





| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VMNetworkAttachmentList` | | |
| `metadata` _[ListMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#listmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `items` _[VMNetworkAttachment](#vmnetworkattachment) array_ |  |  |  |


#### VMNetworkAttachmentSpec



VMNetworkAttachmentSpec defines the desired state of VMNetworkAttachment. A
VirtualMachine uses an attachment through spec.networks[].networkRef, in
its own namespace. Only the spec.network block that matches the type of the
VM's Provider is read; ipAllocation, security, qos and metadata are
accepted but not acted on in this release.



_Appears in:_
- [VMNetworkAttachment](#vmnetworkattachment)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `network` _[NetworkConfig](#networkconfig)_ | Network holds the per-hypervisor network settings. Only the block that<br />matches the type of the VM's Provider (vsphere, libvirt or proxmox) is<br />read; the other blocks are ignored. |  |  |
| `ipAllocation` _[IPAllocationConfig](#ipallocationconfig)_ | IPAllocation defines how IP addresses are assigned. Accepted but not acted<br />on in this release. This applies to every field below it. Set a static IP,<br />prefix, gateway and DNS servers on the entry of the VirtualMachine's<br />spec.networks instead. |  | Optional: \{\} <br /> |
| `security` _[NetworkSecurityConfig](#networksecurityconfig)_ | Security defines network security settings. Accepted but not acted on in<br />this release. This applies to every field below it. |  | Optional: \{\} <br /> |
| `qos` _[NetworkQoSConfig](#networkqosconfig)_ | QoS defines Quality of Service settings. Accepted but not acted on in this<br />release. This applies to every field below it. |  | Optional: \{\} <br /> |
| `metadata` _[NetworkMetadata](#networkmetadata)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  | Optional: \{\} <br /> |


#### VMNetworkAttachmentStatus



VMNetworkAttachmentStatus defines the observed state of
VMNetworkAttachment. Not populated in this release: the controller for this
resource only watches it and writes no status.



_Appears in:_
- [VMNetworkAttachment](#vmnetworkattachment)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `ready` _boolean_ | Ready indicates if the network is ready for use. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `phase` _[NetworkAttachmentPhase](#networkattachmentphase)_ | Phase represents the current phase. Not populated in this release. |  | Enum: [Pending Configuring Ready Failed] <br />Optional: \{\} <br /> |
| `message` _string_ | Message provides additional details about the current state. Not populated<br />in this release. |  | Optional: \{\} <br /> |
| `availableOn` _string array_ | AvailableOn lists the providers where the network is available. Not<br />populated in this release. |  | Optional: \{\} <br /> |
| `conditions` _[Condition](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#condition-v1-meta) array_ | Conditions represent the latest available observations. Not populated in<br />this release. |  | Optional: \{\} <br /> |
| `observedGeneration` _integer_ | ObservedGeneration reflects the generation observed by the controller. Not<br />populated in this release. |  | Optional: \{\} <br /> |
| `connectedVMs` _integer_ | ConnectedVMs is the number of VMs using this network. Not populated in<br />this release. |  | Optional: \{\} <br /> |
| `ipAllocations` _[IPAllocation](#ipallocation) array_ | IPAllocations contains current IP allocations. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `providerStatus` _object (keys:string, values:[ProviderNetworkStatus](#providernetworkstatus))_ | ProviderStatus contains provider-specific status information. Not<br />populated in this release. |  | Optional: \{\} <br /> |


#### VMNetworkRef



VMNetworkRef represents a reference to a network attachment



_Appears in:_
- [MigrationTarget](#migrationtarget)
- [VMCloneTarget](#vmclonetarget)
- [VirtualMachineSpec](#virtualmachinespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the name of this network attachment |  | MaxLength: 63 <br />Pattern: `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$` <br /> |
| `networkRef` _[ObjectRef](#objectref)_ | NetworkRef references the VMNetworkAttachment (optional)<br />When not specified, the template's pre-configured network adapter is used. |  | Optional: \{\} <br /> |
| `ipAddress` _string_ | IPAddress specifies a static IP address (optional) |  | Pattern: `^((25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)\.)\{3\}(25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)$` <br />Optional: \{\} <br /> |
| `prefix` _integer_ | Prefix specifies the network prefix length (e.g., 24 for /24) |  | Maximum: 32 <br />Minimum: 1 <br />Optional: \{\} <br /> |
| `gateway` _string_ | Gateway specifies the default gateway IP address |  | Pattern: `^((25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)\.)\{3\}(25[0-5]\|2[0-4][0-9]\|[01]?[0-9][0-9]?)$` <br />Optional: \{\} <br /> |
| `dns` _string_ | DNS specifies DNS server IP addresses (comma-separated) |  | Optional: \{\} <br /> |
| `macAddress` _string_ | MACAddress specifies a static MAC address (optional). Accepted but not acted<br />on in this release: it is not sent to the provider. |  | Pattern: `^([0-9A-Fa-f]\{2\}[:-])\{5\}([0-9A-Fa-f]\{2\})$` <br />Optional: \{\} <br /> |


#### VMPlacementPolicy



VMPlacementPolicy holds rules for choosing the Host of a VirtualMachine. A
VirtualMachine references it with spec.placementRef, in its own namespace.
Only the scheduler of a clustered Provider (spec.topology: cluster) reads
it, when it places a VM on a Host; there, a VM whose placementRef names a
policy that does not exist is not scheduled. On any other Provider the
reference is not read. Within the policy, hard, soft, affinity,
antiAffinity and resourceConstraints are acted on as described on each
field; securityConstraints, priority and weight are accepted but not acted
on in this release. Status is not populated in this release, so the Used By
VMs, Successful and Failed columns are empty.



_Appears in:_
- [VMPlacementPolicyList](#vmplacementpolicylist)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VMPlacementPolicy` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[VMPlacementPolicySpec](#vmplacementpolicyspec)_ |  |  |  |
| `status` _[VMPlacementPolicyStatus](#vmplacementpolicystatus)_ |  |  |  |


#### VMPlacementPolicyList



VMPlacementPolicyList contains a list of VMPlacementPolicy





| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VMPlacementPolicyList` | | |
| `metadata` _[ListMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#listmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `items` _[VMPlacementPolicy](#vmplacementpolicy) array_ |  |  |  |


#### VMPlacementPolicySpec



VMPlacementPolicySpec defines the desired state of VMPlacementPolicy. Only
the scheduler of a clustered Provider reads it (see VMPlacementPolicy).
securityConstraints, priority and weight are accepted but not acted on in
this release.



_Appears in:_
- [VMPlacementPolicy](#vmplacementpolicy)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `hard` _[PlacementConstraints](#placementconstraints)_ | Hard constraints that a Host must satisfy to be a candidate for the VM.<br />The scheduler acts on hosts, excludedHosts and nodeSelector; the other<br />fields are accepted but not acted on in this release. |  | Optional: \{\} <br /> |
| `soft` _[PlacementConstraints](#placementconstraints)_ | Soft constraints that rank the candidate Hosts without removing any. The<br />scheduler acts on hosts, excludedHosts and nodeSelector; the other fields<br />are accepted but not acted on in this release. |  | Optional: \{\} <br /> |
| `antiAffinity` _[AntiAffinityRules](#antiaffinityrules)_ | AntiAffinity defines anti-affinity rules. The scheduler acts on<br />hostAntiAffinity and vmAntiAffinity; the cluster, datastore, zone and<br />application rules are accepted but not acted on in this release. |  | Optional: \{\} <br /> |
| `affinity` _[AffinityRules](#affinityrules)_ | Affinity defines affinity rules. The scheduler acts on hostAffinity and<br />vmAffinity; the cluster, datastore, zone and application rules are<br />accepted but not acted on in this release. |  | Optional: \{\} <br /> |
| `resourceConstraints` _[ResourceConstraints](#resourceconstraints)_ | ResourceConstraints defines placement constraints on the resources and CPU<br />features of a Host. The scheduler acts on minCPUPerHost, minMemoryPerHost,<br />minDiskSpacePerHost, requiredFeatures and preferredFeatures; the<br />utilization limits are accepted but not acted on in this release. |  | Optional: \{\} <br /> |
| `securityConstraints` _[SecurityConstraints](#securityconstraints)_ | SecurityConstraints defines security-based placement constraints. Accepted<br />but not acted on in this release. This applies to every field below it: no<br />Host status field carries this information. Label the Hosts and use<br />nodeSelector instead. |  | Optional: \{\} <br /> |
| `priority` _integer_ | Priority defines the priority of this placement policy. Accepted but not<br />acted on in this release. |  | Maximum: 1000 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `weight` _integer_ | Weight defines the weight of this placement policy. Accepted but not acted<br />on in this release. |  | Maximum: 100 <br />Minimum: 1 <br />Optional: \{\} <br /> |


#### VMPlacementPolicyStatus



VMPlacementPolicyStatus defines the observed state of VMPlacementPolicy.
Not populated in this release: no controller writes it.



_Appears in:_
- [VMPlacementPolicy](#vmplacementpolicy)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `observedGeneration` _integer_ | ObservedGeneration is the most recent generation observed by the<br />controller. Not populated in this release. |  | Optional: \{\} <br /> |
| `usedByVMs` _[LocalObjectReference](#localobjectreference) array_ | UsedByVMs lists VMs currently using this policy. Not populated in this<br />release. |  | MaxItems: 1000 <br />Optional: \{\} <br /> |
| `conditions` _[Condition](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#condition-v1-meta) array_ | Conditions represent the current service state. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `validationResults` _object (keys:string, values:[PolicyValidationResult](#policyvalidationresult))_ | ValidationResults contains validation results for different providers. Not<br />populated in this release. |  | Optional: \{\} <br /> |
| `placementStats` _[PlacementStatistics](#placementstatistics)_ | PlacementStats provides statistics about VM placements using this policy.<br />Not populated in this release. |  | Optional: \{\} <br /> |
| `conflictingPolicies` _[PolicyConflict](#policyconflict) array_ | ConflictingPolicies lists policies that conflict with this policy. Not<br />populated in this release. |  | MaxItems: 50 <br />Optional: \{\} <br /> |


#### VMResourceLimits



VMResourceLimits defines resource limits and reservations. Accepted but
not acted on in this release.



_Appears in:_
- [VMClassSpec](#vmclassspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `cpuLimit` _integer_ | CPULimit is the maximum CPU usage limit (in MHz or percentage).<br />Accepted but not acted on in this release. |  | Maximum: 100000 <br />Minimum: 100 <br />Optional: \{\} <br /> |
| `cpuReservation` _integer_ | CPUReservation is the guaranteed CPU allocation (in MHz). Accepted but<br />not acted on in this release. |  | Maximum: 100000 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `memoryLimit` _[Quantity](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#quantity-resource-api)_ | MemoryLimit is the maximum memory usage limit. Accepted but not acted<br />on in this release. |  | Optional: \{\} <br /> |
| `memoryReservation` _[Quantity](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#quantity-resource-api)_ | MemoryReservation is the guaranteed memory allocation. Accepted but not<br />acted on in this release. |  | Optional: \{\} <br /> |
| `cpuShares` _integer_ | CPUShares defines the relative CPU priority (higher = more priority).<br />Accepted but not acted on in this release. |  | Maximum: 1e+06 <br />Minimum: 1 <br />Optional: \{\} <br /> |


#### VMSelectorOperator

_Underlying type:_ _string_

VMSelectorOperator represents a selector operator

_Validation:_
- Enum: [In NotIn Exists DoesNotExist]

_Appears in:_
- [VMSelectorRequirement](#vmselectorrequirement)

| Field | Description |
| --- | --- |
| `In` | VMSelectorOpIn means the key must be in the set of values<br /> |
| `NotIn` | VMSelectorOpNotIn means the key must not be in the set of values<br /> |
| `Exists` | VMSelectorOpExists means the key must exist<br /> |
| `DoesNotExist` | VMSelectorOpDoesNotExist means the key must not exist<br /> |


#### VMSelectorRequirement



VMSelectorRequirement defines a requirement on the labels of a VM.



_Appears in:_
- [VMAffinityTerm](#vmaffinityterm)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `key` _string_ | Key is the label key that the requirement applies to. |  | MaxLength: 253 <br /> |
| `operator` _[VMSelectorOperator](#vmselectoroperator)_ | Operator represents the relationship between the label and Values: In,<br />NotIn, Exists or DoesNotExist. |  | Enum: [In NotIn Exists DoesNotExist] <br /> |
| `values` _string array_ | Values is the list of label values used by In and NotIn. It is ignored by<br />Exists and DoesNotExist. |  | MaxItems: 50 <br />Optional: \{\} <br /> |


#### VMSet



VMSet is the Schema for the vmsets API. It has no active controller in this
release: the controller only sets the condition Ready=False with the reason
ControllerNotImplemented on each VMSet, and creates, scales and updates no
VMs. Every spec field is accepted but not acted on in this release, and
status is not populated apart from that condition and observedGeneration.



_Appears in:_
- [VMSetList](#vmsetlist)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VMSet` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[VMSetSpec](#vmsetspec)_ |  |  |  |
| `status` _[VMSetStatus](#vmsetstatus)_ |  |  |  |


#### VMSetFailedVM



VMSetFailedVM represents a VM that failed to update. Not populated in this
release.



_Appears in:_
- [VMSetUpdateStatus](#vmsetupdatestatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the name of the failed VM. Not populated in this release. |  |  |
| `reason` _string_ | Reason provides the reason for failure. Not populated in this release. |  | Optional: \{\} <br /> |
| `message` _string_ | Message provides additional details about the failure. Not populated in<br />this release. |  | Optional: \{\} <br /> |
| `lastAttempt` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LastAttempt is when the last update attempt was made. Not populated in<br />this release. |  | Optional: \{\} <br /> |
| `retryCount` _integer_ | RetryCount is the number of retry attempts. Not populated in this release. |  | Optional: \{\} <br /> |


#### VMSetList



VMSetList contains a list of VMSet





| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VMSetList` | | |
| `metadata` _[ListMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#listmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `items` _[VMSet](#vmset) array_ |  |  |  |


#### VMSetOrdinals



VMSetOrdinals configures the sequential ordering of VM indices. Accepted
but not acted on in this release.



_Appears in:_
- [VMSetSpec](#vmsetspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `start` _integer_ | Start is the number representing the first replica's index. Accepted but<br />not acted on in this release. | 0 | Maximum: 999999 <br />Minimum: 0 <br />Optional: \{\} <br /> |


#### VMSetPersistentVolumeClaimRetentionPolicy



VMSetPersistentVolumeClaimRetentionPolicy defines the retention policy for
PVCs. Accepted but not acted on in this release.



_Appears in:_
- [VMSetSpec](#vmsetspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `whenDeleted` _[PersistentVolumeClaimRetentionPolicyType](#persistentvolumeclaimretentionpolicytype)_ | WhenDeleted specifies what happens to PVCs created from VMSet<br />VolumeClaimTemplates when the VMSet is deleted. Accepted but not acted on<br />in this release. | Retain | Enum: [Retain Delete] <br />Optional: \{\} <br /> |
| `whenScaled` _[PersistentVolumeClaimRetentionPolicyType](#persistentvolumeclaimretentionpolicytype)_ | WhenScaled specifies what happens to PVCs created from VMSet<br />VolumeClaimTemplates when the VMSet is scaled down. Accepted but not acted<br />on in this release. | Retain | Enum: [Retain Delete] <br />Optional: \{\} <br /> |


#### VMSetPodManagementPolicyType

_Underlying type:_ _string_

VMSetPodManagementPolicyType defines the policy for creating VMs. Accepted
but not acted on in this release.

_Validation:_
- Enum: [OrderedReady Parallel]

_Appears in:_
- [RollingUpdateVMSetStrategy](#rollingupdatevmsetstrategy)

| Field | Description |
| --- | --- |
| `OrderedReady` | OrderedReadyVMSetPodManagementPolicy creates VMs in order and waits for each to be ready<br /> |
| `Parallel` | ParallelVMSetPodManagementPolicy creates VMs in parallel<br /> |


#### VMSetSpec



VMSetSpec defines the desired state of VMSet. VMSet has no active
controller in this release, so every field is accepted but not acted on: no
VMs are created from the template.



_Appears in:_
- [VMSet](#vmset)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `replicas` _integer_ | Replicas is the desired number of VMs in the set. Accepted but not acted<br />on in this release. | 1 | Maximum: 1000 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `selector` _[LabelSelector](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#labelselector-v1-meta)_ | Selector is a label query over VMs that should match the replica count.<br />Accepted but not acted on in this release. |  |  |
| `template` _[VMSetTemplate](#vmsettemplate)_ | Template describes the VMs the set is meant to run.<br />Accepted but not acted on in this release. |  |  |
| `updateStrategy` _[VMSetUpdateStrategy](#vmsetupdatestrategy)_ | UpdateStrategy defines how to replace existing VMs with new ones. Accepted<br />but not acted on in this release. |  | Optional: \{\} <br /> |
| `minReadySeconds` _integer_ | MinReadySeconds is the minimum number of seconds for which a newly created<br />VM should be ready before it is considered available. Accepted but not<br />acted on in this release. |  | Maximum: 3600 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `revisionHistoryLimit` _integer_ | RevisionHistoryLimit is the number of old VMSets to retain. Accepted but<br />not acted on in this release. | 10 | Maximum: 100 <br />Minimum: 0 <br />Optional: \{\} <br /> |
| `persistentVolumeClaimRetentionPolicy` _[VMSetPersistentVolumeClaimRetentionPolicy](#vmsetpersistentvolumeclaimretentionpolicy)_ | PersistentVolumeClaimRetentionPolicy defines the retention policy for<br />PVCs. Accepted but not acted on in this release. |  | Optional: \{\} <br /> |
| `ordinals` _[VMSetOrdinals](#vmsetordinals)_ | Ordinals configures the sequential ordering of VM indices. Accepted but<br />not acted on in this release. |  | Optional: \{\} <br /> |
| `serviceName` _string_ | ServiceName is the name of the service that governs this VMSet. Accepted<br />but not acted on in this release. |  | MaxLength: 253 <br />Optional: \{\} <br /> |
| `volumeClaimTemplates` _[PersistentVolumeClaimTemplate](#persistentvolumeclaimtemplate) array_ | VolumeClaimTemplates defines a list of claims that VMs are allowed to<br />reference. Accepted but not acted on in this release. |  | MaxItems: 20 <br />Optional: \{\} <br /> |


#### VMSetStatus



VMSetStatus defines the observed state of VMSet. Only observedGeneration
and the Ready condition are written in this release; every other field is
not populated.



_Appears in:_
- [VMSet](#vmset)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `observedGeneration` _integer_ | ObservedGeneration is the most recent generation observed by the<br />controller. |  | Optional: \{\} <br /> |
| `replicas` _integer_ | Replicas is the number of VMs created by the VMSet controller. Not<br />populated in this release. |  | Optional: \{\} <br /> |
| `readyReplicas` _integer_ | ReadyReplicas is the number of VMs that are ready. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `availableReplicas` _integer_ | AvailableReplicas is the number of VMs that are available. Not populated<br />in this release. |  | Optional: \{\} <br /> |
| `updatedReplicas` _integer_ | UpdatedReplicas is the number of VMs that have been updated. Not populated<br />in this release. |  | Optional: \{\} <br /> |
| `currentRevision` _string_ | CurrentRevision is the revision of the current VMSet. Not populated in<br />this release. |  | Optional: \{\} <br /> |
| `updateRevision` _string_ | UpdateRevision is the revision of the updated VMSet. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `collisionCount` _integer_ | CollisionCount is the count of hash collisions for the VMSet. Not<br />populated in this release. |  | Optional: \{\} <br /> |
| `conditions` _[Condition](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#condition-v1-meta) array_ | Conditions represent the current service state. In this release the only<br />condition is Ready=False with the reason ControllerNotImplemented. |  | Optional: \{\} <br /> |
| `currentReplicas` _integer_ | CurrentReplicas is the number of VMs currently running. Not populated in<br />this release. |  | Optional: \{\} <br /> |
| `updateStatus` _[VMSetUpdateStatus](#vmsetupdatestatus)_ | UpdateStatus provides detailed update operation status. Not populated in<br />this release. |  | Optional: \{\} <br /> |
| `vmStatus` _[VMSetVMStatus](#vmsetvmstatus) array_ | VMStatus provides per-VM status information. Not populated in this<br />release. |  | MaxItems: 1000 <br />Optional: \{\} <br /> |


#### VMSetTemplate



VMSetTemplate defines the template for VMs in a VMSet. Accepted but not
acted on in this release.



_Appears in:_
- [VMSetSpec](#vmsetspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  | Optional: \{\} <br /> |
| `spec` _[VirtualMachineSpec](#virtualmachinespec)_ | Spec is the VM specification. Accepted but not acted on in this release. |  |  |


#### VMSetUpdatePhase

_Underlying type:_ _string_

VMSetUpdatePhase represents the phase of a VMSet update. Not populated in
this release.

_Validation:_
- Enum: [Pending InProgress Paused Completed Failed]

_Appears in:_
- [VMSetUpdateStatus](#vmsetupdatestatus)

| Field | Description |
| --- | --- |
| `Pending` | VMSetUpdatePhasePending indicates the update is pending<br /> |
| `InProgress` | VMSetUpdatePhaseInProgress indicates the update is in progress<br /> |
| `Paused` | VMSetUpdatePhasePaused indicates the update is paused<br /> |
| `Completed` | VMSetUpdatePhaseCompleted indicates the update is completed<br /> |
| `Failed` | VMSetUpdatePhaseFailed indicates the update failed<br /> |


#### VMSetUpdateStatus



VMSetUpdateStatus provides detailed update operation status. Not populated
in this release.



_Appears in:_
- [VMSetStatus](#vmsetstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `phase` _[VMSetUpdatePhase](#vmsetupdatephase)_ | Phase represents the current phase of the update. Not populated in this<br />release. |  | Enum: [Pending InProgress Paused Completed Failed] <br />Optional: \{\} <br /> |
| `message` _string_ | Message provides additional details about the update. Not populated in<br />this release. |  | Optional: \{\} <br /> |
| `startTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | StartTime is when the update started. Not populated in this release. |  | Optional: \{\} <br /> |
| `completionTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | CompletionTime is when the update completed. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `updatedVMs` _string array_ | UpdatedVMs lists VMs that have been updated. Not populated in this<br />release. |  | MaxItems: 1000 <br />Optional: \{\} <br /> |
| `pendingVMs` _string array_ | PendingVMs lists VMs that are pending update. Not populated in this<br />release. |  | MaxItems: 1000 <br />Optional: \{\} <br /> |
| `failedVMs` _[VMSetFailedVM](#vmsetfailedvm) array_ | FailedVMs lists VMs that failed to update. Not populated in this release. |  | MaxItems: 1000 <br />Optional: \{\} <br /> |


#### VMSetUpdateStrategy



VMSetUpdateStrategy defines the update strategy for a VMSet. Accepted but
not acted on in this release.



_Appears in:_
- [VMSetSpec](#vmsetspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `type` _[VMSetUpdateStrategyType](#vmsetupdatestrategytype)_ | Type can be "RollingUpdate", "OnDelete" or "Recreate". Accepted but not<br />acted on in this release. | RollingUpdate | Enum: [RollingUpdate OnDelete Recreate] <br />Optional: \{\} <br /> |
| `rollingUpdate` _[RollingUpdateVMSetStrategy](#rollingupdatevmsetstrategy)_ | RollingUpdate is used when Type is RollingUpdate. Accepted but not acted<br />on in this release. |  | Optional: \{\} <br /> |


#### VMSetUpdateStrategyType

_Underlying type:_ _string_

VMSetUpdateStrategyType defines the type of update strategy. Accepted but
not acted on in this release.

_Validation:_
- Enum: [RollingUpdate OnDelete Recreate]

_Appears in:_
- [VMSetUpdateStrategy](#vmsetupdatestrategy)

| Field | Description |
| --- | --- |
| `RollingUpdate` | RollingUpdateVMSetStrategyType replaces VMs one by one<br /> |
| `OnDelete` | OnDeleteVMSetStrategyType replaces VMs only when manually deleted<br /> |
| `Recreate` | RecreateVMSetStrategyType deletes all VMs before creating new ones<br /> |


#### VMSetVMStatus



VMSetVMStatus provides per-VM status information. Not populated in this
release.



_Appears in:_
- [VMSetStatus](#vmsetstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the VM name. Not populated in this release. |  |  |
| `phase` _[VirtualMachinePhase](#virtualmachinephase)_ | Phase is the VM phase. Not populated in this release. |  | Enum: [Pending Provisioning Running Stopped Reconfiguring Deleting Failed] <br />Optional: \{\} <br /> |
| `ready` _boolean_ | Ready indicates if the VM is ready. Not populated in this release. |  | Optional: \{\} <br /> |
| `revision` _string_ | Revision is the VM revision. Not populated in this release. |  | Optional: \{\} <br /> |
| `creationTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | CreationTime is when the VM was created. Not populated in this release. |  | Optional: \{\} <br /> |
| `lastUpdateTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LastUpdateTime is when the VM was last updated. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `message` _string_ | Message provides additional VM status information. Not populated in this<br />release. |  | Optional: \{\} <br /> |


#### VMSnapshot



VMSnapshot takes one snapshot of a VirtualMachine, through the VM's Provider,
and records the result. Deleting the VMSnapshot deletes the provider
snapshot. The VM must be in the VMSnapshot's namespace. To revert a VM to a
snapshot, set spec.snapshot.revertToRef on the VirtualMachine.



_Appears in:_
- [VMSnapshotList](#vmsnapshotlist)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VMSnapshot` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[VMSnapshotSpec](#vmsnapshotspec)_ |  |  |  |
| `status` _[VMSnapshotStatus](#vmsnapshotstatus)_ |  |  |  |


#### VMSnapshotInfo



VMSnapshotInfo provides information about a VM snapshot



_Appears in:_
- [VirtualMachineStatus](#virtualmachinestatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `id` _string_ | ID is the provider-specific snapshot identifier |  |  |
| `name` _string_ | Name is the snapshot name |  |  |
| `creationTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | CreationTime is when the snapshot was created |  |  |
| `description` _string_ | Description provides additional context |  | Optional: \{\} <br /> |
| `sizeBytes` _integer_ | SizeBytes is the size of the snapshot |  | Optional: \{\} <br /> |
| `hasMemory` _boolean_ | HasMemory indicates if memory state is included |  | Optional: \{\} <br /> |


#### VMSnapshotList



VMSnapshotList contains a list of VMSnapshot





| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VMSnapshotList` | | |
| `metadata` _[ListMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#listmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `items` _[VMSnapshot](#vmsnapshot) array_ |  |  |  |


#### VMSnapshotOperation



VMSnapshotOperation defines snapshot operations in VM spec



_Appears in:_
- [VirtualMachineSpec](#virtualmachinespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `revertToRef` _[LocalObjectReference](#localobjectreference)_ | RevertToRef names a VMSnapshot, in the VM's namespace, to revert the VM<br />to. The snapshot must have been taken of this VM (its spec.vmRef and<br />status.vmUID) and be Ready. The revert is sent only while the VM is<br />powered off and spec.powerState is Off or OffGraceful: the controller<br />never powers a VM off for a revert, and does not power it on afterwards<br />(spec.powerState decides that). It is sent at most once per request:<br />status.snapshotRevert records the outcome, and while the field stays set<br />to the same VMSnapshot nothing is sent again (a GitOps re-apply is a<br />no-op). To revert to the same snapshot again, remove the field, then set<br />it again; naming another VMSnapshot (another UID) is a new request.<br />The SnapshotReverted condition reports the progress. |  | Optional: \{\} <br /> |


#### VMSnapshotSpec



VMSnapshotSpec defines the desired state of VMSnapshot. A VMSnapshot takes
one snapshot of one VirtualMachine, through the VM's Provider. Of the spec,
vmRef, snapshotConfig (name, description, includeMemory) and retentionPolicy
(maxAge, deleteOnVMDelete) are acted on; schedule and metadata are accepted
but not acted on in this release.



_Appears in:_
- [VMSnapshot](#vmsnapshot)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `vmRef` _[LocalObjectReference](#localobjectreference)_ | VMRef references the VirtualMachine to snapshot, by name, in the<br />VMSnapshot's own namespace. |  |  |
| `snapshotConfig` _[SnapshotConfig](#snapshotconfig)_ | SnapshotConfig defines snapshot configuration options. When it is<br />omitted, the snapshot is named after the VMSnapshot and has no description<br />and no memory state. |  | Optional: \{\} <br /> |
| `retentionPolicy` _[SnapshotRetentionPolicy](#snapshotretentionpolicy)_ | RetentionPolicy defines when the VMSnapshot, and with it the provider<br />snapshot, is deleted automatically. Only maxAge and deleteOnVMDelete are<br />acted on; the other fields are accepted but not acted on in this release.<br />With no retentionPolicy a snapshot is kept until the VMSnapshot is deleted. |  | Optional: \{\} <br /> |
| `schedule` _[SnapshotSchedule](#snapshotschedule)_ | Schedule defines automated snapshot scheduling. Accepted but not acted on<br />in this release: no controller reads it, and no snapshot is taken on a<br />schedule. Create VMSnapshot objects yourself (for example from a CronJob). |  | Optional: \{\} <br /> |
| `metadata` _[SnapshotMetadata](#snapshotmetadata)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  | Optional: \{\} <br /> |


#### VMSnapshotStatus



VMSnapshotStatus defines the observed state of VMSnapshot. The controller
writes snapshotID, phase, message, creationTime, taskRef, vmUID,
boundProvider and conditions. completionTime, size, virtualSize, progress,
providerStatus, children, parent and expiryTime are not populated in this
release.



_Appears in:_
- [VMSnapshot](#vmsnapshot)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `snapshotID` _string_ | SnapshotID is the provider-specific identifier for the snapshot, as<br />returned by the provider when the snapshot is created. On libvirt and<br />Proxmox it is the snapshot's name; on vSphere it is the snapshot's<br />managed object ID. |  | Optional: \{\} <br /> |
| `phase` _[SnapshotPhase](#snapshotphase)_ | Phase represents the current phase of the snapshot. It is empty until the<br />controller issues the create, then Creating, then Ready or Failed; it is<br />Deleting while the VMSnapshot is being deleted. |  | Enum: [Pending Creating Ready Deleting Failed Expired] <br />Optional: \{\} <br /> |
| `message` _string_ | Message provides additional details about the current state |  | Optional: \{\} <br /> |
| `creationTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | CreationTime is when the controller received the provider's answer to the<br />create. It is the start of the age counted by retentionPolicy.maxAge. |  | Optional: \{\} <br /> |
| `completionTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | CompletionTime is when the snapshot creation completed. Not populated in<br />this release. |  | Optional: \{\} <br /> |
| `size` _[Quantity](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#quantity-resource-api)_ | Size is the size of the snapshot. Not populated in this release. |  | Optional: \{\} <br /> |
| `virtualSize` _[Quantity](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#quantity-resource-api)_ | VirtualSize is the virtual size of the snapshot. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `taskRef` _string_ | TaskRef is the provider task of an in-flight asynchronous snapshot create.<br />The controller polls it until the task completes, then clears it. |  | Optional: \{\} <br /> |
| `vmUID` _string_ | VMUID is the UID of the VirtualMachine the snapshot was taken of,<br />recorded when its create is issued. A VirtualMachine deleted and<br />re-created under the same name has another UID: the snapshot is never<br />deleted or retained through it (no provider call is made), because on a<br />provider whose snapshot ids are names the call could reach another<br />VM's snapshot. Empty for a snapshot taken by an earlier release, which is<br />bound on first reconcile when its VM was created before the snapshot.<br />Written only by the operator. |  | MaxLength: 128 <br />Optional: \{\} <br /> |
| `boundProvider` _[BoundProviderRef](#boundproviderref)_ | BoundProvider is the Provider the snapshot was taken through, recorded<br />with VMUID. The snapshot is deleted only through this same Provider<br />(namespace, name and, when recorded, UID). Written only by the<br />operator. |  | Optional: \{\} <br /> |
| `conditions` _[Condition](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#condition-v1-meta) array_ | Conditions represent the latest observations of the snapshot. Ready is<br />True once the snapshot exists; Creating and Deleting are True while a<br />create or a delete is in progress. |  | Optional: \{\} <br /> |
| `observedGeneration` _integer_ | ObservedGeneration is the generation the controller recorded when it<br />refused the snapshot because its VM uses a Provider in another namespace<br />that does not allow it; it is not populated otherwise. Each condition<br />carries its own observedGeneration. |  | Optional: \{\} <br /> |
| `progress` _[SnapshotProgress](#snapshotprogress)_ | Progress shows the snapshot creation progress. Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `providerStatus` _object (keys:string, values:[ProviderSnapshotStatus](#providersnapshotstatus))_ | ProviderStatus contains provider-specific status information. Not<br />populated in this release. |  | Optional: \{\} <br /> |
| `children` _[SnapshotRef](#snapshotref) array_ | Children lists child snapshots (for snapshot trees). Not populated in this<br />release. |  | Optional: \{\} <br /> |
| `parent` _[SnapshotRef](#snapshotref)_ | Parent references the parent snapshot (for snapshot trees). Not populated<br />in this release. |  | Optional: \{\} <br /> |
| `expiryTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | ExpiryTime is when the snapshot will expire. Not populated in this<br />release, so the Expires column of kubectl get is empty; a snapshot is<br />deleted when retentionPolicy.maxAge has passed since status.creationTime. |  | Optional: \{\} <br /> |


#### VMTaintEffect

_Underlying type:_ _string_

VMTaintEffect represents the effect of a taint. Accepted but not acted on
in this release.

_Validation:_
- Enum: [NoSchedule PreferNoSchedule NoExecute]

_Appears in:_
- [VMToleration](#vmtoleration)

| Field | Description |
| --- | --- |
| `NoSchedule` | VMTaintEffectNoSchedule means no new VMs will be scheduled<br /> |
| `PreferNoSchedule` | VMTaintEffectPreferNoSchedule means avoid scheduling if possible<br /> |
| `NoExecute` | VMTaintEffectNoExecute means existing VMs will be evicted<br /> |


#### VMToleration



VMToleration represents a toleration for VM placement. Accepted but not
acted on in this release.



_Appears in:_
- [PlacementConstraints](#placementconstraints)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `key` _string_ | Key is the taint key that the toleration applies to. Accepted but not<br />acted on in this release. |  | MaxLength: 253 <br />Optional: \{\} <br /> |
| `operator` _[VMTolerationOperator](#vmtolerationoperator)_ | Operator represents the relationship between the key and value. Accepted<br />but not acted on in this release. | Equal | Enum: [Exists Equal] <br />Optional: \{\} <br /> |
| `value` _string_ | Value is the taint value the toleration matches to. Accepted but not acted<br />on in this release. |  | MaxLength: 253 <br />Optional: \{\} <br /> |
| `effect` _[VMTaintEffect](#vmtainteffect)_ | Effect indicates the taint effect to match. Accepted but not acted on in<br />this release. |  | Enum: [NoSchedule PreferNoSchedule NoExecute] <br />Optional: \{\} <br /> |
| `tolerationSeconds` _integer_ | TolerationSeconds represents the period of time the toleration tolerates<br />the taint. Accepted but not acted on in this release. |  | Minimum: 0 <br />Optional: \{\} <br /> |


#### VMTolerationOperator

_Underlying type:_ _string_

VMTolerationOperator represents the operator for toleration. Accepted but
not acted on in this release.

_Validation:_
- Enum: [Exists Equal]

_Appears in:_
- [VMToleration](#vmtoleration)

| Field | Description |
| --- | --- |
| `Exists` | VMTolerationOpExists means the toleration exists<br /> |
| `Equal` | VMTolerationOpEqual means the toleration equals the value<br /> |


#### VSphereImageSource



VSphereImageSource defines vSphere-specific image configuration. Set one of:
  - TemplateName: an existing vSphere template, by name or inventory path.
    Nothing is prepared; VMs are cloned from it.
  - OVAURL: an OVA to download and import as a template, when the first VM
    that uses the image is created.
  - ContentLibrary: accepted but not acted on in this release.

Setting OVAURL together with TemplateName or ContentLibrary is refused when
the image is prepared.



_Appears in:_
- [ImageSource](#imagesource)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `templateName` _string_ | TemplateName references an existing vSphere template by name.<br />This can be a simple name, matched exactly against the VMs in the<br />Provider's default datacenter, or an inventory path within that<br />datacenter's VM folder (absolute, e.g. "/DC1/vm/templates/ubuntu", or<br />relative to the VM folder, e.g. "templates/ubuntu"; an absolute path in any<br />other datacenter is rejected). It must name an object marked as a vSphere<br />template: a regular VM (running or powered off) is never used as a clone<br />source, a name matching more than one template is rejected (use an<br />inventory path), and a name of the form "vm-" followed only by digits is<br />rejected. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `contentLibrary` _[ContentLibraryRef](#contentlibraryref)_ | ContentLibrary references a vSphere content library item. Accepted but not<br />acted on in this release: the provider does not resolve content library<br />items, so a VM cannot be created from an image that has only this source.<br />Use templateName or ovaURL. |  | Optional: \{\} <br /> |
| `ovaURL` _string_ | OVAURL is the URL of an OVA file to import as a vSphere template. The<br />vSphere provider downloads it and imports it when the first VM that uses the<br />image is created; the template is named after the VMImage's namespace, name,<br />UID and source and is reused by later VMs. The scheme must be http or https, and a<br />bare .ovf is refused when the image is prepared (publish an .ova). The<br />provider refuses addresses such as loopback and link-local ones. Keep<br />credentials out of the URL: it is part of the VMImage, which other<br />namespaces may be able to read (see docs/image-preparation.md). |  | Pattern: `^https?://.*\.(ova\|ovf)$` <br />Optional: \{\} <br /> |
| `checksum` _string_ | Checksum is the expected checksum of the downloaded OVA: the hex digest<br />only, without an algorithm prefix, compared case-insensitively. It is<br />checked when the OVA is imported (ovaURL) and a mismatch fails the prepare;<br />it is not used with templateName. Empty disables the check. |  | Optional: \{\} <br /> |
| `checksumType` _[ChecksumType](#checksumtype)_ | ChecksumType specifies the checksum algorithm: md5, sha1, sha256 or sha512. | sha256 | Enum: [md5 sha1 sha256 sha512] <br />Optional: \{\} <br /> |
| `providerRef` _[LocalObjectReference](#localobjectreference)_ | ProviderRef references the vSphere provider for importing. Accepted but not<br />acted on in this release: an image is prepared through the Provider of the<br />VirtualMachine that uses it. |  | Optional: \{\} <br /> |


#### VSphereNetworkConfig



VSphereNetworkConfig defines vSphere-specific network settings. Only
portgroup is acted on: for the first entry of the VM's spec.networks the
vSphere provider adds a vmxnet3 adapter on the network of that name; the
template's own adapters are left unchanged. The other fields are accepted but not acted on in this
release.



_Appears in:_
- [NetworkConfig](#networkconfig)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `portgroup` _string_ | Portgroup is the name of the vSphere network that the added vmxnet3<br />adapter is attached to. The vSphere provider uses it for the first entry<br />of the VM's spec.networks only. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `distributedSwitch` _[DistributedSwitchConfig](#distributedswitchconfig)_ | DistributedSwitch specifies the distributed virtual switch. Accepted but<br />not acted on in this release. This applies to every field below it. |  | Optional: \{\} <br /> |
| `vlan` _[VLANConfig](#vlanconfig)_ | VLAN specifies the VLAN configuration. Accepted but not acted on in this<br />release. This applies to every field below it: the manager forwards<br />vlan.vlanID, but the vSphere provider does not use it, so the VLAN is the<br />one the portgroup is configured with. |  | Optional: \{\} <br /> |
| `security` _[PortgroupSecurityConfig](#portgroupsecurityconfig)_ | Security defines portgroup security settings. Accepted but not acted on in<br />this release. This applies to every field below it. |  | Optional: \{\} <br /> |
| `trafficShaping` _[TrafficShapingConfig](#trafficshapingconfig)_ | TrafficShaping defines traffic shaping settings. Accepted but not acted on<br />in this release. This applies to every field below it. |  | Optional: \{\} <br /> |
| `pciSlotNumber` _integer_ | PCISlotNumber specifies the PCI slot number for the network adapter.<br />Accepted but not acted on in this release. The manager forwards it to the<br />provider, but the vSphere provider does not use it, so it does not control<br />the guest's interface name. |  | Maximum: 1024 <br />Minimum: 32 <br />Optional: \{\} <br /> |
| `adapterType` _string_ | AdapterType specifies the network adapter type. Accepted but not acted on<br />in this release. The vSphere provider always creates a vmxnet3 adapter. | vmxnet3 | Enum: [vmxnet3 e1000 e1000e] <br />Optional: \{\} <br /> |


#### VSphereStorageOptions



VSphereStorageOptions defines vSphere storage preparation options. Accepted
but not acted on in this release.



_Appears in:_
- [StoragePrepareOptions](#storageprepareoptions)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `datastore` _string_ | Datastore specifies the target datastore for import. Accepted but not<br />acted on in this release. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `folder` _string_ | Folder specifies the target folder for import. Accepted but not acted on<br />in this release: an OVA is imported into the Provider's spec.defaults.folder. |  | MaxLength: 255 <br />Optional: \{\} <br /> |
| `thinProvisioned` _boolean_ | ThinProvisioned indicates whether to use thin provisioning. Accepted but<br />not acted on in this release. |  | Optional: \{\} <br /> |
| `diskType` _string_ | DiskType specifies the disk provisioning type. Accepted but not acted on<br />in this release. |  | Enum: [thin thick eagerzeroedthick] <br />Optional: \{\} <br /> |


#### ValidationChecks



ValidationChecks defines validation checks to perform. Accepted but not acted
on in this release.



_Appears in:_
- [MigrationOptions](#migrationoptions)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `checkDiskSize` _boolean_ | CheckDiskSize verifies disk size matches. Accepted but not acted on in this release. | true | Optional: \{\} <br /> |
| `checkChecksum` _boolean_ | CheckChecksum verifies checksums match. Accepted but not acted on in this release. | true | Optional: \{\} <br /> |
| `checkBoot` _boolean_ | CheckBoot verifies VM boots successfully. Accepted but not acted on in this release. | false | Optional: \{\} <br /> |
| `checkConnectivity` _boolean_ | CheckConnectivity tests network connectivity. Accepted but not acted on in this release. | false | Optional: \{\} <br /> |


#### ValidationResult



ValidationResult represents a validation result for a provider. Not
populated in this release.



_Appears in:_
- [VMClassStatus](#vmclassstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `valid` _boolean_ | Valid indicates if the class is valid for the provider. Not populated<br />in this release. |  |  |
| `message` _string_ | Message provides details about the validation result. Not populated in<br />this release. |  | Optional: \{\} <br /> |
| `warnings` _string array_ | Warnings lists any validation warnings. Not populated in this release. |  | Optional: \{\} <br /> |
| `lastValidated` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LastValidated is when this validation was last performed. Not populated<br />in this release. |  | Optional: \{\} <br /> |


#### ValidationResults



ValidationResults contains results of validation checks. Not populated in this
release.



_Appears in:_
- [VMMigrationStatus](#vmmigrationstatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `diskSizeMatch` _boolean_ | DiskSizeMatch indicates if disk sizes match |  | Optional: \{\} <br /> |
| `checksumMatch` _boolean_ | ChecksumMatch indicates if checksums match |  | Optional: \{\} <br /> |
| `bootSuccess` _boolean_ | BootSuccess indicates if the target VM booted successfully |  | Optional: \{\} <br /> |
| `connectivitySuccess` _boolean_ | ConnectivitySuccess indicates if network connectivity works |  | Optional: \{\} <br /> |
| `validationErrors` _string array_ | ValidationErrors lists any validation errors |  | Optional: \{\} <br /> |


#### VirtualMachine



VirtualMachine is the Schema for the virtualmachines API.

spec.providerRef is locked once the VM is bound (status.id or
status.placement.pendingHost set in the STORED object). The rule below is a
transition rule, evaluated only on update; it lives on the root so it can
read the stored status. With the status subresource enabled, a main-resource
update is validated against the stored status and a status update carries
the stored spec, so neither path can unlock or change it. providerRef is
compared as a whole: an unset namespace equals only an unset namespace (an
explicit "" is rejected by the ObjectRef pattern), so unset -> explicit is a
change. (A per-field comparison through conditional expressions exceeds the
apiserver's static CEL cost budget; whole-object equality does not.)

spec.classRef and spec.resources are locked while a clustered create is
pending: status.placement.pendingHost set and status.id still empty in the
STORED object. The scheduler admitted the VM at that size and every other
schedule counts the pending VM at it, so its owner must not grow it before
the create lands.
Once the VM is created, its size is counted from status.currentResources and
a resize-up is admitted against the host's capacity instead. A transition
rule on the root, like the providerRef rule above; both are compared as
whole objects.



_Appears in:_
- [VirtualMachineList](#virtualmachinelist)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VirtualMachine` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[VirtualMachineSpec](#virtualmachinespec)_ |  |  |  |
| `status` _[VirtualMachineStatus](#virtualmachinestatus)_ |  |  |  |




#### VirtualMachineLifecycle



VirtualMachineLifecycle defines lifecycle configuration for a VM. Accepted but
not acted on in this release.



_Appears in:_
- [VirtualMachineSpec](#virtualmachinespec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `preStop` _[LifecycleHandler](#lifecyclehandler)_ | PreStop defines actions to take before stopping the VM. Accepted but not<br />acted on in this release. |  | Optional: \{\} <br /> |
| `postStart` _[LifecycleHandler](#lifecyclehandler)_ | PostStart defines actions to take after starting the VM. Accepted but not<br />acted on in this release. |  | Optional: \{\} <br /> |
| `gracefulShutdownTimeout` _[Duration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#duration-v1-meta)_ | GracefulShutdownTimeout defines how long to wait for graceful shutdown.<br />Accepted but not acted on in this release. | 60s | Optional: \{\} <br /> |


#### VirtualMachineList



VirtualMachineList contains a list of VirtualMachine





| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `infra.virtrigaud.io/v1beta1` | | |
| `kind` _string_ | `VirtualMachineList` | | |
| `metadata` _[ListMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#listmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `items` _[VirtualMachine](#virtualmachine) array_ |  |  |  |


#### VirtualMachinePhase

_Underlying type:_ _string_

VirtualMachinePhase represents the phase of a VM

_Validation:_
- Enum: [Pending Provisioning Running Stopped Reconfiguring Deleting Failed]

_Appears in:_
- [VMSetVMStatus](#vmsetvmstatus)
- [VirtualMachineStatus](#virtualmachinestatus)

| Field | Description |
| --- | --- |
| `Pending` | VirtualMachinePhasePending indicates the VM is waiting to be processed<br /> |
| `Provisioning` | VirtualMachinePhaseProvisioning indicates the VM is being created<br /> |
| `Running` | VirtualMachinePhaseRunning indicates the VM is running<br /> |
| `Stopped` | VirtualMachinePhaseStopped indicates the VM is stopped<br /> |
| `Reconfiguring` | VirtualMachinePhaseReconfiguring indicates the VM is being reconfigured<br /> |
| `Deleting` | VirtualMachinePhaseDeleting indicates the VM is being deleted<br /> |
| `Failed` | VirtualMachinePhaseFailed indicates the VM is in a failed state<br /> |


#### VirtualMachineResources



VirtualMachineResources defines resource overrides for a VM



_Appears in:_
- [VirtualMachineSpec](#virtualmachinespec)
- [VirtualMachineStatus](#virtualmachinestatus)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `cpu` _integer_ | CPU specifies the number of virtual CPUs |  | Maximum: 128 <br />Minimum: 1 <br />Optional: \{\} <br /> |
| `memoryMiB` _integer_ | MemoryMiB specifies the amount of memory in MiB |  | Maximum: 1.048576e+06 <br />Minimum: 128 <br />Optional: \{\} <br /> |
| `gpu` _[GPUConfig](#gpuconfig)_ | GPU specifies GPU configuration. Accepted but not acted on in this release:<br />no GPU is requested from the provider. |  | Optional: \{\} <br /> |


#### VirtualMachineSpec



VirtualMachineSpec defines the desired state of VirtualMachine.



_Appears in:_
- [VMSetTemplate](#vmsettemplate)
- [VirtualMachine](#virtualmachine)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `providerRef` _[ObjectRef](#objectref)_ | ProviderRef references the Provider that manages this VM. On a<br />VirtualMachine it is immutable once the VM is bound to a hypervisor VM<br />(status.id or status.placement.pendingHost is set): every per-VM call<br />addresses the VM by its provider id, which is meaningful only on the<br />Provider that assigned it. Before binding (e.g. to fix a typo after a<br />failed create) it may still be changed. An unset namespace means the VM's<br />own; changing it from unset to an explicit namespace also counts as a<br />change. |  |  |
| `classRef` _[ObjectRef](#objectref)_ | ClassRef references the VMClass that defines resource allocation |  |  |
| `imageRef` _[ObjectRef](#objectref)_ | ImageRef references the VMImage to use as base template.<br />Either ImageRef or ImportedDisk must be specified, but not both. |  | Optional: \{\} <br /> |
| `importedDisk` _[ImportedDiskRef](#importeddiskref)_ | ImportedDisk references a pre-imported disk (e.g., from migration).<br />Either ImageRef or ImportedDisk must be specified, but not both. |  | Optional: \{\} <br /> |
| `networks` _[VMNetworkRef](#vmnetworkref) array_ | Networks specifies network attachments for the VM |  | MaxItems: 10 <br />Optional: \{\} <br /> |
| `disks` _[DiskSpec](#diskspec) array_ | Disks specifies additional disks beyond the root disk. The vSphere provider<br />attaches them at create. The libvirt and Proxmox providers attach none: a VM<br />on such a Provider reports DisksApplied=False (reason<br />NotSupportedByProvider), and the spec is not refused. |  | MaxItems: 20 <br />Optional: \{\} <br /> |
| `userData` _[UserData](#userdata)_ | UserData contains cloud-init configuration |  | Optional: \{\} <br /> |
| `metaData` _[MetaData](#metadata)_ | MetaData contains cloud-init metadata configuration |  | Optional: \{\} <br /> |
| `placement` _[Placement](#placement)_ | Placement provides hints for VM placement. Cluster, datastore, storagePod<br />and folder are sent to the provider with the create request and are used by<br />the vSphere provider only; the libvirt and Proxmox providers do not use<br />them when creating a VM. host and resourcePool are accepted but not acted<br />on in this release. On a clustered Provider the scheduler chooses the host<br />(see status.placement and spec.placementRef). |  | Optional: \{\} <br /> |
| `powerState` _[PowerState](#powerstate)_ | PowerState specifies the desired power state |  | Enum: [On Off OffGraceful] <br />Optional: \{\} <br /> |
| `tags` _string array_ | Tags are sent to the provider with the create request. No provider applies<br />them to the hypervisor VM in this release. |  | MaxItems: 50 <br />Optional: \{\} <br /> |
| `resources` _[VirtualMachineResources](#virtualmachineresources)_ | Resources allows overriding resource allocation from the VMClass |  | Optional: \{\} <br /> |
| `placementRef` _[LocalObjectReference](#localobjectreference)_ | PlacementRef references a VMPlacementPolicy for advanced placement rules |  | Optional: \{\} <br /> |
| `snapshot` _[VMSnapshotOperation](#vmsnapshotoperation)_ | Snapshot defines snapshot-related operations |  | Optional: \{\} <br /> |
| `lifecycle` _[VirtualMachineLifecycle](#virtualmachinelifecycle)_ | Lifecycle defines VM lifecycle configuration. Accepted but not acted on in<br />this release: no preStop or postStart handler runs and<br />gracefulShutdownTimeout is not used. |  | Optional: \{\} <br /> |


#### VirtualMachineStatus



VirtualMachineStatus defines the observed state of VirtualMachine.



_Appears in:_
- [VirtualMachine](#virtualmachine)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `id` _string_ | ID is the provider-specific identifier for this VM |  | Optional: \{\} <br /> |
| `powerState` _[ObservedPowerState](#observedpowerstate)_ | PowerState reflects the current power state as the provider reports it:<br />On, Off, or — from a provider that can tell (libvirt) — Suspended (the<br />VM is paused or suspended to RAM: still active, not powered off) or<br />Unknown. While a VM is Suspended or Unknown it is not reconfigured and<br />not powered on; a Suspended VM whose spec.powerState is Off is powered<br />off (hard), while OffGraceful is held until the VM is resumed (a<br />suspended guest cannot shut down gracefully). |  | Enum: [On Off OffGraceful Suspended Unknown] <br />Optional: \{\} <br /> |
| `ips` _string array_ | IPs lists the addresses a user can reach the VM on, in the order the<br />provider reported them, without duplicates: private, IPv6 unique-local<br />and global addresses, IPv4 and IPv6. Loopback (127.0.0.0/8, ::1),<br />unspecified (0.0.0.0, ::), link-local (169.254.0.0/16, fe80::/10) and<br />multicast addresses are never listed. It is empty while the provider<br />cannot see an address, for example while the guest tools (VMware Tools,<br />the QEMU guest agent) are not running in the guest. |  | Optional: \{\} <br /> |
| `consoleURL` _string_ | ConsoleURL provides access to the VM console |  | Optional: \{\} <br /> |
| `conditions` _[Condition](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#condition-v1-meta) array_ | Conditions represent the latest available observations |  | Optional: \{\} <br /> |
| `observedGeneration` _integer_ | ObservedGeneration reflects the generation observed by the controller |  | Optional: \{\} <br /> |
| `lastTaskRef` _string_ | LastTaskRef references the last async operation |  | Optional: \{\} <br /> |
| `provider` _object (keys:string, values:string)_ | Provider contains provider-specific details the provider reported when it<br />last described the VM (and, for an adopted VM, when it was adopted). |  | Optional: \{\} <br /> |
| `reconfigureTaskRef` _string_ | ReconfigureTaskRef tracks reconfiguration operations |  | Optional: \{\} <br /> |
| `lastReconfigureTime` _[Time](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.32/#time-v1-meta)_ | LastReconfigureTime records when the last reconfiguration occurred |  | Optional: \{\} <br /> |
| `currentResources` _[VirtualMachineResources](#virtualmachineresources)_ | CurrentResources shows the current resource allocation |  | Optional: \{\} <br /> |
| `snapshots` _[VMSnapshotInfo](#vmsnapshotinfo) array_ | Snapshots lists available snapshots for this VM. Not populated in this<br />release; list the VMSnapshot objects whose spec.vmRef names the VM instead. |  | Optional: \{\} <br /> |
| `phase` _[VirtualMachinePhase](#virtualmachinephase)_ | Phase is the VM's phase, derived by the controller from the rest of its<br />status on every status write (never set by hand): Pending (not created<br />yet: waiting for its Provider, class, image or placement), Provisioning<br />(a create is requested or in flight, or its outcome is not known),<br />Running or Stopped (by status.powerState; a suspended VM counts as<br />Running), Reconfiguring (a resize is in flight), Deleting (the VM is<br />being deleted, also while the delete is held) and Failed (a hold that<br />needs an operator, such as VMNotOwned, OwnerStampUnreadable,<br />ConsumerNotAllowed or CreateOutcomeUnknown; a create the provider<br />refused; or a power state the provider cannot classify). The Ready<br />condition's reason says why. |  | Enum: [Pending Provisioning Running Stopped Reconfiguring Deleting Failed] <br />Optional: \{\} <br /> |
| `message` _string_ | Message provides additional details about the current state |  | Optional: \{\} <br /> |
| `placement` _[PlacementStatus](#placementstatus)_ | Placement records where the scheduler of a clustered Provider<br />(spec.topology=cluster) bound this VM. It is the durable record of which<br />host runs the VM. The operator writes the host only after the provider<br />confirms the VM is on it (create success), never speculatively. Empty for<br />VMs on single-host Providers, which have no operator-owned placement<br />decision. |  | Optional: \{\} <br /> |
| `boundProvider` _[BoundProviderRef](#boundproviderref)_ | BoundProvider records the Provider this VM was bound through: the one<br />whose hypervisor assigned status.id (or, for a clustered create in<br />flight, the one status.placement.pendingHost belongs to). The operator<br />writes it in the same status write that binds the VM (VM create, clone,<br />adoption) and, for a VM bound before this field existed, backfills it on<br />the first reconcile from spec.providerRef. While the VM is bound, the<br />operator makes no provider call for it — and its finalizer does not<br />delete through a Provider — unless spec.providerRef still resolves to<br />this Provider (same namespace and name and, when recorded, UID);<br />otherwise the VM reports Ready=False/ProviderRefMismatch. A<br />deliberately re-created Provider (new UID) is re-accepted by an<br />administrator clearing this field through the status subresource. |  | Optional: \{\} <br /> |
| `snapshotRevert` _[SnapshotRevertStatus](#snapshotrevertstatus)_ | SnapshotRevert records the revert spec.snapshot.revertToRef requests:<br />the VMSnapshot it is for (name and UID), its phase and outcome. While<br />it records Succeeded or Failed for the VMSnapshot the field names,<br />nothing is sent again. Cleared when spec.snapshot.revertToRef is<br />removed. Written only by the operator. |  | Optional: \{\} <br /> |


#### WeightedVMAffinityTerm



WeightedVMAffinityTerm defines a weighted VM affinity term.



_Appears in:_
- [VMAffinity](#vmaffinity)
- [VMAntiAffinity](#vmantiaffinity)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `weight` _integer_ | Weight is added to (affinity) or subtracted from (anti-affinity) the rank<br />of a Host that runs a VM matching the term. |  | Maximum: 100 <br />Minimum: 1 <br /> |
| `vmAffinityTerm` _[VMAffinityTerm](#vmaffinityterm)_ | VMAffinityTerm defines the VM affinity term |  |  |


#### ZoneAffinityRule



ZoneAffinityRule defines zone affinity rules. Accepted but not acted on in
this release.



_Appears in:_
- [AffinityRules](#affinityrules)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled indicates if zone affinity is enabled. Accepted but not acted on<br />in this release. |  |  |
| `preferredZones` _string array_ | PreferredZones lists preferred zones. Accepted but not acted on in this<br />release. |  | MaxItems: 10 <br />Optional: \{\} <br /> |
| `scope` _string_ | Scope defines the scope of the affinity rule. Accepted but not acted on in<br />this release. |  | Enum: [strict preferred] <br />Optional: \{\} <br /> |


#### ZoneAntiAffinityRule



ZoneAntiAffinityRule defines zone anti-affinity rules. Accepted but not
acted on in this release.



_Appears in:_
- [AntiAffinityRules](#antiaffinityrules)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled indicates if zone anti-affinity is enabled. Accepted but not acted<br />on in this release. |  |  |
| `maxVMsPerZone` _integer_ | MaxVMsPerZone limits the number of VMs per zone. Accepted but not acted on<br />in this release. |  | Maximum: 10000 <br />Minimum: 1 <br />Optional: \{\} <br /> |
| `scope` _string_ | Scope defines the scope of the anti-affinity rule. Accepted but not acted<br />on in this release. |  | Enum: [strict preferred] <br />Optional: \{\} <br /> |


