import AppKit
import CoreBridge
import SidebarModel
import XCTest
@testable import ShellUI

/// Proposed control identifiers for the Settings form, exercised through the shared editor adapter.
@MainActor
final class LinkRoutingFormTests: XCTestCase {
  private let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  private let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  private let missing = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

  private func find<T: NSView>(_ id: String, in window: NSWindow, as: T.Type) throws -> T {
    func search(_ view: NSView) -> NSView? {
      if view.accessibilityIdentifier() == id { return view }
      for child in view.subviews { if let found = search(child) { return found } }
      return nil
    }
    return try XCTUnwrap(window.contentView.flatMap(search) as? T, "Missing control \(id)")
  }

  private func waitUntil(_ predicate: () -> Bool) async -> Bool {
    for _ in 0..<1_000 {
      if predicate() { return true }
      await Task.yield()
    }
    return predicate()
  }

  private func choose(_ index: Int, _ popup: SettingsPopUpButton) throws {
    guard popup.items.indices.contains(index) else {
      XCTFail("Missing popup item at index \(index)")
      throw FormTestError.missingChoice
    }
    let item = NSMenuItem(title: popup.items[index], action: nil, keyEquivalent: "")
    item.tag = index
    _ = popup.perform(NSSelectorFromString("chose:"), with: item)
  }

  private func withWindow(initial: LinkRouting, failFirst: Bool = false,
                          _ body: (NSWindow, LinkRoutingSettingsModel, FormRoutingStore) async throws -> Void) async throws {
    _ = NSApplication.shared
    let store = FormRoutingStore(initial: initial, failFirst: failFirst)
    let model = LinkRoutingSettingsModel(state: store)
    await model.load()
    let suite = "dev.arkt.tests.routingForm.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var services = SettingsServices()
    services.linkRoutingRows = model.settingsRows
    services.spaces = { [self] in
      [first, second].map { SettingsSpaceSummary(id: $0, title: "Shared", profile: "default",
                                                   gradient: [], icon: nil, pinned: 0, today: 0) }
    }
    let controller = SettingsWindowController(settings: AppSettings(defaults: defaults), services: services)
    controller.show(pane: .spaces)
    defer {
      if let window = controller.window, let sheet = window.attachedSheet { window.endSheet(sheet) }
      controller.window?.close()
    }
    let window = try XCTUnwrap(controller.window)
    let loaded = await waitUntil {
      (try? self.find(AXID.Settings.control("spaces", "linksFromOtherApps"),
                      in: window, as: SettingsPopUpButton.self))?.items.contains("Most Recent Space") == true
    }
    guard loaded else { XCTFail("Routing controls did not load"); throw FormTestError.notLoaded }
    try await body(window, model, store)
  }

  private func openAdd(_ window: NSWindow) throws -> NSWindow {
    let add = try find(AXID.Settings.control("spaces", "addRoute"), in: window, as: NSButton.self)
    XCTAssertTrue(add.isEnabled, "Add Route must be available after routing loads")
    add.performClick(nil)
    return try XCTUnwrap(window.attachedSheet)
  }

  func testCancelAndEscapeLeaveRoutesUnchanged() async throws {
    let original = LinkRouting.Route(condition: .contains("  Mixed/路径  "), destination: .space(missing))
    let initial = LinkRouting(routes: [original, original])
    try await withWindow(initial: initial) { window, model, store in
      let sheet = try openAdd(window)
      let field = try find("settings.route.literal", in: sheet, as: NSTextField.self)
      XCTAssertFalse((field.accessibilityLabel() ?? "").isEmpty)
      XCTAssertTrue(sheet.firstResponder === field || (field.currentEditor().map { sheet.firstResponder === $0 } ?? false))
      field.stringValue = "discarded"
      try find("settings.route.cancel", in: sheet, as: NSButton.self).performClick(nil)
      XCTAssertNil(window.attachedSheet)
      let afterCancel = await store.snapshot()
      XCTAssertEqual(model.settings, initial)
      XCTAssertEqual(afterCancel, initial)

      let next = try openAdd(window)
      try find("settings.route.literal", in: next, as: NSTextField.self).stringValue = "discarded too"
      next.cancelOperation(nil)
      XCTAssertNil(window.attachedSheet)
      let afterEscape = await store.snapshot()
      XCTAssertEqual(model.settings, initial)
      XCTAssertEqual(afterEscape, initial)
    }
  }

  func testEditSecondDuplicateRetainsUnavailableSpaceAndRetriesFailedSave() async throws {
    let original = LinkRouting.Route(condition: .contains("  Mixed/路径  "), destination: .space(missing))
    let initial = LinkRouting(routes: [original, original])
    try await withWindow(initial: initial, failFirst: true) { window, model, store in
      let edit = try find("settings.spaces.route.1.edit", in: window, as: NSButton.self)
      edit.performClick(nil)
      var sheet = try XCTUnwrap(window.attachedSheet)
      let field = try find("settings.route.literal", in: sheet, as: NSTextField.self)
      XCTAssertEqual(field.stringValue, "  Mixed/路径  ")
      let destination = try find("settings.route.destination", in: sheet, as: SettingsPopUpButton.self)
      XCTAssertEqual(destination.selectedTitle, "Unavailable Space")
      let literal = String(repeating: "Long/路径 ", count: 120) + "  "
      field.stringValue = literal
      try choose(1, find("settings.route.condition", in: sheet, as: SettingsPopUpButton.self))
      try find("settings.route.save", in: sheet, as: NSButton.self).performClick(nil)
      let edited = LinkRouting.Route(condition: .matches(literal), destination: .space(missing))
      let failed = await waitUntil { model.lastError != nil }
      XCTAssertTrue(failed)
      let afterFailure = await store.snapshot()
      XCTAssertEqual(model.settings.routes, [original, edited])
      XCTAssertEqual(afterFailure, initial)
      // The failure must be visible in the window, not just retained in the model.
      let error = try find("settings.route.saveError", in: window, as: NSView.self)
      XCTAssertFalse((error.accessibilityLabel() ?? "").isEmpty)

      let retry = try find("settings.spaces.route.1.edit", in: window, as: NSButton.self)
      retry.performClick(nil)
      sheet = try XCTUnwrap(window.attachedSheet)
      XCTAssertEqual(try find("settings.route.literal", in: sheet, as: NSTextField.self).stringValue, literal)
      try find("settings.route.save", in: sheet, as: NSButton.self).performClick(nil)
      let saved = await waitUntil { model.lastError == nil && !model.needsFlush }
      XCTAssertTrue(saved)
      let afterRetry = await store.snapshot()
      XCTAssertEqual(afterRetry.routes, [original, edited])
    }
  }

  func testAddAppendsLiteralAndSelectsSecondSpaceWithDuplicateTitle() async throws {
    let original = LinkRouting.Route(condition: .matches("Existing"), destination: .littleArkt)
    let initial = LinkRouting(routes: [original, original])
    try await withWindow(initial: initial) { window, model, store in
      let sheet = try openAdd(window)
      try find("settings.route.literal", in: sheet, as: NSTextField.self).stringValue = "  Mixed/路径  "
      let condition = try find("settings.route.condition", in: sheet, as: SettingsPopUpButton.self)
      let destination = try find("settings.route.destination", in: sheet, as: SettingsPopUpButton.self)
      XCTAssertFalse((condition.accessibilityLabel() ?? "").isEmpty)
      XCTAssertFalse((destination.accessibilityLabel() ?? "").isEmpty)
      try choose(0, condition) // contains
      XCTAssertEqual(destination.items.filter { $0 == "Shared" }.count, 2)
      let shared = destination.items.indices.filter { destination.items[$0] == "Shared" }
      let secondShared = try XCTUnwrap(shared.last)
      try choose(secondShared, destination)
      try find("settings.route.save", in: sheet, as: NSButton.self).performClick(nil)
      let appended = LinkRouting.Route(condition: .contains("  Mixed/路径  "), destination: .space(second))
      let saved = await waitUntil { model.settings.routes == [original, original, appended] && !model.needsFlush }
      XCTAssertTrue(saved)
      let snapshot = await store.snapshot()
      XCTAssertEqual(snapshot.routes, [original, original, appended])
    }
  }
}

private enum FormTestError: Error { case missingChoice, notLoaded }

private actor FormRoutingStore: LinkRoutingSettingsStoring {
  enum Failure: Error { case requested }
  private var value: LinkRouting
  private var fail: Bool
  init(initial: LinkRouting, failFirst: Bool) { value = initial; fail = failFirst }
  func snapshot() -> LinkRouting { value }
  func loadLinkRouting() async throws -> LinkRouting { value }
  func updateLinkRouting(at date: Date, _ change: @escaping @Sendable (inout LinkRouting) -> Void) async throws -> LinkRouting {
    if fail { fail = false; throw Failure.requested }
    change(&value)
    return value
  }
}
