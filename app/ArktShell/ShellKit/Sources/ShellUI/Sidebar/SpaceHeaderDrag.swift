import CoreGraphics
import Foundation

/// Header drag that reorders Spaces (BH-039). `moveSpace(_:to:)`'s index is in the full `spaceOrder`, measured
/// before the Space is removed. `visible` is the profile's order, which is what the drag slots follow.
enum SpaceHeaderDrag {
  /// Slots crossed by a horizontal drag. Nil when that rounds to staying put.
  static func slotDelta(translation: CGFloat, pitch: CGFloat) -> Int? {
    guard pitch > 0 else { return nil }
    let slots = Int((translation / pitch).rounded())
    return slots == 0 ? nil : slots
  }

  /// Index to pass to `moveSpace(_:to:)`. Nil for an unknown id, a zero delta, or a delta that clamps to the same slot.
  static func moveIndex(id: SpaceID, order: [SpaceID], visible: [SpaceID], delta: Int) -> Int? {
    guard delta != 0, let fromVisible = visible.firstIndex(of: id), let fromFull = order.firstIndex(of: id) else {
      return nil
    }
    let destination = min(max(fromVisible + delta, 0), visible.count - 1)
    guard destination != fromVisible, visible.indices.contains(destination) else { return nil }
    let target = order.firstIndex(of: visible[destination])
    guard let target else { return nil }
    return target > fromFull ? target + 1 : target
  }
}
