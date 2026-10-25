#!/usr/bin/env bash
# Copyright (c) 2026 VirtRigaud Creators
# SPDX-License-Identifier: Apache-2.0
#
# Generate the gRPC API reference page from provider.proto.
#
# Usage: tools/gen-proto-docs.sh [VIRTRIGAUD_DIR]
#   VIRTRIGAUD_DIR  checkout of projectbeskar/virtrigaud (default: ./virtrigaud)
#
# Writes src/references/grpc-api.md. The page is purely generated: the
# hand-written explanation lives in src/references/grpc-api-guide.md, which
# this script never touches. Requires buf and protoc-gen-doc on PATH.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$(cd "${1:-${VIRTRIGAUD_DIR:-$ROOT/virtrigaud}}" && pwd)"

# -o makes the template's relative `out` resolve under src/references, so the
# VirtRigaud checkout is only read, never written.
(cd "$SRC" && buf generate proto \
  --template "$ROOT/tools/buf.gen.docs.yaml" \
  -o "$ROOT/src/references")
echo "Proto documentation generated at src/references/grpc-api.md"
