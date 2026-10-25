# Copyright (c) 2026 VirtRigaud Creators
# SPDX-License-Identifier: Apache-2.0

.PHONY: help install install-crd-tools install-proto-tools clone-virtrigaud generate-crds generate-proto-docs build serve clean lint

# Variables
VIRTRIGAUD_REPO ?= https://github.com/projectbeskar/virtrigaud.git
VIRTRIGAUD_DIR ?= virtrigaud
# Release tag of VirtRigaud the reference pages are generated from (pinned in VIRTRIGAUD_VERSION).
VIRTRIGAUD_VERSION ?= $(shell cat VIRTRIGAUD_VERSION)
CRD_OUTPUT := src/references/generated-crd-docs.md
PROTO_OUTPUT := src/references/grpc-api.md
GOPATH ?= $(shell go env GOPATH 2>/dev/null || echo $$HOME/go)
CRD_REF_DOCS := $(GOPATH)/bin/crd-ref-docs
BUF := $(GOPATH)/bin/buf
export PATH := $(GOPATH)/bin:$(PATH)
PORT ?= 8000

# Default target
help:
	@echo "VirtRigaud Documentation - Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  install             - Install dependencies with Poetry"
	@echo "  install-crd-tools   - Install crd-ref-docs tool (requires Go)"
	@echo "  install-proto-tools - Install buf tool (requires Go)"
	@echo "  clone-virtrigaud    - Clone/update VirtRigaud repository at the tag in VIRTRIGAUD_VERSION"
	@echo "  generate-crds       - Generate CRD documentation from VirtRigaud repo"
	@echo "  generate-proto-docs - Generate gRPC/proto API documentation from VirtRigaud repo"
	@echo "  build               - Generate all docs and build the documentation site"
	@echo "  build-strict        - Build in strict mode (for CI/CD)"
	@echo "  serve               - Serve the documentation locally with live reload"
	@echo "  clean               - Remove generated files"
	@echo "  lint                - Run linting checks"

# Install dependencies
install:
	@echo "Installing dependencies with Poetry..."
	poetry install

# Install crd-ref-docs tool (requires Go)
install-crd-tools:
	@echo "Checking for Go..."
	@which go > /dev/null || (echo "Error: Go is not installed. Please install Go first." && exit 1)
	@echo "Installing crd-ref-docs to $(GOPATH)/bin..."
	@go install github.com/elastic/crd-ref-docs@latest
	@if [ -f "$(CRD_REF_DOCS)" ]; then \
		echo "crd-ref-docs installed successfully at $(CRD_REF_DOCS)"; \
	else \
		echo "Error: Installation failed"; \
		exit 1; \
	fi
	@echo ""
	@echo "Note: Make sure $(GOPATH)/bin is in your PATH"
	@echo "Add this to your ~/.bashrc, ~/.zshrc, or equivalent:"
	@echo '  export PATH="$$PATH:$(GOPATH)/bin"'

# Clone or update VirtRigaud repository
clone-virtrigaud:
	@if [ -d "$(VIRTRIGAUD_DIR)/.git" ]; then \
		echo "Updating VirtRigaud repository to $(VIRTRIGAUD_VERSION)..."; \
		cd $(VIRTRIGAUD_DIR) && git fetch --tags --force origin && git checkout --detach $(VIRTRIGAUD_VERSION); \
	else \
		echo "Cloning VirtRigaud repository at $(VIRTRIGAUD_VERSION)..."; \
		git clone $(VIRTRIGAUD_REPO) $(VIRTRIGAUD_DIR) && cd $(VIRTRIGAUD_DIR) && git checkout --detach $(VIRTRIGAUD_VERSION); \
	fi

# Install buf tool (requires Go)
install-proto-tools:
	@echo "Checking for Go..."
	@which go > /dev/null || (echo "Error: Go is not installed. Please install Go first." && exit 1)
	@echo "Installing buf to $(GOPATH)/bin..."
	@go install github.com/bufbuild/buf/cmd/buf@latest
	@if [ -f "$(BUF)" ]; then \
		echo "buf installed successfully at $(BUF)"; \
	else \
		echo "Error: Installation failed"; \
		exit 1; \
	fi

# Generate CRD documentation
generate-crds: install-crd-tools clone-virtrigaud
	@echo "Generating CRD documentation..."
	@./tools/gen-crd-docs.sh $(VIRTRIGAUD_DIR)

# Generate proto/gRPC API documentation
generate-proto-docs: install-proto-tools clone-virtrigaud
	@echo "Generating proto/gRPC API documentation..."
	@./tools/gen-proto-docs.sh $(VIRTRIGAUD_DIR)

# Build the site
build: install generate-crds generate-proto-docs
	@echo "Building documentation site..."
	poetry run mkdocs build

# Serve locally with live reload
serve: build
	@echo "Starting local server with live reload..."
	@echo "Documentation will be available at http://127.0.0.1:$(PORT)"
	poetry run mkdocs serve --dev-addr 127.0.0.1:$(PORT)

# Clean generated files
clean:
	@echo "Cleaning generated files..."
	rm -rf site/
	rm -rf .cache/
	rm -rf $(VIRTRIGAUD_DIR)/
	# $(CRD_OUTPUT) and $(PROTO_OUTPUT) are committed; regenerate them with 'make generate-crds generate-proto-docs'.
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true

# Build the site in strict mode (for CI/CD)
build-strict: install generate-crds generate-proto-docs
	@echo "Building documentation site in strict mode..."
	poetry run mkdocs build --strict

# Lint documentation (check for broken links and formatting)
lint:
	@echo "Linting documentation..."
	poetry run mkdocs build --verbose
	@echo "Lint check complete!"
