<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Bearer Token Authentication

!!! danger "Bearer-token auth is available in the SDK; it is NOT enabled in the in-tree providers in v0.3.6, and the manager does not currently send a bearer token."
    The provider SDK exposes `middleware.AuthConfig.BearerTokenAuth` and an operator-supplied `ValidateToken` callback (`sdk/provider/middleware/middleware.go:81-94`). An external provider author can opt in by wiring it through `server.Config.Middleware.Auth`. The four in-tree providers — `cmd/provider-vsphere`, `cmd/provider-libvirt`, `cmd/provider-proxmox`, `cmd/provider-mock` — do **not** enable it; their main files configure only `Logging` and `Recovery` interceptors (verify at `cmd/provider-vsphere/main.go:64-73`).

    Equally important: the manager-side gRPC client (`internal/transport/grpc/client.go`) does **not** attach an `Authorization: Bearer <token>` metadata header on outbound RPCs. If you enable Bearer-token auth on a provider that the in-tree manager dials, the manager will get back `codes.Unauthenticated` and reconciles will fail.

    This page therefore covers two distinct scopes:

    1. **Provider API tokens to hypervisors** (Proxmox API tokens, future REST-based providers) — these are real, in-production, and the recommended posture for Proxmox.
    2. **gRPC-channel bearer auth via the SDK** — possible for external provider authors, but the in-tree manager will not interoperate without code changes. Treat this as roadmap, not production-ready.

## Scope 1: Hypervisor API tokens

This is the **production-relevant** form of bearer-token-style authentication in v0.3.6. It applies to the Proxmox provider today and is the model for any future REST-API-based provider.

### Proxmox API tokens

The Proxmox provider's `pveapi` client uses Proxmox VE's native API-token header on every request:

```
Authorization: PVEAPIToken=<token_id>=<token_secret>
```

The token is built from two Secret-key values that the provider reads as files:

| Secret key      | File path                                          | Source         |
|-----------------|----------------------------------------------------|----------------|
| `token_id`      | `/etc/virtrigaud/credentials/token_id`             | `internal/providers/proxmox/server.go:69` |
| `token_secret`  | `/etc/virtrigaud/credentials/token_secret`         | `internal/providers/proxmox/server.go:70` |

#### Why API tokens beat password auth in production

- **Scoped at creation time** in the PVE UI — you bind the token to a role (typically `VirtRigaudRole`) and a path (typically `/`). The token cannot do anything the underlying user can't do, but it also can't do anything the role doesn't grant.
- **Revocable independently** of the user account. If the token leaks, you delete the token in PVE; the user account stays intact.
- **No interactive-session state** in the provider. Password auth issues a session ticket that has to be refreshed; token auth is stateless.
- **PVE audit log** records the token ID on every action, making the trail traceable to the VirtRigaud deployment that holds it (one token per deployment is the recommended pattern).

#### Creating a Proxmox API token (CLI)

```bash
# On a PVE node, as root:
pveum user add virtrigaud@pve --password "..."   # underlying user, no login needed
pveum role add VirtRigaudRole -privs "VM.Allocate,VM.Audit,VM.Config.CPU,\
VM.Config.Cloudinit,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,\
VM.Config.Network,VM.Config.Options,VM.Console,VM.Monitor,VM.PowerMgmt,\
Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,\
Sys.Audit,Sys.Modify"
pveum aclmod / -user virtrigaud@pve -role VirtRigaudRole

# Create the token. Save the printed secret — PVE will not show it again.
pveum user token add virtrigaud@pve vrtg-token --privsep 0
```

The output gives you:

- `token_id = "virtrigaud@pve!vrtg-token"`
- `token_secret = "<uuid>"`

Materialise as a K8s Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: proxmox-prod-credentials
  namespace: virtrigaud-system
type: Opaque
stringData:
  token_id: "virtrigaud@pve!vrtg-token"
  token_secret: "<uuid>"
```

And reference from your Provider CR:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: proxmox-prod
  namespace: virtrigaud-system
spec:
  type: proxmox
  endpoint: https://pve-cluster.internal.example.com:8006
  credentialSecretRef:
    name: proxmox-prod-credentials
  runtime:
    image: ghcr.io/projectbeskar/virtrigaud/provider-proxmox:v0.3.6
```

#### Token rotation

Token rotation is a multi-step operation in v0.3.6:

1. Create a new token in PVE.
2. Update the K8s Secret (or your ExternalSecret) with the new `token_id` / `token_secret`.
3. Restart the provider pod — the provider reads credentials only at startup (see [External Secrets](external-secrets.md#what-eso-does-not-solve-in-v036)).
4. Once the new token is confirmed working (the `Provider` CR `Healthy` condition stays True), delete the old token in PVE.

In-process token reload is on the roadmap for v0.4.0+.

### vSphere SSO username/password

The vSphere provider does **not** use bearer-token-style auth. It authenticates via vCenter SSO (username/password). See the [vSphere provider page](../vsphere.md) for the service-account configuration pattern.

A future SAML/OIDC-based vCenter authentication mode could be modelled as a bearer token, but is not implemented in v0.3.6.

### Libvirt

Libvirt authentication is SSH-based (key or password). Bearer tokens do not apply.

## Scope 2: gRPC-channel bearer auth (SDK, external providers)

This scope is for operators writing their own **external** provider against `sdk/provider`. It is documented for completeness and as the **roadmap target** for in-tree providers.

### SDK API

`sdk/provider/middleware/middleware.go:81-94`:

```go
type AuthConfig struct {
    // RequireTLS requires TLS client certificates
    RequireTLS bool

    // AllowedSANs lists allowed Subject Alternative Names for mTLS
    AllowedSANs []string

    // BearerTokenAuth enables bearer token authentication
    BearerTokenAuth bool

    // ValidateToken function for bearer token validation
    ValidateToken func(ctx context.Context, token string) error
}
```

When `BearerTokenAuth: true`, the SDK installs unary and stream interceptors that:

1. Extract the `authorization` metadata header from every incoming gRPC call.
2. Strip the `Bearer ` prefix.
3. Call your `ValidateToken` callback with the token string and request context.
4. Reject with `codes.Unauthenticated` if `ValidateToken` returns an error or the header is missing/malformed.

### External-provider example

In a hypothetical `cmd/provider-mycustom/main.go`:

```go
config := server.DefaultConfig()
config.Middleware = &middleware.Config{
    Logging:  &middleware.LoggingConfig{Enabled: true, Logger: logger},
    Recovery: &middleware.RecoveryConfig{Enabled: true, Logger: logger},
    Auth: &middleware.AuthConfig{
        BearerTokenAuth: true,
        ValidateToken:   validateMyToken,
    },
}

// validateMyToken is operator-supplied. It MUST be cheap and side-effect-free
// on the happy path, since it runs on every RPC.
func validateMyToken(ctx context.Context, token string) error {
    // Example: HMAC-signed token with a shared secret read from disk.
    if !hmac.Equal(expected, sha256.Sum256([]byte(token))) {
        return fmt.Errorf("invalid token")
    }
    return nil
}
```

### Why the in-tree manager will not interoperate

The in-tree manager's gRPC client does not currently attach a bearer token to outbound calls. The relevant code path is `internal/transport/grpc/client.go:94-165`, where unary client interceptors are appended in this order:

1. `providerRPCMetricsInterceptor` (G4 / #90)
2. (optional) `providerCircuitBreakerInterceptor` (G6 / #112)

There is no `authorization`-header-injecting interceptor. If you enable `BearerTokenAuth: true` on the server side, every RPC from the in-tree manager will fail with `codes.Unauthenticated`.

**Roadmap**: a future v0.4.x release is expected to add a client-side interceptor that reads a token from a Secret referenced by the Provider CR and attaches it to every outbound RPC. The CRD shape will likely extend `ProviderRuntimeSpec.Service` with an optional `bearerTokenSecretRef`. Track this against the project's gap inventory in [Operations -> Security](../../operations/security.md#v036-security-gap-inventory).

### Why this is not "JWT with scopes" in v0.3.6

The SDK's `ValidateToken` is intentionally a flat `func(ctx, token) error` — it does not encode scopes, claims, expiration, audience, or any other JWT-like structure. Two reasons:

1. **Scope mapping needs the gRPC method name to mean something policy-wise.** That requires either:
    - The provider knowing about scopes (which couples the SDK to a policy model), or
    - A separate authorisation interceptor that lives downstream of `ValidateToken` and inspects `info.FullMethod`.

    Neither is implemented in v0.3.6.

2. **In a one-manager-one-provider trust model, scoping doesn't add much.** The manager is the only legitimate caller, so the question "what is this caller allowed to do?" is just "is this the manager?". The interesting authorisation surface is the K8s RBAC on the `Provider` CR — who is allowed to create/modify it — not the gRPC channel.

When and if multi-tenant providers become a thing, the design would extend `ValidateToken` to return a typed context value (claims), and a follow-on interceptor would gate methods on claim values. That is roadmap, not v0.3.6.

## Auditing

For Scope 1 (hypervisor API tokens):

- **Proxmox audit log** records the token ID on every API call. Configure your PVE cluster to ship audit events to your SIEM.
- **VirtRigaud-side logs** record `token_id` (the ID, not the secret) at DEBUG level when establishing the PVE client. The token secret is **never** logged.

For Scope 2 (gRPC-channel bearer auth, when wired):

- The SDK's `Logging` middleware (enabled in all in-tree providers) logs `method`, `code`, and `duration` per RPC. It does NOT log the `authorization` header value.

## See also

- [Operations -> Security](../../operations/security.md#provider-credentials) — overall credential flow.
- [External Secrets](external-secrets.md) — sourcing the `token_id` / `token_secret` from your secret store.
- [Proxmox provider](../proxmox.md#authentication) — Proxmox-specific token guidance.
- [mTLS](mtls.md) — the other half of the gRPC-channel security story.
