import AppKit

extension ShellWindowController {
  /// File > Import Browser Data...: the import sheet over this window (#514). The sheet keeps itself alive until it
  /// closes; nil when the window is not on screen or already has a sheet.
  @discardableResult
  public func presentBrowserDataImport(source: any BrowserDataImportSource) -> BrowserDataImportSheet? {
    guard let window, window.attachedSheet == nil else { return nil }
    let sheet = BrowserDataImportSheet(source: source)
    sheet.begin(on: window)
    return sheet
  }
}
