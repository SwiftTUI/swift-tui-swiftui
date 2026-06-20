# swift-tui-swiftui

The native SwiftUI host for [SwiftTUI](https://swifttui.sh) — embed a SwiftTUI
app inside a SwiftUI view on macOS and iOS.

This repo publishes one Swift package product:

| Product | Module | What it is |
| --- | --- | --- |
| **`SwiftUIHost`** | `import SwiftUIHost` | A SwiftUI `View` (`SwiftUIHostAppView`) plus the `@Observable` state types that retain a `HostedSceneSession` and draw a `HostedRasterSurface`. It bundles the terminal font and bridges keyboard, pointer, clipboard, and accessibility between SwiftUI/AppKit/UIKit and the SwiftTUI runtime. |

It is the Apple-platform sibling of
[`swift-tui-android`](https://github.com/SwiftTUI/swift-tui-android) (Jetpack
Compose host) and [`swift-tui-web`](https://github.com/SwiftTUI/swift-tui-web)
(browser host). The runtime it drives lives in
[`swift-tui`](https://github.com/SwiftTUI/swift-tui) and is consumed here as a
public, tagged HTTPS dependency on its `SwiftTUIRuntime` product.

## Using it (consumer)

Add both `swift-tui` (for the framework + your views) and `swift-tui-swiftui`
(for the host) to your package:

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.0.25"),
  .package(url: "https://github.com/SwiftTUI/swift-tui-swiftui.git", exact: "0.0.25"),
],
targets: [
  .executableTarget(
    name: "MyApp",
    dependencies: [
      .product(name: "SwiftTUI", package: "swift-tui"),
      .product(name: "SwiftUIHost", package: "swift-tui-swiftui"),
    ]
  )
]
```

Then wrap your SwiftTUI `App` in a `SwiftUIHostAppView`:

```swift
import SwiftUI
import SwiftUIHost
import SwiftTUI   // your root View / App lives here

@main
struct MyHostApp: SwiftUI.App {
  @State private var hostState = try! SwiftUIHostAppState(app: MyTUIApp())
  var body: some SwiftUI.Scene {
    WindowGroup {
      SwiftUIHostAppView(state: hostState)
    }
  }
}
```

`SwiftUIHostAppState` starts/stops the runtime and exposes the live scene; pass
a `SwiftUIHostTerminalStyle` to control font size, palette, theme, and cursor.

Runnable demos live in
[`swift-tui-examples`](https://github.com/SwiftTUI/swift-tui-examples):
`SwiftUIExample`, `LayoutsSwiftUI`, and `three-hosts-demo` (the same source
rendered in a terminal, a SwiftUI window, and the browser).

## Building locally

```bash
swift build              # build the SwiftUIHost module
swift test               # run the SwiftUIHostTests suite (macOS)
```

SwiftUIHost imports SwiftUI/AppKit/UIKit, so it builds on Apple platforms only;
it is excluded from Linux at the package-graph level.

## License

MIT — see [LICENSE](LICENSE).
