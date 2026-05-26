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
  the toolchain floor from 1.24.0 → 1.26.0). The repo's `go.mod` is the source
  of truth; CI uses `go-version-file: go.mod` so locally you should match.
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

# Regenerate CRDs under config/crd/bases/
make gen-crds          # alias: make manifests

# Regenerate CRDs directly into the Helm chart (charts/virtrigaud/crds/)
make gen-helm-crds

# Sanity check: the chart must lint with the freshly generated CRDs
make helm-lint
```

The Go types under `api/infra.virtrigaud.io/v1beta1/*_types.go` are the
**single source of truth**. Never hand-edit `config/crd/bases/`,
`charts/virtrigaud/crds/`, or `zz_generated.deepcopy.go` — regenerate them
instead. v1beta1 is the stable API; breaking changes require an ADR.

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

Keep CRDs synchronized between `config/crd/bases/` and
`charts/virtrigaud/crds/`. Both are regenerated from
`api/infra.virtrigaud.io/v1beta1/*_types.go` — the Go types are the single
source of truth.

```bash
# After API changes, regenerate both locations
make gen-crds          # writes config/crd/bases/
make gen-helm-crds     # writes charts/virtrigaud/crds/

# Lint the chart with the regenerated CRDs (this is what CI also runs)
make helm-lint
```

CI's **Validate Helm Charts** job re-runs `helm lint` / `helm template`
against the chart, so if you forget to regenerate, the build fails there.

### 3. Testing

```bash
# Unit tests (default `go test ./...`)
make test

# Integration tests (cross-package observability tests; no cluster required)
make test-integration

# End-to-end tests (requires kind cluster; gated behind //go:build e2e
# since v0.3.6 / #133 so default `go test ./...` no longer fails on TestE2E).
# NOTE: `make test-e2e` itself does NOT yet pass `-tags=e2e` (see #133
# follow-up), so until that lands run the explicit form below.
go test -tags=e2e ./test/e2e/... -v -ginkgo.v
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
`user.name` / `user.email` git config. Without the trailer, the PR will fail
the DCO check and cannot be merged.

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

Versioned release headers (`## [0.3.6] - 2026-05-25`) sit at the top and
aggregate the per-PR entries that preceded them. Don't reorganise existing
release sections.

## CI on pull requests

Every PR triggers the CI workflow (`.github/workflows/ci.yml`), which runs the
following jobs:

| Job                       | What it checks                                                                 |
|---------------------------|--------------------------------------------------------------------------------|
| **Test**                  | `make test` excluding libvirt + e2e packages; uploads coverage to Codecov.    |
| **Lint**                  | `golangci-lint` v2.12.2 with a 10-minute timeout.                              |
| **Security Scan**         | `gosec` (SARIF upload) + Trivy in repo mode (SARIF upload).                    |
| **Verify Generated Files**| Regenerates CRDs + checks for drift; fails if `make gen-crds` / `make gen-helm-crds` would diff. |
| **Build**                 | Compiles manager + all 4 providers + supporting binaries.                      |
| **Build Tools**           | Compiles `vrtg`, `vrtg-provider`, `vcts`, `virtrigaud-loadgen`.                |
| **Build Container Images**| Builds (no push) the manager + provider images from `build/Dockerfile.*`.      |
| **Validate Helm Charts**  | `helm lint` + `helm template` + `chart-testing` against the chart.             |
| **Conformance Tests**     | Runs `vcts` against the mock provider.                                         |
| **Integration Tests**     | `make test-integration` (cross-package observability tests).                   |
| **Catalog Validation**    | Validates `examples/` YAMLs against the live CRD schemas.                      |
| **API Conversion Tests**  | Exercises round-trip conversion between API versions.                          |
| **CI Summary**            | Aggregates the above; the PR is mergeable only if everything green.            |

CI uses `go-version-file: go.mod` for the Go version (currently 1.26.x).

### Lint: CI vs local

The Lint job runs **golangci-lint v2.12.2** (installed by
`golangci/golangci-lint-action@v9`). The version pinned in the project
Makefile is older — there's a known drift here. If your `make lint` passes
locally but CI Lint fails, that's why. **Treat CI Lint as the source of
truth** until the versions are reconciled.

### Branch protection on `main`

The `main` branch has a ruleset enforcing:

- 1 approving review required
- Linear history (no merge commits via the UI)
- No force-push
- No deletion

Required status checks are **not** currently enforced at the ruleset level
(they're observable via the **CI Summary** job, which authors and reviewers
are expected to check before merge).

## Contribution Guidelines

### Pull Request Process

1. **Fork and branch**: Create a feature branch from `main`.
2. **Make changes**: Follow the development workflow above.
3. **Test thoroughly**: `make fmt lint test build` locally before pushing.
4. **Sign off**: Every commit needs `-s` (DCO).
5. **CHANGELOG**: Add an entry for any code-affecting change.
6. **CRD sync**: If you touched `api/`, run `make generate gen-crds
   gen-helm-crds` and commit the regen output. CI's **Verify Generated
   Files** job will fail otherwise.
7. **Submit PR**: Clear description, linked issue, mention which CI jobs you
   expect to be affected.

### PR Requirements

- [ ] All CI checks pass (see table above)
- [ ] CRDs are in sync (Verify Generated Files green)
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
# Requires a kind cluster + the manager image loaded.
# Since #133 the e2e suite is gated behind //go:build e2e; `make test-e2e`
# does not yet pass `-tags=e2e` so use the explicit `go test` form below:
go test -tags=e2e ./test/e2e/... -v -ginkgo.v
```

### Provider Conformance Tests

VCTS (VirtRigaud Conformance Test Suite) lives at `cmd/vcts/`. To run it
against the mock provider:

```bash
# Build the suite + the mock provider
make build-provider-mock
go build -o bin/vcts ./cmd/vcts

# Start the mock provider, then point vcts at it
./bin/provider-mock &
./bin/vcts run --endpoint=localhost:9090
```

CI runs an equivalent flow in the **Conformance Tests** job using the mock
provider built from the same source tree.

## Release Process

### For Maintainers

1. **Prepare release**:
   ```bash
   # Regenerate deepcopy methods and both CRD locations
   make generate
   make gen-crds
   make gen-helm-crds

   # Update version in charts
   vim charts/virtrigaud/Chart.yaml

   # Update CHANGELOG.md with a versioned header
   vim CHANGELOG.md
   ```

2. **Cut an RC, smoke, then promote**:
   ```bash
   git tag v0.3.7-rc1
   git push origin v0.3.7-rc1
   # ...deploy to lab, run smoke recipe, then:
   git tag v0.3.7
   git push origin v0.3.7
   ```

3. **CI handles**:
   - Building and pushing multi-arch images
   - Running Trivy on the manager image (release blocker if HIGH/CRITICAL CVE)
   - Creating GitHub release
   - Publishing Helm charts
   - Generating CLI binaries

The project follows an **`rc1 → smoke → final`** pattern; v0.3.5 and v0.3.6
each shipped on a single RC. A failing Trivy scan on the manager image is a
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

If you see "Helm chart CRDs are out of sync" in CI:

```bash
make update-crds
git add config/crd/bases/ charts/virtrigaud/crds/ api/
git commit -s -m "chore: regen CRDs"
```

### Test Failures

```bash
# Clean and retry
make clean
make test

# For libvirt-related failures locally
export SKIP_LIBVIRT_TESTS=true
make test
```

### Development Environment

```bash
# Reset the local Kind deployment
make dev-cleanup
make dev-deploy

# Check logs
kubectl logs -n virtrigaud-system deployment/virtrigaud-manager
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
