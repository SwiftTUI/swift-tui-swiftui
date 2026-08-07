# AGENTS.md

Guidance for agentic assistants working in this repository. Keep this file
concise. `README.md` is the consumer-facing story; `docs/` holds internal
notes.

## What this repo is

The native Apple-platform host for SwiftTUI. It ships the `SwiftUIHost`
library product (`SwiftUIHostAppView`, `SwiftUIHostAppState`,
`SwiftUIHostTerminalStyle`), embedding a SwiftTUI `App` in SwiftUI on
macOS 15+ / iOS 18+.

## Build & test commands

```bash
swiftly run swift build        # build SwiftUIHost
swiftly run swift test         # run SwiftUIHostTests (macOS)
Scripts/native_gate.sh     # the repo gate CI runs
```

Do not run builds or tests with bare `swift` or `xcrun swift` — use
`swiftly run swift ...` so runs match the pinned toolchain.

## Rules

- This package consumes `swift-tui`'s `SwiftTUIRuntime` product through a
  public, tagged HTTPS dependency pinned `exact:` — see
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the lockstep `@_spi`
  contract. Never introduce a path dependency; pre-tag integration happens in
  the SwiftTUI org coordination root.
- Planning and proposal documents live in the SwiftTUI org coordination root,
  not here. `docs/` describes `HEAD` only.
- Use Swift Testing (`import Testing`, `@Test`, `#expect`) for tests.

## Conventions

- Agent guidance uses `AGENTS.md` as the real file. `CLAUDE.md` is a symlink
  to it.
