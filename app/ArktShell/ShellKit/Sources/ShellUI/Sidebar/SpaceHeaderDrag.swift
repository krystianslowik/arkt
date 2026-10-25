import CoreGraphics
import Foundation

/// Header drag that reorders Spaces (BH-039). `moveSpace(_:to:)`'s index is in the full `spaceOrder`, measured
/// before the Space is removed. `visible` is the profile's order, which is what the drag slots follow.
enum SpaceHeaderDrag {
  /// One slot per header width: the header is the Space's page, so dragging it one page width passes one Space, and
  /// a move commits at half of that, the same distance a swipe between Space pages commits at. Derived from the
  /// header's own geometry, not the dock's dot pitch.
  static func pitch(headerWidth: CGFloat) -> CGFloat { max(headerWidth, 0) }

  /// Slots crossed by a horizontal drag. Nil when that rounds to staying put.
  static func slotDelta(translation: CGFloat, pitch: CGFloat) -> Int? {
    guard pitch > 0 else { return nil }
    let slots = Int((translation / pitch).rounded())
    return slots == 0 ? nil : slots
  }

  /// Where the title is drawn for a drag of `translation`: 1:1 as far as the slots the Space can move to (`slotsBefore`
  /// to the left, `slotsAfter` to the right), rubber-banded past them so the drag still answers where nothing is left
  /// to pass.
  static func displayedOffset(_ translation: CGFloat, slotsBefore: Int, slotsAfter: Int, pitch: CGFloat) -> CGFloat {
    let lower = -CGFloat(max(slotsBefore, 0)) * pitch
    let upper = CGFloat(max(slotsAfter, 0)) * pitch
    if translation > upper { return upper + PagingMath.rubberBand(translation - upper, dimension: pitch) }
    if translation < lower { return lower - PagingMath.rubberBand(lower - translation, dimension: pitch) }
    return translation
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
