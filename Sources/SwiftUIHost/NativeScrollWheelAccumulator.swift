import CoreGraphics

/// Converts native wheel and trackpad scroll travel into the runtime's scroll
/// deltas: signed whole terminal cells on each axis (`ScrollWheelEvent`).
///
/// The rule matches the browser host. Point deltas divide by the presented
/// cell pitch, and line deltas are one cell per line. Travel below a whole cell
/// carries to the next event, and travel opposing the carried remainder drops
/// it first. The carry stays in the event's own unit, points or lines, so
/// deltas that add up to an exact multiple of the pitch complete their cells on
/// that event; a change of unit or pitch converts it as a fraction of a cell.
/// Each axis of one record is bounded to ``maximumCellDelta`` cells: travel
/// beyond the bound, the carry included, sends the bound and is discarded
/// rather than carried, so no single event scrolls farther.
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

  /// Sub-cell travel carried on one axis: an amount in the unit of the event
  /// that left it, under one `pitch`, the cell pitch in that unit.
  private struct Carry {
    var travel = 0.0
    var pitch = 1.0

    /// The carried travel in a unit whose cell pitch is `other`: exact while
    /// the pitch is unchanged, otherwise converted as a fraction of a cell.
    func travel(atPitch other: Double) -> Double {
      other == pitch ? travel : travel / pitch * other
    }
  }

  private var carryX = Carry()
  private var carryY = Carry()

  /// Sub-cell travel carried to the next event, in cells (under one per axis).
  var remainderX: Double { carryX.travel / carryX.pitch }
  var remainderY: Double { carryY.travel / carryY.pitch }

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
    let x = Self.wholeCells(carry: carryX, delta: horizontal, pitch: pitch.width)
    let y = Self.wholeCells(carry: carryY, delta: vertical, pitch: pitch.height)
    carryX = x.carry
    carryY = y.carry
    return (x.cells, y.cells)
  }

  /// Adds one axis of an event to its carry and splits the total into the
  /// whole cells to send now and the travel to carry. `delta` is in the
  /// event's unit and `pitch` is one cell in that unit; a pitch that is not a
  /// finite positive number makes the delta one cell in its direction.
  /// Nonfinite or zero travel neither scrolls nor drops the carry.
  private static func wholeCells(
    carry: Carry,
    delta: Double,
    pitch: Double
  ) -> (cells: Int, carry: Carry) {
    guard delta.isFinite, delta != 0 else {
      return (0, carry)
    }
    let (travel, cellPitch) =
      pitch.isFinite && pitch > 0 ? (delta, pitch) : (delta > 0 ? 1.0 : -1.0, 1.0)
    let carried = carry.travel(atPitch: cellPitch)
    let reverses = carried != 0 && (travel < 0) != (carried < 0)
    let total = (reverses ? 0 : carried) + travel
    // The bound applies to the travel itself, not to its whole cells, so
    // travel between 16 and 17 cells also sends 16 and carries nothing.
    // Scaling by 16 is exact.
    guard total.isFinite, abs(total) <= Double(maximumCellDelta) * cellPitch else {
      return (
        total > 0 ? maximumCellDelta : -maximumCellDelta,
        Carry(travel: 0, pitch: cellPitch)
      )
    }
    // The remainder is exact, has the total's sign and is under one pitch.
    let remainder = total.truncatingRemainder(dividingBy: cellPitch)
    let cells = ((total - remainder) / cellPitch).rounded()
    return (Int(cells), Carry(travel: remainder, pitch: cellPitch))
  }
}
