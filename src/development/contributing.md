<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Contributing to VirtRigaud

Thank you for your interest in contributing to VirtRigaud! This document
provides guidelines and information for contributors.

## Development Setup

### Prerequisites

- **Go 1.26+** — required since
  [#125](https://github.com/projectbeskar/virtrigaud/pull/125) (v0.3.6 bumped
  the toolchain floor from 1.24.0 → 1.26.0; v0.4.0 builds on **1.26.10**). The
  repo's `go.mod` is the source of truth; CI uses `go-version-file: go.mod`
  so locally you should match.
- Docker
- Kubernetes cluster (kind, k3s, or remote)
- kubectl
- Helm 3.x
- make

### Clone and Setup

```bash
git clone https://github.com/projectbeskar/virtrigaud.git
cd virtrigaud

# Build the manager once to bootstrap controller-gen + envtest dependencies
make build
```

## Development Workflow

### 1. Making Changes

#### API Changes

When modifying API types under `api/infra.virtrigaud.io/v1beta1/`:

```bash
# Edit API types
vim api/infra.virtrigaud.io/v1beta1/virtualmachine_types.go

# Regenerate deepcopy methods
make generate

# Regenerate CRDs under config/crd/bases/ (committed)
make gen-crds          # alias: make manifests

# Regenerate CRDs directly into the Helm chart (charts/virtrigaud/crds/,
# gitignored: generated on demand, never committed)
make gen-helm-crds

# Sanity check: the chart must lint with the freshly generated CRDs
make helm-lint
```

The Go types under `api/infra.virtrigaud.io/v1beta1/*_types.go` are the
**single source of truth**. Never hand-edit `config/crd/bases/`,
`charts/virtrigaud/crds/`, or `zz_generated.deepcopy.go` — regenerate them
instead. v1beta1 is the stable API; breaking changes require an ADR.

If you change `proto/provider/v1/provider.proto`, regenerate the Go bindings with
`make proto` and check it with `make proto-lint` and `make proto-breaking`;
the generated files under `proto/rpc/provider/v1/` are committed.

#### Code Changes

For other code changes, the mandatory loop after **any** `.go` edit is:

```bash
make fmt    # must produce no diff
make lint   # fix every warning
make test   # all packages pass
make build  # must succeed
```

Add or update the corresponding `*_test.go` and add a CHANGELOG entry (see
below) before opening a PR.

### 2. CRD Management

CRDs are generated from `api/infra.virtrigaud.io/v1beta1/*_types.go` — the
Go types are the single source of truth — and are not duplicated in git:

- `config/crd/bases/` is **committed**; it is what `kubectl apply -k` and the
  release use.
- `charts/virtrigaud/crds/` is **gitignored** (only a `.gitkeep` is tracked);
  it is generated at package time.

```bash
# After ANY change to api/infra.virtrigaud.io/v1beta1/*_types.go
make generate          # DeepCopy methods
make gen-crds          # writes config/crd/bases/ (commit the result)
make gen-helm-crds     # writes charts/virtrigaud/crds/ (not committed)

# Lint / render the chart; both regenerate the chart CRDs first
make helm-lint
make helm-template
```

!!! warning "Installing the chart from a checkout"
    A fresh checkout has an empty `charts/virtrigaud/crds/`. Run
    `make gen-helm-crds` (or use `make helm-package`, `make helm-lint` or
    `make helm-template`, which do) before `helm install` / `helm upgrade`
    from `charts/virtrigaud`. Otherwise the chart ships no — or stale —
    CRDs, and on upgrade a stale set can prune fields from the live CRDs.

CI's **Verify Generated Files** job regenerates the code, the CRDs and the
protobuf bindings and fails if `git diff` is not clean; it also runs
`make verify-helm-crds`, which asserts that the chart CRDs generated from
the Go types are byte-identical to `config/crd/bases/` (this trips when a
new CRD is added but the chart generator does not emit it).

### 3. Testing

```bash
# Unit tests (default `go test ./...`)
make test

# Integration tests (cross-package observability tests; no cluster required)
make test-integration

# go-libvirt integration tests (need a reachable libvirtd; skip otherwise)
make test-libvirt-integration

# End-to-end tests (requires a running kind cluster; the suite is gated
# behind //go:build e2e and the make target passes -tags=e2e)
make test-e2e
```

See [Testing Locally](testing-locally.md) for more details.

### 4. Local Development

```bash
# Deploy to local Kind cluster for development
make dev-deploy

# Hot reload after code changes (rebuild images + restart pods)
make dev-reload

# Watch for file changes and auto-reload (requires fswatch / inotify-tools)
make dev-watch

# Status, logs, shell, cleanup
make dev-status
make dev-logs
make dev-shell
make dev-cleanup
```

## DCO sign-off (mandatory)

Every commit must be signed off with a `Signed-off-by:` trailer per the
[Developer Certificate of Origin](https://developercertificate.org/). The
simplest way is to pass `-s` when committing:

```bash
git commit -s -m "feat(vsphere): add graceful shutdown support"
```

This appends `Signed-off-by: Your Name <your@email>` automatically from your
`user.name` / `user.email` git config. Commits without the trailer are not
accepted.

!!! tip "Maintainer workflow"
    The project maintainer's local clone uses a `prepare-commit-msg` git hook
    (under `.claude/hooks/`, gitignored) to add sign-off automatically. That
    setup is personal and not required for contributors — just remember `-s`.

## CHANGELOG entries

Every code change in `api/`, `cmd/`, `internal/`, `charts/`, `proto/`, or
`sdk/` requires a `CHANGELOG.md` entry with author attribution. The format
is strict:

```
## [YYYY-MM-DD HH:MM] - Brief Title
**Author:** @your-github-handle (Your Full Name)

### Added | Changed | Fixed | Removed | Security
- `path/to/file`: Description.

### Why
1–3 sentences on motivation.

### Impact
- [ ] Breaking change
- [ ] Requires cluster rollout
- [ ] Config change only
- [ ] Documentation only
```

Versioned release headers (`## [0.3.6] - 2026-05-25`) aggregate the per-PR
entries that preceded them. Don't reorganise existing
release sections.

## CI on pull requests

Every PR triggers the CI workflow (`.github/workflows/ci.yml`). Most of the jobs
below run on every PR; two are gated and in practice run on pushes only:

| Job                       | What it checks                                                                 |
|---------------------------|--------------------------------------------------------------------------------|
| **Test**                  | `go vet` over the root, `sdk/` and `proto/` modules, then `make test` (envtest, includes the `examples/` dry-run); uploads coverage to Codecov. |
| **Libvirt Integration**   | `make test-libvirt-integration` against a `libvirt-daemon-system` `test://` driver. |
| **Lint**                  | `golangci-lint` v2.12.2 (the version pinned in the Makefile).                  |
| **Security Scan**         | `gosec` (SARIF upload) + Trivy in repo mode (SARIF upload).                    |
| **Supply Chain Vulnerability Scan** | `govulncheck` on the root and `sdk/` modules.                        |
| **Verify Generated Files**| Runs `make generate`, `make gen-crds` and `make proto`, fails on any `git diff`, and runs `make verify-helm-crds`. |
| **Build**                 | Compiles the manager and the three hypervisor providers (libvirt, vSphere, Proxmox), `CGO_ENABLED=0`. |
| **Build Tools**           | Compiles `vrtg`, `vcts`, `virtrigaud-loadgen`, `vrtg-provider`.                |
| **Build Container Images**| On PRs, builds the manager and provider images without pushing; on `main`, pushes per-arch images and merges the manifests. |
| **Validate Helm Charts**  | `helm lint`, `helm template`, and the render checks (webhooks, NetworkPolicy, `/tmp` size limits, disk-size ceiling, admission policy). |
| **Conformance Tests**     | `vcts validate test/conformance/specs/` (spec validation only).                |
| **Integration Tests**     | `make test-integration` (cross-package observability tests).                   |
| **Catalog Validation**    | Validates `providers/catalog.yaml` against a schema; gated on that file changing (the gate reads `head_commit`, which exists only on push events, so it is skipped on pull requests). |
| **API Conversion Tests**  | Gated on `api/` or `config/crd/` changing (push events only, as above): single-version CRDs, CRD kustomization in sync, no internal lab names in tracked files, CRD generation drift. |
| **CI Summary**            | Aggregates most of the above (its `needs:` list is in `ci.yml`).              |

CI uses `go-version-file: go.mod` for the Go version (1.26.10 in v0.4.0).

### Lint

`make lint` and the CI Lint job both run **golangci-lint v2.12.2**; the
version is pinned in the Makefile (`GOLANGCI_LINT_VERSION`) and the CI
workflow, and the configuration is `.golangci.yml`. Keep the two in lockstep
when bumping.

### Branch protection on `main`

The `main` branch has a ruleset enforcing:

- 1 approving review required
- Linear history (no merge commits via the UI)
- No force-push
- No deletion

Required status checks are **not** currently enforced at the ruleset level
(they're observable via the **CI Summary** job, which authors and reviewers
are expected to check before merge). Merge, squash and rebase merges are all
allowed.

## Contribution Guidelines

### Pull Request Process

1. **Fork and branch**: Create a feature branch from `main`.
2. **Make changes**: Follow the development workflow above.
3. **Test thoroughly**: `make fmt lint test build` locally before pushing.
4. **Sign off**: Every commit needs `-s` (DCO).
5. **CHANGELOG**: Add an entry for any code-affecting change.
6. **Regenerate**: If you touched `api/`, run `make generate gen-crds` and
   commit the regenerated `zz_generated.deepcopy.go` and
   `config/crd/bases/`; if you touched `provider.proto`, run `make proto`
   and commit the bindings. (`charts/virtrigaud/crds/` is generated and
   gitignored.) CI's **Verify Generated Files** job fails otherwise.
7. **Submit PR**: Clear description, linked issue, mention which CI jobs you
   expect to be affected.

### PR Requirements

- [ ] All CI checks pass (see table above)
- [ ] Generated files are in sync (Verify Generated Files green)
- [ ] Code is formatted (`make fmt`)
- [ ] Code is linted (CI Lint green)
- [ ] Documentation updated if needed (separate PR on the
      [website repo](https://github.com/projectbeskar/virtrigaud-website) for
      user-facing docs)
- [ ] CHANGELOG entry added with author attribution
- [ ] Commits signed off (DCO)

### Commit Message Format

Use conventional commit format:

```
<type>(<scope>): <description>

[optional body]

Signed-off-by: Your Name <your@email>
```

**Types:**

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes
- `refactor`: Code refactoring
- `test`: Test changes
- `chore`: Maintenance tasks
- `security`: Security-related changes (CVE fixes, dependency bumps)

**Examples:**

```
feat(vsphere): add graceful shutdown support
fix(crd): resolve powerState validation conflict
docs(upgrade): add v0.3.5 → v0.3.6 section
security: bump go.opentelemetry.io/otel + sdk to v1.43.0
```

## Code Style

### Go Code

- Follow standard Go conventions
- Use `gofmt` and `golangci-lint`
- Add GoDoc on every exported function, type, constant, and variable
- Wrap errors with context: `fmt.Errorf("get VirtualMachine %s: %w", name, err)`
- Context (`ctx context.Context`) is the first parameter for any I/O function
- No `panic()` in library code; no `time.Sleep()` for synchronization; no
  hardcoded namespaces
- No `interface{}` / `any` without a typed assertion
- Use structured logging via `ctrl.LoggerFrom(ctx)`
- Use `controllerutil.SetControllerReference` for owner refs on child resources
- Use `meta.SetStatusCondition` and always set `ObservedGeneration`
- Finalizers: `controllerutil.AddFinalizer` / `RemoveFinalizer`, and check
  `DeletionTimestamp.IsZero()` before reconciling spec
- Global constants for any string literal used 2+ times (finalizers, condition
  types, annotation keys)
- Include unit tests for new functionality

### YAML/Kubernetes

- Use 2-space indentation
- Follow Kubernetes API conventions
- Add descriptions to CRD fields
- Include examples in documentation

### Documentation

- Use clear, concise language
- Include code examples
- Update both API docs and user guides
- Test documentation examples

## Compliance posture

VirtRigaud is documented as deployable in **regulated banking environments**.
That means contributors must:

- Never log, persist, or expose secrets — including in Status fields or
  Kubernetes events.
- Never commit example secrets, internal hostnames, or customer data.
- Treat CHANGELOG entries with author attribution as an audit record — keep
  them accurate and well-attributed.

## Testing

### Unit Tests

```bash
# Run all unit tests
make test

# Run tests for a specific package
go test ./internal/controller/...

# Run with coverage (no dedicated make target; use go test -cover)
go test -cover ./...
```

### Integration Tests

```bash
make test-integration
```

### End-to-end Tests

```bash
# Requires a running kind cluster; the suite is gated behind //go:build e2e
# and the make target passes -tags=e2e.
make test-e2e
```

The e2e suite is the kubebuilder scaffold and is not run by CI. See
[Testing Locally](testing-locally.md#end-to-end-tests-kind) for its caveats.

### Provider Conformance Specs

VCTS (VirtRigaud Conformance Test Suite) lives at `cmd/vcts/`, with its runner
in `internal/conformance/` and its specs in `test/conformance/specs/`. What
CI runs, and what you should run after editing a spec, is spec validation:

```bash
go build -o bin/vcts ./cmd/vcts
./bin/vcts validate test/conformance/specs/
```

`vcts run` exists but its step executor is not implemented in v0.4.0; see the
[CLI Tools Reference](../references/cli-tools.md#vcts).

## Release Process

### For Maintainers

1. **Prepare release**:
   ```bash
   # Regenerate deepcopy methods and the committed CRDs
   make generate
   make gen-crds

   # Update version in charts
   vim charts/virtrigaud/Chart.yaml

   # Update CHANGELOG.md with a versioned header
   vim CHANGELOG.md
   ```

2. **Cut an RC, smoke, then promote**:
   ```bash
   git tag v0.4.0-rc1
   git push origin v0.4.0-rc1
   # ...deploy to a test cluster, run the smoke recipe, then:
   git tag v0.4.0
   git push origin v0.4.0
   ```

3. **The release workflow handles** (any `v*` tag; a tag containing `-` is
   published as a pre-release):
   - Building and pushing multi-arch images, signing them with cosign, and
     generating SBOMs and SLSA provenance
   - Running Trivy on the images (release blocker if HIGH/CRITICAL CVE)
   - Creating the GitHub release
   - Packaging the Helm chart (it runs `make gen-helm-crds` first, since the
     chart CRDs are not committed)
   - Building the CLI binaries (`vrtg`, `vcts`, `vrtg-provider`,
     `virtrigaud-loadgen`) for linux and darwin (amd64, arm64) and windows
     (amd64)

The project follows an **`rc1 → smoke → final`** pattern; v0.3.5 and v0.3.6
each shipped on a single RC, while v0.4.0 went through nine release
candidates. A failing Trivy scan on the manager image is a
hard release blocker — see the v0.3.6 changelog for the OpenTelemetry CVE
example.

## Dependabot policy

Dependency PRs are managed by Dependabot per the policy in
`.github/dependabot.yml`
([#135](https://github.com/projectbeskar/virtrigaud/pull/135)):

- **Schedule**: weekly, Monday 09:00 America/Toronto
- **Minor + patch bumps** for GitHub Actions: batched into a single grouped PR
  per ecosystem (group: `ci-actions-non-major`)
- **Major bumps**: surfaced individually so each can be reviewed for
  breaking-change context
- Top-of-file comments document the Node 20 deadline (2026-09-16) and the
  SHA-pinning caveat

If a Dependabot major bump lands that touches CI infrastructure, please
verify the matching `# vX` version-comment in the workflow file gets updated
in the same PR.

## Common Issues

### CRD Sync Issues

If **Verify Generated Files** fails in CI (generated files out of sync, or
"Helm chart CRDs drifted"):

```bash
make generate gen-crds gen-helm-crds
make proto           # only if provider.proto changed
git add api/ config/crd/bases/ proto/
git commit -s -m "chore: regen generated files"
```

`charts/virtrigaud/crds/` is gitignored, so it is never added. If
`make verify-helm-crds` itself fails, `make gen-helm-crds` no longer
produces the same CRD set as `make gen-crds` (for example a new CRD is not
emitted into the chart); fix the generator rather than the generated files.

### Test Failures

```bash
# Re-run the failing package verbosely
go test -v -count=1 ./internal/controller/...

# The go-libvirt integration tests skip themselves when no libvirtd is
# reachable; run them against a local libvirtd with
make test-libvirt-integration
```

(`make clean` and `SKIP_LIBVIRT_TESTS` do not exist.) If envtest cannot find
`etcd` / `kube-apiserver`, see
[Testing Locally](testing-locally.md#envtest-cannot-find-etcd-kube-apiserver).

### Development Environment

```bash
# Reset the local Kind deployment
make dev-cleanup
make dev-deploy

# Check logs
make dev-logs
```

## Documentation Contributions

We welcome documentation improvements! User-facing docs live in a separate
repository.

### Documentation Repository

```bash
git clone https://github.com/projectbeskar/virtrigaud-website.git
cd virtrigaud-website
```

### Making Documentation Changes

1. Install dependencies:
   ```bash
   make install
   make install-crd-tools
   make install-proto-tools
   ```

2. Make your changes in the `src/` directory

3. Preview locally:
   ```bash
   make serve
   # Visit http://127.0.0.1:8000
   ```

4. Submit a pull request (signed off with `-s`, same as the main repo)

See [Building Locally](building-locally.md) for more details on documentation
development.

## Getting Help

- **[GitHub Issues](https://github.com/projectbeskar/virtrigaud/issues)** — Bug reports and feature requests
- **[GitHub Discussions](https://github.com/projectbeskar/virtrigaud/discussions)** — Questions and community support
- **[Documentation](https://projectbeskar.github.io/virtrigaud/)** — Comprehensive guides

## Code of Conduct

VirtRigaud follows the CNCF Code of Conduct. Please be respectful and
inclusive in all interactions.

## Recognition

Contributors are recognized in:

- CHANGELOG.md with author attribution (per-PR and per-release)
- GitHub contributor graphs
- Release notes

Thank you for contributing to VirtRigaud.

## Next Steps

- [Build VirtRigaud locally](building-locally.md)
- [Run tests](testing-locally.md)
- [Develop a custom provider](../providers/tutorial.md)
- [Join the community](https://github.com/projectbeskar/virtrigaud)
