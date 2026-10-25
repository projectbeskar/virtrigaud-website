<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Development

Reference for contributors and external provider authors working against
**VirtRigaud v0.4.0**.

## Where to go from here

| Topic | Page |
|-------|------|
| Build VirtRigaud from source — manager, in-tree providers, container images | [Building Locally](building-locally.md) |
| The contribution workflow — branch, test, CHANGELOG, sign-off | [Contributing](contributing.md) |
| Running the test suites — unit, integration, e2e (Kind), conformance | [Testing Locally](testing-locally.md) |
| Writing an external provider against the SDK | [Provider Development](providers.md) |
| Internal provider deep dives (vSphere, Libvirt, Proxmox) | [Provider docs](../providers/vsphere.md) |
| API surface — CRDs, gRPC contract, metrics catalog | [References section](../references/generated-crd-docs.md) |

## Prerequisites (v0.4.0)

The toolchain floor first moved in v0.3.6 (PR
[#125](https://github.com/projectbeskar/virtrigaud/pull/125)); v0.4.0 builds
on **Go 1.26.10**:

- **Go 1.26+** (v0.4.0 builds on **1.26.10**) — `go.mod` is the source of
  truth; CI uses `go-version-file: go.mod` so you should match locally.
  `sdk/go.mod` and `proto/go.mod` carry the same `go` line. Source builders
  must match it; **binary consumers via released container images are
  unaffected**.
- Docker — for image builds.
- Kubernetes cluster — `kind`, `k3d`, or a real cluster. `kind` is what
  the `make test-e2e` target expects.
- `kubectl`.
- Helm 3.x.
- `make`.

Optional, depending on what you're doing:

- `golangci-lint` — pinned by the Makefile (`GOLANGCI_LINT_VERSION`, v2.12.2,
  the same version CI runs); `make lint` installs it under `bin/` on first
  invocation.
- `setup-envtest` — `make test` bootstraps this for you. The Kubernetes
  version it downloads is derived from the `k8s.io/api` version in
  `go.mod` (v0.32.x, so envtest **1.32**).
- `buf` (v1.46.0, installed under `bin/` on demand) — for `make proto`,
  `make proto-lint` and `make proto-breaking`.
- `libvirtd` — only to run the go-libvirt integration tests
  (`make test-libvirt-integration`, which skips itself when none is
  reachable). Since the libvirt provider became pure Go, **no `libvirt-dev`
  headers or CGO toolchain are needed** to build it: every provider binary is
  built with `CGO_ENABLED=0`.

## One-time bootstrap

```bash
git clone https://github.com/projectbeskar/virtrigaud.git
cd virtrigaud

# Bootstraps controller-gen, regenerates CRDs and deepcopy code, runs
# fmt and vet, and produces bin/manager. Subsequent invocations are
# incremental.
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

`make test`, `make build` and `make run` already depend on `gen-crds`,
`generate`, `fmt` and `vet`, so the generated files are refreshed as a side
effect. If `api/infra.virtrigaud.io/v1beta1/*_types.go` changed, regenerate
explicitly and commit the result:

```bash
make generate          # DeepCopy methods (zz_generated.deepcopy.go)
make gen-crds          # config/crd/bases/ (committed); `make manifests` is an alias
make gen-helm-crds     # charts/virtrigaud/crds/ (gitignored, generated on demand)
```

If `proto/provider/v1/provider.proto` changed, run `make proto` (regenerate the
Go bindings) and `make proto-lint`; `make proto-breaking` checks for
breaking changes against `main`.

Then add or update tests and a CHANGELOG entry. The full mandate is on the
[Contributing](contributing.md) page; the **CHANGELOG entry is not
optional** for any change in `api/`, `cmd/`, `internal/`, `charts/`,
`proto/`, or `sdk/`.

## Where the code lives

```text
api/infra.virtrigaud.io/v1beta1/  CRD Go types — source of truth
cmd/                              manager, providers, CLI
  manager/                        canonical manager entrypoint
  provider-{vsphere,libvirt,proxmox,mock}/   provider binaries (+ Dockerfile each)
  vrtg/ vcts/ vrtg-provider/ virtrigaud-loadgen/ alpha-to-beta-dryrun/   CLIs
build/                            Dockerfile.manager, Dockerfile.kubectl
internal/
  controller/                     reconcilers (flat package, not subpackages)
  providers/{vsphere,libvirt,proxmox,mock}/   gRPC server implementations
  transport/grpc/                 manager-side gRPC client + CB interceptor
  scheduler/ clustered/           placement scheduler and clustered-provider helpers
  conformance/                    vcts runner and spec validator
  obs/                            metrics, logging, tracing
  resilience/                     CircuitBreaker primitive
  runtime/                        remote.Resolver, manager runtime helpers
  scaffold/                       vrtg-provider init templates
  storage/ imageartifact/ diskutil/   migration storage, prepared images, disk helpers
proto/                            separate Go module: provider.proto + generated bindings (proto/rpc)
sdk/                              separate Go module: provider SDK for external authors
charts/virtrigaud/                Helm chart (crds/ is generated, not committed)
config/                           Kustomize CRDs + RBAC + samples
docs/                             design notes, ADRs, release notes
examples/                         operator-facing YAML examples
providers/catalog.yaml            provider catalog
test/{e2e,integration,conformance,utils,performance}/   out-of-tree test suites
hack/                             dev and CI helper scripts
```

A few legacy paths that appear in older docs **do not exist** in
v0.4.0 — ignore any reference to them:

- `api/v1beta1/` (the old kubebuilder default — use
  `api/infra.virtrigaud.io/v1beta1/`).
- `pkg/grpc/` (use `internal/transport/grpc/` for manager-side and
  `sdk/provider/` for the SDK).

## Building images

```bash
# Manager image (uses build/Dockerfile.manager; unified path since v0.3.6)
make docker-build

# Provider images (libvirt, vsphere and proxmox have image targets;
# the mock provider has a Dockerfile but no make target)
make docker-provider-vsphere
make docker-provider-libvirt
make docker-provider-proxmox
make docker-providers                       # all three

# Build and push multi-arch provider images
make docker-buildx-providers

# Multi-arch
make docker-build-multiplatform
make docker-buildx BUILD_PLATFORMS=linux/amd64,linux/arm64
```

The manager and provider Dockerfiles accept the same set of build args
(documented in `build/Dockerfile.manager` and the per-provider
`cmd/provider-<name>/Dockerfile`) — `BUILDER_IMAGE`, `BASE_IMAGE`,
`GOPROXY`, CA-cert handling — useful for corporate / banking deployments
that need a private builder image or an internal proxy. The default builder
image is `golang:1.26.10`.

## Documentation

This site is built with MkDocs Material. The Go code itself does not build
the docs; the [virtrigaud-website](https://github.com/projectbeskar/virtrigaud-website)
repository owns them. To preview the site locally:

```bash
# In the virtrigaud-website repo
make install     # poetry install
make serve       # build (with generated CRD and gRPC reference pages) and serve on :8000
```

The CRD and gRPC reference pages (`src/references/generated-crd-docs.md` and
`src/references/grpc-api.md`) are generated from the API types and
`provider.proto`; do not hand-edit them. See
[Building Locally](building-locally.md#building-documentation).

## Provider development

There are two paths to add a provider:

1. **In-tree** (`internal/providers/<name>/`). Used by vSphere, Libvirt,
   Proxmox, and Mock. Has the most direct access to the manager's helpers
   but lives inside the main module. A new in-tree provider needs every RPC
   implemented (or answered `Unimplemented` and declared through its
   capabilities) and a `cmd/provider-<name>/` binary.
2. **Out-of-tree using the SDK** (`sdk/provider/`). For provider authors
   who want to ship their own gRPC server and image without forking the
   manager. See [Provider Development](providers.md).

The [Provider Tutorial](../providers/tutorial.md) walks through the
in-tree case end-to-end and is the most concrete reference; the SDK-based
case is documented at [Provider Development](providers.md).

## Release process

Tagged via `rc → smoke → final`:

1. `git tag v<X.Y.Z>-rc1`; push. Any tag matching `v*` starts the release
   workflow, and a tag containing `-` is published as a pre-release.
2. The release workflow builds multi-arch container images, signs them with
   cosign, generates SBOMs and SLSA provenance, packages the Helm chart,
   builds the CLI binaries, and runs Trivy scans (which has caught real CVEs
   pre-promotion — see
   [v0.3.6 release notes](../operations/upgrade.md#v035-v036)). A HIGH or
   CRITICAL finding blocks promotion.
3. Deploy the release candidate to a test cluster and smoke-test it.
4. If clean, tag `v<X.Y.Z>` from the same commit; the final release
   automation runs.
5. Announce.

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
