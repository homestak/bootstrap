#!/usr/bin/env bash
#
# Integration test: bootstrap install on a remote target.
#
# Replicates iac-driver's bootstrap-install scenario as a standalone
# shell script. Runs 3 phases via SSH:
#   1. Install - curl|bash install.sh with optional env vars
#   2. Verify modules - homestak status shows ansible/iac-driver/tofu
#   3. Verify homestak user - check user exists with NOPASSWD sudo
#
# Usage:
#   ./tests/test-install-remote.sh --target <ip> [--user root] \
#       [--branch <name>]
#
# Exit codes: 0=pass, 1=fail, 2=usage error
#

set -euo pipefail

BOOTSTRAP_URL="https://raw.githubusercontent.com/homestak/bootstrap/master/install"

# Defaults
TARGET=""
SSH_USER="root"
BRANCH=""
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

usage() {
    echo "Usage: $0 --target <ip> [options]"
    echo ""
    echo "Options:"
    echo "  --target <ip>           Target host IP (required)"
    echo "  --user <name>           SSH user (default: root)"
    echo "  --branch <name>         HOMESTAK_BRANCH for install.sh"
    echo "  --help                  Show this help"
    exit 2
}

log_phase() {
    echo -e "${GREEN}==>${NC} Phase: $1"
}

log_ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

log_fail() {
    echo -e "  ${RED}✗${NC} $1"
}

run_ssh() {
    # shellcheck disable=SC2086
    ssh $SSH_OPTS "${SSH_USER}@${TARGET}" "$@"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --user) SSH_USER="$2"; shift 2 ;;
        --branch) BRANCH="$2"; shift 2 ;;
        --help|-h) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [[ -z "$TARGET" ]]; then
    echo "Error: --target is required"
    usage
fi

FAILED=0

# Phase 1: Install
log_phase "Install bootstrap on $TARGET"

env_vars=""
if [[ -n "$BRANCH" ]]; then
    env_vars="HOMESTAK_BRANCH=$BRANCH "
fi

install_cmd="curl -fsSL $BOOTSTRAP_URL | ${env_vars}bash"
if run_ssh "$install_cmd"; then
    log_ok "Bootstrap completed"
else
    log_fail "Bootstrap failed"
    exit 1
fi

# Phase 2: Verify modules
log_phase "Verify installation"

status_output=$(run_ssh "homestak status" 2>&1) || {
    log_fail "homestak status failed"
    exit 1
}

required_modules=("ansible" "iac-driver" "tofu")
for module in "${required_modules[@]}"; do
    if echo "$status_output" | grep -q "$module" && \
       ! echo "$status_output" | grep "$module" | grep -q "(not installed)"; then
        log_ok "$module installed"
    else
        log_fail "$module missing or not installed"
        FAILED=1
    fi
done

# Phase 3: Verify homestak user
log_phase "Verify homestak user"

if run_ssh "id homestak" >/dev/null 2>&1; then
    log_ok "User exists"
else
    log_fail "User 'homestak' not found"
    FAILED=1
fi

if run_ssh "grep -r homestak /etc/sudoers.d/ 2>/dev/null | grep -q NOPASSWD"; then
    log_ok "NOPASSWD sudo configured"
else
    log_fail "User 'homestak' does not have passwordless sudo"
    FAILED=1
fi

# Summary
echo ""
if [[ "$FAILED" -eq 0 ]]; then
    echo -e "${GREEN}PASSED${NC} - All checks passed"
    exit 0
else
    echo -e "${RED}FAILED${NC} - One or more checks failed"
    exit 1
fi
