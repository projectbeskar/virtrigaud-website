<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Bearer Token Authentication

!!! note "In v0.4.0 the gRPC channel is secured by mTLS, not bearer tokens. This page is primarily about hypervisor API tokens."
    As of v0.4.0 (unchanged since v0.3.7) the manager↔provider gRPC channel is authenticated by **mutual TLS with a client-cert SAN allow-list** (see [mTLS](mtls.md)), not by a bearer token. A bearer token is unnecessary when the manager is the only legitimate caller, so the in-tree manager does **not** attach an `Authorization: Bearer <token>` metadata header on outbound RPCs.

    The provider SDK still exposes `middleware.AuthConfig.BearerTokenAuth` and an operator-supplied `ValidateToken` callback (`sdk/provider/middleware`) for **external** provider authors who want it in addition to (or instead of) mTLS. If you enable Bearer-token auth on a provider that the in-tree manager dials, the manager will get back `codes.PermissionDenied` and reconciles will fail — so treat gRPC-channel bearer auth as an external-provider feature, not an in-tree production path.

    This page therefore covers two distinct scopes:

    1. **Provider API tokens to hypervisors** (Proxmox API tokens, future REST-based providers) — these are real, in-production, and the recommended posture for Proxmox.
    2. **gRPC-channel bearer auth via the SDK** — available for external provider authors; the in-tree manager authenticates with mTLS instead and will not send a bearer token.

## Scope 1: Hypervisor API tokens

This is the **production-relevant** form of bearer-token-style authentication in v0.4.0. It applies to the Proxmox provider today and is the model for any future REST-API-based provider.

### Proxmox API tokens

The Proxmox provider's `pveapi` client uses Proxmox VE's native API-token header on every request:

```
Authorization: PVEAPIToken=<token_id>=<token_secret>
```

The token is built from two Secret-key values that the provider reads as files:

| Secret key      | File path                                          | Source         |
|-----------------|----------------------------------------------------|----------------|
| `token_id`      | `/etc/virtrigaud/credentials/token_id`             | Provider credentials Secret |
| `token_secret`  | `/etc/virtrigaud/credentials/token_secret`         | Provider credentials Secret |

#### Why API tokens beat password auth in production

- **Scoped at creation time** — with privilege separation (`--privsep 1`) you bind the token to its own role and path, so it can do only what that ACL grants, even if the underlying user can do more.
- **Revocable independently** of the user account. If the token leaks, you delete the token in PVE; the user account stays intact.
- **No interactive-session state** in the provider. Password auth issues a session ticket that has to be refreshed; token auth is stateless.
- **PVE audit log** records the token ID on every action, making the trail traceable to the VirtRigaud deployment that holds it (use one token per Proxmox `Provider`: the provider tells its own clone and create tasks from other users' by the PVE user that ran them, so Providers that share a token hold each other's creates).

#### Creating a Proxmox API token (CLI)

```bash
# On a PVE node, as root@pam:
pveum user add virtrigaud@pve --comment "VirtRigaud"   # underlying user, no login needed

# Create the token with privilege separation. Save the printed secret:
# PVE will not show it again.
pveum user token add virtrigaud@pve vrtg-token --privsep 1

# With --privsep 1 the token needs its own ACL. Either a built-in role ...
pveum acl modify / --tokens 'virtrigaud@pve!vrtg-token' --roles PVEVMAdmin
# ... or a tighter custom role (see "PVE privileges" on the Proxmox page):
# pveum role add VirtRigaud --privs "VM.Allocate,VM.Audit,..."
# pveum acl modify / --tokens 'virtrigaud@pve!vrtg-token' --roles VirtRigaud
```

The privileges the provider needs depend on the features you use (create, clone, snapshots, network and cloud-init settings, migration). VirtRigaud does not publish a complete, tested PVE role; the list of what the code and the Proxmox API documentation establish is in [PVE privileges](../proxmox.md#pve-privileges). In particular, since v0.4.0 the provider applies a VM's bridge, VLAN tag and static IP, which needs `VM.Config.Network`, `VM.Config.Cloudinit` and `SDN.Use` on every bridge. **Those `SDN.Use` ACLs are what decide which bridges and VLANs the authors of `VirtualMachine`s in a namespace can reach**, because the provider applies whatever bridge and tag the manager sends. Likewise `VM.Config.Options` and `VM.Allocate` are the ownership boundary for VirtRigaud's VM stamps: grant them only to VirtRigaud's tokens and your administrators.

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
    image: ghcr.io/projectbeskar/virtrigaud/provider-proxmox:v0.4.0
```

#### Token rotation

Token rotation is a multi-step operation in v0.4.0:

1. Create a new token in PVE.
2. Update the K8s Secret (or your ExternalSecret) with the new `token_id` / `token_secret`.
3. Restart the provider pod — the provider reads credentials only at startup; there is no in-process reload (see [External Secrets](external-secrets.md#what-eso-does-not-solve-in-v036)).
4. Once the new token is confirmed working (VirtualMachines on that Provider reconcile and `virtrigaud_circuit_breaker_state` stays `0`), delete the old token in PVE.

### vSphere SSO username/password

The vSphere provider does **not** use bearer-token-style auth. It authenticates via vCenter SSO (username/password). See the [vSphere provider page](../vsphere.md) for the service-account configuration pattern.

A SAML/OIDC-based vCenter authentication mode is not implemented. The vCenter account needs the privilege `VirtualMachine.Config.AdvancedConfig` since v0.4.0 (see [Security](../../operations/security.md#vm-ownership-and-owner-stamps)).

### Libvirt

Libvirt authentication is SSH-based (key or password), with the host key verified against a `known_hosts` entry in the credentials Secret. Bearer tokens do not apply.

### Proxmox SSH data plane

Migration disk transfer and `qemu-img` on the PVE node use SSH, not the API token. Add `ssh_user` and `ssh_password` or `ssh_privatekey`, and `known_hosts`, to the same credentials Secret (see [External Secrets](external-secrets.md#proxmox-api-token-strongly-recommended-for-production)). Host-key verification is on by default; `PROXMOX_INSECURE_SKIP_HOST_KEY_VERIFICATION=true` is an audit-flagged lab opt-out.

## Scope 2: gRPC-channel bearer auth (SDK, external providers)

This scope is for operators writing their own **external** provider against `sdk/provider`. It is documented for completeness. In-tree providers authenticate the manager via mTLS (see [mTLS](mtls.md)); bearer-token auth on the gRPC channel is an optional extra that only external provider authors would wire in.

### SDK API

`sdk/provider/middleware/middleware.go`:

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
4. Reject with `codes.PermissionDenied` (`token authentication failed`) if `ValidateToken` returns an error or the header is missing/malformed.

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

The in-tree manager's gRPC client does not attach a bearer token to outbound calls. The unary client interceptors in `internal/transport/grpc/client.go` are, in order:

1. `requestSentInterceptor` (records whether a request was sent)
2. `providerRPCMetricsInterceptor`
3. `providerCircuitBreakerInterceptor` (when the Provider has a breaker)

There is no `authorization`-header-injecting interceptor. If you enable `BearerTokenAuth: true` on the server side, every RPC from the in-tree manager will fail with `codes.PermissionDenied`.

!!! note "The in-tree channel is authenticated by mTLS, not bearer tokens"
    In v0.4.0 the manager authenticates to providers with a **client certificate** verified against a configured CA and a SAN allow-list (see [mTLS](mtls.md)). That is the in-tree authentication path; there is no plan to also send a bearer token from the in-tree manager. SDK bearer-token auth remains an optional control for external provider authors who want an additional or alternative gate on top of (or instead of) mTLS.

### Why this is not "JWT with scopes"

The SDK's `ValidateToken` is intentionally a flat `func(ctx, token) error` — it does not encode scopes, claims, expiration, audience, or any other JWT-like structure. Two reasons:

1. **Scope mapping needs the gRPC method name to mean something policy-wise.** That requires either:
    - The provider knowing about scopes (which couples the SDK to a policy model), or
    - A separate authorisation interceptor that lives downstream of `ValidateToken` and inspects `info.FullMethod`.

    Neither is implemented.

2. **In a one-manager-one-provider trust model, scoping doesn't add much.** The manager is the only legitimate caller, so the question "what is this caller allowed to do?" is just "is this the manager?" — answered by mTLS client-cert identity and the SAN allow-list. The interesting authorisation surface is the K8s RBAC on the `Provider` CR — who is allowed to create/modify it — not the gRPC channel.

When and if multi-tenant providers become a thing, the design would extend `ValidateToken` to return a typed context value (claims), and a follow-on interceptor would gate methods on claim values. That is not implemented.

## Auditing

For Scope 1 (hypervisor API tokens):

- **Proxmox audit log** records the token ID on every API call. Configure your PVE cluster to ship audit events to your SIEM.
- **VirtRigaud-side logs** never contain the token secret; credential diagnostics are length-only.

For Scope 2 (gRPC-channel bearer auth, for external providers that enable it):

- The SDK's `Logging` middleware (enabled in the in-tree providers) logs method, code and duration per RPC. It is not configured to log the `authorization` header value.

## See also

- [Operations -> Security](../../operations/security.md#provider-credentials) — overall credential flow.
- [External Secrets](external-secrets.md) — sourcing the `token_id` / `token_secret` from your secret store.
- [Proxmox provider](../proxmox.md#authentication) — Proxmox-specific token guidance.
- [mTLS](mtls.md) — the other half of the gRPC-channel security story.
