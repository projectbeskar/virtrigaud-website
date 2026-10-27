<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Versioning & Compatibility

This page describes the actual versioning model VirtRigaud follows today, the API-stability commitment, and how the project chooses release tags.

It is aligned to **VirtRigaud v0.4.1** (the current latest).

## TL;DR

- **Current latest**: `v0.4.1`. Helm chart `--version 0.4.1`. Provider images tagged `v0.4.1`.
- **CRD API version**: `infra.virtrigaud.io/v1beta1` is the **stable** API. Breaking changes need an ADR.
- **Release pattern**: release candidates, a soak against real hypervisors, then the final tag. v0.4.0 went through nine release candidates.
- **Support**: best-effort on the latest minor. The project does not maintain LTS branches. Upgrade to the latest patch within the current minor to get fixes.

## Components and their version dimensions

VirtRigaud is composed of several artefacts that each carry a version label:

| Component | Where it lives | Versioning notes |
|-----------|----------------|------------------|
| Manager binary | `cmd/manager` → `ghcr.io/projectbeskar/virtrigaud/manager:v0.4.1` | Tracks the project release tag exactly. |
| Provider binaries | `cmd/provider-{vsphere,libvirt,proxmox,mock}` → `ghcr.io/projectbeskar/virtrigaud/provider-*:v0.4.1` | Currently released in lockstep with the manager. |
| Helm chart | `charts/virtrigaud` | Chart version matches the project release without the `v` (`0.4.1`); the release workflow sets `Chart.yaml` and the image tags in `values.yaml` when it packages the chart. |
| CRD API | `api/infra.virtrigaud.io/v1beta1` | `v1beta1` — stable in the Kubernetes sense; see [API stability](#api-stability-v1beta1) below. |
| gRPC contract | `proto/provider/v1/provider.proto` | Separate Go module. New RPCs land additively; breaking proto changes would require a major proto-package bump. |
| Provider SDK | `sdk/` | Separate Go module. Used by external provider authors. |

All of the above are tagged together as `v0.4.1` for the v0.4.1 release. The `mock` provider is a development image and is not published under release tags.

## Semantic versioning

VirtRigaud follows [Semantic Versioning 2.0.0](https://semver.org/) for the project as a whole:

- **MAJOR.MINOR.PATCH**
- MAJOR: reserved for breaking CRD or gRPC contract changes — has not happened on the public release line.
- MINOR: backward-compatible feature additions (new CRDs, new metric families, new RPCs declared via capabilities).
- PATCH: bug fixes, security backports, dependency bumps.

## API stability (v1beta1)

The `infra.virtrigaud.io/v1beta1` API is the **stable** CRD surface in the Kubernetes sense:

- Adding new optional fields is allowed and routine (every minor release does this).
- Removing or renaming fields requires an ADR and an upgrade path. None have been removed on the public release line.
- Validation tightening (new `kubebuilder:validation:*` markers) is meant not to reject objects that were valid in a prior release. v0.4.0 is a deliberate exception for security: `spec.providerRef` of a bound `VirtualMachine`, `Provider.spec.type` and `Provider.spec.topology` are immutable, and a reference to another namespace's `Provider`, `VMClass` or `VMImage` needs `spec.consumerNamespaceSelector`. Each is called out in the [Upgrade Guide](../operations/upgrade.md).

The project rule is that a breaking change to the v1beta1 contract needs an ADR (see [Contributing](../development/contributing.md)).

There is no `v1alpha*` and no `v1` for the `infra.virtrigaud.io` group — operators target `v1beta1` for all CRs.

The 12 CRDs at v0.4.0: `VirtualMachine`, `Provider`, `VMClass`, `VMImage`, `VMNetworkAttachment`, `VMMigration`, `VMSnapshot`, `VMSet`, `VMPlacementPolicy`, `VMClone`, `Host`, `HostPool` (the last two are new in v0.4.0). `VMAdoption` is a controller, not a CRD.

## Release cadence and pattern

Releases land on a "ship when ready" cadence; the project does not commit to a fixed monthly or quarterly drumbeat. A release is cut as release candidates (`vX.Y.Z-rcN`) from `main`, validated against real hypervisors (vSphere, libvirt, Proxmox VE), and promoted to the final tag from the same commit once no candidate shows a regression. Each candidate is built, scanned, signed and published to ghcr.io; a candidate that fails the image scan is not published.

| Step | Purpose |
|------|---------|
| `-rcN` (release candidate) | Cut from `main` once all gates are green. Pre-release: not for production. |
| soak | Candidates are deployed against real hypervisors and exercised. Each finding goes back to `main` for a fix and a new candidate. |
| final | Tag promoted to its production name (for example `v0.4.0`) and shipped to the Helm repo. |

Track record: v0.3.3 took four candidates; v0.3.5 and v0.3.6 one each (v0.3.6 caught three HIGH-severity OpenTelemetry CVEs at the scan gate and was re-cut); v0.4.0 took nine (`rc3` was tagged but its release run was stopped by the image scan, so no `rc3` was published).

If you are choosing a version for production, prefer the latest final tag, and read the [Upgrade Guide](../operations/upgrade.md) before moving across a minor.

## Helm chart versioning

The chart version is identical to the project version. Always pin in production:

```bash
helm install virtrigaud virtrigaud/virtrigaud \
  --version 0.4.1 \
  --namespace virtrigaud-system \
  --create-namespace
```

```bash
helm upgrade virtrigaud virtrigaud/virtrigaud \
  --version 0.4.1 \
  --namespace virtrigaud-system \
  --reset-then-reuse-values
```

The published chart bundles the CRDs. Helm itself never upgrades CRDs from a chart's `crds/` directory, so the chart runs a pre-install and pre-upgrade hook Job that applies them with server-side apply (`crdUpgrade.enabled`, default `true`). Upgrading with a chart packaged before a newer CRD schema can overwrite the live CRDs and prune fields, so always use the chart from the matching release. See the [Helm CRD upgrades guide](../getting-started/helm-crd-upgrades.md) for the upgrade flow and for why a minor with required ordering (v0.4.0) needs the CRDs applied first.

## Provider image tags

Provider pods run separate images, each tagged to the same version as the manager:

```yaml
spec:
  runtime:
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.1"
```

A provider image must be compatible with the manager that drives it. Keep the provider images on the same release as the manager. When you upgrade, roll the CRDs first, then the manager, then the providers; the [Upgrade Guide](../operations/upgrade.md) lists the few cases where a provider must not be rolled ahead of the manager (libvirt, Proxmox) or must be rolled promptly after it (clustered libvirt, `ImagePrepare` identity).

## What constitutes a breaking change

These categories are treated as breaking and require an ADR + a deprecation cycle:

**CRD breaking**:

- Removing or renaming a field.
- Changing a field's type or accepted values.
- Tightening validation in a way that rejects previously-valid objects.
- Changing required vs optional semantics for an existing field.

**gRPC contract breaking**:

- Removing a field number, RPC method, or enum value from `proto/provider/v1/provider.proto`.
- Changing the semantics of an existing field.

**Capability flag breaking**:

- A provider flipping a capability from `true` to `false` without the operator-facing release notes calling it out — this counts as breaking because the manager's short-circuiting changes behaviour for existing CRs. (v0.3.8 corrected several libvirt cells; v0.4.0 reports libvirt `SupportsLinkedClones=false` because libvirt linked clones are disabled, with the change called out in the release notes. See [the capability matrix](providers-capabilities.md).)

**Compatibility-safe**:

- Adding new optional CRD fields.
- Adding new RPC methods (must be implemented in all providers, even if as `Unimplemented` declared via capabilities). v0.4.0 added `ListHosts`, `GetHostInfo`, `TransferOwner`, `DeleteStagedDisk` and `DeleteLandedDisk`; the mock provider answers the last two with `Unimplemented`.
- Adding new fields to existing messages (v0.4.0 added `target_host_id`, `owner` and others; a manager or provider that does not know a field ignores it).
- Adding new metric families.
- Adding new ADR-blessed CRDs.

## Backward-compatibility expectations

| Direction | Expectation |
|-----------|-------------|
| Older CR objects on a newer manager | Always valid (additive evolution only). |
| Newer CR objects on an older manager | Not supported. The older manager will reject the unknown fields. Upgrade the manager first. |
| Provider image newer than the manager | Best-effort. Do not pin a provider image to a release later than the manager; with a v0.3.11 manager, a v0.4.0 Proxmox provider fails every Proxmox-target `VMMigration` (it needs the manager's verified-stage fields). |
| Manager newer than provider images | Supported while you stage the rollout (CRDs, manager, providers), with known degradations: for example a v0.4.1 manager holds import-style image prepares and clustered resizes until the provider reports `supportsImageArtifactIdentity` / `supportsHonestReconfigure`. |

For the canonical step-by-step upgrade (v0.3.11 → v0.4.0 has a required order and several breaking changes), see the [Upgrade Guide](../operations/upgrade.md).

## Support window

The project does **not** maintain long-term-support branches. Support is best-effort on the latest minor:

- **Latest minor (`v0.4.x`)** — actively supported. Security backports land on `main` and ship in the next `v0.4.x` patch.
- **Prior minor** — community-only. No proactive backports; fixes accepted via PR.
- **Older** — not supported. Upgrade.

If you operate VirtRigaud in a regulated environment, pin to a specific patch and upgrade on a schedule rather than chasing latest. Each release tag is reproducible: the manager binary emits `virtrigaud_build_info{version="v0.4.0"}` on `/metrics`, and the container image digest is signed and published to ghcr.io.

## Where to track releases

- **Releases**: [github.com/projectbeskar/virtrigaud/releases](https://github.com/projectbeskar/virtrigaud/releases) — every final tag has release notes pointing to the `CHANGELOG.md` block.
- **Changelog**: [`CHANGELOG.md`](https://github.com/projectbeskar/virtrigaud/blob/main/CHANGELOG.md) — every change since v0.1.0 with author attribution.
- **Roadmap**: tracked in GitHub issues and labels; no separate roadmap document.

## Choosing a version

- **New installs**: use `v0.4.0`.
- **Upgrading from `v0.3.11`**: read the [Upgrade Guide](../operations/upgrade.md) first. v0.4.0 is a security-hardening release with breaking changes (cross-namespace grants, immutable `spec.providerRef`, a new vCenter privilege, libvirt host preparation, and more) and a required order: CRDs, then grants, then the manager, then the providers.
- **Upgrading from older `v0.3.x`**: upgrade to v0.3.11 first, or read every intermediate CHANGELOG block.
- **Anything pre-`v0.3.0`**: not supported. Migrate to `v0.3.x` directly.

## API reference

- [Capability matrix](providers-capabilities.md) — per-provider capabilities at v0.4.1.
- [Generated CRD reference](../references/generated-crd-docs.md).
- [Provider gRPC contract reference](../references/grpc-api.md).
