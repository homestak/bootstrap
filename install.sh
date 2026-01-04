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
#   HOMESTAK_APPLY=pve-setup Run a task after bootstrap
#
# Examples:
#   # Basic bootstrap
#   curl -fsSL .../install.sh | bash
#
#   # Bootstrap and apply pve-setup
#   curl -fsSL .../install.sh | HOMESTAK_APPLY=pve-setup bash
#
#   # Use develop branch
#   curl -fsSL .../install.sh | HOMESTAK_BRANCH=develop bash
#
set -euo pipefail

# Configuration
HOMESTAK_DIR="/opt/homestak"
GITHUB_ORG="https://github.com/homestak-dev"
BRANCH="${HOMESTAK_BRANCH:-master}"
APPLY_TASK="${HOMESTAK_APPLY:-}"

# Repos to clone
REPOS=(ansible)

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
# Step 1: Install prerequisites
#
log_info "Installing prerequisites..."
apt-get update -qq
apt-get install -y -qq git ansible python3-pip sudo > /dev/null

#
# Step 2: Clone/update homestak repos
#
log_info "Setting up homestak repositories..."
mkdir -p "$HOMESTAK_DIR"

clone_or_update() {
    local repo_name="$1"
    local repo_url="${GITHUB_ORG}/${repo_name}.git"
    local target_dir="${HOMESTAK_DIR}/${repo_name}"

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

for repo in "${REPOS[@]}"; do
    clone_or_update "$repo"
done

# Create symlink for backward compatibility
[[ -L /opt/ansible ]] && rm /opt/ansible
[[ -d /opt/ansible ]] || ln -sf "$HOMESTAK_DIR/ansible" /opt/ansible

#
# Step 3: Install local execution wrapper
#
log_info "Installing local execution wrapper..."

cat > "$HOMESTAK_DIR/run-local.sh" << 'WRAPPER'
#!/bin/bash
#
# Homestak Local Runner
# Run ansible playbooks locally on this host
#
set -euo pipefail

ANSIBLE_DIR="/opt/homestak/ansible"
INVENTORY="$ANSIBLE_DIR/inventory/local.yml"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

usage() {
    echo "Homestak Local Runner"
    echo ""
    echo "Usage: $0 <playbook> [ansible options...]"
    echo ""
    echo "Playbooks:"
    echo "  pve-setup      Core PVE configuration"
    echo "  pve-install    Install PVE on Debian 13"
    echo "  user           User management"
    echo "  network        Network configuration"
    echo ""
    echo "Examples:"
    echo "  $0 pve-setup"
    echo "  $0 user -e local_user=myuser"
    echo "  $0 network -e pve_network_tasks='[\"static\"]' -e pve_new_ip=10.0.12.100"
    echo ""
    exit 1
}

[[ $# -lt 1 ]] && usage

PLAYBOOK="$1"
shift

# Map short names to playbook files
case "$PLAYBOOK" in
    pve-setup)   PLAYBOOK_FILE="$ANSIBLE_DIR/playbooks/pve-setup.yml" ;;
    pve-install) PLAYBOOK_FILE="$ANSIBLE_DIR/playbooks/pve-install.yml" ;;
    user)        PLAYBOOK_FILE="$ANSIBLE_DIR/playbooks/user.yml" ;;
    network)     PLAYBOOK_FILE="$ANSIBLE_DIR/playbooks/pve-network.yml" ;;
    -h|--help)   usage ;;
    *)
        # Allow direct playbook path
        if [[ -f "$PLAYBOOK" ]]; then
            PLAYBOOK_FILE="$PLAYBOOK"
        elif [[ -f "$ANSIBLE_DIR/playbooks/$PLAYBOOK" ]]; then
            PLAYBOOK_FILE="$ANSIBLE_DIR/playbooks/$PLAYBOOK"
        else
            echo -e "${RED}Unknown playbook: $PLAYBOOK${NC}"
            usage
        fi
        ;;
esac

if [[ ! -f "$PLAYBOOK_FILE" ]]; then
    echo -e "${RED}Playbook not found: $PLAYBOOK_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}==>${NC} Running: $(basename $PLAYBOOK_FILE)"
cd "$ANSIBLE_DIR"
exec ansible-playbook -i "$INVENTORY" "$PLAYBOOK_FILE" -c local "$@"
WRAPPER

chmod +x "$HOMESTAK_DIR/run-local.sh"

# Add to PATH via symlink
ln -sf "$HOMESTAK_DIR/run-local.sh" /usr/local/bin/homestak

#
# Step 4: Apply task if requested
#
if [[ -n "$APPLY_TASK" ]]; then
    log_info "Applying task: $APPLY_TASK"
    "$HOMESTAK_DIR/run-local.sh" "$APPLY_TASK"
fi

#
# Done
#
log_info "Bootstrap complete!"
echo ""
echo "Homestak installed to: $HOMESTAK_DIR"
echo ""
echo "Run playbooks locally:"
echo "  homestak pve-setup"
echo "  homestak user -e local_user=myuser"
echo "  homestak network -e pve_network_tasks='[\"reip\"]' -e pve_new_ip=10.0.12.100"
echo ""
echo "Or use the full path:"
echo "  /opt/homestak/run-local.sh <playbook> [options]"
echo ""
