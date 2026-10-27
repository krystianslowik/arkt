import Foundation
import Testing
import EngineAPI
@testable import ShellUI

/// A site's permission request as the shell's dialog content (#400): the engine's strings, three equal answers, no
/// Return default, Escape closing it, and the 0.5 s input protection.
struct PermissionContentTests {
  private func request(kinds: [PermissionKind] = [.geolocation], oneTime: Bool = true) -> PermissionRequest {
    PermissionRequest(id: PermissionRequestID(), tab: TabID(), origin: "example.com", kinds: kinds,
                      title: "example.com wants to", items: kinds.map { "Wants \($0)" },
                      allowTitle: oneTime ? "Allow while visiting the site" : "Allow",
                      allowThisTimeTitle: oneTime ? "Allow this time" : nil, blockTitle: oneTime ? "Never allow" : "Block")
  }

  @Test func theTitleNamesTheOriginAndTheListNamesWhatItWants() {
    let content = DialogContent.permissionRequest(request(kinds: [.camera, .microphone]))
    #expect(content.title == "example.com wants to")
    #expect(content.listItems == ["Wants camera", "Wants microphone"])
    #expect(content.accessibilityDescription == "Wants camera Wants microphone")
    #expect(content.width == 320)
  }

  @Test func aOneVisitRequestStacksThreeNeutralAnswersWithTheEnginesTitles() {
    let content = DialogContent.permissionRequest(request())
    #expect(content.primaryTitle == "Allow while visiting the site")
    #expect(content.secondaryTitle == "Allow this time")
    #expect(content.cancelTitle == "Never allow")
    #expect(content.stackedButtons && content.neutralPrimary)
    #expect(!content.isDestructive)
  }

  @Test func aRequestWithoutAOneVisitGrantHasAllowAndBlock() {
    let content = DialogContent.permissionRequest(request(kinds: [.notifications], oneTime: false))
    #expect(content.primaryTitle == "Allow" && content.cancelTitle == "Block" && content.secondaryTitle == nil)
  }

  @Test func nothingIsTheReturnDefaultAndEscapeClosesWithoutAnAnswer() {
    let content = DialogContent.permissionRequest(request())
    #expect(content.defaultButton == .none)
    #expect(content.escapeDismisses)
  }

  @Test func inputIsProtectedForHalfASecond() {
    #expect(DialogContent.permissionRequest(request()).inputProtection == 0.5)
    #expect(DialogContent(title: "t", primaryTitle: "OK").inputProtection == 0, "other dialogs have none")
  }

  @Test func answersMapToTheEnginesChoices() {
    #expect(PermissionChoice(.primary) == .allow)
    #expect(PermissionChoice(.secondary) == .allowThisTime)
    #expect(PermissionChoice(.cancel) == .block)
  }
}
