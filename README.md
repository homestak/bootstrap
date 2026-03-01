# Homestak Bootstrap

One-command setup for Proxmox infrastructure-as-code.

## Quick Start

```bash
# 1. Bootstrap (creates homestak user, clones repos)
curl -fsSL https://raw.githubusercontent.com/homestak-dev/bootstrap/master/install.sh | sudo bash

# 2. Configure site defaults for your network
sudo -u homestak vi ~homestak/etc/site.yaml
# Required: defaults.gateway, defaults.dns_servers
# Optional: defaults.domain (e.g., home.arpa)

# 3. Initialize site configuration (generates host config, SSH key)
homestak site-init

# 4. Install PVE + configure host (generates API token, signing key, node config)
# Note: On fresh Debian, pve-setup reboots after kernel install.
#       Re-run the same command after reboot to complete setup.
homestak pve-setup

# 5. Download and publish packer images
homestak images download all --publish
```

Your host is now ready to provision VMs:

```bash
cd ~/lib/iac-driver
./run.sh manifest apply -M n1-push -H $(hostname -s) --verbose
```

## Usage

```bash
# Check installation
homestak status

# Configure PVE host
homestak pve-setup

# Download and publish packer images
homestak images download all --publish

# Install optional modules
homestak install packer

# Update all repos
homestak update
```

## Options

Set environment variables before piping to bash:

```bash
# Use a different branch
curl ... | HOMESTAK_BRANCH=develop sudo bash

# Bootstrap and immediately run pve-setup
curl ... | HOMESTAK_APPLY=pve-setup sudo bash
```

## What Gets Installed

**Code repos** (`~homestak/lib/`):
- `bootstrap/` - CLI and installer
- `ansible/` - Playbooks and roles
- `iac-driver/` - Orchestration engine
- `tofu/` - VM provisioning with OpenTofu

**Configuration** (`~homestak/etc/`):
- `site-config/` contents - secrets, hosts, nodes, manifests

**CLI:**
- `~homestak/bin/homestak` (symlinked to `/usr/local/bin/homestak`)

**Optional:**
- `packer/` - Image building (install via `homestak install packer`)

## Requirements

- Proxmox VE 8.x (or Debian 12/13 for pve-install)
- Root access (for initial bootstrap)
- Internet connection (for initial clone)

## License

Apache 2.0 - See [LICENSE](LICENSE)
