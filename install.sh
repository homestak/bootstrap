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

# Configuration
HOMESTAK_DIR="/opt/homestak"
GITHUB_ORG="https://github.com/homestak-dev"
BRANCH="${HOMESTAK_BRANCH:-master}"
HOMESTAK_USER="${HOMESTAK_USER:-}"
APPLY_TASK="${HOMESTAK_APPLY:-}"

# Core repos (always installed)
CORE_REPOS=(site-config ansible iac-driver tofu)

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

for repo in "${CORE_REPOS[@]}"; do
    clone_or_update "$repo"
done

#
# Step 3: Setup site-config
#
log_info "Setting up site-config..."
if [[ -f "$HOMESTAK_DIR/site-config/Makefile" ]]; then
    make -C "$HOMESTAK_DIR/site-config" setup 2>&1 | sed 's/^/    /' || true
fi

# Export for iac-driver discovery
export HOMESTAK_SITE_CONFIG="$HOMESTAK_DIR/site-config"

#
# Step 4: Install dependencies for each repo
#
log_info "Installing dependencies..."
for repo in "${CORE_REPOS[@]}"; do
    if [[ -f "$HOMESTAK_DIR/$repo/Makefile" ]] && [[ "$repo" != "site-config" ]]; then
        log_info "  $repo..."
        make -C "$HOMESTAK_DIR/$repo" install-deps 2>&1 | sed 's/^/    /'
    fi
done

#
# Step 5: Install homestak CLI
#
log_info "Installing homestak CLI..."

cat > "$HOMESTAK_DIR/homestak" << 'CLI'
#!/bin/bash
#
# Homestak CLI
# Unified interface for homestak IAC tooling
#
set -euo pipefail

HOMESTAK_DIR="/opt/homestak"
ANSIBLE_DIR="$HOMESTAK_DIR/ansible"
IAC_DRIVER_DIR="$HOMESTAK_DIR/iac-driver"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo "Homestak CLI"
    echo ""
    echo "Usage: homestak <command> [options]"
    echo ""
    echo "Commands:"
    echo "  site-init [--force]       Initialize site configuration"
    echo "  images <subcommand>       Manage packer images"
    echo "  playbook <name> [args]    Run an ansible playbook"
    echo "  scenario <name> [args]    Run an iac-driver scenario"
    echo "  secrets <action>          Manage secrets (decrypt, encrypt, check, validate)"
    echo "  install <module>          Install optional module (packer)"
    echo "  update                    Update all repositories"
    echo "  status                    Show installation status"
    echo ""
    echo "Image subcommands:"
    echo "  images list [--version <tag>]"
    echo "  images download <target...> [--version <tag>] [--overwrite] [--publish]"
    echo "  images publish [<target...>] [--overwrite]"
    echo ""
    echo "Playbook shortcuts:"
    echo "  pve-setup                 Configure Proxmox host"
    echo "  pve-install               Install PVE on Debian 13"
    echo "  user                      User management"
    echo "  network                   Network configuration"
    echo ""
    echo "Examples:"
    echo "  homestak site-init"
    echo "  homestak images download all --publish"
    echo "  homestak pve-setup"
    echo "  homestak playbook user -e local_user=myuser"
    echo "  homestak scenario pve-setup --local"
    echo "  homestak secrets decrypt"
    echo "  homestak install packer"
    echo ""
    exit 1
}

run_playbook() {
    local playbook="$1"
    shift
    local playbook_file

    # Map short names to playbook files
    case "$playbook" in
        pve-setup)   playbook_file="$ANSIBLE_DIR/playbooks/pve-setup.yml" ;;
        pve-install) playbook_file="$ANSIBLE_DIR/playbooks/pve-install.yml" ;;
        user)        playbook_file="$ANSIBLE_DIR/playbooks/user.yml" ;;
        network)     playbook_file="$ANSIBLE_DIR/playbooks/pve-network.yml" ;;
        *)
            if [[ -f "$playbook" ]]; then
                playbook_file="$playbook"
            elif [[ -f "$ANSIBLE_DIR/playbooks/$playbook" ]]; then
                playbook_file="$ANSIBLE_DIR/playbooks/$playbook"
            elif [[ -f "$ANSIBLE_DIR/playbooks/${playbook}.yml" ]]; then
                playbook_file="$ANSIBLE_DIR/playbooks/${playbook}.yml"
            else
                echo -e "${RED}Unknown playbook: $playbook${NC}"
                exit 1
            fi
            ;;
    esac

    if [[ ! -f "$playbook_file" ]]; then
        echo -e "${RED}Playbook not found: $playbook_file${NC}"
        exit 1
    fi

    echo -e "${GREEN}==>${NC} Running playbook: $(basename "$playbook_file")"
    cd "$ANSIBLE_DIR"
    exec ansible-playbook -i inventory/local.yml "$playbook_file" -c local "$@"
}

run_scenario() {
    local scenario="$1"
    shift

    if [[ ! -x "$IAC_DRIVER_DIR/run.sh" ]]; then
        echo -e "${RED}iac-driver not found${NC}"
        exit 1
    fi

    echo -e "${GREEN}==>${NC} Running scenario: $scenario"
    exec "$IAC_DRIVER_DIR/run.sh" --scenario "$scenario" "$@"
}

install_module() {
    local module="$1"
    local repo_url="https://github.com/homestak-dev/${module}.git"
    local target_dir="$HOMESTAK_DIR/$module"

    case "$module" in
        packer)
            echo -e "${GREEN}==>${NC} Installing $module..."
            if [[ -d "$target_dir/.git" ]]; then
                echo "  Already installed, updating..."
                git -C "$target_dir" pull -q
            else
                git clone -q "$repo_url" "$target_dir"
            fi
            if [[ -f "$target_dir/Makefile" ]]; then
                make -C "$target_dir" install-deps 2>&1 | sed 's/^/  /'
            fi
            echo -e "${GREEN}==>${NC} Done."
            ;;
        *)
            echo -e "${RED}Unknown module: $module${NC}"
            echo "Available modules: packer"
            exit 1
            ;;
    esac
}

manage_secrets() {
    local action="$1"
    local site_config="$HOMESTAK_DIR/site-config"

    if [[ ! -d "$site_config" ]]; then
        echo -e "${RED}site-config not found${NC}"
        exit 1
    fi

    case "$action" in
        decrypt|encrypt|check|validate)
            echo -e "${GREEN}==>${NC} Running: make $action"
            make -C "$site_config" "$action"
            ;;
        *)
            echo -e "${RED}Unknown action: $action${NC}"
            echo "Available actions: decrypt, encrypt, check, validate"
            exit 1
            ;;
    esac
}

update_repos() {
    echo -e "${GREEN}==>${NC} Updating repositories..."
    for repo in site-config ansible iac-driver tofu packer; do
        local target_dir="$HOMESTAK_DIR/$repo"
        if [[ -d "$target_dir/.git" ]]; then
            echo "  $repo..."
            git -C "$target_dir" pull -q 2>/dev/null || echo "    (failed to update)"
        fi
    done
    echo -e "${GREEN}==>${NC} Done."
}

show_status() {
    echo "Homestak Status"
    echo ""
    echo "Installation directory: $HOMESTAK_DIR"
    echo ""
    echo "Installed modules:"
    for repo in site-config ansible iac-driver tofu packer; do
        local target_dir="$HOMESTAK_DIR/$repo"
        if [[ -d "$target_dir/.git" ]]; then
            local branch=$(git -C "$target_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
            local commit=$(git -C "$target_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
            printf "  %-12s %s (%s)\n" "$repo" "$branch" "$commit"
        else
            printf "  %-12s %s\n" "$repo" "(not installed)"
        fi
    done
    echo ""
    echo "Tools:"
    printf "  %-12s " "ansible" && (ansible --version 2>/dev/null | head -1 || echo "not installed")
    printf "  %-12s " "tofu" && (tofu version 2>/dev/null | head -1 || echo "not installed")
    printf "  %-12s " "packer" && (packer version 2>/dev/null | head -1 || echo "not installed")
    echo ""
}

site_init() {
    local force=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=true; shift ;;
            *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
        esac
    done

    local site_config="$HOMESTAK_DIR/site-config"
    if [[ ! -d "$site_config" ]]; then
        echo -e "${RED}site-config not found. Run bootstrap first.${NC}"
        exit 1
    fi

    echo -e "${GREEN}==>${NC} Site initialization"

    # Step 1: Generate host configuration
    local host_config="$site_config/hosts/$(hostname).yaml"
    if [[ -f "$host_config" && "$force" != "true" ]]; then
        echo -e "${RED}Host config already exists: $host_config${NC}"
        echo "Use --force to overwrite"
        exit 1
    fi
    echo "  Generating host configuration..."
    if [[ "$force" == "true" ]]; then
        make -C "$site_config" host-config FORCE=1 2>&1 | sed 's/^/    /'
    else
        make -C "$site_config" host-config 2>&1 | sed 's/^/    /'
    fi

    # Step 2: Generate node configuration (if PVE is installed)
    if command -v pvesh &>/dev/null; then
        local node_config="$site_config/nodes/$(hostname).yaml"
        if [[ -f "$node_config" && "$force" != "true" ]]; then
            echo -e "${RED}Node config already exists: $node_config${NC}"
            echo "Use --force to overwrite"
            exit 1
        fi
        echo "  Generating node configuration (PVE detected)..."
        if [[ "$force" == "true" ]]; then
            make -C "$site_config" node-config FORCE=1 2>&1 | sed 's/^/    /'
        else
            make -C "$site_config" node-config 2>&1 | sed 's/^/    /'
        fi
    else
        echo "  Skipping node config (PVE not detected)"
    fi

    # Step 3: Check/generate SSH key
    local ssh_key="$HOME/.ssh/id_ed25519"
    local ssh_pub="$HOME/.ssh/id_ed25519.pub"
    if [[ ! -f "$ssh_pub" ]]; then
        echo "  Generating SSH key (ed25519)..."
        ssh-keygen -t ed25519 -f "$ssh_key" -N "" -C "$(whoami)@$(hostname)"
        echo "  Created: $ssh_pub"
    else
        echo "  SSH key exists: $ssh_pub"
    fi

    # Step 4: Decrypt secrets if encrypted file exists
    if [[ -f "$site_config/secrets.yaml.enc" ]]; then
        if [[ -f "$site_config/secrets.yaml" ]]; then
            echo "  Secrets already decrypted"
        else
            echo "  Decrypting secrets..."
            make -C "$site_config" decrypt 2>&1 | sed 's/^/    /' || {
                echo -e "${YELLOW}  Warning: Could not decrypt secrets (age key may be missing)${NC}"
            }
        fi
    else
        echo "  No encrypted secrets found"
    fi

    echo ""
    echo -e "${GREEN}==>${NC} Site initialization complete"
    echo ""
    echo "Next steps:"
    echo "  1. Review generated configs in $site_config/"
    echo "  2. Add your SSH public key to secrets.yaml"
    echo "  3. Run: homestak images download all --publish"
    echo ""
}

# Images directory
IMAGES_DIR="/var/tmp/homestak/images"
PVE_ISO_DIR="/var/lib/vz/template/iso"

images_list() {
    local version="latest"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version) version="$2"; shift 2 ;;
            *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
        esac
    done

    echo -e "${GREEN}==>${NC} Available images (release: $version)"
    echo ""

    local assets
    assets=$(gh release view "$version" --repo "homestak-dev/packer" --json assets --jq '.assets[].name' 2>/dev/null)

    if [[ -z "$assets" ]]; then
        echo "No images found in release '$version'"
        exit 1
    fi

    # Filter to only .qcow2 files (not checksums or parts)
    local images
    images=$(echo "$assets" | grep '\.qcow2$' || true)

    if [[ -z "$images" ]]; then
        # Check for split files
        images=$(echo "$assets" | grep '\.qcow2\.partaa$' | sed 's/\.partaa$//' || true)
    fi

    if [[ -z "$images" ]]; then
        echo "No images found in release '$version'"
        exit 1
    fi

    echo "Images:"
    echo "$images" | while read -r img; do
        local size=""
        # Check if split
        if echo "$assets" | grep -q "^${img}\.partaa$"; then
            local parts
            parts=$(echo "$assets" | grep "^${img}\.part" | wc -l)
            echo "  $img (split: $parts parts)"
        else
            echo "  $img"
        fi
    done
    echo ""
}

images_download() {
    local version="latest"
    local overwrite=false
    local publish=false
    local targets=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version) version="$2"; shift 2 ;;
            --overwrite) overwrite=true; shift ;;
            --publish) publish=true; shift ;;
            -*) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
            *) targets+=("$1"); shift ;;
        esac
    done

    if [[ ${#targets[@]} -eq 0 ]]; then
        echo "Usage: homestak images download <target...> [--version <tag>] [--overwrite] [--publish]"
        echo ""
        echo "Targets: all, debian-12-custom, debian-13-custom, debian-13-pve, or any .qcow2 filename"
        exit 1
    fi

    mkdir -p "$IMAGES_DIR"

    echo -e "${GREEN}==>${NC} Downloading images (release: $version)"

    # Get list of available assets
    local assets
    assets=$(gh release view "$version" --repo "homestak-dev/packer" --json assets --jq '.assets[].name' 2>/dev/null)

    if [[ -z "$assets" ]]; then
        echo -e "${RED}No release found: $version${NC}"
        exit 1
    fi

    # Expand "all" target
    if [[ " ${targets[*]} " =~ " all " ]]; then
        targets=($(echo "$assets" | grep '\.qcow2$' || true))
        # Also get split file bases
        local split_bases
        split_bases=$(echo "$assets" | grep '\.qcow2\.partaa$' | sed 's/\.partaa$//' || true)
        if [[ -n "$split_bases" ]]; then
            while read -r base; do
                targets+=("$base")
            done <<< "$split_bases"
        fi
    fi

    for target in "${targets[@]}"; do
        # Normalize target name (add .qcow2 if missing)
        if [[ ! "$target" =~ \.qcow2$ ]]; then
            target="${target}.qcow2"
        fi

        local output_file="$IMAGES_DIR/$target"

        # Check if exists
        if [[ -f "$output_file" && "$overwrite" != "true" ]]; then
            echo -e "${RED}File exists: $output_file${NC}"
            echo "Use --overwrite to replace"
            continue
        fi

        # Check if this is a split file
        if echo "$assets" | grep -q "^${target}\.partaa$"; then
            echo "  Downloading $target (split file)..."
            local parts
            parts=$(echo "$assets" | grep "^${target}\.part" | sort)

            # Download each part with resume support
            local all_parts_ok=true
            while read -r part; do
                local part_file="$IMAGES_DIR/$part"
                if [[ -f "$part_file" && "$overwrite" != "true" ]]; then
                    echo "    Skipping $part (exists)"
                else
                    echo "    Downloading $part..."
                    if ! gh release download "$version" --repo "homestak-dev/packer" \
                        --pattern "$part" --dir "$IMAGES_DIR" --clobber 2>/dev/null; then
                        # Try curl with resume
                        local url
                        url=$(gh release view "$version" --repo "homestak-dev/packer" \
                            --json assets --jq ".assets[] | select(.name==\"$part\") | .url" 2>/dev/null)
                        if [[ -n "$url" ]]; then
                            curl -L -C - -o "$part_file" "$url" || all_parts_ok=false
                        else
                            all_parts_ok=false
                        fi
                    fi
                fi
            done <<< "$parts"

            # Reassemble if all parts downloaded
            if [[ "$all_parts_ok" == "true" ]]; then
                echo "    Reassembling..."
                cat "$IMAGES_DIR/${target}".part* > "$output_file" 2>/dev/null && \
                    rm -f "$IMAGES_DIR/${target}".part*
                echo "    Created: $output_file"
            else
                echo -e "${RED}    Failed to download all parts${NC}"
            fi
        elif echo "$assets" | grep -q "^${target}$"; then
            echo "  Downloading $target..."
            gh release download "$version" --repo "homestak-dev/packer" \
                --pattern "$target" --dir "$IMAGES_DIR" --clobber 2>/dev/null || {
                # Fallback to curl with resume
                local url
                url=$(gh release view "$version" --repo "homestak-dev/packer" \
                    --json assets --jq ".assets[] | select(.name==\"$target\") | .url" 2>/dev/null)
                if [[ -n "$url" ]]; then
                    curl -L -C - -o "$output_file" "$url"
                fi
            }
            echo "    Downloaded: $output_file"
        else
            echo -e "${YELLOW}  Not found in release: $target${NC}"
        fi

        # Download checksum if available
        local checksum="${target}.sha256"
        if echo "$assets" | grep -q "^${checksum}$"; then
            gh release download "$version" --repo "homestak-dev/packer" \
                --pattern "$checksum" --dir "$IMAGES_DIR" --clobber 2>/dev/null || true
        fi
    done

    echo ""
    echo -e "${GREEN}==>${NC} Download complete"
    echo "Images saved to: $IMAGES_DIR"

    # Auto-publish if requested
    if [[ "$publish" == "true" ]]; then
        echo ""
        images_publish "${targets[@]}" $(if [[ "$overwrite" == "true" ]]; then echo "--overwrite"; fi)
    fi
}

images_publish() {
    local overwrite=false
    local targets=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --overwrite) overwrite=true; shift ;;
            -*) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
            *) targets+=("$1"); shift ;;
        esac
    done

    if [[ ${#targets[@]} -eq 0 ]]; then
        # Publish all downloaded images
        targets=($(ls "$IMAGES_DIR"/*.qcow2 2>/dev/null | xargs -I{} basename {} || true))
    fi

    if [[ ${#targets[@]} -eq 0 ]]; then
        echo "No images to publish. Run: homestak images download all"
        exit 1
    fi

    # Check if PVE storage exists
    if [[ ! -d "$PVE_ISO_DIR" ]]; then
        echo -e "${RED}PVE storage not found: $PVE_ISO_DIR${NC}"
        echo "Is Proxmox VE installed?"
        exit 1
    fi

    echo -e "${GREEN}==>${NC} Publishing images to PVE storage"

    for target in "${targets[@]}"; do
        # Normalize target name
        if [[ ! "$target" =~ \.qcow2$ ]]; then
            target="${target}.qcow2"
        fi

        local source_file="$IMAGES_DIR/$target"
        # Convert .qcow2 to .img for PVE
        local dest_name="${target%.qcow2}.img"
        local dest_file="$PVE_ISO_DIR/$dest_name"

        if [[ ! -f "$source_file" ]]; then
            echo -e "${YELLOW}  Not found: $source_file${NC}"
            continue
        fi

        if [[ -f "$dest_file" && "$overwrite" != "true" ]]; then
            echo -e "${RED}  Exists: $dest_file${NC}"
            echo "  Use --overwrite to replace"
            continue
        fi

        echo "  Publishing $target -> $dest_name"
        mv "$source_file" "$dest_file"
        echo "    Installed: $dest_file"
    done

    echo ""
    echo -e "${GREEN}==>${NC} Publish complete"
}

# Main
[[ $# -lt 1 ]] && usage

CMD="$1"
shift

case "$CMD" in
    site-init)
        site_init "$@"
        ;;
    images)
        [[ $# -lt 1 ]] && { echo "Usage: homestak images <list|download|publish> [args]"; exit 1; }
        SUBCMD="$1"
        shift
        case "$SUBCMD" in
            list) images_list "$@" ;;
            download) images_download "$@" ;;
            publish) images_publish "$@" ;;
            *) echo -e "${RED}Unknown images subcommand: $SUBCMD${NC}"; exit 1 ;;
        esac
        ;;
    playbook)
        [[ $# -lt 1 ]] && { echo "Usage: homestak playbook <name> [args]"; exit 1; }
        run_playbook "$@"
        ;;
    scenario)
        [[ $# -lt 1 ]] && { echo "Usage: homestak scenario <name> [args]"; exit 1; }
        run_scenario "$@"
        ;;
    secrets)
        [[ $# -lt 1 ]] && { echo "Usage: homestak secrets <decrypt|encrypt|check|validate>"; exit 1; }
        manage_secrets "$1"
        ;;
    install)
        [[ $# -lt 1 ]] && { echo "Usage: homestak install <module>"; exit 1; }
        install_module "$1"
        ;;
    update)
        update_repos
        ;;
    status)
        show_status
        ;;
    # Playbook shortcuts
    pve-setup|pve-install|user|network)
        run_playbook "$CMD" "$@"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo -e "${RED}Unknown command: $CMD${NC}"
        usage
        ;;
esac
CLI

chmod +x "$HOMESTAK_DIR/homestak"
ln -sf "$HOMESTAK_DIR/homestak" /usr/local/bin/homestak

#
# Step 6: Create user if requested
#
if [[ -n "$HOMESTAK_USER" ]]; then
    log_info "Creating user: $HOMESTAK_USER"
    "$HOMESTAK_DIR/homestak" playbook user -e local_user="$HOMESTAK_USER"
fi

#
# Step 7: Apply task if requested
#
if [[ -n "$APPLY_TASK" ]]; then
    log_info "Applying task: $APPLY_TASK"
    "$HOMESTAK_DIR/homestak" "$APPLY_TASK"
fi

#
# Done - Show summary
#
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  Homestak Bootstrap Complete${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo "Installed to: $HOMESTAK_DIR"
echo ""
echo "Modules:"
for repo in "${CORE_REPOS[@]}"; do
    echo "  - $repo"
done
echo ""
echo "Quick start:"
echo "  homestak status              # Check installation"
echo "  homestak pve-setup           # Configure Proxmox"
echo "  homestak user -e local_user=myuser"
echo "  homestak scenario --help     # View available scenarios"
echo ""
