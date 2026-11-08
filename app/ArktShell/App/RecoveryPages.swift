import Foundation
import Persistence
import ShellUI

/// The shell sees values only; persistence and its ordered background writes stay in the app layer.
@MainActor
final class RecoveryPages: RecoveryPageSource {
  private let writer: RecoveryPageWriter
  private var suspended = false
  var pages: [ShellRecoveryPage] {
    didSet {
      if suspended { pages = oldValue } else { writer.schedule(Self.state(pages)) }
    }
  }
  var needsFlush: Bool { writer.needsFlush }

  init(state: RecoveryPageState, store: SettingsStore) {
    pages = state.pages.map {
      ShellRecoveryPage(title: $0.title, url: $0.url,
                        kind: $0.kind == .peek ? .peek : .littleArkt, sourceNode: $0.sourceNode)
    }
    writer = RecoveryPageWriter(store: store, initial: state)
    writer.onFailure = { AppSession.log.error("recovery pages not saved") }
  }

  func suspendWrites() { suspended = true }
  func resumeWrites() { suspended = false }

  func flush() async -> Bool {
    let success = await writer.flush()
    if !success { AppSession.log.error("recovery pages not saved") }
    return success
  }

  func flushBlocking() -> Bool {
    let success = writer.flushBlocking()
    if !success { AppSession.log.error("recovery pages not saved") }
    return success
  }

  private static func state(_ pages: [ShellRecoveryPage]) -> RecoveryPageState {
    RecoveryPageState(pages: pages.map {
      RecoveryPageRecord(title: $0.title, url: $0.url,
                         kind: $0.kind == .peek ? .peek : .littleArkt, sourceNode: $0.sourceNode)
    })
  }
}
