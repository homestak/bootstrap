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

# Configure PVE
homestak pve-setup

# Create a user
homestak playbook user -e local_user=myuser

# Run a scenario
homestak scenario pve-setup --local

# Change network settings
homestak network -e pve_network_tasks='["static"]' -e pve_new_ip=10.0.12.100

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

**Core modules:**
- `/opt/homestak/site-config/` - Site-specific secrets and configuration
- `/opt/homestak/ansible/` - Ansible playbooks and roles
- `/opt/homestak/iac-driver/` - Orchestration engine
- `/opt/homestak/tofu/` - VM provisioning with OpenTofu

**CLI:**
- `/opt/homestak/homestak` - Unified CLI
- `/usr/local/bin/homestak` - Symlink for PATH access

**Optional:**
- `/opt/homestak/packer/` - Image building (install via `homestak install packer`)

## Requirements

- Proxmox VE 8.x (or Debian 12/13 for pve-install)
- Root access
- Internet connection (for initial clone)

## License

Apache 2.0 - See [LICENSE](LICENSE)
