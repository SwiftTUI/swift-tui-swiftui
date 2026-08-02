public import CoreGraphics
import SwiftTUIRuntime

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
#endif

/// Provides offscreen rasterization of a hosted SwiftTUI surface through the `Raster` SPI.
/// Coordination tools use this SPI to compare SwiftUI and SwiftTUI layouts.
/// It uses the same path as the on-screen renderer:
/// ``NativeRasterSurfaceRenderer/draw(surface:style:metrics:bounds:dirtyRect:context:)``.
/// Thus, the captured bitmap matches the output from ``NativeTerminalSurfaceView``.
/// The capture does not require a window, terminal, or run loop for an on-screen view.
///
/// On macOS, the text path uses `NSString.draw` to draw into the current `NSGraphicsContext`.
/// On non-AppKit platforms, these entry points return `nil`.
@_spi(Raster) public enum SwiftUIHostRasterCapture {
  /// Renders `surface` into an offscreen `CGImage` with the fonts and palette from `style`.
  /// `scale` specifies the number of backing pixels for each point.
  /// If `surface` is `nil`, the function returns `nil`.
  /// On a non-AppKit platform, the function returns `nil`.
  /// If the function cannot create the bitmap context, it returns `nil`.
  ///
  /// The image size is `cols*cellWidth*scale × rows*cellHeight*scale` pixels.
  /// The bundled terminal font at `style.fontSize` determines the cell size.
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
  /// Renders the most recent committed surface of this host to an offscreen `CGImage`.
  /// If the host has not committed a frame, this function returns `nil`.
  /// In this case, run `start()` and wait for a frame. See ``latestFrameSequence``.
  @MainActor
  public func renderLatestSurfaceToCGImage(scale: CGFloat) -> CGImage? {
    SwiftUIHostRasterCapture.image(of: latestSurface, style: style, scale: scale)
  }
}
