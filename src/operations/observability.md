<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Observability Guide

This is the operator's guide to what VirtRigaud emits, what it means, and how to build dashboards and alerts from it. For the machine-readable catalog (exact help strings, label sets, histogram buckets) see the [Metrics Reference](../api-reference/metrics.md). For circuit-breaker lifecycle details see [Resilience](resilience.md). For migration recipes from v0.3.5 metrics see [Upgrade Guide](upgrade.md).

## What VirtRigaud emits

The manager exposes all metrics on **`:8080/metrics`** (plain HTTP) by default. Pass `--metrics-secure=true` at manager startup to switch to HTTPS on the same port.

Three families of metrics live on that endpoint:

| Family | Who owns it | Coverage |
|---|---|---|
| `virtrigaud_*` | VirtRigaud — described in this guide | 11 wired families + 1 deprecated in v0.3.6 |
| `workqueue_*` | controller-runtime standard metrics | 9 families; per-reconciler queue depth, latency, retries. Present since v0.3.0. |
| `go_*` / `process_*` | Go runtime | Memory, GC pauses, goroutine count, file descriptors, etc. |

The `workqueue_*` family is particularly useful alongside `virtrigaud_manager_reconcile_*`. See [the kind → controller-name mapping](upgrade.md) in the Upgrade Guide if you are migrating from the deprecated `virtrigaud_queue_depth` gauge.

---

## The `virtrigaud_*` catalog (v0.3.8)

### 1. `virtrigaud_build_info`

**Type:** Gauge  
**Labels:** `version`, `git_sha`, `go_version`, `component`  
**Value:** Always `1`.

Populated by `metrics.SetupMetrics()` at manager startup. Use it to confirm that the running process matches your expected version + git SHA without looking at pod annotations.

```promql
# Is the right version running?
virtrigaud_build_info{component="manager", version="v0.3.8"}

# What git SHA is deployed?
virtrigaud_build_info{component="manager"} == 1
```

If this query returns nothing, the manager has not started successfully.

---

### 2. `virtrigaud_manager_reconcile_total`

**Type:** Counter  
**Labels:** `kind`, `outcome`  
**`outcome` values:** `success`, `error`, `requeue`

Incremented once per reconcile run by every reconciler (VirtualMachine, Provider, VMClass, VMImage, VMNetworkAttachment, VMAdoption, VMSnapshot, VMMigration, and — added in **v0.3.8** — VMClone and VMSet). The outcome is inferred from the named return values of the reconcile function via a deferred timer block — no manual instrumentation at each return site.

!!! note "New `kind` values in v0.3.8"
    v0.3.8 introduced the VMClone and VMSet controllers, so this counter now
    emits `kind="VMClone"` and `kind="VMSet"` series in addition to the existing
    kinds. The label set is otherwise unchanged. Example:
    `virtrigaud_manager_reconcile_total{kind="VMClone",outcome="success"}`.

`requeue` means the reconciler explicitly requested a requeue without returning an error (e.g. waiting for a provider task to complete). `error` means an error was returned and controller-runtime will apply exponential backoff. `success` means the reconcile completed cleanly.

```promql
# Reconcile error rate across all kinds
sum by (kind) (rate(virtrigaud_manager_reconcile_total{outcome="error"}[5m]))

# Per-kind success/error breakdown
sum by (kind, outcome) (rate(virtrigaud_manager_reconcile_total[5m]))
```

**Alerting:** A sustained non-zero rate on `outcome="error"` for a specific `kind` suggests a bug or misconfiguration in that reconciler's path.

---

### 3. `virtrigaud_manager_reconcile_duration_seconds`

**Type:** Histogram  
**Labels:** `kind`  
**Buckets:** Exponential, 1ms to ~32s (15 buckets)

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

A typed error counter used to slice failures by root cause without scraping logs. Each reconciler defines a small set of `errReason*` constants (e.g. `get-vm`, `deps-not-found`, `provider-resolve`, `provider-validate`, `provider-describe`, `provider-task-status`, `provider-delete`). The `component` label is always `manager` for errors emitted from reconcilers.

```promql
# Top-5 error reasons in the last 10 minutes
topk(5, sum by (reason) (rate(virtrigaud_errors_total{component="manager"}[10m])))

# Are any VMs failing because their Provider CR can't be resolved?
rate(virtrigaud_errors_total{reason="provider-resolve"}[5m])
```

Use this before opening the logs to triage whether a surge of errors is infrastructure (`provider-describe`, `provider-task-status`) or configuration (`deps-not-found`, `provider-resolve`).

---

### 5. `virtrigaud_provider_rpc_requests_total`

**Type:** Counter  
**Labels:** `provider_type`, `method`, `code`  
**Wired since:** v0.3.5 (G4 / PR #107)

Every outbound gRPC RPC from the manager to a provider pod is counted here. `method` is the short RPC name (e.g. `Create`, `Delete`, `Power`, `Describe`, `TaskStatus`, `SnapshotCreate`). `code` is the canonical gRPC status code string from `codes.Code.String()` — `OK`, `Unavailable`, `DeadlineExceeded`, `NotFound`, etc.

!!! important "Circuit-breaker rejections are visible here"
    The metrics interceptor runs *before* the circuit-breaker interceptor in the chain. Breaker fast-fails appear as `code="Unavailable"` — not as silent drops. If `virtrigaud_circuit_breaker_state` is 2 (Open) and `virtrigaud_provider_rpc_requests_total{code="Unavailable"}` is climbing, that is the breaker protecting the provider, not the provider itself refusing RPCs.

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
**Buckets:** Exponential, 1ms to ~32s (15 buckets)  
**Wired since:** v0.3.5 (G4 / PR #107)

Wall-clock time for each outbound RPC, recorded by the same metrics interceptor as `virtrigaud_provider_rpc_requests_total`. Useful for detecting a degraded-but-not-failing provider (latency rising, error rate still low).

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

One time-series per `Provider` CR. The gauge is seeded to `0` (Closed) at the moment the manager constructs the gRPC client for a Provider, so all Provider rows appear on `/metrics` from boot — operators get a stable label set to dashboard against even before any failures occur.

For the full circuit-breaker lifecycle (state machine diagram, failure classification, HalfOpen trial semantics) see [Resilience](resilience.md).

```promql
# Alert: any breaker non-closed for more than 5 minutes
ALERT ProviderCircuitBreakerOpen
  IF virtrigaud_circuit_breaker_state > 0
  FOR 5m
  LABELS { severity = "warning" }
  ANNOTATIONS {
    summary = "Provider {{ $labels.provider }} circuit breaker is {{ $value | humanize }} (0=Closed,1=HalfOpen,2=Open)"
  }
```

!!! note "v0.3.6-rc1 smoke observation"
    On the `vr1.lab.k8` lab cluster, the libvirt breaker tripped immediately on first deploy because of a persistent libvirt-SSH connectivity issue (issue #I1). This is correct behaviour — the breaker is working as designed, and `virtrigaud_circuit_breaker_state{provider="libvirt-lab"} 2` is the signal that prompts you to check the SSH tunnel rather than grep manager logs. See [Resilience](resilience.md) for the full narrative.

---

### 8. `virtrigaud_circuit_breaker_failures_total`

**Type:** Counter  
**Labels:** `provider_type`, `provider`  
**Added:** v0.3.6 (G6 / PR #111)

Incremented on every infra-class RPC failure (`Unavailable`, `DeadlineExceeded`, `Internal`, `Unknown`) counted against the breaker. Business errors (`NotFound`, `InvalidArgument`, etc.) do not increment this counter — those indicate the provider is healthy and the request was invalid.

The counter increments every time `recordFailure()` is called inside the CircuitBreaker, not just on transitions. This means it answers "how often is this provider failing at the infrastructure level?" independently of whether the breaker has tripped.

```promql
# Rate of infra failures per provider
rate(virtrigaud_circuit_breaker_failures_total[5m]) by (provider_type, provider)
```

---

### 9. `virtrigaud_vm_operations_total`

**Type:** Counter  
**Labels:** `operation`, `provider_type`, `provider`, `outcome`  
**`operation` values:** `Create`, `Delete`, `Power`, `Describe`, `Reconfigure`  
**`outcome` values:** `success`, `error`  
**Added:** v0.3.6 (G7.1 / PR #124)

Per-Provider VM operation outcome counter. Recorded via `defer c.recordVMOp(op, &retErr)` at the top of each VM-operation method in the gRPC client. The `outcome` is inferred from the named return value at function exit — same pattern as the reconcile-level metrics.

This gives a higher-level view than `virtrigaud_provider_rpc_requests_total`: one Create operation may involve several RPCs (Create + repeated TaskStatus polls), but it produces exactly one sample here at the end.

```promql
# Per-Provider VM-op error rate
sum by (provider) (rate(virtrigaud_vm_operations_total{outcome="error"}[5m]))

# Create success rate for vsphere provider
rate(virtrigaud_vm_operations_total{operation="Create",provider_type="vsphere",outcome="success"}[5m])
  /
rate(virtrigaud_vm_operations_total{operation="Create",provider_type="vsphere"}[5m])
```

**Alerting recipe:**

```promql
ALERT VMOperationsErrorRateHigh
  IF sum by (provider) (rate(virtrigaud_vm_operations_total{outcome="error"}[5m]))
       /
     sum by (provider) (rate(virtrigaud_vm_operations_total[5m])) > 0.1
  FOR 10m
  LABELS { severity = "warning" }
```

---

### 10. `virtrigaud_ip_discovery_duration_seconds`

**Type:** Histogram  
**Labels:** `provider_type`  
**Buckets:** Exponential, 100ms to ~100s (10 buckets)  
**Added:** v0.3.6 (G7.2 / PR #127)

Measures the wall-clock time from `kubectl apply` (specifically, `vm.CreationTimestamp`) to the moment the first IP address appears in `vm.Status.IPs`. This is the operator-visible SLO answer to "how long from create to first IP on this provider type?"

A single sample is emitted per VM on the no-IPs → has-IPs transition. The gate in `recordIPDiscoveryIfFirstSeen` requires: the current `vm.Status.IPs` is empty, the provider just returned at least one IP, and `vm.CreationTimestamp` is non-zero. Because `vm.Status.IPs` is persisted to etcd as soon as the gate fires, the metric is idempotent across manager restarts — a restart during the same VM's lifecycle will not emit a second sample.

```promql
# 95th-percentile IP discovery time for libvirt
histogram_quantile(0.95,
  sum(rate(virtrigaud_ip_discovery_duration_seconds_bucket{provider_type="libvirt"}[5m]))
  by (le)
)

# Median across all provider types
histogram_quantile(0.50,
  sum(rate(virtrigaud_ip_discovery_duration_seconds_bucket[5m]))
  by (le, provider_type)
)
```

!!! note "Adopted VMs"
    VMs created by the VMAdoption controller (watching `virtrigaud.io/adopt-vms: "true"` on Provider CRs) already have IPs at the moment their VirtualMachine CR is created. For those VMs the gate fires immediately and the duration will be very short (~milliseconds). Filter by `provider_type` if you want to compare native-create latency vs adoption latency.

---

### 11. `virtrigaud_provider_tasks_inflight`

**Type:** Gauge  
**Labels:** `provider_type`, `provider`  
**Added:** v0.3.6 (G7.3 / PR #129)

Tracks how many async tasks the manager is currently monitoring for a given Provider CR. The gauge is seeded to `0` at startup (so all Provider rows appear on `/metrics` immediately — see note on build_info above).

`trackTaskStart` is called in the 9 task-creating RPCs: `Create`, `Delete`, `Power`, `Reconfigure`, `SnapshotCreate`, `SnapshotDelete`, `SnapshotRevert`, `ExportDisk`, `ImportDisk`. `trackTaskDone` is called in `IsTaskComplete` and `TaskStatus` when the terminal state (Done or Error) is observed.

The gauge measures "tasks THIS manager instance is tracking." After a manager restart, the inflightTasks map starts empty, so the gauge resets to 0 even if the provider has tasks running from the previous instance. The reconciler will discover those tasks from `vm.Status.LastTaskRef` and repopulate the set on the next reconcile cycle.

```promql
# Is any Provider accumulating tasks faster than it's completing them?
virtrigaud_provider_tasks_inflight > 5

# Task inflight count across all providers
sum by (provider) (virtrigaud_provider_tasks_inflight)
```

**Alerting recipe:**

```promql
ALERT ProviderTasksAccumulating
  IF virtrigaud_provider_tasks_inflight > 5
  FOR 5m
  LABELS { severity = "warning" }
  ANNOTATIONS {
    summary = "Provider {{ $labels.provider }} has {{ $value }} inflight tasks — possible task polling loop or provider wedge"
  }
```

---

## Deprecated: `virtrigaud_queue_depth`

**Deprecated in:** v0.3.6 (G7.4 / PR #131)  
**Removal:** v0.4.0 or later  
**Help string:** `[DEPRECATED v0.3.6 — use controller-runtime's workqueue_depth{name} instead. See CHANGELOG.] Current depth of work queue by kind.`

This gauge is redundant with controller-runtime's standard `workqueue_depth{name}` metric, which has been present on `/metrics` since v0.3.0. Reinventing it under a `virtrigaud_*` namespace forces operators to dashboard two redundant series.

The variable and helper remain callable for compile compatibility with out-of-tree code. Production code in this repo no longer calls `SetQueueDepth`.

**Migration:** replace `virtrigaud_queue_depth{kind=<KIND>}` queries with `workqueue_depth{name=<controller-name>}`. The full kind → controller-name mapping table lives in the [Upgrade Guide](upgrade.md).

---

## Wiring summary

The following table shows which code path populates each metric and when:

| Metric | Code path | Fires when |
|---|---|---|
| `build_info` | `metrics.SetupMetrics()` in `cmd/manager/main.go` | Manager start |
| `reconcile_total` + `reconcile_duration` | Deferred `ReconcileTimer.Finish()` in each `Reconcile()` function | Every reconcile |
| `errors_total` | `metrics.RecordError()` at each error site in controllers | Each error return |
| `rpc_requests_total` + `rpc_latency` | `providerRPCMetricsInterceptor` on the gRPC client chain | Every outbound RPC |
| `circuit_breaker_state` | `CircuitBreaker.transitionTo*()` | CB state change + at client construction (seed) |
| `circuit_breaker_failures_total` | `CircuitBreaker.recordFailure()` | Every infra-class RPC failure |
| `vm_operations_total` | `defer c.recordVMOp(op, &retErr)` in gRPC client methods | Each VM operation (Create/Delete/Power/Describe/Reconfigure) |
| `ip_discovery_duration` | `recordIPDiscoveryIfFirstSeen()` in VirtualMachine controller | First no-IPs → has-IPs transition per VM |
| `provider_tasks_inflight` | `trackTaskStart` / `trackTaskDone` in gRPC client | Each task-creating or task-completing RPC |

---

## Scraping setup

### ServiceMonitor (Prometheus Operator)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: virtrigaud-manager
  namespace: virtrigaud-system
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: virtrigaud
      app.kubernetes.io/component: manager
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

### Verify the endpoint manually

```bash
kubectl port-forward -n virtrigaud-system svc/virtrigaud-manager 8080:8080
curl -s http://localhost:8080/metrics | grep '^virtrigaud_build_info'
# Expected: virtrigaud_build_info{component="manager",git_sha="...",go_version="...",version="v0.3.8"} 1
```

---

## Troubleshooting

### `virtrigaud_build_info` absent

The manager pod has not started successfully. Check `kubectl get pods -n virtrigaud-system` and `kubectl logs`.

### `virtrigaud_circuit_breaker_state` absent

The manager is running but no Provider CRs have been created yet, or the manager version predates v0.3.6. Check `kubectl get providers -A`.

### `virtrigaud_ip_discovery_duration_seconds` has no samples

No VM has completed the no-IPs → has-IPs transition since the last manager restart. This is normal on a freshly deployed cluster with no VMs, or if all current VMs were adopted (they arrive with IPs and the gate fires near-instantly).

### High `virtrigaud_errors_total{reason="provider-resolve"}`

The VirtualMachine controller cannot find the Provider CR referenced in `spec.providerRef`. Verify the Provider CR exists in the correct namespace and the `providerRef` fields match exactly.

### `virtrigaud_circuit_breaker_state{provider="X"} 2` on startup

The provider is unreachable. Ten infra-class failures are required to trip the breaker from Closed, so this indicates at least 10 failed RPCs occurred before you checked — usually because the provider pod is not running or SSH connectivity is broken. See [Resilience](resilience.md) for the recovery path.
