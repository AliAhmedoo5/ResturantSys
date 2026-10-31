## Core Workflow & Engineering Rules

### 1. Remote CI/CD & Build Execution (Zero Local Framework Builds)
- Every Flutter or any other framework-related process (building, packaging, compilation, running builds, running tests) **MUST** be executed via **GitHub Actions**, never on the local machine.
- The local machine is strictly for editing, git operations, and lightweight configuration tasks. All framework compilation and build artifact generation belong in remote CI/CD workflows.

### 2. Mandatory Context7 Usage
- For standardized code, idiomatic architecture, SDK APIs, and best-practice techniques, **ALWAYS** consult **Context7 MCP** without exception before implementing or refactoring.
- Do not rely on unverified assumptions or memory for framework implementations; verify through Context7 first.

### 3. Fail-Fast & Recover-First Remote CI Feedback Loop
- **Remote TDD Cadence:** When implementing tickets or bugfixes (via Matt Pocock's skills like `implement` or `tdd`), use GitHub Actions as the remote compilation and testing engine.
- **Fast Gatekeeper (< 45s):** The `analyze` job fails fast on any syntax errors, type mismatches, or missing arguments. Inspect failures immediately via `gh run view --log-failed`, patch the code, and re-push.
- **Rapid Recovery Cycle:** If any test fails, CI fails fast and aborts remaining work. Fetch the exact failure logs, patch the logic or edge case, and push. Obsolete in-flight CI runs are automatically terminated via `cancel-in-progress`.
- **Targeted Test Execution:** When testing single files or tickets during development, trigger `workflow_dispatch` with `test_paths` (`gh workflow run ci.yml -f test_paths="test/path/to_test.dart"`). The primary runner will execute only that test file in ~40 seconds.
- **Parallel Regression:** Full test regression runs across 4 parallel shards, finishing all 138 test files in ~5 minutes.

## Agent skills

### Issue tracker

GitHub Issues via `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical 5-role triage vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout. See `docs/agents/domain.md`.
