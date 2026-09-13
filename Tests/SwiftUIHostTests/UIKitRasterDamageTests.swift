import CoreGraphics
import Foundation
import SwiftTUIRuntime
import Testing

@testable import SwiftUIHost

#if canImport(UIKit)
  import UIKit

  @MainActor
  struct UIKitRasterDamageTests {
    @Test("STUI-470: UIKit disjoint invalidations preserve background and image gap pixels")
    func disjointViewDamage() throws {
      let metrics = NativeTerminalMetrics(style: .default)
      let bounds = CGRect(
        x: 0, y: 0, width: metrics.cellSize.width * 8, height: metrics.cellSize.height)
      let controller = UIViewController()
      let window = UIWindow(frame: bounds)
      window.rootViewController = controller
      window.isHidden = false
      defer { window.isHidden = true }
      let view = NativeTerminalSurfaceView(frame: bounds)
      controller.view.addSubview(view)
      controller.view.layoutIfNeeded()
      let bytes = Array(
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 1)).pngData { output in
          UIColor.white.setFill()
          output.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
        })
      func surface(_ background: SwiftTUIRuntime.Color, opacity: Double) -> RasterSurface {
        RasterSurface(
          size: .init(width: 8, height: 1),
          cells: [
            Array(
              repeating: RasterCell(character: " ", style: .init(backgroundColor: background)),
              count: 8)
          ],
          imageAttachments: [
            .init(
              identity: Identity(components: ["uikit-damage"]),
              bounds: .init(origin: .zero, size: .init(width: 8, height: 1)),
              source: .data(bytes), isResizable: true, opacity: opacity)
          ])
      }
      let context = try #require(
        unsafe CGContext(
          data: nil,
          width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8, bytesPerRow: 0,
          space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.translateBy(x: 0, y: bounds.height)
      context.scaleBy(x: 1, y: -1)
      var painted: [CGRect] = []
      view.onDrawRect = { [weak view] rect in
        guard let view else { return }
        painted.append(rect)
        UIGraphicsPushContext(context)
        NativeRasterSurfaceRenderer.draw(
          surface: view.surface, style: .default, metrics: metrics,
          bounds: bounds, dirtyRect: rect, context: context)
        UIGraphicsPopContext()
      }
      defer { view.onDrawRect = nil }
      view.present(surface: surface(.init(red: 0, green: 0, blue: 1), opacity: 0.25), damage: nil)
      view.layer.displayIfNeeded()
      #expect(!painted.isEmpty)
      let before = try #require(context.makeImage())
      let oldBytes = [UInt8](try #require(before.dataProvider?.data as Data?))
      painted.removeAll()
      view.present(
        surface: surface(.init(red: 1, green: 0, blue: 0), opacity: 0.75),
        damage: .init(textRows: [.init(row: 0, columnRanges: [0..<1, 7..<8])]))
      view.layer.displayIfNeeded()
      #expect(painted.count == 2)
      let after = try #require(context.makeImage())
      let newBytes = [UInt8](try #require(after.dataProvider?.data as Data?))
      for column in 0..<8 {
        let x = Int((CGFloat(column) + 0.5) * metrics.cellSize.width)
        let offset = Int(bounds.height / 2) * after.bytesPerRow + x * 4
        #expect(oldBytes[offset + 3] > 240)
        if column == 0 || column == 7 {
          #expect(Int(newBytes[offset]) > Int(oldBytes[offset]) + 40)
        } else {
          #expect(newBytes[offset..<(offset + 4)] == oldBytes[offset..<(offset + 4)])
        }
      }
    }
  }
#endif
