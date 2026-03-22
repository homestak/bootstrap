# Install Script

## Installed Structure

After running install:

```
~homestak/
├── bootstrap/              # bootstrap repo (contains CLI)
│   ├── homestak
│   └── install
├── config/                 # site configuration
│   ├── site.yaml
│   ├── secrets.yaml
│   ├── defs/
│   ├── hosts/
│   ├── nodes/
│   ├── postures/
│   ├── specs/
│   ├── presets/
│   └── manifests/
├── iac/                    # code repos
│   ├── ansible/
│   ├── iac-driver/
│   ├── tofu/
│   └── packer/             # (optional)
├── logs/
└── cache/
```

## homestak CLI

```bash
# Global options
homestak --version                 # Show CLI version
homestak --verbose <command>       # Enable verbose output
homestak --help                    # Show help message

# Commands
homestak site-init [--force]       # Initialize site configuration
homestak images <subcommand>       # Manage packer images
homestak scenario <name> [args]    # Run iac-driver scenario
homestak secrets <action>          # Manage secrets (decrypt, encrypt, check, validate)
homestak spec <subcommand>         # Manage VM specifications
homestak install <module>          # Install optional module (packer)
homestak update [options]          # Update all repositories
homestak preflight [host]          # Run preflight checks (local by default)
homestak status                    # Show installation status

# Update options
homestak update --dry-run          # Preview updates without applying
homestak update --version v0.24    # Checkout specific version across all repos
homestak update --branch sprint/my-feature  # Switch repos to named branch
homestak update --stash            # Stash uncommitted changes before updating

# Image subcommands
homestak images list [--version <tag>]
homestak images download <target...> [--version <tag>] [--overwrite] [--publish]
homestak images publish [<target...>] [--overwrite]

# Scenario shortcuts
homestak pve-setup                 # Configure Proxmox host
homestak pve-install               # Install PVE on Debian 13
homestak user                      # User management
```

### Execution Requirements

All `homestak` commands must run as the `homestak` user (paths resolve via `$HOME`):

```bash
sudo -iu homestak
homestak scenario push-vm-roundtrip --host srv1
homestak pve-setup
```

Commands that need root (e.g., `pveum`, `apt`, `systemctl`) use the `as_root` helper internally.

### Site Initialization

The `site-init` command prepares a fresh system for homestak workflows:

1. Generates `hosts/<hostname>.yaml` from system info
2. Generates `nodes/<hostname>.yaml` if PVE is installed
3. Creates SSH key (ed25519) if none exists
4. Initializes secrets via `make init-secrets` (decrypts `.enc` if present, or copies `.example` template)

### Image Management

The `images` command manages packer images from GitHub releases:

- **Download location**: `~/.cache/images/` (under HOMESTAK_ROOT)
- **Publish location**: `/var/lib/vz/template/iso/` (PVE storage)
- **Split files**: Automatically reassembles `*.partaa`, `*.partab`, etc.
- **Resume support**: Uses `curl -C -` for interrupted downloads
- **No `gh` auth required**: Falls back to curl + GitHub REST API for public repos when `gh` CLI is not authenticated. Uses `gh` when available (preferred) for higher rate limits.

Typical workflow:
```bash
homestak images download all --publish   # Download and install all images
homestak images list --version v0.22     # List images in specific release
```

### Spec Management

The `spec` command fetches VM specifications from the server:

```bash
# Fetch spec from server (manual testing)
homestak spec get --server https://srv1:44443 --identity dev1

# Identity defaults to hostname if omitted
homestak spec get --server https://srv1:44443

# Fetch spec using environment variables (automated path)
HOMESTAK_SERVER=https://srv1:44443 homestak spec get
```

**Exit codes (get):**
- `0` - Success
- `1` - Client error (missing args, invalid config)
- `2` - Server error (network, HTTP error)
- `3` - Validation error (schema invalid)

Requires `python3-yaml` for get.

**Schema validation** has moved to config: `cd ~/config && make validate`

## Dependency Installation

Each repo has a `Makefile` with an `install-deps` target:

| Repo | Dependencies |
|------|--------------|
| ansible | python3, python3-pip, python3-venv, pipx, git, sudo, ansible-core (via pipx) |
| iac-driver | python3, python3-yaml |
| tofu | tofu (from official OpenTofu repo) |
| packer | packer (optional, installed via `homestak install packer`) |

Bootstrap installs `git`, `make`, and `gh` (GitHub CLI), then delegates to each repo's Makefile.

## Core vs Optional Modules

**Core (always installed):**
- config - Site-specific secrets and configuration
- ansible - Playbooks and roles
- iac-driver - Orchestration engine
- tofu - VM provisioning with OpenTofu

**Optional (installed via `homestak install`):**
- packer - Image building (release assets available on GitHub)
