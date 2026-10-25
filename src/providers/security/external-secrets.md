<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# External Secrets for Provider Credentials

This page shows how to wire [External Secrets Operator](https://external-secrets.io) (ESO) into a VirtRigaud **v0.4.0** deployment so provider credentials are sourced from your central secret store (Vault / AWS Secrets Manager / Azure Key Vault / GCP Secret Manager / etc.) rather than committed to Git or hand-applied with `kubectl create secret`.

The key constraint is: **VirtRigaud providers read credentials as named files**, not as env vars. So the `ExternalSecret` you produce must materialise a `Secret` whose **keys match exactly** what each provider reads.

## How VirtRigaud consumes the Secret

```
ExternalSecret  ────►  Secret (operator namespace)
                              │
                              │ Provider.spec.credentialSecretRef.name = "<Secret name>"
                              ▼
                       ProviderReconciler
                              │
                              │ mounts the Secret read-only at
                              │ /etc/virtrigaud/credentials inside the provider pod
                              ▼
                       Provider pod reads each Secret key as a FILE
                       (e.g. /etc/virtrigaud/credentials/username)
```

References (code paths): the controller mounts the Secret in `internal/controller/provider_controller.go`; vSphere reads `username` and `password` (`internal/providers/vsphere/server.go`); libvirt reads `username`, `password`, `ssh-privatekey` and `known_hosts` (`internal/providers/libvirt/virsh.go`, `sshhostkey.go`); Proxmox reads `token_id`, `token_secret`, `username`, `password` (`internal/providers/proxmox/server.go`) and, for its SSH data plane, `ssh_user`, `ssh_password`, `ssh_privatekey`, `known_hosts` (`internal/providers/proxmox/ssh.go`).

The Secret must be in the **same namespace as the `Provider`** (the pod mounts it as a volume). Whoever can read Secrets in that namespace can read the hypervisor credentials, so keep the namespace of a shared `Provider` administrator-only (tenants use the Provider from their own namespaces through `consumerNamespaceSelector`; see [Security](../../operations/security.md#cross-namespace-use-of-a-provider)).

The implication: **every example below must produce a Secret whose `.data` keys match those filenames exactly**. Wrong key names = silent credential failure at provider startup (validation will fail with "no valid credentials found in environment variables or mounted files" for libvirt, or "username and password are required" for vSphere).

## Per-provider key requirements (authoritative)

### vSphere

```yaml
# The Secret your ExternalSecret must produce
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-prod-credentials
type: Opaque
data:
  username: <base64>  # vCenter SSO principal, e.g. virtrigaud@vsphere.local
  password: <base64>
```

Optional additional fields are not consumed by the vSphere provider. Do **not** include `server` or `endpoint` in the Secret — the endpoint comes from `Provider.spec.endpoint`, not from credentials.

### Libvirt (SSH password auth)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: libvirt-prod-credentials
type: Opaque
data:
  username: <base64>  # SSH username (also injected into qemu+ssh:// URI)
  password: <base64>  # SSH password
```

### Libvirt (SSH key auth — preferred)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: libvirt-prod-credentials
type: Opaque
data:
  username: <base64>          # SSH username
  ssh-privatekey: <base64>    # PEM-encoded SSH private key
  known_hosts: <base64>       # host-key trust for the libvirt host (ssh-keyscan -H <host>)
```

The key name is `ssh-privatekey` (hyphen, no underscore) for libvirt. **`known_hosts` is required** unless you set the audit-flagged `LIBVIRT_INSECURE_SKIP_HOST_KEY_VERIFICATION=true`: without it the connection hard-fails (there is no trust-on-first-use). The same applies to the password variant above. See [Security](../../operations/security.md#libvirt-ssh-host-key-verification).

For a **clustered** libvirt Provider, each `Host` uses the Secret named by its own `spec.credentialSecretRef` if set, otherwise the Provider's `spec.credentialSecretRef`; both are read from the Provider's namespace and carry the same `ssh-privatekey` / `known_hosts` keys. See the [clustered libvirt guide](../../guides/clustered/index.md).

### Proxmox (API token — required for production)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: proxmox-prod-credentials
type: Opaque
data:
  token_id: <base64>      # e.g. virtrigaud@pve!vrtg-token
  token_secret: <base64>  # the token's UUID value
```

For disk migration and `qemu-img` on the PVE node the provider also uses an SSH **data plane**; add its credentials to the same Secret (all optional if you do not use those features):

```yaml
  ssh_user: <base64>        # SSH user on the PVE node
  ssh_privatekey: <base64>  # or ssh_password
  known_hosts: <base64>     # host-key trust; verification is on by default
```

Give each Proxmox `Provider` its own API token.

### Proxmox (password — development/CI only)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: proxmox-dev-credentials
type: Opaque
data:
  username: <base64>  # e.g. virtrigaud@pve
  password: <base64>
```

See the [Proxmox provider page](../proxmox.md#authentication) for why API tokens are required in production.

## Installing ESO

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace \
  --set installCRDs=true
```

## HashiCorp Vault

### SecretStore

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-virtrigaud
  namespace: virtrigaud-system
spec:
  provider:
    vault:
      server: "https://vault.internal.example.com:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "virtrigaud"
          serviceAccountRef:
            name: external-secrets
```

The Vault role `virtrigaud` should be bound to the `external-secrets` ServiceAccount in `virtrigaud-system` and have policy granting `read` on `secret/data/virtrigaud/*`.

### vSphere via Vault

Stored in Vault at `secret/data/virtrigaud/vsphere-prod`:

```json
{
  "username": "virtrigaud@vsphere.local",
  "password": "..."
}
```

Materialise as a K8s Secret with the correct keys:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: vsphere-prod-credentials
  namespace: virtrigaud-system
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-virtrigaud
    kind: SecretStore
  target:
    name: vsphere-prod-credentials  # must match Provider.spec.credentialSecretRef.name
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: secret/data/virtrigaud/vsphere-prod
        property: username
    - secretKey: password
      remoteRef:
        key: secret/data/virtrigaud/vsphere-prod
        property: password
```

### Libvirt SSH key via Vault

Stored at `secret/data/virtrigaud/libvirt-prod`:

```json
{
  "username": "virtrigaud",
  "ssh_privatekey": "-----BEGIN OPENSSH PRIVATE KEY-----\n...",
  "known_hosts": "libvirt-host.example.com ssh-ed25519 AAAA..."
}
```

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: libvirt-prod-credentials
  namespace: virtrigaud-system
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-virtrigaud
    kind: SecretStore
  target:
    name: libvirt-prod-credentials
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: secret/data/virtrigaud/libvirt-prod
        property: username
    # NOTE the secretKey value: ssh-privatekey (hyphen), matching the file
    # that the libvirt provider reads. The Vault property
    # name on the right is whatever you store it under; the LEFT side must
    # match the provider's expected filename exactly.
    - secretKey: ssh-privatekey
      remoteRef:
        key: secret/data/virtrigaud/libvirt-prod
        property: ssh_privatekey
    # known_hosts is required unless host-key verification is explicitly
    # disabled (there is no trust-on-first-use).
    - secretKey: known_hosts
      remoteRef:
        key: secret/data/virtrigaud/libvirt-prod
        property: known_hosts
```

### Proxmox API token via Vault

Stored at `secret/data/virtrigaud/proxmox-prod`:

```json
{
  "token_id": "virtrigaud@pve!vrtg-token",
  "token_secret": "12345678-1234-1234-1234-123456789012"
}
```

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: proxmox-prod-credentials
  namespace: virtrigaud-system
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-virtrigaud
    kind: SecretStore
  target:
    name: proxmox-prod-credentials
    creationPolicy: Owner
  data:
    - secretKey: token_id
      remoteRef:
        key: secret/data/virtrigaud/proxmox-prod
        property: token_id
    - secretKey: token_secret
      remoteRef:
        key: secret/data/virtrigaud/proxmox-prod
        property: token_secret
```

## AWS Secrets Manager

### SecretStore with IRSA

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-virtrigaud
  namespace: virtrigaud-system
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
```

The ESO ServiceAccount needs an IAM role (via IRSA annotation) with this policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-west-2:ACCOUNT:secret:virtrigaud/*"
    }
  ]
}
```

### vSphere from AWS Secrets Manager

Stored in AWS as JSON under the secret name `virtrigaud/vsphere-prod`:

```json
{ "username": "virtrigaud@vsphere.local", "password": "..." }
```

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: vsphere-prod-credentials
  namespace: virtrigaud-system
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-virtrigaud
    kind: SecretStore
  target:
    name: vsphere-prod-credentials
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: virtrigaud/vsphere-prod
        property: username
    - secretKey: password
      remoteRef:
        key: virtrigaud/vsphere-prod
        property: password
```

## Azure Key Vault

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: azure-virtrigaud
  namespace: virtrigaud-system
spec:
  provider:
    azurekv:
      vaultUrl: "https://virtrigaud-kv.vault.azure.net/"
      authType: WorkloadIdentity
      serviceAccountRef:
        name: external-secrets
```

In Azure Key Vault, store each value as a separate secret:

- `virtrigaud-vsphere-prod-username`
- `virtrigaud-vsphere-prod-password`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: vsphere-prod-credentials
  namespace: virtrigaud-system
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-virtrigaud
    kind: SecretStore
  target:
    name: vsphere-prod-credentials
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: virtrigaud-vsphere-prod-username
    - secretKey: password
      remoteRef:
        key: virtrigaud-vsphere-prod-password
```

## Google Secret Manager

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: gcp-virtrigaud
  namespace: virtrigaud-system
spec:
  provider:
    gcpsm:
      projectID: my-gcp-project
      auth:
        workloadIdentity:
          clusterLocation: us-central1
          clusterName: virtrigaud-cluster
          serviceAccountRef:
            name: external-secrets
```

Store as `projects/my-gcp-project/secrets/virtrigaud-vsphere-prod-username` etc., and reference per-key as in the Azure example.

## What ESO does NOT solve in v0.3.6

!!! note "Heading retained for stable links; limitations still apply in v0.4.0"
    This heading and its anchor (`#what-eso-does-not-solve-in-v036`) are retained so existing cross-links keep resolving. The limitations below are **still current in v0.4.0** unless noted otherwise; item 3 (mTLS material distribution) was resolved in v0.3.7.

ESO solves **provisioning** of the K8s Secret. It does **not** solve:

1. **Rotation propagation to the running provider pod.** When ESO refreshes the K8s Secret, the kubelet eventually updates the projected files inside the pod (typically within `syncFrequency`, default 1 minute), but the provider only reads the files at startup. **Rotating a credential requires a provider pod restart** (still the case in v0.4.0). There is no in-process credential reload.

    Workaround: pair the `ExternalSecret` with a deployment-restart hook (e.g. `stakater/Reloader`) keyed on the Secret name. Stakater Reloader's annotation:

    ```yaml
    metadata:
      annotations:
        reloader.stakater.com/auto: "true"
    ```

    applied to the per-Provider Deployment (which the controller owns) will trigger a rolling restart when the Secret changes. **Note**: this annotation is on the Deployment that the controller creates; you may need a small Mutating webhook or a post-reconcile patch to set it, since the controller does not currently propagate Deployment annotations from the Provider CR.

2. **Provider-side encryption-at-rest of the file.** The provider pod's tmpfs holds the credential plaintext while the pod is running. K8s does not encrypt projected Secret volumes; the cluster-level `EncryptionConfiguration` only protects etcd. A node-level attacker with root on the kubelet host can read the file.

3. **mTLS material distribution to the provider pod — resolved in v0.3.7 (unchanged in v0.4.0).** This was a v0.3.6 gap: the controller did not mount TLS material into the provider pod. Since v0.3.7 the controller mounts the TLS Secret referenced by `spec.runtime.service.tls.secretRef` at `/etc/virtrigaud/tls` and wires mTLS by default. ESO can deliver the `tls.crt` / `tls.key` / `ca.crt` keys into that Secret exactly as it does for credential Secrets. See [mTLS](mtls.md).

    !!! note "Keep TLS and credential Secrets separate"
        The TLS Secret and the credential Secret are distinct objects with different keys and mount paths (`/etc/virtrigaud/tls` vs `/etc/virtrigaud/credentials`). If you source both from ESO, produce two `ExternalSecret` resources, not one.

## Validating the materialised Secret

After ESO syncs, verify the K8s Secret has the right keys:

```bash
kubectl get secret vsphere-prod-credentials -n virtrigaud-system \
  -o jsonpath='{.data}' | jq 'keys'
# Expected for vSphere:
# [ "password", "username" ]

# For libvirt SSH key:
# [ "known_hosts", "ssh-privatekey", "username" ]

# For Proxmox API token:
# [ "token_id", "token_secret" ]
```

If a key is missing or mistyped, the provider will fail to authenticate to the hypervisor: VMs on the Provider show `Ready=False` with a provider error, and `virtrigaud_circuit_breaker_state` rises after repeated failures. The provider container logs (length-only diagnostics, never the values) tell you which key was missing. Note that the Provider's `ProviderAvailable` condition only reports that the provider *pod* is ready; it does not validate the credentials.

## See also

- [Operations -> Security: Provider credentials](../../operations/security.md#provider-credentials) — full flow diagram.
- [Bearer token authentication](bearer-token.md) — separate authentication path for the gRPC channel (not via Secrets).
- [Proxmox provider](../proxmox.md#authentication) — why API tokens are required in production.
- [Libvirt provider](../libvirt.md) — SSH credential options.
