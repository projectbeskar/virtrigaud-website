<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# CLI Reference

VirtRigaud provides several command-line tools for inspecting resources, validating conformance specs, developing providers, and load testing. This reference covers v0.4.0 and lists the commands and flags the tools actually define. For longer explanations and caveats see the [CLI Tools Reference](../references/cli-tools.md).

## Overview

| Tool | Purpose | Target Users |
|------|---------|--------------|
| [`vrtg`](#vrtg) | Read-only CLI for VMs and Providers | End users, DevOps teams |
| [`vcts`](#vcts) | Conformance test runner and spec validator | Provider developers, QA teams |
| [`vrtg-provider`](#vrtg-provider) | Provider development toolkit | Provider developers |
| [`virtrigaud-loadgen`](#virtrigaud-loadgen) | Load generator | Performance engineers |
| [`alpha-to-beta-dryrun`](#alpha-to-beta-dryrun) | v1alpha1 migration helper (tombstone) | Pre-v0.3.0 upgraders |

## Installation

### From GitHub Releases

Each release publishes one binary per tool and platform, named `<tool>-<os>-<arch>` (`.exe` on Windows), plus a `checksums.txt`. Platforms are `linux` and `darwin` (each `amd64` and `arm64`) and `windows` (`amd64`).

```bash
# Download v0.4.0
curl -fsSL "https://github.com/projectbeskar/virtrigaud/releases/download/v0.4.0/vrtg-linux-amd64" -o vrtg
chmod +x vrtg
sudo mv vrtg /usr/local/bin/
```

The same naming applies to `vcts`, `vrtg-provider` and `virtrigaud-loadgen`.

### From Source

There are no `make` targets for the CLI tools; build them with `go build` from a checkout of the release tag.

```bash
git clone https://github.com/projectbeskar/virtrigaud.git
cd virtrigaud
git checkout v0.4.0

mkdir -p bin
for tool in vrtg vcts vrtg-provider virtrigaud-loadgen; do
  go build -o "bin/${tool}" "./cmd/${tool}"
done
```

`go install github.com/projectbeskar/virtrigaud/cmd/<tool>@v0.4.0` is not supported: the root `go.mod` has `replace` directives for the local `proto/` and `sdk/` modules, which `go install` with a version suffix rejects.

## vrtg

CLI for looking at VirtRigaud resources. Source: [`cmd/vrtg/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/cmd/vrtg/main.go).

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file (accepted but not used; set KUBECONFIG instead)
-n, --namespace       Kubernetes namespace (default: "default")
-o, --output          Output format: table, json, yaml (default: "table"; json and yaml are not implemented)
--timeout duration    Request timeout (default: 30s)
-h, --help            Help for vrtg
```

### Commands

| Command | Aliases | Status | Description |
|---------|---------|--------|-------------|
| `vrtg vm list` | `virtualmachine`, `vms` | Fails in v0.4.0 | List VirtualMachines in all namespaces (name, provider, class, image, IPs, age). |
| `vrtg vm describe <name>` | | Fails in v0.4.0 | Show one VirtualMachine: provider, class, image, power state, IDs, IPs, console URL, conditions. |
| `vrtg vm events <name>` | | Works | Show the Kubernetes events of a VirtualMachine in `--namespace`. |
| `vrtg vm console-url <name>` | | Fails in v0.4.0 | Print `status.consoleURL`. |
| `vrtg provider list` | `providers` | Fails in v0.4.0 | List Providers in all namespaces (name, type, endpoint, age). |
| `vrtg provider status <name>` | | Fails in v0.4.0 | Show a Provider's type, endpoint and conditions. |
| `vrtg provider logs <name>` | | Placeholder | Prints "not implemented - use kubectl logs". |
| `vrtg snapshot create <vm> <snapshot>`, `list [vm]`, `revert <vm> <snapshot>` | `snap`, `snapshots` | Placeholder | Print "not implemented". |
| `vrtg clone run <source> <target>`, `list` | `clones` | Placeholder | Print "not implemented". |
| `vrtg conformance run <provider>` | `conf` | Placeholder | Prints "not implemented"; use [`vcts`](#vcts). |
| `vrtg diag bundle` | `diagnostics` | Placeholder | Prints "not implemented". |
| `vrtg init` | | Placeholder | Prints "not implemented". |
| `vrtg completion bash\|zsh\|fish\|powershell` | | Implemented | Generate a shell completion script. |

None of the subcommands defines flags beyond the global ones. Placeholder commands print a message and exit 0. `vm list` and `provider list` ignore `--namespace`.

```bash
vrtg vm list
vrtg vm describe my-vm -n production
vrtg vm events my-vm -n production
vrtg provider status vsphere-prod -n virtrigaud-system
```

### Cluster access

`vrtg` uses controller-runtime's default configuration loading: the `KUBECONFIG` environment variable, then in-cluster configuration, then `~/.kube/config`. There is no `~/.vrtg/config.yaml` and `vrtg` reads no `VRTG_*` environment variables.

## vcts

VirtRigaud Conformance Test Suite. Source: [`cmd/vcts/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/cmd/vcts/main.go).

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file (accepted but not used; set KUBECONFIG instead)
-n, --namespace       Namespace of the Provider under test (default: "default")
-v, --verbose         Verbose output
-h, --help            Help for vcts
```

### Commands

#### run

Run conformance tests against a Provider resource.

| Flag | Default | Description |
|------|---------|-------------|
| `-p, --provider` | required | Provider name to test |
| `-o, --output-dir` | `./conformance-results` | Directory for `results.json`, `junit.xml` and `report.md` |
| `--skip` | none | Test names to skip |
| `--timeout` | `30m` | Test timeout |
| `--parallel` | `1` | Accepted, but tests run sequentially |

```bash
vcts run --provider vsphere-prod --namespace virtrigaud-system --skip vm-power-cycle
```

!!! warning "`vcts run` fails in v0.4.0"
    It reads the Provider with a client that does not register the VirtRigaud API types and exits with `no kind is registered for the type v1beta1.Provider in scheme` before writing any result. Behind that, the step executor returns "not implemented" for every step type. See the [CLI Tools Reference](../references/cli-tools.md#vcts).

#### list

Print the tests defined in `test/conformance/specs/` (relative to the current directory) with their descriptions and required capabilities.

#### validate

Validate the YAML test specifications. Takes an optional directory argument (default `test/conformance/specs`). It exits non-zero only when no spec file is found; an invalid file is printed as `ERROR: ...` but does not change the exit status (v0.4.0).

```bash
vcts validate test/conformance/specs/
```

The repository ships `test/conformance/specs/basic-lifecycle.yaml` with two tests, `vm-create-delete` and `vm-power-cycle`. There are no test suites, `--suite`, `--suites` or `--config` options.

## vrtg-provider

Development toolkit for provider projects. Source: [`cmd/vrtg-provider/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/cmd/vrtg-provider/main.go).

### Global Flags

```bash
-v, --verbose       Enable verbose output
--version           Print the version
-h, --help          Help for vrtg-provider
```

### Commands

#### init

Initialize a new provider project. Source: [`cmd/vrtg-provider/init.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/cmd/vrtg-provider/init.go).

```bash
vrtg-provider init <provider-name> [flags]
```

| Flag | Default | Description |
|------|---------|-------------|
| `-o, --output` | `.` | Output directory; the project is written to `<output>/providers/<provider-name>/` |
| `-t, --type` | `generic` | Provider type: `vsphere`, `libvirt`, `firecracker`, `qemu`, `generic` |
| `--remote` | `false` | Generate remote runtime configuration |
| `--force` | `false` | Overwrite existing files |

```bash
vrtg-provider init myprovider --type libvirt --output ./providers/
```

!!! warning "The scaffold needs fixing before it builds"
    In v0.4.0 the generated project does not compile as written (it imports the main module's `internal/version`, has an unused import, and a stale `ImagePrepare` signature). See [`vrtg-provider init`](../references/cli-tools.md#init-initialize-provider).

#### generate

!!! warning "`generate`, `verify` and `publish` do not run in v0.4.0"
    Each first checks that the directory is a provider project and always fails with `not in a provider project directory: go.mod does not contain virtrigaud dependency`, even in a project created by `init`. See the [CLI Tools Reference](../references/cli-tools.md#generate-code-generation).

Regenerate protocol buffer bindings. Source: [`cmd/vrtg-provider/generate.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/cmd/vrtg-provider/generate.go). Run from within a provider project directory (`go.mod` and `Makefile` required).

| Flag | Default | Description |
|------|---------|-------------|
| `--proto-only` | `false` | Only regenerate proto bindings |
| `--clean` | `false` | Intended to clean first; it only prints `Would remove files matching: ...` and deletes nothing |

#### verify

Build, check, test and (best effort) conformance-check a provider project. Source: [`cmd/vrtg-provider/verify.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/cmd/vrtg-provider/verify.go). Run from within a provider project directory.

| Flag | Default | Description |
|------|---------|-------------|
| `--skip-build` | `false` | Skip build check |
| `--skip-tests` | `false` | Skip unit tests |
| `--skip-conformance` | `false` | Skip the VCTS conformance step |
| `--profile` | `core` | Conformance profile: `core`, `snapshot`, `clone`, `advanced` |

The conformance step invokes `vcts version` and `vcts run --profile`, neither of which exists in `vcts`, so it only ever prints a warning; use `--skip-conformance`.

```bash
vrtg-provider verify --skip-conformance
```

#### publish

Write a catalog entry for a provider. Source: [`cmd/vrtg-provider/publish.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/cmd/vrtg-provider/publish.go). Run from within a provider project directory.

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--image` | Yes | | Container image repository |
| `--repo` | Yes | | Source code repository URL |
| `--maintainer` | Yes | | Maintainer email |
| `--name` | No | directory name | Provider name |
| `--tag` | No | `latest` | Image tag |
| `--license` | No | `Apache-2.0` | SPDX license identifier |
| `--skip-verify` | No | `false` | Skip the verification step |
| `--dry-run` | No | `false` | Print the catalog entry without writing it |
| `--catalog` | No | auto-detect | Path to `providers/catalog.yaml` |

The verification step records fixed placeholder results; it does not run the conformance suite.

```bash
vrtg-provider publish \
  --image ghcr.io/yourorg/myprovider \
  --repo https://github.com/yourorg/myprovider \
  --maintainer you@example.com \
  --dry-run
```

#### version

```bash
vrtg-provider version
```

Prints the version and git SHA compiled into the binary (`dev` / `unknown` for a locally built binary).

## virtrigaud-loadgen

Load generator for VirtualMachine create, delete and list operations. In v0.4.0 those three operations fail against a real cluster (the client does not register the VirtRigaud API types); see the [CLI Tools Reference](../references/cli-tools.md#virtrigaud-loadgen). Source: [`cmd/virtrigaud-loadgen/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/cmd/virtrigaud-loadgen/main.go).

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file (accepted but not used; set KUBECONFIG instead)
-n, --namespace       Namespace to create and delete VMs in (default: "default")
-o, --output-dir      Output directory for results (default: "./loadgen-results")
--dry-run             Don't create or delete Kubernetes resources
-v, --verbose         Verbose output
-h, --help            Help for virtrigaud-loadgen
```

### Commands

#### run

```bash
virtrigaud-loadgen run [flags]
```

| Flag | Description |
|------|-------------|
| `-c, --config` | Load generation config file. Not implemented in v0.4.0: the file is not read and built-in defaults apply (5 minutes, 2 workers, provider `test-provider`, class `test-class`, image `test-image`). |

```bash
# Dry run
virtrigaud-loadgen run --dry-run --namespace loadtest

# Real run into a dedicated namespace
virtrigaud-loadgen run --namespace loadtest --output-dir ./perf-results
```

The `delete` operation removes a random VirtualMachine from the target namespace (not only ones the tool created), so always use a dedicated namespace. Only create, delete and describe (a list) call the API; power, reconfigure, snapshot and clone are recorded as instant successes.

There are no `scenarios` or `analyze` subcommands and no `--workers`, `--duration`, `--scenario` or `--vms` flags.

### Results

`<output-dir>/results.csv` has one row per operation (columns `Operation`, `Provider`, `VMName`, `StartTime`, `Duration`, `Success`, `Error`, `Phase`); `<output-dir>/summary.md` has the totals and P50 / P95 / P99 / max latency per operation type.

```csv
Operation,Provider,VMName,StartTime,Duration,Success,Error,Phase
power,test-provider,,2026-01-15T10:00:01Z,0s,true,,PowerToggle
describe,test-provider,,2026-01-15T10:00:02Z,24µs,false,"failed to list VMs: no kind is registered for the type v1beta1.VirtualMachineList in scheme",
```

## alpha-to-beta-dryrun

A tombstoned migration helper from the v1alpha1 API era. Source: [`cmd/alpha-to-beta-dryrun/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/cmd/alpha-to-beta-dryrun/main.go).

!!! warning "No-op"
    The v1alpha1 API was removed before v0.3.0. Running this binary prints an error explaining that v1alpha1 resources should have already been migrated and exits with status 1. There are no flags and no useful operations, and it is not part of the release binaries.

---

## virtrigaud-manager flags

The manager binary (`cmd/manager`) is deployed via the Helm chart and is not typically invoked directly. The flags below are the ones it defines; run `manager --help` for the full list, which also includes the standard `--zap-*` logging flags. Source: [`cmd/manager/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.0/cmd/manager/main.go).

| Flag | Default | Description |
|------|---------|-------------|
| `--metrics-bind-address` | `:8080` | Address the metrics endpoint binds to. |
| `--health-probe-bind-address` | `:8081` | Address the health/readiness probes bind to. |
| `--leader-elect` | `false` | Enable leader election for HA deployments. |
| `--metrics-secure` | `false` | Serve metrics over HTTPS with RBAC authn/authz. |
| `--metrics-cert-path`, `--metrics-cert-name`, `--metrics-cert-key` | empty, `tls.crt`, `tls.key` | Metrics server certificate location (a non-empty path enables hot reload). |
| `--webhook-cert-path`, `--webhook-cert-name`, `--webhook-cert-key` | empty, `tls.crt`, `tls.key` | Webhook certificate location. |
| `--enable-http2` | `false` | Enable HTTP/2 for the metrics and webhook servers. |
| `--enforce-provider-capabilities` | `false` | Refuse snapshot and migration operations the provider does not advertise in its capabilities, instead of letting the RPC fail. Opt-in; added in v0.3.8. |
| `--migration-storage-allowed-hosts` | empty | Comma-separated IP/CIDR allow-list for migration staging backends (S3 endpoint host, NFS server). |
| `--provider-tmp-size-limit` | empty | `sizeLimit` of the `/tmp` volume of every provider pod (a quantity or `none`); empty keeps the per-type defaults. Chart value `manager.providerTmpSizeLimit`. Added in v0.4.0. |
| `--provider-tmp-size-limit-max` | empty | Ceiling on that `sizeLimit`; larger annotation values are clamped to it. Chart value `manager.providerTmpSizeLimitMax`. Added in v0.4.0. |
| `--max-disk-size` | empty | Administrator's ceiling on the size of every disk VirtRigaud creates or grows (`1Gi` to `64Pi`, binary units). Chart value `manager.maxDiskSize`. Added in v0.4.0. |

`--grpc-dial-timeout` and `--circuit-breaker-*` flags do not exist; the circuit-breaker thresholds are built in. The Helm chart has no generic `extraArgs` value; see [Setting flags with Helm](../references/cli-tools.md#setting-flags-with-helm).

---

## Best Practices

### Using vrtg

1. **Select the cluster explicitly** with `KUBECONFIG` or `kubectl config use-context`; `--kubeconfig` is not read.
2. **Pass `--namespace`** for `describe`, `events`, `console-url` and `provider status`; the `list` commands always span all namespaces.
3. **Use `kubectl`** for everything except `vrtg vm events`: the other read commands fail in v0.4.0 and the rest are placeholders (there is no JSON or YAML output).

### Testing with vcts

1. **Validate specs in CI** with `vcts validate`.
2. **Treat `vcts run` as scaffolding** until the step executor is implemented.

### Developing with vrtg-provider

1. **Start with `init`**, then fix the generated project so it builds, or start from `cmd/provider-mock`.
2. **Implement the core RPCs first** and declare only the capabilities you really implement.
3. **Use `--skip-conformance`** with `verify`.

### Load Testing with virtrigaud-loadgen

1. **Use a dedicated namespace**, and `--dry-run` first.
2. **Create the Provider, VMClass and VMImage** named in the defaults (`test-provider`, `test-class`, `test-image`) before a real run.
3. **Remember what is simulated**: power, reconfigure, snapshot and clone are simulated, and create, delete and describe fail against a cluster in v0.4.0.

## Support

- **Documentation**: [VirtRigaud Docs](https://projectbeskar.github.io/virtrigaud/)
- **Issues**: [GitHub Issues](https://github.com/projectbeskar/virtrigaud/issues)
- **Discussions**: [GitHub Discussions](https://github.com/projectbeskar/virtrigaud/discussions)

## Version Information

This reference covers VirtRigaud CLI tools v0.4.0.

For older versions, see the [releases page](https://github.com/projectbeskar/virtrigaud/releases).
