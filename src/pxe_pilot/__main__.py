"""CLI entry point for pxe-pilot."""

import argparse
import logging
import os
import sys
from pathlib import Path

from . import __version__
from .server import run_server


def setup_logging(verbose: bool = False) -> None:
    """Configure logging."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        prog="pxe-pilot",
        description="Composable PXE boot config engine for automated Proxmox VE installs",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"pxe-pilot {__version__}",
    )

    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # serve command
    serve_parser = subparsers.add_parser("serve", help="Start the HTTP server")
    serve_parser.add_argument(
        "--config-dir",
        "-c",
        type=Path,
        default=os.environ.get("CONFIG_DIR", "./config"),
        help="Path to config directory (default: ./config or $CONFIG_DIR)",
    )
    serve_parser.add_argument(
        "--host",
        "-H",
        type=str,
        default=os.environ.get("HOST", "0.0.0.0"),
        help="Host to bind to (default: 0.0.0.0 or $HOST)",
    )
    serve_parser.add_argument(
        "--port",
        "-p",
        type=int,
        default=int(os.environ.get("PORT", "8080")),
        help="Port to listen on (default: 8080 or $PORT)",
    )
    serve_parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Enable verbose logging",
    )

    # validate command
    validate_parser = subparsers.add_parser("validate", help="Validate configuration files")
    validate_parser.add_argument(
        "--config-dir",
        "-c",
        type=Path,
        default=os.environ.get("CONFIG_DIR", "./config"),
        help="Path to config directory",
    )
    validate_parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Enable verbose logging",
    )

    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        return 1

    setup_logging(getattr(args, "verbose", False))

    if args.command == "serve":
        return cmd_serve(args)
    elif args.command == "validate":
        return cmd_validate(args)

    return 0


def cmd_serve(args: argparse.Namespace) -> int:
    """Run the serve command."""
    config_dir = Path(args.config_dir)

    if not config_dir.exists():
        logging.error("Config directory does not exist: %s", config_dir)
        return 1

    run_server(config_dir, args.host, args.port)
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    """Run the validate command."""
    from .answer import validate_config
    from .config import ConfigLoader

    config_dir = Path(args.config_dir)
    logger = logging.getLogger(__name__)

    if not config_dir.exists():
        logger.error("Config directory does not exist: %s", config_dir)
        return 1

    loader = ConfigLoader(config_dir)
    hosts = loader.list_hosts()

    if not hosts:
        logger.warning("No host configurations found in %s", config_dir / "hosts")

    errors = 0
    for host in hosts:
        try:
            config = loader.get_config_for_mac(host)
            missing = validate_config(config)

            if missing:
                logger.error("Host %s: missing fields: %s", host, ", ".join(missing))
                errors += 1
            else:
                logger.info("Host %s: valid", host)
        except Exception as e:
            logger.error("Host %s: error loading config: %s", host, e)
            errors += 1

    if errors:
        logger.error("Validation failed with %d error(s)", errors)
        return 1

    logger.info("All configurations valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
