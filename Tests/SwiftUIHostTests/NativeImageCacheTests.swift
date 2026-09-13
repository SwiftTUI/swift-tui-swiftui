import CoreGraphics
import Foundation
import ImageIO
import SwiftTUIRuntime
import Testing

@testable import SwiftUIHost

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
    weak var retired = cache?.content(for: first)
    #expect(autoreleasepool { cache?.image(for: first, background: .black) != nil })
    weak var retiredBitmap = cache?.retainedBitmap
    let second = try attachment(red: 0)
    #expect(autoreleasepool { cache?.image(for: second, background: .black) != nil })
    #expect(retired == nil)
    #expect(retiredBitmap == nil)
    #expect(cache?.sourceCount == 1)
    #expect(cache?.decodedCount == 1)
    #expect(try #require(cache?.retainedSourceBytes) <= 4096)
    #expect(try #require(cache?.retainedDecodedBytes) <= 4096)
    weak var disposed = cache?.content(for: second)
    weak var disposedBitmap = cache?.retainedBitmap
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
