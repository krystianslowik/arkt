import Foundation

/// The first run (`firstRun`), or Help > Welcome to Arkt over a window that already has Spaces (`reentry`, onboarding
/// spec section 12).
public enum OnboardingMode: String, Sendable, Codable {
  case firstRun, reentry
}

/// One screen of the flow. The tour is one step of five tips.
public enum OnboardingStep: Hashable, Sendable {
  case welcome, importData, theme, defaultBrowser, extensions
  case tour(tip: Int)
  case done

  public static let tipCount = 5

  /// The step in the step list, tips folded into `.tour`.
  public enum Kind: Int, CaseIterable, Sendable, Comparable {
    case welcome, importData, theme, defaultBrowser, extensions, tour, done
    public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }

    var firstStep: OnboardingStep {
      switch self {
      case .welcome: .welcome
      case .importData: .importData
      case .theme: .theme
      case .defaultBrowser: .defaultBrowser
      case .extensions: .extensions
      case .tour: .tour(tip: 1)
      case .done: .done
      }
    }
  }

  public var kind: Kind {
    switch self {
    case .welcome: .welcome
    case .importData: .importData
    case .theme: .theme
    case .defaultBrowser: .defaultBrowser
    case .extensions: .extensions
    case .tour: .tour
    case .done: .done
    }
  }

  /// A stable name for saving the step and for accessibility identifiers: "welcome", "import", "theme", "default",
  /// "extensions", "tour-1" ... "tour-5", "done".
  public var identifier: String {
    switch self {
    case .welcome: "welcome"
    case .importData: "import"
    case .theme: "theme"
    case .defaultBrowser: "default"
    case .extensions: "extensions"
    case .tour(let tip): "tour-\(tip)"
    case .done: "done"
    }
  }

  public init?(identifier: String) {
    switch identifier {
    case "welcome": self = .welcome
    case "import": self = .importData
    case "theme": self = .theme
    case "default": self = .defaultBrowser
    case "extensions": self = .extensions
    case "done": self = .done
    default:
      guard identifier.hasPrefix("tour-"), let tip = Int(identifier.dropFirst(5)),
            (1...Self.tipCount).contains(tip) else { return nil }
      self = .tour(tip: tip)
    }
  }
}

/// The five states of the Import step (section 6.2).
public enum OnboardingImportPhase: Hashable, Sendable {
  case counting, ready, importing
  /// `skipped`: items that could not be imported (the note mentions them only when there are some).
  case imported(skipped: Int)
  case failed
}

/// The first-run flow as a value (sections 2, 10 and 13): which steps the branch has, where the user is, what the
/// footer shows, what Return and Escape do, the arrow keys' history and the snapshot saved for resume. It decides
/// nothing about the system: the controller feeds it the Arc check, the import state and the default-browser check.
public struct OnboardingFlow: Equatable, Sendable {
  public enum ArcAvailability: Sendable, Equatable {
    /// The existence check has not answered yet: Import is shown counting.
    case checking, found, notFound
  }

  public struct Conditions: Equatable, Sendable {
    public var arc: ArcAvailability
    public var isDefaultBrowser: Bool
    /// The Chromium engine configuration only.
    public var includesExtensions: Bool
    public var mode: OnboardingMode

    public init(arc: ArcAvailability, isDefaultBrowser: Bool, includesExtensions: Bool, mode: OnboardingMode) {
      self.arc = arc; self.isDefaultBrowser = isDefaultBrowser
      self.includesExtensions = includesExtensions; self.mode = mode
    }
  }

  /// "{index} of {total}" in the footer: the steps after Welcome on the current branch, the tour counted once.
  public struct Progress: Equatable, Sendable {
    public var index: Int
    public var total: Int
  }

  /// What Return does (the default button). Nil while the primary button is disabled.
  public enum PrimaryAction: Equatable, Sendable {
    case getStarted, importData, tryAgain, `continue`, makeDefault, nextTip, finishTour, startBrowsing
  }

  /// What Escape and the secondary button do. Nil where Escape does nothing.
  public enum SecondaryAction: Equatable, Sendable {
    case askSkipSetup, startFresh, skipTheme, notNow, skipExtensions, skipTour
  }

  /// Which version of Make it yours the step shows.
  public enum ThemePath: Equatable, Sendable { case fresh, imported }

  public private(set) var conditions: Conditions
  public private(set) var step: OnboardingStep = .welcome
  public private(set) var importPhase: OnboardingImportPhase = .counting
  /// Steps left with Back (or Left), most recent last; Right returns to them. Moving on any other way clears it.
  private var forward: [OnboardingStep] = []

  public init(conditions: Conditions) {
    self.conditions = conditions
  }

  // MARK: - Step list

  /// The steps after Welcome on this branch, in order.
  public var kinds: [OnboardingStep.Kind] {
    var kinds: [OnboardingStep.Kind] = []
    if conditions.arc != .notFound { kinds.append(.importData) }
    kinds.append(.theme)
    if !conditions.isDefaultBrowser { kinds.append(.defaultBrowser) }
    if conditions.includesExtensions { kinds.append(.extensions) }
    kinds += [.tour, .done]
    return kinds
  }

  public var progress: Progress? {
    guard let index = kinds.firstIndex(of: step.kind) else { return nil }
    return Progress(index: index + 1, total: kinds.count)
  }

  public var themePath: ThemePath {
    if case .imported = importPhase { return .imported }
    return .fresh
  }

  // MARK: - Footer

  /// Back is hidden on Welcome, on the first step after it, on Done and while importing. Hidden pieces keep their
  /// place.
  public var showsBack: Bool {
    guard step != .welcome, step != .done, step.kind != kinds.first else { return false }
    if step == .importData, importPhase == .importing { return false }
    return true
  }

  public var showsSkipSetup: Bool { step != .done }
  public var showsProgress: Bool { step != .welcome && step != .done }
  public var canGoForward: Bool { !forward.isEmpty }

  // MARK: - Actions

  public var primaryAction: PrimaryAction? {
    switch step {
    case .welcome: return .getStarted
    case .importData:
      switch importPhase {
      case .counting, .importing: return nil
      case .ready: return .importData
      case .imported: return .continue
      case .failed: return .tryAgain
      }
    case .theme, .extensions: return .continue
    case .defaultBrowser: return .makeDefault
    case .tour(let tip): return tip < OnboardingStep.tipCount ? .nextTip : .finishTour
    case .done: return .startBrowsing
    }
  }

  public var secondaryAction: SecondaryAction? {
    switch step {
    case .welcome: return .askSkipSetup
    case .importData:
      switch importPhase {
      case .counting, .ready, .failed: return .startFresh
      case .importing, .imported: return nil
      }
    case .theme: return .skipTheme
    case .defaultBrowser: return .notNow
    case .extensions: return .skipExtensions
    case .tour: return .skipTour
    case .done: return nil
    }
  }

  // MARK: - Moving

  /// Moves on to the next step (or tip): every primary and secondary action that leaves the step. Clears the Right
  /// arrow's history.
  public mutating func advance() {
    forward = []
    step = next(after: step)
  }

  /// Skip tour: straight to Done.
  public mutating func skipTour() {
    forward = []
    step = .done
  }

  /// Back and the Left arrow: the previous tip, else the previous step. Nothing before the first step after Welcome.
  public mutating func back() {
    guard let previous = previous(before: step) else { return }
    forward.append(step)
    step = previous
  }

  /// The Right arrow: back to the step left with Back, never a new one. False when there is none.
  @discardableResult
  public mutating func goForward() -> Bool {
    while let next = forward.popLast() {
      guard kinds.contains(next.kind) else { continue }
      step = next
      return true
    }
    return false
  }

  /// Sets the step directly (resume, tests).
  public mutating func jump(to step: OnboardingStep) {
    forward = []
    self.step = step
  }

  public mutating func setImportPhase(_ phase: OnboardingImportPhase) {
    importPhase = phase
  }

  /// The Arc check answered. "No Arc" while Import is shown replaces it with Make it yours (a normal step change).
  public mutating func setArc(_ availability: ArcAvailability) {
    conditions.arc = availability
    dropForwardStepsLeftOut()
    if availability == .notFound, step == .importData { step = .theme }
  }

  public mutating func setDefaultBrowser(_ isDefault: Bool) {
    conditions.isDefaultBrowser = isDefault
    dropForwardStepsLeftOut()
  }

  private mutating func dropForwardStepsLeftOut() {
    let kinds = kinds
    forward.removeAll { !kinds.contains($0.kind) }
  }

  private func next(after step: OnboardingStep) -> OnboardingStep {
    if case .tour(let tip) = step, tip < OnboardingStep.tipCount { return .tour(tip: tip + 1) }
    if step == .done { return .done }
    return kinds.first { $0 > step.kind }?.firstStep ?? .done
  }

  private func previous(before step: OnboardingStep) -> OnboardingStep? {
    if case .tour(let tip) = step, tip > 1 { return .tour(tip: tip - 1) }
    guard let index = kinds.firstIndex(of: step.kind), index > 0 else { return nil }
    let kind = kinds[index - 1]
    return kind == .tour ? .tour(tip: OnboardingStep.tipCount) : kind.firstStep
  }

  // MARK: - Resume (section 13)

  /// What is saved as the user moves on: the step, and whether the import finished (a finished import stays
  /// imported). Counts only; nothing names user data.
  public struct Snapshot: Codable, Equatable, Sendable {
    public var step: String
    public var imported: Bool
    public var importSkipped: Int

    public init(step: String, imported: Bool, importSkipped: Int) {
      self.step = step; self.imported = imported; self.importSkipped = importSkipped
    }
  }

  public var snapshot: Snapshot {
    if case .imported(let skipped) = importPhase {
      return Snapshot(step: step.identifier, imported: true, importSkipped: skipped)
    }
    return Snapshot(step: step.identifier, imported: false, importSkipped: 0)
  }

  /// Resumes at the saved step (or the next step of this branch when it is left out now), without the Welcome
  /// reveal. An import that did not finish counts again.
  public init(resuming snapshot: Snapshot, conditions: Conditions) {
    self.conditions = conditions
    if snapshot.imported { importPhase = .imported(skipped: snapshot.importSkipped) }
    guard let saved = OnboardingStep(identifier: snapshot.step), saved != .welcome else { return }
    if kinds.contains(saved.kind) {
      step = saved
    } else {
      step = kinds.first { $0 > saved.kind }?.firstStep ?? .done
    }
  }
}
