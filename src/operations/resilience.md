<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VirtRigaud Resilience Guide

This document describes the resilience patterns and error-handling mechanisms in VirtRigaud as of **v0.3.8**.

## Overview

VirtRigaud's resilience model is layered:

- **Error Taxonomy** — Structured error classification (`internal/providers/contracts`)
- **CircuitBreaker on the provider gRPC RPC path** — One breaker per Provider CR, **wired automatically** since v0.3.6 (G6 / #112). Operators get a visible signal when a provider goes bad and the manager stops hammering it.
- **Provider-side connection resilience** — The vSphere provider keeps its vCenter session alive and reconnects on a real probe failure; the libvirt provider retries transient SSH connection failures. Both landed in **v0.3.8** (#190, #191) and are documented below.
- **Migration-storage PVC safety** — The provider controller no longer deletes migration-storage PVCs out from under an in-flight migration (#184, v0.3.8).
- **Exponential Backoff** — Intelligent retry strategies for transient failures
- **Timeout Policies** — Per-RPC deadlines prevent resource exhaustion
- **Rate Limiting** — Provider-side protection

## CircuitBreaker on the Provider gRPC Path (v0.3.6)

### What changed in v0.3.6

The `internal/resilience/circuitbreaker.go` primitive has existed in the codebase for several releases, but **before v0.3.6 it had no production callsite on the gRPC path**. The manager would happily keep firing RPCs at a wedged provider, and operators had no metric signal that a provider was unhealthy.

v0.3.6 (G6 / PR #112) fixed that. The gRPC client constructor (`internal/transport/grpc/client.go`) now installs a `providerCircuitBreakerInterceptor` on every outbound RPC, fed by one breaker per `Provider` CR.

### Architecture

```
VirtualMachine reconciler
        │
        │ resolver.GetProvider(ctx, vm.Spec.ProviderRef)
        ▼
remote.Resolver
        │  cbRegistry.GetOrCreate("provider-grpc",
        │                          provider.Spec.Type,
        │                          provider.Name)
        ▼
resilience.Registry  ────►  resilience.CircuitBreaker  (one per Provider CR)
        │                              │
        ▼                              │ wraps every RPC via
grpc.Client                            │ providerCircuitBreakerInterceptor
        │ chained unary interceptors:  │
        │   1. providerRPCMetricsInterceptor (G4)  ──► virtrigaud_provider_rpc_*
        │   2. providerCircuitBreakerInterceptor   ──► virtrigaud_circuit_breaker_*
        ▼
provider-vsphere / provider-libvirt / provider-proxmox
```

Important properties of the v0.3.6 wiring:

- **One breaker per `Provider` CR**, allocated lazily on first use by the `remote.Resolver`. Allocation key: `(providerType, providerName, "provider-grpc")`. Breakers are removed from the registry when the resolver invalidates a Provider connection.
- **Interceptor order matters.** The metrics interceptor runs *before* the breaker interceptor, so every RPC (including breaker fast-fails, which surface as `code=Unavailable`) shows up in `virtrigaud_provider_rpc_requests_total`. Operators see breaker-rejected RPCs as `Unavailable` in their RPC dashboards — not as silent drops.
- **The interceptor never panics**, by design. If it did, every provider RPC in the cluster would break.

### Default configuration

`resilience.DefaultConfig()`:

| Setting | Value | Meaning |
|---|---|---|
| `FailureThreshold` | `10` | Number of consecutive infra-class failures that trip the breaker from Closed → Open. |
| `ResetTimeout` | `60s` | After this much time in Open, the next call admits the breaker to Half-Open. |
| `HalfOpenMaxCalls` | `3` | Number of trial calls admitted in Half-Open. All three must succeed to close the breaker; any single failure re-opens it. |

These thresholds apply uniformly to all Provider CRs in v0.3.6. Per-Provider override is on the roadmap.

### Failure classification — what trips the breaker

The breaker is opinionated about which errors count toward the failure threshold. This matters: a `NotFound` on a deleted VM should not contribute to the manager deciding the whole provider is down.

`internal/transport/grpc/client.go:isInfraFailure` classifies as follows.

**Infra-class — counts toward the threshold:**

| gRPC code | Meaning |
|---|---|
| `Unavailable` | Provider pod down, network partition, mTLS handshake failed |
| `DeadlineExceeded` | Provider hung past the call timeout |
| `Internal` | Provider crashed mid-call |
| `Unknown` | Non-gRPC error from the transport layer (e.g. TCP reset) |

**Business-class — passes through, does NOT trip the breaker:**

| gRPC code | Why it shouldn't trip the breaker |
|---|---|
| `OK` | Obvious success |
| `Canceled` | Caller gave up, not the provider failing |
| `NotFound` | VM doesn't exist — the provider is healthy, the request was bad |
| `InvalidArgument` | Provider correctly rejected a malformed request |
| `AlreadyExists` | Provider correctly rejected a duplicate |
| `FailedPrecondition` | Provider in a state that rejects this RPC right now |
| `PermissionDenied` | Auth working as expected |
| `Unauthenticated` | Same |
| `ResourceExhausted` | Rate-limit signal — caller should back off this one call, not stop talking to the provider |
| `Aborted`, `OutOfRange`, `Unimplemented` | Protocol-level, unrelated to provider health |

Rationale: the breaker should fire when "the provider as a whole is in trouble," not when "one request was bad."

### What happens when the breaker is open

When the breaker is Open and an RPC arrives, the interceptor **does not invoke the provider call**. Instead, it synthesises a canonical `codes.Unavailable` status:

```
circuit breaker open: <breaker-name>
```

Downstream code paths — `c.mapGRPCError`, callers that do `errors.Is(err, contracts.RetryableError)`, the controller-runtime retry loop — all treat this exactly like any other `Unavailable` from the provider. Operators don't need a special handling path for "breaker open" vs "provider down."

### State machine

```
       FailureThreshold infra-failures
   ┌────────────────────────────────────►┌─────────┐
   │                                      │  Open   │◄──┐ infra-failure
┌──┴──────┐                                └────┬────┘   │
│ Closed  │                                     │        │
└──┬──────┘                                     │ ResetTimeout elapses
   ▲                                            ▼
   │ all HalfOpenMaxCalls succeed     ┌───────────────┐
   └──────────────────────────────────│  Half-Open    │
                                       │ (≤ 3 trial    │
                                       │  RPCs)        │
                                       └───────────────┘
```

- **Closed** — Normal operation. Each infra-class failure increments a counter; reaching `FailureThreshold` transitions to Open. Each success resets the counter.
- **Open** — Fast-fail mode. RPCs return `Unavailable` without hitting the provider. After `ResetTimeout` (60s default), the *next* RPC admits the breaker to Half-Open and counts as the first half-open call (see issue #96).
- **Half-Open** — Up to `HalfOpenMaxCalls` (3) trial RPCs are admitted. All three must succeed to transition back to Closed; any single infra-failure during this window re-opens the breaker.

### Metrics

```
# Gauge: current state. 0=Closed, 1=Half-Open, 2=Open.
virtrigaud_circuit_breaker_state{provider_type="vsphere", provider="vsphere-prod"} 0

# Counter: every infra-class failure recorded against the breaker.
virtrigaud_circuit_breaker_failures_total{provider_type="vsphere", provider="vsphere-prod"} 5
```

Both families have one series per `Provider` CR. Suggested operator alerts:

- `virtrigaud_circuit_breaker_state > 0` — any breaker in a non-Closed state across the fleet.
- `rate(virtrigaud_circuit_breaker_failures_total[5m]) > 0` — sustained infra failures even before the breaker trips.

### Operational note from the v0.3.6-rc1 smoke

On the v0.3.6-rc1 deploy to the `vr1.lab.k8` lab cluster, **the libvirt breaker tripped to Open immediately**. This was the metric working exactly as designed: the lab's libvirt provider had a pre-existing SSH-connectivity issue (tracked as #I1) that was silently failing every RPC in v0.3.5 with no operator-visible signal. Post-v0.3.6, the breaker surfaced it via the gauge within seconds.

The expected operator response to a tripped breaker is:

1. Check `virtrigaud_provider_rpc_requests_total{code="Unavailable"}` to confirm the failure pattern is on the provider, not the manager.
2. Investigate the provider pod (`kubectl logs deployment/provider-<name>`) and its hypervisor connectivity.
3. The breaker will self-recover once underlying connectivity is restored — no manual reset required. (`(*resilience.CircuitBreaker).Reset()` exists for emergency use but is not exposed via an admin API in v0.3.6.)

## Provider-side connection resilience (v0.3.8)

The circuit breaker above protects the manager from a *wedged* provider. v0.3.8
adds the complementary layer: making the providers themselves survive the
transient hypervisor-connectivity failures that previously tripped the breaker
unnecessarily. These are provider-internal behaviors — no Provider CR change is
required to benefit from them.

### vSphere: vCenter session keepalive + real-probe reconnect (#190)

Before v0.3.8, a vSphere provider that sat idle for a long time (no VMs being
created, a quiet overnight window) could have its vCenter session silently
expire. The next RPC would fail with `NotAuthenticated`, surface to the manager
as an infra-class failure, and — after enough of them — trip the per-Provider
circuit breaker. The operator-visible symptom was a provider that looked healthy
all day and went `ProviderAvailable=False` after an idle period.

v0.3.8 ([#190](https://github.com/projectbeskar/virtrigaud/pull/190)) fixes this
on the provider side:

- The provider runs a **session keepalive** so an otherwise-idle vCenter session
  does not lapse.
- `Validate` performs a **real probe** against vCenter rather than trusting a
  cached session handle, so a stale session is detected at health-check time
  rather than on the next mutating RPC.
- When the probe detects a dead session, the provider **reconnects
  transparently** and retries, so a single expired session does not surface as a
  user-visible failure.

The net effect: a vSphere provider survives long idle periods without the
`NotAuthenticated` storm that used to trip the breaker. If you previously saw
`virtrigaud_circuit_breaker_state{provider_type="vsphere"}` flip to Open after
quiet windows, that pattern should disappear after upgrading to v0.3.8.

### Libvirt: retry transient SSH connection failures (#191)

The libvirt provider drives the host over SSH (`virsh` subprocess). Bursts of
short-lived SSH connections — common during reconcile storms or migration RPC
sequences — can hit transient handshake failures such as
`kex_exchange_identification: Connection closed by remote host`, often because
the host's `sshd` is rate-limiting concurrent unauthenticated connections.

v0.3.8 ([#191](https://github.com/projectbeskar/virtrigaud/pull/191)) makes the
libvirt provider **retry these transient SSH connection failures with bounded
backoff** instead of failing the RPC on the first stumble. A connection that
would previously have counted as an infra-class failure (and pushed the breaker
toward Open) now recovers within the provider.

!!! note "Client-side mitigation; tune the host too"
    The retry is the *client-side* half of the fix. If your libvirt host's
    `sshd` `MaxStartups` is low (or `fail2ban` is aggressive), bursts can still
    exhaust the host's connection budget faster than the provider can back off.
    See [Libvirt Host Preparation](libvirt-host-prepare.md) for the host-side
    `MaxStartups` / `fail2ban` tuning that complements this retry.

### Migration-storage PVC safety (#184)

The provider controller annotates Provider CRs with a migration PVC and rolls
the provider pods to mount it (see [VM Migration Guide](../migration/vm-migration-guide.md)).
In v0.3.8 ([#184](https://github.com/projectbeskar/virtrigaud/pull/184)) the
provider controller **no longer deletes migration-storage PVCs** as part of its
reconcile, and it **watches** those PVCs so a roll does not race their lifecycle.
Ownership and cleanup of the intermediate PVC remain with the `VMMigration` CR
(see [VMMigration API Reference](../migration/api-reference.md#finalizer)). This
removes a class of failure where an in-flight migration's transfer medium could
be reclaimed before the import completed.

## Error Taxonomy

### Error Types

VirtRigaud classifies all provider-returned errors into specific categories. The classification drives controller retry behaviour and the conditions surfaced on each CR.

| Type | Retryable | Description | Example |
|------|-----------|-------------|---------|
| `NotFound` | No | Resource doesn't exist | VM not found |
| `InvalidSpec` | No | Invalid configuration | Malformed VM spec |
| `Unauthorized` | No | Authentication failed | Invalid credentials |
| `NotSupported` | No | Unsupported operation | Feature not available |
| `Retryable` | Yes | Transient error | Network timeout |
| `Unavailable` | Yes | Service unavailable | Provider down — **including circuit-breaker open** |
| `RateLimit` | Yes | Rate limited | API quota exceeded |
| `Timeout` | Yes | Operation timeout | Long-running task |
| `QuotaExceeded` | No | Resource quota hit | Storage full |
| `Conflict` | No | Resource conflict | Duplicate name |

### Error Creation (provider authors)

```go
import "github.com/projectbeskar/virtrigaud/internal/providers/contracts"

// Create specific error types
err := contracts.NewNotFoundError("VM not found", originalErr)
err := contracts.NewRetryableError("Network timeout", originalErr)
err := contracts.NewUnavailableError("Provider unavailable", originalErr)

// Check if error is retryable
if providerErr, ok := err.(*contracts.ProviderError); ok {
    if providerErr.IsRetryable() {
        // Retry the operation
    }
}
```

## CircuitBreaker — programmatic API

You generally do **not** need to interact with the CircuitBreaker primitive directly in v0.3.6 — it is wired automatically on the gRPC RPC path. The API below is documented for reference and for advanced reconciler authors who want to wrap a non-gRPC code path.

### Direct construction

```go
import "github.com/projectbeskar/virtrigaud/internal/resilience"

config := &resilience.Config{
    FailureThreshold: 10,
    ResetTimeout:     60 * time.Second,
    HalfOpenMaxCalls: 3,
}

cb := resilience.NewCircuitBreaker("provider-vsphere", "vsphere", "prod", config)
```

### Usage

```go
err := cb.Call(ctx, func(ctx context.Context) error {
    // Call the potentially failing operation
    return provider.Create(ctx, request)
})

if err != nil {
    // Handle error (may be circuit breaker protection)
    log.Error(err, "Operation failed")
}
```

### Registry

The `Registry` is what the manager uses to allocate breakers per Provider CR. If you need similar per-target isolation in your own code, use the same pattern:

```go
registry := resilience.NewRegistry(resilience.DefaultConfig())
cb := registry.GetOrCreate("my-operation", "vsphere", "vsphere-prod")
// ... use cb ...
registry.Remove("my-operation", "vsphere", "vsphere-prod") // on Provider deletion
```

## Retry Strategies

### Exponential Backoff

```go
import "github.com/projectbeskar/virtrigaud/internal/resilience"

config := &resilience.RetryConfig{
    MaxAttempts: 5,
    BaseDelay:   500 * time.Millisecond,
    MaxDelay:    30 * time.Second,
    Multiplier:  2.0,
    Jitter:      true,
}

err := resilience.Retry(ctx, config, func(ctx context.Context, attempt int) error {
    return provider.Describe(ctx, vmID)
})
```

### Backoff Calculation

For attempt `n`:
```
delay = BaseDelay × Multiplier^n
delay = min(delay, MaxDelay)
if Jitter:
    delay += random(0, delay * 0.1)
```

Example delays with `BaseDelay=500ms`, `Multiplier=2.0`:
- Attempt 0: 500ms
- Attempt 1: 1s
- Attempt 2: 2s
- Attempt 3: 4s
- Attempt 4: 8s

### Predefined Configurations

```go
// For frequent, low-latency operations
aggressive := resilience.AggressiveRetryConfig()
// MaxAttempts: 10, BaseDelay: 100ms, Multiplier: 1.5

// For expensive operations
conservative := resilience.ConservativeRetryConfig()
// MaxAttempts: 3, BaseDelay: 1s, Multiplier: 3.0

// Disable retries
none := resilience.NoRetryConfig()
// MaxAttempts: 1
```

## Timeout Policies

### Per-RPC Timeouts

Each RPC in the gRPC client has its own context deadline (`internal/transport/grpc/client.go`):

| RPC | Default deadline | Rationale |
|---|---|---|
| `Validate` | 30s | Cheap health check |
| `Describe` | 30s | Read-only state query |
| `Power` | 2 min | State change + provider confirmation |
| `Delete` | 2 min | Provider cleanup may take time |
| `Create` | 5 min | Template clone / disk provisioning |
| `Reconfigure` | 5 min | Hot-plug or restart-required path |
| `TaskStatus` | 10s | Poll, must be cheap |
| `SnapshotCreate` | 5 min | Memory + disk capture |
| `ExportDisk` / `ImportDisk` | 30 min | Large data transfer |
| `GetDiskInfo` | 2 min | Backing-chain walk |
| `ListVMs` | 2 min | Full provider enumeration (used by VMAdoption) |

When a deadline expires, the gRPC client returns `DeadlineExceeded`, which (a) is mapped to `contracts.RetryableError` for the caller and (b) counts as an infra-class failure toward the CircuitBreaker.

### Context Propagation (provider authors)

Always respect context deadlines:

```go
func (p *Provider) Create(ctx context.Context, req CreateRequest) error {
    // Check if context is already cancelled
    select {
    case <-ctx.Done():
        return ctx.Err()
    default:
    }

    // Perform operation with context
    return p.performCreate(ctx, req)
}
```

## Rate Limiting

### Provider Protection

```go
import "golang.org/x/time/rate"

// Configure rate limiter
limiter := rate.NewLimiter(
    rate.Limit(config.RateLimit.QPS),    // 10 requests per second
    config.RateLimit.Burst,              // Allow bursts of 20
)

// Check rate limit before operation
if !limiter.Allow() {
    return contracts.NewRateLimitError("Rate limit exceeded", nil)
}

// Proceed with operation
return provider.Create(ctx, request)
```

`ResourceExhausted` (gRPC code) is *not* an infra-class failure and will not trip the CircuitBreaker — see [Failure classification](#failure-classification-what-trips-the-breaker).

## Condition Mapping

### VM Conditions

VirtRigaud sets standard conditions based on operations:

| Condition | Status | Reason | Description |
|-----------|--------|--------|-------------|
| `Ready` | True | `VMReady` | VM is ready for use |
| `Ready` | False | `ProviderError` | Provider operation failed |
| `Ready` | False | `ValidationError` | Spec validation failed |
| `Provisioning` | True | `Creating` | VM creation in progress |
| `Provisioning` | False | `CreateFailed` | VM creation failed |

### Provider Conditions

| Condition | Status | Reason | Description |
|-----------|--------|--------|-------------|
| `ProviderRuntimeReady` | True | `DeploymentReady` | Remote runtime ready |
| `ProviderRuntimeReady` | False | `DeploymentError` | Deployment failed |
| `ProviderAvailable` | True | `HealthCheckPassed` | Provider healthy |
| `ProviderAvailable` | False | `HealthCheckFailed` | Provider unhealthy |

### Error to Condition Mapping

```go
func mapErrorToCondition(err error) metav1.Condition {
    if providerErr, ok := err.(*contracts.ProviderError); ok {
        switch providerErr.Type {
        case contracts.ErrorTypeNotFound:
            return metav1.Condition{
                Type:    "Ready",
                Status:  metav1.ConditionFalse,
                Reason:  "ResourceNotFound",
                Message: providerErr.Message,
            }
        case contracts.ErrorTypeUnauthorized:
            return metav1.Condition{
                Type:    "Ready",
                Status:  metav1.ConditionFalse,
                Reason:  "AuthenticationFailed",
                Message: providerErr.Message,
            }
        case contracts.ErrorTypeUnavailable:
            return metav1.Condition{
                Type:    "Ready",
                Status:  metav1.ConditionFalse,
                Reason:  "ProviderUnavailable",
                Message: providerErr.Message,
            }
        }
    }

    // Default error condition
    return metav1.Condition{
        Type:    "Ready",
        Status:  metav1.ConditionFalse,
        Reason:  "InternalError",
        Message: err.Error(),
    }
}
```

## Best Practices

### Error Handling

1. **Always classify errors** — Use appropriate error types so the breaker can distinguish infra failures from business errors.
2. **Preserve context** — Wrap errors with additional context.
3. **Avoid retrying non-retryable errors** — Check error type first.
4. **Set meaningful conditions** — Help users understand state.

### CircuitBreakers

1. **Trust the per-Provider default.** v0.3.6 gives you one breaker per Provider CR automatically; don't add a second layer in your reconciler unless you have a measured reason.
2. **Alert on `virtrigaud_circuit_breaker_state > 0`.** This is your "provider is in trouble" signal.
3. **Monitor `virtrigaud_circuit_breaker_failures_total` rate.** Sustained non-zero rate even with a closed breaker means you're skating close to the threshold.
4. **Investigate the provider, not the breaker.** A tripped breaker is a symptom; the root cause is in the provider pod or its hypervisor connectivity.

### Timeouts

1. **Operation-appropriate** — Different timeouts for different ops (the defaults above are calibrated; override only with measurement).
2. **Propagate context** — Always pass context through.
3. **Handle cancellation** — Check `context.Done()` regularly in long-running operations.
4. **Resource cleanup** — Ensure resources are freed on timeout.

### Rate Limiting

1. **Provider protection** — Prevent overwhelming providers.
2. **Burst handling** — Allow reasonable bursts.
3. **Back-pressure** — Surface rate limits to users.
4. **Fair sharing** — Consider tenant isolation.

## Configuration Examples

### Development Environment

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: virtrigaud-config
data:
  # Relaxed timeouts for development
  RPC_TIMEOUT_MUTATING: "10m"

  # Aggressive retries for flaky dev environments
  RETRY_MAX_ATTEMPTS: "10"
  RETRY_BASE_DELAY: "100ms"

  # Lower circuit breaker threshold
  CB_FAILURE_THRESHOLD: "5"
  CB_RESET_SECONDS: "30s"
```

### Production Environment

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: virtrigaud-config
data:
  # Strict timeouts
  RPC_TIMEOUT_MUTATING: "4m"
  RPC_TIMEOUT_DESCRIBE: "30s"

  # Conservative retries
  RETRY_MAX_ATTEMPTS: "3"
  RETRY_BASE_DELAY: "1s"
  RETRY_MAX_DELAY: "60s"

  # Higher circuit breaker threshold
  CB_FAILURE_THRESHOLD: "15"
  CB_RESET_SECONDS: "120s"

  # Rate limiting
  RATE_LIMIT_QPS: "20"
  RATE_LIMIT_BURST: "50"
```

> **Note (still current as of v0.3.8):** The CircuitBreaker uses `resilience.DefaultConfig()` unconditionally — the per-Provider override via the ConfigMap above is still on the roadmap and was not added in v0.3.8. The values shown are the design target. Track progress in the [CHANGELOG](https://github.com/projectbeskar/virtrigaud/blob/main/CHANGELOG.md).
