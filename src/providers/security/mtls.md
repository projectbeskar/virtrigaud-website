<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# mTLS for Manager <-> Provider gRPC

!!! danger "mTLS is documented for future support. It is NOT wired through in v0.3.6."
    The gRPC client (`internal/transport/grpc/client.go:951-991`) and the SDK gRPC server (`sdk/provider/server/server.go:72-88`) **both have correct TLS plumbing**. The piece that connects them — the manager-side `Resolver.buildTLSConfig()` method — is intentionally short-circuited in v0.3.6:

    ```go
    // internal/runtime/remote/resolver.go:142-148
    func (r *Resolver) buildTLSConfig(ctx context.Context, provider *infravirtrigaudiov1beta1.Provider) (*grpcClient.TLSConfig, error) {
        // If TLS is not enabled, return nil for insecure connection
        // TLS configuration removed in v1beta1, always return nil for insecure connection
        if true {
            return nil, nil
        }
        // unreachable
    }
    ```

    No matter how you populate `Provider.spec.runtime.service.tls.secretRef` on a Provider CR, the manager dials providers over **plaintext gRPC**. The CRD field is parsed and validated but has no runtime effect.

    Likewise, the four in-tree providers (`cmd/provider-{vsphere,libvirt,proxmox,mock}/main.go`) do **not** enable `Auth.RequireTLS` in their SDK middleware config. They will not refuse an unauthenticated caller.

    This page describes (a) the current reality, (b) the partial workaround an operator can deploy today using their own side-channel cert injection, and (c) the design target for when first-class mTLS support lands.

## Current v0.3.6 reality

| Component                                | TLS capability today |
|-----------------------------------------|----------------------|
| Manager-side gRPC client                | Supports `CertFile / KeyFile / CAFile / Insecure` if a `TLSConfig` is supplied (`internal/transport/grpc/client.go:951-991`). |
| Provider-side gRPC server (SDK)         | Supports `CertFile / KeyFile / CAFile / RequireClientCert / AutoReload` (`sdk/provider/server/server.go:72-88`). |
| `Resolver.buildTLSConfig()`             | **Returns `nil, nil` unconditionally** (`internal/runtime/remote/resolver.go:146`). |
| In-tree provider binaries (`cmd/provider-*`) | Construct middleware with only `Logging` + `Recovery`; no `Auth.RequireTLS`. `cmd/provider-libvirt/main.go` does not even use the SDK server config; it constructs a raw `grpc.NewServer()`. |
| `Provider.spec.runtime.service.tls`     | CRD field exists (`api/infra.virtrigaud.io/v1beta1/provider_types.go:60-78`) and is validated. It is NOT consumed by the controller in v0.3.6. |

**Implication**: in a default v0.3.6 deployment, an attacker with pod-network access can:

- Sniff the plaintext gRPC traffic between the manager and any provider pod.
- Spoof a provider service (e.g. via DNS hijacking inside the cluster) to intercept manager RPCs.

For a regulated deployment, you must compensate via the pod-network layer:

1. **NetworkPolicy** that locks provider-pod ingress to the manager pod only (see [Network Policies](network-policies.md)).
2. **Encrypted CNI overlay** (Cilium WireGuard transparent encryption, Calico WireGuard, IPsec, or equivalent).
3. **Private cluster networking** if the cluster runs across multiple physical sites.

## Why this page exists

This page is preserved because:

- The CRD shape for declarative TLS configuration (`ProviderTLSSpec`) is already in v1beta1. Operators planning v0.4.0+ deployments can author their CRs with TLS now, knowing the wiring is the next step.
- An operator who is willing to write a small amount of glue can already deploy mTLS-protected provider pods today by **side-channel** injecting the cert into the provider Deployment and dialing it from the manager with a hand-rolled TLSConfig. This requires forking or patching, but the SDK and gRPC client both honour the TLS config when populated.
- The target design is stable: the only piece changing is the `Resolver.buildTLSConfig` method, which will read the existing `Provider.spec.runtime.service.tls.secretRef` field, fetch the referenced Secret, and pass certificate material to `grpcClient.NewClient`.

## What an operator can do today

### Option A: Wait for v0.4.0+

For most operators, this is the right answer. Use a NetworkPolicy and an encrypted CNI in the interim. Track the gap in the project's roadmap (see ["v0.3.6 security gap inventory"](../../operations/security.md#v036-security-gap-inventory)).

### Option B: Side-channel inject for a single critical Provider

If you have one Provider that needs mTLS **now**, you can patch the provider Deployment after the controller creates it and run a forked manager that consumes a Secret directly. This is not supported and will not survive a controller reconcile that resets the Deployment spec, but it is a valid emergency control while waiting for first-class support.

You would need to:

1. **Issue certs** (cert-manager is the recommended path):

    ```yaml
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: provider-vsphere-prod-tls
      namespace: virtrigaud-system
    spec:
      secretName: provider-vsphere-prod-tls
      issuerRef:
        name: virtrigaud-ca-issuer
        kind: ClusterIssuer
      commonName: provider-vsphere-prod
      dnsNames:
        - provider-vsphere-prod
        - provider-vsphere-prod.virtrigaud-system.svc.cluster.local
      duration: 8760h
      renewBefore: 720h
    ```

2. **Modify the provider main** (your fork) to read the cert and enable `RequireTLS`:

    ```go
    // in cmd/provider-vsphere/main.go (forked)
    config.TLS = &server.TLSConfig{
        CertFile:          "/etc/tls/tls.crt",
        KeyFile:           "/etc/tls/tls.key",
        CAFile:            "/etc/tls/ca.crt",
        RequireClientCert: true,
        AutoReload:        true,
    }
    config.Middleware.Auth = &middleware.AuthConfig{
        RequireTLS:  true,
        AllowedSANs: []string{"virtrigaud-manager"},
    }
    ```

3. **Patch the Deployment** (kubectl patch in a post-reconcile hook, or a Mutating webhook) to mount the cert Secret at `/etc/tls`.

4. **Modify the manager main** to consume the cert from a Secret and pass it to `grpcClient.NewClient` instead of nil. This currently requires editing `internal/runtime/remote/resolver.go` directly.

This is a **non-trivial fork**. Most operators should choose Option A.

### Option C: Service-mesh sidecar mTLS (the practical answer for many regulated clusters)

If you are running Istio, Linkerd, or Cilium Service Mesh, you can put the manager and provider pods inside the mesh and let the sidecar enforce mTLS transparently. From the application's point of view the gRPC channel is still plaintext on `localhost`, but on the wire the mesh upgrades it to mTLS.

This is the **recommended workaround today** for regulated environments that already have a service mesh. It does not require any VirtRigaud code changes.

Configuration:

- Label the `virtrigaud-system` namespace and the namespace hosting your provider pods for sidecar injection.
- Apply a `PeerAuthentication` (Istio) / equivalent that requires mTLS for the relevant workloads.

## Target design (when wiring lands)

When the `Resolver.buildTLSConfig()` short-circuit is removed, the design will be:

```
Provider CR
  spec:
    runtime:
      service:
        tls:
          enabled: true
          secretRef:
            name: provider-vsphere-prod-tls  # Secret with tls.crt / tls.key / ca.crt
          insecureSkipVerify: false
                │
                ▼
ProviderReconciler mounts the Secret on the provider pod at /etc/virtrigaud/tls
(this is already implemented at internal/controller/provider_controller.go:583-589;
 the conditional is currently `if false`)
                │
                ▼
Resolver.buildTLSConfig() reads the same Secret, materialises CertFile/KeyFile/CAFile
in tmpfs, and returns a populated *TLSConfig to grpcClient.NewClient
                │
                ▼
grpcClient.NewClient (already wired, internal/transport/grpc/client.go:100-108)
                │
                ▼
gRPC dial uses credentials.NewTLS(tlsConfig) — mTLS established
```

The CRD shape is stable. Operators authoring Provider CRs today with the `runtime.service.tls.*` block will get correct behaviour when the wiring lands; no CR rewrite needed.

## Certificate management recommendations

When mTLS is wired through, the project will recommend:

- **cert-manager** as the cert issuer (a private `ClusterIssuer` rooted in your organisation's PKI, not a public CA).
- **Short-lived certs** (24h duration, 8h renewBefore) with auto-reload on the provider side (`TLSConfig.AutoReload: true` is already implemented in `sdk/provider/server/server.go`).
- **Per-Provider CA rotation** via separate `Issuer` per Provider CR so a compromised provider cert blast-radius is limited to one provider.
- **SAN-based authorisation**: providers should set `AllowedSANs` on `AuthConfig` to enforce that incoming connections come specifically from the manager's identity, not any client cert signed by the same CA.

## See also

- [Operations -> Security](../../operations/security.md) — overall security posture for v0.3.6.
- [Network Policies](network-policies.md) — the primary compensating control for the missing mTLS today.
- [Resilience](../../operations/resilience.md) — per-Provider CircuitBreaker limits blast radius of a degraded provider, including an attacker-spoofed one.
