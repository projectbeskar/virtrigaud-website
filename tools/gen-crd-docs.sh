#!/usr/bin/env bash
# Copyright (c) 2026 VirtRigaud Creators
# SPDX-License-Identifier: Apache-2.0
#
# Generate the full CRD reference page from the VirtRigaud API types.
#
# Usage: tools/gen-crd-docs.sh [VIRTRIGAUD_DIR]
#   VIRTRIGAUD_DIR  checkout of projectbeskar/virtrigaud (default: ./virtrigaud)
#
# Writes src/references/generated-crd-docs.md (the page mkdocs.yml links to)
# and prepends the licence header. Requires crd-ref-docs on PATH.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$(cd "${1:-${VIRTRIGAUD_DIR:-$ROOT/virtrigaud}}" && pwd)"
OUT="$ROOT/src/references/generated-crd-docs.md"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

(cd "$SRC" && crd-ref-docs \
  --source-path=api \
  --config="$ROOT/tools/crd-ref-docs-config.yaml" \
  --renderer=markdown \
  --output-path="$TMP")

{
  printf '<!--\nCopyright (c) 2026 VirtRigaud Creators\nSPDX-License-Identifier: Apache-2.0\n-->\n\n'
  cat "$TMP"
} > "$OUT"
echo "CRD documentation generated at src/references/generated-crd-docs.md"
