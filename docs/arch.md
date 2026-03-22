# Architecture

Design rationale for the bootstrap installer, source-type detection, the
systemd pve-config pattern, and the HOMESTAK_ROOT anchoring model.

## Bootstrap Phases

The install script runs as root and executes six sequential phases:

1. **User creation** -- Creates the `homestak` user with a home directory and
   passwordless sudo (`/etc/sudoers.d/homestak`). All subsequent file
   operations run as this user via `sudo -u homestak`.

2. **Apt prerequisites** -- Installs only `git` and `make`. Everything else is
   delegated to each repo's `make install-deps`. Before running apt, the
   installer stops apt timers (`apt-daily.timer`, `apt-daily-upgrade.timer`)
   and waits for any running apt/dpkg processes to release locks. It also sets
   a system-wide `DPkg::Lock::Timeout "-1"` so downstream Makefiles wait for
   locks instead of failing.

3. **Repo cloning** -- Clones bootstrap, config, and three IaC repos (ansible,
   iac-driver, tofu) into the homestak user's home directory. Each repo maps
   to a GitHub org via the `REPO_ORGS` associative array.

4. **Config setup** -- Runs `make setup`, `make init-site`, and
   `make init-secrets` on the config repo. This creates `site.yaml` from the
   template and either decrypts `secrets.yaml.enc` or copies the example.

5. **Dependency installation** -- Runs `make install-deps` in each repo.
   Each repo owns its dependencies: ansible installs pipx and ansible-core,
   iac-driver installs python3-yaml, tofu installs OpenTofu, config installs
   age and sops.

6. **PATH setup** -- Appends `HOMESTAK_ROOT` and the bootstrap directory to
   `~homestak/.profile` so the `homestak` CLI is on PATH for interactive
   sessions. This write is idempotent (checks for existing entry first).

An optional seventh phase runs if `HOMESTAK_BOOT_SCENARIO` is set:

7. **Boot scenario** -- Dispatches to iac-driver for post-bootstrap
   configuration (`vm-config`, `pve-config`, `pve-setup`, or any named
   scenario).

## Source-Type Detection

The installer supports three source types, detected from `HOMESTAK_SERVER`:

| Source | When used | How repos are fetched |
|--------|-----------|----------------------|
| `github` | Default. Standard installs from the internet. | `git clone` from `https://github.com/{org}/{repo}.git` |
| `http` / `https` | Pull-mode VMs bootstrapping from a controller. | `git clone` from `{server_url}/{repo}.git` with optional bearer token and TLS skip |
| `file` | Air-gapped environments or USB installs. | `git clone` from a local filesystem path |

The `detect_source()` function parses the source URL and sets `SOURCE_TYPE`,
`BASE_URL`, and `REF`. The `clone_or_update()` function then uses these to
build the correct git URL and options (token headers for HTTP, SSL verification
bypass for `--insecure`).

The `--ref` flag (or `HOMESTAK_REF` env var) controls which git ref to check
out. Common values: `master` (default), a version tag (`v0.37`), or `_working`
(the server's current working tree snapshot, used in pull-mode bootstrapping
and development to test uncommitted changes via `serve-repos`).

## The systemd Oneshot Pattern (pve-config)

When `HOMESTAK_BOOT_SCENARIO=pve-config`, the installer does not run the
scenario inline. Instead, it creates a systemd oneshot service:

```ini
[Service]
Type=oneshot
User=homestak
Environment=HOMESTAK_SERVER=...
Environment=HOMESTAK_TOKEN=...
ExecStart=/home/homestak/iac/iac-driver/run.sh scenario run pve-config --local
RemainAfterExit=yes
```

This pattern exists because PVE installation may require a kernel reboot
(e.g., installing the PVE kernel package triggers a reboot). A oneshot service
with `WantedBy=multi-user.target` ensures the configuration resumes after
reboot without any external orchestration. The service runs once, marks itself
complete (`RemainAfterExit=yes`), and does not restart.

The `vm-config` boot scenario, by contrast, runs inline because VM
configuration does not require reboots.

## Why a Dedicated User

Bootstrap creates a `homestak` system user rather than running as root for
three reasons:

1. **Isolation.** All homestak files (repos, config, secrets, logs, cache)
   live under `~homestak/`. No system directories are modified beyond the
   sudoers drop-in and PATH. Uninstalling means removing the user.

2. **Sudo without root SSH.** The homestak user has passwordless sudo but is
   not root. This means `PermitRootLogin no` can be set in sshd_config
   without breaking homestak operations. Ansible roles escalate privileges
   internally via `become`.

3. **Ownership clarity.** Files created during bootstrap are owned by
   `homestak:homestak`, not root. This prevents permission errors when the
   homestak CLI or iac-driver later modifies those files without sudo.

## The HOMESTAK_ROOT Anchoring Model

All paths in both the install script and the homestak CLI derive from a single
anchor: `HOMESTAK_ROOT`. By default this is `/home/homestak` (the user's home
directory). Every other path is computed relative to it:

```
HOMESTAK_ROOT=/home/homestak
├── bootstrap/     = $HOMESTAK_ROOT/bootstrap
├── config/        = $HOMESTAK_ROOT/config
└── iac/           = $HOMESTAK_ROOT/iac
    ├── ansible/
    ├── iac-driver/
    └── tofu/
```

Two environment variables control path resolution at different times:

- **`HOMESTAK_DEST`** (install-time) — overrides where the install script puts files (default: `/home/homestak`). Setting `HOMESTAK_DEST=/tmp/test-install` lands the entire installation in a temporary directory and bypasses the root-check, enabling unprivileged testing.
- **`HOMESTAK_ROOT`** (runtime) — the CLI reads this at startup (default: `$HOME`) and derives `CONFIG_DIR`, `IAC_DIR`, `BOOTSTRAP_DIR`, and `ANSIBLE_DIR` from it. This means the same CLI works in both the bootstrap layout (`/home/homestak/`) and the dev workspace layout (`~/homestak/`) without configuration.

## Config Discovery

Other homestak tools find the config repo at `$HOMESTAK_ROOT/config`. On
installed hosts this resolves to `~homestak/config/` (bootstrap puts it there).
On dev workstations, set `HOMESTAK_ROOT` to your workspace root.
