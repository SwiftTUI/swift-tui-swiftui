import CoreGraphics
import Foundation
import SwiftTUIRuntime
import Testing

@testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  @MainActor
  struct NativeRasterDamageTests {
    @Test("dirty cell lookup selects only intersecting cells and their wide lead")
    func sparseCellSelection() {
      let metrics = NativeTerminalMetrics(style: .default)
      var row = Array(repeating: RasterCell.empty, count: 160)
      row[20] = RasterCell(character: "界", spanWidth: 2)
      row[21] = RasterCell(continuationLeadX: 20)
      let dirty = CGRect(
        x: metrics.cellSize.width * 21, y: 0,
        width: metrics.cellSize.width, height: metrics.cellSize.height
      )
      #expect(
        NativeRasterSurfaceRenderer.visibleColumns(
          in: row, dirtyRect: dirty, metrics: metrics
        ) == 20..<22)
      #expect(
        NativeRasterSurfaceRenderer.visibleIndices(
          lower: metrics.cellSize.height * 30, upper: metrics.cellSize.height * 31,
          pitch: metrics.cellSize.height, count: 60
        ) == 30..<31)
      #expect(
        NativeRasterSurfaceRenderer.visibleIndices(
          lower: -100, upper: -10, pitch: metrics.cellSize.width, count: 160
        ).isEmpty)
    }

    @Test("a clipped image preserves its original placement instead of squeezing")
    func croppedImageKeepsSourceCoordinates() throws {
      let bytes = try imageBytes(left: .red, right: .blue)
      let attachment = RasterImageAttachment(
        identity: Identity(components: ["crop"]),
        bounds: rect(x: -2, width: 4),
        visibleBounds: rect(x: 0, width: 2),
        source: .data(bytes), isResizable: true
      )
      let surface = RasterSurface(
        size: CellSize(width: 2, height: 1),
        cells: [[.empty, .empty]], imageAttachments: [attachment]
      )
      try withContext(columns: 2) { context, metrics, bounds in
        NativeRasterSurfaceRenderer.draw(
          surface: surface, style: .default, metrics: metrics,
          bounds: bounds, dirtyRect: bounds, context: context
        )
        let pixel = try color(context, x: Int(metrics.cellSize.width / 2))
        #expect(pixel.blueComponent > 0.9)
        #expect(pixel.redComponent < 0.1)
      }
    }

    @Test("partial native repaint preserves untouched translucent image pixels", arguments: [1, 2])
    func partialImageRepaint(scale: Int) throws {
      let attachment = RasterImageAttachment(
        identity: Identity(components: ["alpha"]),
        bounds: rect(x: 0, width: 2),
        source: .data(try imageBytes(left: .white, right: .white)),
        isResizable: true, opacity: 0.5
      )
      let surface = RasterSurface(
        size: CellSize(width: 2, height: 1), cells: [[.empty, .empty]],
        imageAttachments: [attachment]
      )
      try withContext(columns: 2, scale: scale) { context, metrics, bounds in
        NativeRasterSurfaceRenderer.draw(
          surface: surface, style: .default, metrics: metrics,
          bounds: bounds, dirtyRect: bounds, context: context
        )
        let before = try pixels(context)
        for _ in 0..<4 {
          NativeRasterSurfaceRenderer.draw(
            surface: surface, style: .default, metrics: metrics, bounds: bounds,
            dirtyRect: CGRect(origin: .zero, size: metrics.cellSize), context: context
          )
        }
        #expect(try pixels(context) == before)
      }
    }

    @Test("typed image opacity affects actual native pixels")
    func typedOpacity() throws {
      let bytes = try imageBytes(left: .white, right: .white)
      let image = try #require(NSImage(data: Data(bytes)))
      var values: [CGFloat] = []
      for opacity in [0.0, 0.5, 1.0] {
        let attachment = RasterImageAttachment(
          identity: Identity(components: ["opacity"]),
          bounds: rect(x: 0, width: 1),
          source: .data(bytes), opacity: opacity
        )
        try withContext(columns: 1) { context, metrics, bounds in
          NativeRasterSurfaceRenderer.draw(
            surface: RasterSurface(
              size: CellSize(width: 1, height: 1), cells: [[.empty]],
              imageAttachments: [attachment]
            ), style: .default, metrics: metrics, bounds: bounds,
            dirtyRect: bounds, context: context
          )
          values.append(try color(context, x: Int(metrics.cellSize.width / 2)).redComponent)
          let actual = try pixels(context)
          try withContext(columns: 1) { reference, _, referenceBounds in
            reference.setFillColor(
              NativePlatformColor.terminalColor(
                SwiftUIHostTerminalStyle.default.palette.background
              ).cgColor)
            reference.fill(referenceBounds)
            image.draw(
              in: referenceBounds, from: .zero, operation: .sourceOver,
              fraction: opacity, respectFlipped: true, hints: nil
            )
            let expected = try pixels(reference)
            #expect(expected == actual)
          }
        }
      }
      #expect(values[0] < values[1])
      #expect(values[1] < values[2])
    }

    @Test("reverse video paints blank cell backgrounds")
    func reversedBlank() throws {
      let style = ResolvedTextStyle(
        foregroundColor: .red, backgroundColor: .blue, emphasis: [.reverse]
      )
      try withContext(columns: 1) { context, metrics, bounds in
        NativeRasterSurfaceRenderer.draw(
          surface: RasterSurface(
            size: CellSize(width: 1, height: 1), cells: [[RasterCell(style: style)]]
          ), style: .default, metrics: metrics, bounds: bounds,
          dirtyRect: bounds, context: context
        )
        let actual = try pixels(context)
        NativeRasterSurfaceRenderer.draw(
          surface: RasterSurface(
            size: CellSize(width: 1, height: 1),
            cells: [
              [
                RasterCell(
                  style: ResolvedTextStyle(
                    foregroundColor: .blue, backgroundColor: .red
                  ))
              ]
            ]
          ), style: .default, metrics: metrics, bounds: bounds,
          dirtyRect: bounds, context: context
        )
        #expect(try pixels(context) == actual)
      }
    }

    @Test("blank cells retain their line decorations")
    func decoratedBlank() throws {
      try withContext(columns: 1) { context, metrics, bounds in
        let plain = RasterSurface(size: CellSize(width: 1, height: 1), cells: [[.empty]])
        NativeRasterSurfaceRenderer.draw(
          surface: plain, style: .default, metrics: metrics, bounds: bounds,
          dirtyRect: bounds, context: context
        )
        let before = try pixels(context)
        let decorated = RasterSurface(
          size: CellSize(width: 1, height: 1),
          cells: [
            [
              RasterCell(
                style: ResolvedTextStyle(
                  underlineStyle: .init(pattern: .solid)
                ))
            ]
          ]
        )
        NativeRasterSurfaceRenderer.draw(
          surface: decorated, style: .default, metrics: metrics, bounds: bounds,
          dirtyRect: bounds, context: context
        )
        #expect(try pixels(context) != before)
      }
    }

    @Test("italic glyph changes and removal match full paint", arguments: [1, 2])
    func italicIncrementalPaint(scale: Int) throws {
      try withContext(columns: 3, scale: scale) { context, metrics, bounds in
        let dirty = CGRect(
          x: metrics.cellSize.width, y: 0,
          width: metrics.cellSize.width, height: metrics.cellSize.height
        )
        let blank = RasterSurface(
          size: CellSize(width: 3, height: 1), cells: [[.empty, .empty, .empty]])
        NativeRasterSurfaceRenderer.draw(
          surface: blank, style: .default, metrics: metrics, bounds: bounds,
          dirtyRect: bounds, context: context
        )
        for character: Character in ["W", "f", " "] {
          let surface = RasterSurface(
            size: CellSize(width: 3, height: 1),
            cells: [
              [
                .empty,
                RasterCell(character: character, style: ResolvedTextStyle(emphasis: [.italic])),
                .empty,
              ]
            ])
          NativeRasterSurfaceRenderer.draw(
            surface: surface, style: .default, metrics: metrics, bounds: bounds,
            dirtyRect: dirty, context: context
          )
          let actual = try pixels(context)
          try withContext(columns: 3, scale: scale) {
            reference, referenceMetrics, referenceBounds in
            NativeRasterSurfaceRenderer.draw(
              surface: surface, style: .default, metrics: referenceMetrics, bounds: referenceBounds,
              dirtyRect: referenceBounds, context: reference
            )
            let expected = try pixels(reference)
            #expect(expected == actual)
          }
        }
      }
    }

    private func withContext(
      columns: Int, scale: Int = 1,
      body: (CGContext, NativeTerminalMetrics, CGRect) throws -> Void
    ) throws {
      let metrics = NativeTerminalMetrics(style: .default)
      let width = Int(metrics.cellSize.width) * columns * scale
      let height = Int(metrics.cellSize.height) * scale
      let bitmap = unsafe CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
      let context = try #require(bitmap)
      context.translateBy(x: 0, y: CGFloat(height))
      context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
      defer { NSGraphicsContext.restoreGraphicsState() }
      try body(
        context, metrics,
        CGRect(
          x: 0, y: 0, width: metrics.cellSize.width * CGFloat(columns),
          height: metrics.cellSize.height
        ))
    }

    private func pixels(_ context: CGContext) throws -> Data {
      try #require(context.makeImage()?.dataProvider?.data as Data?)
    }

    private func rect(x: Int, width: Int) -> CellRect {
      CellRect(origin: CellPoint(x: x, y: 0), size: CellSize(width: width, height: 1))
    }

    private func color(_ context: CGContext, x: Int) throws -> NSColor {
      let image = try #require(context.makeImage())
      let color = try #require(NSBitmapImageRep(cgImage: image).colorAt(x: x, y: image.height / 2))
      return try #require(color.usingColorSpace(.sRGB))
    }

    private func imageBytes(left: NSColor, right: NSColor) throws -> [UInt8] {
      let bitmap = unsafe CGContext(
        data: nil, width: 4, height: 1, bitsPerComponent: 8, bytesPerRow: 16,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
      let context = try #require(bitmap)
      context.setFillColor(left.cgColor)
      context.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
      context.setFillColor(right.cgColor)
      context.fill(CGRect(x: 2, y: 0, width: 2, height: 1))
      let image = try #require(context.makeImage())
      return Array(
        try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])))
    }
  }
#endif
