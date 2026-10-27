# NexLauncher

A native macOS 26 app (SwiftUI + Liquid Glass) that finds the projects in your projects folder and runs their
frontend, backend, Flutter, Docker or other targets from one place. It comes with a GitHub-Desktop-style git panel,
an embedded terminal, an AI assistant that hands tasks to Claude Code, Codex, Antigravity or Gemini, a menu bar
panel and desktop widgets.

**Website and download:** https://niyonshutidavid.github.io/NexLauncher/

## Features

- **Finds your projects** from their manifests (`package.json`, `manage.py`, `pyproject.toml`, `pubspec.yaml`,
  `go.mod`, `Cargo.toml`, `docker-compose.yml`, and more), not folder names. Frontend and backend side by side get a
  *Full-stack* tag; folders that hold several apps show as collections.
- **One-click run** for Frontend, Backend, Both, Flutter (on a chosen simulator or emulator), Docker or the app itself,
  with live logs, ports and a setup step when dependencies are missing.
- **Git panel**: identity, stage, commit, pull, push, branches and history. Uses your existing credentials.
- **Embedded terminal** in any project or folder.
- **AI assistant**: give a task to Claude Code, Codex, Antigravity (`agy`) or Gemini CLI from the app, or from a side
  panel on a project page. Runs stream their progress, can be stopped and continued. NexLauncher never stores keys.
- **Tasks** per project, shown in a desktop widget.
- **Filters and breadcrumbs**: filter by type, framework, git state, running or pinned, and choose how collections show.
- **Menu bar panel** (⌃⌥⌘L) with running and pinned projects and open tasks; desktop widgets for running services,
  quick launch and tasks.
- **Themes** from nexventures.net in light and dark: Nexventures Ember, Ocean, Forest, Violet, Graphite.

## Install

Download the latest release from the website, unzip it and move **NexLauncher.app** to Applications.

The app isn't notarised yet, so the first time macOS will say it can't check it. Right-click the app, choose
**Open**, then **Open** again (or run `xattr -dr com.apple.quarantine /Applications/NexLauncher.app`).

## Build from source

Requires macOS 26 and Xcode 26 (Swift 6.2).

```bash
./build.sh            # builds NexLauncher.app next to this file
./build.sh --install  # also copies it to /Applications and launches it
swift test            # unit tests
```

Signing uses your first "Apple Development" identity (override with `SIGN_IDENTITY`), falling back to ad-hoc.
Widgets need a real signature to load. `--install` refuses to replace a running NexLauncher that still has
services, agents or terminals open (`FORCE=1` overrides).

## Project layout

| Path | What's there |
| --- | --- |
| `Sources/NexCore` | Models, stack detection, scanning, settings, agents (no UI) |
| `Sources/NexProcess` | Spawning and stopping services in their own process groups |
| `Sources/NexGit` | Git commands and parsing |
| `Sources/NexTerminal` | Embedded terminal (SwiftTerm) |
| `Sources/NexUI` | SwiftUI views and the app model |
| `Sources/NexLauncher` | App entry point, menu bar, Dock menu |
| `Widgets` | WidgetKit extension |
| `Tests` | Swift Testing suites |
| `site` | The landing page (GitHub Pages) |
| `docs` | Design specs and implementation plans |

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Notes

- Widgets read `~/Library/Application Support/NexLauncher/widget-snapshot.json` through a read-only sandbox
  exception (no App Group needed), so the app isn't App Store eligible.
- Git uses your existing credentials (Keychain / SSH). The app never stores tokens and never force-pushes.
