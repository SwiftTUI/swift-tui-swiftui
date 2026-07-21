# SwiftTUI for SwiftUI

**Embed a SwiftTUI app inside a native SwiftUI view on macOS and iOS — no `NSViewRepresentable`/`UIViewRepresentable` glue; keyboard, pointer, clipboard, and accessibility already bridged.**

![Swift 6.3](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)
![Platforms](https://img.shields.io/badge/platforms-macOS%2015%2B%20%C2%B7%20iOS%2018%2B-1E90FF)
![Status](https://img.shields.io/badge/status-0.1.12%20pre--release-DAA520)
![License](https://img.shields.io/badge/license-MIT-3DA639)

`swift-tui-swiftui` is the native Apple-platform host for
[SwiftTUI](https://swifttui.sh) — SwiftUI semantics, drawn in terminal cells. It
wraps a SwiftTUI `App` in an ordinary SwiftUI `View`, so the same view tree, the
same `@State`, and the same `@FocusState` you run in a terminal render inside a
window, a sheet, or a pane of your AppKit/UIKit app.

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

`SwiftUIHostAppView` is a plain `View`; `SwiftUIHostAppState` starts and stops
the runtime and exposes the live scene. That is the whole integration.

## Why use it

- **One app, five hosts.** Code authored against SwiftTUI runs unchanged as a
  terminal executable, a static WASI bundle, a localhost WebHost, a native
  Android surface, and — through this package — a native SwiftUI surface on macOS
  or iOS, which means you write the interface once and choose where it ships. The
  [`three-hosts-demo`](https://github.com/SwiftTUI/swift-tui-examples/tree/main/three-hosts-demo)
  renders one source in a terminal, a SwiftUI window, and the browser at once.
- **Drop-in SwiftUI.** `SwiftUIHostAppView` goes straight into a `WindowGroup`, a
  split view, or a sheet, which means no representable bridge to write and nothing
  to wire before your view appears.
- **Native input, already bridged.** Keyboard, pointer, clipboard, and
  VoiceOver/UIKit accessibility are connected between AppKit/UIKit and the
  SwiftTUI runtime, and the terminal font is bundled — which means the embedded
  surface behaves like the rest of your app on day one.
- **Styled to match your app.** `SwiftUIHostTerminalStyle` controls font size,
  palette, theme, and cursor, which means the hosted surface inherits your app's
  look instead of standing out as a console.

## Installation

Add both `swift-tui` (the framework and your views) and `swift-tui-swiftui` (the
host). Pin both to the **same** tag with `exact:`: the host bridges to the
runtime's internal scene and raster surfaces rather than only its semver-stable
public API, so the two are released and consumed in lockstep.

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.1.12"),
  .package(url: "https://github.com/SwiftTUI/swift-tui-swiftui.git", exact: "0.1.12"),
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

Import `SwiftUIHost`. The consumer surface is three types: `SwiftUIHostAppView`
(the SwiftUI `View`), `SwiftUIHostAppState` (drives the runtime; its initializer
throws if the app declares no scenes), and `SwiftUIHostTerminalStyle` (styling).

## Run the demo

```bash
git clone https://github.com/SwiftTUI/swift-tui-examples.git
cd swift-tui-examples
open SwiftUIExample/SwiftUIExample.xcodeproj   # native SwiftUI host app — run the app scheme
```

`SwiftUIExample` (the native host app above), `LayoutsSwiftUI`, and
`three-hosts-demo` (the same source in a terminal, a SwiftUI window, and the
browser) all live in
[`swift-tui-examples`](https://github.com/SwiftTUI/swift-tui-examples). For a
headless `swift run` instead of Xcode, try
`swiftly run swift run --package-path three-hosts-demo three-hosts-demo`.

## Requirements

| | |
| --- | --- |
| Swift toolchain | Swift 6.3 (`swift-tools-version: 6.3`) |
| Platforms | macOS 15+, iOS 18+ — imports SwiftUI/AppKit/UIKit, so it is Apple-platform only and excluded from Linux at the package-graph level |

This package is the Apple-platform sibling of
[`swift-tui-android`](https://github.com/SwiftTUI/swift-tui-android) (Jetpack
Compose host) and [`swift-tui-web`](https://github.com/SwiftTUI/swift-tui-web)
(browser host). The runtime it drives lives in
[`swift-tui`](https://github.com/SwiftTUI/swift-tui), consumed here as a public,
tagged HTTPS dependency on its `SwiftTUIRuntime` product.

## Building locally

```bash
swift build              # build the SwiftUIHost module
swift test               # run the SwiftUIHostTests suite (macOS)
```

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
