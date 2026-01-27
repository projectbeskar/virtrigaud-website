<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Operations Guide

This section covers operational aspects of running VirtRigaud in production environments.

## Overview

Operating VirtRigaud involves monitoring, security, maintenance, and troubleshooting. This guide provides best practices and procedures for production deployments.

## Core Topics

### [Observability](observability.md)
Monitor VirtRigaud with metrics, logs, and alerts:

- Prometheus metrics integration
- Grafana dashboards
- Log aggregation
- Alert rules
- Performance monitoring

### [Security](security.md)
Secure your VirtRigaud deployment:

- RBAC configuration
- Secret management
- Network policies
- mTLS setup
- Security best practices

See also the [Security subsection](#security-configuration) below for detailed security configurations.

### [Resilience](resilience.md)
Build fault-tolerant VirtRigaud deployments:

- High availability setup
- Disaster recovery
- Backup strategies
- Failure scenarios
- Recovery procedures

### [Upgrade Guide](upgrade.md)
Safely upgrade VirtRigaud:

- Version compatibility
- Upgrade procedures
- CRD migrations
- Rollback strategies
- Breaking changes

## Infrastructure-Specific Topics

### [vSphere Hardware Versions](vsphere-hardware-version.md)
Manage VMware hardware compatibility:

- Hardware version selection
- Compatibility matrix
- Upgrade procedures
- Feature availability

### [Libvirt Host Preparation](libvirt-host-prepare.md)
Prepare hosts for Libvirt provider:

- Host requirements
- KVM configuration
- Network setup
- Storage configuration
- Security hardening

## Security Configuration

Detailed security configuration guides:

### [Bearer Token Authentication](../providers/security/bearer-token.md)
Configure token-based authentication:

- Token generation
- Token rotation
- Service accounts
- Token best practices

### [mTLS Configuration](../providers/security/mtls.md)
Enable mutual TLS:

- Certificate generation
- Certificate management
- Provider configuration
- Troubleshooting

### [External Secrets](../providers/security/external-secrets.md)
Integrate with secret management systems:

- External Secrets Operator
- Vault integration
- AWS Secrets Manager
- Secret rotation

### [Network Policies](../providers/security/network-policies.md)
Restrict network communication:

- Policy examples
- Provider isolation
- Egress rules
- Troubleshooting

## Production Checklist

Before deploying to production:

- [ ] **Monitoring**: Set up metrics and alerts
- [ ] **Security**: Configure RBAC and network policies
- [ ] **Secrets**: Use external secret management
- [ ] **High Availability**: Deploy with multiple replicas
- [ ] **Backups**: Configure backup procedures
- [ ] **Documentation**: Document your configuration
- [ ] **Testing**: Validate in staging environment
- [ ] **Runbooks**: Create incident response procedures

## Common Operational Tasks

### Scaling Providers

```bash
# Scale provider deployment
kubectl scale deployment vsphere-provider \
  -n virtrigaud-system \
  --replicas=3
```

### Rotating Credentials

```bash
# Update provider credentials
kubectl create secret generic vsphere-creds \
  --from-literal=password=new-password \
  --dry-run=client -o yaml | \
  kubectl apply -f -

# Restart provider to pick up new credentials
kubectl rollout restart deployment vsphere-provider \
  -n virtrigaud-system
```

### Checking Provider Health

```bash
# Check provider status
kubectl get providers

# Check provider pod status
kubectl get pods -n virtrigaud-system -l app=virtrigaud-provider

# View provider logs
kubectl logs -n virtrigaud-system \
  -l app=virtrigaud-provider \
  --tail=100
```

### Monitoring VM Operations

```bash
# List all VMs
kubectl get vms -A

# Watch VM status
kubectl get vms -w

# Check VM events
kubectl get events --field-selector involvedObject.kind=VirtualMachine
```

## Troubleshooting

### Manager Not Starting

```bash
# Check manager logs
kubectl logs -n virtrigaud-system deployment/virtrigaud-manager

# Check webhook configuration
kubectl get validatingwebhookconfigurations
kubectl get mutatingwebhookconfigurations

# Verify CRDs are installed
kubectl get crds | grep virtrigaud
```

### Provider Connection Issues

```bash
# Test provider connectivity
kubectl exec -n virtrigaud-system deployment/vsphere-provider -- \
  curl -k https://vcenter.example.com

# Check credentials
kubectl get secret vsphere-creds -o yaml

# Verify provider configuration
kubectl describe provider vsphere-provider
```

### VM Creation Failures

```bash
# Check VM status
kubectl describe vm my-vm

# Check provider logs
kubectl logs -n virtrigaud-system \
  -l app=virtrigaud-provider \
  --tail=100 | grep my-vm

# Check manager logs
kubectl logs -n virtrigaud-system deployment/virtrigaud-manager | grep my-vm
```

## Best Practices

### Resource Management

- Set appropriate resource requests/limits for providers
- Use PodDisruptionBudgets for manager and providers
- Configure autoscaling for high-load scenarios

### Security

- Use least-privilege RBAC roles
- Rotate credentials regularly
- Enable audit logging
- Use NetworkPolicies to restrict traffic
- Enable mTLS for provider communication

### Monitoring

- Set up Prometheus ServiceMonitor
- Configure alerting rules
- Create Grafana dashboards
- Enable structured logging
- Track key metrics (VM operations, errors, latency)

### High Availability

- Run manager with multiple replicas
- Deploy providers redundantly
- Use topology spread constraints
- Configure pod anti-affinity
- Test failover scenarios

## Performance Tuning

### Manager Optimization

```yaml
# Increase concurrent reconcilers
spec:
  template:
    spec:
      containers:
      - name: manager
        env:
        - name: MAX_CONCURRENT_RECONCILES
          value: "10"
```

### Provider Optimization

```yaml
# Tune provider connection pool
spec:
  template:
    spec:
      containers:
      - name: provider
        env:
        - name: MAX_CONNECTIONS
          value: "20"
        - name: CONNECTION_TIMEOUT
          value: "30s"
```

## Maintenance Windows

### Planning Maintenance

1. **Notify users** of maintenance window
2. **Scale down** non-critical workloads
3. **Backup** critical resources
4. **Test** in staging environment
5. **Execute** maintenance tasks
6. **Verify** system health
7. **Document** changes made

### During Maintenance

```bash
# Prevent new VM operations (example using labels)
kubectl label namespace production maintenance=true

# Drain nodes if needed
kubectl drain node-1 --ignore-daemonsets

# Perform upgrades
helm upgrade virtrigaud virtrigaud/virtrigaud \
  --namespace virtrigaud-system \
  --version 0.2.3

# Verify health
kubectl get pods -n virtrigaud-system
kubectl get vms -A
```

## Support and Resources

- **[GitHub Issues](https://github.com/projectbeskar/virtrigaud/issues)** - Report bugs
- **[Slack Channel](https://kubernetes.slack.com/messages/virtrigaud)** - Community support
- **[Documentation](https://projectbeskar.github.io/virtrigaud/)** - Comprehensive guides
- **[Security Guide](security.md)** - Security best practices
- **[Observability Guide](observability.md)** - Monitoring setup

## Next Steps

- Set up [observability](observability.md) for your deployment
- Configure [security](security.md) policies
- Plan for [high availability](resilience.md)
- Review the [upgrade guide](upgrade.md)
