# Turnshare

macOS menu bar app for sharing AI coding sessions via GitHub Gists. Supports Claude Code, Codex, and OpenCode.

## Quick Reference

```bash
# Build
cd apps/macos && swift build

# Run tests (122 tests across 5 test targets)
cd apps/macos && swift test

# Run specific test target
cd apps/macos && swift test --filter SessionCoreTests
cd apps/macos && swift test --filter ProviderClaudeTests
cd apps/macos && swift test --filter ProviderCodexTests
cd apps/macos && swift test --filter PublisherGistTests
cd apps/macos && swift test --filter TurnshareTests
```

## Architecture

```
apps/macos/                    # Swift Package (macOS 14+, SPM 5.9)
  Sources/
    SessionCore/               # Normalized session model (Session, Turn, Agent)
    ProviderClaude/            # Reads Claude Code JSONL → Session
    PublisherGist/             # Publishes Session to GitHub Gist
    Turnshare/                 # Main app (menu bar, floating panel, hotkey)
  Tests/
    SessionCoreTests/          # Model encode/decode tests
    ProviderClaudeTests/       # Claude JSONL parsing tests
    ProviderCodexTests/        # Codex JSONL parsing tests
    PublisherGistTests/        # Gist payload structure tests
    TurnshareTests/            # AppState logic, preview, hotkey config tests

docs/                          # Web renderer (GitHub Pages, static HTML/JS)
  index.html                   # Session viewer — fetches gist, renders turns
  preview.html                 # Side panel preview

schema/
  session.schema.json          # Normalized session JSON schema (version 1)

convert-session.mjs            # CLI: Claude Code JSONL → session.json
```

## Key Patterns

- **Session model**: `SessionCore` defines `Session`, `Turn`, `ContentBlock` (text/toolUse/toolResult)
- **JSON coding**: Use `JSONEncoder.turnshare` / `JSONDecoder.turnshare` for ISO8601 date handling
- **Providers**: Each agent has a provider that converts native format → normalized `Session`
- **Tests**: Pure logic tests — no UI tests, no network calls, all use temp directories
- **Web renderer**: Vanilla HTML/JS/CSS, no build step, reads `session.json` from gist API

## Dependencies

- [HotKey](https://github.com/soffes/HotKey) v0.2.0+ — global keyboard shortcuts
- No other external Swift dependencies

## Session Schema

Version 1 schema at `schema/session.schema.json`. Key types:
- Agents: `claude-code`, `codex`, `opencode`
- Roles: `user`, `assistant`, `tool`
- Content blocks: `text`, `tool_use`, `tool_result`

## GitHub Auth

Uses OAuth device flow. Token stored in macOS keychain. No `.env` files needed.
