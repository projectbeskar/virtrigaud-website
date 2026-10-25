<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Writing a Provider

This page is aligned to **VirtRigaud v0.4.0** and describes how to build a
provider against the public SDK in
[`sdk/provider/`](https://github.com/projectbeskar/virtrigaud/tree/v0.4.0/sdk/provider).
External providers are first-class — they implement the same gRPC contract
as the in-tree vSphere/Libvirt/Proxmox providers and the manager dials them
identically.

For the high-level "what is a provider" overview, see [Provider
Tutorial](../providers/tutorial.md). For day-2 operator concerns, see
[Operations](../operations/index.md).

## Two paths

| Path | When to use |
|------|------------|
| **In-tree** (`internal/providers/<name>/`) | You want your provider in the canonical repo; you're comfortable with the project's release cadence and contribution rules. Used by vSphere, Libvirt, Proxmox, Mock. Has direct access to the manager's internal helpers but lives inside the main Go module. A new in-tree provider needs a `cmd/provider-<name>/` binary, every RPC implemented (or answered `Unimplemented` and declared through its capabilities), and an entry in the `spec.type` enum. |
| **Out-of-tree, SDK-based** (`sdk/provider/`) | You want to ship your own gRPC server and container image without forking the manager. The SDK is a **separate Go module** (`sdk/go.mod`) with a stable API surface. **This is the path this page documents.** |

!!! warning "`spec.type` is a closed enum"
    `Provider.spec.type` accepts `vsphere`, `libvirt`, `firecracker`, `qemu` or
    `proxmox` (the `ProviderType` enum in
    `api/infra.virtrigaud.io/v1beta1/provider_types.go`) and is immutable. An
    out-of-tree provider runs under one of those values (it also selects the
    `provider_type` metric label); adding a new value is an API change in the
    main repository.

### The `vrtg-provider` scaffolder

`vrtg-provider init|generate|verify|publish` scaffolds and checks a provider
project (see the [CLI Tools
Reference](../references/cli-tools.md#vrtg-provider)):

```bash
vrtg-provider init myprovider --type libvirt --virtrigaud-path /path/to/virtrigaud
cd providers/myprovider
go mod tidy
make build
make test
vrtg-provider verify
```

- `init` writes a project whose provider answers `Validate` and `GetCapabilities` and returns `Unimplemented` for the VM operations, with a test, a `Makefile`, a `Dockerfile` and a
  CI workflow. `--type` accepts `generic`, `vsphere`, `libvirt`, `firecracker`
  and `qemu` (not `proxmox`); it selects the scaffold's template and is separate from
  the closed `Provider.spec.type` enum above.
- The SDK and proto modules have no version tags of their own, so the
  generated `go.mod` resolves them from a local VirtRigaud checkout through
  `replace` directives: `init` finds the checkout when the project is created
  inside it, otherwise pass `--virtrigaud-path`. The generated `Dockerfile`
  cannot see that checkout, so build the image from a context that contains
  both, or adjust it.
- `verify` builds the project, runs its unit tests and reports `gofmt`,
  `go vet` and `golangci-lint` findings. It does **not** run the conformance
  suite, and `vcts run` cannot pass yet (the runner implements no steps).
- `publish` writes a catalog entry and records conformance as not run
  (`core: skip`); it never claims a pass.

[`cmd/provider-mock/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/cmd/provider-mock/main.go)
together with `internal/providers/mock/` is a fuller reference implementation.

## Consuming the SDK from your own module

The `sdk/` and `proto/` modules do not have published version tags (there are
no `sdk/vX.Y.Z` or `proto/vX.Y.Z` tags), and `sdk/go.mod` requires
`proto v0.1.0`, so a plain `go get` of the SDK does not resolve. Pin both
modules to the commit of the release tag and redirect the `proto` requirement
to the same commit:

```bash
REV=$(git -C /path/to/virtrigaud rev-list -n1 v0.4.0)

go get github.com/projectbeskar/virtrigaud/proto@$REV

# go prints the proto pseudo-version it selected, e.g. v0.0.0-<date>-<hash>
go mod edit -replace \
  github.com/projectbeskar/virtrigaud/proto@v0.1.0=github.com/projectbeskar/virtrigaud/proto@<that-pseudo-version>

# The SDK imports internal packages of the root module, so pin the root
# module and the SDK to the same commit AFTER the replace (go get of proto
# drops the SDK requirement, and go mod tidy would otherwise pick main)
go get github.com/projectbeskar/virtrigaud@$REV
go get github.com/projectbeskar/virtrigaud/sdk@$REV
go mod tidy
```

Check `go.mod` afterwards: `sdk`, the root module and `proto` should all name the release commit.

(Alternatively, check the repository out next to your module and use two
local `replace` directives, as the root `go.mod` does.) The generated Go
bindings are imported from `github.com/projectbeskar/virtrigaud/proto/rpc/provider/v1`.

## Contract surface (v0.4.0)

The gRPC contract lives in
[`proto/provider/v1/provider.proto`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/proto/provider/v1/provider.proto)
(service `provider.v1.Provider`) and is a separate Go module. The RPCs your
provider must implement (or explicitly answer with `Unimplemented`) are:

```text
# Core lifecycle (all providers must implement)
rpc Validate(ValidateRequest)         returns (ValidateResponse);
rpc Create(CreateRequest)             returns (CreateResponse);
rpc Delete(DeleteRequest)             returns (TaskResponse);
rpc Power(PowerRequest)               returns (TaskResponse);
rpc Reconfigure(ReconfigureRequest)   returns (TaskResponse);
rpc HardwareUpgrade(HardwareUpgradeRequest) returns (TaskResponse);  // vSphere-specific in practice
rpc Describe(DescribeRequest)         returns (DescribeResponse);
rpc TaskStatus(TaskStatusRequest)     returns (TaskStatusResponse);

# Snapshots (optional via capabilities)
rpc SnapshotCreate(SnapshotCreateRequest) returns (SnapshotCreateResponse);
rpc SnapshotDelete(SnapshotDeleteRequest) returns (TaskResponse);
rpc SnapshotRevert(SnapshotRevertRequest) returns (TaskResponse);

# Clones (optional via capabilities)
rpc Clone(CloneRequest)               returns (CloneResponse);

# Image management (optional via capabilities)
rpc ImagePrepare(ImagePrepareRequest) returns (ImagePrepareResponse);

# Capabilities + migration support
rpc GetCapabilities(GetCapabilitiesRequest) returns (GetCapabilitiesResponse);
rpc ExportDisk(ExportDiskRequest)     returns (ExportDiskResponse);
rpc ImportDisk(ImportDiskRequest)     returns (ImportDiskResponse);
rpc GetDiskInfo(GetDiskInfoRequest)   returns (GetDiskInfoResponse);
rpc DeleteStagedDisk(DeleteStagedDiskRequest) returns (DeleteStagedDiskResponse);  // nfs / s3 staging cleanup
rpc DeleteLandedDisk(DeleteLandedDiskRequest) returns (DeleteLandedDiskResponse);  // unused imported disk cleanup

# Inventory and ownership
rpc ListVMs(ListVMsRequest)           returns (ListVMsResponse);
rpc TransferOwner(TransferOwnerRequest) returns (TransferOwnerResponse);

# Host inventory (clustered providers only)
rpc ListHosts(ListHostsRequest)       returns (ListHostsResponse);
rpc GetHostInfo(GetHostInfoRequest)   returns (HostInfo);
```

Returning `codes.Unimplemented` from an RPC is acceptable **only if**
your provider also advertises the absence via the capabilities mechanism —
otherwise the manager will try to call it and treat the
`Unimplemented` as a hard failure for migration / snapshot / clone flows.
For the optional RPCs added since v0.3.11 the matching declarations are:

| RPC | Declare the absence by |
|-----|------------------------|
| `ListHosts`, `GetHostInfo` | Answering `Unimplemented` and reporting `supports_clustering = false` (every non-clustered provider). |
| `DeleteStagedDisk` | Leaving a backend out of `supported_staged_disk_delete_backends` (empty means the manager never sends it and records the staged object as left behind). |
| `DeleteLandedDisk` | `supports_landed_disk_delete = false`. |
| `TransferOwner` | `supports_owner_transfer = false` (single-host) and `supports_routed_adoption = false` (clustered). |

## Ownership and clustered providers

Two contracts matter to every provider author, because the manager sends the
fields to every provider and keys safety decisions on what the provider reports:

- **Owner stamps.** `CreateRequest.owner` (an `ObjectIdentity` with `uid`,
  `namespace`, `name`) identifies the `VirtualMachine` a create is for. A
  provider whose hypervisor-side names are not unique across namespaces stamps
  the owner onto the VM it creates, treats a create for a VM that already exists
  as an idempotent success **only** when the stamp carries the same `uid`, and
  otherwise fails closed with `ALREADY_EXISTS`. `ListVMs` reports each VM's
  `owner_namespace` / `owner_name` (and `owner_uid` in `provider_raw`), honours
  the optional `ListVMsRequest.owner_namespace` / `owner_name` filter, and
  `TransferOwner` re-stamps a VM compare-and-swap when the manager adopts it.
  Advertise what you implement with `supports_owner_rebind` (Create and Clone
  re-bind to the VM an earlier attempt made, never a second one),
  `supports_owner_transfer`, `supports_list_owner_filter` and
  `supports_routed_adoption`.
- **Clustered providers.** A Provider with `spec.topology: cluster` fronts
  several hosts. The manager decides placement and sends the chosen host as
  `target_host_id` on the per-VM requests (and `source_host_id` on `Clone`);
  single-host providers never receive it. A clustered provider must route by it,
  must not default to some host when it is empty, implements `ListHosts` /
  `GetHostInfo` (returning `HostInfo` with allocatable CPU, memory and storage,
  health, labels and CPU/emulator details), tags every `VMInfo` with `host_id`
  and names the hosts it could not list in `ListVMsResponse.unreachable_host_ids`,
  and reports `supports_clustering` (plus `supports_routed_clone`,
  `supports_routed_import` and the flags above). See the
  [Libvirt provider guide](../providers/libvirt.md) for the operator-side
  behaviour.

Both are additive in the proto: a provider that predates them keeps working
and the manager falls back to the earlier behaviour (for example, it never
re-sends an uncertain Create to a provider that does not report
`supports_owner_rebind`).

## SDK packages

The SDK is laid out as five packages under
[`sdk/provider/`](https://github.com/projectbeskar/virtrigaud/tree/v0.4.0/sdk/provider):

| Package | What it gives you | Source |
|--------|------------------|--------|
| `server` | gRPC + HTTP health server bootstrap, TLS config (including certificate hot-reload and `ResolveTLSAndAuth`), keep-alive defaults, optional `/metrics` handler, graceful shutdown. | `sdk/provider/server/server.go`, `sdk/provider/server/tlsconfig.go` |
| `middleware` | Unary + stream interceptors: recovery, logging, timeout, metrics, rate limiting, and **`Auth.RequireTLS` / `Auth.BearerTokenAuth`**. | `sdk/provider/middleware/middleware.go` |
| `capabilities` | Builder for `GetCapabilitiesResponse`. Encodes flags like `SupportsSnapshots`, `SupportsLinkedClones`. | `sdk/provider/capabilities/capabilities.go` |
| `errors` | Typed errors (`NewNotFound`, `NewInvalidSpec`, etc.) that map cleanly to gRPC status codes via `.GRPCStatus()`. | `sdk/provider/errors/errors.go` |
| `client` | High-level gRPC client (mostly useful for testing your provider end-to-end from another Go program). | `sdk/provider/client/client.go` |

The [`sdk/provider/doc.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/sdk/provider/doc.go)
is the canonical entry point; it includes a working server example.

### Compatibility commitment

`sdk/` is a separate Go module from `internal/`. Per
[`sdk/provider/doc.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/sdk/provider/doc.go):

> The SDK abstracts the underlying gRPC protocol and provides stable
> interfaces that will not change in minor releases, even if the internal
> RPC protocol evolves.

Breaking changes ship in **major** SDK releases only. The proto module
(`proto/`) is also separate; new RPCs and fields land additively, and a
generated server that embeds `UnimplementedProviderServer` keeps compiling.

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
    return &providerv1.ValidateResponse{Ok: true}, nil
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
    }

    // TLS: see "mTLS" below. In a pod run by the manager, resolve it from
    // the standard mount instead of hard-coding paths:
    //   res, err := server.ResolveTLSAndAuth()
    //   cfg.TLS = res.TLS
    //   cfg.Middleware.Auth = res.Auth

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

`lookupVM` and `describeVM` stand for your own hypervisor code. The skeleton
above (minus those two helpers) compiles against the v0.4.0 SDK.

### Why the `Unimplemented` embedding matters

The generated gRPC code uses the
[forward-compatible service registration](https://grpc.io/blog/optional-grpc-go-fields/)
pattern: embedding `providerv1.UnimplementedProviderServer` in your struct
means proto evolution that adds new RPCs **does not break your provider's
build** — the unimplemented embeddings supply default `Unimplemented`
responses for the new RPCs until you fill them in. Always embed it, and keep
your method signatures identical to the generated interface (a method with
the same name but a different signature, such as an old `ImagePrepare` that
returns `*TaskResponse`, hides the embedded one and the type no longer
satisfies `ProviderServer`).

## Capabilities — the contract for "what works"

The manager fetches `GetCapabilities` on its Provider reconcile, once the
Provider is healthy and its runtime is `Running`, and writes the result to the
Provider's status. It surfaces what a provider reported under
`Provider.status.reportedCapabilities`, and an opt-in
`--enforce-provider-capabilities` manager flag (default **off**) makes the
manager refuse snapshot and migration operations a provider does not
advertise. Intrinsic correctness gates — such as the
[VMClone](../guides/advanced/vm-cloning.md) linked-clone pre-check — run
regardless of that flag, so advertising a capability you do not implement
will still surface as a failure.

Capabilities the manager reads from `GetCapabilitiesResponse`
(`proto/provider/v1/provider.proto`), and the SDK builder method that sets each:

| Capability flag | Set via builder | Meaning |
|----------------|-----------------|---------|
| `supports_reconfigure_online` | `.OnlineReconfigure()` | CPU/memory changes while powered on. |
| `supports_disk_expansion_online` | `.OnlineDiskExpansion()` | Disk expansion while powered on. |
| `supports_snapshots` | `.Snapshots()` | `SnapshotCreate/Delete/Revert` work. |
| `supports_memory_snapshots` | `.MemorySnapshots()` | Snapshots include memory state. |
| `supports_linked_clones` | `.LinkedClones()` | `Clone` produces a linked (CoW) clone. |
| `supports_image_import` | `.ImageImport()` | `ImagePrepare` is meaningful. |
| `supports_image_artifact_identity` | `.ImageArtifactIdentity()` | `ImagePrepare` names and stamps prepared artifacts from the image/source-digest/provider identity and never reuses one by bare name (identity-safe image preparation). The manager holds import-style prepares through a provider that supports image import but does not advertise this. |
| `supports_honest_reconfigure` | `.HonestReconfigure()` | `Reconfigure` applies every requested change (to the running VM and its definition), or reports `restart_required`, or fails; it never reports success for a change it did not apply. |
| `supports_disk_export` / `supports_disk_import` | `.DiskExport(formats...)` / `.DiskImport(formats...)` | Disk export / import for migration, with the formats; also `.ExportCompression()`. |
| `supported_export_backends[]` / `supported_import_backends[]` / `supported_transfer_modes[]` | `.ExportBackends(...)` / `.ImportBackends(...)` / `.TransferModes(...)` | Migration staging backends (`pvc`, `nfs`, `s3`) and transfer modes (`relay`, `direct`); empty means PVC and relay only. |
| `supports_clustering` | `.Clustering()` | Fronts several hosts and implements `ListHosts` / `GetHostInfo`. |
| `supports_owner_transfer`, `supports_owner_rebind`, `supports_import_size_limit`, `supports_landed_disk_delete`, `supports_routed_import` | `.OwnerTransfer()`, `.OwnerRebind()`, `.ImportSizeLimit()`, `.LandedDiskDelete()`, `.RoutedImport()` | Ownership and migration-safety contracts described above and in the proto comments. |
| `supported_staged_disk_delete_backends[]`, `resend_safe_export_backends[]`, `resend_safe_import_backends[]` | `.StagedDiskDeleteBackends(...)`, `.ResendSafeExportBackends(...)`, `.ResendSafeImportBackends(...)` | Backends on which staging cleanup and re-sent export/import are safe. |
| `supports_routed_adoption`, `supports_list_owner_filter` | `Manager.AddCapability(capabilities.CapabilityRoutedAdoption)` / `CapabilityListOwnerFilter` | Clustered-provider ListVMs/TransferOwner contracts (no dedicated builder method). `supports_routed_clone` is also not set by the SDK's `GetCapabilities`. |
| `supported_disk_types[]` | `.DiskTypes(...)` | E.g. `"qcow2", "raw", "vmdk"`. |
| `supported_network_types[]` | `.NetworkTypes(...)` | E.g. `"bridge", "nat", "vlan"`. |

**Be honest.** Returning `supports_linked_clones: true` while having
`Clone` return a non-linked synthetic response is the kind of drift that
caused real audit findings against the in-tree libvirt provider
(see [Libvirt Host Prep](../operations/libvirt-host-prepare.md#linked-clones-qcow2-backing-files)).
In v0.4.0 the in-tree libvirt provider implements full clones and advertises
`supports_linked_clones: false` (it refuses a linked clone because the source
disk is not frozen), so a [VMClone](../guides/advanced/vm-cloning.md) that asks
for a linked clone against a libvirt source is refused cleanly rather than
silently producing a broken VM. Reflect the real shape of your implementation;
the operator's [Provider Capabilities Matrix](../providers/providers-capabilities.md)
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

The full constructor list (`NewInvalidSpec`, `NewNotFound`, `NewAlreadyExists`,
`NewPermissionDenied`, `NewUnavailable`, `NewInternal`, `NewUnimplemented`,
`NewTimeout`, `NewRateLimit`, `NewCanceled`) is in
`sdk/provider/errors/errors.go`.

### What the manager's CircuitBreaker counts

Per `internal/transport/grpc/client.go:isInfraFailure`, the manager's
per-Provider CircuitBreaker counts these gRPC codes as **infra failures**
toward the threshold:

- `Unavailable`
- `DeadlineExceeded`
- `Internal`
- `Unknown`

These are **not** counted (operational failures, not provider-health
issues):

- `NotFound`, `AlreadyExists`, `InvalidArgument`, `PermissionDenied`,
  `Unauthenticated`, `FailedPrecondition`, `ResourceExhausted`, `Aborted`,
  `OutOfRange`, `Unimplemented`, `Canceled`.

Some answers never count whatever their code, because the provider answered
and is healthy: a clustered provider's host-scoped `Unavailable`
(`HOST_UNAVAILABLE`), a per-VM operation that failed on its host
(`VM_OPERATION_FAILED`), a refused disk dependency check
(`VM_DISK_CHECK_FAILED`), a `VM_OUTCOME_UNKNOWN_RETRY` outcome, and, on
`ImagePrepare`, `IMAGE_ARTIFACT_IN_PROGRESS` / `IMAGE_SOURCE_UNAVAILABLE` and
manager-side `DeadlineExceeded` / `Canceled`. Using these reasons is how a
clustered provider keeps one dead host or one tenant's failing request from
opening the breaker for every VM of the Provider.

Returning `Unavailable` for a transient SSH blip is exactly correct — the
breaker will Open after enough such failures, and your provider's
operator will see it via
`virtrigaud_circuit_breaker_state{provider=…}`.
Returning `Internal` for a business error (a bad request) would count
against the provider's health; use `InvalidArgument`, `NotFound` or
`FailedPrecondition` for those.

See [Resilience](../operations/resilience.md) for the full classification.

## mTLS and bearer-token auth

The SDK supports both. The in-tree manager negotiates mTLS with providers; it
does not send bearer tokens.

### Server side (your provider)

For a provider the manager deploys (`spec.runtime`), the manager mounts the
TLS material at `/etc/virtrigaud/tls/{tls.crt,tls.key,ca.crt}` and sets
`VIRTRIGAUD_PROVIDER_INSECURE=true` only when the Provider disables TLS. Resolve
that contract with one call, exactly as the in-tree providers do:

```go
res, err := server.ResolveTLSAndAuth()
switch {
case err == nil:
    // TLS material present: mTLS (RequireClientCert), leaf-certificate hot reload.
case errors.Is(err, server.ErrInsecureModeOptedIn):
    // No TLS files and VIRTRIGAUD_PROVIDER_INSECURE=true: plaintext (log a loud warning).
default:
    log.Fatalf("TLS: %v", err) // no material and no explicit opt-out: refuse to start
}
cfg.TLS = res.TLS
cfg.Middleware.Auth = res.Auth
```

(`errors` here is the standard library package; import the SDK's `errors`
package under another name if you use both.) `VIRTRIGAUD_PROVIDER_ALLOWED_SANS`
(comma-separated) restricts which SANs of the manager's client certificate are
accepted; empty accepts any certificate signed by the configured CA.

To configure TLS by hand instead:

```go
cfg.TLS = &server.TLSConfig{
    CertFile: "/etc/certs/tls.crt",
    KeyFile:  "/etc/certs/tls.key",
    CAFile:   "/etc/certs/ca.crt",
    RequireClientCert: true,           // mTLS: require + verify client cert
    AutoReload:        true,           // hot-reload the leaf cert (the CA still needs a restart)
}

cfg.Middleware.Auth = &middleware.AuthConfig{
    RequireTLS:  true,
    AllowedSANs: []string{"virtrigaud-manager.example.com"},
}
```

### Manager side

- **mTLS.** The manager builds a TLS 1.3 client configuration from the
  Secret named by `Provider.spec.runtime.service.tls.secretRef` (keys
  `tls.crt`, `tls.key`, `ca.crt`) and verifies the provider's certificate
  against the Service name
  `virtrigaud-provider-<namespace>-<name>.<namespace>.svc.cluster.local`
  (`internal/runtime/remote/resolver.go`, `buildTLSConfig`). The `tls` block
  must be set explicitly: an unset block is reported as
  `TLSConfigured=False` (`TLSBlockMissing`) rather than silently falling back
  to plaintext; `tls.enabled: false` is the explicit plaintext opt-out.
- **Bearer tokens.** `internal/transport/grpc` does not attach an
  `Authorization: Bearer …` header to outbound RPCs. If you enable
  `BearerTokenAuth` on a provider the in-tree manager dials, the manager's
  RPCs will fail with `Unauthenticated`. Use mTLS (`RequireTLS`) for
  manager-to-provider authentication.

See [mTLS](../providers/security/mtls.md) and [Bearer
Token](../providers/security/bearer-token.md) for the operator-facing
configuration.

## proto + SDK regeneration

The protobuf bindings are owned by the
[`proto/`](https://github.com/projectbeskar/virtrigaud/tree/v0.4.0/proto)
module and regenerated with `buf`:

```bash
# In the virtrigaud repo root
make proto           # regen all Go bindings (proto/rpc/provider/v1/)
make proto-lint      # buf lint
make proto-breaking  # check for breaking changes vs the main branch
```

The generated files are committed, and CI's *Verify Generated Files* job fails
if they are out of date. A new RPC in `provider.proto` must be implemented, or
stubbed with `Unimplemented` and declared through the capabilities, in all four
in-tree providers (vsphere, libvirt, proxmox, mock). To pick up a new
contract in an external provider, update the pinned SDK/proto commit (see
[above](#consuming-the-sdk-from-your-own-module)) and regenerate nothing —
the bindings are consumed as a Go package.

## Building and publishing

There is no opinionated build harness for external providers. The
in-tree providers use the `build/Dockerfile.manager` pattern
(parameterised on `BUILDER_IMAGE`/`BASE_IMAGE`/`GOPROXY`); you can
adopt that pattern or your own.

Minimal Dockerfile sketch for an SDK-based provider:

```dockerfile
# syntax=docker/dockerfile:1
ARG BUILDER_IMAGE=docker.io/golang:1.26.10
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

Then wire the image into a `Provider` CR. The manager runs it as a Deployment
(`spec.runtime`), passes the Provider's settings in environment variables
(`PROVIDER_TYPE`, `PROVIDER_ENDPOINT`, `PROVIDER_NAMESPACE`, `PROVIDER_NAME`,
`TLS_ENABLED`, `TLS_INSECURE_SKIP_VERIFY`, `LOG_LEVEL`, `LOG_FORMAT`), mounts the credentials Secret at
`/etc/virtrigaud/credentials` and the TLS Secret at `/etc/virtrigaud/tls`:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: my-provider
  namespace: default
spec:
  type: qemu                              # must be one of the ProviderType enum values
  endpoint: qemu+ssh://hypervisor.example.com/system   # passed to your provider as PROVIDER_ENDPOINT
  credentialSecretRef:
    name: my-provider-creds
  runtime:
    mode: Remote
    image: ghcr.io/my-org/my-provider:v0.1.0
    service:
      port: 9443
      tls:
        enabled: true
        secretRef:
          name: my-provider-tls           # tls.crt, tls.key, ca.crt
```

## Reference implementations

The in-tree providers are the best examples; reading them is the fastest
way to understand the contract:

| Provider | File | Notes |
|---------|------|-------|
| **vSphere** | `internal/providers/vsphere/server.go` | Pure-Go, uses `govmomi`. The most feature-complete in-tree provider; supports linked clones and online reconfigure. |
| **Libvirt** | `internal/providers/libvirt/server.go` and the other files in that package | Pure Go (`CGO_ENABLED=0`): in-process SSH transport, `virsh` on the host for most operations, and an opt-in `go-libvirt` shadow-compare read path. Full clones only. Implements the clustered-provider contract (`topology: cluster`), owner stamps and routed per-host lifecycle. |
| **Proxmox** | `internal/providers/proxmox/server.go` | Uses the Proxmox REST API with API-token auth (the recommended Proxmox posture). |
| **Mock** | `internal/providers/mock/` + `cmd/provider-mock/main.go` | The smallest complete provider; useful as a starting skeleton. |

A useful exercise when starting a new provider: read `cmd/provider-mock/main.go`
end-to-end; it's the SDK in production, minus a real hypervisor.

## See also

- [SDK doc.go](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/sdk/provider/doc.go) — canonical usage example.
- [proto/provider/v1/provider.proto](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/proto/provider/v1/provider.proto) — the contract.
- [Provider gRPC API](../references/grpc-api.md) — the generated reference for the contract.
- [Provider Tutorial](../providers/tutorial.md) — operator-facing walkthrough.
- [Provider Capabilities Matrix](../providers/providers-capabilities.md) —
  what each in-tree provider can and cannot do; useful as a comparison for
  declaring your own capabilities.
- [Resilience](../operations/resilience.md) — failure classification and
  CircuitBreaker behavior; informs your error-code choices.
- [mTLS](../providers/security/mtls.md), [Bearer Token](../providers/security/bearer-token.md), [Network Policies](../providers/security/network-policies.md) — the manager-to-provider security controls.
