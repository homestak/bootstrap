# Changelog

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
