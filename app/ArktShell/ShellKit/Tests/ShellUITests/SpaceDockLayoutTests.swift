import CoreGraphics
import Testing
@testable import ShellUI

/// #193: the Space dock centers the dots when they fit and scrolls a strip when they do not.
/// Widths are the dock slot between the archive and new-tab buttons: 110 pt at the default 190 pt sidebar,
/// 70 pt at the 150 pt minimum. Pitch 21.5 pt (4 pt dot, 17.5 pt gap).
struct SpaceDockLayoutTests {
  @Test func fiveSpacesFitCenteredAtTheDefaultWidth() {
    let layout = SpaceDockLayout(count: 5, width: 110)
    #expect(layout.contentWidth == 90)
    #expect(!layout.overflows)
    #expect(layout.maxOffset == 0)
    #expect(layout.dotMinX(0, offset: 0) == 10)
    #expect(layout.dotMinX(4, offset: 0) == 96)
  }

  @Test func fourSpacesFitAtTheMinimumWidth() {
    let layout = SpaceDockLayout(count: 4, width: 70)
    #expect(!layout.overflows)
    #expect(layout.dotMinX(0, offset: 0) >= 0)
    #expect(layout.dotMinX(3, offset: 0) + SidebarMetrics.spaceDotSize <= 70)
  }

  @Test func sixSpacesOverflowTheDefaultWidth() {
    let layout = SpaceDockLayout(count: 6, width: 110)
    #expect(layout.overflows)
    // Half a gap before the first dot and after the last one: 6 * 21.5 = 129.
    #expect(layout.stripWidth == 129)
    #expect(layout.maxOffset == 19)
    #expect(layout.dotMinX(0, offset: 0) == 8.75)
    #expect(layout.dotMinX(0, offset: 19) == -10.25)
    #expect(layout.hitMinX(5, offset: 19) + layout.pitch == 110, "scrolled to the end, the last hit box ends at the edge")
  }

  @Test func clampsTheOffset() {
    let layout = SpaceDockLayout(count: 12, width: 70)
    #expect(layout.maxOffset == 188)
    #expect(layout.clamp(-5) == 0)
    #expect(layout.clamp(500) == 188)
    #expect(layout.clamp(40) == 40)
    #expect(SpaceDockLayout(count: 3, width: 110).clamp(40) == 0)
  }

  @Test func revealScrollsOnlyAsFarAsNeeded() {
    let layout = SpaceDockLayout(count: 12, width: 110)
    #expect(layout.offsetRevealing(2, from: 0) == 0, "already visible")
    #expect(layout.offsetRevealing(11, from: 0) == 148, "last hit box ends at the right edge")
    #expect(layout.offsetRevealing(0, from: 148) == 0)
    #expect(layout.offsetRevealing(7, from: 0) == 8 * 21.5 - 110)
    #expect(layout.offsetRevealing(3, from: 100) == 3 * 21.5)
    #expect(layout.offsetRevealing(99, from: 0) == 148, "an out-of-range index reveals the nearest end")
    #expect(SpaceDockLayout(count: 5, width: 110).offsetRevealing(4, from: 30) == 0, "no scrolling when it fits")
  }

  @Test func everyDotIsFullyVisibleAfterRevealing() {
    for width in [70.0, 110.0, 150.0] {
      for count in [5, 7, 12] {
        let layout = SpaceDockLayout(count: count, width: width)
        for index in 0..<count {
          let offset = layout.offsetRevealing(index, from: index.isMultiple(of: 2) ? 0 : layout.maxOffset)
          let minX = layout.dotMinX(index, offset: offset)
          #expect(minX >= 0 && minX + SidebarMetrics.spaceDotSize <= width, "\(count) at \(width): dot \(index)")
        }
      }
    }
  }

  @Test func fadesOnlyTheSidesWithHiddenDots() {
    let layout = SpaceDockLayout(count: 12, width: 110)
    #expect(layout.fades(offset: 0) == (leading: false, trailing: true))
    #expect(layout.fades(offset: 60) == (leading: true, trailing: true))
    #expect(layout.fades(offset: layout.maxOffset) == (leading: true, trailing: false))
    #expect(SpaceDockLayout(count: 3, width: 110).fades(offset: 0) == (leading: false, trailing: false))
  }

  @Test func noSpacesNoContent() {
    let layout = SpaceDockLayout(count: 0, width: 110)
    #expect(layout.contentWidth == 0)
    #expect(!layout.overflows)
    #expect(layout.offsetRevealing(0, from: 0) == 0)
  }
}
