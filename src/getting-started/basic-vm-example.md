<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Creating Your First Virtual Machine

This guide walks through creating a complete, working virtual machine from start to finish using VirtRigaud v0.3.8.

## Prerequisites

- VirtRigaud v0.3.8 installed in your Kubernetes cluster
- A configured Provider (vSphere, Libvirt, or Proxmox)
- `kubectl` access to your cluster

## Overview

Creating a VM requires four resources in order:

1. **Provider** — connection to your hypervisor
2. **VMClass** — VM size/specifications (CPU, memory)
3. **VMImage** — operating system template
4. **VirtualMachine** — the actual VM instance

## Step 1: Create a Provider

Create credentials for your hypervisor, then create the Provider CR.

=== "vSphere"

    ```bash
    kubectl create secret generic vsphere-creds \
      --namespace default \
      --from-literal=endpoint=https://vcenter.example.com \
      --from-literal=username=administrator@vsphere.local \
      --from-literal=password=your-password \
      --from-literal=insecure=false
    ```

    ```yaml
    apiVersion: infra.virtrigaud.io/v1beta1
    kind: Provider
    metadata:
      name: vsphere-provider
      namespace: default
    spec:
      type: vsphere
      endpoint: https://vcenter.example.com
      credentialSecretRef:
        name: vsphere-creds
        namespace: default
      runtime:
        mode: Remote
        image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.3.8"
        service:
          port: 9090
    ```

=== "Libvirt"

    ```bash
    kubectl create secret generic libvirt-creds \
      --namespace default \
      --from-literal=uri=qemu+ssh://root@hypervisor.example.com/system \
      --from-literal=privateKey="$(cat ~/.ssh/id_rsa)"
    ```

    ```yaml
    apiVersion: infra.virtrigaud.io/v1beta1
    kind: Provider
    metadata:
      name: libvirt-provider
      namespace: default
    spec:
      type: libvirt
      endpoint: qemu+ssh://root@hypervisor.example.com/system
      credentialSecretRef:
        name: libvirt-creds
        namespace: default
      runtime:
        mode: Remote
        image: "ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.3.8"
        service:
          port: 9090
    ```

=== "Proxmox"

    ```bash
    kubectl create secret generic proxmox-creds \
      --namespace default \
      --from-literal=endpoint=https://proxmox.example.com:8006 \
      --from-literal=tokenID=user@pam!token \
      --from-literal=secret=your-token-secret \
      --from-literal=insecure=false
    ```

    ```yaml
    apiVersion: infra.virtrigaud.io/v1beta1
    kind: Provider
    metadata:
      name: proxmox-provider
      namespace: default
    spec:
      type: proxmox
      endpoint: https://proxmox.example.com:8006
      credentialSecretRef:
        name: proxmox-creds
        namespace: default
      runtime:
        mode: Remote
        image: "ghcr.io/projectbeskar/virtrigaud/provider-proxmox:v0.3.8"
        service:
          port: 9090
    ```

Apply and verify:

```bash
kubectl apply -f provider.yaml
kubectl get providers
# NAME               TYPE      READY   AGE
# vsphere-provider   vsphere   true    10s
```

!!! note "TLS block required"
    Production Provider CRs must include a `spec.runtime.service.tls` block
    (required since v0.3.7). The abbreviated examples above omit it for
    readability; see the [15-Minute Quickstart](index.md#step-3-configure-a-provider)
    for a complete Provider CR with TLS configured.

## Step 2: Define a VM Class

`spec.cpu` is an integer (number of vCPUs). `spec.memory` is a Kubernetes resource quantity.

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: small
  namespace: default
spec:
  cpu: 2
  memory: 4Gi
```

```bash
kubectl apply -f vmclass.yaml
```

## Step 3: Define a VM Image

Reference your OS template or image URL. The source structure is provider-specific.

=== "vSphere"

    ```yaml
    apiVersion: infra.virtrigaud.io/v1beta1
    kind: VMImage
    metadata:
      name: ubuntu-22
      namespace: default
    spec:
      source:
        vsphere:
          templateName: ubuntu-22.04-template
    ```

=== "Libvirt"

    ```yaml
    apiVersion: infra.virtrigaud.io/v1beta1
    kind: VMImage
    metadata:
      name: ubuntu-22
      namespace: default
    spec:
      source:
        libvirt:
          url: https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
    ```

=== "Proxmox"

    ```yaml
    apiVersion: infra.virtrigaud.io/v1beta1
    kind: VMImage
    metadata:
      name: ubuntu-22
      namespace: default
    spec:
      source:
        proxmox:
          templateId: 9000
    ```

```bash
kubectl apply -f vmimage.yaml
```

## Step 4: Create the Virtual Machine

Network attachments are listed under `spec.networks[]`. Each entry references a `VMNetworkAttachment` CR via `networkRef`. If `networkRef` is omitted, the VM template's pre-configured network adapter is used.

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: my-first-vm
  namespace: default
spec:
  providerRef:
    name: vsphere-provider   # or libvirt-provider, proxmox-provider
    namespace: default
  classRef:
    name: small
    namespace: default
  imageRef:
    name: ubuntu-22
    namespace: default
  powerState: "On"
  networks:
  - name: default
```

```bash
kubectl apply -f vm.yaml
```

## Step 5: Verify VM Creation

```bash
# Watch VM status
kubectl get vm my-first-vm -w

# Detailed status
kubectl describe vm my-first-vm

# VM events
kubectl get events --field-selector involvedObject.name=my-first-vm
```

Once the VM is ready:

```
NAME          PROVIDER           CLASS   IMAGE       PHASE     AGE
my-first-vm   vsphere-provider   small   ubuntu-22   Running   2m
```

!!! note "Phase column for adopted VMs"
    VMs auto-adopted by the VMAdoption controller (watching Provider CRs annotated `virtrigaud.io/adopt-vms: "true"`) may show an empty `phase` column. This is a known gap (issue I2); `status.ips` is still populated correctly.

## Step 6: Access Your VM

```bash
# Get the VM's IP addresses
kubectl get vm my-first-vm -o jsonpath='{.status.ips}'

# Get console URL (provider-dependent)
kubectl get vm my-first-vm -o jsonpath='{.status.consoleURL}'
```

=== "SSH"

    ```bash
    ssh ubuntu@<vm-ip-address>
    ```

=== "Console (Libvirt)"

    ```bash
    # VNC address is in status.consoleURL
    kubectl get vm my-first-vm -o jsonpath='{.status.consoleURL}'
    ```

## Complete Example

All resources in one file:

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-creds
  namespace: default
type: Opaque
stringData:
  endpoint: https://vcenter.example.com
  username: administrator@vsphere.local
  password: your-password
  insecure: "false"
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: vsphere-provider
  namespace: default
spec:
  type: vsphere
  endpoint: https://vcenter.example.com
  credentialSecretRef:
    name: vsphere-creds
    namespace: default
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.3.8"
    service:
      port: 9090
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: small
  namespace: default
spec:
  cpu: 2
  memory: 4Gi
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-22
  namespace: default
spec:
  source:
    vsphere:
      templateName: ubuntu-22.04-template
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: my-first-vm
  namespace: default
spec:
  providerRef:
    name: vsphere-provider
    namespace: default
  classRef:
    name: small
    namespace: default
  imageRef:
    name: ubuntu-22
    namespace: default
  powerState: "On"
  networks:
  - name: default
```

```bash
kubectl apply -f complete-vm.yaml
```

## Next Steps

- [Advanced VM Operations](../examples/) — Snapshots, cloning (VMClone MVP in v0.3.8)
- [Provider Capabilities](../providers/providers-capabilities.md) — per-provider feature matrix
- [Observability Guide](../operations/observability.md) — dashboards and alerting

## Troubleshooting

### VM Stuck in Pending

```bash
# Check provider status and circuit breaker
kubectl describe provider vsphere-provider
kubectl describe vm my-first-vm
```

If `virtrigaud_circuit_breaker_state{provider="vsphere-provider"} 2`, the provider is unreachable. See [Resilience](../operations/resilience.md).

### VM Not Getting IP Address

```bash
# Check IPs in status
kubectl get vm my-first-vm -o jsonpath='{.status.ips}'

# Verify VMware Tools / guest agent is installed and the VM is actually running
kubectl get vm my-first-vm -o jsonpath='{.status.powerState}'
```

`virtrigaud_ip_discovery_duration_seconds` on `/metrics` tracks how long the no-IPs → has-IPs transition takes per provider type.

### Authentication Errors

```bash
# Verify the credentials secret exists and has the expected keys
kubectl get secret vsphere-creds -o yaml

# Check provider pod logs
kubectl logs -n virtrigaud-system -l app.kubernetes.io/component=provider-vsphere
```
