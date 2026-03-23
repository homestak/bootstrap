#!/usr/bin/env python3
"""Set a default value in site.yaml if the field is currently empty.

Usage: set-site-defaults.py <site_yaml_path> <dotted_key> <value> [--force]

Exit codes:
  0 = value written
  1 = error
  2 = field already has a non-empty value (skipped)

Examples:
  set-site-defaults.py site.yaml defaults.gateway 10.0.12.1
  set-site-defaults.py site.yaml defaults.dns_servers '["10.0.12.1"]'
  set-site-defaults.py site.yaml defaults.domain home.arpa
  set-site-defaults.py site.yaml defaults.gateway 10.0.12.1 --force
"""

import json
import sys

try:
    import yaml
except ImportError:
    print("Error: PyYAML not installed. Run: apt install python3-yaml", file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) < 4:
        print(f"Usage: {sys.argv[0]} <site_yaml> <dotted_key> <value> [--force]",
              file=sys.stderr)
        sys.exit(1)

    site_yaml_path = sys.argv[1]
    dotted_key = sys.argv[2]
    raw_value = sys.argv[3]
    force = "--force" in sys.argv

    # Parse the value — try JSON first (for lists like dns_servers), fall back to string
    try:
        value = json.loads(raw_value)
    except (json.JSONDecodeError, ValueError):
        value = raw_value

    # Load site.yaml
    try:
        with open(site_yaml_path, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except FileNotFoundError:
        print(f"Error: {site_yaml_path} not found", file=sys.stderr)
        sys.exit(1)

    # Navigate to the parent key
    keys = dotted_key.split(".")
    parent = data
    for key in keys[:-1]:
        if key not in parent or not isinstance(parent[key], dict):
            parent[key] = {}
        parent = parent[key]

    field = keys[-1]

    # Check if field already has a non-empty value
    current = parent.get(field)
    if not force and current is not None and current != "" and current != []:
        sys.exit(2)

    # Set the value
    parent[field] = value

    # Write back
    with open(site_yaml_path, "w", encoding="utf-8") as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)

    sys.exit(0)


if __name__ == "__main__":
    main()
