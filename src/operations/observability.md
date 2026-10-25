<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Observability Guide

This is the operator's guide to what VirtRigaud **v0.4.0** emits, what it means, and how to build dashboards and alerts from it. For the machine-readable catalog (exact help strings, label sets, histogram buckets) see the [Metrics Reference](../api-reference/metrics.md). For circuit-breaker lifecycle details and the semantics of provider calls whose outcome is unknown see [Resilience](resilience.md). For migration recipes from v0.3.5 metrics see [Upgrade Guide](upgrade.md).

!!! note "Metrics are only part of the signal"
    Several v0.4.0 behaviours that matter operationally have **no metric**: held provider calls (`...OutcomeUnknown`), `DeleteBlocked`, restore holds, placement decisions and `HostPool` health. They are reported as **status conditions and Events** on the objects themselves; see [Status conditions and events worth alerting on](#status-conditions-and-events-worth-alerting-on). Alert on those through `kube-state-metrics` custom-resource state metrics (or your own exporter), not through `virtrigaud_*`.

## What VirtRigaud emits

VirtRigaud serves Prometheus metrics from **two kinds of process**:

| Endpoint | Process | Default | What is on it |
|---|---|---|---|
| `:8080/metrics` on the **manager** | The manager Deployment | Plain HTTP. `--metrics-secure=true` switches the same port to HTTPS with Kubernetes authn/authz (see [Securing the manager endpoint](#securing-the-manager-endpoint)) | Every `virtrigaud_*` family except the five that are emitted inside provider processes (below), plus `workqueue_*`, `controller_runtime_*`, `go_*` and `process_*`. |
| `:8080/metrics` on each **provider pod** | The Deployment the manager creates for each `Provider` (libvirt, vSphere and Proxmox providers) | Plain HTTP, on the provider's health port (`--health-port`, default `8080`); the provider `Service` exposes it as port `metrics` | The `virtrigaud_*` families that are emitted by provider code: [`virtrigaud_provider_host_guard_refusals_total`](#provider-process-metrics), [`virtrigaud_provider_image_prepare_legacy_requests_total`](#provider-process-metrics) and the three [libvirt driver-transition metrics](#libvirt-driver-transition-metrics), plus `go_*` and `process_*`. |

The chart's `ServiceMonitor` and `PrometheusRule` cover the **manager** only. To scrape provider pods, add a `ServiceMonitor` or `PodMonitor` of your own that selects the `metrics` port of the provider `Service` (labels `app.kubernetes.io/component: provider`, `app.kubernetes.io/managed-by: virtrigaud`). Provider pods do not carry `virtrigaud_build_info`, and the provider metrics endpoint is not authenticated.

Three families of metrics live on the manager endpoint:

| Family | Who owns it | Coverage |
|---|---|---|
| `virtrigaud_*` | VirtRigaud — described in this guide | See the catalog below. |
| `workqueue_*` and `controller_runtime_*` | controller-runtime standard metrics | Per-controller queue depth, latency and retries. The `workqueue_*` series are the supported replacement for the deprecated `virtrigaud_queue_depth`. |
| `go_*` / `process_*` | Go runtime | Memory, GC pauses, goroutine count, file descriptors, etc. |

---

## The `virtrigaud_*` catalog (v0.4.0)

Metrics 1 to 11 are unchanged in name and labels since v0.3.8 (new `kind` and `reason` values are noted). Metrics 12 to 14, the provider-process metrics and the libvirt driver-transition metrics are new in v0.4.0.

### 1. `virtrigaud_build_info`

**Type:** Gauge  
**Labels:** `version`, `git_sha`, `go_version`, `component`  
**Value:** Always `1`.

Populated by `metrics.SetupMetrics()` at manager startup (manager only; provider pods do not emit it). Use it to confirm that the running process matches your expected version and git SHA without looking at pod annotations.

```promql
# Which build is running?
virtrigaud_build_info{component="manager"}
```

If this query returns nothing, the manager has not started successfully. The chart's `VirtRigaudManagerDown` alert is `absent(virtrigaud_build_info)` for 5 minutes.

---

### 2. `virtrigaud_manager_reconcile_total`

**Type:** Counter  
**Labels:** `kind`, `outcome`  
**`outcome` values:** `success`, `error`, `requeue`

Incremented once per reconcile run by every reconciler. The outcome is inferred from the named return values of the reconcile function via a deferred timer block — no manual instrumentation at each return site.

!!! note "`kind` values"
    The series carry one `kind` per controller: `VirtualMachine`, `Provider`, `VMClass`, `VMImage`, `VMNetworkAttachment`, `VMAdoption`, `VMMigration`, `VMSnapshot`, `VMClone`, `VMSet` and — new in v0.4.0, with the clustered-provider inventory — `Host` and `HostPool`. (`VMPlacementPolicy` is read by the scheduler and has no reconciler of its own.)

`requeue` means the reconciler explicitly requested a requeue without returning an error (e.g. waiting for a provider task to complete, or a held create being re-checked). `error` means an error was returned and controller-runtime will apply exponential backoff. `success` means the reconcile completed cleanly.

```promql
# Reconcile error rate across all kinds
sum by (kind) (rate(virtrigaud_manager_reconcile_total{outcome="error"}[5m]))

# Per-kind success/error breakdown
sum by (kind, outcome) (rate(virtrigaud_manager_reconcile_total[5m]))
```

**Alerting:** A sustained non-zero rate on `outcome="error"` for a specific `kind` suggests a bug or misconfiguration in that reconciler's path. The chart's `VirtRigaudHighReconcileErrorRate` alert fires above 20% errors for 15 minutes.

---

### 3. `virtrigaud_manager_reconcile_duration_seconds`

**Type:** Histogram  
**Labels:** `kind`  
**Buckets:** Exponential, 1ms to ~16s (15 buckets: 0.001 doubling)

Wall-clock time per reconcile run. Recorded alongside `virtrigaud_manager_reconcile_total`.

```promql
# 95th-percentile reconcile time for VirtualMachine
histogram_quantile(0.95,
  sum(rate(virtrigaud_manager_reconcile_duration_seconds_bucket{kind="VirtualMachine"}[5m]))
  by (le)
)
```

Reconciles that consistently run longer than ~5s suggest slow provider RPCs or stuck task polling. Correlate with `virtrigaud_provider_rpc_latency_seconds`.

---

### 4. `virtrigaud_errors_total`

**Type:** Counter  
**Labels:** `reason`, `component`

A typed error counter used to slice failures by root cause without scraping logs. The `component` label is always `manager` for errors emitted from reconcilers. `reason` is a short kebab-case constant defined per controller. Reasons you will meet most often:

| Reason | Meaning |
|---|---|
| `get-vm`, `get-provider`, `get-clone`, `get-migration`, `get-snapshot` | The object could not be read. |
| `deps-not-found`, `deps-error` | A `VMClass`, `VMImage` or `VMNetworkAttachment` the VM references is missing or could not be read. |
| `provider-resolve` | The `Provider` the VM references cannot be resolved, or its runtime is not `Running`. |
| `provider-describe`, `provider-task-status`, `provider-delete`, `provider-power`, `provider-reconfigure` | The provider call failed. |
| `provider-create-rejected`, `provider-clone-rejected` | The provider refused a create or clone (for example, a pre-existing VM it does not own: `ProviderConflict`). |
| `provider-create-backoff`, `create-outcome-unknown`, `provider-outcome-unknown`, `clone-outcome-unknown` | A create, clone, snapshot or migration call is being held or retried because its outcome is not known. See [Resilience](resilience.md#calls-whose-outcome-is-unknown). |
| `consumer-not-allowed` | A reference to a `Provider`, `VMClass` or `VMImage` in another namespace was refused because its `spec.consumerNamespaceSelector` does not select the referencing namespace. |
| `vm-not-owned`, `vm-is-image-artifact`, `owner-stamp-unreadable` | The ownership checks refused to act on a hypervisor VM. |
| `provider-ref-mismatch`, `provider-deleting`, `provider-in-use-check` | `spec.providerRef` no longer matches the bound Provider; the Provider is being deleted; the Provider in-use finalizer could not count its consumers. |
| `orphan-not-allowed`, `force-delete-not-allowed` | A `virtrigaud.io/orphan-on-delete` or `force-delete` annotation was not honoured. |
| `disk-size-limit` | A disk exceeded the administrator's limit (`manager.maxDiskSize`). |
| `restore-pending`, `placement`, `preschedule-check` | Clustered-provider holds: a restore guard, or a scheduling failure. |
| `image-prepare` | An image preparation call failed or was not confirmed. |
| `host-*`, `hostpool-*`, `host-provider-resolve` | Failures in the `Host` / `HostPool` controllers (reading, inventory sync, status update). |
| `vm-crd-security-features-missing` | The installed CRDs are older than the manager (see metric 12). |
| `tls-not-configured`, `runtime-spec-invalid`, `deployment-reconcile-failed`, `service-reconcile-failed`, `serviceaccount-reconcile-failed` | Provider runtime reconciliation failed. |

```promql
# Top-5 error reasons in the last 10 minutes
topk(5, sum by (reason) (rate(virtrigaud_errors_total{component="manager"}[10m])))

# Are any VMs failing because their Provider CR can't be resolved?
rate(virtrigaud_errors_total{reason="provider-resolve"}[5m])
```

Use this before opening the logs to triage whether a surge of errors is infrastructure (`provider-describe`, `provider-task-status`) or configuration (`deps-not-found`, `provider-resolve`, `consumer-not-allowed`). The list above is not exhaustive: the reason set grows with the controllers.

---

### 5. `virtrigaud_provider_rpc_requests_total`

**Type:** Counter  
**Labels:** `provider_type`, `method`, `code`  
**Wired since:** v0.3.5 (G4 / PR #107)

Every outbound gRPC RPC from the manager to a provider pod is counted here. `method` is the short RPC name (e.g. `Create`, `Delete`, `Power`, `Describe`, `TaskStatus`, `SnapshotCreate`, `ImagePrepare`, `ListVMs`, `ListHosts`). `code` is the canonical gRPC status code string from `codes.Code.String()` — `OK`, `Unavailable`, `DeadlineExceeded`, `NotFound`, `FailedPrecondition`, etc.

!!! important "Circuit-breaker rejections are visible here"
    The metrics interceptor runs *before* the circuit-breaker interceptor in the chain. Breaker fast-fails appear as `code="Unavailable"` — not as silent drops. If `virtrigaud_circuit_breaker_state` is 2 (Open) and `virtrigaud_provider_rpc_requests_total{code="Unavailable"}` is climbing, that is the breaker protecting the provider, not the provider itself refusing RPCs.

!!! warning "`Unavailable` is not always a failure of the provider"
    A clustered libvirt provider answers `Unavailable` (with a `HOST_UNAVAILABLE`, `VM_OPERATION_FAILED` or `VM_DISK_CHECK_FAILED` reason) when **one host** is unreachable or a check could not run. Those answers show up here as errors, but they do **not** count toward the circuit breaker, and the VM shows the cause in its conditions. See [Resilience](resilience.md#what-does-not-count-as-a-failure).

```promql
# Per-provider gRPC error rate
sum by (provider_type, code) (
  rate(virtrigaud_provider_rpc_requests_total{code!="OK"}[5m])
)

# Fraction of Describe RPCs that time out
rate(virtrigaud_provider_rpc_requests_total{method="Describe",code="DeadlineExceeded"}[5m])
  /
rate(virtrigaud_provider_rpc_requests_total{method="Describe"}[5m])
```

---

### 6. `virtrigaud_provider_rpc_latency_seconds`

**Type:** Histogram  
**Labels:** `provider_type`, `method`  
**Buckets:** Exponential, 1ms to ~16s (15 buckets: 0.001 doubling)  
**Wired since:** v0.3.5 (G4 / PR #107)

Wall-clock time for each outbound RPC, recorded by the same metrics interceptor as `virtrigaud_provider_rpc_requests_total`. Useful for detecting a degraded-but-not-failing provider (latency rising, error rate still low). The highest finite bucket is ~16s, so calls with long deadlines (`Create`, `ExportDisk`, `ImportDisk`) fall in `+Inf` when they run longer; use the per-RPC deadlines in [Resilience](resilience.md#timeouts) to interpret the tail.

```promql
# 99th-percentile Create latency per provider type
histogram_quantile(0.99,
  sum(rate(virtrigaud_provider_rpc_latency_seconds_bucket{method="Create"}[5m]))
  by (le, provider_type)
)
```

---

### 7. `virtrigaud_circuit_breaker_state`

**Type:** Gauge  
**Labels:** `provider_type`, `provider`  
**Values:** 0 = Closed, 1 = HalfOpen, 2 = Open  
**Added:** v0.3.6 (G6 / PR #111)

One time-series per `Provider` CR (labelled by the Provider's **name**; the namespace is not a label). The gauge is seeded to `0` (Closed) when the manager creates the breaker for a Provider, which happens the first time it builds a gRPC client for it — that is, once the Provider's runtime phase is `Running`. Breakers live for the life of the manager process; a manager restart starts every breaker Closed.

For the full circuit-breaker lifecycle (state machine, what counts as a failure, HalfOpen trial semantics) see [Resilience](resilience.md).

```yaml
# PrometheusRule fragment: any breaker open for 5 minutes
# (the chart's VirtRigaudProviderCircuitBreakerOpen alert does the same, at state == 2)
- alert: ProviderCircuitBreakerNotClosed
  expr: virtrigaud_circuit_breaker_state > 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Provider {{ $labels.provider }} circuit breaker is {{ $value }} (0=Closed,1=HalfOpen,2=Open)"
```

---

### 8. `virtrigaud_circuit_breaker_failures_total`

**Type:** Counter  
**Labels:** `provider_type`, `provider`  
**Added:** v0.3.6 (G6 / PR #111)

Incremented on every RPC failure that counts against the breaker (`Unavailable`, `DeadlineExceeded`, `Internal`, `Unknown`, minus the exclusions listed under [what does not count as a failure](resilience.md#what-does-not-count-as-a-failure)). Business errors (`NotFound`, `InvalidArgument`, `FailedPrecondition`, …) do not increment this counter — those indicate the provider is healthy and the request was refused.

The counter increments on every counted failure, not just on state transitions. This means it answers "how often is this provider failing at the infrastructure level?" independently of whether the breaker has tripped. The breaker trips after **10 consecutive** counted failures (a success resets the count).

```promql
# Rate of infra failures per provider
sum by (provider_type, provider) (rate(virtrigaud_circuit_breaker_failures_total[5m]))
```

---

### 9. `virtrigaud_vm_operations_total`

**Type:** Counter  
**Labels:** `operation`, `provider_type`, `provider`, `outcome`  
**`operation` values:** `Create`, `Delete`, `Power`, `Describe`, `Reconfigure`  
**`outcome` values:** `success`, `error`  
**Added:** v0.3.6 (G7.1 / PR #124)

Per-Provider VM operation outcome counter. Recorded via `defer c.recordVMOp(op, &retErr)` at the top of each of these five methods in the gRPC client. The `outcome` is inferred from the named return value at function exit — same pattern as the reconcile-level metrics. Other calls (`Clone`, `SnapshotCreate`, `ExportDisk`, `ImportDisk`, …) are visible only through metric 5.

This gives a higher-level view than `virtrigaud_provider_rpc_requests_total`: one Create operation may involve several RPCs (Create + repeated TaskStatus polls), but it produces exactly one sample here at the end. Note that a retried call (a held create, a re-checked `Describe` on an unreachable host) produces one sample per attempt.

```promql
# Per-Provider VM-op error rate
sum by (provider) (rate(virtrigaud_vm_operations_total{outcome="error"}[5m]))

# Create success rate for vsphere provider
rate(virtrigaud_vm_operations_total{operation="Create",provider_type="vsphere",outcome="success"}[5m])
  /
rate(virtrigaud_vm_operations_total{operation="Create",provider_type="vsphere"}[5m])
```

```yaml
- alert: VMOperationsErrorRateHigh
  expr: |
    sum by (provider) (rate(virtrigaud_vm_operations_total{outcome="error"}[5m]))
      /
    sum by (provider) (rate(virtrigaud_vm_operations_total[5m])) > 0.1
  for: 10m
  labels:
    severity: warning
```

---

### 10. `virtrigaud_ip_discovery_duration_seconds`

**Type:** Histogram  
**Labels:** `provider_type`  
**Buckets:** Exponential, 100ms to ~51s (10 buckets: 0.1 doubling)  
**Added:** v0.3.6 (G7.2 / PR #127)

Measures the wall-clock time from `kubectl apply` (specifically, `vm.CreationTimestamp`) to the moment the first IP address appears in `vm.Status.IPs`. This is the operator-visible SLO answer to "how long from create to first IP on this provider type?"

A single sample is emitted per VM on the no-IPs → has-IPs transition. The gate in `recordIPDiscoveryIfFirstSeen` requires: the current `vm.Status.IPs` is empty, the provider just returned at least one IP, and `vm.CreationTimestamp` is non-zero. Because `vm.Status.IPs` is persisted to etcd as soon as the gate fires, the metric is idempotent across manager restarts — a restart during the same VM's lifecycle will not emit a second sample.

Since v0.4.0, `status.ips` lists only routable addresses (loopback, link-local and multicast addresses are dropped), and an address that is dropped does not count as "has an IP" here. A libvirt guest on libvirt's NAT network now gets its DHCP lease reported without the guest agent; a guest on a host bridge needs the QEMU guest agent. See [`status.ips`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-status-ips.md).

```promql
# 95th-percentile IP discovery time for libvirt
histogram_quantile(0.95,
  sum(rate(virtrigaud_ip_discovery_duration_seconds_bucket{provider_type="libvirt"}[5m]))
  by (le)
)
```

!!! note "Adopted VMs"
    VMs created by the VMAdoption controller (watching `virtrigaud.io/adopt-vms: "true"` on Provider CRs) already have IPs at the moment their VirtualMachine CR is created. For those VMs the gate fires immediately and the duration will be very short. Filter by `provider_type` if you want to compare native-create latency vs adoption latency.

---

### 11. `virtrigaud_provider_tasks_inflight`

**Type:** Gauge  
**Labels:** `provider_type`, `provider`  
**Added:** v0.3.6 (G7.3 / PR #129)

Tracks how many async tasks the manager is currently monitoring for a given Provider CR. The gauge is seeded to `0` when the client for the Provider is built, so the Provider's row appears on `/metrics` immediately.

`trackTaskStart` is called in the 11 task-creating RPCs: `Create`, `Clone`, `ImagePrepare`, `Delete`, `Power`, `Reconfigure`, `SnapshotCreate`, `SnapshotDelete`, `SnapshotRevert`, `ExportDisk`, `ImportDisk`. `trackTaskDone` is called in `IsTaskComplete` and `TaskStatus` when the terminal state (Done or Error) is observed.

The gauge measures "tasks THIS manager instance is tracking." After a manager restart, the in-memory set starts empty, so the gauge resets to 0 even if the provider has tasks running from the previous instance. The reconciler will rediscover those tasks from the objects' task references and repopulate the set on the next reconcile cycle.

```promql
# Is any Provider accumulating tasks faster than it's completing them?
virtrigaud_provider_tasks_inflight > 5

# Task inflight count across all providers
sum by (provider) (virtrigaud_provider_tasks_inflight)
```

```yaml
- alert: ProviderTasksAccumulating
  expr: virtrigaud_provider_tasks_inflight > 5
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Provider {{ $labels.provider }} has {{ $value }} inflight tasks — possible task polling loop or provider wedge"
```

---

### 12. `virtrigaud_manager_vm_crd_security_features`

**Type:** Gauge  
**Labels:** `state`  
**`state` values:** `verified`, `missing`, `unknown`  
**Added:** v0.4.0

Whether the installed CRDs carry the fields the v0.4.0 security model relies on: the `VirtualMachine` provider binding (`status.boundProvider` and the `spec.providerRef` immutability rule), `spec.consumerNamespaceSelector` on `Provider`, `VMClass` and `VMImage`, and the per-Provider `VMImage` prepare state (`status.providerStatus[]`) and `Provider` `status.reportedCapabilities.supportsImageArtifactIdentity` that identity-safe image preparation needs. Exactly one of the three series is `1`:

- `verified` — every required field is present.
- `missing` — at least one installed CRD is older than the manager. The manager's **readiness probe fails** until the CRDs are upgraded, and each check adds one `virtrigaud_errors_total{reason="vm-crd-security-features-missing"}`.
- `unknown` — a CRD could not be read (for example, RBAC forbids it, or `rbac.scope=namespace`, where the manager cannot read CRDs); readiness is not affected.

```promql
# Manager is running against stale CRDs
virtrigaud_manager_vm_crd_security_features{state="missing"} == 1
```

After `helm upgrade`, apply the new CRDs **before** rolling the manager; see the [Upgrade Guide](upgrade.md).

---

### 13. `virtrigaud_image_prepare_artifact_total`

**Type:** Counter  
**Labels:** `provider_type`, `outcome`  
**`outcome` values:** `created`, `reused`, `in_progress`, `conflict`  
**Added:** v0.4.0 (ADR-0009)

The outcome of each identity-safe `ImagePrepare` call the manager issues: a new artifact was imported (`created`), an existing artifact whose stamp matches the `VMImage`'s UID and source digest was reused (`reused`), another request is still importing it (`in_progress`, retried), or an artifact at the derived name was **not** prepared for this `VMImage` (`conflict`). A rising `conflict` count means a file or template sits at the name VirtRigaud derived for an image and it will neither use nor replace it; an administrator has to investigate. The `VMImage` shows `ArtifactConflict` and a `Warning` event `ImageArtifactConflict`.

```promql
increase(virtrigaud_image_prepare_artifact_total{outcome="conflict"}[1h]) > 0
```

---

### 14. `virtrigaud_host_committed_cpu` and `virtrigaud_host_committed_memory_mib`

**Type:** Gauge (two families)  
**Labels:** `provider` (`<namespace>/<name>` of the clustered Provider), `host` (the `Host` object's name)  
**Added:** v0.4.0 (clustered libvirt providers)

The vCPUs and the memory (MiB) that the `VirtualMachine`s bound to, or pending on, a `Host` hold: the committed capacity the placement scheduler subtracts from the host's allocatable capacity. They are refreshed by the `Host` controller on every sync (about once a minute) and removed when the `Host` is deleted, so the series count is the number of `Host`s. Compare with `Host.status.allocatableCPU` / `allocatableMemoryMiB`. Alert suggestions, the host guard counter and how to read an unreachable host are in [Clustered libvirt: operations and troubleshooting](../guides/clustered/operations.md#metrics-and-alerts).

```promql
virtrigaud_host_committed_cpu{provider="virtrigaud-system/libvirt-cluster"}
```

---

### Provider-process metrics

These two families are emitted by provider code and appear on the **provider pods'** `/metrics`, not on the manager's.

#### `virtrigaud_provider_host_guard_refusals_total`

**Type:** Counter  
**Labels:** `provider_type`, `reason`  
**`reason` values:** `lock_dir_unsafe`, `lock_symlink`, `target_symlink`, `unknown`  
**Added:** v0.4.0

A long routed host command (a clone's disk copy, a disk export or import) was refused by the host guard: the provider's lock directory on the hypervisor host is a symbolic link, not a directory, or not owned by the SSH user, or a lock file or the file the command would write is a symbolic link. **Any increment needs an administrator's attention**: it means a path VirtRigaud writes to on the host was pre-created or tampered with by another local user.

#### `virtrigaud_provider_image_prepare_legacy_requests_total`

**Type:** Counter  
**Labels:** `provider_type`  
**Added:** v0.4.0 (ADR-0009)

`ImagePrepare` requests that arrived without an image identity, i.e. from a manager older than v0.4.0. Non-zero means a manager has to be upgraded: the bare-name reuse such requests allow is the cross-tenant artifact defect ADR-0009 closes. The metric is removed together with legacy mode.

---

### Libvirt driver-transition metrics

The libvirt provider is moving from `virsh` subprocess reads to a pure-Go `go-libvirt` client (ADR-0008). In v0.4.0 this is an **opt-in, behaviour-preserving shadow mode**: with `VIRTRIGAUD_LIBVIRT_NATIVE` unset (the default) go-libvirt is dormant and none of these series carry anything but the `virsh` driver. These three families are emitted by the **libvirt provider process** and read from the provider pod's `/metrics`:

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `virtrigaud_libvirt_active_driver` | Gauge | `family`, `driver` | The effective driver per read family (`describe`, `list`): `1` for the active driver (`virsh`, `shadow` or `native`), `0` for the others. A family configured `native` runs as `shadow` in v0.4.0 and reads `shadow`: the metric reports what is happening, not what was requested. |
| `virtrigaud_libvirt_shadow_compare_total` | Counter | `family`, `result` | Shadow-compare runs by result: `equal`, `divergent`, `error`, `panic`. The denominator for the divergence rate, and proof that the harness is running. `error` and `panic` are recovered; the caller always gets virsh's answer. |
| `virtrigaud_libvirt_shadow_divergence_total` | Counter | `family`, `field` | Semantic divergences between the two drivers, by field. This is the ADR-0008 flip-gate metric: a read family may flip to native only after it reads `0` over the soak window. |

Enable shadow mode per family through the Provider's `spec.runtime.env` (`VIRTRIGAUD_LIBVIRT_NATIVE=shadow:describe,shadow:list`); see [`libvirt-shadow-reads.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/libvirt-shadow-reads.md). Shadowing roughly doubles the work of each shadowed read. Read the divergence counter together with the compare counter: a divergence counter at `0` proves nothing unless `virtrigaud_libvirt_shadow_compare_total{result="equal"}` is rising.

---

## Deprecated: `virtrigaud_queue_depth`

**Deprecated in:** v0.3.6 (G7.4 / PR #131)  
**Removal:** not removed in v0.4.0; the helper is still compiled in and still registered  
**Help string:** `[DEPRECATED v0.3.6 — use controller-runtime's workqueue_depth{name} instead. See CHANGELOG.] Current depth of work queue by kind.`

This gauge is redundant with controller-runtime's standard `workqueue_depth{name}` metric, which has been present on `/metrics` since v0.3.0. Production code in this repository no longer calls `SetQueueDepth`, so the series is never written. Do not build new dashboards on it.

**Migration:** replace `virtrigaud_queue_depth{kind=<KIND>}` queries with `workqueue_depth{name=<controller-name>}`. The full kind → controller-name mapping table lives in the [Upgrade Guide](upgrade.md).

---

## Wiring summary

| Metric | Code path | Fires when |
|---|---|---|
| `build_info` | `metrics.SetupMetrics()` in `cmd/manager/main.go` | Manager start |
| `reconcile_total` + `reconcile_duration` | Deferred `ReconcileTimer.Finish()` in each `Reconcile()` function | Every reconcile |
| `errors_total` | `metrics.RecordError()` at each error site in controllers | Each error return |
| `rpc_requests_total` + `rpc_latency` | `providerRPCMetricsInterceptor` on the gRPC client chain | Every outbound RPC |
| `circuit_breaker_state` | `CircuitBreaker.transitionTo*()` | Breaker creation (seed) and each state change |
| `circuit_breaker_failures_total` | `CircuitBreaker.recordFailure()` | Every counted RPC failure |
| `vm_operations_total` | `defer c.recordVMOp(op, &retErr)` in gRPC client methods | Each Create/Delete/Power/Describe/Reconfigure call |
| `ip_discovery_duration` | `recordIPDiscoveryIfFirstSeen()` in the VirtualMachine controller | First no-IPs → has-IPs transition per VM |
| `provider_tasks_inflight` | `trackTaskStart` / `trackTaskDone` in the gRPC client | Each task-creating or task-completing RPC |
| `manager_vm_crd_security_features` | CRD feature check (also the `/readyz` check `vm-crd-security-features`) | Manager start, and on each readiness probe |
| `image_prepare_artifact_total` | VirtualMachine controller, image preparation | Each identity `ImagePrepare` answer |
| `host_committed_cpu` / `_memory_mib` | `Host` controller | Each `Host` sync (about once a minute) |
| `provider_host_guard_refusals_total`, `provider_image_prepare_legacy_requests_total`, `libvirt_*` | Provider processes | Host-guard refusal; legacy request; shadow compare / startup |

---

## Status conditions and events worth alerting on

These have no `virtrigaud_*` metric. They are the operator-visible signal for the v0.4.0 safety behaviours. Read them with `kubectl get -o yaml` / `kubectl describe`, or export them with `kube-state-metrics` custom-resource state metrics.

### VirtualMachine

| Condition / reason | Meaning | What to do |
|---|---|---|
| `Ready=False`, reason `ProviderError` | The provider call failed; retried. | Check the Provider and the message. |
| `Ready=False`, reason `ProviderConflict` | `Create` found a VM it cannot prove it owns and refused. | Adopt it, remove it, or rename; see [VM ownership](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-ownership.md). |
| `Ready=False`, reason `ConsumerNotAllowed` | The VM references a `Provider`, `VMClass` or `VMImage` in another namespace that does not share itself with this namespace. No provider call is made. | Set `spec.consumerNamespaceSelector` on the shared object. |
| `Ready=False`, reason `CreateOutcomeUnknown` | A single-host `Create` was requested but its outcome was never recorded and the provider cannot tell whether it made a VM; no second Create is sent. | Confirm the outcome with the `virtrigaud.io/create-outcome` annotation after checking the hypervisor. |
| `Ready=False`, reason `DiskSizeExceedsLimit` / `DiskSizeLimitUnverifiable`; condition `DiskSizeWithinLimit=False` | A disk exceeds `manager.maxDiskSize`, or its size could not be verified. | Lower the size or ask the administrator. |
| `Ready=False`, reason `HostUnavailable` (clustered) | The VM's host did not answer; re-checked every 30 s. | Restore the host. |
| `Ready=False`, reason `VMMissingOnHost` (clustered) | The bound host reports the domain missing; it is **not** re-created. | Investigate; see the [clustered libvirt guide](../guides/clustered/index.md). |
| `Placed=False` (clustered), reasons `CreatePending`, `HostUnavailable`, `Unbound`, `HostExcluded`, `AllHostsExcluded`, `RestorePending`, `PendingSizeGrew` | Why a clustered VM is not (yet) bound to a host. `RestorePending` is a restore guard; the VM's phase is `Pending`, not `Failed`. | See the [clustered libvirt guide](../guides/clustered/index.md). |
| `Provisioning=False`, reasons `Unschedulable`, `NoHostPool`, `MultipleHostPools`, `PlacementPolicyNotFound`, `InsufficientHostCapacity` | The scheduler cannot place the VM. | Fix pool membership, policy or capacity. |
| `DeleteBlocked=True` (and `Ready=False`/`DeleteBlocked`), reasons `HostUnreachable`, `DiskCheckFailed`, `DiskInUse`, and others | A delete is held with its finalizer kept, because the host cannot be reached, a cross-host disk check cannot run, or another VM depends on the disk (for example a libvirt linked clone). Retried with a backoff (15 s doubling to 5 min). A `Warning` event `DeleteBlocked` is recorded. | Restore the host, or release the VM with `virtrigaud.io/orphan-on-delete` / `virtrigaud.io/force-delete` after reading the message. |
| `ForceDeleteRefused=True` | `force-delete` was not honoured (a cross-namespace consumer of a clustered Provider that does not allow it). | See [Security](security.md#cross-namespace-use-of-a-provider). The same applies to `orphan-on-delete` (`Ready=False/OrphanOnDeleteNotAllowed`). |
| `DisksApplied=False`, reason `NotSupportedByProvider` | `spec.disks` is set but the Provider (libvirt, Proxmox) does not attach additional disks. Never `True`; it does not change `Ready`. | Remove `spec.disks` or use a Provider that attaches them. |
| `Reconfiguring=True`, reason `RestartRequired` | A resize was persisted but takes effect at the next power cycle. | Power-cycle the VM. |
| `SnapshotReverted` (and `status.snapshotRevert`) | State of a `spec.snapshot.revertToRef` revert: `Reverting` while a call is outstanding; `Failed` with reason `RevertFailed` (or `Unsupported`) when it ended. | See [`vm-snapshot-revert.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-snapshot-revert.md). |
| `LinkedClonesDependOnDisk=True` | Other VMs use this VM's disk as a backing file; powering it on can corrupt them. | Keep it powered off. |

### VMSnapshot, VMClone and VMMigration

| Object | Condition / reason | Meaning |
|---|---|---|
| `VMSnapshot` | `Ready=False`, reason `SnapshotOutcomeUnknown` | A `SnapshotCreate` was sent and its result was lost; held for an operator (single-host) or re-sent (clustered). Marker condition `SnapshotRequested=True`. |
| `VMMigration` | `Ready=False`, reasons `SnapshotOutcomeUnknown`, `ExportOutcomeUnknown`, `ImportOutcomeUnknown` | The same for the snapshot, export and import calls of a migration. Marker conditions `SnapshotRequested`, `ExportRequested`, `ImportRequested`. |
| `VMClone` | reason `CloneOutcomeUnknown`, `CloneRetrying` | A clone whose outcome is unknown or that is being retried. |
| `VMMigration` | `Importing=False`, reason `TargetHostUnavailable` | The landing host of a migration into a clustered Provider cannot be reached; the target is never moved off its host automatically. |

How these are produced, how long they are retried and how to release them is in [Resilience: calls whose outcome is unknown](resilience.md#calls-whose-outcome-is-unknown). Operator confirmation is recorded as a `Warning` event `OperationOutcomeConfirmed`.

### Provider, Host and HostPool

| Object | Condition / field | Meaning |
|---|---|---|
| `Provider` | `ProviderRuntimeReady`, `ProviderAvailable` | The runtime `Deployment` has ready replicas (`DeploymentReady` / `RemoteAvailable`). `ProviderAvailable` is **not** a live health probe of the hypervisor: it is set when the Deployment is ready. Use the circuit-breaker gauge for connectivity. `status.healthy` follows it. |
| `Provider` | `TLSConfigured` | Audit-visible TLS posture: `Enabled`, `ExplicitlyDisabled`, `SecretRefMissing`, `TLSBlockMissing`. See [mTLS](../providers/security/mtls.md). |
| `Provider` | `CapabilitiesReported` | Whether the Provider's self-reported capabilities were fetched (`CapabilitiesFetched` / `CapabilitiesUnavailable`). |
| `Provider` | `DeleteBlocked=True`, reason `ProviderInUse` | A `Provider` being deleted is held by VMs, snapshots, clones or migrations that need it (ADR-0010). A `Warning` event `ProviderDeleteBlocked` names counts and namespaces, never objects. Released with `virtrigaud.io/force-delete: "true"` on the Provider (event `ProviderForceDeleted`). |
| `Host` | `status.health`, `Ready`, `lastHeartbeatTime` | Inventory-sync result; a stale `lastHeartbeatTime` means the sync is not running. |
| `HostPool` | `status.totalHosts`, `readyHosts`, `schedulableHosts`, `Ready` | Written by the `HostPool` controller (a pool with no schedulable host cannot place VMs). |

For the reasons on a VM (`Ready`, `Placed`, `DeleteBlocked`, the `...OutcomeUnknown` holds) see the [VM status reference](../guides/vm-status.md).

---

## Logs

- **Manager.** The manager logs through controller-runtime's `zap` logger (`logr`), one structured record per event with the standard controller-runtime keys (`controller`, `controllerKind`, `namespace`, `name`, `reconcileID`). It is started with controller-runtime's `zap` flags (`--zap-devel`, `--zap-log-level`, `--zap-encoder`, …) and **Development-mode defaults** (console encoder). The chart (v0.4.0) does not have a values key for extra manager arguments, and the `VIRTRIGAUD_LOG_LEVEL` / `VIRTRIGAUD_LOG_FORMAT` / `VIRTRIGAUD_TRACING_*` entries in `manager.env` and the `observability.tracing` block of `values.yaml` are **not read by the manager** in v0.4.0. To change the manager's log flags, patch the Deployment `args` (for example with Kustomize `patches` on the rendered chart).
- **Providers.** Set `spec.runtime.logLevel` (`debug`, `info`, `warn`, `error`) and `spec.runtime.logFormat` (`text`, `json`) on the `Provider`; the controller passes them to the provider pod as `LOG_LEVEL` / `LOG_FORMAT`. Provider logs use Go `slog`.
- **What is never logged.** Secret values (credentials, TLS keys, cloud-init payloads) are not written to logs, events or status. The disk and ownership guards deliberately keep hypervisor paths, other tenants' namespaces and hostnames out of `status` and events: a `Conflict` message names only the requested object, and the details are in the **provider's** log. Look there for who owns a conflicting VM or which path was refused.
- **Warnings worth grepping for.** The manager logs `WARNING:` lines when `insecureSkipVerify` is set on a Provider, when TLS is explicitly disabled, and when a CRD security feature is missing or cannot be verified.

---

## Scraping setup

### Helm values (ServiceMonitor, alerts, dashboard)

The `ServiceMonitor` and the `PrometheusRule` are rendered only when `observability.prometheus.enabled` is `true` **and** their own `enabled` flag is set, and only when the `monitoring.coreos.com/v1` API exists in the cluster (for `helm template`, pass `--api-versions monitoring.coreos.com/v1`). The Grafana dashboard ConfigMap needs `observability.grafana.enabled` and `observability.grafana.dashboards.enabled` (it does not depend on `observability.prometheus.enabled` or on the Prometheus Operator).

```yaml
observability:
  prometheus:
    enabled: true
    serviceMonitor:
      enabled: true          # default false
      interval: 30s
      scrapeTimeout: 10s
      labels: {}             # extra labels, e.g. release: kube-prometheus-stack
    prometheusRule:
      enabled: true          # default false
      labels: {}
  grafana:
    enabled: true
    dashboards:
      enabled: true          # default false
      labels:
        grafana_dashboard: "1"   # picked up by the Grafana sidecar
```

- **ServiceMonitor** `<release>-manager`, in the release namespace, selecting the manager Service (`app.kubernetes.io/component: manager`) and scraping its `metrics` port (8080) at `/metrics` over **plain HTTP**.
- **PrometheusRule** `<release>`: four starter alerts — `VirtRigaudManagerDown` (critical; `absent(virtrigaud_build_info)` for 5m), `VirtRigaudProviderCircuitBreakerOpen` (`virtrigaud_circuit_breaker_state == 2` for 5m), `VirtRigaudHighReconcileErrorRate` (>20% errors per `kind` for 15m) and `VirtRigaudProviderRPCErrors` (>10% non-`OK` per `provider_type`/`method` for 10m).
- **Grafana dashboard** `VirtRigaud — Operator Overview` (`virtrigaud-overview`), shipped as a ConfigMap: build info, circuit-breaker state, tasks in flight, reconcile rate and p95, RPC rate and p95, VM operations and errors by reason.

The dashboard and the starter alerts use only metrics 1 to 11. The v0.4.0 additions (metrics 12 to 14, the provider-process metrics and the conditions above) have no ready-made alerts; build them from the queries in this guide.

!!! note "NetworkPolicy"
    If you enable the chart's `networkPolicy`, label the monitoring namespace to match `networkPolicy.monitoringNamespaceSelector` (default `metrics: enabled`), or the manager's `:8080` ingress is closed to Prometheus. See [Network Policies](../providers/security/network-policies.md).

### Securing the manager endpoint

`--metrics-secure=true` serves `/metrics` over HTTPS and requires a Kubernetes bearer token with `get` on the `/metrics` non-resource URL (see [Security](security.md#metrics-endpoint-security)). The chart has no value for this flag, and the chart's `ServiceMonitor` scrapes plain HTTP, so combine the flag with your own patch and `ServiceMonitor`.

### Verify the endpoint manually

```bash
kubectl port-forward -n virtrigaud-system svc/virtrigaud-manager 8080:8080
curl -s http://localhost:8080/metrics | grep '^virtrigaud_build_info'
# Expected: virtrigaud_build_info{component="manager",git_sha="...",go_version="...",version="..."} 1
```

The Service is named `<release fullname>-manager`; `virtrigaud-manager` assumes a release named `virtrigaud`. For a provider pod:

```bash
kubectl port-forward -n virtrigaud-system deploy/virtrigaud-provider-virtrigaud-system-libvirt-prod 8080:8080
curl -s http://localhost:8080/metrics | grep '^virtrigaud_libvirt'
```

---

## Troubleshooting

### `virtrigaud_build_info` absent

The manager pod has not started successfully, or the scrape is failing. Check `kubectl get pods -n virtrigaud-system` and `kubectl logs`. If the pod is `Running` but not Ready, check whether `virtrigaud_manager_vm_crd_security_features{state="missing"}` is `1` (the readiness probe fails until the CRDs are upgraded).

### `virtrigaud_circuit_breaker_state` absent

No Provider has reached runtime phase `Running` yet (the breaker is created when the first client for a Provider is built), or no Provider CRs exist. Check `kubectl get providers -A`.

### `virtrigaud_ip_discovery_duration_seconds` has no samples

No VM has completed the no-IPs → has-IPs transition since the last manager restart. This is normal on a freshly deployed cluster with no VMs, or if all current VMs were adopted (they arrive with IPs and the gate fires near-instantly).

### High `virtrigaud_errors_total{reason="provider-resolve"}`

The VirtualMachine controller cannot get a client for the Provider referenced in `spec.providerRef`: the Provider does not exist, its runtime is not `Running` (check `status.runtime.phase` and the `ProviderRuntimeReady` / `TLSConfigured` conditions), or the TLS Secret is missing a key.

### `virtrigaud_circuit_breaker_state{provider="X"} 2`

The provider is failing at the infrastructure level: ten consecutive counted failures (`Unavailable`, `DeadlineExceeded`, `Internal`, `Unknown`) occurred. Check the provider pod and its hypervisor connectivity first. It self-recovers 60 s after the last failure once calls succeed. See [Resilience](resilience.md).

### A VM is `Ready=False` but no error metric is moving

The VM is probably held on purpose: look at its conditions (`DeleteBlocked`, `Placed`, `CreateOutcomeUnknown`, `ConsumerNotAllowed`, `DiskSizeExceedsLimit`, …) in the table above. Holds re-check on their own schedule and are not reconcile errors.
