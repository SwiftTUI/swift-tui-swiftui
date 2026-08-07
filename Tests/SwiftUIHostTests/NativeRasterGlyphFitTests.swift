import CoreGraphics
import Foundation
import SwiftTUI
import Testing

@_spi(Raster) @testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)

  /// A cell's glyph must render entirely inside its span rect.
  ///
  /// Characters outside the bundled font's coverage (the Geometric Shapes
  /// block: Toggle's `◉`/`○`, Spinner's `◐`, tab chrome's `▼`) come from
  /// CoreText's fallback cascade with a natural advance wider than the cell.
  /// Cells paint left-to-right and incremental repaints clip to per-cell
  /// dirty rects, so any overflow is chopped at the trailing cell edge —
  /// the glyph has to be fitted into its span instead.
  @MainActor
  struct NativeRasterGlyphFitTests {
    @Test(
      "wide fallback glyph leaves trailing cells untouched",
      arguments: ["◉", "○", "◐", "▼"]
    )
    func fallbackGlyphStaysInsideItsCell(glyph: String) throws {
      let glyphRender = try renderedCellRegions(character: try #require(glyph.first))
      let blankRender = try renderedCellRegions(character: " ")

      // Trailing cells must be byte-identical to a blank render: any
      // difference is glyph ink that bled past the cell's span rect.
      #expect(glyphRender.trailingCells == blankRender.trailingCells)

      // The glyph must still leave ink in its own cell — a fit that
      // erased the glyph outright would also pass the bleed check.
      #expect(glyphRender.ownCell != blankRender.ownCell)
    }

    @Test("bundled-font glyph keeps its unscaled monospace rendering")
    func bundledGlyphIsUnaffected() throws {
      let render = try renderedCellRegions(character: "✓")
      let blank = try renderedCellRegions(character: " ")

      #expect(render.trailingCells == blank.trailingCells)
      #expect(render.ownCell != blank.ownCell)
    }

    /// Renders `character` into cell 0 of a 3×1 surface and returns the
    /// pixel bytes of that cell and of the two trailing cells.
    private func renderedCellRegions(
      character: Character
    ) throws -> (ownCell: [UInt8], trailingCells: [UInt8]) {
      let surface = RasterSurface(
        size: .init(width: 3, height: 1),
        cells: [[RasterCell(character: character), .empty, .empty]]
      )
      let image = try #require(
        SwiftUIHostRasterCapture.image(of: surface, style: .default, scale: 1)
      )

      let metrics = NativeTerminalMetrics(style: .default)
      let cellPixelWidth = Int(metrics.cellSize.width.rounded())
      let data = try #require(image.dataProvider?.data as Data?)
      let bytesPerPixel = image.bitsPerPixel / 8

      var ownCell: [UInt8] = []
      var trailingCells: [UInt8] = []
      for y in 0..<image.height {
        let rowStart = y * image.bytesPerRow
        for x in 0..<image.width {
          let pixelStart = rowStart + x * bytesPerPixel
          let pixel = data[pixelStart..<(pixelStart + bytesPerPixel)]
          if x < cellPixelWidth {
            ownCell.append(contentsOf: pixel)
          } else {
            trailingCells.append(contentsOf: pixel)
          }
        }
      }
      return (ownCell, trailingCells)
    }
  }
#endif
