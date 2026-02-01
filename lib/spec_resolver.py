#!/usr/bin/env python3
"""
Spec resolver for homestak serve.

Loads specs from site-config/v2/specs/ and resolves foreign key references
to postures and secrets.
"""

import os
import logging
from pathlib import Path
from typing import Optional

import yaml

logger = logging.getLogger(__name__)


class SpecError(Exception):
    """Base exception for spec resolution errors."""

    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message
        super().__init__(f"{code}: {message}")


class SpecNotFoundError(SpecError):
    """Spec file not found."""

    def __init__(self, identity: str):
        super().__init__("E200", f"Spec not found: {identity}")


class PostureNotFoundError(SpecError):
    """Posture file not found."""

    def __init__(self, posture: str):
        super().__init__("E201", f"Posture not found: {posture}")


class SSHKeyNotFoundError(SpecError):
    """SSH key not found in secrets."""

    def __init__(self, key_id: str):
        super().__init__("E202", f"SSH key not found: {key_id}")


class SchemaValidationError(SpecError):
    """Schema validation failed."""

    def __init__(self, message: str):
        super().__init__("E400", f"Schema validation failed: {message}")


def discover_etc_path() -> Path:
    """
    Discover the site-config path.

    Priority:
    1. HOMESTAK_ETC environment variable
    2. ../site-config/ sibling (dev workspace)
    3. /usr/local/etc/homestak/ (FHS bootstrap)
    4. /opt/homestak/site-config/ (legacy bootstrap)

    Returns:
        Path to site-config directory

    Raises:
        SpecError: If no valid path found
    """
    # Check environment variable first
    if env_path := os.environ.get("HOMESTAK_ETC"):
        path = Path(env_path)
        if path.is_dir():
            return path

    # Check sibling directory (dev workspace)
    script_dir = Path(__file__).resolve().parent.parent.parent
    sibling = script_dir / "site-config"
    if sibling.is_dir():
        return sibling

    # Check FHS path
    fhs_path = Path("/usr/local/etc/homestak")
    if fhs_path.is_dir():
        return fhs_path

    # Check legacy path
    legacy_path = Path("/opt/homestak/site-config")
    if legacy_path.is_dir():
        return legacy_path

    raise SpecError("E500", "Cannot find site-config directory")


class SpecResolver:
    """Resolves specs from site-config with FK expansion."""

    def __init__(self, etc_path: Optional[Path] = None):
        """
        Initialize resolver.

        Args:
            etc_path: Path to site-config. Auto-discovered if not provided.
        """
        self.etc_path = etc_path or discover_etc_path()
        self._spec_cache: dict = {}
        self._posture_cache: dict = {}
        self._secrets: Optional[dict] = None
        self._site: Optional[dict] = None

    def clear_cache(self):
        """Clear all caches (called on SIGHUP)."""
        self._spec_cache.clear()
        self._posture_cache.clear()
        self._secrets = None
        self._site = None
        logger.info("Cache cleared")

    def _load_yaml(self, path: Path) -> dict:
        """Load YAML file."""
        with open(path, "r") as f:
            return yaml.safe_load(f) or {}

    def _load_secrets(self) -> dict:
        """Load secrets.yaml (cached)."""
        if self._secrets is None:
            secrets_path = self.etc_path / "secrets.yaml"
            if not secrets_path.exists():
                raise SpecError("E500", f"Secrets file not found: {secrets_path}")
            self._secrets = self._load_yaml(secrets_path)
        return self._secrets

    def _load_site(self) -> dict:
        """Load site.yaml (cached)."""
        if self._site is None:
            site_path = self.etc_path / "site.yaml"
            if site_path.exists():
                self._site = self._load_yaml(site_path)
            else:
                self._site = {}
        return self._site

    def _load_posture(self, name: str) -> dict:
        """Load posture by name (cached)."""
        if name not in self._posture_cache:
            posture_path = self.etc_path / "v2" / "postures" / f"{name}.yaml"
            if not posture_path.exists():
                raise PostureNotFoundError(name)
            self._posture_cache[name] = self._load_yaml(posture_path)
        return self._posture_cache[name]

    def _load_spec(self, identity: str) -> dict:
        """Load raw spec by identity."""
        spec_path = self.etc_path / "v2" / "specs" / f"{identity}.yaml"
        if not spec_path.exists():
            raise SpecNotFoundError(identity)
        return self._load_yaml(spec_path)

    def _resolve_ssh_keys(self, key_refs: list) -> list:
        """Resolve SSH key references to actual keys."""
        secrets = self._load_secrets()
        ssh_keys = secrets.get("ssh_keys", {})
        resolved = []

        for ref in key_refs:
            # Handle both "ssh_keys.keyname" and "keyname" formats
            key_id = ref.replace("ssh_keys.", "") if ref.startswith("ssh_keys.") else ref
            if key_id not in ssh_keys:
                raise SSHKeyNotFoundError(key_id)
            resolved.append(ssh_keys[key_id])

        return resolved

    def _apply_site_defaults(self, spec: dict) -> dict:
        """Apply site.yaml defaults to spec."""
        site = self._load_site()
        defaults = site.get("defaults", {})

        # Apply identity defaults
        if "identity" not in spec:
            spec["identity"] = {}
        if "domain" not in spec.get("identity", {}) and "domain" in defaults:
            spec["identity"]["domain"] = defaults["domain"]

        # Apply config defaults
        if "config" not in spec:
            spec["config"] = {}
        if "timezone" not in spec.get("config", {}) and "timezone" in defaults:
            spec["config"]["timezone"] = defaults["timezone"]

        return spec

    def resolve(self, identity: str) -> dict:
        """
        Resolve spec by identity with all FK expansion.

        Args:
            identity: Spec identifier (e.g., "base", "pve")

        Returns:
            Fully resolved spec with FKs expanded

        Raises:
            SpecNotFoundError: Spec file not found
            PostureNotFoundError: Posture not found
            SSHKeyNotFoundError: SSH key not found
        """
        # Check cache first
        if identity in self._spec_cache:
            return self._spec_cache[identity]

        # Load raw spec
        spec = self._load_spec(identity)

        # Apply site defaults
        spec = self._apply_site_defaults(spec)

        # Set identity.hostname if not specified
        if "identity" not in spec:
            spec["identity"] = {}
        if "hostname" not in spec["identity"]:
            spec["identity"]["hostname"] = identity

        # Resolve posture FK
        posture_name = spec.get("access", {}).get("posture", "dev")
        posture = self._load_posture(posture_name)

        # Merge posture settings into access (posture values as defaults)
        if "access" not in spec:
            spec["access"] = {}
        spec["access"]["_posture"] = posture  # Include full posture for auth checks

        # Resolve SSH key FKs in users
        users = spec.get("access", {}).get("users", [])
        for user in users:
            if "ssh_keys" in user:
                user["ssh_keys"] = self._resolve_ssh_keys(user["ssh_keys"])

        # Cache and return
        self._spec_cache[identity] = spec
        return spec

    def get_auth_method(self, identity: str) -> str:
        """
        Get the auth method for a spec.

        Args:
            identity: Spec identifier

        Returns:
            Auth method: "network", "site_token", or "node_token"
        """
        spec = self.resolve(identity)
        posture = spec.get("access", {}).get("_posture", {})
        return posture.get("auth", {}).get("method", "network")

    def get_site_token(self) -> Optional[str]:
        """Get the site token from secrets."""
        secrets = self._load_secrets()
        return secrets.get("auth", {}).get("site_token")

    def get_node_token(self, identity: str) -> Optional[str]:
        """Get the node token for a specific identity."""
        secrets = self._load_secrets()
        return secrets.get("auth", {}).get("node_tokens", {}).get(identity)

    def list_specs(self) -> list:
        """List available spec identities."""
        specs_dir = self.etc_path / "v2" / "specs"
        if not specs_dir.exists():
            return []
        return [p.stem for p in specs_dir.glob("*.yaml")]
