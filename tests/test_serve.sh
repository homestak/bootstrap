#!/bin/bash
#
# Automated tests for homestak serve
#
# Usage: ./test_serve.sh [--verbose]
#
# Prerequisites:
#   - site-config with v2/specs/ and v2/postures/
#   - secrets.yaml with auth.site_token (for token tests)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOTSTRAP_DIR="$(dirname "$SCRIPT_DIR")"
PORT=44599  # Use non-default port for testing
SERVER_PID=""
VERBOSE=false
FAILED=0
PASSED=0

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

# Check prerequisites
if ! command -v curl &>/dev/null; then
    log "${RED}curl is required${NC}"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    log "${YELLOW}jq not found, some response validation may be limited${NC}"
fi

# Start the server
start_server

log ""
log "Running tests..."
log ""

# Test 1: Health check
response=$(curl -s "http://127.0.0.1:$PORT/health")
if echo "$response" | grep -q '"status": "ok"'; then
    pass "Health check returns ok"
else
    fail "Health check returns ok" '{"status": "ok"}' "$response"
fi

# Test 2: List specs
response=$(curl -s "http://127.0.0.1:$PORT/specs")
if echo "$response" | grep -q '"specs"'; then
    pass "List specs endpoint works"
    log_verbose "      Specs: $response"
else
    fail "List specs endpoint works" '{"specs": [...]}' "$response"
fi

# Test 3: Fetch spec (network auth - should work without token)
response=$(curl -s "http://127.0.0.1:$PORT/spec/base")
if echo "$response" | grep -q '"schema_version"'; then
    pass "Fetch spec/base returns spec"
    log_verbose "      Response: $(echo "$response" | head -c 200)..."
elif echo "$response" | grep -q '"error"'; then
    # Might fail if spec doesn't exist - check error code
    if echo "$response" | grep -q '"E200"'; then
        log "${YELLOW}SKIP${NC}: spec/base not found (E200) - create v2/specs/base.yaml"
    else
        fail "Fetch spec/base returns spec" "schema_version in response" "$response"
    fi
else
    fail "Fetch spec/base returns spec" "schema_version in response" "$response"
fi

# Test 4: Fetch non-existent spec
response=$(curl -s "http://127.0.0.1:$PORT/spec/nonexistent-spec-12345")
if echo "$response" | grep -q '"E200"'; then
    pass "Non-existent spec returns E200"
else
    fail "Non-existent spec returns E200" 'E200 error' "$response"
fi

# Test 5: Unknown endpoint
response=$(curl -s "http://127.0.0.1:$PORT/unknown")
if echo "$response" | grep -q '"E100"'; then
    pass "Unknown endpoint returns E100"
else
    fail "Unknown endpoint returns E100" 'E100 error' "$response"
fi

# Test 6: Missing identity
response=$(curl -s "http://127.0.0.1:$PORT/spec/")
if echo "$response" | grep -q '"E101"'; then
    pass "Missing identity returns E101"
else
    fail "Missing identity returns E101" 'E101 error' "$response"
fi

# Test 7: HTTP status codes
status=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/health")
if [[ "$status" == "200" ]]; then
    pass "Health check returns HTTP 200"
else
    fail "Health check returns HTTP 200" "200" "$status"
fi

status=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/spec/nonexistent-spec-12345")
if [[ "$status" == "404" ]]; then
    pass "Not found returns HTTP 404"
else
    fail "Not found returns HTTP 404" "404" "$status"
fi

status=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/unknown")
if [[ "$status" == "400" ]]; then
    pass "Bad request returns HTTP 400"
else
    fail "Bad request returns HTTP 400" "400" "$status"
fi

# Test 8: SIGHUP clears cache (if server still running)
if kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -HUP "$SERVER_PID"
    sleep 0.5
    response=$(curl -s "http://127.0.0.1:$PORT/health")
    if echo "$response" | grep -q '"status": "ok"'; then
        pass "Server survives SIGHUP"
    else
        fail "Server survives SIGHUP" "server responds after HUP" "no response"
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
