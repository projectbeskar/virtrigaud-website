<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# CLI Reference

VirtRigaud provides several command-line tools for managing virtual machines, testing providers, and developing new providers. This reference covers v0.3.6.

## Overview

| Tool | Purpose | Target Users |
|------|---------|--------------|
| [`vrtg`](#vrtg) | Main CLI for VM management | End users, DevOps teams |
| [`vcts`](#vcts) | Conformance testing suite | Provider developers, QA teams |
| [`vrtg-provider`](#vrtg-provider) | Provider development toolkit | Provider developers |
| [`virtrigaud-loadgen`](#virtrigaud-loadgen) | Load testing and benchmarking | Performance engineers |
| [`alpha-to-beta-dryrun`](#alpha-to-beta-dryrun) | v1alpha1 migration helper (tombstone) | Pre-v0.3.0 upgraders |

## Installation

### From GitHub Releases

```bash
# Download v0.3.6
curl -L "https://github.com/projectbeskar/virtrigaud/releases/download/v0.3.6/vrtg-linux-amd64" -o vrtg
chmod +x vrtg
sudo mv vrtg /usr/local/bin/

# Install all CLI tools
curl -L "https://github.com/projectbeskar/virtrigaud/releases/download/v0.3.6/virtrigaud-cli-linux-amd64.tar.gz" | tar xz
sudo mv vrtg vcts vrtg-provider virtrigaud-loadgen /usr/local/bin/
```

### From Source

```bash
git clone https://github.com/projectbeskar/virtrigaud.git
cd virtrigaud

# Build all CLI tools
make build-cli

# Install to /usr/local/bin
sudo make install-cli
```

### Using Go

```bash
go install github.com/projectbeskar/virtrigaud/cmd/vrtg@v0.3.6
go install github.com/projectbeskar/virtrigaud/cmd/vcts@v0.3.6
go install github.com/projectbeskar/virtrigaud/cmd/vrtg-provider@v0.3.6
go install github.com/projectbeskar/virtrigaud/cmd/virtrigaud-loadgen@v0.3.6
```

## vrtg

The main CLI tool for managing VirtRigaud resources and virtual machines.

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file (default: $KUBECONFIG or ~/.kube/config)
--namespace string    Kubernetes namespace (default: "default")
--output string       Output format: table, json, yaml (default: "table")
--timeout duration    Operation timeout (default: 5m0s)
-h, --help           Help for vrtg
```

### Commands

#### vm

Manage virtual machines.

```bash
# List all VMs
vrtg vm list

# Get detailed VM information
vrtg vm get <vm-name>

# Create a VM from configuration
vrtg vm create --file vm.yaml

# Delete a VM
vrtg vm delete <vm-name>

# Power operations
vrtg vm start <vm-name>
vrtg vm stop <vm-name>
vrtg vm restart <vm-name>

# Scale VMSet
vrtg vm scale <vmset-name> --replicas 5

# Get VM console URL
vrtg vm console <vm-name>

# Watch VM status changes
vrtg vm watch <vm-name>
```

**Examples:**

```bash
# List VMs with custom output
vrtg vm list --output json --namespace production

# Create VM with timeout
vrtg vm create --file my-vm.yaml --timeout 10m

# Power on all VMs in namespace
vrtg vm list --output json | jq -r '.items[].metadata.name' | xargs -I {} vrtg vm start {}
```

#### provider

Manage provider configurations.

```bash
# List providers
vrtg provider list

# Get provider details
vrtg provider get <provider-name>

# Check provider connectivity
vrtg provider validate <provider-name>

# Get provider capabilities
vrtg provider capabilities <provider-name>

# View provider logs
vrtg provider logs <provider-name>

# Test provider functionality
vrtg provider test <provider-name>
```

**Examples:**

```bash
# Validate all providers
vrtg provider list --output json | jq -r '.items[].metadata.name' | xargs -I {} vrtg provider validate {}

# Get detailed provider status
vrtg provider get vsphere-prod --output yaml
```

#### image

Manage VM images and templates.

```bash
# List available images
vrtg image list

# Get image details
vrtg image get <image-name>

# Prepare an image
vrtg image prepare <image-name>

# Delete an image
vrtg image delete <image-name>
```

#### snapshot

Manage VM snapshots.

```bash
# List snapshots for a VM
vrtg snapshot list --vm <vm-name>

# Create a snapshot
vrtg snapshot create <vm-name> --name "pre-upgrade"

# Restore from snapshot
vrtg snapshot restore <vm-name> <snapshot-name>

# Delete a snapshot
vrtg snapshot delete <vm-name> <snapshot-name>
```

#### completion

Generate shell completion scripts.

```bash
# Bash
vrtg completion bash > /etc/bash_completion.d/vrtg

# Zsh
vrtg completion zsh > "${fpath[1]}/_vrtg"

# Fish
vrtg completion fish > ~/.config/fish/completions/vrtg.fish

# PowerShell
vrtg completion powershell > vrtg.ps1
```

### Configuration

vrtg uses the same kubeconfig as kubectl. Configuration precedence:

1. `--kubeconfig` flag
2. `KUBECONFIG` environment variable
3. `~/.kube/config`

#### Config File

Create `~/.vrtg/config.yaml` for default settings:

```yaml
defaults:
  namespace: "virtrigaud-system"
  timeout: "10m"
  output: "table"
providers:
  preferred: "vsphere-prod"
output:
  colors: true
  timestamps: true
```

## vcts

VirtRigaud Conformance Test Suite for validating provider implementations.

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file
--namespace string    Test namespace (default: "vcts")
--provider string     Provider to test
--output-dir string   Directory for test results
--timeout duration    Test timeout (default: 30m)
--parallel int        Number of parallel tests (default: 1)
--skip strings        Tests to skip (comma-separated)
--verbose             Verbose output
-h, --help           Help for vcts
```

### Commands

#### run

Run conformance tests against a provider.

```bash
# Run all tests
vcts run --provider vsphere-prod

# Run specific test suites
vcts run --provider vsphere-prod --suites core,storage

# Run with custom configuration
vcts run --provider libvirt-test --config test-config.yaml

# Skip specific tests
vcts run --provider vsphere-prod --skip "test-large-vm,test-snapshot-memory"

# Generate detailed report
vcts run --provider vsphere-prod --output-dir ./test-results --verbose
```

#### list

List available test suites and tests.

```bash
# List all test suites
vcts list suites

# List tests in a suite
vcts list tests --suite core

# List supported providers
vcts list providers
```

#### validate

Validate test configuration.

```bash
# Validate configuration file
vcts validate --config test-config.yaml

# Validate provider setup
vcts validate --provider vsphere-prod
```

### Test Suites

#### Core Suite
- Basic VM lifecycle (create, start, stop, delete)
- Provider connectivity and authentication
- Resource allocation and management

#### Storage Suite
- Disk creation and attachment
- Volume expansion operations
- Storage pool management

#### Network Suite
- Network interface management
- IP address allocation
- Network connectivity tests

#### Snapshot Suite
- Snapshot creation and deletion
- Snapshot restoration
- Memory state preservation

#### Performance Suite
- VM creation performance
- Resource utilization benchmarks
- Concurrent operation handling

### Test Configuration

Create `test-config.yaml`:

```yaml
provider:
  name: "vsphere-prod"
  type: "vsphere"
  
tests:
  core:
    enabled: true
    timeout: "15m"
  storage:
    enabled: true
    testDiskSize: "10Gi"
  network:
    enabled: false  # Skip network tests
    
resources:
  vmClass: "test-small"
  vmImage: "ubuntu-22-04"
  
cleanup:
  enabled: true
  timeout: "10m"
```

## vrtg-provider

Development toolkit for creating and maintaining VirtRigaud providers. Defined in [`cmd/vrtg-provider/main.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg-provider/main.go).

### Global Flags

```bash
--verbose, -v       Enable verbose output
-h, --help         Help for vrtg-provider
```

### Commands

#### init

Initialize a new provider project. Source: [`cmd/vrtg-provider/init.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg-provider/init.go).

```bash
vrtg-provider init <provider-name> [flags]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--output, -o` | `.` | Output directory |
| `--type, -t` | `generic` | Provider type: `vsphere`, `libvirt`, `firecracker`, `qemu`, `generic` |
| `--remote` | `false` | Generate remote runtime configuration |
| `--force` | `false` | Overwrite existing files |

```bash
# Create a libvirt-style provider in ./providers/
vrtg-provider init myprovider --type libvirt --output ./providers/
```

#### generate

Regenerate protocol buffer bindings. Source: [`cmd/vrtg-provider/generate.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg-provider/generate.go).

Run from within a provider project directory (`go.mod` + `Makefile` required).

| Flag | Default | Description |
|------|---------|-------------|
| `--proto-only` | `false` | Only regenerate proto bindings |
| `--clean` | `false` | Clean generated files first |

#### verify

Verify provider implementation. Source: [`cmd/vrtg-provider/verify.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg-provider/verify.go).

Run from within a provider project directory.

| Flag | Default | Description |
|------|---------|-------------|
| `--skip-build` | `false` | Skip build check |
| `--skip-tests` | `false` | Skip unit tests |
| `--skip-conformance` | `false` | Skip VCTS conformance |
| `--profile` | `core` | Conformance profile: `core`, `snapshot`, `clone`, `advanced` |

```bash
# Full verification (build + tests + conformance core profile)
vrtg-provider verify

# Skip conformance — useful in CI before a provider endpoint is available
vrtg-provider verify --skip-conformance
```

#### publish

Publish a provider to the VirtRigaud catalog. Source: [`cmd/vrtg-provider/publish.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg-provider/publish.go).

Run from within a provider project directory.

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--image` | Yes | — | Container image repository |
| `--repo` | Yes | — | Source code repository URL |
| `--maintainer` | Yes | — | Maintainer email |
| `--name` | No | directory name | Provider name |
| `--tag` | No | `latest` | Image tag |
| `--license` | No | `Apache-2.0` | SPDX license identifier |
| `--skip-verify` | No | `false` | Skip VCTS verification |
| `--dry-run` | No | `false` | Print catalog entry without writing |
| `--catalog` | No | auto-detect | Path to `providers/catalog.yaml` |

```bash
# Dry-run preview
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

Prints binary version and git SHA.

## virtrigaud-loadgen

Load testing and performance benchmarking tool for VirtRigaud providers.

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file
--namespace string    Test namespace (default: "loadgen")
--output-dir string   Output directory for results
--config-file string  Load generation configuration file
--dry-run            Show what would be created without executing
--verbose            Verbose output
-h, --help          Help for virtrigaud-loadgen
```

### Commands

#### run

Execute load generation scenarios.

```bash
# Run default load test
virtrigaud-loadgen run --config loadtest.yaml

# Run with custom settings
virtrigaud-loadgen run --config loadtest.yaml --workers 50 --duration 10m

# Run specific scenario
virtrigaud-loadgen run --scenario vm-creation --vms 100

# Generate performance report
virtrigaud-loadgen run --config loadtest.yaml --output-dir ./perf-results
```

#### scenarios

Manage load testing scenarios.

```bash
# List available scenarios
virtrigaud-loadgen scenarios list

# Show scenario details
virtrigaud-loadgen scenarios get vm-lifecycle

# Validate scenario configuration
virtrigaud-loadgen scenarios validate --config custom-scenario.yaml
```

#### analyze

Analyze load test results.

```bash
# Generate performance report
virtrigaud-loadgen analyze --input ./perf-results

# Compare test runs
virtrigaud-loadgen analyze --compare run1.csv,run2.csv

# Generate charts
virtrigaud-loadgen analyze --input ./perf-results --charts
```

### Load Test Configuration

Create `loadtest.yaml`:

```yaml
metadata:
  name: "vm-creation-load-test"
  description: "Test VM creation performance"

scenarios:
  - name: "vm-creation"
    type: "vm-lifecycle"
    workers: 20
    duration: "5m"
    resources:
      vmClass: "small"
      vmImage: "ubuntu-22-04"
      provider: "vsphere-prod"
    
  - name: "vm-scaling"
    type: "vmset-scaling"
    workers: 5
    iterations: 10
    scaling:
      min: 1
      max: 50
      step: 5

providers:
  - name: "vsphere-prod"
    type: "vsphere"
  - name: "libvirt-test"
    type: "libvirt"

output:
  format: ["csv", "json"]
  metrics: ["latency", "throughput", "errors"]
  
cleanup:
  enabled: true
  timeout: "15m"
```

### Performance Scenarios

#### VM Lifecycle
- Create, start, stop, delete operations
- Measures end-to-end VM management performance

#### Burst Creation
- Rapid VM creation under load
- Tests provider scaling capabilities

#### VMSet Scaling
- Scale VMSets up and down
- Measures horizontal scaling performance

#### Provider Stress
- High concurrent operations
- Tests provider reliability under stress

### Results Analysis

Load test results include:

- **Latency metrics**: P50, P95, P99 response times
- **Throughput**: Operations per second
- **Error rates**: Failed operations percentage
- **Resource usage**: CPU, memory, network utilization
- **Provider metrics**: API call statistics

Example output:

```csv
timestamp,scenario,operation,latency_ms,status,provider
2025-01-15T10:00:01Z,vm-creation,create,2500,success,vsphere-prod
2025-01-15T10:00:03Z,vm-creation,create,2800,success,vsphere-prod
2025-01-15T10:00:05Z,vm-creation,create,failed,timeout,vsphere-prod
```

## alpha-to-beta-dryrun

A tombstoned migration helper from the v1alpha1 API era. Source: [`cmd/alpha-to-beta-dryrun/main.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/alpha-to-beta-dryrun/main.go).

!!! warning "No-op in v0.3.6"
    The v1alpha1 API was removed before v0.3.0. Running this binary exits with an error explaining that v1alpha1 resources should have already been migrated. There are no flags and no useful operations.

---

## Best Practices

### Using vrtg

1. **Use namespaces** to organize resources
2. **Set timeouts** appropriately for your environment
3. **Use dry-run** options for validation before execution
4. **Monitor operations** with watch commands

### Testing with vcts

1. **Run core tests first** to validate basic functionality
2. **Use separate namespaces** for different test runs
3. **Clean up resources** after testing
4. **Document test results** for compliance tracking

### Developing with vrtg-provider

1. **Start with init** to create proper structure
2. **Implement core capabilities** before advanced features
3. **Test thoroughly** with vcts before publishing
4. **Follow naming conventions** for consistency

### Load Testing with virtrigaud-loadgen

1. **Start small** and gradually increase load
2. **Monitor system resources** during tests
3. **Use realistic scenarios** that match production workloads
4. **Analyze results** to identify bottlenecks

## Support

- **Documentation**: [VirtRigaud Docs](https://projectbeskar.github.io/virtrigaud/)
- **Issues**: [GitHub Issues](https://github.com/projectbeskar/virtrigaud/issues)
- **Discussions**: [GitHub Discussions](https://github.com/projectbeskar/virtrigaud/discussions)

## Version Information

This reference covers VirtRigaud CLI tools v0.3.6.

For older versions, see the [releases page](https://github.com/projectbeskar/virtrigaud/releases).
