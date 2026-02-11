# Project Instructions for Claude

## Development Workflow

### Branching Strategy

- **Never commit directly to `main`** - Always use feature branches
- Create feature branches from main: `feature/<description>`
- Examples: `feature/add-validation`, `feature/fix-loop-device-error`
- Push branches and create PRs for all changes (code, docs, config)

### Issue Tracking

- **Use GitHub Issues for all work items** - bugs, features, investigations, tasks
- When discovering issues during work, create a GitHub Issue immediately
- Do NOT maintain or update `TODO.md` - track work in Issues instead
- Reference issues in commits: `Fixes #5`, `Closes #12`, `Related to #7`
- Add appropriate labels: `bug`, `enhancement`, `documentation`, etc.

### Pull Request Workflow

1. Create feature branch
2. Make changes and commit
3. Push branch to origin
4. Create PR with descriptive title and summary
5. Wait for review/approval (or self-merge if authorized)
6. Delete feature branch after merge

## Git Commit Guidelines

- Do not add "Co-Authored-By: Claude" to commit messages
- Use conventional commit format: `type(scope): description`
- Keep commit messages concise and descriptive
- Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`
