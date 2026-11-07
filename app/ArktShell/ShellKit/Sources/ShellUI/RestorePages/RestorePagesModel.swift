import EngineAPI
import Foundation

/// The one-time decision for pages outside the sidebar after an unclean exit.
@MainActor
public final class RestorePagesModel {
  public enum Presentation: Equatable, Sendable {
    case none
    case notice
    case offer([RecoveryPage])
  }

  public private(set) var presentation: Presentation = .none
  private let recovery: any EngineSessionRecovery
  private let reopen: @MainActor ([RecoveryPage]) -> Bool
  public var onAnswer: (@MainActor () -> Void)?

  public init(recovery: any EngineSessionRecovery, restore: @escaping @MainActor ([RecoveryPage]) -> Bool) {
    self.recovery = recovery
    self.reopen = restore
    guard recovery.lastSessionCrashed else { return }
    let pages = (recovery as? any EnginePageRecovery)?.recoveryPages ?? []
    if pages.isEmpty {
      presentation = .notice
      recovery.dismissLastSession()
    } else {
      presentation = .offer(pages)
    }
  }

  public func dismiss() {
    guard case .offer = presentation else { return }
    presentation = .none
    recovery.dismissLastSession()
    onAnswer?()
  }

  public func restore() {
    guard case let .offer(pages) = presentation, reopen(pages) else { return }
    presentation = .none
    recovery.dismissLastSession()
    onAnswer?()
  }
}
