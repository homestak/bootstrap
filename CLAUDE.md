# Bootstrap - Homestak Entry Point

The "front door" to the homestak infrastructure-as-code ecosystem. This repo provides the curl|bash entry point that sets up a Proxmox host for local IAC execution.

## Quick Reference

```bash
# Basic bootstrap
curl -fsSL https://raw.githubusercontent.com/homestak-dev/bootstrap/master/install.sh | bash

# Bootstrap and apply pve-setup
curl -fsSL .../install.sh | HOMESTAK_APPLY=pve-setup bash

# After bootstrap, use the 'homestak' command
homestak pve-setup
homestak user -e local_user=myuser
homestak network -e pve_network_tasks='["reip"]' -e pve_new_ip=10.0.12.100
```

## What It Does

1. **Installs prerequisites** - git, ansible, python3-pip, sudo
2. **Clones homestak repos** - Currently just `ansible`, extensible
3. **Installs `homestak` command** - Wrapper for local ansible execution
4. **Optionally runs initial setup** - Via `HOMESTAK_APPLY` env var

Note: Proxmox-specific configuration (repos, packages) is handled by ansible playbooks (e.g., `pve-setup`), not the bootstrap script. This keeps bootstrap generic.

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
├── ansible/        # Cloned from homestak-dev/ansible
├── run-local.sh    # Local execution wrapper
└── ...             # Future: other repos as needed

/usr/local/bin/
└── homestak -> /opt/homestak/run-local.sh
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HOMESTAK_BRANCH` | master | Git branch to use for all repos |
| `HOMESTAK_USER` | (none) | Create this user with sudo privileges |
| `HOMESTAK_APPLY` | (none) | Task to run after bootstrap (pve-setup, user, network) |

## Related Projects

| Repo | Purpose |
|------|---------|
| [bootstrap](https://github.com/homestak-dev/bootstrap) | This repo - entry point |
| [ansible](https://github.com/homestak-dev/ansible) | Playbooks and roles |
| [iac-driver](https://github.com/homestak-dev/iac-driver) | E2E test orchestration |
| [packer](https://github.com/homestak-dev/packer) | Custom Debian cloud images |
| [tofu](https://github.com/homestak-dev/tofu) | VM provisioning with OpenTofu |

## Design Philosophy

- **Single entry point**: One URL to remember
- **Local execution**: Avoids SSH connection issues (especially for network changes)
- **Idempotent**: Safe to run multiple times
- **Extensible**: Easy to add more repos to clone

## License

Apache 2.0
