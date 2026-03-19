<p align="center">
  <img src="Design/Logo/turnshare-app-icon-1024.png" width="128" height="128" alt="Turnshare icon">
</p>

<h1 align="center">Turnshare</h1>

<p align="center">
  Share your AI coding sessions with a single keystroke.<br>
  A macOS menu bar app that publishes <a href="https://claude.ai/code">Claude Code</a> and <a href="https://openai.com/index/introducing-codex/">Codex</a> sessions as shareable links via GitHub Gists.
</p>

<p align="center">
  <a href="https://github.com/nclandrei/turnshare/releases/latest">Download</a> &middot;
  <a href="https://nclandrei.github.io/turnshare">Web Viewer</a>
</p>

## How It Works

1. **Activate** the panel with a global hotkey (default `⌃⇧S`)
2. **Browse** your Claude Code and Codex sessions — searchable, sorted by recency
3. **Publish** with a modifier+number shortcut (e.g. `⌘1`) — the session is uploaded as a GitHub Gist and a shareable URL is copied to your clipboard
4. **Share** the link — anyone can view the rendered session in the [web viewer](https://nclandrei.github.io/turnshare)

Sessions are read directly from `~/.claude/projects/` and `~/.codex/` — no configuration needed.

## Install

### Homebrew (recommended)

```bash
brew install --cask nclandrei/tap/turnshare
```

### Manual download

Download `Turnshare.zip` from the [latest release](https://github.com/nclandrei/turnshare/releases/latest), unzip, and drag to `/Applications`.

> Requires macOS 14 (Sonoma) or later. The app is signed and notarized — it opens without Gatekeeper warnings.

### Build from source

```bash
cd apps/macos
swift build -c release
# Binary at .build/release/Turnshare
```

## Features

- **Multi-provider** — reads sessions from Claude Code and Codex (OpenCode planned)
- **Global hotkey** — configurable keyboard shortcut to toggle the panel
- **Quick publish** — modifier+number shortcuts to publish any of the first 9 sessions instantly
- **Confirmation mode** — optional two-step publish (select then confirm) to avoid accidental publishes
- **Search** — filter sessions by project name, git branch, or message content
- **Hover preview** — preview session turns in a side panel without publishing
- **Pagination** — loads sessions on demand; handles thousands of session files
- **Deduplication** — re-publishing a session reuses the existing gist
- **GitHub OAuth** — device flow authentication, token stored in macOS Keychain

## Architecture

```
apps/macos/                    # Swift Package (macOS 14+, SPM 5.9)
  Sources/
    SessionCore/               # Normalized session model (Session, Turn, Agent)
    ProviderClaude/            # Reads Claude Code ~/.claude JSONL → Session
    ProviderCodex/             # Reads Codex ~/.codex JSONL → Session
    PublisherGist/             # Publishes Session → GitHub Gist
    Turnshare/                 # Menu bar app, floating panel, hotkey, settings

docs/                          # Web viewer (GitHub Pages, vanilla HTML/JS/CSS)
schema/session.schema.json     # Normalized session JSON schema (v1)
Design/Logo/                   # App icon and menu bar icon assets
```

### Session Schema

All providers normalize native formats into a common schema ([`schema/session.schema.json`](schema/session.schema.json)):

| Field | Type | Description |
|-------|------|-------------|
| `agent` | `claude-code` \| `codex` \| `opencode` | Which AI agent |
| `sessionId` | string | Unique session identifier |
| `turns` | array | Sequence of user, assistant, and tool turns |
| `content` | array | Text blocks, tool use, or tool results per turn |

### Dependencies

- [HotKey](https://github.com/soffes/HotKey) — global keyboard shortcuts
- No other external Swift dependencies

## Development

```bash
cd apps/macos

# Run all tests (122 tests across 5 targets)
swift test

# Run a specific test target
swift test --filter ProviderClaudeTests
swift test --filter ProviderCodexTests
swift test --filter PublisherGistTests
swift test --filter SessionCoreTests
swift test --filter TurnshareTests
```

## License

MIT
