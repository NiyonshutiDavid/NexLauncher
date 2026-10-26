# NexLauncher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS app that auto-detects projects in `~/Documents/Nexventures`, runs their frontend/backend/Flutter targets, offers GitHub-Desktop-style git operations, and exposes status via menu bar and desktop widgets.

**Architecture:** A SwiftPM package of four library targets (`NexCore`, `NexProcess`, `NexGit`, `NexUI`) plus an executable app target; logic lives in libraries and is unit-tested, the SwiftUI app only composes them. A WidgetKit extension reads state the app writes to a shared App Group file. `build.sh` assembles, signs and installs the `.app`.

**Tech Stack:** Swift 6.2, SwiftUI (Liquid Glass `glassEffect`), WidgetKit + App Intents, `SMAppService`, Swift Testing, system `/usr/bin/git`, Xcode 26.0 / macOS 26.5.

**Spec:** `docs/superpowers/specs/2026-10-26-nexlauncher-design.md`

## Global Constraints

- Platform: macOS 26+ (`.macOS(.v26)`); no macOS 27 APIs.
- Scan root default: `~/Documents/Nexventures`; skip `node_modules`, `.git`, `build`, `dist`, `.next`, `.dart_tool`, `venv`, `.venv`, and the `NexLauncher` folder; recurse two levels.
- Roles come from manifests, never from folder names.
- Services run as `/bin/zsh -lc "<command>"` in their own process group; Stop = SIGTERM then SIGKILL after a timeout.
- Git uses `/usr/bin/git` with porcelain output; pull is `--ff-only` by default; never force-push; app never stores credentials.
- Greeting variants: morning / afternoon / evening / night, using the display name (default: Mac account first name).
- Personal-use app, not App Store.

## Review Focus

- Project folder names containing spaces (e.g. `BTN Limited Management system`, `Kigali Height Proposal`): commands and git calls must not break. Test in Tasks 3 and 5.
- Malformed or unreadable `package.json` / empty Nexventures folder / symlink loops: scanner skips and continues. Test in Task 2.
- A process that exits immediately or ignores SIGTERM: state becomes `.failed`/`.stopped`, no orphan remains. Test in Task 4.
- Log output with ANSI colour codes (Vite, Django): port parsing still works. Test in Task 4.
- Repo with no commits, detached HEAD, or no upstream: status/push do not crash and say what is missing. Tests in Tasks 5 and 6.
- Pull that cannot fast-forward, and commit with nothing staged or an empty message: a clear typed error, repo left untouched. Test in Task 6.

---

### Task 1: Package skeleton and core models

**Files:**
- Create: `Package.swift`, `Sources/NexCore/Models.swift`, `Tests/NexCoreTests/ModelsTests.swift`, `.gitignore`

**Interfaces:**
- Produces:
  - `enum ServiceKind: String, Codable, Sendable { case frontend, backend, flutter, docker }`
  - `struct ServiceTarget: Codable, Hashable, Sendable { let kind: ServiceKind; let directory: URL; let framework: String?; var command: String }`
  - `struct Project: Identifiable, Codable, Hashable, Sendable { let id: String; let name: String; let root: URL; var targets: [ServiceTarget]; var isFullStack: Bool }` where `isFullStack` is true iff targets contain both `.frontend` and `.backend`.
  - `struct Greeter { static func greeting(for date: Date, name: String, calendar: Calendar) -> String }`

- [ ] **Step 1: Write failing tests** in `ModelsTests.swift`: `fullStackWhenFrontendAndBackend`, `notFullStackWithFrontendOnly`, `greetingMorningAt9` ("Good morning, David"), `greetingAfternoonAt14`, `greetingEveningAt19`, `greetingNightAt23` and at 03:00 ("Good night, David").
- [ ] **Step 2: Run** `swift test` — Expected: FAIL (types missing).
- [ ] **Step 3: Implement** `Package.swift` declaring targets `NexCore`, `NexProcess`, `NexGit`, `NexUI`, executable `NexLauncher`, and matching test targets; implement models and `Greeter` (morning 05–11, afternoon 12–17, evening 18–21, else night). Add `.build/` and `*.app` to `.gitignore`.
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: package skeleton, models, greeter`.

### Task 2: ProjectScanner

**Files:**
- Create: `Sources/NexCore/ProjectScanner.swift`, `Tests/NexCoreTests/ProjectScannerTests.swift`, `Tests/NexCoreTests/Fixtures.swift` (helper that builds a temp tree)

**Interfaces:**
- Consumes: `Project`, `ServiceTarget`, `ServiceKind` (Task 1).
- Produces: `struct ProjectScanner { init(skipNames: Set<String> = ProjectScanner.defaultSkips); func scan(root: URL) -> [Project] }`; `static let defaultSkips: Set<String>`.

- [ ] **Step 1: Write failing tests**, each building a temp tree: `djangoPlusViteIsFullStack` (CleanPay layout: `frontend/package.json` with `dev` script + vite dep, `backend/manage.py`); `differentFolderNamesStillDetected` (`client` + `server`, `web` + `api`); `flutterDetectedFromPubspec`; `dockerComposeDetected`; `nodeModulesIgnored`; `frontendOnlyProject`; `scriptlessPackageJsonIsNotFrontend`; `malformedPackageJsonSkippedNotCrash`; `emptyRootReturnsEmpty`; `symlinkLoopTerminates`; `folderWithSpacesKeepsName` ("Kigali Height Proposal"); `nexLauncherFolderSkipped`.
- [ ] **Step 2: Run** `swift test --filter ProjectScannerTests` — Expected: FAIL.
- [ ] **Step 3: Implement** `ProjectScanner.scan`: for each child dir, collect manifest-based targets up to depth 2 using the rules in spec §1 (frontend = `package.json` with `dev`/`start` script and no backend-style deps; backend = `manage.py`, FastAPI/Flask in `requirements.txt`, or Express/Nest deps; framework from dependencies). Default `command` strings come from Task 3's builder, so leave `command` as an empty string here and let Task 3 fill it. Track visited real paths to stop symlink loops. Sort projects by name.
- [ ] **Step 4: Run** tests — Expected: PASS.
- [ ] **Step 5: Commit** `feat: project scanner with manifest-based detection`.

### Task 3: CommandBuilder and project overrides

**Files:**
- Create: `Sources/NexCore/CommandBuilder.swift`, `Sources/NexCore/OverrideStore.swift`, `Tests/NexCoreTests/CommandBuilderTests.swift`

**Interfaces:**
- Consumes: `ServiceTarget` (Task 1).
- Produces:
  - `struct CommandBuilder { static func command(for kind: ServiceKind, at directory: URL, framework: String?, flutterDevice: String?) -> String; static func needsInstall(_ target: ServiceTarget) -> Bool; static func installCommand(for target: ServiceTarget) -> String }`
  - `struct Override: Codable { var kind: ServiceKind?; var command: String?; var port: Int? }`; `final class OverrideStore { init(fileURL: URL); func override(forPath: String) -> Override?; func set(_: Override?, forPath: String) }`
  - Scanner gains `func scan(root:)` now filling `ServiceTarget.command` via `CommandBuilder` and applying `OverrideStore`.

- [ ] **Step 1: Write failing tests**: `nodeUsesNpmRunDev`, `nodeFallsBackToStart`, `djangoUsesVenvPythonWhenPresent`, `djangoPlainPython3WithoutVenv`, `flutterIncludesDevice` (`flutter run -d macos`), `dockerComposeUp`, `needsInstallWhenNodeModulesMissing`, `pathWithSpacesIsQuoted` (command contains the directory single-quoted, e.g. `cd 'BTN Limited Management system/apps'`), `overridePersistsAcrossReload`, `overrideCommandReplacesDefault`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** as specified; shell-quote with single quotes escaping embedded quotes; `OverrideStore` persists JSON at the given URL.
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: command builder and per-project overrides`.

### Task 4: ProcessManager

**Files:**
- Create: `Sources/NexProcess/ProcessManager.swift`, `Sources/NexProcess/PortParser.swift`, `Tests/NexProcessTests/ProcessManagerTests.swift`

**Interfaces:**
- Consumes: `ServiceTarget` (Task 1).
- Produces:
  - `enum ServiceState: Equatable, Sendable { case stopped, starting, running(port: Int?), failed(String) }`
  - `struct ServiceID: Hashable, Sendable { let projectID: String; let kind: ServiceKind }`
  - `@MainActor @Observable final class ProcessManager { var states: [ServiceID: ServiceState]; var logs: [ServiceID: [String]]; func start(_ target: ServiceTarget, projectID: String); func stop(_ id: ServiceID) async; func stopAll() async; var runningCount: Int }`
  - `enum PortParser { static func port(in line: String) -> Int? }` (strips ANSI escapes, matches `localhost:NNNN`, `127.0.0.1:NNNN`, `port NNNN`, `0.0.0.0:NNNN`).

- [ ] **Step 1: Write failing tests**: `parsesVitePortWithAnsi` (`"\u{1B}[32m  ➜  Local:   http://localhost:5173/\u{1B}[0m"` → 5173), `parsesDjangoPort`, `noPortReturnsNil`, `startCapturesLogLines` (target command `echo hi; sleep 30`), `stopTerminatesGroupAndChildren` (command spawns `sleep 300 &` then waits; after `stop`, no process with that PID exists), `stopEscalatesToSigkill` (command `trap '' TERM; sleep 300`), `immediateExitBecomesStopped` or `.failed` with non-zero exit code and last log line, `missingDirectoryGivesFailedState`, `stopAllLeavesNoRunning`, `logsCapAt5000Lines`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** with `Foundation.Process` launching `/bin/zsh -lc`, `setpgid`-style new process group (via `posix_spawn` attributes or `Process` plus `setsid` wrapper `exec`), pipe readers appending lines on the main actor, SIGTERM to the negative PGID then SIGKILL after 3 s.
- [ ] **Step 4: Run** `swift test --filter NexProcessTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: process manager with group-kill and port detection`.

### Task 5: GitService — read side and identity

**Files:**
- Create: `Sources/NexGit/GitRunner.swift`, `Sources/NexGit/GitModels.swift`, `Sources/NexGit/GitService.swift`, `Tests/NexGitTests/GitServiceReadTests.swift`, `Tests/NexGitTests/TempRepo.swift`

**Interfaces:**
- Produces:
  - `enum GitError: Error, Equatable { case notARepo, commandFailed(code: Int32, stderr: String), timeout, noUpstream, nothingToCommit, emptyMessage, cannotFastForward, conflicts([String]), authFailed(String) }`
  - `struct GitRunner { func run(_ args: [String], in dir: URL, timeout: TimeInterval = 30) async throws -> String }`
  - `struct FileChange: Hashable, Sendable { let path: String; let index: Character; let worktree: Character; var isStaged: Bool; var isUntracked: Bool }`
  - `struct RepoStatus: Sendable { let branch: String?; let upstream: String?; let ahead: Int; let behind: Int; let changes: [FileChange]; let isDetached: Bool; let hasCommits: Bool }`
  - `struct CommitInfo: Identifiable, Sendable { let id: String; let subject: String; let author: String; let date: Date }`
  - `struct GitIdentity: Equatable, Sendable { var name: String?; var email: String? }`; `enum GitScope { case global, repo }`
  - `struct GitService { init(runner: GitRunner = GitRunner()); func findRepos(under project: URL) -> [URL]; func status(_ repo: URL) async throws -> RepoStatus; func diff(_ repo: URL, file: FileChange) async throws -> String; func log(_ repo: URL, limit: Int) async throws -> [CommitInfo]; func branches(_ repo: URL) async throws -> [String]; func identity(_ repo: URL, scope: GitScope) async throws -> GitIdentity; func setIdentity(_ id: GitIdentity, repo: URL, scope: GitScope) async throws }`

- [ ] **Step 1: Write failing tests** using `TempRepo` (runs real `git init` in a temp dir, local identity configured so tests never touch global config): `statusCleanRepo`, `statusShowsUntrackedAndModified`, `statusStagedVsUnstaged`, `statusInEmptyRepoHasNoCommits`, `statusDetachedHead`, `statusWithoutUpstreamHasNilUpstream`, `statusAheadBehindAgainstBareRemote`, `notARepoThrows`, `pathWithSpaces` (repo under `My Project/api`), `diffReturnsUnifiedDiff`, `logReturnsNewestFirst`, `branchesListsLocal`, `setAndReadRepoIdentity`, `findReposFindsNestedRepos` (two repos under one project dir).
- [ ] **Step 2: Run** `swift test --filter NexGitTests` — Expected: FAIL.
- [ ] **Step 3: Implement** via `git status --porcelain=v2 --branch`, `git diff`, `git log --format`, `git branch --format`, `git config [--global] --get/--set`; `GitRunner` uses `Process` with arguments array (no shell), `GIT_TERMINAL_PROMPT=0`, and a timeout.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat: git read operations and identity`.

### Task 6: GitService — write side

**Files:**
- Modify: `Sources/NexGit/GitService.swift`
- Test: `Tests/NexGitTests/GitServiceWriteTests.swift`

**Interfaces:**
- Consumes: Task 5 types.
- Produces on `GitService`: `func stage(_ repo: URL, paths: [String]) async throws`, `func unstage(_ repo: URL, paths: [String]) async throws`, `func discard(_ repo: URL, paths: [String]) async throws`, `func commit(_ repo: URL, summary: String, description: String) async throws`, `func fetch(_ repo: URL) async throws`, `enum PullStrategy { case ffOnly, merge, rebase }`, `func pull(_ repo: URL, strategy: PullStrategy) async throws`, `func push(_ repo: URL) async throws`, `func switchBranch(_ repo: URL, to: String) async throws`, `func createBranch(_ repo: URL, named: String) async throws`.

- [ ] **Step 1: Write failing tests** (local bare remote as origin): `stageThenCommitCreatesCommit`, `commitWithEmptySummaryThrowsEmptyMessage`, `commitWithNothingStagedThrowsNothingToCommit`, `commitIncludesDescriptionBody`, `unstageRestoresIndex`, `discardRevertsTrackedAndDeletesUntrackedOnlyWhenListed`, `pushSetsUpstreamWhenMissing`, `pushNeverForces` (diverged remote → error, remote history intact), `pullFastForwards`, `pullNonFastForwardThrowsCannotFastForwardAndLeavesTreeClean`, `pullMergeConflictThrowsConflictsWithFileList`, `pullWithNoUpstreamThrowsNoUpstream`, `switchAndCreateBranch`, `authFailureMappedToAuthFailed` (simulate with stderr text containing "Authentication failed" via a stub runner).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** using `git add`, `restore --staged`, `restore` / `clean -f -- <paths>`, `commit -m summary [-m description]`, `pull --ff-only|--no-rebase|--rebase`, `push` (with `-u origin <branch>` if no upstream); map stderr patterns to `GitError` cases. Never pass `--force`.
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: git stage, commit, pull, push, branches`.

### Task 7: App state, settings and shared widget snapshot

**Files:**
- Create: `Sources/NexCore/Settings.swift`, `Sources/NexCore/WidgetSnapshot.swift`, `Tests/NexCoreTests/SettingsTests.swift`

**Interfaces:**
- Produces:
  - `struct AppSettings: Codable, Equatable { var displayName: String; var scanRoot: URL; var showDockIcon: Bool; var pinnedProjectIDs: [String]; static func defaults() -> AppSettings }` (`displayName` default = first word of `NSFullUserName()`, falling back to `"there"`), and `final class SettingsStore { init(fileURL: URL); var settings: AppSettings; func save() }`.
  - `struct WidgetSnapshot: Codable, Equatable { struct Running: Codable, Equatable { let projectName: String; let kind: ServiceKind; let port: Int? }; var running: [Running]; var pinned: [PinnedProject]; struct PinnedProject: Codable, Equatable { let id: String; let name: String } }` and `enum SharedContainer { static let groupID = "group.net.nexventures.nexlauncher"; static func write(_: WidgetSnapshot); static func read() -> WidgetSnapshot }` (falls back to `~/Library/Application Support/NexLauncher/` when the group container is unavailable).

- [ ] **Step 1: Write failing tests**: `defaultsUseFirstNameFromFullName`, `settingsRoundTripThroughDisk`, `corruptSettingsFileFallsBackToDefaults`, `snapshotRoundTrip`, `missingSnapshotReadsEmpty`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** as above (JSON files, atomic writes).
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat: settings store and shared widget snapshot`.

### Task 8: App shell, greeting and project grid

**Files:**
- Create: `Sources/NexLauncher/NexLauncherApp.swift`, `Sources/NexUI/AppModel.swift`, `Sources/NexUI/GreetingHeader.swift`, `Sources/NexUI/ProjectCard.swift`, `Sources/NexUI/ProjectGridView.swift`, `Tests/NexUITests/AppModelTests.swift`

**Interfaces:**
- Consumes: `ProjectScanner`, `OverrideStore`, `ProcessManager`, `SettingsStore`, `GitService`.
- Produces: `@MainActor @Observable final class AppModel { var projects: [Project]; var searchText: String; var filteredProjects: [Project]; func refresh() async; let processes: ProcessManager; let git: GitService; let settings: SettingsStore }`; `ProjectCard(project:)` showing name, badges (Full-stack / Frontend / Backend / Flutter / Docker), and a git badge placeholder.

- [ ] **Step 1: Write failing tests**: `refreshLoadsProjectsFromScanner` (temp root with two projects), `searchFiltersByNameCaseInsensitively`, `refreshWithMissingRootGivesEmptyListNotCrash`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the model; build the window with `NavigationSplitView`, glass cards via `glassEffect(.regular, in: .rect(cornerRadius: 20))` inside a `GlassEffectContainer`, `GreetingHeader` using `Greeter`, search field and Refresh button. App entry is a `WindowGroup`.
- [ ] **Step 4: Run** `swift test` and `swift build` — Expected: PASS, build succeeds.
- [ ] **Step 5: Commit** `feat: app shell with greeting and project grid`.

### Task 9: Run controls and log panel

**Files:**
- Create: `Sources/NexUI/RunControls.swift`, `Sources/NexUI/LogPanel.swift`, `Sources/NexUI/FlutterDevicePicker.swift`
- Modify: `Sources/NexUI/ProjectCard.swift`, `Sources/NexUI/AppModel.swift`
- Test: `Tests/NexUITests/RunActionsTests.swift`

**Interfaces:**
- Produces on `AppModel`: `func run(_ project: Project, kinds: Set<ServiceKind>) async` (runs install first when `CommandBuilder.needsInstall`, after confirmation flag `installConfirmed`), `func stop(_ project: Project) async`, `func availableActions(for project: Project) -> [RunAction]` where `enum RunAction { case frontend, backend, both, flutter, docker }`; `func flutterDevices() async -> [String]` parsing `flutter devices --machine`.

- [ ] **Step 1: Write failing tests**: `fullStackOffersFrontendBackendBoth`, `frontendOnlyOffersOnlyFrontend`, `flutterOfferedOnlyWhenPubspecPresent`, `bothStartsTwoServices` (dummy commands), `runWithMissingNodeModulesRequestsInstall`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the actions and the UI: buttons per available action, Stop, state pill, "Open in browser" when a port is known, collapsible log panel with auto-scroll, Flutter device picker sheet.
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: run controls, logs and flutter device picker`.

### Task 10: Git panel UI

**Files:**
- Create: `Sources/NexUI/GitPanelView.swift`, `Sources/NexUI/GitModel.swift`, `Sources/NexUI/DiffView.swift`, `Sources/NexUI/IdentitySheet.swift`
- Modify: `Sources/NexUI/ProjectCard.swift` (git badge: clean / N changes / ↑ahead ↓behind)
- Test: `Tests/NexUITests/GitModelTests.swift`

**Interfaces:**
- Consumes: `GitService` (Tasks 5–6).
- Produces: `@MainActor @Observable final class GitModel { init(repo: URL, service: GitService); var status: RepoStatus?; var selectedFile: FileChange?; var diffText: String; var summary: String; var descriptionText: String; var errorMessage: String?; var isBusy: Bool; func reload() async; func toggleStage(_: FileChange) async; func commit() async; func pull(strategy: PullStrategy) async; func push() async; func fetch() async; var identity: GitIdentity; func saveIdentity(_: GitIdentity, scope: GitScope) async }`.

- [ ] **Step 1: Write failing tests** against a `TempRepo`: `reloadPopulatesStatus`, `commitClearsFieldsAndRefreshes`, `commitWithEmptySummarySetsErrorMessage`, `pullNonFastForwardOffersMergeChoice` (model exposes `pendingPullChoice == true`), `pushErrorSurfacesStderr`, `firstRunPromptsWhenIdentityMissing` (`needsIdentity == true`).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the model and the GitHub-Desktop-style split view: changed-files list with checkboxes and the diff on the right, summary/description box, Commit, Pull, Push, Fetch toolbar, branch menu, history tab, repo picker when a project contains several repos, discard confirmation dialog, identity sheet.
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: git panel UI`.

### Task 11: Menu bar and quit behaviour

**Files:**
- Create: `Sources/NexUI/MenuBarContent.swift`
- Modify: `Sources/NexLauncher/NexLauncherApp.swift`
- Test: `Tests/NexUITests/MenuBarModelTests.swift`

**Interfaces:**
- Produces: `MenuBarContent(model: AppModel)`; `AppModel.menuBarTitle: String` (e.g. `"3 running"` / `""`); `AppModel.shouldConfirmQuit: Bool` (true when `runningCount > 0`); `func applyDockIconPolicy()` toggling `NSApp.setActivationPolicy`.

- [ ] **Step 1: Write failing tests**: `menuBarTitleReflectsRunningCount`, `confirmQuitOnlyWhenServicesRunning`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** `MenuBarExtra(.window)` with project list, quick Run/Stop, change counts, "Open window", Quit; quit prompt "Stop services / Keep running in menu bar / Cancel"; closing the window keeps the app alive.
- [ ] **Step 4: Run** `swift test` and `swift build` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: menu bar extra and quit confirmation`.

### Task 12: Settings window and launch at login

**Files:**
- Create: `Sources/NexUI/SettingsView.swift`, `Sources/NexCore/LoginItem.swift`
- Test: `Tests/NexCoreTests/LoginItemTests.swift`

**Interfaces:**
- Produces: `protocol LoginItemControlling { var isEnabled: Bool { get }; func setEnabled(_: Bool) throws }`; `struct SMLoginItem: LoginItemControlling` backed by `SMAppService.mainApp`.

- [ ] **Step 1: Write failing test** with a fake controller: `toggleCallsSetEnabled`, `failureSurfacedNotSwallowed`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the Settings scene: launch-at-login toggle, display name, scan root picker, Dock icon toggle, pinned projects, per-project override editor.
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: settings window and launch at login`.

### Task 13: Widgets, packaging and install script

**Files:**
- Create: `Widgets/NexWidgets.swift`, `Widgets/Info.plist`, `Widgets/NexWidgets.entitlements`, `Resources/NexLauncher.entitlements`, `Resources/Info.plist`, `build.sh`
- Modify: `Sources/NexUI/AppModel.swift` (write `WidgetSnapshot` and call `WidgetCenter.shared.reloadAllTimelines()` on every service state change and pin change)

**Interfaces:**
- Consumes: `WidgetSnapshot`, `SharedContainer` (Task 7).
- Produces: widgets `RunningServicesWidget` (kind `"RunningServices"`) and `QuickLaunchWidget` (kind `"QuickLaunch"`), App Intent `StartProjectIntent(projectID: String)` that opens the app via URL scheme `nexlauncher://run?project=<id>` handled in `NexLauncherApp`; `./build.sh [--install]`.

- [ ] **Step 1: Write failing test** `Tests/NexCoreTests/SnapshotPublishTests.swift`: `modelPublishesSnapshotWhenServiceStarts` (AppModel with an injected publisher closure receives running list).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** snapshot publishing, URL handler, widget views (small/medium), and `build.sh`: `swift build -c release`, assemble `NexLauncher.app/Contents/{MacOS,Resources,PlugIns/NexWidgets.appex}`, compile the widget with `swiftc` against WidgetKit as an app-extension (`-application-extension`), codesign with the user's team identity found by `security find-identity -v -p codesigning` (ad-hoc `-` if none), then copy to `/Applications` with `--install`. If the widget cannot be signed this way, create a minimal `NexWidgets.xcodeproj` for the extension only and have `build.sh` call `xcodebuild` for it.
- [ ] **Step 4: Run** `swift test` and `./build.sh` — Expected: tests PASS; `NexLauncher.app` produced; `codesign --verify --deep NexLauncher.app` exits 0.
- [ ] **Step 5: Commit** `feat: widgets, packaging and build script`.

### Task 14: End-to-end verification against the real folder

**Files:**
- Modify: `README.md` (create) with build/install/usage notes

- [ ] **Step 1: Run** `./build.sh --install` and launch the app. Expected: greeting shows "Good <time>, David"; the grid shows the projects, with CleanPay, NVMS, blessedlawfirm, Kigali Height Proposal and DRD_tracking_system tagged Full-stack and Jarama/ijwi showing Flutter.
- [ ] **Step 2: Run** one real project (e.g. `Nexventures-revampsite` Frontend) from the card. Expected: log shows Vite output, the port appears with an Open button, Stop leaves no `node` process (`pgrep -fl vite` empty).
- [ ] **Step 3: Test git** in a scratch clone (not a real project): set identity, edit a file, stage, commit, push to a local bare remote, pull. Expected: each action succeeds and the badge updates.
- [ ] **Step 4: Verify** menu bar item appears with running count, the Launch-at-login toggle registers (System Settings → Login Items shows NexLauncher), and both widgets can be added from the desktop widget gallery and show data.
- [ ] **Step 5: Commit** `docs: README and verification notes`.
