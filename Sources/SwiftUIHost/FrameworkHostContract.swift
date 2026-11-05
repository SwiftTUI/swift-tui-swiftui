#if SWIFTTUI_HOST_CONTRACT_V1
  @_spi(Host) import SwiftTUIRuntime
#else
  // The tagged 0.20.1 floor predates Host SPI. Keep its adapter bounded here;
  // the rendering and accessibility implementations consume the values below.
  @_spi(Runners) import SwiftTUIRuntime
#endif

extension AccessibilityNode {
  var hostFocusIdentity: Identity { runtimeFocusIdentity }

  var hostPresentationIdentity: Identity {
    #if SWIFTTUI_HOST_CONTRACT_V1
      presentationIdentity
    #else
      let focus = runtimeFocusIdentity
      return focus != identity && FrameworkHostContract.hasOccurrence(focus) ? focus : identity
    #endif
  }
}

enum FrameworkHostContract {
  static func hasOccurrence(_ identity: Identity) -> Bool {
    #if SWIFTTUI_HOST_CONTRACT_V1
      identity.hasPresentationOccurrence
    #else
      // Released framework compatibility only. New hosts use the typed query;
      // rendered identity strings are not part of the Host profile's grammar.
      identity.components.contains { component in
        guard component.hasPrefix("ID["), component.hasSuffix("]") else { return false }
        let interior = component.dropFirst(3).dropLast(1)
        guard let marker = interior.lastIndex(of: "#") else { return false }
        let digits = interior[interior.index(after: marker)...]
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
      }
    #endif
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
