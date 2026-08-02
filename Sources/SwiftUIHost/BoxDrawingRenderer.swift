import CoreGraphics
import Foundation

/// A procedural renderer for Unicode box-drawing characters (U+2500–U+257F), block elements (U+2580–U+259F), and braille patterns (U+2800–U+28FF).
///
/// These glyphs fill the em square and connect across adjacent cells.
/// Most fonts supply the glyphs at the em size.
/// Terminal cells include additional height for descenders and leading.
/// Thus, font-rendered box-drawing columns can have a visible vertical gap.
/// Procedural drawing fills the cell rectangle without gaps for all font metrics and cell dimensions.
///
/// The renderer treats braille glyphs as a 2×4 subpixel mosaic that matches `BrailleCanvas`.
/// Each set bit fills its subcell rectangle instead of a font-style dot.
/// Thus, partial fills connect to their neighbors, and `⣿` is pixel-identical to `█`.
enum BoxDrawingRenderer {
  static func canRender(_ character: Character) -> Bool {
    guard character.unicodeScalars.count == 1,
      let scalar = character.unicodeScalars.first
    else {
      return false
    }
    let value = scalar.value
    return (0x2500...0x259F).contains(value) || (0x2800...0x28FF).contains(value)
  }

  /// Paints `character` into `rect` with `color`.
  /// If the renderer supports the code point, it paints the glyph and returns `true`.
  /// If the renderer does not support the code point, it returns `false`.
  /// The caller can then use font rendering.
  @discardableResult
  static func draw(
    character: Character,
    in rect: CGRect,
    color: CGColor,
    context: CGContext
  ) -> Bool {
    guard character.unicodeScalars.count == 1,
      let scalar = character.unicodeScalars.first
    else {
      return false
    }
    let codePoint = scalar.value

    context.saveGState()
    defer { context.restoreGState() }
    context.setFillColor(color)
    context.setStrokeColor(color)

    if (0x2500...0x257F).contains(codePoint) {
      return drawBoxDrawing(codePoint: codePoint, rect: rect, context: context)
    }
    if (0x2580...0x259F).contains(codePoint) {
      return drawBlockElement(codePoint: codePoint, rect: rect, context: context)
    }
    if (0x2800...0x28FF).contains(codePoint) {
      return drawBraille(codePoint: codePoint, rect: rect, context: context)
    }
    return false
  }

  // MARK: - Internal types
  //
  // Shared geometry types for the renderer. Widened from `fileprivate` to
  // file-internal so the Lines / Blocks / Braille extensions in their own
  // files can reach them. They stay namespaced under `BoxDrawingRenderer`.

  enum LineWeight: UInt8 {
    case none = 0
    case light
    case heavy
    case double
  }

  typealias Spec = (n: LineWeight, e: LineWeight, s: LineWeight, w: LineWeight)

  struct StrokeMetrics {
    let light: CGFloat
    let heavy: CGFloat
    let doubleGap: CGFloat
  }

  static func strokeMetrics(for rect: CGRect) -> StrokeMetrics {
    let unit = max(1, (min(rect.width, rect.height) / 16).rounded())
    return StrokeMetrics(light: unit, heavy: unit * 2, doubleGap: unit)
  }

  enum Direction {
    case north, east, south, west
  }

  enum Corner {
    case topLeft, topRight, bottomLeft, bottomRight
  }
}

// The three glyph-block renderers each live in their own file:
// - box-drawing lines (U+2500–U+257F) → `BoxDrawingRenderer+Lines.swift`
// - block elements (U+2580–U+259F) → `BoxDrawingRenderer+Blocks.swift`
// - braille patterns (U+2800–U+28FF) → `BoxDrawingRenderer+Braille.swift`
