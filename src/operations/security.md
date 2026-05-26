<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VirtRigaud Security Guide

This is the canonical operator-facing security reference for VirtRigaud **v0.3.6**. It describes the current security posture honestly: what the code actually does today, what it does not yet do, and what the operator is expected to provide for a regulated (e.g. banking) deployment.

!!! warning "Read this before relying on the page below"
    Several security features that an experienced operator might **expect** from a Kubernetes operator that talks to hypervisors are **not yet implemented in v0.3.6**. They are called out inline with `[NOT WIRED IN v0.3.6]` admonitions. Do not silently assume a control is in place; verify against the source references provided.

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

| Threat                  | Where VirtRigaud is exposed                                          | Mitigation status in v0.3.6                                                                         |
|-------------------------|----------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| **Spoofing**            | A rogue Provider CR could point the manager at an attacker endpoint. | RBAC on Provider CR is the only gate. mTLS between manager and provider is **[NOT WIRED]** — see below. |
| **Tampering**           | Provider gRPC traffic on the pod network.                            | gRPC is plaintext by default in v0.3.6. Treat the pod network as trusted (CNI encryption / private cluster). |
| **Repudiation**         | Admin actions on CRs.                                                | K8s audit logs (operator-provided). VirtRigaud emits `Events` for reconcile decisions.              |
| **Information disclosure** | Credentials in logs, status, events, metrics labels.              | Audited: no credentials are logged or returned in `Status`. Length-only diagnostics (e.g. `password_length=N`) are present. |
| **Denial of service**   | Runaway provider RPCs, controller starvation.                         | Per-Provider CircuitBreaker (G6/#112) limits how loudly a flapping provider can fail. See [Resilience](resilience.md). |
| **Elevation of privilege** | Manager ServiceAccount has cluster-wide write on VirtRigaud CRDs. | RBAC scoped to `infra.virtrigaud.io` + a narrow set of core K8s verbs. No `*` resources, no `cluster-admin`. |

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
- libvirt SSH password auth uses `sshpass -e` (env-var-bearing) rather than command-line — but see the [SSH host-key verification gap](#libvirt-ssh-host-key-verification) below; password-over-network has a separate threat.

### Where credentials are NOT exposed

- They never appear in `Provider.status`.
- They never appear in `Event` records.
- They never appear in metric labels (label cardinality is bounded; secret values would be unbounded anyway).
- gRPC request/response logging (when enabled via the SDK Logging middleware) does not include user_data/meta_data payloads or credential fields.

## gRPC transport between manager and providers

!!! danger "mTLS is documented for future support; not wired in v0.3.6"
    The `internal/transport/grpc/client.go` `Client` accepts a `TLSConfig` (CertFile, KeyFile, CAFile, Insecure — see lines 951-991) and builds gRPC transport credentials correctly. However, the `internal/runtime/remote/resolver.go` `buildTLSConfig()` method that **decides whether to populate that TLSConfig** is currently short-circuited:

    ```go
    // internal/runtime/remote/resolver.go:142-148
    func (r *Resolver) buildTLSConfig(ctx context.Context, provider *infravirtrigaudiov1beta1.Provider) (*grpcClient.TLSConfig, error) {
        // If TLS is not enabled, return nil for insecure connection
        // TLS configuration removed in v1beta1, always return nil for insecure connection
        if true {
            return nil, nil
        }
        // ... unreachable code follows
    }
    ```

    **Net effect**: regardless of whether you populate `Provider.spec.runtime.service.tls.secretRef` on a Provider CR, the manager dials providers with `insecure.NewCredentials()` (plaintext gRPC). The CRD field is parsed and validated but has no runtime effect in v0.3.6.

    **What this means for a banking deployment**: the pod-network path between manager and provider is currently a plaintext gRPC channel. You must treat the pod network as trusted (encrypted CNI such as Cilium with WireGuard, or a network policy that guarantees the traffic never crosses an untrusted boundary). Plan to revisit this when first-class mTLS lands.

    Tracking: this is a known v0.3.6 gap. See "[v0.3.6 security gap inventory](#v036-security-gap-inventory)" below.

### Provider-side gRPC server authentication

The provider SDK (`sdk/provider/middleware/middleware.go:81-94`) defines:

- `AuthConfig.RequireTLS` — refuse RPCs without a valid client cert (mTLS).
- `AuthConfig.BearerTokenAuth` + `AuthConfig.ValidateToken` — accept a Bearer-token Authorization metadata header and validate it with an operator-supplied function.

!!! warning "Auth interceptors are present in the SDK but NOT wired in the in-tree providers"
    The four in-tree provider binaries (`cmd/provider-vsphere`, `cmd/provider-libvirt`, `cmd/provider-proxmox`, `cmd/provider-mock`) construct their middleware config with only `Logging` and `Recovery` interceptors. None enable `Auth.RequireTLS` or `Auth.BearerTokenAuth`. The libvirt provider in `cmd/provider-libvirt/main.go` does not even use the SDK's `server.New(config)` path — it constructs a raw `grpc.NewServer()` with no middleware at all.

    **An external provider author** writing their own binary against `sdk/provider` MAY enable Bearer-token auth today; see [Bearer Token Authentication](../providers/security/bearer-token.md). The manager does not currently send a bearer token, so an external provider that requires one will reject the manager's RPCs.

### Libvirt SSH host-key verification

When a libvirt Provider CR uses a `qemu+ssh://` endpoint, the provider injects `no_verify=1` into the SSH URI:

```go
// internal/providers/libvirt/virsh.go:165-171
if strings.Contains(parsedURI.Scheme, "ssh") {
    query := parsedURI.Query()
    query.Set("no_verify", "1") // Skip host key verification
    query.Set("no_tty", "1")    // Non-interactive mode
    parsedURI.RawQuery = query.Encode()
}
```

This means the libvirt provider does **not verify the SSH host key** of the hypervisor it dials. An attacker who can MITM the pod-to-hypervisor connection can present any host key and the provider will accept it.

**Mitigations for regulated environments:**

1. **Treat the network path as trusted.** Co-locate the libvirt provider pod and the libvirt host on the same private subnet, behind a CNI that enforces traffic on that path (Calico + WireGuard, Cilium + IPsec). Combine with a NetworkPolicy that allows egress to that subnet only.
2. **Mount a known_hosts file.** Bake the libvirt host's host key into a ConfigMap, mount it at a known path, and modify the provider Deployment to consume it. This needs a code-path that consumes operator-provided known_hosts; **that path does not exist in v0.3.6** — it is a planned follow-up.
3. **Use an SSH-bastion proxy.** Stand up an SSH bastion with verified host keys; have the provider talk to the bastion instead of the libvirt host directly. The bastion verifies the next hop.
4. **Use a libvirt-go native binding.** Future direction: replace the `qemu+ssh+virsh` shell-out path with a libvirt-go API client that does TLS directly. Tracked as a v0.4.0+ follow-up.

For v0.3.6, the project's official posture is **option 1 (trusted network)**. Auditors should be told this explicitly.

## RBAC

### Manager RBAC

`charts/virtrigaud/templates/manager-rbac.yaml` grants the manager's ServiceAccount these verbs:

- **VirtRigaud CRDs** (`infra.virtrigaud.io`): `create, delete, get, list, patch, update, watch` on `virtualmachines`, `providers`, `vmsnapshots`, `vmclones`, `vmmigrations`, `vmsets`, `vmclasses`, `vmimages`, `vmnetworkattachments`, `vmplacementpolicies` (and their `/status` and `/finalizers` subresources).
- **Core K8s**: `secrets, configmaps, services, events` (`create, delete, get, list, patch, update, watch`).
- **`persistentvolumeclaims`** (for migration storage): full verbs.
- **`pods`**: `get, list, watch` (for provider-readiness checks).
- **`apps/deployments`** (for spawning provider pods): full verbs.
- **`coordination.k8s.io/leases`**: leader election.
- **`metrics.k8s.io/pods,nodes`**: `get, list`.

**No wildcards. No `cluster-admin`. No `*` resources.** The chart supports `rbac.scope=namespace` for single-namespace deployments via the Role/RoleBinding branch.

!!! note "Secrets verb scope"
    The manager needs `secrets` `get/list/watch` because:

    - `Provider.spec.credentialSecretRef` resolves to a Secret it must mount into the provider Deployment.
    - It owns the migration-PVC Secret bridge.

    It does **not** need `create/delete/update` on Secrets in principle. The current chart grants them; tightening this is a v0.4.0 follow-up.

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

This is the current honest list of security work the project is aware of and has not yet shipped. Operators in regulated environments must factor these into their compensating-control posture.

| Gap | Severity (banking) | Mitigation today |
|-----|---------------------|-------------------|
| **mTLS not wired through Resolver** — `internal/runtime/remote/resolver.go:142-148` short-circuits TLS config; CRD field exists but has no effect. | HIGH | Treat pod network as trusted (CNI-level encryption, NetworkPolicy). |
| **In-tree providers do not enable Bearer-token or mTLS auth** in their middleware config — `cmd/provider-{vsphere,proxmox,mock}/main.go` enable only Logging+Recovery; `cmd/provider-libvirt/main.go` uses no SDK middleware at all. | HIGH | NetworkPolicy that allows ingress to provider pods only from the manager pod. See [Network Policies](../providers/security/network-policies.md). |
| **libvirt SSH `no_verify=1`** — `internal/providers/libvirt/virsh.go:167` disables host-key verification. | HIGH | Trusted-network posture or SSH bastion; documented in the [libvirt provider page](../providers/libvirt.md#authentication). |
| **Manager `--metrics-secure=false`** is the v0.3.6 default. | MEDIUM | Pass `--metrics-secure=true` and wire RBAC for Prometheus. Default flip planned for v0.4.0. |
| **Manager RBAC includes `secrets` `create/delete/update`** that is wider than required. | LOW | Acceptable; tightening is a v0.4.0 follow-up. |
| **`govulncheck` is not a CI gate.** Trivy on the image catches CVEs at release time, but not at PR time. | LOW | Manual `govulncheck ./...` before tag. |
| **provider-libvirt image is `debian:bookworm-slim`**, not distroless, because it shells out to `virsh` / `ssh` / `scp`. | LOW | Image is still non-root + readOnlyRootFS + dropAllCaps. Future: replace SSH-virsh with libvirt-go. |
