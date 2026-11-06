@_spi(Host) import SwiftTUIRuntime

@MainActor
func installNativeClipboardReader(on surface: HostedRasterSurface) {
  surface.setClipboardReader(NativeClipboard.read)
}

extension AccessibilityNode {
  var hostFocusIdentity: Identity { runtimeFocusIdentity }

  var hostPresentationIdentity: Identity {
    presentationIdentity
  }
}

enum FrameworkHostContract {
  static func hasOccurrence(_ identity: Identity) -> Bool {
    identity.hasPresentationOccurrence
  }
}

struct HostImagePayload {
  let id: String
  let bytes: [UInt8]
}

final class HostImageCompositor {
  private let compositor = ImageBlendCompositor()

  func encodedPNGPayload(
    for attachment: RasterImageAttachment, fallbackBackground: Color
  ) -> HostImagePayload? {
    compositor.encodedPNGPayload(for: attachment, fallbackBackground: fallbackBackground).map {
      HostImagePayload(id: $0.id, bytes: $0.bytes)
    }
  }
}
