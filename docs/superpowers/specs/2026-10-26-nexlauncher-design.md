# NexLauncher — Design

A native macOS app (SwiftUI, Liquid Glass, macOS 26+) that auto-detects the projects in
`~/Documents/Nexventures`, runs their frontend / backend / Flutter targets from inside the app,
offers a GitHub-Desktop-style git workflow, and surfaces status through a menu bar item and
desktop widgets.

## Agreed intent

- Personal tool for one user (David), not App Store distributed.
- Auto-detect projects in the Nexventures folder; flag full-stack projects; let the user run
  frontend only, backend only, both, or Flutter (when present).
- Servers run **inside the app** (option 1): the app owns the processes, shows logs, offers Stop.
- Greeting on launch ("Good morning, David").
- Desktop widgets, menu bar presence, optional launch at login, Liquid Glass UI (macOS 26;
  "macOS 27" does not exist yet, so target 26 and later).
- Git operations like GitHub Desktop: set username/email, pull, commit, push.

## Non-goals

Code editing, remote deployment, Windows/Linux, App Store distribution, pull-request / issue
management, merge-conflict resolution UI (conflicts are reported, resolved outside the app).

## Build approach

Swift Package Manager for the app and shared library, plus a `build.sh` that assembles
`NexLauncher.app`, embeds the WidgetKit extension, code-signs with the user's personal team
(ad-hoc fallback for the app alone) and installs to `/Applications`. If widget signing cannot be
done from the script, fall back to a minimal Xcode project for the widget target only.

Modules:

| Module | Purpose | Depends on |
| --- | --- | --- |
| `NexCore` | Models, `ProjectScanner`, `CommandBuilder`, shared store | Foundation |
| `NexProcess` | `ProcessManager`: start/stop/log services | NexCore |
| `NexGit` | `GitService`: wraps `/usr/bin/git` | NexCore |
| `NexLauncher` (app) | SwiftUI window, menu bar, settings, greeting | all |
| `NexWidgets` (extension) | WidgetKit widgets + App Intents | NexCore |

## 1. Detection (`ProjectScanner`)

- Scans each direct child of the scan root, recursing two levels. Skips `node_modules`, `.git`,
  `build`, `dist`, `.next`, `.dart_tool`, `venv`, `.venv`, and the launcher's own folder.
- Folder names vary (`web`, `client`, `Clients`, `api`, `Server`, `backend`), so roles come from
  manifests, never names:
  - **Frontend**: `package.json` with a `dev` or `start` script; framework (Vite / Next / CRA /
    other) inferred from dependencies.
  - **Backend**: `manage.py` (Django), `requirements.txt` with FastAPI/Flask, or a `package.json`
    with Express/Nest-style deps and a `start` script.
  - **Flutter**: `pubspec.yaml`.
  - **Docker**: `docker-compose.yml` / `compose.yaml`.
- A project with both a frontend and a backend target is tagged **Full-stack**.
- Per-project manual overrides (change a folder's role, set a custom command / port) are stored.
- Re-scan on launch, on Refresh, and when the root folder changes (FSEvents).

## 2. Running (`ProcessManager`)

- Each service runs as `/bin/zsh -lc "<command>"` in its working directory, in its own process
  group, so the login PATH (Node, Flutter, Python) applies.
- Default commands: `npm run dev` / `npm start`; `python manage.py runserver` (project venv if
  present); `flutter run -d <device>` with a device picker; `docker compose up`.
- If `node_modules` is missing, the app offers to run the install first.
- Card buttons: **Frontend**, **Backend**, **Both**, **Flutter** (only those that apply) and Stop.
- Logs stream into a per-service panel; ports are parsed from output and shown with an
  "Open in browser" button.
- Stop terminates the whole process group (SIGTERM, then SIGKILL after a timeout). No orphans.
- Quitting asks to stop services or keep running; services are only kept alive while the app
  lives on in the menu bar.

## 3. Git (`GitService`)

A GitHub-Desktop-style panel for every project, and for each nested repository inside it
(a full-stack project may have one repo or several). Implemented by running the system `git`
(`/usr/bin/git`) with `--porcelain` formats; no libgit2 dependency.

- **Identity**: view and set `user.name` / `user.email`, scoped to global or to the repo.
  A first-run prompt offers to set them if unset.
- **Status**: branch, ahead/behind counts, list of changed files (staged / unstaged / untracked).
- **Diff**: per-file unified diff viewer.
- **Stage / unstage** individual files or all; **discard changes** with a confirmation dialog.
- **Commit**: summary + description fields, commits the staged files (or all if none staged).
- **Pull**: fetch then `git pull --ff-only` by default; if it cannot fast-forward the app says
  so and offers merge or rebase as an explicit choice. Conflicts are reported with the file list.
- **Push**: pushes the current branch, setting upstream when needed. Never force-pushes.
- **Fetch**, **branch list / switch / create**, and a **history** list of recent commits.
- **Authentication**: relies on the user's existing credential helper (macOS Keychain) or SSH
  keys. The app never stores or asks for tokens or passwords itself; auth failures are shown with
  the git error text.
- All git commands run off the main thread with a timeout; stderr is surfaced verbatim on failure.
- Cards show a small git badge (clean / N changes / ahead / behind).

## 4. Window and greeting

- Main window: sidebar + grid of project cards using `glassEffect` and glass containers.
- On launch a large greeting: "Good morning / afternoon / evening / night, <name>", followed by
  the grid, a search field and a Refresh button.
- Name defaults to the Mac account's first name; editable in Settings.

## 5. Menu bar

- `MenuBarExtra` with a status icon and a count of running services.
- Popover lists projects with quick Run / Stop and git change counts; has "Open window" and Quit.
- Dock icon visibility is a setting.

## 6. Widgets

- WidgetKit extension with two widgets:
  - **Running Services**: live list of running services and ports.
  - **Quick Launch**: buttons for pinned projects, starting them through App Intents.
- App and extension share state via an App Group container; widget timelines are reloaded when a
  service starts or stops.
- Known limitations: widget refresh is system-throttled, and the extension needs correct signing
  and an App Group entitlement. This will be called out during testing.

## 7. Settings

Launch at login (`SMAppService`), display name, scan root, Dock icon on/off, pinned projects,
per-project overrides.

## Error handling

Process spawn failures, missing toolchains (node, flutter, python, docker not found), port
conflicts and git failures show inline on the relevant card with the underlying message.

## Testing

- Unit: `ProjectScanner` against fixture folders mirroring the real layouts (CleanPay, NVMS,
  blessedlawfirm, Kigali, DRD, Jarama); `CommandBuilder`.
- `ProcessManager` with a dummy long-running process: start, log capture, stop, no orphans.
- `GitService` against temporary git repos (init, status, stage, commit, pull/push against a
  local bare remote, identity config).
- Manual end-to-end: build and launch the app, verify greeting, run a real project, commit/push in
  a scratch repo, check the menu bar and a widget.
