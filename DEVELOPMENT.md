<!--
Copyright (c) 2026 VirtRigaud Creators
SPDX-License-Identifier: Apache-2.0
-->

## Development Note

This project requires Go 1.23+ but your system has Go 1.22.2.

**Solutions:**
1. **Recommended**: Use Docker-based commands:
   - `make build` instead of `go build`
   - `make dev-deploy` for development
   - `make lint` for linting

2. **Install Go 1.23+** system-wide

3. **Current workaround**: The project builds successfully with Docker.
   Direct `go mod tidy` will fail, but all functionality works.

**Status**: ✅ All VirtRigaud functionality is working correctly!

