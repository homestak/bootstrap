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
#   --skip-apt-wait    Skip waiting for apt processes (use when apt is idle)
#   --insecure         Accept self-signed TLS certificates
#   --help             Show help message
#   --version          Show version
#
# Environment Variables:
#   HOMESTAK_SOURCE    Installation source (overridden by --source)
#   HOMESTAK_REF       Git ref (overridden by --ref)
#   HOMESTAK_TOKEN     Auth token for HTTP/HTTPS sources (optional)
#   HOMESTAK_INSECURE  Accept self-signed TLS certs (set to 1)
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
                     - http[s]://host:port (HTTP/HTTPS server)
                     - file:///path (local filesystem)
  --ref REF          Git ref to checkout (default: master)
                     - master, main (branches)
                     - v0.37 (tags)
                     - _working (working tree state from serve-repos.sh)
  --skip-apt-wait    Skip waiting for apt processes to complete
                     Use when apt is known to be idle (e.g., dedicated VMs)
  --insecure         Accept self-signed TLS certificates (HTTPS sources)
  --help, -h         Show this help message
  --version          Show version

Environment Variables:
  HOMESTAK_SOURCE    Installation source (overridden by --source)
  HOMESTAK_REF       Git ref (overridden by --ref)
  HOMESTAK_TOKEN     Auth token for HTTP/HTTPS sources (optional)
  HOMESTAK_INSECURE  Accept self-signed TLS certs (overridden by --insecure)
  HOMESTAK_USER      Create a sudo user during bootstrap
  HOMESTAK_APPLY     Run a task after bootstrap (e.g., pve-setup)
  HOMESTAK_DEST      Custom installation directory (for testing)

Installation Paths (FHS-compliant):
  /usr/local/bin/homestak      CLI symlink
  /usr/local/etc/homestak/     site-config (configuration)
  /usr/local/lib/homestak/     code repos

Source Types:
  github      Default. Clones from GitHub, includes site-config.
  http[s]://  Controller/server. Token optional, --insecure for self-signed.
  file://     Air-gapped. Clones from local path.

Examples:
  # Basic bootstrap from GitHub
  curl -fsSL .../install.sh | bash

  # Pin to specific version
  curl -fsSL .../install.sh | HOMESTAK_REF=v0.37 bash

  # Bootstrap from controller (pull mode first boot)
  curl -fsSk https://father:44443/bootstrap.git/install.sh | \
  HOMESTAK_SOURCE=https://father:44443 HOMESTAK_INSECURE=1 bash

  # Air-gapped installation
  ./install.sh --source file:///mnt/usb/homestak --ref v0.37

  # Show help
  curl -fsSL .../install.sh | bash -s -- --help

For more information: https://github.com/homestak-dev
EOF
    exit 0
}

# Parse arguments
SKIP_APT_WAIT=false
INSECURE="${HOMESTAK_INSECURE:-}"

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
            --skip-apt-wait)
                SKIP_APT_WAIT=true
                shift
                ;;
            --insecure)
                INSECURE=1
                shift
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
SKIP_SITE_CONFIG="${SKIP_SITE_CONFIG:-false}"

detect_source() {
    local source="${HOMESTAK_SOURCE:-github}"

    case "$source" in
        github|https://github.com/*)
            SOURCE_TYPE="github"
            BASE_URL="$GITHUB_ORG"
            REF="${HOMESTAK_REF:-master}"
            ;;
        http://*|https://*)
            SOURCE_TYPE="http"
            BASE_URL="$source"
            REF="${HOMESTAK_REF:-master}"
            ;;
        file://*)
            SOURCE_TYPE="file"
            BASE_URL="${source#file://}"
            REF="${HOMESTAK_REF:-master}"
            ;;
        *)
            log_error "Unknown source type: $source"
            echo "Expected: github, http[s]://..., or file://..."
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
# Step 0: Stop apt timers to prevent lock contention
#
# unattended-upgrades runs via apt-daily.timer and apt-daily-upgrade.timer.
# These can grab apt locks at unpredictable times (RandomizedDelaySec up to 60min).
# Stop them before any apt operations to ensure deterministic behavior.
# Timers re-enable automatically on next reboot.
#
# Use --skip-apt-wait to bypass this when apt is known to be idle.
#
# wait_for_apt: Block until no apt/dpkg processes are running.
# DPkg::Lock::Timeout only covers dpkg locks, not apt's own lists lock
# (/var/lib/apt/lists/lock), so we must wait for processes to finish.
wait_for_apt() {
    if [[ "$SKIP_APT_WAIT" == true ]]; then
        return 0
    fi
    log_info "Waiting for apt processes to complete..."
    while pgrep -x apt-get >/dev/null 2>&1 || pgrep -x apt >/dev/null 2>&1 || pgrep -x dpkg >/dev/null 2>&1; do
        sleep 2
    done
}

if [[ "$SKIP_APT_WAIT" == true ]]; then
    log_info "Skipping apt wait (--skip-apt-wait)"
else
    # Wait for cloud-init to complete before touching apt.
    # On first boot, cloud-init runs apt-get update as part of its cc_apt_configure
    # module. If we start our apt operations while cloud-init is still running,
    # we'll hit the apt lists lock. Waiting here is the clean solution.
    if command -v cloud-init >/dev/null 2>&1; then
        log_info "Waiting for cloud-init to complete..."
        cloud-init status --wait >/dev/null 2>&1 || true
    fi

    log_info "Stopping apt timers and services to prevent lock contention..."
    systemctl stop apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
    systemctl stop apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
    systemctl stop unattended-upgrades.service 2>/dev/null || true

    # Brief delay to allow services to fully release locks
    sleep 2

    wait_for_apt

    # Set system-wide apt lock wait so ALL apt-get calls (including downstream
    # Makefiles) wait indefinitely for dpkg locks instead of failing immediately.
    # This covers install-deps in ansible, iac-driver, tofu Makefiles without
    # requiring cross-repo changes.
    log_info "Configuring apt lock wait policy..."
    echo 'DPkg::Lock::Timeout "-1";' > /etc/apt/apt.conf.d/99-homestak-lock-wait
fi

#
# Step 1: Install minimal prerequisites
#
log_info "Installing prerequisites (git, make)..."
export DEBIAN_FRONTEND=noninteractive  # Prevent debconf prompts in non-TTY environments

# Retry apt-get with exponential backoff for lock contention
apt_retry() {
    local cmd="$1"
    local max_attempts=5
    local attempt=1
    local delay=2

    while [ $attempt -le $max_attempts ]; do
        if $cmd; then
            return 0
        fi
        if [ $attempt -lt $max_attempts ]; then
            log_warn "apt command failed (attempt $attempt/$max_attempts), retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

apt_retry "apt-get update -qq" || {
    log_error "apt-get update failed after multiple attempts"
    exit 1
}
apt_retry "apt-get install -y -qq git make" || {
    log_error "apt-get install failed after multiple attempts"
    exit 1
}

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
            if [[ -n "${HOMESTAK_TOKEN:-}" ]]; then
                git_opts+=(-c "http.extraHeader=Authorization: Bearer ${HOMESTAK_TOKEN}")
            fi
            if [[ "$INSECURE" == "1" ]]; then
                git_opts+=(-c "http.sslVerify=false")
            fi
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
    if ! clone_or_update "$repo" "$HOMESTAK_LIB/$repo"; then
        log_error "Failed to clone $repo - aborting"
        exit 1
    fi
done

# Clone site-config to /usr/local/etc/homestak/ (skip for HTTP sources)
if [[ "$SKIP_SITE_CONFIG" == "true" ]] || [[ "$SKIP_SITE_CONFIG" == "1" ]]; then
    log_info "  Skipping site-config (SKIP_SITE_CONFIG=${SKIP_SITE_CONFIG})"
else
    clone_or_update "site-config" "$HOMESTAK_ETC"
fi

#
# Step 3: Setup site-config
#
if [[ "$SKIP_SITE_CONFIG" != "true" ]] && [[ "$SKIP_SITE_CONFIG" != "1" ]]; then
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
# Clear apt cache to prevent corrupt-cache errors from interrupted operations
# (e.g., cloud-init apt-get update that was killed or overlapped).
apt-get clean 2>/dev/null || true
log_info "Installing dependencies..."
for repo in "${CODE_REPOS[@]}"; do
    if [[ -f "$HOMESTAK_LIB/$repo/Makefile" ]] && [[ "$repo" != "bootstrap" ]]; then
        # Wait before EACH repo — apt processes may start between repos
        # (unattended-upgrades, cloud-init, etc. can spawn new apt-get at any time)
        wait_for_apt
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
if [[ "$SKIP_SITE_CONFIG" != "true" ]] && [[ "$SKIP_SITE_CONFIG" != "1" ]]; then
    echo "  Config:      $HOMESTAK_ETC"
fi
echo "  CLI:         $HOMESTAK_BIN/homestak"
echo ""
echo "Modules:"
for repo in "${CODE_REPOS[@]}"; do
    echo "  - $repo"
done
if [[ "$SKIP_SITE_CONFIG" != "true" ]] && [[ "$SKIP_SITE_CONFIG" != "1" ]]; then
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
