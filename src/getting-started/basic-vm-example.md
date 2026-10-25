<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Creating Your First Virtual Machine

This guide walks through creating a complete, working virtual machine from start to finish using VirtRigaud v0.4.0.

## Prerequisites

- VirtRigaud v0.4.0 installed in your Kubernetes cluster
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
      --from-literal=username=administrator@vsphere.local \
      --from-literal=password=your-password
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
      runtime:
        mode: Remote
        image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.0"
        service:
          port: 9090
          tls:
            enabled: true
            secretRef:
              name: provider-vsphere-tls
    ```

    The vCenter account needs **Virtual machine > Change Configuration > Advanced
    configuration** (`VirtualMachine.Config.AdvancedConfig`): every `Create` and
    `Clone` writes an owner stamp into the VM's extra configuration. `VMImage`
    `templateName` must name a real vSphere template, not a regular VM.

=== "Libvirt"

    The libvirt provider connects over SSH. The Secret holds `username`, either
    `ssh-privatekey` or `password`, and a `known_hosts` entry for the host (host-key
    verification is on by default; there is no trust-on-first-use).

    ```bash
    kubectl create secret generic libvirt-creds \
      --namespace default \
      --from-literal=username=virtrigaud \
      --from-file=ssh-privatekey=$HOME/.ssh/id_ed25519 \
      --from-file=known_hosts=<(ssh-keyscan -t ed25519 hypervisor.example.com)
    ```

    ```yaml
    apiVersion: infra.virtrigaud.io/v1beta1
    kind: Provider
    metadata:
      name: libvirt-provider
      namespace: default
    spec:
      type: libvirt
      endpoint: qemu+ssh://virtrigaud@hypervisor.example.com/system
      credentialSecretRef:
        name: libvirt-creds
      runtime:
        mode: Remote
        image: "ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.4.0"
        service:
          port: 9090
          tls:
            enabled: true
            secretRef:
              name: provider-libvirt-tls
    ```

    Prepare each libvirt host once, as root, or every create fails with
    `refusing to stage cloud-init data`:

    ```bash
    install -d -m 0711 -o virtrigaud -g virtrigaud /var/lib/libvirt/virtrigaud-seeds
    ```

    See the [Libvirt provider page](../providers/libvirt.md) for the other host requirements.

=== "Proxmox"

    ```bash
    kubectl create secret generic proxmox-creds \
      --namespace default \
      --from-literal=token_id='virtrigaud@pve!vrtg-token' \
      --from-literal=token_secret=your-token-secret
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
      runtime:
        mode: Remote
        image: "ghcr.io/projectbeskar/virtrigaud/provider-proxmox:v0.4.0"
        service:
          port: 9090
          tls:
            enabled: true
            secretRef:
              name: provider-proxmox-tls
    ```

Apply and verify:

```bash
kubectl apply -f provider.yaml
kubectl get providers
# NAME               TYPE      ENDPOINT                      HEALTHY   CONNECTED VMS   AGE
# vsphere-provider   vsphere   https://vcenter.example.com   true      0               10s
```

!!! note "TLS block required"
    Every Provider CR needs a `spec.runtime.service.tls` block (required since v0.3.7); a
    Provider without it does not reconcile (`TLSConfigured=False, Reason=TLSBlockMissing`).
    With `tls.enabled: true` the Secret named by `secretRef` must exist in the Provider's
    namespace and hold `tls.crt`, `tls.key` and `ca.crt` (see
    [mTLS Configuration](../providers/security/mtls.md)). For a throwaway lab only,
    `tls.enabled: false` is an explicit plaintext opt-out. The
    [15-Minute Quickstart](index.md#step-3-configure-a-provider) has complete examples.

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
          templateID: 9000
          node: pve1
    ```

```bash
kubectl apply -f vmimage.yaml
```

## Step 4: Create the Virtual Machine

Network attachments are listed under `spec.networks[]`. Each entry may reference a `VMNetworkAttachment` CR via `networkRef`. If `networkRef` is omitted, vSphere and Proxmox use the template's pre-configured network adapter, and a libvirt VM gets a user-mode interface with no libvirt-managed DHCP lease. To put a libvirt VM on libvirt's `default` network, create a `VMNetworkAttachment` and reference it:

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMNetworkAttachment
metadata:
  name: kvm-default-network
  namespace: default
spec:
  network:
    type: bridged
    libvirt:
      networkName: default
      model: virtio
  ipAllocation:
    type: DHCP
```

```yaml
# in the VirtualMachine spec
  networks:
  - name: default
    networkRef:
      name: kvm-default-network
      namespace: default
```

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
  userData:
    cloudInit:
      inline: |
        #cloud-config
        users:
          - name: ubuntu
            sudo: ALL=(ALL) NOPASSWD:ALL
            ssh_authorized_keys:
              - ssh-ed25519 AAAAC3... your-public-key
  networks:
  - name: default
```

```bash
kubectl apply -f vm.yaml
```

!!! warning "Give a libvirt VM its own login"
    A libvirt VM created without `spec.userData` gets no default user, SSH key or
    sudo (changed after v0.3.11). Supply `spec.userData` as above or you cannot log in.

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
NAME          PHASE     PROVIDER           CLASS   IMAGE       IPS            AGE
my-first-vm   Running   vsphere-provider   small   ubuntu-22   192.0.2.50     2m
```

`status.phase` is set on every status write and is never empty: `Pending`, `Provisioning`, `Running`, `Stopped`, `Reconfiguring`, `Deleting` or `Failed`. The `Ready`, `Provisioning`, `Reconfiguring` and `Placed` conditions carry the reason; every phase, condition and reason is explained in the [VM Status Reference](../guides/vm-status.md).

## Step 6: Access Your VM

```bash
# Get the VM's IP addresses
kubectl get vm my-first-vm -o jsonpath='{.status.ips}'

# Get console URL (provider-dependent)
kubectl get vm my-first-vm -o jsonpath='{.status.consoleURL}'
```

`status.ips` lists only addresses a client can reach (loopback, link-local and similar addresses are dropped). It needs VMware Tools (vSphere) or the QEMU guest agent (Proxmox, libvirt) in the guest; a libvirt guest on a libvirt-managed network also shows its DHCP lease without the agent.

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
  username: administrator@vsphere.local
  password: your-password
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
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.0"
    service:
      port: 9090
      tls:
        enabled: true
        secretRef:
          name: provider-vsphere-tls   # Secret with tls.crt, tls.key, ca.crt
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
  userData:
    cloudInit:
      inline: |
        #cloud-config
        users:
          - name: ubuntu
            sudo: ALL=(ALL) NOPASSWD:ALL
            ssh_authorized_keys:
              - ssh-ed25519 AAAAC3... your-public-key
  networks:
  - name: default
```

```bash
kubectl apply -f complete-vm.yaml
```

## Next Steps

- [Quickstart](index.md#step-9-advanced-operations) — snapshots, snapshot revert and cloning (`VMClone`)
- [Examples](../examples/index.md) — more configuration files
- [VM Status Reference](../guides/vm-status.md) — phases, conditions and what to do about a reason
- [VM Snapshots and Revert](../guides/vm-snapshots.md) — snapshot a VM and revert it
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

### VM Held with `ConsumerNotAllowed`

`Ready=False` with reason `ConsumerNotAllowed` (phase `Failed`) means the VM names a `Provider`, `VMClass` or `VMImage` in another namespace whose `spec.consumerNamespaceSelector` does not select the VM's namespace. Nothing is sent to the provider. Set the selector on that object (unset means its own namespace only, `{}` means every namespace).

### Authentication Errors

```bash
# Verify the credentials secret exists and has the expected keys
# (vSphere: username, password; libvirt: username + ssh-privatekey or password, known_hosts;
#  Proxmox: token_id, token_secret)
kubectl get secret vsphere-creds -o jsonpath='{.data}' | jq 'keys'

# Check provider pod logs
kubectl logs -n default -l app.kubernetes.io/name=virtrigaud-provider,app.kubernetes.io/instance=vsphere-provider
```
