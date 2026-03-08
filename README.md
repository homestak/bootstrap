# Homestak Bootstrap

One-command setup for Proxmox infrastructure-as-code.

## Quick Start

```bash
# 1. Bootstrap (creates homestak user, clones repos)
curl -fsSL https://raw.githubusercontent.com/homestak/bootstrap/master/install | sudo bash

# 2. Switch to homestak user (all subsequent commands run as homestak)
sudo -iu homestak

# 3. Configure site defaults for your network
vi ~/etc/site.yaml
# Required: defaults.gateway, defaults.dns_servers
# Optional: defaults.domain (e.g., home.arpa)

# 4. Initialize site configuration (generates host config, SSH key)
homestak site-init

# 5. Install PVE + configure host (generates API token, signing key, node config)
# Note: On fresh Debian, pve-setup reboots after kernel install.
#       After reboot: sudo -iu homestak, then re-run homestak pve-setup
homestak pve-setup

# 6. Download and publish packer images
homestak images download all --publish
```

Your host is now ready to provision VMs:

```bash
cd ~/lib/iac-driver
./run.sh manifest apply -M n1-push -H $(hostname -s) --verbose
```

## Usage

All `homestak` commands run as the `homestak` user:

```bash
sudo -iu homestak

homestak status                        # Check installation
homestak pve-setup                     # Configure PVE host
homestak images download all --publish # Download and publish packer images
homestak install packer                # Install optional modules
homestak update                        # Update all repos
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
- `~homestak/bin/homestak`

**Optional:**
- `packer/` - Image building (install via `homestak install packer`)

## Requirements

- Proxmox VE 8.x (or Debian 12/13 for pve-install)
- Root access (for initial bootstrap)
- Internet connection (for initial clone)

## License

Apache 2.0 - See [LICENSE](LICENSE)
