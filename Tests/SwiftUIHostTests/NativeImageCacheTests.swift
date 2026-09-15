import CoreGraphics
import Foundation
import ImageIO
import SwiftTUIRuntime
import Testing

@testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

@MainActor
struct NativeImageCacheTests {
  @Test("STUI-469: placement, palette and alpha reuse decoded content; changed frames invalidate")
  func contentIdentity() throws {
    let cache = NativeImageCache()
    var image = try attachment(red: 1)
    let content = try #require(cache.content(for: image))
    for frame in 0..<100 {
      image.bounds.origin.x = frame
      image.visibleBounds = image.bounds
      image.opacity = Double(frame) / 100
      #expect(cache.image(for: image, background: frame % 2 == 0 ? .white : .black) != nil)
      #expect(cache.content(for: image) === content)
    }
    #expect(cache.decodeCount == 1)
    image.source = .data(try png(red: 0))
    #expect(cache.image(for: image, background: .black) != nil)
    #expect(cache.decodeCount == 2)
    #expect(cache.content(for: image)?.id != content.id)
    image.source = .data(content.bytes)
    #expect(cache.image(for: image, background: .black) != nil)
    #expect(cache.decodeCount == 2)
  }

  @Test("a 160 by 60 image document reuses four decodes across full and partial native paint")
  func imageDocumentQualification() throws {
    let sources = try [CGFloat(0), 0.33, 0.66, 1].map { try png(red: $0) }
    let images = (0..<100).map { index in
      RasterImageAttachment(
        identity: Identity(components: ["document", String(index)]),
        bounds: .init(
          origin: .init(x: (index % 20) * 8, y: (index / 20) * 12),
          size: .init(width: 8, height: 12)), source: .data(sources[index % 4]), opacity: 0.5)
    }
    let surface = RasterSurface(
      size: .init(width: 160, height: 60),
      cells: Array(repeating: Array(repeating: .empty, count: 160), count: 60),
      imageAttachments: images)
    let metrics = NativeTerminalMetrics(style: .default)
    let width = Int(metrics.cellSize.width * 160)
    let height = Int(metrics.cellSize.height * 60)
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    let bitmap = unsafe CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    let context = try #require(bitmap)
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
      defer { NSGraphicsContext.restoreGraphicsState() }
    #else
      UIGraphicsPushContext(context)
      defer { UIGraphicsPopContext() }
    #endif
    let cache = NativeImageCache()
    NativeRasterSurfaceRenderer.draw(
      surface: surface, style: .default, metrics: metrics,
      bounds: bounds, dirtyRect: bounds, context: context, imageCache: cache)
    let full = try #require(context.makeImage()?.dataProvider?.data as Data?)
    for index in 0..<100 {
      let dirty = CGRect(
        x: CGFloat(index % 160) * metrics.cellSize.width,
        y: CGFloat(index % 60) * metrics.cellSize.height,
        width: metrics.cellSize.width, height: metrics.cellSize.height)
      NativeRasterSurfaceRenderer.draw(
        surface: surface, style: .default, metrics: metrics,
        bounds: bounds, dirtyRect: dirty, context: context, imageCache: cache)
    }
    let partial = try #require(context.makeImage()?.dataProvider?.data as Data?)
    #expect(partial == full)
    #expect(cache.decodeCount == 4)
    #expect(cache.sourceCount == 4)
    #expect(cache.retainedSourceBytes <= 32 * 1024 * 1024)
    #expect(cache.retainedDecodedBytes <= 64 * 1024 * 1024)
    print(
      "IMAGE-CACHE-QUALIFICATION grid=160x60 attachments=100 partialPaints=100 decodes=\(cache.decodeCount) sourceBytes=\(cache.retainedSourceBytes) decodedBytes=\(cache.retainedDecodedBytes) equalPixels=true"
    )
  }

  @Test(
    "file snapshots invalidate on replacement and same-inode writes; references are authoritative")
  func fileInvalidation() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try Data(png(red: 1)).write(to: file)
    var image = try attachment(red: 0)
    image.resolvedReference = .filePath(file.path)
    let cache = NativeImageCache()
    let first = try #require(cache.content(for: image))
    for _ in 0..<50 { #expect(cache.image(for: image, background: .black) != nil) }
    #expect(cache.fileReads == 1)
    #expect(cache.decodeCount == 1)
    try Data(png(red: 0)).write(to: file, options: .atomic)
    let second = try #require(cache.content(for: image))
    #expect(second.id != first.id)
    #expect(cache.image(for: image, background: .black) != nil)
    let modified = try #require(
      FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate])
    try Data(png(red: 0.5)).write(to: file)
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
    #expect(cache.content(for: image)?.id != second.id)
    #expect(cache.image(for: image, background: .black) != nil)
    #expect(cache.decodeCount == 3)
    try FileManager.default.removeItem(at: file)
    #expect(cache.image(for: image, background: .black) == nil)
  }

  @Test("eviction, oversized admission and presenter disposal release bounded resources")
  func lifetimeAndBounds() throws {
    var cache: NativeImageCache? = NativeImageCache(
      maxEntries: 1, sourceBytes: 4096, decodedBytes: 4096)
    let first = try attachment(red: 1)
    weak let retired = cache?.content(for: first)
    #expect(autoreleasepool { cache?.image(for: first, background: .black) != nil })
    weak let retiredBitmap = cache?.retainedBitmap
    let second = try attachment(red: 0)
    #expect(autoreleasepool { cache?.image(for: second, background: .black) != nil })
    #expect(retired == nil)
    #expect(retiredBitmap == nil)
    #expect(cache?.sourceCount == 1)
    #expect(cache?.decodedCount == 1)
    #expect(try #require(cache?.retainedSourceBytes) <= 4096)
    #expect(try #require(cache?.retainedDecodedBytes) <= 4096)
    weak let disposed = cache?.content(for: second)
    weak let disposedBitmap = cache?.retainedBitmap
    cache = nil
    #expect(disposed == nil)
    #expect(disposedBitmap == nil)
    let tiny = NativeImageCache(maxEntries: 1, sourceBytes: 1, decodedBytes: 1)
    #expect(tiny.image(for: first, background: .black) != nil)
    #expect(tiny.sourceCount == 0)
    #expect(tiny.decodedCount == 0)
    let presenter = HostedSurfacePresenter()
    #expect(presenter.imageCache.image(for: first, background: .black) != nil)
    _ = presenter.present(surface: nil, damage: nil, bounds: .zero)
    #expect(presenter.imageCache.sourceCount == 0)
    #expect(presenter.imageCache.decodedCount == 0)
  }

  private func attachment(red: CGFloat) throws -> RasterImageAttachment {
    RasterImageAttachment(
      identity: Identity(components: ["image"]),
      bounds: .init(origin: .zero, size: .init(width: 2, height: 1)),
      source: .data(try png(red: red)))
  }

  private func png(red: CGFloat) throws -> [UInt8] {
    let bitmap = unsafe CGContext(
      data: nil, width: 2, height: 1, bitsPerComponent: 8,
      bytesPerRow: 8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    let context = try #require(bitmap)
    context.setFillColor(CGColor(red: red, green: 0, blue: 1 - red, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
    let data = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    return Array(data as Data)
  }
}
