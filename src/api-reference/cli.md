<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# CLI Reference

VirtRigaud provides several command-line tools for inspecting resources, validating conformance specs, developing providers, and load testing. This reference covers v0.4.0 and lists the commands and flags the tools define. For longer explanations and caveats see the [CLI Tools Reference](../references/cli-tools.md).

## Overview

| Tool | Purpose | Target Users |
|------|---------|--------------|
| [`vrtg`](#vrtg) | Read-only CLI for VMs and Providers | End users, DevOps teams |
| [`vcts`](#vcts) | Conformance test spec validator and runner (the runner cannot pass yet) | Provider developers, QA teams |
| [`vrtg-provider`](#vrtg-provider) | Scaffold, check and catalog a new provider | Provider developers |
| [`virtrigaud-loadgen`](#virtrigaud-loadgen) | Load generator for `VirtualMachine` create, delete and list | Performance engineers |
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

The same naming applies to `vcts`, `vrtg-provider` and `virtrigaud-loadgen`. `<tool> --version` prints the release the binary was built from (`dev` for a source build).

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

CLI for looking at VirtRigaud resources. Source: [`cmd/vrtg/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/vrtg/main.go).

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file (default: KUBECONFIG, in-cluster, then ~/.kube/config)
-n, --namespace       Kubernetes namespace (default: "default")
-o, --output          Output format: table, json, yaml (default: "table")
--timeout duration    Request timeout (default: 30s)
-h, --help            Help for vrtg
```

### Commands

| Command | Aliases | Status | Description |
|---------|---------|--------|-------------|
| `vrtg vm list` | `virtualmachine`, `vms` | Implemented | List VirtualMachines (namespace, name, provider, class, image, IPs, age). All namespaces unless `-n` is given. |
| `vrtg vm describe <name>` | | Implemented | Show one VirtualMachine: provider, class, image, power state, IDs, IPs, console URL, conditions. |
| `vrtg vm events <name>` | | Implemented | Show the Kubernetes events of a VirtualMachine in `--namespace`. |
| `vrtg vm console-url <name>` | | Implemented | Print `status.consoleURL`. |
| `vrtg provider list` | `providers` | Implemented | List Providers (namespace, name, type, endpoint, age). All namespaces unless `-n` is given. |
| `vrtg provider status <name>` | | Implemented | Show a Provider's type, endpoint, `status.healthy` and conditions. |
| `vrtg provider logs <name>` | | Not implemented | Exits non-zero; use `kubectl logs`. |
| `vrtg snapshot create <vm> <snapshot>`, `list [vm]`, `revert <vm> <snapshot>` | `snap`, `snapshots` | Not implemented | Exit non-zero; use `VMSnapshot` resources and `spec.snapshot.revertToRef`. |
| `vrtg clone run <source> <target>`, `list` | `clones` | Not implemented | Exit non-zero; use `VMClone` resources. |
| `vrtg conformance run <provider>` | `conf` | Not implemented | Exits non-zero; use [`vcts`](#vcts). |
| `vrtg diag bundle` | `diagnostics` | Not implemented | Exits non-zero; use `kubectl describe` and `kubectl logs`. |
| `vrtg init` | | Not implemented | Exits non-zero; install with the Helm chart. |
| `vrtg completion bash\|zsh\|fish\|powershell` | | Implemented | Generate a shell completion script. |

The aliases in the table belong to the command group (`vrtg virtualmachine list`, `vrtg vms list`, `vrtg providers list`, `vrtg snap list`, `vrtg clones list`), not to the subcommand. None of the subcommands defines flags beyond the global ones. `-o json` and `-o yaml` apply to `vm list`, `vm describe`, `provider list` and `provider status` (the output carries `apiVersion` and `kind` and omits `metadata.managedFields`); `vm events` and `vm console-url` always print text. `describe`, `console-url`, `events` and `provider status` read the namespace given by `-n` (`default` if omitted).

```bash
vrtg vm list
vrtg vm list -n production -o yaml
vrtg vm describe my-vm -n production
vrtg vm events my-vm -n production
vrtg provider status vsphere-prod -n virtrigaud-system
```

### Cluster access

Without `--kubeconfig`, `vrtg` uses controller-runtime's default configuration loading: the `KUBECONFIG` environment variable, then in-cluster configuration, then `~/.kube/config`. A `--kubeconfig` path that cannot be loaded is an error; the tool does not fall back to another cluster. There is no `~/.vrtg/config.yaml` and `vrtg` reads no `VRTG_*` environment variables.

## vcts

VirtRigaud Conformance Test Suite. Source: [`cmd/vcts/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/vcts/main.go).

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file (default: KUBECONFIG, in-cluster, then ~/.kube/config)
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

!!! warning "`vcts run` cannot pass yet"
    The runner reads the Provider and writes `results.json`, `junit.xml` and `report.md`, but it does not execute the steps of a specification: every `create`, `update`, `delete`, `wait` and `validate` step reports "not implemented", so each selected test fails at its first step and the command exits non-zero. Only `vsphere` and `libvirt` Providers select any test; for other Provider types, or outside a checkout, zero tests are selected and the command exits 0. See the [CLI Tools Reference](../references/cli-tools.md#vcts).

#### list

Print the tests defined in `test/conformance/specs/` with their descriptions and required capabilities. `list` and `run` read that directory relative to the current directory, so run them from the root of a VirtRigaud checkout.

#### validate

Validate the YAML test specifications. Takes an optional directory argument (default `test/conformance/specs`). It exits non-zero when no spec file is found or when a file cannot be parsed or holds an invalid test (the file is printed as `ERROR: ...`); it exits 0 only when every file is valid.

```bash
vcts validate test/conformance/specs/
```

The repository ships `test/conformance/specs/basic-lifecycle.yaml` with two tests, `vm-create-delete` and `vm-power-cycle`. There are no test suites, `--suite`, `--suites` or `--config` options.

## vrtg-provider

Development toolkit for provider projects outside this repository; it edits local files only. Source: [`cmd/vrtg-provider/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/vrtg-provider/main.go).

### Global Flags

```bash
-v, --verbose       Accepted, no effect
--version           Print the version
-h, --help          Help for vrtg-provider
```

### Commands

#### init

Initialize a new provider project. Source: [`cmd/vrtg-provider/init.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/vrtg-provider/init.go).

```bash
vrtg-provider init <provider-name> [flags]
```

| Flag | Default | Description |
|------|---------|-------------|
| `-o, --output` | `.` | Output directory; the project is written to `<output>/providers/<provider-name>/` |
| `-t, --type` | `generic` | Provider type: `vsphere`, `libvirt`, `firecracker`, `qemu`, `generic` (there is no `proxmox` value) |
| `--remote` | `false` | Generate remote runtime configuration (the manifests under `config/`) |
| `--virtrigaud-path` | the checkout the project is created in, if any | VirtRigaud checkout the generated `go.mod` resolves the SDK and proto modules from |
| `--force` | `false` | Overwrite existing files |

```bash
vrtg-provider init myprovider --type libvirt --output ./providers/
```

The SDK and proto modules are not published under their own version tags, so the generated `go.mod` points at a local VirtRigaud checkout through `replace` directives: `init` writes them (a relative path when the project is inside the checkout) or, with `--virtrigaud-path`, uses the checkout you name. Run `go mod tidy` first, then `make build`. The generated `Dockerfile` cannot see that checkout, so build the image from a context that contains both. See [`vrtg-provider init`](../references/cli-tools.md#init-initialize-provider).

#### generate

Regenerate protocol buffer bindings. Source: [`cmd/vrtg-provider/generate.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/vrtg-provider/generate.go). Run from within a provider project directory (a `Makefile` and a `go.mod` that requires a `github.com/projectbeskar/virtrigaud` module, which `init` creates). A scaffolded project imports its bindings from the proto module, so there is nothing to generate and the command says so.

| Flag | Default | Description |
|------|---------|-------------|
| `--proto-only` | `false` | Only regenerate proto bindings |
| `--clean` | `false` | Remove `*.pb.go` files under `internal/rpc` before regenerating |

#### verify

Build, check and test a provider project. Source: [`cmd/vrtg-provider/verify.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/vrtg-provider/verify.go). Run from within a provider project directory.

| Flag | Default | Description |
|------|---------|-------------|
| `--skip-build` | `false` | Skip build check |
| `--skip-tests` | `false` | Skip unit tests |
| `--skip-conformance` | `false` | Skip the closing reminder that conformance was not run |
| `--profile` | `core` | Deprecated and without effect |

`verify` does not run the conformance suite, which needs the provider deployed in a cluster: deploy it, then run `vcts run --provider <name>` (the runner cannot pass yet, see [`vcts`](#vcts)).

```bash
vrtg-provider verify
```

#### publish

Write a catalog entry for a provider. Source: [`cmd/vrtg-provider/publish.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/vrtg-provider/publish.go). Run from within a provider project directory.

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--image` | Yes | | Container image repository |
| `--repo` | Yes | | Source code repository URL |
| `--maintainer` | Yes | | Maintainer email |
| `--name` | No | directory name | Provider name |
| `--tag` | No | `latest` | Image tag |
| `--license` | No | `Apache-2.0` | SPDX license identifier |
| `--skip-verify` | No | `false` | Skip the build and test step |
| `--dry-run` | No | `false` | Print the catalog entry without writing it (the build and tests still run unless `--skip-verify`) |
| `--catalog` | No | auto-detect | Path to `providers/catalog.yaml` |

`publish` builds and tests the project, then records the conformance profile `core` as `skip` (not run) with a "not run" badge; it never claims a pass, with or without `--skip-verify`. It writes a local catalog file and does not open a pull request.

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

Prints the version and git SHA: a release binary reports its release tag and `Git SHA: unknown`; a local build reports `dev` and `unknown`.

## virtrigaud-loadgen

Load generator for VirtualMachine create, delete and list operations; see the [CLI Tools Reference](../references/cli-tools.md#virtrigaud-loadgen) for the details. Source: [`cmd/virtrigaud-loadgen/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/virtrigaud-loadgen/main.go).

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file (default: KUBECONFIG, in-cluster, then ~/.kube/config)
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
| `-c, --config` | Load generation config file (YAML) that overrides the built-in defaults (5 minutes, 2 workers, provider `test-provider`, class `test-class`, image `test-image`). Keys you leave out keep their default; an unknown key is an error. |

```bash
# Dry run
virtrigaud-loadgen run --dry-run --namespace loadtest

# Real run with a config file, into a dedicated namespace
virtrigaud-loadgen run --config loadtest.yaml --namespace loadtest --output-dir ./perf-results
```

Always use a dedicated namespace: a run creates real VirtualMachines and leaves the ones still present when it ends (remove them with `kubectl delete virtualmachine -n <namespace> -l generated-by=loadgen`). The `delete` operation removes only VMs that the same run created. Only create, delete and describe (a list) call the API; power, reconfigure, snapshot and clone are simulated and recorded as instant successes. The config file keys and their defaults are in the [CLI Tools Reference](../references/cli-tools.md#run-execute-load-test).

There are no `scenarios` or `analyze` subcommands and no `--workers`, `--duration`, `--scenario` or `--vms` flags.

### Results

`<output-dir>/results.csv` has one row per operation (columns `Operation`, `Provider`, `VMName`, `StartTime`, `Duration`, `Success`, `Error`, `Phase`); `<output-dir>/summary.md` has the totals and P50 / P95 / P99 / max latency per operation type.

```csv
Operation,Provider,VMName,StartTime,Duration,Success,Error,Phase
create,test-provider,loadgen-vm-1a2b3c-0-1,2026-01-15T10:00:01Z,41ms,true,,Creating
power,test-provider,,2026-01-15T10:00:02Z,0s,true,,PowerToggle
```

## alpha-to-beta-dryrun

A tombstoned migration helper from the v1alpha1 API era. Source: [`cmd/alpha-to-beta-dryrun/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/alpha-to-beta-dryrun/main.go).

!!! warning "No-op"
    The v1alpha1 API was removed before v0.3.0. Running this binary prints an error explaining that v1alpha1 resources should have already been migrated and exits with status 1. There are no flags and no useful operations, and it is not part of the release binaries.

---

## virtrigaud-manager flags

The manager binary (`cmd/manager`) is deployed via the Helm chart and is not typically invoked directly. The flags below are the ones it defines; run `manager --help` for the full list, which also includes the standard `--zap-*` logging flags. Source: [`cmd/manager/main.go`](https://github.com/projectbeskar/virtrigaud/blob/v0.4.1/cmd/manager/main.go).

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

1. **Pass `--namespace`** when you want one namespace: the `list` commands span all namespaces without it, while `describe`, `events`, `console-url` and `provider status` read `default` unless you name one.
2. **Use `-o json` or `-o yaml`** to feed other tools; use `kubectl` for waiting on conditions and for the commands `vrtg` does not implement (snapshots, clones, logs).

### Testing with vcts

1. **Validate specs in CI** with `vcts validate`; it exits non-zero on an invalid spec.
2. **Do not rely on `vcts run` yet**: the runner does not execute specification steps, so the selected tests fail.

### Developing with vrtg-provider

1. **Start with `init`** inside a VirtRigaud checkout (or pass `--virtrigaud-path`), run `go mod tidy`, then `make build` and `vrtg-provider verify`.
2. **Implement the core RPCs first** and declare only the capabilities you really implement.
3. **Treat a `publish` entry as unverified**: it records conformance as not run.

### Load Testing with virtrigaud-loadgen

1. **Use a dedicated namespace**, and `--dry-run` first.
2. **Create the Provider, VMClass and VMImage** named in the defaults or in your `--config` file before a real run; the tool does not check that they exist, and VMs with missing references are created but do not reconcile.
3. **Remember what is simulated**: power, reconfigure, snapshot and clone are not sent to the API, so give them weight 0 unless you want them in the mix.
4. **Clean up** the VMs left at the end with `kubectl delete virtualmachine -n <namespace> -l generated-by=loadgen`.

## Support

- **Documentation**: [VirtRigaud Docs](https://projectbeskar.github.io/virtrigaud/)
- **Issues**: [GitHub Issues](https://github.com/projectbeskar/virtrigaud/issues)
- **Discussions**: [GitHub Discussions](https://github.com/projectbeskar/virtrigaud/discussions)

## Version Information

This reference covers VirtRigaud CLI tools v0.4.0.

For older versions, see the [releases page](https://github.com/projectbeskar/virtrigaud/releases).
