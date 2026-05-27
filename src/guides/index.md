<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# VirtRigaud Provider Guides

This section provides step-by-step guides for working with VirtRigaud providers.

## What is a Provider?

A **Provider** is VirtRigaud's connection to your hypervisor infrastructure. It acts as a bridge between Kubernetes and your virtualization platform (vSphere, Libvirt/KVM, or Proxmox VE), translating Kubernetes resource definitions into actual virtual machines.

Think of providers as plugins that enable VirtRigaud to manage VMs on different platforms. Each provider:

- Authenticates with your hypervisor
- Translates VirtRigaud resource specs to platform-specific configurations
- Manages VM lifecycle (create, delete, power operations)
- Reports VM status back to Kubernetes

## Provider Architecture

VirtRigaud uses a **Remote Provider** architecture where each provider runs as an independent service:

```
┌─────────────────────────────────────────┐
│         Kubernetes Cluster               │
│  ┌──────────────────────────────────┐   │
│  │   VirtRigaud Manager             │   │
│  │   (Controller)                   │   │
│  └─────────┬────────────────────────┘   │
│            │ gRPC                        │
│            │                             │
│  ┌─────────▼────────────────────────┐   │
│  │   Provider Pod                   │   │
│  │   (vSphere/Libvirt/Proxmox)      │   │
│  └─────────┬────────────────────────┘   │
└────────────┼──────────────────────────────┘
             │ API calls
             │
        ┌────▼─────┐
        │Hypervisor│
        └──────────┘
```

**Benefits of this architecture:**

- **Isolation**: Provider failures don't crash the manager
- **Scalability**: Scale providers independently
- **Security**: Credentials stay in provider pods
- **Flexibility**: Mix multiple provider versions

## Supported Providers

| Provider | Status | Best For | Features |
|----------|--------|----------|----------|
| **vSphere** | Production | Enterprise environments | Full reconfiguration, snapshots, cloning, templates |
| **Libvirt** | Production | Development, edge computing | Cloud-init, VNC console, local/remote hosts |
| **Proxmox VE** | Production | Cost-effective virtualization | API token auth, guest agent, templates |

## Quick Start

Choose your provider and follow the setup guide:

1. **[vSphere Provider Guide](../providers/vsphere.md)** - For VMware vSphere environments
2. **[Libvirt Provider Guide](../providers/libvirt.md)** - For KVM/QEMU hosts
3. **[Proxmox Provider Guide](../providers/proxmox.md)** - For Proxmox VE clusters

Each guide covers:

- Prerequisites and requirements
- Authentication setup
- Provider configuration
- First VM creation
- Troubleshooting tips

## Provider Capabilities Matrix

Not all providers support the same features. See the [Provider Capabilities Matrix](../providers/providers-capabilities.md) for a detailed comparison.

This is an abbreviated summary for v0.3.6. For the full authoritative matrix, see [providers/providers-capabilities.md](../providers/providers-capabilities.md).

| Feature | vSphere | Libvirt | Proxmox |
|---------|---------|---------|---------|
| VM Creation | Yes | Yes | Yes |
| Power Management | Yes | Yes | Yes |
| Reconfiguration | Yes | Yes (offline) | Yes |
| Snapshots | Yes | Yes | Yes |
| Cloning | Yes | Stub (#153) | Yes |
| Console Access | Yes | Yes (VNC) | Yes (VNC) |
| Cloud-init | Yes | Yes | Yes |
| Migration (tested) | vSphere → Libvirt only | target only | — |

## Advanced Topics

Once you're comfortable with basic provider setup:

- **[Advanced VM Lifecycle](advanced/advanced-lifecycle.md)** - Snapshots, cloning, reconfiguration
- **[Nested Virtualization](advanced/nested-virtualization.md)** - Running hypervisors in VMs
- **[Graceful Shutdown](advanced/graceful-shutdown.md)** - Proper VM shutdown handling
- **[Remote Providers](advanced/remote-providers.md)** - Provider architecture deep dive

## Developing Custom Providers

Want to add support for a new hypervisor?

- **[Provider Development Tutorial](../providers/tutorial.md)** - Step-by-step guide
- **[Provider Versioning](../providers/versioning.md)** - Version management

## Multi-Provider Deployments

VirtRigaud can manage multiple providers simultaneously:

```yaml
# Production vSphere
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: vsphere-prod
spec:
  type: vsphere
  # ... vSphere config

---
# Development Libvirt
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: libvirt-dev
spec:
  type: libvirt
  # ... Libvirt config
```

Each VM can specify which provider to use via `spec.providerRef`.

## Security Considerations

When setting up providers, consider:

- **Credential management**: Use Kubernetes secrets, never hardcode credentials
- **Least privilege**: Grant minimal required permissions
- **Network isolation**: Use NetworkPolicies to restrict provider communication
- **Secret management**: Consider [External Secrets Operator](../providers/security/external-secrets.md)
- **mTLS**: Enable mutual TLS for production deployments

See the [Security Guide](../operations/security.md) for detailed recommendations.

!!! warning "v0.3.6 security gaps"
    mTLS between the manager and provider pods is not enforced in v0.3.6 ([#147](https://github.com/projectbeskar/virtrigaud/issues/147)); provider gRPC servers do not require authentication ([#148](https://github.com/projectbeskar/virtrigaud/issues/148)). Use Kubernetes NetworkPolicies to restrict who can reach provider pods until these are resolved. See [Network Policies](../providers/security/network-policies.md).

## Getting Help

- **[Provider Documentation](../providers/vsphere.md)** — vSphere, [Libvirt](../providers/libvirt.md), [Proxmox](../providers/proxmox.md)
- **[Troubleshooting](../getting-started/index.md#troubleshooting)** - Common issues
- **[Examples](../examples/index.md)** - Working configurations
- **[GitHub Issues](https://github.com/projectbeskar/virtrigaud/issues)** - Report bugs or request features

## Next Steps

1. Choose your provider from the list above
2. Follow the provider-specific setup guide
3. Create your [first VM](../getting-started/basic-vm-example.md)
4. Explore [advanced features](../advanced-lifecycle.md)
