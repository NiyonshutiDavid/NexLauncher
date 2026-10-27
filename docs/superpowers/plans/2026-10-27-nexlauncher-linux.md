# NexLauncher for Linux Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native Linux desktop app (GTK 4 / libadwaita) that shares NexLauncher's Swift core and app model with the Mac app, shipped as a Flatpak from the website.

**Architecture:** One Swift package. Core (`NexCore`, `NexProcess`, `NexGit`) and a new shared app model (`NexApp`) build on both systems; `Package.swift` adds the Mac UI on macOS and the Linux UI (`NexLinux`, `CVte`) on Linux. Platform-specific behaviour (URLs, clipboard, notifications, terminals, autostart, Flatpak host commands) sits behind small protocols with one implementation per system.

**Tech Stack:** Swift 6.2 (language mode 5), Swift Testing, Adwaita for Swift (libadwaita 1.5+, GTK 4), VTE 0.76+ (`vte-2.91-gtk4`), Flatpak (GNOME runtime + Swift SDK extension), GitHub Actions (`swift:6.2-noble` container, `ubuntu-24.04` and `ubuntu-24.04-arm`).

**Spec:** `docs/superpowers/specs/2026-10-27-nexlauncher-linux-design.md`

## Global Constraints

- The Mac app must not change in look or behaviour; every existing macOS test keeps passing (`swift test` on macOS: 425 tests at the start).
- Mac minimum stays macOS 14; `build.sh` stays the Mac build.
- Linux floor: glibc 2.34, GTK 4.12, libadwaita 1.5 (Ubuntu 24.04 / Fedora 40 and later).
- No credentials are stored; task text, project names and paths are never spliced into a shell string (pass as environment variables or argument arrays).
- App ID `net.nexventures.NexLauncher`; Linux release version `4.0.0`.
- Settings files stay JSON-compatible with the Mac format (same `AppSettings` keys).
- Copy: no em dashes; same wording as the Mac app where the feature is the same.

## Review Focus

1. **Stopping inside the Flatpak sandbox:** a dev server started with `flatpak-spawn --host` must stop with every child (e.g. `npm run dev` → `vite` → `esbuild`); nothing may survive Stop or Quit. Pinned by `ProcessManagerLinuxTests.stopKillsHostProcessGroup` (Task 3).
2. **PATH from the user's shell:** tools installed through nvm, pyenv, asdf or `~/.local/bin` are only on PATH in a login shell; with `SHELL=/bin/bash` and a `~/.bash_profile` that extends PATH, `command -v` must find them. Pinned by `PlatformShellTests.loginShellLoadsProfile` (Task 2).
3. **Folders with spaces and non-ASCII names** (e.g. `~/Projects/Café App`) must run, open in the terminal and in git, inside and outside Flatpak. Pinned by `HostCommandTests.argumentsSurviveSpacesAndUnicode` (Task 3) and `GitRunnerLinuxTests.repoPathWithSpaces` (Task 4).
4. **No projects folder yet:** on a fresh Linux account `~/Projects` and `~/Documents` may not exist; onboarding must offer to choose or create one instead of scanning `~`'s entire tree. Pinned by `PlatformPathsTests.defaultScanRootFallsBack` (Task 2) and `LinuxOnboardingTests.missingFolderOffersChoice` (Task 11).
5. **Settings written on macOS read on Linux and the reverse** (people sync dotfiles): unknown or Mac-only keys must be kept, not dropped. Pinned by `SettingsPortabilityTests.roundTripKeepsMacKeys` (Task 2).

---

## Phase 1: Portable core

### Task 1: Linux CI and a Linux-aware package manifest

**Files:**
- Modify: `Package.swift`
- Create: `.github/workflows/ci.yml`
- Modify: `Sources/NexCore/LoginItem.swift` (wrap the SMAppService implementation in `#if canImport(ServiceManagement)`; keep the `LoginItemControlling` protocol for all systems)

**Interfaces:**
- Produces: on Linux, `swift build` builds `NexCore`, `NexProcess`, `NexGit`, `NexTestSupport` and their tests only; on macOS the manifest is unchanged in effect.

- [ ] **Step 1:** Restructure `Package.swift` with `#if os(Linux)`: shared targets and test targets in one array; append SwiftTerm, `NexTerminal`, `NexUI`, `NexLauncher` and their tests only on macOS.
- [ ] **Step 2:** Add `ci.yml` with two jobs: `macos` (`macos-15`, Xcode 26, `swift test`) and `linux` (container `swift:6.2-noble`, `swift build` then `swift test`). Trigger on push and pull request.
- [ ] **Step 3:** Run on macOS: `swift test` → 425 tests pass.
- [ ] **Step 4:** Push a branch; Linux job is expected to FAIL on the spawn flags and paths (that is Task 2 and 3's red). Record the failing errors in the PR description.
- [ ] **Step 5:** Commit: `ci: build and test the core on Linux`.

### Task 2: `Platform` paths, shell and settings portability

**Files:**
- Create: `Sources/NexCore/Platform.swift`
- Modify: `Sources/NexCore/Settings.swift` (`AppSettings.supportDirectory`, `realHome`, `defaults()` delegate to `Platform`)
- Modify: `Sources/NexCore/Tasks.swift`, `Sources/NexCore/WidgetSnapshot.swift`, `Sources/NexCore/Devices.swift` (`androidSDK` candidates)
- Test: `Tests/NexCoreTests/PlatformTests.swift`

**Interfaces:**
- Produces:
  - `public enum HostOS: Sendable { case macOS, linux }` and `public static var current: HostOS`
  - `public struct PlatformPaths: Sendable { configDirectory: URL; dataDirectory: URL; defaultScanRoot: URL; androidSDKCandidates: [URL] }`
  - `public static func paths(os: HostOS, home: URL, environment: [String: String], exists: (URL) -> Bool) -> PlatformPaths` (pure, for tests)
  - `public static var paths: PlatformPaths` (live)
  - `public static func loginShell(environment: [String: String], passwdShell: String?) -> String`
  - `public static var isFlatpak: Bool` (`/.flatpak-info` exists)
  - `public static var supportsIOSSimulators: Bool` (macOS only)

- [ ] **Step 1: Write failing tests** in `PlatformTests.swift`:
  - `macPathsUnchanged`: macOS → `configDirectory == home/Library/Application Support/NexLauncher`, `dataDirectory` same.
  - `linuxUsesXDG`: `XDG_CONFIG_HOME=/x/cfg`, `XDG_DATA_HOME=/x/data` → `/x/cfg/nexlauncher`, `/x/data/nexlauncher`; unset → `home/.config/nexlauncher`, `home/.local/share/nexlauncher`.
  - `defaultScanRootFallsBack`: Linux with only `~/Documents` existing → `~/Documents`; with `~/Projects` → `~/Projects`; neither → `home`. macOS keeps `~/Documents/Nexventures`.
  - `androidSDKCandidates`: Linux → `ANDROID_HOME` first, then `home/Android/Sdk`; macOS → `home/Library/Android/sdk`.
  - `loginShellOrder`: `SHELL=/usr/bin/fish` wins; no `SHELL` → passwd shell; neither → `/bin/sh`.
  - `PlatformShellTests.loginShellLoadsProfile` (Linux only, `.enabled(if: HostOS.current == .linux)`): temp HOME with `.bash_profile` exporting `PATH=$HOME/tools:$PATH`, `SHELL=/bin/bash`; spawning `command -v nex-test-tool` through `ProcessSpawner` finds `$HOME/tools/nex-test-tool`.
  - `SettingsPortabilityTests.roundTripKeepsMacKeys`: decoding a Mac settings JSON containing `widgetsConfirmed`, `avatarPhotoPath` and an unknown key `futureKey` then encoding keeps all three.
- [ ] **Step 2:** `swift test --filter "PlatformTests|SettingsPortabilityTests"` → FAIL (`Platform` undefined).
- [ ] **Step 3:** Implement `Platform.swift`; route existing callers through it. `AppSettings` keeps unknown keys by storing them in a `[String: JSONValue]` `extras` dictionary (add a small `JSONValue` Codable enum in `Settings.swift`).
- [ ] **Step 4:** Tests pass on macOS (`swift test`) and Linux (CI).
- [ ] **Step 5:** Commit: `core: platform paths, login shell and settings that survive both systems`.

### Task 3: Process spawning on Linux and the Flatpak host bridge

**Files:**
- Create: `Sources/NexProcess/HostCommand.swift`
- Modify: `Sources/NexProcess/ProcessManager.swift` (`ProcessSpawner.spawn`, `terminateGroup`, the `/bin/zsh` call sites at lines ~29-63, ~117, ~261)
- Test: `Tests/NexProcessTests/HostCommandTests.swift`, `Tests/NexProcessTests/ProcessManagerLinuxTests.swift`

**Interfaces:**
- Consumes: `Platform.loginShell`, `Platform.isFlatpak`
- Produces:
  - `public struct HostInvocation: Equatable, Sendable { executable: String; arguments: [String]; environment: [String: String] }`
  - `public enum HostCommand { static func shell(_ command: String, in directory: URL, environment: [String: String], flatpak: Bool, shell: String) -> HostInvocation; static func exec(_ executable: String, _ arguments: [String], in directory: URL, flatpak: Bool) -> HostInvocation }`
    - Outside Flatpak: `shell` → `(shell, ["-lc", command])`.
    - Inside Flatpak: executable `/usr/bin/flatpak-spawn`, arguments `["--host", "--watch-bus", "--directory=<dir>", "--env=NEX_CMD=<command>", "--env=K=V"…, "/bin/sh", "-c", "echo NEXPGID=$$; exec setsid -w \"$0\" -lc \"$NEX_CMD\"", <shell>]`. The command only ever travels in `NEX_CMD`. The first output line `NEXPGID=<n>` is the host process group; `ProcessManager` keeps it and drops the line from the logs.
  - `ProcessSpawner.spawn(command:directory:environment:)` keeps its signature; on Linux uses `POSIX_SPAWN_SETSID`, `posix_spawn_file_actions_addchdir_np`, `posix_spawn_file_actions_addclosefrom_np(&a, 3)`.
  - `ProcessSpawner.terminateGroup(_ pid: pid_t, hostPGID: Int32?, grace:)`: with `hostPGID`, sends `flatpak-spawn --host kill -TERM -<pgid>` then `-KILL` after `grace`.

- [ ] **Step 1: Write failing tests:**
  - `HostCommandTests.plainShell`: flatpak false → executable `/bin/bash`, arguments `["-lc", "npm run dev"]`.
  - `HostCommandTests.flatpakNeverSplicesCommand`: flatpak true, command `echo "a; rm -rf /"` → no element of `arguments` contains `rm -rf`; `environment["NEX_CMD"] == command`; arguments start with `["--host", "--watch-bus"]` and contain `--directory=<dir>`.
  - `HostCommandTests.argumentsSurviveSpacesAndUnicode`: directory `/tmp/Café App` → `--directory=/tmp/Café App` is one argument.
  - `ProcessManagerLinuxTests.spawnRunsInDirectory` (Linux): `pwd` in a temp folder with a space prints that folder.
  - `ProcessManagerLinuxTests.stopKillsWholeGroup` (Linux): command `sleep 300 & sleep 300; wait`; after `terminateGroup`, no `sleep` with that PGID remains (`/proc/*/stat` field 5).
  - `ProcessManagerLinuxTests.stopKillsHostProcessGroup`: parse `NEXPGID=4242` first line → `ProcessManager` stores 4242 and the stop path builds `["--host", "kill", "-TERM", "-4242"]` (unit-level, no real Flatpak).
- [ ] **Step 2:** Run `swift test --filter "HostCommandTests|ProcessManagerLinuxTests"` → FAIL.
- [ ] **Step 3:** Implement `HostCommand`; switch `ProcessSpawner` and `ProcessManager` (including the `/bin/zsh` probe at ~261) to it; `#if os(Linux)` for spawn flags.
- [ ] **Step 4:** macOS `swift test` → all pass; Linux CI → core tests pass.
- [ ] **Step 5:** Commit: `process: Linux spawning and the Flatpak host bridge`.

### Task 4: Git and device discovery on Linux

**Files:**
- Modify: `Sources/NexGit/GitRunner.swift` (`/usr/bin/git` at lines ~31 and ~80), `Sources/NexGit/GitService.swift:147`
- Modify: `Sources/NexCore/Devices.swift`
- Test: `Tests/NexGitTests/GitRunnerLinuxTests.swift`, `Tests/NexCoreTests/DevicesLinuxTests.swift`

**Interfaces:**
- Consumes: `HostCommand.exec`, `Platform.paths.androidSDKCandidates`, `Platform.supportsIOSSimulators`
- Produces: `GitRunner` resolves git as `HostCommand.exec("git", args, in:, flatpak:)` (PATH lookup, not a fixed path); `DeviceParsers.androidSDK(environment:candidates:exists:) -> URL?`.

- [ ] **Step 1: Failing tests:** `GitRunnerLinuxTests.repoPathWithSpaces` (init, commit and `status` in `/tmp/My Repo é`); `GitRunnerLinuxTests.flatpakUsesHostGit` (invocation starts `flatpak-spawn --host git`); `DevicesLinuxTests.sdkFromAndroidHome`, `DevicesLinuxTests.sdkDefaultLinuxPath`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** macOS and Linux CI green.
- [ ] **Step 5:** Commit: `git, devices: find tools the Linux way`.

## Phase 2: Shared app model

### Task 5: `NexApp` target with `PlatformServices`

**Files:**
- Create: `Sources/NexApp/PlatformServices.swift`, `Sources/NexApp/TerminalHost.swift`
- Move (git mv, then fix imports) from `Sources/NexUI` to `Sources/NexApp`: `AppModel.swift`, `AppModel+Filters.swift`, `AppModel+Navigation.swift` (model parts only; `Crumb`, `AppPage`, `HomeItem`, `SettingsSection`, `DetailTab`), `AppModel+Run.swift`, `AppModel+Tasks.swift`, `AppModel+Pinning.swift`, `AppModel+QuickActions.swift`, `AppModel+Notifications.swift`, `AppModel+Agents.swift`, `Agents.swift`, `CTA.swift`, `Onboarding.swift`, `GitModel.swift`, `DevicesModel.swift`, `SetupSession.swift`, the `Notifying` protocol and `NotificationEvents` from `Notifications.swift`
- Create: `Sources/NexUI/MacPlatformServices.swift`, `Sources/NexUI/MacTerminalHost.swift` (wraps `TerminalTabs`)
- Move tests: `Tests/NexUITests/*` that only use the model → `Tests/NexAppTests/`
- Modify: `Package.swift` (`NexApp` shared; `NexUI` depends on it)

**Interfaces:**
- Produces:
  ```swift
  @MainActor public protocol PlatformServices: AnyObject {
      func open(_ url: URL)
      func reveal(_ path: URL)
      func copy(_ text: String)
      func open(_ files: [URL], withApplicationAt app: URL)
      func activateMainWindow()
      func reloadWidgets()
      func setDockIconVisible(_ visible: Bool)     // no-op on Linux
      var isAppActive: Bool { get }
  }
  @MainActor public protocol TerminalHost: AnyObject {
      var hasRunningPrograms: Bool { get }
      func openTab(at directory: URL, command: String?) -> UUID
      func close(_ id: UUID)
  }
  ```
  `AppModel.init(… services: PlatformServices, terminals: TerminalHost, hostOS: HostOS = .current, …)` (replaces the `reloadWidgets` and `appIsActive` closures); `NoopPlatformServices` and `RecordingPlatformServices` in `NexTestSupport` for tests.
- Every former AppKit/WidgetKit call in the moved files becomes a `services.` call: `NSPasteboard` and `NSWorkspace.open(_:withApplicationAt:)` in `AppModel+Agents.swift:83-86`, `NSApp.windows`/`activate` in `AppModel+Navigation.swift:39-45`, `WidgetCenter` in `AppModel.swift:90`, `NSApp.isActive` at `:115`, `setActivationPolicy` at `:222`; the views' own reveal and open-in-browser calls go through `services` too.

- [ ] **Step 1:** Add `Tests/NexAppTests/PlatformServicesTests.swift`: `copyTaskForAntigravity` (macOS host, Antigravity without CLI → `RecordingPlatformServices.copied == [task text]` and `openedWithApp` contains the project root), `showMainWindowActivates` (`activations == 1`), `dockIconPolicyGoesThroughServices` (`applyDockIconPolicy()` with `showDockIcon = false` → `dockIconVisible == [false]`).
- [ ] **Step 2:** Run → FAIL (module `NexApp` missing).
- [ ] **Step 3:** Create the target, move files, introduce the two protocols, implement the Mac versions in `NexUI`, update `NexLauncherApp.swift` to pass `MacPlatformServices()`.
- [ ] **Step 4:** macOS `swift test` → 425 + new tests pass; `./build.sh` builds; the Mac app looks and behaves the same (compare the demo screenshots in `site/assets/shots`). Linux CI runs `NexAppTests`.
- [ ] **Step 5:** Commit: `app: move the model into NexApp, shared by both platforms`.

## Phase 3: Linux app (Adwaita for Swift)

### Task 6: `NexLinux` skeleton and Linux platform services

**Files:**
- Modify: `Package.swift` (Linux only: dependency `https://git.aparoksha.dev/aparoksha/adwaita-swift` pinned to a commit; executable target `NexLinux` depends on `NexApp`, `Adwaita`)
- Create: `Sources/NexLinux/main.swift` (`NexLauncherApp: App`, window `net.nexventures.NexLauncher`), `Sources/NexLinux/LinuxPlatformServices.swift`, `Sources/NexLinux/Theme.css` (Ember accent `#cf3f0e` light, `#f0561f` dark, from `ThemePalette`), `Sources/NexLinux/Sidebar.swift`
- Modify: `.github/workflows/ci.yml` (`linux-app` job: `apt install libadwaita-1-dev libgtk-4-dev libvte-2.91-gtk4-dev`, `swift build --product NexLinux`)

**Interfaces:**
- Consumes: `AppModel`, `PlatformServices`
- Produces: `LinuxPlatformServices` (URLs and reveal through `gio` portals: `org.freedesktop.portal.OpenURI`; clipboard via GDK; `activateMainWindow` presents the window; `reloadWidgets` no-op); sidebar items identical to `SidebarView` (All Projects, Pinned, Running, Full-stack, Flutter, Tasks, AI Assistant, profile row → Settings).

- [ ] **Step 1:** Test `LinuxPlatformServicesTests.openURLUsesPortal` (Linux; services built with an injected `DBusCalling` recorder → one call to `org.freedesktop.portal.OpenURI.OpenURI` with the URL).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement the skeleton: `Adw.NavigationSplitView` with the sidebar and an empty content page; scan on launch.
- [ ] **Step 4:** CI `linux-app` builds; on a Linux desktop (see Task 13 check list) the window opens and the sidebar counts match the scanned projects.
- [ ] **Step 5:** Commit: `linux: app skeleton with sidebar and platform services`.

### Task 7: Home, filters, search, collections

**Files:** Create `Sources/NexLinux/HomePage.swift`, `ProjectCard.swift`, `FilterPopover.swift`, `CollectionPage.swift`, `HeaderBar.swift`

**Interfaces:** Consumes `AppModel.homeItems`, `filters`, `ProjectFilterSet`, `KindFilter`, `GitFilter`, `CollectionMode`, `availableFrameworks`, `breadcrumbs(for:)`, `goBack()`, `RunAction`, `availableActions(for:)`, `run(_:for:)`.

- [ ] **Step 1:** Model-level behaviour is already tested in `NexAppTests` (filters, breadcrumbs). Add `LinuxViewSmokeTests.homeBuildsForEveryEmptyState` (constructs `HomePage` for each `EmptyStateKind` without crashing).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement: greeting, project grid (`Adw.Clamp` + flow box), card with Run split button (actions from `availableActions`), git badge, pin; header with view switch, filter popover (Type, Framework, Collections, Git, Running/Pinned), search entry, Add project; breadcrumbs in the header title widget on collection and project pages.
- [ ] **Step 4:** CI green; manual check list items 1-4 (Task 13).
- [ ] **Step 5:** Commit: `linux: home, filters and collections`.

### Task 8: Project page, logs and setup

**Files:** Create `Sources/NexLinux/ProjectPage.swift`, `LogsView.swift`, `SetupDialog.swift`, `AddProjectDialog.swift`

**Interfaces:** Consumes `AppModel.run`, `confirmInstall`, `cancelInstall`, `setup`, `processes.logs[ServiceID]`, `createProject(name:in:initGit:)`, `cloneProject(url:name:in:onLine:)`, `DetailTab`.

- [ ] **Step 1:** `LinuxViewSmokeTests.projectPageEveryTab` (builds the page for each `DetailTab`).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement header (icon tile, name, subtitle, Run, pin, terminal, reveal, Ask AI), `Adw.ViewSwitcher` tabs, live logs (`Gtk.TextView`, auto-scroll), setup dialog with steps and Cancel, Add project dialog (new folder / clone with progress).
- [ ] **Step 4:** CI green; manual check list items 5-7.
- [ ] **Step 5:** Commit: `linux: project page, logs, setup and add project`.

### Task 9: Git panel, Tasks and Flutter devices

**Files:** Create `Sources/NexLinux/GitPanel.swift`, `TasksPage.swift`, `IdentityDialog.swift`, `FlutterPage.swift`

**Interfaces:** Consumes `GitModel` (stage, commit, pull, push, branches, history, identity), `AppModel.tasks(for:)`, `addTask(title:notes:project:)`, `setTaskDone(_:_:)`, `deleteTask(_:)`, `draftAgentTask(_:project:)`, `DevicesModel` (Android emulators and `flutter devices`; the iOS section is hidden when `Platform.supportsIOSSimulators` is false).

- [ ] **Step 1:** `LinuxViewSmokeTests.gitPanelWithoutRepo`, `tasksPageEmpty`, and `NexAppTests.DevicesLinuxModelTests.noIOSSectionOnLinux` (`DevicesModel` with `HostOS.linux` never runs `xcrun`).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement, matching the Mac panel's sections and button labels.
- [ ] **Step 4:** CI green; manual check list item 8.
- [ ] **Step 5:** Commit: `linux: git panel and tasks`.

### Task 10: AI page and Ask AI side panel

**Files:** Create `Sources/NexLinux/AIPage.swift`, `AgentRunRow.swift`, `ProjectAIPanel.swift`

**Interfaces:** Consumes `AgentCatalog`, `AgentKind`, `AgentAutonomy`, `startAgent`, `continueAgent`, `stopAgent`, `agentRuns(for:)`, `aiPanelProjectID`, `toggleAIPanel(for:)`. Antigravity on Linux: CLI only (when `agents.hasCommandLine(.antigravity)` is false, show the install command, never "Open in Antigravity").

- [ ] **Step 1:** `NexAppTests.AgentsLinuxTests.antigravityWithoutCLIDoesNotOpenApp` (with `HostOS.linux` injected, `startAgent(.antigravity…)` returns nil, sets `agentError`, and records no `open(_:withApplicationAt:)`).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement the agents grid, composer, runs list with streamed events, reply box; side panel via `Adw.OverlaySplitView` on the project page.
- [ ] **Step 4:** CI green; manual check list item 9.
- [ ] **Step 5:** Commit: `linux: AI assistant and Ask AI panel`.

### Task 11: Terminal (VTE), settings, onboarding, autostart, notifications

**Files:**
- Create: `Sources/CVte/module.modulemap` + `shim.h` (system library target, `pkgConfig: "vte-2.91-gtk4"`), `Sources/NexLinux/TerminalView.swift`, `LinuxTerminalHost.swift`, `SettingsPage.swift`, `OnboardingWindow.swift`, `LinuxLoginItem.swift`, `LinuxNotifier.swift`
- Test: `Tests/NexAppTests/LinuxOnboardingTests.swift`, `Tests/NexCoreTests/LinuxLoginItemTests.swift`

**Interfaces:**
- Consumes: `TerminalHost`, `LoginItemControlling`, `Notifying`, `OnboardingModel`, `HostCommand`
- Produces: `LinuxTerminalHost` (VTE spawn via `vte_terminal_spawn_async` of `HostCommand.shell`'s invocation); `LinuxLoginItem` writes `~/.config/autostart/net.nexventures.NexLauncher.desktop` (`Exec=flatpak run net.nexventures.NexLauncher` inside Flatpak, the binary path otherwise); `LinuxNotifier` uses `GNotification`.

- [ ] **Step 1: Failing tests:** `LinuxLoginItemTests.writesAutostartFile` (enable → file with `Exec=` and `X-GNOME-Autostart-enabled=true`; disable → file removed); `LinuxOnboardingTests.missingFolderOffersChoice` (defaults with no `~/Projects`/`~/Documents` → `OnboardingModel.folderExists == false` and the projects step requires a choice).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement; settings sections Profile, Git, AI, Appearance (system/light/dark, themes via CSS), Notifications, General (autostart, projects folder), Projects (overrides). No Dock/widgets/menu-bar settings on Linux.
- [ ] **Step 4:** CI green; manual check list items 10-12.
- [ ] **Step 5:** Commit: `linux: terminal, settings, onboarding, autostart and notifications`.

## Phase 4: Packaging and release

### Task 12: Flatpak

**Files:**
- Create: `linux/net.nexventures.NexLauncher.yml` (runtime `org.gnome.Platform` current stable, SDK extension for Swift 6, `--static-swift-stdlib`; finish-args `--share=network --share=ipc --socket=wayland --socket=fallback-x11 --device=dri --filesystem=home --talk-name=org.freedesktop.Flatpak --talk-name=org.freedesktop.Notifications`), `linux/net.nexventures.NexLauncher.desktop`, `linux/net.nexventures.NexLauncher.metainfo.xml`, `linux/icons/` (256, 512 from `Resources/AppIcon.icns`)
- Create: `.github/workflows/linux-release.yml` (on tag `v*`: `flatpak-builder` for x86_64 on `ubuntu-24.04` and aarch64 on `ubuntu-24.04-arm`, upload `NexLauncher-<v>-linux-<arch>.flatpak` as artifacts)

- [ ] **Step 1:** `appstreamcli validate` and `desktop-file-validate` run in the workflow; expect FAIL before the files exist.
- [ ] **Step 2:** Add the files; workflow builds both bundles.
- [ ] **Step 3:** Manual check list (below) on a Linux desktop, run from the bundle with `flatpak install --user`.
- [ ] **Step 4:** Commit: `linux: Flatpak packaging and release workflow`.

### Task 13: Manual check list (Linux desktop, inside the Flatpak)

Run once before release on Ubuntu 24.04 GNOME (Wayland) and Fedora 41 (KDE, X11). Each item is pass/fail.

1. Onboarding with no `~/Projects`: choose a folder; projects appear.
2. Sidebar counts equal the cards shown for each section.
3. Filters: Type Flutter + Collections Hide; clearing restores everything.
4. Breadcrumbs and Back on a project inside a collection.
5. Run Both on a Vite + FastAPI project; logs stream; port opens in the browser.
6. Stop and Quit: `ps -eo pgid,cmd` on the host shows nothing left from the project.
7. Missing `node_modules`: setup dialog asks, installs, then runs.
8. Git: commit and push using the host's SSH key.
9. Ask AI with Claude Code in Plan only; the run streams and finishes.
10. Terminal opens in `~/Projects/Café App` and `nvm`'s node is on PATH.
11. Launch at login: log out and in; app starts.
12. Light/dark follows the system; Ember accent on buttons.

### Task 14: Release 4.0.0 on the website

**Files:**
- Modify: `site/js/site.js` (chooser gains "Linux" options per arch; detect `navigator.userAgent` containing `Linux` to preselect), `site/index.html`, `site/how-it-works.html` (Linux install section: `flatpak install --user ./NexLauncher-4.0.0-linux-x86_64.flatpak`), `site/contribute.html` (Linux build: `apt install libadwaita-1-dev libgtk-4-dev libvte-2.91-gtk4-dev`, `swift run NexLinux`), `README.md`
- Create: `supabase/migrations/<timestamp>_linux_downloads.sql` (allow `arch` values `linux-x86_64`, `linux-aarch64`; `record_download` accepts them)
- Data: release `4.0.0` row with `files` for `arm64`, `x86_64`, `linux-x86_64`, `linux-aarch64`, changelog entry; uploads through a temporary per-file storage policy removed afterwards (as for 3.1.0)

- [ ] **Step 1:** Extend the chooser test page logic; verify in the browser that Linux user agents preselect Linux and Mac ones don't.
- [ ] **Step 2:** Apply the migration; `record_download('4.0.0', 'linux-x86_64')` returns the Linux bundle path.
- [ ] **Step 3:** Upload, insert the release, deploy the site, check the live chooser.
- [ ] **Step 4:** Commit: `release: NexLauncher 4.0.0 with Linux`.
