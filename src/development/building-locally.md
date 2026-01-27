# Building VirtRigaud Locally

This guide covers building VirtRigaud from source and building the documentation.

## Building VirtRigaud Project

### Prerequisites

- **Go 1.23+** - [Download](https://go.dev/dl/)
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

# Install development dependencies
make dev-setup

# Build all binaries
make build

# Run tests
make test
```

### Build Targets

```bash
# Build manager
make build-manager

# Build specific provider
make build-provider-vsphere
make build-provider-libvirt
make build-provider-proxmox

# Build all providers
make build-providers

# Build everything
make build-all
```

### Container Images

```bash
# Build Docker images
make docker-build

# Build specific image
make docker-build-manager
make docker-build-provider-vsphere

# Push to registry
make docker-push

# Build and push
make docker-build docker-push
```

### Testing

```bash
# Run unit tests
make test

# Run with coverage
make test-coverage

# Run integration tests
make test-integration

# Run provider conformance tests
make test-vcts

# Lint code
make lint

# Format code
make fmt
```

## Building Documentation

The VirtRigaud documentation is built with MkDocs and includes auto-generated CRD reference documentation.

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

Go 1.23 or higher is required for generating CRD documentation.

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

The build process automatically generates API reference documentation for VirtRigaud's Custom Resource Definitions (CRDs):

1. **Clones VirtRigaud repository** - Gets the latest CRD definitions from the main project
2. **Runs crd-ref-docs** - Extracts CRD schemas and generates markdown documentation
3. **Outputs to `src/generated-crd-docs.md`** - Creates a comprehensive API reference

This ensures the documentation always reflects the current CRD structure.

## Project Structure

### VirtRigaud Repository

```
virtrigaud/
├── api/                    # API definitions (CRDs)
│   └── infra.virtrigaud.io/
│       └── v1beta1/       # API version
├── cmd/                    # Main applications
│   ├── manager/           # Controller manager
│   └── provider-*/        # Provider binaries
├── internal/              # Internal packages
│   ├── controllers/       # Kubernetes controllers
│   ├── providers/         # Provider implementations
│   └── webhooks/          # Admission webhooks
├── pkg/                   # Public libraries
├── config/               # Kustomize configs
├── charts/              # Helm charts
├── docs/                # Documentation source
└── test/                # Test suites
```

### Documentation Repository

```
virtrigaud-website/
├── mkdocs.yml                   # MkDocs configuration
├── crd-ref-docs-config.yaml    # CRD doc generation config
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

## Deployment

The documentation is automatically deployed to GitHub Pages when changes are pushed to the main branch. The workflow:

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
  --config=../crd-ref-docs-config.yaml \
  --renderer=markdown \
  --output-path=../src/generated-crd-docs.md
```

## Next Steps

- [Contributing Guide](contributing.md) - How to contribute
- [Testing Locally](testing-locally.md) - Run tests
- [Provider Development](../providers/tutorial.md) - Build a provider
- [GitHub Repository](https://github.com/projectbeskar/virtrigaud) - Main project
