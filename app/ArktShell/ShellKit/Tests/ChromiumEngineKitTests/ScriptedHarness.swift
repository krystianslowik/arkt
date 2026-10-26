import AppKit
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
@testable import ChromiumEngineKit

/// The contract harness for `ChromiumEngine` over a `ScriptedFacade`, with every driver. The drivers go through the
/// engine's test API where the W3-9 runner will (title, `beforeunload`, `window.open`, dialog answers), and through
/// the scripted facade where the runner uses an extension (`chrome.tabs.remove`, `chrome.tabs.update`).
@MainActor
enum ScriptedHarness {
  static func make(configure: @escaping @MainActor (ScriptedFacade) -> Void = { _ in }) -> EngineHarness {
    EngineHarness(
      makeEngine: {
        let facade = ScriptedFacade()
        configure(facade)
        let engine = ChromiumEngine(facade: facade)
        // An instance with no window cannot place window-less tabs (rules 1-10): the window comes first.
        engine.createWindow(host: StubWindowHost())
        return engine
      },
      pageURL: { title in URL(string: "arkt-test://page.test/\(title)")! },
      settle: { engine, id in
        let (chromium, tab) = try parts(engine, id)
        tab.finishLoad()
        try await delivered(chromium)
      },
      retitle: { engine, id, title in
        _ = try await chromium(engine).evaluateScript("document.title = \"\(title)\"", in: id, userGesture: false)
      },
      pagesOnTwoHosts: {
        (URL(string: "arkt-test://alpha.test/Alpha")!, URL(string: "arkt-test://beta.test/Beta")!)
      },
      engineCreateTab: { engine, window, opener, active in
        let chromium = try chromium(engine)
        let before = Set(chromium.tabIDs)
        if let opener, active {
          let opened = try await chromium.evaluateScript("window.open(\"arkt-test://page.test/Opened\")", in: opener,
                                                         userGesture: true)
          guard opened == .bool(true) else { throw HarnessError("window.open answered \(String(describing: opened))") }
        } else {
          let browser = try scriptedBrowser(chromium, window)
          let openerTab = try opener.map { try scriptedTab(chromium, $0) }
          scripted(chromium).engineCreateTab(in: browser, url: URL(string: "arkt-test://page.test/Created"),
                                             opener: openerTab, active: active)
        }
        try await ScriptedWait.until("the engine-created tab to be listed") {
          Set(chromium.tabIDs).subtracting(before).count == 1
        }
        guard let created = Set(chromium.tabIDs).subtracting(before).first else { throw HarnessError("no new tab") }
        return created
      },
      engineCloseTab: { engine, id in
        let (chromium, tab) = try parts(engine, id)
        scripted(chromium).engineCloseTab(tab, reason: .extension)
        try await delivered(chromium)
      },
      engineActivate: { engine, id in
        let (chromium, tab) = try parts(engine, id)
        scripted(chromium).engineActivate(tab)
        try await delivered(chromium)
      },
      holdClose: { engine, id in
        _ = try await chromium(engine).evaluateScript("window.onbeforeunload = () => true", in: id, userGesture: true)
      },
      answerDialog: { engine, id, accept in
        guard try chromium(engine).answerDialog(in: id, accept: accept) else {
          throw HarnessError("no pending dialog in \(id)")
        }
      },
      makeAudible: { engine, id in
        _ = try await chromium(engine).evaluateScript(EngineContract.toneScript, in: id, userGesture: true)
      },
      engineCloseWindow: { engine, window in
        let chromium = try chromium(engine)
        try scriptedBrowser(chromium, window).closeByExtension()
        try await delivered(chromium)
      },
      // A scripted tab has a frame once its load finished; nothing to show.
      showPage: { _, _ in },
      raiseDialog: { engine, id, kind, message, defaultText in
        let (chromium, tab) = try parts(engine, id)
        tab.raiseDialog(ArktDialogKind(kind), message: message, defaultText: defaultText)
        try await delivered(chromium)
      }
    )
  }

  // MARK: Helpers

  struct HarnessError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
  }

  static func chromium(_ engine: any EngineClient) throws -> ChromiumEngine {
    guard let engine = engine as? ChromiumEngine else { throw HarnessError("not a ChromiumEngine: \(engine)") }
    return engine
  }

  static func scripted(_ engine: ChromiumEngine) -> ScriptedFacade {
    // The harness builds every engine over a ScriptedFacade.
    engine.facade as! ScriptedFacade
  }

  static func scriptedTab(_ engine: ChromiumEngine, _ id: TabID) throws -> ScriptedTab {
    guard let tab = engine.handle(of: id) as? ScriptedTab else { throw HarnessError("no scripted tab for \(id)") }
    return tab
  }

  static func scriptedBrowser(_ engine: ChromiumEngine, _ id: EngineWindowID) throws -> ScriptedBrowser {
    guard let browser = engine.windows[id]?.browser as? ScriptedBrowser else {
      throw HarnessError("no scripted browser for \(id)")
    }
    return browser
  }

  static func parts(_ engine: any EngineClient, _ id: TabID) throws -> (ChromiumEngine, ScriptedTab) {
    let chromium = try chromium(engine)
    return (chromium, try scriptedTab(chromium, id))
  }

  /// Waits until the facade has delivered everything it recorded (its batches arrive one main-actor turn later).
  static func delivered(_ engine: ChromiumEngine) async throws {
    let facade = scripted(engine)
    try await ScriptedWait.until("the facade to deliver its batch") { facade.isIdle }
  }
}

extension ArktDialogKind {
  init(_ kind: JavaScriptDialog.Kind) {
    switch kind {
    case .alert: self = .alert
    case .confirm: self = .confirm
    case .prompt: self = .prompt
    }
  }
}
