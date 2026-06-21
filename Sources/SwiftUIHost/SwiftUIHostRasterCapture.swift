public import CoreGraphics
import SwiftTUIRuntime

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
#endif

/// Offscreen rasterization of a hosted SwiftTUI surface, exposed under the
/// `Raster` SPI for coordination tooling (the SwiftUI-vs-SwiftTUI layout
/// comparison sweep). It reuses the exact on-screen path —
/// ``NativeRasterSurfaceRenderer/draw(surface:style:metrics:bounds:dirtyRect:context:)``
/// — so the captured bitmap equals what ``NativeTerminalSurfaceView`` paints,
/// without a window, a terminal, or a run loop driving an on-screen view.
///
/// macOS/AppKit only: the renderer's text path uses `NSString.draw`, which
/// draws into the current `NSGraphicsContext`. On non-AppKit platforms these
/// entry points return `nil`.
@_spi(Raster) public enum SwiftUIHostRasterCapture {
  /// Render `surface` into an offscreen `CGImage` at `scale` backing pixels per
  /// point, using `style` for fonts/palette. Returns `nil` if `surface` is
  /// `nil`, on a non-AppKit platform, or if the bitmap context can't be made.
  ///
  /// The image is `cols*cellWidth*scale × rows*cellHeight*scale` pixels, where
  /// the cell size is derived from the bundled terminal font at `style.fontSize`.
  @MainActor
  public static func image(
    of surface: RasterSurface?,
    style: SwiftUIHostTerminalStyle,
    scale: CGFloat
  ) -> CGImage? {
    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
      guard let surface else { return nil }
      BundledFonts.registerIfNeeded()

      let metrics = NativeTerminalMetrics(style: style)
      let pointWidth = CGFloat(surface.size.width) * metrics.cellSize.width
      let pointHeight = CGFloat(surface.size.height) * metrics.cellSize.height
      guard pointWidth >= 1, pointHeight >= 1, scale > 0 else { return nil }

      let pixelWidth = max(1, Int((pointWidth * scale).rounded()))
      let pixelHeight = max(1, Int((pointHeight * scale).rounded()))

      guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = unsafe CGContext(
          data: nil,
          width: pixelWidth,
          height: pixelHeight,
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else { return nil }

      // The renderer assumes a top-left origin (it is driven from an
      // `isFlipped == true` NSView). Flip the y-axis and apply the backing
      // scale so the renderer keeps working in points.
      context.translateBy(x: 0, y: CGFloat(pixelHeight))
      context.scaleBy(x: scale, y: -scale)
      context.setShouldSmoothFonts(false)  // deterministic glyph edges across machines

      // `NSString.draw` (the non-box-drawing glyph path) renders into the
      // current NSGraphicsContext; mark it flipped to match the CTM above.
      let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = graphicsContext
      defer { NSGraphicsContext.restoreGraphicsState() }

      let bounds = CGRect(x: 0, y: 0, width: pointWidth, height: pointHeight)
      NativeRasterSurfaceRenderer.draw(
        surface: surface,
        style: style,
        metrics: metrics,
        bounds: bounds,
        dirtyRect: bounds,  // full repaint — ignore frame-to-frame damage
        context: context
      )

      return context.makeImage()
    #else
      return nil
    #endif
  }
}

@_spi(Raster) extension SwiftUIHostSceneHost {
  /// Render this host's most recent committed surface to an offscreen `CGImage`.
  /// Returns `nil` if no frame has been committed yet (drive `start()` and await
  /// a frame first — see ``latestFrameSequence``).
  @MainActor
  public func renderLatestSurfaceToCGImage(scale: CGFloat) -> CGImage? {
    SwiftUIHostRasterCapture.image(of: latestSurface, style: style, scale: scale)
  }
}
