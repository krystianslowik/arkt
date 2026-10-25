import CoreGraphics
import Testing
@testable import ShellUI

/// Sidebar hide, edge gestures and the hover reveal overlay (#102: BH-001 to BH-004, GS-017, GS-018), pure parts.
struct SidebarHideTests {
  let metrics = ShellMetrics.standard
  let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)   // flipped: y grows downward

  // MARK: Edge drag (BH-002, GS-017)

  @Test func dragAboveTheHideWidthResizesClamped() {
    #expect(ShellLayout.resolveDrag(proposedWidth: 300, metrics: metrics) == .resize(300))
    #expect(ShellLayout.resolveDrag(proposedWidth: 900, metrics: metrics) == .resize(metrics.sidebarMaxWidth))
    // Between the hide width and the minimum the sidebar stays at its minimum (hysteresis for a drag back).
    #expect(ShellLayout.resolveDrag(proposedWidth: 100, metrics: metrics) == .resize(metrics.sidebarMinWidth))
    #expect(ShellLayout.resolveDrag(proposedWidth: metrics.sidebarHideWidth, metrics: metrics)
      == .resize(metrics.sidebarMinWidth))
  }

  @Test func dragFullyLeftHides() {
    #expect(metrics.sidebarHideWidth < metrics.sidebarMinWidth)
    #expect(ShellLayout.resolveDrag(proposedWidth: metrics.sidebarHideWidth - 1, metrics: metrics) == .hide)
    #expect(ShellLayout.resolveDrag(proposedWidth: 0, metrics: metrics) == .hide)
    #expect(ShellLayout.resolveDrag(proposedWidth: -40, metrics: metrics) == .hide)
  }

  // MARK: Hidden layout (BH-001, BH-004)

  @Test func hiddenSidebarKeepsItsWidthAsAnInsetOverlay() {
    let layout = ShellLayout.compute(bounds: bounds, sidebarWidth: 230, sidebarVisible: false, metrics: metrics)
    let inset = metrics.sidebarOverlayInset
    // The sidebar keeps its width (no relayout of its rows), floating inside the window's edges.
    #expect(layout.sidebarFrame == CGRect(x: inset, y: inset, width: 230, height: 800 - 2 * inset))
    #expect(layout.cardFrame == CGRect(x: 10, y: 10, width: 1180, height: 780))
    #expect(layout.resizeHandleFrame == .zero)
    #expect(layout.revealEdgeFrame == CGRect(x: 0, y: 0, width: metrics.sidebarRevealEdgeWidth, height: 800))
  }

  @Test func visibleSidebarHasNoRevealEdge() {
    let layout = ShellLayout.compute(bounds: bounds, sidebarWidth: 190, sidebarVisible: true, metrics: metrics)
    #expect(layout.revealEdgeFrame == .zero)
  }

  @Test func revealEdgeLiesInTheGutterLeftOfTheCard() {
    let layout = ShellLayout.compute(bounds: bounds, sidebarWidth: 190, sidebarVisible: false, metrics: metrics)
    #expect(layout.revealEdgeFrame.maxX <= layout.cardFrame.minX)
    #expect(layout.revealEdgeFrame.width > 0)
    // No gap between the strip and the overlay: the pointer goes from one straight onto the other.
    #expect(layout.revealEdgeFrame.maxX >= layout.sidebarFrame.minX)
  }

  // MARK: Menu (KB-017)

  @Test func menuTitleFollowsVisibility() {
    #expect(ShellWindowController.sidebarMenuTitle(isVisible: true) == "Hide Sidebar")
    #expect(ShellWindowController.sidebarMenuTitle(isVisible: false) == "Show Sidebar")
  }

  // MARK: Reveal presentation (BH-004): transform and opacity only

  @Test func concealedOffsetClearsTheWindowAndTheShadow() {
    let frame = CGRect(x: 10, y: 10, width: 190, height: 780)
    let offset = SidebarRevealMotion.concealedOffset(overlayFrame: frame)
    #expect(offset <= -(frame.maxX + SidebarRevealMotion.shadowRadius))
  }

  @Test func fullMotionSlidesAtFullOpacity() {
    let distance: CGFloat = 220
    let concealed = SidebarRevealMotion.presentation(offset: -distance, distance: distance, reduceMotion: false,
                                                     scale: 2)
    #expect(concealed.translation == -distance)
    #expect(concealed.alpha == 1)
    #expect(concealed.progress == 0)
    let half = SidebarRevealMotion.presentation(offset: -110.3, distance: distance, reduceMotion: false, scale: 2)
    #expect(half.translation == -110.5, "pixel-aligned at 2x")
    #expect(abs(half.progress - 0.4986) < 0.001)
    let revealed = SidebarRevealMotion.presentation(offset: 0, distance: distance, reduceMotion: false, scale: 2)
    #expect(revealed.translation == 0)
    #expect(revealed.progress == 1)
  }

  @Test func springOvershootNeverOpensAGapAtTheLeftEdge() {
    let p = SidebarRevealMotion.presentation(offset: 3, distance: 220, reduceMotion: false, scale: 2)
    #expect(p.translation == 0)
    #expect(p.progress == 1)
  }

  @Test func reduceMotionFadesInPlace() {
    let distance: CGFloat = 220
    let concealed = SidebarRevealMotion.presentation(offset: -distance, distance: distance, reduceMotion: true,
                                                     scale: 2)
    #expect(concealed.translation == 0)
    #expect(concealed.alpha == 0)
    let quarter = SidebarRevealMotion.presentation(offset: -165, distance: distance, reduceMotion: true, scale: 2)
    #expect(quarter.translation == 0)
    #expect(abs(quarter.alpha - 0.25) < 0.0001)
    let revealed = SidebarRevealMotion.presentation(offset: 0, distance: distance, reduceMotion: true, scale: 2)
    #expect(revealed.alpha == 1)
  }

  @Test func zeroDistanceIsRevealed() {
    let p = SidebarRevealMotion.presentation(offset: 0, distance: 0, reduceMotion: false, scale: 2)
    #expect(p.progress == 1)
    #expect(p.translation == 0)
  }

  @Test func revealSpringsComeFromTheSharedPresets() {
    #expect(SidebarRevealMotion.revealPreset == .firm)
    #expect(SidebarRevealMotion.concealPreset == .firmFast)
    // Exit is faster than entry.
    #expect(SidebarRevealMotion.concealPreset.parameters.response < SidebarRevealMotion.revealPreset.parameters.response)
    // No visible bounce on a panel the pointer is aiming at.
    #expect(SidebarRevealMotion.revealPreset.parameters.dampingRatio >= 0.9)
  }

  // MARK: Toasts (BH-006)

  @Test func creationToastTexts() {
    #expect(ShellWindowController.creationToastText(.tab) == "New Tab Created")
    #expect(ShellWindowController.creationToastText(.space) == "New Space Created")
  }
}
