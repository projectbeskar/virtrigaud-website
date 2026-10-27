<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# CLI Tools Reference

VirtRigaud provides a set of command-line tools for inspecting VirtRigaud resources, developing providers, validating conformance specs, and load testing. This guide covers the tools shipped in v0.4.1, with the flags and subcommands each one defines. v0.4.1 makes `vcts run` and `virtrigaud-loadgen` do what their documentation says, and adds `vrtg-provider init --type proxmox`.

The tools are separate from the operator. They talk to the cluster with your kubeconfig (`vrtg-provider` only edits local files), and nothing in the manager or in a provider image depends on them.

## Overview

| Tool | Purpose | Target Users |
|------|---------|--------------|
| [`vrtg`](#vrtg) | Read VirtRigaud resources: list and describe `VirtualMachine`s, list `Provider`s | End users, DevOps teams, System administrators |
| [`vcts`](#vcts) | Validate conformance test specifications; run the conformance tests against a `Provider` | Provider developers, QA teams, CI/CD pipelines |
| [`vrtg-provider`](#vrtg-provider) | Scaffold, check and catalog a new out-of-tree provider | Provider developers, Contributors |
| [`virtrigaud-loadgen`](#virtrigaud-loadgen) | Create, power, resize, snapshot, clone and delete `VirtualMachine`s at a steady rate and record how long the API calls (and, optionally, the provider) take | Performance engineers, SREs |
| [`alpha-to-beta-dryrun`](#alpha-to-beta-dryrun) | v1alpha1 migration helper (tombstone) | Operators upgrading from pre-v0.3.0 |

`vrtg`, `vcts run` and `virtrigaud-loadgen` need the VirtRigaud CRDs installed in the cluster and permission to read (`vrtg`) or to get, list, create, patch and delete (`vcts run`, `virtrigaud-loadgen`) the resources they touch. `vcts validate` and `vcts list` read local files only and need no cluster.

!!! note "Limits in v0.4.1"
    - `vcts run` and `virtrigaud-loadgen` create **real VMs** on the hypervisor. Run them in a throw-away namespace on a non-production cluster, and size the datastore for `virtrigaud-loadgen` (`vmCount` times the disk size, plus snapshots).
    - Some `vrtg` subcommands exist in the command tree but are not implemented; they exit non-zero and name the alternative.
    - `go install ...@v0.4.1` does not work for any of the tools (the root `go.mod` has `replace` directives); download the binaries from the release or build from a checkout.

    Each section below gives the detail.

## Installation

### From GitHub Releases

Each release publishes one binary per tool and platform, named `<tool>-<os>-<arch>` (plus `.exe` on Windows), together with a `checksums.txt`. Platforms are `linux`, `darwin` (each `amd64` and `arm64`) and `windows` (`amd64` only). The tools are `vrtg`, `vcts`, `vrtg-provider` and `virtrigaud-loadgen`.

```bash
export VIRTRIGAUD_VERSION="v0.4.1"
export PLATFORM="linux-amd64"  # or linux-arm64, darwin-amd64, darwin-arm64

for tool in vrtg vcts vrtg-provider virtrigaud-loadgen; do
  curl -fsSL "https://github.com/projectbeskar/virtrigaud/releases/download/${VIRTRIGAUD_VERSION}/${tool}-${PLATFORM}" -o "${tool}"
  chmod +x "${tool}"
done

sudo mv vrtg vcts vrtg-provider virtrigaud-loadgen /usr/local/bin/
```

`checksums.txt` lists the SHA-256 of every release binary; compare it with `sha256sum <file>` before installing.

### From Source

There is no `make` target for the CLI tools (the Makefile builds the manager and the providers). Build them with `go build`; the Go version is the one in `go.mod` (1.26.10 in v0.4.1).

```bash
git clone https://github.com/projectbeskar/virtrigaud.git
cd virtrigaud
git checkout v0.4.1

mkdir -p bin
for tool in vrtg vcts vrtg-provider virtrigaud-loadgen; do
  go build -o "bin/${tool}" "./cmd/${tool}"
done

sudo install -m 0755 bin/vrtg bin/vcts bin/vrtg-provider bin/virtrigaud-loadgen /usr/local/bin/
```

!!! note "`go install ...@v0.4.1` does not work"
    The root `go.mod` carries `replace` directives for the local `proto/` and `sdk/` modules, so `go install github.com/projectbeskar/virtrigaud/cmd/vrtg@v0.4.1` is refused by the Go toolchain. Build from a checkout as shown above.

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

These commands exist so the command tree is stable. They are **not implemented** in v0.4.1: each exits with a non-zero status and an error that names what to use instead. None defines flags.

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

VirtRigaud Conformance Test Suite. Defined in [`cmd/vcts/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/vcts/main.go) with the runner in [`internal/conformance/`](https://github.com/projectbeskar/virtrigaud/tree/v0.4.1/internal/conformance). `vcts validate` and `vcts list` read local files; `vcts run` runs the tests against a `Provider` that is deployed and healthy in the cluster.

!!! warning "`vcts run` creates real objects"
    `vcts run` (new in v0.4.1; in v0.4.0 every step reported "not implemented") creates `VirtualMachine`, `VMSnapshot`, `VMClone` and `VMClass` objects in the namespace you pass with `-n` (`default` if omitted), which make real VMs on the hypervisor. Run it against a non-production cluster, in a throw-away namespace. It touches only what its run created, and never creates, changes or deletes a `Provider`.

### Usage

```bash
vcts [command] [flags]
```

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file (default: KUBECONFIG, in-cluster, then ~/.kube/config; a path that cannot be loaded is an error)
-n, --namespace       Kubernetes namespace of the Provider under test, and where the tests create their objects (default: "default")
-v, --verbose         Verbose output: each step as it finishes
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
| `--set NAME=value` | none | Set a specification variable (repeatable). The shipped tests need `--set IMAGE=<name>`: an existing `VMImage` in the namespace that the provider can boot |
| `-o, --output-dir` | `./conformance-results` | Directory for the results |
| `--skip` | none | Test names to skip (comma-separated or repeated) |
| `--timeout` | `3h` | Timeout of the whole run |
| `--keep` | `false` | Leave the objects the tests created in place (no cleanup) |
| `--cleanup-timeout` | `10m` | Time allowed to clean up after each test, also after `--timeout` or an interrupt |
| `--parallel` | `1` | Run up to N tests at once |
| `--spec-dir` | `test/conformance/specs` | Directory of the test specifications (`*.yaml`), relative to the current directory |

```bash
# Run the shipped tests against a libvirt Provider in the vcts namespace
vcts run --provider libvirt-lab -n vcts --set IMAGE=ubuntu-22 -v

# Skip a test and set the timeout and result directory
vcts run --provider vsphere-prod -n vcts --set IMAGE=ubuntu-22 \
  --skip vm-power-cycle --timeout 1h --output-dir /tmp/test-results
```

Each test creates its objects in the namespace, waits for the operator and the provider to act on them, checks their status, then deletes everything it created. The shipped tests are:

| Test | Requires | What it checks |
|------|----------|----------------|
| `vm-create-delete` | `vm-create`, `vm-delete` | A VM becomes `Ready` and powered on, with `status.id`, phase `Running`, `status.boundProvider` and `status.currentResources`; deleting it removes it |
| `vm-power-cycle` | `vm-create`, `vm-power`, `vm-delete` | `spec.powerState` Off then On is reflected in `status.powerState` and `status.phase` |
| `vm-reconfigure-offline` | `vm-create`, `vm-reconfigure`, `vm-delete` | A powered-off VM's `spec.resources` change is recorded in `status.currentResources` |
| `vm-snapshot-create-delete` | `vm-create`, `vm-snapshot`, `vm-delete` | A `VMSnapshot` of a powered-off VM becomes `Ready` with a `status.snapshotID`; deleting it removes it |
| `vm-clone-full` | `vm-create`, `vm-clone`, `vm-delete` | A full `VMClone` of a powered-off VM becomes `Ready` and its target VM is bound to a provider VM |

(`basic-lifecycle.yaml` holds the first two; `vm-reconfigure-offline`, `vm-snapshot-create-delete` and `vm-clone-full` are new in v0.4.1.)

How it behaves:

- **Variables.** Specifications refer to `${RUN}` (the run id: six lower-case letters and digits), `${TEST}`, `${PROVIDER}` and `${NAMESPACE}`, which `vcts` sets, and to the variables you pass with `--set`. A test that refers to a variable you did not set stops the run before anything is created.
- **Names and labels.** Every object a test creates has `${RUN}` in its name, so runs never collide, and carries the labels `vcts.virtrigaud.io/run=<run id>`, `vcts.virtrigaud.io/test=<test>` and `app.kubernetes.io/managed-by=vcts`. An `update` or `delete` step acts only on an object that carries the run's label.
- **Capabilities.** A test lists `requiredCapabilities`. `vm-create`, `vm-delete`, `vm-power`, `vm-reconfigure` (a powered-off VM) and `vm-clone` (a full clone) are part of the provider contract and always offered. The others come from the Provider's `status.reportedCapabilities`: `vm-snapshot` (`supportsSnapshots`), `vm-snapshot-memory` (`supportsMemorySnapshots`), `vm-reconfigure-online` (`supportsReconfigureOnline`), `vm-clone-linked` (`supportsLinkedClones`), `image-import` (`supportsImageImport`), `disk-export` (`supportsDiskExport`) and `disk-import` (`supportsDiskImport`). A test that needs a capability the Provider does not offer is reported as **skipped**, with the reason, not failed. So is a test named with `--skip`.
- **Timeouts.** `--timeout` bounds the whole run: a test still running when it ends fails, and a test not started yet counts as **failed** ("not run"), so an interrupted or timed-out run never exits 0. A test's `timeout` (default 15m) bounds its steps; a wait step's timeout (default 5m) bounds the wait; other steps default to 1m. Waiting polls every 2 seconds. A wait fails when the object's `status.phase` has stayed `Failed` for 30 seconds (the operator retries some failed phases, such as a create in backoff).
- **Cleanup.** After its steps, whether they passed or not, each test runs its `cleanup` steps, then deletes the objects labelled with its run and test that it did not create itself (such as a clone's target VM), then the objects it created, newest first, and waits until each is gone. A `VMClone` whose provider clone may still be in flight is waited for first; one that does not settle is left in place with its source and target VMs (deleting them could leave the cloned VM on the hypervisor with nothing recording it) and the test fails. Cleanup also runs after `--timeout` or an interrupt (Ctrl-C; a second Ctrl-C exits at once), bounded by `--cleanup-timeout` per test. A cleanup that fails fails the test. `--keep` skips the cleanup and lists what was left; remove it with `kubectl delete virtualmachines,vmsnapshots,vmclones,vmclasses -n <namespace> -l vcts.virtrigaud.io/run=<run id>`.
- **Results.** `results.json`, `junit.xml` (one test case per test, the step results in `system-out`) and `report.md` (a summary, and each test's steps and cleanup) in `--output-dir`, with passed, failed or skipped per test and per step. `vcts run` exits **non-zero** when a test fails.
- **Permissions.** `vcts run` needs get, list, create, patch and delete on the kinds a specification creates in the namespace (`VirtualMachine`s, `VMSnapshot`s, `VMClone`s and `VMClass`es for the shipped tests) and get on the `Provider`.

The specification format is described in [`test/conformance/README.md`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/test/conformance/README.md).

#### list - List Available Tests

```bash
# Print the tests defined under test/conformance/specs/ (relative to the current directory)
vcts list

# Another directory
vcts list --spec-dir path/to/specs
```

For each test it prints the name, description, required capabilities and the variables it needs from `--set`. The default `--spec-dir` is relative to the current directory, so run `vcts` from the root of a VirtRigaud checkout or pass the path.

#### validate - Validate Test Specifications

```bash
# Validate every *.yaml under test/conformance/specs/
vcts validate

# Validate another directory
vcts validate path/to/specs/
```

It takes an optional directory argument (default `test/conformance/specs`) and checks every `*.yaml` file in it. It exits **non-zero** when no spec file is found or when a file cannot be parsed or holds an invalid test; the offending file is printed as `ERROR: ...`. It exits 0 only when every file is valid. The project's CI uses it on `test/conformance/specs`.

!!! warning "Stricter than in v0.4.0"
    `vcts validate` and `vcts run` decode specifications strictly. A custom specification that `vcts validate` accepted in v0.4.0 can be rejected now: an unknown key is an error; a step's resource must be an `infra.virtrigaud.io/v1beta1` kind named without a namespace; a created object's name must contain `${RUN}`; `wait` steps need a resource and a condition or `validate` entries; unknown capabilities, malformed paths, variables or regular expressions, duplicate test names and names over 63 characters are errors, and so is a step that creates, updates or deletes a `Provider`. Run `vcts validate <dir>` on your specifications before you rely on them in CI.

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
- `--type, -t`: Provider type: `generic`, `vsphere`, `libvirt`, `proxmox`, `firecracker`, `qemu` (default: `generic`). `proxmox` is new in v0.4.1.
- `--remote`: Generate remote runtime configuration (the Kubernetes manifests under `config/`)
- `--virtrigaud-path`: VirtRigaud checkout to resolve the SDK and proto modules from, with `replace` directives (for local development; see below)
- `--force`: Overwrite existing files

**Examples:**

```bash
# Create a new provider scaffolded for a vSphere-like hypervisor
vrtg-provider init myprovider --type vsphere

# Scaffold a Proxmox provider: core profile, raw/qcow2 disks, bridge/vlan networks
vrtg-provider init mypve --type proxmox

# Create with remote runtime configuration under ./work/providers/myprovider
vrtg-provider init myprovider --remote --output ./work

# Resolve the SDK and proto modules from a checkout elsewhere
vrtg-provider init myprovider --virtrigaud-path ~/src/virtrigaud

# Overwrite an existing scaffold
vrtg-provider init myprovider --force
```

The scaffold is created under `<output>/providers/<provider-name>/`. The provider name must be lowercase letters, digits and hyphens, start and end with a letter or digit, and be at most 63 characters. `init` stops when the target directory already contains any file, unless `--force` is given. The generated Go files are `gofmt`-clean.

`--type` picks the platform the scaffold is written for: its README, the credentials its remote Deployment reads and the capabilities it declares. The `proxmox` type declares only the core profile and the `raw`/`qcow2` disk and `bridge`/`vlan` network types, every operation still returns `Unimplemented`, and its test asserts that no optional capability (snapshots, linked clones, online reconfigure) is advertised; add each one as you implement the operation behind it. The `vsphere`, `libvirt` and `qemu` types still declare optional capabilities (snapshots, and for `vsphere` and `libvirt` also linked clones) although every operation of a fresh scaffold returns `Unimplemented`; the capabilities a scaffold advertises are the ones `New()` builds in `internal/provider/provider.go`, so review them before you deploy one.

**How the project finds the SDK and proto modules.** The SDK (`github.com/projectbeskar/virtrigaud/sdk`) and the protobuf bindings (`github.com/projectbeskar/virtrigaud/proto`) are separate Go modules. Since v0.4.1 every release publishes them under their own tags (`sdk/vX.Y.Z` and `proto/vX.Y.Z`, see [Go modules](../development/providers.md#go-modules-the-sdk-and-proto)); releases up to v0.4.0 have no such tags. Where the generated `go.mod` gets them from depends on the `vrtg-provider` binary and its flags:

- **A release binary** (downloaded from a GitHub release; `vrtg-provider version` prints a version such as `v0.4.1`) requires the VirtRigaud, SDK and proto modules at its own version, with no `replace` directives, also when the project is created inside a checkout. The `go` directive is the Go version the binary was built with.
- **`--virtrigaud-path <checkout>`** overrides that, for local development: `go.mod` gets `replace` directives that resolve the three modules from the checkout (an absolute path, or a relative one when the project is inside the checkout), and the checkout's `go` directive.
- **A development build** (built from a checkout without a release version, for example with `go build ./cmd/vrtg-provider`) finds the checkout the project is created in and writes the `replace` directives with a relative path (for example `=> ../../sdk` for `<checkout>/providers/<name>`). Outside a checkout, `go.mod` requires placeholder versions (`v0.0.0`) and leaves a commented `replace` block: set the three versions to a release, fill in the `replace` block, or pass `--virtrigaud-path`.

Then, in the project directory:

```bash
go mod tidy        # first time only: resolves the modules and writes go.sum
make build         # bin/provider-<name>
make test
vrtg-provider verify
```

!!! note "Building the image"
    The generated `Dockerfile` builds from the project directory alone (`go.mod` and `go.sum` first, then the source; run `go mod tidy` once so that `go.sum` exists). A project that requires a release of the modules builds that way. A project whose `go.mod` has `replace` directives to a checkout cannot: the checkout is not in the build context, and the generated `Dockerfile` says so in a comment. Build such an image from a context that contains both, or switch `go.mod` to a release before building.

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

`verify` does **not** run the conformance suite, which needs the provider deployed in a cluster. Deploy it, then run `vcts run --provider <name> --set IMAGE=<vmimage>` (see [`vcts`](#vcts)).

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

Load generator that creates, powers, resizes, snapshots, clones and deletes `VirtualMachine` resources in a cluster and records how long each operation took. Defined in [`cmd/virtrigaud-loadgen/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/virtrigaud-loadgen/main.go), with the operations in [`operations.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/virtrigaud-loadgen/operations.go) and the cleanup in [`cleanup.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/virtrigaud-loadgen/cleanup.go).

!!! warning "Run it in a dedicated namespace, and size the datastore first"
    Since v0.4.1 `power`, `reconfigure`, `snapshot` and `clone` act on the hypervisor (in v0.4.0 they were recorded as successful without any call), and `create` and `clone` make real VMs. On providers that copy disks (a Proxmox full clone, a libvirt volume copy) each VM can occupy the whole size of its disk, and an earlier release, which accepted `vmCount` but ignored it, filled a small Proxmox thin pool to 100%. A run now keeps at most **`vmCount`** VMs alive at once (default 10), and the worst case is **`vmCount` times the disk size** of the image or source VM, plus snapshots, which `vmCount` does not limit. Pick `vmCount` so that fits with room to spare, point `--namespace` at a throw-away namespace, and run with `--cleanup` so nothing outlives the run. `--dry-run` makes no API call at all.

### Usage

```bash
virtrigaud-loadgen [command] [flags]
```

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file (default: KUBECONFIG, in-cluster, then ~/.kube/config)
-n, --namespace       Kubernetes namespace to create the objects in (default: "default")
-o, --output-dir      Output directory for results (default: "./loadgen-results")
--dry-run             Dry-run mode: no API calls at all, no kubeconfig needed
-v, --verbose         Verbose output
-h, --help            Help for virtrigaud-loadgen
```

### Commands

#### run - Execute Load Test

```bash
virtrigaud-loadgen run [--config loadtest.yaml] [flags]
```

**Flags:**

| Flag | Default | Description |
|------|---------|-------------|
| `-c, --config` | none | Load generation config file (YAML). Without it the built-in defaults apply |
| `--observe` | `false` | After each accepted request, poll the object until its status reflects it and record the time |
| `--observe-timeout` | `5m` | How long `--observe` waits per operation |
| `--cleanup` | `false` | Delete everything the run created at the end (also after an interrupt) |
| `--cleanup-timeout` | `10m` | Time allowed for `--cleanup` |

Each worker performs one randomly chosen operation per second for the configured duration. Without `--config` the built-in defaults apply: 5 minutes, 2 workers, at most 10 VMs alive at once, VMs created against a provider named `test-provider` with class `test-class` and image `test-image`, and the operation mix create 20, delete 10, power 15, reconfigure 10, snapshot 5, clone 5, describe 35. Create the `Provider`, `VMClass` and `VMImage` named in the configuration first. The tool does not check that they exist.

`--config` reads a YAML file that overrides the defaults; keys you leave out keep their default. Durations are Go duration strings (`30s`, `5m`).

```yaml
duration: 2m
concurrency: 4
providers: [libvirt-lab]          # a Provider in -n; one is chosen at random per create
vmCount: 6                        # the most VMs the run has alive at once (default 10, at least 1)
vmTemplate:
  classRef: small                 # an existing VMClass
  imageRef: ubuntu-22             # an existing VMImage
  labels:
    team: perf
  resources:                      # optional; used by reconfigure only
    cpuRange: [1, 4]              # vCPUs (1..128); default: alternate between 1 and 2
    memoryRange: [1024, 4096]     # MiB (128..1048576); default: memory is not changed
operations:                       # relative weights, not percentages; at least one must be above 0
  create: 30
  delete: 10
  describe: 20
  power: 15
  reconfigure: 10
  snapshot: 10
  clone: 5
```

An unknown key, an unparsable duration or an unusable value (no providers, all weights zero, `vmCount` below 1, a range that is not `[min, max]` within the `VirtualMachine` `spec.resources` bounds, a missing `classRef` or `imageRef`, ...) is an error and nothing is created. In v0.4.0 the `vmTemplate.resources` ranges were accepted without being used, so a configuration with out-of-bounds ranges that ran then is rejected now. The keys `rampUpTime`, `steadyState`, `rampDownTime`, the `*Interval` keys and `vmTemplate.annotations` are accepted but not used (the run starts all workers at once, runs for `duration` and uses `operations` for the mix); the command prints a warning when a file sets one of them. `test/performance/proxmox-loadtest.yaml` in the repository is a ready configuration in this format for a Provider named `proxmox-perf`; edit the provider, class and image names for your cluster.

**`vmCount`: the cap on VMs.** It is the most VMs the run has alive at once: the VMs it created and has not deleted, the target VMs of the clones it requested, and the VMs whose delete it sent that are not yet gone (they still hold their storage). A `create` or `clone` that would go beyond it is **skipped**: no call is made, and the operation is recorded as skipped (not as a failure, and not in the totals, success rates or latencies). VMs that are not the run's, and snapshots, do not count. A configuration that omits `vmCount` is now capped at 10 VMs. Deleting frees room again, so a run with `create` weighted above `delete` reaches `vmCount` quickly and then mostly skips creates; raise the `delete` weight for churn at a steady VM count.

**What each operation does.** Every operation but `create` and `describe` acts on a VM **this run created**, chosen at random among those no other operation is using; it never touches another VM in the namespace. Patches and deletes carry the VM's UID. With no such VM available the operation is recorded as failed (`no VM created by this run is available`) and nothing is called.

| Operation | API call |
|-----------|----------|
| `create` | Creates a `VirtualMachine` `loadgen-vm-<run>-<worker>-<n>` (`spec.powerState: On`) from the template, with the labels `generated-by: loadgen` and `loadgen.virtrigaud.io/run: <run>` plus your template labels |
| `delete` | Deletes a VM of the run (its `VMSnapshot`s follow it). Never the source of a `VMClone` that has not ended: deleting it while the provider copies its disk could leave a VM on the hypervisor that nothing records |
| `describe` | Lists the `VirtualMachine`s in the namespace |
| `power` | Patches `spec.powerState` of a VM of the run to `Off`, or back to `On` |
| `reconfigure` | Patches `spec.resources.cpu` (and `spec.resources.memoryMiB` when `memoryRange` is set) of a VM of the run to a value from the range that differs from the one the run last set, which the `VirtualMachine` controller sends to the provider as a Reconfigure |
| `snapshot` | Creates a `VMSnapshot` `loadgen-snap-<run>-<n>` of a VM of the run with `retentionPolicy.deleteOnVMDelete: true` |
| `clone` | Creates a `VMClone` `loadgen-clone-<run>-<n>` (full clone, target powered off) of a VM of the run, preferring one the run powered off (some providers, libvirt among them, hold a clone of a running source until it is powered off); the operator creates its target VM, `loadgen-vm-<run>-clone-<n>`, with the run's labels. When the `VMClone` is `Ready`, the target becomes one of the run's VMs |

**How long a run takes.** The workers start no operation once `duration` has passed. An operation already in flight finishes, and so does its `--observe` wait (up to `--observe-timeout`), so a run lasts `duration` plus at most the longest operation or observation still in flight, plus the `--cleanup`. An interrupt stops the wait.

**What is measured.** `Duration` is the time of the API call alone: from sending the request until the apiserver answered. It does not include the provider's work. With **`--observe`**, after each accepted request the worker also polls the object (every second, up to `--observe-timeout`) until its status reflects the request, and records `ObservedDuration`:

| Operation | Observed when |
|-----------|---------------|
| `create` | `status.id` is set and `status.powerState` is `On` |
| `delete` | the VM is gone |
| `power` | `status.powerState` equals the requested state |
| `reconfigure` | `status.currentResources` holds the requested CPU (and memory), or the VM reports `Reconfiguring=True`, reason `RestartRequired`, for the patched generation |
| `snapshot` | the `VMSnapshot`'s `status.phase` is `Ready` |
| `clone` | the `VMClone`'s `status.phase` is `Ready` |

A VM, snapshot or clone that reaches phase `Failed`, or one not observed in time, is recorded in `ObserveError` (the API call still counts as successful). A worker waits for the observation before its next operation, so `--observe` lowers the request rate.

**Cleanup.** By default everything the run created is **left in place**, and the command prints how to remove it: `kubectl delete vmsnapshots,vmclones,virtualmachines -n <namespace> -l loadgen.virtrigaud.io/run=<run>`. With **`--cleanup`** the tool deletes, at the end (also after an interrupt), the run's `VMSnapshot`s and waits until they are gone, then its `VMClone`s, the clone target VMs that carry the run's label, its VMs and the VMs whose delete it issued during the run, and waits until they are gone, up to `--cleanup-timeout`. A `VMClone` whose provider clone may still be in flight is waited for first; one that does not settle in time is left in place with its source and target VMs. It does **not** delete the target VM of a failed `VMClone` that the operator keeps on purpose (its `TargetCleanup` condition has reason `TargetKept`, or `status.targetVMID` is set, or it has a `CloneRequested` condition): removing it could leave the cloned VM on the hypervisor with nothing recording it. The tool exits non-zero, naming what is left, when anything remains. Deleting a `VMClone`, its target or its source while the provider is still copying the disk can leave a VM on the hypervisor that no `VirtualMachine` records, and the tool cannot see it: if you delete the objects of a run yourself while clones are in progress, check the hypervisor afterwards.

**Exit status.** `0` when the run reached the end of its duration and, with `--cleanup`, the cleanup completed. **Non-zero** when the run was interrupted (`SIGINT` or `SIGTERM`): the results are saved and the `--cleanup` runs first, so a script can tell an interrupted run from a finished one by the status alone. Non-zero also when the cleanup left objects behind or the configuration was unusable. A signal that arrives while the cleanup is running does not stop it (send a second one to terminate the process at once). Operations that failed do not change the status: read `summary.md` and `results.csv`.

**Examples:**

```bash
# Dry run: no API call at all, no kubeconfig needed
virtrigaud-loadgen run --dry-run --namespace loadtest

# Real run with a config file, observing the provider, and cleaning up afterwards
virtrigaud-loadgen run --config loadtest.yaml --namespace loadtest \
  --observe --cleanup --output-dir ./perf-results
```

### Metrics and Reporting

Results are written to `<output-dir>/results.csv` and `<output-dir>/summary.md`. Each CSV row is one operation attempt with the columns `Operation`, `Provider`, `VMName`, `StartTime`, `Duration`, `Success`, `Error`, `Phase` (what was requested) and, with `--observe`, `ObservedDuration` and `ObserveError`, then `Skipped`: `true` for a create or clone skipped because of `vmCount` (also `Success=false` with no `Error`). The `Skipped` column is new in v0.4.1.

The Markdown summary contains the totals, the number of skipped operations, and a table of count and P50, P95, P99 and max latency per operation type, plus, with `--observe`, the same for the observed time. The tool has no scenarios or pass/fail thresholds: compare the summary with your own targets.

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
          curl -fsSL "https://github.com/projectbeskar/virtrigaud/releases/download/v0.4.1/vcts-linux-amd64" -o vcts
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
