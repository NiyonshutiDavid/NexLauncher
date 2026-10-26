# NexLauncher v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign NexLauncher in an App Store style with CTA cards and illustrations, add nested-project detection with a Cards/Folders switch, an embedded terminal, Add Project (new folder / clone), and an in-window profile + Settings with themes based on nexventures.net.

**Architecture:** Pure logic (palettes, scanner tree, CTA ranking, project creation, settings) lives in testable library targets (`NexCore`, `NexGit`, `NexUI` models); SwiftUI views only compose it. The terminal is isolated in a new `NexTerminal` target that wraps SwiftTerm. A `Theme` value in the SwiftUI environment is the single source of colour.

**Tech Stack:** Swift 6.2 (language mode 5), SwiftUI, Swift Testing, SwiftTerm 1.5.0 (`https://github.com/migueldeicaza/SwiftTerm.git`, `from: "1.5.0"`), system `/usr/bin/git`.

**Spec:** `docs/superpowers/specs/2026-10-26-nexlauncher-v2-design.md` (builds on v1: `docs/superpowers/specs/2026-10-26-nexlauncher-design.md`)

## Global Constraints

- macOS 26+ only; Liquid Glass (`glassEffect`) only on sidebar, toolbar and buttons; cards are solid surfaces, radius 22, hairline in dark, soft shadow in light.
- Light tokens: canvas `#f7f8fa`, surface `#ffffff`, fg `#0b0d12`, fg2 `#454c5a`, fg3 `#697285`, line `#e2dfdb`, accent `#cf3f0e`, accent hover `#a8320b`, accent soft `#fff0e8`.
- Dark tokens: canvas `#07080c`, surface `#0f1117`, fg `#f3f4f7`, fg2 `#aeb4c2`, fg3 `#767d8f`, line `#2c3140`, accent `#f0561f`, accent hover `#ff7440`, accent soft `#2a140c`.
- Themes: `ember` (default, the tokens above), `ocean`, `forest`, `violet`, `graphite`; themes change only accent / hover / soft. Appearance: system (default) / light / dark.
- Illustrations are drawn in SwiftUI (no image assets, no network) and use only theme tokens.
- CTA shelf shows at most 3 cards, ranked, dismissible, dismissal persisted by id.
- Scanner descends at most 4 levels, skips `node_modules`, `.git`, `build`, `dist`, `.next`, `.dart_tool`, `venv`, `.venv`, `NexLauncher`, never follows symlink loops, and stays off the main thread.
- Git and process invocations use argument arrays (never shell strings built from user input); `git clone` is always called with `--` before the URL.
- `settings.json` written by v1 must keep loading (every new key optional with a default).
- New `NexCore` files must compile inside the widget extension (Foundation only; `build.sh` compiles all of `Sources/NexCore/*.swift` except `LoginItem.swift`).

## Review Focus

- A v1 `settings.json` (only `displayName`, `scanRoot`, `showDockIcon`, `pinnedProjectIDs`) loads with all v2 defaults. Test in Task 1.
- Clone / new-folder names and URLs: `..`, `a/b`, empty, existing folder, spaces, a URL starting with `-` (option injection), cancel mid-clone leaves no partial folder. Tests in Task 9.
- Collection heuristic against the real tree (`intern-sessions`, `mobileapp-sessions`, `Centerpiece`, `Jarama`) and a large tree staying fast: fixtures in Task 3 plus a depth/skip test.
- Terminal in a folder whose name has spaces or quotes; closing a tab ends its shell; quitting warns when a foreground program is running. Tests in Task 8.
- Every theme × light/dark meets contrast (text on surface ≥ 4.5, secondary text ≥ 3, on-accent text on accent ≥ 4.5) and every illustration renders in every combination. Tests in Tasks 2 and 6.

---

### Task 1: Settings v2 keys with backward-compatible decoding

**Files:**
- Modify: `Sources/NexCore/Settings.swift`
- Test: `Tests/NexCoreTests/SettingsV2Tests.swift`

**Interfaces:**
- Produces: `enum AppearanceMode: String, Codable, CaseIterable, Sendable { case system, light, dark }`; `enum ThemeID: String, Codable, CaseIterable, Sendable { case ember, ocean, forest, violet, graphite }`; `enum ViewMode: String, Codable, Sendable { case cards, folders }`; `enum PullPreference: String, Codable, Sendable { case ffOnly, merge, rebase }`; `struct LastRun: Codable, Equatable, Sendable { var projectID: String; var action: String }`.
- `AppSettings` gains: `appearance = .system`, `theme = .ember`, `viewMode = .cards`, `dismissedCTAs: Set<String> = []`, `avatarColorHex: String? = nil`, `avatarPhotoPath: String? = nil`, `lastRun: LastRun? = nil`, `defaultBranch = "main"`, `defaultPullStrategy = PullPreference.ffOnly`, `widgetsConfirmed = false`.
- `AppSettings.initials(from name: String) -> String` ("David Niyonshuti" → "DN", "david" → "D", "" → "?").

- [ ] **Step 1: Write failing tests**: `v1SettingsFileLoadsWithV2Defaults` (JSON with only the four v1 keys → `theme == .ember`, `appearance == .system`, `viewMode == .cards`, `defaultBranch == "main"`, `dismissedCTAs.isEmpty`), `v2FieldsRoundTrip`, `unknownKeysAreIgnored`, `initialsFromName` (three cases above plus `"  a  b  c "` → "AB").
- [ ] **Step 2: Run** `swift test --filter SettingsV2Tests` — Expected: FAIL (types missing).
- [ ] **Step 3: Implement** the enums and fields; give `AppSettings` a custom `init(from:)` using `decodeIfPresent` with the defaults above, keeping the memberwise init and `defaults()`.
- [ ] **Step 4: Run** `swift test` — Expected: PASS (existing SettingsTests still pass).
- [ ] **Step 5: Commit** `feat: settings v2 keys with v1-compatible decoding`.

### Task 2: Brand palettes and contrast

**Files:**
- Create: `Sources/NexCore/ThemePalette.swift`
- Test: `Tests/NexCoreTests/ThemePaletteTests.swift`

**Interfaces:**
- Consumes: `ThemeID` (Task 1).
- Produces: `struct HexColor: Equatable, Sendable { init(hex: String); let red, green, blue: Double /* 0...1 */; var hexString: String; var luminance: Double; static func contrast(_ a: HexColor, _ b: HexColor) -> Double }`; `struct Palette: Equatable, Sendable { canvas, surface, fg, fg2, fg3, line, accent, accentHover, accentSoft, onAccent: HexColor }`; `enum ThemeCatalog { static func palette(_ theme: ThemeID, dark: Bool) -> Palette; static let displayNames: [ThemeID: String] }`.

- [ ] **Step 1: Write failing tests**: `ember light/dark match the Global Constraints hex values exactly`; `contrastOfBlackOnWhiteIs21`; `everyThemeAndModeMeetsContrast` (for all 5 × 2: fg/surface ≥ 4.5, fg/canvas ≥ 4.5, fg2/surface ≥ 4.5, fg3/surface ≥ 3, onAccent/accent ≥ 4.5); `themesChangeOnlyAccentFamily` (canvas, surface, fg, fg2, fg3, line identical across themes for the same mode); `hexParsingAcceptsHashAndCase`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** `HexColor` (WCAG relative luminance), `ThemeCatalog` tables. `onAccent` is whichever of `#ffffff` / `#0b0d12` has the higher contrast with the accent. Ocean / Forest / Violet / Graphite accents are chosen so the contrast tests pass (adjust lightness until they do; record chosen values in the test file as the source of truth).
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: nexventures brand palettes and themes`.

### Task 3: Nested projects — `ProjectNode` and `scanTree`

**Files:**
- Create: `Sources/NexCore/ProjectNode.swift`
- Modify: `Sources/NexCore/ProjectScanner.swift`
- Test: `Tests/NexCoreTests/ProjectTreeTests.swift`

**Interfaces:**
- Consumes: `ProjectScanner.detect(in:)`, `Project`, `ServiceTarget`.
- Produces: `struct ProjectNode: Identifiable, Hashable, Sendable { enum Kind: Sendable { case app, collection }; let id: String; let name: String; let url: URL; let kind: Kind; let project: Project?; var children: [ProjectNode]; var apps: [Project] /* this node's project (if any) plus all descendants' */ }`; `ProjectScanner.scanTree(root: URL) -> [ProjectNode]`. `ProjectScanner.scan(root:)` now returns `scanTree(root: root).flatMap(\.apps)` (flat list of every runnable app).
- **Rule (decided here; the spec's "not part of its own front/back split" is made concrete):** for a folder F, let *slots* be its immediate subfolders that contain at least one target within two levels.
  1. F has targets at its own root → **app**. Subfolders that have their own `.git` and their own targets are excluded from F's targets and become `children` (nested repos).
  2. Else if there are ≥ 2 slots and the slots do **not** include both a frontend and a backend → **collection**; each slot is evaluated recursively with the same rules (max depth 4 below the scan root).
  3. Else (0 or 1 slot, or a frontend+backend pair) → one **app** with the targets found as in v1 (omitted when there are none).

- [ ] **Step 1: Write failing tests** with `TempTree`: `twoFlutterAppsBecomeACollection` (`intern/week3_a/pubspec.yaml`, `intern/week3_b/pubspec.yaml` → one collection node "intern" with two app children); `frontendPlusBackendStaysOneFullStackApp` (Centerpiece-like: Webapp, Backend, GreenWonder, MobileApp → one app node, `isFullStack`); `rootManifestWithFlutterSubfolderIsOneApp` (Jarama-like → one app with frontend + flutter targets, no children); `nestedRepoBecomesChildApp` (app root has `package.json`; `sub/.git` + `sub/pubspec.yaml` → child); `collectionOfCollections` (`sessions/week1/app/pubspec.yaml`, `sessions/week2/app/pubspec.yaml` → collection with two app children named week1, week2); `singleSlotIsAnApp` (ijwi-new-like); `depthLimitFour` (a manifest at depth 5 is ignored); `skipNamesStillSkipped`; `symlinkLoopTerminates`; `flatScanEqualsAppsOfTree`; `idsAreFolderPaths`; `folderNameWithSpacesKept`. Existing `ProjectScannerTests` must still pass.
- [ ] **Step 2: Run** `swift test --filter ProjectTreeTests` — Expected: FAIL.
- [ ] **Step 3: Implement** `scanTree` and `ProjectNode` per the rule; reuse `detect`/`finalize`; keep a visited-set of real paths.
- [ ] **Step 4: Run** `swift test` — Expected: PASS (all prior scanner tests included).
- [ ] **Step 5: Commit** `feat: collections and nested projects in the scanner`.

### Task 4: FolderTree for the Folders view and Files tab

**Files:**
- Create: `Sources/NexCore/FolderTree.swift`
- Test: `Tests/NexCoreTests/FolderTreeTests.swift`

**Interfaces:**
- Produces: `struct FolderEntry: Identifiable, Hashable, Sendable { let id: String; let name: String; let url: URL; let isApp: Bool; let hasSubfolders: Bool }`; `enum FolderTree { static func entries(in directory: URL, skipNames: Set<String> = ProjectScanner.defaultSkips) -> [FolderEntry] }` (directories only, hidden skipped, sorted case-insensitively, one level, lazy).

- [ ] **Step 1: Write failing tests**: `listsOnlyDirectoriesSorted`, `marksFoldersWithManifestsAsApps`, `skipsNodeModulesAndHidden`, `hasSubfoldersFlag`, `missingDirectoryReturnsEmpty`, `symlinkedDirectoryIsListedOnceWithoutRecursing`.
- [ ] **Step 2: Run** — Expected: FAIL. **Step 3: Implement.** **Step 4: Run** `swift test` — PASS.
- [ ] **Step 5: Commit** `feat: lazy folder tree listing`.

### Task 5: Theme plumbing and card building blocks

**Files:**
- Create: `Sources/NexUI/Theme.swift`, `Sources/NexUI/Components.swift`
- Test: `Tests/NexUITests/ThemeTests.swift`

**Interfaces:**
- Consumes: `Palette`, `ThemeCatalog`, `AppearanceMode`, `ThemeID`, `Project`.
- Produces: `struct Theme { let palette: Palette; var canvas, surface, fg, fg2, fg3, line, accent, accentHover, accentSoft, onAccent: Color }`; `EnvironmentValues.theme: Theme`; `View.nexTheme(_ id: ThemeID, appearance: AppearanceMode) -> some View` (applies `preferredColorScheme` for light/dark, reads `colorScheme` for system, injects the theme); `IconStyle.hue(for name: String) -> Double` (0...1, stable hash); `ProjectSubtitle.text(for project: Project) -> String`; views `IconTile(name:glyph:size:)`, `Pill(title:style:action:)` (`.prominent` accent fill, `.quiet`), `CardSurface { content }`, `SectionHeader(title:action:)`, `ShelfRow`.

- [ ] **Step 1: Write failing tests**: `hueIsStableAndInUnitRange` (same name → same value, different names usually differ, always 0...1); `subtitleFullStackNamesFrameworks` (Vite frontend + Django backend → "Full-stack · Vite + Django"); `subtitleFrontendOnly` ("Frontend · Vite"); `subtitleFlutterOnly` ("Flutter"); `subtitleDockerOnly` ("Docker"); `themeResolvesDarkPaletteWhenDark` (`Theme.resolve(.ember, dark: true).palette == ThemeCatalog.palette(.ember, dark: true)`).
- [ ] **Step 2: Run** — Expected: FAIL. **Step 3: Implement** (card: radius 22, light shadow `black.opacity(0.06) r12 y4`, dark 1 px `line` stroke). **Step 4: Run** — PASS. **Step 5: Commit** `feat: theme environment and card components`.

### Task 6: Illustrations

**Files:**
- Create: `Sources/NexUI/Illustrations.swift`
- Test: `Tests/NexUITests/IllustrationTests.swift`

**Interfaces:**
- Consumes: `Theme` (Task 5).
- Produces: `enum IllustrationKind: CaseIterable, Sendable { case rocket, branchGraph, terminal, swatches, folders, telescope, widgets, power }`; `struct IllustrationView: View { init(_ kind: IllustrationKind) }` (square, scales to its container, flat geometric shapes with rounded corners, uses only `Theme` colours and opacity variants).

- [ ] **Step 1: Write failing test** `everyIllustrationRendersInEveryThemeMode`: for all kinds × 5 themes × light/dark × sizes 48, 160, 320, `ImageRenderer(content: IllustrationView(kind).nexTheme(...).frame(...)).cgImage` is non-nil and not fully transparent (sample ≥ 1 pixel with alpha > 0).
- [ ] **Step 2: Run** — Expected: FAIL. **Step 3: Implement** the eight drawings with `Canvas`/`Path` (rocket with flame and window; three-node branch graph; terminal window with prompt and cursor; four overlapping swatch circles; stacked folders; telescope on a tripod; two widget tiles; power glyph over a sunrise arc). **Step 4: Run** — PASS. **Step 5: Commit** `feat: vector illustrations`.

### Task 7: CTA engine

**Files:**
- Create: `Sources/NexUI/CTA.swift`
- Test: `Tests/NexUITests/CTATests.swift`

**Interfaces:**
- Consumes: `IllustrationKind`, `LastRun`.
- Produces: `enum CTAID: String, CaseIterable, Sendable { case addProject = "add-project", gitIdentity = "git-identity", uncommitted, resume, themes, widgets, login }`; `struct CTAContext { var gitIdentitySet: Bool; var projectsWithChanges: Int; var lastRunName: String?; var anythingRunning: Bool; var themeChanged: Bool; var widgetsConfirmed: Bool; var launchAtLogin: Bool }`; `struct CTA: Identifiable, Equatable { let id: CTAID; let headline: String; let body: String; let button: String; let illustration: IllustrationKind }`; `enum CTAEngine { static func visible(_ context: CTAContext, dismissed: Set<String>, limit: Int = 3) -> [CTA] }`. Priority: gitIdentity, uncommitted, resume, addProject, login, themes, widgets. Conditions and copy per the spec's table; `uncommitted` headline "N projects have unsaved changes" (singular "1 project has unsaved changes"); `resume` headline "Pick up where you left off", button "Run <lastRunName>".

- [ ] **Step 1: Write failing tests**: `freshUserSeesIdentityAddProjectAndLogin` (identity unset, no changes, no last run → [gitIdentity, addProject, login]); `cappedAtThree`; `dismissedCardsAreHidden`; `uncommittedNeedsAtLeastOneProject` and its singular/plural headline; `resumeOnlyWhenNothingRunningAndHasLastRun`; `themesHiddenOnceChanged`; `widgetsHiddenOnceConfirmed`; `loginHiddenWhenEnabled`; `orderFollowsPriority`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS. **Step 5: Commit** `feat: CTA ranking engine`.

### Task 8: Terminal (SwiftTerm)

**Files:**
- Modify: `Package.swift` (add the SwiftTerm dependency and target `NexTerminal`, test target `NexTerminalTests`; `NexUI` depends on `NexTerminal`)
- Create: `Sources/NexTerminal/TerminalSession.swift`, `Sources/NexTerminal/TerminalTabs.swift`, `Sources/NexTerminal/TerminalHostView.swift`
- Test: `Tests/NexTerminalTests/TerminalSessionTests.swift`

**Interfaces:**
- Produces: `@MainActor @Observable final class TerminalSession: Identifiable { let id: UUID; let directory: URL; var title: String; private(set) var isAlive: Bool; var hasForegroundProgram: Bool { get }; func start(); func send(_ text: String); func terminate(); var outputForTesting: String { get } }`; `@MainActor @Observable final class TerminalTabs { var sessions: [TerminalSession]; var selectedID: UUID?; func open(at directory: URL) -> TerminalSession; func close(_ id: UUID); var anyForegroundProgram: Bool { get }; func closeAll() }`; `struct TerminalHostView: NSViewRepresentable { init(session: TerminalSession) }` hosting SwiftTerm's `LocalProcessTerminalView`.
- The shell is started as `/bin/zsh` with args `["-l", "-c", "cd -- \"$NEX_DIR\" && exec zsh -l"]` and environment `NEX_DIR=<directory path>` plus `TERM=xterm-256color`, so directory names with spaces or quotes need no escaping.

- [ ] **Step 1: Write failing tests**: `startsInRequestedDirectoryWithSpaces` (temp dir `My "Proj" x`; start, `send("pwd\n")`, wait ≤ 5 s until `outputForTesting` contains the path); `echoesInput` (`send("echo nex-ok\n")` → output contains `nex-ok`); `terminateEndsTheShell` (`isAlive` becomes false, process gone); `closingTabTerminatesItsSession`; `foregroundProgramDetected` (`send("sleep 30\n")` → `hasForegroundProgram` true; after terminate false); `multipleTabsAreIndependent`.
- [ ] **Step 2: Run** `swift test --filter NexTerminalTests` — Expected: FAIL (target missing / unresolved).
- [ ] **Step 3: Implement** using SwiftTerm's `LocalProcess` for the headless session (output captured through its delegate) and `LocalProcessTerminalView` in `TerminalHostView`; foreground detection compares the PTY's foreground process group (`tcgetpgrp`) with the shell's pid.
- [ ] **Step 4: Run** `swift test` — Expected: PASS (first run downloads SwiftTerm; requires network).
- [ ] **Step 5: Commit** `feat: embedded terminal sessions and tabs`.

### Task 9: Project creation — new folder and clone

**Files:**
- Modify: `Sources/NexGit/GitRunner.swift` (add `stream`), `Sources/NexGit/GitService+Write.swift` (add `clone`)
- Create: `Sources/NexGit/ProjectCreator.swift`
- Test: `Tests/NexGitTests/ProjectCreatorTests.swift`

**Interfaces:**
- Produces: `GitRunner.stream(_ args: [String], in dir: URL, onLine: @escaping @Sendable (String) -> Void) async throws -> Int32` (stdout+stderr lines as they arrive; Task cancellation terminates the process); `GitService.clone(url: String, into parent: URL, name: String, onLine: @escaping @Sendable (String) -> Void) async throws` (runs `git clone --progress -- <url> <name>`, maps failures with `classify`); `enum NameError: Error, Equatable { case empty, invalidCharacters, alreadyExists }`; `struct ProjectCreator { init(git: GitService = GitService()); static func validate(name: String, in parent: URL) -> NameError?; static func repositoryName(from url: String) -> String; func createFolder(name: String, in parent: URL, initGit: Bool, defaultBranch: String) async throws -> URL; func clone(url: String, name: String, in parent: URL, onLine: @escaping @Sendable (String) -> Void) async throws -> URL }`. A failed or cancelled clone removes the partially created folder.

- [ ] **Step 1: Write failing tests**: `validateRejectsEmptyDotDotSlashAndExisting` (`""`, `".."`, `"a/b"`, `"  "`, existing name → matching `NameError`); `validateAcceptsSpacesAndUnicode` (`"My App é"`); `repositoryNameFromHTTPSAndSSH` (`https://github.com/x/y.git` → `y`, `git@github.com:x/y.git` → `y`, `https://h/x/y/` → `y`, `https://h/x/y` → `y`); `createFolderMakesDirectoryAndInitialisesGitWithBranch` (HEAD branch equals the given default branch); `createFolderWithoutGit` (no `.git`); `cloneFromLocalBareRepoCopiesFilesAndReportsProgress`; `cloneIntoNameWithSpaces`; `urlStartingWithDashIsNotAnOption` (`"--upload-pack=touch /tmp/x"` fails as an invalid repository, creates no marker file); `failedCloneLeavesNoPartialFolder`; `cancelledCloneLeavesNoPartialFolder` (cancel the Task after the first line; folder absent afterwards); `authFailureIsMapped` (via `classify`).
- [ ] **Step 2: Run** — Expected: FAIL. **Step 3: Implement.** **Step 4: Run** `swift test` — PASS.
- [ ] **Step 5: Commit** `feat: create folders and clone repositories`.

### Task 10: App model v2 — tree, navigation, view mode, last run

**Files:**
- Modify: `Sources/NexUI/AppModel.swift`, `Sources/NexUI/AppModel+Run.swift`
- Create: `Sources/NexUI/AppModel+Navigation.swift`
- Test: `Tests/NexUITests/AppModelV2Tests.swift`

**Interfaces:**
- Consumes: `scanTree`, `CTAEngine`, `TerminalTabs`, `ProjectCreator`, v2 settings.
- Produces on `AppModel`: `private(set) var tree: [ProjectNode]`; `projects` stays the flat list of apps (`tree.flatMap(\.apps)`); `var page: AppPage` (`enum AppPage: Equatable { case home, settings(SettingsSection), collection(String /* node id */), project(String /* project id */) }`); `enum SettingsSection: String, CaseIterable { case profile, git, appearance, general, projects }`; `var sheet: AppSheet?` (`enum AppSheet: Identifiable { case addProject(AddProjectMode), widgetsHowTo }`, `enum AddProjectMode { case newFolder, clone }`); `let terminals: TerminalTabs`; `var viewMode: ViewMode { get set }` (persists to settings); `func openTerminal(at url: URL)`; `func dismiss(_ cta: CTAID)`; `func resetTips()`; `var ctaContext: CTAContext`; `var visibleCTAs: [CTA]`; `func perform(_ cta: CTAID) async` (routes: addProject → sheet, gitIdentity → `page = .settings(.git)`, uncommitted → filter to projects with changes, resume → run `lastRun`, themes → `.settings(.appearance)`, widgets → sheet, login → enable via `LaunchAtLogin`); `func addProject(...)`. `run(_:kinds:)` records `settings.lastRun` and saves.

- [ ] **Step 1: Write failing tests**: `refreshBuildsTreeAndFlatProjects` (collection fixture → `tree.count == 1`, `projects.count == 2`); `viewModePersistsToSettingsFile`; `runRecordsLastRun`; `dismissingCTAPersistsAndHidesIt` (reload store → still dismissed); `resetTipsClearsDismissals`; `performAddProjectOpensSheet`; `performGitIdentityGoesToGitSettings`; `performUncommittedFiltersProjects`; `performResumeRunsLastRun`; `openTerminalCreatesTabAtDirectory`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** `swift test` — PASS.
- [ ] **Step 5: Commit** `feat: app model v2 (tree, navigation, CTAs, terminals)`.

### Task 11: App Store-style UI — home, cards, detail, collections, folders, terminal

**Files:**
- Modify: `Sources/NexUI/ContentView.swift`, `ProjectGridView.swift`, `ProjectCard.swift`, `ProjectDetailView.swift`, `RunControls.swift`, `GreetingHeader.swift`, `MenuBarContent.swift`
- Create: `Sources/NexUI/SidebarView.swift`, `CTACardView.swift`, `RunningShelf.swift`, `CollectionView.swift`, `FolderOutlineView.swift`, `FilesTab.swift`, `TerminalPanel.swift`, `EmptyStateView.swift`
- Test: `Tests/NexUITests/UIStateTests.swift`

**Interfaces:**
- Consumes: all of the above. Produces views only; logic lives in `AppModel`.
- Layout per the spec: sidebar (Projects, Running, Full-stack, Flutter; profile row pinned at the bottom → `page = .settings(.profile)`); Home = greeting, CTA shelf (illustration right, ✕ dismiss), Running shelf, grid or outline according to `viewMode` (toolbar segmented control Cards ⇄ Folders, plus `+` Add project and Refresh); project card = `IconTile`, name, `ProjectSubtitle`, `Pill` Run/Stop with menu, git badge, Terminal button, "N apps inside" chip; collection card = stacked-folders illustration, opens `CollectionView`; detail page tabs Overview · Terminal · Logs · Git · Files; empty states use illustrations with Add project / Clone / Choose folder buttons.

- [ ] **Step 1: Write failing tests** for the view-state helpers only: `sidebarSelectionMapsToFilter`, `emptyStateKindForNoProjectsVsNoResults`, `appsInsideChipTextSingularAndPlural` ("1 app inside" / "3 apps inside"), `cardPrimaryActionTitle` ("Run" / "Stop" / "Run Frontend").
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement** helpers and all views; wrap the root in `.nexTheme(settings.theme, appearance: settings.appearance)`.
- [ ] **Step 4: Run** `swift test` and `swift build` — Expected: PASS and no errors.
- [ ] **Step 5: Commit** `feat: app store style UI with CTA cards, collections, folders view and terminal`.

### Task 12: Add Project sheet, in-window Settings and profile

**Files:**
- Create: `Sources/NexUI/AddProjectSheet.swift`, `SettingsPage.swift`, `ProfileAvatar.swift`, `GitSettingsSection.swift`, `AppearanceSection.swift`
- Delete: `Sources/NexUI/SettingsView.swift` (its override editor moves into the Projects section); modify `Sources/NexLauncher/NexLauncherApp.swift` (remove the `Settings` scene; ⌘, sets `model.page = .settings(.general)`; terminals closed in `applicationShouldTerminate` after a confirmation when `terminals.anyForegroundProgram`)
- Test: `Tests/NexUITests/SettingsPageTests.swift`

**Interfaces:**
- Consumes: `ProjectCreator`, `GitService.identity/setIdentity/effectiveIdentity`, `LaunchAtLogin`, settings.
- Produces: `AddProjectSheet(model:mode:)` (New folder tab: name + parent picker + git-init checkbox; Clone tab: URL, name defaulting to `ProjectCreator.repositoryName`, parent picker, live log, Cancel; on success refresh, `page = .project(id)`, offer Open terminal / Run); `SettingsPage(model:section:)` with Profile (name, avatar colour or photo via `NSOpenPanel`), Git (global name/email via `git config --global`, default branch → `init.defaultBranch` global config and `settings.defaultBranch`, default pull strategy, credential helper status read from `git config --get credential.helper`, "Reset tips"), Appearance (mode picker, theme grid with live preview swatches), General (launch at login, Dock icon, projects folder), Projects (pins, overrides using `Override.edited`). The toolbar Pull button uses `settings.defaultPullStrategy`.

- [ ] **Step 1: Write failing tests** for the testable parts: `addProjectNameDefaultsFromURL`, `addProjectDisabledUntilNameValid`, `savingGitIdentityWritesGlobalConfig` (using a throwaway `GIT_CONFIG_GLOBAL`), `defaultBranchSettingWritesGitConfig`, `profileInitialsShownInAvatar` (uses `AppSettings.initials`), `pullButtonUsesDefaultStrategy`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** `swift test` and `swift build` — PASS.
- [ ] **Step 5: Commit** `feat: add project sheet, in-window settings and profile`.

### Task 13: Package, widget compatibility and installation

**Files:**
- Modify: `build.sh` (nothing changes for SwiftTerm — `swift build` resolves it; verify), `README.md`
- Test: build only

- [ ] **Step 1: Run** `swift build -c release --product NexLauncher` — Expected: succeeds (SwiftTerm resolved and linked).
- [ ] **Step 2: Run** `./build.sh` — Expected: widget extension still compiles with the new `NexCore` files and `codesign --verify --deep --strict NexLauncher.app` exits 0.
- [ ] **Step 3: Run** `swift test` three times — Expected: 3/3 green, no leftover `sleep` processes (`pgrep -fl "sleep 300"` empty).
- [ ] **Step 4: Update** `README.md` (themes, collections, folders view, terminal, add project) and commit `docs: v2 README`.

### Task 14: Verification against the real folder

- [ ] **Step 1: Run** `./build.sh --install`. Expected: app launches; light and dark appearances both follow the nexventures.net palette (screenshot each; switch via Settings → Appearance); all five themes switch live.
- [ ] **Step 2: Verify** collections on the real tree: `intern-sessions` and `mobileapp-sessions` show as collections with their apps; `Centerpiece` stays one full-stack app; the Folders view mirrors disk and each row offers Run / Terminal / Git.
- [ ] **Step 3: Verify** the terminal opens in a project folder and in a nested app, runs `pwd` and `ls`, and quitting with a foreground program asks first.
- [ ] **Step 4: Verify** Add project: create a new folder with git init in a scratch parent, clone a small public repository, confirm both appear and open their detail pages; delete the scratch folders afterwards.
- [ ] **Step 5: Verify** CTA cards appear for the current state, dismiss and reset work, and every illustration displays in light and dark. Record anything not visually verified in the ledger.
