# Turnshare Plan

Generated: 2026-03-17

## Goal

Build `Turnshare`: a macOS-first tool that lets a developer press a global shortcut, browse recent AI coding sessions across agents, publish one selected session with a single GitHub-authenticated action, and immediately paste a share URL anywhere.

## Product Definition

Turnshare has two main parts inside one public monorepo:

- `apps/macos-launcher`: the native launcher with global hotkey and Maccy-style chooser
- `apps/web-renderer`: the public renderer site that displays shared sessions from user-owned GitHub gists

Suggested repo name:

- `turnshare`

Suggested product name:

- `Turnshare`

## Core User Workflow

1. User presses `Cmd + Option + Control + C`
2. Turnshare opens a small popup, similar to Maccy
3. The popup lists recent sessions from:
   - Claude Code
   - Codex
   - OpenCode
4. User can navigate sessions with keyboard
5. User presses `Cmd + 1` or explicitly selects a share action
6. Turnshare publishes the selected session
7. Turnshare copies the final URL to the clipboard
8. User pastes the URL into Slack, email, etc.

This should feel like a clipboard/share utility, not like a developer setup tool.

## Key Product Decisions

### 1. Single GitHub Authentication

Do not require the user to bring their own host.

Assumption:

- the user has a GitHub account
- the user is willing to authenticate once with GitHub

GitHub is the only required account or infrastructure for the MVP.

### 2. Storage Model

Use `GitHub Gists` for storage.

The shared session should be saved in the user's own GitHub account as a gist. This avoids:

- tying the product to the user's personal website
- requiring GitHub Pages setup
- requiring cloud storage or custom hosting setup

### 3. Renderer Model

Do **not** depend on `gisthost.github.io` or any third-party gist renderer.

Instead:

- Turnshare hosts its own public renderer site
- that site fetches the gist and renders it

This keeps the system simple for users while avoiding dependency on someone else's rendering service.

### 4. Safe Rendering Strategy

Do **not** treat the gist as hosted HTML and blindly execute arbitrary HTML from it.

Preferred approach:

- store structured data in the gist, primarily `session.json`
- optionally include `manifest.json`
- Turnshare Web reads the gist contents and renders the session itself

This is safer and more durable than uploading arbitrary HTML and trying to display it directly.

### 5. Session Look and Feel

The shared page should look terminal-like, but it does **not** need to be a perfect replay of the terminal buffer.

Important distinction:

- session JSONL gives semantic transcript data
- it does not give exact terminal screen state

Decision:

- render a terminal-inspired session view
- do not build around literal terminal capture or replay for MVP

### 6. Cross-Agent Support

Turnshare should support multiple providers behind one normalized session model.

Initial providers:

- Claude Code
- Codex
- OpenCode

Turnshare should not be branded around one agent.

### 7. Repository Strategy

Start with a single public monorepo:

- `turnshare`

Reason:

- launcher, parser, gist format, and renderer will change together early
- easier OSS adoption
- one issue tracker, one release story

Suggested structure:

```text
turnshare/
  apps/
    macos-launcher/
    web-renderer/
  packages/
    session-core/
    provider-claude/
    provider-codex/
    provider-opencode/
    publisher-gist/
  docs/
```

## Architecture Decisions

### Local App

The macOS app is responsible for:

- global hotkey handling
- recent-session indexing
- showing the Maccy-style chooser
- invoking publish
- copying the returned URL to the clipboard

### Session Pipeline

Use a normalized internal model:

1. provider adapter reads native session source
2. provider adapter converts to normalized Turnshare session
3. gist publisher uploads normalized data
4. Turnshare Web renders that normalized data

This is the main separation of concerns.

### Gist Contents

MVP gist payload:

- `session.json`
- `manifest.json`

Possible future additions:

- `attachments/` or embedded assets if needed
- pre-rendered `index.html` as an export convenience, but not as the primary rendering contract

### URL Shape

Preferred public URL shape:

- `https://<turnshare-domain>/g/<gist-id>`

The gist ID is the durable storage pointer. The public URL should be renderer-owned and stable.

## What To Reuse From Existing Inspiration

Primary inspiration:

- Simon Willison's `claude-code-transcripts`

Useful ideas to borrow:

- local session parsing
- interactive recent-session selection
- normalization before rendering
- self-contained export mindset
- gist publishing as a simple user-owned storage backend

Do **not** copy directly as the product base because:

- it is Claude-specific
- it uses a terminal CLI picker, not a native macOS launcher
- it outputs transcript cards, not the final terminal-like UI we want
- it relies on gist preview hosting patterns we do not want to depend on

## Explicitly Rejected Paths

### Rejected for MVP: Bring Your Own Host

Reason:

- too much setup friction
- poor adoption

### Rejected for MVP: GitHub Pages per User

Reason:

- clever, but still feels like hosting setup
- slower and less direct than gist storage
- more moving parts for the user

### Rejected for MVP: Third-Party Renderer Dependency

Reason:

- external reliability risk
- not a product-quality foundation

### Rejected for MVP: Exact Terminal Replay

Reason:

- requires capture from session start
- not available from native agent session files
- adds complexity that is unnecessary for first value

## UX Decisions

- The popup should feel close to Maccy
- Sessions should be listed from local sources, not inferred from active app/tab
- The user should be able to select any recent session, not only the currently active one
- Publishing should be one keypress after opening the popup
- The clipboard should end with the final share URL

## Open Questions

- Final domain name for Turnshare Web
- Best macOS implementation approach for the popup:
  - Swift/AppKit
  - Raycast extension prototype
  - Hammerspoon prototype
- Exact normalized session schema
- Best renderer stack for terminal-like display
- GitHub auth flow details for desktop app

## Recommended MVP Implementation Order

1. Create monorepo `turnshare`
2. Define normalized `session.json` schema
3. Build Claude provider first
4. Build Codex provider second
5. Build OpenCode provider third
6. Build gist publisher with one GitHub auth flow
7. Build web renderer that reads `session.json` from a gist
8. Build macOS chooser UI with hotkey and publish action
9. Add clipboard URL copy
10. Refine terminal-like presentation

## Suggested First Milestone

End-to-end Claude-only proof of concept:

- pick a Claude session from a local list
- publish `session.json` to a user gist
- open `https://<turnshare-domain>/g/<gist-id>`
- renderer displays a readable, terminal-inspired session page
- URL is copied to clipboard

After that, add Codex, then OpenCode.

## Notes For Future Agents

- Keep the product optimized for zero setup after GitHub login
- Treat gist storage and renderer hosting as separate concerns
- Prefer structured session rendering over arbitrary HTML execution
- Keep the UX keyboard-first
- Do not overfit the architecture to one agent vendor
