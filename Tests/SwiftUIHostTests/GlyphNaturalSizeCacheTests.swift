import CoreGraphics
import Foundation
import SwiftTUI
import Testing

@testable import SwiftUIHost

/// The glyph-size cache must return the measured size while calling the
/// measurement exactly once per (character, emphasis) key — the measurement
/// is a full Core Text layout, and the renderer performs one lookup per
/// non-space glyph cell per repaint.
struct GlyphNaturalSizeCacheTests {
  @Test("measures once per key and serves the cached size afterwards")
  func measuresOncePerKey() {
    let cache = GlyphNaturalSizeCache()
    var measureCount = 0
    let measured = CGSize(width: 14, height: 21)

    let first = cache.size(for: "◉", emphasis: []) {
      measureCount += 1
      return measured
    }
    let second = cache.size(for: "◉", emphasis: []) {
      measureCount += 1
      return measured
    }

    #expect(first == measured)
    #expect(second == measured)
    #expect(measureCount == 1)
  }

  @Test("distinct characters and emphasis variants are distinct keys")
  func distinctKeysMeasureIndependently() {
    let cache = GlyphNaturalSizeCache()
    let regular = CGSize(width: 8, height: 18)
    let bold = CGSize(width: 9, height: 18)
    let narrow = CGSize(width: 4, height: 18)

    #expect(cache.size(for: "W", emphasis: []) { regular } == regular)
    #expect(cache.size(for: "W", emphasis: [.bold]) { bold } == bold)
    #expect(cache.size(for: "i", emphasis: []) { narrow } == narrow)

    // Each key serves its own cached value, not the last measurement.
    #expect(cache.size(for: "W", emphasis: []) { .zero } == regular)
    #expect(cache.size(for: "W", emphasis: [.bold]) { .zero } == bold)
    #expect(cache.size(for: "i", emphasis: []) { .zero } == narrow)
  }

  @Test("reaching capacity resets the cache and keeps serving fresh measurements")
  func capacityOverflowResets() {
    let cache = GlyphNaturalSizeCache(capacity: 2)
    let sizeA = CGSize(width: 1, height: 1)
    let sizeB = CGSize(width: 2, height: 2)
    let sizeC = CGSize(width: 3, height: 3)
    let remeasuredA = CGSize(width: 4, height: 4)

    #expect(cache.size(for: "a", emphasis: []) { sizeA } == sizeA)
    #expect(cache.size(for: "b", emphasis: []) { sizeB } == sizeB)
    // The third insert overflows capacity 2 and resets the storage.
    #expect(cache.size(for: "c", emphasis: []) { sizeC } == sizeC)

    // "a" was dropped by the reset — it measures again.
    #expect(cache.size(for: "a", emphasis: []) { remeasuredA } == remeasuredA)
  }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  /// `NativeTerminalMetrics.naturalGlyphSize` must agree with a direct
  /// measurement in the metrics' own font — the renderer's fit decision
  /// depends on it.
  @MainActor
  struct NativeTerminalMetricsGlyphSizeTests {
    @Test func naturalGlyphSizeMatchesDirectMeasurement() {
      let metrics = NativeTerminalMetrics(style: .default)
      let expected = ("◉" as NSString).size(
        withAttributes: [.font: metrics.font(for: [])]
      )

      #expect(metrics.naturalGlyphSize(for: "◉", emphasis: []) == expected)
      // The second (cached) lookup answers identically.
      #expect(metrics.naturalGlyphSize(for: "◉", emphasis: []) == expected)
    }
  }
#endif
