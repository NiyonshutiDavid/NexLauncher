# NexLauncher v2 — App Store-style redesign and new features

Addendum to `2026-10-26-nexlauncher-design.md`. Everything in v1 stays unless stated here.

## Requests covered

1. App Store-inspired cards and overall cleanliness, with **CTA cards** and **illustrations**.
2. Detect folders that contain other projects; a switch between cards and a folder structure view.
3. A terminal inside the app, usable at any project or nested-project folder.
4. Add a project: new folder, or clone a git repository.
5. Profile icon at the bottom of the sidebar that opens Settings (git, theme, more).
6. Multiple themes; default colours taken from nexventures.net in both light and dark.

## 1. Design language

**Layout.** Sidebar (Projects, Running, Full-stack, Flutter, then a profile row pinned to the bottom) and a content area. Home is a vertical stack: greeting → CTA shelf → "Running now" shelf (only when something runs) → project grid. Detail pages follow the App Store product page: large icon tile, name, primary pill button, then tabs **Overview · Terminal · Logs · Git · Files**.

**Cards.** Solid surfaces (not glass), 22 pt radius, 1 px hairline in dark mode and a soft shadow in light mode, generous padding. Glass (`glassEffect`) is kept for the sidebar, toolbar and buttons only.

**Project card.** Icon tile (rounded squircle with a gradient derived from the project name and the theme accent, plus a framework glyph), name, one-line subtitle (e.g. "Full-stack · React + Django"), a pill **Run / Stop** button with a menu for Frontend / Backend / Both / Flutter / Docker, status dots, git badge, and a Terminal button.

**Tokens (from nexventures.net's own stylesheet).**

| Token | Light | Dark |
| --- | --- | --- |
| canvas | `#f7f8fa` | `#07080c` |
| surface | `#ffffff` | `#0f1117` (derived) |
| text (fg) | `#0b0d12` | `#f3f4f7` |
| text 2 | `#454c5a` | `#aeb4c2` |
| text 3 | `#697285` | `#767d8f` |
| line | `#e2dfdb` | `#2c3140` |
| accent (Ember) | `#cf3f0e` | `#f0561f` |
| accent hover | `#a8320b` | `#ff7440` |
| accent soft | `#fff0e8` | `#2a140c` |

## 2. Themes and appearance

- **Appearance:** System (default), Light, Dark.
- **Themes** change the accent family only; neutrals stay on brand: **Nexventures Ember** (default), **Ocean**, **Forest**, **Violet**, **Graphite**. Each theme defines accent / hover / soft for light and dark.
- Implemented as a `Theme` value injected through the SwiftUI environment; every view reads colours from it (no hard-coded colours in views). Persisted in settings.

## 3. CTA cards

Large promotional cards in a horizontal shelf at the top of Home, in the style of App Store editorial cards: accent-tinted background, an illustration on the right, a headline, one line of support text, and one button. Up to **three** show at once, ranked by priority; each has a ✕ that dismisses it (persisted by id; a "Reset tips" button in Settings brings them back).

| id | Shown when | Headline / button | Action |
| --- | --- | --- | --- |
| `add-project` | always until dismissed | "Start something new" / **Add project** | opens the Add Project sheet |
| `git-identity` | global git name or email is unset | "Tell git who you are" / **Set up** | opens Settings → Git |
| `uncommitted` | one or more projects have uncommitted changes | "N projects have unsaved changes" / **Review** | filters the grid to those projects |
| `resume` | a project was run before and nothing is running | "Pick up where you left off" / **Run <name>** | runs that project's last action |
| `themes` | theme never changed | "Make it yours" / **Choose a theme** | opens Settings → Appearance |
| `widgets` | widgets not yet confirmed added | "Keep an eye on your servers" / **Show me how** | opens a short how-to sheet |
| `login` | launch at login is off | "Start with your Mac" / **Turn on** | enables launch at login |

Empty states are CTAs too: no projects found → "Nothing here yet" with **Add project**, **Clone repository**, **Choose folder**.

## 4. Illustrations

Drawn in code as resolution-independent SwiftUI vector views (`Canvas` / `Path`), flat geometric style with rounded shapes, using only the active theme's accent and the neutral tokens, so they recolour with the theme and with light/dark. No image assets, no network.

Set: **rocket** (add project), **branch graph** (git), **terminal window** (terminal / resume), **palette swatches** (themes), **stacked folders** (collections, empty state), **telescope** (no results), **desktop widgets** (widgets), **power button / sunrise** (login). API: `IllustrationView(.rocket)` sized by its container; each illustration is previewable and unit-tested only for "renders at several sizes without a crash".

## 5. Nested projects and the folders view

**Model.** A `ProjectNode` tree replaces the flat list: a node is an **app** (has runnable targets), a **collection** (no targets of its own, one or more descendant apps), or an app that also **contains** other apps (e.g. a Flutter `mobile/` next to a web app, or a monorepo). The scanner descends up to **4 levels**, never into skipped folders (`node_modules`, `.git`, …), and still guards against symlink loops.

**Rules.**
- A folder with targets is an app; its sub-apps (separate manifests in subfolders that are not part of its own front/back split) become `children`.
- A folder with no targets whose descendants include apps is a collection and lists those apps.
- Existing full-stack behaviour (frontend + backend siblings combine into one app) is unchanged.

**UI.** Collections appear as a stacked-folders card ("Intern sessions · 2 projects") that opens an inner grid. Apps with children show an "N apps inside" chip; the detail page lists them as cards. Every nested app is a first-class project (run, terminal, git, logs).

**Cards ⇄ Folders switch.** A segmented toggle in the toolbar switches the main view between the card grid and an expandable outline that mirrors the folders on disk. Each outline row has the same Run, Terminal and Git actions. The choice is remembered.

## 6. Terminal

- An embedded terminal using **SwiftTerm** (open-source Swift package, added as a dependency and fetched from GitHub once at build time). Real pseudo-terminal running the user's login `zsh`, so colours, history, editors (vim) and interactive tools work.
- A **Terminal** button on every card, outline row and detail page opens a terminal tab with its working directory set to that folder (nested apps included). Multiple tabs; a tab keeps running while hidden and is closed explicitly.
- Separate from the managed servers: running a command in a terminal never appears in the Running list.
- Quitting warns if terminal tabs still have a running foreground program.

## 7. Add project

A **+** button in the toolbar and sidebar opens a sheet with two tabs:

- **New folder** — name (validated: not empty, no `/`, not existing), parent (projects folder by default, or any subfolder via a picker), checkbox "Initialise a git repository" (on), creates the folder, optionally runs `git init`.
- **Clone repository** — URL (https or ssh), destination folder name (defaults to the repo name), parent as above. Runs `git clone --progress` through the existing runner with live output and a Cancel button. Uses the user's existing credentials; auth failures are shown verbatim and mapped to a helpful message.

On success the app rescans, selects the new project and offers **Open terminal** / **Run**.

## 8. Profile and Settings

- The sidebar's bottom row shows an avatar (initials on an accent tile, or a chosen photo) and the display name; clicking opens **Settings inside the main window**. ⌘, opens the same page. The separate v1 settings window is removed.
- **Sections:** Profile (name, avatar colour or photo) · **Git** (global name/email, default branch for new repos, default pull strategy, credential helper / sign-in status, reset tips) · **Appearance** (mode, theme with live previews) · **General** (launch at login, Dock icon, projects folder) · **Projects** (pinned for widgets, command/port overrides).

## Persistence

Extends `settings.json`: `appearance`, `theme`, `viewMode`, `dismissedCTAs`, `avatarColor`, `avatarPhotoPath`, `lastRun` (project id + action), `defaultBranch`, `defaultPullStrategy`. Unknown or missing keys fall back to defaults so existing settings files keep loading.

## Non-goals

Windows/Linux, App Store distribution, a code editor, custom user themes (only the five built-in), animations beyond standard SwiftUI transitions.

## Risks

- SwiftTerm needs network once to resolve; if unavailable the build fails clearly and the terminal feature can be stubbed behind a flag.
- Hand-drawn vector illustrations are simple by design; they can later be replaced by designer artwork without API changes.
- Deeper scanning (4 levels) costs more on large trees; the scan stays off the main thread and is cached between launches.

## Testing

- Scanner: collections, apps with children, monorepos, depth limit, symlink loops, skip lists, names with spaces; fixtures mirror `intern-sessions`, `Zanda-portfolio`, `ijwi-new`, `Jarama`.
- Theme: every token resolves for every theme × light/dark; contrast of text on surface and accent buttons meets WCAG AA (computed in tests).
- CTA ranking: which cards appear for given states, the cap of three, dismissal persistence, reset.
- Add project: validation, `git init`, clone against a local bare repository, cancel, failure messages.
- Terminal: working directory is the requested folder; a shell starts and echoes input (using SwiftTerm's headless terminal).
- Settings: backwards-compatible decoding of v1 `settings.json`; new keys round-trip.
- Manual: build, install, visual check in light and dark, each theme, nested folders against the real Nexventures folder.
