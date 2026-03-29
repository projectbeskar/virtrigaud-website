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

Go 1.23 or higher is required for generating CRD documentation.

## Quick Start

```bash
# Install dependencies (Python and Go tools)
make install
make install-crd-tools

# Build the documentation (includes CRD generation)
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

The `make build` target automatically handles CRD generation by:
1. Installing Python dependencies with Poetry
2. Cloning/updating the VirtRigaud repository
3. Running `crd-ref-docs` to generate CRD documentation
4. Building the MkDocs site with all content

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

1. **Clones VirtRigaud repository** - Gets the latest CRD definitions from the main project
2. **Runs crd-ref-docs** - Extracts CRD schemas and generates markdown documentation
3. **Outputs to `src/generated-crd-docs.md`** - Creates a comprehensive API reference

This ensures the documentation always reflects the current CRD structure.

## Structure

- `mkdocs.yml` - MkDocs configuration
- `tools/crd-ref-docs-config.yaml` - CRD documentation generation config
- `tools/buf.gen.docs.yaml` - buf template for gRPC API doc generation
- `pyproject.toml` - Python dependencies (Poetry)
- `Makefile` - Build automation
- `src/` - All documentation markdown files
- `src/stylesheets/` - Custom CSS styles
- `src/generated-crd-docs.md` - Generated CRD API reference (not in git)
- `site/` - Build output (gitignored)
- `virtrigaud/` - Cloned VirtRigaud repo for CRD generation (gitignored)
- `.github/workflows/` - CI/CD workflows

## Deployment

The documentation is automatically deployed to GitHub Pages when changes are pushed to the main branch. The workflow:

1. Clones the VirtRigaud repository
2. Generates CRD documentation using `crd-ref-docs`
3. Builds the MkDocs site
4. Deploys to GitHub Pages

Manual deployment can be triggered via the GitHub Actions UI.

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
