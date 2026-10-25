<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

# Contributing to the VirtRigaud documentation

This repository holds the source of the VirtRigaud documentation site. The
operator code lives in [projectbeskar/virtrigaud](https://github.com/projectbeskar/virtrigaud).

- **Contributing to the operator or the docs content**: read the
  [Contributing guide](src/development/contributing.md) (published on the site
  under *Development*). It covers the workflow, the DCO sign-off (`git commit -s`)
  and the pull request checklist.
- **Building this site locally**: see [BUILD.md](BUILD.md) and the
  [Building Locally](src/development/building-locally.md) page. In short:

  ```bash
  make install
  make install-crd-tools install-proto-tools
  make build-strict   # same check as CI: fails on any mkdocs warning
  ```

- **Which release the site documents**: the tag in
  [VIRTRIGAUD_VERSION](VIRTRIGAUD_VERSION). The pages under `src/` describe that
  release only; do not document behaviour that is not in it. The two generated
  pages, `src/references/generated-crd-docs.md` and `src/references/grpc-api.md`,
  are committed; regenerate them with `make generate-crds generate-proto-docs`
  rather than editing them.

Report documentation errors as issues on this repository. Report bugs in the
operator itself in the [main repository](https://github.com/projectbeskar/virtrigaud/issues).
