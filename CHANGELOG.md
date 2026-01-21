# Changelog

## Unreleased

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
