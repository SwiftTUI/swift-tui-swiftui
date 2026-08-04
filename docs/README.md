# swift-tui-swiftui internal documentation

Internal notes for maintainers. The consumer-facing story is
[../README.md](../README.md); the `SwiftUIHost` API reference is the DocC
catalog at `Sources/SwiftUIHost/SwiftUIHost.docc`.

| Document | What it covers |
| --- | --- |
| [ARCHITECTURE.md](ARCHITECTURE.md) | The host boundary: what the package wraps, the lockstep `@_spi(Runners)` contract, and why releases pin `exact:`. |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Toolchain, gate, and release notes. |
