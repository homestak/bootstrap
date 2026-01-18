#!/usr/bin/env python3
"""
Add an SSH public key to secrets.yaml safely.

Uses PyYAML for proper YAML manipulation to avoid indentation corruption.
"""

import sys
import yaml

def add_ssh_key(secrets_file: str, key_id: str, pub_key: str) -> bool:
    """
    Add an SSH public key to secrets.yaml under ssh_keys section.

    Args:
        secrets_file: Path to secrets.yaml
        key_id: Key identifier (e.g., root@father)
        pub_key: Full public key string

    Returns:
        True if key was added, False if already exists
    """
    # Read existing secrets
    with open(secrets_file, 'r') as f:
        data = yaml.safe_load(f) or {}

    # Initialize ssh_keys section if missing
    if 'ssh_keys' not in data:
        data['ssh_keys'] = {}

    # Check if key already exists by content
    key_content = pub_key.split()[1] if len(pub_key.split()) > 1 else pub_key
    for existing_key in data['ssh_keys'].values():
        if key_content in str(existing_key):
            return False

    # Add the new key
    data['ssh_keys'][key_id] = pub_key

    # Write back with proper formatting
    with open(secrets_file, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

    return True


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <secrets_file> <key_id> <pub_key>", file=sys.stderr)
        sys.exit(1)

    secrets_file = sys.argv[1]
    key_id = sys.argv[2]
    pub_key = sys.argv[3]

    try:
        if add_ssh_key(secrets_file, key_id, pub_key):
            print(f"Added SSH key: {key_id}")
            sys.exit(0)
        else:
            print(f"SSH key already exists")
            sys.exit(2)
    except FileNotFoundError:
        print(f"Secrets file not found: {secrets_file}", file=sys.stderr)
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"YAML error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
