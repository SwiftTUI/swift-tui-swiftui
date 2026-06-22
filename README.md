# SwiftTUI for SwiftUI

**Embed a SwiftTUI app inside a native SwiftUI view on macOS and iOS.**

![Swift 6.3](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)
![Platforms](https://img.shields.io/badge/platforms-macOS%2015%2B%20%C2%B7%20iOS%2018%2B-1E90FF)
![Status](https://img.shields.io/badge/status-0.0.27%20alpha-DAA520)
![License](https://img.shields.io/badge/license-MIT-3DA639)

`swift-tui-swiftui` is the native Apple-platform host for
[SwiftTUI](https://swifttui.sh). It wraps a SwiftTUI `App` in an ordinary
SwiftUI `View`, so the same view code you run in a terminal renders inside a
window, a sheet, or a pane of your AppKit/UIKit app — with keyboard, pointer,
clipboard, and accessibility already bridged for you.

## Why use it

- **One codebase, every surface.** Code authored against SwiftTUI runs unchanged
  in a terminal, in the browser, on Android, and — through this package —
  inside a native macOS or iOS app. The
  [`three-hosts-demo`](https://github.com/SwiftTUI/swift-tui-examples/tree/main/three-hosts-demo)
  renders the same source in a terminal, a SwiftUI window, and the browser at
  once.
- **Drop-in SwiftUI.** `SwiftUIHostAppView` is a plain `View`. Put it in a
  `WindowGroup`, a split view, a sheet, or anywhere else you compose SwiftUI —
  no `NSViewRepresentable`/`UIViewRepresentable` glue to write.
- **Native input, already wired.** Keyboard, pointer, clipboard, and
  VoiceOver/UIKit accessibility are bridged between AppKit/UIKit and the
  SwiftTUI runtime, and the terminal font is bundled.
- **Styleable.** A `SwiftUIHostTerminalStyle` controls font size, palette,
  theme, and cursor.

## What this package publishes

| Product | Module | What it is |
| --- | --- | --- |
| **`SwiftUIHost`** | `import SwiftUIHost` | A SwiftUI `View` (`SwiftUIHostAppView`) plus the `@Observable` state types that retain a `HostedSceneSession` and draw a `HostedRasterSurface`. It bundles the terminal font and bridges keyboard, pointer, clipboard, and accessibility between SwiftUI/AppKit/UIKit and the SwiftTUI runtime. |

It is the Apple-platform sibling of
[`swift-tui-android`](https://github.com/SwiftTUI/swift-tui-android) (Jetpack
Compose host) and [`swift-tui-web`](https://github.com/SwiftTUI/swift-tui-web)
(browser host). The runtime it drives lives in
[`swift-tui`](https://github.com/SwiftTUI/swift-tui) and is consumed here as a
public, tagged HTTPS dependency on its `SwiftTUIRuntime` product.

## Requirements

| | |
| --- | --- |
| Swift toolchain | Swift 6.3 (`swift-tools-version: 6.3`) |
| Platforms | macOS 15+, iOS 18+ (imports SwiftUI/AppKit/UIKit; excluded from Linux at the package-graph level) |

## Installation

Add both `swift-tui` (the framework and your views) and `swift-tui-swiftui`
(the host). Pin both to the **same** tag with `exact:`: the host bridges to the
runtime's internal scene/raster surfaces rather than only its semver-stable
public API, so the two are released and consumed in lockstep.

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.0.27"),
  .package(url: "https://github.com/SwiftTUI/swift-tui-swiftui.git", exact: "0.0.27"),
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

## Quick start

Wrap your SwiftTUI `App` in a `SwiftUIHostAppView`:

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

`SwiftUIHostAppState` starts/stops the runtime and exposes the live scene; its
initializer throws if the app declares no scenes. Pass a
`SwiftUIHostTerminalStyle` to control font size, palette, theme, and cursor.

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

## Documentation & support

- **Project site & live API reference:** <https://swifttui.sh/docs/documentation/>
- **The framework:** [`SwiftTUI/swift-tui`](https://github.com/SwiftTUI/swift-tui)
  — the authoring API, products, and platform matrix.
- **Other hosts:** [`swift-tui-web`](https://github.com/SwiftTUI/swift-tui-web)
  (browser) and [`swift-tui-android`](https://github.com/SwiftTUI/swift-tui-android)
  (Jetpack Compose).
- **Questions & issues:** <https://github.com/SwiftTUI/swift-tui-swiftui/issues>

## License

MIT — see [LICENSE](LICENSE).
