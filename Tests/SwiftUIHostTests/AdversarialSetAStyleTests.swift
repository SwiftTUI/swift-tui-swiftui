import CoreGraphics
import Foundation
import SwiftTUIRuntime
import Testing

@_spi(Raster) @testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  @MainActor
  struct AdversarialSetAStyleTests {
    @Test(arguments: Array(86...90))
    func contract(id: Int) throws {
      let fg = try SwiftTUIRuntime.Color.hex("#123456")
      let bg = try SwiftTUIRuntime.Color.hex("#654321")
      let tint = try SwiftTUIRuntime.Color.hex("#1122AA")
      var palette = SwiftUIHostTerminalPalette.default
      palette.foreground = fg
      palette.background = bg
      palette.cursor = tint
      if id == 90 { palette.ansi = .init(indexedColors: [1: tint]) }
      let explicit = Theme(foreground: bg, background: fg, tint: tint)
      let style = SwiftUIHostTerminalStyle(
        cursorStyle: .bar, cursorBlink: false,
        backgroundOpacity: 0.5, palette: palette, theme: id == 87 ? explicit : nil)
      switch id {
      case 86:
        #expect(style.terminalAppearance.foregroundColor == fg)
        #expect(style.terminalAppearance.backgroundColor == bg)
        #expect(style.terminalAppearance.tintColor == tint)
        #expect(style.terminalAppearance.source == .override)
      case 87: #expect(style.renderStyle.theme == explicit)
      case 88:
        #expect(style.theme.foreground == fg && style.theme.background == bg)
        // Theme synthesis preserves the base colors but repairs insufficient
        // tint contrast. These fixture colors are opaque sRGB values.
        func luminance(_ color: SwiftTUIRuntime.Color) -> Double {
          func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
          }
          return 0.2126 * linear(color.red) + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
        }
        let tintLuminance = luminance(style.theme.tint)
        let backgroundLuminance = luminance(bg)
        let contrast =
          (max(tintLuminance, backgroundLuminance) + 0.05)
          / (min(tintLuminance, backgroundLuminance) + 0.05)
        #expect(style.theme.tint != tint)
        #expect(contrast >= 3 - 1e-8)
      case 89:
        #expect(style.cursorStyle == .bar && !style.cursorBlink && style.backgroundOpacity == 0.5)
      case 90: #expect(style.renderStyle.appearance.palette[1] == tint)
      default: Issue.record("unknown scenario")
      }
    }
  }
#endif
