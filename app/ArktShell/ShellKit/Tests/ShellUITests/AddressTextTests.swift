import CoreGraphics
import Foundation
import Testing
@testable import ShellUI

struct AddressTextTests {
  @Test func hostDropsSchemePathAndWWW() {
    #expect(AddressText.host(URL(string: "https://www.example.com/a/b?q=1#f")) == "example.com")
    #expect(AddressText.host(URL(string: "https://docs.example.org:8443/x")) == "docs.example.org")
    #expect(AddressText.host(URL(string: "http://WWW.Example.COM")) == "example.com")
  }

  @Test func hostKeepsWWWLikeLabelsThatAreNotThePrefix() {
    #expect(AddressText.host(URL(string: "https://www2.example.com")) == "www2.example.com")
    #expect(AddressText.host(URL(string: "https://wwwexample.com")) == "wwwexample.com")
  }

  @Test func hostWithoutURLIsEmpty() {
    #expect(AddressText.host(nil) == "")
  }

  @Test func fileURLShowsTheFileName() {
    #expect(AddressText.host(URL(fileURLWithPath: "/tmp/pages/page.html")) == "page.html")
  }

  @Test func hostlessURLFallsBackToTheWholeString() {
    #expect(AddressText.host(URL(string: "about:blank")) == "about:blank")
  }

  @Test func fullIsTheAbsoluteString() {
    #expect(AddressText.full(URL(string: "https://www.example.com/a?q=1")) == "https://www.example.com/a?q=1")
    #expect(AddressText.full(nil) == "")
  }
}

struct CardToolbarLayoutTests {
  // ContentCardView is not flipped: the toolbar sits at the top, so at the highest y.
  let bounds = CGRect(x: 0, y: 0, width: 1000, height: 781)

  @Test func visibleToolbarTakesTheTopStrip() {
    let layout = CardToolbarLayout.compute(bounds: bounds, toolbarVisible: true, toolbarHeight: 40)
    #expect(layout.toolbarFrame == CGRect(x: 0, y: 741, width: 1000, height: 40))
    #expect(layout.contentFrame == CGRect(x: 0, y: 0, width: 1000, height: 741))
  }

  @Test func hiddenToolbarLeavesTheWholeCardToTheContent() {
    let layout = CardToolbarLayout.compute(bounds: bounds, toolbarVisible: false, toolbarHeight: 40)
    #expect(layout.toolbarFrame == .zero)
    #expect(layout.contentFrame == bounds)
  }

  @Test func shortCardNeverGivesNegativeHeights() {
    let tiny = CGRect(x: 0, y: 0, width: 300, height: 20)
    let layout = CardToolbarLayout.compute(bounds: tiny, toolbarVisible: true, toolbarHeight: 40)
    #expect(layout.toolbarFrame.height == 20)
    #expect(layout.contentFrame.height == 0)
  }
}

@MainActor
struct ToolbarSettingTests {
  private func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
    let name = "dev.arkt.tests.toolbar.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    try body(defaults)
  }

  @Test func usesArcsKeyName() {
    #expect(ToolbarSetting.defaultsKey == "topBarURLEnabled")
  }

  @Test func hiddenByDefault() {
    withSuite { defaults in
      #expect(ToolbarSetting(defaults: defaults).isVisible == false)
    }
  }

  @Test func persistsAcrossInstances() {
    withSuite { defaults in
      let first = ToolbarSetting(defaults: defaults)
      first.isVisible = true
      #expect(defaults.bool(forKey: ToolbarSetting.defaultsKey))
      #expect(ToolbarSetting(defaults: defaults).isVisible)
      first.isVisible = false
      #expect(ToolbarSetting(defaults: defaults).isVisible == false)
    }
  }

  @Test func ephemeralSettingKeepsItsValueInMemoryOnly() {
    let setting = ToolbarSetting.ephemeral()
    setting.isVisible = true
    #expect(setting.isVisible)
    #expect(ToolbarSetting.ephemeral().isVisible == false)
  }

  @Test func observersHearEachChangeUntilTheyGo() {
    final class Counter: ToolbarSettingObserver {
      var count = 0
      func toolbarSettingDidChange(_ setting: ToolbarSetting) { count += 1 }
    }
    let setting = ToolbarSetting.ephemeral()
    let kept = Counter()
    var dropped: Counter? = Counter()
    weak let droppedRef = dropped
    setting.addObserver(kept)
    setting.addObserver(dropped!)
    setting.addObserver(kept)                                  // added twice, told once
    setting.isVisible = true
    setting.isVisible = true                                   // no change, no call
    #expect(kept.count == 1 && dropped?.count == 1)
    dropped = nil
    #expect(droppedRef == nil, "the setting holds observers weakly")
    setting.isVisible = false
    #expect(kept.count == 2)
  }

  @Test func menuTitleFollowsTheState() {
    #expect(ToolbarSetting.menuTitle(isVisible: false) == "Show Toolbar")
    #expect(ToolbarSetting.menuTitle(isVisible: true) == "Hide Toolbar")
  }
}
