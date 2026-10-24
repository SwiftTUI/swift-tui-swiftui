import CoreGraphics
import Foundation
import SwiftTUIRuntime
import Testing

@_spi(Raster) @testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  @MainActor
  struct AdversarialSetAFocusTests {
    @Test(arguments: Array(61...65))
    func contract(id: Int) throws {
      let a = s1Node("a")
      let b = s1Node("b")
      if id == 64 {
        var hidden = a
        hidden.hidden = true
        let mappings = [hidden, b].compactMap { s1Mapping($0, focused: a.identity) }
        #expect(mappings.count == 1)
        #expect(HostedAccessibilityFocusPolicy.requestedFocusID(in: mappings) == nil)
        return
      }
      let focused: Identity? = id == 61 ? nil : a.identity
      let first = try #require(s1Mapping(a, focused: focused))
      let second = try #require(s1Mapping(b, focused: id == 63 ? b.identity : focused))
      let selected = HostedAccessibilityFocusPolicy.requestedFocusID(in: [first, second])
      #expect(selected == (id == 61 ? nil : a.identity.path))
      if id == 62 { #expect(first.isFocused && !second.isFocused) }
      if id == 65 {
        let moved = [a, b].compactMap { s1Mapping($0, focused: b.identity) }
        #expect(HostedAccessibilityFocusPolicy.requestedFocusID(in: moved) == b.identity.path)
      }
    }
  }
#endif
