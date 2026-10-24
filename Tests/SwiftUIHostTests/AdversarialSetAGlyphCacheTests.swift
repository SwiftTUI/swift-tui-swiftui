import CoreGraphics
import Foundation
import SwiftTUIRuntime
import Testing

@_spi(Raster) @testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  @MainActor
  struct AdversarialSetAGlyphCacheTests {
    @Test(arguments: Array(26...35))
    func contract(id: Int) throws {
      if id <= 33 {
        let cache = GlyphNaturalSizeCache(capacity: id == 33 ? 1 : 2)
        var measurements = 0
        func size(
          _ character: Character, _ emphasis: TextStyle.TextEmphasis = [], _ width: CGFloat = 1
        ) -> CGSize {
          cache.size(for: character, emphasis: emphasis) {
            measurements += 1
            return .init(width: width, height: 2)
          }
        }
        let first = size("a")
        switch id {
        case 26:
          #expect(size("a", [], 9) == first)
          #expect(measurements == 1)
        case 27:
          #expect(size("b", [], 3).width == 3)
          #expect(size("a", [], 9) == first)
          #expect(measurements == 2)
        case 28, 29, 30:
          let emphasis: TextStyle.TextEmphasis =
            id == 28 ? [.bold] : id == 29 ? [.italic] : [.bold, .italic]
          #expect(size("a", emphasis, 3).width == 3)
          if id == 30 {
            #expect(size("a", [.bold], 4).width == 4)
            #expect(measurements == 3)
          } else {
            #expect(size("a", [], 9) == first)
            #expect(measurements == 2)
          }
        case 31:
          _ = size("b")
          _ = size("c")
          #expect(size("a", [], 4).width == 4)
          #expect(measurements == 4)
        case 32:
          _ = size("b")
          #expect(size("a", [], 9) == first)
          #expect(size("b", [], 9).width == 1)
          #expect(measurements == 2)
        case 33:
          _ = size("b", [], 3)
          #expect(size("b", [], 9).width == 3)
          #expect(measurements == 2)
        default: Issue.record("unknown scenario")
        }
      } else {
        var style = SwiftUIHostTerminalStyle.default
        style.fontSize = 12
        let first = NativeTerminalMetrics(style: style)
        if id == 35 { style.fontSize = 24 }
        let next = id == 34 ? first : NativeTerminalMetrics(style: style)
        let measured = next.naturalGlyphSize(for: "W", emphasis: [])
        let expected = ("W" as NSString).size(withAttributes: [.font: next.font(for: [])])
        #expect(measured == expected)
        if id == 34 {
          #expect(measured == first.naturalGlyphSize(for: "W", emphasis: []))
        } else {
          #expect(measured.width > first.naturalGlyphSize(for: "W", emphasis: []).width)
        }
      }
    }
  }
#endif
