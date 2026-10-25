<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Metrics Reference

Pure catalog of all `virtrigaud_*` metric families as of v0.4.0. For operator interpretation, PromQL examples, alerting recipes, and wiring details see the [Observability Guide](../operations/observability.md).

All metrics are registered with controller-runtime's metrics registry. Two kinds of process serve it:

- **The manager** serves it on `--metrics-bind-address` (default `:8080`; the chart sets `0.0.0.0:8080`) at `/metrics`, alongside the standard `workqueue_*`, `go_*`, and `process_*` families. The endpoint is plain HTTP unless the manager runs with `--metrics-secure=true` (default `false`).
- **The vSphere, libvirt and Proxmox provider pods** serve the same registry at `/metrics` on their health port (`8080`). The mock provider does not serve `/metrics`. Only the families marked *provider* in the table below are ever written in a provider process; the other `virtrigaud_*` families are manager-only.

| Family | Exposed by | Added |
|---|---|---|
| `virtrigaud_build_info` | manager | v0.3.0 |
| `virtrigaud_manager_reconcile_total` | manager | v0.3.0 |
| `virtrigaud_manager_reconcile_duration_seconds` | manager | v0.3.0 |
| `virtrigaud_errors_total` | manager | v0.3.0 |
| `virtrigaud_provider_rpc_requests_total` | manager | v0.3.5 |
| `virtrigaud_provider_rpc_latency_seconds` | manager | v0.3.5 |
| `virtrigaud_circuit_breaker_state` | manager | v0.3.6 |
| `virtrigaud_circuit_breaker_failures_total` | manager | v0.3.6 |
| `virtrigaud_vm_operations_total` | manager | v0.3.6 |
| `virtrigaud_ip_discovery_duration_seconds` | manager | v0.3.6 |
| `virtrigaud_provider_tasks_inflight` | manager | v0.3.6 |
| `virtrigaud_manager_vm_crd_security_features` | manager | v0.4.0 |
| `virtrigaud_host_committed_cpu` | manager | v0.4.0 |
| `virtrigaud_host_committed_memory_mib` | manager | v0.4.0 |
| `virtrigaud_image_prepare_artifact_total` | manager | v0.4.0 |
| `virtrigaud_provider_image_prepare_legacy_requests_total` | provider | v0.4.0 |
| `virtrigaud_provider_host_guard_refusals_total` | provider (libvirt) | v0.4.0 |
| `virtrigaud_libvirt_shadow_divergence_total` | provider (libvirt) | v0.4.0 |
| `virtrigaud_libvirt_shadow_compare_total` | provider (libvirt) | v0.4.0 |
| `virtrigaud_libvirt_active_driver` | provider (libvirt) | v0.4.0 |
| `virtrigaud_queue_depth` (deprecated) | manager (no series emitted) | v0.3.0 or earlier |

!!! note "Provider-side `build_info`"
    `virtrigaud_build_info` is written only by the manager (`component="manager"`). Provider processes do not call `SetupMetrics`, so no `component="provider"` series exists in v0.4.0, and `virtrigaud_errors_total` is likewise only written with `component="manager"`.

---

## Manager families

### `virtrigaud_build_info`

| Property | Value |
|---|---|
| Type | Gauge |
| Help | `Build information for virtrigaud components` |
| Labels | `version`, `git_sha`, `go_version`, `component` |
| Value | Always `1` |
| Stable since | v0.3.0 |

Label notes:

- `component`: `manager` for the manager process. The label value `provider` is defined by the metrics package but no provider process sets it in v0.4.0.
- `go_version`: the Go runtime version string returned by `runtime.Version()` (e.g. `go1.26.0`).

---

### `virtrigaud_manager_reconcile_total`

| Property | Value |
|---|---|
| Type | Counter |
| Help | `Total number of reconcile operations by kind and outcome` |
| Labels | `kind`, `outcome` |
| Stable since | v0.3.0 |

`outcome` values: `success`, `error`, `requeue`.

`kind` values (as of v0.4.0): `VirtualMachine`, `Provider`, `VMClass`, `VMImage`, `VMNetworkAttachment`, `VMAdoption`, `VMSnapshot`, `VMMigration`, `VMClone`, `VMSet`, `Host`, `HostPool`. `Host` and `HostPool` are new in v0.4.0 (clustered libvirt providers). There is no `VMPlacementPolicy` kind: that resource has no reconciler.

A series appears only after its first reconcile; the families are not pre-seeded at manager startup. The `VMSet` reconciler is a stub: it reports a `ControllerNotImplemented` condition and returns success, so it emits `outcome="success"` (an `error` only if reading or updating the VMSet fails).

---

### `virtrigaud_manager_reconcile_duration_seconds`

| Property | Value |
|---|---|
| Type | Histogram |
| Help | `Duration of reconcile operations by kind` |
| Labels | `kind` |
| Buckets | Exponential: 1ms, 2ms, 4ms, 8ms, 16ms, 32ms, 64ms, 128ms, 256ms, 512ms, 1.024s, 2.048s, 4.096s, 8.192s, 16.384s (15 buckets, `prometheus.ExponentialBuckets(0.001, 2, 15)`) |
| Stable since | v0.3.0 |

---

### `virtrigaud_errors_total`

| Property | Value |
|---|---|
| Type | Counter |
| Help | `Total number of errors by reason and component` |
| Labels | `reason`, `component` |
| Stable since | v0.3.0 |

`component` values: `manager` in practice (see the note above).

`reason` is a small enum defined per-reconciler via `errReason*` constants. Reasons in v0.4.0, by area:

| Area | `reason` values |
|---|---|
| VirtualMachine | `get-vm`, `add-finalizer`, `remove-finalizer`, `deps-not-found`, `deps-error`, `provider-resolve`, `provider-describe`, `provider-task-status`, `provider-delete`, `provider-power`, `provider-reconfigure`, `provider-create-rejected`, `provider-create-backoff`, `image-prepare` |
| VirtualMachine, clustered and ownership | `placement`, `restore-pending`, `preschedule-check`, `provider-ref-mismatch`, `provider-deleting`, `provider-snapshot-revert`, `vm-not-owned`, `vm-is-image-artifact`, `owner-stamp-unreadable`, `orphan-not-allowed`, `force-delete-not-allowed`, `consumer-not-allowed`, `disk-size-limit`, `migration-not-found` |
| Provider outcome unknown | `provider-outcome-unknown`, `create-outcome-unknown`, `clone-outcome-unknown` |
| VMClone | `get-clone`, `provider-clone-rejected` |
| VMSnapshot | `get-snapshot` |
| VMMigration | `get-migration`, `migration-storage-discovery-failed` |
| VMAdoption | `adoption-discover-failed`, `adoption-invalid-filter`, `adoption-capabilities`, `adoption-status-update`, `adoption-owner-transfer` |
| Provider | `get-provider`, `provider-finalizer`, `provider-in-use-check`, `cleanup-failed`, `runtime-spec-invalid`, `tls-not-configured`, `service-reconcile-failed`, `serviceaccount-reconcile-failed`, `deployment-reconcile-failed`, `hostinventory-reconcile-failed` |
| Host and HostPool | `host-get`, `host-finalizer`, `host-provider-resolve`, `host-get-info`, `host-status-update`, `hostpool-get`, `hostpool-list-hosts`, `hostpool-status-update` |
| VMSet | `get-vmset` |
| CRD check | `vm-crd-security-features-missing` |

The set grows with the reconcilers; treat it as open-ended and alert on rates rather than on specific values.

---

### `virtrigaud_provider_rpc_requests_total`

| Property | Value |
|---|---|
| Type | Counter |
| Help | `Total number of provider RPC requests by provider type, method, and code` |
| Labels | `provider_type`, `method`, `code` |
| Stable since | v0.3.5 (G4 / PR #107) |

`provider_type`: the value of `Provider.spec.type` (e.g. `vsphere`, `libvirt`, `proxmox`, `mock`).

`method`: short RPC name extracted from the gRPC full method path. Any RPC of the `Provider` service can appear, for example `Validate`, `Create`, `Delete`, `Power`, `Reconfigure`, `HardwareUpgrade`, `Describe`, `TaskStatus`, `SnapshotCreate`, `SnapshotDelete`, `SnapshotRevert`, `Clone`, `ImagePrepare`, `GetCapabilities`, `ExportDisk`, `ImportDisk`, `GetDiskInfo`, `DeleteStagedDisk`, `DeleteLandedDisk`, `ListVMs`, `TransferOwner`, `ListHosts`, `GetHostInfo`.

`code`: stringified gRPC status code from `codes.Code.String()`. Common values: `OK`, `Unavailable`, `DeadlineExceeded`, `NotFound`, `InvalidArgument`, `Internal`, `Unknown`. Circuit-breaker rejections appear as `Unavailable`.

---

### `virtrigaud_provider_rpc_latency_seconds`

| Property | Value |
|---|---|
| Type | Histogram |
| Help | `Latency of provider RPC requests by provider type and method` |
| Labels | `provider_type`, `method` |
| Buckets | Exponential: 1ms to ~32s (15 buckets, `prometheus.ExponentialBuckets(0.001, 2, 15)`) |
| Stable since | v0.3.5 (G4 / PR #107) |

---

### `virtrigaud_circuit_breaker_state`

| Property | Value |
|---|---|
| Type | Gauge |
| Help | `Circuit breaker state (0=closed, 1=half-open, 2=open)` |
| Labels | `provider_type`, `provider` |
| Values | `0` = Closed, `1` = HalfOpen, `2` = Open |
| Added | v0.3.6 (G6 / PR #111) |

`provider`: the `metadata.name` of the `Provider` CR (not namespace-qualified). Set to `0` (closed) when the manager first creates the breaker for a Provider, that is, when it first builds a gRPC client for it. One time-series per Provider CR.

---

### `virtrigaud_circuit_breaker_failures_total`

| Property | Value |
|---|---|
| Type | Counter |
| Help | `Total number of circuit breaker failures` |
| Labels | `provider_type`, `provider` |
| Added | v0.3.6 (G6 / PR #111) |

Counts infra-class RPC failures (`Unavailable`, `DeadlineExceeded`, `Internal`, `Unknown`) that are counted toward the circuit breaker's failure threshold. Business-class errors (`NotFound`, `InvalidArgument`, etc.) do not increment this counter.

Since v0.4.0, some infra-class codes are also excluded because the provider answered and is healthy: a clustered provider's host-scoped `Unavailable` (one host unknown, draining or unreachable), a per-VM operation that failed on its host, a per-VM operation the provider declined because its disk-dependency check could not run, a call whose outcome the provider could not determine after its host stopped answering, and an `ImagePrepare` answered as in progress or as source unavailable. One dead host therefore cannot open the breaker for every VM of the Provider.

---

### `virtrigaud_vm_operations_total`

| Property | Value |
|---|---|
| Type | Counter |
| Help | `Total number of VM operations by operation, provider type, provider, and outcome` |
| Labels | `operation`, `provider_type`, `provider`, `outcome` |
| Added | v0.3.6 (G7.1 / PR #124) |

`operation` values: `Create`, `Delete`, `Power`, `Describe`, `Reconfigure`.

`outcome` values: `success`, `error`.

`provider`: the `metadata.name` of the `Provider` CR (not namespace-qualified).

One sample per VM operation method call (not per RPC — a Create that emits multiple TaskStatus polls still produces one sample here).

---

### `virtrigaud_ip_discovery_duration_seconds`

| Property | Value |
|---|---|
| Type | Histogram |
| Help | `Duration of IP discovery operations by provider type` |
| Labels | `provider_type` |
| Buckets | Exponential: 100ms, 200ms, 400ms, 800ms, 1.6s, 3.2s, 6.4s, 12.8s, 25.6s, 51.2s (10 buckets, `prometheus.ExponentialBuckets(0.1, 2, 10)`) |
| Added | v0.3.6 (G7.2 / PR #127) |

Duration measured from `vm.CreationTimestamp` to the first reconcile where `vm.Status.IPs` transitions from empty to non-empty. Emits exactly one sample per VM over its lifetime (idempotent across manager restarts via etcd persistence).

---

### `virtrigaud_provider_tasks_inflight`

| Property | Value |
|---|---|
| Type | Gauge |
| Help | `Number of inflight tasks by provider type and provider` |
| Labels | `provider_type`, `provider` |
| Added | v0.3.6 (G7.3 / PR #129) |

Counts tasks the current manager instance is actively tracking (in its in-memory set). Set to `0` when the gRPC client for a Provider is created. Measures "tasks THIS manager instance is tracking", not "tasks the provider believes are in-flight" — the gauge resets on manager restart.

Task-creating RPCs: `Create`, `Delete`, `Power`, `Reconfigure`, `Clone`, `ImagePrepare`, `SnapshotCreate`, `SnapshotDelete`, `SnapshotRevert`, `ExportDisk`, `ImportDisk` (11 methods). Tasks are removed from the set when `IsTaskComplete` or `TaskStatus` observes `Done=true` or a terminal error.

---

### `virtrigaud_manager_vm_crd_security_features`

| Property | Value |
|---|---|
| Type | Gauge |
| Help | `Whether the installed CRDs have the security features the manager relies on (VirtualMachine status.boundProvider and spec.providerRef immutability rule; spec.consumerNamespaceSelector on Provider, VMClass and VMImage; VMImage status.providerStatus[].providerUID, taskRef and sourceDigest; Provider status.reportedCapabilities.supportsImageArtifactIdentity): 1 for the current state (verified\|missing\|unknown), 0 otherwise.` |
| Labels | `state` |
| Exposed by | manager |
| Added | v0.4.0 |

`state` values: `verified` (the installed CRDs carry every feature the manager needs), `missing` (at least one CRD is older than the manager), `unknown` (a CRD could not be read, for example because RBAC forbids it). Exactly one of the three series is `1`; the others are `0`. The check result is cached for one minute. In the `missing` state the manager also increments `virtrigaud_errors_total{reason="vm-crd-security-features-missing"}` and its readiness check fails until the CRDs are upgraded.

---

### `virtrigaud_host_committed_cpu`

| Property | Value |
|---|---|
| Type | Gauge |
| Help | `vCPUs committed to a clustered Provider's Host by the VirtualMachines bound to or pending on it (the scheduler's committed capacity), by provider (namespace/name) and host.` |
| Labels | `provider`, `host` |
| Exposed by | manager |
| Added | v0.4.0 |

`provider` is the namespace-qualified Provider (`namespace/name`); `host` is the `Host` resource name. One series per Host of a clustered Provider, refreshed by the Host controller on every Host sync (about once a minute) and removed when the Host is deleted or moved to another Provider.

---

### `virtrigaud_host_committed_memory_mib`

| Property | Value |
|---|---|
| Type | Gauge |
| Help | `Memory in MiB committed to a clustered Provider's Host by the VirtualMachines bound to or pending on it (the scheduler's committed capacity), by provider (namespace/name) and host.` |
| Labels | `provider`, `host` |
| Exposed by | manager |
| Added | v0.4.0 |

Same semantics, labels and lifecycle as `virtrigaud_host_committed_cpu`, in MiB. These two gauges are cross-tenant administrator signals (they show how full each host is); restrict who can scrape the manager's `/metrics` (NetworkPolicy, or `--metrics-secure`). See [Clustered provider inventory](https://github.com/projectbeskar/virtrigaud/blob/main/docs/clustered-provider-inventory.md) in the main repository for how the scheduler uses committed capacity.

---

### `virtrigaud_image_prepare_artifact_total`

| Property | Value |
|---|---|
| Type | Counter |
| Help | `Total identity ImagePrepare outcomes observed by the manager (created, reused, in_progress, conflict), by provider type (ADR-0009).` |
| Labels | `provider_type`, `outcome` |
| Exposed by | manager |
| Added | v0.4.0 |

`outcome` values recorded by the manager: `created` (the provider started or completed a new import), `reused` (an existing artifact with a matching identity stamp was reused), `in_progress` (the artifact is still being prepared for the requesting VMImage by another request; a retryable answer), `conflict` (an artifact at the derived name was not prepared for the requesting VMImage; the provider refused to use or replace it). A rising `conflict` count needs an administrator. The constant `abandoned_cleanup` is reserved and never recorded.

---

### `virtrigaud_provider_image_prepare_legacy_requests_total`

| Property | Value |
|---|---|
| Type | Counter |
| Help | `Total ImagePrepare requests without an image identity (from a manager older than ADR-0009), served in deprecated legacy mode or refused, by provider type. Non-zero means a manager must be upgraded.` |
| Labels | `provider_type` |
| Exposed by | provider (vSphere, libvirt, Proxmox) |
| Added | v0.4.0 |

Incremented once per `ImagePrepare` request that carries no image identity, that is, a request from a manager older than v0.4.0. Each such request is also logged at WARN. Any non-zero value means the manager must be upgraded to match the provider.

---

### `virtrigaud_provider_host_guard_refusals_total`

| Property | Value |
|---|---|
| Type | Counter |
| Help | `Long routed host commands the host guard refused to run (an unsafe lock directory, or a symlinked lock or target), by provider type and reason. Any increment needs an administrator's attention.` |
| Labels | `provider_type`, `reason` |
| Exposed by | provider (libvirt) |
| Added | v0.4.0 |

`reason` values: `lock_dir_unsafe` (the provider's lock directory on the host is a symbolic link, not a directory, or not owned by the SSH user), `lock_symlink` (a lock file is a symbolic link), `target_symlink` (the file a command writes, such as a clone's disk or an export's copy, is a symbolic link), `unknown`. There is no host, path or tenant label. Any increment means a host path VirtRigaud writes to was tampered with or pre-created by another local user.

---

### `virtrigaud_libvirt_shadow_divergence_total`

| Property | Value |
|---|---|
| Type | Counter |
| Help | `Total semantic divergences between the virsh (authoritative) and go-libvirt (shadow) libvirt drivers, by operation family and field. The ADR-0008 D5 flip-gate metric; PR 5 requires this at 0 across the soak window before flipping a read family to native.` |
| Labels | `family`, `field` |
| Exposed by | provider (libvirt) |
| Added | v0.4.0 |

`family` values: `describe`, `list`. `field` is the name of the diverging field. Only populated when shadow reads are enabled with `VIRTRIGAUD_LIBVIRT_NATIVE`; see [Libvirt shadow reads](https://github.com/projectbeskar/virtrigaud/blob/main/docs/libvirt-shadow-reads.md) in the main repository.

---

### `virtrigaud_libvirt_shadow_compare_total`

| Property | Value |
|---|---|
| Type | Counter |
| Help | `Total libvirt shadow-compare read runs by family and result (equal\|divergent\|error\|panic). Denominator for the divergence rate and proof the shadow harness is running (ADR-0008 D5).` |
| Labels | `family`, `result` |
| Exposed by | provider (libvirt) |
| Added | v0.4.0 |

`result` values: `equal`, `divergent`, `error`, `panic`. `error` and `panic` are shadow-path failures that were recovered and metered; the caller always received the authoritative virsh answer.

---

### `virtrigaud_libvirt_active_driver`

| Property | Value |
|---|---|
| Type | Gauge |
| Help | `Effective libvirt driver per operation family: 1 for the active driver (virsh\|shadow\|native), 0 otherwise. ADR-0008 D4 audit signal (read-only, non-API-committing).` |
| Labels | `family`, `driver` |
| Exposed by | provider (libvirt) |
| Added | v0.4.0 |

`family` values: `describe`, `list`. `driver` values: `virsh` (authoritative subprocess driver), `shadow` (both drivers run, virsh's answer is returned), `native`. Each family has exactly one series at `1`. In v0.4.0 a family configured `native` runs as `shadow`, and the metric reports what is actually running.

---

## Deprecated families

### `virtrigaud_queue_depth`

| Property | Value |
|---|---|
| Type | Gauge |
| Help | `[DEPRECATED v0.3.6 — use controller-runtime's workqueue_depth{name} instead. See CHANGELOG.] Current depth of work queue by kind.` |
| Labels | `kind` |
| Deprecated in | v0.3.6 (G7.4 / PR #131) |
| Status in v0.4.0 | Still registered; not removed |

Superseded by controller-runtime's standard `workqueue_depth{name}` metric. The family is still registered in v0.4.0, but the Go variable and `SetQueueDepth` helper remain only for compile compatibility with out-of-tree code: production code never calls `SetQueueDepth`, so no `virtrigaud_queue_depth` series is emitted and the family does not appear in `/metrics` output. It will be removed in a later release.

Migration: see the kind → controller-name mapping table in the [Upgrade Guide](../operations/upgrade.md).

---

## Standard families (controller-runtime + Go runtime)

These appear on the same `/metrics` endpoint. Documented upstream; listed here for completeness.

| Family prefix | Source | Notes |
|---|---|---|
| `workqueue_*` | controller-runtime | Per-reconciler depth, latency, retries. Present since v0.3.0. Manager only. |
| `go_*` | Go runtime | Goroutine count, GC pauses, memory stats |
| `process_*` | Go runtime | CPU, RSS, file descriptor count |
| `controller_runtime_*` | controller-runtime | Webhook admission metrics, active workers. Manager only. |
