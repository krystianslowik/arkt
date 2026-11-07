import EngineAPI
import Foundation

/// The one-time decision for pages outside the sidebar after an unclean exit.
@MainActor
public final class RestorePagesModel {
  public struct Page: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
      case littleArkt, peek, incognito, blank, sidebar
    }

    public let title: String
    public let url: URL
    public let kind: Kind

    public init(title: String, url: URL, kind: Kind) {
      self.title = title
      self.url = url
      self.kind = kind
    }
  }

  public enum Presentation: Equatable, Sendable {
    case none
    case notice
    case offer([Page])
  }

  public private(set) var presentation: Presentation = .none
  private let recovery: any EngineSessionRecovery
  private var reopen: @MainActor ([Page]) -> Bool
  public var onAnswer: (@MainActor () -> Void)?

  init(recovery: any EngineSessionRecovery, pages: [Page],
              restore: @escaping @MainActor ([Page]) -> Void = { _ in }) {
    self.recovery = recovery
    self.reopen = { pages in restore(pages); return true }
    guard recovery.lastSessionCrashed else { return }
    let eligible = pages.filter { $0.kind == .littleArkt || $0.kind == .peek }
    if eligible.isEmpty {
      presentation = .notice
      recovery.dismissLastSession()
    } else {
      presentation = .offer(eligible)
    }
  }

  /// Production path: the provider owns the reopen operation and its typed payload.
  public convenience init(recovery: any EngineSessionRecovery) {
    guard let provider = recovery as? any EnginePageRecovery else {
      self.init(recovery: recovery, pages: [])
      return
    }
    let pages = provider.recoveryPages.map { page in
      Page(title: page.title, url: page.url, kind: page.kind == .peek ? .peek : .littleArkt)
    }
    self.init(recovery: recovery, pages: pages)
    self.reopen = { pages in
      provider.restorePages(pages.compactMap { page in
        let kind: RecoveryPage.Kind
        switch page.kind {
        case .littleArkt: kind = .littleArkt
        case .peek: kind = .peek
        case .incognito, .blank, .sidebar: return nil
        }
        return RecoveryPage(title: page.title, url: page.url, kind: kind)
      })
    }
  }

  public func dismiss() {
    guard case .offer = presentation else { return }
    presentation = .none
    recovery.dismissLastSession()
    onAnswer?()
  }

  public func restore() {
    guard case let .offer(pages) = presentation else { return }
    guard reopen(pages) else { return }
    presentation = .none
    recovery.dismissLastSession()
    onAnswer?()
  }
}
