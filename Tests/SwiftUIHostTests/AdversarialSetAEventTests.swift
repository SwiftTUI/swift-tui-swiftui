import CoreGraphics
import Foundation
import SwiftTUIRuntime
import Testing

@_spi(Raster) @testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  @MainActor
  struct AdversarialSetAEventTests {
    @Test(arguments: Array(76...85))
    func contract(id: Int) throws {
      if id >= 84 {
        let metrics = NativeTerminalMetrics(style: .default)
        let x = id == 84 ? 2.5 : -0.5
        let y = id == 84 ? 1.25 : -0.25
        let local = CGPoint(x: metrics.cellSize.width * x, y: metrics.cellSize.height * y)
        let location = metrics.pointerLocation(
          for: local, in: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 2)
        #expect(location.location == Point(x: x, y: y))
        #expect(location.rawPixel == PixelPoint(x: local.x * 2, y: local.y * 2))
        return
      }
      let code: UInt16
      let characters: String
      let modifiers: NSEvent.ModifierFlags
      let expected: InputEvent?
      switch id {
      case 76:
        code = 36
        characters = "\r"
        modifiers = []
        expected = .key(.init(.return))
      case 77:
        code = 48
        characters = "\t"
        modifiers = .shift
        expected = .key(.init(.tab, modifiers: .shift))
      case 78:
        code = 51
        characters = "\u{7F}"
        modifiers = []
        expected = .key(.init(.backspace))
      case 79:
        code = 115
        characters = ""
        modifiers = []
        expected = .key(.init(.home))
      case 80:
        code = 123
        characters = ""
        modifiers = .option
        expected = .key(.init(.arrowLeft, modifiers: .alt))
      case 81, 82:
        code = 9
        characters = "v"
        modifiers = id == 81 ? .command : .control
        expected = .key(.init(.character("v"), modifiers: .ctrl))
      case 83:
        code = 0
        characters = "ab"
        modifiers = []
        expected = nil
      default:
        Issue.record("unknown scenario")
        return
      }
      let event = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: modifiers,
          timestamp: 0, windowNumber: 0, context: nil, characters: characters,
          charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
      #expect(NativeInputMapper.inputEvent(for: event) == expected)
    }
  }
#endif
