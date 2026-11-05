import Foundation
import Testing
@testable import ShellUI

/// The Edit Pin popover's state (#363, design/edit-pin): the prefilled fields, what Save stores, the invalid
/// address line and Use Current Page. A value, so no window is needed.
struct EditPinFormTests {
  private let pinned = URL(string: "https://planning.example.com/roadmap")!
  private let current = URL(string: "https://planning.example.com/boards/q4?view=timeline")!

  private func form(_ kind: EditPinKind = .pinnedTab, name: String = "Q4 planning", url: URL? = nil) -> EditPinForm {
    EditPinForm(kind: kind, name: name, url: url ?? pinned, currentPage: current)
  }

  @Test func titlesFollowTheKind() {
    #expect(form(.pinnedTab).title == "Edit Pinned Tab")
    #expect(form(.favorite).title == "Edit Favorite")
  }

  /// The fields open with the current name and the pinned address, an https address without its scheme.
  @Test func fieldsArePrefilled() {
    let form = form()
    #expect(form.name == "Q4 planning")
    #expect(form.urlText == "planning.example.com/roadmap")
    #expect(!form.showsInvalidAddress)
    let plain = self.form(url: URL(string: "http://localhost:3000/a")!)
    #expect(plain.urlText == "http://localhost:3000/a", "a scheme the field cannot infer is kept")
  }

  @Test func savingUnchangedFieldsStoresNothing() {
    var form = form()
    #expect(form.submit() == .save(name: nil, url: nil))
    var plain = self.form(url: URL(string: "http://localhost:3000/a")!)
    #expect(plain.submit() == .save(name: nil, url: nil))
  }

  @Test func aNewAddressIsNormalizedAndStored() {
    var form = form()
    form.edit(urlText: "  example.com/next ")
    #expect(form.submit() == .save(name: nil, url: URL(string: "https://example.com/next")!))
  }

  @Test func aNewNameIsTrimmedAndStored() {
    var form = form(.favorite)
    form.edit(name: "  Team calendar  ")
    #expect(form.submit() == .save(name: "Team calendar", url: nil))
  }

  /// An empty name clears the custom title: the tab shows its page's title again.
  @Test func anEmptyNameIsStoredAsEmpty() {
    var form = form()
    form.edit(name: "   ")
    #expect(form.submit() == .save(name: "", url: nil))
  }

  @Test func nonLatinNamesAndAddressesSave() {
    var form = form(.favorite)
    form.edit(name: "Календарь команды")
    form.edit(urlText: "münchen.de/plan")
    guard case .save(let name, let url?) = form.submit() else {
      Issue.record("expected a save")
      return
    }
    #expect(name == "Календарь команды")
    #expect(url.absoluteString == "https://xn--mnchen-3ya.de/plan")
  }

  /// Save stays enabled: something that is not a web address shows the reason and stores nothing; the next edit
  /// clears it.
  @Test func anInvalidAddressShowsTheReasonUntilTheNextEdit() {
    var form = form()
    form.edit(urlText: "planning example com/roadmap")
    #expect(!form.showsInvalidAddress, "the line shows only on Save")
    #expect(form.submit() == .invalid)
    #expect(form.showsInvalidAddress)
    #expect(EditPinForm.invalidAddressMessage == "Enter a web address, like example.com")
    form.edit(urlText: "planning.example.com/roadmap2")
    #expect(!form.showsInvalidAddress)
  }

  @Test func anEmptyAddressIsInvalid() {
    var form = form()
    form.edit(urlText: "  ")
    #expect(form.submit() == .invalid)
  }

  @Test func editingTheNameDoesNotClearTheAddressLine() {
    var form = form()
    form.edit(urlText: "not an address")
    _ = form.submit()
    form.edit(name: "Other")
    #expect(form.showsInvalidAddress, "the line belongs to the URL field")
  }

  @Test func useCurrentPageFillsTheAddressAndClearsTheLine() {
    var form = form()
    form.edit(urlText: "bad address")
    _ = form.submit()
    form.useCurrentPage()
    #expect(form.urlText == "planning.example.com/boards/q4?view=timeline")
    #expect(!form.showsInvalidAddress)
    #expect(form.submit() == .save(name: nil, url: current))
  }

  /// A current page the field cannot type back (an internal page) is still stored as it is.
  @Test func useCurrentPageKeepsAnAddressTheParserWouldNotInfer() {
    let internalPage = URL(string: "http://127.0.0.1:8080/a")!
    var form = EditPinForm(kind: .favorite, name: "F", url: pinned, currentPage: internalPage)
    form.useCurrentPage()
    #expect(form.submit() == .save(name: nil, url: internalPage))
  }

  /// The popover grows by the invalid address line over 0.15 s; with Reduce Motion it takes its height at once.
  @Test func theErrorLineGrowsThePopoverOnlyWithoutReduceMotion() {
    #expect(EditPinMotion.errorResizeDuration(reducesMotion: false) == 0.15)
    #expect(EditPinMotion.errorResizeDuration(reducesMotion: true) == nil)
    #expect(EditPinMetrics.height(showingError: true) - EditPinMetrics.height(showingError: false)
              == EditPinMetrics.errorGap + EditPinMetrics.errorHeight)
  }
}
