import AppKit
import CoreBridge
import SidebarModel
import XCTest
@testable import ShellUI

@MainActor
final class LinkRoutingRetryTests: XCTestCase {
  func testFailedSaveSurvivesReopeningAndSameChoiceRetries() async throws {
    _ = NSApplication.shared
    let route = LinkRouting.Route(condition: .contains("literal"), destination: .littleArkt)
    let store = RetryRoutingStore(initial: LinkRouting(routes: [route, route]))
    let model = LinkRoutingSettingsModel(state: store)
    let suite = "dev.arkt.tests.routing.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var services = SettingsServices()
    services.linkRoutingRows = model.settingsRows
    func open() -> SettingsWindowController {
      let controller = SettingsWindowController(settings: AppSettings(defaults: defaults), services: services)
      controller.show(pane: .spaces)
      return controller
    }
    func popup(_ controller: SettingsWindowController) -> SettingsPopUpButton? {
      func find(_ view: NSView) -> SettingsPopUpButton? {
        if view.accessibilityIdentifier() == AXID.Settings.control("spaces", "linksFromOtherApps") {
          return view as? SettingsPopUpButton
        }
        for child in view.subviews { if let found = find(child) { return found } }
        return nil
      }
      return controller.window?.contentView.flatMap(find)
    }
    func waitUntil(_ predicate: () -> Bool) async -> Bool {
      for _ in 0..<1_000 {
        if predicate() { return true }
        await Task.yield()
      }
      return predicate()
    }
    func choose(_ index: Int, on button: SettingsPopUpButton) {
      let item = NSMenuItem(title: button.items[index], action: nil, keyEquivalent: "")
      item.tag = index
      _ = button.perform(NSSelectorFromString("chose:"), with: item)
    }

    let first = open()
    let firstLoaded = await waitUntil { popup(first)?.items.contains("Most Recent Space") == true }
    XCTAssertTrue(firstLoaded)
    let firstPopup = try XCTUnwrap(popup(first))
    choose(1, on: firstPopup)
    let failed = await waitUntil { firstPopup.enclosingSettingsRow?.captionText.contains("Could not save") == true }
    XCTAssertTrue(failed)
    first.window?.close()

    let second = open()
    defer { second.window?.close() }
    let secondLoaded = await waitUntil { popup(second)?.selectedTitle == "Most Recent Space" }
    XCTAssertTrue(secondLoaded)
    let reopened = try XCTUnwrap(popup(second))
    XCTAssertTrue(try XCTUnwrap(reopened.enclosingSettingsRow).captionText.contains("Could not save"))
    choose(1, on: reopened)
    let retried = await waitUntil { model.lastError == nil }
    XCTAssertTrue(retried)
    XCTAssertFalse(try XCTUnwrap(reopened.enclosingSettingsRow).captionText.contains("Could not save"))
    let value = await store.value
    XCTAssertEqual(value, LinkRouting(routes: [route, route], defaultDestination: .mostRecentSpace))
  }
}

private actor RetryRoutingStore: LinkRoutingSettingsStoring {
  enum Failure: Error { case requested }
  private(set) var value: LinkRouting
  private var fail = true
  init(initial: LinkRouting) { value = initial }
  func loadLinkRouting() async throws -> LinkRouting { value }
  func updateLinkRouting(at date: Date, _ change: @escaping @Sendable (inout LinkRouting) -> Void) async throws -> LinkRouting {
    if fail { fail = false; throw Failure.requested }
    change(&value)
    return value
  }
}
