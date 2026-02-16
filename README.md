# Homestak Bootstrap

One-command setup for Proxmox infrastructure-as-code.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/homestak-dev/bootstrap/master/install.sh | bash
```

This installs the `homestak` command for managing your Proxmox infrastructure.

## Usage

After bootstrap:

```bash
# Check installation
homestak status

# Decrypt secrets (requires age key)
homestak secrets decrypt

# Configure PVE host
sudo homestak pve-setup

# Install optional modules
homestak install packer

# Update all repos
homestak update
```

## Options

Set environment variables before piping to bash:

```bash
# Use a different branch
curl ... | HOMESTAK_BRANCH=develop bash

# Create a user during bootstrap
curl ... | HOMESTAK_USER=homestak bash

# Bootstrap and immediately run pve-setup
curl ... | HOMESTAK_APPLY=pve-setup bash

# Combine options
curl ... | HOMESTAK_USER=homestak HOMESTAK_APPLY=pve-setup bash
```

## What Gets Installed

**Code repos** (`/usr/local/lib/homestak/`):
- `bootstrap/` - CLI and installer
- `ansible/` - Playbooks and roles
- `iac-driver/` - Orchestration engine
- `tofu/` - VM provisioning with OpenTofu

**Configuration** (`/usr/local/etc/homestak/`):
- `site-config/` contents - secrets, hosts, nodes, manifests

**CLI:**
- `/usr/local/bin/homestak` - Symlink to `bootstrap/homestak.sh`

**Optional:**
- `packer/` - Image building (install via `homestak install packer`)

## Requirements

- Proxmox VE 8.x (or Debian 12/13 for pve-install)
- Root access
- Internet connection (for initial clone)

## License

Apache 2.0 - See [LICENSE](LICENSE)
