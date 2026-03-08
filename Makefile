# bootstrap Makefile

.PHONY: help install-deps lint test

help:
	@echo "bootstrap - homestak CLI and installer"
	@echo ""
	@echo "Targets:"
	@echo "  make install-deps  - Install shellcheck, bats, and gh for testing"
	@echo "  make lint          - Run shellcheck on shell scripts"
	@echo "  make test          - Run bats unit tests"

install-deps:
	@echo "Installing dependencies..."
	@for pkg in shellcheck bats gh; do \
		if ! command -v $$pkg >/dev/null 2>&1; then \
			echo "Installing $$pkg..."; \
			apt-get install -y $$pkg >/dev/null 2>&1 || echo "Warning: could not install $$pkg"; \
		fi; \
	done
	@echo "Dependencies installed"

lint:
	@echo "Running shellcheck..."
	@shellcheck install homestak
	@echo "Lint passed"

test:
	@echo "Running bats tests..."
	@bats tests/
	@echo "Tests passed"
