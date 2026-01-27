<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VirtRigaud Documentation Website

This repository contains the source code for the [VirtRigaud documentation website](https://projectbeskar.github.io/virtrigaud/), built with [MkDocs](https://www.mkdocs.org/) and the [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/) theme.

## What is VirtRigaud?

VirtRigaud is a Kubernetes operator for managing virtual machines across multiple hypervisors including vSphere, Libvirt/KVM, and Proxmox VE. For the main project repository, see [projectbeskar/virtrigaud](https://github.com/projectbeskar/virtrigaud).

## Prerequisites

- Python 3.8 or higher
- [Poetry](https://python-poetry.org/) (Python dependency manager)
- [Go](https://go.dev/) 1.23 or higher (required for CRD documentation generation)

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
# Install dependencies
make install

# Serve with live reload for development (http://127.0.0.1:8000)
make serve

# Build the static site
make build
```

## Building the Documentation

### Using Make (Recommended)

```bash
# Install dependencies
make install

# Install CRD generation tools (requires Go)
make install-crd-tools

# Generate CRD documentation from VirtRigaud repository
make generate-crds

# Build the documentation (automatically generates CRDs)
make build

# Serve with live reload for development
make serve

# Clean generated files (including cloned repo and generated CRDs)
make clean

# Run linting checks
make lint
```

The `make build` target automatically:
1. Installs Python dependencies
2. Clones/updates the VirtRigaud repository
3. Generates CRD documentation using `crd-ref-docs`
4. Builds the MkDocs site

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
├── book.toml               # mdBook configuration (alternative)
├── pyproject.toml          # Python dependencies (Poetry)
├── Makefile                # Build automation
├── src/                    # Documentation markdown files
│   ├── README.md           # Homepage
│   ├── getting-started/    # Getting started guides
│   ├── providers/          # Provider-specific documentation
│   ├── examples/           # Configuration examples
│   └── ...                 # Other documentation files
├── theme/                  # Custom theme assets
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

1. Clones the main VirtRigaud repository
2. Generates CRD documentation using `crd-ref-docs`
3. Builds the MkDocs site
4. Deploys to GitHub Pages

Manual deployment can be triggered via the GitHub Actions UI.

## Related Links

- [VirtRigaud Main Repository](https://github.com/projectbeskar/virtrigaud) - The operator source code
- [Live Documentation](https://projectbeskar.github.io/virtrigaud/) - Published documentation site
- [MkDocs Documentation](https://www.mkdocs.org/) - MkDocs reference
- [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/) - Theme documentation

## Contributing

Contributions are welcome! Please see the main project's [contributing guidelines](https://github.com/projectbeskar/virtrigaud/blob/main/CONTRIBUTING.md).

## License

This documentation is licensed under Apache License 2.0. See the main project's [LICENSE](https://github.com/projectbeskar/virtrigaud/blob/main/LICENSE) for details.
