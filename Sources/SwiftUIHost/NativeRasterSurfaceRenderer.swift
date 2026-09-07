import CoreGraphics
import Foundation
// Image blend compositing for hosted raster surfaces is exposed by
// `SwiftTUIRuntime` through the `Runners` host-integration SPI.
@_spi(Runners) import SwiftTUIRuntime

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

// Raster rendering for the native terminal surface.
//
// `NativeRasterSurfaceRenderer` paints a `RasterSurface` into a `CGContext`:
// it fills the background, draws each cell (procedural box-drawing glyphs via
// `BoxDrawingRenderer`, otherwise font text), applies underline/strikethrough
// decorations, and composites image attachments. `dirtyRects` translates a
// `PresentationDamage` into the `CGRect`s that need repainting.
//
// Split out of `NativeTerminalSurfaceView.swift`. The enum is widened from
// `private` to file-internal so the platform view classes can drive it; its
// helpers stay `private` (file-scoped here). The platform color/image
// adapters it uses live in `NativeTerminalPlatformAdapters.swift`.

enum NativeRasterSurfaceRenderer {
  private static let imageBlendCompositor = ImageBlendCompositor()

  static func draw(
    surface: RasterSurface?,
    style: SwiftUIHostTerminalStyle,
    metrics: NativeTerminalMetrics,
    bounds: CGRect,
    dirtyRect: CGRect,
    context: CGContext
  ) {
    let dirtyBounds = bounds.intersection(dirtyRect)
    guard !dirtyBounds.isNull, !dirtyBounds.isEmpty else {
      return
    }

    context.saveGState()
    defer { context.restoreGState() }
    context.clip(to: dirtyBounds)

    let defaultForeground = style.palette.foreground
    let defaultBackground = style.palette.background
    context.setFillColor(
      NativePlatformColor.terminalColor(
        defaultBackground,
        alphaMultiplier: Double(style.backgroundOpacity)
      ).cgColor
    )
    context.fill(dirtyBounds)

    guard let surface else {
      return
    }

    let rows = visibleIndices(
      lower: dirtyBounds.minY, upper: dirtyBounds.maxY,
      pitch: metrics.cellSize.height, count: surface.cells.count
    )
    for y in rows {
      let row = surface.cells[y]
      for x in visibleColumns(in: row, dirtyRect: dirtyBounds, metrics: metrics) {
        let cell = row[x]
        guard !cell.isContinuation else { continue }
        let rect = cellRect(x: x, y: y, span: cell.spanWidth, metrics: metrics)
        guard rect.intersects(dirtyBounds) else {
          continue
        }
        drawCell(
          cell,
          x: x,
          y: y,
          style: cell.style ?? ResolvedTextStyle(),
          defaultForeground: defaultForeground,
          defaultBackground: defaultBackground,
          metrics: metrics,
          context: context
        )
      }
    }

    for attachment in surface.imageAttachments {
      drawImageAttachment(
        attachment,
        style: style,
        metrics: metrics,
        dirtyRect: dirtyBounds,
        context: context
      )
    }
  }

  static func visibleIndices(lower: CGFloat, upper: CGFloat, pitch: CGFloat, count: Int)
    -> Range<Int>
  {
    guard count > 0, pitch.isFinite, pitch > 0, lower.isFinite, upper.isFinite,
      lower < upper
    else { return 0..<0 }
    let first = Int(max(0, min(CGFloat(count), floor(lower / pitch))))
    let end = Int(max(CGFloat(first), min(CGFloat(count), ceil(upper / pitch))))
    return first..<end
  }

  static func visibleColumns(
    in row: [RasterCell], dirtyRect: CGRect, metrics: NativeTerminalMetrics
  ) -> Range<Int> {
    let columns = visibleIndices(
      lower: dirtyRect.minX, upper: dirtyRect.maxX,
      pitch: metrics.cellSize.width, count: row.count
    )
    guard !columns.isEmpty else { return columns }
    // Damage can start inside a wide glyph. Recover its lead without scanning
    // every preceding cell; the raster continuation carries that exact index.
    if let lead = row[columns.lowerBound].continuationLeadX,
      lead >= 0, lead < columns.lowerBound
    {
      return lead..<columns.upperBound
    }
    return columns
  }

  static func dirtyRects(
    for damage: PresentationDamage,
    surface: RasterSurface,
    metrics: NativeTerminalMetrics,
    bounds: CGRect
  ) -> [CGRect] {
    guard !damage.requiresFullTextRepaint else {
      return [bounds]
    }

    var rects: [CGRect] = []
    for textRow in damage.textRows {
      guard textRow.row >= 0, textRow.row < surface.size.height else {
        continue
      }
      if textRow.columnRanges.isEmpty {
        appendDirtyRect(
          x: 0,
          y: textRow.row,
          width: surface.size.width,
          metrics: metrics,
          bounds: bounds,
          to: &rects
        )
        continue
      }

      for range in textRow.columnRanges {
        let lowerBound = max(0, min(surface.size.width, range.lowerBound))
        let upperBound = max(lowerBound, min(surface.size.width, range.upperBound))
        guard lowerBound < upperBound else {
          continue
        }
        appendDirtyRect(
          x: lowerBound,
          y: textRow.row,
          width: upperBound - lowerBound,
          metrics: metrics,
          bounds: bounds,
          to: &rects
        )
      }
    }
    return rects
  }

  private static func appendDirtyRect(
    x: Int,
    y: Int,
    width: Int,
    metrics: NativeTerminalMetrics,
    bounds: CGRect,
    to rects: inout [CGRect]
  ) {
    let rect = cellRect(
      x: x,
      y: y,
      span: width,
      metrics: metrics
    ).intersection(bounds)
    guard !rect.isNull, !rect.isEmpty else {
      return
    }
    rects.append(rect)
  }

  private static func cellRect(
    x: Int,
    y: Int,
    span: Int,
    metrics: NativeTerminalMetrics
  ) -> CGRect {
    CGRect(
      x: CGFloat(x) * metrics.cellSize.width,
      y: CGFloat(y) * metrics.cellSize.height,
      width: CGFloat(max(1, span)) * metrics.cellSize.width,
      height: metrics.cellSize.height
    )
  }

  private static func drawCell(
    _ cell: RasterCell,
    x: Int,
    y: Int,
    style: ResolvedTextStyle,
    defaultForeground: SwiftTUIRuntime.Color,
    defaultBackground: SwiftTUIRuntime.Color,
    metrics: NativeTerminalMetrics,
    context: CGContext
  ) {
    let spanWidth = max(1, cell.spanWidth)
    let rect = cellRect(x: x, y: y, span: spanWidth, metrics: metrics)
    // Terminal cells own their ink, including italic/fallback overhang. Apply
    // the same bounds during full and incremental paint so damage never leaves
    // stale glyph pixels in a neighbouring cell.
    context.saveGState()
    defer { context.restoreGState() }
    context.clip(to: rect)

    let reversed = style.emphasis.contains(.reverse)
    let foreground =
      reversed
      ? (style.backgroundColor ?? defaultBackground)
      : (style.foregroundColor ?? defaultForeground)
    let background =
      reversed
      ? (style.foregroundColor ?? defaultForeground)
      : style.backgroundColor
    if let background {
      context.setFillColor(
        NativePlatformColor.terminalColor(
          background,
          alphaMultiplier: style.opacity
        ).cgColor
      )
      context.fill(rect)
    }

    let color = NativePlatformColor.terminalColor(
      foreground,
      alphaMultiplier: style.opacity
    )

    let drewBoxDrawing =
      cell.character == " "
      || BoxDrawingRenderer.canRender(cell.character)
        && BoxDrawingRenderer.draw(
          character: cell.character,
          in: rect,
          color: color.cgColor,
          context: context
        )

    if !drewBoxDrawing {
      drawGlyph(
        cell.character,
        emphasis: style.emphasis,
        color: color,
        in: rect,
        metrics: metrics,
        context: context
      )
    }

    drawLineDecorations(
      style: style,
      fallbackColor: color,
      rect: rect,
      metrics: metrics,
      context: context
    )
  }

  /// Draws a cell's glyph, fitted to the cell's span rect.
  ///
  /// The grid assumes every glyph advances exactly `cellSize.width` per
  /// spanned column, but characters outside the terminal font's coverage
  /// come from CoreText's fallback cascade with their natural — often
  /// wider — advance. Cells paint left-to-right and incremental repaints
  /// clip to per-cell dirty rects, so any overflow would be chopped at the
  /// trailing cell edge. Scale such a glyph uniformly into the span
  /// instead, the way terminal emulators fit fallback glyphs to the cell
  /// box. The fit decision reads the metrics' memoized glyph size, so the
  /// per-cell measurement cost is paid once per (character, emphasis).
  private static func drawGlyph(
    _ character: Character,
    emphasis: SwiftTUIRuntime.TextStyle.TextEmphasis,
    color: NativePlatformColor,
    in rect: CGRect,
    metrics: NativeTerminalMetrics,
    context: CGContext
  ) {
    let text = String(character) as NSString
    let attributes: [NSAttributedString.Key: Any] = [
      .font: metrics.font(for: emphasis),
      .foregroundColor: color,
    ]
    let naturalSize = metrics.naturalGlyphSize(for: character, emphasis: emphasis)
    guard naturalSize.width > rect.width, rect.width > 0 else {
      text.draw(
        at: CGPoint(x: rect.minX, y: rect.minY + metrics.textOffset.y),
        withAttributes: attributes
      )
      return
    }

    let scale = rect.width / naturalSize.width
    context.saveGState()
    context.translateBy(
      x: rect.minX,
      y: rect.minY + max(0, (rect.height - naturalSize.height * scale) / 2)
    )
    context.scaleBy(x: scale, y: scale)
    text.draw(at: .zero, withAttributes: attributes)
    context.restoreGState()
  }

  private static func drawLineDecorations(
    style: ResolvedTextStyle,
    fallbackColor: NativePlatformColor,
    rect: CGRect,
    metrics: NativeTerminalMetrics,
    context: CGContext
  ) {
    if let underlineStyle = style.underlineStyle {
      let color =
        underlineStyle.color.map {
          NativePlatformColor.terminalColor($0, alphaMultiplier: style.opacity)
        } ?? fallbackColor
      strokeLine(
        y: rect.minY + metrics.cellSize.height - 2,
        color: color,
        rect: rect,
        context: context
      )
    }

    if let strikethroughStyle = style.strikethroughStyle {
      let color =
        strikethroughStyle.color.map {
          NativePlatformColor.terminalColor($0, alphaMultiplier: style.opacity)
        } ?? fallbackColor
      strokeLine(
        y: rect.midY,
        color: color,
        rect: rect,
        context: context
      )
    }
  }

  private static func strokeLine(
    y: CGFloat,
    color: NativePlatformColor,
    rect: CGRect,
    context: CGContext
  ) {
    context.saveGState()
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(1)
    context.move(to: CGPoint(x: rect.minX, y: y))
    context.addLine(to: CGPoint(x: rect.maxX, y: y))
    context.strokePath()
    context.restoreGState()
  }

  private static func drawImageAttachment(
    _ attachment: RasterImageAttachment,
    style: SwiftUIHostTerminalStyle,
    metrics: NativeTerminalMetrics,
    dirtyRect: CGRect,
    context: CGContext
  ) {
    let bounds = attachment.visibleBounds
    guard !bounds.isEmpty, !attachment.bounds.isEmpty else {
      return
    }

    let rect = CGRect(
      x: CGFloat(bounds.origin.x) * metrics.cellSize.width,
      y: CGFloat(bounds.origin.y) * metrics.cellSize.height,
      width: CGFloat(bounds.size.width) * metrics.cellSize.width,
      height: CGFloat(bounds.size.height) * metrics.cellSize.height
    )
    guard rect.intersects(dirtyRect) else {
      return
    }
    // Geometry rejection precedes file/data lookup and blend preparation.
    guard let resolved = nativeImage(for: attachment, style: style) else { return }
    let placement = CGRect(
      x: CGFloat(resolved.bounds.origin.x) * metrics.cellSize.width,
      y: CGFloat(resolved.bounds.origin.y) * metrics.cellSize.height,
      width: CGFloat(resolved.bounds.size.width) * metrics.cellSize.width,
      height: CGFloat(resolved.bounds.size.height) * metrics.cellSize.height
    )
    context.saveGState()
    defer { context.restoreGState() }
    context.clip(to: rect)
    // Placement alpha is deliberately applied after image lookup/compositing:
    // changing opacity must not change decoded payload identity, and blended
    // images fade as one composited result.
    resolved.image.drawTerminalImage(in: placement, opacity: CGFloat(attachment.opacity))
  }

  private static func nativeImage(
    for attachment: RasterImageAttachment,
    style: SwiftUIHostTerminalStyle
  ) -> (image: NativePlatformImage, bounds: CellRect)? {
    if attachment.compositing != nil,
      let payload = imageBlendCompositor.encodedPNGPayload(
        for: attachment,
        fallbackBackground: style.palette.background
      ),
      let image = NativePlatformImage.terminalImage(from: .data(payload.bytes))
    {
      // The encoded blend payload is already cropped to visibleBounds.
      return (image, attachment.visibleBounds)
    }

    guard let image = NativePlatformImage.terminalImage(from: attachment.source) else { return nil }
    return (image, attachment.bounds)
  }
}
