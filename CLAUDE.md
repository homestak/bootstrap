# Bootstrap - Homestak Entry Point

The "front door" to the homestak infrastructure-as-code ecosystem. This repo provides the curl|bash entry point that sets up a Proxmox host for local IAC execution.

## Ecosystem Context

This repo is part of the homestak polyrepo workspace. For project architecture,
development lifecycle, sprint/release process, and cross-repo conventions, see:

- `~/homestak/dev/meta/CLAUDE.md` — primary reference
- `docs/process/` in meta — 7-phase development process
- `docs/standards/claude-guidelines.md` in meta — documentation standards

When working in a scoped session (this repo only), follow the same sprint/release
process defined in meta. Use `/session save` before context compaction and
`/session resume` to restore state in new sessions.

### Agent Boundaries

This agent operates within the following constraints:

- Opens PRs via `homestak-bot`; never merges without human approval
- Runs lint and validation tools only; never executes infrastructure operations
- Never runs `./install` or `homestak` CLI; system modifications are human-initiated

## Quick Reference

```bash
# Basic bootstrap (creates homestak user, clones repos)
curl -fsSL https://raw.githubusercontent.com/homestak/bootstrap/master/install | sudo bash

# Bootstrap and immediately run pve-setup
curl -fsSL .../install | HOMESTAK_BOOT_SCENARIO=pve-setup sudo bash

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
3. **Clones code repos** - bootstrap, ansible, iac-driver, tofu to `~homestak/iac/`
4. **Clones config** - to `~homestak/config/`
5. **Sets up site-config** - runs `make setup` and `make install-deps` (installs age, sops)
6. **Initializes secrets** - runs `make init-secrets` (decrypts `.enc` or copies `.example` template)
7. **Runs `make install-deps`** - each code repo installs its own dependencies
8. **Installs `homestak` CLI** - at `~homestak/bootstrap/homestak`
9. **Optionally runs boot scenario** - via `HOMESTAK_BOOT_SCENARIO` env var

## Project Structure

```
bootstrap/
├── install         # curl|bash entry point
├── homestak        # Standalone CLI script
├── lib/            # Python modules
│   └── spec_client.py  # HTTP client for spec fetching
├── docs/           # Detailed documentation
│   ├── boot-flow.md    # Create → config flow
│   └── install.md      # Install script & CLI reference
├── tests/          # Test scripts
│   ├── homestak.bats          # CLI unit tests (bats)
│   ├── test_spec_client.sh    # Spec client integration test
│   └── test-install-remote.sh # Remote install integration test
├── CLAUDE.md       # This file
└── README.md       # User-facing documentation
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HOMESTAK_BRANCH` | master | Git branch to use for all repos |
| `HOMESTAK_BOOT_SCENARIO` | (none) | Scenario to run after bootstrap (pve-setup, pve-config, vm-config) |
| `HOMESTAK_SERVER` | (none) | Server URL for bootstrap and provisioning (e.g., `https://srv1:44443`) |
| `HOMESTAK_TOKEN` | (none) | HMAC-signed provisioning token (minted by ConfigResolver) |
| `HOMESTAK_REF` | master | Git ref for bootstrap clones (e.g., `_working` for server repos) |
| `HOMESTAK_INSECURE` | (none) | Skip TLS verification for server connections |

## Documentation

@docs/boot-flow.md
@docs/install.md

## Related Projects

| Repo | Purpose |
|------|---------|
| [bootstrap](https://github.com/homestak/bootstrap) | This repo - entry point |
| [config](https://github.com/homestak/config) | Site-specific secrets and configuration |
| [ansible](https://github.com/homestak-iac/ansible) | Playbooks and roles |
| [iac-driver](https://github.com/homestak-iac/iac-driver) | Orchestration engine |
| [tofu](https://github.com/homestak-iac/tofu) | VM provisioning |
| [packer](https://github.com/homestak-iac/packer) | Custom Debian cloud images |

## Design Philosophy

- **Single entry point**: One URL to remember
- **Minimal bootstrap**: Only git + make, repos own their dependencies
- **Local execution**: Avoids SSH connection issues (especially for network changes)
- **Idempotent**: Safe to run multiple times
- **Extensible**: Easy to add more repos/modules

## License

Apache 2.0
