# Copyright (c) 2026 VirtRigaud Creators
# SPDX-License-Identifier: Apache-2.0

.PHONY: help install install-crd-tools clone-virtrigaud generate-crds build serve clean lint

# Variables
VIRTRIGAUD_REPO ?= https://github.com/projectbeskar/virtrigaud.git
VIRTRIGAUD_DIR := virtrigaud
CRD_OUTPUT := src/generated-crd-docs.md
GOPATH ?= $(shell go env GOPATH 2>/dev/null || echo $$HOME/go)
CRD_REF_DOCS := $(GOPATH)/bin/crd-ref-docs

# Default target
help:
	@echo "VirtRigaud Documentation - Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  install           - Install dependencies with Poetry"
	@echo "  install-crd-tools - Install crd-ref-docs tool (requires Go)"
	@echo "  clone-virtrigaud  - Clone/update VirtRigaud repository"
	@echo "  generate-crds     - Generate CRD documentation from VirtRigaud repo"
	@echo "  build             - Generate CRDs and build the documentation site"
	@echo "  build-strict      - Build in strict mode (for CI/CD)"
	@echo "  serve             - Serve the documentation locally with live reload"
	@echo "  clean             - Remove generated files"
	@echo "  lint              - Run linting checks"

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
	@if [ -d "$(VIRTRIGAUD_DIR)" ]; then \
		echo "Updating VirtRigaud repository..."; \
		cd $(VIRTRIGAUD_DIR) && git pull; \
	else \
		echo "Cloning VirtRigaud repository..."; \
		git clone $(VIRTRIGAUD_REPO) $(VIRTRIGAUD_DIR); \
	fi

# Generate CRD documentation
generate-crds: install-crd-tools clone-virtrigaud
	@echo "Generating CRD documentation..."
	@if [ ! -f "$(CRD_REF_DOCS)" ]; then \
		echo "Error: crd-ref-docs not found at $(CRD_REF_DOCS)"; \
		echo "Please run 'make install-crd-tools' first"; \
		exit 1; \
	fi
	@cd $(VIRTRIGAUD_DIR) && \
		$(CRD_REF_DOCS) \
			--source-path=api \
			--config=../crd-ref-docs-config.yaml \
			--renderer=markdown \
			--output-path=../$(CRD_OUTPUT)
	@echo "CRD documentation generated at $(CRD_OUTPUT)"

# Build the site
build: install generate-crds
	@echo "Building documentation site..."
	poetry run mkdocs build

# Serve locally with live reload
serve: build
	@echo "Starting local server with live reload..."
	@echo "Documentation will be available at http://127.0.0.1:8000"
	poetry run mkdocs serve

# Clean generated files
clean:
	@echo "Cleaning generated files..."
	rm -rf site/
	rm -rf .cache/
	rm -rf $(VIRTRIGAUD_DIR)/
	rm -f $(CRD_OUTPUT)
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true

# Build the site in strict mode (for CI/CD)
build-strict: install generate-crds
	@echo "Building documentation site in strict mode..."
	poetry run mkdocs build --strict

# Lint documentation (check for broken links and formatting)
lint:
	@echo "Linting documentation..."
	poetry run mkdocs build --verbose
	@echo "Lint check complete!"
