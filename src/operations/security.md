<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VirtRigaud Security Guide

This is the canonical operator-facing security reference for VirtRigaud **v0.4.0**. It describes the current security posture honestly: what the code and the Helm chart actually do, what the operator is expected to provide, and what remains out of scope for a regulated (e.g. banking) deployment.

!!! info "What changed in v0.4.0"
    v0.4.0 is a large security-hardening release, mostly about **multi-tenancy**: several namespaces (tenants) sharing one hypervisor account. In summary (each item is described below, with the main-repository document that holds the detail):

    - **VM ownership.** Every VM a provider creates or adopts is stamped with the owner's UID; a provider binds to an existing VM only when it can prove the requesting `VirtualMachine` created it ([Ownership](#vm-ownership-and-owner-stamps)).
    - **Cross-namespace references need a grant.** A `Provider`, `VMClass` or `VMImage` in another namespace can be used only if its `spec.consumerNamespaceSelector` selects the referencing namespace; a clone or migration target in another namespace needs an `infra.virtrigaud.io/allowed-source-namespaces` annotation on the target namespace ([Cross-namespace use](#cross-namespace-use-of-a-provider)).
    - **Reserved-keys admission policy** (Kubernetes 1.30+): only the manager may write the provenance, claim and adoption annotations on a `VirtualMachine` ([Admission policy](#reserved-keys-admission-policy)).
    - **Provider in-use finalizer** (ADR-0010): a `Provider` that is still needed is not deleted from under its VMs ([Provider in-use finalizer](#provider-in-use-finalizer)).
    - **Identity-safe image preparation** (ADR-0009), **private cloud-init seeds**, **migration PVC mounts per migration**, and an opt-in **administrator disk-size limit** ([Hypervisor-side isolation](#hypervisor-side-isolation)).
    - **Chart:** opt-in `NetworkPolicy` templates, token-less per-Provider ServiceAccounts, a `/tmp` size limit on every pod, TLS 1.2 floor on the webhook and metrics servers ([RBAC](#rbac), [Container hardening](#container-hardening)).
    - The manager↔provider mTLS (v0.3.7), libvirt SSH host-key verification (v0.3.7) and least-privilege manager RBAC (v0.3.7) controls remain in force.

    Several of these are **breaking** for existing installs (a shared `Provider` stops working for other namespaces until it carries a `consumerNamespaceSelector`; a `VirtualMachine`'s `spec.providerRef` becomes immutable once bound; vSphere creates need a new vCenter privilege; libvirt VMs without `spec.userData` no longer get a default login; and more). Read the [breaking changes in the upgrade guide](https://github.com/projectbeskar/virtrigaud/blob/main/docs/upgrading.md#breaking-changes) before upgrading, and see the [Upgrade Guide](upgrade.md) of this site.

!!! warning "Security posture history retained"
    The two breaking transport changes of **v0.3.6 → v0.3.7** are unchanged and still apply to anyone upgrading from v0.3.6: a `Provider` without a `spec.runtime.service.tls` block does not deploy until you provision a TLS Secret or explicitly opt into plaintext, and libvirt SSH Providers no longer connect without a `known_hosts` entry. The historical gap list, annotated with what shipped, is retained at [v0.3.6 security gap inventory](#v036-security-gap-inventory).

## Threat model

### What VirtRigaud is trying to protect

- **Hypervisor credentials** at rest in K8s Secrets and in flight between the provider pod and the hypervisor API endpoint (vCenter SOAP, libvirt over SSH, Proxmox REST).
- **Operator intent** carried by `VirtualMachine` / `Provider` / `VMMigration` CRs — these are authoritative declarations of cluster state.
- **One tenant's VMs, disks and images from another tenant** that shares the same `Provider` (and so the same hypervisor account). This is the main goal of the v0.4.0 hardening.
- **Provider runtime integrity** — the per-`Provider` Deployment that runs the gRPC server and holds the credentials Secret.

### What VirtRigaud relies on Kubernetes to provide

- **API-server authentication and authorization** — every `kubectl apply` or controller action is authorised by the kube-apiserver against RBAC. The manager has cluster-wide rights; **tenant isolation depends on the RBAC you give tenants** ([below](#who-can-grant-what)).
- **Secret encryption at rest** — VirtRigaud assumes the operator has enabled `EncryptionConfiguration` on the kube-apiserver; the credentials Secret is otherwise stored in etcd as base64.
- **Namespace boundaries** — VirtRigaud does **not** invent novel sandboxing. A cluster-admin can `kubectl get secret` from any namespace and read every provider credential. Treat manager- and provider-hosting namespaces as **high-privilege**.
- **Pod-network policy enforcement** — Kubernetes NetworkPolicies require a CNI that enforces them (Calico, Cilium, etc.). Without one, the [Network Policies](../providers/security/network-policies.md) page and the chart's `networkPolicy` templates are documentation, not control.
- **PKI for admission webhooks** — the validating webhooks (off by default) need a serving certificate: the chart can generate one, render a cert-manager `Certificate`, or use one you supply (`webhooks.certificates.source`).
- **Kubernetes 1.30 or later** for the reserved-keys `ValidatingAdmissionPolicy`. On an older cluster nothing is rendered.

### What VirtRigaud is NOT trying to protect against

- **A compromised cluster-admin.** Cluster-admin can read all Secrets in all namespaces, including every provider credential.
- **A compromised hypervisor.** If vCenter / Proxmox / libvirt itself is owned, VirtRigaud is not a defender.
- **A tenant you share a `Provider` with, against what that Provider's account can read.** Sharing a `Provider` shares everything its credentials can reach: a tenant who may use it can create its own `VMImage` that names any template or image file the account can read. Share a `Provider` only with namespaces trusted with everything its hypervisor account can see, and scope that account accordingly.
- **Side-channel attacks against shared infrastructure.** VirtRigaud has no model for noisy-neighbour or hardware-level isolation.

### STRIDE quick-reference

| Threat                  | Where VirtRigaud is exposed                                          | Mitigation status in v0.4.0                                                                         |
|-------------------------|----------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| **Spoofing**            | A rogue Provider CR could point the manager at an attacker endpoint; a spoofed provider service could intercept manager RPCs; a tenant could forge the manager's provenance annotations on a `VirtualMachine`. | RBAC on the Provider CR plus **mTLS**: the manager verifies the provider's server cert (TLS 1.3, SNI anchored to the Service FQDN) and the provider rejects any caller whose client cert is not signed by the configured CA / not on the SAN allow-list. The [reserved-keys admission policy](#reserved-keys-admission-policy) stops tenants forging the manager's annotations. |
| **Tampering**           | Provider gRPC traffic on the pod network; one tenant's `Create`, `Clone` or image import overwriting another's VM, disk or template. | gRPC is **encrypted with mTLS by default**. Owner stamps, per-tenant domain/landing names and stamped image artifacts make providers refuse to bind to, or reuse, anything they cannot prove is the requester's. |
| **Repudiation**         | Admin actions on CRs.                                                | K8s audit logs (operator-provided). VirtRigaud emits `Events` for reconcile decisions and holds; operator confirmations (`OperationOutcomeConfirmed`) are logged and recorded as events, but the API server's audit log is the authoritative record of **who** set an annotation. The `TLSConfigured` condition records TLS posture per Provider. |
| **Information disclosure** | Credentials in logs, status, events, metrics labels; one tenant learning another's VMs, namespaces or hosts. | Audited: no credentials are logged or returned in `Status`. Refusals (`ProviderConflict`, `ArtifactConflict`, `ConsumerNotAllowed`, …) carry constant messages that name only the requester's own object; details are in the provider's log. Credentials travel only inside mTLS-protected gRPC streams. |
| **Denial of service**   | Runaway provider RPCs, controller starvation, a tenant filling a datastore or a node's disk. | Per-Provider CircuitBreaker (see [Resilience](resilience.md)); host-scoped failures do not open it. Opt-in `manager.maxDiskSize`; a `sizeLimit` on every pod's `/tmp`. |
| **Elevation of privilege** | Manager ServiceAccount has cluster-wide write on VirtRigaud CRDs; a tenant using a shared `Provider`; a tenant naming another tenant's disk. | RBAC scoped per resource (no `*`, no `cluster-admin`); cross-namespace use needs an explicit grant; disks are attached in place only when they are the VM's own verified landing disk. |

## Provider credentials

### How credentials flow

```
K8s Secret (operator-supplied, in the Provider's namespace)
        │
        │ referenced by Provider.spec.credentialSecretRef.name
        ▼
ProviderReconciler (internal/controller/provider_controller.go)
        │  mounts the Secret read-only as a volume named "provider-credentials"
        │  at /etc/virtrigaud/credentials inside the provider pod
        ▼
Provider pod (vsphere / libvirt / proxmox / mock)
        │  reads individual keys as FILES, one file per Secret key
        ▼
Hypervisor API (vCenter SOAP / libvirt SSH / Proxmox REST + SSH)
```

Credentials are **never** placed in env vars by the controller. They are mounted as files. Each provider reads only the keys it needs. The Secret lives in the Provider's own namespace; whoever can read Secrets there can read the credentials.

### Secret-key naming by provider

| Provider | Secret keys read (filename under `/etc/virtrigaud/credentials/`) |
|---------|------------------------------------------------------------------|
| **vSphere** | `username`, `password` |
| **Libvirt** | `username`, and `password` (password SSH) or `ssh-privatekey` (key SSH); `known_hosts` (SSH host-key trust, required unless the audit-flagged opt-out is set) |
| **Proxmox** | `token_id`, `token_secret` (preferred), or `username`, `password` (fallback). For the SSH **data plane** (migration disk import/export, `qemu-img`): `ssh_user`, `ssh_password` or `ssh_privatekey`, and `known_hosts` |

For Proxmox, **API tokens MUST be used in production**. See the [Proxmox provider page](../providers/proxmox.md#authentication) for the rationale and the [bearer-token page](../providers/security/bearer-token.md) for the privileges the token needs. Password auth is retained for development/CI parity only.

A **clustered** libvirt Provider's hosts use the Secret named by `Host.spec.credentialSecretRef` (else the Provider's own credentials Secret), always read from the Provider's namespace; the manager renders the SSH material of every host into a per-Provider Secret it owns (`<provider>-hosts`) that the provider pod mounts read-only. See the [clustered libvirt guide](../guides/clustered-libvirt.md).

### What is logged

- VirtRigaud logs **length-only diagnostics** (e.g. `username_length=12 password_length=24`) to confirm credentials were mounted, never the values.
- The vSphere provider uses `url.UserPassword` for the SOAP client, so credentials are not visible in process listings.
- The libvirt provider connects to hosts with an in-process SSH client; every command it sends over SSH is shell-quoted (v0.4.0), which closes a command-injection path through domain names, image paths and snapshot descriptions. The Proxmox data plane uses the `ssh` client with a mounted key or `sshpass`.

### Where credentials are NOT exposed

- They never appear in `Provider.status`.
- They never appear in `Event` records.
- They never appear in metric labels.
- gRPC request/response logging does not include user_data/meta_data payloads or credential fields.

## gRPC transport between manager and providers

!!! success "mTLS is wired and on by default (since v0.3.7)"
    Manager↔provider gRPC traffic is protected by **mutual TLS by default** (ADR-0003, shipped in v0.3.7, unchanged in v0.4.0). The manager loads a client cert + key + CA bundle from the Provider's TLS Secret and dials over **TLS 1.3** with the SNI `ServerName` anchored to the provider Service FQDN. The provider serves mTLS with `RequireAndVerifyClientCert` and enforces a SAN allow-list before any RPC is accepted.

    Plaintext gRPC is not the default. A provider with no TLS material and no explicit opt-out **hard-exits on startup** (fail-closed). The full configuration, escape hatches, and rotation story live on the [mTLS page](../providers/security/mtls.md).

    For a banking deployment, mTLS is the **primary** transport control; NetworkPolicy + encrypted CNI remain valid defence-in-depth and are the required compensating control for any Provider you deliberately run with `tls.enabled=false`.

### How it is wired

- **CRD field with runtime effect.** `Provider.spec.runtime.service.tls` (`enabled`, `secretRef`, `insecureSkipVerify`) drives behaviour. The referenced Secret carries `tls.crt` / `tls.key` / `ca.crt` (a `kubernetes.io/tls` Secret or an `Opaque` Secret with those three keys) and is mounted on the provider pod at `/etc/virtrigaud/tls`.
- **Manager side** (`internal/runtime/remote/resolver.go`): `MinVersion=TLS1.3`, `RootCAs` from `ca.crt`, client `Certificates` from `tls.crt`+`tls.key`, `ServerName` anchored to the provider Service FQDN.
- **Provider side** (SDK): `MinVersion=TLS1.3`, `RequireAndVerifyClientCert`, CA bundle in `ClientCAs`, SAN allow-list via `validateTLSPeer`.
- **Status condition** `TLSConfigured` (reasons `Enabled` / `ExplicitlyDisabled` / `SecretRefMissing` / `TLSBlockMissing`) makes posture auditable via `kubectl get providers`.
- **Cert rotation** hot-reloads the **leaf** cert/key without a pod restart; rotating the **CA bundle** still requires a provider restart.

!!! warning "Breaking change introduced in v0.3.7 (historical)"
    Existing Provider CRs **without** a `spec.runtime.service.tls` block fail to reconcile (`TLSConfigured=False, Reason=TLSBlockMissing`, **no Deployment created**) until the operator either provisions a Secret with `tls.enabled=true` + `secretRef`, or explicitly sets `tls.enabled=false` for audit-flagged plaintext. There is **no global `--insecure-no-tls-providers` flag** — per-Provider `tls.enabled=false` (or `providerTLS.insecure` for chart-templated providers) is the only escape hatch.

### Provider-side gRPC server authentication

The provider SDK (`sdk/provider/middleware`) defines:

- `AuthConfig.RequireTLS` + `AuthConfig.AllowedSANs` — refuse RPCs without a verified client cert (mTLS), and gate accepted identities by SAN/CN allow-list.
- `AuthConfig.BearerTokenAuth` + `AuthConfig.ValidateToken` — accept a Bearer-token Authorization metadata header and validate it with an operator-supplied function.

!!! note "mTLS auth is enabled in the in-tree providers"
    All in-tree provider binaries enable `Auth.RequireTLS` when TLS material is present. `validateTLSPeer` rejects an unverified caller with gRPC `Unauthenticated` and a non-matching SAN with `PermissionDenied`. An **empty** allow-list is permissive (any cert signed by the configured CA is accepted — single-CA trust model); populate `VIRTRIGAUD_PROVIDER_ALLOWED_SANS` for SAN-level authorization. For a Provider the controller manages, set it through `spec.runtime.env`; the controller does not set it for you. See the [mTLS page](../providers/security/mtls.md#the-san-allow-list).

    Bearer-token auth on the gRPC channel remains available in the SDK but unused by the in-tree manager. See [Bearer Token Authentication](../providers/security/bearer-token.md).

### Libvirt SSH host-key verification

!!! success "Host-key verification is on by default (since v0.3.7)"
    When a libvirt Provider uses a `qemu+ssh://` endpoint, the provider **verifies the SSH host key** of the hypervisor it dials (ADR-0004, shipped in v0.3.7). There is **no TOFU (trust-on-first-use)**: if verification is on but no usable `known_hosts` is present, the connection **hard-fails** with an actionable error rather than silently accepting any key.

**Trust material.** The host key lives in a `known_hosts` entry inside the libvirt credentials Secret (the one referenced by `credentialSecretRef`), mounted at `/etc/virtrigaud/credentials/known_hosts`. Seed it with:

```bash
ssh-keyscan -H <libvirt-host> >> known_hosts
```

then add the resulting `known_hosts` key to the credentials Secret. The same applies to the Proxmox **data plane** (SSH to the PVE node for migration and `qemu-img`), which reads `known_hosts` from the same mount. For a clustered Provider, each `Host` carries its own `known_hosts`. The full operational runbook lives on the libvirt provider and [host-preparation](libvirt-host-prepare.md) pages.

**Escape hatch (lab / migration only).** Set `LIBVIRT_INSECURE_SKIP_HOST_KEY_VERIFICATION=true` (libvirt) or `PROXMOX_INSECURE_SKIP_HOST_KEY_VERIFICATION=true` (Proxmox data plane) via `spec.runtime.env` to fall back to non-verifying behaviour. This is **audit-flagged**: a WARN is logged on every connection. Do not use it in regulated environments.

**Defence-in-depth (still recommended):** keep the libvirt provider pod and the libvirt host on the same private subnet behind a CNI that enforces traffic on that path, with a NetworkPolicy scoping egress. Host-key verification is the primary control; network isolation is the backstop.

## Who can grant what

Tenant isolation in v0.4.0 is a set of **grants** that two kinds of identities control. The manager itself has cluster-wide rights, so the rule is "refuse unless a grant exists", and the grants are only as strong as the RBAC around them:

| Grant | Set by | Who can change it |
|---|---|---|
| `spec.consumerNamespaceSelector` on a `Provider`, `VMClass` or `VMImage` | The object's owner | Whoever has `update`/`patch` on that object. |
| The labels the selector matches | Namespace labels | Whoever can label a `Namespace` — a cluster administrator on a plain cluster. |
| `infra.virtrigaud.io/allowed-source-namespaces` on a target `Namespace` | The target namespace's owner | Whoever can annotate that `Namespace`. |
| `admissionPolicy.reservedKeys.exemptUsernames` / `exemptGroups` | Chart values | The identity that runs `helm upgrade`. |
| `infra.virtrigaud.io/allow-consumer-orphan-on-delete`, `infra.virtrigaud.io/max-disk-size`, `infra.virtrigaud.io/tmp-size-limit`, `virtrigaud.io/adopt-vms`, `virtrigaud.io/adopt-stamped-vms` | Annotations on a `Provider` | Whoever can edit the `Provider`. |

Practical rules:

- Treat `create`/`update`/`patch` on **`Provider`** as a privileged right. A Provider chooses the runtime image, environment and (optionally) the container security context of a pod that holds hypervisor credentials, and decides which namespaces may use it.
- Give tenants namespaced rights on `VirtualMachine`, `VMSnapshot`, `VMClone`, `VMMigration` and (if they own them) `VMClass` / `VMImage` **in their own namespace** only, and keep `update`/`patch` on `namespaces` limited to platform administrators.
- **Self-service platforms** (Capsule, HNC, Rancher projects) can let a namespace owner edit their own `Namespace` labels and annotations — and so give themselves, or open to others, a grant. Prefer selectors on `kubernetes.io/metadata.name` (set by the API server, immutable) or restrict the labels and annotations with a Kyverno or Gatekeeper rule.
- **Grants match names and labels, not identities.** A namespace deleted and re-created under the same name inherits its grants; review `allowed-source-namespaces` values before reusing a namespace name.

## Cross-namespace use of a Provider

A `VirtualMachine` names its `Provider`, `VMClass` and `VMImage` with `spec.providerRef`, `classRef` and `imageRef`, each with an optional `namespace`.

- **Own namespace: no change.** No selector is needed.
- **Another namespace: refused unless the object shares itself.** `Provider`, `VMClass` and `VMImage` have an optional `spec.consumerNamespaceSelector` (a standard label selector): unset means its own namespace only, `{}` means every namespace, otherwise its own namespace plus every namespace whose labels match. A refused VM shows `Ready=False` with reason `ConsumerNotAllowed`, and no provider call is made.
- **Each object grants for itself.** Sharing a `Provider` does not share its `VMClass`es or `VMImage`s.
- **Negative selectors (`NotIn`, `DoesNotExist`) also match namespaces created later.** Prefer positive selectors.
- **A clone or migration target in another namespace** needs the target `Namespace` to carry `infra.virtrigaud.io/allowed-source-namespaces: "team-a, team-c"` (a comma-separated list of exact namespace names; no wildcards). A refusal shows `TargetNamespaceNotAllowed`; the manager does nothing in the target namespace.
- **`spec.providerRef` is immutable once the VM is bound** (`status.boundProvider`), so a VM cannot be re-pointed at another Provider. To detach a VM from VirtRigaud without deleting it from the hypervisor, annotate it `virtrigaud.io/orphan-on-delete: "true"` and delete the `VirtualMachine`. For VMs of a **clustered** Provider in another namespace, `orphan-on-delete` and `force-delete` are honoured only if the Provider carries `infra.virtrigaud.io/allow-consumer-orphan-on-delete: "true"`, because an orphaned VM would keep running on shared hosts outside the capacity accounting.
- The manager's readiness probe fails until the installed `Provider`, `VMClass` and `VMImage` CRDs have `spec.consumerNamespaceSelector` (see [`virtrigaud_manager_vm_crd_security_features`](observability.md#12-virtrigaud_manager_vm_crd_security_features)). **Apply the new CRDs and set the selectors on shared objects before rolling the manager**, or VMs that use them fail closed.

Details: [`cross-namespace-references.md`](https://github.com/projectbeskar/virtrigaud/blob/main/docs/cross-namespace-references.md), [`cross-namespace-targets.md`](https://github.com/projectbeskar/virtrigaud/blob/main/docs/cross-namespace-targets.md), [`vm-provider-binding.md`](https://github.com/projectbeskar/virtrigaud/blob/main/docs/vm-provider-binding.md).

## VM ownership and owner stamps

A vSphere VM created by VirtRigaud is named after the `VirtualMachine`, without its namespace, so two namespaces sharing a Provider can ask for the same hypervisor name. The rule since v0.4.0:

**`Create` never binds a `VirtualMachine` to an existing VM unless it can prove that this `VirtualMachine` created it.**

- Every `Create` carries the owner's UID, namespace and name. The provider records them on the VM it creates (libvirt: the domain's `<metadata>`; vSphere: the VM's ExtraConfig; Proxmox: a stamp in the VM's description) and binds to an existing VM only when the stamp records the requester's UID. Anything else is a non-retryable `ProviderConflict` that names only the requested VM.
- Adoption (`virtrigaud.io/adopt-vms` on a Provider) **stamps the adopted VM** before binding it, and skips templates, image artifacts and VMs whose stamp is unreadable or names a live `VirtualMachine` elsewhere. A VM whose stamp names a `VirtualMachine` that no longer exists in this cluster is not adopted unless the single-host Provider carries `virtrigaud.io/adopt-stamped-vms: "true"`.
- Per-VM operations (`Describe`, `Power`, `Reconfigure`, snapshots, `Delete`) are owner-checked; a template or image artifact is refused (`VM_IS_IMAGE_ARTIFACT`); a VM that is not the requester's is reported as not owned (`VMNotOwned`) rather than gone.
- New libvirt domains are named `<namespace>.<name>`, and vSphere/Proxmox landing names carry the namespace, closing same-host name squatting.
- **Owner stamps are scoped to one cluster.** Two VirtRigaud installations managing the same vCenter or host do not see each other's `VirtualMachine`s; do not point two installations at one hypervisor without reading [Owner stamps are scoped to one cluster](https://github.com/projectbeskar/virtrigaud/blob/main/docs/vm-ownership.md#owner-stamps-are-scoped-to-one-cluster).
- **vSphere requires the vCenter privilege `VirtualMachine.Config.AdvancedConfig`** for every `Create`, `Clone` and adoption (the stamp is an ExtraConfig write), and `System.Read` on the root folder (propagated) for the imported-disk checks. Proxmox applying a VM's bridge and VLAN needs `SDN.Use` ACLs on the bridges: those ACLs decide which networks the authors of `VirtualMachine`s in a namespace can reach. See the [bearer-token page](../providers/security/bearer-token.md#proxmox-api-tokens).

Details: [`vm-ownership.md`](https://github.com/projectbeskar/virtrigaud/blob/main/docs/vm-ownership.md), [`libvirt-domain-ownership.md`](https://github.com/projectbeskar/virtrigaud/blob/main/docs/libvirt-domain-ownership.md).

## Reserved-keys admission policy

The manager writes some annotations and labels on `VirtualMachine`s: where a migrated VM came from, which `VMClone` produced a VM, that a VM was adopted. Some controllers decide which `VirtualMachine` a hypervisor VM is bound to from these keys, so a tenant who could forge them could hijack an adoption or clone. The chart therefore installs a **`ValidatingAdmissionPolicy`** (`<release>-reserved-keys`) and its binding, evaluated inside the API server (not a webhook, so it works with `webhooks.enabled: false` and while the manager is down), that lets only the manager's ServiceAccount add or change the `virtrigaud.io/migration`, `migration-claim`, `migrated-from`, `imported-disk-id`, `disk-checksum`, `migration-completed`, `migration-completed-at`, `clone`, `clone-uid`, `cloned-from`, `adopted-host`, `adopted-id` annotations and the `virtrigaud.io/adopted` label. Keys users set themselves (`orphan-on-delete`, `force-delete`, `create-outcome`) are not affected, and an update that leaves the reserved keys unchanged is allowed.

```yaml
admissionPolicy:
  reservedKeys:
    enabled: true        # default; do not disable unless Kyverno/Gatekeeper reserves the same keys
    exemptUsernames: []  # e.g. ["system:serviceaccount:velero:velero"] for a restore tool
    exemptGroups: []     # e.g. ["platform-break-glass"]; system:masters is NOT exempt by default
```

- **Requires Kubernetes 1.30 or later**; on an older cluster the chart renders nothing and the adoption/clone markers stay forgeable by anyone who can create `VirtualMachine`s. Restrict `create`/`update` on `virtualmachines` there.
- The identity that runs `helm install`/`upgrade` needs rights to create `validatingadmissionpolicies` and `validatingadmissionpolicybindings`.
- A restore tool that re-creates `VirtualMachine`s with their annotations (Velero) is rejected until added to `exemptUsernames`. A second VirtRigaud installation in the same cluster must have its manager ServiceAccount listed too.
- A `VMMigration` does not rely on the policy: it binds its target by the UID its own `Create` returned. It also drops every `virtrigaud.io` key from `spec.target.annotations` and the reserved label from `spec.target.labels` (event `TargetLabelsDropped`).

Details: [`admission-policy.md`](https://github.com/projectbeskar/virtrigaud/blob/main/docs/admission-policy.md).

## Provider in-use finalizer

A `Provider` now carries the finalizer `provider.infra.virtrigaud.io/in-use` (ADR-0010). Deleting a `Provider` that is still needed no longer orphans the VMs created through it:

- While any `VirtualMachine` (in **any** namespace) that is bound to it or may have something on the hypervisor, or a `VMSnapshot`, in-flight `VMClone` or `VMMigration` that needs it, still exists, the `Provider` and its runtime (Deployment, Service, ServiceAccount) are kept, so those objects can still be deleted through it. The `Provider` shows `DeleteBlocked=True`, reason `ProviderInUse`, with the number of objects and the namespaces (at most 10; never an object name) and one `Warning` event `ProviderDeleteBlocked`.
- It is released when nothing holds it any more, or when an administrator annotates the `Provider` `virtrigaud.io/force-delete: "true"` (event `ProviderForceDeleted`). That is a deliberate, audited choice to leave hypervisor VMs running unmanaged.
- A cluster administrator deleting a **namespace** that holds both a `Provider` and its VMs is a Kubernetes limit the finalizer cannot fully close: the namespace controller also deletes the provider's pods. See the ADR for the details and the mitigations.

Details: [ADR-0010](https://github.com/projectbeskar/virtrigaud/blob/main/docs/adr/0010-provider-in-use-finalizer.md).

## Hypervisor-side isolation

These v0.4.0 controls apply inside the providers and are on by default unless noted. Each links to the main-repository document with the exact behaviour and the upgrade notes.

- **Identity-safe image preparation (ADR-0009).** A prepared image (a vSphere template, a libvirt pool file, a Proxmox template) used to be named after the `VMImage` alone, and any existing artifact of that name was reused, so a tenant could pre-create the artifact another tenant's VMs are cloned from. The manager now sends the `VMImage`'s UID and a digest of its `spec.source`; the provider derives a unique artifact name, stamps the artifact, and reuses an existing one only when its stamp carries the same UID and digest. An artifact at the derived name with a different stamp is a **conflict**: VirtRigaud never adopts, overwrites or deletes it (`ArtifactConflict`, event `ImageArtifactConflict`, metric [`virtrigaud_image_prepare_artifact_total`](observability.md#13-virtrigaud_image_prepare_artifact_total)). An import-capable provider that does not report `supportsImageArtifactIdentity` is held, so roll the providers with the manager. Prepare state is recorded **per Provider identity** in `VMImage.status.providerStatus`. [`image-preparation.md`](https://github.com/projectbeskar/virtrigaud/blob/main/docs/image-preparation.md#prepared-image-artifact-identity).
- **libvirt image paths are confined.** Base images must lie in allowed directories (default `/var/lib/libvirt/images`; `VIRTRIGAUD_LIBVIRT_IMAGE_DIRS`) and are always copied, never attached in place. With a shared pool, set the variable to a catalog directory **apart from the pool**: any unused file in the pool directory is otherwise copyable by any tenant of the Provider.
- **Private cloud-init seeds (libvirt).** A VM's cloud-init seed carries its user-data (passwords, keys, tokens). It is built `0600` in a dedicated directory (`VIRTRIGAUD_LIBVIRT_SEED_DIR`, default `/var/lib/libvirt/virtrigaud-seeds`) that the provider checks and refuses to use if it is not private; it must exist on every host, including migration target hosts. The directory holds every VM's user-data in plaintext: exclude it from host backups or encrypt them. A clone gets its own seed, a new cloud-init instance-id and its own SSH host keys, and `create` on `VMClone` is read access to the source's data. libvirt VMs created without `spec.userData` no longer get a default login. See [libvirt host preparation](libvirt-host-prepare.md) and [`libvirt-clones.md`](https://github.com/projectbeskar/virtrigaud/blob/main/docs/libvirt-clones.md).
- **Disk handling.** libvirt disks are written in a private directory and renamed into place, are created `0640 libvirt-qemu:kvm`, and a symbolic link at a disk's name is refused. A VM delete removes only the VM's own files inside the storage pool; a source VM whose disk a linked clone still uses cannot be deleted, reverted or snapshotted (`DeleteBlocked`). libvirt linked clones are disabled. vSphere attaches an imported disk in place only when it is the VM's own verified landing disk, and migrations land per namespace; Proxmox imports a migrated disk only from the VM's own verified stage.
- **Migration PVC mounts.** A provider pod mounts only the migration PVCs that a live `VMMigration` references (the target's read-only), and staged migration files on the `pvc` backend are opened without following symbolic links. Migration storage endpoints are user-supplied; the manager's SSRF gate always refuses loopback, link-local, metadata and multicast targets, and `--migration-storage-allowed-hosts` (a comma-separated IP/CIDR allow-list, ADR-0006) locks it to your storage networks. The chart has no value for that flag; use `networkPolicy.hypervisorEgressCIDRs` as a second layer.
- **Administrator disk-size limit (opt-in).** By default a tenant can ask for disks up to the CRD bound of 64 Ti each and fill a shared datastore. Set `manager.maxDiskSize` (the manager's `--max-disk-size`, binary units such as `500Gi`) to cap every disk VirtRigaud creates or grows: VMs that would create a larger disk are held (`DiskSizeExceedsLimit`), a Reconfigure never grows a disk beyond it, and clones and migrations are checked by the real sizes of the source's disks (an unknown size refuses them). Existing larger disks are kept and never shrunk. A Provider's owner can **lower** it with the annotation `infra.virtrigaud.io/max-disk-size` (never raise it); with webhooks enabled, `VirtualMachine` and `VMClass` writes above the limit are also refused at admission. An image or template larger than the class size is not covered.
- **`/tmp` size limits.** Every pod's writable `/tmp` emptyDir has a `sizeLimit` (manager `128Mi`; vSphere providers `512Gi`; libvirt, Proxmox and others `1Gi`) and a pod that writes past it is evicted. It bounds the pod but does not reserve node storage. Change one Provider's limit with `infra.virtrigaud.io/tmp-size-limit` or all of them with `manager.providerTmpSizeLimit`; cap what the annotation may ask for with `manager.providerTmpSizeLimitMax` (a larger request is clamped with a `TmpSizeLimitClamped` event).
- **vSphere** `ListVMs` leaves out templates and image artifacts; `Delete`, `Power`, `Reconfigure` and snapshot calls refuse them.

## RBAC

### Manager RBAC

The chart's `manager-rbac.yaml` grants the manager's ServiceAccount a `ClusterRole` (`rbac.scope: cluster`, the default) or, with `rbac.scope: namespace`, a namespaced `Role` with the same rules. **There are no wildcard verbs or resources and no `cluster-admin`.** The rules, by purpose:

| Resources | Verbs | Why |
|---|---|---|
| `infra.virtrigaud.io`: `virtualmachines`, `providers`, `vmsnapshots`, `vmmigrations` (+ `/status`, `/finalizers`) | `create, delete, get, list, patch, update, watch` | The objects the controllers drive. |
| `vmclones` (+ `/status`, `/finalizers`) | `get, list, patch, update, watch` | Never created or deleted by the manager. |
| `vmclasses` (+ `/status`) | `create, get, list, patch, update, watch` | Created by adoption; never deleted. |
| `vmimages`, `vmnetworkattachments`, `vmplacementpolicies`, `hostpools` | `get, list, watch` | Read-only inputs. `vmimages/status`, `hostpools/status`, `hosts/status`, `vmsets/status`: `get, patch, update`. |
| `hosts` | `get, list, update, watch` (+ `hosts/finalizers` `update`) | `update` is for exactly one purpose: the Host in-use finalizer. The manager never changes a `Host` spec. |
| `secrets` | `create, get, list, update, watch` | Reads provider credential, TLS and cloud-init Secrets; **creates and updates** only the single host-inventory Secret it owns per clustered Provider (`<provider>-hosts`). It never deletes Secrets (garbage collection reclaims that one). RBAC cannot scope `create` to one name, so this is wider than read-only; provider pods have **no** Secret access. |
| `services`, `serviceaccounts`, `apps/deployments` | `create, delete, get, list, patch, update, watch` | The per-Provider runtime. |
| `persistentvolumeclaims` | `create, delete, get, list, patch, update, watch` | Migration storage. |
| `pods` | `get, list, watch` | Provider-readiness checks for migrations. |
| `events` | `create, patch` | Emits events only. |
| `storage.k8s.io/storageclasses` | `get` | A migration PVC is mounted only if its StorageClass can bind. |
| `namespaces` | `get, list, watch` | Reads the `allowed-source-namespaces` grant and matches `consumerNamespaceSelector` against Namespace labels. Never written. `Namespace` is cluster-scoped, so use `rbac.scope: cluster` if you rely on cross-namespace grants. |
| `apiextensions.k8s.io/customresourcedefinitions` (five named CRDs only) | `get` | The startup/readiness check that the installed CRDs have the security fields. Cluster scope only. |
| `coordination.k8s.io/leases` | `create, get, list, update` | Leader election. |

The v0.3.7 tightening still holds: unused grants were removed, and the manager cannot delete Secrets. If a custom deployment needs more, add rules through the chart's `rbac.additionalRules` value rather than widening the built-in role. Changes need a `helm upgrade` to take effect.

!!! note "Corrections to earlier versions of this page"
    The manager does not hold `configmaps` or `metrics.k8s.io` access, and its `secrets` access is not read-only: it can `create` and `update` (the host-inventory Secret above), never `delete`.

### Provider pod RBAC

Each Provider runs under its **own, token-less ServiceAccount**: the controller creates a dedicated ServiceAccount per Provider with **no RoleBinding or ClusterRoleBinding**, and the pod sets `automountServiceAccountToken: false`, so no Kubernetes API token is projected into it at all. Provider pods are gRPC servers that never call the Kubernetes API; credentials and TLS material arrive as kubelet-mounted Secret volumes. A compromised provider pod therefore cannot list other Secrets or reach the API. The chart's optional static provider Deployments (`providers.*.enabled`) use their own token-less ServiceAccounts the same way. If you add custom RBAC for a provider, scope it to what that provider actually needs (typically: none).

### CRD upgrade hook

With `crdUpgrade.enabled` (the default) the chart runs a `pre-install,pre-upgrade` Job, under a `ServiceAccount` and `ClusterRole` that exist only for the hook's duration, which can `get, list, create, update, patch` `customresourcedefinitions` cluster-wide to apply the new CRDs. Disable it (`crdUpgrade.enabled: false`) and apply the CRDs yourself if you do not want a chart hook with that right; see the chart README.

### Values that look like security settings but are not wired

The chart's `security.podSecurityProfile`, `security.tls.*` and `config.*` (circuit breaker, retry, rate limit, workers) blocks are not consumed by any template or by the manager in v0.4.0. Setting them changes nothing. Use `manager.securityContext` / `manager.podSecurityContext`, the Provider's `spec.runtime.service.tls` and `providerTLS`, and the settings documented on this page instead.

## Container hardening

| Component             | Base image                              | USER        | Read-only root FS |
|----------------------|------------------------------------------|-------------|-------------------|
| Manager              | `gcr.io/distroless/static:nonroot`       | `65532:65532` | Yes (Pod `securityContext`) |
| provider-mock        | `gcr.io/distroless/static:nonroot`       | `65532:65532` | Yes |
| provider-vsphere     | `debian:bookworm-slim` (+ `qemu-utils`, for disk conversion) | `app` (`65532`) | Yes |
| provider-libvirt     | `debian:bookworm-slim` (+ `libvirt-clients` for `virsh`, `libxml2`) | `app` (`65532`) | Yes |
| provider-proxmox     | `debian:bookworm-slim` (+ `openssh-client`, `sshpass`) | `app` (`65532`) | Yes |

Only the manager and the mock provider are distroless; the three hypervisor providers need tools (`virsh`, `qemu-img`, `ssh`). They are still non-root and read-only-rootfs. References: `build/Dockerfile.manager`, `cmd/provider-*/Dockerfile`.

The default **manager** security context (chart `manager.securityContext` / `podSecurityContext`) is `runAsNonRoot`, UID/GID `65532`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]` and `seccompProfile: RuntimeDefault`. The **provider** container the controller creates uses:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 65532
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
```

A Provider's `spec.runtime.securityContext` **replaces** this default entirely (another reason `Provider` write access is privileged). The controller does not set a pod-level `seccompProfile` on provider pods; if your cluster enforces the Pod Security `restricted` profile, set one through the namespace's policy or `spec.runtime.securityContext`.

### NetworkPolicy

The chart can render namespaced `NetworkPolicy` objects for the manager and the provider pods: `networkPolicy.enabled: true` (**default off**, so an upgrade never switches isolation on by accident). They need a CNI that enforces NetworkPolicy and deployment-specific tuning (monitoring namespace label, DNS selectors, API-server and hypervisor CIDRs). See [Network Policies](../providers/security/network-policies.md) for what the templates allow and how to tune them.

## Metrics endpoint security

By default the manager's `/metrics` endpoint is **HTTP on `:8080`, unauthenticated** (the controller-runtime default). Provider pods also serve `/metrics` on their health port (`:8080`), unauthenticated, with an ingress rule that must stay open to the kubelet's probes (see [Network Policies](../providers/security/network-policies.md)); it carries telemetry only (no secrets), but it is reachable cluster-wide unless your CNI restricts it.

### Opting into RBAC-authenticated manager `/metrics`

Pass `--metrics-secure=true` to the manager. When this flag is set:

- `/metrics` is served over HTTPS (minimum TLS 1.2).
- `metrics/filters.WithAuthenticationAndAuthorization` is installed as the metrics FilterProvider.
- Every scrape must present a Kubernetes-issued bearer token (typically a ServiceAccount token from the Prometheus pod). The token's TokenReview must succeed AND a SubjectAccessReview must show the token holder has `get` on `nonResourceURLs: ["/metrics"]`.

The **chart has no value for this flag** and its `ServiceMonitor` scrapes plain HTTP, so you have to patch the Deployment `args` and supply your own `ServiceMonitor` with `bearerTokenFile` and `tlsConfig`. Grant Prometheus's ServiceAccount the right to scrape:

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

!!! note "The default is still plain HTTP in v0.4.0"
    `--metrics-secure=false` remains the default. Operators in regulated environments should secure the manager endpoint with this flag **and** restrict who can reach port 8080 with a NetworkPolicy.

The webhook and metrics servers pin an explicit **TLS 1.2 minimum** (the floor is active on the always-TLS webhook server, and on the metrics server when it is served over HTTPS). HTTP/2 is disabled unless `--enable-http2` is set.

See the [Observability Guide](observability.md) for the metric catalogue.

## CircuitBreaker as a denial-of-service control

The per-Provider CircuitBreaker is also a security control: it caps how loudly a wedged, flapping, or compromised provider can fail. When the breaker is open, the manager fast-fails RPCs to that provider with `codes.Unavailable` for a cool-down period instead of hammering it. Host-scoped and per-tenant failures of a clustered provider are deliberately kept out of the breaker so that one tenant's failing request cannot fast-fail every other tenant. See [Resilience](resilience.md) for the lifecycle, metrics and what counts.

## Enforcing provider capabilities

The manager flag `--enforce-provider-capabilities` (**default OFF**) fail-closes snapshot and migration operations against any provider that does not advertise the corresponding capability, returning a clear error instead of attempting an RPC the provider cannot honour.

- **Default OFF** — existing deployments behave as before unless an operator opts in.
- **How to enable** — pass `--enforce-provider-capabilities` to the manager. The chart has no value for it, so patch the Deployment `args`. Confirm each Provider advertises the capabilities you rely on first, since enabling it rejects operations on providers that under-report.

This is an operational hardening toggle, not a transport or credential control; it complements mTLS and RBAC.

## Supply chain

### CVE management

- **Container images are scanned with Trivy** on every release (`.github/workflows/release.yml`). The release workflow **fails** if Trivy finds a HIGH or CRITICAL vulnerability in the manager or a provider image (the kubectl helper image is scanned but does not gate).
- **Code is scanned with Trivy in repo mode and with `govulncheck`** on every CI run (`.github/workflows/ci.yml`). `govulncheck` is a **blocking** gate for the root and SDK modules. Trivy results are uploaded to the GitHub Security tab as SARIF.
- **Release artifacts are signed and attested with cosign.** Every published multi-arch image — and its per-arch children, via `cosign sign --recursive` — carries a keyless **signature** (Fulcio + Rekor), an **SBOM** attestation (`spdxjson`), and **SLSA L3 provenance** (`slsa-github-generator`, `generator_container_slsa3.yml@v2.1.0`).

#### Verifying release artifacts

The signature, SBOM and SLSA provenance are all stored in the legacy `.sig`/`.att` tag format (the release pins cosign to `v2.6.3`), so a **single cosign version (any ≥ 2.2)** verifies all three with default flags. Prefer an immutable `@sha256:…` digest over a tag:

```bash
IMAGE=ghcr.io/projectbeskar/virtrigaud/manager:v0.4.0
ISSUER=https://token.actions.githubusercontent.com
# Accepts both the release workflow (signature/SBOM) and the SLSA generator
# (provenance) identities; tighten per-artifact if you need a stricter policy.
ID_RE='https://github.com/(projectbeskar/virtrigaud|slsa-framework/slsa-github-generator)/.*'

# 1. Signature
cosign verify "$IMAGE" \
  --certificate-identity-regexp="$ID_RE" \
  --certificate-oidc-issuer="$ISSUER"

# 2. SBOM (SPDX)
cosign verify-attestation "$IMAGE" --type spdxjson \
  --certificate-identity-regexp="$ID_RE" \
  --certificate-oidc-issuer="$ISSUER"

# 3. SLSA provenance
cosign verify-attestation "$IMAGE" --type slsaprovenance \
  --certificate-identity-regexp="$ID_RE" \
  --certificate-oidc-issuer="$ISSUER"
```

!!! note "v0.3.6–v0.3.8: split storage format"
    Releases v0.3.6 through v0.3.8 were signed with cosign v3.0.x, which stored the signature and SBOM in the new Sigstore-bundle (OCI 1.1 referrer) format while SLSA provenance stayed on the legacy `.att` tag: use cosign ≥ 2.6 for the signature and SBOM, and cosign 2.2.x for the provenance of those releases. Every artifact is valid; this was a discovery-format split, resolved from v0.3.9.

### GitHub Actions pinning

All third-party Actions are pinned to **40-character commit SHAs**, not floating tags. Dependabot maintains the SHA-pin policy via `.github/dependabot.yml`.

### Go module integrity

- `go.sum` is verified on every CI run via `go mod download` against the module proxy.
- `make verify-tidy` fails on a dirty `go mod tidy` diff.
- `govulncheck` runs as a blocking CI gate, failing the build on a known vulnerability in a reachable code path.

## CRD input validation

Every string field that flows to a hypervisor API call has Kubebuilder validation. Spot-check examples:

- `Provider.spec.endpoint`: regex-validated to accept only well-formed `http(s)://`, `tcp://`, `grpc://`, or `qemu(+ssh|+tcp|+tls)://` URIs.
- `Provider.spec.type`: enum-validated (`vsphere | libvirt | firecracker | qemu | proxmox`) and **immutable** once set, because the controllers decide type-specific safety rules from it.
- `VirtualMachine.spec.providerRef` is immutable once the VM is bound.
- `ProviderRuntimeSpec.image`: regex-validated to enforce `image[:tag][@digest]` format only.
- `ProviderDefaults.{datastore,cluster,folder,resourcePool,network}`: `MaxLength=255`.
- Numeric ports, replicas, QPS, burst — all range-bounded; a disk is at most 64 Ti.

Provider-side name checks reject names that tooling would resolve as something other than a name (vSphere `vm-<digits>` names are refused), and `VirtualMachine.spec.userData.cloudInit` is treated as **opaque bytes** by the manager and never interpreted as shell: it is forwarded to the provider in `CreateRequest.UserData`. Every libvirt command sent over SSH is shell-quoted, and libvirt domain XML escapes every user-derived value.

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
| 0.4.x   | yes       |
| 0.3.x   | security fixes only on request; upgrade to 0.4.x |
| < 0.3   | no        |

## v0.3.6 security gap inventory

This section tracks the security gaps that were open in v0.3.6 and records what shipped to close them. The heading and anchor (`#v036-security-gap-inventory`) are retained so links from older pages still resolve.

!!! success "Resolved in v0.3.7 (still closed)"
    | Former gap | Status |
    |------------|------------------|
    | **mTLS not wired through Resolver** — the CRD field had no runtime effect. | **Resolved.** `Provider.spec.runtime.service.tls` drives mTLS by default (TLS 1.3 floor). See [gRPC transport](#grpc-transport-between-manager-and-providers). |
    | **In-tree providers did not enable mTLS/Bearer auth** in their middleware. | **Resolved.** In-tree providers enforce `Auth.RequireTLS` + the SAN allow-list. Unauthenticated callers are rejected (`Unauthenticated`); off-list certs get `PermissionDenied`. |
    | **libvirt SSH `no_verify=1`** disabled host-key verification. | **Resolved.** Host-key verification is **on by default** (no TOFU). See [Libvirt SSH host-key verification](#libvirt-ssh-host-key-verification). |
    | **Manager RBAC included `secrets` `delete`** and other wider-than-required grants. | **Resolved.** Unused grants were removed; the manager cannot delete Secrets. See [RBAC](#rbac). |
    | **`govulncheck` was not a CI gate.** | **Resolved** in v0.3.7: it is a blocking gate. |

The following remain open and operators in regulated environments must factor them into their compensating-control posture:

| Gap | Severity (banking) | Mitigation today |
|-----|---------------------|-------------------|
| **Manager `--metrics-secure=false`** is still the default, and provider pods serve unauthenticated `/metrics`. | MEDIUM | Pass `--metrics-secure=true` (Deployment `args`) and wire RBAC for Prometheus; enable the NetworkPolicy templates and restrict who can reach `:8080`. |
| **The hypervisor-provider images are `debian:bookworm-slim`**, not distroless, because they shell out to `virsh` / `qemu-img` / `ssh`. | LOW | Images are non-root, read-only rootFS, all capabilities dropped. |
| **Reserved-keys admission policy needs Kubernetes 1.30+.** | MEDIUM on older clusters | Restrict `create`/`update` on `virtualmachines`, or reserve the keys with Kyverno/Gatekeeper. |
| **Chart cannot pass extra manager flags** (`--metrics-secure`, `--enforce-provider-capabilities`, `--migration-storage-allowed-hosts`). | LOW | Patch the rendered Deployment `args`. |
