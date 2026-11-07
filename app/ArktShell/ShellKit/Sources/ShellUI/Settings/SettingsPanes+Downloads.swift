import AppKit
import Foundation

/// Settings > General > Downloads (#132, BH-182, design/downloads, "Location"): when a file downloads Arkt either asks
/// where to save it (the system save panel) or saves to a folder with no panel; the folder is Downloads, Desktop or one
/// chosen with Choose...; a Library row opens the Library. Dangerous files are held whichever way this is set.
extension SettingsWindowController {
  static let downloadsNote = "Dangerous files are always held for your decision, whichever way this is set."
  static let askTitle = "Ask Where to Save"
  static let folderTitle = "Save to Folder"

  func downloadRows() -> [SettingsBlockView] {
    let location = settings.downloadLocation
    let mode = SettingsSegmentedControl(segments: [Self.askTitle, Self.folderTitle],
                                        selected: location.asksWhereToSave ? 0 : 1, segmentWidth: 128)
    mode.onChange = { [weak self] index in
      self?.settings.downloadLocation.asksWhereToSave = index == 0
    }
    mode.setAccessibilityLabel("When a file downloads")
    identify(mode, .general, "downloadsMode")
    mode.setAccessibilityIdentifier(AXID.Downloads.locationMode)
    downloadModeControl = mode
    let modeRow = row("When a file downloads", Self.modeCaption(asks: location.asksWhereToSave), [mode])
    downloadModeRow = modeRow
    let folderRow = row("Folder", Self.folderCaption(location, defaultFolder: services.downloadsFolder),
                        downloadFolderControls())
    downloadFolderRow = folderRow
    folderRow.setDimmed(location.asksWhereToSave)
    let library = pill(.general, "openLibrary", "Open Library", small: true) { [weak self] in self?.services.openLibrary?() }
    library.isEnabled = services.openLibrary != nil
    library.setAccessibilityIdentifierWithCell(AXID.Downloads.openLibrary)
    let libraryRow = row("Library", "Opens on the section you used last. Command-Shift-J jumps to Downloads.", [library])
    return [modeRow, folderRow, libraryRow]
  }

  static func modeCaption(asks: Bool) -> String {
    asks ? "A save panel asks where to put each file." : "Files save straight to the folder below. No panel."
  }

  static func folderCaption(_ location: DownloadLocationSetting, defaultFolder: URL) -> String {
    ((location.folder ?? defaultFolder).path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
  }

  /// The pop-up's titles: Downloads, Desktop, the chosen folder when it is neither, and Other....
  func downloadFolderItems() -> (items: [String], selected: String) {
    let location = settings.downloadLocation
    let chosen = (location.folder ?? services.downloadsFolder).standardizedFileURL
    let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.standardizedFileURL
    var items = ["Downloads", "Desktop"]
    let selected: String
    if chosen == services.downloadsFolder.standardizedFileURL {
      selected = "Downloads"
    } else if chosen == desktop {
      selected = "Desktop"
    } else {
      selected = chosen.lastPathComponent
      items.append(selected)
    }
    return (items + ["Other..."], selected)
  }

  private func downloadFolderControls() -> [NSView] {
    let (items, selected) = downloadFolderItems()
    let popUp = SettingsPopUpButton(items: items, selected: selected)
    identify(popUp, .general, "downloadsFolder")
    popUp.setAccessibilityIdentifier(AXID.Downloads.locationFolder)
    popUp.setAccessibilityLabel("Folder")
    popUp.onChange = { [weak self] title in self?.chooseDownloadFolder(titled: title) }
    let choose = pill(.general, "downloadsChoose", "Choose...", small: true) { [weak self] in self?.pickDownloadFolder() }
    choose.setAccessibilityIdentifierWithCell(AXID.Downloads.locationChoose)
    return [popUp, choose]
  }

  /// The pop-up chose `title`: a named folder applies at once; Other... opens the panel.
  func chooseDownloadFolder(titled title: String) {
    switch title {
    case "Downloads": settings.downloadLocation.folder = nil
    case "Desktop":
      settings.downloadLocation.folder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    case "Other...": pickDownloadFolder()
    default: break                                             // the chosen folder's own entry: no change
    }
    applyDownloadLocation()
  }

  /// Choose... and Other...: the folder panel, then the folder applies. Cancelling changes nothing.
  func pickDownloadFolder() {
    downloadFolderPicker(window) { [weak self] url in
      guard let self else { return }
      if let url { self.settings.downloadLocation.folder = url }
      self.applyDownloadLocation()
    }
  }

  /// Follows the store: the mode, the captions, the dimmed folder row and the pop-up's entries.
  func applyDownloadLocation() {
    guard let modeRow = downloadModeRow, let folderRow = downloadFolderRow else { return }
    let location = settings.downloadLocation
    downloadModeControl?.select(location.asksWhereToSave ? 0 : 1)
    modeRow.setCaption(Self.modeCaption(asks: location.asksWhereToSave))
    folderRow.setCaption(Self.folderCaption(location, defaultFolder: services.downloadsFolder))
    folderRow.setDimmed(location.asksWhereToSave)
    folderRow.setTrailing(downloadFolderControls())
    layoutPane()
  }
}
