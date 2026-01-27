<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Creating Your First Virtual Machine

This guide walks you through creating a complete, working virtual machine from start to finish using VirtRigaud.

## Prerequisites

Before creating a VM, ensure you have:

- VirtRigaud installed in your Kubernetes cluster
- A configured provider (vSphere, Libvirt, or Proxmox)
- `kubectl` access to your cluster

## Overview

Creating a VM requires four resources:

1. **Provider** - Connection to your hypervisor
2. **VMClass** - VM size/specifications (CPU, memory)
3. **VMImage** - Operating system template
4. **VirtualMachine** - The actual VM instance

## Step 1: Create a Provider

First, create credentials for your hypervisor:

=== "vSphere"

    ```bash
    kubectl create secret generic vsphere-creds \
      --namespace default \
      --from-literal=endpoint=https://vcenter.example.com \
      --from-literal=username=administrator@vsphere.local \
      --from-literal=password=your-password \
      --from-literal=insecure=false
    ```

    Then create the Provider:

    ```yaml
    apiVersion: infra.virtrigaud.io/v1beta1
    kind: Provider
    metadata:
      name: vsphere-provider
      namespace: default
    spec:
      type: vsphere
      credentialsSecretRef:
        name: vsphere-creds
      config:
        datacenter: DC1
        datastore: datastore1
        network: "VM Network"
        resourcePool: /DC1/host/Cluster1/Resources
    ```

=== "Libvirt"

    ```bash
    kubectl create secret generic libvirt-creds \
      --namespace default \
      --from-literal=uri=qemu+ssh://root@hypervisor.example.com/system
    ```

    Then create the Provider:

    ```yaml
    apiVersion: infra.virtrigaud.io/v1beta1
    kind: Provider
    metadata:
      name: libvirt-provider
      namespace: default
    spec:
      type: libvirt
      credentialsSecretRef:
        name: libvirt-creds
      config:
        storagePool: default
        network: default
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

    Then create the Provider:

    ```yaml
    apiVersion: infra.virtrigaud.io/v1beta1
    kind: Provider
    metadata:
      name: proxmox-provider
      namespace: default
    spec:
      type: proxmox
      credentialsSecretRef:
        name: proxmox-creds
      config:
        node: pve1
        storage: local-lvm
        network: vmbr0
    ```

Apply the provider configuration:

```bash
kubectl apply -f provider.yaml
```

Verify the provider is ready:

```bash
kubectl get providers
# NAME               TYPE      READY   AGE
# vsphere-provider   vsphere   true    10s
```

## Step 2: Define a VM Class

Create a VM class that defines the size and specifications:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: small
  namespace: default
spec:
  hardware:
    cpus: 2
    memory: 4Gi
  policies:
    resources:
      requests:
        cpu: "1"
        memory: 2Gi
      limits:
        cpu: "2"
        memory: 4Gi
```

Apply the VM class:

```bash
kubectl apply -f vmclass.yaml
```

## Step 3: Define a VM Image

Create a VM image referencing your OS template:

=== "vSphere"

    ```yaml
    apiVersion: infra.virtrigaud.io/v1beta1
    kind: VMImage
    metadata:
      name: ubuntu-22
      namespace: default
    spec:
      providerRef:
        name: vsphere-provider
      osInfo:
        type: linux
        version: "22.04"
      source:
        type: template
        name: ubuntu-22.04-template
    ```

=== "Libvirt"

    ```yaml
    apiVersion: infra.virtrigaud.io/v1beta1
    kind: VMImage
    metadata:
      name: ubuntu-22
      namespace: default
    spec:
      providerRef:
        name: libvirt-provider
      osInfo:
        type: linux
        version: "22.04"
      source:
        type: url
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
      providerRef:
        name: proxmox-provider
      osInfo:
        type: linux
        version: "22.04"
      source:
        type: template
        id: 9000
    ```

Apply the VM image:

```bash
kubectl apply -f vmimage.yaml
```

## Step 4: Create the Virtual Machine

Now create your first VM:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: my-first-vm
  namespace: default
spec:
  providerRef:
    name: vsphere-provider  # or libvirt-provider, proxmox-provider
  classRef:
    name: small
  imageRef:
    name: ubuntu-22
  powerState: "On"
  network:
    hostname: my-first-vm
    interfaces:
      - name: eth0
        type: dhcp
```

Apply the VM configuration:

```bash
kubectl apply -f vm.yaml
```

## Step 5: Verify VM Creation

Watch the VM being created:

```bash
# Watch VM status
kubectl get vm my-first-vm -w

# Check detailed status
kubectl describe vm my-first-vm

# View VM events
kubectl get events --field-selector involvedObject.name=my-first-vm
```

Once the VM is ready, you should see:

```bash
NAME          PROVIDER           CLASS   IMAGE       POWER   READY   AGE
my-first-vm   vsphere-provider   small   ubuntu-22   On      True    2m
```

## Step 6: Access Your VM

Get the VM's IP address:

```bash
kubectl get vm my-first-vm -o jsonpath='{.status.network.ipAddress}'
```

Access the VM:

=== "SSH"

    ```bash
    ssh ubuntu@<vm-ip-address>
    ```

=== "Console (Libvirt)"

    ```bash
    # Get console access via VNC
    kubectl get vm my-first-vm -o jsonpath='{.status.console.vnc}'
    ```

## Complete Example

Here's a complete YAML file with all resources:

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
  credentialsSecretRef:
    name: vsphere-creds
  config:
    datacenter: DC1
    datastore: datastore1
    network: "VM Network"
    resourcePool: /DC1/host/Cluster1/Resources
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: small
  namespace: default
spec:
  hardware:
    cpus: 2
    memory: 4Gi
  policies:
    resources:
      requests:
        cpu: "1"
        memory: 2Gi
      limits:
        cpu: "2"
        memory: 4Gi
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-22
  namespace: default
spec:
  providerRef:
    name: vsphere-provider
  osInfo:
    type: linux
    version: "22.04"
  source:
    type: template
    name: ubuntu-22.04-template
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: my-first-vm
  namespace: default
spec:
  providerRef:
    name: vsphere-provider
  classRef:
    name: small
  imageRef:
    name: ubuntu-22
  powerState: "On"
  network:
    hostname: my-first-vm
    interfaces:
      - name: eth0
        type: dhcp
```

Save this to `complete-vm.yaml` and apply:

```bash
kubectl apply -f complete-vm.yaml
```

## Next Steps

Now that you've created your first VM, explore:

- [Advanced VM Operations](../examples/advanced/) - Snapshots, cloning, scaling
- [Provider-Specific Features](../providers/) - Provider capabilities
- [VM Lifecycle Management](../advanced-lifecycle/) - Managing VM states
- [Networking Configuration](../guides/networking/) - Advanced networking

## Troubleshooting

### VM Stuck in Pending

```bash
# Check provider status
kubectl describe provider vsphere-provider

# Check VM events
kubectl describe vm my-first-vm
```

### VM Not Getting IP Address

```bash
# Verify VMware Tools / guest agent is installed
kubectl get vm my-first-vm -o jsonpath='{.status.guestAgent}'

# Check network configuration
kubectl get vm my-first-vm -o yaml | yq '.spec.network'
```

### Authentication Errors

```bash
# Verify credentials secret
kubectl get secret vsphere-creds -o yaml

# Check provider logs
kubectl logs -n virtrigaud-system deployment/virtrigaud-manager | grep "my-first-vm"
```
