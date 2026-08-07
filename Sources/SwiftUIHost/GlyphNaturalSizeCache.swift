import CoreGraphics
import Foundation
import SwiftTUIRuntime

/// Memoizes natural glyph sizes for `NativeTerminalMetrics`.
///
/// `NativeRasterSurfaceRenderer` measures every non-space glyph it draws to
/// decide whether the glyph fits its cell span. The measurement is a full
/// Core Text layout — comparable in cost to the draw itself — so a repaint
/// would otherwise pay it once per glyph cell. A glyph's natural size varies
/// only with the character and the resolved font, and one metrics value
/// fixes its four font variants for its lifetime, so (character, emphasis)
/// fully keys a measurement. The owning metrics value ties the cache's
/// lifetime to its font configuration: a style change builds new metrics and
/// with it a fresh cache.
///
/// The capacity bound is a safety valve, not an eviction policy: a terminal
/// app's glyph repertoire is small, so the bound should never be reached in
/// practice. If it is, the cache resets wholesale rather than tracking
/// recency.
final class GlyphNaturalSizeCache: @unchecked Sendable {
  private struct Key: Hashable {
    let character: Character
    let emphasis: UInt8
  }

  private let capacity: Int
  private let lock = NSLock()
  private var sizes: [Key: CGSize] = [:]

  init(capacity: Int = 4096) {
    self.capacity = capacity
  }

  /// Returns the memoized size for `(character, emphasis)`, calling
  /// `measure` only on the first lookup of that key. `measure` runs outside
  /// the lock — measuring is idempotent, so a racing lookup of the same key
  /// may measure a second time rather than block behind Core Text layout.
  func size(
    for character: Character,
    emphasis: SwiftTUIRuntime.TextStyle.TextEmphasis,
    measure: () -> CGSize
  ) -> CGSize {
    let key = Key(character: character, emphasis: emphasis.rawValue)

    lock.lock()
    let cached = sizes[key]
    lock.unlock()
    if let cached {
      return cached
    }

    let measured = measure()

    lock.lock()
    if sizes.count >= capacity {
      sizes.removeAll(keepingCapacity: true)
    }
    sizes[key] = measured
    lock.unlock()
    return measured
  }
}
