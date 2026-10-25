<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VirtRigaud Documentation Website

This repository contains the source code for the [VirtRigaud documentation website](https://projectbeskar.github.io/virtrigaud/), built with [MkDocs](https://www.mkdocs.org/) and the [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/) theme.

## What is VirtRigaud?

VirtRigaud is a Kubernetes operator for managing virtual machines across multiple hypervisors including vSphere, Libvirt/KVM, and Proxmox VE. For the main project repository, see [projectbeskar/virtrigaud](https://github.com/projectbeskar/virtrigaud).

## Prerequisites

- Python 3.9 or higher
- [Poetry](https://python-poetry.org/) (Python dependency manager)
- [Go](https://go.dev/) 1.26.10 or newer, the version the documented release's `go.mod` requires (required for the CRD and gRPC reference generation; with the default `GOTOOLCHAIN=auto`, an older `go` downloads it)

Install Poetry:

```bash
# macOS/Linux
curl -sSL https://install.python-poetry.org | python3 -

# Or use pip
pip install poetry

# Or use your package manager
brew install poetry  # macOS
```

## Quick Start

```bash
# Install Python dependencies and the pinned Go generator tools
make install
make install-crd-tools
make install-proto-tools

# Build the static site (clones VirtRigaud at the tag in VIRTRIGAUD_VERSION,
# regenerates the CRD and gRPC reference pages, then runs mkdocs)
make build

# Serve with live reload for development (http://127.0.0.1:8000)
make serve
```

## Building the Documentation

### Using Make (Recommended)

```bash
# Install dependencies
make install

# Install CRD generation tools (requires Go)
make install-crd-tools

# Install gRPC reference tools, buf and protoc-gen-doc (requires Go)
make install-proto-tools

# Generate CRD documentation from the VirtRigaud release in VIRTRIGAUD_VERSION
make generate-crds

# Generate the gRPC API reference
make generate-proto-docs

# Build the documentation (automatically generates both references)
make build

# Same, but fail on warnings (CI builds with --strict)
make build-strict

# Serve with live reload for development
make serve

# Remove site/, .cache/ and the cloned virtrigaud/ (the committed generated pages are kept)
make clean

# Run linting checks
make lint
```

The `make build` target:
1. Installs Python dependencies
2. Clones/updates the VirtRigaud repository at the tag in `VIRTRIGAUD_VERSION`
3. Generates the CRD reference using `crd-ref-docs`
4. Generates the gRPC reference using `buf` and `protoc-gen-doc`
5. Builds the MkDocs site

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

## Repository Structure

```
.
├── mkdocs.yml              # MkDocs configuration
├── pyproject.toml          # Python dependencies (Poetry)
├── Makefile                # Build automation
├── VIRTRIGAUD_VERSION      # VirtRigaud release tag the reference pages describe
├── tools/                  # Reference generators (gen-*.sh), their configs and pinned tool versions
├── src/                    # Documentation markdown files
│   ├── index.md            # Homepage
│   ├── getting-started/    # Getting started guides
│   ├── providers/          # Provider-specific documentation
│   ├── examples/           # Configuration examples
│   ├── stylesheets/        # Custom CSS
│   └── ...                 # Other documentation files
├── site/                   # Build output (generated, gitignored)
└── .github/workflows/      # CI/CD automation
```

## Development

When making changes to documentation:

1. Run `make serve` to start the development server
2. Navigate to http://127.0.0.1:8000
3. Edit files in the `src/` directory
4. Changes will automatically reload in your browser

The site features:
- Live reload on file changes
- Full-text search
- Dark/light theme toggle
- Mobile-responsive design
- Code syntax highlighting
- Mermaid diagram support

## Adding New Pages

1. Create a new markdown file in the `src/` directory
2. Add an entry to the `nav` section in `mkdocs.yml`
3. The page will be included in the next build

## Deployment

The documentation is automatically deployed to GitHub Pages when changes are pushed to the `main` branch. The CI/CD workflow:

1. Checks out the VirtRigaud release tag in `VIRTRIGAUD_VERSION` (never the default branch, so unreleased behaviour does not reach the site)
2. Generates the CRD reference using `crd-ref-docs`
3. Generates the gRPC reference using `buf` and `protoc-gen-doc`
4. Builds the MkDocs site with `--strict`
5. Deploys to GitHub Pages

To document another release, change `VIRTRIGAUD_VERSION`, regenerate the two reference pages and commit them. A manual run of the workflow accepts a release tag; it deploys only when started from `main`.

## Related Links

- [VirtRigaud Main Repository](https://github.com/projectbeskar/virtrigaud) - The operator source code
- [Live Documentation](https://projectbeskar.github.io/virtrigaud/) - Published documentation site
- [MkDocs Documentation](https://www.mkdocs.org/) - MkDocs reference
- [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/) - Theme documentation

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for this documentation repository and the main project's [contributing guidelines](https://github.com/projectbeskar/virtrigaud/blob/main/CONTRIBUTING.md) for the operator code.

## License

This documentation is licensed under Apache License 2.0. See the main project's [LICENSE](https://github.com/projectbeskar/virtrigaud/blob/main/LICENSE) for details.
