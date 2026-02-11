# CI/CD Pipeline Design

**Date:** 2026-02-10
**Status:** Approved
**Purpose:** Automate testing, building, and publishing of pxe-pilot Docker images

## Summary

This design establishes a complete CI/CD pipeline for pxe-pilot using GitHub Actions. The pipeline runs tests on every PR, builds Docker images on releases, and publishes them to GitHub Container Registry.

## Goals

1. Run tests and linting on every PR to catch issues early
2. Build and publish Docker images automatically on release tags
3. Create GitHub releases with changelogs and image links
4. Make images available for users to deploy in their own environments

## Architecture

### Components

**Server Image** (`server/`)
- FastAPI HTTP server for Proxmox answer files
- Multi-stage build with iPXE binaries embedded
- Has test suite in `server/tests/`
- Published as `ghcr.io/wisherops/pxe-pilot-server`

**Builder Image** (`builder/`)
- Tool image with Proxmox auto-install-assistant
- Shell scripts for ISO manipulation
- No test suite (validated by successful build)
- Published as `ghcr.io/wisherops/pxe-pilot-builder`

### Workflow Structure

**CI Workflow** (`.github/workflows/ci.yml`)
- Triggers: Every push and pull request
- Runs tests and linting in parallel
- Blocks PR merge if checks fail
- Server tests only (builder validated by build success)

**Release Workflow** (`.github/workflows/release.yml`)
- Triggers: Git tags matching `v*.*.*` pattern
- Builds both images sequentially
- Pushes to GitHub Container Registry
- Creates GitHub release with changelog

## CI Workflow Details

### Test Job

Runs pytest with coverage on the server code.

**Environment:**
- OS: ubuntu-latest
- Python: 3.12 (matches production)
- Working directory: `server/`

**Steps:**
1. Check out repository
2. Set up Python 3.12
3. Install dependencies from `server/requirements.txt` and `requirements-dev.txt`
4. Run `pytest server/tests/ -v --cov=server`
5. Generate coverage report

**Failure condition:** Any test fails or coverage drops below threshold.

### Lint Job

Validates code formatting and style with ruff.

**Environment:**
- OS: ubuntu-latest
- Python: 3.12

**Steps:**
1. Check out repository
2. Set up Python 3.12
3. Install ruff
4. Run `ruff check server/`
5. Run `ruff format --check server/`

**Failure condition:** Any linting errors or formatting violations.

### Job Dependencies

Both jobs run in parallel with no dependencies. PRs cannot merge unless both pass.

## Release Workflow Details

### Server Image Build

**Build context:** `./server`
**Dockerfile:** `server/Dockerfile`
**Platform:** linux/amd64

**Build process:**
- Stage 1: Compiles iPXE binaries (BIOS + UEFI)
- Stage 2: Creates Python server image with binaries

**Optimizations:**
- GitHub Actions cache for Docker layers
- Multi-stage build reduces final image size

### Builder Image Build

**Build context:** `./builder`
**Dockerfile:** `builder/Dockerfile`
**Platform:** linux/amd64

**Build process:**
- Single-stage build with Debian base
- Installs Proxmox auto-install-assistant
- Copies entrypoint and scripts

### Publishing Strategy

Images push to GitHub Container Registry with multiple tags:

**Server tags:**
```
ghcr.io/wisherops/pxe-pilot-server:latest
ghcr.io/wisherops/pxe-pilot-server:1.2.3
ghcr.io/wisherops/pxe-pilot-server:1.2
ghcr.io/wisherops/pxe-pilot-server:1
```

**Builder tags:**
```
ghcr.io/wisherops/pxe-pilot-builder:latest
ghcr.io/wisherops/pxe-pilot-builder:1.2.3
ghcr.io/wisherops/pxe-pilot-builder:1.2
ghcr.io/wisherops/pxe-pilot-builder:1
```

**Tag strategy benefits:**
- `latest` - Always get the newest version
- `1.2.3` - Pin to exact version for production stability
- `1.2` - Receive patch updates automatically
- `1` - Stay on major version, get minor and patch updates

### Image Metadata

Each image includes OCI labels:
- `org.opencontainers.image.source` - GitHub repository URL
- `org.opencontainers.image.version` - Release version
- `org.opencontainers.image.created` - Build timestamp
- `org.opencontainers.image.revision` - Git commit SHA

### Release Creation

After successful image publishing, the workflow creates a GitHub release.

**Release configuration:**
- Name: Same as git tag (e.g., "v1.2.3")
- Tag: Points to tagged commit
- Status: Published
- Prerelease: Auto-detected from version (e.g., v1.2.3-beta)

**Auto-generated changelog includes:**
- Commit messages since last tag
- Direct links to pull both images
- List of contributors
- Link to full diff

**Example release body:**

```markdown
## Docker Images

Server:
- `docker pull ghcr.io/wisherops/pxe-pilot-server:1.2.3`
- `docker pull ghcr.io/wisherops/pxe-pilot-server:latest`

Builder:
- `docker pull ghcr.io/wisherops/pxe-pilot-builder:1.2.3`
- `docker pull ghcr.io/wisherops/pxe-pilot-builder:latest`

## What's Changed
- Add iPXE boot menu by @username
- Fix ISO extraction bug by @username

**Full Changelog**: v1.2.2...v1.2.3
```

## Release Process

To create a new release:

1. Ensure all changes are merged to main
2. Create and push a git tag:
   ```bash
   git tag v1.2.3
   git push origin v1.2.3
   ```
3. GitHub Actions runs automatically
4. Monitor workflow at github.com/wisherops/pxe-pilot/actions
5. Release appears at github.com/wisherops/pxe-pilot/releases
6. Images are available at ghcr.io

## Branch Protection

Configure the main branch to require:
- CI workflow passing before merge
- Optional: Require pull request reviews
- Prevent force pushes

## Authentication

**GitHub Container Registry:**
- Uses automatic `GITHUB_TOKEN`
- No additional secrets required
- Repository owner has push permissions

**Image visibility:**
- Public (anyone can pull)
- No authentication needed for pulls

## Error Handling

**Build failures:**
- Workflow stops immediately
- No partial images pushed
- Build logs available in Actions tab

**Test failures:**
- PR shows failed status check
- Merge blocked until fixed
- Clear error messages in logs

**Tag conflicts:**
- Workflow fails if tag already exists
- Prevents accidental overwrites

## Future Enhancements

**Potential additions:**
- ARM64 builds for Apple Silicon
- Smoke tests for builder scripts
- Vulnerability scanning with Trivy
- Image size optimization tracking
- Deployment to demo environment

## Monitoring

**Workflow status:**
- Check Actions tab for build history
- Email notifications on workflow failures
- Status badges for README

**Image metrics:**
- ghcr.io shows download counts
- GitHub Insights tracks release adoption

## Summary

This CI/CD pipeline provides:
- Automated quality checks on every PR
- Push-button releases via git tags
- Public Docker images on ghcr.io
- Clear documentation via GitHub releases

Users can pull images and deploy pxe-pilot in their own environments without manual build steps.
