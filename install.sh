#!/bin/bash
#
# Homestak Bootstrap
# Installs the homestak IAC tooling for local execution
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/homestak-dev/bootstrap/master/install.sh | bash
#
# Options:
#   --source URL       Installation source (github, http://..., file://...)
#   --ref REF          Git ref to checkout (branch, tag, or _working)
#   --help             Show help message
#   --version          Show version
#
# Environment Variables:
#   HOMESTAK_SOURCE    Installation source (overridden by --source)
#   HOMESTAK_REF       Git ref (overridden by --ref)
#   HOMESTAK_TOKEN     Auth token for HTTP sources (required)
#   HOMESTAK_USER      Create a sudo user during bootstrap
#   HOMESTAK_APPLY     Run a task after bootstrap (e.g., pve-setup)
#
# Examples:
#   # Basic bootstrap from GitHub
#   curl -fsSL .../install.sh | bash
#
#   # Pin to specific version
#   curl -fsSL .../install.sh | HOMESTAK_REF=v0.37 bash
#
#   # Bootstrap from HTTP server (dev workflow)
#   HOMESTAK_SOURCE=http://192.0.2.1:54321 \
#   HOMESTAK_TOKEN=a7Bx9kLmN2pQ4rSt \
#   HOMESTAK_REF=_working \
#   ./install.sh
#
set -euo pipefail

VERSION="0.37"

# Show help
show_help() {
    cat << 'EOF'
Homestak Bootstrap - Install homestak IAC tooling

Usage:
  curl -fsSL https://raw.githubusercontent.com/homestak-dev/bootstrap/master/install.sh | bash

  Or run directly:
  ./install.sh [options]

Options:
  --source URL       Installation source (default: github)
                     - github or https://github.com/... (GitHub)
                     - http://host:port (HTTP server - requires --ref and HOMESTAK_TOKEN)
                     - file:///path (local filesystem)
  --ref REF          Git ref to checkout (default: master for github/file)
                     - master, main (branches)
                     - v0.37 (tags)
                     - _working (working tree state from serve-repos.sh)
  --help, -h         Show this help message
  --version          Show version

Environment Variables:
  HOMESTAK_SOURCE    Installation source (overridden by --source)
  HOMESTAK_REF       Git ref (overridden by --ref)
  HOMESTAK_TOKEN     Auth token for HTTP sources (required for http://)
  HOMESTAK_USER      Create a sudo user during bootstrap
  HOMESTAK_APPLY     Run a task after bootstrap (e.g., pve-setup)
  HOMESTAK_DEST      Custom installation directory (for testing)

Installation Paths (FHS-compliant):
  /usr/local/bin/homestak      CLI symlink
  /usr/local/etc/homestak/     site-config (configuration)
  /usr/local/lib/homestak/     code repos

Source Types:
  github   Default. Clones from GitHub, includes site-config.
  http://  Dev workflow. Requires --ref and HOMESTAK_TOKEN. Skips site-config.
  file://  Air-gapped. Clones from local path.

Examples:
  # Basic bootstrap from GitHub
  curl -fsSL .../install.sh | bash

  # Pin to specific version
  curl -fsSL .../install.sh | HOMESTAK_REF=v0.37 bash

  # Bootstrap from HTTP server (dev workflow)
  HOMESTAK_SOURCE=http://192.0.2.1:54321 \
  HOMESTAK_TOKEN=a7Bx9kLmN2pQ4rSt \
  HOMESTAK_REF=_working \
  ./install.sh

  # Air-gapped installation
  ./install.sh --source file:///mnt/usb/homestak --ref v0.37

  # Show help
  curl -fsSL .../install.sh | bash -s -- --help

For more information: https://github.com/homestak-dev
EOF
    exit 0
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --source)
                HOMESTAK_SOURCE="$2"
                shift 2
                ;;
            --ref)
                HOMESTAK_REF="$2"
                shift 2
                ;;
            --version)
                echo "install.sh v$VERSION"
                exit 0
                ;;
            --help|-h)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

parse_args "$@"

# FHS-compliant installation paths (can be overridden for testing)
HOMESTAK_LIB="${HOMESTAK_DEST:-/usr/local/lib/homestak}"   # Code repos
HOMESTAK_ETC="${HOMESTAK_DEST:+${HOMESTAK_DEST}/etc}"
HOMESTAK_ETC="${HOMESTAK_ETC:-/usr/local/etc/homestak}"    # Configuration (site-config)
HOMESTAK_BIN="${HOMESTAK_DEST:+${HOMESTAK_DEST}/bin}"
HOMESTAK_BIN="${HOMESTAK_BIN:-/usr/local/bin}"             # CLI symlink

GITHUB_ORG="https://github.com/homestak-dev"
HOMESTAK_USER="${HOMESTAK_USER:-}"
APPLY_TASK="${HOMESTAK_APPLY:-}"

# Code repos (cloned to HOMESTAK_LIB)
CODE_REPOS=(bootstrap ansible iac-driver tofu)

# Source detection and configuration
SOURCE_TYPE=""
BASE_URL=""
REF=""
SKIP_SITE_CONFIG=false

detect_source() {
    local source="${HOMESTAK_SOURCE:-github}"

    case "$source" in
        github|https://github.com/*)
            SOURCE_TYPE="github"
            BASE_URL="$GITHUB_ORG"
            REF="${HOMESTAK_REF:-master}"
            SKIP_SITE_CONFIG=false
            ;;
        http://*)
            SOURCE_TYPE="http"
            BASE_URL="$source"
            REF="${HOMESTAK_REF:-}"
            SKIP_SITE_CONFIG=true  # Ansible handles secrets separately

            # Validate HTTP source requirements
            if [[ -z "$REF" ]]; then
                log_error "HTTP source requires --ref (e.g., master, v0.37, _working)"
                exit 1
            fi
            if [[ -z "${HOMESTAK_TOKEN:-}" ]]; then
                log_error "HTTP source requires HOMESTAK_TOKEN"
                exit 1
            fi
            ;;
        file://*)
            SOURCE_TYPE="file"
            BASE_URL="${source#file://}"
            REF="${HOMESTAK_REF:-master}"
            SKIP_SITE_CONFIG=false
            ;;
        *)
            log_error "Unknown source type: $source"
            echo "Expected: github, http://..., or file://..."
            exit 1
            ;;
    esac
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}==>${NC} $1"; }
log_warn() { echo -e "${YELLOW}==>${NC} $1"; }
log_error() { echo -e "${RED}==>${NC} $1"; }

# Must run as root (skip check if HOMESTAK_DEST is set for testing)
if [[ -z "${HOMESTAK_DEST:-}" ]] && [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    echo "Usage: curl -fsSL .../install.sh | sudo bash"
    exit 1
fi

# Detect and configure source
detect_source

log_info "Homestak Bootstrap"
log_info "Source: $SOURCE_TYPE ($BASE_URL)"
log_info "Ref: $REF"

#
# Step 1: Install minimal prerequisites
#
log_info "Installing prerequisites (git, make)..."
apt-get update -qq
apt-get install -y -qq git make > /dev/null

#
# Step 2: Clone/update homestak repos
#
log_info "Setting up homestak repositories..."
mkdir -p "$HOMESTAK_LIB"
mkdir -p "$HOMESTAK_ETC"

clone_or_update() {
    local repo_name="$1"
    local target_dir="$2"
    local repo_url
    local git_opts=()

    # Build URL and options based on source type
    case "$SOURCE_TYPE" in
        github)
            repo_url="${BASE_URL}/${repo_name}.git"
            ;;
        http)
            repo_url="${BASE_URL}/${repo_name}.git"
            # Add auth header for HTTP sources
            git_opts+=(-c "http.extraHeader=Authorization: Bearer ${HOMESTAK_TOKEN}")
            ;;
        file)
            repo_url="${BASE_URL}/${repo_name}"
            ;;
    esac

    if [[ -d "$target_dir/.git" ]]; then
        log_info "  Updating $repo_name..."
        git "${git_opts[@]}" -C "$target_dir" fetch -q origin 2>/dev/null || true
        git -C "$target_dir" checkout -q "$REF" 2>/dev/null || \
            git -C "$target_dir" checkout -q "origin/$REF" 2>/dev/null || true
        git "${git_opts[@]}" -C "$target_dir" pull -q origin "$REF" 2>/dev/null || true
    else
        [[ -d "$target_dir" ]] && rm -rf "$target_dir"
        log_info "  Cloning $repo_name from $SOURCE_TYPE ($REF)..."
        if ! git "${git_opts[@]}" clone -q -b "$REF" "$repo_url" "$target_dir" 2>&1; then
            log_error "Failed to clone $repo_name"
            return 1
        fi
    fi
}

# Clone code repos to /usr/local/lib/homestak/
for repo in "${CODE_REPOS[@]}"; do
    clone_or_update "$repo" "$HOMESTAK_LIB/$repo"
done

# Clone site-config to /usr/local/etc/homestak/ (skip for HTTP sources)
if [[ "$SKIP_SITE_CONFIG" == true ]]; then
    log_info "  Skipping site-config (will be configured separately for HTTP source)"
else
    clone_or_update "site-config" "$HOMESTAK_ETC"
fi

#
# Step 3: Setup site-config
#
if [[ "$SKIP_SITE_CONFIG" != true ]]; then
    log_info "Setting up site-config..."
    if [[ -f "$HOMESTAK_ETC/Makefile" ]]; then
        make -C "$HOMESTAK_ETC" setup 2>&1 | sed 's/^/    /' || true
    fi
else
    log_info "Skipping site-config setup (HTTP source)"
fi

# Export for iac-driver discovery
export HOMESTAK_SITE_CONFIG="$HOMESTAK_ETC"

#
# Step 4: Install dependencies for each repo
#
log_info "Installing dependencies..."
for repo in "${CODE_REPOS[@]}"; do
    if [[ -f "$HOMESTAK_LIB/$repo/Makefile" ]] && [[ "$repo" != "bootstrap" ]]; then
        log_info "  $repo..."
        make -C "$HOMESTAK_LIB/$repo" install-deps 2>&1 | sed 's/^/    /'
    fi
done

#
# Step 5: Install homestak CLI (symlink to bootstrap/homestak.sh)
#
log_info "Installing homestak CLI..."
ln -sf "$HOMESTAK_LIB/bootstrap/homestak.sh" "$HOMESTAK_BIN/homestak"
log_info "  Linked: $HOMESTAK_BIN/homestak -> $HOMESTAK_LIB/bootstrap/homestak.sh"

#
# Step 6: Create user if requested
#
if [[ -n "$HOMESTAK_USER" ]]; then
    log_info "Creating user: $HOMESTAK_USER"
    "$HOMESTAK_BIN/homestak" playbook user -e local_user="$HOMESTAK_USER"
fi

#
# Step 7: Apply task if requested
#
if [[ -n "$APPLY_TASK" ]]; then
    log_info "Applying task: $APPLY_TASK"
    "$HOMESTAK_BIN/homestak" "$APPLY_TASK"
fi

#
# Done - Show summary
#
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  Homestak Bootstrap Complete${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo "Installation:"
echo "  Source:      $SOURCE_TYPE ($REF)"
echo "  Code repos:  $HOMESTAK_LIB"
if [[ "$SKIP_SITE_CONFIG" != true ]]; then
    echo "  Config:      $HOMESTAK_ETC"
fi
echo "  CLI:         $HOMESTAK_BIN/homestak"
echo ""
echo "Modules:"
for repo in "${CODE_REPOS[@]}"; do
    echo "  - $repo"
done
if [[ "$SKIP_SITE_CONFIG" != true ]]; then
    echo "  - site-config"
else
    echo "  - site-config (skipped - configure separately)"
fi
echo ""
echo "Quick start:"
echo "  homestak status              # Check installation"
echo "  homestak site-init           # Initialize configuration"
echo "  homestak pve-setup           # Configure Proxmox"
echo "  homestak user -e local_user=myuser"
echo "  homestak scenario --help     # View available scenarios"
echo ""
