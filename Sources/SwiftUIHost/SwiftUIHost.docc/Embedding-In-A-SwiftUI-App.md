# Embedding in a SwiftUI App

Host a SwiftTUI `App` inside a native SwiftUI view on macOS and iOS.

## Overview

`SwiftUIHost` wraps a SwiftTUI `App` in an ordinary SwiftUI `View`. The same
view tree, `@State`, and `@FocusState` that run in a terminal render into a
window, sheet, or AppKit/UIKit pane — with keyboard, pointer, and clipboard
bridged natively and no `NSViewRepresentable`/`UIViewRepresentable` glue to
write.

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

``SwiftUIHostAppView`` is a plain `View`. ``SwiftUIHostAppState`` starts and
stops the runtime and exposes the live scene; its initializer throws if the
app declares no scenes, so handle that failure properly outside of samples.

## Install

Add both `swift-tui` (the framework and your views) and `swift-tui-swiftui`
(the host). Pin both to the **same** tag with `exact:` — the host uses the
runtime's internal scene and raster surfaces, so the two packages are
released and consumed in lockstep.

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.10.1"),
  .package(url: "https://github.com/SwiftTUI/swift-tui-swiftui.git", exact: "0.10.1"),
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

## The Consumer Surface

Import `SwiftUIHost`. Three types cover the integration:

- ``SwiftUIHostAppView`` — the SwiftUI `View`. Put it in a `WindowGroup`, a
  split view, or a sheet.
- ``SwiftUIHostAppState`` — controls the runtime and scene selection.
- ``SwiftUIHostTerminalStyle`` — font size, palette, theme, and cursor, so
  the hosted surface inherits your app's look instead of standing out as a
  console.

## Platform Behavior

Keyboard, pointer, and clipboard events are bridged between AppKit/UIKit and
the SwiftTUI runtime. The native accessibility overlay presents roles,
labels, hints, and runtime focus to VoiceOver; assistive-origin focus and
control actions are not yet routed back into SwiftTUI in 0.9. The terminal
font is bundled. Scrolling follows the platform: on iOS a scroll view pans
when you drag it, while on macOS a press-drag stays a click-drag.

## Run the Demo

[`swift-tui-examples`](https://github.com/SwiftTUI/swift-tui-examples)
contains `SwiftUIExample` (a full Xcode host app) and `LayoutsSwiftUI` (a
SwiftUI-vs-SwiftTUI parity gallery). The multi-host counter in
[`swift-tui-counter-demo`](https://github.com/SwiftTUI/swift-tui-counter-demo)
runs the same view in a terminal, this host, and the browser — its SwiftUI
window opens without Xcode via
`swift run --package-path counter CounterSwiftUI`.

## Requirements

Swift 6.3+, macOS 15+ or iOS 18+. The package imports SwiftUI/AppKit/UIKit,
so the package graph excludes it from Linux.
