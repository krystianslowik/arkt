import AppKit
import os

/// How an import run by the first run ended.
public enum OnboardingImportResult: Equatable, Sendable {
  /// `addedSpaces` in the source's order; the browser lands on the first one.
  case imported(skipped: Int, addedSpaces: [SpaceID])
  case failed
}

/// What the app provides to the first run: the Arc check, the count pass and the import (CoreBridge, through the
/// app), the default-browser registration, and where progress is saved. ShellUI never sees the database or Arc's
/// files.
@MainActor
public protocol OnboardingServices: AnyObject {
  /// Whether Arc's sidebar file exists (existence only).
  func checkArc() async -> Bool
  /// The read-only count pass: cumulative counts as it walks the data.
  func countArcData() -> AsyncThrowingStream<OnboardingCounts, any Error>
  /// Imports, without the summary alert.
  func importArcData() async -> OnboardingImportResult
  /// Arkt opens http and https links now.
  func isDefaultBrowser() -> Bool
  /// Asks macOS to make Arkt the default browser; returns when the system prompt closed, whatever the answer.
  func makeDefaultBrowser() async
  /// The step the user reached, saved as they move on (first run only).
  func saveProgress(_ snapshot: OnboardingFlow.Snapshot)
  /// Start browsing or a confirmed Skip setup: `onboardingCompletedVersion` is written and the saved step cleared.
  func markCompleted()
}

/// Runs the first run (or Help > Welcome to Arkt) over one window: the flow model, the step views, the stage, the
/// import, Make it yours, the default-browser step and the landing in the browser (sections 2, 6, 8, 10 to 13).
@MainActor
public final class OnboardingController {
  public struct Options: Sendable {
    public var mode: OnboardingMode
    /// The Chromium engine configuration shows the Extensions step.
    public var includesExtensions: Bool
    /// Resume at a saved step, without the Welcome reveal.
    public var resume: OnboardingFlow.Snapshot?
    /// The Chrome Web Store's address for the extensions option.
    public var webStoreURL: URL

    public init(mode: OnboardingMode, includesExtensions: Bool, resume: OnboardingFlow.Snapshot? = nil,
                webStoreURL: URL = Options.chromeWebStore) {
      self.mode = mode
      self.includesExtensions = includesExtensions
      self.resume = resume
      self.webStoreURL = webStoreURL
    }

    // A constant literal that always parses.
    public static let chromeWebStore = URL(string: "https://chromewebstore.google.com/")!
  }

  static let log = Logger(subsystem: ShellSignposts.subsystem, category: "onboarding")
  /// Count updates re-form the numbers at most 12 times a second (P4).
  static let countInterval: TimeInterval = 1.0 / 12

  public private(set) var flow: OnboardingFlow
  public private(set) var theme: OnboardingTheme?
  public private(set) var counts = OnboardingCounts()
  public private(set) var webStoreOn = false
  public private(set) var isFinished = false
  /// The Space Make it yours created (fresh path); later visits edit it.
  public private(set) var createdSpace: SpaceID?
  /// The Spaces the import added.
  public private(set) var importedSpaces: [SpaceID] = []
  /// Called once the flow ended and the overlay is gone.
  public var onFinish: (@MainActor () -> Void)?
  /// Test seam: runs instead of the `NSAlert` sheet; answer true to confirm Skip setup.
  public var confirmSkip: (@MainActor (@escaping @MainActor (Bool) -> Void) -> Void)?

  let view: OnboardingView
  private weak var window: ShellWindowController?
  private let services: any OnboardingServices
  private let options: Options
  private var themeOpened: OnboardingTheme?
  private var countTask: Task<Void, Never>?
  private var pendingCounts: OnboardingCounts?
  private var countTimer: Timer?
  private var lastCountApply: TimeInterval = 0
  private var landed: Set<OnboardingCounts.Kind> = []
  private var isPrompting = false
  private var skipAfterImport = false
  private var isAsking = false
  private var browserViews: [(NSView, Bool)] = []
  private var firstStepShown = false

  public var stage: any OnboardingStage { view.stage }

  public init(window: ShellWindowController, services: any OnboardingServices, options: Options,
              stage: any OnboardingStage = CoreAnimationOnboardingStage(),
              appearance: OnboardingAppearance? = nil) {
    self.window = window
    self.services = services
    self.options = options
    let conditions = OnboardingFlow.Conditions(
      arc: .checking, isDefaultBrowser: services.isDefaultBrowser(),
      includesExtensions: options.includesExtensions, mode: options.mode)
    flow = options.resume.map { OnboardingFlow(resuming: $0, conditions: conditions) }
      ?? OnboardingFlow(conditions: conditions)
    let resolved = appearance ?? OnboardingAppearance.current(
      for: window.window?.effectiveAppearance ?? NSAppearance.currentDrawing())
    view = OnboardingView(stage: stage, appearance: resolved)
    view.onKey = { [weak self] key in self?.handle(key) }
    view.onBack = { [weak self] in self?.back() }
    view.onSkipSetup = { [weak self] in self?.askSkipSetup() }
  }

  // MARK: - Start

  /// Covers the window, checks for Arc, and shows the first step (Welcome with M1, or the saved step at rest).
  public func start() {
    guard let window, let root = window.window?.contentView else { return }
    view.frame = root.bounds
    view.autoresizingMask = [.width, .height]
    root.addSubview(view)
    hideBrowser(true)
    if case .imported = flow.importPhase { importedSpaces = Array(window.sidebar.spaceOrder.prefix(1)) }
    showStep(animated: false, firstReveal: options.resume == nil)
    window.window?.makeFirstResponder(view)
    Task { [weak self, services] in
      let found = await services.checkArc()
      self?.arcChecked(found)
    }
  }

  private func arcChecked(_ found: Bool) {
    guard !isFinished else { return }
    let wasImport = flow.step == .importData
    flow.setArc(found ? .found : .notFound)
    if wasImport, flow.step != .importData {
      showStep(animated: true)                        // "no Arc": Import is replaced by Make it yours
    } else if flow.step == .importData {
      startCountingIfNeeded()
      refreshFooter(animated: true)
    } else {
      refreshFooter(animated: false)
    }
  }

  // MARK: - Steps

  private func showStep(animated: Bool, firstReveal: Bool = false) {
    let signpost = ShellSignposts.signposter.beginInterval("onboarding.step")
    let compact = view.bounds.height < 700
    if flow.step == .theme { prepareTheme() }
    let stepView = OnboardingStepView(content: content(for: flow.step), appearance: view.appearanceModel,
                                      compact: compact)
    configure(stepView)
    view.setStep(stepView, animated: animated)
    refreshFooter(animated: animated)
    if animated || firstReveal {
      stepView.reveal(reduceMotion: view.appearanceModel.reduceMotion, firstReveal: firstReveal)
    } else {
      stepView.showAtRest()
    }
    view.stage.show(formation(for: stepView), appearance: view.appearanceModel, animated: animated || firstReveal)
    view.setWash(flow.step == .theme ? theme?.resolvedTheme : nil, animated: animated)
    if flow.step == .importData { startCountingIfNeeded() }
    if options.mode == .firstRun, firstStepShown || options.resume != nil || flow.step != .welcome {
      services.saveProgress(flow.snapshot)
    }
    firstStepShown = true
    view.window?.makeFirstResponder(view)
    NSAccessibility.post(element: view, notification: .layoutChanged,
                         userInfo: [.uiElements: [stepView.title]])
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { ShellSignposts.signposter.endInterval("onboarding.step", signpost) }
  }

  private func refreshFooter(animated: Bool) {
    let progress = flow.progress
    view.stepValue = progress.map { OnboardingCopy.stepValue($0.index, of: $0.total) } ?? ""
    view.setFooter(showsBack: flow.showsBack,
                   progress: flow.showsProgress ? progress.map { OnboardingCopy.progress($0.index, of: $0.total) } : nil,
                   showsSkip: flow.showsSkipSetup, animated: animated)
  }

  private func content(for step: OnboardingStep) -> OnboardingStepView.Content {
    typealias C = OnboardingCopy
    typealias B = OnboardingStepView.Button
    let reentry = options.mode == .reentry
    switch step {
    case .welcome:
      return .init(step: step, eyebrow: nil, title: C.welcomeTitle, titleRole: .welcomeTitle, lede: C.welcomeLede,
                   ledeRole: .welcomeLede, primary: B(title: C.getStarted, identifier: AXID.Onboarding.getStarted),
                   stageLabel: C.markLabel)
    case .importData:
      let phase = flow.importPhase
      let primaryID: String = switch phase {
      case .failed: AXID.Onboarding.tryAgain
      case .imported: AXID.Onboarding.continueButton
      default: AXID.Onboarding.importData
      }
      let secondary: B? = switch phase {
      case .imported: nil
      default: B(title: C.startFresh, identifier: AXID.Onboarding.startFresh, isEnabled: phase != .importing)
      }
      return .init(step: step, eyebrow: C.importEyebrow(phase, mode: options.mode), title: C.importTitle(phase),
                   titleRole: .importTitle, lede: C.importNote(phase, mode: options.mode), ledeRole: .note,
                   extra: .counts, secondary: secondary,
                   primary: B(title: C.importPrimaryTitle(phase), identifier: primaryID,
                              isEnabled: phase != .counting && phase != .importing))
    case .theme:
      let lede = flow.themePath == .imported ? C.themeLedeImported : C.themeLedeFresh
      return .init(step: step, eyebrow: C.themeEyebrow, title: theme?.resolvedName ?? "", titleRole: .nameField,
                   lede: lede, ledeRole: .note, extra: .theme,
                   secondary: B(title: C.skip, identifier: AXID.Onboarding.skip),
                   primary: B(title: C.continueButton, identifier: AXID.Onboarding.continueButton))
    case .defaultBrowser:
      return .init(step: step, eyebrow: nil, title: C.defaultTitle, titleRole: .stepTitle,
                   lede: isPrompting ? C.defaultPrompting : C.defaultLede,
                   secondary: B(title: C.notNow, identifier: AXID.Onboarding.notNow, isEnabled: !isPrompting),
                   primary: B(title: C.makeDefault, identifier: AXID.Onboarding.makeDefault, isEnabled: !isPrompting))
    case .extensions:
      return .init(step: step, eyebrow: nil, title: C.extensionsTitle, titleRole: .stepTitle, lede: C.extensionsLede,
                   extra: .option(isOn: webStoreOn),
                   secondary: B(title: C.skip, identifier: AXID.Onboarding.skip),
                   primary: B(title: C.continueButton, identifier: AXID.Onboarding.continueButton))
    case .tour(let tip):
      let info = C.tips[tip - 1]
      let last = tip == OnboardingStep.tipCount
      return .init(step: step, eyebrow: C.tipEyebrow(tip), title: info.title, titleRole: .stepTitle, lede: info.lede,
                   ledeEmphasis: info.keys,
                   secondary: B(title: C.skipTour, identifier: AXID.Onboarding.skipTour),
                   primary: B(title: last ? C.done : C.next, identifier: AXID.Onboarding.next),
                   stageLabel: info.stageLabel)
    case .done:
      return .init(step: step, eyebrow: nil, title: C.doneTitle, titleRole: .stepTitle,
                   lede: reentry ? C.doneLedeReentry : C.doneLede,
                   primary: B(title: reentry ? C.backToBrowsing : C.startBrowsing,
                              identifier: AXID.Onboarding.startBrowsing),
                   stageLabel: C.markLabel)
    }
  }

  private func configure(_ stepView: OnboardingStepView) {
    stepView.primaryButton?.onPress = { [weak self] in self?.primary() }
    stepView.secondaryButton?.onPress = { [weak self] in self?.secondary() }
    if let countsView = stepView.countsView {
      countsView.drawsDigits = !view.stage.drawsCounts
      countsView.update(counts, state: countState, failed: flow.importPhase == .failed)
      if case .imported = flow.importPhase { countsView.landAll() } else { countsView.land(landed, reduceMotion: true) }
    }
    if stepView.nameField != nil { configureTheme(stepView) }
    stepView.option?.onToggle = { [weak self] on in self?.webStoreOn = on }
  }

  private var countState: OnboardingCopy.CountState {
    switch flow.importPhase {
    case .counting: .counting
    case .imported: .imported
    default: .ready
    }
  }

  /// The stage's shape for `stepView`, from its laid-out rects.
  private func formation(for stepView: OnboardingStepView) -> OnboardingFormation {
    let rect = stepView.convert(stepView.stageRect, to: view)
    func mark(_ size: CGFloat) -> CGRect {
      CGRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size)
    }
    switch flow.step {
    case .welcome:
      return .welcome(mark: CGRect(x: rect.minX + rect.width * 0.04, y: rect.minY + rect.height * 0.04,
                                   width: rect.width * 0.92, height: rect.height * 0.92))
    case .importData: return .counts(countFormation(stepView))
    case .theme:
      let preview = stepView.preview.map { stepView.convert($0.frame, to: view) } ?? rect
      return .theme(preview: preview, theme: theme?.resolvedTheme ?? SpaceThemeCatalog.defaultFamily.light,
                    origin: nil)
    case .defaultBrowser: return .defaultBrowser(mark: mark(150))
    case .extensions: return .extensions(mark: mark(104), rings: rect)
    case .tour(let tip): return .tour(tip: tip, stage: rect)
    case .done: return .done(mark: mark(168))
    }
  }

  private func countFormation(_ stepView: OnboardingStepView) -> OnboardingCountFormation {
    let numbers = stepView.countsView?.numberFrames().map { item in
      OnboardingCountFormation.Number(kind: item.kind, text: item.text,
                                      frame: stepView.countsView.map { $0.convert(item.frame, to: view) } ?? item.frame,
                                      fontSize: item.size)
    } ?? []
    let state: OnboardingCountFormation.State = switch flow.importPhase {
    case .counting: .counting
    case .ready: .ready
    case .importing: .importing(landed: landed)
    case .imported: .imported
    case .failed: .failed
    }
    return OnboardingCountFormation(numbers: numbers, state: state)
  }

  // MARK: - Actions

  private func primary() {
    guard !isFinished, !isAsking, !isPrompting, let action = flow.primaryAction else { return }
    switch action {
    case .getStarted, .continue, .nextTip, .finishTour:
      leaveTheme(keeping: true)
      advance()
    case .importData, .tryAgain: startImport()
    case .makeDefault: makeDefault()
    case .startBrowsing: finish(skipped: false)
    }
  }

  private func secondary() {
    guard !isFinished, !isAsking, !isPrompting, let action = flow.secondaryAction else { return }
    switch action {
    case .askSkipSetup: askSkipSetup()
    case .startFresh, .notNow, .skipExtensions:
      if action == .skipExtensions { webStoreOn = false }
      advance()
    case .skipTheme:
      leaveTheme(keeping: false)
      advance()
    case .skipTour:
      flow.skipTour()
      showStep(animated: true)
    }
  }

  private func advance() {
    flow.advance()
    showStep(animated: true)
  }

  private func back() {
    guard !isFinished, !isAsking, flow.showsBack || flow.step.kind == .tour else { return }
    let before = flow.step
    flow.back()
    guard flow.step != before else { return }
    showStep(animated: true)
  }

  private func handle(_ key: OnboardingView.Key) {
    guard !isFinished, !isAsking else { return }
    switch key {
    case .escape:
      if flow.secondaryAction != nil { secondary() }
    case .left:
      guard flow.showsBack else { return }
      back()
    case .right:
      guard flow.goForward() else { return }
      showStep(animated: true)
    }
  }

  // MARK: - Import

  private func startCountingIfNeeded() {
    guard flow.step == .importData, flow.importPhase == .counting, countTask == nil,
          flow.conditions.arc == .found else { return }
    countTask = Task { [weak self, services] in
      do {
        for try await update in services.countArcData() {
          self?.receive(update)
        }
        self?.countingFinished(failed: false)
      } catch {
        self?.countingFinished(failed: true)
      }
    }
  }

  private func receive(_ update: OnboardingCounts) {
    pendingCounts = update
    let now = ProcessInfo.processInfo.systemUptime
    if now - lastCountApply >= Self.countInterval {
      applyPendingCounts()
    } else if countTimer == nil {
      countTimer = Timer.scheduledTimer(withTimeInterval: Self.countInterval, repeats: false) { [weak self] _ in
        MainActor.assumeIsolated { self?.applyPendingCounts() }
      }
    }
  }

  private func applyPendingCounts() {
    countTimer?.invalidate()
    countTimer = nil
    guard let pending = pendingCounts else { return }
    pendingCounts = nil
    lastCountApply = ProcessInfo.processInfo.systemUptime
    counts = pending
    refreshCounts()
  }

  private func refreshCounts() {
    guard flow.step == .importData, let stepView = view.stepView, let countsView = stepView.countsView else { return }
    countsView.update(counts, state: countState, failed: flow.importPhase == .failed)
    view.stage.show(.counts(countFormation(stepView)), appearance: view.appearanceModel, animated: true)
  }

  private func countingFinished(failed: Bool) {
    applyPendingCounts()
    countTask = nil
    guard flow.importPhase == .counting else { return }
    flow.setImportPhase(failed ? .failed : .ready)
    rebuildImportStep()
    announce(failed ? OnboardingCopy.importTitle(.failed) : OnboardingCopy.foundAnnouncement(counts))
  }

  private func startImport() {
    flow.setImportPhase(.importing)
    landed = []
    rebuildImportStep()
    announce(OnboardingCopy.importStartedAnnouncement)
    Task { [weak self, services] in
      let result = await services.importArcData()
      self?.importFinished(result)
    }
  }

  private func importFinished(_ result: OnboardingImportResult) {
    switch result {
    case .imported(let skipped, let added):
      importedSpaces = added.isEmpty ? Array((window?.sidebar.spaceOrder ?? []).prefix(1)) : added
      // Per-category completion is not reported by the importer: every category lands together (M4 fallback).
      landed = Set(OnboardingCounts.Kind.allCases)
      flow.setImportPhase(.imported(skipped: skipped))
      announce(OnboardingCopy.importFinishedAnnouncement)
    case .failed:
      flow.setImportPhase(.failed)
      announce(OnboardingCopy.importTitle(.failed))
    }
    if options.mode == .firstRun { services.saveProgress(flow.snapshot) }
    if skipAfterImport {
      finish(skipped: true)
      return
    }
    rebuildImportStep()
    if case .imported = flow.importPhase { view.stepView?.countsView?.land(landed, reduceMotion: view.appearanceModel.reduceMotion) }
  }

  /// The Import step's state changed: its text crossfades (M5) while the stage keeps its shape.
  private func rebuildImportStep() {
    guard flow.step == .importData, !isFinished else { return }
    let stepView = OnboardingStepView(content: content(for: .importData), appearance: view.appearanceModel,
                                      compact: view.bounds.height < 700)
    configure(stepView)
    view.setStep(stepView, animated: true)
    stepView.showAtRest()
    if let layer = stepView.layer {
      OnboardingMotion.set { layer.opacity = 0 }
      OnboardingMotion.animate(layer, "opacity", to: Float(1), duration: 0.2)
    }
    refreshFooter(animated: true)
    view.stage.show(formation(for: stepView), appearance: view.appearanceModel, animated: true)
    view.window?.makeFirstResponder(view)
  }

  // MARK: - Make it yours

  private var systemFlavor: ThemeFlavor { view.appearanceModel.flavor }

  private func prepareTheme() {
    guard let window else { return }
    let path = flow.themePath
    if options.mode == .reentry {
      if theme == nil, let space = window.currentSpace, let info = window.sidebar.space(space) {
        theme = .current(theme: info.theme, name: info.title, appearance: systemFlavor)
      }
    } else if path == .imported, let first = importedSpaces.first ?? window.sidebar.spaceOrder.first,
              let info = window.sidebar.space(first) {
      if theme?.swatches.first?.isOwn != true {
        theme = .imported(theme: info.theme, name: info.title, appearance: systemFlavor)
      }
    } else if theme == nil || theme?.swatches.first?.isOwn == true {
      theme = .fresh(appearance: systemFlavor, placeholder: "\(ShellWindowController.newSpaceTitle) 1")
    }
    if theme == nil { theme = .fresh(appearance: systemFlavor) }
    themeOpened = theme
  }

  private func configureTheme(_ stepView: OnboardingStepView) {
    guard let theme else { return }
    stepView.title.isHidden = true                   // the name field is the headline
    stepView.nameField?.configure(name: theme.name, placeholder: theme.placeholder)
    stepView.nameField?.onChange = { [weak self] text in self?.setName(text) }
    stepView.nameField?.onRestore = { [weak self] text in self?.setName(text) }
    stepView.swatches?.configure(theme)
    stepView.swatches?.onSelect = { [weak self] index in self?.selectSwatch(index) }
    stepView.segment?.setValue(theme.appearance, animated: false)
    stepView.segment?.isEnabled = theme.isAppearanceEnabled
    stepView.segment?.onChange = { [weak self] flavor in self?.setAppearance(flavor) }
    stepView.themeName?.text = theme.selectedTitle
    stepView.preview?.configure(theme: theme.resolvedTheme, name: theme.resolvedName, animated: false)
  }

  private func setName(_ text: String) {
    theme?.name = text
    guard let theme, let stepView = view.stepView else { return }
    stepView.preview?.configure(theme: theme.resolvedTheme, name: theme.resolvedName, animated: false)
  }

  private func selectSwatch(_ index: Int) {
    theme?.select(index)
    themeChanged(origin: view.stepView?.swatches.flatMap { row in
      row.swatchViews.indices.contains(index) ? row.convert(NSPoint(x: row.swatchViews[index].frame.midX,
                                                                    y: row.swatchViews[index].frame.midY), to: view)
        : nil
    })
  }

  private func setAppearance(_ flavor: ThemeFlavor) {
    guard theme?.isAppearanceEnabled == true else { return }
    theme?.appearance = flavor
    themeChanged(origin: view.stepView?.segment.map { $0.convert(NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: view) })
  }

  /// M6: the preview crossfades, the swatch ring and the segmented thumb move, the wash changes and the stage
  /// re-tints from the pressed control (P6).
  private func themeChanged(origin: CGPoint?) {
    guard let theme, let stepView = view.stepView else { return }
    stepView.swatches?.configure(theme)
    stepView.segment?.setValue(theme.appearance, animated: true)
    stepView.segment?.isEnabled = theme.isAppearanceEnabled
    stepView.themeName?.text = theme.selectedTitle
    stepView.preview?.configure(theme: theme.resolvedTheme, name: theme.resolvedName, animated: true)
    view.setWash(theme.resolvedTheme, animated: true)
    let preview = stepView.preview.map { stepView.convert($0.frame, to: view) } ?? .zero
    view.stage.show(.theme(preview: preview, theme: theme.resolvedTheme, origin: origin),
                    appearance: view.appearanceModel, animated: true)
  }

  /// Leaving Make it yours forward: Continue keeps the choice, Skip restores what the step opened with. The Space is
  /// created (fresh path) or updated (import path, re-entry) now.
  private func leaveTheme(keeping: Bool) {
    guard flow.step == .theme, var chosen = theme, let window else { return }
    if !keeping, let opened = themeOpened {
      chosen.restore(opened)
      theme = chosen
    }
    let sidebar = window.sidebar
    switch (options.mode, flow.themePath) {
    case (.firstRun, .fresh):
      if let created = createdSpace, sidebar.space(created) != nil {
        sidebar.renameSpace(created, to: chosen.resolvedName)
      } else {
        do { createdSpace = try sidebar.addSpace(title: chosen.resolvedName) } catch {
          window.onError?(.addSpace, error)
          return
        }
      }
      if let created = createdSpace { sidebar.setTheme(created, to: chosen.resolvedTheme) }
    case (.firstRun, .imported):
      guard let first = importedSpaces.first ?? sidebar.spaceOrder.first else { return }
      if !chosen.name.trimmingCharacters(in: .whitespaces).isEmpty { sidebar.renameSpace(first, to: chosen.resolvedName) }
      if !chosen.selectedSwatch.isOwn { sidebar.setTheme(first, to: chosen.resolvedTheme) }
    case (.reentry, _):
      guard let space = window.currentSpace, keeping else { return }
      if !chosen.name.trimmingCharacters(in: .whitespaces).isEmpty { sidebar.renameSpace(space, to: chosen.resolvedName) }
      if !chosen.selectedSwatch.isOwn { sidebar.setTheme(space, to: chosen.resolvedTheme) }
    }
  }

  // MARK: - Default browser

  private func makeDefault() {
    isPrompting = true
    showStepContentInPlace()
    Task { [weak self, services] in
      await services.makeDefaultBrowser()
      guard let self, !self.isFinished else { return }
      self.isPrompting = false
      if self.flow.step == .defaultBrowser { self.advance() }
    }
  }

  /// Rebuilds the current step's text without the step-change motion (the prompt note).
  private func showStepContentInPlace() {
    let stepView = OnboardingStepView(content: content(for: flow.step), appearance: view.appearanceModel,
                                      compact: view.bounds.height < 700)
    configure(stepView)
    view.setStep(stepView, animated: false)
    stepView.showAtRest()
  }

  // MARK: - Skip setup (6.9)

  private func askSkipSetup() {
    guard !isFinished, !isAsking, flow.showsSkipSetup else { return }
    isAsking = true
    let responder = view.window?.firstResponder
    let answer: @MainActor (Bool) -> Void = { [weak self] confirmed in
      guard let self else { return }
      self.isAsking = false
      if confirmed {
        self.skipConfirmed()
      } else {
        self.view.window?.makeFirstResponder(responder ?? self.view)
      }
    }
    if let confirmSkip {
      confirmSkip(answer)
      return
    }
    guard let sheetWindow = view.window else {
      answer(false)
      return
    }
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = OnboardingCopy.skipTitle
    alert.informativeText = OnboardingCopy.skipMessage
    alert.addButton(withTitle: OnboardingCopy.skipConfirm)
    let cancel = alert.addButton(withTitle: OnboardingCopy.cancel)
    cancel.keyEquivalent = "\u{1b}"
    alert.beginSheetModal(for: sheetWindow) { response in
      MainActor.assumeIsolated { answer(response == .alertFirstButtonReturn) }
    }
  }

  /// Confirmed: a theme preview is dropped; with no import a fresh "Space 1" in Dune; during an import the import
  /// finishes first (no Space is added); after one the browser opens on the first imported Space.
  private func skipConfirmed() {
    if flow.step == .theme, let opened = themeOpened { theme = opened }
    view.setWash(nil, animated: true)
    if flow.importPhase == .importing {
      skipAfterImport = true
      return
    }
    finish(skipped: true)
  }

  // MARK: - Finish (M8, P9)

  /// Start browsing, a confirmed Skip setup, or Back to browsing on re-entry.
  private func finish(skipped: Bool) {
    guard !isFinished, let window else { return }
    isFinished = true
    countTask?.cancel()
    countTimer?.invalidate()
    let signpost = ShellSignposts.signposter.beginInterval("onboarding.finish")
    if options.mode == .firstRun { services.markCompleted() }
    let landing = landingSpace(skipped: skipped, window: window)
    let reduceMotion = view.appearanceModel.reduceMotion
    view.stepView?.conceal(duration: 0.16)
    view.setFooter(showsBack: false, progress: nil, showsSkip: false, animated: true)
    let card = window.rootView.convert(window.rootView.card.frame, to: view)
    view.stage.finish(onto: card, appearance: view.appearanceModel) {}
    hideBrowser(false)
    if options.mode == .firstRun { land(on: landing, window: window) }
    let reveal: CFTimeInterval = reduceMotion ? 0 : 0.65
    DispatchQueue.main.asyncAfter(deadline: .now() + reveal) { [weak self] in
      guard let self, let layer = self.view.layer else { return }
      OnboardingMotion.animate(layer, "opacity", to: Float(0), duration: reduceMotion ? 0 : 0.24)
    }
    let commandBarDelay: CFTimeInterval = reduceMotion ? 0.05 : 0.9
    DispatchQueue.main.asyncAfter(deadline: .now() + commandBarDelay) { [weak self] in
      guard let self else { return }
      self.view.removeFromSuperview()
      if self.options.mode == .firstRun, !self.webStoreOn {
        window.window?.makeFirstResponder(nil)
        window.commandBar.toggle(.currentTab(nil))
        self.announce(OnboardingCopy.finishedAnnouncement)
      } else {
        self.announce(OnboardingCopy.finishedReentryAnnouncement)
      }
      ShellSignposts.signposter.endInterval("onboarding.finish", signpost)
      window.onboardingDidFinish()
      self.onFinish?()
    }
  }

  private func landingSpace(skipped: Bool, window: ShellWindowController) -> SpaceID? {
    let sidebar = window.sidebar
    if case .imported = flow.importPhase, let first = importedSpaces.first ?? sidebar.spaceOrder.first {
      return first
    }
    if let created = createdSpace, sidebar.space(created) != nil { return created }
    guard options.mode == .firstRun else { return window.currentSpace }
    if let existing = sidebar.spaceOrder.first { return existing }
    // No import ran and Make it yours never created one: a fresh "Space 1" in Dune.
    do {
      let space = try sidebar.addSpace(title: "\(ShellWindowController.newSpaceTitle) 1")
      sidebar.setTheme(space, to: SpaceThemeCatalog.defaultFamily.theme(systemFlavor))
      return space
    } catch {
      window.onError?(.addSpace, error)
      return nil
    }
  }

  /// The browser on the landing Space: a current "New Tab" Today row with the command bar opening over it, or the
  /// Chrome Web Store as the first tab when that option was on.
  private func land(on space: SpaceID?, window: ShellWindowController) {
    guard let space else { return }
    window.sidebarController.showSpace(space)
    let url = webStoreOn ? options.webStoreURL : ShellWindowController.blankPage
    let title = webStoreOn ? "Chrome Web Store" : "New Tab"
    do {
      let node = try window.sidebar.addTab(url: url, title: title, in: .today(space), at: 0)
      window.activate(node: node)
    } catch {
      window.onError?(.addTab, error)
    }
  }

  /// Hides the browser's views from VoiceOver and the key loop while the overlay covers them; shows them again for
  /// M8. The page stays loaded.
  private func hideBrowser(_ hide: Bool) {
    guard let root = window?.rootView else { return }
    if hide {
      browserViews = [root.sidebarContainer, root.card, root.split].map { ($0, $0.isHidden) }
      for (view, _) in browserViews { view.isHidden = true }
    } else {
      for (view, wasHidden) in browserViews { view.isHidden = wasHidden }
      browserViews = []
    }
  }

  private func announce(_ text: String) {
    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                         userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
  }

  // MARK: - System changes

  /// The window's appearance or an accessibility display option changed: the current step is drawn again at rest.
  func appearanceChanged(_ appearance: OnboardingAppearance) {
    guard !isFinished, appearance != view.appearanceModel else { return }
    view.appearanceModel = appearance
    showStepContentInPlace()
    view.stage.show(view.stepView.map(formation(for:)) ?? .none, appearance: appearance, animated: false)
    view.setWash(flow.step == .theme ? theme?.resolvedTheme : nil, animated: false)
    refreshFooter(animated: false)
  }

  /// Occluded, miniaturized or hidden: the stage draws no frames.
  func windowVisibilityChanged(_ visible: Bool) {
    view.stage.setVisible(visible)
  }

  // MARK: - Test seams

  /// Presses the step's primary button as Return would.
  public func performPrimary() { primary() }
  /// Runs the step's secondary action as Escape would.
  public func performEscape() { handle(.escape) }
  public func performBack() { back() }
  public func performRight() { handle(.right) }
}
