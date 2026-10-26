# NexLauncher

A native macOS 26 app (SwiftUI + Liquid Glass) that finds the projects in `~/Documents/Nexventures`
and runs their frontend, backend, Flutter or Docker targets from one place, with a GitHub-Desktop-style
git panel, a menu bar item and desktop widgets.

## Build and install

```bash
./build.sh            # builds NexLauncher.app next to this file
./build.sh --install  # also copies it to /Applications and launches it
swift test            # unit tests
```

Signing uses your first "Apple Development" identity (override with `SIGN_IDENTITY`), falling back to ad-hoc.
Widgets need a real signature to load.

## What's in v2

- **App Store-style home**: greeting, CTA cards with illustrations (dismissible; *Settings → Git → Show dismissed tips again* brings them back), a *Running now* shelf and project cards with a Run pill.
- **Brand colours from nexventures.net** in light and dark, plus themes (Nexventures Ember, Ocean, Forest, Violet, Graphite). *Settings → Appearance*.
- **Collections and nested projects**: folders that hold several apps (e.g. `intern-sessions`, `mobileapp-sessions`) show as collections; apps with their own nested repositories list them inside.
- **Cards ⇄ Folders switch** in the toolbar: the Folders view mirrors the disk, each row with Run, Terminal and Git.
- **Embedded terminal** (SwiftTerm) on every card, row and detail page, usable in any folder, including nested apps.
- **Add project** (＋ in the toolbar): new folder (optionally `git init`) or clone a repository with live progress.
- **Profile** at the bottom of the sidebar opens Settings in the main window (⌘, too): profile, git identity and defaults, appearance, general, pins and overrides.

## Using it

- **Projects** are detected from manifests (`package.json`, `manage.py`, `requirements.txt`, `pubspec.yaml`,
  `docker-compose.yml`), not folder names. Projects with both a frontend and a backend get a *Full-stack* tag.
- Each card has Frontend / Backend / Both / Flutter / Docker buttons (only those that apply) and Stop.
  Click a card for logs and the **Git** tab (identity, stage, commit, pull, push, branches, history).
- **Settings** (⌘,): launch at login, Dock icon, greeting name, projects folder, pinned projects for the
  Quick Launch widget, and per-service command/port overrides.
- **Widgets**: add *Running Services* or *Quick Launch* from the desktop widget gallery (Edit Widgets).
- Quitting with services running asks whether to stop them or keep them running from the menu bar.

## Notes

- Widgets read `~/Library/Application Support/NexLauncher/widget-snapshot.json` through a read-only
  sandbox exception (no App Group needed). Personal use only; not App Store eligible.
- Git uses your existing credentials (Keychain / SSH). The app never stores tokens and never force-pushes.
- Design: `docs/superpowers/specs/`, plan: `docs/superpowers/plans/`.
