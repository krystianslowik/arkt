import Foundation

// What the views draw for a `BrowserDataImportState`: the title and the lede, the two groups of rows, the overall
// progress, the notices and the buttons. Copy follows design/browser-data-import (direction B); it never names the
// other browser.

public struct BrowserDataImportRow: Equatable, Sendable, Identifiable {
  public enum Leading: Equatable, Sendable {
    /// Consent: a checkbox; `isEnabled` is false for a type with nothing to import.
    case checkbox(isOn: Bool, isEnabled: Bool)
    case done, working, waiting, skipped, notImported
  }

  public var kind: BrowserDataKind
  public var title: String
  /// "in 4 Spaces", or how many items were refused.
  public var detail: String?
  /// The trailing text: a count, "30,854 of 48,210", "Waiting", "Not imported".
  public var value: String
  public var leading: Leading
  /// Drawn in the secondary color: nothing to import, not reached, not chosen or not imported.
  public var isDimmed: Bool
  /// A bar under the name while the row works, from 0 to 1; nil: no bar.
  public var barFraction: Double?
  public var accessibilityLabel: String
  /// Read as the checkbox's description.
  public var accessibilityDescription: String?

  public var id: BrowserDataKind { kind }
}

public struct BrowserDataImportNotice: Equatable, Sendable {
  public enum Symbol: Equatable, Sendable { case lock, exclamation }
  public var symbol: Symbol
  /// The text; `emphasis` is the part of it drawn heavier.
  public var text: String
  public var emphasis: String?
}

public struct BrowserDataImportGroup: Equatable, Sendable {
  public var heading: String
  public var rows: [BrowserDataImportRow]
  public var notice: BrowserDataImportNotice?
}

public struct BrowserDataImportButton: Equatable, Sendable {
  public enum Action: Equatable, Sendable { case importData, cancel, done, retry }
  public var action: Action
  public var title: String
  public var isEnabled: Bool
}

public struct BrowserDataImportOverall: Equatable, Sendable {
  /// "Importing history", "Waiting for macOS".
  public var label: String
  /// "1 of 5 done".
  public var trailing: String
  public var fraction: Double
}

extension BrowserDataImportState {
  // MARK: - Facts

  /// The kinds the user may tick: the ones with something in them.
  public var availableKinds: [BrowserDataKind] { BrowserDataKind.allCases.filter { counts[$0] > 0 } }

  /// Every type counted zero.
  public var isNothingToImport: Bool { availableKinds.isEmpty }

  /// What Import would run.
  public var effectiveSelection: Set<BrowserDataKind> { selection.filter { counts[$0] > 0 } }

  public var canImport: Bool { phase == .consent && !effectiveSelection.isEmpty }

  /// The pre-prompt line: while consent has cookies or passwords ticked, and while a Retry waits on the prompt.
  public var showsKeychainLine: Bool {
    switch phase {
    case .consent: effectiveSelection.contains { $0.needsPassword }
    case .progress:
      isRetry && BrowserDataKind.passwordKinds.contains { kind in
        switch rows[kind] {
        case .waiting?, .waitingForMac?, .working?: true
        default: false
        }
      }
    default: false
    }
  }

  private func status(_ kind: BrowserDataKind) -> BrowserDataRowStatus { rows[kind] ?? .idle }

  private func isTerminal(_ status: BrowserDataRowStatus) -> Bool {
    switch status {
    case .imported, .stopped, .notImported: true
    default: false
    }
  }

  /// The kinds whose Keychain read macOS refused.
  public var deniedKinds: [BrowserDataKind] {
    BrowserDataKind.passwordKinds.filter { status($0) == .notImported(.keychainDenied) }
  }

  private var importedKinds: [BrowserDataKind] {
    BrowserDataKind.allCases.filter { if case .imported = status($0) { true } else { false } }
  }

  private var notImportedKinds: [BrowserDataKind] {
    BrowserDataKind.allCases.filter {
      switch status($0) {
      case .notImported, .stopped: true
      default: false
      }
    }
  }

  private var isPartial: Bool { !notImportedKinds.isEmpty }

  // MARK: - Copy

  private static let stays = "Your other browser stays as it is."

  /// The sheet's title.
  public var title: String {
    switch phase {
    case .counting: "Import browser data"
    case .consent: isNothingToImport ? "Nothing to import" : "Import browser data"
    case .progress: "Importing your browser data"
    case .result, .dismissed:
      if result.couldNotRead { "Nothing came over" } else if result.cancelled { "Import stopped" } else { "Import finished" }
    }
  }

  /// The sheet's subtitle.
  public var subtitle: String {
    switch phase {
    case .counting: "Checking what your other browser has."
    case .consent:
      isNothingToImport ? "Your other browser has nothing Arkt can bring over."
        : "Choose what to bring into Arkt. \(Self.stays)"
    case .progress: isStopping ? "Stopping after the batch being written." : Self.stays
    case .result, .dismissed:
      if result.couldNotRead { "Arkt couldn't read your other browser's data." }
      else if result.cancelled { "What already came over stays." }
      else if importedKinds.isEmpty { "None of it came over." }
      else if isPartial { "Most of it came over." }
      else { "Everything you chose came over." }
    }
  }

  /// The Hero entry's headline.
  public var heroTitle: String {
    switch phase {
    case .counting: "Looking it over."
    case .consent: isNothingToImport ? "Nothing to import." : "Choose what comes over."
    case .progress: "Bringing it over."
    case .result, .dismissed:
      if result.couldNotRead { "Nothing came over." }
      else if result.cancelled { "What came over stays." }
      else if isPartial { importedKinds.isEmpty ? "None of it came over." : "Most of it came over." }
      else { "Your setup is here." }
    }
  }

  /// The Hero entry's lede.
  public var heroLede: String {
    switch phase {
    case .counting: "Checking what your other browser has."
    case .consent: isNothingToImport ? "Your other browser has nothing Arkt can bring over." : Self.stays
    default: Self.stays
    }
  }

  /// The small line over the Hero headline.
  public var heroEyebrow: String {
    switch phase {
    case .counting, .consent: "Your browser data"
    case .progress: "Importing"
    case .result, .dismissed: result.couldNotRead ? "Not imported" : "Imported"
    }
  }

  // MARK: - Groups

  public var groups: [BrowserDataImportGroup] {
    switch phase {
    case .counting, .consent: tierGroups(headings: ("Ready to import", "Needs your Mac password"))
    case .progress: tierGroups(headings: ("No password needed", "Needs your Mac password"))
    case .result, .dismissed: resultGroups
    }
  }

  private func tierGroups(headings: (String, String)) -> [BrowserDataImportGroup] {
    let keychain = showsKeychainLine ? Self.keychainNotice : nil
    return [
      BrowserDataImportGroup(heading: headings.0, rows: BrowserDataKind.readyKinds.map(row), notice: nil),
      BrowserDataImportGroup(heading: headings.1, rows: BrowserDataKind.passwordKinds.map(row), notice: keychain),
    ]
  }

  public static let keychainNotice = BrowserDataImportNotice(
    symbol: .lock,
    text: "Next, macOS will ask to let Arkt read your other browser's saved logins. Choose Allow, not Always Allow, "
      + "so this is a one-time permission.",
    emphasis: "Choose Allow, not Always Allow")

  private var resultGroups: [BrowserDataImportGroup] {
    var groups: [BrowserDataImportGroup] = []
    let imported = importedKinds.map(row)
    if !imported.isEmpty { groups.append(BrowserDataImportGroup(heading: "Imported", rows: imported, notice: nil)) }
    let missed = notImportedKinds.map(row)
    if !missed.isEmpty { groups.append(BrowserDataImportGroup(heading: "Not imported", rows: missed, notice: missedNotice)) }
    return groups
  }

  /// The reason under the Not imported rows: the denied Keychain, naming only what was ticked, or a failed read.
  private var missedNotice: BrowserDataImportNotice? {
    let denied = deniedKinds
    if !denied.isEmpty {
      let lead: String = switch (denied.contains(.passwords), denied.contains(.cookies)) {
      case (true, true): "Passwords and cookies weren't imported."
      case (true, false): "Passwords weren't imported."
      default: "Cookies weren't imported."
      }
      return BrowserDataImportNotice(
        symbol: .exclamation,
        text: "\(lead) macOS didn't let Arkt read your other browser's saved logins. Retry asks again.", emphasis: lead)
    }
    let unreadable = BrowserDataKind.allCases.contains { status($0) == .notImported(.unreadable) }
    guard unreadable else { return nil }
    let lead = "Some of it couldn't be read."
    return BrowserDataImportNotice(symbol: .exclamation, text: "\(lead) Retry tries again.", emphasis: lead)
  }

  // MARK: - Rows

  private func row(_ kind: BrowserDataKind) -> BrowserDataImportRow {
    let count = counts[kind]
    let countText = BrowserDataNumberFormat.text(count, locale: locale)
    let note = kind.needsPassword ? "Needs your Mac password" : nil
    var detail = kind == .spacesAndTabs && counts.spaces > 0 ? "in \(BrowserDataNumberFormat.spaces(counts.spaces, locale: locale))" : nil
    let status = status(kind)
    var value: String
    let leading: BrowserDataImportRow.Leading
    var dimmed = false
    var bar: Double?
    var label: String
    var description: String?

    switch (phase, status) {
    case (.counting, _), (.consent, _):
      let isOn = selection.contains(kind) && count > 0
      leading = .checkbox(isOn: isOn, isEnabled: count > 0 && phase == .consent)
      value = phase == .counting ? "" : countText
      dimmed = count == 0 || phase == .counting
      label = phase == .counting ? kind.title : "\(kind.title), \(countText)"
      description = note
    default:
      switch status {
      case .idle, .waiting:
        leading = .waiting; value = "Waiting"; dimmed = true
        label = "\(kind.title), waiting"
      case .waitingForMac:
        leading = .waiting; value = "Waiting for macOS"; dimmed = true
        label = "\(kind.title), waiting for macOS"
      case .working(let done, let total):
        leading = .working
        value = total > 0 ? BrowserDataNumberFormat.progress(done: done, total: total, locale: locale) : "Starting"
        bar = total > 0 ? min(1, max(0, Double(done) / Double(total))) : 0
        label = "\(kind.title), \(value)"
      case .imported(let imported, let failed):
        leading = .done
        value = BrowserDataNumberFormat.text(imported, locale: locale)
        if failed > 0 {
          let refused = "\(BrowserDataNumberFormat.text(failed, locale: locale)) couldn't be imported"
          detail = detail.map { "\($0), \(refused)" } ?? refused
        }
        bar = phase == .progress ? 1 : nil
        label = "\(kind.title), \(value), imported" + (failed > 0 ? ", \(BrowserDataNumberFormat.text(failed, locale: locale)) couldn't be imported" : "")
      case .skipped:
        leading = .skipped; value = "Skipped"; dimmed = true
        label = "\(kind.title), skipped"
      case .stopped:
        leading = .skipped; value = "Skipped"; dimmed = true
        label = "\(kind.title), skipped"
      case .notImported:
        leading = .notImported; value = "Not imported"; dimmed = true
        label = "\(kind.title), not imported"
      }
    }
    return BrowserDataImportRow(kind: kind, title: kind.title, detail: detail, value: value, leading: leading,
                                isDimmed: dimmed, barFraction: bar, accessibilityLabel: label,
                                accessibilityDescription: description)
  }

  // MARK: - Progress

  public var overall: BrowserDataImportOverall {
    let chosen = BrowserDataKind.allCases.filter { selection.contains($0) }
    let finished = chosen.filter { isTerminal(status($0)) }.count
    var sum = 0.0
    var current: String?
    var waitingForMac = false
    for kind in chosen {
      switch status(kind) {
      case .working(let done, let total):
        sum += total > 0 ? min(1, max(0, Double(done) / Double(total))) : 0
        current = current ?? "Importing \(kind.title.lowercased())"
      case .waitingForMac: waitingForMac = true
      case let status where isTerminal(status): sum += 1
      default: break
      }
    }
    let label = waitingForMac ? "Waiting for macOS" : (current ?? (finished == chosen.count ? "Finishing" : "Getting ready"))
    return BrowserDataImportOverall(
      label: label, trailing: "\(finished) of \(chosen.count) done",
      fraction: chosen.isEmpty ? 0 : sum / Double(chosen.count))
  }

  /// "Cancel keeps what has already come over." under the rows while importing.
  public var footnote: String? {
    phase == .progress ? (isStopping ? "Stopping after the batch being written." : "Cancel keeps what has already come over.") : nil
  }

  // MARK: - Buttons

  /// The primary (mustard) button; nil while importing, where Cancel is the only one.
  public var primaryButton: BrowserDataImportButton? {
    switch phase {
    case .counting: BrowserDataImportButton(action: .importData, title: "Import", isEnabled: false)
    case .consent: BrowserDataImportButton(action: .importData, title: "Import", isEnabled: canImport)
    case .progress, .dismissed: nil
    case .result:
      result.canRetry ? BrowserDataImportButton(action: .retry, title: "Retry", isEnabled: true)
        : BrowserDataImportButton(action: .done, title: "Done", isEnabled: true)
    }
  }

  /// The quiet button: Cancel, Done after a Retry offer. The Hero entry's consent answers "Not now" and its result
  /// "Continue".
  public func secondaryButton(hero: Bool = false) -> BrowserDataImportButton? {
    switch phase {
    case .counting, .consent: BrowserDataImportButton(action: .cancel, title: hero ? "Not now" : "Cancel", isEnabled: true)
    case .progress: BrowserDataImportButton(action: .cancel, title: "Cancel", isEnabled: !isStopping)
    case .result: result.canRetry ? BrowserDataImportButton(action: .done, title: hero ? "Continue" : "Done", isEnabled: true) : nil
    case .dismissed: nil
    }
  }

  /// The primary's title in the Hero entry, where finishing is "Continue".
  public func heroPrimaryButton() -> BrowserDataImportButton? {
    guard var button = primaryButton else { return nil }
    if button.action == .done { button.title = "Continue" }
    return button
  }

  // MARK: - VoiceOver

  /// What VoiceOver announces for the change from `old` to `self`: the phase, a type finishing, or the Keychain wait.
  /// Never one per count.
  public func announcement(after old: BrowserDataImportState?) -> String? {
    if old?.phase != phase {
      switch phase {
      case .counting, .dismissed: return nil
      case .consent: return isNothingToImport ? "Nothing to import" : "Choose what to import"
      case .progress: return "Importing your browser data"
      case .result:
        let notice = groups.compactMap(\.notice).first?.text
        return ["\(title).", subtitle, notice].compactMap { $0 }.joined(separator: " ")
      }
    }
    guard phase == .progress, let old else { return nil }
    func isImported(_ status: BrowserDataRowStatus?) -> Bool {
      if case .imported? = status { true } else { false }
    }
    for kind in BrowserDataKind.allCases where isImported(rows[kind]) && !isImported(old.rows[kind]) {
      return "\(kind.title) imported"
    }
    let wasWaiting = old.rows.values.contains(.waitingForMac)
    if !wasWaiting && rows.values.contains(.waitingForMac) { return "Waiting for macOS" }
    return nil
  }
}

// MARK: - The seam

/// What the sheet and the Hero view drive. CoreBridge's `BrowserDataImportModel` is the app's implementation.
@MainActor
public protocol BrowserDataImportSource: AnyObject {
  var state: BrowserDataImportState { get }
  /// Called after every change of `state`; the view sets it.
  var onChange: (@MainActor () -> Void)? { get set }
  /// Called once when the flow ends with the Spaces it added (the first run lands on the first), and how many Arc
  /// sidebar items could not be imported.
  var onFinish: (@MainActor (BrowserDataImportOutcome) -> Void)? { get set }
  /// Begins the snapshot and the count; the state moves to consent.
  func start()
  func setSelected(_ kind: BrowserDataKind, _ isOn: Bool)
  /// Import: runs what is ticked.
  func beginImport()
  /// Cancel: closes the consent, or stops the run after the batch being written (what came over stays).
  func cancel()
  /// Retry: runs only the types that failed.
  func retry()
  /// Done or Continue: closes the result.
  func finish()
}

/// How a flow ended, for the first run: whether anything came over, and the Spaces added.
public struct BrowserDataImportOutcome: Equatable, Sendable {
  /// At least one type came over.
  public var importedAnything: Bool
  public var skippedSidebarItems: Int
  public var addedSpaces: [SpaceID]

  public init(importedAnything: Bool, skippedSidebarItems: Int = 0, addedSpaces: [SpaceID] = []) {
    self.importedAnything = importedAnything
    self.skippedSidebarItems = skippedSidebarItems
    self.addedSpaces = addedSpaces
  }
}
