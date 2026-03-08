# Bootstrap - Homestak Entry Point

The "front door" to the homestak infrastructure-as-code ecosystem. This repo provides the curl|bash entry point that sets up a Proxmox host for local IAC execution.

## Quick Reference

```bash
# Basic bootstrap (creates homestak user, clones repos)
curl -fsSL https://raw.githubusercontent.com/homestak-dev/bootstrap/master/install | sudo bash

# Bootstrap and immediately run pve-setup
curl -fsSL .../install | HOMESTAK_APPLY=pve-setup sudo bash

# View install options (download first)
./install --help

# After bootstrap, switch to homestak user
sudo -iu homestak
homestak status
homestak pve-setup
```

## What It Does

1. **Creates `homestak` user** - dedicated user with sudo privileges
2. **Installs prerequisites** - git, make (minimal)
3. **Clones code repos** - bootstrap, ansible, iac-driver, tofu to `~homestak/lib/`
4. **Clones site-config** - to `~homestak/etc/`
5. **Sets up site-config** - runs `make setup` and `make install-deps` (installs age, sops)
6. **Initializes secrets** - runs `make init-secrets` (decrypts `.enc` or copies `.example` template)
7. **Runs `make install-deps`** - each code repo installs its own dependencies
8. **Installs `homestak` CLI** - symlink to `~homestak/bin/homestak`
9. **Optionally runs initial task** - via `HOMESTAK_APPLY` env var

## Project Structure

```
bootstrap/
├── install         # curl|bash entry point
├── homestak        # Standalone CLI script
├── lib/            # Python modules
│   └── spec_client.py  # HTTP client for spec fetching
├── tests/          # Test scripts
│   ├── homestak.bats          # CLI unit tests (bats)
│   ├── test_spec_client.sh    # Spec client integration test
│   └── test-install-remote.sh # Remote install integration test
├── CLAUDE.md       # This file
└── README.md       # User-facing documentation
```

## Installed Structure

After running install:

```
~homestak/
├── bin/
│   └── homestak → ../lib/bootstrap/homestak
├── etc/                    # site-config (configuration)
│   ├── site.yaml
│   ├── secrets.yaml
│   ├── defs/
│   ├── hosts/
│   ├── nodes/
│   ├── postures/
│   ├── specs/
│   ├── presets/
│   └── manifests/
├── lib/                    # code repos
│   ├── bootstrap/
│   │   ├── homestak
│   │   └── install
│   ├── ansible/
│   ├── iac-driver/
│   ├── tofu/
│   └── packer/             # (optional)
├── log/
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

- **Download location**: `/var/tmp/homestak/images/` (persists across reboots)
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

**Schema validation** has moved to site-config: `cd ~/etc && make validate`

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HOMESTAK_BRANCH` | master | Git branch to use for all repos |
| `HOMESTAK_APPLY` | (none) | Task to run after bootstrap (pve-setup, pve-install, user, config) |
| `HOMESTAK_LIB` | ~/lib | Code repos directory (for development) |
| `HOMESTAK_ETC` | ~/etc | Site-config directory (for development) |
| `HOMESTAK_SERVER` | (none) | Spec server URL (e.g., `https://srv1:44443`) |
| `HOMESTAK_TOKEN` | (none) | HMAC-signed provisioning token (minted by ConfigResolver) |
| `HOMESTAK_SOURCE` | (none) | Repo source URL for bootstrap (e.g., server URL for pull mode) |
| `HOMESTAK_REF` | master | Git ref for bootstrap clones (e.g., `_working` for server repos) |
| `HOMESTAK_INSECURE` | (none) | Skip TLS verification for server connections |

## Create → Config Flow (v0.45+)

The create → config flow enables automatic spec discovery for newly provisioned VMs.

### Overview

```
Driver (srv1)                  VM (test)
┌─────────────────┐              ┌─────────────────┐
│ ./run.sh server │◄─────────────│ homestak spec   │
│ start (daemon)  │   GET /spec  │ get             │
│ :44443          │   /test      │                 │
└─────────────────┘              └─────────────────┘
                                        │
                                        ▼
                                 ~/etc/state/
                                 spec.yaml
```

### How It Works

1. **create phase (tofu)**:
   - VM provisioned with cloud-init
   - Environment variables injected to `/etc/profile.d/homestak.sh`:
     - `HOMESTAK_SERVER` - Spec server URL
     - `HOMESTAK_TOKEN` - HMAC-signed provisioning token (carries identity + spec FK)

2. **First Boot (cloud-init runcmd)**:
   - Bootstraps from server (`HOMESTAK_SOURCE`) using `_working` branch
   - Runs `./run.sh config fetch --insecure && ./run.sh config apply` (iac-driver fetches spec + applies config)
   - Config-complete marker written on success

3. **Config phase (v0.48+)**:
   - `./run.sh config fetch` downloads spec from server; `./run.sh config apply` applies it locally
   - Maps spec sections to ansible role variables via `spec_to_ansible_vars()`
   - Runs `config-apply.yml` playbook (base, users, security roles)
   - Writes completion marker to `state/config-complete.json`
   - **Push mode** (default): driver SSHes into VM and runs config
   - **Pull mode**: cloud-init runs `./run.sh config fetch --insecure && ./run.sh config apply` on first boot
   - See `iac-driver/CLAUDE.md` for full execution mode documentation

### Configuration

**Driver (site.yaml)**:
```yaml
defaults:
  spec_server: "https://srv1:44443"
```

**Server**:
```bash
# Start on driver (iac-driver)
cd ~/lib/iac-driver && ./run.sh server start
```

**Validation Scenarios**:
```bash
# Test create → specify flow (push verification)
cd ~/lib/iac-driver && ./run.sh scenario run push-vm-roundtrip -H srv1

# Test create → config flow (pull verification, v0.48+)
cd ~/lib/iac-driver && ./run.sh scenario run pull-vm-roundtrip -H srv1
```

### Authentication

VMs authenticate to the spec server using a provisioning token (`HOMESTAK_TOKEN`) — an HMAC-SHA256 signed credential carrying the node identity and spec FK. The token is minted by ConfigResolver and injected via cloud-init. The server verifies the signature against `secrets.auth.signing_key`.

## Architecture

### Dependency Installation

Each repo has a `Makefile` with an `install-deps` target:

| Repo | Dependencies |
|------|--------------|
| ansible | python3, python3-pip, python3-venv, pipx, git, sudo, ansible-core (via pipx) |
| iac-driver | python3, python3-yaml |
| tofu | tofu (from official OpenTofu repo) |
| packer | packer (optional, installed via `homestak install packer`) |

Bootstrap installs `git`, `make`, and `gh` (GitHub CLI), then delegates to each repo's Makefile.

### Core vs Optional Modules

**Core (always installed):**
- site-config - Site-specific secrets and configuration
- ansible - Playbooks and roles
- iac-driver - Orchestration engine
- tofu - VM provisioning with OpenTofu

**Optional (installed via `homestak install`):**
- packer - Image building (release assets available on GitHub)

## Related Projects

| Repo | Purpose |
|------|---------|
| [bootstrap](https://github.com/homestak-dev/bootstrap) | This repo - entry point |
| [site-config](https://github.com/homestak-dev/site-config) | Site-specific secrets and configuration |
| [ansible](https://github.com/homestak-dev/ansible) | Playbooks and roles |
| [iac-driver](https://github.com/homestak-dev/iac-driver) | Orchestration engine |
| [tofu](https://github.com/homestak-dev/tofu) | VM provisioning |
| [packer](https://github.com/homestak-dev/packer) | Custom Debian cloud images |

## Design Philosophy

- **Single entry point**: One URL to remember
- **Minimal bootstrap**: Only git + make, repos own their dependencies
- **Local execution**: Avoids SSH connection issues (especially for network changes)
- **Idempotent**: Safe to run multiple times
- **Extensible**: Easy to add more repos/modules

## License

Apache 2.0
