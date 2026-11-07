import Foundation
internal import ArktEngineABI
import EngineAPI

// MARK: - Permission requests (#400, contract rule 20)

extension ChromiumEngine {
  /// Chromium's permission manager decides when a prompt shows and when it ends; the facade reports each prompt with the
  /// site's values and each end with one `PermissionEnded`. A tab the manager hides loses its prompt and gets a new one
  /// when shown again, which arrives here as a new request. A request of a tab this instance does not list (another
  /// instance's window) is not reported.
  func permissionRequested(_ event: any ArktEngineEvent) {
    guard let request = event.permission, let tab = tabByHandle[ObjectIdentifier(request.tab)], tabs[tab] != nil,
          permissionByHandle[ObjectIdentifier(request)] == nil else { return }
    endPermissions(of: tab)         // Chromium ends the earlier one first; this only guards the order
    let value = PermissionRequest(
      id: PermissionRequestID(), tab: tab, origin: request.origin,
      kinds: request.kinds.map { PermissionKind(facade: ArktPermissionKind(rawValue: $0.intValue) ?? .other) },
      title: request.title, items: request.items, allowTitle: request.allowTitle,
      allowThisTimeTitle: request.allowThisTimeTitle, blockTitle: request.blockTitle)
    pendingPermissions[value.id] = PendingPermission(id: value.id, tab: tab, handle: request)
    permissionByHandle[ObjectIdentifier(request)] = value.id
    hub.emit(.permissionRequested(value))
  }

  /// The engine ended the request, or the facade reports the end of one this client answered (dropped: it was reported
  /// when the answer went out).
  func permissionEnded(_ event: any ArktEngineEvent) {
    guard let request = event.permission, let id = permissionByHandle[ObjectIdentifier(request)] else { return }
    finishPermission(id)
  }

  /// The facade runs the site's callback and reports the end; the shell sees `.permissionEnded` before this returns. A
  /// request the engine already ended (its event is still queued) answers NO and ends here all the same.
  public func respond(toPermission request: PermissionRequestID, choice: PermissionChoice) {
    guard let pending = pendingPermissions[request] else { return }
    _ = pending.handle.respond(choice: ArktPermissionChoice(choice))
    finishPermission(request)
  }

  /// Ends every pending request of `tab`, in the order they were raised.
  func endPermissions(of tab: TabID) {
    for pending in pendingPermissions.values where pending.tab == tab { finishPermission(pending.id) }
  }

  private func finishPermission(_ id: PermissionRequestID) {
    guard let pending = pendingPermissions.removeValue(forKey: id) else { return }
    permissionByHandle[ObjectIdentifier(pending.handle)] = nil
    hub.emit(.permissionEnded(pending.tab, id))
  }
}

extension PermissionKind {
  init(facade kind: ArktPermissionKind) {
    switch kind {
    case .geolocation: self = .geolocation
    case .notifications: self = .notifications
    case .camera: self = .camera
    case .microphone: self = .microphone
    case .other: self = .other
    @unknown default: self = .other
    }
  }
}

extension ArktPermissionChoice {
  init(_ choice: PermissionChoice) {
    switch choice {
    case .allow: self = .allow
    case .allowThisTime: self = .allowThisTime
    case .block: self = .block
    case .dismiss: self = .dismiss
    }
  }
}
