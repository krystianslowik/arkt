import Foundation
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// How the scripted facade orders a load's events.
enum FacadeScript: String, CaseIterable, Sendable {
  /// Chromium's usual order: title, favicon clear, load end.
  case chromiumOrder
  /// The title and the favicon clear recorded after the load end, in the same batch (Risk 2).
  case titleAfterLoadEnd
}

/// The shared contract against `ChromiumEngine` over the scripted facade, in plain `swift test` (no Chromium). Every
/// harness driver is present, so no rule is reported as not applicable.
@MainActor
struct ChromiumEngineContractTests {
  @Test(arguments: ContractCheck.allCases, FacadeScript.allCases)
  func contract(_ check: ContractCheck, _ script: FacadeScript) async throws {
    let harness = ScriptedHarness.make { facade in facade.titleAfterLoadEnd = script == .titleAfterLoadEnd }
    try await check.run(harness)
  }

  /// The drivers are all present: a rule that needs one never throws `ContractNotApplicable`.
  @Test func everyDriverIsPresent() {
    let harness = ScriptedHarness.make()
    #expect(harness.engineCreateTab != nil && harness.engineCloseTab != nil && harness.engineActivate != nil)
    #expect(harness.holdClose != nil && harness.answerDialog != nil)
    #expect(harness.makeAudible != nil && harness.engineCloseWindow != nil && harness.showPage != nil)
  }

  /// The list names every public check of `EngineContract` (read from its sources), so a new rule cannot be left out.
  @Test func everyContractCheckIsListed() throws {
    let support = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appending(path: "../../Sources/EngineAPITestSupport").standardizedFileURL
    let files = try FileManager.default.contentsOfDirectory(at: support, includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent.hasPrefix("EngineContract") }
    var names: Set<String> = []
    for file in files {
      let source = try String(contentsOf: file, encoding: .utf8)
      for match in source.matches(of: #/public static func (\w+)\(_ h: EngineHarness\)/#) {
        names.insert(String(match.output.1))
      }
    }
    #expect(names.count == 32)
    #expect(names == Set(ContractCheck.allCases.map(\.rawValue)))
    #expect(Set(ContractCheck.allCases.map(\.rule)) == Set(1...19))
  }
}
