<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Building VirtRigaud Locally

This guide covers building VirtRigaud from source and building the documentation.

!!! note "Build-path consolidation (PRs #115/#117/#119/#121, stable since v0.3.6)"
    Prior to v0.3.6 there were two parallel build paths — `cmd/main.go` + a root
    `Dockerfile`, and `cmd/manager/main.go` + `build/Dockerfile.manager`. The two
    drifted: `make build` and `make docker-build` produced a binary missing
    metrics setup plus the VMSnapshot and VMMigration controllers (latent bug
    [#113](https://github.com/projectbeskar/virtrigaud/issues/113)). v0.3.6
    deletes the orphan entrypoint + root Dockerfile and redirects every Make
    target to the canonical pair below. **If you were relying on `cmd/main.go`
    or the root `Dockerfile` before v0.3.6, switch to the canonical paths.**

## Canonical build inputs (v0.3.6+)

| Concern             | Canonical path                       |
|---------------------|--------------------------------------|
| Manager entrypoint  | `cmd/manager/main.go`                |
| Manager Dockerfile  | `build/Dockerfile.manager`           |
| Builder image       | `docker.io/golang:1.26.10` (override via `BUILDER_IMAGE`) |
| Runtime base image  | `gcr.io/distroless/static:nonroot` (override via `BASE_IMAGE`) |

`make build`, `make run`, `make docker-build`, `make docker-build-multiplatform`,
and `make docker-buildx` all build the canonical entrypoint with the canonical
Dockerfile.

## Building VirtRigaud Project

### Prerequisites

- **Go 1.26+** - [Download](https://go.dev/dl/) — the Go toolchain floor
  was raised to **1.26.3** in v0.3.7, to **1.26.4** in v0.3.8, and is
  **1.26.10** in v0.4.1. Binary consumers via released images are unaffected;
  only source builders need to upgrade. `go.mod` is the source of truth (the
  `sdk/` and `proto/` modules use the same version).
- **Docker** - [Install](https://docs.docker.com/get-docker/)
- **Kubernetes cluster** - kind, k3s, or remote
- **kubectl** - [Install](https://kubernetes.io/docs/tasks/tools/)
- **Helm 3.x** - [Install](https://helm.sh/docs/intro/install/)
- **make** - Usually pre-installed on Linux/macOS

### Quick Start

```bash
# Clone the repository
git clone https://github.com/projectbeskar/virtrigaud.git
cd virtrigaud

# Build the manager binary (canonical entrypoint).
# The target also bootstraps controller-gen and runs gen-crds/generate/fmt/vet
# the first time, so you do not need a separate `dev-setup` step.
make build

# Run tests
make test
```

### Build Targets

```bash
# Build manager (from cmd/manager/main.go → bin/manager)
make build

# Build a specific provider (CGO_ENABLED=0; binaries land in bin/).
# The libvirt provider is pure Go: no libvirt-dev headers are needed.
make build-provider-vsphere
make build-provider-libvirt
make build-provider-proxmox
make build-provider-mock

# Build all providers
make build-providers

# Run the manager from your host (handy for local controller dev)
make run
```

`make build` and the provider targets regenerate what they depend on: `make build`
runs `gen-crds generate fmt vet` first, and the `build-provider-libvirt`,
`build-provider-vsphere` and `build-provider-proxmox` targets run `make proto`
(which needs `buf`; it is installed under `bin/` on demand and fetches its
plugins from the Buf Schema Registry, so it needs network access).

The CLI tools (`vrtg`, `vcts`, `vrtg-provider`, `virtrigaud-loadgen`) have no
`make` target; build them with `go build -o bin/<tool> ./cmd/<tool>`.

### Container Images

```bash
# Build the manager image (uses build/Dockerfile.manager).
# The image tag comes from CONTROLLER_IMG (default controller:latest).
make docker-build CONTROLLER_IMG=example.com/virtrigaud/manager:dev

# Build for multiple platforms (loads locally; no push)
make docker-build-multiplatform

# Build + push multi-arch via buildx
make docker-buildx BUILD_PLATFORMS=linux/amd64,linux/arm64

# Build the provider images (PROVIDER_{LIBVIRT,VSPHERE,PROXMOX}_IMG set the tags;
# the mock provider has a Dockerfile but no make target)
make docker-providers
make docker-provider-vsphere
make docker-provider-libvirt
make docker-provider-proxmox

# Build + push multi-arch provider images
make docker-buildx-providers
make docker-buildx-provider-vsphere
make docker-buildx-provider-libvirt
make docker-buildx-provider-proxmox
```

### Testing

```bash
# Run unit tests (envtest-backed; includes a dry-run of every VirtRigaud
# object under examples/ against the CRDs)
make test

# Run integration tests (no cluster required — cross-package observability tests)
make test-integration

# Run the go-libvirt integration tests (need a reachable libvirtd; skip themselves otherwise)
make test-libvirt-integration

# Run end-to-end tests (requires a running kind cluster; the suite is gated
# behind //go:build e2e and the make target passes -tags=e2e)
make test-e2e

# Lint code (golangci-lint v2.12.2, pinned in the Makefile and used by CI)
make lint

# Format code
make fmt
```

See [Testing Locally](testing-locally.md) for what each layer covers.

## Corporate / banking deployments

v0.3.6 ([PR #117](https://github.com/projectbeskar/virtrigaud/pull/117), part of
the H1 build-path consolidation) parametrised `build/Dockerfile.manager` so
forks in environments that cannot pull from `docker.io` / `gcr.io` can point
at internal mirrors without patching the Dockerfile. This is still the
mechanism in v0.4.1.

### Override the builder and base images

Pass `BUILDER_IMAGE` / `BASE_IMAGE` as build args to point at your internal
registry (Artifactory, Harbor, ECR, etc.):

```bash
docker build -f build/Dockerfile.manager \
  --build-arg BUILDER_IMAGE=corp.io/golang:1.26.10 \
  --build-arg BASE_IMAGE=corp.io/distroless/static:nonroot \
  --build-arg VERSION=v0.4.1 \
  --build-arg GIT_SHA=$(git rev-parse HEAD) \
  -t corp.io/virtrigaud/manager:v0.4.1 .
```

Or via `make`:

```bash
make docker-build \
  BUILDER_IMAGE=corp.io/golang:1.26.10 \
  BASE_IMAGE=corp.io/distroless/static:nonroot \
  VERSION=v0.4.1 GIT_SHA=$(git rev-parse HEAD)
```

Defaults match the upstream public images so unpatched builds behave exactly
as before.

### Override the Go module proxy

The Dockerfile passes `GOPROXY`, `GOINSECURE`, `GOPRIVATE`, and `GOSUMDB`
through to the builder stage so corporate-proxy module fetches work without
rebuilding a custom builder image:

```bash
make docker-build \
  GOPROXY=https://artifactory.corp.io/go,direct \
  GOPRIVATE=*.corp.io \
  GOSUMDB=off
```

Defaults are empty (no override) except `GOSUMDB` which uses
`sum.golang.org`.

### Corporate TLS-intercepting proxies (CA cert injection)

If your `go mod download` traffic transits a TLS-intercepting proxy (Zscaler,
Netskope, BlueCoat, etc.) that re-signs HTTPS with an internal CA, drop the
`.crt` files into the `ca-certs/` directory at the repo root:

```
ca-certs/corporate-root-ca.crt
ca-certs/internal-tls-intercept.crt
```

The Dockerfile copies them into `/usr/local/share/ca-certificates/` and runs
`update-ca-certificates` **before** `go mod download` so the corporate trust
bundle is in place for module fetches. Upstream releases ship this directory
empty (only `.gitkeep` + `README.md`), so the `COPY` is a no-op for vanilla
builds — `update-ca-certificates` skips non-`.crt` files. See
`ca-certs/README.md` in the main repo for the full pattern (including the
distinction between builder-time CAs and runtime-pod CAs).

!!! warning "Runtime CAs are separate"
    `ca-certs/` injects certs into the **builder stage only**. The final image
    is `gcr.io/distroless/static:nonroot` and is not rebuilt to include those
    CAs. If the manager talks to remote provider pods over HTTPS through a
    TLS-intercepting proxy, mount runtime CAs into the deployed pod via a
    Secret/ConfigMap, or use a custom `BASE_IMAGE` that already trusts them.

## Building Documentation

The VirtRigaud documentation is built with MkDocs and includes auto-generated
CRD reference documentation.

### Prerequisites

#### Poetry (Python dependency manager)

```bash
# macOS/Linux
curl -sSL https://install.python-poetry.org | python3 -

# Or use pip
pip install poetry

# Or use your package manager
brew install poetry  # macOS
```

#### Go (for CRD documentation generation)

```bash
# macOS
brew install go

# Linux (Debian/Ubuntu)
sudo apt-get install golang-go

# Or download from https://go.dev/dl/
```

Go 1.26+ is required for generating CRD documentation from the v0.4.1 source
tree (the toolchain floor is **1.26.10** in v0.4.1).

### Quick Start

```bash
# Install dependencies (Python and Go tools)
make install
make install-crd-tools
make install-proto-tools

# Build the documentation (includes CRD and gRPC reference generation)
make build

# Serve with live reload for development
make serve
```

### Documentation Build Process

The documentation build automatically:

1. Installs Python dependencies with Poetry
2. Clones/updates the VirtRigaud repository
3. Runs `crd-ref-docs` to generate CRD documentation
4. Runs `buf generate` (with `protoc-gen-doc`) to generate the gRPC API reference from `provider.proto`
5. Builds the MkDocs site with all content

### Using Make (Recommended)

```bash
# Install Python dependencies
make install

# Install CRD generation tools (requires Go)
make install-crd-tools

# Clone/update VirtRigaud repository
make clone-virtrigaud

# Install buf and protoc-gen-doc (requires Go) for the gRPC API reference
make install-proto-tools

# Generate CRD documentation
make generate-crds

# Generate the gRPC API reference (src/references/grpc-api.md)
make generate-proto-docs

# Build the documentation (automatically runs generate-crds and generate-proto-docs)
make build

# Same, but fail on warnings (CI builds with --strict)
make build-strict

# Serve with live reload for development (http://127.0.0.1:8000)
make serve

# Remove site/, .cache/ and the cloned virtrigaud/ (the committed generated pages are kept)
make clean

# Run linting checks
make lint
```

### Using Poetry Directly

```bash
# Install dependencies
poetry install

# Build the documentation
poetry run mkdocs build

# Serve with live reload for development
poetry run mkdocs serve

# Build with strict mode (fails on warnings)
poetry run mkdocs build --strict
```

## CRD Documentation Generation

The build process automatically generates API reference documentation for
VirtRigaud's Custom Resource Definitions (CRDs):

1. **Clones VirtRigaud repository** - Checks out the release tag pinned in
   the website repository's `VIRTRIGAUD_VERSION` file
2. **Runs crd-ref-docs** - Extracts CRD schemas and generates markdown
   documentation
3. **Writes `src/references/generated-crd-docs.md`** - A comprehensive API
   reference, the page the site navigation links to. The file is committed
   and refreshed for each release; do not hand-edit it.

This ensures the documentation reflects the CRD structure of the cloned
source. As of v0.4.1 there are **12 CRDs**: VirtualMachine, Provider,
VMClass, VMImage, VMNetworkAttachment, VMMigration, VMSnapshot, VMClone,
VMSet, VMPlacementPolicy, Host and HostPool. (VMAdoption is a controller, not
a CRD.) VMSet's controller is still a not-yet-active stub that only reports a
`ControllerNotImplemented` condition. VMPlacementPolicy is consumed by the
placement scheduler for VirtualMachines on a clustered Provider; Host and
HostPool describe the hosts of a clustered Provider.

## Project Structure

### VirtRigaud Repository (v0.4.1)

```
virtrigaud/
├── api/infra.virtrigaud.io/v1beta1/   # CRD Go types (source of truth)
├── cmd/                                # Binaries
│   ├── manager/                        # Canonical manager entrypoint
│   ├── provider-vsphere/               # each provider has main.go + Dockerfile
│   ├── provider-libvirt/
│   ├── provider-proxmox/
│   ├── provider-mock/
│   ├── vrtg/                           # CLI
│   ├── vrtg-provider/                  # Provider scaffolder
│   ├── vcts/                           # Conformance test suite
│   ├── virtrigaud-loadgen/             # Load generator
│   └── alpha-to-beta-dryrun/
├── build/                              # Dockerfile.manager, Dockerfile.kubectl
├── ca-certs/                           # Corporate CA injection slot
├── internal/                           # Internal packages
│   ├── controller/                     # Kubernetes controllers (flat package)
│   ├── providers/{vsphere,libvirt,proxmox,mock}/   # Provider gRPC servers
│   ├── transport/grpc/                 # Manager-side gRPC client
│   ├── scheduler/ clustered/           # Placement scheduler, clustered-provider helpers
│   ├── conformance/                    # vcts runner and validator
│   └── {obs,resilience,storage,k8s,runtime,scaffold,...}/
├── proto/                              # Separate Go module: provider.proto + generated bindings
├── sdk/                                # Separate Go module: provider SDK
├── config/                             # Kustomize configs (CRD bases are committed)
├── charts/virtrigaud/                  # Helm chart (crds/ is generated, gitignored)
├── providers/catalog.yaml              # Provider catalog
├── docs/                               # Design notes, ADRs, release notes
├── examples/                           # YAML examples (dry-run in make test)
├── hack/                               # Dev and CI helper scripts
└── test/{e2e,conformance,integration,performance,utils}/
```

### Documentation Repository

```
virtrigaud-website/
├── mkdocs.yml                   # MkDocs configuration
├── VIRTRIGAUD_VERSION           # VirtRigaud release tag the references describe
├── tools/
│   ├── gen-crd-docs.sh             # generates src/references/generated-crd-docs.md
│   ├── gen-proto-docs.sh           # generates src/references/grpc-api.md
│   ├── crd-ref-docs-config.yaml    # CRD doc generation config
│   ├── buf.gen.docs.yaml           # buf template for gRPC API docs
│   └── tool-versions.env           # pinned crd-ref-docs, buf, protoc-gen-doc versions
├── pyproject.toml               # Python dependencies
├── Makefile                     # Build automation
├── src/                         # Documentation markdown
│   ├── getting-started/
│   ├── guides/
│   ├── providers/
│   ├── examples/
│   ├── operations/
│   ├── migration/
│   ├── references/              # includes generated-crd-docs.md and grpc-api.md (generated)
│   ├── api-reference/
│   └── development/
├── site/                        # Build output (ignored)
└── virtrigaud/                  # Cloned repo (ignored)
```

## Live Development

When making changes to documentation files, run `make serve` to see changes in
real-time at http://127.0.0.1:8000.

The site features:

- Live reload on file changes
- Full-text search
- Dark/light theme toggle
- Mobile-responsive design
- Code syntax highlighting
- Mermaid diagram support

## Adding New Pages

1. Add your markdown file to the `src/` directory
2. Update the `nav` section in `mkdocs.yml`
3. The page will automatically be included in the next build

## Deployment

The documentation is automatically deployed to GitHub Pages when changes are
pushed to the main branch. The workflow:
1. Checks out the VirtRigaud release tag pinned in `VIRTRIGAUD_VERSION`
2. Generates CRD documentation using `crd-ref-docs`
3. Generates the gRPC API reference from `provider.proto` using `buf` and `protoc-gen-doc`
4. Builds the MkDocs site with `--strict`
5. Deploys to GitHub Pages (only from the `main` branch)

Manual deployment can be triggered via the GitHub Actions UI, optionally with
a VirtRigaud release tag to document (the default is the tag in `VIRTRIGAUD_VERSION`).

## Troubleshooting

### Poetry Installation Issues

If Poetry installation fails:

```bash
# Try using pipx
pip install pipx
pipx install poetry
```

### Go Tool Installation

If `crd-ref-docs` installation fails:

```bash
# Ensure GOPATH/bin is in your PATH
export PATH=$PATH:$(go env GOPATH)/bin

# Add to your shell profile
echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.bashrc  # or ~/.zshrc
```

### MkDocs Build Failures

If the build fails:

```bash
# Clean and rebuild
make clean
make install
make build

# Check for missing dependencies
poetry install --no-root

# Validate mkdocs.yml
poetry run mkdocs build --strict
```

### CRD Generation Fails

If CRD generation fails:

```bash
# Verify crd-ref-docs is installed
which crd-ref-docs

# Reinstall the tool
make install-crd-tools

# Manually clone the pinned release and generate
git clone --branch "$(cat VIRTRIGAUD_VERSION)" https://github.com/projectbeskar/virtrigaud.git
./tools/gen-crd-docs.sh virtrigaud
```

## Next Steps

- [Contributing Guide](contributing.md) - How to contribute
- [Testing Locally](testing-locally.md) - Run tests
- [Provider Tutorial](../providers/tutorial.md) - Build a provider
- [GitHub Repository](https://github.com/projectbeskar/virtrigaud) - Main project
