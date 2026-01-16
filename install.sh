#!/bin/bash
#
# Homestak Bootstrap
# Installs the homestak IAC tooling for local execution
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/homestak-dev/bootstrap/master/install.sh | bash
#
# Options (via environment variables):
#   HOMESTAK_BRANCH=develop  Use a different branch
#   HOMESTAK_USER=homestak   Create a sudo user during bootstrap
#   HOMESTAK_APPLY=pve-setup Run a task after bootstrap
#
# Examples:
#   # Basic bootstrap
#   curl -fsSL .../install.sh | bash
#
#   # Bootstrap with user creation and pve-setup
#   curl -fsSL .../install.sh | HOMESTAK_USER=homestak HOMESTAK_APPLY=pve-setup bash
#
#   # Use develop branch
#   curl -fsSL .../install.sh | HOMESTAK_BRANCH=develop bash
#
set -euo pipefail

# FHS-compliant installation paths
HOMESTAK_LIB="/usr/local/lib/homestak"   # Code repos
HOMESTAK_ETC="/usr/local/etc/homestak"   # Configuration (site-config)
HOMESTAK_BIN="/usr/local/bin"            # CLI symlink

GITHUB_ORG="https://github.com/homestak-dev"
BRANCH="${HOMESTAK_BRANCH:-master}"
HOMESTAK_USER="${HOMESTAK_USER:-}"
APPLY_TASK="${HOMESTAK_APPLY:-}"

# Code repos (cloned to HOMESTAK_LIB)
CODE_REPOS=(bootstrap ansible iac-driver tofu)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}==>${NC} $1"; }
log_warn() { echo -e "${YELLOW}==>${NC} $1"; }
log_error() { echo -e "${RED}==>${NC} $1"; }

# Must run as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    echo "Usage: curl -fsSL .../install.sh | sudo bash"
    exit 1
fi

log_info "Homestak Bootstrap"
log_info "Branch: $BRANCH"

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
    local repo_url="${GITHUB_ORG}/${repo_name}.git"

    if [[ -d "$target_dir/.git" ]]; then
        log_info "  Updating $repo_name..."
        git -C "$target_dir" fetch -q origin
        git -C "$target_dir" checkout -q "$BRANCH" 2>/dev/null || \
            git -C "$target_dir" checkout -q "origin/$BRANCH" 2>/dev/null || true
        git -C "$target_dir" pull -q origin "$BRANCH" 2>/dev/null || true
    else
        [[ -d "$target_dir" ]] && rm -rf "$target_dir"
        log_info "  Cloning $repo_name..."
        git clone -q -b "$BRANCH" "$repo_url" "$target_dir" 2>/dev/null || \
            git clone -q "$repo_url" "$target_dir"
    fi
}

# Clone code repos to /usr/local/lib/homestak/
for repo in "${CODE_REPOS[@]}"; do
    clone_or_update "$repo" "$HOMESTAK_LIB/$repo"
done

# Clone site-config to /usr/local/etc/homestak/
clone_or_update "site-config" "$HOMESTAK_ETC"

#
# Step 3: Setup site-config
#
log_info "Setting up site-config..."
if [[ -f "$HOMESTAK_ETC/Makefile" ]]; then
    make -C "$HOMESTAK_ETC" setup 2>&1 | sed 's/^/    /' || true
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
echo "  Code repos:  $HOMESTAK_LIB"
echo "  Config:      $HOMESTAK_ETC"
echo "  CLI:         $HOMESTAK_BIN/homestak"
echo ""
echo "Modules:"
for repo in "${CODE_REPOS[@]}"; do
    echo "  - $repo"
done
echo "  - site-config"
echo ""
echo "Quick start:"
echo "  homestak status              # Check installation"
echo "  homestak site-init           # Initialize configuration"
echo "  homestak pve-setup           # Configure Proxmox"
echo "  homestak user -e local_user=myuser"
echo "  homestak scenario --help     # View available scenarios"
echo ""
