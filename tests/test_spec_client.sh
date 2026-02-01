#!/bin/bash
#
# Automated tests for homestak spec get
#
# Usage: ./test_spec_client.sh [--verbose]
#
# Prerequisites:
#   - site-config with v2/specs/ and v2/postures/
#   - Server will be started automatically for testing
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOTSTRAP_DIR="$(dirname "$SCRIPT_DIR")"
PORT=44598  # Use non-default port for testing
SERVER_PID=""
VERBOSE=false
FAILED=0
PASSED=0
TEST_STATE_DIR=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

cleanup() {
    if [[ -n "$SERVER_PID" ]]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    if [[ -n "$TEST_STATE_DIR" && -d "$TEST_STATE_DIR" ]]; then
        rm -rf "$TEST_STATE_DIR"
    fi
}

trap cleanup EXIT

log() {
    echo -e "$@"
}

log_verbose() {
    if $VERBOSE; then
        echo -e "$@"
    fi
}

pass() {
    log "${GREEN}PASS${NC}: $1"
    ((PASSED++))
}

fail() {
    log "${RED}FAIL${NC}: $1"
    if [[ -n "${2:-}" ]]; then
        log "      Expected: $2"
    fi
    if [[ -n "${3:-}" ]]; then
        log "      Got: $3"
    fi
    ((FAILED++))
}

start_server() {
    log "Starting server on port $PORT..."

    # Set PYTHONPATH and start server in background
    cd "$BOOTSTRAP_DIR"
    PYTHONPATH="$BOOTSTRAP_DIR" python3 -m lib.serve --port "$PORT" --bind 127.0.0.1 &
    SERVER_PID=$!

    # Wait for server to be ready
    local attempts=0
    while ! curl -s "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; do
        sleep 0.2
        ((attempts++))
        if [[ $attempts -gt 25 ]]; then
            log "${RED}Server failed to start${NC}"
            exit 1
        fi
    done
    log "Server started (PID: $SERVER_PID)"
}

run_client() {
    # Run spec client with test state directory
    cd "$BOOTSTRAP_DIR"
    PYTHONPATH="$BOOTSTRAP_DIR" python3 -m lib.spec_client --output "$TEST_STATE_DIR" "$@"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        *)
            log "${RED}Unknown argument: $1${NC}"
            exit 1
            ;;
    esac
done

# Create test state directory
TEST_STATE_DIR=$(mktemp -d)
log "Test state directory: $TEST_STATE_DIR"

# Start the server
start_server

log ""
log "Running spec client tests..."
log ""

# Test 1: Missing server argument
output=$(run_client --identity test 2>&1) && exit_code=0 || exit_code=$?
if [[ $exit_code -eq 1 ]] && echo "$output" | grep -q "server.*required"; then
    pass "Missing server returns exit 1"
else
    fail "Missing server returns exit 1" "exit 1 + error message" "exit $exit_code: $output"
fi

# Test 2: Missing identity argument
output=$(run_client --server "http://127.0.0.1:$PORT" 2>&1) && exit_code=0 || exit_code=$?
if [[ $exit_code -eq 1 ]] && echo "$output" | grep -q "identity.*required"; then
    pass "Missing identity returns exit 1"
else
    fail "Missing identity returns exit 1" "exit 1 + error message" "exit $exit_code: $output"
fi

# Test 3: Fetch existing spec (base - network auth)
output=$(run_client --server "http://127.0.0.1:$PORT" --identity base 2>&1) && exit_code=0 || exit_code=$?
if [[ $exit_code -eq 0 ]] && echo "$output" | grep -q "Spec fetched successfully"; then
    pass "Fetch existing spec succeeds"
    log_verbose "      Output: $output"
elif echo "$output" | grep -q "E200"; then
    log "${YELLOW}SKIP${NC}: spec/base not found (E200) - create v2/specs/base.yaml"
else
    fail "Fetch existing spec succeeds" "exit 0 + success message" "exit $exit_code: $output"
fi

# Test 4: Spec file saved to state directory
if [[ -f "$TEST_STATE_DIR/spec.yaml" ]]; then
    pass "Spec saved to state directory"
    log_verbose "      Contents: $(head -5 "$TEST_STATE_DIR/spec.yaml")"
else
    fail "Spec saved to state directory" "spec.yaml exists" "file not found"
fi

# Test 5: Fetch non-existent spec
output=$(run_client --server "http://127.0.0.1:$PORT" --identity nonexistent-spec-12345 2>&1) && exit_code=0 || exit_code=$?
if [[ $exit_code -eq 2 ]] && echo "$output" | grep -q "E200"; then
    pass "Non-existent spec returns exit 2 with E200"
else
    fail "Non-existent spec returns exit 2 with E200" "exit 2 + E200 error" "exit $exit_code: $output"
fi

# Test 6: Server unreachable
output=$(run_client --server "http://127.0.0.1:65432" --identity test 2>&1) && exit_code=0 || exit_code=$?
if [[ $exit_code -eq 2 ]] && echo "$output" | grep -q "E501"; then
    pass "Unreachable server returns exit 2 with E501"
else
    fail "Unreachable server returns exit 2 with E501" "exit 2 + E501 error" "exit $exit_code: $output"
fi

# Test 7: Environment variables work
export HOMESTAK_DISCOVERY="http://127.0.0.1:$PORT"
export HOMESTAK_IDENTITY="base"
output=$(run_client 2>&1) && exit_code=0 || exit_code=$?
if [[ $exit_code -eq 0 ]] || echo "$output" | grep -q "E200"; then
    pass "Environment variables work"
else
    fail "Environment variables work" "exit 0 or E200" "exit $exit_code: $output"
fi
unset HOMESTAK_DISCOVERY HOMESTAK_IDENTITY

# Test 8: CLI flags override env vars
export HOMESTAK_DISCOVERY="http://wrong-host:12345"
export HOMESTAK_IDENTITY="wrong-identity"
output=$(run_client --server "http://127.0.0.1:$PORT" --identity base 2>&1) && exit_code=0 || exit_code=$?
if [[ $exit_code -eq 0 ]] || echo "$output" | grep -q "E200"; then
    pass "CLI flags override env vars"
else
    fail "CLI flags override env vars" "use CLI values, not env" "exit $exit_code: $output"
fi
unset HOMESTAK_DISCOVERY HOMESTAK_IDENTITY

# Test 9: Previous spec backed up
# First fetch creates spec.yaml, second fetch should backup to spec.yaml.prev
if [[ -f "$TEST_STATE_DIR/spec.yaml" ]]; then
    # Fetch again to trigger backup
    run_client --server "http://127.0.0.1:$PORT" --identity base 2>&1 || true
    if [[ -f "$TEST_STATE_DIR/spec.yaml.prev" ]]; then
        pass "Previous spec backed up to .prev"
    else
        fail "Previous spec backed up to .prev" "spec.yaml.prev exists" "file not found"
    fi
else
    log "${YELLOW}SKIP${NC}: Backup test (no spec.yaml from earlier test)"
fi

# Test 10: Verbose output
output=$(run_client --server "http://127.0.0.1:$PORT" --identity base --verbose 2>&1) && exit_code=0 || exit_code=$?
if echo "$output" | grep -qi "fetching\|debug"; then
    pass "Verbose flag produces extra output"
else
    # Even without debug messages, it should work
    if [[ $exit_code -eq 0 ]] || echo "$output" | grep -q "E200"; then
        pass "Verbose flag works (no extra output visible)"
    else
        fail "Verbose flag works" "command succeeds with --verbose" "exit $exit_code"
    fi
fi

# Summary
log ""
log "========================================"
log "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"
log "========================================"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
