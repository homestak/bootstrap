# Getting Started

How to develop, test, and work with the bootstrap repo.

## Prerequisites

Install test and lint dependencies:

```bash
sudo make install-deps    # Installs shellcheck, bats, gh
```

## Testing

### Running the test suite

```bash
make test     # Runs bats tests in tests/
make lint     # Runs shellcheck on install and homestak scripts
```

The bats test suite (`tests/homestak.bats`) validates the homestak CLI:

- Basic invocation (help, version, no-args behavior)
- Command routing (known commands dispatch correctly, unknown commands fail)
- Subcommand validation (images, secrets, install, spec, update)
- Argument parsing (mutually exclusive flags, required arguments)
- Path detection (HOMESTAK_ROOT derivation)

### Testing with HOMESTAK_DEST

The `HOMESTAK_DEST` environment variable redirects the entire installation to
a custom directory. This is the primary mechanism for testing install changes
without a real host:

```bash
export HOMESTAK_DEST=/tmp/test-install
mkdir -p "$HOMESTAK_DEST"
./install --source github --ref master
```

When `HOMESTAK_DEST` is set:

- The root check (`EUID -ne 0`) is bypassed, so tests run unprivileged
- All repos clone into `$HOMESTAK_DEST/` instead of `/home/homestak/`
- PATH setup writes to `$HOMESTAK_DEST/.profile`

This allows full end-to-end testing of the install script on a development
machine without creating a system user or modifying system directories.

### Testing the CLI in isolation

The bats tests create a temporary directory structure via `setup()`:

```bash
export HOMESTAK_ROOT="$(mktemp -d)"
mkdir -p "$HOMESTAK_ROOT/iac" "$HOMESTAK_ROOT/config" "$HOMESTAK_ROOT/bootstrap"
```

This lets each test run against a minimal filesystem without cloning real
repos. Tests verify command routing and argument parsing, not infrastructure
operations.

### Remote install testing

`tests/test-install-remote.sh` tests the install script against a real remote
host via SSH. This is an integration test that requires a target machine and is
not part of `make test`.

## The homestak CLI

After bootstrap, the `homestak` command is the primary interface. It lives at
`~/bootstrap/homestak` and is added to PATH via `~/.profile`.

### Command reference

| Command | Purpose |
|---------|---------|
| `homestak status` | Show installed repos, branches, and tool versions |
| `homestak update [--dry-run\|--version\|--branch]` | Pull latest for all repos |
| `homestak site-init [--force]` | Generate host/node configs, create SSH keys |
| `homestak preflight [host]` | Run preflight checks |
| `homestak scenario <name> [args]` | Run any iac-driver scenario |
| `homestak pve-setup` / `pve-install` / `user` | Scenario shortcuts |
| `homestak secrets <decrypt\|encrypt\|check>` | Manage secrets |
| `homestak images <list\|download\|publish>` | Manage packer images |
| `homestak spec get --server <url>` | Fetch VM spec from server |
| `homestak install packer` | Install optional packer module |

## Development Workflow

### Modifying the install script

1. Edit `install`
2. Run `make lint` to check for shellcheck issues
3. Test with `HOMESTAK_DEST`:
   ```bash
   HOMESTAK_DEST=/tmp/test-install ./install
   ls /tmp/test-install/    # Verify directory structure
   ```
4. Run `make test` to verify CLI behavior

### Modifying the CLI

1. Edit `homestak`
2. Run `make lint`
3. Run `make test` -- bats tests cover command routing and argument parsing
4. For manual testing, set `HOMESTAK_ROOT` to a temp directory:
   ```bash
   HOMESTAK_ROOT=/tmp/test-cli ./homestak status
   ```

### Adding a new CLI command

1. Add the command to `usage()` in `homestak`
2. Add a case in the main dispatch block
3. Add bats tests in `tests/homestak.bats`
4. Run `make test && make lint`

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `HOMESTAK_ROOT` | `$HOME` | Base directory for all paths |
| `HOMESTAK_DEST` | `/home/homestak` | Override home directory (testing) |
| `HOMESTAK_SERVER` | (none) | Installation source URL |
| `HOMESTAK_REF` | `master` | Git ref for repo clones |
| `HOMESTAK_TOKEN` | (none) | Auth token for HTTP sources |
| `HOMESTAK_INSECURE` | (none) | Skip TLS verification |
| `HOMESTAK_BOOT_SCENARIO` | (none) | Scenario to run after bootstrap |
| `HOMESTAK_BRANCH` | `master` | Git branch for all repos |
