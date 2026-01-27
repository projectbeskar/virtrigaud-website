# VirtRigaud Documentation

Welcome to the VirtRigaud documentation. VirtRigaud is a Kubernetes operator for managing virtual machines across multiple hypervisors including vSphere, Libvirt/KVM, and Proxmox VE.

## Quick Navigation

### Getting Started
- [15-Minute Quickstart](getting-started/index.md) - Get up and running quickly
- [Installation Guide](getting-started/install-helm-only.md) - Helm installation instructions
- [Basic VM Example](getting-started/basic-vm-example.md) - Create your first VM
- [Helm CRD Upgrades](getting-started/helm-crd-upgrades.md) - Managing CRD updates

### Guides
- [Provider Guides](guides/index.md) - Overview and provider setup
- [Provider Capabilities Matrix](providers/providers-capabilities.md) - Feature comparison
- [Advanced Topics](guides/advanced/advanced-lifecycle.md) - Advanced VM operations

### Provider-Specific Guides
- [vSphere Provider](providers/vsphere.md) - VMware vCenter/ESXi integration
- [Libvirt Provider](providers/libvirt.md) - KVM/QEMU virtualization
- [Proxmox VE Provider](providers/proxmox.md) - Proxmox Virtual Environment
- [Provider Tutorial](providers/tutorial.md) - Build your own provider
- [Provider Versioning](providers/versioning.md) - Version management

### Advanced Topics
- [VM Lifecycle Management](guides/advanced/advanced-lifecycle.md) - Advanced VM operations
- [Nested Virtualization](guides/advanced/nested-virtualization.md) - Run hypervisors in VMs
- [Graceful Shutdown](guides/advanced/graceful-shutdown.md) - Proper VM shutdown handling
- [VM Snapshots](guides/advanced/advanced-lifecycle.md#snapshots) - Backup and restore
- [Remote Providers](guides/advanced/remote-providers.md) - Provider architecture

### Operations
- [Overview](operations/index.md) - Operations guide
- [Observability](operations/observability.md) - Monitoring and metrics
- [Security](operations/security.md) - Security best practices
- [Resilience](operations/resilience.md) - High availability and fault tolerance
- [Upgrade Guide](operations/upgrade.md) - Version upgrade procedures
- [vSphere Hardware Versions](operations/vsphere-hardware-version.md) - Hardware compatibility

### Security Configuration
- [Bearer Token Authentication](providers/security/bearer-token.md)
- [mTLS Configuration](providers/security/mtls.md)
- [External Secrets](providers/security/external-secrets.md)
- [Network Policies](providers/security/network-policies.md)

### References
- [Custom Resource Definitions](references/crds.md) - Complete API reference
- [CLI Tools Reference](references/cli-tools.md) - Command-line interface guide
- [CLI API Reference](api-reference/cli.md) - Detailed CLI documentation
- [Metrics Catalog](api-reference/metrics.md) - Available metrics
- [Provider Catalog](references/catalog.md) - Available providers

### Development
- [Overview](development/index.md) - Development guide
- [Building Locally](development/building-locally.md) - Build from source
- [Contributing Guide](development/contributing.md) - Contribution guidelines
- [Testing Locally](development/testing-locally.md) - Local testing

### Examples Directory
- [Example README](examples/index.md) - Overview of all examples
- [Complete Examples](examples/) - Working configuration files
- [Advanced Examples](examples/advanced/) - Complex scenarios
- [Security Examples](examples/security/) - Security configurations

## Version Information

This documentation covers **VirtRigaud v0.2.3**.

### Recent Changes
- **v0.2.3**: Provider feature parity - Reconfigure, Clone, TaskStatus, ConsoleURL
- **v0.2.2**: Nested virtualization, TPM support, snapshot management
- **v0.2.1**: Critical fixes and documentation updates
- **v0.2.0**: Production-ready vSphere and Libvirt providers

See [CHANGELOG.md](https://github.com/projectbeskar/virtrigaud/blob/main/CHANGELOG.md) for complete version history.

## Provider Status

| Provider | Status | Maturity | Documentation |
|----------|--------|----------|---------------|
| vSphere | Production Ready | Stable | [Guide](providers/vsphere.md) |
| Libvirt/KVM | Production Ready | Stable | [Guide](providers/libvirt.md) |
| Proxmox VE | Production Ready | Beta | [Guide](providers/proxmox.md) |
| Mock | Complete | Testing | [providers/tutorial.md](providers/tutorial.md) |

## Support

- **GitHub Issues**: [github.com/projectbeskar/virtrigaud/issues](https://github.com/projectbeskar/virtrigaud/issues)
- **Discussions**: [github.com/projectbeskar/virtrigaud/discussions](https://github.com/projectbeskar/virtrigaud/discussions)
- **Slack**: #virtrigaud on Kubernetes Slack

## Quick Links

- [Main README](https://github.com/projectbeskar/virtrigaud#readme) - Project overview
- [CHANGELOG](https://github.com/projectbeskar/virtrigaud/blob/main/CHANGELOG.md) - Version history
- [Contributing](https://github.com/projectbeskar/virtrigaud/blob/main/CONTRIBUTING.md) - How to contribute
- [License](https://github.com/projectbeskar/virtrigaud/blob/main/LICENSE) - Apache License 2.0
