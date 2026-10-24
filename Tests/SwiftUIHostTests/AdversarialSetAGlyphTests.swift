import CoreGraphics
import Foundation
import SwiftTUIRuntime
import Testing

@_spi(Raster) @testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  @MainActor
  struct AdversarialSetAGlyphTests {
    @Test(arguments: Array(16...25))
    func contract(id: Int) throws {
      var style = ResolvedTextStyle()
      var character: Character = "W"
      let span = id == 20 || id == 21 ? 2 : 1
      switch id {
      case 16: character = "◉"
      case 17: character = "▼"
      case 18: style.emphasis = [.italic]
      case 19: style.emphasis = [.bold]
      case 20: character = "界"
      case 21: character = "😀"
      case 22: character = "e\u{301}"
      case 23:
        character = " "
        style.emphasis = [.reverse]
      case 24:
        character = " "
        style.underlineStyle = .init(pattern: .solid)
      case 25:
        character = " "
        style.strikethroughStyle = .init(pattern: .solid)
      default: Issue.record("unknown scenario")
      }
      func regions(_ styled: Bool) throws -> (own: Data, trailing: Data) {
        var lead = RasterCell(character: styled ? character : " ", spanWidth: span)
        if styled { lead.style = style }
        var row = [lead]
        if span == 2 { row.append(RasterCell(continuationLeadX: 0)) }
        while row.count < 3 { row.append(.empty) }
        let raster = RasterSurface(size: .init(width: 3, height: 1), cells: [row])
        let image = try #require(
          SwiftUIHostRasterCapture.image(of: raster, style: .default, scale: 1))
        let data = try #require(image.dataProvider?.data as Data?)
        let cellWidth = Int(NativeTerminalMetrics(style: .default).cellSize.width)
        let bpp = image.bitsPerPixel / 8
        var own = Data()
        var trailing = Data()
        for y in 0..<image.height {
          let start = y * image.bytesPerRow
          let split = start + cellWidth * span * bpp
          own.append(data[start..<split])
          trailing.append(data[split..<(start + image.width * bpp)])
        }
        return (own, trailing)
      }
      let actual = try regions(true)
      let blank = try regions(false)
      #expect(actual.trailing == blank.trailing)
      #expect(actual.own != blank.own)
    }
  }
#endif
