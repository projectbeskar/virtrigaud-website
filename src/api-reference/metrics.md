<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Metrics Reference

Pure catalog of all `virtrigaud_*` metric families. For operator interpretation, PromQL examples, alerting recipes, and wiring details see the [Observability Guide](../operations/observability.md).

All metrics are registered with controller-runtime's metrics registry and served on **`:8080/metrics`** alongside the standard `workqueue_*`, `go_*`, and `process_*` families.

---

## Stable families (v0.3.8)

### `virtrigaud_build_info`

| Property | Value |
|---|---|
| Type | Gauge |
| Help | `Build information for virtrigaud components` |
| Labels | `version`, `git_sha`, `go_version`, `component` |
| Value | Always `1` |
| Stable since | v0.3.0 |

Label notes:

- `component`: `manager` for the manager process; `provider` for provider sidecars that call `SetupMetrics`.
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

`kind` values (as of v0.3.8): `VirtualMachine`, `Provider`, `VMClass`, `VMImage`, `VMNetworkAttachment`, `VMAdoption`, `VMSnapshot`, `VMMigration`, `VMClone`, `VMSet`, `VMPlacementPolicy`.

Note: `VMClone` and `VMSet` series are seeded to `0` at manager startup even before any resources of those kinds exist. The `VMSet` reconciler is a stub in v0.3.8; it emits `outcome="error"` for every reconcile until the controller is implemented.

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

`component` values: `manager`, `provider`.

`reason` is a small enum defined per-reconciler via `errReason*` constants. Taxonomy as of v0.3.8 for the VirtualMachine reconciler: `get-vm`, `add-finalizer`, `remove-finalizer`, `deps-not-found`, `deps-error`, `provider-resolve`, `provider-validate`, `provider-describe`, `provider-task-status`, `provider-delete`. The VMClone reconciler adds: `get-clone`, `source-resolve`, `clone-target-exists`, `provider-clone`. Other reconcilers define their own reason sets.

---

### `virtrigaud_provider_rpc_requests_total`

| Property | Value |
|---|---|
| Type | Counter |
| Help | `Total number of provider RPC requests by provider type, method, and code` |
| Labels | `provider_type`, `method`, `code` |
| Stable since | v0.3.5 (G4 / PR #107) |

`provider_type`: the value of `Provider.spec.type` (e.g. `vsphere`, `libvirt`, `proxmox`, `mock`).

`method`: short RPC name extracted from the gRPC full method path (e.g. `Validate`, `Create`, `Delete`, `Power`, `Describe`, `Reconfigure`, `TaskStatus`, `ListVMs`, `SnapshotCreate`, `SnapshotDelete`, `SnapshotRevert`, `ExportDisk`, `ImportDisk`, `GetDiskInfo`).

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

`provider`: the `metadata.name` of the `Provider` CR. Seeded to `0` at manager startup when the gRPC client is constructed. One time-series per Provider CR.

---

### `virtrigaud_circuit_breaker_failures_total`

| Property | Value |
|---|---|
| Type | Counter |
| Help | `Total number of circuit breaker failures` |
| Labels | `provider_type`, `provider` |
| Added | v0.3.6 (G6 / PR #111) |

Counts infra-class RPC failures (`Unavailable`, `DeadlineExceeded`, `Internal`, `Unknown`) that are counted toward the circuit breaker's failure threshold. Business-class errors (`NotFound`, `InvalidArgument`, etc.) do not increment this counter.

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

`provider`: the `metadata.name` of the `Provider` CR (the `providerName` passed to `NewClient`).

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

Counts tasks the current manager instance is actively tracking (in its in-memory set). Seeded to `0` at manager startup. Measures "tasks THIS manager instance is tracking", not "tasks the provider believes are in-flight" — the gauge resets on manager restart.

Task-creating RPCs: `Create`, `Delete`, `Power`, `Reconfigure`, `SnapshotCreate`, `SnapshotDelete`, `SnapshotRevert`, `ExportDisk`, `ImportDisk` (9 methods). Tasks are removed from the set when `IsTaskComplete` or `TaskStatus` observes `Done=true` or a terminal error.

---

## Deprecated families

### `virtrigaud_queue_depth`

| Property | Value |
|---|---|
| Type | Gauge |
| Help | `[DEPRECATED v0.3.6 — use controller-runtime's workqueue_depth{name} instead. See CHANGELOG.] Current depth of work queue by kind.` |
| Labels | `kind` |
| Deprecated in | v0.3.6 (G7.4 / PR #131) |
| Removal scheduled | v0.4.0 or later |

Superseded by controller-runtime's standard `workqueue_depth{name}` metric. The Go variable and `SetQueueDepth` helper remain for compile compatibility with out-of-tree code that imported the metrics package; production code no longer calls `SetQueueDepth`.

Migration: see the kind → controller-name mapping table in the [Upgrade Guide](../operations/upgrade.md).

---

## Standard families (controller-runtime + Go runtime)

These appear on the same `/metrics` endpoint. Documented upstream; listed here for completeness.

| Family prefix | Source | Notes |
|---|---|---|
| `workqueue_*` | controller-runtime | 9 families; per-reconciler depth, latency, retries. Present since v0.3.0. |
| `go_*` | Go runtime | Goroutine count, GC pauses, memory stats |
| `process_*` | Go runtime | CPU, RSS, file descriptor count |
| `controller_runtime_*` | controller-runtime | Webhook admission metrics, active workers |
