<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# NetworkPolicies for VirtRigaud

This page describes the NetworkPolicy templates that ship in the **v0.4.0** Helm chart, how to tune them, and a hand-written equivalent for deployments that do not use the chart. Manager↔provider gRPC is protected by **mTLS by default** (see [mTLS](mtls.md)), so mTLS — not NetworkPolicy — is the **primary** transport control. NetworkPolicy remains valuable as **defence-in-depth**, limits what a compromised provider pod can reach, and is the **required compensating control** for any Provider you deliberately run with `tls.enabled=false` (audit-flagged plaintext). Regulated deployments should treat it as required, not optional.

!!! warning "NetworkPolicy requires an enforcing CNI"
    NetworkPolicy is a Kubernetes API; enforcement depends on the CNI. Calico, Cilium, Antrea and Kube-router enforce it. **Flannel does not enforce NetworkPolicy by default.** Verify with your CNI's documentation before assuming these policies are taking effect: on a CNI that does not enforce them they are inert.

## Port surface in v0.4.0

### Manager pod

| Port  | Protocol | Purpose                                                | Notes                                                                |
|-------|----------|--------------------------------------------------------|----------------------------------------------------------------------|
| 8080  | TCP      | Prometheus `/metrics` endpoint                          | HTTP by default; HTTPS + RBAC when `--metrics-secure=true`           |
| 8081  | TCP      | Health probes (`/healthz`, `/readyz`)                   | HTTP, used by the kubelet only                                       |
| 9443  | TCP      | Admission webhook server                                | TLS; the kube-apiserver dials this. Only when `webhooks.enabled=true` |

The manager does **not** open a gRPC server port — it is purely a gRPC client to providers.

### Provider pod (any of vsphere / libvirt / proxmox / mock)

| Port  | Protocol | Purpose                          | Notes                                                                |
|-------|----------|----------------------------------|----------------------------------------------------------------------|
| 9443 (default) | TCP | gRPC server (`provider.v1.Provider`) | The Provider's `spec.runtime.service.port`. mTLS by default since v0.3.7; plaintext only on an explicit per-Provider opt-out (see [mTLS](mtls.md)). The chart's optional static provider Deployments listen on **9090** instead. |
| 8080  | TCP      | Health probes (`/healthz`, `/readyz`) **and `/metrics`** | HTTP. The kubelet probes it, and the provider's Prometheus registry is served on the same port, so it is **not** a kubelet-only port. See [the note on provider metrics](#provider-metrics-exposure). |

### Egress destinations

| Pod | Destination | Port(s) |
|---|---|---|
| Manager | kube-apiserver | 443 / 6443 |
| Manager | kube-dns / CoreDNS | 53 UDP+TCP |
| Manager | provider pods | the Provider gRPC port |
| vSphere provider | vCenter | 443 TCP |
| Libvirt provider | libvirt host over SSH (`qemu+ssh://`) | 22 TCP |
| Proxmox provider | Proxmox VE REST API | 8006 TCP |
| Proxmox provider | PVE node over SSH (migration data plane, `qemu-img`) | 22 TCP |
| Any provider | VM console / VNC endpoints | 5900–5901 TCP |
| Any provider (migration) | S3-compatible storage / NFS server | 443 TCP / 2049 TCP |
| Any provider | kube-dns / CoreDNS | 53 UDP+TCP |

Provider pods never call the Kubernetes API (they run with no ServiceAccount token), so they need no API-server egress. A **clustered** libvirt Provider's single provider pod dials every `Host` it fronts over SSH on its own port (default 22); allow egress to each host.

## The chart's NetworkPolicies

The chart renders two namespaced `NetworkPolicy` objects, `<release>-manager` and `<release>-provider`, from `templates/networkpolicy.yaml`. They are **opt-in and disabled by default**:

```yaml
networkPolicy:
  enabled: false   # set true to render them
```

!!! note "Why default-off, and the old key"
    The settings live under `networkPolicy`, not the legacy `security.networkPolicies` block, which is now **ignored** (v0.3.11 shipped `security.networkPolicies.enabled: true`, but no template ever consumed it). Because `helm upgrade --reuse-values` reuses the **old** chart's defaults, enabling `networkPolicy` on a release upgraded that way fails the render with a message asking for `--reset-then-reuse-values` (Helm 3.14+), which takes the new chart's defaults and keeps your own values.

**What the policies allow** (when `networkPolicy.enabled: true`; everything else in the selected direction is denied):

| Pod | Ingress | Egress |
|-----|---------|--------|
| **manager** | health probes (`:8081`, open source: the kubelet); metrics (`:8080`, from `monitoringNamespaceSelector`); webhook (`:9443`, open source: the API server; only when `webhooks.enabled`) | DNS (kube-dns); Kubernetes API (`apiServerPorts`, optionally `apiServerCIDRs`); gRPC to provider pods (`providerGRPCPort`) |
| **provider** | health and metrics (`:8080`, open source); gRPC from the manager pod (`providerGRPCPort`) | DNS (kube-dns); hypervisor and migration-staging ports (`hypervisorEgressPorts`, optionally `hypervisorEgressCIDRs`) |

The kubelet and the API server originate from node IPs that a pod or namespace selector cannot match, so those rules are port-scoped with an open source; narrowing them would break readiness, or, under `webhooks.validating.failurePolicy: Fail`, Provider admission.

The relevant values and their defaults:

```yaml
networkPolicy:
  enabled: false
  monitoringNamespaceSelector:           # who may scrape the manager's :8080
    matchLabels: {metrics: enabled}
  dnsNamespaceSelector:
    matchLabels: {kubernetes.io/metadata.name: kube-system}
  dnsPodSelector:
    matchLabels: {k8s-app: kube-dns}
  dnsEgressCIDRs: []                     # e.g. the NodeLocal DNSCache address
  providerPodSelector:                   # the pods the manager creates for Provider CRs
    matchLabels:
      app.kubernetes.io/managed-by: virtrigaud
      app.kubernetes.io/component: provider
  providerGRPCPort: 9443
  providerNamespaceSelector: {}          # only if providers run outside the release namespace
  apiServerPorts: [443, 6443]
  apiServerCIDRs: []                     # empty = any destination on those ports
  hypervisorEgressPorts: [22, 443, 2049, 8006, 5900, 5901]
  hypervisorEgressCIDRs: []              # empty = any destination on those ports
  ingress: {managerToProvider: true, webhookIngress: true, metrics: true}
  egress:  {managerToProvider: true, providerToHypervisor: true, dns: true, kubernetesAPI: true}
```

**Tuning checklist** (all values-driven):

- **Metrics scrape.** Label your monitoring namespace to match `monitoringNamespaceSelector` (default `metrics: enabled`). If Prometheus runs in the **same** namespace as the manager, label that namespace too: a `namespaceSelector` does not implicitly match the policy's own namespace. Otherwise the manager's `:8080` is closed to Prometheus and the chart's `ServiceMonitor` scrapes fail.
- **DNS.** The defaults target CoreDNS (`k8s-app: kube-dns` in `kube-system`). On clusters with **NodeLocal DNSCache**, pods resolve through a node-local link-local address that a selector cannot match: set `dnsEgressCIDRs`, or DNS is black-holed.
- **Providers in another namespace.** By default the manager→provider egress peer is scoped to the release namespace, so with policies enabled all provider pods **must** live in the release namespace or the manager cannot reach them and VMs stop reconciling. If providers run elsewhere, set `providerNamespaceSelector` (include the release namespace too) **and** render an equivalent provider policy into each provider namespace; `NetworkPolicy` is namespaced, and the chart's provider policy only covers its own namespace.
- **Chart-templated providers** (`providers.*.enabled: true`) carry `app.kubernetes.io/component: provider-<hypervisor>`, listen on 9090 and use gRPC kubelet probes on that port: override `providerPodSelector` and `providerGRPCPort`, and widen the provider health allow to the probe port.
- **Lock down egress (recommended for regulated deployments).** Pin `apiServerCIDRs` to the control-plane network and `hypervisorEgressCIDRs` to your hypervisor and storage networks. The latter is SSRF defence-in-depth behind the application-layer allow-list: migration storage endpoints are user-supplied through `VMMigration` specs. For a clustered libvirt Provider list every host's address.
- **Do not disable** `egress.dns` or `egress.kubernetesAPI` while other egress rules stay on: that makes those directions denied and **wedges the manager** (no leader election, no reconcile). Likewise keep `ingress.webhookIngress` on while a `failurePolicy: Fail` webhook is enabled.

Render before you apply:

```bash
helm template virtrigaud virtrigaud/virtrigaud --version 0.4.1 \
  --set networkPolicy.enabled=true | grep -B2 -A12 'kind: NetworkPolicy'
```

### Provider metrics exposure

Provider pods serve `/metrics` on their health port, and the ingress rule for that port has an open source (the kubelet's probe source cannot be selected), so provider telemetry is reachable from anywhere the CNI lets traffic in. It carries telemetry only (no secrets): the libvirt driver-transition metrics, host-guard refusals and Go runtime metrics. If that matters in your environment, restrict ingress to the provider pods with an additional, CNI-specific policy that allows the node (kubelet) range and your Prometheus.

## A hand-written policy set

If you do not use the chart, or need a policy the chart cannot express, the following is a hand-written equivalent. Adjust the namespaces, selectors and CIDRs; the CIDRs here are placeholders (RFC 5737 documentation ranges).

### Default-deny baseline

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

Repeat in the namespace where the per-Provider Deployments land (the Provider's own namespace).

### Manager

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: virtrigaud-manager
  namespace: virtrigaud-system
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: virtrigaud        # the chart's selector labels
      app.kubernetes.io/instance: virtrigaud    # the Helm release name
      app.kubernetes.io/component: manager
  policyTypes:
    - Ingress
    - Egress

  ingress:
    # Health probes :8081 come from the kubelet (node IP). Many CNIs let the
    # kubelet through regardless; if yours does not, allow the port from anywhere.
    - ports:
        - protocol: TCP
          port: 8081

    # /metrics :8080 — only from your Prometheus pod.
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

    # Webhook :9443 — only if webhooks.enabled. The API server's source IP
    # cannot be selected by pod or namespace, so the source is open; scope by port.
    - ports:
        - protocol: TCP
          port: 9443

  egress:
    # DNS to CoreDNS.
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

    # kube-apiserver — for the watches, leader election and (with
    # --metrics-secure) token review. Use your control-plane address(es).
    - to:
        - ipBlock:
            cidr: 192.0.2.10/32
      ports:
        - protocol: TCP
          port: 443

    # gRPC to provider pods, in this namespace (the controller-created ones).
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/managed-by: virtrigaud
              app.kubernetes.io/component: provider
      ports:
        - protocol: TCP
          port: 9443
```

### Provider

This is a **high-value policy**: the provider pod should be reachable only from the manager pod. The labels below are the ones the Provider controller puts on every provider pod it creates (`app.kubernetes.io/name: virtrigaud-provider`, `app.kubernetes.io/instance: <Provider name>`, `app.kubernetes.io/component: provider`, `app.kubernetes.io/managed-by: virtrigaud`, `virtrigaud.io/provider-type: <type>`). A single policy per hypervisor type can select on `virtrigaud.io/provider-type`.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: virtrigaud-provider-vsphere
  namespace: virtrigaud-system  # the Provider's namespace
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/managed-by: virtrigaud
      app.kubernetes.io/component: provider
      virtrigaud.io/provider-type: vsphere
  policyTypes:
    - Ingress
    - Egress

  ingress:
    # ONLY the manager pod may dial the provider's gRPC port.
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: virtrigaud-system
          podSelector:
            matchLabels:
              app.kubernetes.io/name: virtrigaud
              app.kubernetes.io/component: manager
      ports:
        - protocol: TCP
          port: 9443
    # Health probes and /metrics :8080 (see "Provider metrics exposure").
    - ports:
        - protocol: TCP
          port: 8080

  egress:
    # DNS — required for resolving the hypervisor and storage hostnames.
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

    # Hypervisor API — vCenter. Use single-host CIDRs.
    - to:
        - ipBlock:
            cidr: 198.51.100.5/32
      ports:
        - protocol: TCP
          port: 443

    # Migration staging (S3-compatible 443 / NFS 2049), only if you migrate through this Provider:
    # - to:
    #     - ipBlock:
    #         cidr: 198.51.100.40/32
    #   ports:
    #     - protocol: TCP
    #       port: 443
    #     - protocol: TCP
    #       port: 2049
```

!!! note "Specify hypervisor CIDRs explicitly"
    Do not use broad blocks like `10.0.0.0/8`. The hypervisor endpoint is highly sensitive: write the policy with single-host CIDRs (`/32`) where possible and document each.

### Per-provider variants

Use the policy above and change only the `virtrigaud.io/provider-type` value and the hypervisor egress block.

**vSphere.** Egress to vCenter on TCP 443 (the `/sdk` endpoint). ESXi hosts are not dialled directly in the current code paths; if you migrate through a vSphere Provider, allow egress to the datastore or staging endpoints you configure.

**Libvirt (`qemu+ssh://`).** Egress to the libvirt host on TCP 22. SSH host-key verification is on by default (see the [libvirt provider page](../libvirt.md#authentication) and [Security](../../operations/security.md#libvirt-ssh-host-key-verification)), so it — not the NetworkPolicy — is the primary control on the SSH path; keep the egress scoped to the single libvirt host anyway. Disk transfers use the same SSH connection (no extra port). A clustered Provider needs one egress rule per `Host`.

```yaml
egress:
  - to:
      - ipBlock:
          cidr: 198.51.100.10/32  # libvirt host
    ports:
      - protocol: TCP
        port: 22
```

**Proxmox.** Egress to the PVE REST API on TCP 8006, and to the PVE node on TCP 22 if you use migration or the `qemu-img` data plane. For a PVE cluster list every node address (or the shared VIP).

```yaml
egress:
  - to:
      - ipBlock:
          cidr: 198.51.100.20/32  # PVE node or cluster VIP
    ports:
      - protocol: TCP
        port: 8006
      - protocol: TCP
        port: 22
```

**Mock provider.** No egress beyond DNS. Its ingress rule is identical to the production providers.

## Verification

After applying the policies, verify enforcement from a pod that should be denied:

```bash
# From a random pod in a different namespace, attempt to dial a provider's gRPC
# port. The expected outcome is a CONNECTION TIMEOUT (a "refused" would mean no
# policy applies and the port is simply closed; a timeout means the policy is
# dropping the SYN, which is what you want).
kubectl run -it --rm netcheck \
  --image=nicolaka/netshoot:v0.13 \
  --restart=Never \
  --namespace=default \
  -- nc -zv -w 5 virtrigaud-provider-virtrigaud-system-vsphere-prod.virtrigaud-system.svc.cluster.local 9443
```

The provider Service is named `virtrigaud-provider-<namespace>-<name>`.

To confirm that the manager can still reach the provider, do not exec into it (the manager image is distroless and has no `nc`): apply or touch a `VirtualMachine` and watch `virtrigaud_provider_rpc_requests_total{code="OK"}` rise, or check that the Provider's `ProviderRuntimeReady` condition is `True` and the `virtrigaud_circuit_breaker_state` of the Provider stays `0`. A policy that blocks the manager shows up as `DeadlineExceeded` RPCs (the client waits for a connection until the call's deadline) and, after ten of them, an open breaker.

## CNI-specific notes

### Cilium

A `CiliumNetworkPolicy` can express the same L3/L4 rules with endpoint selectors:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: virtrigaud-provider-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/component: provider
      app.kubernetes.io/managed-by: virtrigaud
  ingress:
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/component: manager
      toPorts:
        - ports:
            - port: "9443"
              protocol: TCP
```

Do not rely on L7 (gRPC method) rules: with mTLS enabled the traffic is encrypted end to end and the proxy cannot see the method.

### Calico

Calico's `GlobalNetworkPolicy` lets you apply the same rule across all namespaces. Combine it with a `GlobalNetworkSet` for hypervisor address allow-lists that you can update without re-applying every Provider policy:

```yaml
apiVersion: projectcalico.org/v3
kind: GlobalNetworkSet
metadata:
  name: hypervisor-endpoints
  labels:
    role: hypervisor
spec:
  nets:
    - 198.51.100.5/32
    - 198.51.100.6/32
```

Then reference `selector: role == "hypervisor"` in your `GlobalNetworkPolicy` egress rules.

## See also

- [mTLS](mtls.md) — what this NetworkPolicy is compensating for.
- [Operations -> Security](../../operations/security.md#v036-security-gap-inventory) — the gap inventory that motivates these policies.
- [Libvirt provider](../libvirt.md#authentication) — the SSH host-key trust model.
- [Observability](../../operations/observability.md#scraping-setup) — scraping with the chart's `ServiceMonitor`.
