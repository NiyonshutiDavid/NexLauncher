# NexLauncher v3 — plan

Requested on 2026-10-26 (one message). Built natively on branch `build/v3`, test-first for logic; views verified by build,
offscreen renders and live screenshots (never synthetic keystrokes).

## Decisions

| Request | Decision |
| --- | --- |
| Revert sidebar + top header, keep the + background | Back to the system window toolbar (macOS 26 renders its items as glass capsules: view switch, filled +, refresh, search). The floating glass bar is removed. |
| Window controls like WhatsApp; sidebar title/tabs up high | Traffic lights sit inside the floating sidebar; the sidebar toggle and toolbar separator are removed from the sidebar column so "NexLauncher" and the tabs start right under the traffic lights. |
| Menu bar "not working" | Root cause found: the popover's project list was a `ScrollView` with only `maxHeight`, which collapses to zero inside a `MenuBarExtra` window. Rebuilt with explicit height. Content reduced to **Running** (Open in browser, Stop) and **Pinned** (Run/Stop), plus Open NexLauncher and Quit. |
| Run any stack | Manifest detection extended: package manager by lockfile (npm/pnpm/yarn/bun), Expo/React Native, Deno, Python (Django, FastAPI, Flask, Streamlit, plain `main.py`/`app.py`, Poetry/uv), Rails, Laravel/PHP, Go, Rust, Spring (Maven/Gradle), .NET, Elixir/Phoenix, Swift packages, static HTML, Makefile and Procfile. New generic kind `app` for runnables that aren't web front/back ends. Install commands per stack. |
| Animations while setting up / scanning | Scanning: animated hero + shimmering placeholder cards. Missing dependencies: a "Set up <project>" sheet (illustration, step list, live progress, log line) replaces the plain dialog. |
| A top CTA with illustration on every page | `HeroBanner` per page (Projects, Pinned, Running, Full-stack, Flutter, Tasks, AI, collections, project pages), each with its own illustration, copy and actions. New illustrations: pin, play, layers, phone, checklist, robot. |
| Flutter emulators | Flutter page lists iOS simulators (`xcrun simctl list -j`), Android Studio AVDs (`emulator -list-avds` from the SDK) and connected devices (`flutter devices --machine`); Launch / Shut down; run a project on a chosen device. |
| Tasks per project, done tasks in widgets | `TaskStore` (JSON in the app support folder, readable by the widget). Tasks tab per project, Tasks page across projects, new **Tasks** widget (recently done + open count). Tasks can be handed to an AI agent; a successful run marks the task done. |
| AI mode | Agents detected on the Mac: **Claude Code** (`claude -p --output-format stream-json --verbose --permission-mode …`, verified on this Mac), **Codex** (`codex exec`), **Gemini CLI** (`gemini -p`), **Antigravity** (no command-line runner: opens the project in the app and copies the task), **Custom** (a command template; the task is passed as `$NEX_TASK`, never spliced into the command). Autonomy: Plan only / Edit files (default) / Full auto (warned). Runs stream progress, can be stopped, notify on finish, keep a history. Sign-in is done by each agent's own CLI in a terminal tab; NexLauncher stores no credentials. |
| Better widgets | Ember gradient backgrounds, brand illustrations, clearer hierarchy; Running Services, Quick Launch and the new Tasks widget. |

## Order

1. Layout revert + WhatsApp-style sidebar + filled +.
2. Menu bar popover fix and simplification.
3. Stack detection and commands (tests per stack).
4. Setup sheet and scanning animations.
5. Hero banners and new illustrations.
6. Flutter devices (parsers tested with fixtures).
7. Tasks (store, UI, widget).
8. AI mode (detection, command building, stream parsing, runs; tested with a fake agent script).
9. Widget redesign.
10. Build, install, live check, fresh review, fix pass.
