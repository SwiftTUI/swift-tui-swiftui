# SwiftTUI for SwiftUI

**Embed a SwiftTUI app inside a native SwiftUI view on macOS and iOS, with keyboard, pointer, clipboard, and a native semantic accessibility overlay and no `NSViewRepresentable`/`UIViewRepresentable` glue to write.**

![Swift 6.4](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)
![Platforms](https://img.shields.io/badge/platforms-macOS%2015%2B%20%C2%B7%20iOS%2018%2B-1E90FF)
![Status](https://img.shields.io/badge/status-beta-DAA520)
![License](https://img.shields.io/badge/license-MIT-3DA639)

`swift-tui-swiftui` is the native Apple-platform host for
[SwiftTUI](https://swifttui.sh): SwiftUI semantics, drawn in terminal cells. It
wraps a SwiftTUI `App` in an ordinary SwiftUI `View`. The same view tree,
`@State`, and `@FocusState` can run in a terminal or an Apple app. The Apple app
can show the SwiftTUI view in a window, sheet, or AppKit/UIKit pane.

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

`SwiftUIHostAppView` is a plain `View`. `SwiftUIHostAppState` starts and stops
the runtime and exposes the live scene.

The manual keyboard toggle is hidden by default. To enable it on iOS, pass a
`SwiftUIHostConfiguration`:

```swift
SwiftUIHostAppView(
  state: hostState,
  configuration: .init(showsKeyboardToggleButton: true)
)
```

The button appears only when no text-input control is focused. Text-input
controls continue to present the keyboard automatically when focused.

For touch interfaces, keep primary actions visible and provide enough space to
tap them. The shared tree can read `pointerInputCapabilities.supportsScrollPanning`
to select touch-oriented control sizes and navigation while keeping the same
model and actions. See
[Adapting an Interface to Its Host](https://swifttui.sh/docs/documentation/swifttuiviews/adapting-to-hosts).

## Why use it

- **One app, five hosts.** Code authored against SwiftTUI runs unchanged as a
  terminal executable, a static WASI bundle, a localhost WebHost, a native
  Android surface, and, through this package, a native SwiftUI surface on macOS
  or iOS. You write the interface once and choose where it ships. The
  [`swift-tui-counter-demo`](https://github.com/SwiftTUI/swift-tui-counter-demo)
  repo renders one source in a terminal, a SwiftUI window, the browser, and an
  Android app.
- **Drop-in SwiftUI.** `SwiftUIHostAppView` goes straight into a `WindowGroup`, a
  split view, or a sheet. There is no representable bridge to write and nothing
  to wire before your view appears.
- **Native input and semantic presentation.** Keyboard, pointer, and clipboard
  events are bridged between AppKit/UIKit and the SwiftTUI runtime. The native
  accessibility overlay presents roles, labels, hints, and runtime focus to
  VoiceOver; assistive-origin focus and control actions are not yet routed back
  into SwiftTUI. The terminal font is bundled. Scrolling follows the platform:
  on iOS a scroll view pans when you drag it, while on macOS a press-drag stays
  a click-drag.
- **Styled to match your app.** `SwiftUIHostTerminalStyle` controls font size,
  palette, theme, and cursor, so the hosted surface inherits your app's
  look instead of standing out as a console.

## Drawing on the native surface

The presenter preserves authored image order, opacity, and shape clipping while
reusing source image content and decoded bitmaps within bounded caches. Text
decorations retain their patterns across partial redraws. These are rendering
behaviors of the shared surface; application views use the ordinary SwiftTUI
drawing APIs. See [architecture](docs/ARCHITECTURE.md) for cache and damage rules.

## Installation

Add both `swift-tui` (the framework and your views) and `swift-tui-swiftui` (the
host). Pin both to the **same** tag with `exact:`. The host uses the runtime's
internal scene and raster surfaces. Thus, the two packages are released and
consumed in lockstep.

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.14.0"),
  .package(url: "https://github.com/SwiftTUI/swift-tui-swiftui.git", exact: "0.14.0"),
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

Import `SwiftUIHost`. The main integration types are:

- `SwiftUIHostAppView` is the SwiftUI `View`.
- `SwiftUIHostConfiguration` controls host presentation options, including the
  opt-in iOS keyboard toggle.
- `SwiftUIHostAppState` controls the runtime. Its initializer throws if the app
  declares no scenes.
- `SwiftUIHostTerminalStyle` controls the terminal style.

## Run the demo

```bash
git clone https://github.com/SwiftTUI/swift-tui-examples.git
cd swift-tui-examples
open SwiftUIExample/SwiftUIExample.xcodeproj   # native SwiftUI host app — run the app scheme
```

[`swift-tui-examples`](https://github.com/SwiftTUI/swift-tui-examples) contains
`SwiftUIExample` and `LayoutsSwiftUI`, a SwiftUI-vs-SwiftTUI parity gallery.
The multi-host counter lives in
[`swift-tui-counter-demo`](https://github.com/SwiftTUI/swift-tui-counter-demo);
clone it and open its SwiftUI window without Xcode via
`swiftly run swift run --package-path counter CounterSwiftUI`.

## Requirements

| | |
| --- | --- |
| Swift toolchain | Swift 6.4 (`swift-tools-version: 6.4`) |
| Platforms | macOS 15+, iOS 18+. The package imports SwiftUI/AppKit/UIKit, so the package graph excludes it from Linux. |

This package is the Apple-platform sibling of
[`swift-tui-android`](https://github.com/SwiftTUI/swift-tui-android) (Jetpack
Compose host) and [`swift-tui-web`](https://github.com/SwiftTUI/swift-tui-web)
(browser host). The host uses the runtime in
[`swift-tui`](https://github.com/SwiftTUI/swift-tui). This package consumes the
`SwiftTUIRuntime` product through a public, tagged HTTPS dependency.

## Building locally

```bash
swiftly run swift build        # build the SwiftUIHost module
swiftly run swift test         # run the SwiftUIHostTests suite (macOS)
```

Use the pinned toolchain through `swiftly`, not bare `swift`. See
[AGENTS.md](AGENTS.md) for the repo gate and conventions, and
[docs/](docs/README.md) for architecture and development notes.

## Documentation & support

- **Project site & framework API reference:** <https://swifttui.sh/docs/documentation/>
- **`SwiftUIHost` API reference:** hosted by
  [Swift Package Index](https://swiftpackageindex.com/SwiftTUI/swift-tui-swiftui/documentation)
  (built from this package's DocC catalog).
- **The framework:** [`SwiftTUI/swift-tui`](https://github.com/SwiftTUI/swift-tui),
  the authoring API, products, and platform matrix.
- **Other hosts:** [`swift-tui-web`](https://github.com/SwiftTUI/swift-tui-web)
  (browser) and [`swift-tui-android`](https://github.com/SwiftTUI/swift-tui-android)
  (Jetpack Compose).
- **Questions & issues:** <https://github.com/SwiftTUI/swift-tui-swiftui/issues>

## License

MIT; see [LICENSE](LICENSE).
