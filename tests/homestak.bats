#!/usr/bin/env bats
#
# Unit tests for homestak CLI
#
# Run with: bats tests/homestak.bats
# Or: make test
#

# Setup - create temporary test directories
setup() {
    export TEST_DIR="$(mktemp -d)"
    export HOMESTAK_ROOT="$TEST_DIR"
    mkdir -p "$TEST_DIR/iac" "$TEST_DIR/config" "$TEST_DIR/bootstrap"

    # Path to the script under test
    export HOMESTAK_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/homestak"
}

# Teardown - clean up test directories
teardown() {
    rm -rf "$TEST_DIR"
}

# Helper: source homestak functions (without running main)
load_functions() {
    # Create a modified version that doesn't run main
    local tmpscript="$TEST_DIR/homestak_test.sh"
    sed '/^# Main$/,/^esac$/d' "$HOMESTAK_SH" > "$tmpscript"
    # Also remove the final check
    sed -i '/^\[\[ \$# -lt 1 \]\]/d' "$tmpscript"
    source "$tmpscript"
}

#
# Basic CLI tests
#

@test "homestak exists and is executable" {
    [ -f "$HOMESTAK_SH" ]
    [ -x "$HOMESTAK_SH" ]
}

@test "homestak --help shows usage" {
    run "$HOMESTAK_SH" --help
    [ "$status" -eq 1 ]  # usage exits with 1
    [[ "$output" =~ "homestak" ]]
    [[ "$output" =~ "Usage:" ]]
}

@test "homestak help shows usage" {
    run "$HOMESTAK_SH" help
    [ "$status" -eq 1 ]
    [[ "$output" =~ "homestak" ]]
}

@test "homestak with no args shows usage" {
    run "$HOMESTAK_SH"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "homestak unknown command fails" {
    run "$HOMESTAK_SH" foobar
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown command: foobar" ]]
}

#
# Path detection tests
#

@test "path defaults use HOMESTAK_ROOT" {
    run grep 'HOMESTAK_ROOT=.*HOME' "$HOMESTAK_SH"
    [[ "$output" =~ 'HOMESTAK_ROOT' ]]

    run grep 'CONFIG_DIR=.*HOMESTAK_ROOT' "$HOMESTAK_SH"
    [[ "$output" =~ 'config' ]]
}

@test "as_root function is defined" {
    run grep "^as_root()" "$HOMESTAK_SH"
    [ "$status" -eq 0 ]
}

#
# Command routing tests
#

@test "status command is recognized" {
    # Create minimal repo structure for status to work
    mkdir -p "$HOMESTAK_ROOT/bootstrap/.git"
    mkdir -p "$HOMESTAK_ROOT/config/.git"

    # Run with modified paths (won't work without git repos but tests routing)
    run bash -c "HOMESTAK_ROOT='$HOMESTAK_ROOT' source '$HOMESTAK_SH' 2>/dev/null; show_status"
    # Should output something about status even if repos not found
    [[ "$output" =~ "Homestak Status" ]] || [[ "$output" =~ "status" ]]
}

@test "scenario shortcuts are recognized" {
    # These should fail looking for iac-driver, not "unknown command"
    for cmd in pve-setup pve-install user; do
        run "$HOMESTAK_SH" "$cmd" 2>&1
        [[ ! "$output" =~ "Unknown command" ]]
    done
}

#
# Images subcommand tests
#

@test "images requires subcommand" {
    run "$HOMESTAK_SH" images
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage: homestak images" ]]
}

@test "images unknown subcommand fails" {
    run "$HOMESTAK_SH" images foobar
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown images subcommand" ]]
}

#
# Secrets subcommand tests
#

@test "secrets requires action" {
    run "$HOMESTAK_SH" secrets
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage: homestak secrets" ]]
}

@test "secrets unknown action fails" {
    run "$HOMESTAK_SH" secrets foobar 2>&1
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown action" ]] || [[ "$output" =~ "not found" ]]
}

#
# Install subcommand tests
#

@test "install requires module" {
    run "$HOMESTAK_SH" install
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage: homestak install" ]]
}

@test "install unknown module fails" {
    run "$HOMESTAK_SH" install foobar 2>&1
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown module" ]]
    [[ "$output" =~ "Available modules: packer" ]]
}

#
# Update subcommand tests
#

@test "update unknown option fails" {
    run "$HOMESTAK_SH" update --badoption
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option" ]]
}

@test "update --version requires argument" {
    run "$HOMESTAK_SH" update --version
    [ "$status" -ne 0 ]
}

@test "update --branch requires argument" {
    run "$HOMESTAK_SH" update --branch
    [ "$status" -ne 0 ]
}

@test "update --branch and --version are mutually exclusive" {
    run "$HOMESTAK_SH" update --version v0.30 --branch sprint/foo
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Cannot use --version and --branch together" ]]
}

#
# site-init tests
#

@test "site-init without site-config directory fails" {
    # Remove the config dir so site-config check triggers
    rmdir "$HOMESTAK_ROOT/config"
    run "$HOMESTAK_SH" site-init
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not found" ]]
}

#
# Scenario routing tests
#

@test "scenario requires name" {
    run "$HOMESTAK_SH" scenario
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage: homestak scenario" ]]
}

#
# spec subcommand tests
#

@test "spec requires subcommand" {
    run "$HOMESTAK_SH" spec
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage: homestak spec" ]]
}

@test "spec unknown subcommand fails" {
    run "$HOMESTAK_SH" spec foobar
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown spec subcommand" ]]
}

@test "spec validate shows migration hint" {
    run "$HOMESTAK_SH" spec validate
    [ "$status" -eq 1 ]
    [[ "$output" =~ "moved to site-config" ]]
}

@test "spec validate with args still shows migration hint" {
    run "$HOMESTAK_SH" spec validate /some/file.yaml
    [ "$status" -eq 1 ]
    [[ "$output" =~ "moved to site-config" ]]
}

#
# spec get tests
#

@test "spec get requires --server or HOMESTAK_SERVER" {
    run "$HOMESTAK_SH" spec get --identity test
    [ "$status" -eq 1 ]
    [[ "$output" =~ "server" ]] || [[ "$output" =~ "HOMESTAK_SERVER" ]]
}

@test "spec get with server arg attempts fetch" {
    # Identity defaults to hostname, so only --server is required.
    # Should fail with connection error (no server), not argument error.
    run "$HOMESTAK_SH" spec get --server http://localhost:65432 --identity test 2>&1
    [ "$status" -eq 2 ]  # Server error exit code
    [[ "$output" =~ "E501" ]] || [[ "$output" =~ "Cannot connect" ]] || [[ "$output" =~ "Error" ]]
}
