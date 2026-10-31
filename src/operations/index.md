<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Operations Guide

Operator-facing reference for running VirtRigaud **v0.4.2** in production. The
pages linked from here are the authoritative source for each topic; this index
is a router, not a duplicate.

!!! warning "Upgrading? Read the Upgrade Guide first"
    From v0.4.0, [Upgrading from v0.4.0 to v0.4.1](upgrade.md#upgrading-from-v040-to-v041) lists three actions: SSH credentials for Proxmox Providers whose VMs carry user-data, a check of libvirt VMClasses with `firmware: UEFI`, and rotating secrets set in a `VMClone`'s `spec.customization`.

    From v0.4.1 or a v0.4.2 release candidate: [Upgrading from v0.4.1 to v0.4.2](upgrade.md#upgrading-from-v041-to-v042) needs the CRDs before the manager (one new optional status field), `helm upgrade --reset-then-reuse-values` with any pinned image tag overridden, and each `Provider`'s `spec.runtime.image` rolled by you (the vSphere providers together with the manager). It re-checks clustered admissions inherited from an earlier manager, changes the polling cadence and the circuit breaker's accounting, and restricts rollback while a clustered VM holds a resize reservation.

    From v0.3.11:
    v0.4.0 is a security-hardening release with breaking changes (cross-namespace
    references need a grant, `providerRef` is immutable once bound, a new vCenter
    privilege, a libvirt seed directory that must exist before the provider rolls).
    Follow the [Upgrade Guide](upgrade.md) in order.

!!! warning "Read the security page before you trust this section in production"
    Several network-security controls are enforced: mTLS between the manager and
    provider pods (since v0.3.7, #147) and libvirt SSH host-key verification
    (since v0.3.7, #149). Server-side bearer auth on the provider gRPC endpoint
    (#148) is still not enabled by the in-tree providers; `NetworkPolicy`
    remains the compensating control there. These are called out on the
    [Security](security.md) page and the per-control pages
    ([mTLS](../providers/security/mtls.md),
    [Bearer Token](../providers/security/bearer-token.md)). Do not assume a
    control is in place because the field exists in a CRD — verify against the
    source references those pages cite.

## Core operational topics

| Page | Scope |
|------|-------|
| [Observability](observability.md) | What VirtRigaud exposes on `/metrics`: the `virtrigaud_*` families wired in code, with their labels and when they populate. No invented metrics. |
| [Resilience](resilience.md) | The per-`Provider` CircuitBreaker (`internal/transport/grpc/client.go`), failure classification (`isInfraFailure`), default thresholds (`FailureThreshold=10`, `ResetTimeout=60s`, `HalfOpenMaxCalls=3`), and provider-side connection resilience (vSphere vCenter keepalive/reconnect, libvirt SSH retry, migration-PVC delete safety). |
| [Security](security.md) | Canonical operator-facing security reference. STRIDE pass, credential-flow diagram, the mTLS/SSH host-key controls, the remaining gRPC-auth disclosure, and the compensating controls a regulated deployment must layer on top. |
| [Upgrade Guide](upgrade.md) | **v0.4.1 → v0.4.2** (and from a v0.4.2 release candidate: the procedure, the new `resizeReservation` status field and CRD ordering, pinned Helm image tags, provider images through `spec.runtime.image`, checking the running images, re-check of inherited admissions, polling, connection and circuit-breaker changes, client rate limits, rollback restrictions, known limitations), then **v0.4.0 → v0.4.1** (actions for Proxmox user-data, libvirt UEFI and `VMClone` secrets; what changed in status, backoff and logs; known limitations; verification), then **v0.3.11 → v0.4.0**: pre-flight checks, the required order (hosts and accounts, CRDs, consumer grants, manager, providers), every breaking change with its action, new privileges, changed chart values, in-flight migrations, upgrading from a release candidate, rollback caveats. Plus notes for older releases, GitOps and troubleshooting. |

### Security sub-pages

The detailed control-by-control pages live under `providers/security/` because
they apply equally to in-tree providers and external providers built on the
SDK. They are kept **honest about what is and is not wired**:

- [Bearer Token Authentication](../providers/security/bearer-token.md) —
  Production-relevant for **hypervisor API tokens** (Proxmox today, future
  REST-based providers). gRPC-channel bearer auth via the SDK exists but is
  **still not enabled by the in-tree providers and not sent by the manager**.
- [mTLS Configuration](../providers/security/mtls.md) — **Wired and enforced
  since v0.3.7** (#147). Every Provider CR now requires a
  `spec.runtime.service.tls` block (or an explicit, audit-flagged opt-out); see
  the [Upgrade Guide](upgrade.md) for the migration steps.
- [External Secrets](../providers/security/external-secrets.md) — Wiring
  External Secrets Operator / Vault into the credentials Secret that
  VirtRigaud mounts.
- [Network Policies](../providers/security/network-policies.md) — Still a
  recommended defence-in-depth control and the compensating control for the
  unwired gRPC bearer-auth path (#148).

## Infrastructure-specific topics

| Page | When you need it |
|------|------------------|
| [vSphere Hardware Versions](vsphere-hardware-version.md) | Setting the `vmx-N` compatibility level at VM creation (VMClass `extraConfig`) and upgrading existing VMs via the `HardwareUpgrade` gRPC RPC (no controller path yet). vSphere-only. |
| [Libvirt Host Preparation](libvirt-host-prepare.md) | Preparing a Libvirt/KVM host so the libvirt provider can drive it: SSH user and host-key verification, the `default` pool and image directories, the cloud-init seed directory (required in v0.4.2), sudo rules for disk reads and copies, bridged networking and placement labels for clustered hosts, AppArmor/SELinux. |

## Production-readiness checklist

Use this before promoting a VirtRigaud deployment to production. Each item links
to the page that actually covers it.

- [ ] **CRDs installed at the v0.4.2 schema** (v0.4.2 adds only the optional `status.placement.resizeReservation` to `VirtualMachine`; apply the CRDs before the manager) — `helm pull virtrigaud/virtrigaud --version 0.4.2 --untar && kubectl apply --server-side --force-conflicts -f virtrigaud/crds/`. See [Upgrade Guide](upgrade.md).
- [ ] **Manager + provider images pinned to v0.4.2** — release artifacts are tagged in lockstep; do not mix versions across the manager/providers/CRDs trio. Provider images are set per `Provider` in `spec.runtime.image`; the chart does not change them.
- [ ] **Shared `Provider`/`VMClass`/`VMImage` have a consumer grant** — `spec.consumerNamespaceSelector` on every object another namespace uses (v0.4.0); unset means own namespace only. See the [Upgrade Guide](upgrade.md#breaking-changes).
- [ ] **Hypervisor accounts and hosts prepared** — vSphere: `VirtualMachine.Config.AdvancedConfig` and `System.Read`; Proxmox: `VM.Config.Network`, `VM.Config.Cloudinit`, `SDN.Use`, and for VMs with user-data SSH credentials, `genisoimage` and `flock` on the node ([details](../providers/proxmox.md#seed-prerequisites)); libvirt: [seed directory, sudo rules, image directories, `curl`, and an OVMF package for UEFI VMClasses](libvirt-host-prepare.md).
- [ ] **Admission policy understood** — on Kubernetes 1.30+ the chart installs a ValidatingAdmissionPolicy that reserves the manager-owned `virtrigaud.io` keys; exempt your backup/restore tooling (`admissionPolicy.reservedKeys`).
- [ ] **Metrics scrape configured** — a `ServiceMonitor` (or equivalent) against the manager's `/metrics`. Expect the families documented in [Observability](observability.md), including the v0.3.8 `kind="VMClone"`/`kind="VMSet"` reconcile series.
- [ ] **mTLS configured on every Provider CR** — enforced since v0.3.7 (#147).
      A Provider without a `spec.runtime.service.tls` block (or an explicit,
      audit-flagged opt-out) will not reconcile. See [mTLS](../providers/security/mtls.md)
      and the [Upgrade Guide](upgrade.md).
- [ ] **Per-Provider CircuitBreaker behavior understood** — read [Resilience](resilience.md). The CB will trip Open within seconds of a provider going bad. That is the metric working as designed.
- [ ] **Compensating network controls for the unwired gRPC bearer-auth path (#148)** —
      `NetworkPolicy` that restricts provider-pod ingress to the manager pod,
      complementing the now-wired mTLS. See [Bearer Token](../providers/security/bearer-token.md)
      and [Network Policies](../providers/security/network-policies.md).
- [ ] **Provider credentials reviewed** — for **Proxmox**, API tokens
      (`token_id` / `token_secret`) are strongly recommended; username/password
      is for development and CI only. See [Bearer Token Authentication](../providers/security/bearer-token.md).
- [ ] **Secrets backend chosen** — at minimum, kube-apiserver
      `EncryptionConfiguration` for etcd-at-rest encryption. For multi-cluster /
      regulated deployments, External Secrets Operator (Vault, AWS Secrets
      Manager, etc.) per [External Secrets](../providers/security/external-secrets.md).
- [ ] **Manager HA** — the chart passes `--leader-elect` to the manager (the
      flag itself defaults to false) but `manager.replicaCount` defaults to 1;
      set `manager.replicaCount: 2` for a standby manager.
- [ ] **Audit trail** — K8s audit logging enabled at the cluster level, and the
      release notes / CHANGELOG reviewed for each upgrade (regulated-deployment
      posture).
- [ ] **Backup/restore procedure** — VirtRigaud does not back up CRs;
      reuse your standard `etcd` snapshot + cluster-level Velero / equivalent.

## Day-2 cheatsheet

The commands below are the same patterns the [Observability](observability.md)
and [Security](security.md) pages cite; they live here as a quick-reference.
Provider workloads are normally deployed by the manager from `Provider` CRs, as
a Deployment named `virtrigaud-provider-<namespace>-<provider>` carrying the
labels `app.kubernetes.io/managed-by=virtrigaud` and
`app.kubernetes.io/component=provider`. The chart's templated providers are
**disabled by default** (since v0.3.8); set `providers.<type>.enabled=true` only
if you rely on them. The commands assume the chart's defaults.

### Inspect Provider CR state

```bash
# All Provider CRs and their reconcile state
kubectl get providers.infra.virtrigaud.io -A

# Detailed view of a provider (events, conditions, last-seen credentials)
kubectl describe provider.infra.virtrigaud.io <name>
```

### Inspect VirtualMachine state

```bash
kubectl get virtualmachines.infra.virtrigaud.io -A

# Watch a single VM through reconciliation
kubectl get virtualmachines.infra.virtrigaud.io my-vm -w

# Events for a VM
kubectl get events --field-selector involvedObject.kind=VirtualMachine,involvedObject.name=my-vm
```

### Manager / provider logs

```bash
# Manager logs
kubectl logs -n virtrigaud-system deploy/virtrigaud-manager

# Provider pod logs (CR-managed providers; add -n <namespace> of the Provider)
kubectl logs -n virtrigaud-system -l app.kubernetes.io/component=provider --tail=200
```

### Rotating provider credentials

The credentials Secret is mounted **read-only as files** under
`/etc/virtrigaud/credentials/` inside each provider pod
(`internal/controller/provider_controller.go`). After updating the Secret,
restart the provider Deployment so it re-reads the files:

```bash
kubectl -n virtrigaud-system patch secret <provider-creds> \
  -p '{"stringData":{"password":"<NEW>"}}'

# Restart so the file mount picks up the new value
kubectl -n virtrigaud-system rollout restart deploy/virtrigaud-provider-<namespace>-<provider>
```

### Reading CircuitBreaker state

The G6 wiring (since v0.3.6) exposes one breaker per Provider CR. The fast
operator signal is:

```bash
kubectl -n virtrigaud-system port-forward deploy/virtrigaud-manager 8080:8080 &
curl -s localhost:8080/metrics | \
  grep -E 'virtrigaud_circuit_breaker_(state|failures_total)'
```

`state == 0` is Closed, `state == 1` is Half-Open and `state == 2` is Open
(`# HELP`: "0=closed, 1=half-open, 2=open"). See
[Resilience](resilience.md#circuit-breaker).

## What this section does NOT cover

- **In-cluster networking design** — VirtRigaud does not ship a CNI choice or
  an Ingress recommendation; pick one that meets your security posture and
  follow its documentation.
- **Hypervisor administration** — vCenter capacity planning, libvirt host
  hardening at the OS level, Proxmox cluster maintenance: not in scope.
- **Application-level VM ops** — patching guest OS, monitoring guest
  applications: out of scope; VirtRigaud manages the VM lifecycle, not what
  runs inside.

## Next steps

- New operator? Start at the [Quickstart](../getting-started/index.md), then
  read [Security](security.md) and [Resilience](resilience.md) before promoting
  to production.
- Upgrading from a previous release? Use the [Upgrade Guide](upgrade.md).
- Investigating an incident? [Observability](observability.md) lists every
  `virtrigaud_*` metric and what it tells you.
