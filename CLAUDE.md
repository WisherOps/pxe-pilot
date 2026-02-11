# Project Instructions for Claude

## Development Workflow

### Branching Strategy

**Always use feature branches + PRs for:**
- Code changes (`server/`, `builder/`, `scripts/`)
- CI/CD workflows (`.github/workflows/`)
- Docker configurations (`Dockerfile`, `docker-compose.yml`)
- Dependencies (`requirements.txt`, `requirements-dev.txt`)
- New documentation files
- Configuration that affects runtime behavior

**Direct commits to `main` allowed for:**
- `CLAUDE.md` updates (workflow instructions)
- Typo fixes in existing documentation
- `.gitignore` additions
- Comment-only changes
- Minor formatting fixes

**When in doubt, use a PR.**

### Issue Tracking

- **Use GitHub Issues for all work items** - bugs, features, investigations, tasks
- When discovering issues during work, create a GitHub Issue immediately
- Do NOT maintain or update `TODO.md` - track work in Issues instead
- Reference issues in commits: `Fixes #5`, `Closes #12`, `Related to #7`
- Add appropriate labels: `bug`, `enhancement`, `documentation`, etc.

### Pull Request Workflow

1. Create feature branch: `feature/<description>`
2. Make changes and commit with conventional commit format
3. Push branch to origin
4. Create PR with descriptive title and summary
5. Merge when ready (self-merge allowed for maintainers)
6. Delete feature branch after merge

## Git Commit Guidelines

- Do not add "Co-Authored-By: Claude" to commit messages
- Use conventional commit format: `type(scope): description`
- Keep commit messages concise and descriptive
- Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`
