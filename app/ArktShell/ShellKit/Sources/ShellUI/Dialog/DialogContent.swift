import Foundation
import Motion
import QuartzCore

/// What a dialog says and asks (docs/design/alerts-sheets-toasts.md, section 3.1): the shell's twin of the engine's
/// `ArktDialogSheetContent`, so Delete Space, the launch alerts and later confirmations share one look with the
/// engine's prompts. One content model, three hosts (`DialogSheet`, `DialogPanel`, `DialogAlert`).
///
/// Not mirrored from the engine model, because no shell dialog uses it yet: the checkbox. The text field and the
/// capped, scrolling body are for a page's `prompt()` and long `alert()` messages (#400); stacked buttons, a neutral
/// primary, Escape dismissing and the input protection are for a site's permission request (#400).
public struct DialogContent: Equatable, Sendable {
  public enum Icon: Equatable, Sendable {
    case none
    /// The plain app icon at 56 pt, no badge, its clear space kept (decision 5).
    case appIcon
    /// A Space's theme swatch (its gradient stops) with its mark: the Space Delete Space removes.
    case spaceSwatch(colors: [RGBA], isDark: Bool, mark: SpaceIconInfo?)
    /// A neutral tile with an SF Symbol: the dangerous-file sheet's warning.
    case symbol(String)
  }

  /// Where the icon sits: beside the title (32 pt, body indented under the title) or stacked above it (the app-modal
  /// alert, as in system alerts).
  public enum IconPlacement: Equatable, Sendable { case beside, stacked }

  public struct Paragraph: Equatable, Sendable {
    public var text: String
    /// Drawn in `secondaryText` (a counts line, an error code).
    public var isSecondary: Bool

    public init(_ text: String, secondary: Bool = false) {
      self.text = text
      isSecondary = secondary
    }
  }

  /// The button Return presses; `.none`: Return presses nothing.
  public enum DefaultButton: Equatable, Sendable { case none, primary, cancel }

  /// How a dialog was answered.
  public enum Answer: Equatable, Sendable { case primary, secondary, cancel }

  /// A one-line text field under the body (a page's `prompt()`); focus starts in it, with its text selected.
  public struct Input: Equatable, Sendable {
    public var text: String
    /// What VoiceOver calls the field.
    public var accessibilityLabel: String

    public init(text: String, accessibilityLabel: String) {
      self.text = text
      self.accessibilityLabel = accessibilityLabel
    }
  }

  public var title: String
  public var icon: Icon
  public var iconPlacement: IconPlacement
  public var subtitle: String?
  public var paragraphs: [Paragraph]
  public var listHeading: String?
  public var listItems: [String]
  /// A quiet text link at the footer's leading edge (Show Data Folder); it does not answer the dialog.
  public var footerLink: String?
  /// The footer link is a quiet red text link (Keep Anyway), not the neutral one.
  public var footerLinkIsDestructive: Bool
  /// The answer that continues, on the trailing edge: mustard, or a quiet red title when `isDestructive`.
  public var primaryTitle: String
  /// A third answer between cancel and primary.
  public var secondaryTitle: String?
  public var cancelTitle: String?
  public var defaultButton: DefaultButton
  /// A neutral pill with a `destructiveText` title, never the Return key.
  public var isDestructive: Bool
  /// Escape answers cancel (or dismisses when there is no cancel button).
  public var escapeAnswersCancel: Bool
  /// VoiceOver help on the primary button ("Deletes the Space").
  public var primaryHelp: String?
  public var width: CGFloat
  public var input: Input?
  /// The body (all paragraphs) scrolls inside this height when it needs more; nil: it takes the height it needs.
  public var bodyMaxHeight: CGFloat?
  /// Full-width pills one above the other, primary first (a permission request: the answers carry equal weight).
  public var stackedButtons: Bool
  /// The primary is a neutral pill, not the mustard one: the dialog does not steer toward it.
  public var neutralPrimary: Bool
  /// Escape closes the dialog without an answer (`DialogPanel.onDismiss`), not as Cancel.
  public var escapeDismisses: Bool
  /// Seconds after the dialog appears in which button presses and Return are ignored; 0: none.
  public var inputProtection: TimeInterval

  public init(title: String, icon: Icon = .none, iconPlacement: IconPlacement = .beside, subtitle: String? = nil,
              paragraphs: [Paragraph] = [], listHeading: String? = nil, listItems: [String] = [],
              footerLink: String? = nil, footerLinkIsDestructive: Bool = false, primaryTitle: String, secondaryTitle: String? = nil,
              cancelTitle: String? = nil, defaultButton: DefaultButton = .primary, isDestructive: Bool = false,
              escapeAnswersCancel: Bool = true, primaryHelp: String? = nil, width: CGFloat = 420,
              input: Input? = nil, bodyMaxHeight: CGFloat? = nil, stackedButtons: Bool = false,
              neutralPrimary: Bool = false, escapeDismisses: Bool = false, inputProtection: TimeInterval = 0) {
    self.title = title
    self.icon = icon
    self.iconPlacement = iconPlacement
    self.subtitle = subtitle
    self.paragraphs = paragraphs
    self.listHeading = listHeading
    self.listItems = listItems
    self.footerLink = footerLink
    self.footerLinkIsDestructive = footerLinkIsDestructive
    self.primaryTitle = primaryTitle
    self.secondaryTitle = secondaryTitle
    self.cancelTitle = cancelTitle
    // A destructive primary never takes Return (section 3.2).
    self.defaultButton = isDestructive && defaultButton == .primary ? .none : defaultButton
    self.isDestructive = isDestructive
    self.escapeAnswersCancel = escapeAnswersCancel
    self.primaryHelp = primaryHelp
    self.width = width
    self.input = input
    self.bodyMaxHeight = bodyMaxHeight
    self.stackedButtons = stackedButtons
    self.neutralPrimary = neutralPrimary
    self.escapeDismisses = escapeDismisses
    self.inputProtection = inputProtection
  }

  /// What VoiceOver speaks when the dialog appears: the title, then the list as items ("example.com wants to: Use your
  /// camera, Use your microphone"); the title alone when there is no list.
  public var announcement: String {
    listItems.isEmpty ? title : "\(title): \(listItems.joined(separator: ", "))"
  }

  /// The body as VoiceOver describes the dialog: the paragraphs in order, then the list heading and its items, which
  /// are separated by commas so they do not run into one sentence.
  public var accessibilityDescription: String {
    var parts = paragraphs.map(\.text)
    if let listHeading { parts.append(listHeading) }
    if !listItems.isEmpty { parts.append(listItems.joined(separator: ", ")) }
    return parts.joined(separator: " ")
  }
}

// MARK: - Launch alerts (section 3.4)

extension DialogContent {
  /// The launch failed: Try Again (Return), Quit, and Show Data Folder as the footer link (decision 4). `errorCode`
  /// is the error's type and code, never a path.
  public static func launchFailure(errorCode: String) -> DialogContent {
    DialogContent(title: "Arkt couldn't open its data", icon: .appIcon, iconPlacement: .stacked,
                  paragraphs: [.init("Nothing was changed. Try again, or show the data folder."),
                               .init("Error: \(errorCode)", secondary: true)],
                  footerLink: "Show Data Folder", primaryTitle: "Try Again", cancelTitle: "Quit",
                  defaultButton: .primary, escapeAnswersCancel: false)
  }

  /// The data was written by a newer Arkt: Quit only.
  public static let newerSchema = DialogContent(
    title: "This data was saved by a newer version of Arkt", icon: .appIcon, iconPlacement: .stacked,
    paragraphs: [.init("Update Arkt to open it. Nothing was changed.")], primaryTitle: "Quit",
    defaultButton: .primary, escapeAnswersCancel: false)
}

// MARK: - Crash report ask (#129)

extension DialogContent {
  /// The one-time ask on the launch after a crash, with the switch off: Send (Return) opens the report as a GitHub
  /// issue once, Always Send turns the switch on, Don't Send (Escape) deletes the report. Every answer ends the ask.
  public static let crashReportAsk = DialogContent(
    title: "Arkt quit unexpectedly. Send a report?", icon: .appIcon, iconPlacement: .stacked,
    paragraphs: [
      .init("The report has no web addresses, page titles, file paths or names. "
        + "Nothing is sent until you review it in your browser."),
      .init("You can change this in Settings, under Privacy.", secondary: true),
    ],
    primaryTitle: "Send", secondaryTitle: "Always Send", cancelTitle: "Don't Send",
    defaultButton: .primary, escapeAnswersCancel: true)
}

// MARK: - Quit warning (#487, BH-177)

extension DialogContent {
  /// Cmd-Q while "Warn before quitting" is on: Quit (Return) continues, Cancel (Escape) leaves the app running.
  public static let quitWarning = DialogContent(
    title: "Quit Arkt?", icon: .appIcon, iconPlacement: .stacked,
    paragraphs: [.init("A window is still open.")],
    primaryTitle: "Quit", cancelTitle: "Cancel",
    defaultButton: .primary, escapeAnswersCancel: true)
}

// MARK: - Motion (section 7)

/// Dialog motion as data. AppKit animates the window sheet; the app-modal alert grows from its center on `firmFast`,
/// the anchored panel from its top-leading corner. Transform and opacity on the content layer only; Reduce Motion
/// keeps a 0.15 s fade.
public enum DialogMotion {
  public struct Step: Equatable, Sendable {
    public var scale: CGFloat
    /// Points down (positive) or up (negative) from the resting place, where the entrance starts.
    public var offsetY: CGFloat
    /// Nil: no transform motion.
    public var spring: SpringParameters?
    public var fadeDuration: CFTimeInterval
  }

  private static let reducedFade = Step(scale: 1, offsetY: 0, spring: nil, fadeDuration: 0.15)

  public static func alertIn(reduceMotion: Bool) -> Step {
    reduceMotion ? reducedFade
      : Step(scale: 0.96, offsetY: 0, spring: SpringPreset.firmFast.parameters, fadeDuration: 0.18)
  }

  public static func panelIn(reduceMotion: Bool) -> Step {
    reduceMotion ? reducedFade
      : Step(scale: 0.97, offsetY: -4, spring: SpringPreset.firmFast.parameters, fadeDuration: 0.16)
  }

  /// The panel's exit fade; 0 (instant) when the keyboard answered it or under Reduce Motion.
  public static func panelOut(keyboard: Bool, reduceMotion: Bool) -> CFTimeInterval {
    keyboard || reduceMotion ? 0 : 0.10
  }

  /// The layer transform that scales by `scale` about `pivot` (in the layer's bounds) and moves it `offsetY` points
  /// along its own y axis, for a layer whose anchor point is `layerAnchor`.
  public static func transform(scale: CGFloat, offsetY: CGFloat, about pivot: CGPoint, bounds: CGRect,
                               layerAnchor: CGPoint) -> CATransform3D {
    guard scale != 1 || offsetY != 0 else { return CATransform3DIdentity }
    let px = pivot.x - layerAnchor.x * bounds.width
    let py = pivot.y - layerAnchor.y * bounds.height
    var t = CATransform3DMakeTranslation(px, py + offsetY, 0)
    t = CATransform3DScale(t, scale, scale, 1)
    return CATransform3DTranslate(t, -px, -py, 0)
  }

  /// Strong ease-out (the design system's `cubic-bezier(0.23, 1, 0.32, 1)`).
  static var easeOut: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1) }
}
