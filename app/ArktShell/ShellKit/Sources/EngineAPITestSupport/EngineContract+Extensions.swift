import EngineAPI
import Foundation

// MARK: - Rule 27 (#721): uninstalling an extension

extension EngineContract {
  /// An id no profile has: 32 letters a to p, the form of a Chromium extension id.
  static let unknownExtensionID = String(repeating: "p", count: 32)

  public static func uninstallRemovesTheExtensionFromEveryWindow(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    guard let extensions = engine as? any EngineExtensions else {
      throw ContractNotApplicable(driver: "EngineExtensions")
    }
    guard let removableExtension = h.removableExtension else {
      throw ContractNotApplicable(driver: "removableExtension")
    }
    let first = engine.createWindow(host: h.makeWindowHost())
    let second = engine.createWindow(host: h.makeWindowHost())
    let id = try await removableExtension(engine, [first, second])
    let listed = { (window: EngineWindowID) in
      extensions.extensionActions(in: window).contains { $0.extensionID == id }
    }
    try await wait("both windows to list \(id)") { listed(first) && listed(second) }
    let action = try requireValue(extensions.extensionActions(in: first).first { $0.extensionID == id },
                                  "the action of \(id)")
    try require(action.canUninstall, "the harness's extension is removable")
    let tabs = engine.tabIDs

    // An id the profile does not have changes nothing; the real uninstall below comes after it in the engine's
    // order, so its events show that nothing came before them.
    let recorder = EventRecorder(engine)
    extensions.uninstallExtension(unknownExtensionID, reportAbuse: true, in: first)
    try require(listed(first) && listed(second), "an unknown id leaves the listing alone")

    extensions.uninstallExtension(id, reportAbuse: false, in: first)
    try await wait("\(id) to leave both windows") { !listed(first) && !listed(second) }
    try await wait("the announcement on both windows") {
      recorder.windowEvents.contains(.extensionActionsChanged(first))
        && recorder.windowEvents.contains(.extensionActionsChanged(second))
    }
    let created = recorder.events.filter { if case .tabCreated = $0 { true } else { false } }
    try require(created.isEmpty, "Report abuse off opens no tab")
    try require(engine.tabIDs == tabs, "no tab opened or closed")
  }
}
