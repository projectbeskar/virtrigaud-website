<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# 15-Minute Quickstart

This guide gets you up and running with VirtRigaud v0.4.0 in 15 minutes using a vSphere, Libvirt or Proxmox VE provider.

## Prerequisites

- Kubernetes cluster (1.25+). The reserved-keys admission policy that the chart installs by default needs Kubernetes 1.30+; on an older cluster it is not rendered (see [Helm installation](install-helm-only.md#admission-policy-kubernetes-130)).
- `kubectl` configured
- Helm 3.8+ (3.14+ if you carry custom values across chart upgrades with `--reset-then-reuse-values`)
- Access to a vSphere, Libvirt/KVM or Proxmox VE host

!!! warning "Upgrading from v0.3.11?"
    This page is for a new installation. v0.4.0 contains breaking changes
    (cross-namespace references need `spec.consumerNamespaceSelector`,
    `spec.providerRef` is immutable once bound, vSphere needs a new vCenter
    privilege, libvirt hosts need a seed directory, and more). Read the
    [Upgrade Guide](../operations/upgrade.md) and [Helm CRD Upgrades](helm-crd-upgrades.md) first.

## API

All resources use **`infra.virtrigaud.io/v1beta1`**. This is the stable API for all new deployments.

## Step 1: Install VirtRigaud

### Using Helm (recommended)

```bash
helm repo add virtrigaud https://projectbeskar.github.io/virtrigaud
helm repo update virtrigaud

helm install virtrigaud virtrigaud/virtrigaud \
  --version 0.4.0 \
  --namespace virtrigaud-system \
  --create-namespace
```

The chart installs the CRDs, the manager, its RBAC and, on Kubernetes 1.30+, the
reserved-keys `ValidatingAdmissionPolicy`. Admission webhooks are **off** by
default (`webhooks.enabled=false`); see [Helm installation](install-helm-only.md#admission-webhooks)
before turning them on.

!!! note "Providers are created from Provider CRs"
    You do not enable providers with Helm flags. Create a `Provider` resource
    (Step 3) and the manager deploys the provider pod for it. The chart's own
    `providers.<type>.enabled` Deployments are off by default and are only for
    standalone provider pods; if you opt in you must also set the `providerTLS`
    values (see [Helm installation](install-helm-only.md#provider-tls-values)).

To skip CRDs if you manage them separately:

```bash
helm install virtrigaud virtrigaud/virtrigaud \
  --version 0.4.0 \
  --namespace virtrigaud-system \
  --create-namespace \
  --skip-crds \
  --set crdUpgrade.enabled=false
```

### Using Kustomize

The Kustomize base under `config/` is meant for development. It does not create
the namespace, its manager image is the placeholder `controller:latest`, and the
resource names differ from the Helm chart (the Deployment is
`virtrigaud-controller-manager`). Use a checkout of the release tag, set the
image, and apply server-side because the CRDs are too large for client-side apply:

```bash
git clone --branch v0.4.0 https://github.com/projectbeskar/virtrigaud.git
cd virtrigaud
(cd config/manager && kustomize edit set image controller=ghcr.io/projectbeskar/virtrigaud/manager:v0.4.0)
kubectl create namespace virtrigaud-system
kubectl apply --server-side --force-conflicts -k config/default
```

The remaining steps use the Helm resource names (`deployment/virtrigaud-manager`).

## Step 2: Verify Installation

```bash
# Manager pod is running
kubectl get pods -n virtrigaud-system

# All 12 CRDs are installed
kubectl get crds | grep virtrigaud.io

# Manager logs
kubectl logs -n virtrigaud-system deployment/virtrigaud-manager | head -5
```

The 12 CRDs in `infra.virtrigaud.io/v1beta1` are `virtualmachines`, `providers`,
`vmclasses`, `vmimages`, `vmnetworkattachments`, `vmsnapshots`, `vmmigrations`,
`vmclones`, `vmsets`, `vmplacementpolicies`, `hosts` and `hostpools`. `hosts` and
`hostpools` are used only by [clustered libvirt providers](../providers/libvirt.md).

Confirm the running version through the metrics endpoint:

```bash
kubectl port-forward -n virtrigaud-system svc/virtrigaud-manager 8080:8080 &
curl -s http://localhost:8080/metrics | grep '^virtrigaud_build_info'
# virtrigaud_build_info{component="manager",...,version="v0.4.0"} 1
```

The `virtrigaud_circuit_breaker_state` and `virtrigaud_provider_tasks_inflight` families
appear for every Provider CR. See the [Metrics Catalog](../api-reference/metrics.md) and the
[Observability Guide](../operations/observability.md) for the full metrics surface.

## Step 3: Configure a Provider

A `Provider` names one hypervisor endpoint, the Secret that holds its credentials,
and the provider image the manager runs for it. Credentials are read by the provider
pod from files mounted from that Secret and never pass through the manager.

### Option A: vSphere Provider

```bash
kubectl create secret generic vsphere-credentials \
  --namespace default \
  --from-literal=username=administrator@vsphere.local \
  --from-literal=password=your-password
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
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.0"
    service:
      port: 9090
      tls:
        enabled: true
        secretRef:
          name: provider-vsphere-tls
        insecureSkipVerify: false
```

!!! warning "New vCenter privilege since v0.3.11"
    The vCenter account needs **Virtual machine > Change Configuration > Advanced
    configuration** (`VirtualMachine.Config.AdvancedConfig`) on the VM folder and
    resource pool. Every `Create` and `Clone` writes an owner stamp into the VM's
    extra configuration and fails without it. `VMImage` `templateName` must name a
    real vSphere template.

### Option B: Libvirt Provider

The libvirt provider reaches the host over SSH. The Secret holds `username` plus
either `ssh-privatekey` or `password`, and a `known_hosts` entry for the host.
Host-key verification is on by default and there is no trust-on-first-use.

```bash
kubectl create secret generic libvirt-credentials \
  --namespace default \
  --from-literal=username=virtrigaud \
  --from-file=ssh-privatekey=$HOME/.ssh/id_ed25519 \
  --from-file=known_hosts=<(ssh-keyscan -t ed25519 libvirt-host.example.com)
```

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: libvirt-lab
  namespace: default
spec:
  type: libvirt
  endpoint: qemu+ssh://virtrigaud@libvirt-host.example.com/system
  credentialSecretRef:
    name: libvirt-credentials
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.4.0"
    service:
      port: 9090
      tls:
        enabled: true
        secretRef:
          name: provider-libvirt-tls
        insecureSkipVerify: false
```

!!! warning "Prepare the libvirt host first"
    Every VM create builds its cloud-init seed in a private directory on the
    host, and the provider refuses to create anything when that directory is
    missing or not private (`refusing to stage cloud-init data`). On each libvirt
    host, as root:

    ```bash
    install -d -m 0711 -o virtrigaud -g virtrigaud /var/lib/libvirt/virtrigaud-seeds
    ```

    Use the SSH user from your Secret instead of `virtrigaud`. The
    [Libvirt provider page](../providers/libvirt.md) lists the other host
    requirements (sudo rules, image directories).

### Option C: Proxmox VE Provider

```bash
kubectl create secret generic proxmox-credentials \
  --namespace default \
  --from-literal=token_id='virtrigaud@pve!vrtg-token' \
  --from-literal=token_secret='your-token-secret'
```

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: proxmox-lab
  namespace: default
spec:
  type: proxmox
  endpoint: https://proxmox.example.com:8006
  credentialSecretRef:
    name: proxmox-credentials
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-proxmox:v0.4.0"
    service:
      port: 9090
      tls:
        enabled: true
        secretRef:
          name: provider-proxmox-tls
        insecureSkipVerify: false
```

```bash
kubectl apply -f provider.yaml
kubectl get providers
```

!!! note "mTLS required"
    Every Provider CR must include a `spec.runtime.service.tls` block. A Provider
    without it does not reconcile (`TLSConfigured=False, Reason=TLSBlockMissing`).
    With `tls.enabled: true`, the `secretRef` Secret must exist in the Provider's
    namespace and hold `tls.crt`, `tls.key` and `ca.crt`; see
    [mTLS Configuration](../providers/security/mtls.md). For a throwaway lab only,
    `tls.enabled: false` is an explicit, audit-visible plaintext opt-out. Images are
    multi-arch (`linux/amd64` and `linux/arm64`).

!!! note "Circuit breaker on first deploy"
    If the provider pod is unreachable on first deploy (for example, the SSH host is not yet reachable from a libvirt provider), the circuit breaker trips after 10 failed RPCs and `virtrigaud_circuit_breaker_state{provider="libvirt-lab"}` reads `2` (Open). This is working as designed. See [Resilience](../operations/resilience.md) for the recovery path.

!!! note "Using a Provider from another namespace"
    A `Provider`, `VMClass` or `VMImage` in another namespace can be referenced only if
    its `spec.consumerNamespaceSelector` selects the referencing namespace. Unset means
    "own namespace only", `{}` means "every namespace". A refused reference leaves the VM
    at `Ready=False`, reason `ConsumerNotAllowed`. The examples on this page keep
    everything in `default`, so no selector is needed. See
    [Cross-namespace references](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/cross-namespace-references.md).

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

### Proxmox VE

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

A libvirt `url` image is downloaded, converted to qcow2 and published in the
storage pool the first time a VM needs it; every VM gets its own copy. See
[Image preparation](../providers/libvirt.md) for the libvirt rules.

## Step 6: Create Your First VM

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: my-first-vm
  namespace: default
spec:
  providerRef:
    name: vsphere-prod   # or libvirt-lab, proxmox-lab
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

!!! warning "Supply your own `userData` on libvirt"
    A libvirt VM created without `spec.userData` no longer gets a default `ubuntu`
    user, SSH key or passwordless sudo (changed after v0.3.11). Give it a login
    through `spec.userData` as above, or you cannot log in.

`networks[].networkRef` is optional. Without it, vSphere and Proxmox use the
template's network adapter. A libvirt VM with no network attachment gets a
user-mode interface that has no libvirt-managed DHCP lease; to put it on the
libvirt `default` network or a host bridge, create a `VMNetworkAttachment` and
reference it from `networkRef` (see the [Libvirt provider page](../providers/libvirt.md)).

## Step 7: Monitor VM Creation

```bash
# Watch VM status
kubectl get vm my-first-vm -w

# Detailed status including phase, conditions and IPs
kubectl describe vm my-first-vm

# Events
kubectl get events --field-selector involvedObject.name=my-first-vm
```

`status.phase` is set on every status write, so it is never empty: `Pending`
(waiting for the Provider, class, image or a placement), `Provisioning`,
`Running`, `Stopped`, `Reconfiguring`, `Deleting` or `Failed` (a hold that needs an
operator, such as `ConsumerNotAllowed`, `VMNotOwned` or `DeleteBlocked`). The
`Ready`, `Provisioning`, `Reconfiguring` and `Placed` conditions carry the reason.
VMs adopted from a hypervisor get their phase on the next regular reconcile.

## Step 8: Access Your VM

```bash
# Get VM IP address
kubectl get vm my-first-vm -o jsonpath='{.status.ips[0]}'

# Get console URL (if supported by the provider)
kubectl get vm my-first-vm -o jsonpath='{.status.consoleURL}'

# SSH once the VM has an IP
ssh ubuntu@<vm-ip>
```

`status.ips` lists only addresses a client can reach. Loopback, link-local,
unspecified and multicast addresses are dropped on every provider. VMware Tools
(vSphere) or the QEMU guest agent (Proxmox, libvirt) must run in the guest to
report an address; a libvirt guest on a libvirt-managed network such as `default`
also shows its DHCP lease without the agent, but a guest on a host bridge needs the
agent.

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
  snapshotConfig:
    name: pre-update
    description: Before the update
    includeMemory: false
```

### Revert to a Snapshot

`spec.snapshot.revertToRef` on a `VirtualMachine` reverts the VM to a `Ready` `VMSnapshot`
taken of that VM. **A revert discards what was written to the VM's disks since the
snapshot.** VirtRigaud never powers a VM off for a revert: it is sent only while the
VM is off and `spec.powerState` is `Off` or `OffGraceful`, and it does not power the VM
on afterwards.

```bash
kubectl patch vm my-first-vm --type merge -p '{"spec":{"powerState":"Off"}}'
kubectl patch vm my-first-vm --type merge \
  -p '{"spec":{"snapshot":{"revertToRef":{"name":"my-vm-snapshot"}}}}'

# Phase is Succeeded (SnapshotReverted=True, reason Reverted) or Failed
kubectl get vm my-first-vm -o jsonpath='{.status.snapshotRevert.phase}{"\n"}'
```

On libvirt a revert needs a snapshot taken with the VM powered off. See the
[capability matrix](../providers/providers-capabilities.md) for what each provider
supports.

### Clone a VM

`VMClone` clones a VM through the same Provider (vSphere, Proxmox and libvirt; a libvirt
full clone needs its source VM powered off, and libvirt linked clones are not supported).
The clone stays powered off unless `options.powerOn: true`.

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClone
metadata:
  name: my-first-vm-clone
  namespace: default
spec:
  source:
    vmRef:
      name: my-first-vm
  target:
    name: my-first-vm-clone-target
    classRef:
      name: small
  options:
    type: FullClone
    powerOn: false
```

A clone gets a new cloud-init instance id and new SSH host keys, so it does not
present its source's identity.

### VMSet (stub - not functional)

!!! warning "VMSet controller not active"
    The `VMSet` CRD is installed but the controller is a stub. Any `VMSet`
    resource shows `Ready=False / Reason=ControllerNotImplemented`.
    Do not use VMSet in v0.4.0.

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMSet
metadata:
  name: web-servers
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
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
kubectl delete vmclone my-first-vm-clone
kubectl delete vmsnapshot my-vm-snapshot
kubectl delete vm my-first-vm
kubectl delete vm my-first-vm-clone-target

# Delete VirtualMachines and Providers BEFORE uninstalling the chart.
# A Provider carries an in-use finalizer that only the manager releases; it stays
# Terminating while a VirtualMachine, VMSnapshot, VMClone or VMMigration still needs it.
kubectl delete provider vsphere-prod   # or libvirt-lab, proxmox-lab

# Uninstall VirtRigaud (optional)
helm uninstall virtrigaud -n virtrigaud-system
kubectl delete namespace virtrigaud-system
```

## Next Steps

- [Basic VM Example](basic-vm-example.md) — step-by-step with all four required resources
- [Observability Guide](../operations/observability.md) — what VirtRigaud emits and how to alert on it
- [Resilience Guide](../operations/resilience.md) — circuit breaker behaviour and recovery
- [Provider Capabilities](../providers/providers-capabilities.md) — per-provider feature matrix
- [Helm installation](install-helm-only.md) and [Helm CRD Upgrades](helm-crd-upgrades.md) — chart options and upgrade order

## Troubleshooting

1. Check provider status and conditions: `kubectl get providers -A` and `kubectl describe provider <name>` (`TLSConfigured=False, Reason=TLSBlockMissing` means the `spec.runtime.service.tls` block is missing).
2. Check the VM: `kubectl describe vm <name>`. `Ready=False` with reason `ConsumerNotAllowed` means the Provider, VMClass or VMImage is in another namespace and its `spec.consumerNamespaceSelector` does not select this one.
3. Check manager logs: `kubectl logs -n virtrigaud-system deployment/virtrigaud-manager`
4. Check provider logs: `kubectl logs -n <provider namespace> -l app.kubernetes.io/name=virtrigaud-provider,app.kubernetes.io/instance=<provider name>` (a libvirt create that fails with `refusing to stage cloud-init data` means the seed directory on the host is missing or not private, see Step 3).
5. Check the circuit breaker: `curl -s http://localhost:8080/metrics | grep circuit_breaker_state`
6. File an issue: [github.com/projectbeskar/virtrigaud/issues](https://github.com/projectbeskar/virtrigaud/issues)
