<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# mTLS for Manager <-> Provider gRPC

!!! success "mTLS is wired and on by default (since v0.3.7, unchanged in v0.3.8)"
    Manager↔provider gRPC traffic is protected by **mutual TLS by default** (ADR-0003, #147/#148, shipped in v0.3.7). The manager dials each provider over TLS 1.3, presenting a client certificate; the provider verifies that certificate against a configured CA and enforces a SAN allow-list before accepting any RPC. Plaintext gRPC is not the default and requires an **explicit, audit-flagged opt-out**.

    This behaviour landed in v0.3.7 (a change from v0.3.6, where the `Provider.spec.runtime.service.tls` field was parsed but had no runtime effect) and is **unchanged in v0.3.8** — there are no new mTLS features or breaking changes in v0.3.8. See the historical [v0.3.6 → v0.3.7 upgrade note](#breaking-change-v036-v037-historical) below.

This page describes how to enable and operate mTLS for manager↔provider gRPC in v0.3.8: the Provider CR `tls` block, how the manager and provider enforce it, the SAN allow-list, the secure-by-default/fail-closed behaviour, certificate rotation and its limitation, the Helm `providerTLS` block for chart-templated providers, the `TLSConfigured` status condition, and a worked cert-manager example for producing the TLS Secret.

## Trust model

VirtRigaud uses a **single CA per install** (ADR-0003 decision #5):

- The manager holds a **client** certificate + key plus the CA bundle.
- Each provider holds a **server** certificate + key plus the same CA bundle.
- All provider pods trust the same CA. One VirtRigaud install is one administrative boundary.

The TLS Secret is **provisioned by the operator**. VirtRigaud reads a Kubernetes Secret containing `tls.crt` / `tls.key` / `ca.crt`; how those bytes are minted — manual `openssl`, an internal PKI pipeline, Vault, External Secrets, or cert-manager — is the operator's choice. **The Helm chart ships no cert-manager `Certificate` or issuer scaffolding**; it only references a Secret you provide. A worked cert-manager example for *producing* that Secret is given [below](#producing-the-secret-with-cert-manager).

!!! note "Per-provider trust roots are deferred"
    The `tls` block is per-Provider, so the data path can already carry a per-Provider CA bundle, but the manager side is currently single-CA. Per-provider trust roots and SPIFFE/SPIRE identity remain out of scope in v0.3.8 and are tracked as follow-up ADRs.

## The Provider CR `tls` block

mTLS for a controller-managed provider is configured on the Provider CR under `spec.runtime.service.tls` (`ProviderTLSSpec`):

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: provider-vsphere-prod
  namespace: virtrigaud-system
spec:
  type: vsphere
  endpoint: https://vcenter.internal.example.com
  credentialSecretRef:
    name: vsphere-prod-credentials
  runtime:
    image: ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.3.8
    service:
      tls:
        enabled: true                       # default true
        secretRef:
          name: provider-vsphere-prod-tls   # Secret with tls.crt / tls.key / ca.crt
        insecureSkipVerify: false           # default false — dev-only
```

| Field | Type | Meaning |
|-------|------|---------|
| `enabled` | bool | When `true` (the default), the manager dials this provider over mTLS and the provider runs TLS-mandatory. When `false`, both ends fall back to **audit-flagged plaintext** (see [escape hatch](#escape-hatches-plaintext-fallback)). |
| `secretRef.name` | string | Name of a Secret (in the Provider's namespace) holding `tls.crt`, `tls.key`, and `ca.crt`. Required when `enabled: true`. |
| `insecureSkipVerify` | bool | Dev-only. When `true`, the manager does **not** verify the provider's server certificate. Defaults to `false`. |

The referenced Secret may be either a `kubernetes.io/tls`-typed Secret (with an extra `ca.crt` key) **or** a plain `Opaque` Secret carrying all three keys explicitly. Both shapes are accepted, so a cert-manager-produced Secret needs no translation.

!!! danger "`insecureSkipVerify: true` defeats mTLS"
    Setting `insecureSkipVerify: true` disables the manager's verification of the provider server certificate, removing protection against a spoofed provider endpoint. It is intended only for lab or first-bootstrap scenarios. The manager logs a **per-reconcile WARNING** naming the Provider and namespace whenever it is set, so this never silently survives into a regulated environment. Do not use it in production.

## How enforcement works end-to-end

```
Provider CR (spec.runtime.service.tls.enabled=true, secretRef → Secret)
        │
        ▼
ProviderReconciler                                  internal/controller/provider_controller.go
  evaluateTLSPosture() sets the TLSConfigured Condition,
  mounts the Secret on the provider pod at /etc/virtrigaud/tls,
  and passes VIRTRIGAUD_PROVIDER_ALLOWED_SANS to the provider
        │
        ├──────────────► Manager-side gRPC client          internal/runtime/remote/resolver.go
        │                  buildTLSConfig() loads tls.crt/tls.key/ca.crt
        │                  from the Secret and builds a *tls.Config:
        │                    MinVersion = TLS 1.3
        │                    RootCAs    = ca.crt
        │                    Certificates = tls.crt + tls.key (client cert)
        │                    ServerName = provider Service FQDN
        │
        └──────────────► Provider-side gRPC server          sdk/provider/server, middleware
                           serves mTLS:
                             MinVersion = TLS 1.3
                             RequireAndVerifyClientCert
                             ClientCAs  = ca.crt
                           validateTLSPeer() enforces the SAN allow-list
```

### Manager side

The manager's resolver (`internal/runtime/remote/resolver.go`) builds the gRPC client TLS config from the Secret:

- `MinVersion = TLS 1.3` (the project floor).
- `RootCAs` from `ca.crt` — used to verify the provider's **server** certificate.
- `Certificates` from `tls.crt` + `tls.key` — the manager's **client** certificate.
- `ServerName` anchored to the provider Service FQDN (`virtrigaud-provider-<namespace>-<name>.<namespace>.svc.cluster.local`), so SNI matches a deterministic SAN you mint into the provider server cert.

### Provider side

The provider gRPC server (SDK `sdk/provider/...`) serves mTLS with:

- `MinVersion = TLS 1.3`.
- `RequireAndVerifyClientCert` — the TLS stack itself must validate the manager's client cert against the CA bundle loaded into `ClientCAs`.
- A SAN allow-list enforced by `validateTLSPeer` (next section).

TLS material is mounted on the provider pod at `/etc/virtrigaud/tls` (`tls.crt`, `tls.key`, `ca.crt`).

## The SAN allow-list

On top of TLS chain verification, the provider applies an authorization gate via `validateTLSPeer` (ADR-0003 decision #5):

| Condition | Result |
|-----------|--------|
| No peer info, connection not TLS, or no **verified** chain | gRPC `Unauthenticated` — the caller is rejected before any allow-list check. |
| Allow-list **empty** (default) | **Permissive** — any client certificate signed by the configured CA is accepted. This is the single-CA trust model: the CA *is* the trust boundary. |
| Allow-list **non-empty** | The leaf certificate must match an entry by **DNS SAN**, **URI SAN**, or **Common Name** (CN checked last, as a fallback for legacy CN-only certs). A mismatch returns gRPC `PermissionDenied`. |

The allow-list is delivered to the provider via the `VIRTRIGAUD_PROVIDER_ALLOWED_SANS` environment variable (comma-joined), set by the controller for controller-managed providers and by the chart for static providers.

!!! warning "Empty allow-list assumes a trustworthy CA"
    The permissive empty-list default matches kube-apiserver client-cert auth: it trusts any certificate the configured CA signed. This is correct for a single-administrative-domain install. It would be **incorrect** for a multi-tenant cluster where multiple distinct managers share one CA — in that posture, populate `AllowedSANs` (via `providerTLS.allowedSANs` or the controller-derived value) so a provider only accepts its own manager's identity.

## Secure-by-default and fail-closed

The provider is fail-closed (behaviour shipped in v0.3.7, unchanged in v0.3.8). A provider pod that finds **no TLS material** at `/etc/virtrigaud/tls` **and** does not have `VIRTRIGAUD_PROVIDER_INSECURE=true` set will **hard-exit on startup** rather than silently fall back to plaintext, with this error:

```
TLS material missing at /etc/virtrigaud/tls and VIRTRIGAUD_PROVIDER_INSECURE is not set to "true"; either provision /etc/virtrigaud/tls/{tls.crt,tls.key,ca.crt} or set VIRTRIGAUD_PROVIDER_INSECURE=true to opt into plaintext (audit-flagged)
```

This is deliberate: a misconfigured upgrade refuses to start rather than regressing to plaintext.

### Escape hatches (plaintext fallback)

There is **no global `--insecure-no-tls-providers` flag**. Plaintext is opt-in **per Provider**:

- **Controller-managed providers**: set `spec.runtime.service.tls.enabled=false` on the Provider CR. The controller then sets `VIRTRIGAUD_PROVIDER_INSECURE=true` on the provider pod so it boots in audit-flagged plaintext instead of crash-looping. The manager logs a WARNING and the `TLSConfigured` condition reads `False` / `ExplicitlyDisabled`.
- **Chart-templated (static) providers**: set `providerTLS.insecure=true` (only honoured when `providerTLS.secretName` is empty).

In both cases the provider starts plaintext with a loud audit WARNING. Compensating controls (NetworkPolicy + encrypted CNI) remain the operator's responsibility for those Providers — see [Network Policies](network-policies.md).

## The `TLSConfigured` status condition

The controller surfaces a `TLSConfigured` condition on every Provider CR so auditors can verify TLS posture with `kubectl get providers` rather than a packet capture:

| Reason | Status | Meaning | Deployment created? |
|--------|--------|---------|---------------------|
| `TLSBlockMissing` | `False` | `spec.runtime.service.tls` is nil. **Loud failure** — the operator has not made an explicit decision. | **No** — the controller refuses to deploy. |
| `ExplicitlyDisabled` | `False` | `tls.enabled=false`. Audit-flagged plaintext opt-out. | Yes (plaintext, `VIRTRIGAUD_PROVIDER_INSECURE=true`). |
| `SecretRefMissing` | `False` | `tls.enabled=true` but `secretRef` is empty/unset. | **No**. |
| `Enabled` | `True` | TLS wired with a valid `secretRef`. | Yes (mTLS). |

```bash
kubectl get provider provider-vsphere-prod -n virtrigaud-system \
  -o jsonpath='{.status.conditions[?(@.type=="TLSConfigured")]}{"\n"}'
```

!!! note "A nil `tls` block does not deploy anything"
    Unlike `tls.enabled=false` (which deploys a plaintext provider), a **missing** `tls` block is a loud failure: no Deployment is created at all until the operator either provisions a Secret with `tls.enabled=true` or explicitly sets `tls.enabled=false`.

## Certificate rotation

Leaf certificate/key rotation is **hot-reloaded** without a pod restart. When TLS material is present, the provider enables a controller-runtime `certwatcher` on the mounted leaf cert/key by default; Kubernetes' Secret-to-Pod sync (~60s) updates the mounted files and the watcher picks up the new bytes.

To rotate the leaf certificate:

1. Re-mint the leaf cert/key (keeping the same CA).
2. `kubectl apply` the updated Secret.
3. Watch the `TLSConfigured` condition stay green; no pod restart needed.

!!! warning "CA-bundle rotation requires a provider restart"
    Hot-reload covers the **leaf cert/key only**. Rotating the **CA bundle** (`ca.crt`, which populates the provider's `ClientCAs` and the manager's `RootCAs`) still requires a **provider pod restart** to take effect. Plan CA rotations as a rolling restart of the affected provider Deployments. Do not assume a CA swap takes effect live.

## Helm `providerTLS` block (chart-templated providers only)

The `providerTLS` block in `values.yaml` governs **chart-templated / static provider Deployments only**. Controller-managed providers read their TLS posture from the Provider CR's `tls` block, not from these values.

```yaml
providerTLS:
  # Name of an externally-provisioned Kubernetes Secret (typically
  # kubernetes.io/tls) containing tls.crt, tls.key, and ca.crt. Empty
  # by default — operators opt in by setting it.
  secretName: ""

  # SAN/CN values the provider accepts from the manager's client cert.
  # Maps to VIRTRIGAUD_PROVIDER_ALLOWED_SANS (comma-joined). Empty
  # (default) is permissive: any cert signed by the configured CA.
  allowedSANs: []

  # Explicit plaintext escape hatch. Maps to VIRTRIGAUD_PROVIDER_INSECURE.
  # Only honoured when secretName is empty. false by default.
  insecure: false
```

Chart behaviour:

| `secretName` | `insecure` | Result |
|--------------|-----------|--------|
| set | (any) | Secret mounted at `/etc/virtrigaud/tls`; provider runs mTLS-mandatory. `allowedSANs` is wired through `VIRTRIGAUD_PROVIDER_ALLOWED_SANS`. |
| empty | `true` | No mount; `VIRTRIGAUD_PROVIDER_INSECURE=true` is set; provider boots in audit-flagged plaintext. |
| empty | `false` | No TLS env wiring rendered; the provider's own startup check **hard-exits** (secure-by-default). |

The chart ships **no cert-manager `Certificate` or issuer template**. Provision the Secret yourself; cert-manager is a fine way to produce it (see below).

## Producing the Secret with cert-manager

cert-manager is a convenient way to *produce* the `tls.crt` / `tls.key` / `ca.crt` Secret. The chart does **not** create these resources — you apply them yourself. Root the issuer in your organisation's private PKI, **not** a public CA.

```yaml
# 1. A private CA issuer (or reuse your org's existing ClusterIssuer).
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: virtrigaud-ca-issuer
  namespace: virtrigaud-system
spec:
  ca:
    secretName: virtrigaud-ca-keypair   # your CA cert + key, provisioned out of band
---
# 2. A Certificate that produces the provider's server Secret.
#    cert-manager writes tls.crt / tls.key, and (with the ca.crt option)
#    the CA bundle into the same Secret — exactly the three keys VirtRigaud reads.
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: provider-vsphere-prod-tls
  namespace: virtrigaud-system
spec:
  secretName: provider-vsphere-prod-tls        # referenced by the Provider CR's secretRef
  issuerRef:
    name: virtrigaud-ca-issuer
    kind: Issuer
  commonName: provider-vsphere-prod
  dnsNames:
    - virtrigaud-provider-virtrigaud-system-provider-vsphere-prod.virtrigaud-system.svc.cluster.local
  duration: 2160h     # 90 days
  renewBefore: 720h   # rotate 30 days early; leaf hot-reloads, no restart
```

!!! note "Match the SAN to the manager's expected ServerName"
    The manager dials the provider with `ServerName` set to the provider Service FQDN (`virtrigaud-provider-<namespace>-<name>.<namespace>.svc.cluster.local`). The provider server certificate's DNS SAN **must** include that FQDN, or the manager's verification fails. Mint the manager's own client certificate from the same CA, with a SAN you can list in `providerTLS.allowedSANs` if you want SAN-level authorization rather than the permissive CA-only default.

For the manual `openssl`-only recipe (CA, manager client cert, and N provider server certs) and the operator runbook, see the in-repo operator security guide and the [Operations → Security](../../operations/security.md) page.

## Certificate management recommendations

For a regulated deployment:

- **Use a private CA** rooted in your organisation's PKI (a cert-manager `Issuer`/`ClusterIssuer` over your CA, or your existing PKI pipeline). Do **not** use a public CA.
- **Use short-lived leaf certs** (e.g. 90-day `duration`, 30-day `renewBefore`) and rely on leaf hot-reload — no pod restart is needed for leaf rotation.
- **Schedule CA rotations as rolling provider restarts**, since the CA bundle does not hot-reload. Keep CA lifetimes long enough that this is infrequent and planned.
- **Populate `AllowedSANs`** when more than one identity could present a cert signed by the CA, so a provider only accepts its own manager. Leave it empty only when the CA's signing scope is exactly your manager's identity.
- **Keep TLS Secrets distinct from credential Secrets** — they use different keys and different mount paths (`/etc/virtrigaud/tls` vs `/etc/virtrigaud/credentials`) and should be managed independently.

## Breaking change: v0.3.6 → v0.3.7 (historical)

!!! note "Upgrading v0.3.7 → v0.3.8 needs no mTLS action"
    The breaking change documented below landed on the **v0.3.6 → v0.3.7** upgrade. Upgrading from **v0.3.7 → v0.3.8** requires no mTLS changes — the posture is unchanged. This section is retained for operators still moving off v0.3.6.

!!! danger "Existing Provider CRs without a `tls` block will not reconcile after upgrade from v0.3.6"
    In v0.3.6, the `spec.runtime.service.tls` block had no runtime effect. In v0.3.7, a **nil** `tls` block is a loud failure: the Provider reports `TLSConfigured=False, Reason=TLSBlockMissing` and **no Deployment is created** until the operator decides.

    Before or immediately after upgrading, for each existing Provider CR either:

    1. **Enable mTLS** — provision a Secret with `tls.crt` / `tls.key` / `ca.crt`, then set `tls.enabled=true` with `secretRef.name`, **or**
    2. **Opt into plaintext explicitly** — set `tls.enabled=false` to keep plaintext (audit-flagged; `TLSConfigured=False, Reason=ExplicitlyDisabled`).

    This is intentional secure-by-default behaviour, not a bug. Auditors can confirm posture with `kubectl get providers` and the `TLSConfigured` condition.

## See also

- [Operations -> Security](../../operations/security.md) — overall v0.3.8 security posture, including the [resolved-gap inventory](../../operations/security.md#v036-security-gap-inventory).
- [Bearer Token Authentication](bearer-token.md) — the other half of the gRPC-channel and hypervisor-credential auth story.
- [Network Policies](network-policies.md) — defence-in-depth, and the required compensating control for any Provider you run with `tls.enabled=false`.
- [Resilience](../../operations/resilience.md) — per-Provider CircuitBreaker limits the blast radius of a degraded or spoofed provider.
