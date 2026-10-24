import CoreGraphics
import Foundation
import SwiftTUIRuntime
import Testing

@_spi(Raster) @testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  @MainActor
  struct AdversarialSetAAccessibilityTests {
    @Test(arguments: Array(46...60))
    func contract(id: Int) throws {
      var node = s1Node()
      var cell = CGSize(width: 9, height: 17)
      switch id {
      case 46: node.hidden = true
      case 47: node.rect = .zero
      case 48: node.rect = .init(origin: .init(x: 2, y: 3), size: .init(width: 4, height: 2))
      case 49: node.rect.origin = .init(x: -1, y: -2)
      case 50: cell.width = 0
      case 51: node.role = .button
      case 52: node.role = .heading(level: 2)
      case 53: node.role = .link
      case 54: node.role = .image
      case 55: node.role = .secureField
      case 56: node.role = .slider
      case 57: node.role = .custom("meter")
      case 58:
        node.label = "界😀"
        node.hint = "e\u{301}"
      case 59: node.parentIdentity = s1Identity("parent")
      case 60: node.liveRegion = .polite
      default: Issue.record("unknown scenario")
      }
      let result = s1Mapping(node, cell: cell)
      if [46, 47, 50].contains(id) {
        #expect(result == nil)
        return
      }
      let mapped = try #require(result)
      #expect(mapped.identity == node.identity)
      switch id {
      case 48: #expect(mapped.frame == CGRect(x: 18, y: 51, width: 36, height: 34))
      case 49: #expect(mapped.frame.origin == CGPoint(x: -9, y: -34))
      case 51: #expect(mapped.traits == [.button] && mapped.controlKind == .action)
      case 52: #expect(mapped.traits == [.header] && mapped.controlKind == .staticText)
      case 53: #expect(mapped.traits == [.link] && mapped.controlKind == .link)
      case 54: #expect(mapped.traits == [.image] && mapped.controlKind == .image)
      case 55: #expect(mapped.traits.isEmpty && mapped.controlKind == .textInput)
      case 56: #expect(mapped.controlKind == .adjustable)
      case 57: #expect(mapped.controlKind == .group && mapped.roleDescription == "custom(meter)")
      case 58: #expect(mapped.label == "界😀" && mapped.hint == "e\u{301}")
      case 59: #expect(mapped.parentIdentity == s1Identity("parent"))
      case 60: #expect(mapped.liveRegion == .polite)
      default: Issue.record("unknown mapped scenario")
      }
    }
  }
#endif
