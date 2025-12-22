# Repository Guidelines

## North Star: Modern Apple Development Excellence

**Build best-in-class apps using current Apple patterns and practices.**

### Core Principles:

**Modern-First Architecture**
- SwiftUI, Observable, MainActor, async/await, Structured Concurrency
- RealityKit ECS patterns for spatial computing
- Swift 6 strict concurrency where applicable

**No Legacy Compromises**
- No UIKit fallbacks, no deprecated APIs, no "just in case" backwards compatibility
- Every legacy pattern adds tech debt and confusion
- If it requires old patterns, challenge the requirement

**Fail Fast Philosophy**
- Compiler errors over runtime failures
- Type safety over string-based APIs
- @MainActor annotations over dispatch queue management
- Let the system crash early rather than limp along broken

**Clean Code Standards**
- Lean, purposeful implementations
- No defensive bloat or "AI safety padding"
- No commented-out alternatives or hedge-bet code paths
- Trust modern APIs to work as designed

**Reactive & Declarative**
- Embrace SwiftUI's declarative nature
- Use Observation framework, not ObservableObject
- Combine/AsyncSequence for data flows
- State flows down, actions flow up

**When in doubt: What would Apple's sample code do in 2025?**

## Coding Style & Conventions

- Swift 5.x; targets visionOS 2.0+; tab indentation (use tabs, not spaces).
- Types: `PascalCase`; methods/vars: `camelCase`; constants use `camelCase`.
- Match existing folder structure; keep changes minimal and focused.

## RepoPrompt Tooling (Use These First)

- `get_file_tree type="code_structure"`: quick project map.
- `get_code_structure paths=["RepoPrompt/Services", "RepoPrompt/Models"]`: directory-first overview; prefer directories before individual files.
- `file_search pattern="SystemPromptService" regex=false`: locate symbols fast.
- `read_file path="…" start_line=1 limit=120`: read in small chunks.
- `manage_selection action="list|replace"`: actively curate the working set; keep under ~80k tokens.
- `apply_edits` and `file_actions`: make precise edits or create/move files.
- `update_plan`: keep short, verifiable steps with one `in_progress` item.
- `chat_send mode=plan|chat|edit`: planning discussion or second-opinion review.

## MCP Flows & Hotwords

- [DISCOVER]: Use Discover flow to curate context and craft handoff.
`workspace_context` → `get_file_tree` → directory `get_code_structure` → `file_search` → targeted `read_file` → `manage_selection replace` → `prompt op="set"`.
- [AGENT]: Autonomous edit flow; favor RepoPrompt tools for navigation, reads, and edits.
  - Steps: start with [DISCOVER] if context is unclear; then `apply_edits`/`file_actions` with tight diffs.
- [PAIR]: Collaborative flow; discuss plan, then implement iteratively.
  - Use `chat_send mode=plan` to validate approach; then small, reversible edits.
- Complex or high-risk tasks: trigger a [SECOND OPINION] via `chat_send mode=plan` before applying broad changes.

## Testing Guidelines

- Unit tests only (no UI tests). Keep runs green before opening PRs.
- Add focused XCTest near related code; mirror file names (e.g., `PathMatcherTests.swift`).
- Run via `XcodeBuildMCP` (preferred) or the CLI examples above; ensure the app builds and launches, then run unit tests.

## Commit & PR Guidelines

- Commits: imperative mood, scoped and small (e.g., "Fix path matcher edge cases").
- PRs: clear description, linked issues, repro steps, screenshots if UI; list risk/rollback.
