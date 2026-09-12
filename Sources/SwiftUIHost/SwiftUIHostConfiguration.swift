/// Presentation options for a ``SwiftUIHostAppView``.
public struct SwiftUIHostConfiguration: Equatable, Sendable {
  /// Whether to show the manual keyboard toggle on iOS when no text-input
  /// control is focused. Defaults to `false`; ignored on macOS and Mac Catalyst.
  public var showsKeyboardToggleButton: Bool

  public init(showsKeyboardToggleButton: Bool = false) {
    self.showsKeyboardToggleButton = showsKeyboardToggleButton
  }

  public static let `default` = Self()
}
