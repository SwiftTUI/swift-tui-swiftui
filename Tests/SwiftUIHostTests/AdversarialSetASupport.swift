import CoreGraphics
import Foundation
import SwiftTUIRuntime
import Testing

@_spi(Raster) @testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
  import ImageIO

  @MainActor
  func s1Identity(_ value: String) -> Identity { Identity(components: ["s1", value]) }

  @MainActor
  func s1Node(_ value: String = "node", role: AccessibilityRole = .button) -> AccessibilityNode {
    AccessibilityNode(
      identity: s1Identity(value),
      rect: .init(origin: .zero, size: .init(width: 1, height: 1)), role: role)
  }

  @MainActor
  func s1Mapping(
    _ node: AccessibilityNode, focused: Identity? = nil, cell: CGSize = .init(width: 8, height: 16)
  ) -> AccessibilityNodeMapping? {
    AccessibilityNodeMapper.mapping(for: node, focusedIdentity: focused, cellSize: cell)
  }

  @MainActor
  final class S1Session: HostedSceneSessionHandling {
    var starts = 0
    var stops = 0
    var refreshes = 0
    var events: [InputEvent] = []
    func start() async throws -> RunLoopExitReason {
      starts += 1
      return .inputEnded
    }
    func stop() { stops += 1 }
    func requestSurfaceRefresh() { refreshes += 1 }
    func send(_ event: InputEvent) { events.append(event) }
  }

  @MainActor
  func s1Bridge() -> NativeSceneBridge {
    NativeSceneBridge(
      descriptor: .init(id: "first", title: "First", isDefault: true), style: .default)
  }

  @MainActor
  func s1Surface() -> HostedRasterSurface {
    HostedRasterSurface(
      surfaceSize: .init(width: 8, height: 2), appearance: .fallback, onFrame: { _ in })
  }

  struct S1App: SwiftTUIRuntime.App {
    init() {}
    var body: some Scene {
      WindowGroup("First", id: "first") { Text("First") }
      WindowGroup("Second", id: "second") { Text("Second") }
    }
  }

  @MainActor
  func s1Raster(_ characters: String = "ABCD") -> RasterSurface {
    RasterSurface(
      size: .init(width: 4, height: 2),
      cells: [characters.map { RasterCell(character: $0) }, Array(repeating: .empty, count: 4)])
  }

  @MainActor
  func s1Bitmap(_ body: (CGContext, NativeTerminalMetrics, CGRect) throws -> Void) throws {
    let metrics = NativeTerminalMetrics(style: .default)
    let width = Int(metrics.cellSize.width * 4)
    let height = Int(metrics.cellSize.height * 2)
    let allocated = unsafe CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    let context = try #require(allocated)
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    defer { NSGraphicsContext.restoreGraphicsState() }
    try body(context, metrics, CGRect(x: 0, y: 0, width: width, height: height))
  }

  @MainActor
  func s1Pixels(_ context: CGContext) throws -> Data {
    try #require(context.makeImage()?.dataProvider?.data as Data?)
  }

  @MainActor
  func s1PNG() throws -> [UInt8] {
    let allocated = unsafe CGContext(
      data: nil, width: 1, height: 1, bitsPerComponent: 8,
      bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    let context = try #require(allocated)
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    let data = NSMutableData()
    let target = try #require(
      CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(target, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(target))
    return Array(data as Data)
  }

  @MainActor
  func s1Attachment(_ bytes: [UInt8]) -> RasterImageAttachment {
    .init(
      identity: s1Identity("image"), bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
      source: .data(bytes))
  }
#endif
