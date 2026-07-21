// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

// `swift-tui-swiftui` is the native SwiftUI host for SwiftTUI: it embeds a
// `SwiftTUIRuntime` app inside a SwiftUI view on macOS and iOS. It is the
// Apple-platform sibling of `swift-tui-android` (Compose host) and
// `swift-tui-web` (browser host). The Swift runtime it drives lives in the
// `swift-tui` package, consumed here through a public, tagged HTTPS dependency.

let explicitPlatforms = ProcessInfo.processInfo.environment["DISABLE_EXPLICIT_PLATFORMS"] != "1"

let packagePlatforms: [SupportedPlatform]? = {
  if !explicitPlatforms {
    return nil
  }

  return [
    .macOS(.v15),
    .iOS(.v18),
  ]
}()

func swiftSettings(_ settings: PackageDescription.SwiftSetting...) -> [PackageDescription
  .SwiftSetting]
{
  [
    .swiftLanguageMode(.v6),
    .strictMemorySafety(),
    .defaultIsolation(.none),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  ] + settings
}

let package = Package(
  name: "swift-tui-swiftui",
  platforms: packagePlatforms,
  products: [
    .library(name: "SwiftUIHost", targets: ["SwiftUIHost"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/SwiftTUI/swift-tui.git",
      exact: "0.1.13"
    )
  ],
  targets: [
    .target(
      name: "SwiftUIHost",
      dependencies: [
        .product(name: "SwiftTUIRuntime", package: "swift-tui")
      ],
      path: "Sources/SwiftUIHost",
      resources: [
        .process("Resources")
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftUIHostTests",
      dependencies: [
        "SwiftUIHost",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUIRuntime", package: "swift-tui"),
        .product(name: "SwiftTUITestSupport", package: "swift-tui"),
      ],
      path: "Tests/SwiftUIHostTests",
      swiftSettings: swiftSettings()
    ),
  ]
)
