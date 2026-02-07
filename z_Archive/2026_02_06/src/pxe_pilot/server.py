"""HTTP server for pxe-pilot answer file service."""

import json
import logging
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any

from .answer import AnswerFileError, generate_answer_toml
from .config import ConfigLoader, normalize_mac

logger = logging.getLogger(__name__)


class AnswerRequestHandler(BaseHTTPRequestHandler):
    """HTTP request handler for the answer file endpoint."""

    config_loader: ConfigLoader  # Set by the server

    def log_message(self, format: str, *args: Any) -> None:
        """Override to use Python logging."""
        logger.info("%s - %s", self.address_string(), format % args)

    def do_GET(self) -> None:
        """Handle GET requests."""
        if self.path == "/health":
            self._send_response(200, "application/json", '{"status": "ok"}')
        elif self.path == "/hosts":
            hosts = self.config_loader.list_hosts()
            self._send_response(200, "application/json", json.dumps({"hosts": hosts}))
        else:
            self._send_error(404, "Not Found")

    def do_POST(self) -> None:
        """Handle POST requests."""
        if self.path == "/answer":
            self._handle_answer_request()
        else:
            self._send_error(404, "Not Found")

    def _handle_answer_request(self) -> None:
        """Handle POST /answer request from Proxmox installer."""
        # Read request body
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length == 0:
            self._send_error(400, "Missing request body")
            return

        body = self.rfile.read(content_length)

        try:
            data = json.loads(body)
        except json.JSONDecodeError as e:
            logger.error("Invalid JSON in request: %s", e)
            self._send_error(400, f"Invalid JSON: {e}")
            return

        # Extract MAC address from network interfaces
        mac = self._extract_mac(data)
        if mac is None:
            self._send_error(400, "No MAC address found in request")
            return

        logger.info("Received answer request for MAC: %s", mac)

        # Load and merge configuration
        try:
            config = self.config_loader.get_config_for_mac(mac)
        except ValueError as e:
            logger.error("Invalid MAC address: %s", e)
            self._send_error(400, str(e))
            return
        except Exception as e:
            logger.error("Error loading config for MAC %s: %s", mac, e)
            self._send_error(500, f"Error loading config: {e}")
            return

        if not config:
            logger.warning("No configuration found for MAC: %s", mac)
            self._send_error(404, f"No configuration found for MAC: {mac}")
            return

        # Generate answer file
        try:
            answer_toml = generate_answer_toml(config, strict=True)
        except AnswerFileError as e:
            logger.error("Error generating answer file for MAC %s: %s", mac, e)
            self._send_error(500, str(e))
            return

        logger.info("Serving answer file for MAC: %s", mac)
        self._send_response(200, "application/toml", answer_toml)

    def _extract_mac(self, data: dict[str, Any]) -> str | None:
        """Extract the first MAC address from the request data.

        Proxmox installer sends network_interfaces with MAC addresses.
        """
        interfaces = data.get("network_interfaces", [])

        if not interfaces:
            # Try alternative field names
            interfaces = data.get("interfaces", [])

        if not interfaces:
            # Check for direct mac field
            if "mac" in data:
                return data["mac"]
            return None

        # Get the first interface's MAC
        for interface in interfaces:
            if "mac" in interface:
                return interface["mac"]

        return None

    def _send_response(self, status: int, content_type: str, body: str) -> None:
        """Send an HTTP response."""
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body.encode())

    def _send_error(self, status: int, message: str) -> None:
        """Send an error response."""
        body = json.dumps({"error": message})
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body.encode())


def create_handler(config_loader: ConfigLoader) -> type[AnswerRequestHandler]:
    """Create a request handler class with the config loader attached."""

    class Handler(AnswerRequestHandler):
        pass

    Handler.config_loader = config_loader
    return Handler


def run_server(config_dir: Path | str, host: str = "0.0.0.0", port: int = 8080) -> None:
    """Run the pxe-pilot HTTP server."""
    config_loader = ConfigLoader(config_dir)
    handler = create_handler(config_loader)

    server = HTTPServer((host, port), handler)
    logger.info("Starting pxe-pilot server on %s:%d", host, port)
    logger.info("Config directory: %s", config_dir)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down server")
        server.shutdown()
