import CoreGraphics

/// Converts native wheel and trackpad scroll travel into the runtime's scroll
/// deltas: signed whole terminal cells on each axis (`ScrollWheelEvent`).
///
/// The rule matches the browser host. Point deltas divide by the presented
/// cell pitch, and line deltas are one cell per line. Travel below a whole cell
/// carries to the next event, and travel opposing the carried remainder drops
/// it first. Each axis of one record is bounded to ``maximumCellDelta`` cells;
/// clamped travel is discarded rather than carried, so no single event scrolls
/// farther.
struct NativeScrollWheelAccumulator {
  /// The unit a platform scroll delta is reported in.
  enum Unit {
    /// Points of travel. One cell is the presented cell pitch on that axis.
    case points(cellSize: CGSize)
    /// Lines of a discrete wheel. One line is one cell.
    case lines
  }

  /// The most cells one scroll record carries on each axis, the same bound
  /// the browser and Android hosts apply.
  static let maximumCellDelta = 16

  /// Sub-cell travel carried to the next event, under one cell per axis.
  private(set) var remainderX = 0.0
  private(set) var remainderY = 0.0

  /// Adds one event's travel, already in the runtime's direction (positive
  /// moves right and down), and returns the whole cells to send now.
  mutating func cellDelta(
    horizontal: Double,
    vertical: Double,
    unit: Unit
  ) -> (deltaX: Int, deltaY: Int) {
    let pitch: (width: Double, height: Double)
    switch unit {
    case .points(let cellSize):
      pitch = (Double(cellSize.width), Double(cellSize.height))
    case .lines:
      pitch = (1, 1)
    }
    let x = Self.wholeCells(
      remainder: remainderX, travel: Self.travel(horizontal, pitch: pitch.width))
    let y = Self.wholeCells(
      remainder: remainderY, travel: Self.travel(vertical, pitch: pitch.height))
    remainderX = x.remainder
    remainderY = y.remainder
    return (x.cells, y.cells)
  }

  /// One axis of travel in (fractional) cells. A pitch that is not a finite
  /// positive number falls back to one cell in the delta's direction.
  private static func travel(_ delta: Double, pitch: Double) -> Double {
    guard delta.isFinite, delta != 0 else {
      return 0
    }
    guard pitch.isFinite, pitch > 0 else {
      return delta > 0 ? 1 : -1
    }
    return delta / pitch
  }

  private static func wholeCells(
    remainder: Double,
    travel: Double
  ) -> (cells: Int, remainder: Double) {
    let reverses = travel != 0 && remainder != 0 && (travel < 0) != (remainder < 0)
    let total = (reverses ? 0 : remainder) + travel
    let whole = total.rounded(.towardZero)
    guard abs(whole) <= Double(maximumCellDelta) else {
      return (whole > 0 ? maximumCellDelta : -maximumCellDelta, 0)
    }
    return (Int(whole), total - whole)
  }
}
