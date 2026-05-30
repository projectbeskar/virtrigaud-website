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
| Builder image       | `docker.io/golang:1.26.3` (override via `BUILDER_IMAGE`) |
| Runtime base image  | `gcr.io/distroless/static:nonroot` (override via `BASE_IMAGE`) |

`make build`, `make run`, `make docker-build`, `make docker-build-multiplatform`,
and `make docker-buildx` all build the canonical entrypoint with the canonical
Dockerfile.

## Building VirtRigaud Project

### Prerequisites

- **Go 1.26.3+** - [Download](https://go.dev/dl/) — the Go toolchain floor
  was raised to **1.26.3** in v0.3.7. Binary consumers via released images are
  unaffected; only source builders need to upgrade.
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

# Build a specific provider
make build-provider-vsphere
make build-provider-libvirt    # requires CGO + libvirt-dev headers
make build-provider-proxmox
make build-provider-mock

# Build all providers
make build-providers

# Run the manager from your host (handy for local controller dev)
make run
```

### Container Images

```bash
# Build the manager image (uses build/Dockerfile.manager)
make docker-build

# Build for multiple platforms (loads locally; no push)
make docker-build-multiplatform

# Build + push multi-arch via buildx
make docker-buildx BUILD_PLATFORMS=linux/amd64,linux/arm64

# Build + push providers
make docker-buildx-providers
make docker-buildx-provider-vsphere
make docker-buildx-provider-libvirt
make docker-buildx-provider-proxmox
```

### Testing

```bash
# Run unit tests
make test

# Run integration tests (no cluster required — cross-package observability tests)
make test-integration

# Run end-to-end tests (requires kind cluster; gated behind //go:build e2e
# since #133). NB: `make test-e2e` itself does not yet pass `-tags=e2e`, so
# until that lands invoke the explicit form:
go test -tags=e2e ./test/e2e/... -v -ginkgo.v

# Lint code (CI uses golangci-lint v2.12.2 — see Contributing)
make lint

# Format code
make fmt
```

## Corporate / banking deployments

v0.3.6 ([PR #117](https://github.com/projectbeskar/virtrigaud/pull/117), part of
the H1 build-path consolidation) parametrises `build/Dockerfile.manager` so
forks in environments that cannot pull from `docker.io` / `gcr.io` can point
at internal mirrors without patching the Dockerfile.

### Override the builder and base images

Pass `BUILDER_IMAGE` / `BASE_IMAGE` as build args to point at your internal
registry (Artifactory, Harbor, ECR, etc.):

```bash
docker build -f build/Dockerfile.manager \
  --build-arg BUILDER_IMAGE=corp.io/golang:1.26.3 \
  --build-arg BASE_IMAGE=corp.io/distroless/static:nonroot \
  --build-arg VERSION=v0.3.6 \
  --build-arg GIT_SHA=$(git rev-parse HEAD) \
  -t corp.io/virtrigaud/manager:v0.3.6 .
```

Or via `make`:

```bash
make docker-build \
  BUILDER_IMAGE=corp.io/golang:1.26.3 \
  BASE_IMAGE=corp.io/distroless/static:nonroot \
  VERSION=v0.3.6 GIT_SHA=$(git rev-parse HEAD)
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

Go 1.26.3 or higher is required for generating CRD documentation from the
v0.3.7+ source tree.

### Quick Start

```bash
# Install dependencies (Python and Go tools)
make install
make install-crd-tools

# Build the documentation (includes CRD generation)
make build

# Serve with live reload for development
make serve
```

### Documentation Build Process

The documentation build automatically:

1. Installs Python dependencies with Poetry
2. Clones/updates the VirtRigaud repository
3. Runs `crd-ref-docs` to generate CRD documentation
4. Builds the MkDocs site with all content

### Using Make (Recommended)

```bash
# Install Python dependencies
make install

# Install CRD generation tools (requires Go)
make install-crd-tools

# Clone/update VirtRigaud repository
make clone-virtrigaud

# Generate CRD documentation
make generate-crds

# Build the documentation (automatically runs generate-crds)
make build

# Serve with live reload for development (http://127.0.0.1:8000)
make serve

# Clean generated files (including cloned repo and generated CRDs)
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

1. **Clones VirtRigaud repository** - Gets the latest CRD definitions from the
   main project
2. **Runs crd-ref-docs** - Extracts CRD schemas and generates markdown
   documentation
3. **Outputs to `src/generated-crd-docs.md`** - Creates a comprehensive API
   reference

This ensures the documentation always reflects the current CRD structure. As
of v0.3.6 there are **10 CRDs**: VirtualMachine, Provider, VMClass, VMImage,
VMNetworkAttachment, VMMigration, VMSnapshot, VMSet, VMPlacementPolicy,
VMClone. (VMAdoption is a controller, not a CRD.)

## Project Structure

### VirtRigaud Repository (v0.3.6)

```
virtrigaud/
├── api/infra.virtrigaud.io/v1beta1/   # CRD Go types (source of truth)
├── cmd/                                # Binaries
│   ├── manager/                        # Canonical manager entrypoint
│   ├── provider-vsphere/
│   ├── provider-libvirt/
│   ├── provider-proxmox/
│   ├── provider-mock/
│   ├── vrtg/                           # CLI
│   ├── vrtg-provider/                  # Provider scaffolder
│   ├── vcts/                           # Conformance test suite
│   ├── virtrigaud-loadgen/             # Load generator
│   └── alpha-to-beta-dryrun/
├── build/                              # Dockerfiles
│   ├── Dockerfile.manager              # Canonical manager image
│   ├── Dockerfile.provider-vsphere
│   ├── Dockerfile.provider-libvirt
│   └── Dockerfile.kubectl
├── ca-certs/                           # Corporate CA injection slot
├── internal/                           # Internal packages
│   ├── controller/                     # Kubernetes controllers (flat package)
│   ├── providers/{vsphere,libvirt,proxmox,mock}/   # Provider gRPC servers
│   ├── transport/grpc/                 # Manager-side gRPC client
│   └── {obs,resilience,storage,k8s,runtime,scaffold}/
├── proto/                              # Separate Go module: provider.proto
├── sdk/                                # Separate Go module: provider SDK
├── config/                             # Kustomize configs
├── charts/virtrigaud/                  # Helm chart (templates + synced CRDs)
├── docs/                               # Documentation source
└── test/{e2e,conformance,integration,performance,utils}/
```

### Documentation Repository

```
virtrigaud-website/
├── mkdocs.yml                   # MkDocs configuration
├── tools/
│   ├── crd-ref-docs-config.yaml    # CRD doc generation config
│   └── buf.gen.docs.yaml           # buf template for gRPC API docs
├── pyproject.toml               # Python dependencies
├── Makefile                     # Build automation
├── src/                         # Documentation markdown
│   ├── getting-started/
│   ├── guides/
│   ├── providers/
│   ├── examples/
│   ├── development/
│   └── generated-crd-docs.md    # Auto-generated
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

1. Clones the VirtRigaud repository
2. Generates CRD documentation using `crd-ref-docs`
3. Builds the MkDocs site
4. Deploys to GitHub Pages

Manual deployment can be triggered via the GitHub Actions UI.

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

# Manually clone and generate
git clone https://github.com/projectbeskar/virtrigaud.git
cd virtrigaud
crd-ref-docs \
  --source-path=api \
  --config=../tools/crd-ref-docs-config.yaml \
  --renderer=markdown \
  --output-path=../src/generated-crd-docs.md
```

## Next Steps

- [Contributing Guide](contributing.md) - How to contribute
- [Testing Locally](testing-locally.md) - Run tests
- [Provider Development](../providers/tutorial.md) - Build a provider
- [GitHub Repository](https://github.com/projectbeskar/virtrigaud) - Main project
