# NexLauncher

A native app for macOS (SwiftUI, with Liquid Glass on macOS 26) and Linux (GTK 4 and libadwaita) that finds the projects in your projects folder and runs their
frontend, backend, Flutter, Docker or other targets from one place. It comes with a GitHub-Desktop-style git panel,
an embedded terminal and an AI assistant that hands tasks to Claude Code, Codex, Antigravity or Gemini. On the Mac it
also has a menu bar panel and desktop widgets.

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
- **Menu bar panel** (⌃⌥⌘L, Mac) with running and pinned projects and open tasks; desktop widgets for running services,
  quick launch and tasks.
- **Themes** from nexventures.net in light and dark: Nexventures Ember, Ocean, Forest, Violet, Graphite.

## Install

### Mac

Runs on **macOS 14 Sonoma or later**, on Apple silicon and Intel Macs. On macOS 26 it uses the Liquid Glass look;
on macOS 14 and 15 it uses the standard system materials and controls.

Download the latest release from the website, unzip it and move **NexLauncher.app** to Applications.

The app isn't notarised yet, so the first time macOS says it can't check it for malicious software. Click **Done**,
open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to NexLauncher, then
confirm. (Or run `xattr -dr com.apple.quarantine /Applications/NexLauncher.app` in Terminal.)

### Linux

A Flatpak for x86_64 and ARM (aarch64), on the GNOME 50 runtime from Flathub. Download the bundle for your processor
from the website, then:

```bash
flatpak install --user NexLauncher-4.0.0-linux-x86_64.flatpak
flatpak run net.nexventures.NexLauncher
```

Dev servers, git, terminals and AI agents run on your system through `flatpak-spawn --host`, with your login shell and
its PATH. Settings live in `~/.config/nexlauncher`, tasks in `~/.local/share/nexlauncher`. Not on Linux yet: desktop
widgets, the menu bar panel, the Dock menu and iOS simulators.

## Build from source

### Mac

Building needs Xcode 26 (Swift 6.2); the app it produces runs on macOS 14 and later.

```bash
./build.sh            # builds a universal NexLauncher.app (Apple silicon + Intel) next to this file
ARCHS=arm64 ./build.sh  # quicker: one architecture
./build.sh --install  # also copies it to /Applications and launches it
swift test            # unit tests
```

Signing uses your first "Apple Development" identity (override with `SIGN_IDENTITY`), falling back to ad-hoc.
Widgets need a real signature to load. `--install` refuses to replace a running NexLauncher that still has
services, agents or terminals open (`FORCE=1` overrides).

### Linux

The Linux app needs Swift 6.3, GTK 4.20 and libadwaita 1.8, so it's easiest to build as a Flatpak with the GNOME 50 SDK:

```bash
flatpak install --user flathub org.gnome.Sdk//50 org.freedesktop.Sdk.Extension.swift6//25.08
flatpak-builder --user --install --force-clean build linux/net.nexventures.NexLauncher.yml
```

With older GTK you can still build and test the shared core: `NEX_CORE_ONLY=1 swift test`.

## Project layout

| Path | What's there |
| --- | --- |
| `Sources/NexCore` | Models, stack detection, scanning, settings, agents, platform paths (no UI) |
| `Sources/NexProcess` | Spawning and stopping services in their own process groups |
| `Sources/NexGit` | Git commands and parsing |
| `Sources/NexTerminal` | Embedded terminal (SwiftTerm) |
| `Sources/NexApp` | The app model shared by both interfaces |
| `Sources/NexUI` | Mac: SwiftUI views |
| `Sources/NexLauncher` | Mac: app entry point, menu bar, Dock menu |
| `Sources/NexLinux`, `Sources/CVte` | Linux: libadwaita interface, VTE terminal |
| `linux` | Flatpak manifest, desktop entry, AppStream metadata, icons |
| `Widgets` | WidgetKit extension |
| `Tests` | Swift Testing suites |
| `site` | The landing page (GitHub Pages) |
| `docs` | Design specs and implementation plans |

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 NiyonshutiDavid

## Notes

- Widgets read `~/Library/Application Support/NexLauncher/widget-snapshot.json` through a read-only sandbox
  exception (no App Group needed), so the app isn't App Store eligible.
- Git uses your existing credentials (Keychain / SSH). The app never stores tokens and never force-pushes.
