<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Operations Guide

Operator-facing reference for running VirtRigaud **v0.3.6** in production. The
pages linked from here are the authoritative source for each topic; this index
is a router, not a duplicate.

!!! warning "Read the security page before you trust this section in production"
    Several network-security controls that an experienced operator might
    *expect* from a Kubernetes operator that talks to hypervisors are **not yet
    wired in v0.3.6**: mTLS between the manager and provider pods (#147),
    server-side auth on the provider gRPC endpoint (#148), and libvirt SSH
    host-key verification (#149). They are called out honestly on the
    [Security](security.md) page and on the per-control pages
    ([mTLS](../providers/security/mtls.md),
    [Bearer Token](../providers/security/bearer-token.md)). Do not assume a
    control is in place because the field exists in a CRD — verify against the
    source references those pages cite.

## Core operational topics

| Page | Scope |
|------|-------|
| [Observability](observability.md) | What VirtRigaud exposes on `/metrics` after v0.3.6: 11 of 12 `virtrigaud_*` families wired in code (G6 CircuitBreaker pair + G7.1/7.2/7.3 + v0.3.5 baseline), the 12th deprecated. No invented metrics. |
| [Resilience](resilience.md) | **G6 CircuitBreaker is now WIRED in v0.3.6** (one breaker per `Provider` CR via `internal/transport/grpc/client.go`). Explains failure classification (`isInfraFailure`), default thresholds (`FailureThreshold=10`, `ResetTimeout=60s`, `HalfOpenMaxCalls=3`), and what tripping looks like in metrics. |
| [Security](security.md) | Canonical operator-facing security reference. STRIDE pass, credential-flow diagram, the three honest [NOT WIRED IN v0.3.6] disclosures, and the compensating controls a regulated deployment must layer on top. |
| [Upgrade Guide](upgrade.md) | Helm-based upgrade matrix, **v0.3.5 → v0.3.6** notes (Go 1.26+ toolchain floor for source builders, no operator-visible breaking changes), CRD upgrade procedure, rollback. |

### Security sub-pages

The detailed control-by-control pages live under `providers/security/` because
they apply equally to in-tree providers and external providers built on the
SDK. They were rewritten in Phase 6 to be **honest about what is and is not
wired in v0.3.6**:

- [Bearer Token Authentication](../providers/security/bearer-token.md) —
  Production-relevant for **hypervisor API tokens** (Proxmox today, future
  REST-based providers). gRPC-channel bearer auth via the SDK exists but is
  **not enabled by the in-tree providers and not sent by the manager** in v0.3.6.
- [mTLS Configuration](../providers/security/mtls.md) — **NOT WIRED in v0.3.6**
  (#147). `Resolver.buildTLSConfig` returns `nil, nil` unconditionally. The CRD
  field `Provider.spec.runtime.service.tls` is parsed and validated but has no
  runtime effect.
- [External Secrets](../providers/security/external-secrets.md) — Wiring
  External Secrets Operator / Vault into the credentials Secret that
  VirtRigaud mounts.
- [Network Policies](../providers/security/network-policies.md) — Mandatory
  compensating control while mTLS is not wired.

## Infrastructure-specific topics

| Page | When you need it |
|------|------------------|
| [vSphere Hardware Versions](vsphere-hardware-version.md) | Managing the `vmx-N` compatibility level of guest VMs via the `HardwareUpgrade` gRPC RPC. vSphere-only. |
| [Libvirt Host Preparation](libvirt-host-prepare.md) | Preparing a Libvirt/KVM host (SSH user, groups, storage pool, network bridge, SELinux/AppArmor) so the libvirt provider can drive it. Includes the v0.3.6 honest disclosure about SSH host-key verification being skipped (#149). |

## Production-readiness checklist

Use this before promoting a VirtRigaud deployment to production. Each item links
to the page that actually covers it.

- [ ] **CRDs installed at the v0.3.6 schema** — `helm pull virtrigaud/virtrigaud --version 0.3.6 --untar && kubectl apply -f virtrigaud/crds/`. See [Upgrade Guide](upgrade.md).
- [ ] **Manager + provider images pinned to v0.3.6** — release artifacts are tagged in lockstep; do not mix versions across the manager/providers/CRDs trio.
- [ ] **Metrics scrape configured** — a `ServiceMonitor` (or equivalent) against the manager's `/metrics`. After v0.3.6, expect the families documented in [Observability](observability.md).
- [ ] **Per-Provider CircuitBreaker behavior understood** — read [Resilience](resilience.md). The CB will trip Open within seconds of a provider going bad. That is the metric working as designed.
- [ ] **Compensating network controls for the unwired mTLS path** —
      `NetworkPolicy` that restricts provider-pod ingress to the manager pod,
      and either an encrypted CNI (Cilium WireGuard, Calico WireGuard, IPsec) or
      private cluster networking. See [mTLS](../providers/security/mtls.md) and
      [Network Policies](../providers/security/network-policies.md).
- [ ] **Provider credentials reviewed** — for **Proxmox**, API tokens
      (`token_id` / `token_secret`) **must** be used; password fallback is for
      development parity only. See [Bearer Token Authentication](../providers/security/bearer-token.md).
- [ ] **Secrets backend chosen** — at minimum, kube-apiserver
      `EncryptionConfiguration` for etcd-at-rest encryption. For multi-cluster /
      regulated deployments, External Secrets Operator (Vault, AWS Secrets
      Manager, etc.) per [External Secrets](../providers/security/external-secrets.md).
- [ ] **Manager HA** — manager Deployment with at least 2 replicas and leader
      election (controller-runtime enables it by default).
- [ ] **Audit trail** — CHANGELOG entries with author attribution per
      `CLAUDE.md` (regulated-deployment posture), plus K8s audit logging
      enabled at the cluster level.
- [ ] **Backup/restore procedure** — VirtRigaud does not back up CRs;
      reuse your standard `etcd` snapshot + cluster-level Velero / equivalent.

## Day-2 cheatsheet

The commands below are the same patterns the [Observability](observability.md)
and [Security](security.md) pages cite; they live here as a quick-reference.
Provider workloads in v0.3.6 are operator-deployed via Helm with the chart's
provider sub-charts (or applied directly as Deployments referenced by a
`Provider` CR); the labels below assume the chart's defaults.

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

# Provider pod logs (label depends on chart values; this matches the default sub-chart)
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
kubectl -n virtrigaud-system rollout restart deploy/<provider-deployment>
```

### Reading CircuitBreaker state

The v0.3.6 G6 wiring exposes one breaker per Provider CR. The fast operator
signal is:

```bash
kubectl exec -n virtrigaud-system deploy/virtrigaud-manager -- \
  curl -s localhost:8080/metrics | \
  grep -E 'virtrigaud_circuit_breaker_(state|failures_total)'
```

`state == 1` is Open; `state == 2` is Half-Open; `state == 0` is Closed. See
[Resilience](resilience.md#circuitbreaker-on-the-provider-grpc-path-v036).

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
