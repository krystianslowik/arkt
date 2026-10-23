import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

@MainActor
final class SplitContainerViewTests: XCTestCase {
  private var windows: [NSWindow] = []

  override func setUp() async throws { _ = NSApplication.shared }

  override func tearDown() async throws {
    for window in windows { window.close() }
    windows = []
  }

  /// A 1010 x 600 container (two equal panes are 500 wide with the 10 pt gap) in an off-screen-safe window.
  private func makeContainer(width: CGFloat = 1010, height: CGFloat = 600) -> SplitContainerView {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    windows.append(window)
    let container = SplitContainerView()
    container.frame = NSRect(x: 0, y: 0, width: width, height: height)
    window.contentView = NSView(frame: container.frame)
    window.contentView?.addSubview(container)
    container.layoutSubtreeIfNeeded()
    return container
  }

  private func page(_ color: NSColor) -> NSView {
    let view = NSView(frame: .zero)
    view.wantsLayer = true
    view.layer?.backgroundColor = color.cgColor
    return view
  }

  private func show(_ container: SplitContainerView, _ panes: [NSView?], axis: SplitAxis = .sideBySide,
                    factors: [Double]? = nil) {
    container.show(panes: panes, axis: axis,
                   factors: factors ?? Array(repeating: 1 / Double(panes.count), count: panes.count))
    container.layoutSubtreeIfNeeded()
  }

  private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, in view: NSView,
                          clickCount: Int = 1) throws -> NSEvent {
    let window = try XCTUnwrap(view.window)
    let location = view.convert(point, to: nil)
    return try XCTUnwrap(NSEvent.mouseEvent(
      with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1))
  }

  // MARK: Showing panes

  func testShowTwoPanesPlacesContentInCards() throws {
    let container = makeContainer()
    let a = page(.systemRed)
    let b = page(.systemBlue)
    show(container, [a, b])
    XCTAssertEqual(container.paneCards.count, 2)
    XCTAssertEqual(container.dividers.count, 1)
    XCTAssertTrue(a.superview === container.paneCards[0].clipView)
    XCTAssertTrue(b.superview === container.paneCards[1].clipView)
    XCTAssertEqual(container.paneCards[0].frame, NSRect(x: 0, y: 0, width: 500, height: 600))
    XCTAssertEqual(container.paneCards[1].frame, NSRect(x: 510, y: 0, width: 500, height: 600))
    XCTAssertEqual(container.dividers[0].frame, NSRect(x: 500, y: 0, width: 10, height: 600))
    XCTAssertEqual(a.frame.size, container.paneCards[0].clipView.bounds.size)
  }

  func testStackedPanesPutTheFirstOnTop() throws {
    let container = makeContainer(width: 800, height: 610)
    show(container, [page(.systemRed), page(.systemBlue)], axis: .stacked)
    XCTAssertEqual(container.paneCards[0].frame, NSRect(x: 0, y: 310, width: 800, height: 300))
    XCTAssertEqual(container.paneCards[1].frame, NSRect(x: 0, y: 0, width: 800, height: 300))
  }

  func testPaneCardsAreReusedAcrossShowCalls() throws {
    let container = makeContainer()
    let a = page(.systemRed)
    let b = page(.systemBlue)
    let c = page(.systemGreen)
    show(container, [a, b, c])
    let cards = container.paneCards
    let dividers = container.dividers
    // Fewer panes hides the extra card; the same pages in another order move between the same cards.
    show(container, [b, a])
    XCTAssertTrue(container.paneCards[0] === cards[0])
    XCTAssertTrue(container.paneCards[1] === cards[1])
    XCTAssertTrue(container.dividers[0] === dividers[0])
    XCTAssertTrue(cards[2].isHidden)
    XCTAssertNil(cards[2].contentView)
    XCTAssertTrue(c.superview == nil)
    XCTAssertTrue(b.superview === cards[0].clipView)
    XCTAssertTrue(a.superview === cards[1].clipView)
    show(container, [a, b, c])
    XCTAssertTrue(container.paneCards[2] === cards[2])
    XCTAssertFalse(cards[2].isHidden)
    XCTAssertTrue(c.superview === cards[2].clipView)
    XCTAssertTrue(a.superview === cards[0].clipView)
  }

  func testClosedPaneShowsPlaceholderAndClickRequestsFocus() throws {
    let container = makeContainer()
    let a = page(.systemRed)
    show(container, [a, nil])
    XCTAssertNil(container.paneCards[1].contentView)
    let placeholder = try XCTUnwrap(container.paneCards[1].emptyStateView)
    var requests: [Int] = []
    container.onFocusRequest = { requests.append($0) }
    placeholder.mouseDown(with: try mouseEvent(.leftMouseDown, at: NSPoint(x: 20, y: 20), in: placeholder))
    XCTAssertEqual(requests, [1])
    show(container, [a, page(.systemBlue)])
    XCTAssertNil(container.paneCards[1].emptyStateView)
  }

  func testShowCapsAtFourPanesAndNormalizesFactors() throws {
    let container = makeContainer(width: 1200)
    show(container, (0..<5).map { _ in page(.systemGray) }, factors: [0.5, 0.5])
    XCTAssertEqual(container.paneCards.count, SplitLayoutInfo.maximumPanes)
    XCTAssertEqual(container.liveFactors, [0.25, 0.25, 0.25, 0.25])
  }

  func testFocusedPaneDrawsTheStrongerBorder() throws {
    let container = makeContainer()
    show(container, [page(.systemRed), page(.systemBlue)])
    container.focusedIndex = 1
    XCTAssertEqual(container.paneCards[0].borderEmphasis, 0.5)
    XCTAssertEqual(container.paneCards[1].borderEmphasis, 1)
  }

  // MARK: Divider drag

  func testDragMovesFramesWithoutCommitUntilEnd() throws {
    let container = makeContainer()
    show(container, [page(.systemRed), page(.systemBlue)])
    var commits: [[Double]] = []
    container.onCommitFactors = { commits.append($0) }
    let divider = container.dividers[0]
    divider.beginDrag()
    divider.drag(to: 300)
    XCTAssertEqual(container.paneCards[0].frame, NSRect(x: 0, y: 0, width: 300, height: 600))
    XCTAssertEqual(container.paneCards[1].frame, NSRect(x: 310, y: 0, width: 700, height: 600))
    XCTAssertEqual(divider.frame.minX, 300)
    divider.drag(to: 400)
    XCTAssertEqual(container.paneCards[0].frame.width, 400)
    XCTAssertTrue(commits.isEmpty, "a drag never writes the source per frame")
    divider.endDrag()
    XCTAssertEqual(commits.count, 1)
    XCTAssertEqual(commits.first?[0] ?? 0, 0.4, accuracy: 1e-9)
    XCTAssertEqual(commits.first?[1] ?? 0, 0.6, accuracy: 1e-9)
    XCTAssertEqual(container.liveFactors, commits.first)
    XCTAssertNotNil(container.lastPacing)
    // A second end, or an end without a begin, commits nothing.
    divider.endDrag()
    XCTAssertEqual(commits.count, 1)
  }

  func testDragClampsToTheMinimumPaneLength() throws {
    let container = makeContainer()
    show(container, [page(.systemRed), page(.systemBlue)])
    let divider = container.dividers[0]
    divider.beginDrag()
    divider.drag(to: 10)
    XCTAssertEqual(container.paneCards[0].frame.width, SplitLayout.minimumPaneLength)
    divider.endDrag()
  }

  func testMouseDragFollowsThePointerAndCommitsOnce() throws {
    let container = makeContainer()
    show(container, [page(.systemRed), page(.systemBlue)])
    var commits: [[Double]] = []
    container.onCommitFactors = { commits.append($0) }
    let divider = container.dividers[0]
    // A plain click on the gap moves nothing and writes nothing.
    divider.mouseDown(with: try mouseEvent(.leftMouseDown, at: NSPoint(x: 504, y: 300), in: container))
    divider.mouseUp(with: try mouseEvent(.leftMouseUp, at: NSPoint(x: 504, y: 300), in: container))
    XCTAssertTrue(commits.isEmpty)
    // Grab the divider 4 pt into the gap; the gap keeps that offset under the pointer.
    divider.mouseDown(with: try mouseEvent(.leftMouseDown, at: NSPoint(x: 504, y: 300), in: container))
    divider.mouseDragged(with: try mouseEvent(.leftMouseDragged, at: NSPoint(x: 704, y: 300), in: container))
    XCTAssertEqual(container.paneCards[0].frame.width, 700)
    XCTAssertTrue(commits.isEmpty)
    divider.mouseUp(with: try mouseEvent(.leftMouseUp, at: NSPoint(x: 704, y: 300), in: container))
    XCTAssertEqual(commits.count, 1)
    XCTAssertEqual(commits.first?[0] ?? 0, 0.7, accuracy: 1e-9)
  }

  func testDoubleClickEqualizes() throws {
    let container = makeContainer(width: 1220)
    show(container, [page(.systemRed), page(.systemBlue), page(.systemGreen)], factors: [0.5, 0.3, 0.2])
    var commits: [[Double]] = []
    container.onCommitFactors = { commits.append($0) }
    let divider = container.dividers[1]
    let point = NSPoint(x: divider.frame.midX, y: 300)
    // AppKit delivers a double-click as down(1), up(1), down(2), up(2).
    divider.mouseDown(with: try mouseEvent(.leftMouseDown, at: point, in: container))
    divider.mouseUp(with: try mouseEvent(.leftMouseUp, at: point, in: container))
    divider.mouseDown(with: try mouseEvent(.leftMouseDown, at: point, in: container, clickCount: 2))
    divider.mouseUp(with: try mouseEvent(.leftMouseUp, at: point, in: container, clickCount: 2))
    let third: Double = 1.0 / 3
    XCTAssertEqual(container.liveFactors, [third, third, third])
    XCTAssertEqual(commits.count, 1, "the double-click commits once and the mouse-up adds nothing")
    XCTAssertEqual(container.paneCards.map(\.frame.width), [400, 400, 400])
  }

  func testDoubleClickOnAnEqualSplitCommitsNothing() throws {
    let container = makeContainer()
    show(container, [page(.systemRed), page(.systemBlue)], factors: [0.5, 0.5])
    var commits: [[Double]] = []
    container.onCommitFactors = { commits.append($0) }
    let divider = container.dividers[0]
    let point = NSPoint(x: divider.frame.midX, y: 300)
    divider.mouseDown(with: try mouseEvent(.leftMouseDown, at: point, in: container))
    divider.mouseUp(with: try mouseEvent(.leftMouseUp, at: point, in: container))
    divider.mouseDown(with: try mouseEvent(.leftMouseDown, at: point, in: container, clickCount: 2))
    divider.mouseUp(with: try mouseEvent(.leftMouseUp, at: point, in: container, clickCount: 2))
    XCTAssertTrue(commits.isEmpty, "equal shares are already stored; nothing to write")
    XCTAssertEqual(container.liveFactors, [0.5, 0.5])
  }

  func testBackingScaleChangeRequestsLayout() throws {
    let container = makeContainer()
    show(container, [page(.systemRed), page(.systemBlue)])
    XCTAssertFalse(container.needsLayout)
    container.viewDidChangeBackingProperties()
    XCTAssertTrue(container.needsLayout)
  }

  func testWindowResizeKeepsFactors() throws {
    let container = makeContainer()
    show(container, [page(.systemRed), page(.systemBlue)], factors: [0.3, 0.7])
    container.setFrameSize(NSSize(width: 2010, height: 600))
    container.layoutSubtreeIfNeeded()
    XCTAssertEqual(container.liveFactors, [0.3, 0.7])
    XCTAssertEqual(container.paneCards[0].frame.width, 600)
    XCTAssertEqual(container.paneCards[1].frame.width, 1400)
  }

  func testNoImplicitAnimationsOnDrag() throws {
    let container = makeContainer()
    show(container, [page(.systemRed), page(.systemBlue)])
    let divider = container.dividers[0]
    divider.beginDrag()
    divider.drag(to: 320)
    container.layoutSubtreeIfNeeded()
    var layers: [CALayer] = [container.layer, divider.layer].compactMap { $0 }
    for card in container.paneCards {
      layers += [card.layer, card.clipView.layer, card.contentView?.layer].compactMap { $0 }
    }
    XCTAssertFalse(layers.isEmpty)
    for layer in layers {
      XCTAssertNil(layer.animationKeys(), "implicit animation on \(layer)")
    }
    divider.endDrag()
  }

  // MARK: Window

  func testRootViewHostsAHiddenSplitAtTheCardFrame() throws {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    let window = try XCTUnwrap(controller.window)
    windows.append(window)
    let root = try XCTUnwrap(window.contentView as? ShellRootView)
    root.layoutSubtreeIfNeeded()
    XCTAssertTrue(root.split.isHidden)
    XCTAssertEqual(root.split.frame, root.card.frame)
    XCTAssertTrue(root.split.superview === root)
  }

  // MARK: Accessibility

  func testDividerIsAnAdjustableSplitter() throws {
    let container = makeContainer()
    show(container, [page(.systemRed), page(.systemBlue)], factors: [0.4, 0.6])
    var commits: [[Double]] = []
    container.onCommitFactors = { commits.append($0) }
    let divider = container.dividers[0]
    XCTAssertTrue(divider.isAccessibilityElement())
    XCTAssertEqual(divider.accessibilityRole(), .splitter)
    XCTAssertEqual(divider.accessibilityOrientation(), .vertical)
    XCTAssertEqual((divider.accessibilityValue() as? NSNumber)?.doubleValue ?? 0, 0.4, accuracy: 1e-9)
    XCTAssertTrue(divider.accessibilityPerformIncrement())
    XCTAssertEqual(commits.count, 1)
    XCTAssertGreaterThan(container.liveFactors[0], 0.4)
    XCTAssertTrue(divider.accessibilityPerformDecrement())
    XCTAssertEqual(commits.count, 2)
    XCTAssertEqual(container.liveFactors[0], 0.4, accuracy: 1e-9)
    XCTAssertEqual(container.accessibilityRole(), .splitGroup)
    show(container, [page(.systemRed), page(.systemBlue)], axis: .stacked)
    XCTAssertEqual(divider.accessibilityOrientation(), .horizontal)
  }
}
