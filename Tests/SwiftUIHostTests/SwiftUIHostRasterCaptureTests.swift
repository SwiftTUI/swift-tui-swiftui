import CoreGraphics
import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Raster) @testable import SwiftUIHost

/// Tests for the `@_spi(Raster)` offscreen capture seam used by the
/// SwiftUI-vs-SwiftTUI layout-comparison coordination tooling.
@MainActor
@Suite(.serialized)
struct SwiftUIHostRasterCaptureTests {
  @Test
  func renders_latest_surface_to_image_at_expected_pixel_size() async throws {
    let host = try SwiftUIHostSceneHost(
      app: RasterHostApp(),
      descriptor: .init(id: "main", title: "Main", isDefault: true),
      style: .default
    )

    let frameSignal = MainActorConditionSignal()
    host.onFrameForTesting = { frameSignal.notify() }
    host.start()
    defer { host.stop() }

    await frameSignal.wait {
      host.latestSurface?.lines.contains { $0.contains("Hello") } == true
    }

    let surface = try #require(host.latestSurface)
    #expect(host.latestFrameSequence != nil)

    let scale: CGFloat = 2
    let image = try #require(host.renderLatestSurfaceToCGImage(scale: scale))

    // The image is `cols*cellWidth*scale × rows*cellHeight*scale` pixels.
    let metrics = NativeTerminalMetrics(style: .default)
    let expectedWidth = Int((CGFloat(surface.size.width) * metrics.cellSize.width * scale).rounded())
    let expectedHeight = Int((CGFloat(surface.size.height) * metrics.cellSize.height * scale).rounded())
    #expect(image.width == expectedWidth)
    #expect(image.height == expectedHeight)
  }

  @Test
  func nil_surface_yields_nil_image() {
    #expect(SwiftUIHostRasterCapture.image(of: nil, style: .default, scale: 2) == nil)
  }
}

@MainActor
private struct RasterHostApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      Text("Hello")
    }
  }
}
