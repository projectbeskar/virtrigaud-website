<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# NetworkPolicies for VirtRigaud

This page gives concrete NetworkPolicy templates for the manager and provider pods in **v0.3.6**. With mTLS not yet wired through the manager-provider gRPC channel (see [mTLS](mtls.md)), **NetworkPolicy is the primary compensating control** for the pod-network path. Regulated deployments should treat the policies on this page as required, not optional.

!!! warning "NetworkPolicy requires an enforcing CNI"
    NetworkPolicy is a Kubernetes API; enforcement depends on the CNI. The major CNIs that enforce it are Calico, Cilium, Antrea, Kube-router, and Weave. **Flannel does not enforce NetworkPolicy by default.** Verify with `kubectl get pods -n kube-system` and your CNI's documentation before assuming these policies are taking effect.

## Port surface in v0.3.6

Verify against `cmd/manager/main.go`, `charts/virtrigaud/templates/manager-deployment.yaml`, `cmd/provider-*/main.go`, and `internal/controller/provider_controller.go:617-652`.

### Manager pod

| Port  | Protocol | Purpose                                                | Notes                                                                |
|-------|----------|--------------------------------------------------------|----------------------------------------------------------------------|
| 8080  | TCP      | Prometheus `/metrics` endpoint                          | HTTP by default; HTTPS + RBAC when `--metrics-secure=true`           |
| 8081  | TCP      | Health probes (`/healthz`, `/readyz`)                   | HTTP, used by kubelet only                                            |
| 9443  | TCP      | Admission webhook server                                | TLS; the kube-apiserver dials this for CRD webhooks                  |

The manager does **not** open a gRPC server port — it is purely a gRPC client to providers.

### Provider pod (any of vsphere / libvirt / proxmox / mock)

| Port  | Protocol | Purpose                          | Notes                                                                |
|-------|----------|----------------------------------|----------------------------------------------------------------------|
| 9443  | TCP      | gRPC server (`provider.v1.Provider`) | Plaintext in v0.3.6 (see [mTLS](mtls.md))                       |
| 8080  | TCP      | Health probes (`/healthz`)        | HTTP, used by kubelet only. NOT a metrics endpoint.                   |

The provider's health endpoint on `:8080` is a `kubelet`-only path. Provider pods do not export Prometheus metrics — all `virtrigaud_*` series come from the manager pod.

### Hypervisor endpoints (provider egress)

| Provider     | Egress destination                              | Port(s)         |
|--------------|--------------------------------------------------|-----------------|
| vSphere      | vCenter SOAP API                                 | 443 TCP         |
| Libvirt      | libvirt host over SSH (`qemu+ssh://`)            | 22 TCP          |
| Libvirt      | libvirt daemon over TLS (`qemu+tls://`)          | 16514 TCP       |
| Libvirt      | libvirt daemon over plain TCP (`qemu+tcp://`)    | 16509 TCP       |
| Proxmox      | Proxmox VE REST API                              | 8006 TCP        |

For the libvirt provider over SSH, also note the [SSH host-key verification gap](../libvirt.md#authentication) and plan the egress allowlist tightly (single host CIDR, not a broad block).

## Default-deny baseline

Apply a default-deny NetworkPolicy in every namespace that hosts a manager or provider pod, then layer specific allow rules on top.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: virtrigaud-system
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

Repeat in the namespace where the per-Provider Deployments land (by default the same namespace as the manager).

## Manager NetworkPolicy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: virtrigaud-manager
  namespace: virtrigaud-system
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: manager
      app.kubernetes.io/name: virtrigaud
  policyTypes:
    - Ingress
    - Egress

  ingress:
    # /metrics — only from your Prometheus pod.
    # Tighten the selector to match your monitoring stack
    # (kube-prometheus-stack defaults shown).
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
          podSelector:
            matchLabels:
              app.kubernetes.io/name: prometheus
      ports:
        - protocol: TCP
          port: 8080

    # Webhook :9443 — only from the kube-apiserver.
    # The CNI must expose an apiserver selector; on managed
    # clusters check the cloud provider's recommendation.
    - from:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              component: kube-apiserver
      ports:
        - protocol: TCP
          port: 9443

    # Health probes :8081 are kubelet-initiated and do not
    # traverse pod network. No NetworkPolicy entry needed —
    # kubelet bypasses NetworkPolicy by design.

  egress:
    # DNS to kube-system CoreDNS.
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53

    # kube-apiserver — for ListWatch and SubjectAccessReview.
    # On most clusters the apiserver is at the cluster-internal
    # virtual IP 10.96.0.1:443. If yours differs, adjust the CIDR.
    - to:
        - ipBlock:
            cidr: 10.96.0.1/32  # cluster apiserver virtual IP
      ports:
        - protocol: TCP
          port: 443

    # Egress to provider pods (gRPC :9443) in the same namespace
    # AND in any namespace that holds provider deployments. The
    # provider controller deploys providers into the same namespace
    # as the manager unless overridden.
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/component: provider-runtime
      ports:
        - protocol: TCP
          port: 9443
```

If your provider runtimes live in a different namespace than the manager, add a `namespaceSelector` to the manager's egress rule and a matching `namespaceSelector` on the providers' ingress rule below.

## Provider NetworkPolicy

This is the **single most important policy** in v0.3.6. With gRPC plaintext between manager and provider, the provider pod must be reachable only from the manager pod.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: virtrigaud-provider
  namespace: virtrigaud-system  # adjust if providers run elsewhere
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: provider-runtime
  policyTypes:
    - Ingress
    - Egress

  ingress:
    # ONLY the manager pod may dial the provider's gRPC port.
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/component: manager
              app.kubernetes.io/name: virtrigaud
      ports:
        - protocol: TCP
          port: 9443

    # Health probes :8080 are kubelet-initiated; no rule needed.

  egress:
    # DNS — required for resolving the hypervisor endpoint hostname.
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53

    # Hypervisor API — adjust per provider type. Each provider needs
    # exactly ONE of these blocks. Replace the CIDR with the actual
    # hypervisor host or vCenter VIP.

    # --- vSphere example ---
    - to:
        - ipBlock:
            cidr: 10.10.20.5/32  # vCenter VIP
      ports:
        - protocol: TCP
          port: 443

    # --- Libvirt-over-SSH example (replace with your libvirt host) ---
    # - to:
    #     - ipBlock:
    #         cidr: 10.10.30.10/32
    #   ports:
    #     - protocol: TCP
    #       port: 22

    # --- Proxmox example ---
    # - to:
    #     - ipBlock:
    #         cidr: 10.10.40.20/32
    #   ports:
    #     - protocol: TCP
    #       port: 8006
```

!!! note "Specify hypervisor CIDRs explicitly"
    Do not use broad blocks like `10.0.0.0/8`. The hypervisor endpoint is highly sensitive — write the policy with single-host CIDRs (`/32`) where possible and document each.

## Per-provider variants

### vSphere

The vSphere provider needs egress to:

- vCenter SOAP API (`/sdk` endpoint) on TCP 443
- Optionally ESXi hosts directly if your topology has the provider talk to ESXi for some operations (rare in current code paths)

Use the template above, with the egress `ipBlock` pointing at the vCenter VIP only.

### Libvirt (qemu+ssh://)

The libvirt provider needs egress to the libvirt host on TCP 22. Combine the NetworkPolicy below with the SSH-host-key warning on the [libvirt provider page](../libvirt.md#authentication) — the NetworkPolicy ensures the SSH traffic does not cross an untrusted boundary, which is the project's official mitigation for the missing host-key verification.

```yaml
egress:
  - to:
      - ipBlock:
          cidr: 10.10.30.10/32  # libvirt host
    ports:
      - protocol: TCP
        port: 22
```

The libvirt provider also runs `scp` for disk transfers on the same SSH connection — that is still port 22, no extra rule needed.

### Proxmox

The Proxmox provider needs egress to the Proxmox VE REST API on TCP 8006.

```yaml
egress:
  - to:
      - ipBlock:
          cidr: 10.10.40.20/32  # PVE node or cluster VIP
    ports:
      - protocol: TCP
        port: 8006
```

If your PVE deployment is a cluster, list all node IPs (or the cluster's shared VIP).

### Mock provider

The mock provider has no egress requirement beyond DNS. Its ingress rule is identical to the production providers — only the manager pod may dial it.

## Verification

After applying the policies, verify enforcement from inside a pod that should be denied:

```bash
# From a random pod in a different namespace, attempt to dial the
# provider's gRPC port. The expected outcome is a CONNECTION TIMEOUT
# (NOT a refused connection — connection refused means there is no
# policy and the port is just closed; timeout means the policy is
# dropping the SYN, which is what you want).
kubectl run -it --rm netcheck \
  --image=nicolaka/netshoot:v0.13 \
  --restart=Never \
  --namespace=default \
  -- nc -zv -w 5 provider-vsphere-prod.virtrigaud-system.svc.cluster.local 9443
```

Then verify that the manager pod CAN still dial it:

```bash
kubectl exec -n virtrigaud-system deploy/virtrigaud-manager -- \
  /bin/sh -c "command -v nc >/dev/null && nc -zv provider-vsphere-prod 9443"
```

The manager pod runs distroless and does not include `nc`, so this exec will likely fail with `command not found` — check the gRPC behaviour via a real reconcile instead (look at `virtrigaud_provider_rpc_requests_total` after applying a `VirtualMachine`).

## CNI-specific notes

### Cilium

If you use `CiliumNetworkPolicy` (extends `NetworkPolicy` with L7 rules), you can add gRPC-method-level restrictions:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: virtrigaud-provider-l7
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/component: provider-runtime
  ingress:
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/component: manager
      toPorts:
        - ports:
            - port: "9443"
              protocol: TCP
```

You CAN add a gRPC-method allowlist here (e.g. allow only `Validate, Create, Describe, Power, Delete, TaskStatus`). Be careful: if you forget a method, the manager will fail with `codes.PermissionDenied` and the operator-visible signal will be `virtrigaud_provider_rpc_requests_total{code="PermissionDenied"}` going up.

### Calico

Calico's `GlobalNetworkPolicy` lets you apply the same rule across all namespaces. Combine with `NetworkSet` for hypervisor IP allowlists that you can update without re-applying every Provider policy:

```yaml
apiVersion: projectcalico.org/v3
kind: GlobalNetworkSet
metadata:
  name: hypervisor-endpoints
  labels:
    role: hypervisor
spec:
  nets:
    - 10.10.20.5/32
    - 10.10.20.6/32
```

Then reference `selector: role == "hypervisor"` in your `GlobalNetworkPolicy` egress rules.

## See also

- [mTLS](mtls.md) — what this NetworkPolicy is compensating for.
- [Operations -> Security](../../operations/security.md#v036-security-gap-inventory) — the gap inventory that motivates these policies.
- [Libvirt provider](../libvirt.md#authentication) — the SSH host-key trust model.
