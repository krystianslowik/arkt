import EngineAPI
import Foundation

/// The post-install toast (#594, `design/extensions`, `toast-pin`): after an extension installs, "<name> added" on the
/// window the user is in, with one quiet action, Pin. New extensions are not pinned (#590). It replaces Chromium's
/// post-install text, so nothing here names the engine or the Window menu.
///
/// `.installed` may arrive after the `.extensionActionsChanged` that lists the extension's action (and its pin), so
/// the pin state is read when `.installed` arrives: an extension the engine already pinned gets no Pin action. Pin on
/// an extension pinned meanwhile (from the panel) is a no-op in the engine.
@MainActor
final class ExtensionInstallToasts {
  /// The longest name shown, in characters, ellipsis included; the rest is cut so "added" always shows.
  static let nameLimit = 40
  static let pinTitle = "Pin"

  private var observation: EngineObservation?

  /// `presenter` is the window the toast goes to (the one most recently main); nil: none is open and no toast shows.
  init(extensions: any EngineExtensions, presenter: @escaping @MainActor () -> ToastPresenter?) {
    observation = extensions.observeExtensions { [weak extensions] event in
      guard case .installed(let info) = event, let extensions, let presenter = presenter() else { return }
      let isPinned = extensions.pinnedExtensionIDs.contains(info.id)
      let toast = Self.toast(for: info, isPinned: isPinned)
      if isPinned {
        presenter.show(toast)
      } else {
        presenter.show(toast) { [weak extensions] in extensions?.setExtensionPinned(info.id, pinned: true) }
      }
    }
  }

  /// "<name> added" in curly quotes, the name cut to `nameLimit`; VoiceOver hears the whole name without quotes.
  static func toast(for info: InstalledExtension, isPinned: Bool) -> Toast {
    let name = info.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let actionTitle = isPinned ? nil : pinTitle
    guard !name.isEmpty else { return Toast(text: "Extension added", actionTitle: actionTitle) }
    let shown = name.count > nameLimit
      ? name.prefix(nameLimit - 1).trimmingCharacters(in: .whitespaces) + "\u{2026}"
      : name
    return Toast(text: "\u{201C}\(shown)\u{201D} added", actionTitle: actionTitle, announcement: "\(name) added")
  }
}
