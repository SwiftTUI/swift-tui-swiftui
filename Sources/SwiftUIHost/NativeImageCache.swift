import CoreGraphics
import Darwin
import Foundation
import ImageIO
@_spi(Runners) import SwiftTUIRuntime

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

// Presenter-owned encoded sources and eagerly decoded first-frame images. The
// source owner, not placement geometry or alpha, determines decoded identity.
// This adapter intentionally uses the released host SPI: the standalone package
// continues to build against its tagged framework dependency.
@MainActor
final class NativeImageCache {
  final class Content {
    let id = UUID()
    let bytes: [UInt8]
    init(_ bytes: [UInt8]) { self.bytes = bytes }
  }

  private struct ByteKey: Hashable {
    let bytes: [UInt8]
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.bytes == rhs.bytes }
    func hash(into hasher: inout Hasher) {
      hasher.combine(bytes.count)
      for byte in bytes.prefix(64) { hasher.combine(byte) }
      if bytes.count > 64 {
        for byte in bytes.suffix(64) { hasher.combine(byte) }
      }
    }
  }

  private struct Revision: Hashable {
    let device: dev_t
    let inode: ino_t
    let size: off_t
    let modified: Int
    let modifiedNanos: Int
    let changed: Int
    let changedNanos: Int

    static func read(_ path: String) -> Self? {
      var info = stat()
      guard path.withCString({ unsafe stat($0, &info) }) == 0 else { return nil }
      return Self(
        device: info.st_dev, inode: info.st_ino, size: info.st_size,
        modified: info.st_mtimespec.tv_sec, modifiedNanos: info.st_mtimespec.tv_nsec,
        changed: info.st_ctimespec.tv_sec, changedNanos: info.st_ctimespec.tv_nsec)
    }
  }

  private enum SourceKey: Hashable {
    case bytes(ByteKey)
    case file(String, Revision)
  }
  private enum DecodedKey: Hashable {
    case source(UUID)
    case blend(String)
  }

  private let sources: NativeImageLRU<SourceKey, Content>
  private let decoded: NativeImageLRU<DecodedKey, CGImage>
  private var compositor: ImageBlendCompositor?
  private(set) var fileReads = 0
  private(set) var decodeCount = 0

  init(
    maxEntries: Int = 128, sourceBytes: Int = 32 * 1024 * 1024,
    decodedBytes: Int = 64 * 1024 * 1024
  ) {
    sources = NativeImageLRU(maxEntries: maxEntries, maxBytes: sourceBytes)
    decoded = NativeImageLRU(maxEntries: maxEntries, maxBytes: decodedBytes)
  }

  var retainedBitmap: CGImage? { decoded.firstValue }
  var sourceCount: Int { sources.count }
  var decodedCount: Int { decoded.count }
  var retainedSourceBytes: Int { sources.bytes }
  var retainedDecodedBytes: Int { decoded.bytes }

  func removeAll() {
    sources.removeAll()
    decoded.removeAll()
    compositor = nil
  }

  func content(for attachment: RasterImageAttachment) -> Content? {
    if let reference = attachment.resolvedReference {
      switch reference {
      case .filePath(let path): return file(path)
      case .embeddedImage(let bytes): return embedded(bytes)
      case .namedResource: break
      }
    }
    switch attachment.source {
    case .data(let bytes): return embedded(bytes)
    case .path(let path): return file(path)
    case .fileURL(let value):
      guard let url = URL(string: value), url.isFileURL else { return nil }
      return file(url.path)
    }
  }

  private func embedded(_ bytes: [UInt8]) -> Content {
    let key = SourceKey.bytes(ByteKey(bytes: bytes))
    if let content = sources.value(for: key) { return content }
    let content = Content(bytes)
    sources.insert(content, for: key, cost: Self.cost(bytes.count, bytes.count, 256))
    return content
  }

  private func file(_ path: String) -> Content? {
    for _ in 0..<2 {
      guard let revision = Revision.read(path) else { return nil }
      let key = SourceKey.file(path, revision)
      if let content = sources.value(for: key) { return content }
      guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
      fileReads += 1
      guard revision == Revision.read(path) else { continue }
      let content = Content(Array(data))
      sources.insert(content, for: key, cost: Self.cost(data.count, path.utf8.count, 256))
      return content
    }
    return nil
  }

  func image(for attachment: RasterImageAttachment, background: Color)
    -> (image: NativePlatformImage, bounds: CellRect)?
  {
    guard let content = content(for: attachment) else { return nil }
    let key: DecodedKey
    let bytes: [UInt8]
    let bounds: CellRect
    if attachment.compositing != nil {
      if compositor == nil { compositor = ImageBlendCompositor() }
      // Pass the captured version through the existing SPI. In particular, an
      // older framework's path-keyed blend cache cannot hide a replaced file.
      var captured = attachment
      captured.source = .data(content.bytes)
      captured.resolvedReference = .embeddedImage(content.bytes)
      if let payload = compositor?.encodedPNGPayload(
        for: captured, fallbackBackground: background)
      {
        key = .blend(payload.id)
        bytes = payload.bytes
        bounds = attachment.visibleBounds
      } else {
        key = .source(content.id)
        bytes = content.bytes
        bounds = attachment.bounds
      }
    } else {
      key = .source(content.id)
      bytes = content.bytes
      bounds = attachment.bounds
    }
    let bitmap: CGImage
    if let cached = decoded.value(for: key) {
      bitmap = cached
    } else {
      guard let image = Self.decode(bytes) else { return nil }
      decodeCount += 1
      bitmap = image
      let (pixels, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
      decoded.insert(
        image, for: key,
        cost: overflow ? Int.max : Self.cost(pixels, bytes.count, 256))
    }
    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
      let image = NSImage(cgImage: bitmap, size: CGSize(width: bitmap.width, height: bitmap.height))
    #else
      let image = UIImage(cgImage: bitmap)
    #endif
    return (image, bounds)
  }

  private static func decode(_ bytes: [UInt8]) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(Data(bytes) as CFData, nil) else { return nil }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
    if orientation != 1 {
      let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
      let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
      guard max(width, height) > 0 else { return nil }
      return CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: max(width, height),
          kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }
    return CGImageSourceCreateImageAtIndex(
      source, 0,
      [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
  }

  private static func cost(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let (ab, first) = a.addingReportingOverflow(b)
    let (abc, second) = ab.addingReportingOverflow(c)
    return first || second ? Int.max : abc
  }
}

@MainActor
private final class NativeImageLRU<Key: Hashable, Value> {
  private struct Entry {
    var value: Value
    var cost: Int
    var access: UInt64
  }
  private var entries: [Key: Entry] = [:]
  private var generation: UInt64 = 0
  private let maxEntries: Int
  private let maxBytes: Int
  private(set) var bytes = 0
  var count: Int { entries.count }
  var firstValue: Value? { entries.first?.value.value }

  init(maxEntries: Int, maxBytes: Int) {
    self.maxEntries = max(0, maxEntries)
    self.maxBytes = max(0, maxBytes)
  }
  func value(for key: Key) -> Value? {
    guard var entry = entries[key] else { return nil }
    generation += 1
    entry.access = generation
    entries[key] = entry
    return entry.value
  }
  func insert(_ value: Value, for key: Key, cost: Int) {
    guard maxEntries > 0, cost <= maxBytes else { return }
    if let old = entries.removeValue(forKey: key) { bytes -= old.cost }
    while entries.count >= maxEntries || bytes > maxBytes - cost {
      guard let oldest = entries.min(by: { $0.value.access < $1.value.access }) else { break }
      bytes -= oldest.value.cost
      entries.removeValue(forKey: oldest.key)
    }
    generation += 1
    entries[key] = Entry(value: value, cost: cost, access: generation)
    bytes += cost
  }
  func removeAll() {
    entries.removeAll()
    bytes = 0
  }
}
