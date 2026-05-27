<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# CLI Tools Reference

VirtRigaud provides a set of command-line tools for managing virtual machines, developing providers, running conformance tests, and performing load testing. This guide covers all available CLI tools and their usage in v0.3.6.

## Overview

| Tool | Purpose | Target Users |
|------|---------|--------------|
| [`vrtg`](#vrtg) | Main CLI for VM management and operations | End users, DevOps teams, System administrators |
| [`vcts`](#vcts) | Conformance testing suite | Provider developers, QA teams, CI/CD pipelines |
| [`vrtg-provider`](#vrtg-provider) | Provider development toolkit | Provider developers, Contributors |
| [`virtrigaud-loadgen`](#virtrigaud-loadgen) | Load testing and benchmarking | Performance engineers, SREs |
| [`alpha-to-beta-dryrun`](#alpha-to-beta-dryrun) | v1alpha1 migration helper (tombstone) | Operators upgrading from pre-v0.3.0 |

!!! note "Implementation status"
    Several `vrtg` subcommand handlers print "not implemented" and exit 0 in v0.3.6. The commands are defined in [`cmd/vrtg/main.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg/main.go) and are scaffolded for future releases. Fully implemented commands are noted in each section below.

## Installation

### From GitHub Releases

```bash
# Download the latest release
export VIRTRIGAUD_VERSION="v0.3.6"
export PLATFORM="linux-amd64"  # or darwin-amd64, windows-amd64

# Install main CLI tool
curl -L "https://github.com/projectbeskar/virtrigaud/releases/download/${VIRTRIGAUD_VERSION}/vrtg-${PLATFORM}" -o vrtg
chmod +x vrtg
sudo mv vrtg /usr/local/bin/

# Install all CLI tools
curl -L "https://github.com/projectbeskar/virtrigaud/releases/download/${VIRTRIGAUD_VERSION}/virtrigaud-cli-${PLATFORM}.tar.gz" | tar xz
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

# Or install to custom location
make install-cli PREFIX=/usr/local
```

### Using Go

```bash
# Install specific version
go install github.com/projectbeskar/virtrigaud/cmd/vrtg@v0.3.6
go install github.com/projectbeskar/virtrigaud/cmd/vcts@v0.3.6
go install github.com/projectbeskar/virtrigaud/cmd/vrtg-provider@v0.3.6
go install github.com/projectbeskar/virtrigaud/cmd/virtrigaud-loadgen@v0.3.6

# Install latest
go install github.com/projectbeskar/virtrigaud/cmd/vrtg@latest
```

### Completion

Enable shell completion for enhanced productivity:

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

The main CLI tool for managing VirtRigaud resources and virtual machines. Defined in [`cmd/vrtg/main.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg/main.go).

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file (default: $KUBECONFIG or ~/.kube/config)
--namespace, -n       Kubernetes namespace (default: "default")
--output, -o          Output format: table, json, yaml (default: "table")
--timeout duration    Request timeout (default: 30s)
-h, --help           Help for vrtg
```

### Commands

#### vm - Virtual Machine Management

Manage virtual machines with comprehensive lifecycle operations. Aliases: `virtualmachine`, `vms`.

```bash
# List virtual machines  [IMPLEMENTED]
vrtg vm list [flags]

# Describe a virtual machine  [IMPLEMENTED]
vrtg vm describe <name> [flags]

# Show VM events  [IMPLEMENTED]
vrtg vm events <name> [flags]

# Get VM console URL  [IMPLEMENTED]
vrtg vm console-url <name> [flags]
```

!!! note "v0.3.6 status"
    `vm list` and `vm describe` query the Kubernetes API directly and print real data. `vm events`, `vm console-url`, `vm snapshot`, `vm clone`, `vrtg init`, and `vrtg diag bundle` are defined but print a "not implemented" message. Output format (`--output json/yaml`) is also not yet implemented.

**Examples:**

```bash
# List all VMs in table format
vrtg vm list

# List VMs with custom output format
vrtg vm list --output json --namespace production

# List VMs across all namespaces
vrtg vm list --all-namespaces

# Filter VMs by labels
vrtg vm list --label-selector environment=production,tier=web

# Watch VM status changes
vrtg vm list --watch

# Get detailed VM information
vrtg vm describe my-vm --output yaml

# Get VM console URL
vrtg vm console-url my-vm

# Show recent VM events
vrtg vm events my-vm
```

#### provider - Provider Management

Manage provider configurations and monitor their health.

```bash
# List providers
vrtg provider list [flags]

# Show provider status
vrtg provider status <name> [flags]

# Show provider logs
vrtg provider logs <name> [flags]
```

**Flags:**
- `--follow`: Follow log output (for logs command)
- `--tail`: Number of lines to show from end of logs (default: 100)
- `--since`: Show logs since timestamp (e.g., 1h, 30m)

**Examples:**

```bash
# List all providers
vrtg provider list

# Check provider status
vrtg provider status vsphere-provider

# View provider logs
vrtg provider logs vsphere-provider --tail 50

# Follow provider logs in real-time
vrtg provider logs vsphere-provider --follow

# Show logs from last hour
vrtg provider logs vsphere-provider --since 1h
```

#### snapshot - Snapshot Management

Manage VM snapshots for backup and recovery.

```bash
# Create a VM snapshot
vrtg snapshot create <vm-name> <snapshot-name> [flags]

# List snapshots
vrtg snapshot list [vm-name] [flags]

# Revert VM to snapshot
vrtg snapshot revert <vm-name> <snapshot-name> [flags]
```

**Flags for create:**
- `--description`: Snapshot description
- `--include-memory`: Include memory state in snapshot

**Examples:**

```bash
# Create a simple snapshot
vrtg snapshot create my-vm pre-upgrade

# Create snapshot with description and memory
vrtg snapshot create my-vm pre-maintenance \
  --description "Before maintenance window" \
  --include-memory

# List all snapshots
vrtg snapshot list

# List snapshots for specific VM
vrtg snapshot list my-vm

# Revert to a snapshot
vrtg snapshot revert my-vm pre-upgrade
```

#### clone - VM Cloning

Clone virtual machines for rapid provisioning.

```bash
# Clone a virtual machine
vrtg clone run <source-vm> <target-vm> [flags]

# List clone operations
vrtg clone list [flags]
```

**Flags for run:**
- `--linked`: Create linked clone (faster, space-efficient)
- `--target-namespace`: Namespace for target VM
- `--customize`: Apply customization during clone

**Examples:**

```bash
# Simple VM clone
vrtg clone run template-vm new-vm

# Linked clone for development
vrtg clone run production-vm dev-vm --linked

# Clone to different namespace
vrtg clone run template-vm test-vm --target-namespace testing

# List clone operations
vrtg clone list
```

#### conformance - Provider Testing

Run conformance tests against providers.

```bash
# Run conformance tests
vrtg conformance run <provider> [flags]
```

**Flags:**
- `--output-dir`: Directory for test results
- `--skip-tests`: Comma-separated list of tests to skip
- `--timeout`: Test timeout (default: 30m)

**Examples:**

```bash
# Run conformance tests
vrtg conformance run vsphere-provider

# Run tests with custom timeout
vrtg conformance run vsphere-provider --timeout 1h

# Skip specific tests
vrtg conformance run vsphere-provider --skip-tests "test-large-vms,test-network"
```

#### diag - Diagnostics

Diagnostic tools for troubleshooting.

```bash
# Create diagnostic bundle
vrtg diag bundle [flags]
```

**Flags:**
- `--output`: Output file path (default: virtrigaud-diag-\<timestamp\>.tar.gz)
- `--include-logs`: Include provider logs in bundle
- `--since`: Collect logs since timestamp

**Examples:**

```bash
# Create diagnostic bundle
vrtg diag bundle

# Create bundle with logs from last 2 hours
vrtg diag bundle --include-logs --since 2h

# Custom output location
vrtg diag bundle --output /tmp/debug-bundle.tar.gz
```

#### init - Installation

Initialize VirtRigaud in a Kubernetes cluster.

```bash
# Initialize virtrigaud
vrtg init [flags]
```

**Flags:**
- `--chart-version`: Helm chart version to install
- `--namespace`: Installation namespace (default: virtrigaud-system)
- `--values`: Values file for Helm chart
- `--dry-run`: Show what would be installed

**Examples:**

```bash
# Basic installation
vrtg init

# Install specific version
vrtg init --chart-version v0.2.1

# Install with custom values
vrtg init --values custom-values.yaml

# Dry run to see what would be installed
vrtg init --dry-run
```

---

## vcts

VirtRigaud Conformance Test Suite - runs standardized tests against providers.

### Usage

```bash
vcts [command] [flags]
```

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file
--namespace string    Kubernetes namespace (default: "virtrigaud-system")
--provider string     Provider name to test
--output-dir string   Output directory for test results (default: "./conformance-results")
--skip-tests strings  Comma-separated list of tests to skip
--timeout duration    Test timeout (default: 30m)
--parallel int        Number of parallel test executions (default: 1)
--verbose             Enable verbose output
```

### Commands

#### run - Execute Tests

```bash
# Run all conformance tests
vcts run --provider vsphere-provider

# Run with custom settings
vcts run --provider vsphere-provider \
  --timeout 1h \
  --parallel 3 \
  --output-dir /tmp/test-results

# Skip specific tests
vcts run --provider libvirt-provider \
  --skip-tests "test-snapshots,test-linked-clones"

# Verbose output for debugging
vcts run --provider proxmox-provider --verbose
```

#### list - List Available Tests

```bash
# List all available tests
vcts list

# List tests for specific capability
vcts list --capability snapshots
```

#### validate - Validate Provider

```bash
# Validate provider configuration
vcts validate --provider vsphere-provider

# Check provider connectivity
vcts validate --provider vsphere-provider --check-connectivity
```

### Test Categories

1. **Basic Operations**: VM creation, deletion, power operations
2. **Lifecycle Management**: Start, stop, restart, suspend operations  
3. **Resource Management**: CPU, memory, disk operations
4. **Networking**: Network configuration and connectivity
5. **Storage**: Disk operations, resizing, multiple disks
6. **Snapshots**: Create, list, revert, delete snapshots
7. **Cloning**: VM cloning and linked clones
8. **Error Handling**: Provider error scenarios
9. **Performance**: Basic performance benchmarks

### Output Formats

Test results are available in multiple formats:

- **JUnit XML**: For CI/CD integration
- **JSON**: Machine-readable format  
- **HTML**: Human-readable report
- **TAP**: Test Anything Protocol

---

## vrtg-provider

Provider development toolkit for creating and managing VirtRigaud providers. Defined in [`cmd/vrtg-provider/main.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg-provider/main.go).

### Usage

```bash
vrtg-provider [command] [flags]
```

### Global Flags

```bash
--verbose, -v   Enable verbose output
--help          Help for vrtg-provider
```

### Commands

#### init - Initialize Provider

Bootstrap a new provider project with scaffolded code. Defined in [`cmd/vrtg-provider/init.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg-provider/init.go).

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

The scaffold is created under `<output>/providers/<provider-name>/`. The provider name must be lowercase alphanumeric with hyphens (max 63 chars).

#### generate - Code Generation

Regenerate protocol buffer bindings and other generated code. Defined in [`cmd/vrtg-provider/generate.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg-provider/generate.go).

Must be run from within a provider project directory (directory must contain `go.mod` and `Makefile`).

```bash
vrtg-provider generate [flags]
```

**Flags:**
- `--proto-only`: Only regenerate protocol buffer bindings
- `--clean`: Clean generated files before regenerating

**Examples:**

```bash
# Regenerate all generated code
vrtg-provider generate

# Regenerate proto bindings only
vrtg-provider generate --proto-only

# Clean and regenerate
vrtg-provider generate --clean
```

#### verify - Verification

Verify provider implementation by running build, unit tests, and VCTS conformance. Defined in [`cmd/vrtg-provider/verify.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg-provider/verify.go).

Must be run from within a provider project directory.

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

Publish a provider to the VirtRigaud catalog. Defined in [`cmd/vrtg-provider/publish.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/vrtg-provider/publish.go).

Must be run from within a provider project directory.

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

Prints the `vrtg-provider` binary version and git SHA.

### Provider Template Structure

The `init` command creates the following structure under `<output>/providers/<name>/`:

```
providers/my-provider/
├── cmd/
│   └── provider/
│       └── main.go              # Provider entry point
├── internal/
│   ├── provider/
│   │   ├── server.go           # gRPC server implementation
│   │   └── types.go            # Provider-specific types
│   └── config/
│       └── config.go           # Configuration management
├── test/
│   └── conformance/            # Conformance tests
├── deploy/
│   └── k8s/                    # Kubernetes manifests
├── Dockerfile                  # Container image
├── Makefile                    # Build automation
└── go.mod
```

---

## virtrigaud-loadgen

Load testing and benchmarking tool for VirtRigaud deployments. Defined in [`cmd/virtrigaud-loadgen/main.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/virtrigaud-loadgen/main.go).

### Usage

```bash
virtrigaud-loadgen [command] [flags]
```

### Global Flags

```bash
--kubeconfig string   Path to kubeconfig file
--namespace, -n       Kubernetes namespace (default: "default")
--output-dir, -o      Output directory for results (default: "./loadgen-results")
--dry-run            Dry-run mode (don't create Kubernetes resources)
--verbose, -v        Verbose output
```

### Commands

#### run - Execute Load Test

```bash
virtrigaud-loadgen run [flags]
```

**Flags:**
- `--config, -c`: Load generation config file (YAML)

The load parameters (duration, concurrency, VM count, operation mix) are driven by the config file. Without `--config`, defaults are used: 5m duration, concurrency 2, 10 VMs, providers `["test-provider"]`.

**Examples:**

```bash
# Run with defaults
virtrigaud-loadgen run

# Run with a config file
virtrigaud-loadgen run --config loadtest-config.yaml

# Dry run (logs what would happen without creating VMs)
virtrigaud-loadgen run --config loadtest-config.yaml --dry-run
```

### Configuration File

The YAML config maps to the `LoadGenConfig` struct in `cmd/virtrigaud-loadgen/main.go`:

```yaml
# loadtest-config.yaml
duration: "30m"
concurrency: 10
rampUpTime: "5m"
steadyState: "20m"
rampDownTime: "5m"

vmTemplate:
  classRef: "small"
  imageRef: "ubuntu-22-template"
  labels:
    generated-by: loadgen

providers:
  - "vsphere-provider"

vmCount: 50

# Operation mix — percentages, must not need to sum to 100
operations:
  create: 20
  delete: 10
  power: 15
  reconfigure: 10
  snapshot: 5
  clone: 5
  describe: 35
```

### Metrics and Reporting

Results are saved to `<output-dir>/` in CSV and Markdown summary formats. Each row in the CSV represents one operation attempt with columns: `Operation`, `Provider`, `VMName`, `StartTime`, `Duration`, `Success`, `Error`, `Phase`.

The Markdown summary includes P50 / P95 / P99 latency percentiles per operation type.

---

## Advanced Usage

### Automation and Scripting

#### Bash Integration

```bash
#!/bin/bash
# VM management script

# Function to check VM status
check_vm_status() {
  local vm_name=$1
  vrtg vm describe "$vm_name" --output json | jq -r '.status.powerState'
}

# Wait for VM to be ready
wait_for_vm() {
  local vm_name=$1
  local timeout=300
  local count=0
  
  while [ $count -lt $timeout ]; do
    status=$(check_vm_status "$vm_name")
    if [ "$status" = "On" ]; then
      echo "VM $vm_name is ready"
      return 0
    fi
    sleep 5
    count=$((count + 5))
  done
  
  echo "Timeout waiting for VM $vm_name"
  return 1
}

# Create and wait for VM
vrtg vm create --file vm-config.yaml
wait_for_vm "my-vm"
```

#### CI/CD Integration

```yaml
# .github/workflows/vm-test.yml
name: VM Integration Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install vrtg CLI
        run: |
          curl -L "https://github.com/projectbeskar/virtrigaud/releases/latest/download/vrtg-linux-amd64" -o vrtg
          chmod +x vrtg
          sudo mv vrtg /usr/local/bin/
      
      - name: Setup kubeconfig
        run: echo "${{ secrets.KUBECONFIG }}" | base64 -d > ~/.kube/config
      
      - name: Run conformance tests
        run: vcts run --provider test-provider --output-dir test-results
      
      - name: Upload test results
        uses: actions/upload-artifact@v3
        with:
          name: conformance-results
          path: test-results/
```

### Configuration Management

#### Environment-specific Configurations

```bash
# Development environment
export VRTG_KUBECONFIG=~/.kube/dev-config
export VRTG_NAMESPACE=development
export VRTG_OUTPUT=yaml

# Production environment  
export VRTG_KUBECONFIG=~/.kube/prod-config
export VRTG_NAMESPACE=production
export VRTG_OUTPUT=json

# Use environment-specific settings
vrtg vm list  # Uses environment variables
```

#### Configuration Files

Create `~/.vrtg/config.yaml`:

```yaml
contexts:
  development:
    kubeconfig: ~/.kube/dev-config
    namespace: development
    output: yaml
    timeout: 30s
  
  production:
    kubeconfig: ~/.kube/prod-config
    namespace: production
    output: json
    timeout: 60s

current-context: development

aliases:
  ls: vm list
  get: vm describe
  logs: provider logs
```

### Troubleshooting

#### Common Issues

1. **Connection Issues**
```bash
# Check cluster connectivity
vrtg provider list

# Validate kubeconfig
kubectl cluster-info

# Check provider logs
vrtg provider logs <provider-name> --tail 100
```

2. **Permission Issues**
```bash
# Check RBAC permissions
kubectl auth can-i create virtualmachines

# Get current user context
kubectl auth whoami
```

3. **Provider Issues**
```bash
# Check provider status
vrtg provider status <provider-name>

# Run diagnostics
vrtg diag bundle --include-logs
```

#### Debug Mode

Enable debug output:

```bash
# Global debug flag
vrtg --verbose vm list

# Provider-specific debugging
vrtg provider logs <provider-name> --follow --verbose

# Conformance test debugging
vcts run --provider <provider-name> --verbose
```

---

## alpha-to-beta-dryrun

A one-shot migration helper from the v1alpha1 API era. Defined in [`cmd/alpha-to-beta-dryrun/main.go`](https://github.com/projectbeskar/virtrigaud/blob/main/cmd/alpha-to-beta-dryrun/main.go).

!!! warning "Tombstoned in v0.3.6"
    The `v1alpha1` API was removed before v0.3.0. This binary now exits with an error message explaining that v1alpha1 resources should have been migrated before reaching this version. It is retained in the repository as a safety net but has no useful functionality.

    If you are upgrading from a pre-v0.3.0 cluster, you must have already migrated your resources to `v1beta1` in a prior release. There is no automated migration path from v1alpha1 at this version.

---

## See Also

- [Getting Started Guide](../getting-started/index.md)
- [Provider Development](../providers/tutorial.md)
- [API Reference](../api-reference/cli.md)
- [Examples](../examples/index.md)
