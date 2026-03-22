# Bootstrap & Config Flow

The create → config flow enables automatic spec discovery for newly provisioned VMs (v0.45+).

## Overview

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

## How It Works

1. **create phase (tofu)**:
   - VM provisioned with cloud-init
   - Environment variables injected to `/etc/profile.d/homestak.sh`:
     - `HOMESTAK_SERVER` - Spec server URL
     - `HOMESTAK_TOKEN` - HMAC-signed provisioning token (carries identity + spec FK)

2. **First Boot (cloud-init runcmd)**:
   - Bootstraps from server (`HOMESTAK_SERVER`) using `_working` branch
   - Runs `./run.sh config fetch --insecure && ./run.sh config apply` (iac-driver fetches spec + applies config)
   - Config-complete marker written on success

3. **Config phase (v0.48+)**:
   - `./run.sh config fetch` downloads spec from server; `./run.sh config apply` applies it locally
   - Maps spec sections to ansible role variables via `spec_to_ansible_vars()`
   - Runs `config-apply.yml` playbook (base, users, security roles)
   - Writes completion marker to `$HOMESTAK_ROOT/.state/config/complete.json`
   - **Push mode** (default): driver SSHes into VM and runs config
   - **Pull mode**: cloud-init runs `./run.sh config fetch --insecure && ./run.sh config apply` on first boot
   - See `iac-driver/CLAUDE.md` for full execution mode documentation

## Configuration

**Driver (site.yaml)**:
```yaml
defaults:
  server_url: "https://srv1:44443"
```

**Server**:
```bash
# Start on driver (iac-driver)
cd ~/iac/iac-driver && ./run.sh server start
```

**Validation Scenarios**:
```bash
# Test create → specify flow (push verification)
cd ~/iac/iac-driver && ./run.sh scenario run push-vm-roundtrip -H srv1

# Test create → config flow (pull verification, v0.48+)
cd ~/iac/iac-driver && ./run.sh scenario run pull-vm-roundtrip -H srv1
```

## Authentication

VMs authenticate to the spec server using a provisioning token (`HOMESTAK_TOKEN`) — an HMAC-SHA256 signed credential carrying the node identity and spec FK. The token is minted by ConfigResolver and injected via cloud-init. The server verifies the signature against `secrets.auth.signing_key`.
