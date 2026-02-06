#!/usr/bin/env bats
#
# Unit tests for homestak.sh CLI
#
# Run with: bats tests/homestak.bats
# Or: make test
#

# Setup - create temporary test directories
setup() {
    export TEST_DIR="$(mktemp -d)"
    export HOMESTAK_LIB="$TEST_DIR/lib"
    export HOMESTAK_ETC="$TEST_DIR/etc"
    mkdir -p "$HOMESTAK_LIB" "$HOMESTAK_ETC"

    # Path to the script under test
    export HOMESTAK_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/homestak.sh"
}

# Teardown - clean up test directories
teardown() {
    rm -rf "$TEST_DIR"
}

# Helper: source homestak.sh functions (without running main)
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

@test "homestak.sh exists and is executable" {
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

@test "FHS paths are defined correctly" {
    run grep "HOMESTAK_LIB=" "$HOMESTAK_SH"
    [[ "$output" =~ '/usr/local/lib/homestak' ]]

    run grep "HOMESTAK_ETC=" "$HOMESTAK_SH"
    [[ "$output" =~ '/usr/local/etc/homestak' ]]
}

#
# Command routing tests
#

@test "status command is recognized" {
    # Create minimal repo structure for status to work
    mkdir -p "$HOMESTAK_LIB/bootstrap/.git"
    mkdir -p "$HOMESTAK_ETC/.git"

    # Run with modified paths (won't work without git repos but tests routing)
    run bash -c "HOMESTAK_LIB='$HOMESTAK_LIB' HOMESTAK_ETC='$HOMESTAK_ETC' source '$HOMESTAK_SH' 2>/dev/null; show_status"
    # Should output something about status even if repos not found
    [[ "$output" =~ "Homestak Status" ]] || [[ "$output" =~ "status" ]]
}

@test "playbook shortcuts are recognized" {
    # These should fail with "not found" but prove routing works
    for cmd in pve-setup pve-install user network; do
        run "$HOMESTAK_SH" "$cmd" 2>&1
        # Should fail looking for playbook, not "unknown command"
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

#
# site-init tests
#

@test "site-init unknown option fails" {
    run "$HOMESTAK_SH" site-init --badoption
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option" ]]
}

#
# Playbook/scenario routing tests
#

@test "playbook requires name" {
    run "$HOMESTAK_SH" playbook
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage: homestak playbook" ]]
}

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

@test "spec get requires --server or HOMESTAK_DISCOVERY" {
    run "$HOMESTAK_SH" spec get --identity test
    [ "$status" -eq 1 ]
    [[ "$output" =~ "server" ]] || [[ "$output" =~ "HOMESTAK_DISCOVERY" ]]
}

@test "spec get requires --identity or HOMESTAK_IDENTITY" {
    run "$HOMESTAK_SH" spec get --server http://localhost:44443
    [ "$status" -eq 1 ]
    [[ "$output" =~ "identity" ]] || [[ "$output" =~ "HOMESTAK_IDENTITY" ]]
}

@test "spec get with both args attempts fetch" {
    # Should fail with connection error (no server), not argument error
    run "$HOMESTAK_SH" spec get --server http://localhost:65432 --identity test 2>&1
    [ "$status" -eq 2 ]  # Server error exit code
    [[ "$output" =~ "E501" ]] || [[ "$output" =~ "Cannot connect" ]] || [[ "$output" =~ "Error" ]]
}
