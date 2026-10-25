<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Provider Architecture

This page describes how providers run in VirtRigaud **v0.4.0**: the Remote Provider model, what the manager creates for a `Provider`, how the Provider spec becomes a pod, TLS, security, sharing a Provider across namespaces, clustered topology, the Provider deletion rules and troubleshooting.

## Overview

VirtRigaud uses a **Remote Provider** architecture: each `Provider` resource gets its own provider pod, which talks to the hypervisor, and the manager reaches it over gRPC with mutual TLS. `Remote` is the only runtime mode (`spec.runtime.mode`).

```
┌──────────────────┐    ┌───────────────────┐
│ VirtualMachine,  │    │ Provider CR       │
│ VMClone, ...     │    └─────────┬─────────┘
└────────┬─────────┘              │ reconciled by
         │                        ▼
┌────────▼─────────┐    ┌───────────────────┐   creates   ┌───────────────────────┐
│ Manager          │    │ Provider          │────────────▶│ Deployment, Service,  │
│  VM, Clone, ...  │    │ controller        │             │ ServiceAccount        │
│  controllers     │    └───────────────────┘             │ (provider pod)        │
│                  │                                      └──────────┬────────────┘
│  gRPC client ────┼──────────── mTLS gRPC ─────────────────────────┘
└──────────────────┘     virtrigaud-provider-<namespace>-<name>:9443
                                                          │
                                                          ▼  hypervisor API / SSH
```

## What a Provider creates

For a `Provider` named `<name>` in namespace `<ns>` the Provider controller reconciles, in the Provider's namespace:

| Object | Name | Notes |
|--------|------|-------|
| `Deployment` | `virtrigaud-provider-<ns>-<name>` | One container, `provider`. Labels `app.kubernetes.io/name=virtrigaud-provider`, `app.kubernetes.io/instance=<name>`, `virtrigaud.io/provider-type=<type>` |
| `Service` | `virtrigaud-provider-<ns>-<name>` | ClusterIP; ports `grpc` (`spec.runtime.service.port`, default **9443**) and `metrics` (8080) |
| `ServiceAccount` | `virtrigaud-provider-<ns>-<name>` | Token-less and without any RoleBinding or ClusterRoleBinding |
| `Secret` `<name>-hosts` | | Only for `topology: cluster`: the rendered host inventory, owned by the Provider |

All are owned by the Provider and deleted with it. `Provider.status.runtime` records the endpoint, the service reference, the phase (`Pending`, `Starting`, `Running`, `Stopping`, `Failed`) and the ready replicas; the `ProviderRuntimeReady` condition says why a runtime is not ready.

### Configuration flow: Provider spec to pod

You never write the pod's arguments or environment: the controller derives them.

| Provider field | Result in the pod |
|----------------|-------------------|
| `spec.runtime.service.port` (default 9443) | Argument `--port=<port>`; container port `grpc`. The health and metrics server is always on port 8080 (`--health-port=8080`) |
| `spec.type` | Env `PROVIDER_TYPE` |
| `spec.endpoint` | Env `PROVIDER_ENDPOINT` |
| `metadata.namespace`, `metadata.name` | Env `PROVIDER_NAMESPACE`, `PROVIDER_NAME` |
| `spec.runtime.service.tls` | Env `TLS_ENABLED`; with `tls.enabled: true` the Secret is mounted at `/etc/virtrigaud/tls`; with `tls.enabled: false` the pod gets `VIRTRIGAUD_PROVIDER_INSECURE=true` so it starts in plaintext. `TLS_INSECURE_SKIP_VERIFY` carries the top-level `spec.insecureSkipVerify` (deprecated; it controls whether the provider verifies the hypervisor's certificate), not `spec.runtime.service.tls.insecureSkipVerify`, which only makes the manager skip verification of the provider's server certificate |
| `spec.runtime.logLevel`, `logFormat` | Env `LOG_LEVEL` (`debug`, `info`, `warn`, `error`), `LOG_FORMAT` (`text`, `json`) |
| `spec.defaults.{datastore,storagePod,cluster,folder}` | Env `PROVIDER_DEFAULT_DATASTORE`, `_STORAGE_POD`, `_CLUSTER`, `_FOLDER` |
| `spec.runtime.env` | Appended to the environment |
| `spec.credentialSecretRef` | The Secret (in the Provider's namespace) is mounted read-only at `/etc/virtrigaud/credentials/`, one file per key (`username`, `password`, `token`, `ssh-privatekey`, ...) |
| `spec.runtime.resources` | Container resources. Default: requests 100m CPU / 128Mi, limits 1 CPU / 512Mi |
| `spec.runtime.securityContext` | Replaces the default container security context |
| `spec.runtime.nodeSelector`, `tolerations`, `affinity`, `imagePullPolicy` | Copied to the pod (`imagePullPolicy` defaults to `IfNotPresent`) |

!!! note "Not in the pod spec"
    `spec.runtime.imagePullSecrets`, `livenessProbe` and `readinessProbe` exist in the schema, but the controller does not copy them to the Deployment: the container always uses its own `/healthz` probes on port 8080, and a private registry is reached through the pod's service account or node configuration. Check `kubectl get deploy virtrigaud-provider-<ns>-<name> -o yaml` for the rendered result.

### Complete example

```yaml
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: vsphere-datacenter
  namespace: default
spec:
  type: vsphere
  endpoint: "https://vcenter.example.com:443"
  credentialSecretRef:
    name: vsphere-credentials
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.0"
    service:
      port: 9443
      tls:
        enabled: true
        secretRef:
          name: vsphere-provider-tls   # tls.crt, tls.key, ca.crt
```

The resulting container runs `--port=9443 --health-port=8080` with `PROVIDER_TYPE=vsphere`, `PROVIDER_ENDPOINT=https://vcenter.example.com:443`, `PROVIDER_NAMESPACE=default`, `PROVIDER_NAME=vsphere-datacenter` and `TLS_ENABLED=true`, and mounts `/etc/virtrigaud/credentials/` and `/etc/virtrigaud/tls/`.

## Provider images

Use the image that matches your manager release; all are published under `ghcr.io/projectbeskar/virtrigaud/`:

| Image | Provider |
|-------|----------|
| `provider-vsphere:v0.4.0` | vSphere, using govmomi |
| `provider-libvirt:v0.4.0` | libvirt/KVM, using `virsh` and `qemu-img` over SSH |
| `provider-proxmox:v0.4.0` | Proxmox VE (REST API plus SSH for disk transfer) |

The mock provider (`provider-mock`) is a development and conformance-testing image built from the source tree; it is not one of the release images. `spec.runtime.image` accepts `image:tag`, `image@sha256:<digest>` or `image:tag@sha256:<digest>`. **A Provider pins its image: upgrading VirtRigaud does not change `spec.runtime.image`.** Roll providers by editing the field (see [Upgrading provider images](#upgrading-provider-images)); keep the manager and its providers on the same release.

## TLS between manager and provider

Since v0.3.7 the gRPC channel is **mutual TLS by default**, and the Provider spec must make the decision explicitly:

| `spec.runtime.service.tls` | Result |
|----------------------------|--------|
| Absent | **Not deployed.** `TLSConfigured=False`, reason `TLSBlockMissing`; the runtime phase is `Failed` (`ProviderRuntimeReady=False`, reason `TLSNotConfigured`) |
| `enabled: true`, no `secretRef` | Not deployed: `TLSConfigured=False`, reason `SecretRefMissing` |
| `enabled: true` with `secretRef` | TLS 1.3 mTLS: `TLSConfigured=True`, reason `Enabled` |
| `enabled: false` | Plaintext, an explicit opt-out: `TLSConfigured=False`, reason `ExplicitlyDisabled`. Compensating controls (NetworkPolicy, an encrypted CNI) are yours |

The Secret (in the Provider's namespace) holds `tls.crt`, `tls.key` and `ca.crt`. The provider pod uses it as its server certificate and requires a client certificate signed by `ca.crt`; the manager reads **the same Secret** for its client certificate and CA. The server certificate must carry the DNS name the manager dials, `virtrigaud-provider-<ns>-<name>.<ns>.svc.cluster.local`. The leaf certificate hot-reloads; rotating the CA needs a provider restart. `VIRTRIGAUD_PROVIDER_ALLOWED_SANS` (a comma-separated list, set through `spec.runtime.env`) restricts which client-certificate SANs the provider accepts; empty accepts any certificate from the CA. `spec.runtime.service.tls.insecureSkipVerify: true` makes the manager skip verifying the provider's certificate and defeats mTLS: lab use only.

The Helm chart's own provider Deployments (`providers.libvirt|vsphere|proxmox.enabled`) are separate from Provider CRs and take their TLS posture from the chart's `providerTLS` block (`secretName`, `allowedSANs`, `insecure`); the chart does not mint certificates. See [Security](../../operations/security.md).

## Provider configuration

### Basic setup

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-credentials
  namespace: default
type: Opaque
stringData:
  username: "administrator@vsphere.local"
  password: "REDACTED"
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: vsphere-datacenter
  namespace: default
spec:
  type: vsphere
  endpoint: "https://vcenter.example.com:443"
  credentialSecretRef:
    name: vsphere-credentials
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.0"
    service:
      port: 9443
      tls:
        enabled: true
        secretRef:
          name: vsphere-provider-tls
```

### Runtime options

```yaml
spec:
  type: libvirt
  endpoint: "qemu+ssh://virt@kvm.example.com/system"
  credentialSecretRef:
    name: libvirt-credentials
  rateLimit:
    qps: 20
    burst: 50
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.4.0"
    replicas: 2
    service:
      port: 9443
      tls: {enabled: true, secretRef: {name: libvirt-provider-tls}}
    resources:
      requests: {cpu: 200m, memory: 256Mi}
      limits: {cpu: "2", memory: 2Gi}
    nodeSelector:
      workload-type: compute
    tolerations:
      - {key: compute-dedicated, operator: Equal, value: "true", effect: NoSchedule}
    logLevel: info
    logFormat: json
```

- `spec.runtime.replicas` (1 to 10, default 1) scales the provider pods. **A vSphere Provider and a clustered Provider always run exactly one replica**, replaced with the `Recreate` strategy (the provider is briefly unavailable during a rollout): they serialize work with a per-process lock, so a larger `replicas` is ignored with a log line. For other Providers, replicas share the same hypervisor credentials; run more than one only if you need the redundancy.
- `spec.rateLimit`, `spec.healthCheck` and `spec.connectionPooling` are accepted by the API; see the CRD reference for their fields.
- The provider's `/tmp` is a size-limited `emptyDir` (needed for the read-only root file system and, on vSphere and libvirt, for disk staging). Override the manager-wide default per Provider with the annotation `infra.virtrigaud.io/tmp-size-limit` (a quantity such as `20Gi`, or `none`); changing it rolls the pods. A pod that writes past the limit is evicted.
- `infra.virtrigaud.io/max-disk-size` (a quantity of at least `1Gi`, for example `500Gi`) caps the size of every disk created or grown through the Provider. It can only lower the manager-wide ceiling (`manager.maxDiskSize` in the chart, `--max-disk-size`); the smaller of the two applies.
- `spec.type` and `spec.topology` are **immutable**: create a new Provider to change either.

## Sharing a Provider with other namespaces: `consumerNamespaceSelector`

By default only the Provider's own namespace may use it. `spec.consumerNamespaceSelector` lists the other namespaces whose `VirtualMachine`s may name it in `spec.providerRef` and whose `VMClone`, `VMMigration` and `VMSnapshot` objects may act through it:

```yaml
spec:
  consumerNamespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: team-a      # unset: own namespace only; {}: every namespace
```

A reference from a namespace the selector does not match is refused with `Ready=False` / `ConsumerNotAllowed`, and no provider call is made. Each object grants for itself: sharing a Provider does not share its VMClasses or VMImages. **Sharing a Provider shares everything its credentials can reach** (a tenant can write its own `VMImage` naming any template or image file the account can read): share only with namespaces trusted with that, and scope the hypervisor account accordingly. See [`shared-provider-consumer-namespaces.yaml`](../../examples/shared-provider-consumer-namespaces.yaml) and [Cross-namespace references](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/cross-namespace-references.md).

## Clustered topology (experimental)

`spec.topology` is `single` (the default: one provider process bound to one host) or `cluster` (one provider fronting N libvirt hosts registered as `Host` objects under a `HostPool`). `cluster` is accepted for `type: libvirt` only (the validating webhook rejects it for other types), is opt-in and experimental in v0.4.0. In a clustered Provider every `Host`, `HostPool` and per-host credential Secret must live in the Provider's namespace; the controller renders the hosts into the Secret `<name>-hosts`, which **contains the hosts' SSH credentials**, and mounts it read-only at `/etc/virtrigaud/hosts`. See the [Clustered libvirt guide](../clustered/index.md) and [`provider-libvirt-clustered.yaml`](../../examples/provider-libvirt-clustered.yaml).

## Deleting a Provider: the in-use finalizer

The controller keeps the finalizer `provider.infra.virtrigaud.io/in-use` on every Provider (ADR-0010). A Provider that is deleted while it is still needed is **held**:

- A bound `VirtualMachine` in the Provider's namespace, bound through it, or in a namespace its `consumerNamespaceSelector` allows holds it, as does a `VMSnapshot` with a delete still to run, an in-flight `VMClone`, and an in-flight `VMMigration` out of or into it.
- While held, the Deployment, Service and ServiceAccount are kept so the VMs can still be deleted through it. The Provider shows `DeleteBlocked=True` with reason `ProviderInUse` (the message counts objects per kind and namespace), and one `Warning` event `ProviderDeleteBlocked`.
- It is released when the last object is gone. `virtrigaud.io/force-delete: "true"` on the Provider releases it at once and leaves the hypervisor VMs running and unmanaged (a `Warning` event `ProviderForceDeleted` records what still used it).
- **Delete the VMs, and wait for them to go, before deleting their namespace.** Deleting a namespace removes the provider Deployment too; a VM deleted afterwards is held with `ProviderUnavailable` and the Provider shows `ProviderInUseRuntimeNotKept` until you force-delete or the VMs are gone.
- Delete VMs and Providers before removing the manager, or nothing releases the finalizer.

See [VM provider binding](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/vm-provider-binding.md#deleting-a-provider) for the details and the rollback procedure.

## Security model

### Pod security

- Containers run as non-root (UID 65532) with a read-only root file system, `allowPrivilegeEscalation: false` and all capabilities dropped (override with `spec.runtime.securityContext`).
- The pod uses its own ServiceAccount, with **no token mounted** and no role bindings: provider pods never call the Kubernetes API. Credentials and TLS material arrive as Secret volumes, and a compromised provider cannot borrow the manager's access.
- The libvirt provider keeps its SSH private key on a memory-backed (`tmpfs`) volume, never on node disk.
- A `preStop` sleep of 15 seconds inside a 30-second grace period lets in-flight gRPC calls finish.

### Credentials and network

- Each Provider has its own credential Secret in its namespace; a pod mounts only its own.
- The chart's `networkPolicy.*` block (opt-in, default off) renders NetworkPolicies for the manager and the provider pods; providers in a different namespace than the manager need an equivalent policy there.
- The manager makes no hypervisor calls itself: every call goes through a provider pod. (A clustered Provider is the exception for credentials: the manager copies each host's SSH credentials into the `<name>-hosts` Secret, which is why that Secret must be protected like the credential Secrets.)

## Communication protocol

The provider gRPC service (`provider.v1.Provider`, `proto/provider/v1/provider.proto`) has these RPCs:

| Group | RPCs |
|-------|------|
| Lifecycle | `Validate`, `Create`, `Delete`, `Power`, `Reconfigure`, `HardwareUpgrade`, `Describe`, `TaskStatus` |
| Snapshots and clones | `SnapshotCreate`, `SnapshotDelete`, `SnapshotRevert`, `Clone` |
| Images and capabilities | `ImagePrepare`, `GetCapabilities` |
| Migration | `ExportDisk`, `ImportDisk`, `GetDiskInfo`, `DeleteStagedDisk`, `DeleteLandedDisk` |
| Inventory and ownership | `ListVMs`, `TransferOwner`, `ListHosts`, `GetHostInfo` |

An RPC a provider does not implement answers `Unimplemented`, and what a provider supports is reported by `GetCapabilities` into `Provider.status.reportedCapabilities`. Error handling: the manager retries transient failures with backoff, a per-Provider circuit breaker stops calls to a provider that keeps failing (definite per-VM refusals do not count toward it), and a call whose outcome was lost is held rather than repeated ([Provider calls whose outcome was lost](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/docs/provider-call-outcomes.md)).

## Observability

The provider pod serves, on port 8080:

- `/healthz` (liveness and readiness probes) and `/readyz`;
- `/metrics` for the vSphere, libvirt and Proxmox providers: the provider-side series of `internal/obs/metrics`, for example `virtrigaud_provider_host_guard_refusals_total`, `virtrigaud_image_prepare_artifact_total`, and the libvirt `virtrigaud_libvirt_shadow_*` series. The manager exports `virtrigaud_provider_rpc_requests_total`, `virtrigaud_provider_rpc_latency_seconds`, `virtrigaud_circuit_breaker_state` and the others listed in [Observability](../../operations/observability.md).

Logs are text or JSON (`spec.runtime.logFormat`) at the level in `spec.runtime.logLevel`.

## Deployment patterns

```yaml
# One Provider per environment: same type, different namespaces and credentials
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: dev-libvirt
  namespace: development
spec:
  type: libvirt
  endpoint: "qemu+ssh://dev@libvirt-dev.example.com/system"
  credentialSecretRef:
    name: libvirt-credentials
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.4.0"
    service:
      tls: {enabled: true, secretRef: {name: libvirt-provider-tls}}
    resources:
      requests: {cpu: 100m, memory: 128Mi}
---
apiVersion: infra.virtrigaud.io/v1beta1
kind: Provider
metadata:
  name: prod-libvirt
  namespace: production
spec:
  type: libvirt
  endpoint: "qemu+ssh://prod@libvirt-prod.example.com/system"
  credentialSecretRef:
    name: libvirt-credentials
  runtime:
    mode: Remote
    image: "ghcr.io/projectbeskar/virtrigaud/provider-libvirt:v0.4.0"
    replicas: 2
    service:
      tls: {enabled: true, secretRef: {name: libvirt-provider-tls}}
    resources:
      requests: {cpu: 500m, memory: 512Mi}
      limits: {cpu: "2", memory: 2Gi}
```

For several hypervisors in one cluster see [`multi-provider-example.yaml`](../../examples/multi-provider-example.yaml). To run a fleet of libvirt hosts behind one Provider, use the [clustered topology](#clustered-topology-experimental).

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Provider not deploying | `kubectl get provider <name> -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'`: `TLSConfigured=False` with `TLSBlockMissing` or `SecretRefMissing` means a missing TLS decision; `ProviderRuntimeReady=False` gives the other causes |
| Pod `ImagePullBackOff` | The image exists for that tag (`docker pull ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.0`); a private registry needs node-level or service-account pull credentials (see the note above) |
| Pod crash-loops with a TLS error | The TLS Secret has `tls.crt`, `tls.key` and `ca.crt`; or set `tls.enabled: false` for a plaintext lab. A pod that finds no certificate files and no opt-out refuses to start |
| Manager cannot connect | The server certificate has the SAN `virtrigaud-provider-<ns>-<name>.<ns>.svc.cluster.local`; TLS 1.3 is required; both sides use certificates signed by the same CA |
| VMs `Ready=False` / `ConsumerNotAllowed` | The Provider's `consumerNamespaceSelector` does not select the VM's namespace |
| Provider stuck `Terminating` | `DeleteBlocked` condition: VMs, snapshots, clones or migrations still use it; see [the finalizer](#deleting-a-provider-the-in-use-finalizer) |
| Credential problems | The Secret is in the Provider's namespace and mounted: `kubectl describe pod -l app.kubernetes.io/instance=<name>` |

```bash
kubectl describe provider vsphere-datacenter
kubectl get deployment,svc,sa virtrigaud-provider-default-vsphere-datacenter
kubectl logs -l app.kubernetes.io/instance=vsphere-datacenter -f
kubectl port-forward svc/virtrigaud-provider-default-vsphere-datacenter 8080:8080
curl http://localhost:8080/metrics
```

## Upgrading provider images

Providers are pinned by `spec.runtime.image`; upgrade the CRDs and the manager first, then the providers (see the [upgrade guide](../../operations/upgrade.md)):

```bash
kubectl patch provider vsphere-datacenter --type merge -p '
{"spec":{"runtime":{"image":"ghcr.io/projectbeskar/virtrigaud/provider-vsphere:v0.4.0"}}}'

kubectl rollout status deployment virtrigaud-provider-default-vsphere-datacenter
```

A vSphere or clustered Provider is replaced with the `Recreate` strategy, so it is unavailable for the duration of the rollout; VMs are not affected, but their operations wait.
