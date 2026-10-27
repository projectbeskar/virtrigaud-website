<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# CLI Tools Reference

VirtRigaud provides a set of command-line tools for inspecting VirtRigaud resources, developing providers, validating conformance specs, and load testing. This guide covers the tools shipped in v0.4.0, with the flags and subcommands each one defines.

The tools are separate from the operator. They talk to the cluster with your kubeconfig (`vrtg-provider` only edits local files), and nothing in the manager or in a provider image depends on them.

## Overview

| Tool | Purpose | Target Users |
|------|---------|--------------|
| [`vrtg`](#vrtg) | Read VirtRigaud resources: list and describe `VirtualMachine`s, list `Provider`s | End users, DevOps teams, System administrators |
| [`vcts`](#vcts) | Conformance test spec validator and runner (the runner cannot pass yet) | Provider developers, QA teams, CI/CD pipelines |
| [`vrtg-provider`](#vrtg-provider) | Scaffold, check and catalog a new out-of-tree provider | Provider developers, Contributors |
| [`virtrigaud-loadgen`](#virtrigaud-loadgen) | Create and delete `VirtualMachine`s at a steady rate and record how long the API calls take | Performance engineers, SREs |
| [`alpha-to-beta-dryrun`](#alpha-to-beta-dryrun) | v1alpha1 migration helper (tombstone) | Operators upgrading from pre-v0.3.0 |

`vrtg`, `vcts run` and `virtrigaud-loadgen` need the VirtRigaud CRDs installed in the cluster and permission to read (`vrtg`, `vcts run`) or to create and delete (`virtrigaud-loadgen`) the resources they touch. `vcts validate` and `vcts list` read local files only and need no cluster.

!!! note "Limits in v0.4.0"
    - `vcts run` cannot pass yet: the conformance runner does not execute the steps of a specification, so the selected tests are reported as failed. `vcts validate` and `vcts list` work.
    - `virtrigaud-loadgen` simulates its `power`, `reconfigure`, `snapshot` and `clone` operations; only `create`, `delete` and `describe` call the API.
    - Some `vrtg` subcommands exist in the command tree but are not implemented; they exit non-zero and name the alternative.
    - A project made by `vrtg-provider init` builds only against a local VirtRigaud checkout, because the SDK and proto modules are not published under their own version tags.

    Each section below gives the detail.

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

`vrtg`, `vcts`, `vrtg-provider` and `virtrigaud-loadgen` are cobra programs and each has a `completion` subcommand. `<program> --version` prints the release it was built from (`dev` for a source build; `vrtg-provider` prints `dev (unknown)`). For `vrtg`:

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

The CLI for looking at VirtRigaud resources from a terminal. Defined in [`cmd/vrtg/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/vrtg/main.go).

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file (default: KUBECONFIG, in-cluster, then ~/.kube/config)
-n, --namespace       Kubernetes namespace (default: "default")
-o, --output          Output format: table, json, yaml (default: "table")
--timeout duration    Request timeout (default: 30s)
-h, --help            Help for vrtg
```

!!! note "Behaviour to be aware of"
    - **Cluster access.** Without `--kubeconfig`, `vrtg` resolves its configuration the way controller-runtime does: the `KUBECONFIG` environment variable, then in-cluster configuration, then `~/.kube/config`. A `--kubeconfig` path that cannot be loaded is an error; the tool does not fall back to another cluster.
    - **Namespaces.** The `list` commands show every namespace, with a `NAMESPACE` column, unless you pass `-n`. `describe`, `console-url`, `events` and `provider status` read the namespace given by `-n` (`default` if omitted).
    - **Output.** `-o json` and `-o yaml` work for `vm list`, `vm describe`, `provider list` and `provider status`; the output carries `apiVersion` and `kind` and leaves out `metadata.managedFields`. `vm events` and `vm console-url` always print text.
    - **Images.** A `VirtualMachine` with no `spec.imageRef` (one that boots from an imported disk) shows `<none>` as its image.

### Commands

#### vm - Virtual Machines

Aliases: `virtualmachine`, `vms`.

```bash
# List virtual machines (all namespaces unless -n is given)
vrtg vm list

# Describe a virtual machine
vrtg vm describe <name>

# Show events for a virtual machine
vrtg vm events <name>

# Print the console URL (status.consoleURL)
vrtg vm console-url <name>
```

```text
$ vrtg vm list
NAMESPACE   NAME    PROVIDER      CLASS   IMAGE       IPS      AGE
default     web-1   libvirt-prod  small   ubuntu-22   <none>   13s
```

None of the `vm` subcommands defines flags of its own; only the global flags above apply.

- `vm list` prints the columns `NAMESPACE`, `NAME`, `PROVIDER`, `CLASS`, `IMAGE`, `IPS` (from `status.ips`, `<none>` when empty) and `AGE`.
- `vm describe` prints the name, namespace, provider, class, image, desired and current power state, `status.id`, IPs, console URL, creation time and the status conditions (type, status, reason).
- `vm events` lists the Kubernetes events of that VirtualMachine in the selected namespace (`LAST SEEN`, `TYPE`, `REASON`, `MESSAGE`).
- `vm console-url` prints the URL, or `No console URL available for VM <name>`.

**Examples:**

```bash
# List all VMs
vrtg vm list

# List the VMs of one namespace, as YAML
vrtg vm list -n production -o yaml

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
# List providers (all namespaces unless -n is given)
vrtg provider list

# Show provider status
vrtg provider status <name>

# Not implemented - exits non-zero and names kubectl logs
vrtg provider logs <name>
```

- `provider list` prints `NAMESPACE`, `NAME`, `TYPE`, `ENDPOINT` (`spec.endpoint`, `<none>` when empty) and `AGE`.
- `provider status` prints the Provider's name, type, endpoint, `status.healthy` and the status conditions (type, status, reason). For everything else use `kubectl describe provider <name>`.

`provider logs` takes no flags. Read provider logs with `kubectl logs` on the provider pod.

**Examples:**

```bash
vrtg provider list
vrtg provider status vsphere-provider -n virtrigaud-system
vrtg provider status vsphere-provider -n virtrigaud-system -o json
```

#### Subcommands that are not implemented

These commands exist so the command tree is stable. They are **not implemented** in v0.4.0: each exits with a non-zero status and an error that names what to use instead. None defines flags.

| Command | Aliases | Arguments | Use instead |
|---------|---------|-----------|-------------|
| `vrtg provider logs` | none | `<name>` | `kubectl logs` |
| `vrtg snapshot create` / `list` / `revert` | `snap`, `snapshots` | `<vm-name> <snapshot-name>`, `[vm-name]`, `<vm-name> <snapshot-name>` | `VMSnapshot` resources (`kubectl get vmsnapshots`); `spec.snapshot.revertToRef` on the `VirtualMachine` to revert |
| `vrtg clone run` / `list` | `clones` | `<source-vm> <target-vm>` | `VMClone` resources (`kubectl get vmclones`) |
| `vrtg conformance run` | `conf` | `<provider>` | [`vcts run`](#vcts) |
| `vrtg diag bundle` | `diagnostics` | none | `kubectl describe` and `kubectl logs` |
| `vrtg init` | none | none | Install with [Helm](../getting-started/install-helm-only.md) |

---

## vcts

VirtRigaud Conformance Test Suite. Defined in [`cmd/vcts/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/vcts/main.go) with the runner in [`internal/conformance/`](https://github.com/projectbeskar/virtrigaud/tree/v0.4.1/internal/conformance).

!!! warning "`vcts run` cannot pass yet"
    `vcts validate` and `vcts list` work. `vcts run` connects to the cluster and reads the Provider, but the conformance runner does not execute the steps of a specification: the `create`, `update`, `delete`, `wait` and `validate` steps report "not implemented", so each selected test fails at its first step and the command exits non-zero. The runner infers a provider's capabilities from `spec.type` rather than from its status, and only `vsphere` and `libvirt` Providers select any test: for any other Provider type `vcts run` selects zero tests, prints `Total Tests: 0` and exits 0. Use `vcts validate` and `vcts list` today.

### Usage

```bash
vcts [command] [flags]
```

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file (default: KUBECONFIG, in-cluster, then ~/.kube/config)
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

A run writes `results.json`, `junit.xml` and `report.md` into the output directory, prints a summary (total, passed, failed, skipped) and exits non-zero when a test fails. Until the runner executes steps (see the warning above), every selected test fails. A Provider of a type that selects no test (anything but `vsphere` and `libvirt`) gives `Total Tests: 0` and exit status 0, and so does a run outside a checkout, where the specs directory is not found.

#### list - List Available Tests

```bash
# Print the tests defined under test/conformance/specs/ (relative to the current directory)
vcts list
```

For each test it prints the name, description and required capabilities. `vcts list` and `vcts run` read the specifications from `test/conformance/specs` **relative to the current directory**, so run them from the root of a VirtRigaud checkout.

#### validate - Validate Test Specifications

```bash
# Validate every *.yaml under test/conformance/specs/
vcts validate

# Validate another directory
vcts validate path/to/specs/
```

It takes an optional directory argument (default `test/conformance/specs`) and checks every `*.yaml` file in it. It exits **non-zero** when no spec file is found or when a file cannot be parsed or holds an invalid test (a bad test name, a missing description or step, an unknown step type, ...); the offending file is printed as `ERROR: ...`. It exits 0 only when every file is valid. The project's CI uses it on `test/conformance/specs`.

### Shipped specs

`test/conformance/specs/basic-lifecycle.yaml` defines two tests: `vm-create-delete` (requires `vm-create`, `vm-delete`) and `vm-power-cycle` (requires `vm-create`, `vm-power`, `vm-delete`).

### Output Formats

When a run completes, results are written in three formats:

- **JSON** (`results.json`): machine-readable.
- **JUnit XML** (`junit.xml`): for CI/CD integration.
- **Markdown** (`report.md`): human-readable report.

---

## vrtg-provider

Provider development toolkit for creating and checking VirtRigaud providers that live outside this repository. Defined in [`cmd/vrtg-provider/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/vrtg-provider/main.go). It edits local files only and does not talk to a cluster.

### Usage

```bash
vrtg-provider [command] [flags]
```

### Global Flags

```bash
-v, --verbose   Accepted, no effect
--version       Print the version
-h, --help      Help for vrtg-provider
```

### Commands

#### init - Initialize Provider

Bootstrap a new provider project with scaffolded code. Defined in [`cmd/vrtg-provider/init.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/vrtg-provider/init.go); the templates are in [`internal/scaffold`](https://github.com/projectbeskar/virtrigaud/tree/v0.4.1/internal/scaffold).

```bash
vrtg-provider init <provider-name> [flags]
```

**Flags:**

- `--output, -o`: Output directory for the provider project (default: `.`)
- `--type, -t`: Provider type: `generic`, `vsphere`, `libvirt`, `firecracker`, `qemu` (default: `generic`). There is no `proxmox` value.
- `--remote`: Generate remote runtime configuration (the Kubernetes manifests under `config/`)
- `--virtrigaud-path`: VirtRigaud checkout to resolve the SDK and proto modules from (default: the checkout the project is created in, if any)
- `--force`: Overwrite existing files

**Examples:**

```bash
# Create a new provider scaffolded for a vSphere-like hypervisor
vrtg-provider init myprovider --type vsphere

# Create with remote runtime configuration under ./work/providers/myprovider
vrtg-provider init myprovider --remote --output ./work

# Resolve the SDK and proto modules from a checkout elsewhere
vrtg-provider init myprovider --virtrigaud-path ~/src/virtrigaud

# Overwrite an existing scaffold
vrtg-provider init myprovider --force
```

The scaffold is created under `<output>/providers/<provider-name>/`. The provider name must be lowercase letters, digits and hyphens, start and end with a letter or digit, and be at most 63 characters. `init` stops when the target directory already contains any file, unless `--force` is given. The generated Go files are `gofmt`-clean.

**How the project finds the SDK and proto modules.** The SDK (`github.com/projectbeskar/virtrigaud/sdk`) and the protobuf bindings (`github.com/projectbeskar/virtrigaud/proto`) are separate Go modules that are **not published under their own version tags**. A generated project therefore resolves them, and the repository module they import from, from a local VirtRigaud checkout through `replace` directives in its `go.mod`:

- If the project is created inside a checkout, `init` finds it and writes the `replace` directives with a relative path (for example `=> ../../sdk` for `<checkout>/providers/<name>`).
- Otherwise pass `--virtrigaud-path <checkout>` (an absolute path is written), or edit the commented `replace` block that `init` leaves in `go.mod`.

Then, in the project directory:

```bash
go mod tidy        # first time only: resolves the modules and writes go.sum
make build         # bin/provider-<name>
make test
vrtg-provider verify
```

!!! warning "The generated Dockerfile needs a wider build context"
    The Dockerfile builds from the project directory alone, so it cannot see the checkout that the `replace` directives point at. Build the image from a context that contains both, or adjust the Dockerfile, until the modules are published under their own version tags.

`generate`, `verify` and `publish` must be run in a provider project: a directory with a `Makefile` and a `go.mod` that requires a `github.com/projectbeskar/virtrigaud` module (the repository, `sdk` or `proto`), which is what `init` creates.

#### generate - Code Generation

Regenerate protocol buffer bindings and other generated code. Defined in [`cmd/vrtg-provider/generate.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/vrtg-provider/generate.go).

Run it from within a provider project directory. It runs the project's `proto` make target, falling back to `buf generate` in `proto/`; unless `--proto-only` is given it then runs `go generate ./...` and the project's `generate` and `deepcopy` make targets when they exist. A scaffolded project imports the generated bindings from the proto module, so there is nothing to generate and the command says so.

```bash
vrtg-provider generate [flags]
```

**Flags:**

- `--proto-only`: Only regenerate protocol buffer bindings
- `--clean`: Remove `*.pb.go` files under `internal/rpc` before regenerating

**Examples:**

```bash
# Regenerate all generated code
vrtg-provider generate

# Regenerate proto bindings only
vrtg-provider generate --proto-only
```

#### verify - Verification

Check a provider project. Defined in [`cmd/vrtg-provider/verify.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/vrtg-provider/verify.go).

Run it from within a provider project directory. It runs the project's `build` and `test` make targets (or `go build` and `go test`); a failure of either fails the command. It also reports `gofmt`, `go vet` and, when installed, `golangci-lint` findings as warnings without failing.

`verify` does **not** run the conformance suite, which needs the provider deployed in a cluster. Deploy it, then run `vcts run --provider <name>` (see [`vcts`](#vcts); the runner cannot pass yet).

```bash
vrtg-provider verify [flags]
```

**Flags:**

- `--skip-build`: Skip build verification
- `--skip-tests`: Skip unit tests
- `--skip-conformance`: Skip the closing reminder that conformance was not run
- `--profile`: Deprecated and without effect

**Examples:**

```bash
# Build, check and test
vrtg-provider verify

# Build and check only
vrtg-provider verify --skip-tests
```

#### publish - Publishing

Create a catalog entry for a provider and write it to a catalog YAML file. Defined in [`cmd/vrtg-provider/publish.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/vrtg-provider/publish.go).

Run it from within a provider project directory. It builds and tests the project, then adds or updates the provider's entry in the catalog file (default: `providers/catalog.yaml`, found by walking up from the current directory). `--dry-run` prints the entry without writing it; it still runs the build and tests unless `--skip-verify` is also given. If no `providers/catalog.yaml` is found, pass `--catalog`.

!!! note "Publish records conformance as not run"
    `publish` never claims a conformance pass. It records the `core` profile as `skip` (not run) and gives the entry a "not run" badge, both after the build-and-test step and with `--skip-verify`. The entry therefore does not say the provider conforms. `publish` writes to a local catalog file; it does not open a pull request.

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
- `--skip-verify`: Skip the build and test step
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

Prints the version and git SHA. A release binary reports its release tag and `Git SHA: unknown` (the release build stamps only the version); a locally built binary reports `dev` and `unknown`. `--version` prints the version only (`dev (unknown)` for a local build).

### Provider Template Structure

The `init` command creates the following structure under `<output>/providers/<name>/`:

```
providers/my-provider/
├── main.go                      # Entry point: SDK server, logging and recovery middleware
├── internal/
│   └── provider/
│       ├── provider.go          # gRPC service: Validate, GetCapabilities; the VM operations return Unimplemented
│       ├── capabilities.go      # Capability declaration (SDK capabilities builder)
│       └── provider_test.go
├── config/
│   ├── deployment.yaml          # Kubernetes Deployment (with --remote; otherwise a comment)
│   └── service.yaml             # Kubernetes Service (with --remote; otherwise a comment)
├── .github/workflows/ci.yml     # CI workflow
├── Dockerfile
├── Makefile                     # build, test, lint, fmt, vet, docker-build, clean, deps, verify, help
├── README.md
├── .gitignore
└── go.mod
```

---

## virtrigaud-loadgen

Load generator that creates, deletes and lists `VirtualMachine` resources in a cluster and records how long each operation took. Defined in [`cmd/virtrigaud-loadgen/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/virtrigaud-loadgen/main.go).

!!! warning "Run it in a dedicated namespace"
    A run creates real `VirtualMachine` resources and leaves the ones still present when it ends in place. Point `--namespace` at a throw-away namespace, or use `--dry-run`. `delete` removes only VMs that the same run created; it never touches other VMs in the namespace.

### Usage

```bash
virtrigaud-loadgen [command] [flags]
```

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file (default: KUBECONFIG, in-cluster, then ~/.kube/config)
-n, --namespace       Kubernetes namespace to create and delete VMs in (default: "default")
-o, --output-dir      Output directory for results (default: "./loadgen-results")
--dry-run             Dry-run mode (don't create or delete Kubernetes resources)
-v, --verbose         Verbose output
-h, --help            Help for virtrigaud-loadgen
```

### Commands

#### run - Execute Load Test

```bash
virtrigaud-loadgen run [--config loadtest.yaml] [flags]
```

**Flags:**

- `-c, --config`: Load generation config file (YAML). Without it the built-in defaults apply.

Each worker performs one randomly chosen operation per second for the configured duration. The built-in defaults are:

| Parameter | Value |
|-----------|-------|
| Duration | 5 minutes |
| Concurrency (workers) | 2 |
| Providers | `test-provider` |
| VM template | `classRef: test-class`, `imageRef: test-image`, label `generated-by: loadgen`, `powerState: On` |
| Operation mix (weights) | create 20, delete 10, power 15, reconfigure 10, snapshot 5, clone 5, describe 35 |

Create the `Provider`, `VMClass` and `VMImage` named in the configuration in the namespace first. The tool does not check that they exist: a create is recorded as successful once the apiserver accepts the `VirtualMachine`, and a VM whose references are missing then fails to reconcile.

`--config` reads a YAML file that overrides the defaults; keys you leave out keep their default. Durations are Go duration strings (`30s`, `5m`).

```yaml
duration: 2m
concurrency: 4
providers: [libvirt-prod]         # a Provider in -n; one is chosen at random per operation
vmTemplate:
  classRef: small                 # an existing VMClass
  imageRef: ubuntu-22             # an existing VMImage
  labels:
    team: perf
operations:                       # relative weights, not percentages; at least one must be above 0; set 0 for what you do not want
  create: 40
  delete: 20
  describe: 40
  power: 0
  reconfigure: 0
  snapshot: 0
  clone: 0
```

An unknown key, an unparsable duration or an unusable value (no providers, all weights zero, a missing `classRef` or `imageRef`, ...) is an error and nothing is created. The keys `vmCount` (only echoed in the start-up banner), `rampUpTime`, `steadyState`, `rampDownTime`, the `*Interval` keys, `vmTemplate.annotations` and `vmTemplate.resources` are accepted but not used in v0.4.0.

**What each operation does:**

- **create** makes a `VirtualMachine` named `loadgen-vm-<run>-<worker>-<n>` with the label `generated-by: loadgen` plus your template labels.
- **delete** removes a random VM **that this run created** (`No VMs created by this run to delete` is recorded as a failure when there is none).
- **describe** lists the VMs in the namespace.
- **power**, **reconfigure**, **snapshot** and **clone** are **simulated**: they are recorded as instant successes without calling the API, so the summary does not measure those paths of the operator.

**Exit status.** `run` exits 0 whenever the run completes, even if operations failed; read `summary.md` and `results.csv` for the outcome.

**Cleanup.** VMs still present when the run ends are left in place. Remove them with:

```bash
kubectl delete virtualmachine -n <namespace> -l generated-by=loadgen
```

**Examples:**

```bash
# Dry run: records what would happen without creating or deleting VMs
virtrigaud-loadgen run --dry-run --namespace loadtest

# Real run with a config file, results in ./perf-results
virtrigaud-loadgen run --config loadtest.yaml --namespace loadtest --output-dir ./perf-results
```

### Metrics and Reporting

Results are written to `<output-dir>/results.csv` and `<output-dir>/summary.md`. Each CSV row is one operation attempt with the columns `Operation`, `Provider`, `VMName`, `StartTime`, `Duration`, `Success`, `Error`, `Phase`.

The Markdown summary contains the totals, the operation counts, and a table of count, P50, P95, P99 and max latency per operation type.

---

## manager

The `manager` binary is the VirtRigaud controller manager. It is not invoked by end users directly - it runs as a Deployment inside the cluster, installed by the Helm chart. The flags below are relevant to operators tuning its behaviour. Defined in [`cmd/manager/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/manager/main.go).

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

`vrtg vm list`, `vm describe`, `provider list` and `provider status` print JSON or YAML with `-o json` or `-o yaml`. For waiting on a condition or reading one field in a script, `kubectl` is the shorter route. For example, to wait for a VM to become ready:

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
          # exits non-zero when a spec file cannot be parsed or holds an invalid test
          ./vcts validate path/to/specs/
```

### Troubleshooting

1. **Connection issues**
```bash
# Check which cluster the tools will use
echo "${KUBECONFIG:-$HOME/.kube/config}"
kubectl cluster-info

# Check that the CLI can reach the API server
vrtg provider list
vrtg provider list --kubeconfig /path/to/kubeconfig   # or name the kubeconfig explicitly
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

A one-shot migration helper from the v1alpha1 API era. Defined in [`cmd/alpha-to-beta-dryrun/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/alpha-to-beta-dryrun/main.go).

!!! warning "Tombstoned"
    The `v1alpha1` API was removed before v0.3.0. This binary now exits with status 1 and an error message explaining that v1alpha1 resources should have been migrated before reaching this version. It is retained in the repository as a safety net, has no flags or functionality, and is not part of the release binaries.

    If you are upgrading from a pre-v0.3.0 cluster, you must have already migrated your resources to `v1beta1` in a prior release. There is no automated migration path from v1alpha1 at this version.

---

## See Also

- [Getting Started Guide](../getting-started/index.md)
- [Provider Tutorial](../providers/tutorial.md)
- [API Reference](../api-reference/cli.md)
- [Examples](../examples/index.md)
