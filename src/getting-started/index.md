<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# 15-Minute Quickstart

This guide gets you up and running with VirtRigaud v0.3.7 in 15 minutes using either a vSphere or Libvirt provider.

## Prerequisites

- Kubernetes cluster (1.26+)
- `kubectl` configured
- Helm 3.8+
- Access to a vSphere or Libvirt/KVM host

## API

All resources use **`infra.virtrigaud.io/v1beta1`**. This is the stable API for all new deployments.

## Step 1: Install VirtRigaud

### Using Helm (recommended)

```bash
helm repo add virtrigaud https://projectbeskar.github.io/virtrigaud
helm repo update virtrigaud

helm install virtrigaud virtrigaud/virtrigaud \
  --version 0.3.7 \
  --namespace virtrigaud-system \
  --create-namespace
```

To enable specific providers at install time:

```bash
helm install virtrigaud virtrigaud/virtrigaud \
  --version 0.3.7 \
  --namespace virtrigaud-system \
  --create-namespace \
  --set providers.vsphere.enabled=true \
  --set providers.libvirt.enabled=true
```

To skip CRDs if you manage them separately:

```bash
helm install virtrigaud virtrigaud/virtrigaud \
  --version 0.3.7 \
  --namespace virtrigaud-system \
  --create-namespace \
  --skip-crds
```

### Using Kustomize

```bash
git clone https://github.com/projectbeskar/virtrigaud.git
cd virtrigaud
kubectl apply -k config/default
```

## Step 2: Verify Installation

```bash
# Manager pod is running
kubectl get pods -n virtrigaud-system

# All 10 CRDs are installed
kubectl get crds | grep virtrigaud.io

# Manager is at v0.3.7
kubectl logs -n virtrigaud-system deployment/virtrigaud-manager | head -5
```

After the manager starts, confirm v0.3.7 is running via the metrics endpoint:

```bash
kubectl port-forward -n virtrigaud-system svc/virtrigaud-manager 8080:8080 &
curl -s http://localhost:8080/metrics | grep '^virtrigaud_build_info'
# virtrigaud_build_info{component="manager",...,version="v0.3.7"} 1
```

Starting with v0.3.7 you will also see the new `virtrigaud_circuit_breaker_state` and `virtrigaud_provider_tasks_inflight` families on `/metrics` (seeded to 0 at boot for every Provider CR). See the [Observability Guide](../operations/observability.md) for the full v0.3.7 metrics surface.

## Step 3: Configure a Provider

### Option A: vSphere Provider

```bash
kubectl create secret generic vsphere-credentials \
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
  name: vsphere-prod
  namespace: default
spec:
  type: vsphere
  endpoint: https://vcenter.example.com
  credentialSecretRef:
    name: vsphere-credentials
    namespace: default
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.3.7"
    service:
      port: 9090
      tls:
        enabled: true
        secretRef:
          name: provider-vsphere-tls
        insecureSkipVerify: false
```

!!! note "mTLS required in v0.3.7"
    Every Provider CR must include a `spec.runtime.service.tls` block.
    A Provider without it will not reconcile (`TLSConfigured=False,
    Reason=TLSBlockMissing`). See the [upgrade guide](../operations/upgrade.md#v036--v037)
    for remediation steps. Images are now multi-arch (`linux/amd64` +
    `linux/arm64`) — no action required for arm64 clusters.

### Option B: Libvirt Provider

```bash
kubectl create secret generic libvirt-credentials \
  --namespace default \
  --from-literal=uri=qemu+ssh://root@libvirt-host.example.com/system \
  --from-literal=privateKey="$(cat ~/.ssh/id_rsa)"
```

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: libvirt-lab
  namespace: default
spec:
  type: libvirt
  endpoint: qemu+ssh://root@libvirt-host.example.com/system
  credentialSecretRef:
    name: libvirt-credentials
    namespace: default
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.3.7"
    service:
      port: 9090
      tls:
        enabled: true
        secretRef:
          name: provider-libvirt-tls
        insecureSkipVerify: false
```

```bash
kubectl apply -f provider.yaml
```

!!! note "Circuit breaker on first deploy"
    If the provider pod is unreachable on first deploy (e.g. SSH tunnel not yet up for a libvirt provider), the circuit breaker will trip after 10 failed RPCs and `virtrigaud_circuit_breaker_state{provider="libvirt-lab"}` will read `2` (Open). This is working as designed. See [Resilience](../operations/resilience.md) for the recovery path.

## Step 4: Create a VM Class

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: small
  namespace: default
spec:
  cpu: 2
  memory: 2Gi
```

```bash
kubectl apply -f vmclass.yaml
```

## Step 5: Create a VM Image

### vSphere

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

### Libvirt

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

```bash
kubectl apply -f vmimage.yaml
```

## Step 6: Create Your First VM

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: my-first-vm
  namespace: default
spec:
  providerRef:
    name: vsphere-prod   # or libvirt-lab
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
              - ssh-rsa AAAAB3... your-public-key
  networks:
  - name: default
    networkRef:
      name: default-network
      namespace: default
```

```bash
kubectl apply -f vm.yaml
```

## Step 7: Monitor VM Creation

```bash
# Watch VM status
kubectl get vm my-first-vm -w

# Detailed status including phase and IPs
kubectl describe vm my-first-vm

# Events
kubectl get events --field-selector involvedObject.name=my-first-vm
```

!!! note "Phase column"
    The `phase` status field (`Pending` → `Provisioning` → `Running`) may be empty for VMs that were auto-adopted by the VMAdoption controller (watching Provider CRs annotated `virtrigaud.io/adopt-vms: "true"`). Adopted VMs arrive with `status.ips` already populated; the phase field is a known gap for this path (issue I2).

## Step 8: Access Your VM

```bash
# Get VM IP address
kubectl get vm my-first-vm -o jsonpath='{.status.ips[0]}'

# Get console URL (if supported by the provider)
kubectl get vm my-first-vm -o jsonpath='{.status.consoleURL}'

# SSH once the VM has an IP
ssh ubuntu@<vm-ip>
```

## Step 9: Advanced operations

### Create a Snapshot

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMSnapshot
metadata:
  name: my-vm-snapshot
  namespace: default
spec:
  vmRef:
    name: my-first-vm
  nameHint: "pre-update-snapshot"
  memory: true
```

### Scale with VMSet

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMSet
metadata:
  name: web-servers
  namespace: default
spec:
  replicas: 3
  template:
    spec:
      providerRef:
        name: vsphere-prod
        namespace: default
      classRef:
        name: small
        namespace: default
      imageRef:
        name: ubuntu-22
        namespace: default
      powerState: "On"
```

## Step 10: Clean Up

```bash
kubectl delete vm my-first-vm
kubectl delete vmsnapshot my-vm-snapshot
kubectl delete vmset web-servers

# Uninstall VirtRigaud (optional)
helm uninstall virtrigaud -n virtrigaud-system
kubectl delete namespace virtrigaud-system
```

## Next Steps

- [Basic VM Example](basic-vm-example.md) — step-by-step with all four required resources
- [Observability Guide](../operations/observability.md) — what VirtRigaud emits and how to alert on it
- [Resilience Guide](../operations/resilience.md) — circuit breaker behaviour and recovery
- [Provider Capabilities](../providers/providers-capabilities.md) — per-provider feature matrix

## Troubleshooting

1. Check provider status: `kubectl get providers -A`
2. Check manager logs: `kubectl logs -n virtrigaud-system deployment/virtrigaud-manager`
3. Check circuit breaker: `curl -s http://localhost:8080/metrics | grep circuit_breaker_state`
4. File an issue: [github.com/projectbeskar/virtrigaud/issues](https://github.com/projectbeskar/virtrigaud/issues)
