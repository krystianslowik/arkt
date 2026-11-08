import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Title events use the same window and sidebar path as loaded Favorites; URLs and titles are synthetic.
@MainActor
final class FavoriteUnreadIntegrationTests: XCTestCase {
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    let ids: [UUID]

    init() throws {
      var sidebar = SidebarModel.Sidebar()
      _ = sidebar.addSpace(title: "Space")
      ids = try ["x.com", "web.whatsapp.com", "mail.google.com"].map { host in
        try sidebar.addTab(url: URL(string: "https://\(host)/")!, title: "Saved",
                           in: .favorites(profile: "default"))
      }
      source = ModelSidebarSource(sidebar: sidebar, now: { Date(timeIntervalSinceReferenceDate: 800_000_000) })
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
    }

    func tile(_ id: UUID) throws -> FavoriteTileView {
      controller.sidebarController.view.favorites.collectionView.layoutSubtreeIfNeeded()
      return try XCTUnwrap(controller.sidebarController.view.favorites.tile(for: id))
    }

    @discardableResult
    func load(_ id: UUID, title: String) throws -> TabID {
      controller.activate(node: id)
      let tab = try XCTUnwrap(controller.engineTab(of: id))
      engine.finishLoad(tab, title: title)
      return tab
    }

    func badge(_ id: UUID) throws -> String? {
      let view = try tile(id).unreadBadgeView
      return view.isHidden ? nil : view.stringValue
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  func testLiveTitlesClearIncludingEmptyTitle() throws {
    let h = try Harness()
    defer { h.controller.close() }
    let id = h.ids[2]
    let tab = try h.load(id, title: "(1) Mail")
    XCTAssertEqual(try h.badge(id), "1")
    h.engine.setDocumentTitle(tab, "(125) Mail")
    XCTAssertEqual(try h.badge(id), "99+")
    h.engine.setDocumentTitle(tab, "Mail")
    XCTAssertNil(try h.badge(id))
    h.engine.setDocumentTitle(tab, "(0) Mail")
    XCTAssertNil(try h.badge(id))
    h.engine.setDocumentTitle(tab, "(3) Mail")
    h.engine.setDocumentTitle(tab, "")
    XCTAssertNil(try h.badge(id), "empty engine title must clear the badge even if the saved title is retained")
    XCTAssertEqual(try h.tile(id).accessibilityLabel(), "(3) Mail")
  }

  func testHandoffReplaysExistingTabTitles() throws {
    let h = try Harness()
    defer { h.controller.close() }
    let set = ShellWindowSet(engine: h.engine, sidebar: h.source, hostLookup: { [engine = h.engine] in engine.host(of: $0) })
    defer { for window in set.controllers { window.close() } }
    let first = set.openWindow(opensFirstTab: false)
    let second = set.openWindow(opensFirstTab: false)
    let id = h.ids[2]
    first.activate(node: id)
    let tab = try XCTUnwrap(first.engineTab(of: id))
    h.engine.finishLoad(tab, title: "(7) Mail")
    second.activate(node: id)
    XCTAssertEqual(second.engineTab(of: id), tab)
    second.sidebarController.view.favorites.collectionView.layoutSubtreeIfNeeded()
    let tile = try XCTUnwrap(second.sidebarController.view.favorites.tile(for: id))
    XCTAssertEqual(second.liveFavoriteTitle(for: id), "(7) Mail")
    XCTAssertEqual(tile.unreadBadgeView.stringValue, "7")
    XCTAssertFalse(tile.unreadBadgeView.isHidden)
    XCTAssertEqual(tile.accessibilityLabel(), "(7) Mail")
    h.engine.setDocumentTitle(tab, "")
    first.activate(node: id)
    XCTAssertEqual(first.engineTab(of: id), tab)
    first.sidebarController.view.favorites.collectionView.layoutSubtreeIfNeeded()
    let returned = try XCTUnwrap(first.sidebarController.view.favorites.tile(for: id))
    XCTAssertEqual(first.liveFavoriteTitle(for: id), "")
    XCTAssertTrue(returned.unreadBadgeView.isHidden)
    XCTAssertEqual(returned.accessibilityLabel(), "(7) Mail")
  }

  func testUnloadRemovalAndReuseClearBadge() throws {
    let h = try Harness()
    defer { h.controller.close() }
    let id = h.ids[2]
    _ = try h.load(id, title: "(8) Mail")
    let grid = h.controller.sidebarController.view.favorites
    XCTAssertEqual(try h.badge(id), "8")
    let item = try XCTUnwrap(grid.collectionView.item(at: IndexPath(item: 2, section: 0)) as? FavoriteTileItem)
    h.controller.close(node: id)
    XCTAssertNil(try h.badge(id))
    _ = try h.load(id, title: "(8) Mail")
    XCTAssertEqual(try h.badge(id), "8")
    item.prepareForReuse()
    grid.configure(item, for: h.ids[0]) // the same reusable item now represents a different node
    XCTAssertEqual(item.tileView.nodeID, h.ids[0])
    XCTAssertTrue(item.tileView.unreadBadgeView.isHidden)
    h.source.mutate { $0.remove(id) }
    XCTAssertNil(grid.tile(for: id))
    XCTAssertNil(try h.badge(h.ids[0]))
  }

  func testSettingsRefreshUnchangedTitlesIndependentlyInSharedWindows() throws {
    let h = try Harness()
    defer { h.controller.close() }
    let settings = AppSettings.ephemeral()
    let set = ShellWindowSet(engine: h.engine, sidebar: h.source, hostLookup: { [engine = h.engine] in engine.host(of: $0) })
    defer { for window in set.controllers { window.close() } }
    settings.favoriteBadges = .init(twitterBadgeEnabled: true, whatsAppBadgeEnabled: true)
    set.bindFavoriteBadgeSettings(settings)
    let first = set.openWindow(opensFirstTab: false)
    let other = set.openWindow(opensFirstTab: false)
    first.activate(node: h.ids[0])
    let firstX = try XCTUnwrap(first.engineTab(of: h.ids[0]))
    h.engine.finishLoad(firstX, title: "(2) X")
    first.activate(node: h.ids[1])
    let firstChat = try XCTUnwrap(first.engineTab(of: h.ids[1]))
    h.engine.finishLoad(firstChat, title: "(4) Chat")
    func firstBadge(_ id: UUID) throws -> String? {
      first.sidebarController.view.favorites.collectionView.layoutSubtreeIfNeeded()
      let tile = try XCTUnwrap(first.sidebarController.view.favorites.tile(for: id))
      return tile.unreadBadgeView.isHidden ? nil : tile.unreadBadgeView.stringValue
    }
    // Handoff keeps each live page in one window; leave X in the first and Chat in the second.
    other.activate(node: h.ids[1])
    XCTAssertEqual(other.engineTab(of: h.ids[1]), firstChat)
    func otherBadge(_ id: UUID) throws -> String? {
      other.sidebarController.view.favorites.collectionView.layoutSubtreeIfNeeded()
      let tile = try XCTUnwrap(other.sidebarController.view.favorites.tile(for: id))
      return tile.unreadBadgeView.isHidden ? nil : tile.unreadBadgeView.stringValue
    }
    XCTAssertEqual(try firstBadge(h.ids[0]), "2")
    XCTAssertEqual(try otherBadge(h.ids[1]), "4")
    settings.favoriteBadges = .init(twitterBadgeEnabled: false, whatsAppBadgeEnabled: false)
    XCTAssertNil(try firstBadge(h.ids[0]))
    XCTAssertNil(try otherBadge(h.ids[1]))
    settings.favoriteBadges = .init(twitterBadgeEnabled: true, whatsAppBadgeEnabled: false)
    XCTAssertEqual(try firstBadge(h.ids[0]), "2")
    XCTAssertNil(try otherBadge(h.ids[1]))
    settings.favoriteBadges = .init(twitterBadgeEnabled: true, whatsAppBadgeEnabled: true)
    XCTAssertEqual(try otherBadge(h.ids[1]), "4")
  }

  func testAccessibilityAndHoverCloseSurviveTargetedTitleAndFaviconUpdates() async throws {
    let h = try Harness()
    defer { h.controller.close() }
    let id = h.ids[2]
    let tab = try h.load(id, title: "Mail")
    let tile = try h.tile(id)
    let unrelated = try h.tile(h.ids[0])
    unrelated.isHovered = true
    unrelated.selectionAlpha = 0.37
    tile.isHovered = true
    var notifications: [NSAccessibility.Notification] = []
    tile.postedNotificationsForTesting = { notifications.append($0) }
    h.engine.setDocumentTitle(tab, "(2) Mail")
    let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0))
    for y in 0..<8 { for x in 0..<8 { bitmap.setColor(.systemRed, atX: x, y: y) } }
    let favicon = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    h.engine.finishLoad(tab, title: "(2) Mail", favicon: favicon)
    await h.controller.sidebarController.settleFaviconDecodes()
    let updated = try h.tile(id)
    XCTAssertTrue(try h.tile(h.ids[0]) === unrelated)
    XCTAssertTrue(unrelated.isHovered)
    XCTAssertEqual(unrelated.selectionAlpha, 0.37)
    XCTAssertEqual(updated.faviconView.image?.size, NSSize(width: 8, height: 8))
    XCTAssertEqual(updated.accessibilityLabel(), "(2) Mail")
    XCTAssertEqual(updated.accessibilityValue() as? String, AXID.Favorites.loaded)
    XCTAssertTrue(updated.accessibilityValueDescription()?.contains("2") == true)
    XCTAssertTrue(updated.isAccessibilitySelected())
    XCTAssertEqual(updated.accessibilityCustomActions()?.count, 1)
    XCTAssertTrue(notifications.contains(.valueChanged))
    XCTAssertTrue(updated.isCloseButtonShown)
    let button = updated.closeButton
    let content = try XCTUnwrap(button.window?.contentView)
    let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
    XCTAssertTrue(content.hitTest(content.superview?.convert(center, from: nil) ?? center) === button)
    var presented = false
    h.controller.sidebarController.view.favorites.presentAccessibilityMenu = { _, menuTile in
      presented = menuTile === updated
    }
    XCTAssertTrue(updated.accessibilityPerformShowMenu())
    XCTAssertTrue(presented)
    h.controller.activate(node: h.ids[0])
    XCTAssertTrue(updated.accessibilityPerformPress())
    XCTAssertEqual(h.controller.currentTab, tab)
    notifications.removeAll()
    h.engine.setDocumentTitle(tab, "Mail")
    XCTAssertFalse(try XCTUnwrap(h.tile(id).accessibilityValueDescription()).contains("2"))
    XCTAssertTrue(notifications.contains(.valueChanged))
    XCTAssertEqual(try h.tile(id).accessibilityCustomActions()?.count, 1)
    button.performClick(nil)
    XCTAssertNil(h.controller.engineTab(of: id))
    _ = try h.load(id, title: "(2) Mail")
    let action = try XCTUnwrap(try h.tile(id).accessibilityCustomActions()?.first)
    XCTAssertTrue(action.handler?() ?? false)
    XCTAssertNil(h.controller.engineTab(of: id))
  }

  func testBadgeBoundsAtSupportedSizesAndFlavors() throws {
    let h = try Harness()
    defer { h.controller.close() }
    let id = h.ids[2]
    let tab = try h.load(id, title: "(1) Mail")
    let tile = try h.tile(id)
    for flavor in [ThemeFlavor.light, .dark] {
      tile.flavor = flavor
      for width in [FavoritesLayout.minimumTileWidth, CGFloat(100)] {
        tile.frame.size = NSSize(width: width, height: FavoritesLayout.tileHeight)
        for (title, expected) in [("(0) Mail", ""), ("(1) Mail", "1"), ("(100) Mail", "99+")] {
          h.engine.setDocumentTitle(tab, title)
          tile.layoutSubtreeIfNeeded()
          let badge = tile.unreadBadgeView
          if expected.isEmpty { XCTAssertTrue(badge.isHidden); continue }
          XCTAssertFalse(badge.isHidden)
          XCTAssertEqual(badge.stringValue, expected)
          XCTAssertTrue(badge.frame.width.isFinite && badge.frame.height.isFinite)
          XCTAssertGreaterThan(badge.frame.width, 0)
          XCTAssertGreaterThan(badge.frame.height, 0)
          XCTAssertTrue(badge.intrinsicContentSize.width.isFinite && badge.intrinsicContentSize.height.isFinite)
          XCTAssertGreaterThan(badge.intrinsicContentSize.width, 0)
          XCTAssertGreaterThan(badge.intrinsicContentSize.height, 0)
          XCTAssertTrue(tile.bounds.contains(badge.frame))
          XCTAssertGreaterThanOrEqual(badge.bounds.width, badge.intrinsicContentSize.width)
          XCTAssertGreaterThanOrEqual(badge.bounds.height, badge.intrinsicContentSize.height)
        }
      }
    }
  }
}
