<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Provider Onboarding Tutorial

This page walks you through bringing a `Provider` CR online end-to-end on a VirtRigaud v0.3.8 cluster. It uses the vSphere provider as the running example because that is the most common starting point; the same shape applies to libvirt and Proxmox with provider-type-specific tweaks called out inline.

If you are looking to build a **new** provider (a fresh hypervisor like Firecracker, Cloud-Hypervisor, or KubeVirt), that material lives in the developer-facing [provider development guide](../development/providers.md) — this page is for operators wiring up an existing provider against a real hypervisor.

## Prerequisites

- A Kubernetes cluster with VirtRigaud v0.3.8 installed. If you do not have one yet, follow the [Helm-only install guide](../getting-started/install-helm-only.md).
- `kubectl` configured against the cluster.
- Cluster admin (or namespace admin in `virtrigaud-system`) — you need to create `Secret`s, `Provider`s, and at least one `VirtualMachine`.
- Access to the hypervisor you are wiring up (vCenter / libvirt host / PVE cluster) with credentials of an account that can lifecycle VMs.

## Step 1 — Install VirtRigaud (skip if already installed)

```bash
helm repo add virtrigaud https://projectbeskar.github.io/virtrigaud
helm repo update

helm install virtrigaud virtrigaud/virtrigaud \
  --version 0.3.8 \
  --namespace virtrigaud-system \
  --create-namespace
```

Verify the manager is healthy:

```bash
kubectl get pods -n virtrigaud-system
# NAME                                  READY   STATUS    RESTARTS   AGE
# virtrigaud-manager-7d4b8c9d5b-xyz12   1/1     Running   0          1m
```

`/metrics` should already expose the v0.3.8 baseline. Port-forward and confirm:

```bash
kubectl port-forward -n virtrigaud-system svc/virtrigaud-manager 8081:8081 &
curl -s http://localhost:8081/metrics | grep ^virtrigaud_build_info
# virtrigaud_build_info{component="manager", ...version="v0.3.8"} 1
```

If you see `virtrigaud_build_info{version="v0.3.8"} 1`, the manager is up and the metric surface is wired. See [Observability](../operations/observability.md) for the full metric catalog.

## Step 2 — Create the credentials Secret

Each hypervisor has a different set of Secret keys. The keys are read as **files** mounted at `/etc/virtrigaud/credentials` inside the provider pod, so the key names matter.

=== "vSphere"

    ```yaml
    apiVersion: v1
    kind: Secret
    metadata:
      name: vsphere-credentials
      namespace: virtrigaud-system
    type: Opaque
    stringData:
      username: "virtrigaud@vsphere.local"
      password: "REPLACE_ME"
    ```

=== "Libvirt"

    ```yaml
    apiVersion: v1
    kind: Secret
    metadata:
      name: libvirt-credentials
      namespace: virtrigaud-system
    type: Opaque
    stringData:
      username: "virtrigaud"
      ssh-privatekey: |
        -----BEGIN OPENSSH PRIVATE KEY-----
        ...
        -----END OPENSSH PRIVATE KEY-----
    ```

=== "Proxmox"

    ```yaml
    apiVersion: v1
    kind: Secret
    metadata:
      name: proxmox-credentials
      namespace: virtrigaud-system
    type: Opaque
    stringData:
      token_id: "virtrigaud@pve!vrtg-token"
      token_secret: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    ```

Apply the Secret:

```bash
kubectl apply -f secret.yaml
```

## Step 3 — Create the Provider CR

The `Provider` CR tells VirtRigaud how to launch the provider pod and how to reach the hypervisor.

=== "vSphere"

    ```yaml
    apiVersion: infra.virtrigaud.io/v1beta1
    kind: Provider
    metadata:
      name: vsphere-lab
      namespace: virtrigaud-system
    spec:
      type: vsphere
      endpoint: https://vcenter.example.com/sdk
      credentialSecretRef:
        name: vsphere-credentials
      insecureSkipVerify: false       # set true ONLY in dev
      runtime:
        mode: Remote
        image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.3.8"
        service:
          port: 9443
    ```

=== "Libvirt"

    ```yaml
    apiVersion: infra.virtrigaud.io/v1beta1
    kind: Provider
    metadata:
      name: libvirt-lab
      namespace: virtrigaud-system
    spec:
      type: libvirt
      endpoint: "qemu+ssh://virtrigaud@libvirt-host.example.com/system"
      credentialSecretRef:
        name: libvirt-credentials
      runtime:
        mode: Remote
        image: "ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.3.8"
        service:
          port: 9090
    ```

=== "Proxmox"

    ```yaml
    apiVersion: infra.virtrigaud.io/v1beta1
    kind: Provider
    metadata:
      name: proxmox-cluster
      namespace: virtrigaud-system
    spec:
      type: proxmox
      endpoint: "https://pve.example.com:8006"
      credentialSecretRef:
        name: proxmox-credentials
      insecureSkipVerify: false
      runtime:
        mode: Remote
        image: "ghcr.io/projectbeskar/virtrigaud/provider-proxmox:v0.3.8"
        service:
          port: 9443
    ```

Apply:

```bash
kubectl apply -f provider.yaml
```

Watch the provider pod come up:

```bash
kubectl get pods -n virtrigaud-system -l app.kubernetes.io/component=provider -w
```

A successful state looks like:

```
NAME                                            READY   STATUS    RESTARTS   AGE
virtrigaud-provider-vsphere-lab-7c8b4d-abc12    1/1     Running   0          30s
```

Verify the Provider CR status:

```bash
kubectl get provider vsphere-lab -n virtrigaud-system -o jsonpath='{.status.conditions[?(@.type=="Ready")]}'
```

Expect `status: "True"`, reason `Connected`.

## Step 4 — Verify on `/metrics`

This is the part the v0.3.6 observability surface unlocks. After the provider pod has come up and the manager has dialed it, several metric families should populate immediately:

```bash
curl -s http://localhost:8081/metrics | grep -E '^(virtrigaud_circuit_breaker_state|virtrigaud_provider_tasks_inflight|virtrigaud_build_info)' | head
```

Expected (your provider name will differ):

```
virtrigaud_build_info{component="manager", ...version="v0.3.8"} 1
virtrigaud_circuit_breaker_state{provider_type="vsphere", provider="vsphere-lab"} 0
virtrigaud_provider_tasks_inflight{provider_type="vsphere", provider="vsphere-lab"} 0
```

What each tells you:

| Metric | Meaning |
|--------|---------|
| `virtrigaud_build_info` | Manager booted and registered metrics. |
| `virtrigaud_circuit_breaker_state{provider="..."} 0` | The G6 CircuitBreaker around this Provider's gRPC is `Closed` (healthy). A value of `2` (Open) means the manager has fast-failed enough RPCs to stop talking to this provider — that is the signal to investigate the hypervisor side. |
| `virtrigaud_provider_tasks_inflight 0` | No async tasks in flight. Will rise above 0 as soon as you start creating VMs that require server-side task completion. |

The `_total` counter families (`virtrigaud_provider_rpc_requests_total`, `virtrigaud_vm_operations_total`, `virtrigaud_circuit_breaker_failures_total`) appear after the first relevant event — RPC, VM operation, or breaker trip. See [Observability](../operations/observability.md) for the full catalog.

!!! tip "Breaker open on first dial?"
    If `virtrigaud_circuit_breaker_state` is `2` immediately after install, the manager could not reach the provider pod / the provider pod could not reach the hypervisor. Check the provider pod's logs (`kubectl logs -n virtrigaud-system <provider-pod>`) and the `Provider` CR's `status.conditions`. The libvirt provider in particular is sensitive to SSH-host hygiene — see [libvirt troubleshooting](libvirt.md#troubleshooting).

## Step 5 — Create a minimal VMClass and VMImage

Both CRs are referenced by every `VirtualMachine`. Define them once per common workload shape.

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMClass
metadata:
  name: small
  namespace: virtrigaud-system
spec:
  cpu: 2
  memory: "4Gi"
  firmware: UEFI
  diskDefaults:
    type: thin            # use qcow2 for libvirt/proxmox
    size: "20Gi"
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMImage
metadata:
  name: ubuntu-22-04
  namespace: virtrigaud-system
spec:
  source:
    template: "ubuntu-22.04-template"   # vSphere template name
  guestOS: "ubuntu64Guest"
```

(For libvirt / proxmox the `source` block looks different — see the respective provider pages.)

## Step 6 — Create your first VirtualMachine

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: VMNetworkAttachment
metadata:
  name: lan
  namespace: virtrigaud-system
spec:
  network:
    vsphere:
      portgroup: "VM Network"
  ipAllocation:
    type: DHCP
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: VirtualMachine
metadata:
  name: hello-world
  namespace: virtrigaud-system
spec:
  providerRef:
    name: vsphere-lab
  classRef:
    name: small
  imageRef:
    name: ubuntu-22-04
  powerState: On
  networks:
    - name: lan
      networkRef:
        name: lan
  userData:
    cloudInit:
      inline: |
        #cloud-config
        hostname: hello-world
        users:
          - name: ubuntu
            sudo: ALL=(ALL) NOPASSWD:ALL
            ssh_authorized_keys:
              - "ssh-ed25519 AAAA..."
        packages:
          - open-vm-tools     # use qemu-guest-agent on libvirt/proxmox
        runcmd:
          - systemctl enable --now open-vm-tools
```

Apply and watch:

```bash
kubectl apply -f vm.yaml
kubectl get vm hello-world -n virtrigaud-system -w
```

Expected progression:

```
NAME          PHASE       AGE   POWER   IP
hello-world   Pending     5s
hello-world   Creating    10s
hello-world   Running     45s   On      192.168.100.50
```

## Step 7 — Confirm everything end-to-end

After the VM lands in `Running`, several things should now be observable:

```bash
# 1. The VM has an IP (via cloud-init or guest tools)
kubectl get vm hello-world -n virtrigaud-system -o jsonpath='{.status.ips}'

# 2. The console URL is populated
kubectl get vm hello-world -n virtrigaud-system -o jsonpath='{.status.consoleURL}'

# 3. The Provider's CircuitBreaker is still closed
curl -s http://localhost:8081/metrics | grep 'circuit_breaker_state.*vsphere-lab'
# virtrigaud_circuit_breaker_state{provider_type="vsphere", provider="vsphere-lab"} 0

# 4. RPC counter shows real traffic
curl -s http://localhost:8081/metrics | grep virtrigaud_provider_rpc_requests_total | head
# virtrigaud_provider_rpc_requests_total{method="Create", provider="vsphere-lab", ...} 1
# virtrigaud_provider_rpc_requests_total{method="Describe", provider="vsphere-lab", ...} 12

# 5. VM operations counter populated (G7.1)
curl -s http://localhost:8081/metrics | grep virtrigaud_vm_operations_total | head
# virtrigaud_vm_operations_total{operation="create", provider="vsphere-lab"} 1
# virtrigaud_vm_operations_total{operation="describe", provider="vsphere-lab"} 12

# 6. IP-discovery histogram populated (G7.2)
curl -s http://localhost:8081/metrics | grep virtrigaud_ip_discovery_duration_seconds_count
# virtrigaud_ip_discovery_duration_seconds_count{provider="vsphere-lab"} 1
```

SSH into the guest with the IP from step 1 to verify the cloud-init applied:

```bash
ssh ubuntu@<vm-ip>
```

## Step 8 — Clean up

```bash
kubectl delete vm hello-world -n virtrigaud-system
kubectl delete vmnetworkattachment lan -n virtrigaud-system
kubectl delete vmimage ubuntu-22-04 -n virtrigaud-system
kubectl delete vmclass small -n virtrigaud-system
kubectl delete provider vsphere-lab -n virtrigaud-system
kubectl delete secret vsphere-credentials -n virtrigaud-system
```

The provider pod is deleted by the controller when the `Provider` CR is removed (it is an owned resource).

## What to read next

- The [capability matrix](providers-capabilities.md) — what each provider can and cannot do, including the v0.3.8 capability-negotiation surfacing (`Provider.status.reportedCapabilities`) and the corrected libvirt clone / image-import cells.
- The deep-dive pages for the provider you are operating:
  - [vSphere](vsphere.md) — guestinfo cloud-init, SCSI controller specs, StoragePod selection.
  - [Libvirt](libvirt.md) — virsh-over-SSH internals, disk export, why clone/image-import are Unimplemented, the I1 / SSH-host narrative.
  - [Proxmox](proxmox.md) — token vs password auth, memory snapshots, ConsoleURL nuance.
- [Operations — Resilience](../operations/resilience.md) — the v0.3.6 CircuitBreaker, including how to read the metrics.
- [Operations — Observability](../operations/observability.md) — the full metric catalog and example Prometheus alerts.
- [Generated CRD reference](../references/generated-crd-docs.md) — every field on every CRD.

## Building a new provider (SDK path)

If you want to add a hypervisor that does not exist in the tree yet (KubeVirt, Firecracker, Cloud-Hypervisor, direct QEMU, ...) the workflow is different:

1. Read the [provider development guide](../development/providers.md) and the [provider gRPC contract](../references/grpc-api.md).
2. Use the in-tree mock provider (`internal/providers/mock/`) as the minimum-implementation reference.
3. Scaffold a new provider with `vrtg-provider init <name>` (or copy the proxmox layout, which has the cleanest separation between the gRPC server and the REST client).
4. Register the new capability set via the SDK builder (`sdk/provider/capabilities/`).
5. Run the conformance suite (`go test ./test/conformance/...`) against your provider pod.

That work is outside the scope of this operator onboarding page; see the developer documentation referenced above.
