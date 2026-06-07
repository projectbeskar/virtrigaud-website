<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Versioning & Compatibility

This page describes the actual versioning model VirtRigaud follows today, the API-stability commitment, and how the project chooses release tags.

It is aligned to **VirtRigaud v0.3.8** (the current latest).

## TL;DR

- **Current latest**: `v0.3.8`. Helm chart `--version 0.3.8`. Provider images tagged `v0.3.8`.
- **CRD API version**: `infra.virtrigaud.io/v1beta1` is the **stable** API. Breaking changes need an ADR.
- **Release pattern**: `rc1 → smoke → final` is the established cadence. Used successfully for v0.3.3, v0.3.5, v0.3.6, and onward.
- **Support**: best-effort on the latest minor. The project does not maintain LTS branches. Upgrade to the latest patch within the current minor to get fixes.

## Components and their version dimensions

VirtRigaud is composed of several artefacts that each carry a version label:

| Component | Where it lives | Versioning notes |
|-----------|----------------|------------------|
| Manager binary | `cmd/manager` → `ghcr.io/projectbeskar/virtrigaud/manager:v0.3.8` | Tracks the project release tag exactly. |
| Provider binaries | `cmd/provider-{vsphere,libvirt,proxmox,mock}` → `ghcr.io/projectbeskar/virtrigaud/provider-*:v0.3.8` | Currently released in lockstep with the manager. |
| Helm chart | `charts/virtrigaud` | Chart version matches the project release (`Chart.yaml: 0.3.8`). |
| CRD API | `api/infra.virtrigaud.io/v1beta1` | `v1beta1` — stable in the Kubernetes sense; see [API stability](#api-stability-v1beta1) below. |
| gRPC contract | `proto/provider/v1/provider.proto` | Separate Go module. New RPCs land additively; breaking proto changes would require a major proto-package bump. |
| Provider SDK | `sdk/` | Separate Go module. Used by external provider authors. |

All of the above are tagged together as `v0.3.8` for the v0.3.8 release.

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
- Validation tightening (new `kubebuilder:validation:*` markers) must not reject objects that were valid in a prior release.

The v1beta1 contract is enforced project-wide via the `CLAUDE.md` rule that breaking changes need an ADR (see [`development/contributing.md`](../development/contributing.md)).

There is no `v1alpha*` and no `v1` for the `infra.virtrigaud.io` group — operators target `v1beta1` for all CRs.

The 10 CRDs at v0.3.8: `VirtualMachine`, `Provider`, `VMClass`, `VMImage`, `VMNetworkAttachment`, `VMMigration`, `VMSnapshot`, `VMSet`, `VMPlacementPolicy`, `VMClone`. `VMAdoption` is a controller, not a CRD.

## Release cadence and pattern

Releases land on a "ship when ready" cadence; the project does not commit to a fixed monthly or quarterly drumbeat. Each release follows a three-step pattern that has now been used successfully for **three consecutive releases**:

```
rc1  →  smoke on vr1.lab.k8  →  final
```

| Step | Purpose |
|------|---------|
| `rc1` (release candidate) | Cut from `main` once all gates are green. Built, signed, and promoted to ghcr.io with an `-rc1` suffix. |
| smoke | Deployed to the project's lab cluster (`vr1.lab.k8`) and exercised with the field-test scenarios. Any regression bounces back to `main` for a fix and a new rc. |
| final | Tag promoted to its production name (e.g. `v0.3.8`) from the same commit, signed, and shipped to the Helm repo. |

Track record:

- **v0.3.3**: took 4 rcs (first usage of the pattern).
- **v0.3.5**: 1 rc → promoted to final.
- **v0.3.6**: 1 rc → caught and fixed 3 HIGH-severity otel CVEs during the Trivy gate, re-cut → promoted to final.

If you are choosing a version for production, prefer the latest `v0.3.x` final tag.

## Helm chart versioning

The chart version is identical to the project version. Always pin in production:

```bash
helm install virtrigaud virtrigaud/virtrigaud \
  --version 0.3.8 \
  --namespace virtrigaud-system \
  --create-namespace
```

```bash
helm upgrade virtrigaud virtrigaud/virtrigaud \
  --version 0.3.8 \
  --namespace virtrigaud-system
```

The chart bundles the CRDs at `charts/virtrigaud/crds/` and includes them at install time. CRDs are **not** auto-upgraded by Helm during `helm upgrade` (this is standard Helm behaviour). See the [Helm CRD upgrades guide](../getting-started/helm-crd-upgrades.md) for the upgrade flow.

## Provider image tags

Provider pods run separate images, each tagged to the same version as the manager:

```yaml
spec:
  runtime:
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.3.8"
```

A provider image must be compatible with the manager that drives it. The recommendation is to keep the provider images on the same `v0.3.x` minor as the manager.

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

- A provider flipping a capability from `true` to `false` without the operator-facing release notes calling it out — this counts as breaking because the manager's short-circuiting changes behaviour for existing CRs. (Phase 2's v0.3.6 doc alignment corrected two such cells; v0.3.8 then flipped libvirt `SupportsLinkedClones` and `SupportsImageImport` to `false` via the #153/#154 honesty pass, with the change called out in the release notes. See [the capability matrix](providers-capabilities.md).)

**Compatibility-safe**:

- Adding new optional CRD fields.
- Adding new RPC methods (must be implemented in all providers, even if as `Unimplemented` declared via capabilities).
- Adding new metric families.
- Adding new ADR-blessed CRDs.

## Backward-compatibility expectations

| Direction | Expectation |
|-----------|-------------|
| Older CR objects on a newer manager | Always valid (additive evolution only). |
| Newer CR objects on an older manager | Not supported. The older manager will reject the unknown fields. Upgrade the manager first. |
| Provider image one minor newer than the manager | Best-effort. Do not pin a provider image to a release later than the manager. |
| Manager one minor newer than provider images | Supported within the current minor (so a v0.3.8 manager works with v0.3.7 provider pods if you stage rollouts). |

For the canonical step-by-step upgrade (v0.3.7 → v0.3.8 is the current happy path), see the [Upgrade Guide](../operations/upgrade.md).

## Support window

The project does **not** maintain long-term-support branches. Support is best-effort on the latest minor:

- **Latest minor (`v0.3.x`)** — actively supported. Security backports land on `main` and ship in the next `v0.3.x` patch.
- **Prior minor** — community-only. No proactive backports; fixes accepted via PR.
- **Older** — not supported. Upgrade.

If you operate VirtRigaud in a regulated environment (the project is documented as deployable in regulated banking environments — see the field-testing notes), pin to a specific patch and upgrade on a schedule rather than chasing latest. Each release tag is reproducible: the manager binary emits `virtrigaud_build_info{version="v0.3.8"}` on `/metrics`, and the container image digest is signed and published to ghcr.io.

## Where to track releases

- **Releases**: [github.com/projectbeskar/virtrigaud/releases](https://github.com/projectbeskar/virtrigaud/releases) — every final tag has release notes pointing to the `CHANGELOG.md` block.
- **Changelog**: [`CHANGELOG.md`](https://github.com/projectbeskar/virtrigaud/blob/main/CHANGELOG.md) — every change since v0.1.0 with author attribution.
- **Roadmap**: tracked in GitHub issues and labels; no separate roadmap document.

## Choosing a version

- **New installs**: use `v0.3.8`.
- **Upgrading from `v0.3.7`**: routine, no CRD changes; see the [Upgrade Guide](../operations/upgrade.md). Note the v0.3.8 capability-negotiation surfacing (`Provider.status.reportedCapabilities` + the opt-in `--enforce-provider-capabilities` flag, default off) and the corrected libvirt clone/image-import capability flags — see the [capability matrix](providers-capabilities.md).
- **Upgrading from older `v0.3.x`**: same Helm install pattern, but read the intermediate CHANGELOG blocks for new metric families and capability corrections.
- **Anything pre-`v0.3.0`**: not supported. Migrate to `v0.3.x` directly.

## API reference

- [Capability matrix](providers-capabilities.md) — the v0.3.8 corrected snapshot.
- [Generated CRD reference](../references/generated-crd-docs.md).
- [Provider gRPC contract reference](../references/grpc-api.md).
