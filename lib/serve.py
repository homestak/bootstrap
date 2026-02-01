#!/usr/bin/env python3
"""
HTTP server for homestak spec discovery.

Serves specs from site-config/v2/specs/ with posture-based authentication.
"""

import argparse
import json
import logging
import os
import signal
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Optional
from urllib.parse import urlparse

from .spec_resolver import (
    SpecResolver,
    SpecError,
    SpecNotFoundError,
    PostureNotFoundError,
    SSHKeyNotFoundError,
    SchemaValidationError,
)

logger = logging.getLogger(__name__)

# Default configuration
DEFAULT_PORT = 44443
DEFAULT_BIND = "0.0.0.0"


class SpecHandler(BaseHTTPRequestHandler):
    """HTTP request handler for spec serving."""

    # Class-level resolver (shared across requests)
    resolver: Optional[SpecResolver] = None

    def log_message(self, format: str, *args):
        """Override to use Python logging."""
        logger.info("%s - %s", self.address_string(), format % args)

    def send_json(self, data: dict, status: int = 200):
        """Send JSON response."""
        body = json.dumps(data, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_error_response(self, code: str, message: str, http_status: int):
        """Send error response with error code."""
        self.send_json({"error": {"code": code, "message": message}}, http_status)

    def get_bearer_token(self) -> Optional[str]:
        """Extract Bearer token from Authorization header."""
        auth_header = self.headers.get("Authorization", "")
        if auth_header.startswith("Bearer "):
            return auth_header[7:]
        return None

    def validate_auth(self, identity: str) -> Optional[tuple]:
        """
        Validate authentication for the given identity.

        Returns:
            None if auth is valid, or (code, message, http_status) tuple on failure
        """
        if not self.resolver:
            return ("E500", "Resolver not initialized", 500)

        try:
            auth_method = self.resolver.get_auth_method(identity)
        except SpecNotFoundError as e:
            return (e.code, e.message, 404)
        except SpecError as e:
            return (e.code, e.message, 500)

        if auth_method == "network":
            # Trust network boundary, no token required
            return None

        token = self.get_bearer_token()

        if auth_method == "site_token":
            expected = self.resolver.get_site_token()
            if not expected:
                return ("E500", "site_token not configured in secrets", 500)
            if not token:
                return ("E300", "Authorization required", 401)
            if token != expected:
                return ("E301", "Invalid token", 403)
            return None

        if auth_method == "node_token":
            expected = self.resolver.get_node_token(identity)
            if not expected:
                return ("E500", f"node_token not configured for {identity}", 500)
            if not token:
                return ("E300", "Authorization required", 401)
            if token != expected:
                return ("E301", "Invalid token", 403)
            return None

        return ("E500", f"Unknown auth method: {auth_method}", 500)

    def do_GET(self):
        """Handle GET requests."""
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")

        # Health check endpoint
        if path == "/health":
            self.send_json({"status": "ok"})
            return

        # Spec endpoint: /spec/{identity}
        if path.startswith("/spec/"):
            identity = path[6:]  # Remove "/spec/" prefix
            if not identity:
                self.send_error_response("E101", "Missing identity", 400)
                return

            # Validate auth before accessing spec
            auth_error = self.validate_auth(identity)
            if auth_error:
                self.send_error_response(*auth_error)
                return

            # Resolve and return spec
            try:
                spec = self.resolver.resolve(identity)
                # Remove internal _posture field from response
                if "access" in spec and "_posture" in spec["access"]:
                    spec = dict(spec)
                    spec["access"] = {
                        k: v for k, v in spec["access"].items() if k != "_posture"
                    }
                self.send_json(spec)
            except SpecNotFoundError as e:
                self.send_error_response(e.code, e.message, 404)
            except PostureNotFoundError as e:
                self.send_error_response(e.code, e.message, 404)
            except SSHKeyNotFoundError as e:
                self.send_error_response(e.code, e.message, 404)
            except SchemaValidationError as e:
                self.send_error_response(e.code, e.message, 422)
            except SpecError as e:
                self.send_error_response(e.code, e.message, 500)
            except Exception as e:
                logger.exception("Unexpected error resolving spec")
                self.send_error_response("E500", f"Internal error: {e}", 500)
            return

        # List specs endpoint
        if path == "/specs":
            if not self.resolver:
                self.send_error_response("E500", "Resolver not initialized", 500)
                return
            specs = self.resolver.list_specs()
            self.send_json({"specs": specs})
            return

        # Unknown endpoint
        self.send_error_response("E100", f"Unknown endpoint: {path}", 400)


def create_server(
    bind: str = DEFAULT_BIND,
    port: int = DEFAULT_PORT,
    resolver: Optional[SpecResolver] = None,
) -> HTTPServer:
    """
    Create and configure the HTTP server.

    Args:
        bind: Address to bind to
        port: Port to listen on
        resolver: SpecResolver instance (auto-created if not provided)

    Returns:
        Configured HTTPServer instance
    """
    if resolver is None:
        resolver = SpecResolver()

    # Set resolver on handler class
    SpecHandler.resolver = resolver

    server = HTTPServer((bind, port), SpecHandler)
    return server


def setup_signal_handlers(resolver: SpecResolver):
    """Set up signal handlers for cache management."""

    def handle_sighup(signum, frame):
        """Handle SIGHUP by clearing caches."""
        logger.info("Received SIGHUP, clearing cache")
        resolver.clear_cache()

    signal.signal(signal.SIGHUP, handle_sighup)


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Serve homestak specs over HTTP",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--port",
        "-p",
        type=int,
        default=DEFAULT_PORT,
        help="Port to listen on",
    )
    parser.add_argument(
        "--bind",
        "-b",
        default=DEFAULT_BIND,
        help="Address to bind to",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Enable verbose logging",
    )

    args = parser.parse_args()

    # Configure logging
    level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # Create resolver and server
    try:
        resolver = SpecResolver()
        logger.info("Using site-config at: %s", resolver.etc_path)
    except SpecError as e:
        logger.error("Failed to initialize: %s", e.message)
        sys.exit(1)

    # Set up signal handlers
    setup_signal_handlers(resolver)

    # Create and start server
    server = create_server(bind=args.bind, port=args.port, resolver=resolver)
    logger.info("Starting server on %s:%d", args.bind, args.port)
    logger.info("Available specs: %s", resolver.list_specs())

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down")
        server.shutdown()


if __name__ == "__main__":
    main()
