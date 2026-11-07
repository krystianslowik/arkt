import Foundation
import Synchronization
import Testing
@testable import CrashReporting

/// The consent gate and the one-time ask (#129): nothing is stored or offered while the switch is off, except the one
/// newest report the first ask needs; the ask comes once, and every answer ends it.
struct ConsentGateTests {
  private let epoch = Date(timeIntervalSince1970: 2_000_000_000)

  private final class Consent: Sendable {
    private let state: Mutex<(enabled: Bool, asked: Bool)>
    init(enabled: Bool, asked: Bool) { state = Mutex((enabled, asked)) }
    var value: (enabled: Bool, asked: Bool) {
      get { state.withLock { $0 }  }
    }
    func set(enabled: Bool? = nil, asked: Bool? = nil) {
      state.withLock { if let enabled { $0.enabled = enabled }; if let asked { $0.asked = asked } }
    }
  }

  private func makeRecorder(_ consent: Consent, store: CrashReportStore) -> CrashReportRecorder {
    CrashReportRecorder(store: store, stripper: CrashFixtures.stripper, newID: { UUID().uuidString.lowercased() },
                        consent: { consent.value })
  }

  private func makeStore() -> CrashReportStore {
    CrashReportStore(directory: CrashFixtures.makeDirectory(), now: { epoch })
  }

  // MARK: Policy

  @Test func captureActionFollowsTheSwitchAndTheAsk() {
    #expect(CrashReportPolicy.captureAction(enabled: true, asked: false) == .store)
    #expect(CrashReportPolicy.captureAction(enabled: true, asked: true) == .store)
    #expect(CrashReportPolicy.captureAction(enabled: false, asked: false) == .holdForAsk)
    #expect(CrashReportPolicy.captureAction(enabled: false, asked: true) == .discard)
  }

  @Test func theAskIsOnlyForAHeldReportWithTheSwitchOffAndNoAnswerYet() {
    #expect(CrashReportPolicy.shouldAsk(enabled: false, asked: false, hasReport: true))
    #expect(!CrashReportPolicy.shouldAsk(enabled: false, asked: false, hasReport: false))
    #expect(!CrashReportPolicy.shouldAsk(enabled: false, asked: true, hasReport: true), "never again after an answer")
    #expect(!CrashReportPolicy.shouldAsk(enabled: true, asked: false, hasReport: true), "the switch already says yes")
    #expect(!CrashReportPolicy.shouldAsk(enabled: true, asked: true, hasReport: true))
  }

  @Test func everyAnswerEndsTheAsk() {
    for answer in [CrashReportPolicy.Answer.send, .dontSend, .alwaysSend] {
      #expect(CrashReportPolicy.resolution(for: answer).marksAsked, "\(answer)")
    }
  }

  @Test func eachAnswerDoesWhatItSays() {
    let send = CrashReportPolicy.resolution(for: .send)
    #expect(send.opensReport && send.deletesReport && send.enablesSwitch == false)
    let dont = CrashReportPolicy.resolution(for: .dontSend)
    #expect(!dont.opensReport && dont.deletesReport && dont.enablesSwitch == false)
    let always = CrashReportPolicy.resolution(for: .alwaysSend)
    #expect(always.opensReport && !always.deletesReport && always.enablesSwitch)
  }

  // MARK: Recorder

  @Test func withTheSwitchOffAndAnsweredNothingIsStored() throws {
    let store = makeStore()
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let recorder = makeRecorder(Consent(enabled: false, asked: true), store: store)
    #expect(recorder.record(CrashFixtures.raw()) == nil)
    #expect(try store.reports().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: store.directory.path), "not even the folder")
    #expect(recorder.reportToAskAbout() == nil)
  }

  @Test func withTheSwitchOffAndNoAnswerOnlyTheNewestReportIsHeld() throws {
    let store = makeStore()
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let recorder = makeRecorder(Consent(enabled: false, asked: false), store: store)
    let first = try #require(recorder.record(CrashFixtures.raw()))
    let second = try #require(recorder.record(CrashFixtures.raw()))
    #expect(try store.reports().map(\.id) == [second.id])
    #expect(first.id != second.id)
    #expect(recorder.reportToAskAbout()?.id == second.id)
  }

  @Test func withTheSwitchOnReportsAreStoredAndNeverAsked() throws {
    let store = makeStore()
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let recorder = makeRecorder(Consent(enabled: true, asked: false), store: store)
    _ = recorder.record(CrashFixtures.raw())
    _ = recorder.record(CrashFixtures.raw())
    #expect(try store.reports().count == 2)
    #expect(recorder.reportToAskAbout() == nil)
  }

  @Test func theStoredReportIsStrippedOnDisk() throws {
    let store = makeStore()
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let recorder = makeRecorder(Consent(enabled: true, asked: true), store: store)
    _ = recorder.record(CrashFixtures.raw())
    let file = try #require(FileManager.default.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil).first)
    let text = try String(contentsOf: file, encoding: .utf8)
    for value in CrashFixtures.forbidden { #expect(!text.contains(value), "on disk: \(value)") }
  }

  @Test func turningTheSwitchOffClearsWhatWasStored() throws {
    let store = makeStore()
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let consent = Consent(enabled: true, asked: false)
    let recorder = makeRecorder(consent, store: store)
    _ = recorder.record(CrashFixtures.raw())
    consent.set(enabled: false, asked: true)
    recorder.consentChanged()
    #expect(try store.reports().isEmpty)
  }

  @Test func turningTheSwitchOffBeforeAnyAnswerDeletesEverythingAndEndsTheAsk() throws {
    let store = makeStore()
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let consent = Consent(enabled: false, asked: false)
    let recorder = CrashReportRecorder(
      store: store, stripper: CrashFixtures.stripper, newID: { UUID().uuidString.lowercased() },
      consent: { consent.value }, markAsked: { consent.set(asked: true) })
    _ = recorder.record(CrashFixtures.raw())                       // held for the ask
    consent.set(enabled: true)
    recorder.consentChanged()
    #expect(try store.reports().count == 1, "turning it on keeps the report")
    consent.set(enabled: false)                                    // on, then off, before any answer
    recorder.consentChanged()
    #expect(try store.reports().isEmpty, "off deletes every stored report")
    #expect(consent.value.asked, "off settles the ask")
    #expect(recorder.reportToAskAbout() == nil)
    #expect(recorder.record(CrashFixtures.raw()) == nil, "and nothing more is kept")
  }

  @Test func aMetricKitAbortAfterAnExceptionReportIsTheSameCrash() throws {
    let store = makeStore()
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let recorder = makeRecorder(Consent(enabled: true, asked: true), store: store)
    _ = recorder.record(CrashFixtures.raw(source: .uncaughtException, isAbort: true))
    #expect(recorder.record(CrashFixtures.raw(source: .metricKit, isAbort: true)) == nil)
    #expect(try store.reports().count == 1)
    // One exception covers one abort: a second MetricKit abort is a different crash.
    #expect(recorder.record(CrashFixtures.raw(source: .metricKit, isAbort: true)) != nil)
    #expect(try store.reports().count == 2)
  }

  @Test func aMetricKitCrashThatIsNotAnAbortIsNeverMerged() throws {
    let store = makeStore()
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let recorder = makeRecorder(Consent(enabled: true, asked: true), store: store)
    _ = recorder.record(CrashFixtures.raw(source: .uncaughtException, isAbort: true))
    #expect(recorder.record(CrashFixtures.raw(source: .metricKit, isAbort: false)) != nil)
    #expect(try store.reports().count == 2)
  }
}
