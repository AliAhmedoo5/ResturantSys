## Core Workflow & Engineering Rules

### 1. Remote CI/CD & Build Execution (Zero Local Framework Builds)
- Every Flutter or any other framework-related process (building, packaging, compilation, running builds, running tests) **MUST** be executed via **GitHub Actions**, never on the local machine.
- The local machine is strictly for editing, git operations, and lightweight configuration tasks. All framework compilation and build artifact generation belong in remote CI/CD workflows.

### 2. Mandatory Context7 Usage
- For standardized code, idiomatic architecture, SDK APIs, and best-practice techniques, **ALWAYS** consult **Context7 MCP** without exception before implementing or refactoring.
- Do not rely on unverified assumptions or memory for framework implementations; verify through Context7 first.

## Agent skills

### Issue tracker

GitHub Issues via `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical 5-role triage vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout. See `docs/agents/domain.md`.
