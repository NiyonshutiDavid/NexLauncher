# Contributing to NexLauncher

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug or asking for a feature

Open an issue at https://github.com/NiyonshutiDavid/NexLauncher/issues with:

- what you did, what you expected and what happened;
- your macOS version and the NexLauncher version (NexLauncher → About NexLauncher);
- for a project that isn't detected or won't run: its manifest files (e.g. `package.json`, `pyproject.toml`).

## Making a change

1. Fork the repository and create a branch from `main`.
2. Build and test:
   ```bash
   swift test
   ./build.sh
   ```
3. The app supports macOS 14 and later. For anything newer, add a fallback in `Sources/NexUI/Compat.swift`
   (see `nexGlass`, `nexGlassButton`) rather than raising the minimum.
4. Logic goes in `NexCore`, `NexProcess` or `NexGit` with tests next to it in `Tests/`. Views live in `NexUI`.
5. Keep the style of the surrounding code: small types, comments that say *why*, no new dependencies without a
   reason in the pull request.
6. Open a pull request describing the change and how you checked it. Screenshots help for anything visual.

## Ground rules

- NexLauncher never stores credentials: git and AI agents keep their own sign-in.
- Text from projects, tasks or agents is never spliced into a shell command; pass it as an environment variable
  (see `AgentCommandBuilder`).
- Be kind in issues and reviews.
