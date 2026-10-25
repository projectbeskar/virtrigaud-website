<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Testing Locally

This page describes the test suites VirtRigaud ships in **v0.4.0** and how
to run them. Each layer has a specific scope — they are not interchangeable.

| Layer | Target | What it covers | Cluster required? |
|-------|--------|----------------|-------------------|
| **Unit + envtest** | `make test` | Package unit tests plus reconciler tests against an in-process Kubernetes API server (controller-runtime's `envtest`, loading the CRDs from `config/crd/bases/`), including a server-side dry-run of every VirtRigaud object under `examples/`. All packages except `test/e2e` and `test/integration`. The vSphere and libvirt providers are pure Go and **are** covered. | No |
| **go-libvirt integration** | `make test-libvirt-integration` | The go-libvirt `test:///default` driver tests in `internal/providers/libvirt/`. Needs a reachable `libvirtd` (no KVM or privilege); skips itself when there is none. | No (needs libvirtd) |
| **Integration** | `make test-integration` | Cross-package observability tests (and the seed bed for future controller-integration tests). `test/integration/observability_test.go`. | No |
| **End-to-end** | `make test-e2e` | Kind cluster + ginkgo against the manager image. `test/e2e/`. Not run by CI. | **Yes** (Kind) |
| **Conformance specs** | `vcts validate test/conformance/specs/` | Validates the conformance spec files (`internal/conformance/` is the runner and validator). This is what CI runs; `vcts run` is not functional yet. | No |
| **Lint** | `make lint` | `golangci-lint` v2.12.2 over the root module. | No |
| **Build** | `make build` | Compiles `bin/manager`. | No |

## Daily edit loop

After **any** `.go` change, the project rule is:

```bash
make fmt          # must produce no diff
make lint         # fix every warning
make test         # all packages pass
make build        # must succeed
```

`make test` and `make build` already run `gen-crds generate fmt vet` first. If `api/infra.virtrigaud.io/v1beta1/*_types.go` changed, regenerate and commit the output:

```bash
make generate gen-crds   # zz_generated.deepcopy.go + config/crd/bases/ (committed)
make gen-helm-crds       # charts/virtrigaud/crds/ (gitignored, only needed for the chart)
```

If `proto/provider/v1/provider.proto` changed:

```bash
make proto        # regen Go bindings (buf)
make proto-lint   # buf lint
```

## Unit tests + envtest

```bash
# Run all unit tests except the e2e and integration suites
make test
```

Internals of the `test` target (`Makefile`, target `test`):

- Depends on `gen-crds generate fmt vet setup-envtest`. The
  `setup-envtest` step pulls a matching `etcd` + `kube-apiserver` for
  controller-runtime's in-process test cluster.
- The K8s version used by `envtest` is derived from `go.mod`'s `k8s.io/api`
  pin (`ENVTEST_K8S_VERSION` in the Makefile). For v0.4.0 that is
  `k8s.io/api v0.32.x`, so envtest **1.32**.
- Sets `KUBEBUILDER_ASSETS` to the local `bin/k8s/<version>-…` directory
  before invoking `go test`.
- Runs `go test -timeout 20m -coverprofile cover.out` over `go list ./...`
  minus `/test/e2e` and `/test/integration`, which have their own targets.
  `go vet` for the `sdk/` and `proto/` modules runs as part of `make vet`
  (they are separate Go modules, so `go test ./...` at the repository root
  does not reach their tests; run `cd sdk && go test ./...` and
  `cd proto && go test ./...` for those).
- Includes the `examples/` dry-run: every VirtRigaud YAML document under
  `examples/` is created with a server-side dry-run against the envtest API
  server, so an example that drifts from the CRD schema fails the suite
  (`internal/controller/examples_envtest_test.go`).

### Pre-baking the envtest binaries

If you want the envtest assets resolved without running the full test
suite (useful in CI cache layers):

```bash
make envtest-setup
# Prints the KUBEBUILDER_ASSETS path you can export for IDE-driven test runs
```

### Running a single test

`make test` ultimately calls `go test` over a list of packages. To run a
single test by name, invoke `go test` directly:

```bash
# Export KUBEBUILDER_ASSETS once per shell so envtest works
export KUBEBUILDER_ASSETS="$(bin/setup-envtest use $(go list -m -f '{{.Version}}' k8s.io/api | awk -F'[v.]' '{printf "1.%d", $3}') --bin-dir bin -p path)"

# Then target a single test
go test -v -count=1 -run '^TestReconcileVM_DiskSizeLimit_CreateRefused$' ./internal/controller/...
```

### Coverage

`make test` writes `cover.out` to the repo root. Inspect:

```bash
go tool cover -func=cover.out | sort -k 3 -n
go tool cover -html=cover.out -o cover.html
```

## Integration tests

```bash
make test-integration
```

The integration suite (`test/integration/`) currently contains:

- `observability_test.go` — cross-package observability assertions
  (logging, metrics, health, circuit breaker and retry wiring).
- `vm_lifecycle_test.go.disabled` — disabled placeholder for future
  controller-integration tests. **Not** active in v0.4.0.

The target runs with `-race -coverprofile=cover-integration.out`. No
cluster is required.

## End-to-end tests (Kind)

!!! note "Status of the e2e suite"
    The suite under `test/e2e/` is the kubebuilder scaffold and is not run by
    CI. It is gated behind a `//go:build e2e` tag so that a default
    `go test ./...` does not try to start it, and `make test-e2e` passes
    `-tags=e2e`, so it runs the suite rather than zero tests
    ([#146](https://github.com/projectbeskar/virtrigaud/issues/146), fixed in
    [#164](https://github.com/projectbeskar/virtrigaud/pull/164)). The suite builds the manager image with
    `make docker-build IMG=...` and deploys with `make deploy IMG=...`, but the
    Makefile's image variable is `CONTROLLER_IMG`, so the image tag the suite
    loads into Kind and the tag the Makefile builds and deploys differ. Treat
    the suite as a starting point that may need local adjustment before it
    passes.

### Bringing up Kind

```bash
# Create a Kind cluster (make test-e2e requires a running kind cluster)
kind create cluster --name kind

# Run the suite
make test-e2e
```

The Ginkgo `BeforeSuite` builds the manager image, loads it into Kind and
installs cert-manager (skip that with `CERT_MANAGER_INSTALL_SKIP=true` if it
is already installed); the specs then install the CRDs, deploy the manager and
check that it is running and serves metrics.

### Cleaning up

```bash
kind delete cluster --name kind
```

## Provider conformance

The conformance harness lives in two places:

- `internal/conformance/` — the runner + validator implementation (used by
  the `vcts` CLI in `cmd/vcts/`).
- `test/conformance/specs/` — the spec files. `basic-lifecycle.yaml` is the
  only spec shipping in v0.4.0; it defines two tests, `vm-create-delete` and
  `vm-power-cycle`.

What works and what CI runs is spec validation:

```bash
go build -o bin/vcts ./cmd/vcts
./bin/vcts validate test/conformance/specs/   # validate the spec files
./bin/vcts list                               # list the tests (run from the repo root)
```

`vcts validate` exits non-zero when a spec file cannot be parsed or holds an
invalid test. `vcts run --provider <name>` also exists, but the runner's step
executor (create, update, delete, wait, validate) is not implemented in
v0.4.0, so every selected test fails and the command exits non-zero; do not
use it as a pass/fail gate yet. There is no `make` shortcut for conformance.
See the
[CLI Tools Reference](../references/cli-tools.md#vcts).

## Linting

```bash
make lint          # run-only
make lint-fix      # apply auto-fixable issues
make lint-config   # validate the golangci-lint config itself
```

`golangci-lint` is downloaded the first time you invoke `make lint`.
The version (v2.12.2) is pinned in the Makefile by
`GOLANGCI_LINT_VERSION`; CI runs the same version. The configuration is
`.golangci.yml` at the repository root.

## Proto linting and breaking-change checks

```bash
make proto-lint        # buf lint
make proto-breaking    # check for breaking changes vs the main branch
```

Both require `buf` (v1.46.0, installed under `bin/` on demand).

## CI parity

The `make ci` target runs the same checks the GitHub Actions CI runs:

```bash
make ci   # = test + lint + proto-lint + generate + gen-crds + vet
```

`make ci` covers the core of CI's Test, Lint, and Verify Generated Files
jobs. Some CI jobs have no local `make ci` equivalent: the chart render checks
(`make helm-lint`, `make helm-template` and the `make verify-*-render`
targets), `make verify-helm-crds`, `make verify-no-lab-names`, and the
container image builds. Run those as well when your change touches the chart,
the CRDs or the Dockerfiles.

### Workflow-as-code testing with `act`

The repository ships a set of helper scripts under `hack/` that wrap
[`act`](https://github.com/nektos/act) to run the actual GitHub Actions
workflows locally. They are designed to save GitHub Actions minutes for
contributors with limited budgets; they are **not** required for normal
contributions, and `make ci` is sufficient for almost everything.

```bash
hack/test-workflows-locally.sh setup     # one-time
hack/test-lint-locally.sh                # lint workflow only
hack/test-ci-locally.sh                  # ci workflow (quick or full)
hack/test-helm-locally.sh                # helm chart in Kind
hack/test-release-locally.sh v0.4.0-test # release workflow w/ local registry
```

`test-ci-locally.sh`, `test-helm-locally.sh` and `test-workflows-locally.sh` accept `help` or `--help`; read the others' header comments for their options. The orchestrator
(`hack/test-workflows-locally.sh`) creates and reads `.actrc`, `.env.local`
and `.secrets` files in the repo root.

## Troubleshooting

### `envtest` cannot find etcd / kube-apiserver

```bash
make envtest-setup            # downloads to bin/k8s/<version>-<os>-<arch>/
export KUBEBUILDER_ASSETS="$(bin/setup-envtest use $(go list -m -f '{{.Version}}' k8s.io/api | awk -F'[v.]' '{printf "1.%d", $3}') --bin-dir bin -p path)"
```

If the download fails (corporate proxy), fetch the assets on a connected
machine, copy them to `bin/k8s/` and set `KUBEBUILDER_ASSETS` to that directory.

### `golangci-lint` fails on unrelated packages

`make lint` runs `golangci-lint run` with the repository's `.golangci.yml`.
If you run `golangci-lint` by hand, use the same configuration and the
pinned version:

```bash
bin/golangci-lint run --config .golangci.yml ./...
```

### libvirt provider tests

The libvirt provider is pure Go (ADR-0008): it does not link libvirt, so `make
test`, `make lint` and `make build-provider-libvirt` need no CGO toolchain or
`libvirt-dev` headers, and the provider's unit tests run in the default
`make test`. Only the go-libvirt `test:///default` integration tests need a
`libvirtd`:

```bash
sudo apt-get install -y libvirt-daemon-system    # Debian/Ubuntu
sudo make test-libvirt-integration
```

They skip themselves when no libvirtd is reachable.

### IDE "Run all tests" fails on `TestE2E`

The e2e suite is gated behind a build tag, so the IDE should not pick it up
by default. If you still see it, your IDE's Go settings include `-tags=e2e`;
remove it for the default test run.

## See also

- [Building Locally](building-locally.md) — building the binaries before
  testing them.
- [Contributing](contributing.md) — the full PR workflow.
- The Go test suite uses
  [controller-runtime envtest](https://book.kubebuilder.io/reference/envtest.html)
  under the hood — the upstream docs are accurate for our setup.
