import AppKit
import EngineAPI
import Testing
@testable import ShellUI

/// The Extensions panel's content as data (design/extensions, direction C): the Pinned and Not pinned groups, the
/// panel's state, each row's status line, the keyboard moves and the drag's drop place.
@MainActor
struct ExtensionsPanelModelTests {
  private func action(_ id: String, pinned: Bool = false, enabled: Bool = true,
                      access: ExtensionSiteAccess = .onThisSite) -> ExtensionAction {
    ExtensionAction(id: id, name: id.uppercased(), isEnabled: enabled, isPinned: pinned, siteAccess: access)
  }

  @Test func `no actions is the empty state`() {
    let model = ExtensionsPanelModel(actions: [])
    #expect(model.state == .empty)
    #expect(model.pinned.isEmpty && model.unpinned.isEmpty)
  }

  @Test func `actions without a pin show the hint state`() {
    let model = ExtensionsPanelModel(actions: [action("a"), action("b")])
    #expect(model.state == .nonePinned)
    #expect(model.unpinned.map(\.id) == ["a", "b"])
  }

  @Test func `pinned actions keep the engine's order and come first`() {
    let model = ExtensionsPanelModel(actions: [action("c", pinned: true), action("a", pinned: true), action("b")])
    #expect(model.state == .list)
    #expect(model.pinned.map(\.id) == ["c", "a"])
    #expect(model.unpinned.map(\.id) == ["b"])
  }

  @Test func `thirty extensions all appear once`() {
    let actions = (0..<30).map { action("x\($0)", pinned: $0 < 12) }
    let model = ExtensionsPanelModel(actions: actions)
    #expect(model.pinned.count == 12 && model.unpinned.count == 18)
    #expect(Set((model.pinned + model.unpinned).map(\.id)).count == 30)
  }

  @Test(arguments: [
    (ExtensionSiteAccess.onThisSite, true, "Can read this site", false),
    (.onAllSites, true, "Can read this site", false),
    (.onClick, true, "Needs access to this site", true),
    (.noSiteAccess, true, "Doesn't need site access", false),
    (.onThisSite, false, "Not available on this page", false),
  ])
  func `the status line follows site access and the enabled state`(
    access: ExtensionSiteAccess, enabled: Bool, text: String, attention: Bool
  ) {
    let status = ExtensionsPanelModel.status(of: action("a", enabled: enabled, access: access))
    #expect(status.text == text)
    #expect(status.needsAttention == attention)
  }

  @Test func `move left and right step one place and stop at the ends`() {
    let model = ExtensionsPanelModel(actions: [action("a", pinned: true), action("b", pinned: true),
                                               action("c", pinned: true), action("d")])
    #expect(model.moveTarget(of: "a", by: -1) == nil)
    #expect(model.moveTarget(of: "a", by: 1) == 1)
    #expect(model.moveTarget(of: "b", by: -1) == 0)
    #expect(model.moveTarget(of: "c", by: 1) == nil)
    #expect(model.moveTarget(of: "d", by: -1) == nil, "an unpinned extension has no place to move")
    #expect(model.moveTarget(of: "zzz", by: 1) == nil)
  }

  @Test func `the drop gap follows the pointer against the rows' middles`() {
    // Rows 44 pt high from y 0 (flipped): middles at 22, 66, 110.
    let middles: [CGFloat] = [22, 66, 110]
    #expect(ExtensionsPanelModel.insertionGap(pointerY: -30, rowMiddles: middles) == 0)
    #expect(ExtensionsPanelModel.insertionGap(pointerY: 21, rowMiddles: middles) == 0)
    #expect(ExtensionsPanelModel.insertionGap(pointerY: 23, rowMiddles: middles) == 1)
    #expect(ExtensionsPanelModel.insertionGap(pointerY: 100, rowMiddles: middles) == 2)
    #expect(ExtensionsPanelModel.insertionGap(pointerY: 500, rowMiddles: middles) == 3)
  }

  @Test func `a gap next to the dragged row is no move`() {
    #expect(ExtensionsPanelModel.dropIndex(from: 1, gap: 1) == nil)
    #expect(ExtensionsPanelModel.dropIndex(from: 1, gap: 2) == nil)
    #expect(ExtensionsPanelModel.dropIndex(from: 1, gap: 0) == 0)
    #expect(ExtensionsPanelModel.dropIndex(from: 1, gap: 3) == 2)
    #expect(ExtensionsPanelModel.dropIndex(from: 0, gap: 4) == 3)
  }

  @Test func `the panel's height is its content until the window caps it`() {
    #expect(ExtensionsPanelModel.panelHeight(content: 300, available: 600) == .init(height: 300, scrolls: false))
    #expect(ExtensionsPanelModel.panelHeight(content: 900, available: 600) == .init(height: 600, scrolls: true))
    // Never below the footer and one row, even in the smallest window.
    let tiny = ExtensionsPanelModel.panelHeight(content: 900, available: 40)
    #expect(tiny.height == ExtensionsPanelMetrics.minimumHeight && tiny.scrolls)
  }

  @Test func `the panel narrows to the window`() {
    #expect(ExtensionsPanelModel.panelWidth(windowWidth: 1200) == 316)
    #expect(ExtensionsPanelModel.panelWidth(windowWidth: 640) == 316)
    #expect(ExtensionsPanelModel.panelWidth(windowWidth: 300) == 284)
  }
}
