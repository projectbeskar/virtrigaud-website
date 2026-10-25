<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# CLI Tools Reference

VirtRigaud provides a set of command-line tools for inspecting VirtRigaud resources, developing providers, validating conformance specs, and load testing. This guide covers the tools shipped in v0.4.0, with the flags and subcommands each one actually defines.

## Overview

| Tool | Purpose | Target Users |
|------|---------|--------------|
| [`vrtg`](#vrtg) | CLI for VMs and Providers (only `vm events` works in v0.4.0; other commands are scaffolded or fail) | End users, DevOps teams, System administrators |
| [`vcts`](#vcts) | Conformance test runner and spec validator | Provider developers, QA teams, CI/CD pipelines |
| [`vrtg-provider`](#vrtg-provider) | Provider development toolkit | Provider developers, Contributors |
| [`virtrigaud-loadgen`](#virtrigaud-loadgen) | Load generator (its cluster operations fail in v0.4.0) | Performance engineers, SREs |
| [`alpha-to-beta-dryrun`](#alpha-to-beta-dryrun) | v1alpha1 migration helper (tombstone) | Operators upgrading from pre-v0.3.0 |

!!! warning "Implementation status in v0.4.0"
    The CLI tools are early scaffolding. Verified against the v0.4.0 binaries:

    - `vrtg`: only `vm events` works. `vm list`, `vm describe`, `vm console-url`, `provider list` and `provider status` fail with `no kind is registered for the type v1beta1... in scheme`, because the client does not register the VirtRigaud API types. The other `vrtg` commands print "not implemented" and exit 0. Use `kubectl`.
    - `vcts`: `validate` and `list` work; `run` fails for the same reason before it writes any result.
    - `virtrigaud-loadgen`: create, delete and describe fail for the same reason; power, reconfigure, snapshot and clone are simulated.
    - `vrtg-provider`: `init` and `version` work (the scaffold needs fixing); `generate`, `verify` and `publish` refuse to run in any directory.

    Each section below gives the detail. Use `kubectl` for everything these tools cannot do.

## Installation

### From GitHub Releases

Each release publishes one binary per tool and platform, named `<tool>-<os>-<arch>` (plus `.exe` on Windows), together with a `checksums.txt`. Platforms are `linux`, `darwin` (each `amd64` and `arm64`) and `windows` (`amd64` only). The tools are `vrtg`, `vcts`, `vrtg-provider` and `virtrigaud-loadgen`.

```bash
export VIRTRIGAUD_VERSION="v0.4.0"
export PLATFORM="linux-amd64"  # or linux-arm64, darwin-amd64, darwin-arm64

for tool in vrtg vcts vrtg-provider virtrigaud-loadgen; do
  curl -fsSL "https://github.com/projectbeskar/virtrigaud/releases/download/${VIRTRIGAUD_VERSION}/${tool}-${PLATFORM}" -o "${tool}"
  chmod +x "${tool}"
done

sudo mv vrtg vcts vrtg-provider virtrigaud-loadgen /usr/local/bin/
```

`checksums.txt` lists the SHA-256 of every release binary; compare it with `sha256sum <file>` before installing.

### From Source

There is no `make` target for the CLI tools (the Makefile builds the manager and the providers). Build them with `go build`; the Go version is the one in `go.mod` (1.26.10 in v0.4.0).

```bash
git clone https://github.com/projectbeskar/virtrigaud.git
cd virtrigaud
git checkout v0.4.0

mkdir -p bin
for tool in vrtg vcts vrtg-provider virtrigaud-loadgen; do
  go build -o "bin/${tool}" "./cmd/${tool}"
done

sudo install -m 0755 bin/vrtg bin/vcts bin/vrtg-provider bin/virtrigaud-loadgen /usr/local/bin/
```

!!! note "`go install ...@v0.4.0` does not work"
    The root `go.mod` carries `replace` directives for the local `proto/` and `sdk/` modules, so `go install github.com/projectbeskar/virtrigaud/cmd/vrtg@v0.4.0` is refused by the Go toolchain. Build from a checkout as shown above.

### Completion

`vrtg`, `vcts`, `vrtg-provider` and `virtrigaud-loadgen` are cobra programs and each has a `completion` subcommand. For `vrtg`:

```bash
# Bash
vrtg completion bash > /etc/bash_completion.d/vrtg
source /etc/bash_completion.d/vrtg

# Zsh
vrtg completion zsh > "${fpath[1]}/_vrtg"

# Fish
vrtg completion fish > ~/.config/fish/completions/vrtg.fish

# PowerShell
vrtg completion powershell | Out-String | Invoke-Expression
```

---

## vrtg

The CLI for looking at VirtRigaud resources from a terminal. Defined in [`cmd/vrtg/main.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg/main.go).

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file (accepted but not used - see note)
-n, --namespace       Kubernetes namespace (default: "default")
-o, --output          Output format: table, json, yaml (default: "table")
--timeout duration    Request timeout (default: 30s)
-h, --help            Help for vrtg
```

!!! note "Behaviour to be aware of"
    - **Cluster access.** `--kubeconfig` is parsed but never read. `vrtg` loads its cluster configuration the way controller-runtime does: the `KUBECONFIG` environment variable, then in-cluster configuration, then `~/.kube/config`. Select a cluster with `KUBECONFIG` or `kubectl config use-context`.
    - **Output.** `--output json` and `--output yaml` are not implemented: `vm list`, `vm describe` and `provider list` print `JSON/YAML output not implemented` and exit 0. Only the table output works.
    - **Namespaces.** `vm list` and `provider list` list objects in **all** namespaces and ignore `--namespace`. `vm describe`, `vm events`, `vm console-url` and `provider status` use `--namespace`.
    - **Reads fail.** `vm list`, `vm describe`, `vm console-url`, `provider list` and `provider status` build a client without registering the `infra.virtrigaud.io/v1beta1` types and fail with `Error: failed to list VMs: no kind is registered for the type v1beta1.VirtualMachineList in scheme ...`. Only `vm events` (which uses a plain clientset) works. The behaviour described for the other commands below is what the code is written to do, not what v0.4.0 achieves; use `kubectl get virtualmachines` and `kubectl get providers`.

### Commands

#### vm - Virtual Machines

Aliases: `virtualmachine`, `vms`.

```bash
# List virtual machines (all namespaces)
vrtg vm list

# Describe a virtual machine
vrtg vm describe <name>

# Show events for a virtual machine
vrtg vm events <name>

# Print the console URL (status.consoleURL)
vrtg vm console-url <name>
```

None of the `vm` subcommands defines flags of its own; only the global flags above apply.

- `vm list` prints the columns `NAME`, `PROVIDER`, `CLASS`, `IMAGE`, `IPS` (from `status.ips`, `<none>` when empty) and `AGE`.
- `vm describe` prints the name, namespace, provider, class, image, desired and current power state, `status.id`, IPs, console URL, creation time and the status conditions (type, status, reason).
- `vm events` lists the Kubernetes events of that VirtualMachine in the selected namespace (`LAST SEEN`, `TYPE`, `REASON`, `MESSAGE`).
- `vm console-url` prints the URL, or `No console URL available for VM <name>`.

**Examples:**

```bash
# List all VMs
vrtg vm list

# Describe a VM in the production namespace
vrtg vm describe my-vm --namespace production

# Show recent events for a VM
vrtg vm events my-vm -n production

# Print the console URL
vrtg vm console-url my-vm -n production
```

#### provider - Providers

Alias: `providers`.

```bash
# List providers (all namespaces)
vrtg provider list

# Show provider status
vrtg provider status <name>

# Placeholder - prints "not implemented - use kubectl logs"
vrtg provider logs <name>
```

- `provider list` prints `NAME`, `TYPE`, `ENDPOINT` (`spec.endpoint`) and `AGE`.
- `provider status` prints the Provider's name, type, endpoint and conditions.

!!! warning "`provider status` prints a fixed `Status: Available`"
    The `Status: Available` line is a constant in the code, not derived from the Provider. Read the conditions listed under it (or `kubectl describe provider <name>`) to judge health.

`provider logs` takes no flags in v0.4.0. Read provider logs with `kubectl logs` on the provider pod.

**Examples:**

```bash
vrtg provider list
vrtg provider status vsphere-provider -n virtrigaud-system
```

#### Scaffolded commands (not implemented)

These commands exist so the command tree is stable, but they print a "not implemented" message and exit 0 (and define no flags). Use `kubectl` against the underlying resources instead.

| Command | Aliases | Arguments | Use instead |
|---------|---------|-----------|-------------|
| `vrtg snapshot create` / `list` / `revert` | `snap`, `snapshots` | `<vm-name> <snapshot-name>`, `[vm-name]`, `<vm-name> <snapshot-name>` | `kubectl` on `VMSnapshot` resources |
| `vrtg clone run` / `list` | `clones` | `<source-vm> <target-vm>` | `kubectl` on `VMClone` resources |
| `vrtg conformance run` | `conf` | `<provider>` | [`vcts run`](#vcts) |
| `vrtg diag bundle` | `diagnostics` | none | `kubectl logs` / `kubectl describe` |
| `vrtg init` | none | none | Install with [Helm](../getting-started/install-helm-only.md) |

---

## vcts

VirtRigaud Conformance Test Suite. Defined in [`cmd/vcts/main.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vcts/main.go) with the runner in [`internal/conformance/`](https://github.com/projectbeskar/virtrigaud/tree/main/internal/conformance).

!!! warning "Spec validation works; test execution does not"
    `vcts validate` and `vcts list` work. `vcts run` fails at its first step in v0.4.0: it reads the Provider with a client that does not register the VirtRigaud API types (`failed to get provider capabilities: failed to get provider <name>: no kind is registered for the type v1beta1.Provider in scheme`), so it writes no result files. Behind that, the step executor that would create, update, delete, wait for and validate resources returns "not implemented" for every step type, and the runner infers a provider's capabilities from `spec.type` rather than from its status. Treat `vcts run` as scaffolding.

### Usage

```bash
vcts [command] [flags]
```

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file (accepted but not used - KUBECONFIG / in-cluster / ~/.kube/config apply)
-n, --namespace       Kubernetes namespace of the Provider under test (default: "default")
-v, --verbose         Verbose output
-h, --help            Help for vcts
```

### Commands

#### run - Execute Tests

```bash
vcts run --provider <name> [flags]
```

**Flags:**

| Flag | Default | Description |
|------|---------|-------------|
| `-p, --provider` | none (required) | Name of the Provider resource to test, looked up in `--namespace` |
| `-o, --output-dir` | `./conformance-results` | Directory for the results |
| `--skip` | none | Test names to skip (comma-separated or repeated) |
| `--timeout` | `30m` | Overall timeout |
| `--parallel` | `1` | Accepted, but tests currently run one after another |

```bash
# Run against a Provider in the virtrigaud-system namespace
vcts run --provider vsphere-provider --namespace virtrigaud-system

# Skip tests and set the timeout and result directory
vcts run --provider libvirt-provider \
  --skip vm-power-cycle \
  --timeout 1h \
  --output-dir /tmp/test-results
```

As written in the code, a run would write `results.json`, `junit.xml` and `report.md` into the output directory and print a summary; in v0.4.0 it exits non-zero with the error above before that.

#### list - List Available Tests

```bash
# Print the tests defined under test/conformance/specs/ (relative to the current directory)
vcts list
```

For each test it prints the name, description and required capabilities. Run it from a checkout of the repository, because the spec directory is relative to the working directory.

#### validate - Validate Test Specifications

```bash
# Validate every *.yaml under test/conformance/specs/
vcts validate

# Validate another directory
vcts validate path/to/specs/
```

It takes an optional directory argument (default `test/conformance/specs`) and prints each valid test. It exits non-zero only when no spec file is found. A file that fails to parse or validate is reported as `ERROR: ...` but is then skipped, and the command still ends with `All tests are valid!` and exit status 0, so read its output rather than relying on the exit code.

### Shipped specs

`test/conformance/specs/basic-lifecycle.yaml` defines two tests: `vm-create-delete` (requires `vm-create`, `vm-delete`) and `vm-power-cycle` (requires `vm-create`, `vm-power`, `vm-delete`).

### Output Formats

When a run completes, results are written in three formats:

- **JSON** (`results.json`): machine-readable.
- **JUnit XML** (`junit.xml`): for CI/CD integration.
- **Markdown** (`report.md`): human-readable report.

---

## vrtg-provider

Provider development toolkit for creating and managing VirtRigaud providers. Defined in [`cmd/vrtg-provider/main.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg-provider/main.go).

### Usage

```bash
vrtg-provider [command] [flags]
```

### Global Flags

```bash
-v, --verbose   Enable verbose output
--version       Print the version
-h, --help      Help for vrtg-provider
```

### Commands

#### init - Initialize Provider

Bootstrap a new provider project with scaffolded code. Defined in [`cmd/vrtg-provider/init.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg-provider/init.go).

!!! warning "The generated scaffold needs fixing before it builds (v0.4.0)"
    The project that `init` writes does not compile as generated: `main.go` imports `github.com/projectbeskar/virtrigaud/internal/version` (an `internal` package that a separate Go module cannot import), `internal/provider/provider.go` has an unused `fmt` import, its `ImagePrepare` stub still returns `*TaskResponse` (the RPC now returns `ImagePrepareResponse`), and its `go.mod` pins `github.com/projectbeskar/virtrigaud v0.1.0`. Treat it as a skeleton: fix those points, or start from [`cmd/provider-mock/main.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/provider-mock/main.go) as described in [Provider Development](../development/providers.md).

```bash
vrtg-provider init <provider-name> [flags]
```

**Flags:**
- `--output, -o`: Output directory for the provider project (default: `.`)
- `--type, -t`: Provider type: `vsphere`, `libvirt`, `firecracker`, `qemu`, `generic` (default: `generic`)
- `--remote`: Generate remote runtime configuration
- `--force`: Overwrite existing files

**Examples:**

```bash
# Create a new provider scaffolded for a vSphere-like hypervisor
vrtg-provider init myprovider --type vsphere

# Create with remote runtime configuration in a specific directory
vrtg-provider init myprovider --remote --output ./providers/

# Overwrite an existing scaffold
vrtg-provider init myprovider --force
```

The scaffold is created under `<output>/providers/<provider-name>/`. The provider name must be lowercase alphanumeric with hyphens (max 63 chars). `init` refuses to overwrite existing files unless `--force` is given.

#### generate - Code Generation

!!! warning "`generate`, `verify` and `publish` do not run in v0.4.0"
    All three first check that the current directory is a provider project and always fail with `Error: not in a provider project directory: go.mod does not contain virtrigaud dependency`, even in a project created by `vrtg-provider init` (the check compares the whole `go.mod` text with the module path, so it never matches). The descriptions below are what the code is written to do.

Regenerate protocol buffer bindings and other generated code. Defined in [`cmd/vrtg-provider/generate.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg-provider/generate.go).

Must be run from within a provider project directory (the directory must contain `go.mod` and a `Makefile`, and `go.mod` must mention `github.com/projectbeskar/virtrigaud`). It runs the project's `make proto` target, falling back to `buf generate`; unless `--proto-only` is given it then runs `go generate ./...` and the project's `generate` and `deepcopy` make targets when they exist.

```bash
vrtg-provider generate [flags]
```

**Flags:**
- `--proto-only`: Only regenerate protocol buffer bindings
- `--clean`: Intended to clean generated files first; it only prints `Would remove files matching: ...` and deletes nothing

**Examples:**

```bash
# Regenerate all generated code
vrtg-provider generate

# Regenerate proto bindings only
vrtg-provider generate --proto-only

# Regenerate (--clean deletes nothing)
vrtg-provider generate --clean
```

#### verify - Verification

Verify a provider project: build, code-quality checks, unit tests and a VCTS conformance run. Defined in [`cmd/vrtg-provider/verify.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg-provider/verify.go).

Must be run from within a provider project directory. The build (`make build`, else `go build ./...`) and the unit tests (`make test`, else `go test ./...`) fail the command. The code-quality step (`gofmt -l`, `go vet`, `golangci-lint run`, `make lint`) and the conformance step only print warnings.

!!! warning "The conformance step cannot succeed in v0.4.0"
    The step runs `vcts version` and `vcts run --profile <profile> --provider mock`, but `vcts` has no `version` command and no `--profile` flag (see [`vcts`](#vcts)). It therefore always reports a conformance warning, and `--profile` has no effect. Use `--skip-conformance` to leave it out.

```bash
vrtg-provider verify [flags]
```

**Flags:**
- `--skip-build`: Skip build verification
- `--skip-tests`: Skip unit tests
- `--skip-conformance`: Skip VCTS conformance tests
- `--profile`: Conformance test profile: `core`, `snapshot`, `clone`, `advanced` (default: `core`)

**Examples:**

```bash
# Full verification
vrtg-provider verify

# Verify build and unit tests only (skip conformance)
vrtg-provider verify --skip-conformance

# Run conformance against the clone profile
vrtg-provider verify --profile clone
```

#### publish - Publishing

Create a catalog entry for a provider and write it to a catalog YAML file. Defined in [`cmd/vrtg-provider/publish.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg-provider/publish.go).

Must be run from within a provider project directory.

!!! warning "Publish does not run the conformance suite"
    The verification step of `publish` is a placeholder in v0.4.0: it records fixed results (`core`, `snapshot`, `clone` and `advanced` as `pass`, `image-prepare` as `skip`) without running `vcts` or anything else, and with `--skip-verify` it records `core: skip`. The catalog entry therefore does not prove that the provider conforms. `publish` writes to a local catalog file; it does not open a pull request.

```bash
vrtg-provider publish [flags]
```

**Required flags:**
- `--image`: Container image repository (e.g., `ghcr.io/yourorg/your-provider`)
- `--repo`: Source code repository URL
- `--maintainer`: Maintainer email address

**Optional flags:**
- `--name`: Provider name (auto-detected from current directory if omitted)
- `--tag`: Container image tag (default: `latest`)
- `--license`: License identifier in SPDX format (default: `Apache-2.0`)
- `--skip-verify`: Skip VCTS verification
- `--dry-run`: Show the catalog entry without writing it
- `--catalog`: Path to catalog YAML file (default: auto-detected `providers/catalog.yaml`)

**Examples:**

```bash
# Dry-run to preview the catalog entry
vrtg-provider publish \
  --image ghcr.io/yourorg/your-provider \
  --repo https://github.com/yourorg/your-provider \
  --maintainer you@example.com \
  --dry-run

# Publish with explicit tag
vrtg-provider publish \
  --image ghcr.io/yourorg/your-provider \
  --tag v1.0.0 \
  --repo https://github.com/yourorg/your-provider \
  --maintainer you@example.com
```

#### version - Version Information

```bash
vrtg-provider version
```

Prints the version and git SHA that are compiled into the binary (`dev` and `unknown` in a locally built binary). `--version` prints the same.

### Provider Template Structure

The `init` command creates the following structure under `<output>/providers/<name>/`:

```
providers/my-provider/
├── main.go                      # Entry point: SDK server, logging and recovery middleware
├── internal/
│   └── provider/
│       ├── provider.go          # gRPC service stubs
│       ├── capabilities.go      # Capability declaration (SDK capabilities builder)
│       └── provider_test.go
├── config/
│   ├── deployment.yaml          # Kubernetes Deployment
│   └── service.yaml             # Kubernetes Service
├── .github/workflows/ci.yml     # CI workflow
├── Dockerfile
├── Makefile                     # build, test, lint, fmt, vet, docker-build, verify, ...
├── README.md
├── .gitignore
└── go.mod
```

---

## virtrigaud-loadgen

Load generator that creates, deletes and lists `VirtualMachine` resources in a cluster and records how long each operation took. Defined in [`cmd/virtrigaud-loadgen/main.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/virtrigaud-loadgen/main.go).

!!! danger "Run it in a dedicated namespace"
    The `delete` operation deletes a **random VirtualMachine from the target namespace**; it does not restrict itself to VMs that `virtrigaud-loadgen` created. Point `--namespace` at a throw-away namespace, or use `--dry-run`.

### Usage

```bash
virtrigaud-loadgen [command] [flags]
```

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file (accepted but not used - KUBECONFIG / in-cluster / ~/.kube/config apply)
-n, --namespace       Kubernetes namespace to create and delete VMs in (default: "default")
-o, --output-dir      Output directory for results (default: "./loadgen-results")
--dry-run             Dry-run mode (don't create or delete Kubernetes resources)
-v, --verbose         Verbose output
-h, --help            Help for virtrigaud-loadgen
```

### Commands

#### run - Execute Load Test

```bash
virtrigaud-loadgen run [flags]
```

**Flags:**
- `-c, --config`: Load generation config file. **Not implemented in v0.4.0**: the command prints `Loading config from <file> (not implemented)` and carries on with the built-in defaults.

The run always uses these built-in parameters:

| Parameter | Value |
|-----------|-------|
| Duration | 5 minutes |
| Concurrency (workers) | 2 |
| Providers | `test-provider` |
| VM template | `classRef: test-class`, `imageRef: test-image`, label `generated-by: loadgen`, `powerState: On` |
| Operation mix (weights) | create 20, delete 10, power 15, reconfigure 10, snapshot 5, clone 5, describe 35 |

Each worker picks one operation at random (by those weights) about once per second. The `Provider`, `VMClass` and `VMImage` named above must exist in the namespace, or the creates are recorded as failures.

!!! danger "The cluster operations fail in v0.4.0"
    `create`, `delete` and `describe` use a client that does not register the VirtRigaud API types, so against a real cluster each one is recorded as a failure within microseconds (`--dry-run` makes `create` succeed without calling the API, but `delete` and `describe` still fail). The simulated operations succeed instantly, so the summary does not measure the operator.

The operations that were meant to touch the cluster are:

- **create** creates a `VirtualMachine` from the template.
- **delete** deletes a random VM in the namespace (`No VMs found to delete` is recorded as a failure when there are none).
- **describe** lists the VMs in the namespace.

The **power**, **reconfigure**, **snapshot** and **clone** operations are placeholders: they record an instant success without calling the API.

**Examples:**

```bash
# Dry run: records what would happen without creating or deleting VMs
virtrigaud-loadgen run --dry-run --namespace loadtest

# Real run (records failures for the API operations in v0.4.0), results in ./perf-results
virtrigaud-loadgen run --namespace loadtest --output-dir ./perf-results
```

### Metrics and Reporting

Results are written to `<output-dir>/results.csv` and `<output-dir>/summary.md`. Each CSV row is one operation attempt with the columns `Operation`, `Provider`, `VMName`, `StartTime`, `Duration`, `Success`, `Error`, `Phase`.

The Markdown summary contains the totals, the operation counts, and a table of count, P50, P95, P99 and max latency per operation type.

---

## manager

The `manager` binary is the VirtRigaud controller manager. It is not invoked by end users directly - it runs as a Deployment inside the cluster, installed by the Helm chart. The flags below are relevant to operators tuning its behaviour. Defined in [`cmd/manager/main.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/manager/main.go).

`manager --version` (as the first argument) prints the version and exits. The other flags use Go's `flag` syntax (`-flag` and `--flag` are equivalent), and the standard controller-runtime `--zap-*` logging flags are also accepted.

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--metrics-bind-address` | `:8080` | Address the metrics endpoint binds to. |
| `--health-probe-bind-address` | `:8081` | Address the health and readiness probes bind to. |
| `--leader-elect` | `false` | Enable leader election so only one manager is active. |
| `--metrics-secure` | `false` | Serve metrics over HTTPS with authentication and authorization (RBAC). |
| `--metrics-cert-path` / `--metrics-cert-name` / `--metrics-cert-key` | empty / `tls.crt` / `tls.key` | Directory and file names of the metrics server certificate; a non-empty path enables hot reload. |
| `--webhook-cert-path` / `--webhook-cert-name` / `--webhook-cert-key` | empty / `tls.crt` / `tls.key` | Directory and file names of the webhook certificate. The chart sets the path when webhooks are enabled. |
| `--enable-http2` | `false` | Enable HTTP/2 for the metrics and webhook servers (disabled by default). |
| `--enforce-provider-capabilities` | `false` | Gate snapshot and migration operations on the provider's self-reported capabilities (see below). |
| `--migration-storage-allowed-hosts` | empty | Comma-separated IP/CIDR allow-list for migration staging backends (the S3 endpoint host and the NFS server). Empty permits everything except the always-denied loopback, link-local, metadata and multicast targets. |
| `--provider-tmp-size-limit` | empty | `sizeLimit` of the writable `/tmp` volume of every provider pod the manager runs: a positive quantity such as `20Gi`, or `none` for no limit. Empty keeps the per-type defaults (vSphere 512Gi, others 1Gi). A Provider's `infra.virtrigaud.io/tmp-size-limit` annotation overrides it. |
| `--provider-tmp-size-limit-max` | empty | Ceiling on that `/tmp` `sizeLimit`: a positive quantity, or empty for no ceiling. With it set, a larger annotation value (or `none`) is clamped to it with a Warning event, and `--provider-tmp-size-limit` and the per-type defaults are capped at it. |
| `--max-disk-size` | empty | Administrator's ceiling on the size of every disk VirtRigaud creates or grows: a whole number of bytes from `1Gi` to `64Pi`, such as `500Gi` (use binary units: `500G` is about 465.7Gi). Empty means no ceiling beyond the CRD bounds. A Provider's `infra.virtrigaud.io/max-disk-size` annotation can only lower it. Larger existing disks are kept and never shrunk. An invalid value stops the manager at startup. |

The last three were added after v0.3.11. The circuit-breaker thresholds and the gRPC dial timeout are not command-line flags.

### Setting flags with Helm

The chart always passes `--metrics-bind-address`, `--health-probe-bind-address`, `--leader-elect` and, when webhooks are enabled, `--webhook-cert-path`. Three flags have chart values:

```yaml
manager:
  providerTmpSizeLimit: "20Gi"       # --provider-tmp-size-limit
  providerTmpSizeLimitMax: "200Gi"   # --provider-tmp-size-limit-max
  maxDiskSize: "500Gi"               # --max-disk-size (also renders the VM/VMClass disk-size admission webhooks when webhooks.enabled=true)
```

The chart has no generic `extraArgs` value, so `--enforce-provider-capabilities` and `--migration-storage-allowed-hosts` cannot be set through `values.yaml`. Append them to the manager container's arguments, for example:

```bash
# Find the manager Deployment (its name depends on the Helm release name)
kubectl -n virtrigaud-system get deployment -l app.kubernetes.io/component=manager

kubectl -n virtrigaud-system patch deployment <manager-deployment> --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--enforce-provider-capabilities"}]'
```

A later `helm upgrade` re-renders the Deployment and drops the patch; re-apply it (or use a Helm post-renderer) after each upgrade.

### `--enforce-provider-capabilities` (added v0.3.8)

When **OFF** (default): snapshot and migration controllers issue their provider RPCs unconditionally. If a provider cannot handle the operation, the RPC fails and the resource moves to `Failed`.

When **ON**: the snapshot and migration controllers first check what the provider reports (it is also shown in `Provider.status.reportedCapabilities`) and refuse capability-dependent operations that the provider explicitly does not advertise, rather than letting the call fail downstream.

!!! warning "Enable with caution"
    A provider that under-reports a capability (reports `false` for an operation it can actually perform) will have that operation blocked. Confirm your provider's capability flags are accurate before enabling this flag. The flag is intentionally opt-in.

---

## Scripting and CI

### Scripting

`vrtg` has no machine-readable output (`--output json|yaml` is not implemented), so use `kubectl` for scripts. For example, to wait for a VM to become ready:

```bash
kubectl wait --for=condition=Ready virtualmachine/my-vm -n production --timeout=300s
```

and to read its power state:

```bash
kubectl get virtualmachine my-vm -n production -o jsonpath='{.status.powerState}'
```

### CI

The project's own CI builds `vrtg`, `vcts`, `vrtg-provider` and `virtrigaud-loadgen` with `go build` and validates the conformance specs with `vcts validate test/conformance/specs/`. A provider repository can do the same with the released binary:

```yaml
# .github/workflows/specs.yml
name: Validate conformance specs

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install vcts
        run: |
          curl -fsSL "https://github.com/projectbeskar/virtrigaud/releases/download/v0.4.0/vcts-linux-amd64" -o vcts
          chmod +x vcts

      - name: Validate specs
        run: |
          # vcts validate exits 0 even when a spec is invalid; fail on its ERROR lines
          ./vcts validate path/to/specs/ | tee validate.out
          ! grep -q 'ERROR' validate.out
```

### Troubleshooting

1. **Connection issues**
```bash
# Check which cluster the tools will use
echo "${KUBECONFIG:-$HOME/.kube/config}"
kubectl cluster-info

# Check that the CLI can reach the API server
vrtg provider list
```

2. **Permission issues**
```bash
# vrtg reads VirtualMachines and Providers (and, for `vm events`, Events)
kubectl auth can-i list virtualmachines.infra.virtrigaud.io --all-namespaces
kubectl auth can-i list providers.infra.virtrigaud.io --all-namespaces
```

3. **Provider issues**
```bash
vrtg provider status <provider-name> -n <namespace>
kubectl describe provider <provider-name> -n <namespace>
kubectl logs -n <namespace> -l app.kubernetes.io/instance=<provider-name>
```

---

## alpha-to-beta-dryrun

A one-shot migration helper from the v1alpha1 API era. Defined in [`cmd/alpha-to-beta-dryrun/main.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/alpha-to-beta-dryrun/main.go).

!!! warning "Tombstoned"
    The `v1alpha1` API was removed before v0.3.0. This binary now exits with status 1 and an error message explaining that v1alpha1 resources should have been migrated before reaching this version. It is retained in the repository as a safety net, has no flags or functionality, and is not part of the release binaries.

    If you are upgrading from a pre-v0.3.0 cluster, you must have already migrated your resources to `v1beta1` in a prior release. There is no automated migration path from v1alpha1 at this version.

---

## See Also

- [Getting Started Guide](../getting-started/index.md)
- [Provider Development](../providers/tutorial.md)
- [API Reference](../api-reference/cli.md)
- [Examples](../examples/index.md)
