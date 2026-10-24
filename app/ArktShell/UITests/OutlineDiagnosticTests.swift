import AppKit
import ApplicationServices
import XCTest

/// Temporary (#269): dumps how the sidebar outline and the command bar table reach the runner on this OS.
final class OutlineDiagnosticTests: ArktUITestCase {
  func test_Z_dumpOutlineTree() async throws {
    let server = try await fixtureServer()
    let app = try launch(try Sandbox())
    emit("os=\(ProcessInfo.processInfo.operatingSystemVersionString) trusted=\(AXIsProcessTrusted())")

    app.typeKey("t", modifierFlags: .command)
    let field = app.textFields[AXID.CommandBar.field]
    XCTAssertTrue(waitFor(field))
    field.typeText(server.page("alpha"))
    field.typeKey(.return, modifierFlags: [])

    let title = FixtureServer.title(ofPage: "alpha")
    quietWait { app.webViews.firstMatch.exists && app.webViews.firstMatch.label == title }
    let outline = app.outlines.firstMatch
    emit("outlines=\(app.outlines.count) outlineRows=\(app.outlineRows.count) cells=\(app.cells.count)")
    if outline.exists {
      emit("outline.children=\(outline.children(matching: .any).count)")
      snapshotLines(outline, "outline").forEach(emit)
    }
    rawAX(role: "AXOutline").forEach(emit)

    app.typeKey("t", modifierFlags: .command)
    quietWait { field.exists }
    field.typeText("Fixture")
    let results = app.tables[AXID.CommandBar.results]
    quietWait { results.exists && results.tableRows.count > 0 }
    emit("cmdbar.exists=\(results.exists) tableRows=\(results.tableRows.count) children=\(results.children(matching: .any).count)")
    emit("cmdbar.rowIds=\(results.tableRows.allElementsBoundByIndex.map(\.identifier))")
    if results.exists { snapshotLines(results, "cmdbar").forEach(emit) }
    rawAX(role: "AXTable").forEach(emit)
    XCTFail("DIAG done")
  }

  private func emit(_ line: String) { print("DIAG " + line) }

  /// Waits without recording a failure.
  private func quietWait(_ condition: @escaping @MainActor () -> Bool) {
    let predicate = NSPredicate { _, _ in MainActor.assumeIsolated { condition() } }
    _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: Waits.scaled(nil))
  }

  private func snapshotLines(_ element: XCUIElement, _ name: String) -> [String] {
    do {
      let snapshot = try element.snapshot()
      var lines = ["\(name).snapshot children=\(snapshot.children.count) dict=\(snapshot.dictionaryRepresentation)"]
      for child in snapshot.children.prefix(4) {
        lines.append("  child type=\(child.elementType.rawValue) id=\(child.identifier) label=\(child.label) kids=\(child.children.count)")
      }
      return lines
    } catch {
      return ["\(name).snapshot error=\(error)"]
    }
  }

  /// Direct AX from the runner (may fail in the runner's sandbox; the error codes are the point).
  private func rawAX(role wanted: String) -> [String] {
    guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.arkt.ArktShell").first else {
      return ["rawAX: no running app"]
    }
    let root = AXUIElementCreateApplication(running.processIdentifier)
    var lines: [String] = []
    var found: [AXUIElement] = []
    func value(_ e: AXUIElement, _ name: String) -> (CFTypeRef?, Int32) {
      var v: CFTypeRef?
      let err = AXUIElementCopyAttributeValue(e, name as CFString, &v)
      return (v, err.rawValue)
    }
    func walk(_ e: AXUIElement, _ depth: Int) {
      guard depth < 14, found.count < 3 else { return }
      if (value(e, kAXRoleAttribute).0 as? String) == wanted { found.append(e); return }
      for child in value(e, kAXChildrenAttribute).0 as? [AXUIElement] ?? [] { walk(child, depth + 1) }
    }
    let (windows, werr) = value(root, kAXWindowsAttribute)
    lines.append("rawAX windows err=\(werr) count=\((windows as? [AXUIElement])?.count ?? -1)")
    for window in windows as? [AXUIElement] ?? [] { walk(window, 0) }
    for element in found {
      var names: CFArray?
      let nerr = AXUIElementCopyAttributeNames(element, &names)
      lines.append("rawAX \(wanted) names err=\(nerr.rawValue) \((names as? [String]) ?? [])")
      for attribute in ["AXChildren", "AXRows", "AXVisibleRows", "AXChildrenInNavigationOrder", "AXVisibleChildren",
                        "AXIdentifier"] {
        let (v, err) = value(element, attribute)
        let count = (v as? [AXUIElement])?.count
        var n: CFIndex = -1
        let cerr = AXUIElementGetAttributeValueCount(element, attribute as CFString, &n)
        lines.append("  \(attribute) countAPI err=\(cerr.rawValue) n=\(n)")
        lines.append("  \(attribute) err=\(err) count=\(count.map(String.init) ?? "-") value=\(count == nil ? String(describing: v) : "")")
      }
      let children = (value(element, "AXRows").0 as? [AXUIElement] ?? []) + (value(element, "AXChildren").0 as? [AXUIElement] ?? [])
      for child in children.prefix(3) {
        let parentRole = value(child, kAXParentAttribute).0.map { value($0 as! AXUIElement, kAXRoleAttribute).0 as? String } ?? nil
        lines.append("  row role=\(value(child, kAXRoleAttribute).0 as? String ?? "?") id=\(value(child, "AXIdentifier").0 as? String ?? "") "
          + "desc=\(value(child, kAXDescriptionAttribute).0 as? String ?? "") parent=\(parentRole ?? "?") "
          + "kids=\((value(child, kAXChildrenAttribute).0 as? [AXUIElement])?.count ?? -1)")
      }
    }
    return lines
  }
}
