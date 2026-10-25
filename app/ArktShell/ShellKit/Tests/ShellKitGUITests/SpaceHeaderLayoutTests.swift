import AppKit
import XCTest
@testable import ShellUI

@MainActor
final class SpaceHeaderLayoutTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  func testNumberedSpaceTitlesFitBeforeAndDuringHover() throws {
    for title in ["Space 1", "Space 2"] {
      let source = StubSidebar()
      let space = source.addSpace(title: title)
      let page = SpacePageView(source: source, spaceID: space)
      for width: CGFloat in [200, 240, 320] {
        page.frame = NSRect(x: 0, y: 0, width: width, height: 500)
        page.layout()
        let resting = page.titleLabel.frame
        try assertTitleFits(page)
        page.setHeaderHovered(true)
        page.layout()
        XCTAssertFalse(page.editButton.isHidden)
        XCTAssertFalse(page.optionsButton.isHidden)
        XCTAssertEqual(page.titleLabel.frame, resting, "hover must not shrink the title")
        try assertTitleFits(page)
        assertControlsFit(page)
        page.setHeaderHovered(false)
      }
    }
  }

  func testRefreshingShortTitleAfterNarrowLayoutMeasuresFullText() throws {
    let source = StubSidebar()
    let space = source.addSpace(title: "A")
    let page = SpacePageView(source: source, spaceID: space)
    page.frame = NSRect(x: 0, y: 0, width: 80, height: 500)
    page.layout()
    source.renameSpace(space, to: "Space 2")
    page.refresh(from: source.space(space))
    page.frame.size.width = 240
    page.layout()
    try assertTitleFits(page)
    assertControlsFit(page)
  }

  func testLongTitleTruncatesOnlyAfterReservingBothHoverControls() throws {
    let source = StubSidebar()
    let space = source.addSpace(title: String(repeating: "Long Space title ", count: 10))
    let page = SpacePageView(source: source, spaceID: space)
    page.frame = NSRect(x: 0, y: 0, width: 200, height: 500)
    page.layout()
    page.setHeaderHovered(true)
    XCTAssertEqual(page.titleLabel.lineBreakMode, .byTruncatingTail)
    XCTAssertLessThan(page.titleLabel.frame.width, page.titleLabel.attributedStringValue.size().width)
    assertControlsFit(page)
    XCTAssertEqual(page.optionsButton.frame.maxX, page.bounds.width - SidebarMetrics.horizontalPadding)
  }

  private func assertTitleFits(_ page: SpacePageView, file: StaticString = #filePath, line: UInt = #line) throws {
    let cell = try XCTUnwrap(page.titleLabel.cell, file: file, line: line)
    let textWidth = ceil(page.titleLabel.attributedStringValue.size().width)
    let drawingWidth = cell.drawingRect(forBounds: page.titleLabel.bounds).width
    XCTAssertGreaterThanOrEqual(drawingWidth, textWidth, "the complete title fits inside the cell's text inset",
                               file: file, line: line)
    XCTAssertEqual(cell.expansionFrame(withFrame: page.titleLabel.bounds, in: page.titleLabel), .zero,
                   "AppKit must not need an expansion tooltip for the short title", file: file, line: line)
  }

  private func assertControlsFit(_ page: SpacePageView, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertGreaterThanOrEqual(page.editButton.frame.minX, page.titleLabel.frame.maxX, file: file, line: line)
    XCTAssertGreaterThanOrEqual(page.optionsButton.frame.minX, page.editButton.frame.maxX, file: file, line: line)
    XCTAssertLessThanOrEqual(page.optionsButton.frame.maxX, page.bounds.width - SidebarMetrics.horizontalPadding,
                            file: file, line: line)
  }
}
