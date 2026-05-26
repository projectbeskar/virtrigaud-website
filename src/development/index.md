<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Development

Reference for contributors and external provider authors working against
**VirtRigaud v0.3.6**.

## Where to go from here

| Topic | Page |
|-------|------|
| Build VirtRigaud from source — manager, in-tree providers, container images | [Building Locally](building-locally.md) |
| The contribution workflow — branch, test, CHANGELOG, sign-off | [Contributing](contributing.md) |
| Running the test suites — unit, integration, e2e (Kind), conformance | [Testing Locally](testing-locally.md) |
| Writing an external provider against the SDK | [Provider Development](providers.md) |
| Internal provider deep dives (vSphere, Libvirt, Proxmox) | [Provider docs](../providers/vsphere.md) |
| API surface — CRDs, gRPC contract, metrics catalog | [References section](../references/generated-crd-docs.md) |

## Prerequisites (v0.3.6)

The toolchain floor moved in v0.3.6 (PR
[#125](https://github.com/projectbeskar/virtrigaud/pull/125)):

- **Go 1.26+** — `go.mod` is the source of truth; CI uses
  `go-version-file: go.mod` so you should match locally. Source builders
  must upgrade; **binary consumers via released container images are
  unaffected**.
- Docker — for image builds and the libvirt provider's CGO toolchain.
- Kubernetes cluster — `kind`, `k3d`, or a real cluster. `kind` is what
  the `make test-e2e` target expects.
- `kubectl`.
- Helm 3.x.
- `make`.

Optional, depending on what you're building:

- `libvirt-dev` (Debian/Ubuntu) or `libvirt-devel` (Fedora) — required to
  compile the libvirt provider locally (`make build-provider-libvirt`).
  The libvirt provider is `CGO_ENABLED=1`; the other providers are pure
  Go.
- `golangci-lint` — pinned via `make lint`; will be installed locally
  under `bin/` on first invocation.
- `setup-envtest` — `make test` bootstraps this for you.

## One-time bootstrap

```bash
git clone https://github.com/projectbeskar/virtrigaud.git
cd virtrigaud

# Bootstraps controller-gen, envtest, and produces bin/manager.
# Subsequent invocations are incremental.
make build
```

Running `make build` first is the recommended bootstrap because the target
declares `gen-crds generate fmt vet` as dependencies, which pulls in the
code-generation toolchain. Other targets reuse the cached tools.

## The mandatory edit loop

After **any** `.go` change:

```bash
make fmt          # must produce no diff
make lint         # fix every warning
make test         # all packages pass
make build        # must succeed
```

If `*_types.go` changed, additionally:

```bash
make update-crds       # alias: make generate manifests sync-helm-crds
```

Then add or update tests and a CHANGELOG entry. The full mandate is on the
[Contributing](contributing.md) page; the **CHANGELOG entry is not
optional** for any change in `api/`, `cmd/`, `internal/`, `charts/`,
`proto/`, or `sdk/`.

## Where the code lives

```text
api/infra.virtrigaud.io/v1beta1/  CRD Go types — source of truth
cmd/                              manager, providers, CLI
  manager/                        canonical manager entrypoint (v0.3.6+; #119)
  provider-{vsphere,libvirt,proxmox,mock}/
internal/
  controller/                     reconcilers (flat package, not subpackages)
  providers/{vsphere,libvirt,proxmox,mock}/   gRPC server implementations
  transport/grpc/                 manager-side gRPC client + CB interceptor
  obs/                            metrics, logging, tracing
  resilience/                     CircuitBreaker primitive (G6 / #112)
  runtime/                        remote.Resolver, manager runtime helpers
  scaffold/                       boilerplate helpers
proto/                            separate Go module: provider.proto + bindings
sdk/                              separate Go module: provider SDK for external authors
charts/virtrigaud/                Helm chart with synced CRDs
config/                           Kustomize CRDs + RBAC + samples
examples/                         operator-facing YAML examples
test/{e2e,integration,conformance}/   out-of-tree test suites
fieldTesting/                     scratch workspace, NOT part of the build
```

A few legacy paths that appear in older docs **do not exist** in
v0.3.6 — ignore any reference to them:

- `api/v1beta1/` (the old kubebuilder default — use
  `api/infra.virtrigaud.io/v1beta1/`).
- `pkg/grpc/` (use `internal/transport/grpc/` for manager-side and
  `sdk/provider/` for the SDK).

## Building images

```bash
# Manager image (uses build/Dockerfile.manager; v0.3.6 unified path)
make docker-build

# Provider images
make docker-buildx-provider-vsphere
make docker-buildx-provider-libvirt
make docker-buildx-provider-proxmox
make docker-buildx-provider-mock

# All providers
make docker-buildx-providers

# Multi-arch
make docker-build-multiplatform
make docker-buildx BUILD_PLATFORMS=linux/amd64,linux/arm64
```

The manager and provider Dockerfiles accept the same set of build args
(documented in `build/Dockerfile.manager` and the per-provider
`cmd/provider-<name>/Dockerfile`) — `BUILDER_IMAGE`, `BASE_IMAGE`,
`GOPROXY`, CA-cert handling — useful for corporate / banking deployments
that need a private builder image or an internal proxy.

## Documentation

This site is built with MkDocs Material. The Go code itself does not build
the docs; the [virtrigaud-website](https://github.com/projectbeskar/virtrigaud-website)
repository owns them. To preview the site locally:

```bash
# In the virtrigaud-website repo
make install     # pip install -r requirements.txt
make serve       # mkdocs serve on :8000
```

CRD reference pages under `src/references/generated-crd-docs.md` are
regenerated from the actual CRDs; do not hand-edit them.

## Provider development

There are two paths to add a provider:

1. **In-tree** (`internal/providers/<name>/`). Used by vSphere, Libvirt,
   Proxmox, and Mock. Has the most direct access to the manager's helpers
   but lives inside the main module.
2. **Out-of-tree using the SDK** (`sdk/provider/`). For provider authors
   who want to ship their own gRPC server and image without forking the
   manager. See [Provider Development](providers.md).

The [Provider Tutorial](../providers/tutorial.md) walks through the
in-tree case end-to-end and is the most concrete reference; the SDK-based
case is documented at [Provider Development](providers.md).

## Release process

Tagged via `rc → smoke → final`:

1. `git tag v<X.Y.Z>-rc1`; push.
2. The release workflow builds rc1 container images and runs Trivy scans
   (which has caught real CVEs pre-promotion — see
   [v0.3.6 release notes](../operations/upgrade.md#v035-v036)).
3. Deploy rc1 to a lab cluster (`vr1.lab.k8` is the canonical one);
   smoke-test.
4. If clean, tag `v<X.Y.Z>` from the same commit; the final release
   automation runs.
5. Update the Helm chart repo and announce.

The CHANGELOG entries for each release have authoring attribution per the
project rules — that is also the audit-trail mechanism for regulated
deployments.

## Getting help

- **[GitHub Issues](https://github.com/projectbeskar/virtrigaud/issues)** —
  bug reports, feature requests, security advisories.
- **[GitHub Discussions](https://github.com/projectbeskar/virtrigaud/discussions)** —
  questions, design discussion.

That's the full list. Older docs referred to a `#virtrigaud` Slack channel;
**no such channel exists** and that reference was removed in
[PR #9](https://github.com/projectbeskar/virtrigaud-website/pull/9).

## Code of conduct

VirtRigaud follows the CNCF Code of Conduct. Be respectful and inclusive.

## Next steps

- [Building Locally](building-locally.md) — first time building from
  source.
- [Contributing](contributing.md) — opening your first PR.
- [Testing Locally](testing-locally.md) — running the full test matrix.
- [Provider Development](providers.md) — writing an SDK-based provider.
