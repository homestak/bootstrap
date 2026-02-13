# Changelog

## Unreleased

### Features
- Add `--branch <name>` flag to `homestak update` for switching repos to a named branch (#49)
- Add `tests/test-install-remote.sh` — bootstrap install integration test migrated from iac-driver (#45)

### Removed
- Remove `homestak playbook` command entirely (#39)
- Remove `network` shortcut (#39)
- Reroute `pve-setup`, `pve-install`, `user` shortcuts to `homestak scenario --local` (#39)

### Fixed
- Fix apt lock contention during install-deps by dropping `/etc/apt/apt.conf.d/99-homestak-lock-wait` with `DPkg::Lock::Timeout "-1"` for dpkg locks (#52)
- Simplify apt lock handling: indefinite process wait (no timeout) + system-wide dpkg config replaces per-call `-o DPkg::Lock::Timeout=60` (#52)
- Fix `homestak update` aborting after first repo due to `set -e` and `((count++))` from zero (#49)

### Changed
- Rename `HOMESTAK_SPEC_SERVER` → `HOMESTAK_SERVER` in spec_client.py and CLI (iac-driver#188)
- Consolidate `HOMESTAK_IDENTITY` + `HOMESTAK_AUTH_TOKEN` into `HOMESTAK_TOKEN` (iac-driver#187)
- `--identity` flag now optional in `spec get` (defaults to hostname) (iac-driver#187)

### Removed
- Remove `homestak serve` command (#38)
  - Superseded by iac-driver server daemon (`./run.sh server start`)
  - CLI prints migration hint directing to iac-driver server
  - Delete `lib/serve.py` (HTTP spec server)
  - Delete `lib/spec_resolver.py` (spec loading/FK resolution)
  - Delete `tests/test_serve.sh` (serve module tests)

### Removed
- Remove `homestak spec validate` command (#40)
  - Moved to site-config as `scripts/validate-schemas.sh`
  - CLI prints migration hint directing to site-config
  - ~130 lines of embedded Python removed from homestak.sh

### Fixed
- Fix install.sh to abort on code repo clone failure instead of silently continuing (iac-driver#163)
- Make `SKIP_SITE_CONFIG` env-overridable in install.sh for controller-based bootstrap (iac-driver#163)

### Changed
- Update `test_spec_client.sh` to use iac-driver controller as test fixture (#38)
  - HTTPS with self-signed cert instead of HTTP
  - Uses `--insecure` flag for self-signed cert handling

## v0.45 - 2026-02-02

### Theme: Create Integration

Integrates create phase with config mechanism for automatic spec discovery.

### Added
- Add Create → Specify flow documentation to CLAUDE.md (#154)
  - Documents cloud-init env var injection
  - Describes first-boot spec fetch behavior
  - Includes auth model by posture

### Changed
- Rename `HOMESTAK_DISCOVERY` → `HOMESTAK_SPEC_SERVER` environment variable (#154)
  - Aligns with site.yaml `defaults.spec_server` naming convention
  - Affects `homestak spec get` and `spec_client.py`

### Fixed
- Fix PYTHONPATH for `homestak serve` and `spec get` commands (#154)
  - Use `$HOMESTAK_LIB/bootstrap` instead of `$SCRIPT_DIR`
  - Fixes module resolution when CLI invoked via symlink

## v0.44 - 2026-02-02

### Theme: Specify Infrastructure

Completes the Specify phase infrastructure for the VM lifecycle architecture.

### Added
- Add CI workflow with shellcheck, pylint, and bats tests (#163)
- Add `homestak serve` command for spec discovery server (#153)
  - HTTP server on port 44443 serving specs from site-config/v2/specs/
  - Posture-based authentication (network, site_token, node_token)
  - SIGHUP handler to clear cache without restart
  - Error codes E100-E501 per design spec
- Add `homestak spec get` command for fetching specs from server (#153)
  - HTTP client to fetch resolved specs
  - CLI flags: `--server`, `--identity`, `--token`, `--insecure`
  - Environment variable support: `HOMESTAK_SPEC_SERVER`, `HOMESTAK_IDENTITY`, `HOMESTAK_AUTH_TOKEN`
  - State persistence to `/usr/local/etc/homestak/state/spec.yaml`
  - Previous spec backed up to `spec.yaml.prev`

## v0.43 - 2026-02-01

### Added
- Add `spec` subcommand group for VM specification management (#152)
  - `spec validate` - Validates specs against v2/defs/spec.schema.json schema
  - Supports `--json` flag for machine-readable output
  - Exit codes: 0=valid, 1=invalid, 2=error
  - Schema path derived from spec file location (works in dev workspace)
- Make HOMESTAK_LIB and HOMESTAK_ETC environment-overridable for development

## v0.42 - 2026-01-31

- Release alignment with homestak v0.42

## v0.41 - 2026-01-31

### Added
- Add `--skip-apt-wait` flag to bypass apt process waiting (bootstrap#30)
  - Use when apt is known to be idle (e.g., dedicated VMs without unattended-upgrades)
  - Reduces bootstrap time by skipping timer stop and process wait

### Fixed
- Fix apt lock contention with unattended-upgrades (iac-driver#132, bootstrap#30)
  - Stop apt-daily.timer and apt-daily-upgrade.timer before apt operations
  - Wait for apt-daily services to fully stop before proceeding
  - Use DPkg::Lock::Timeout=60 for apt-get to wait for locks instead of failing
  - Timers re-enable automatically on next reboot
  - Ensures deterministic bootstrap behavior on freshly provisioned VMs

## v0.39 - 2026-01-22

### Fixed
- Fix site-config clone for HTTP sources (iac-driver#116)
  - Changed SKIP_SITE_CONFIG from true to false for HTTP sources
  - site-config is now cloned; secrets are copied separately by iac-driver
- Add DEBIAN_FRONTEND=noninteractive for apt-get in non-TTY environments

## v0.38 - 2026-01-21

### Fixed
- Fix bats test assertions to match current help text format (#26)
- Remove obsolete legacy path test (legacy support removed in v0.26)

## v0.37 - 2026-01-20

### Theme: Source-Agnostic Bootstrap

### Added
- Add `--source` and `--ref` flags for flexible installation sources (bootstrap#25)
  - `--source` accepts: `github` (default), `http://host:port`, `file:///path`
  - `--ref` accepts: branch names, tags, `_working` (for dev workflow)
  - HTTP sources require explicit `--ref` and `HOMESTAK_TOKEN`
  - site-config skipped for HTTP sources (ansible handles secrets separately)

- Add `--version` flag to show install.sh version

- Add `HOMESTAK_DEST` environment variable for test isolation
  - Allows non-root testing with custom installation directory

### Changed
- Refactored clone logic to use source type detection
- Updated help text with comprehensive source type documentation

## v0.32 - 2026-01-19

### Added
- Add `--version` and `--verbose` to homestak.sh CLI (#22, #23)
- Add `--help` to install.sh (#22)
- Git-derived version pattern (no hardcoded VERSION constants)

## v0.31 - 2026-01-19

- Release alignment with homestak v0.31

## v0.30 - 2026-01-18

### Fixed
- Fix site-init corrupts secrets.yaml indentation (#21)
  - Replace sed-based YAML manipulation with Python script
  - New `scripts/add-ssh-key.py` uses PyYAML for safe YAML handling
  - Preserves existing file structure and indentation

## v0.29 - 2026-01-18

### Added
- Document sudo requirement for FHS installations in CLAUDE.md

### Known Issues
- site-init corrupts secrets.yaml indentation when adding SSH key (#21)

## v0.28 - 2026-01-18

- Release alignment with homestak v0.28

## v0.27 - 2026-01-17

- Release alignment with homestak v0.27

## v0.26 - 2026-01-17

### Changed
- **BREAKING**: Remove /opt/homestak legacy fallback (#17)
  - FHS paths (`/usr/local/...`) are now required
  - Existing installations at `/opt/homestak` must re-bootstrap

### Added
- Auto-add SSH key to secrets.yaml during site-init (#18)
  - Automatically detects SSH public key after generation
  - Adds to `ssh_keys:` section using `user@host` convention
  - Skips if key already exists (idempotent)

### Fixed
- Fix images list to recognize multipart files (#19)
  - Now displays split images (e.g., debian-13-pve) with "(multipart: N parts)" indicator
  - Previously only showed whole `.qcow2` files

## v0.25 - 2026-01-16

- Release alignment with homestak v0.25

## v0.24 - 2026-01-16

### Changed
- **BREAKING**: Refactor to FHS-compliant installation paths (#14)
  - Code repos now installed to `/usr/local/lib/homestak/`
  - Site-config now installed to `/usr/local/etc/homestak/`
  - CLI symlinked from `/usr/local/bin/homestak` to source
- Extract `homestak` CLI into standalone `homestak.sh` script (#14)
  - Enables independent CLI updates via `homestak update`
  - CLI auto-updates when bootstrap repo is pulled
- Add `bootstrap` repo to installation (cloned alongside other code repos)
- Legacy path support: CLI falls back to `/opt/homestak` if FHS paths don't exist

### Added
- Add bats unit tests for homestak.sh (#15)
  - 20 tests covering CLI routing, path detection, and error handling
  - New `make test` target for running tests
- Enhance `homestak update` command with new options (#13)
  - `--dry-run` - preview available updates without applying
  - `--version <tag>` - checkout specific version tag across all repos
  - `--stash` - automatically stash uncommitted changes before updating
  - Shows success/failure counts and handles dirty repos gracefully
- Add `homestak preflight` command for pre-scenario validation
  - Verifies bootstrap installation, site-init completion, PVE connectivity
  - Supports local (default) and remote host checks
  - Works with iac-driver's `--preflight` flag
- Add `homestak site-init` command for site configuration initialization (#10)
  - Generates host config via `make host-config`
  - Generates node config if PVE is installed
  - Creates SSH key (ed25519) if missing
  - Decrypts secrets if encrypted file exists
  - Supports `--force` to overwrite existing configs
- Add `homestak images` command for packer image management (#11)
  - `images list [--version <tag>]` - list available images from GitHub release
  - `images download <targets...> [--version <tag>] [--overwrite] [--publish]` - download images
  - `images publish [<targets...>] [--overwrite]` - install images to PVE storage
  - Downloads to `/var/tmp/homestak/images/` for persistence
  - Supports split file reassembly for large images
  - Graceful resume with curl `-C -` for interrupted downloads

## v0.18 - 2026-01-13

- Release alignment with homestak v0.18

## v0.16 - 2026-01-11

- Release alignment with homestak v0.16

## v0.13 - 2026-01-10

- Release alignment with homestak-dev v0.13

## v0.12 - 2025-01-09

- Release alignment with homestak-dev v0.12

## v0.11 - 2026-01-08

- Release alignment with iac-driver v0.11

## v0.10 - 2026-01-08

### Documentation

- Fix CLAUDE.md: correct dependency table (ansible-core via pipx, python3-yaml, tofu package name)

### Housekeeping

- Add LICENSE file (Apache 2.0)
- Add standard repository topics
- Add branch protection
- Enable secret scanning and Dependabot

## v0.9 - 2026-01-07

### Documentation

- Update scenario name: `pve-configure` → `pve-setup`

### Housekeeping

- Version alignment with unified versioning scheme (skip from v0.6 to v0.9)

## v0.6.0-rc1 - 2026-01-06

Version alignment release - no functional changes.

Aligns with v0.6.0-rc1 releases across all homestak repositories.

## v0.5.0-rc1 - 2026-01-04

Consolidated pre-release - unified entry point.

### Highlights

- curl|bash installation of full stack
- homestak CLI for unified operations
- site-config integration with secrets management

### Features

- Add [site-config](https://github.com/homestak-dev/site-config) to core modules
- Add `secrets` CLI command for site-config management (decrypt, encrypt, check, validate)

### Changes

- Clone site-config as part of bootstrap workflow
- Run `make setup` for site-config after clone

## v0.1.0-rc1 - 2026-01-03

### Features

- One-command bootstrap via curl|bash
- Install core repos: ansible, iac-driver, tofu
- `homestak` CLI with playbook and scenario support
- Optional user creation via `HOMESTAK_USER` env var
- Optional auto-apply via `HOMESTAK_APPLY` env var
