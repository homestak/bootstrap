# bootstrap Makefile

.PHONY: help install-deps lint

help:
	@echo "bootstrap - homestak CLI and installer"
	@echo ""
	@echo "Targets:"
	@echo "  make install-deps  - Install shellcheck for linting"
	@echo "  make lint          - Run shellcheck on shell scripts"

install-deps:
	@echo "Installing shellcheck..."
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "shellcheck not found. Install with: apt install shellcheck"; \
		exit 1; \
	fi
	@echo "shellcheck installed: $$(shellcheck --version | head -2 | tail -1)"

lint:
	@echo "Running shellcheck..."
	@shellcheck install.sh homestak
	@echo "Lint passed"
