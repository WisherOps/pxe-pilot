# Dev Container - CI/CD Parity

This dev container matches the GitHub Actions CI environment exactly, allowing you to catch issues locally before pushing.

## Features

- **Python 3.12** (matches CI)
- **Same dependencies** as CI (requirements.txt + requirements-dev.txt)
- **Pre-configured VS Code tasks** for running CI checks locally

## Quick Start

### Open in Dev Container

1. Install the "Dev Containers" extension in VS Code
2. Press `F1` → "Dev Containers: Reopen in Container"
3. Wait for container to build

### Run CI Checks Locally

Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac) and select:

- **`Tasks: Run Task`** → **`CI: Run All Checks`** - Run tests + linting (recommended)
- **`Tasks: Run Test Task`** → **`CI: Run Tests`** - Run tests only
- **`Tasks: Run Task`** → **`CI: Run Lint`** - Run linting only
- **`Tasks: Run Task`** → **`CI: Fix Linting`** - Auto-fix linting issues

### Or use terminal commands:

```bash
# Run tests (same as CI)
cd server && pytest tests/ -v --cov=. --cov-report=term-missing --cov-fail-under=80

# Run linting (same as CI)
ruff check server/
ruff format --check server/

# Fix linting
ruff check server/ --fix
ruff format server/
```

## CI Parity

This container ensures:
- ✅ Same Python version (3.12)
- ✅ Same dependencies
- ✅ Same test commands
- ✅ Same linting rules
- ✅ Same coverage threshold (80%)

If tests pass locally, they should pass in CI!
