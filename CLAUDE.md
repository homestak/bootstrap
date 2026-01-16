# Bootstrap - Homestak Entry Point

The "front door" to the homestak infrastructure-as-code ecosystem. This repo provides the curl|bash entry point that sets up a Proxmox host for local IAC execution.

## Quick Reference

```bash
# Basic bootstrap
curl -fsSL https://raw.githubusercontent.com/homestak-dev/bootstrap/master/install.sh | bash

# Bootstrap with user creation
curl -fsSL .../install.sh | HOMESTAK_USER=homestak bash

# After bootstrap, use the 'homestak' command
homestak status
homestak pve-setup
homestak playbook user -e local_user=myuser
homestak scenario pve-setup --local
```

## What It Does

1. **Installs prerequisites** - git, make (minimal)
2. **Clones core repos** - site-config, ansible, iac-driver, tofu
3. **Sets up site-config** - runs `make setup` for secrets management
4. **Runs `make install-deps`** - each repo installs its own dependencies
5. **Installs `homestak` CLI** - unified interface for all tooling
6. **Optionally creates user** - via `HOMESTAK_USER` env var
7. **Optionally runs initial task** - via `HOMESTAK_APPLY` env var

## Project Structure

```
bootstrap/
├── install.sh      # curl|bash entry point
├── CLAUDE.md       # This file
└── README.md       # User-facing documentation
```

## Installed Structure

After running install.sh:

```
/opt/homestak/
├── site-config/    # Site-specific secrets and configuration
├── ansible/        # Playbooks and roles
├── iac-driver/     # Orchestration engine
├── tofu/           # VM provisioning
├── packer/         # (optional) Image building
└── homestak        # CLI wrapper

/usr/local/bin/
└── homestak -> /opt/homestak/homestak
```

## homestak CLI

```bash
# Commands
homestak site-init [--force]       # Initialize site configuration
homestak images <subcommand>       # Manage packer images
homestak playbook <name> [args]    # Run ansible playbook
homestak scenario <name> [args]    # Run iac-driver scenario
homestak secrets <action>          # Manage secrets (decrypt, encrypt, check, validate)
homestak install <module>          # Install optional module (packer)
homestak update                    # Update all repositories
homestak status                    # Show installation status

# Image subcommands
homestak images list [--version <tag>]
homestak images download <target...> [--version <tag>] [--overwrite] [--publish]
homestak images publish [<target...>] [--overwrite]

# Playbook shortcuts
homestak pve-setup                 # Configure Proxmox host
homestak pve-install               # Install PVE on Debian 13
homestak user                      # User management
homestak network                   # Network configuration
```

### Site Initialization

The `site-init` command prepares a fresh system for homestak workflows:

1. Generates `hosts/<hostname>.yaml` from system info
2. Generates `nodes/<hostname>.yaml` if PVE is installed
3. Creates SSH key (ed25519) if none exists
4. Decrypts secrets if encrypted file exists

### Image Management

The `images` command manages packer images from GitHub releases:

- **Download location**: `/var/tmp/homestak/images/` (persists across reboots)
- **Publish location**: `/var/lib/vz/template/iso/` (PVE storage)
- **Split files**: Automatically reassembles `*.partaa`, `*.partab`, etc.
- **Resume support**: Uses `curl -C -` for interrupted downloads

Typical workflow:
```bash
homestak images download all --publish   # Download and install all images
homestak images list --version v0.22     # List images in specific release
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HOMESTAK_BRANCH` | master | Git branch to use for all repos |
| `HOMESTAK_USER` | (none) | Create this user with sudo privileges |
| `HOMESTAK_APPLY` | (none) | Task to run after bootstrap (pve-setup, user, network) |

## Architecture

### Dependency Installation

Each repo has a `Makefile` with an `install-deps` target:

| Repo | Dependencies |
|------|--------------|
| ansible | python3, python3-pip, python3-venv, pipx, git, sudo, ansible-core (via pipx) |
| iac-driver | python3, python3-yaml |
| tofu | tofu (from official OpenTofu repo) |
| packer | packer (optional, installed via `homestak install packer`) |

Bootstrap installs only `git` and `make`, then delegates to each repo's Makefile.

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
