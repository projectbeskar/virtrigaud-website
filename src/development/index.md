<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Development Guide

Welcome to the VirtRigaud development guide! This section provides information for developers who want to contribute to VirtRigaud or build custom providers.

## Quick Links

- **[GitHub Repository](https://github.com/projectbeskar/virtrigaud)** - Main project repository
- **[Building Locally](building-locally.md)** - Build VirtRigaud from source
- **[Contributing Guide](contributing.md)** - How to contribute
- **[Testing Locally](testing-locally.md)** - Test your changes
- **[Provider Development](../providers/tutorial.md)** - Create custom providers

## Getting Started with Development

### Prerequisites

To develop VirtRigaud, you'll need:

- **Go 1.23+** - Primary programming language
- **Docker** - For building container images
- **Kubernetes cluster** - kind, k3s, or remote cluster
- **kubectl** - Kubernetes CLI
- **Helm 3.x** - Package manager
- **make** - Build automation

### Quick Setup

```bash
# Clone the repository
git clone https://github.com/projectbeskar/virtrigaud.git
cd virtrigaud

# Install development dependencies
make dev-setup

# Run tests
make test

# Build binaries
make build
```

## Development Workflows

### Making Code Changes

1. **Fork and clone** the repository
2. **Create a branch** for your changes
3. **Make your changes** with tests
4. **Run tests** locally
5. **Submit a pull request**

See the [Contributing Guide](contributing.md) for detailed instructions.

### API Development

When modifying API types (CRDs):

```bash
# Edit API types
vim api/infra.virtrigaud.io/v1beta1/virtualmachine_types.go

# Generate code and sync CRDs
make generate
make sync-helm-crds

# Verify everything is in sync
make verify-helm-crds
```

### Provider Development

Creating a new provider for a hypervisor platform:

1. **Read the** [Provider Development Tutorial](../providers/tutorial.md)
2. **Implement the** Provider interface
3. **Add tests** and documentation
4. **Submit for** provider catalog inclusion

## Project Structure

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
│   ├── grpc/             # gRPC interfaces
│   └── contracts/        # Provider contracts
├── config/               # Kustomize configs
│   ├── crd/             # CRD definitions
│   ├── manager/         # Manager deployment
│   └── webhook/         # Webhook configs
├── charts/              # Helm charts
│   └── virtrigaud/      # Main Helm chart
├── docs/                # Documentation source
└── test/                # Test suites
```

## Building and Testing

### Build Commands

```bash
# Build all binaries
make build

# Build specific component
make build-manager
make build-provider-vsphere

# Build container images
make docker-build
make docker-push

# Build Helm chart
make helm-package
```

### Testing Commands

```bash
# Run unit tests
make test

# Run integration tests
make test-integration

# Run provider conformance tests
make test-vcts

# Run with coverage
make test-coverage

# Lint code
make lint

# Format code
make fmt
```

See [Testing Locally](testing-locally.md) for more details.

## Documentation

### Building Documentation

This documentation site is built with MkDocs. To build locally:

```bash
# Install dependencies
make install

# Install CRD documentation tools
make install-crd-tools

# Build documentation
make build

# Serve with live reload
make serve
```

See [Building Locally](building-locally.md) for more information.

### Documentation Structure

```
docs/
├── getting-started/     # Getting started guides
├── guides/             # Provider guides
├── providers/          # Provider documentation
├── examples/           # Example configurations
├── api-reference/      # API documentation
└── development/        # This section
```

## Release Process

VirtRigaud follows semantic versioning (semver):

- **Major** (v1.0.0): Breaking changes
- **Minor** (v0.2.0): New features, backwards compatible
- **Patch** (v0.2.1): Bug fixes

### Creating a Release

1. Update version in relevant files
2. Generate changelog
3. Create git tag
4. Build and publish artifacts
5. Update Helm chart repository

See the [Release Guide](https://github.com/projectbeskar/virtrigaud/blob/main/docs/releases.md) for details.

## Community

### Getting Help

- **[GitHub Issues](https://github.com/projectbeskar/virtrigaud/issues)** - Bug reports, feature requests
- **[GitHub Discussions](https://github.com/projectbeskar/virtrigaud/discussions)** - Questions, ideas
- **[Slack Channel](https://kubernetes.slack.com/messages/virtrigaud)** - Real-time chat
- **[Contributing Guide](contributing.md)** - How to contribute

### Code of Conduct

VirtRigaud follows the CNCF Code of Conduct. Be respectful and inclusive.

## Developer Resources

### Key Documentation

- **[Provider Contract](../providers/tutorial.md)** - Provider interface specification
- **[API Reference](../references/crds.md)** - CRD specifications
- **[Architecture](../remote-providers.md)** - System architecture
- **[Security](../operations/security.md)** - Security considerations

### Tools and Libraries

- **controller-runtime** - Kubernetes controller framework
- **gRPC** - Provider communication protocol
- **Kubebuilder** - CRD and controller scaffolding
- **Helm** - Package management
- **MkDocs** - Documentation generation

## Next Steps

- **[Set up your development environment](building-locally.md)**
- **[Read the contributing guide](contributing.md)**
- **[Run tests locally](testing-locally.md)**
- **[Build a custom provider](../providers/tutorial.md)**
- **[Join the community](https://github.com/projectbeskar/virtrigaud)**
