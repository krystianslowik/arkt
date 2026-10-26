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
}
