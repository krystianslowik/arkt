import AppKit
import EngineAPI

/// The app's Downloads: one model, one Library window, and for each browser window a Library button with its popover.
/// Created for an engine that has downloads (`EngineDownloads`); nil for one that has none, and then no window shows a
/// Library button. `ShellWindowSet` attaches every window it builds.
@MainActor
public final class DownloadsCenter {
  public let model: DownloadsModel
  public let settings: AppSettings
  /// The window app-level feedback goes to (the fallback toast); set by the window set.
  public var primaryWindow: @MainActor () -> ShellWindowController? = { nil }
  /// Settings > General, from the Library footer's Change link.
  public var onChangeLocation: (@MainActor () -> Void)? {
    didSet { library.onChangeLocation = onChangeLocation }
  }
  /// What VoiceOver is told; tests replace it. Polite, never every tick.
  public var announce: @MainActor (String) -> Void = { text in
    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
      .announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue,
    ])
  }

  public private(set) lazy var library: LibraryWindowController = {
    let controller = LibraryWindowController(model: model, settings: settings)
    controller.onReview = { [weak self] id in self?.review(id, on: controller.window) }
    controller.onChangeLocation = onChangeLocation
    return controller
  }()

  private struct Attachment {
    weak var controller: ShellWindowController?
    let button: LibraryButton
    let popover: DownloadsPopoverController
    let observation: DownloadsObservation
  }
  private var attachments: [Attachment] = []
  /// The sheet being shown, so one file has one sheet.
  private(set) var sheet: DownloadDangerSheet?

  public init?(engine: any EngineClient, settings: AppSettings) {
    guard let downloads = engine as? any EngineDownloads else { return nil }
    self.settings = settings
    model = DownloadsModel(engine: downloads, settings: settings)
    model.onAnnouncement = { [weak self] text in self?.announce(text) }
    model.onNotice = { [weak self] text in
      self?.primaryWindow()?.toasts.show(Toast(text: text, glyph: "folder"))
    }
    wireSavePanel(downloads)
  }

  /// `.ask` mode: the system save panel, over the primary window when there is one.
  private func wireSavePanel(_ downloads: any EngineDownloads) {
    downloads.downloadDestinationChooser = { [weak self] request in
      await self?.chooseDestination(request)
    }
  }

  func chooseDestination(_ request: DownloadDestinationRequest) async -> URL? {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = request.suggestedFilename
    panel.directoryURL = request.directory
    panel.canCreateDirectories = true
    if let window = primaryWindow()?.window {
      return await withCheckedContinuation { continuation in
        panel.beginSheetModal(for: window) { response in
          continuation.resume(returning: response == .OK ? panel.url : nil)
        }
      }
    }
    return panel.runModal() == .OK ? panel.url : nil
  }

  // MARK: Windows

  /// Gives `controller` its Library button and popover, wires Cmd-Shift-J and Cmd-Y through its claims, and keeps the
  /// button in step with the model.
  public func attach(to controller: ShellWindowController) {
    attachments.removeAll { $0.controller == nil || $0.controller?.isClosed == true }
    let button = LibraryButton()
    let popover = DownloadsPopoverController(model: model, button: button)
    popover.onShowLibrary = { [weak self] in self?.showLibrary() }
    popover.onReview = { [weak self, weak controller] id in self?.review(id, on: controller?.window) }
    let observation = model.addObserver { [weak button, weak model] _ in
      guard let button, let model else { return }
      button.apply(model.ringState)
    }
    button.apply(model.ringState)
    attachments.append(Attachment(controller: controller, button: button, popover: popover, observation: observation))
    controller.sidebarController.view.libraryButton = button
    controller.onShowLibrary = { [weak self] section in self?.showLibrary(section: section) }
  }

  /// The attached button of `controller`, for tests.
  func button(of controller: ShellWindowController) -> LibraryButton? {
    attachments.first { $0.controller === controller }?.button
  }

  func popover(of controller: ShellWindowController) -> DownloadsPopoverController? {
    attachments.first { $0.controller === controller }?.popover
  }

  /// Window > Show Library (Cmd-Shift-L), Downloads (Cmd-Shift-J: `.downloads`) and History (Cmd-Y: `.history`).
  public func showLibrary(section: LibrarySection? = nil) {
    for attachment in attachments { attachment.popover.hide(keyboard: true) }
    library.show(section: section)
  }

  // MARK: The dangerous-file sheet

  /// Review: the sheet over `window` (the Library or the browser window), one at a time.
  func review(_ id: DownloadID, on window: NSWindow?) {
    guard sheet == nil, let item = model.item(id), item.dangerType.needsSheet,
          let host = window ?? primaryWindow()?.window else { return }
    let folderName = (item.targetPath?.deletingLastPathComponent() ?? model.engine.downloadDefaultFolder).lastPathComponent
    let sheet = DownloadDangerSheet(item: item, folderName: folderName)
    self.sheet = sheet
    sheet.onFinish = { [weak self] answer in
      guard let self else { return }
      self.sheet = nil
      switch answer {
      case .delete: self.model.discard(id)
      case .showInFinder: self.model.showInFinder(id)
      case .keep: self.model.keep(id)
      case .dismissed: break
      }
    }
    sheet.begin(on: host)
  }
}
