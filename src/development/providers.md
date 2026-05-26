<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Writing a Provider

This page is aligned to **VirtRigaud v0.3.6** and describes how to build a
provider against the public SDK in
[`sdk/provider/`](https://github.com/projectbeskar/virtrigaud/tree/main/sdk/provider).
External providers are first-class — they implement the same gRPC contract
as the in-tree vSphere/Libvirt/Proxmox providers and the manager dials them
identically.

For the high-level "what is a provider" overview, see [Provider
Tutorial](../providers/tutorial.md). For day-2 operator concerns, see
[Operations](../operations/index.md).

## Two paths

| Path | When to use |
|------|------------|
| **In-tree** (`internal/providers/<name>/`) | You want your provider in the canonical repo; you're comfortable with the project's release cadence and contribution rules. Used by vSphere, Libvirt, Proxmox, Mock. Has direct access to the manager's internal helpers but lives inside the main Go module. |
| **Out-of-tree, SDK-based** (`sdk/provider/`) | You want to ship your own gRPC server and container image without forking the manager. The SDK is a **separate Go module** (`sdk/go.mod`) with a stable API surface. **This is the path this page documents.** |

If you're adding an in-tree provider, the [`add-provider`
skill](https://github.com/projectbeskar/virtrigaud/tree/main/.claude/skills/add-provider)
walks the scaffold step-by-step; the SDK path below is the public, external
authoring path.

!!! warning "CLI tooling that does not exist in v0.3.6"
    Earlier docs referenced `vrtg-provider init|verify|publish` commands.
    **No such CLI is shipped in v0.3.6.** No tooling generates provider
    scaffolds, validates capability declarations, or publishes provider
    images on your behalf. The SDK is consumed as a Go library; the build
    and publish workflow is whatever your project standardizes on (Docker
    + `go build` + your own registry push).

## Contract surface (v0.3.6)

The gRPC contract lives in
[`proto/provider/v1/provider.proto`](https://github.com/projectbeskar/virtrigaud/blob/main/proto/provider/v1/provider.proto)
and is a separate Go module. The RPCs your provider must implement (or
explicitly stub with `Unimplemented`) are:

```text
# Core lifecycle (all providers must implement)
rpc Validate(ValidateRequest)         returns (ValidateResponse);    // .proto:258
rpc Create(CreateRequest)             returns (CreateResponse);      // .proto:261
rpc Delete(DeleteRequest)             returns (TaskResponse);        // .proto:264
rpc Power(PowerRequest)               returns (TaskResponse);        // .proto:267
rpc Reconfigure(ReconfigureRequest)   returns (TaskResponse);        // .proto:270
rpc HardwareUpgrade(HardwareUpgradeRequest) returns (TaskResponse);  // .proto:273 (vSphere-specific in practice)
rpc Describe(DescribeRequest)         returns (DescribeResponse);    // .proto:276
rpc TaskStatus(TaskStatusRequest)     returns (TaskStatusResponse);  // .proto:279

# Snapshots (optional via capabilities)
rpc SnapshotCreate(SnapshotCreateRequest) returns (SnapshotCreateResponse);  // .proto:282
rpc SnapshotDelete(SnapshotDeleteRequest) returns (TaskResponse);            // .proto:283
rpc SnapshotRevert(SnapshotRevertRequest) returns (TaskResponse);            // .proto:284

# Clones (optional via capabilities)
rpc Clone(CloneRequest)               returns (CloneResponse);       // .proto:287

# Image management (optional via capabilities)
rpc ImagePrepare(ImagePrepareRequest) returns (TaskResponse);        // .proto:290

# Capabilities + migration support
rpc GetCapabilities(GetCapabilitiesRequest) returns (GetCapabilitiesResponse); // .proto:293
rpc ExportDisk(ExportDiskRequest)     returns (ExportDiskResponse);  // .proto:296
rpc ImportDisk(ImportDiskRequest)     returns (ImportDiskResponse);  // .proto:297
rpc GetDiskInfo(GetDiskInfoRequest)   returns (GetDiskInfoResponse); // .proto:298

# Inventory
rpc ListVMs(ListVMsRequest)           returns (ListVMsResponse);     // .proto:301
```

Returning `codes.Unimplemented` from an RPC is acceptable **only if**
your provider also advertises the absence via the capabilities mechanism —
otherwise the manager will try to call it and treat the
`Unimplemented` as a hard failure for migration / snapshot / clone flows.

## SDK packages

The SDK is laid out as five packages under
[`sdk/provider/`](https://github.com/projectbeskar/virtrigaud/tree/main/sdk/provider):

| Package | What it gives you | Source |
|--------|------------------|--------|
| `server` | gRPC + HTTP health server bootstrap, TLS config, keep-alive defaults, graceful shutdown. | `sdk/provider/server/server.go` |
| `middleware` | Unary + stream interceptors: recovery, logging, timeout, metrics, and **`Auth.RequireTLS` / `Auth.BearerTokenAuth`**. | `sdk/provider/middleware/middleware.go` |
| `capabilities` | Builder for `GetCapabilitiesResponse`. Encodes flags like `SupportsSnapshots`, `SupportsLinkedClones`. | `sdk/provider/capabilities/capabilities.go` |
| `errors` | Typed errors (`NewNotFound`, `NewInvalidSpec`, etc.) that map cleanly to gRPC status codes via `.GRPCStatus()`. | `sdk/provider/errors/errors.go` |
| `client` | High-level gRPC client (mostly useful for testing your provider end-to-end from another Go program). | `sdk/provider/client/client.go` |

The [`sdk/provider/doc.go`](https://github.com/projectbeskar/virtrigaud/blob/main/sdk/provider/doc.go)
is the canonical entry point; it includes a working server example.

### Compatibility commitment

`sdk/` is a separate Go module from `internal/`. Per
[`sdk/provider/doc.go`](https://github.com/projectbeskar/virtrigaud/blob/main/sdk/provider/doc.go):

> The SDK abstracts the underlying gRPC protocol and provides stable
> interfaces that will not change in minor releases, even if the internal
> RPC protocol evolves.

Breaking changes ship in **major** SDK releases only. The proto module
(`proto/`) is also separate; new RPCs land additively.

## Minimal SDK-based provider

```go
package main

import (
    "context"
    "log"
    "log/slog"

    "github.com/projectbeskar/virtrigaud/sdk/provider/capabilities"
    "github.com/projectbeskar/virtrigaud/sdk/provider/errors"
    "github.com/projectbeskar/virtrigaud/sdk/provider/middleware"
    "github.com/projectbeskar/virtrigaud/sdk/provider/server"

    providerv1 "github.com/projectbeskar/virtrigaud/proto/rpc/provider/v1"
)

// MyProvider is your provider implementation. It must satisfy the
// providerv1.ProviderServer interface (the embedded
// UnimplementedProviderServer lets the compiler accept partial impls
// during development).
type MyProvider struct {
    providerv1.UnimplementedProviderServer
    caps *capabilities.Manager
}

func (p *MyProvider) Validate(ctx context.Context, req *providerv1.ValidateRequest) (*providerv1.ValidateResponse, error) {
    // Your hypervisor reachability check goes here.
    return &providerv1.ValidateResponse{Healthy: true}, nil
}

func (p *MyProvider) Describe(ctx context.Context, req *providerv1.DescribeRequest) (*providerv1.DescribeResponse, error) {
    vm, ok := p.lookupVM(req.Id)
    if !ok {
        // Typed error → gRPC codes.NotFound automatically.
        return nil, errors.NewNotFound("VirtualMachine", req.Id)
    }
    return p.describeVM(vm), nil
}

func (p *MyProvider) GetCapabilities(ctx context.Context, req *providerv1.GetCapabilitiesRequest) (*providerv1.GetCapabilitiesResponse, error) {
    return p.caps.GetCapabilities(ctx, req)
}

// ... implement the rest of the contract, returning
// errors.NewUnimplemented(...) for RPCs you do not support and reflecting
// that in p.caps so the manager knows not to call them.

func main() {
    caps := capabilities.NewBuilder().
        Core().                          // Validate/Create/Delete/Power/Describe/GetCapabilities
        Snapshots().                     // We support snapshots
        DiskTypes("qcow2", "raw").
        NetworkTypes("bridge", "nat").
        Build()

    cfg := server.DefaultConfig()
    cfg.ServiceName = "my-provider"
    cfg.Port = 9443
    cfg.HealthPort = 8080
    cfg.Middleware = &middleware.Config{
        Recovery: &middleware.RecoveryConfig{Enabled: true},
        Logging:  &middleware.LoggingConfig{Enabled: true, Logger: slog.Default()},
        // To require mTLS on the gRPC channel — see the gotcha box below
        // about manager-side compatibility.
        // Auth: &middleware.AuthConfig{RequireTLS: true},
    }

    // To advertise TLS server side:
    // cfg.TLS = &server.TLSConfig{
    //     CertFile: "/etc/certs/tls.crt",
    //     KeyFile:  "/etc/certs/tls.key",
    //     CAFile:   "/etc/certs/ca.crt",
    //     RequireClientCert: true,
    // }

    srv, err := server.New(cfg)
    if err != nil {
        log.Fatalf("server.New: %v", err)
    }

    srv.RegisterProvider(&MyProvider{caps: caps})

    if err := srv.Serve(context.Background()); err != nil {
        log.Fatalf("Serve: %v", err)
    }
}
```

### Why the `Unimplemented` embedding matters

The generated gRPC code uses the
[forward-compatible service registration](https://grpc.io/blog/optional-grpc-go-fields/)
pattern: embedding `providerv1.UnimplementedProviderServer` in your struct
means proto evolution that adds new RPCs **does not break your provider's
build** — the unimplemented embeddings supply default `Unimplemented`
responses for the new RPCs until you fill them in. Always embed it.

## Capabilities — the contract for "what works"

The manager queries `GetCapabilities` after a successful `Validate` and
caches the result per Provider CR. Capabilities the manager reads from
`GetCapabilitiesResponse` (`proto/provider/v1/provider.proto`):

| Capability flag | Set via builder | Meaning |
|----------------|-----------------|---------|
| `supports_reconfigure_online` | `.OnlineReconfigure()` | CPU/memory changes while powered on. |
| `supports_disk_expansion_online` | `.OnlineDiskExpansion()` | Disk expansion while powered on. |
| `supports_snapshots` | `.Snapshots()` | `SnapshotCreate/Delete/Revert` work. |
| `supports_memory_snapshots` | `.MemorySnapshots()` | Snapshots include memory state. |
| `supports_linked_clones` | `.LinkedClones()` | `Clone` produces a linked (CoW) clone. |
| `supports_image_import` | `.ImageImport()` | `ImagePrepare` is meaningful. |
| `supported_disk_types[]` | `.DiskTypes(...)` | E.g. `"qcow2", "raw", "vmdk"`. |
| `supported_network_types[]` | `.NetworkTypes(...)` | E.g. `"bridge", "nat", "vlan"`. |

**Be honest.** Returning `supports_linked_clones: true` while having
`Clone` return a non-linked synthetic response is the kind of drift that
caused real audit findings against the in-tree libvirt provider in v0.3.6
(see [Libvirt Host Prep](../operations/libvirt-host-prepare.md#linked-clones-qcow2-backing-files)).
Reflect the real shape of your implementation; the operator's
[Provider Capabilities Matrix](../providers/providers-capabilities.md)
page is the source of truth they consult.

## Error handling

Use the typed constructors in `sdk/provider/errors`. They wrap a gRPC
`status.Status` with a structured error type and automatically map to the
right `codes.Code`:

```go
import "github.com/projectbeskar/virtrigaud/sdk/provider/errors"

// codes.NotFound
return nil, errors.NewNotFound("VirtualMachine", id)

// codes.InvalidArgument
return nil, errors.NewInvalidSpec("CPU count must be > 0, got %d", req.Cpu)

// codes.PermissionDenied
return nil, errors.NewPermissionDenied("describe VM")

// codes.Unavailable — typically used for hypervisor outages.
// The manager's CircuitBreaker counts these toward the failure threshold
// (FailureThreshold=10 by default, see internal/transport/grpc/client.go:isInfraFailure).
return nil, errors.NewUnavailable("vCenter", cause)
```

The full error-type list is in `sdk/provider/errors/errors.go:30-57`.

### What the manager's CircuitBreaker counts

Per `internal/transport/grpc/client.go:isInfraFailure`, the manager's
per-Provider CircuitBreaker (G6 / PR
[#112](https://github.com/projectbeskar/virtrigaud/pull/112)) counts these
gRPC codes as **infra failures** toward the threshold:

- `Unavailable`
- `DeadlineExceeded`

These are **not** counted (operational failures, not provider-health
issues):

- `NotFound`, `AlreadyExists`, `InvalidArgument`, `PermissionDenied`,
  `Unauthenticated`, `Canceled`, `FailedPrecondition`, `OutOfRange`.

Returning `Unavailable` for a transient SSH blip is exactly correct — the
breaker will Open after enough such failures, and your provider's
operator will see it via
`virtrigaud_circuit_breaker_state{provider=…}`.
Returning `Internal` for everything would deny the operator that signal.

See [Resilience](../operations/resilience.md) for the full classification.

## mTLS and bearer-token auth

The SDK supports both, with a v0.3.6 caveat about the manager side.

### Server side (your provider)

```go
cfg.TLS = &server.TLSConfig{
    CertFile: "/etc/certs/tls.crt",
    KeyFile:  "/etc/certs/tls.key",
    CAFile:   "/etc/certs/ca.crt",
    RequireClientCert: true,           // mTLS: require + verify client cert
}

cfg.Middleware = &middleware.Config{
    Auth: &middleware.AuthConfig{
        RequireTLS:  true,
        AllowedSANs: []string{"virtrigaud-manager.example.com"},

        // OR / AND
        BearerTokenAuth: true,
        ValidateToken: func(ctx context.Context, token string) error {
            // Validate the token however your platform does it (Vault,
            // OIDC, internal secret store, etc.)
            return nil
        },
    },
}
```

The interceptor is built at
`sdk/provider/middleware/middleware.go:222-292`.

### Manager side caveats in v0.3.6

!!! danger "The in-tree manager does NOT currently negotiate mTLS or send bearer tokens"
    - mTLS: `internal/runtime/remote/resolver.go:142-148` —
      `Resolver.buildTLSConfig` returns `nil, nil` unconditionally. The
      manager dials providers plaintext regardless of what the Provider CR
      says (#147).
    - Bearer tokens: `internal/transport/grpc/client.go` does not attach
      an `Authorization: Bearer …` metadata header on outbound RPCs
      (#148).

    If you enable `RequireTLS` or `BearerTokenAuth` on a provider that
    the in-tree manager dials, **the manager's RPCs will fail** with
    `Unauthenticated`. You have three options:

    1. Wait for #147 + #148 to land. Your provider's auth code is
       already correct; the manager's side is what needs the change.
    2. Run a manager fork with `Resolver.buildTLSConfig` filled in to
       parse `Provider.spec.runtime.service.tls.secretRef` and pass it
       through to the gRPC client.
    3. Don't enable provider-side auth, and lean on the K8s-network
       compensating controls described in
       [mTLS](../providers/security/mtls.md) and
       [Network Policies](../providers/security/network-policies.md).

See [mTLS](../providers/security/mtls.md) for the full status and the
roadmap.

## proto + SDK regeneration

The protobuf bindings are owned by the
[`proto/`](https://github.com/projectbeskar/virtrigaud/tree/main/proto)
module and regenerated with `buf`:

```bash
# In the virtrigaud repo root
make proto         # regen all Go bindings
make proto-lint    # buf lint
make proto-breaking # check for breaking changes vs origin/main
```

External providers should depend on a **published tag** of the `proto`
module (e.g. `proto/v0.3.6`), not on `main`. The proto module is tagged
separately via `make release-proto VERSION=v0.3.6`
(`Makefile:233-249`).

## Building and publishing

There is no opinionated build harness for external providers. The
in-tree providers use the `build/Dockerfile.manager` pattern
(parameterised on `BUILDER_IMAGE`/`BASE_IMAGE`/`GOPROXY`); you can
adopt that pattern or your own.

Minimal Dockerfile sketch for an SDK-based provider:

```dockerfile
# syntax=docker/dockerfile:1
ARG BUILDER_IMAGE=docker.io/golang:1.26.3
ARG BASE_IMAGE=gcr.io/distroless/static:nonroot

FROM ${BUILDER_IMAGE} AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/provider .

FROM ${BASE_IMAGE}
COPY --from=build /out/provider /provider
ENTRYPOINT ["/provider"]
EXPOSE 9443 8080
USER 65532:65532
```

Then wire the image into a `Provider` CR:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: my-provider
spec:
  type: my-provider                       # arbitrary string; surfaces in metric labels
  endpoint: my-provider.virtrigaud-system.svc:9443
  credentialSecretRef:
    name: my-provider-creds
  runtime:
    mode: Remote
    image: ghcr.io/my-org/my-provider:v0.1.0
    service:
      port: 9443
    # tls.secretRef field exists in the CRD but is not consumed by the
    # manager in v0.3.6 — see the box above.
```

## Reference implementations

The in-tree providers are the best examples; reading them is the fastest
way to understand the contract:

| Provider | File | Notes |
|---------|------|-------|
| **vSphere** | `internal/providers/vsphere/server.go` (~3842 LOC) | Pure-Go, uses `govmomi`. The most feature-complete in-tree provider. |
| **Libvirt** | `internal/providers/libvirt/server.go` (~752 LOC) + `internal/providers/libvirt/virsh.go` | Uses `virsh` over SSH (no `libvirt-go` CGO at runtime; SSH wrapper instead). Honest disclosures about `Clone` and `ImagePrepare` stubs. |
| **Proxmox** | `internal/providers/proxmox/server.go` | Uses Proxmox REST API with API-token auth (the recommended Proxmox posture). |
| **Mock** | `internal/providers/mock/` + `cmd/provider-mock/main.go` | The smallest complete provider; useful as a starting skeleton. |

A useful exercise when starting a new provider: read `cmd/provider-mock/main.go`
end-to-end; it's the SDK in production, minus a real hypervisor.

## See also

- [SDK doc.go](https://github.com/projectbeskar/virtrigaud/blob/main/sdk/provider/doc.go) — canonical usage example.
- [proto/provider/v1/provider.proto](https://github.com/projectbeskar/virtrigaud/blob/main/proto/provider/v1/provider.proto) — the contract.
- [Provider Tutorial](../providers/tutorial.md) — operator-facing walkthrough.
- [Provider Capabilities Matrix](../providers/providers-capabilities.md) —
  what each in-tree provider can and cannot do; useful as a comparison for
  declaring your own capabilities.
- [Resilience](../operations/resilience.md) — failure classification and
  CircuitBreaker behavior; informs your error-code choices.
- [mTLS](../providers/security/mtls.md), [Bearer Token](../providers/security/bearer-token.md), [Network Policies](../providers/security/network-policies.md) — security control gaps you should be aware of in v0.3.6.
