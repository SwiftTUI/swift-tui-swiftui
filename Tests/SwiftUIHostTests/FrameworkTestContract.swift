@_spi(Host) @_spi(Testing) import SwiftTUIRuntime

extension HostedRasterSurface {
  func contractWaitForSurface(
    matching predicate: @escaping @Sendable (RasterSurface) -> Bool
  ) async -> RasterSurface {
    await waitForSurface(matching: predicate)
  }

  func contractWaitForFrame(
    matching predicate: @escaping @Sendable (SemanticHostFrame) -> Bool
  ) async -> SemanticHostFrame {
    await waitForFrame(matching: predicate)
  }

  func contractWaitForFrames(
    matching predicate: @escaping @Sendable ([SemanticHostFrame]) -> Bool
  ) async -> [SemanticHostFrame] {
    await waitForFrames(matching: predicate)
  }

  @discardableResult
  func contractPresent(_ frame: SemanticHostFrame) throws -> TerminalPresentationMetrics {
    try present(frame)
  }
}
