# CI/CD Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement GitHub Actions workflows for automated testing, building, and publishing of pxe-pilot Docker images.

**Architecture:** Two separate workflows - one for continuous integration (tests/lint on every PR/push) and one for releases (build/push images on git tags). Both workflows use standard GitHub Actions with Docker buildx for multi-platform support.

**Tech Stack:** GitHub Actions, Docker, pytest, ruff, GitHub Container Registry (ghcr.io)

---

## Task 1: Create GitHub Actions Directory Structure

**Files:**
- Create: `.github/workflows/`

**Step 1: Create workflows directory**

```bash
mkdir -p .github/workflows
```

**Step 2: Verify directory exists**

Run: `ls -la .github/`
Expected: Directory `workflows/` exists

**Step 3: Commit directory structure**

```bash
git add .github/
git commit -m "ci: add GitHub Actions directory"
```

---

## Task 2: Create CI Workflow for Testing and Linting

**Files:**
- Create: `.github/workflows/ci.yml`

**Step 1: Write CI workflow file**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    name: Test Server
    runs-on: ubuntu-latest

    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Set up Python 3.12
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'
          cache: 'pip'

      - name: Install dependencies
        working-directory: ./server
        run: |
          pip install -r requirements.txt
          pip install -r ../requirements-dev.txt

      - name: Run tests with coverage
        working-directory: ./server
        run: |
          pytest tests/ -v --cov=. --cov-report=term-missing

      - name: Check test coverage
        working-directory: ./server
        run: |
          pytest tests/ --cov=. --cov-report=json
          python -c "import json; cov = json.load(open('coverage.json')); exit(0 if cov['totals']['percent_covered'] >= 80 else 1)"

  lint:
    name: Lint Server Code
    runs-on: ubuntu-latest

    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Set up Python 3.12
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install ruff
        run: pip install ruff

      - name: Run ruff check
        run: ruff check server/

      - name: Run ruff format check
        run: ruff format --check server/
```

**Step 2: Verify YAML syntax**

Run: `cat .github/workflows/ci.yml | head -20`
Expected: File displays correctly with proper YAML indentation

**Step 3: Commit CI workflow**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add test and lint workflow"
```

---

## Task 3: Create Release Workflow for Building and Publishing Images

**Files:**
- Create: `.github/workflows/release.yml`

**Step 1: Write release workflow file**

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*.*.*'

env:
  REGISTRY: ghcr.io
  SERVER_IMAGE_NAME: ${{ github.repository }}-server
  BUILDER_IMAGE_NAME: ${{ github.repository }}-builder

jobs:
  build-and-push-server:
    name: Build and Push Server Image
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract version from tag
        id: meta
        run: |
          VERSION=${GITHUB_REF#refs/tags/v}
          echo "version=${VERSION}" >> $GITHUB_OUTPUT
          echo "major=$(echo $VERSION | cut -d. -f1)" >> $GITHUB_OUTPUT
          echo "minor=$(echo $VERSION | cut -d. -f1-2)" >> $GITHUB_OUTPUT

      - name: Build and push server image
        uses: docker/build-push-action@v5
        with:
          context: ./server
          file: ./server/Dockerfile
          push: true
          tags: |
            ${{ env.REGISTRY }}/${{ env.SERVER_IMAGE_NAME }}:latest
            ${{ env.REGISTRY }}/${{ env.SERVER_IMAGE_NAME }}:${{ steps.meta.outputs.version }}
            ${{ env.REGISTRY }}/${{ env.SERVER_IMAGE_NAME }}:${{ steps.meta.outputs.minor }}
            ${{ env.REGISTRY }}/${{ env.SERVER_IMAGE_NAME }}:${{ steps.meta.outputs.major }}
          labels: |
            org.opencontainers.image.source=${{ github.repositoryUrl }}
            org.opencontainers.image.version=${{ steps.meta.outputs.version }}
            org.opencontainers.image.created=${{ github.event.repository.updated_at }}
            org.opencontainers.image.revision=${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  build-and-push-builder:
    name: Build and Push Builder Image
    runs-on: ubuntu-latest
    needs: build-and-push-server
    permissions:
      contents: read
      packages: write

    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract version from tag
        id: meta
        run: |
          VERSION=${GITHUB_REF#refs/tags/v}
          echo "version=${VERSION}" >> $GITHUB_OUTPUT
          echo "major=$(echo $VERSION | cut -d. -f1)" >> $GITHUB_OUTPUT
          echo "minor=$(echo $VERSION | cut -d. -f1-2)" >> $GITHUB_OUTPUT

      - name: Build and push builder image
        uses: docker/build-push-action@v5
        with:
          context: ./builder
          file: ./builder/Dockerfile
          push: true
          tags: |
            ${{ env.REGISTRY }}/${{ env.BUILDER_IMAGE_NAME }}:latest
            ${{ env.REGISTRY }}/${{ env.BUILDER_IMAGE_NAME }}:${{ steps.meta.outputs.version }}
            ${{ env.REGISTRY }}/${{ env.BUILDER_IMAGE_NAME }}:${{ steps.meta.outputs.minor }}
            ${{ env.REGISTRY }}/${{ env.BUILDER_IMAGE_NAME }}:${{ steps.meta.outputs.major }}
          labels: |
            org.opencontainers.image.source=${{ github.repositoryUrl }}
            org.opencontainers.image.version=${{ steps.meta.outputs.version }}
            org.opencontainers.image.created=${{ github.event.repository.updated_at }}
            org.opencontainers.image.revision=${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  create-release:
    name: Create GitHub Release
    runs-on: ubuntu-latest
    needs: [build-and-push-server, build-and-push-builder]
    permissions:
      contents: write

    steps:
      - name: Check out code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Extract version from tag
        id: meta
        run: |
          VERSION=${GITHUB_REF#refs/tags/v}
          echo "version=${VERSION}" >> $GITHUB_OUTPUT

      - name: Generate release notes
        id: notes
        run: |
          cat > release-notes.md << 'EOF'
          ## Docker Images

          **Server:**
          - `docker pull ${{ env.REGISTRY }}/${{ env.SERVER_IMAGE_NAME }}:${{ steps.meta.outputs.version }}`
          - `docker pull ${{ env.REGISTRY }}/${{ env.SERVER_IMAGE_NAME }}:latest`

          **Builder:**
          - `docker pull ${{ env.REGISTRY }}/${{ env.BUILDER_IMAGE_NAME }}:${{ steps.meta.outputs.version }}`
          - `docker pull ${{ env.REGISTRY }}/${{ env.BUILDER_IMAGE_NAME }}:latest`

          ## What's Changed

          EOF

          # Get commits since last tag
          PREV_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")
          if [ -z "$PREV_TAG" ]; then
            git log --pretty=format:"- %s" >> release-notes.md
          else
            git log ${PREV_TAG}..HEAD --pretty=format:"- %s" >> release-notes.md
          fi

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          body_path: release-notes.md
          generate_release_notes: false
          draft: false
          prerelease: false
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Step 2: Verify YAML syntax**

Run: `cat .github/workflows/release.yml | head -30`
Expected: File displays correctly with proper YAML indentation

**Step 3: Commit release workflow**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release workflow for Docker image publishing"
```

---

## Task 4: Update README with CI/CD Badge

**Files:**
- Modify: `README.md` (add after title)

**Step 1: Read current README**

Run: `head -10 README.md`
Expected: See current README title and description

**Step 2: Add CI badge to README**

Add after the `# pxe-pilot` title:

```markdown
# pxe-pilot

![CI Status](https://github.com/WisherOps/pxe-pilot/workflows/CI/badge.svg)

HTTP answer file server for Proxmox VE automated installations.
```

**Step 3: Verify README change**

Run: `head -10 README.md`
Expected: Badge appears after title

**Step 4: Commit README update**

```bash
git add README.md
git commit -m "docs: add CI status badge to README"
```

---

## Task 5: Create .gitignore Entry for Coverage Files

**Files:**
- Modify: `.gitignore`

**Step 1: Check current .gitignore**

Run: `cat .gitignore`
Expected: See existing ignore patterns

**Step 2: Add coverage files to .gitignore**

Append to `.gitignore`:

```
# Test coverage
.coverage
coverage.json
htmlcov/
.pytest_cache/
```

**Step 3: Verify .gitignore**

Run: `tail -10 .gitignore`
Expected: Coverage patterns appear at end

**Step 4: Commit .gitignore update**

```bash
git add .gitignore
git commit -m "chore: ignore test coverage files"
```

---

## Task 6: Test CI Workflow Locally (Verification)

**Files:**
- None (testing only)

**Step 1: Verify pytest works locally**

Run: `cd server && pytest tests/ -v`
Expected: All tests pass

**Step 2: Verify ruff check works**

Run: `ruff check server/`
Expected: No linting errors or warnings displayed

**Step 3: Verify ruff format check works**

Run: `ruff format --check server/`
Expected: All files properly formatted message

**Step 4: Check if workflows are valid**

Run: `ls -la .github/workflows/`
Expected: Both `ci.yml` and `release.yml` exist

---

## Task 7: Push Branch and Create Pull Request

**Files:**
- None (git operations)

**Step 1: Push feature branch**

Run: `git push origin feature/cicd-pipeline`
Expected: Branch pushed successfully

**Step 2: Verify CI workflow runs**

1. Go to GitHub repository
2. Navigate to Actions tab
3. Expected: CI workflow triggers and runs
4. Expected: Test and Lint jobs both complete

**Step 3: Create pull request**

Run:
```bash
gh pr create \
  --title "feat: add CI/CD pipeline with GitHub Actions" \
  --body "## Summary

- Add CI workflow for automated testing and linting
- Add release workflow for Docker image publishing
- Configure multi-tag versioning strategy
- Add CI status badge to README

## Testing

- [x] CI workflow runs successfully on push
- [x] Tests pass locally
- [x] Linting passes locally
- [x] Workflows are valid YAML

## Documentation

See design document: docs/plans/2026-02-10-cicd-pipeline-design.md"
```

Expected: PR created and CI runs automatically

**Step 4: Verify PR status checks**

Expected:
- Test job: PASS
- Lint job: PASS
- PR shows green checkmarks

---

## Task 8: Test Release Workflow (After Merge)

**Files:**
- None (testing only)

**Step 1: Merge PR to main**

After approval, merge the PR:
- Option 1: Use GitHub UI
- Option 2: `gh pr merge --squash`

**Step 2: Create test release tag**

```bash
git checkout main
git pull origin main
git tag v0.1.0
git push origin v0.1.0
```

**Step 3: Monitor release workflow**

1. Go to GitHub Actions tab
2. Expected: Release workflow triggers
3. Expected: Server image builds and pushes
4. Expected: Builder image builds and pushes
5. Expected: GitHub release created

**Step 4: Verify images on ghcr.io**

Check packages at: `https://github.com/orgs/WisherOps/packages`

Expected images:
- `pxe-pilot-server:latest`
- `pxe-pilot-server:0.1.0`
- `pxe-pilot-builder:latest`
- `pxe-pilot-builder:0.1.0`

**Step 5: Test pulling images**

Run:
```bash
docker pull ghcr.io/wisherops/pxe-pilot-server:0.1.0
docker pull ghcr.io/wisherops/pxe-pilot-builder:0.1.0
```

Expected: Images download successfully

**Step 6: Verify GitHub release**

Go to: `https://github.com/WisherOps/pxe-pilot/releases`

Expected:
- Release v0.1.0 exists
- Release notes include Docker pull commands
- Release notes include commit history

---

## Task 9: Update Documentation with Release Process

**Files:**
- Create: `docs/release-process.md`

**Step 1: Write release process documentation**

Create `docs/release-process.md`:

```markdown
# Release Process

## Creating a Release

1. Ensure all changes are merged to main branch
2. Pull latest main: `git checkout main && git pull origin main`
3. Create and push a version tag:
   ```bash
   git tag v1.2.3
   git push origin v1.2.3
   ```
4. GitHub Actions automatically:
   - Builds server and builder Docker images
   - Pushes images to ghcr.io with multiple tags
   - Creates GitHub release with changelog

## Version Tags

Use semantic versioning: `vMAJOR.MINOR.PATCH`

Examples:
- `v1.0.0` - Major release
- `v1.2.3` - Minor/patch release
- `v2.0.0-beta` - Prerelease (marked as prerelease on GitHub)

## Docker Image Tags

Each release creates four tags per image:
- `latest` - Always points to newest stable release
- `1.2.3` - Exact version pin
- `1.2` - Latest patch in minor version
- `1` - Latest minor/patch in major version

## Monitoring Releases

- View workflow progress: github.com/WisherOps/pxe-pilot/actions
- View releases: github.com/WisherOps/pxe-pilot/releases
- View images: github.com/orgs/WisherOps/packages

## Troubleshooting

**Workflow fails to push images:**
- Check repository permissions at Settings > Actions > General
- Ensure "Read and write permissions" enabled for workflows

**Tag already exists:**
- Delete remote tag: `git push origin :refs/tags/v1.2.3`
- Delete local tag: `git tag -d v1.2.3`
- Create new tag with different version

**Build fails:**
- Check Dockerfile syntax
- Verify all COPY paths exist
- Review Actions logs for specific errors
```

**Step 2: Commit documentation**

```bash
git add docs/release-process.md
git commit -m "docs: add release process guide"
```

**Step 3: Push to main**

```bash
git push origin main
```

---

## Task 10: Final Verification and Cleanup

**Files:**
- None (verification only)

**Step 1: Verify all workflows exist**

Run: `ls -la .github/workflows/`
Expected: Both `ci.yml` and `release.yml` present

**Step 2: Verify documentation complete**

Run: `ls -la docs/`
Expected: Design document and release process guide exist

**Step 3: Verify clean working directory**

Run: `git status`
Expected: Nothing to commit, working tree clean

**Step 4: Review commit history**

Run: `git log --oneline -10`
Expected: Clean commit history with conventional commits

**Step 5: Celebrate**

CI/CD pipeline is complete and operational!

---

## Summary

This implementation creates a complete CI/CD pipeline with:
- Automated testing and linting on every PR
- Docker image building and publishing on releases
- Multi-tag versioning strategy
- GitHub releases with changelogs
- Comprehensive documentation

**Total estimated time:** 45-60 minutes

**Dependencies:**
- GitHub repository with Actions enabled
- GitHub Container Registry access
- Existing test suite in server/tests/

**Testing strategy:**
- Local verification before push
- PR triggers CI workflow
- Test release tag triggers full workflow
