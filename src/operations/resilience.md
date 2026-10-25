<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VirtRigaud Resilience Guide

This document describes the resilience patterns and error-handling mechanisms in VirtRigaud as of **v0.4.0**: what the manager retries, what it never retries blindly, how the per-Provider circuit breaker decides, and how a host that stops answering is handled.

## Overview

VirtRigaud's resilience model is layered:

- **Error taxonomy** — provider answers are classified (`internal/providers/contracts`); the class decides whether a controller retries, holds or fails.
- **Per-RPC deadlines** — every manager-to-provider call has its own timeout ([Timeouts](#timeouts)).
- **CircuitBreaker on the provider gRPC path** — one breaker per `Provider`, so a wedged provider is not hammered and the operator gets a metric ([below](#circuitbreaker-on-the-provider-grpc-path-v036)).
- **Controller retries and backoff** — transient failures are requeued with fixed or exponential delays ([Retries and backoff](#retries-and-backoff)). There is no global retry setting.
- **Calls whose outcome is unknown are held, not re-sent blindly** — since v0.4.0 the manager records a durable marker before any call that could be duplicated ([Calls whose outcome is unknown](#calls-whose-outcome-is-unknown)).
- **Host-unreachable handling for clustered libvirt providers** — one dead host never opens the Provider's breaker or blocks the Provider's other hosts ([A clustered host that stops answering](#a-clustered-host-that-stops-answering)).
- **Provider-side connection resilience** — the vSphere provider keeps its vCenter session alive; the libvirt provider retries transient SSH connection failures ([below](#provider-side-connection-resilience-v038)).

!!! note "Nothing in this page is tunable through the chart in v0.4.0"
    The circuit-breaker thresholds, the per-RPC deadlines and the retry delays are compiled in. The `config.circuitBreaker`, `config.retry` and `config.rateLimit` blocks in the chart's `values.yaml`, and ConfigMap keys such as `CB_FAILURE_THRESHOLD`, `RPC_TIMEOUT_MUTATING` or `RETRY_MAX_ATTEMPTS`, are **not read by the manager**. Values you set there have no effect.

## CircuitBreaker on the Provider gRPC Path (v0.3.6)

The circuit breaker was wired onto the gRPC path in v0.3.6 (G6) and is unchanged in design in v0.4.0, apart from which failures it ignores (see [What does not count as a failure](#what-does-not-count-as-a-failure)). The gRPC client constructor (`internal/transport/grpc/client.go`) installs a `providerCircuitBreakerInterceptor` on every outbound RPC, fed by one breaker per `Provider`.

### Architecture

```
VirtualMachine reconciler
        │
        │ resolver.GetProvider(ctx, provider)
        ▼
remote.Resolver                                  internal/runtime/remote/resolver.go
        │  cbRegistry.GetOrCreate("rpc",
        │                          provider.Spec.Type,
        │                          provider.Name)
        ▼
resilience.Registry  ────►  resilience.CircuitBreaker  (one per Provider)
        │                              │
        ▼                              │ wraps every RPC via
grpc.Client                            │ providerCircuitBreakerInterceptor
        │ chained unary interceptors:  │
        │   1. requestSentInterceptor      (was the request sent?)
        │   2. providerRPCMetricsInterceptor ──► virtrigaud_provider_rpc_*
        │   3. providerCircuitBreakerInterceptor ─► virtrigaud_circuit_breaker_*
        ▼
provider-vsphere / provider-libvirt / provider-proxmox
```

Important properties:

- **One breaker per Provider**, created lazily the first time the resolver builds a client for it (which needs the Provider's runtime to be `Running`). The key is `(provider type, Provider name)`: the **namespace is not part of it**, so two Providers of the same type and name in different namespaces share one breaker and one set of metric series. Breakers live in memory: a breaker is dropped (with its metric series) when its `Provider` is deleted, and a manager restart starts every breaker Closed.
- **Interceptor order matters.** The metrics interceptor runs *before* the breaker interceptor, so every RPC (including breaker fast-fails, which surface as `code=Unavailable`) shows up in `virtrigaud_provider_rpc_requests_total`. Operators see breaker-rejected RPCs as `Unavailable` — not as silent drops.
- **The outermost interceptor records whether a request was ever sent.** A call that failed before its request left the manager (no connection was made before its deadline, or the breaker refused it) is known to have done nothing. A call that failed after the request headers were sent (the connection dropped, a deadline passed mid-call) may have been processed. That distinction drives [the outcome-unknown protocol](#calls-whose-outcome-is-unknown).
- **The calls wait for a connection.** The client dials with gRPC `WaitForReady`, so while a provider pod is down an RPC does not fail at once: it waits up to its own deadline ([Timeouts](#timeouts)) and then fails with `DeadlineExceeded`, which counts toward the breaker.
- **The interceptor never panics**, by design. If it did, every provider RPC in the cluster would break.

### Default configuration

`resilience.DefaultConfig()`, used unconditionally by the manager:

| Setting | Value | Meaning |
|---|---|---|
| `FailureThreshold` | `10` | **Consecutive** counted failures that trip the breaker from Closed to Open. A successful call in the Closed state resets the count to zero. |
| `ResetTimeout` | `60s` | After this much time in Open, measured from the last counted failure, the next call admits the breaker to Half-Open. Calls refused while Open do not extend it. |
| `HalfOpenMaxCalls` | `3` | Trial calls admitted in Half-Open. The breaker closes when the third admitted call succeeds; any single counted failure re-opens it. |

These apply uniformly to all Providers. There is no per-Provider override.

### Failure classification — what trips the breaker

The breaker fires when "the provider as a whole is in trouble", not when "one request was bad". A `NotFound` on a deleted VM must not contribute to the manager deciding the whole provider is down.

`internal/transport/grpc/client.go` (`isInfraFailure`, `countsTowardBreaker`) classifies as follows.

**Counts toward the threshold:**

| gRPC code | Meaning |
|---|---|
| `Unavailable` | Provider pod down, network partition, mTLS handshake failed |
| `DeadlineExceeded` | Provider hung past the call timeout, or no connection within it |
| `Internal` | Provider crashed mid-call |
| `Unknown` | Non-gRPC error from the transport layer, or an untyped provider failure |

**Does not count (passes through to the caller):**

| gRPC code | Why it shouldn't trip the breaker |
|---|---|
| `OK` | Obvious success |
| `Canceled` | Caller gave up, not the provider failing |
| `NotFound`, `InvalidArgument`, `AlreadyExists`, `FailedPrecondition`, `PermissionDenied`, `Unauthenticated` | Application errors: the provider is healthy and refused the request |
| `ResourceExhausted` | Rate-limit signal: back off this one call, not stop talking to the provider |
| `Aborted`, `OutOfRange`, `Unimplemented` | Protocol-level, unrelated to provider health |

#### What does not count as a failure

Since v0.4.0 some `Unavailable`, `Unknown` and `DeadlineExceeded` answers are **also** kept out of the breaker, because the provider answered and the cause is local to one host, one VM or one tenant. Counting them would let one dead host or one tenant's failing request fast-fail every VM of the Provider:

- A clustered libvirt provider's host-scoped answers: `HOST_UNAVAILABLE` (a host is unknown, draining, cannot be dialled or did not answer in time), `VM_OPERATION_FAILED` (a per-VM operation reached its host and failed there, or was not performed), `VM_DISK_CHECK_FAILED` (a disk-dependency check could not run), and `VM_OUTCOME_UNKNOWN_RETRY` (the outcome could not be told after the host stopped answering). `VM_OPERATION_FAILED` also covers a single-host libvirt provider's `SnapshotCreate`, `ExportDisk` and `ImportDisk` failures that prove nothing was done (a step that only reads, validates or writes in a private area that is removed).
- On `ImagePrepare` only: `IMAGE_ARTIFACT_IN_PROGRESS` (another import is still running), `IMAGE_SOURCE_UNAVAILABLE` (one tenant's image source failed), and a `DeadlineExceeded` or `Canceled` caused by the manager's own prepare timeout. A long legitimate import must not open the breaker of every Provider that shares its image location. On every other RPC a `DeadlineExceeded` still counts.
- The breaker's own fast-fail: a call it refused never reaches the recording step, so it cannot extend an open breaker.

The plain `Unavailable` that `DeleteStagedDisk` returns when a host's `qemu-img` fails still counts.

### What happens when the breaker is open

When the breaker is Open and an RPC arrives, the interceptor **does not invoke the provider call**. It synthesises a canonical `codes.Unavailable` status (`circuit breaker open: ...`). The request is marked as never sent, so the controllers treat the call as one that did nothing. Downstream code paths — `mapGRPCError`, callers that test for a retryable error, the controller-runtime retry loop — treat it like any other `Unavailable` from the provider. Operators don't need a special handling path for "breaker open" vs "provider down".

### State machine

```
       10 consecutive counted failures
   ┌────────────────────────────────────►┌─────────┐
   │                                      │  Open   │◄──┐ any counted failure
┌──┴──────┐                                └────┬────┘   │
│ Closed  │                                     │        │
└──┬──────┘                                     │ 60 s since the last failure
   ▲                                            ▼
   │ the 3rd admitted trial call succeeds   ┌───────────────┐
   └────────────────────────────────────────│  Half-Open    │
                                            │ (≤ 3 trial    │
                                            │  RPCs)        │
                                            └───────────────┘
```

- **Closed** — Normal operation. Each counted failure increments a counter; reaching 10 consecutive transitions to Open. A success resets the counter.
- **Open** — Fast-fail mode. RPCs return `Unavailable` without hitting the provider. After 60 s, the *next* RPC admits the breaker to Half-Open and counts as the first half-open call.
- **Half-Open** — Up to 3 trial RPCs are admitted; further calls are refused until the trial resolves. The breaker closes when the third admitted call succeeds; a single counted failure re-opens it.

### Metrics

```
# Gauge: current state. 0=Closed, 1=Half-Open, 2=Open.
virtrigaud_circuit_breaker_state{provider_type="vsphere", provider="vsphere-prod"} 0

# Counter: every counted failure recorded against the breaker.
virtrigaud_circuit_breaker_failures_total{provider_type="vsphere", provider="vsphere-prod"} 5
```

Both families have one series per Provider name. Suggested alerts:

- `virtrigaud_circuit_breaker_state > 0` — any breaker in a non-Closed state across the fleet. (The chart's optional `PrometheusRule` alerts on `== 2` for 5 minutes.)
- `sum by (provider) (rate(virtrigaud_circuit_breaker_failures_total[5m])) > 0` — sustained infrastructure failures even before the breaker trips.

See the [Observability Guide](observability.md#7-virtrigaud_circuit_breaker_state) for the full catalog.

### Operational response to a tripped breaker

1. Check `virtrigaud_provider_rpc_requests_total{code="Unavailable"}` and `{code="DeadlineExceeded"}` to confirm the failure pattern is on the provider, not the manager.
2. Investigate the provider pod (`kubectl logs deployment/virtrigaud-provider-<namespace>-<name>`) and its hypervisor connectivity (for libvirt: SSH reachability and host-key trust; for vSphere: vCenter and credentials; for Proxmox: the API endpoint and token).
3. The breaker self-recovers once connectivity is restored — no manual reset. (`(*resilience.CircuitBreaker).Reset()` exists in code but is not exposed through any admin API; restarting the manager also resets every breaker.)

!!! note "The Provider's `ProviderAvailable` condition is not the breaker"
    `ProviderAvailable=True` (reason `RemoteAvailable`) means the provider's `Deployment` has ready replicas. It is not driven by RPC failures and does not turn `False` when the breaker opens. Use the breaker gauge, or the `Ready` condition of the VMs, to see a provider that is up but cannot reach its hypervisor.

## Provider-side connection resilience (v0.3.8)

The circuit breaker protects the manager from a *wedged* provider. These are the complementary provider-internal behaviours that make providers survive transient hypervisor-connectivity failures; they need no Provider CR change.

### vSphere: vCenter session keepalive + real-probe reconnect (#190)

A vSphere provider that sat idle for a long time could have its vCenter session silently expire; the next RPC then failed as an infra-class failure and, after enough of them, tripped the breaker. The provider now:

- runs a **session keepalive** (every 5 minutes) so an otherwise-idle vCenter session does not lapse;
- performs a **real probe** against vCenter in `Validate` rather than trusting a cached session handle;
- **reconnects transparently** and retries when the probe detects a dead session.

### Libvirt: retry transient SSH connection failures (#191)

The libvirt provider drives the host over SSH. Bursts of short-lived SSH connections can hit transient handshake failures such as `kex_exchange_identification: Connection closed by remote host`, often because the host's `sshd` is rate-limiting concurrent unauthenticated connections (`MaxStartups`, `fail2ban`). The provider **retries these transient connection failures up to 3 attempts, with a 1 s base backoff that doubles**, instead of failing the RPC on the first stumble. A real `virsh` error is returned at once.

!!! note "Client-side mitigation; tune the host too"
    The retry is the client-side half of the fix. If the host's `sshd` `MaxStartups` is low (or `fail2ban` is aggressive), bursts can still exhaust the host's connection budget. See [Libvirt Host Preparation](libvirt-host-prepare.md) for the host-side tuning.

### Migration-storage PVC safety

The provider controller annotates Provider CRs with a migration PVC and rolls the provider pods to mount it (see [VM Migration Guide](../migration/vm-migration-guide.md)). It does **not** delete migration-storage PVCs, and it watches them so a roll does not race their lifecycle (v0.3.8, #184). Since v0.4.0 a provider pod mounts **only the migration PVCs that a live `VMMigration` references** (the target's read-only), and staged files on the `pvc` backend are opened without following symbolic links. Ownership and cleanup of the intermediate PVC remain with the `VMMigration` (see [VMMigration API Reference](../migration/api-reference.md#finalizer)).

## Error Taxonomy

### Error Types

VirtRigaud classifies provider-returned errors into specific categories (`internal/providers/contracts`). The classification drives controller retry behaviour and the conditions surfaced on each CR.

| Type | Retryable | Description | Example |
|------|-----------|-------------|---------|
| `NotFound` | No | Resource doesn't exist | VM not found |
| `InvalidSpec` | No | Invalid configuration | Malformed VM spec; unsafe name |
| `Unauthorized` | No | Authentication failed | Invalid credentials |
| `NotSupported` | No | Unsupported operation | Feature not available |
| `Retryable` | Yes | Transient error | Network timeout |
| `Unavailable` | Yes | Service unavailable | Provider down — **including circuit-breaker open** |
| `HostUnavailable` | Yes | A clustered provider's host did not answer; nothing was done | See below |
| `InProgress` | Yes | The same work is still running | Image import still in progress |
| `RateLimit` | Yes | Rate limited | API quota exceeded |
| `Timeout` | Yes | Operation timeout | Long-running task |
| `QuotaExceeded` | No | Resource quota hit | Storage full |
| `Conflict` | No | Resource conflict; the provider refused | Duplicate name; a VM it does not own; a disk another VM uses |

A gRPC `AlreadyExists` or `FailedPrecondition` becomes `Conflict` (non-retryable): the VM is shown `Ready=False` with a constant reason (`ProviderConflict`, `DeleteBlocked`, …) and re-checked on a slow schedule instead of a tight loop.

### Error Creation (provider authors)

```go
import "github.com/projectbeskar/virtrigaud/internal/providers/contracts"

// Create specific error types
err := contracts.NewNotFoundError("VM not found", originalErr)
err := contracts.NewRetryableError("Network timeout", originalErr)
err := contracts.NewUnavailableError("Provider unavailable", originalErr)

// Check if error is retryable
var providerErr *contracts.ProviderError
if errors.As(err, &providerErr) && providerErr.IsRetryable() {
    // Retry the operation
}
```

## Timeouts

### Per-RPC deadlines

Each RPC in the gRPC client has its own context deadline (`internal/transport/grpc/client.go`). They are compiled in:

| RPC | Deadline | Rationale |
|---|---|---|
| `Validate`, `GetCapabilities`, `Describe`, `GetHostInfo` | 30 s | Cheap health check / read-only state query |
| `TaskStatus`, `IsTaskComplete` | 10 s | Poll, must be cheap |
| `Power`, `Delete`, `SnapshotDelete` | 2 min | State change + provider confirmation |
| `GetDiskInfo`, `ListHosts` | 2 min | Backing-chain walk / inventory read |
| `ListVMs` | 2 min (45 s for the owner-filtered list) | Full provider enumeration (used by VMAdoption and the clustered disk checks) |
| `TransferOwner`, `DeleteStagedDisk` | 2 min | Adoption stamp; staged migration object cleanup |
| `DeleteLandedDisk` | 3 min | Cleanup of a migration's landed disk |
| `Create`, `Clone`, `Reconfigure`, `SnapshotCreate`, `SnapshotRevert` | 5 min | Template clone / disk provisioning, resize, memory + disk capture |
| `ImagePrepare` | 5 min | Starting or finishing an image import (long imports run as tasks) |
| `ExportDisk`, `ImportDisk` | 30 min | Large data transfer |

When a deadline expires, the gRPC client returns `DeadlineExceeded`, which (a) is mapped to a retryable error for the caller and (b) counts toward the circuit breaker — except on `ImagePrepare`, where the manager's own timeout is not held against the Provider.

A clustered libvirt provider also **ends its waits for a host before the manager's deadline**, so the answer arrives in time ([below](#a-clustered-host-that-stops-answering)).

## Retries and backoff

The manager has no generic retry loop around provider calls. A failed call is returned to the controller, which records the outcome in the object's conditions and **requeues** it. The delay depends on why it failed:

| Situation | Re-check |
|---|---|
| A VM's provider call failed (`Ready=False`, `ProviderError`) | 5 s |
| A create the provider refused because it cannot prove it owns an existing VM (`ProviderConflict`) | 2 min |
| A create refused as an invalid spec or an unsafe name (`ValidationError`) | 30 s |
| A create held by `CreateBackoff` or `CreateRefused`; a clustered create or delete held for an unreachable host (`HostUnavailable`, `DeleteBlocked`), a failed disk check or a restore guard (`RestorePending`) | Backoff of **15 s doubling to 5 min**, counted from when the hold began |
| A clustered VM that cannot be placed because no host can take it (`Unschedulable`) | 30 s, doubling to 2 min |
| A clustered VM blocked by a placement misconfiguration (`NoHostPool`, a dangling `VMPlacementPolicy`, …) | 30 s |
| A bound clustered VM whose host is unavailable (`Describe`, `Power`, `Reconfigure`) | 30 s |
| A `VMSnapshot` delete the provider refused or could not complete | Backoff of 15 s doubling to 5 min |
| A held `VMSnapshot` or `VMMigration` call with an unknown outcome | Re-checked every minute; a confirmation by an operator re-drives it at once |
| An image prepare whose answer did not confirm the image's identity | 30 s doubling to 5 min |
| An image prepare whose asynchronous import failed | 1 min doubling to 30 min per failing source |
| A `Provider` held for deletion by objects that still need it | Event-driven, with a 2 min backstop |

controller-runtime applies its own exponential backoff on top when a reconcile returns an error.

!!! note "The `resilience.Retry` helper is not used on the production path"
    `internal/resilience` also contains a generic exponential-backoff helper (`Retry`, with `DefaultRetryConfig`: 5 attempts, 500 ms base, 30 s cap, ×2, up to 10% jitter, plus `AggressiveRetryConfig`, `ConservativeRetryConfig` and `NoRetryConfig` presets). No manager code calls it in v0.4.0; it exists for provider and controller authors. The delays in the table above are what actually happens.

## Calls whose outcome is unknown

A few provider calls make something that a second call could duplicate: the source snapshot, the disk export and the disk import of a `VMMigration`, the snapshot of a `VMSnapshot`, a single-host `Create`, a `Clone`, and a `SnapshotRevert`. If the manager restarts or leadership moves after such a call was sent but before its result was written to status, the result is lost. The same holds for a call that **fails without a definite answer**: it ran past its deadline, or the connection dropped after the request was written. The provider may still be completing it.

In v0.4.0 the manager never re-sends such a call blindly:

1. **A durable marker is written first.** Before the call, the object's status records a condition of its own (`SnapshotRequested`, `ExportRequested`, `ImportRequested` on a `VMMigration`; `SnapshotRequested` on a `VMSnapshot`), written with the `resourceVersion` the reconcile read. If that write fails, **nothing is sent**. A VM's `Create` and a `spec.snapshot.revertToRef` revert are recorded the same way (reason `CreateRequested` on `Provisioning`; `status.snapshotRevert` with `phase: Reverting`).
2. **A definite answer removes the marker.** The result, or a failure that proves what happened (the request never reached the provider, a clustered host was unreachable, the provider refused the call before doing anything), is written with the marker removed.
3. **Any other failure keeps the marker.** A deadline, an `Unavailable` after the request was written, or an untyped error leaves the marker in place, and the object is **held**, never failed for it. The reason is `SnapshotOutcomeUnknown`, `ExportOutcomeUnknown`, `ImportOutcomeUnknown`, `CreateOutcomeUnknown` or `CloneOutcomeUnknown`, with a constant message and a `Warning` event.

What happens next depends on the call:

| Call | Sent again automatically when | Otherwise |
|---|---|---|
| `SnapshotCreate` through a **clustered** Provider | The routed create is idempotent per request token, so it is re-sent, at least a minute apart, **at most 10 times** | Held (`SnapshotOutcomeUnknown`) |
| `ExportDisk` / `ImportDisk` | The Provider lists the migration's staging backend in its capability `resend_safe_export_backends` / `resend_safe_import_backends` **and** 35 minutes have passed since the marker (the export deadline is 30 minutes); **at most 3 times** | Held (`ExportOutcomeUnknown` / `ImportOutcomeUnknown`) |
| `SnapshotRevert` of a `VirtualMachine` | The VM is still powered off and its spec asks for that, 6 minutes after the last attempt, doubling to 30 minutes; **at most 5 calls** | `status.snapshotRevert.phase: Failed` |
| `SnapshotCreate`, single-host Provider | Never | Held for an operator |

A provider image older than v0.4.0 does not report the re-send capabilities, so a lost export or import is held. Roll the providers promptly after the manager.

**Releasing a held object.** The hold's message names the action; the `Warning` event gives the attempt id. After checking the hypervisor for what the call may have made (a snapshot of that name, a disk landed for the target VM, a still-running export) and removing it, confirm the attempt by annotating the object with `virtrigaud.io/operation-outcome=not-performed@<attempt>`, where `<attempt>` is the marker condition's `lastTransitionTime`. For a VM `Create`, annotate with `virtrigaud.io/create-outcome`. Deleting the object also releases it, but anything the lost call made is yours to remove. The full runbook, the per-provider table of which failures are definite, and the limits are in [`docs/provider-call-outcomes.md`](https://github.com/projectbeskar/virtrigaud/blob/main/docs/provider-call-outcomes.md).

## A clustered host that stops answering

A clustered libvirt Provider (`spec.topology: cluster`, see the [clustered libvirt guide](../guides/clustered-libvirt.md)) runs every per-VM call on one host. The rules below keep one unreachable host from affecting the rest of the Provider:

- **It never opens the Provider's breaker.** Host-scoped answers are excluded from the breaker ([above](#what-does-not-count-as-a-failure)), so the VMs on the healthy hosts keep working.
- **It is answered in time.** Before a command of a routed call runs, the call waits for the host: for a command slot, for the SSH dial and handshake, and for an SSH session. These waits end **5 seconds before the call's deadline** (or a quarter of the time the call has left, when that is shorter), and a wait that ends there is treated as a host that did not answer, instead of letting the call run into the manager's own deadline and end with an unclassified error. The TCP connect of a dial stops after 30 s. A dial that another call already has in flight is waited for under the same bound. The single-host provider is unchanged. (`internal/providers/libvirt/host_answer.go`)
- **The answer says how far the call got.** If the host stopped answering before the call changed anything, the answer is `HOST_UNAVAILABLE` ("nothing was done") and the manager retries or re-places safely. If a command that may change the host was already sent, the answer is "outcome unknown" (`HOST_CONNECTION_LOST`) and the rules in [Calls whose outcome is unknown](#calls-whose-outcome-is-unknown) apply. For calls that can be safely repeated (`Power` `on`/`off`, a `SnapshotCreate` with a request token, `Clone`), the provider answers a retry form (`VM_OUTCOME_UNKNOWN_RETRY`) that the manager retries on the same host.
- **The VM shows it.** A bound VM whose host cannot be reached is `Ready=False` with reason `HostUnavailable` and is re-checked every 30 s; a pending create shows `Placed=False/HostUnavailable` and retries on the same host with the 15 s to 5 min backoff.
- **A delete is held, not abandoned.** A delete whose own host cannot be reached (or stopped answering mid-delete) keeps the finalizer and shows `DeleteBlocked=True` with reason `HostUnreachable`, naming the VM's own host (never another host, an endpoint or an address), plus one `Warning` event. It is retried with the same backoff and completes once the host answers. To release the VM without the provider's delete, annotate it `virtrigaud.io/orphan-on-delete: "true"` (the hypervisor VM is left running) or `virtrigaud.io/force-delete: "true"`. A cross-namespace consumer of a clustered Provider can use either annotation only if the Provider carries `infra.virtrigaud.io/allow-consumer-orphan-on-delete: "true"` (otherwise the VM shows `Ready=False/OrphanOnDeleteNotAllowed` or the `ForceDeleteRefused` condition, and the delete stays held).
- **A disk check that cannot run fails closed.** Before a clustered create, clone or delete touches a disk, the provider checks that no other domain on **any** host of the Provider uses it. A host that cannot be checked fails the operation (`VM_DISK_CHECK_FAILED` or `HOST_UNAVAILABLE`): nothing is written or removed on a partial answer, so a delete may wait until every host of the Provider answers.
- **Migration into a clustered Provider** never moves the target off its landing host automatically: a landing host that cannot be reached shows `Importing=False/TargetHostUnavailable` and is retried at 15 s doubling to 5 min.

The per-RPC behaviour, the restore guard (`RestorePending`) and the re-attach runbook are in the [clustered libvirt guide](../guides/clustered-libvirt.md) and in the main repository's [`docs/clustered-provider-inventory.md`](https://github.com/projectbeskar/virtrigaud/blob/main/docs/clustered-provider-inventory.md) and [`docs/provider-call-outcomes.md`](https://github.com/projectbeskar/virtrigaud/blob/main/docs/provider-call-outcomes.md).

## CircuitBreaker — programmatic API

You generally do **not** need to interact with the CircuitBreaker primitive directly — it is wired automatically on the gRPC RPC path. The API below is documented for reference and for reconciler authors who want to wrap a non-gRPC code path.

```go
import "github.com/projectbeskar/virtrigaud/internal/resilience"

config := &resilience.Config{
    FailureThreshold: 10,
    ResetTimeout:     60 * time.Second,
    HalfOpenMaxCalls: 3,
}

cb := resilience.NewCircuitBreaker("rpc", "vsphere", "prod", config)

err := cb.Call(ctx, func(ctx context.Context) error {
    return provider.Create(ctx, request)
})
```

Every error a wrapped function returns counts as a failure here: classify first, and return `nil` from the wrapped function for errors that should not count (the gRPC interceptor does exactly this).

The `Registry` is what the manager uses to allocate breakers per Provider:

```go
registry := resilience.NewRegistry(resilience.DefaultConfig())
cb := registry.GetOrCreate("rpc", "vsphere", "vsphere-prod")
```

## Rate limiting

The manager applies no rate limit to its provider calls, and the in-tree providers do not enable the SDK's rate-limit middleware (`Logging`, `Recovery` and `Auth` are the middleware they configure). `ResourceExhausted` from a provider is not counted against the breaker, so a provider that rate-limits you is retried without being declared down. The SDK's `middleware.RateLimitConfig` is available to external provider authors who want a server-side limit.

## Best Practices

### Error handling

1. **Always classify errors** — use appropriate error types so the breaker and the controllers can tell infrastructure failures from refusals.
2. **Preserve context** — wrap errors with additional context, but keep messages free of credentials and other tenants' names.
3. **Don't retry non-retryable errors** — check the error type first.
4. **Return a definite answer when you can prove one.** A provider that answers `Unknown` for a failure it could have classified makes the manager hold the object for an operator.

### CircuitBreakers

1. **Trust the per-Provider default.** Don't add a second layer in your reconciler without a measured reason.
2. **Alert on `virtrigaud_circuit_breaker_state > 0`.** This is your "provider is in trouble" signal.
3. **Monitor `virtrigaud_circuit_breaker_failures_total`.** A sustained non-zero rate with a closed breaker means you are close to the threshold.
4. **Investigate the provider, not the breaker.** A tripped breaker is a symptom; the root cause is in the provider pod or its hypervisor connectivity.

### Timeouts

1. **Propagate context** — always pass the incoming context through and check `ctx.Done()` in long operations.
2. **Respect the manager's deadline** — a provider that runs past the deadline makes the manager treat the outcome as unknown for calls that could duplicate work.
3. **Free resources on cancellation** — a command running on a hypervisor host outlives a cancelled call, so provider code must bound it (`timeout(1)`, locks) rather than rely on cancellation.
