import CoreGraphics
import Foundation
import SwiftTUIRuntime
import Testing

@_spi(Raster) @testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  @MainActor
  struct AdversarialSetARasterTests {
    @Test(arguments: Array(1...15))
    func contract(id: Int) throws {
      let surface = s1Raster()
      let metrics = NativeTerminalMetrics(style: .default)
      let w = metrics.cellSize.width
      let h = metrics.cellSize.height
      let bounds = CGRect(x: 0, y: 0, width: 4 * w, height: 2 * h)
      if id <= 10 {
        var damage = PresentationDamage(textRows: [])
        var viewport = bounds
        var expected: [CGRect] = []
        switch id {
        case 1: break
        case 2:
          damage = .init(textRows: [.init(row: 1)])
          expected = [.init(x: 0, y: h, width: 4 * w, height: h)]
        case 3:
          damage = .init(textRows: [.init(row: 0, columnRanges: [1..<3])])
          expected = [.init(x: w, y: 0, width: 2 * w, height: h)]
        case 4: damage = .init(textRows: [.init(row: -1)])
        case 5: damage = .init(textRows: [.init(row: 2)])
        case 6:
          damage = .init(textRows: [.init(row: 0, columnRanges: [-2..<2])])
          expected = [.init(x: 0, y: 0, width: 2 * w, height: h)]
        case 7:
          damage = .init(textRows: [.init(row: 0, columnRanges: [3..<9])])
          expected = [.init(x: 3 * w, y: 0, width: w, height: h)]
        case 8:
          damage = .init(textRows: [.init(row: 0)])
          viewport.size.width = 0
        case 9:
          damage = .init(textRows: [.init(row: 1)])
          viewport.size.height = h
        case 10:
          damage = .init(textRows: [], requiresFullTextRepaint: true)
          expected = [bounds]
        default: Issue.record("unknown scenario")
        }
        #expect(
          NativeRasterSurfaceRenderer.dirtyRects(
            for: damage, surface: surface, metrics: metrics, bounds: viewport) == expected)
        return
      }
      try s1Bitmap { context, metrics, bounds in
        let presenter = HostedSurfacePresenter()
        _ = presenter.present(surface: surface, damage: nil, bounds: bounds)
        presenter.draw(style: .default, bounds: bounds, dirtyRect: bounds, context: context)
        var painted: [CGRect] = []
        presenter.onDrawRect = { painted.append($0) }
        if id == 13 {
          let resized = RasterSurface(
            size: .init(width: 3, height: 2),
            cells: [Array(repeating: .empty, count: 3), Array(repeating: .empty, count: 3)])
          let result = presenter.present(
            surface: resized, damage: .init(textRows: []), bounds: bounds)
          #expect(result.invalidatesNegotiatedSize)
          if case .full = result.display {
          } else {
            Issue.record("resized raster must repaint fully")
          }
          return
        }
        if id == 14 {
          var style = SwiftUIHostTerminalStyle.default
          style.palette.background = .red
          let invalidation = presenter.updateMetrics(
            style: style, bounds: bounds.size, backingScale: 1)
          #expect(!invalidation.invalidatesNegotiatedSize)
          presenter.draw(style: style, bounds: bounds, dirtyRect: bounds, context: context)
          #expect(painted == [bounds])
          return
        }
        let ranges = id == 12 ? [0..<2] : [0..<1, 3..<4]
        let final = id == 15 ? s1Raster("XBCY") : surface
        _ = presenter.present(
          surface: final, damage: .init(textRows: [.init(row: 0, columnRanges: ranges)]),
          bounds: bounds)
        if id == 12 {
          let first = CGRect(
            x: 0, y: 0, width: metrics.cellSize.width, height: metrics.cellSize.height)
          presenter.draw(style: .default, bounds: bounds, dirtyRect: first, context: context)
          #expect(painted == [first])
          painted.removeAll()
          presenter.draw(style: .default, bounds: bounds, dirtyRect: bounds, context: context)
          #expect(painted == [first.offsetBy(dx: first.width, dy: 0)])
        } else {
          presenter.draw(style: .default, bounds: bounds, dirtyRect: bounds, context: context)
          #expect(
            painted == [
              CGRect(x: 0, y: 0, width: w, height: h), CGRect(x: 3 * w, y: 0, width: w, height: h),
            ])
          if id == 15 {
            let actual = try s1Pixels(context)
            try s1Bitmap { reference, referenceMetrics, referenceBounds in
              NativeRasterSurfaceRenderer.draw(
                surface: final, style: .default, metrics: referenceMetrics,
                bounds: referenceBounds, dirtyRect: referenceBounds, context: reference)
              let expectedPixels = try s1Pixels(reference)
              #expect(expectedPixels == actual)
            }
          }
        }
      }
    }
  }
#endif
