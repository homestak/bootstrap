#!/bin/bash
#
# Homestak CLI
# Unified interface for homestak IAC tooling
#
# Installation paths (FHS-compliant):
#   /usr/local/bin/homestak      - CLI symlink
#   /usr/local/etc/homestak/     - site-config (configuration)
#   /usr/local/lib/homestak/     - code repos
#
set -euo pipefail

# Git-derived version (do not use hardcoded VERSION constant)
get_version() {
    git -C "$(dirname "$0")" describe --tags --abbrev=0 2>/dev/null || echo "dev"
}

VERBOSE=false

# FHS-compliant paths
HOMESTAK_LIB="/usr/local/lib/homestak"
HOMESTAK_ETC="/usr/local/etc/homestak"
ANSIBLE_DIR="$HOMESTAK_LIB/ansible"
IAC_DRIVER_DIR="$HOMESTAK_LIB/iac-driver"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo "homestak $(get_version) - Unified interface for homestak IAC tooling"
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
    echo "  update [options]          Update all repositories"
    echo "  preflight [host]          Run preflight checks (local by default)"
    echo "  status                    Show installation status"
    echo ""
    echo "Global options:"
    echo "  --help, -h                Show this help message"
    echo "  --version                 Show version"
    echo "  --verbose, -v             Enable verbose output"
    echo ""
    echo "Update options:"
    echo "  --dry-run                 Show what would be updated without making changes"
    echo "  --version <tag>           Checkout specific version tag (e.g., v0.24)"
    echo "  --stash                   Stash uncommitted changes before updating"
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
    echo "  homestak --version"
    echo "  homestak site-init"
    echo "  homestak images download all --publish"
    echo "  homestak pve-setup"
    echo "  homestak playbook user -e local_user=myuser"
    echo "  homestak scenario pve-setup --local"
    echo "  homestak secrets decrypt"
    echo "  homestak install packer"
    echo "  homestak update --dry-run"
    echo "  homestak update --version v0.24"
    echo "  homestak preflight"
    echo "  homestak preflight mother"
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

run_preflight() {
    if [[ ! -x "$IAC_DRIVER_DIR/run.sh" ]]; then
        echo -e "${RED}iac-driver not found${NC}"
        exit 1
    fi

    # Check if target host specified
    local args=("--preflight" "--local")
    if [[ $# -gt 0 && "$1" != --* ]]; then
        # First non-flag arg is target host
        args=("--preflight" "--host" "$1")
        shift
    fi

    exec "$IAC_DRIVER_DIR/run.sh" "${args[@]}" "$@"
}

install_module() {
    local module="$1"
    local repo_url="https://github.com/homestak-dev/${module}.git"
    local target_dir="$HOMESTAK_LIB/$module"

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

    if [[ ! -d "$HOMESTAK_ETC" ]]; then
        echo -e "${RED}site-config not found at $HOMESTAK_ETC${NC}"
        exit 1
    fi

    case "$action" in
        decrypt|encrypt|check|validate)
            echo -e "${GREEN}==>${NC} Running: make $action"
            make -C "$HOMESTAK_ETC" "$action"
            ;;
        *)
            echo -e "${RED}Unknown action: $action${NC}"
            echo "Available actions: decrypt, encrypt, check, validate"
            exit 1
            ;;
    esac
}

update_repos() {
    local dry_run=false
    local version=""
    local stash=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true; shift ;;
            --version) version="$2"; shift 2 ;;
            --stash) stash=true; shift ;;
            *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
        esac
    done

    local all_repos=("bootstrap" "ansible" "iac-driver" "tofu" "packer" "site-config")
    local success_count=0
    local fail_count=0

    if [[ "$dry_run" == "true" ]]; then
        echo -e "${GREEN}==>${NC} Checking for updates..."
    elif [[ -n "$version" ]]; then
        echo -e "${GREEN}==>${NC} Updating to $version..."
    else
        echo -e "${GREEN}==>${NC} Updating repositories..."
    fi

    for repo in "${all_repos[@]}"; do
        local target_dir
        if [[ "$repo" == "site-config" ]]; then
            target_dir="$HOMESTAK_ETC"
        else
            target_dir="$HOMESTAK_LIB/$repo"
        fi

        if [[ ! -d "$target_dir/.git" ]]; then
            printf "  %-12s %s\n" "$repo" "(not installed)"
            continue
        fi

        # Check for uncommitted changes
        local has_changes=false
        if ! git -C "$target_dir" diff --quiet 2>/dev/null || \
           ! git -C "$target_dir" diff --cached --quiet 2>/dev/null; then
            has_changes=true
        fi

        if [[ "$dry_run" == "true" ]]; then
            # Dry-run: fetch and show what would change
            git -C "$target_dir" fetch -q origin 2>/dev/null || true
            local local_ref=$(git -C "$target_dir" rev-parse HEAD 2>/dev/null)
            local remote_ref=$(git -C "$target_dir" rev-parse origin/master 2>/dev/null || \
                             git -C "$target_dir" rev-parse origin/main 2>/dev/null)
            if [[ -n "$version" ]]; then
                remote_ref=$(git -C "$target_dir" rev-parse "refs/tags/$version" 2>/dev/null || echo "")
                if [[ -z "$remote_ref" ]]; then
                    printf "  %-12s %s\n" "$repo" "(tag $version not found)"
                    continue
                fi
            fi
            if [[ "$local_ref" == "$remote_ref" ]]; then
                printf "  %-12s %s\n" "$repo" "up to date"
            else
                local ahead=$(git -C "$target_dir" rev-list --count "$local_ref".."$remote_ref" 2>/dev/null || echo "?")
                printf "  %-12s %s\n" "$repo" "$ahead new commit(s)"
            fi
            continue
        fi

        # Check for dirty state
        if [[ "$has_changes" == "true" ]]; then
            if [[ "$stash" == "true" ]]; then
                printf "  %-12s stashing changes...\n" "$repo"
                git -C "$target_dir" stash push -m "homestak update $(date +%Y%m%d-%H%M%S)" -q 2>/dev/null || true
            else
                printf "  %-12s %s\n" "$repo" "${YELLOW}skipped (uncommitted changes, use --stash)${NC}"
                ((fail_count++))
                continue
            fi
        fi

        # Fetch and update
        printf "  %-12s " "$repo"
        if ! git -C "$target_dir" fetch -q origin 2>/dev/null; then
            echo -e "${RED}fetch failed${NC}"
            ((fail_count++))
            continue
        fi

        if [[ -n "$version" ]]; then
            # Update to specific version
            if git -C "$target_dir" rev-parse "refs/tags/$version" >/dev/null 2>&1; then
                if git -C "$target_dir" checkout -q "$version" 2>/dev/null; then
                    echo -e "${GREEN}$version${NC}"
                    ((success_count++))
                else
                    echo -e "${RED}checkout failed${NC}"
                    ((fail_count++))
                fi
            else
                echo -e "${YELLOW}tag not found${NC}"
                ((fail_count++))
            fi
        else
            # Update to latest
            local before=$(git -C "$target_dir" rev-parse --short HEAD 2>/dev/null)
            if git -C "$target_dir" pull -q origin 2>/dev/null; then
                local after=$(git -C "$target_dir" rev-parse --short HEAD 2>/dev/null)
                if [[ "$before" == "$after" ]]; then
                    echo -e "${GREEN}up to date${NC}"
                else
                    echo -e "${GREEN}updated ($before..$after)${NC}"
                fi
                ((success_count++))
            else
                echo -e "${RED}pull failed${NC}"
                ((fail_count++))
            fi
        fi
    done

    echo ""
    if [[ "$dry_run" == "true" ]]; then
        echo "Run 'homestak update' to apply changes."
    else
        echo -e "${GREEN}==>${NC} Done. ($success_count updated, $fail_count failed)"
    fi
}

show_status() {
    echo "Homestak Status"
    echo ""
    echo "Code directory: $HOMESTAK_LIB"
    echo "Config directory: $HOMESTAK_ETC"
    echo ""
    echo "Installed modules:"

    # Code repos
    for repo in bootstrap ansible iac-driver tofu packer; do
        local target_dir="$HOMESTAK_LIB/$repo"
        if [[ -d "$target_dir/.git" ]]; then
            local branch=$(git -C "$target_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
            local commit=$(git -C "$target_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
            printf "  %-12s %s (%s)\n" "$repo" "$branch" "$commit"
        else
            printf "  %-12s %s\n" "$repo" "(not installed)"
        fi
    done

    # site-config (separate location)
    if [[ -d "$HOMESTAK_ETC/.git" ]]; then
        local branch=$(git -C "$HOMESTAK_ETC" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        local commit=$(git -C "$HOMESTAK_ETC" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        printf "  %-12s %s (%s)\n" "site-config" "$branch" "$commit"
    else
        printf "  %-12s %s\n" "site-config" "(not installed)"
    fi

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

    if [[ ! -d "$HOMESTAK_ETC" ]]; then
        echo -e "${RED}site-config not found at $HOMESTAK_ETC. Run bootstrap first.${NC}"
        exit 1
    fi

    echo -e "${GREEN}==>${NC} Site initialization"

    # Step 1: Generate host configuration
    local host_config="$HOMESTAK_ETC/hosts/$(hostname).yaml"
    if [[ -f "$host_config" && "$force" != "true" ]]; then
        echo -e "${RED}Host config already exists: $host_config${NC}"
        echo "Use --force to overwrite"
        exit 1
    fi
    echo "  Generating host configuration..."
    if [[ "$force" == "true" ]]; then
        make -C "$HOMESTAK_ETC" host-config FORCE=1 2>&1 | sed 's/^/    /'
    else
        make -C "$HOMESTAK_ETC" host-config 2>&1 | sed 's/^/    /'
    fi

    # Step 2: Generate node configuration (if PVE is installed)
    if command -v pvesh &>/dev/null; then
        local node_config="$HOMESTAK_ETC/nodes/$(hostname).yaml"
        if [[ -f "$node_config" && "$force" != "true" ]]; then
            echo -e "${RED}Node config already exists: $node_config${NC}"
            echo "Use --force to overwrite"
            exit 1
        fi
        echo "  Generating node configuration (PVE detected)..."
        if [[ "$force" == "true" ]]; then
            make -C "$HOMESTAK_ETC" node-config FORCE=1 2>&1 | sed 's/^/    /'
        else
            make -C "$HOMESTAK_ETC" node-config 2>&1 | sed 's/^/    /'
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
    if [[ -f "$HOMESTAK_ETC/secrets.yaml.enc" ]]; then
        if [[ -f "$HOMESTAK_ETC/secrets.yaml" ]]; then
            echo "  Secrets already decrypted"
        else
            echo "  Decrypting secrets..."
            make -C "$HOMESTAK_ETC" decrypt 2>&1 | sed 's/^/    /' || {
                echo -e "${YELLOW}  Warning: Could not decrypt secrets (age key may be missing)${NC}"
            }
        fi
    else
        echo "  No encrypted secrets found"
    fi

    # Step 5: Add SSH key to secrets.yaml if not already present
    local secrets_file="$HOMESTAK_ETC/secrets.yaml"
    if [[ -f "$secrets_file" && -f "$ssh_pub" ]]; then
        local pub_key
        pub_key=$(cat "$ssh_pub")
        # Extract key identifier from comment (last field) or construct from user@host
        local key_id
        key_id=$(echo "$pub_key" | awk '{print $NF}')
        if [[ -z "$key_id" || "$key_id" == "$pub_key" ]]; then
            key_id="$(whoami)@$(hostname)"
        fi

        # Use Python script for safe YAML manipulation
        local add_key_script="$HOMESTAK_LIB/bootstrap/scripts/add-ssh-key.py"
        if [[ -f "$add_key_script" ]]; then
            local result
            result=$(python3 "$add_key_script" "$secrets_file" "$key_id" "$pub_key" 2>&1)
            local exit_code=$?
            if [[ $exit_code -eq 0 ]]; then
                echo -e "  ${GREEN}Added SSH key to secrets.yaml${NC} (${key_id})"
            elif [[ $exit_code -eq 2 ]]; then
                echo "  SSH key already in secrets.yaml"
            else
                echo -e "  ${RED}Failed to add SSH key: $result${NC}"
            fi
        else
            echo -e "  ${YELLOW}Warning: add-ssh-key.py not found, skipping key injection${NC}"
        fi
    fi

    echo ""
    echo -e "${GREEN}==>${NC} Site initialization complete"
    echo ""
    echo "Next steps:"
    echo "  1. Review generated configs in $HOMESTAK_ETC/"
    echo "  2. Run: homestak images download all --publish"
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

    # Collect whole images (.qcow2) and split image bases (.qcow2.partaa)
    local whole_images split_bases images
    whole_images=$(echo "$assets" | grep '\.qcow2$' || true)
    split_bases=$(echo "$assets" | grep '\.qcow2\.partaa$' | sed 's/\.partaa$//' || true)

    # Combine and deduplicate (split bases that also have whole files shouldn't happen, but handle it)
    images=$(printf '%s\n%s' "$whole_images" "$split_bases" | grep -v '^$' | sort -u || true)

    if [[ -z "$images" ]]; then
        echo "No images found in release '$version'"
        exit 1
    fi

    echo "Images:"
    echo "$images" | while read -r img; do
        # Check if this is a multipart image
        if echo "$assets" | grep -q "^${img}\.partaa$"; then
            local parts
            parts=$(echo "$assets" | grep "^${img}\.part" | wc -l)
            echo "  $img (multipart: $parts parts)"
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

# Parse global options first
PASSTHROUGH_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            echo "homestak $(get_version)"
            exit 0
            ;;
        --verbose|-v)
            VERBOSE=true
            PASSTHROUGH_ARGS+=("$1")
            shift
            ;;
        *)
            break
            ;;
    esac
done

[[ $# -lt 1 ]] && usage

CMD="$1"
shift

# Append any remaining passthrough args
PASSTHROUGH_ARGS+=("$@")

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
        update_repos "$@"
        ;;
    status)
        show_status
        ;;
    preflight)
        run_preflight "$@"
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
