# TODO

Actionable items to complete before v1.0.0 release.

## Critical (Must Do)

- [ ] **Test deployment scenarios end-to-end**
  - [ ] Bare-bones (built-in TFTP)
  - [ ] With netboot.xyz integration
  - [ ] HTTP-only mode
  - [ ] Verify all docker-compose examples work

- [ ] **Document operational workflows** (`docs/operations/`)
  - [ ] Answer file lifecycle (create, test, deploy, rollback)
  - [ ] Asset management (rebuilding when answer-url changes)
  - [ ] Best practices: Use DNS names for answer-url, not IPs
  - [ ] Multi-environment patterns (dev/staging/prod)

- [ ] **Provide deployment workflow examples** (`examples/workflows/`)
  - [ ] GitOps workflow (Git repo + GitHub Actions)
  - [ ] Simple deployment scripts (validate + rsync/scp)
  - [ ] Ansible playbook example

- [ ] **Add answer file validation**
  - [ ] Script to validate TOML syntax
  - [ ] Script to check Proxmox schema requirements
  - [ ] Document validation workflow

## Important (Should Do)

- [ ] **Review and merge `feature/docs-cleanup` PR**
  - All documentation complete
  - Examples fixed
  - License added

- [ ] **Research Proxmox answer URL override**
  - Can kernel parameters override baked answer-url?
  - Document findings in operational-workflows.md

- [ ] **Add monitoring guidance**
  - Log analysis for debugging
  - Key metrics to track (boots, failures)
  - Health check integration

- [ ] **Security documentation**
  - Network isolation best practices
  - Answer file security (credentials, sensitive data)
  - TLS/HTTPS considerations

## Nice to Have

- [ ] **CLI tool for answer management** (`pxe-pilot-ctl`)
  - Only if operational workflow docs prove insufficient
  - Wait for real-world usage feedback

- [ ] **Integration tests**
  - Sandbox-based full boot chain tests
  - Validate answer file serving
  - Test dynamic menu generation

- [ ] **Performance testing**
  - How many simultaneous boots?
  - Network bandwidth requirements
  - Document results

- [ ] **CONTRIBUTING.md**
  - Code style
  - PR process
  - Testing requirements

## Future Considerations (Post-1.0)

- [ ] Web UI for answer file management
- [ ] API endpoints for programmatic access
- [ ] Metrics/observability (Prometheus format)
- [ ] Builder as a service (auto-rebuild on changes)
- [ ] Kubernetes deployment examples
- [ ] High availability setup guide

---

**Decision Principle:** Document first, build tools only if real demand emerges.

**Priority:** Operational maturity > New features
