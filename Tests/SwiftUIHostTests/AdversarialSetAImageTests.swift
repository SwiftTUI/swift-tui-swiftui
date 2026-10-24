import CoreGraphics
import Foundation
import SwiftTUIRuntime
import Testing

@_spi(Raster) @testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  @MainActor
  struct AdversarialSetAImageTests {
    @Test(arguments: Array(91...100))
    func contract(id: Int) throws {
      let cache = NativeImageCache(
        maxEntries: id == 95 ? 2 : 128, sourceBytes: id == 96 ? 1 : 32 * 1024 * 1024)
      var attachment = s1Attachment([1, 2, 3])
      if id >= 99 {
        attachment.source = .data(try s1PNG())
        #expect(cache.image(for: attachment, background: .black) != nil)
        #expect(cache.decodeCount == 1)
        if id == 100 {
          cache.removeAll()
          #expect(cache.sourceCount == 0 && cache.decodedCount == 0)
        } else {
          attachment.bounds.origin.x = 2
          attachment.visibleBounds = attachment.bounds
        }
        #expect(cache.image(for: attachment, background: .white) != nil)
        #expect(cache.decodeCount == (id == 100 ? 2 : 1))
        return
      }
      if id == 94 {
        let a = Array(repeating: UInt8(0), count: 130)
        var b = a
        b[65] = 1
        let first = try #require(cache.content(for: s1Attachment(a)))
        let second = try #require(cache.content(for: s1Attachment(b)))
        #expect(first !== second && first.bytes != second.bytes)
        return
      }
      let first = try #require(cache.content(for: attachment))
      switch id {
      case 91:
        attachment.bounds.origin.x = 2
        attachment.visibleBounds = attachment.bounds
        #expect(cache.content(for: attachment) === first)
      case 92:
        attachment.opacity = 0.25
        #expect(cache.content(for: attachment) === first)
      case 93:
        attachment.source = .data([1, 2, 4])
        #expect(cache.content(for: attachment) !== first)
      case 95:
        let b = s1Attachment([4, 5, 6])
        let oldB = try #require(cache.content(for: b))
        #expect(cache.content(for: attachment) === first)
        _ = cache.content(for: s1Attachment([7, 8, 9]))
        #expect(cache.content(for: attachment) === first)
        #expect(cache.content(for: b) !== oldB)
        #expect(cache.sourceCount == 2)
      case 96:
        #expect(first.bytes == [1, 2, 3])
        #expect(cache.sourceCount == 0 && cache.retainedSourceBytes == 0)
      case 97:
        cache.removeAll()
        #expect(cache.sourceCount == 0 && cache.decodedCount == 0)
        #expect(cache.retainedSourceBytes == 0 && cache.retainedDecodedBytes == 0)
      case 98:
        attachment.resolvedReference = .embeddedImage([9, 8, 7])
        #expect(cache.content(for: attachment)?.bytes == [9, 8, 7])
      default: Issue.record("unknown scenario")
      }
    }
  }
#endif
