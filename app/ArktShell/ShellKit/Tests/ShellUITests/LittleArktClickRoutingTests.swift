import EngineAPI
import Foundation
import Testing
@testable import ShellUI

/// Opt-Cmd-click into Little Arkt (#356, BH-132, GS-028): exactly Option and Command, and only while the setting is
/// on (on by default).
struct LittleArktClickRoutingTests {
  private let url = URL(string: "https://example.org/linked")!

  private func link(_ modifiers: EngineLinkModifiers,
                    _ disposition: EngineDisposition = .newBackgroundTab) -> EngineLinkActivation {
    EngineLinkActivation(url: url, sourceTab: TabID(), sourceURL: nil, modifiers: modifiers, disposition: disposition)
  }

  @Test func optionCommandOpensInLittleArktWhileTheSettingIsOn() {
    #expect(LittleArktRouting.opensInLittleArkt(link([.command, .option]), enabled: true))
    #expect(!LittleArktRouting.opensInLittleArkt(link([.command, .option]), enabled: false))
  }

  @Test func otherModifiersDoNot() {
    #expect(!LittleArktRouting.opensInLittleArkt(link([]), enabled: true))
    #expect(!LittleArktRouting.opensInLittleArkt(link([.command]), enabled: true))
    #expect(!LittleArktRouting.opensInLittleArkt(link([.option]), enabled: true))
    #expect(!LittleArktRouting.opensInLittleArkt(link([.command, .option, .shift]), enabled: true))
    #expect(!LittleArktRouting.opensInLittleArkt(link([.command, .option, .control]), enabled: true))
  }

  @Test func theSidebarClickNeedsExactlyOptionAndCommand() {
    #expect(LittleArktRouting.isLittleArktClick([.command, .option]))
    #expect(!LittleArktRouting.isLittleArktClick([.command]))
    #expect(!LittleArktRouting.isLittleArktClick([.command, .option, .shift]))
  }

  @MainActor @Test func theSettingIsOnByDefault() {
    let settings = AppSettings.ephemeral()
    #expect(settings.opensLittleArktOnOptionCommandClick)
    settings.opensLittleArktOnOptionCommandClick = false
    #expect(!settings.opensLittleArktOnOptionCommandClick)
  }

  @Test func theDockMenuCopy() {
    #expect(LittleArktCopy.hideAll == "Hide All Little Arkt Windows")
    #expect(LittleArktCopy.showAll == "Show All Little Arkt Windows")
    #expect(LittleArktCopy.closeAll == "Close Little Arkt Windows")
    #expect(LittleArktCopy.optionCommandClickSetting == "Open Little Arkt when clicking on links with \u{2325}\u{2318} held")
  }

  @Test func aMenuRowNamesThePageThenTheHost() {
    #expect(LittleArktCopy.menuTitle(pageTitle: "Three days in Lisbon", host: "atlas.example") == "Three days in Lisbon")
    #expect(LittleArktCopy.menuTitle(pageTitle: "  ", host: "atlas.example") == "atlas.example")
    #expect(LittleArktCopy.menuTitle(pageTitle: "", host: "") == "Little Arkt")
    let long = String(repeating: "a", count: 200)
    let title = LittleArktCopy.menuTitle(pageTitle: long, host: "")
    #expect(title.count == 60)
    #expect(title.hasSuffix("\u{2026}"))
  }
}
