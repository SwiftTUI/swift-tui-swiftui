# Development

## Toolchain

Swift 6.3 via `swiftly` (`swiftly run swift ...`). The package imports
SwiftUI/AppKit/UIKit, so it builds on macOS (and iOS via Xcode) only; the
package graph excludes it from Linux.

## Gate

`tools/bazel/native_gate.sh` is the repo gate CI runs: it prefers
`swiftly run swift test` when `swiftly` is available. CI provisions the
pinned toolchain the same way (see `.github/workflows/test.yml`).

## Releases

Versions are lockstep with the SwiftTUI org. The org coordination root owns
the release sequence, pin checks, and the pre-tag `@_spi` contract gate. Do
not tag from this repository outside that process.
