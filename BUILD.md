<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Building the Documentation

This directory contains the MkDocs configuration for the VirtRigaud documentation.

## Prerequisites

### Poetry (Python dependency manager)

```bash
# macOS/Linux
curl -sSL https://install.python-poetry.org | python3 -

# Or use pip
pip install poetry

# Or use your package manager
brew install poetry  # macOS
```

### Go (for CRD documentation generation)

```bash
# macOS
brew install go

# Linux (Debian/Ubuntu)
sudo apt-get install golang-go

# Or download from https://go.dev/dl/
```

Go 1.26 or higher is required: the generators run `go` against the pinned VirtRigaud release (v0.4.0 declares `go 1.26.10` in its `go.mod`).

The generators are Go tools pinned in `tools/tool-versions.env` (`crd-ref-docs`, `buf`, `protoc-gen-doc`); `make install-crd-tools` and `make install-proto-tools` install exactly those versions.

## Quick Start

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

## Building the Documentation

### Using Make (Recommended)

```bash
# Install Python dependencies
make install

# Install CRD generation tools (requires Go)
make install-crd-tools

# Install the gRPC reference tools, buf and protoc-gen-doc (requires Go)
make install-proto-tools

# Clone/update VirtRigaud at the release tag in VIRTRIGAUD_VERSION
make clone-virtrigaud

# Generate CRD documentation (src/references/generated-crd-docs.md)
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

The `make build` target:
1. Installs Python dependencies with Poetry
2. Clones/updates the VirtRigaud repository at the tag in `VIRTRIGAUD_VERSION`
3. Runs `crd-ref-docs` (`tools/gen-crd-docs.sh`) to regenerate the CRD reference
4. Runs `buf generate` with `protoc-gen-doc` (`tools/gen-proto-docs.sh`) to regenerate the gRPC reference from `provider.proto`
5. Builds the MkDocs site with all content

### Using Poetry directly

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

The build process automatically generates API reference documentation for VirtRigaud's Custom Resource Definitions (CRDs):

1. **Clones VirtRigaud repository** - Checks out the release tag pinned in `VIRTRIGAUD_VERSION` (CI does the same), so the reference never describes unreleased code
2. **Runs crd-ref-docs** (`tools/gen-crd-docs.sh`) - Extracts CRD schemas and generates markdown documentation
3. **Outputs to `src/references/generated-crd-docs.md`** - the page the navigation links to. The file is committed; regenerate and commit it when `VIRTRIGAUD_VERSION` changes

The gRPC reference `src/references/grpc-api.md` is generated the same way (`tools/gen-proto-docs.sh`, `make generate-proto-docs`) and is purely generated. The hand-written explanation lives in `src/references/grpc-api-guide.md`.

The generated pages describe the CRDs and gRPC contract of the pinned release (`VIRTRIGAUD_VERSION`), not of the VirtRigaud default branch. To document another release, change `VIRTRIGAUD_VERSION`, run `make generate-crds generate-proto-docs` and commit the regenerated pages.

## Structure

- `mkdocs.yml` - MkDocs configuration
- `tools/crd-ref-docs-config.yaml` - CRD documentation generation config
- `tools/buf.gen.docs.yaml` - buf template for gRPC API doc generation
- `tools/tool-versions.env` - pinned versions of `crd-ref-docs`, `buf` and `protoc-gen-doc` (read by the Makefile and by CI)
- `pyproject.toml` - Python dependencies (Poetry)
- `Makefile` - Build automation
- `src/` - All documentation markdown files
- `src/stylesheets/` - Custom CSS styles
- `VIRTRIGAUD_VERSION` - VirtRigaud release tag the reference pages are generated from
- `tools/gen-crd-docs.sh`, `tools/gen-proto-docs.sh` - generators used by both the Makefile and CI
- `src/references/generated-crd-docs.md`, `src/references/grpc-api.md` - Generated references (committed; do not hand-edit)
- `site/` - Build output (gitignored)
- `virtrigaud/` - Cloned VirtRigaud repo used by the generators (gitignored)
- `.github/workflows/` - CI/CD workflows

## Deployment

The documentation is automatically deployed to GitHub Pages when changes are pushed to the main branch. The workflow:

1. Checks out the VirtRigaud release tag in `VIRTRIGAUD_VERSION` (or the tag given to a manual run)
2. Generates the CRD reference with `crd-ref-docs`
3. Generates the gRPC reference with `buf` and `protoc-gen-doc`
4. Builds the MkDocs site with `--strict`
5. Deploys to GitHub Pages (only from the `main` branch)

A manual run of the workflow can document another release tag; started from a branch other than `main`, it builds but does not deploy.

## Live Development

When making changes to documentation files, run `make serve` to see changes in real-time at http://127.0.0.1:8000.

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
