import CoreGraphics
import Foundation
import SwiftTUIRuntime

// Platform-neutral surface presentation/negotiation state machine for the
// native terminal host.
//
// The AppKit (`NSView`) and UIKit (`UIView`) terminal views previously carried
// byte-identical copies of the size-negotiation, grid-publication, and
// damage-to-dirty-rects logic. `HostedSurfacePresenter` owns that shared state
// and behavior once; each platform view keeps only its thin `#if`-gated shell.
//
// The presenter never references a platform view. Platform-variable inputs
// (`bounds`, `backingScale`, `noIntrinsicMetric`) are passed in at call time,
// and the platform-variable side effects (mark-needs-display, partial redraw,
// invalidate-intrinsic-size + needs-layout) are returned as an `Invalidation`
// value that the view applies with its own platform APIs. This keeps the type
// `Sendable`-free of any UIKit/AppKit dependency and avoids a view/presenter
// retain cycle.
//
// Split out of `NativeTerminalSurfaceView.swift`; behavior is identical to the
// former per-platform copies. The type is `@MainActor`-isolated to match the
// isolation of the `NSView`/`UIView` shells it backs — the former per-platform
// state and closures already ran exclusively on the main actor.

@MainActor
final class HostedSurfacePresenter {
  // What redraw a `present(...)` call asks the host view to perform.
  enum DisplayInvalidation {
    case none
    case full
    case rects([CGRect])
  }

  // Side effects a presenter call asks the host view to apply, expressed in
  // platform-neutral terms so each shell can translate to its own API.
  struct Invalidation {
    var invalidatesNegotiatedSize = false
    var display: DisplayInvalidation = .none
  }

  private(set) var surface: RasterSurface?
  var preferredGridSize: CellSize?
  var onResize: ((CellSize, PixelSize?) -> Void)?

  private(set) var metrics = NativeTerminalMetrics(style: .default)
  private var lastPublishedLayoutGrid: CellSize?
  private var lastPublishedLayoutCellPixelSize: PixelSize?
  private var lastRequestedSurfaceGrid: CellSize?
  private var lastRequestedSurfaceCellPixelSize: PixelSize?
  private var confirmedSlack = HostedSurfaceConfirmedSlack()

  // Recompute terminal metrics for a new style. Mirrors the former
  // `updateMetrics()`: the caller is responsible for applying the returned
  // negotiated-size invalidation and for marking itself needs-display.
  func updateMetrics(
    style: SwiftUIHostTerminalStyle,
    bounds: CGSize,
    backingScale: CGFloat
  ) -> Invalidation {
    metrics = NativeTerminalMetrics(style: style)
    publishGridIfNeeded(bounds: bounds, backingScale: backingScale)
    return Invalidation(invalidatesNegotiatedSize: true)
  }

  func present(
    surface: RasterSurface?,
    damage: PresentationDamage?,
    bounds: CGRect
  ) -> Invalidation {
    let previousSize = self.surface?.size
    self.surface = surface
    confirmedSlack.update(
      preferredGridSize: preferredGridSize,
      renderedGridSize: surface?.size
    )
    var invalidation = Invalidation()
    if previousSize != surface?.size {
      invalidation.invalidatesNegotiatedSize = true
    }
    invalidation.display = invalidateSurface(
      previousSize: previousSize,
      surface: surface,
      damage: damage,
      bounds: bounds
    )
    return invalidation
  }

  func intrinsicContentSize(
    noIntrinsicMetric: Double
  ) -> CGSize {
    CGSize(
      sizeNegotiator.intrinsicContentSize(
        noIntrinsicMetric: noIntrinsicMetric
      )
    )
  }

  func negotiatedSizeThatFits(
    proposedWidth: CGFloat?,
    proposedHeight: CGFloat?,
    preferredGridSize: CellSize?,
    backingScale: CGFloat
  ) -> CGSize {
    let negotiation = makeSizeNegotiator(preferredGridSize: preferredGridSize).negotiate(
      proposedWidth: proposedWidth.map(Double.init),
      proposedHeight: proposedHeight.map(Double.init)
    )
    publishProbeGridIfNeeded(negotiation.probeGridSize, backingScale: backingScale)
    return CGSize(negotiation.size)
  }

  // Recompute the published grid for the current bounds. Mirrors the former
  // `publishGridIfNeeded()`; called from `layout`/`didMoveToWindow` shells.
  func publishGridIfNeeded(
    bounds: CGSize,
    backingScale: CGFloat
  ) {
    guard bounds.width > 0, bounds.height > 0 else {
      return
    }
    guard preferredGridSize != nil || surface != nil else {
      return
    }

    let grid = metrics.gridSize(for: bounds)
    let cellPixelSize = metrics.cellPixelSize(scale: backingScale)
    guard
      grid != lastPublishedLayoutGrid
        || cellPixelSize != lastPublishedLayoutCellPixelSize
    else {
      return
    }

    lastPublishedLayoutGrid = grid
    lastPublishedLayoutCellPixelSize = cellPixelSize
    publishSurfaceGridIfNeeded(grid, cellPixelSize: cellPixelSize)
  }

  func pointerLocation(
    for local: CGPoint,
    in bounds: CGRect,
    scale: CGFloat
  ) -> PointerLocation {
    metrics.pointerLocation(for: local, in: bounds, scale: scale)
  }

  private var sizeNegotiator: HostedSurfaceSizeNegotiator {
    makeSizeNegotiator(preferredGridSize: preferredGridSize)
  }

  private func makeSizeNegotiator(
    preferredGridSize: CellSize?
  ) -> HostedSurfaceSizeNegotiator {
    HostedSurfaceSizeNegotiator(
      cellSize: HostLengthSize(metrics.cellSize),
      preferredGridSize: preferredGridSize,
      renderedGridSize: surface?.size,
      confirmedSlack: confirmedSlack
    )
  }

  private func publishProbeGridIfNeeded(
    _ grid: CellSize?,
    backingScale: CGFloat
  ) {
    guard let grid else {
      return
    }
    publishSurfaceGridIfNeeded(
      grid,
      cellPixelSize: metrics.cellPixelSize(scale: backingScale)
    )
  }

  private func publishSurfaceGridIfNeeded(
    _ grid: CellSize,
    cellPixelSize: PixelSize?
  ) {
    guard
      grid != lastRequestedSurfaceGrid
        || cellPixelSize != lastRequestedSurfaceCellPixelSize
    else {
      return
    }

    lastRequestedSurfaceGrid = grid
    lastRequestedSurfaceCellPixelSize = cellPixelSize
    onResize?(grid, cellPixelSize)
  }

  private func invalidateSurface(
    previousSize: CellSize?,
    surface: RasterSurface?,
    damage: PresentationDamage?,
    bounds: CGRect
  ) -> DisplayInvalidation {
    guard let surface,
      let damage,
      previousSize == surface.size,
      !damage.requiresFullTextRepaint,
      !damage.requiresFullGraphicsReplay
    else {
      return .full
    }

    let rects = NativeRasterSurfaceRenderer.dirtyRects(
      for: damage,
      surface: surface,
      metrics: metrics,
      bounds: bounds
    )
    guard !rects.isEmpty else {
      return .none
    }
    return .rects(rects)
  }
}

private extension CGSize {
  init(_ size: HostLengthSize) {
    self.init(width: CGFloat(size.width), height: CGFloat(size.height))
  }
}

private extension HostLengthSize {
  init(_ size: CGSize) {
    self.init(width: Double(size.width), height: Double(size.height))
  }
}
