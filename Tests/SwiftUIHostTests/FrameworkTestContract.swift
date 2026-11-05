#if SWIFTTUI_HOST_CONTRACT_V1
  @_spi(Host) @_spi(Testing) import SwiftTUIRuntime
#else
  // The exact tagged dependency exposes these test operations under Runners.
  // Candidate qualification selects the separate Host and Testing contracts.
  @_spi(Runners) import SwiftTUIRuntime
#endif

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
