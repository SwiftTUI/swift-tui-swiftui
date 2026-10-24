import CoreGraphics
import Foundation
import SwiftTUIRuntime
import Testing

@_spi(Raster) @testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  @MainActor
  struct AdversarialSetAResizeTests {
    @Test(arguments: Array(36...45))
    func contract(id: Int) throws {
      let bridge = s1Bridge()
      let session = S1Session()
      let surface = s1Surface()
      let grid = CellSize(width: 12, height: 3)
      let pixels = PixelSize(width: 8, height: 16)
      if id == 43 { bridge.resize(to: grid, cellPixelSize: pixels) }
      bridge.attach(session: session, surface: surface)
      if id == 36 {
        #expect(session.refreshes == 1)
        #expect(!surface.pointerInputCapabilities.supportsScrollPanning)
        return
      }
      if id == 43 {
        #expect(surface.graphicsCapabilities.cellPixelSize == pixels)
        #expect(bridge.lastViewportSize == grid)
        return
      }
      if id >= 44 {
        let presenter = HostedSurfacePresenter()
        let bounds = CGRect(
          origin: .zero,
          size: .init(
            width: presenter.metrics.cellSize.width * 4,
            height: presenter.metrics.cellSize.height * 2))
        _ = presenter.present(surface: s1Raster(), damage: nil, bounds: bounds)
        var requests: [(CellSize, PixelSize?)] = []
        presenter.onResize = { requests.append(($0, $1)) }
        presenter.publishGridIfNeeded(bounds: bounds.size, backingScale: 1)
        presenter.publishGridIfNeeded(bounds: bounds.size, backingScale: id == 45 ? 2 : 1)
        #expect(requests.count == (id == 45 ? 2 : 1))
        #expect(requests.first?.0 == .init(width: 4, height: 2))
        if id == 45 {
          let a = try #require(requests.first?.1)
          let b = try #require(requests.last?.1)
          #expect(b.width == a.width * 2 && b.height == a.height * 2)
        }
        return
      }
      bridge.resize(to: grid, cellPixelSize: pixels)
      #expect(surface.surfaceSize == grid)
      #expect(session.refreshes == 2)
      switch id {
      case 37: #expect(surface.graphicsCapabilities.cellPixelSize == pixels)
      case 38:
        bridge.resize(to: grid, cellPixelSize: pixels)
        #expect(session.refreshes == 2)
      case 39:
        bridge.resize(to: grid, cellPixelSize: .init(width: 16, height: 32))
        #expect(session.refreshes == 3)
        #expect(surface.graphicsCapabilities.cellPixelSize == .init(width: 16, height: 32))
      case 40, 41:
        bridge.resize(
          to: .init(width: id == 40 ? 0 : 12, height: id == 41 ? 0 : 3), cellPixelSize: nil)
        #expect(session.refreshes == 2)
        #expect(surface.surfaceSize == grid)
      case 42:
        bridge.resize(to: grid, cellPixelSize: nil)
        #expect(session.refreshes == 3)
        #expect(surface.graphicsCapabilities.cellPixelSize == nil)
        #expect(
          surface.pointerInputCapabilities == PointerInputCapabilities(supportsScrollPanning: false)
        )
      default: Issue.record("unknown scenario")
      }
    }
  }
#endif
