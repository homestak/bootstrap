# Changelog

## Unreleased

### Features

- Add [site-config](https://github.com/homestak-dev/site-config) to core modules
- Add `secrets` CLI command for site-config management (decrypt, encrypt, check)

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
