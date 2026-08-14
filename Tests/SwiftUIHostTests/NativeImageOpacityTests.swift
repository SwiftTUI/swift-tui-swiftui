import CoreGraphics
import Testing

@testable import SwiftUIHost

struct NativeImageOpacityTests {
  @Test
  func additiveAttachmentOpacityDefaultsAndClampsAtPlacement() {
    #expect(nativeImageOpacity(LegacyAttachment()) == 1)
    #expect(nativeImageOpacity(OpacityAttachment(opacity: 0.4)) == 0.4)
    #expect(nativeImageOpacity(OpacityAttachment(opacity: -1)) == 0)
    #expect(nativeImageOpacity(OpacityAttachment(opacity: 2)) == 1)
    #expect(nativeImageOpacity(OpacityAttachment(opacity: .nan)) == 1)
  }
}

private struct LegacyAttachment {}

private struct OpacityAttachment {
  let opacity: Double
}
