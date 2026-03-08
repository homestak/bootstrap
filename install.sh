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
  HOMESTAK_APPLY     Run a task after bootstrap (e.g., pve-setup)
  HOMESTAK_DEST      Custom home directory (default: /home/homestak)

Installation Paths (~homestak/ user-owned):
  ~/bootstrap/      Bootstrap repo (contains CLI)
  ~/config/         Site configuration
  ~/iac/            IaC repos (ansible, iac-driver, tofu)

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
  curl -fsSk https://srv1:44443/bootstrap.git/install.sh | \
  HOMESTAK_SOURCE=https://srv1:44443 HOMESTAK_INSECURE=1 bash

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

# User-owned installation paths
_HOME="${HOMESTAK_DEST:-/home/homestak}"
HOMESTAK_ROOT="$_HOME"
IAC_DIR="$HOMESTAK_ROOT/iac"          # IaC repos (ansible, iac-driver, tofu)
CONFIG_DIR="$HOMESTAK_ROOT/config"    # Configuration (site-config)
BOOTSTRAP_DIR="$HOMESTAK_ROOT/bootstrap"  # Bootstrap repo (contains CLI)

GITHUB_ORG="https://github.com/homestak-dev"
APPLY_TASK="${HOMESTAK_APPLY:-}"

# IaC repos (cloned to IAC_DIR)
IAC_REPOS=(ansible iac-driver tofu)

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

# Run a command as the homestak user (files owned correctly from creation)
_su() { sudo -u homestak -- "$@"; }

#
# Step 0a: Create homestak user if it doesn't exist
#
if ! id homestak &>/dev/null; then
    useradd -m -s /bin/bash homestak
    echo "homestak ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/homestak
    chmod 440 /etc/sudoers.d/homestak
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
    # Wait for cloud-init to finish before we start apt operations.
    # On first boot, cloud-init runs apt-get update (cc_apt_configure module).
    #
    # IMPORTANT: When install.sh runs inside cloud-init runcmd (pull mode),
    # "cloud-init status --wait" deadlocks — it waits for cloud-init to finish,
    # but cloud-init waits for runcmd (us) to finish. Detect this and skip.
    if command -v cloud-init >/dev/null 2>&1; then
        ci_status=$(cloud-init status 2>/dev/null || true)
        if echo "$ci_status" | grep -q "status: running"; then
            log_info "Running inside cloud-init — skipping cloud-init wait"
        else
            log_info "Waiting for cloud-init to finish..."
            cloud-init status --wait >/dev/null 2>&1 || true
        fi
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
_su mkdir -p "$IAC_DIR" "$CONFIG_DIR" "$BOOTSTRAP_DIR"
_su mkdir -p "$HOMESTAK_ROOT/logs" "$HOMESTAK_ROOT/.cache" "$_HOME/.ssh"
_su chmod 700 "$_HOME/.ssh"

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
        _su git "${git_opts[@]}" -C "$target_dir" fetch -q origin 2>/dev/null || true
        _su git -C "$target_dir" checkout -q "$REF" 2>/dev/null || \
            _su git -C "$target_dir" checkout -q "origin/$REF" 2>/dev/null || true
        _su git "${git_opts[@]}" -C "$target_dir" pull -q origin "$REF" 2>/dev/null || true
    else
        [[ -d "$target_dir" ]] && _su rm -rf "$target_dir"
        log_info "  Cloning $repo_name from $SOURCE_TYPE ($REF)..."
        if ! _su git "${git_opts[@]}" clone -q -b "$REF" "$repo_url" "$target_dir" 2>&1; then
            log_error "Failed to clone $repo_name"
            return 1
        fi
    fi
}

# Clone bootstrap to $ROOT/bootstrap/
if ! clone_or_update "bootstrap" "$BOOTSTRAP_DIR"; then
    log_error "Failed to clone bootstrap - aborting"
    exit 1
fi

# Clone IaC repos to $ROOT/iac/
for repo in "${IAC_REPOS[@]}"; do
    if ! clone_or_update "$repo" "$IAC_DIR/$repo"; then
        log_error "Failed to clone $repo - aborting"
        exit 1
    fi
done

# Clone site-config to $ROOT/config/
if [[ "$SKIP_SITE_CONFIG" == "true" ]] || [[ "$SKIP_SITE_CONFIG" == "1" ]]; then
    log_info "  Skipping site-config (SKIP_SITE_CONFIG=${SKIP_SITE_CONFIG})"
else
    clone_or_update "site-config" "$CONFIG_DIR"
fi

#
# Step 3: Setup site-config
#
if [[ "$SKIP_SITE_CONFIG" != "true" ]] && [[ "$SKIP_SITE_CONFIG" != "1" ]]; then
    log_info "Setting up site-config..."
    if [[ -f "$CONFIG_DIR/Makefile" ]]; then
        _su make -C "$CONFIG_DIR" setup 2>&1 | sed 's/^/    /' || true
        _su make -C "$CONFIG_DIR" init-site 2>&1 | sed 's/^/    /' || true
        _su make -C "$CONFIG_DIR" init-secrets 2>&1 | sed 's/^/    /' || true
    fi
else
    log_info "Skipping site-config setup (HTTP source)"
fi

# Export for iac-driver discovery
export HOMESTAK_ROOT="$HOMESTAK_ROOT"

#
# Step 4: Install dependencies for each repo
#
# Clear apt cache to prevent corrupt-cache errors from interrupted operations
# (e.g., cloud-init apt-get update that was killed or overlapped).
apt-get clean 2>/dev/null || true
log_info "Installing dependencies..."
for repo in "${IAC_REPOS[@]}"; do
    if [[ -f "$IAC_DIR/$repo/Makefile" ]]; then
        # Wait before EACH repo — apt processes may start between repos
        # (unattended-upgrades, cloud-init, etc. can spawn new apt-get at any time)
        wait_for_apt
        log_info "  $repo..."
        make -C "$IAC_DIR/$repo" install-deps 2>&1 | sed 's/^/    /'
    fi
done
# site-config has its own install-deps (age, sops) — run separately
if [[ -f "$CONFIG_DIR/Makefile" ]]; then
    wait_for_apt
    log_info "  site-config..."
    make -C "$CONFIG_DIR" install-deps 2>&1 | sed 's/^/    /'
fi

#
# Step 5: Set up PATH via ~/.profile
#
log_info "Setting up environment..."
PROFILE="$_HOME/.profile"
# Add HOMESTAK_ROOT and PATH to ~/.profile (idempotent)
if ! grep -q 'HOMESTAK_ROOT' "$PROFILE" 2>/dev/null; then
    _su tee -a "$PROFILE" > /dev/null <<'PROFILEEOF'

# Homestak environment
export HOMESTAK_ROOT="$HOME"
export PATH="$HOMESTAK_ROOT/bootstrap:$PATH"
PROFILEEOF
    log_info "  Added HOMESTAK_ROOT and PATH to $PROFILE"
else
    log_info "  HOMESTAK_ROOT already in $PROFILE"
fi

#
# Step 6: Apply task if requested
#
if [[ -n "$APPLY_TASK" ]]; then
    if [[ "$APPLY_TASK" == "config" ]]; then
        log_info "Applying config phase..."
        su - homestak -c "cd $IAC_DIR/iac-driver && ./run.sh config fetch --insecure && ./run.sh config apply"
    else
        log_info "Applying task: $APPLY_TASK"
        su - homestak -c "homestak $APPLY_TASK"
    fi
fi

# Ensure secrets are never world-readable (safety net — make decrypt already sets 600)
[[ -f "$CONFIG_DIR/secrets.yaml" ]] && chmod 600 "$CONFIG_DIR/secrets.yaml"

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
echo "  Root:        $HOMESTAK_ROOT"
echo "  IaC repos:   $IAC_DIR"
if [[ "$SKIP_SITE_CONFIG" != "true" ]] && [[ "$SKIP_SITE_CONFIG" != "1" ]]; then
    echo "  Config:      $CONFIG_DIR"
fi
echo "  CLI:         $BOOTSTRAP_DIR/homestak.sh"
echo ""
echo "Modules:"
echo "  - bootstrap"
for repo in "${IAC_REPOS[@]}"; do
    echo "  - $repo"
done
if [[ "$SKIP_SITE_CONFIG" != "true" ]] && [[ "$SKIP_SITE_CONFIG" != "1" ]]; then
    echo "  - config (site-config)"
else
    echo "  - config (skipped - configure separately)"
fi
echo ""
echo "Quick start:"
echo "  homestak status              # Check installation"
echo "  homestak site-init           # Initialize configuration"
echo "  homestak pve-setup           # Configure Proxmox"
echo "  homestak user -e local_user=myuser"
echo "  homestak scenario --help     # View available scenarios"
echo ""
