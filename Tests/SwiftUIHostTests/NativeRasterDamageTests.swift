import CoreGraphics
import Foundation
import SwiftTUIRuntime
import Testing

@testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  @MainActor
  struct NativeRasterDamageTests {
    @Test("STUI-209: palette changes repaint without renegotiating unchanged cell geometry")
    func paletteDirtyReasonQualification() throws {
      try withContext(columns: 2) { context, metrics, bounds in
        let presenter = HostedSurfacePresenter()
        let surface = RasterSurface(
          size: .init(width: 2, height: 1), cells: [[RasterCell(character: "W"), .empty]])
        _ = presenter.present(surface: surface, damage: nil, bounds: bounds)
        _ = presenter.updateMetrics(style: .default, bounds: bounds.size, backingScale: 1)
        var resizeCallbacks = 0
        var layoutInvalidations = 0
        presenter.onResize = { _, _ in resizeCallbacks += 1 }
        var style = SwiftUIHostTerminalStyle.default
        for index in 0..<48 {
          style.palette.background = .init(red: Double(index) / 48, green: 0, blue: 0.5)
          let invalidation = presenter.updateMetrics(
            style: style, bounds: bounds.size, backingScale: 1)
          if invalidation.invalidatesNegotiatedSize { layoutInvalidations += 1 }
          presenter.draw(style: style, bounds: bounds, dirtyRect: bounds, context: context)
          let actual = try pixels(context)
          try withContext(columns: 2) { reference, _, _ in
            NativeRasterSurfaceRenderer.draw(
              surface: surface, style: style, metrics: metrics,
              bounds: bounds, dirtyRect: bounds, context: reference)
            let expected = try pixels(reference)
            #expect(expected == actual)
          }
        }
        print(
          "DIRTY-QUALIFICATION paletteChanges=48 layoutInvalidations=\(layoutInvalidations) resizeCallbacks=\(resizeCallbacks)"
        )
        #expect(layoutInvalidations == 0)
        #expect(resizeCallbacks == 0)
        style.fontSize = 30
        #expect(
          presenter.updateMetrics(style: style, bounds: bounds.size, backingScale: 1)
            .invalidatesNegotiatedSize)
        #expect(resizeCallbacks == 1)
      }
    }

    @Test("STUI-320: measure native full-text painting and its cell clip operations")
    func clipCostQualification() throws {
      try withContext(columns: 160, rows: 60) { context, metrics, bounds in
        let surface = RasterSurface(
          size: .init(width: 160, height: 60),
          cells: Array(
            repeating: Array(repeating: RasterCell(character: "W"), count: 160), count: 60))
        var full: [Double] = []
        var clips: [Double] = []
        for iteration in 0..<25 {
          var start = ContinuousClock.now
          NativeRasterSurfaceRenderer.draw(
            surface: surface, style: .default, metrics: metrics,
            bounds: bounds, dirtyRect: bounds, context: context)
          context.flush()
          var elapsed = start.duration(to: .now).components
          if iteration >= 5 {
            full.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
          }
          start = .now
          for row in 0..<60 {
            for column in 0..<160 {
              context.saveGState()
              context.clip(
                to: CGRect(
                  x: CGFloat(column) * metrics.cellSize.width,
                  y: CGFloat(row) * metrics.cellSize.height, width: metrics.cellSize.width,
                  height: metrics.cellSize.height))
              context.restoreGState()
            }
          }
          elapsed = start.duration(to: .now).components
          if iteration >= 5 {
            clips.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
          }
        }
        print(
          "CLIP-QUALIFICATION fullMs=\(full.sorted()[10]) isolatedClipMs=\(clips.sorted()[10]) clips=9600"
        )
      }
    }

    @Test("pending damage survives split callbacks and repeated presentations; bursts are bounded")
    func pendingDamageLifecycle() throws {
      try withContext(columns: 8) { context, metrics, bounds in
        let presenter = HostedSurfacePresenter()
        let surface = RasterSurface(
          size: .init(width: 8, height: 1), cells: [Array(repeating: .empty, count: 8)])
        var painted: [CGRect] = []
        presenter.onDrawRect = { painted.append($0) }
        @MainActor func draw(_ rect: CGRect) {
          presenter.draw(style: .default, bounds: bounds, dirtyRect: rect, context: context)
        }
        @MainActor func present(_ ranges: [Range<Int>]) {
          _ = presenter.present(
            surface: surface,
            damage: .init(textRows: [.init(row: 0, columnRanges: ranges)]), bounds: bounds)
        }
        present([])
        draw(bounds)
        painted.removeAll()
        present([0..<2])
        present([7..<8])
        let firstCell = CGRect(origin: .zero, size: metrics.cellSize)
        draw(firstCell)
        #expect(painted == [firstCell])
        painted.removeAll()
        draw(bounds)
        #expect(painted.count == 2)
        #expect(painted[0].minX == metrics.cellSize.width)
        #expect(painted[0].width == metrics.cellSize.width)
        #expect(painted[1].minX == metrics.cellSize.width * 7)
        painted.removeAll()
        for _ in 0..<129 { present([0..<1]) }
        draw(bounds)
        #expect(painted == [bounds])
        painted.removeAll()
        present([0..<1])
        presenter.invalidateDisplay()
        draw(bounds)
        #expect(painted == [bounds])
      }
    }

    @Test("STUI-321: AppKit view preserves the gap between disjoint invalidations")
    func appKitDisjointViewDamage() throws {
      let metrics = NativeTerminalMetrics(style: .default)
      let bounds = CGRect(
        x: 0, y: 0, width: metrics.cellSize.width * 8, height: metrics.cellSize.height)
      let window = NSWindow(
        contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      defer { window.close() }
      let view = NativeTerminalSurfaceView(frame: bounds)
      window.contentView = view
      let bytes = try imageBytes(left: .white, right: .white)
      func surface(_ background: SwiftTUIRuntime.Color, opacity: Double) -> RasterSurface {
        RasterSurface(
          size: .init(width: 8, height: 1),
          cells: [
            Array(
              repeating: RasterCell(character: " ", style: .init(backgroundColor: background)),
              count: 8)
          ],
          imageAttachments: [
            .init(
              identity: Identity(components: ["view-damage"]),
              bounds: rect(x: 0, width: 8), source: .data(bytes), isResizable: true,
              opacity: opacity)
          ])
      }
      try withContext(columns: 8) { context, _, _ in
        var painted: [CGRect] = []
        view.onDrawRect = { [weak view] rect in
          guard let view else { return }
          painted.append(rect)
          NSGraphicsContext.saveGraphicsState()
          NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
          NativeRasterSurfaceRenderer.draw(
            surface: view.surface, style: .default, metrics: metrics,
            bounds: bounds, dirtyRect: rect, context: context)
          NSGraphicsContext.restoreGraphicsState()
        }
        defer { view.onDrawRect = nil }
        view.present(surface: surface(.init(red: 0, green: 0, blue: 1), opacity: 0.25), damage: nil)
        view.displayIfNeeded()
        #expect(!painted.isEmpty)
        let before = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
        painted.removeAll()
        view.present(
          surface: surface(.init(red: 1, green: 0, blue: 0), opacity: 0.75),
          damage: .init(textRows: [.init(row: 0, columnRanges: [0..<1, 7..<8])]))
        view.displayIfNeeded()
        #expect(painted.count == 2)
        let after = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
        let y = Int(bounds.height / 2)
        for column in 0..<8 {
          let x = Int((CGFloat(column) + 0.5) * metrics.cellSize.width)
          let old = try #require(before.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
          let new = try #require(after.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
          #expect(old.alphaComponent > 0.9)
          if column == 0 || column == 7 {
            #expect(new.redComponent > old.redComponent + 0.2)
          } else {
            #expect(new == old)
          }
        }
      }
    }

    @Test(
      "STUI-306: decoration patterns have distinct full and incremental pixels", arguments: [1, 2])
    func decorationPatterns(scale: Int) throws {
      let patterns: [TextLineStyle.Pattern] = [
        .solid, .dot, .dash, .dashDot, .dashDotDot, .double, .curly,
      ]
      for strike in [false, true] {
        var outputs: Set<Data> = []
        for pattern in patterns {
          let line = TextLineStyle(pattern: pattern, color: .init(red: 1, green: 0, blue: 0))
          let cell = RasterCell(
            character: " ",
            style: ResolvedTextStyle(
              foregroundColor: .init(red: 0, green: 1, blue: 0), backgroundColor: .init(white: 0),
              underlineStyle: strike ? nil : line, strikethroughStyle: strike ? line : nil))
          let surface = RasterSurface(
            size: .init(width: 8, height: 1), cells: [Array(repeating: cell, count: 8)])
          try withContext(columns: 8, scale: scale) { context, metrics, bounds in
            NativeRasterSurfaceRenderer.draw(
              surface: surface, style: .default, metrics: metrics,
              bounds: bounds, dirtyRect: bounds, context: context)
            let full = try pixels(context)
            outputs.insert(full)
            // Damage starts mid-pattern, and revisits the same pixels.
            for column in [3, 5, 3] {
              NativeRasterSurfaceRenderer.draw(
                surface: surface, style: .default, metrics: metrics,
                bounds: bounds,
                dirtyRect: CGRect(
                  x: CGFloat(column) * metrics.cellSize.width,
                  y: 0, width: metrics.cellSize.width, height: bounds.height), context: context)
            }
            #expect(try pixels(context) == full)
            let bitmap = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
            var redRows: Set<Int> = []
            for y in 0..<bitmap.pixelsHigh {
              for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if color.redComponent > 0.4 {
                  redRows.insert(y)
                  #expect(color.redComponent > color.greenComponent)
                }
              }
            }
            #expect(!redRows.isEmpty)
            if pattern == .double {
              #expect((redRows.max()! - redRows.min()!) >= 2 * scale)
            }
          }
        }
        #expect(outputs.count == patterns.count)
      }
    }

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
      columns: Int, rows: Int = 1, scale: Int = 1,
      body: (CGContext, NativeTerminalMetrics, CGRect) throws -> Void
    ) throws {
      let metrics = NativeTerminalMetrics(style: .default)
      let width = Int(metrics.cellSize.width) * columns * scale
      let height = Int(metrics.cellSize.height) * rows * scale
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
          height: metrics.cellSize.height * CGFloat(rows)
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
