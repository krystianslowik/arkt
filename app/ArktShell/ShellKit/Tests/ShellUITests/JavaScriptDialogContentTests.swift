import Foundation
import Testing
import EngineAPI
@testable import ShellUI

/// A page's dialog as the shell's dialog content (#400): the engine's strings, OK as the default, Escape answering the
/// only decline there is, and what each answer returns to the page.
struct JavaScriptDialogContentTests {
  private func dialog(_ kind: JavaScriptDialog.Kind, message: String = "Message", text: String? = nil) -> JavaScriptDialog {
    JavaScriptDialog(id: DialogID(), tab: TabID(), kind: kind, title: "example.com says", message: message,
                     defaultPromptText: text, acceptTitle: "OK", cancelTitle: kind == .alert ? nil : "Cancel")
  }

  @Test func alertShowsOnlyOK() {
    let content = DialogContent.javaScriptDialog(dialog(.alert))
    #expect(content.title == "example.com says")
    #expect(content.paragraphs == [.init("Message")])
    #expect(content.primaryTitle == "OK")
    #expect(content.cancelTitle == nil)
    #expect(content.defaultButton == .primary)
    #expect(content.input == nil)
    #expect(content.escapeAnswersCancel)
  }

  @Test func confirmShowsOKAndCancelWithTheEnginesTitles() {
    let source = JavaScriptDialog(id: DialogID(), tab: TabID(), kind: .confirm, title: "t", message: "m",
                                  defaultPromptText: nil, acceptTitle: "Weiter", cancelTitle: "Abbrechen")
    let content = DialogContent.javaScriptDialog(source)
    #expect(content.primaryTitle == "Weiter")
    #expect(content.cancelTitle == "Abbrechen")
    #expect(!content.isDestructive)
  }

  @Test func promptHasAFieldHoldingTheDefaultText() {
    let content = DialogContent.javaScriptDialog(dialog(.prompt, text: "Ada"))
    #expect(content.input == .init(text: "Ada", accessibilityLabel: "Response"))
    #expect(DialogContent.javaScriptDialog(dialog(.prompt, text: "")).input?.text == "")
  }

  @Test func anEmptyMessageHasNoBodyAndALongOneScrolls() {
    #expect(DialogContent.javaScriptDialog(dialog(.alert, message: "")).paragraphs.isEmpty)
    #expect(DialogContent.javaScriptDialog(dialog(.alert)).bodyMaxHeight == 240)
  }

  @Test func answersMapToWhatThePageReturns() {
    let alert = dialog(.alert), confirm = dialog(.confirm), prompt = dialog(.prompt, text: "x")
    // An alert only has OK, so Escape (cancel) accepts too.
    #expect(alert.response(for: .primary, input: nil) == (true, nil))
    #expect(alert.response(for: .cancel, input: nil) == (true, nil))
    #expect(confirm.response(for: .primary, input: nil) == (true, nil))
    #expect(confirm.response(for: .cancel, input: nil) == (false, nil))
    #expect(prompt.response(for: .primary, input: "Grace") == (true, "Grace"))
    #expect(prompt.response(for: .cancel, input: "Grace") == (false, nil))
  }

  // MARK: Leave site (#584)

  private func leaveSite() -> JavaScriptDialog {
    JavaScriptDialog(id: DialogID(), tab: TabID(), kind: .beforeUnload, title: "Leave site?",
                     message: "Changes you made may not be saved.", defaultPromptText: nil, acceptTitle: "Leave",
                     cancelTitle: "Stay")
  }

  @Test func leaveSiteMakesStayThePrimaryAndLeaveTheNeutralAnswer() {
    let content = DialogContent.javaScriptDialog(leaveSite())
    #expect(content.title == "Leave site?")
    #expect(content.paragraphs == [.init("Changes you made may not be saved.")])
    #expect(content.primaryTitle == "Stay")
    #expect(content.secondaryTitle == "Leave")
    #expect(content.cancelTitle == nil)
    #expect(content.defaultButton == .primary)
    #expect(!content.isDestructive)
    #expect(!content.neutralPrimary)
    #expect(content.input == nil)
    #expect(content.escapeAnswersCancel)
    #expect(!content.escapeDismisses)
    #expect(content.inputProtection == DialogContent.leaveSiteInputProtection)
    #expect(DialogContent.leaveSiteInputProtection > 0 && DialogContent.leaveSiteInputProtection < 0.5)
  }

  @Test func onlyTheLeaveSitePromptHasInputProtection() {
    for kind in [JavaScriptDialog.Kind.alert, .confirm, .prompt] {
      #expect(DialogContent.javaScriptDialog(dialog(kind)).inputProtection == 0, "\(kind)")
    }
  }

  @Test func leaveSiteLeavesOnlyOnLeave() {
    let dialog = leaveSite()
    #expect(dialog.response(for: .secondary, input: nil) == (true, nil))
    #expect(dialog.response(for: .primary, input: nil) == (false, nil))
    // Escape answers cancel: the user stays.
    #expect(dialog.response(for: .cancel, input: "x") == (false, nil))
  }

  @Test func leaveSiteKeepsTheEnginesButtonTitles() {
    var dialog = leaveSite()
    dialog.acceptTitle = "Verlassen"
    dialog.cancelTitle = "Bleiben"
    let content = DialogContent.javaScriptDialog(dialog)
    #expect(content.primaryTitle == "Bleiben")
    #expect(content.secondaryTitle == "Verlassen")
  }

  /// Every page dialog hangs from the card's top edge (#693, design/extensions `surf-dialog`), as the leave-site
  /// prompt did first (#584).
  @Test func everyPageDialogAttachesToTheCardsTopEdge() {
    #expect(leaveSite().panelAttachment == .topEdge)
    #expect(dialog(.alert).panelAttachment == .topEdge)
    #expect(dialog(.confirm).panelAttachment == .topEdge)
    #expect(dialog(.prompt).panelAttachment == .topEdge)
  }
}
