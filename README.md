# Homestak Bootstrap

One-command setup for Proxmox infrastructure-as-code.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/homestak-dev/bootstrap/master/install.sh | bash
```

This installs the `homestak` command for running playbooks locally.

## Usage

After bootstrap:

```bash
# Configure PVE
homestak pve-setup

# Create a user
homestak user -e local_user=myuser

# Change network settings
homestak network -e pve_network_tasks='["static"]' -e pve_new_ip=10.0.12.100 -e pve_new_gateway=10.0.12.1
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

- `/opt/homestak/ansible/` - Ansible playbooks and roles
- `/opt/homestak/run-local.sh` - Local execution wrapper
- `/usr/local/bin/homestak` - Symlink to run-local.sh

## Requirements

- Proxmox VE 8.x (or Debian 12/13 for pve-install)
- Root access
- Internet connection (for initial clone)

## License

Apache 2.0 - See [LICENSE](LICENSE)
