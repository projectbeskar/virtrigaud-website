<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VirtRigaud Security Guide

This is the canonical operator-facing security reference for VirtRigaud **v0.3.7**. It describes the current security posture honestly: what the code actually does, what the operator is expected to provide, and what remains out of scope for a regulated (e.g. banking) deployment.

!!! success "v0.3.7 is a security-hardening release"
    v0.3.7 closes the two highest-severity transport gaps that were open in v0.3.6:

    - **Manager↔provider gRPC is now protected by mutual TLS by default** (TLS 1.3 floor, fail-closed providers, client-cert SAN allow-list). See [gRPC transport](#grpc-transport-between-manager-and-providers).
    - **Libvirt SSH host-key verification is on by default** — the legacy `no_verify=1` behaviour is gone. See [Libvirt SSH host-key verification](#libvirt-ssh-host-key-verification).

    Manager RBAC was also tightened to least-privilege (Secret access is now read-only). The historical gap list, now annotated with what shipped, is retained at [v0.3.6 security gap inventory](#v036-security-gap-inventory) so links from older pages still resolve.

!!! warning "Two breaking changes on upgrade from v0.3.6"
    1. Existing **Provider CRs without a `spec.runtime.service.tls` block fail to reconcile** until you provision a TLS Secret (`tls.enabled=true` + `secretRef`) or explicitly opt into plaintext (`tls.enabled=false`).
    2. Existing **libvirt SSH Providers relying on implicit `no_verify=1` stop connecting** until a `known_hosts` entry is added (or the documented env opt-out is set).

    Both are intentional secure-by-default changes. Details below.

## Threat model

### What VirtRigaud is trying to protect

- **Hypervisor credentials** at rest in K8s Secrets and in flight between the provider pod and the hypervisor API endpoint (vCenter SOAP, libvirt over SSH, Proxmox REST).
- **Operator intent** carried by `VirtualMachine` / `Provider` / `VMMigration` CRs — these are authoritative declarations of cluster state.
- **Provider runtime integrity** — the per-`Provider` Deployment that runs the gRPC server and holds the credentials Secret.

### What VirtRigaud relies on Kubernetes to provide

- **API-server authentication and authorization** — every `kubectl apply` or controller action is authorised by the kube-apiserver against RBAC.
- **Secret encryption at rest** — VirtRigaud assumes the operator has enabled `EncryptionConfiguration` on the kube-apiserver; the credentials Secret is otherwise stored in etcd as base64.
- **Namespace boundaries** — VirtRigaud does **not** invent novel sandboxing. A cluster-admin can `kubectl get secret` from any namespace and read every provider credential. Treat manager- and provider-hosting namespaces as **high-privilege**.
- **Pod-network policy enforcement** — Kubernetes NetworkPolicies require a CNI that enforces them (Calico, Cilium, etc.). Without a CNI that enforces them, the [Network Policies](../providers/security/network-policies.md) page is documentation, not control.
- **PKI for admission webhooks** — VirtRigaud's admission webhook (`charts/virtrigaud/templates/webhooks.yaml`) needs a TLS cert. The Helm chart can generate one (`webhooks.secretName`) or you can wire cert-manager.

### What VirtRigaud is NOT trying to protect against

- **A compromised cluster-admin.** Cluster-admin can read all Secrets in all namespaces, including every provider credential. That is a Kubernetes RBAC concern.
- **A compromised hypervisor.** If vCenter / Proxmox / libvirt itself is owned, VirtRigaud is not a defender — the credentials it holds will be misused.
- **Side-channel attacks against shared infrastructure.** VirtRigaud has no model for noisy-neighbour or hardware-level isolation; that is a hypervisor concern.

### STRIDE quick-reference

| Threat                  | Where VirtRigaud is exposed                                          | Mitigation status in v0.3.7                                                                         |
|-------------------------|----------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| **Spoofing**            | A rogue Provider CR could point the manager at an attacker endpoint; a spoofed provider service could intercept manager RPCs. | RBAC on the Provider CR plus **mTLS**: the manager verifies the provider's server cert (TLS 1.3, SNI anchored to the Service FQDN) and the provider rejects any caller whose client cert is not signed by the configured CA / not on the SAN allow-list. |
| **Tampering**           | Provider gRPC traffic on the pod network.                            | gRPC is **encrypted with mTLS by default** in v0.3.7. Plaintext requires an explicit per-Provider opt-out. |
| **Repudiation**         | Admin actions on CRs.                                                | K8s audit logs (operator-provided). VirtRigaud emits `Events` for reconcile decisions. The `TLSConfigured` Condition records TLS posture per Provider for auditors. |
| **Information disclosure** | Credentials in logs, status, events, metrics labels.              | Audited: no credentials are logged or returned in `Status`. Length-only diagnostics (e.g. `password_length=N`) are present. Credentials now travel only inside mTLS-protected gRPC streams. |
| **Denial of service**   | Runaway provider RPCs, controller starvation.                         | Per-Provider CircuitBreaker (G6/#112) limits how loudly a flapping provider can fail. See [Resilience](resilience.md). |
| **Elevation of privilege** | Manager ServiceAccount has cluster-wide write on VirtRigaud CRDs. | RBAC scoped to `infra.virtrigaud.io` + a narrow set of core K8s verbs; Secret access tightened to **read-only** (`get;list;watch`) in v0.3.7. No `*` resources, no `cluster-admin`. |

## Provider credentials

### How credentials flow

```
K8s Secret (operator-supplied)
        │
        │ referenced by Provider.spec.credentialSecretRef.name
        ▼
ProviderReconciler (internal/controller/provider_controller.go:697)
        │  mounts Secret read-only as a volume named "provider-credentials"
        │  at /etc/virtrigaud/credentials inside the provider pod
        ▼
Provider pod (vsphere / libvirt / proxmox / mock)
        │  reads individual keys as FILES, one file per Secret key
        ▼
Hypervisor API (vCenter SOAP / libvirt SSH / Proxmox REST)
```

Credentials are **never** placed in env vars by the controller. They are mounted as files. Each provider reads only the keys it needs.

### Secret-key naming by provider

| Provider | Secret keys read (filename under `/etc/virtrigaud/credentials/`) | Source reference |
|---------|------------------------------------------------------------------|-------------------|
| **vSphere** | `username`, `password` | `internal/providers/vsphere/server.go:129-140` |
| **Libvirt** | `username`, `password` (for password SSH), or `ssh-privatekey` (for key SSH) | `internal/providers/libvirt/virsh.go:115-133` |
| **Proxmox** | `token_id`, `token_secret` (preferred), or `username`, `password` (fallback) | `internal/providers/proxmox/server.go:69-72` |

For Proxmox specifically, **API tokens MUST be used in production**. See [Proxmox provider page](../providers/proxmox.md#authentication) for the rationale. Password auth is retained for development/CI parity only.

### What is logged

- VirtRigaud logs **length-only diagnostics** (e.g. `username_length=12 password_length=24`) at INFO level to confirm credentials were mounted, never the values.
- vSphere provider explicitly does not pass username/password as command-line arguments; the SOAP client uses `url.UserPassword` so they are not visible in process listings.
- libvirt SSH password auth uses `sshpass -e` (env-var-bearing) rather than command-line; the SSH transport itself now verifies the host key by default (see [Libvirt SSH host-key verification](#libvirt-ssh-host-key-verification) below).

### Where credentials are NOT exposed

- They never appear in `Provider.status`.
- They never appear in `Event` records.
- They never appear in metric labels (label cardinality is bounded; secret values would be unbounded anyway).
- gRPC request/response logging (when enabled via the SDK Logging middleware) does not include user_data/meta_data payloads or credential fields.

## gRPC transport between manager and providers

!!! success "mTLS is wired and on by default in v0.3.7"
    Manager↔provider gRPC traffic is protected by **mutual TLS by default** (ADR-0003, #147/#148). The manager loads a client cert + key + CA bundle from the Provider's TLS Secret and dials over **TLS 1.3** with the SNI `ServerName` anchored to the provider Service FQDN. The provider serves mTLS with `RequireAndVerifyClientCert` and enforces a SAN allow-list before any RPC is accepted.

    Plaintext gRPC is no longer the default. A provider with no TLS material and no explicit opt-out **hard-exits on startup** (fail-closed). The full configuration, escape hatches, and rotation story live on the [mTLS page](../providers/security/mtls.md).

    For a banking deployment, mTLS is now the **primary** transport control; NetworkPolicy + encrypted CNI remain valid defence-in-depth and are the required compensating control for any Provider you deliberately run with `tls.enabled=false`.

### How it is wired

- **CRD field with runtime effect.** `Provider.spec.runtime.service.tls` (`enabled`, `secretRef`, `insecureSkipVerify`) now drives behaviour. The referenced Secret carries `tls.crt` / `tls.key` / `ca.crt` (a `kubernetes.io/tls` Secret or an `Opaque` Secret with those three keys; both accepted) and is mounted on the provider pod at `/etc/virtrigaud/tls`.
- **Manager side** (`internal/runtime/remote/resolver.go`): `MinVersion=TLS1.3`, `RootCAs` from `ca.crt`, client `Certificates` from `tls.crt`+`tls.key`, `ServerName` anchored to the provider Service FQDN.
- **Provider side** (SDK): `MinVersion=TLS1.3`, `RequireAndVerifyClientCert`, CA bundle in `ClientCAs`, SAN allow-list via `validateTLSPeer`.
- **Status condition** `TLSConfigured` (reasons `Enabled` / `ExplicitlyDisabled` / `SecretRefMissing` / `TLSBlockMissing`) makes posture auditable via `kubectl get providers`.
- **Cert rotation** hot-reloads the **leaf** cert/key without a pod restart; rotating the **CA bundle** still requires a provider restart. Documented limitation.

!!! warning "Breaking change on upgrade"
    Existing Provider CRs **without** a `spec.runtime.service.tls` block fail to reconcile (`TLSConfigured=False, Reason=TLSBlockMissing`, **no Deployment created**) until the operator either provisions a Secret with `tls.enabled=true` + `secretRef`, or explicitly sets `tls.enabled=false` for audit-flagged plaintext. There is **no global `--insecure-no-tls-providers` flag** — per-Provider `tls.enabled=false` (or `providerTLS.insecure` for chart-templated providers) is the only escape hatch.

### Provider-side gRPC server authentication

The provider SDK (`sdk/provider/middleware/middleware.go`) defines:

- `AuthConfig.RequireTLS` + `AuthConfig.AllowedSANs` — refuse RPCs without a verified client cert (mTLS), and gate accepted identities by SAN/CN allow-list.
- `AuthConfig.BearerTokenAuth` + `AuthConfig.ValidateToken` — accept a Bearer-token Authorization metadata header and validate it with an operator-supplied function.

!!! note "mTLS auth is now enabled in the in-tree providers"
    All four in-tree provider binaries (`cmd/provider-vsphere`, `cmd/provider-libvirt`, `cmd/provider-proxmox`, `cmd/provider-mock`) enable `Auth.RequireTLS` when TLS material is present. The libvirt provider was migrated onto the SDK server path so it gets the same auth middleware as the others. `validateTLSPeer` rejects an unverified caller with gRPC `Unauthenticated` and a non-matching SAN with `PermissionDenied`. An **empty** allow-list is permissive (any cert signed by the configured CA is accepted — single-CA trust model); populate `VIRTRIGAUD_PROVIDER_ALLOWED_SANS` for SAN-level authorization. See the [mTLS page](../providers/security/mtls.md#the-san-allow-list).

    Bearer-token auth on the gRPC channel remains available in the SDK but unused by the in-tree manager — it is not needed when the manager is the only legitimate caller. See [Bearer Token Authentication](../providers/security/bearer-token.md).

### Libvirt SSH host-key verification

!!! success "Host-key verification is on by default in v0.3.7"
    When a libvirt Provider CR uses a `qemu+ssh://` endpoint, the provider now **verifies the SSH host key** of the hypervisor it dials (ADR-0004, #149). The legacy `no_verify=1` behaviour has been removed from the default path. There is **no TOFU (trust-on-first-use)**: if verification is on but no usable `known_hosts` is present, the connection **hard-fails** with an actionable error rather than silently accepting any key.

**Trust material.** The host key lives in a `known_hosts` entry inside the existing libvirt credentials Secret (the one referenced by `credentialSecretRef`), mounted at `/etc/virtrigaud/credentials/known_hosts`. Seed it with:

```bash
ssh-keyscan -H <libvirt-host> >> known_hosts
```

then add the resulting `known_hosts` key to the credentials Secret. The full operational runbook (keyscan, Secret update, rollout) lives on the libvirt provider and host-prep pages; this page only covers the security framing.

**Escape hatch (lab / migration only).** Set the environment variable `LIBVIRT_INSECURE_SKIP_HOST_KEY_VERIFICATION=true` via `spec.runtime.env` to fall back to non-verifying behaviour. This is **audit-flagged**: a WARN is logged on every connection. Do not use it in regulated environments.

!!! warning "Breaking change on upgrade"
    v0.3.6 libvirt SSH Providers relied on implicit `no_verify=1`. After upgrading to v0.3.7 they **stop connecting** until either a `known_hosts` entry is added to the credentials Secret, or the `LIBVIRT_INSECURE_SKIP_HOST_KEY_VERIFICATION=true` opt-out is set. This is the security control working as designed — a clean, actionable connection failure replaces a silent insecure success.

**Defence-in-depth (still recommended):** keep the libvirt provider pod and the libvirt host on the same private subnet behind a CNI that enforces traffic on that path, with a NetworkPolicy scoping egress. Host-key verification is now the primary control; network isolation is the backstop.

## RBAC

### Manager RBAC

`charts/virtrigaud/templates/manager-rbac.yaml` grants the manager's ServiceAccount these verbs:

- **VirtRigaud CRDs** (`infra.virtrigaud.io`): `create, delete, get, list, patch, update, watch` on `virtualmachines`, `providers`, `vmsnapshots`, `vmclones`, `vmmigrations`, `vmsets`, `vmclasses`, `vmimages`, `vmnetworkattachments`, `vmplacementpolicies` (and their `/status` and `/finalizers` subresources).
- **`secrets`**: `get, list, watch` only — **read-only as of v0.3.7** (#152). The manager resolves `Provider.spec.credentialSecretRef` and the TLS `secretRef` to mount them into provider Deployments; it never creates, updates, or deletes Secrets.
- **Core K8s**: `configmaps, services, events` (scoped to the verbs each actually needs).
- **`persistentvolumeclaims`** (for migration storage).
- **`pods`**: `get, list, watch` (for provider-readiness checks).
- **`apps/deployments`** (for spawning provider pods).
- **`coordination.k8s.io/leases`**: leader election.
- **`metrics.k8s.io/pods,nodes`**: `get, list`.

**No wildcards. No `cluster-admin`. No `*` resources.** The chart supports `rbac.scope=namespace` for single-namespace deployments via the Role/RoleBinding branch.

!!! note "Secrets verb scope tightened in v0.3.7"
    The manager's Secret access was reduced from full CRUD to **read-only** (`get;list;watch`) in v0.3.7 (#152), and unused/phantom grants were removed, bringing the ClusterRole to least-privilege. This requires a `helm upgrade` to take effect. If a custom deployment genuinely needs additional grants, re-add them via the chart's `rbac.additionalRules` value rather than widening the built-in role.

    Read-only is sufficient because:

    - `Provider.spec.credentialSecretRef` resolves to a Secret the manager mounts into the provider Deployment (read).
    - The TLS `secretRef` resolves to a Secret the manager reads to build the gRPC client config and mount on the provider pod (read).
    - The migration-PVC Secret bridge reads, not writes, Secret material.

### Provider pod RBAC

Each Provider gets its own ServiceAccount (auto-created by the controller). Provider pods have **no Kubernetes API access by default**. They are not granted any `Role`, so a compromised provider pod cannot list other Secrets or escape its own credential mount.

This is enforced by the absence of a RoleBinding on the per-Provider ServiceAccount. If you add custom RBAC for a provider, scope it to the resources that provider actually needs (typically: none).

## Container hardening

| Component             | Base image                              | USER        | Read-only root FS | Caps        |
|----------------------|------------------------------------------|-------------|-------------------|-------------|
| Manager              | `gcr.io/distroless/static:nonroot`       | `65532:65532` | Enforced via Pod SecurityContext | drop ALL |
| provider-vsphere     | `gcr.io/distroless/static:nonroot`       | `65532:65532` | Yes                                | drop ALL |
| provider-proxmox     | `gcr.io/distroless/static:nonroot`       | `65532:65532` | Yes                                | drop ALL |
| provider-mock        | `gcr.io/distroless/static:nonroot`       | `65532:65532` | Yes                                | drop ALL |
| provider-libvirt     | `debian:bookworm-slim` (needs libvirt-libs, openssh-client, libxml2) | `app`     | Yes                                | drop ALL |

The provider-libvirt image is the only one that cannot use distroless because it shells out to `virsh`, `ssh`, and `scp`. It is still non-root and reads its own root filesystem read-only. References: `cmd/provider-libvirt/Dockerfile`, `build/Dockerfile.provider-vsphere`, `build/Dockerfile.manager`, `cmd/provider-proxmox/Dockerfile`, `cmd/provider-mock/Dockerfile`.

The `securityContext` applied to every provider pod by the controller (`internal/controller/provider_controller.go:602-611`):

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 65532
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
```

You should apply equivalent settings to the manager Deployment via Helm values if your cluster's Pod Security Standards do not enforce them already.

## Metrics endpoint security

By default in v0.3.6, the manager's `/metrics` endpoint is **HTTP on `:8080`, unauthenticated**. This is the controller-runtime default, ported into the canonical manager entrypoint by H1 PR-1 (#115) as part of the v0.3.6 build-path consolidation (#92).

### Opting into RBAC-authenticated `/metrics`

Pass `--metrics-secure=true` to the manager. When this flag is set:

- `/metrics` is served over HTTPS.
- `metrics/filters.WithAuthenticationAndAuthorization` (`cmd/manager/main.go:209`) is installed as the metrics FilterProvider.
- Every scrape must present a Kubernetes-issued bearer token (typically a ServiceAccount token from the Prometheus pod). The token's TokenReview must succeed AND a SubjectAccessReview must show the token holder has `get` on `nonResourceURLs: ["/metrics"]`.

You must therefore grant Prometheus's ServiceAccount the right to scrape:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-metrics-scraper
rules:
  - nonResourceURLs: ["/metrics"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-metrics-scraper
subjects:
  - kind: ServiceAccount
    name: prometheus-server
    namespace: monitoring
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus-metrics-scraper
```

!!! note "HTTPS-default flip is deferred to v0.4.0"
    `--metrics-secure=false` is the v0.3.6 default. The HTTPS-default flip is intentionally deferred to v0.4.0 to give the H1 build-path consolidation a release of bake time on the canonical manager entrypoint. Operators in regulated environments should pass `--metrics-secure=true` today; the default flip simply removes a footgun for new deployments.

### Provider metrics

The per-provider metrics surface (e.g. RPC metrics emitted by the gRPC client interceptor) is exposed on **the manager's** `/metrics` endpoint — provider pods themselves do **not** expose a Prometheus endpoint. Their `:8080` port is the healthz endpoint only. So securing manager `/metrics` is sufficient to secure all `virtrigaud_*` metric series.

See [Observability Guide](observability.md) for the metric catalogue.

## CircuitBreaker as a denial-of-service control

The per-Provider CircuitBreaker (G6 / #112, wired in v0.3.6) is also a security control: it caps how loudly a wedged, flapping, or compromised provider can fail. When the breaker is open, the manager fast-fails RPCs to that provider with `codes.Unavailable` for a cool-down period instead of hammering it.

Operationally, this means an attacker who manages to put a single provider into a degraded state cannot use that provider to consume controller worker slots indefinitely. See [Resilience](resilience.md) for the lifecycle, metrics, and tuning.

## Supply chain

### CVE management

- **Container images are scanned with Trivy** on every release (`.github/workflows/release.yml:185-198`). The release workflow **fails** if Trivy finds any HIGH or CRITICAL severity vulnerability. v0.3.6 itself was held back until 3 HIGH-severity OpenTelemetry CVEs (CVE-2026-29181, CVE-2026-24051, CVE-2026-39883) were addressed by PR #144.
- **Code is scanned with Trivy in repo mode** on every CI run (`.github/workflows/ci.yml:160-171`). Results are uploaded to the GitHub Security tab as SARIF.
- **Container image signing with cosign** is enabled on releases (`.github/workflows/release.yml:136-140`). Verify images before pulling in regulated environments:

  ```bash
  cosign verify ghcr.io/projectbeskar/virtrigaud/manager:v0.3.6 \
    --certificate-identity-regexp='.*' \
    --certificate-oidc-issuer='https://token.actions.githubusercontent.com'
  ```

### GitHub Actions pinning

All third-party Actions are pinned to **40-character commit SHAs**, not floating tags. Dependabot maintains the SHA-pin policy via `.github/dependabot.yml` (see #135 for the policy ratification).

### Go module integrity

- `go.sum` is verified on every CI run via `go mod download` against the module proxy.
- `make verify-tidy` (the convention) fails on a dirty `go mod tidy` diff.
- The project does not currently run `govulncheck` in CI as a blocking check; that is on the v0.4.0 hardening list.

## CRD input validation

Every string field that flows to a hypervisor API call has Kubebuilder validation. Spot-check examples:

- `Provider.spec.endpoint`: regex-validated to accept only well-formed `http(s)://`, `tcp://`, `grpc://`, or `qemu(+ssh|+tcp|+tls)://` URIs (`api/infra.virtrigaud.io/v1beta1/provider_types.go:218`).
- `Provider.spec.type`: enum-validated to one of `vsphere | libvirt | firecracker | qemu | proxmox`.
- `ProviderDefaults.{datastore,cluster,folder,resourcePool,network}`: `MaxLength=255`.
- `ProviderRuntimeSpec.image`: regex-validated to enforce `image[:tag][@digest]` format only.
- Numeric ports, replicas, QPS, burst — all range-bounded.

Cloud-init `userdata` (carried in `VirtualMachine.spec.userData.cloudInit`) is treated as **opaque bytes** by the manager and never interpreted as shell. It is forwarded to the provider as a raw byte payload via the `CreateRequest.UserData` proto field.

## Vulnerability reporting

**Please do not report security vulnerabilities through public GitHub issues.**

Email `security@virtrigaud.io` with:

- A description of the vulnerability
- Steps to reproduce
- Potential impact
- Any mitigations you have already identified

You should receive a response within 48 hours.

### Severity classification

- **Critical**: patch within 24 hours; out-of-band release if needed.
- **High**: patch within 7 days.
- **Medium**: patch within 30 days.
- **Low**: patch in the next regular release.

We coordinate disclosure on a 90-day default timeline.

## Supported versions

| Version | Supported |
|---------|-----------|
| 0.3.x   | yes       |
| < 0.3   | no        |

## v0.3.6 security gap inventory

This section tracks the security gaps that were open in v0.3.6 and records what shipped to close them. The heading and anchor (`#v036-security-gap-inventory`) are retained so links from older pages still resolve. The two highest-severity transport gaps are **resolved in v0.3.7**.

!!! success "Resolved in v0.3.7"
    | Former gap | Status in v0.3.7 |
    |------------|------------------|
    | **mTLS not wired through Resolver** — the CRD field had no runtime effect. | **Resolved.** `Provider.spec.runtime.service.tls` now drives mTLS by default (TLS 1.3 floor). See [gRPC transport](#grpc-transport-between-manager-and-providers). |
    | **In-tree providers did not enable mTLS/Bearer auth** in their middleware. | **Resolved.** All four in-tree providers enforce `Auth.RequireTLS` + the SAN allow-list; libvirt was migrated onto the SDK server. Unauthenticated callers are rejected (`Unauthenticated`); off-list certs get `PermissionDenied`. |
    | **libvirt SSH `no_verify=1`** disabled host-key verification. | **Resolved.** Host-key verification is **on by default** (no TOFU). Trust material is a `known_hosts` key in the credentials Secret; audit-flagged env opt-out exists for lab use. See [Libvirt SSH host-key verification](#libvirt-ssh-host-key-verification). |
    | **Manager RBAC included `secrets` `create/delete/update`** wider than required. | **Resolved.** Secret access tightened to read-only (`get;list;watch`); unused grants removed (#152). Re-add via `rbac.additionalRules` if genuinely needed. |

The following remain open and operators in regulated environments must factor them into their compensating-control posture:

| Gap | Severity (banking) | Mitigation today |
|-----|---------------------|-------------------|
| **Manager `--metrics-secure=false`** is still the default. | MEDIUM | Pass `--metrics-secure=true` and wire RBAC for Prometheus. Default flip planned for a later release. |
| **`govulncheck` is not a CI gate.** Trivy on the image catches CVEs at release time, but not at PR time. | LOW | Manual `govulncheck ./...` before tag. |
| **provider-libvirt image is `debian:bookworm-slim`**, not distroless, because it shells out to `virsh` / `ssh` / `scp`. | LOW | Image is still non-root + readOnlyRootFS + dropAllCaps. Future: replace SSH-virsh with libvirt-go. |
