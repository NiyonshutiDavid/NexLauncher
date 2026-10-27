# NexLauncher for Linux: design

Requested 2026-10-27: a Linux desktop app with a shared Swift core and a GTK / libadwaita interface. The Mac app
stays as it is.

## Findings that shaped this

- **Core is portable.** `NexCore`, `NexProcess` and `NexGit` (about 2,400 lines) import only Foundation and
  Observation (both ship with Swift on Linux), except `LoginItem.swift` (ServiceManagement). Linux differences:
  `POSIX_SPAWN_CLOEXEC_DEFAULT` is Apple-only; `posix_spawn_file_actions_addchdir` is `_addchdir_np` in glibc;
  `/bin/zsh` is hard-coded (often missing on Linux); data lives in `~/Library/Application Support`; iOS simulators
  come from `xcrun`; the Android SDK default path differs.
- **App model is nearly portable.** `AppModel` and its extensions, `Agents`, `CTA`, `Onboarding`, `GitModel`,
  `DevicesModel`, `SetupSession` (about 1,900 lines, `Sources/NexUI`) use AppKit in about a dozen places only:
  opening URLs, revealing files, the clipboard, opening an app, activating the main window, reloading widgets,
  notifications, and the SwiftTerm-backed terminal sessions.
- **Interface must be rebuilt.** About 4,800 lines of SwiftUI views, the menu bar, Dock menu and WidgetKit
  extension are Apple-only.
- **Toolkit.** [Adwaita for Swift](https://codeberg.org/aparoksha/adwaita-swift) is a SwiftUI-like declarative
  framework for GNOME (libadwaita, GTK 4), actively maintained (commits July 2026), Linux-only, and its template
  ships as a Flatpak built with a Swift SDK extension. SwiftCrossUI's GTK backend was considered and rejected: it
  doesn't produce libadwaita/GNOME-native UI.
- No Linux machine or container runtime is available on the development Mac, so Linux builds and tests run in
  GitHub Actions; the finished Flatpak needs a manual check on a Linux desktop.

## Decisions

| Topic | Decision |
| --- | --- |
| Repository | One Swift package. `Package.swift` branches on `#if os(Linux)`: shared targets everywhere, Mac targets (NexTerminal/SwiftTerm, NexUI, NexLauncher) only on macOS, Linux targets (NexLinux, CVte) only on Linux. |
| Shared model | New target `NexApp` holds `AppModel` and the other model files moved out of `NexUI`. Platform calls go through `PlatformServices`; terminals through `TerminalHost`. `NexUI` keeps views plus the Mac implementations. |
| Linux UI | `NexLinux` executable on Adwaita for Swift, pinned to a commit. Same information architecture as the Mac app: sidebar (All Projects, Pinned, Running, Full-stack, Flutter, Tasks, AI Assistant, profile/Settings), home grid with filters and search, project page with tabs and breadcrumbs, Ask AI side panel, Git, Tasks, Settings, onboarding. Ember accent via libadwaita CSS. |
| Terminal | VTE (`vte-2.91-gtk4`) through a system-library target `CVte`, wrapped as an Adwaita for Swift widget. |
| Processes | glibc `posix_spawn` with `POSIX_SPAWN_SETSID`, `addchdir_np`, `addclosefrom_np(3)` (glibc 2.34+). Shell: `$SHELL`, else the passwd entry, else `/bin/sh`, run as `-lc`. |
| Flatpak sandbox | Every external command (services, git, agents, terminals) runs on the host through `flatpak-spawn --host`. Services start under `setsid` on the host and report their process-group id; Stop runs `flatpak-spawn --host kill -TERM -<pgid>`. Detected by `/.flatpak-info`. |
| Paths | `$XDG_CONFIG_HOME/nexlauncher` (settings, overrides), `$XDG_DATA_HOME/nexlauncher` (tasks), defaults `~/.config`, `~/.local/share`. Default projects folder `~/Projects`, then `~/Documents`, then `~`. Android SDK `~/Android/Sdk`. |
| Features on Linux | Projects, Run/Stop, logs, setup, git, terminal, AI agents (Claude Code, Codex, Gemini CLI, `agy`, custom), tasks, filters, breadcrumbs, settings, onboarding, notifications (GNotification), launch at login (XDG autostart / Background portal), Android emulators and Flutter Linux/web devices. |
| Not on Linux (v1) | Desktop widgets, menu bar/tray panel, Dock menu, iOS simulators, opening the Antigravity app (the `agy` CLI works). |
| Distribution | Flatpak `net.nexventures.NexLauncher` (GNOME runtime, Swift SDK extension) built by GitHub Actions for x86_64 and aarch64; bundles stored in Supabase like the Mac zips; the site's chooser gains Linux. Version 4.0.0. |
