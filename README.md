# Homestak Bootstrap

One-command setup for Proxmox infrastructure-as-code.

## Quick Start

```bash
# 1. Bootstrap
curl -fsSL https://raw.githubusercontent.com/homestak-dev/bootstrap/master/install.sh | bash

# 2. Configure site defaults for your network
sudo vi /usr/local/etc/homestak/site.yaml
# Required: defaults.gateway, defaults.dns_servers
# Optional: defaults.domain (e.g., home.arpa)

# 3. Initialize site configuration (generates host config, SSH key)
sudo homestak site-init

# 4. Install PVE + configure host (generates API token, signing key, node config)
# Note: On fresh Debian, pve-setup reboots after kernel install.
#       Re-run the same command after reboot to complete setup.
sudo homestak pve-setup

# 5. Download and publish packer images
sudo homestak images download all --publish
```

Your host is now ready to provision VMs:

```bash
cd /usr/local/lib/homestak/iac-driver
sudo ./run.sh manifest apply -M n1-push -H $(hostname -s) --verbose
```

## Usage

```bash
# Check installation
sudo homestak status

# Configure PVE host
sudo homestak pve-setup

# Download and publish packer images
sudo homestak images download all --publish

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
