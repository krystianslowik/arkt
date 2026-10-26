import Foundation
import Testing
@testable import ShellUI

/// #331: the sidebar width and hidden state store. Clamped on read, nil when nothing was ever saved.
@MainActor
struct SidebarWindowStateTests {
  private func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
    let name = "SidebarWindowStateTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { UserDefaults().removePersistentDomain(forName: name) }
    try body(defaults)
  }

  @Test func nothingSavedReadsAsNil() {
    withSuite { defaults in
      let store = SidebarWindowStateStore(defaults: defaults)
      #expect(store.state() == nil)
    }
  }

  @Test func savedValuesRoundTrip() {
    withSuite { defaults in
      let store = SidebarWindowStateStore(defaults: defaults)
      store.save(width: 260, isVisible: false)
      #expect(store.state() == SidebarWindowState(width: 260, isVisible: false))
      store.save(width: 300, isVisible: true)
      #expect(store.state() == SidebarWindowState(width: 300, isVisible: true))
    }
  }

  /// An out-of-range stored width is clamped when read (a hand-edited or stale value never reaches a window).
  @Test func anOutOfRangeWidthClampsOnRead() {
    withSuite { defaults in
      let store = SidebarWindowStateStore(defaults: defaults)
      let metrics = ShellMetrics.standard
      store.save(width: 5000, isVisible: true)
      #expect(store.state()?.width == Double(metrics.sidebarMaxWidth))
      store.save(width: 10, isVisible: true)
      #expect(store.state()?.width == Double(metrics.sidebarMinWidth))
    }
  }

  /// A width saved without a visible flag (an interrupted older write) reads as shown.
  @Test func aWidthWithoutAVisibleFlagReadsAsShown() {
    withSuite { defaults in
      defaults.set(220.0, forKey: SidebarWindowStateStore.widthDefaultsKey)
      let store = SidebarWindowStateStore(defaults: defaults)
      #expect(store.state() == SidebarWindowState(width: 220, isVisible: true))
    }
  }

  @Test func theEphemeralStoreNeverTouchesDefaults() {
    withSuite { defaults in
      let store = SidebarWindowStateStore.ephemeral()
      store.save(width: 260, isVisible: false)
      #expect(store.state() == nil)
      #expect(defaults.object(forKey: SidebarWindowStateStore.widthDefaultsKey) == nil)
    }
  }
}
