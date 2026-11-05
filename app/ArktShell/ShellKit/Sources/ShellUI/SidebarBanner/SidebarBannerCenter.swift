import AppKit

/// The app's sidebar banner (#648): one model, and in every browser window a banner row above the bottom bar and an
/// announcement popover. The window set attaches each window it builds. The model holds the notice source, so the
/// updater (#126) replaces only the source.
@MainActor
public final class SidebarBannerCenter {
  public let model: SidebarBannerModel
  private var attachments: [SidebarBannerAttachment] = []

  public init(model: SidebarBannerModel) {
    self.model = model
  }

  /// Gives `controller`'s sidebar the banner, showing the current notice without motion.
  public func attach(to controller: ShellWindowController) {
    attachments.removeAll { $0.controller == nil || $0.controller?.isClosed == true }
    attachments.append(SidebarBannerAttachment(model: model, controller: controller))
  }

  /// The attachment of `controller` (tests).
  func attachment(of controller: ShellWindowController) -> SidebarBannerAttachment? {
    attachments.first { $0.controller === controller }
  }
}

/// One window's banner: follows the model, and routes the row's Restart, close and click (the popover).
@MainActor
final class SidebarBannerAttachment {
  weak var controller: ShellWindowController?
  let popover = SidebarBannerPopover()
  private let model: SidebarBannerModel
  private var observation: SidebarBannerObservation?

  init(model: SidebarBannerModel, controller: ShellWindowController) {
    self.model = model
    self.controller = controller
    let container = controller.sidebarController.view
    let banner = container.banner
    banner.onAction = { [weak model] in model?.performAction() }
    banner.onDismiss = { [weak model] in model?.dismiss() }
    banner.onOpen = { [weak self] in self?.togglePopover() }
    popover.reduceMotion = model.reduceMotion
    popover.onAction = { [weak model] in model?.performAction() }
    popover.onDismiss = { [weak model] in model?.dismiss() }
    container.setBanner(model.current, animated: false, reduceMotion: model.reduceMotion())
    observation = model.addObserver { [weak self] notice in self?.show(notice) }
  }

  private func show(_ notice: SidebarNotice?) {
    guard let container = controller?.sidebarController.view else { return }
    if popover.notice != notice { popover.hide() }
    container.setBanner(notice, animated: true, reduceMotion: model.reduceMotion())
  }

  func togglePopover() {
    guard let container = controller?.sidebarController.view, let notice = container.banner.notice,
          !notice.isUpdate else { return }
    if popover.isShown {
      popover.hide()
    } else {
      popover.show(notice, beside: container.banner.row, flavor: container.flavor)
    }
  }
}
