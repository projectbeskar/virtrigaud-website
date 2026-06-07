<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Testing Locally

This page describes the test suites VirtRigaud ships in **v0.3.8** and how
to run them. Each layer has a specific scope — they are not interchangeable.

| Layer | Target | What it covers | Cluster required? |
|-------|--------|----------------|-------------------|
| **Unit + envtest** | `make test` | Reconciler logic against an in-process Kubernetes API server (controller-runtime's `envtest`). All packages except libvirt (CGO), `test/e2e`, and `test/integration`. The vSphere provider is pure-Go and **is** covered by `make test`. | No |
| **Integration** | `make test-integration` | Cross-package observability tests (and the seed bed for future controller-integration tests). `test/integration/observability_test.go`. | No |
| **End-to-end** | `make test-e2e` *(see warning below)* | Kind cluster + ginkgo against the manager image. `test/e2e/`. | **Yes** (Kind) |
| **Conformance** | hand-run | Per-provider conformance spec at `test/conformance/specs/basic-lifecycle.yaml`. Drives the in-tree conformance runner (`internal/conformance/`). | Yes (provider, real or mock) |
| **Lint** | `make lint` | `golangci-lint` over the same package set as `make test`. | No |
| **Build** | `make build` | Compiles `bin/manager`. | No |

## Daily edit loop

After **any** `.go` change, the project rule (per `CLAUDE.md`) is:

```bash
make fmt          # must produce no diff
make lint         # fix every warning
make test         # all packages pass
make build        # must succeed
```

If `api/infra.virtrigaud.io/v1beta1/*_types.go` changed:

```bash
make update-crds  # alias for: make generate manifests sync-helm-crds
```

If `proto/provider/v1/provider.proto` changed:

```bash
make proto        # regen Go bindings
make proto-lint   # buf lint
```

## Unit tests + envtest

```bash
# Run all unit tests excluding libvirt (CGO) and the e2e + integration suites
make test
```

Internals of the `test` target (`Makefile:127-131`):

- Depends on `gen-crds generate fmt vet setup-envtest`. The
  `setup-envtest` step pulls a matching `etcd` + `kube-apiserver` for
  controller-runtime's in-process test cluster.
- The K8s version used by `envtest` is derived from `go.mod`'s `k8s.io/api`
  pin (`Makefile:520`). For v0.3.8 that pins to a `1.3x` minor.
- Sets `KUBEBUILDER_ASSETS` to the local `bin/k8s/<version>-…` directory
  before invoking `go test`.
- Excludes `/internal/providers/libvirt`, `/cmd/provider-libvirt`,
  `/test/e2e`, and `/test/integration` — libvirt because it requires CGO
  + `libvirt-dev` headers; the latter two because they have their own
  targets. The same libvirt-package exclusion applies to `make lint`, so to
  exercise libvirt you run `go test ./internal/providers/libvirt/...`
  directly (see [the libvirt note below](#libvirt-provider-tests-dont-run)).
  The **vSphere** provider is pure-Go and is built/tested/linted by the
  default targets.

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
go test -v -count=1 -run '^TestVirtualMachineReconciler_Reconcile$' ./internal/controller/...
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
  (metrics families wired through the manager bootstrap).
- `vm_lifecycle_test.go.disabled` — disabled placeholder for future
  controller-integration tests. **Not** active in v0.3.8.

The target runs with `-race -coverprofile=cover-integration.out`. No
cluster is required.

## End-to-end tests (Kind)

!!! danger "`make test-e2e` is broken in v0.3.8 — track #146"
    The `test-e2e` target in the Makefile invokes
    `go test ./test/e2e/ -v -ginkgo.v` (`Makefile:164`).

    Since v0.3.6, [PR
    #133](https://github.com/projectbeskar/virtrigaud/pull/133) added a
    `//go:build e2e` build tag to both `test/e2e/e2e_suite_test.go` and
    `test/e2e/e2e_test.go` so that a default `go test ./...` no longer
    fails on the e2e suite (which needs Kind to be up). That fix is
    correct.

    However, `make test-e2e` does **not** pass `-tags=e2e` — so as of
    v0.3.8, `make test-e2e` happily runs zero tests and exits 0. The fix
    (adding `-tags=e2e` to the target) is tracked as
    [#146](https://github.com/projectbeskar/virtrigaud/issues/146). Until
    that lands, **run the explicit form**:

    ```bash
    go test -tags=e2e ./test/e2e/... -v -ginkgo.v
    ```

### Bringing up Kind

```bash
# Create a Kind cluster the e2e suite expects
kind create cluster --name kind

# (Optional) load the locally-built manager image
make docker-build
kind load docker-image controller:latest --name kind
```

The Ginkgo `BeforeSuite` brings up the manager Deployment, applies CRDs,
and waits for the controller to be `Ready`. If a step fails, the suite
fails fast.

### Cleaning up

```bash
kind delete cluster --name kind
```

## Provider conformance

The conformance harness lives in two places:

- `internal/conformance/` — the runner + validator implementation.
- `test/conformance/specs/` — the spec files. `basic-lifecycle.yaml` is the
  only spec shipping in v0.3.8.

`basic-lifecycle.yaml` is the only spec shipping in v0.3.8. It exercises the
minimal Provider + VMClass + VMImage + VirtualMachine create-delete flow
against a target provider. To run it:

```bash
# Bring up the mock provider (or your real provider) and a manager
# that points at it. Then exercise the spec via the runner:
go run ./internal/conformance/... \
  --spec test/conformance/specs/basic-lifecycle.yaml
```

There is no `make` shortcut for conformance in v0.3.8; the harness is
invoked directly when validating a new provider against the contract.

## Linting

```bash
make lint          # run-only
make lint-fix      # apply auto-fixable issues
make lint-config   # validate the golangci-lint config itself
```

`golangci-lint` is downloaded the first time you invoke `make lint`.
The version is pinned in the Makefile via the `golangci-lint` install
target.

## Proto linting and breaking-change checks

```bash
make proto-lint        # buf lint
make proto-breaking    # check for breaking changes vs origin/main
```

Both require `buf` (installed on demand).

## CI parity

The `make ci` target runs the same checks the GitHub Actions CI runs:

```bash
make ci   # = test + lint + proto-lint + generate + gen-crds + vet
```

If `make ci` passes locally and your changes don't depend on CI-only
infrastructure (Docker registry, signing keys, etc.), the GitHub Actions
run should pass too.

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
hack/test-release-locally.sh v0.3.8-test # release workflow w/ local registry
```

Each script's `--help` flag describes its options. The orchestrator
(`hack/test-workflows-locally.sh`) reads `.actrc`, `.env.local`, and an
optional `.secrets` file in the repo root.

## Troubleshooting

### `envtest` cannot find etcd / kube-apiserver

```bash
make envtest-setup            # downloads to bin/k8s/<version>-<os>-<arch>/
export KUBEBUILDER_ASSETS="$(bin/setup-envtest use $(go list -m -f '{{.Version}}' k8s.io/api | awk -F'[v.]' '{printf "1.%d", $3}') --bin-dir bin -p path)"
```

If the download fails (corporate proxy), point `setup-envtest` at a local
mirror via `ENVTEST_INSTALL_DIR` or pre-populate the directory by hand.

### `golangci-lint` fails on unrelated packages

`make lint` runs the linter over a deliberately-narrow package set, but if
you're running `golangci-lint` by hand it will scan everything. Use the
project config:

```bash
golangci-lint run --config .golangci.yml ./...
```

### libvirt provider tests don't run

That is expected. The libvirt provider uses CGO and depends on
`libvirt-dev` headers, so **both `make test` and `make lint` deliberately
exclude the `internal/providers/libvirt` package** (`Makefile:130`). To
exercise it locally, run it directly:

```bash
sudo apt-get install -y libvirt-dev pkg-config   # Debian/Ubuntu
CGO_ENABLED=1 go test ./internal/providers/libvirt/...
```

The vSphere provider, by contrast, is pure-Go and is covered by the default
`make test` / `make lint` / `make build` targets — no CGO toolchain needed.

### `make test-e2e` exits 0 immediately

You're hitting #146 — the build tag is missing from the make target. Run
the explicit form:

```bash
go test -tags=e2e ./test/e2e/... -v -ginkgo.v
```

### IDE "Run all tests" fails on `TestE2E`

Pre-PR #133 this was the default and the `BeforeSuite` would fail with
"Kind not running". Since v0.3.6 the e2e suite is gated behind a build
tag, so the IDE should no longer pick it up. If you still see it, your
IDE's Go settings include `-tags=e2e`; remove it for the default test run.

## See also

- [Building Locally](building-locally.md) — building the binaries before
  testing them.
- [Contributing](contributing.md) — the full PR workflow.
- The Go test suite uses
  [controller-runtime envtest](https://book.kubebuilder.io/reference/envtest.html)
  under the hood — the upstream docs are accurate for our setup.
