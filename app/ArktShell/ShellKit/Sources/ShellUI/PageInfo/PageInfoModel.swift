import AppKit
import EngineAPI
import Motion

/// The page info panel's measures (#582): `design/extensions` `surf-pageinfo`, laid out as the Site Control Center
/// direction A (`design/site-control-center`, #651) that grows from it, so its extra rows slot in without a new panel.
enum PageInfoMetrics {
  static let width: CGFloat = 330
  static let minWidth: CGFloat = 260
  static let maxHeight: CGFloat = 552
  static let minHeight: CGFloat = 120
  static let corner: CGFloat = 12
  /// From the window's edges, and between the address pill and the panel.
  static let windowMargin: CGFloat = 8
  static let gap: CGFloat = 6
  /// Header: 30 pt badge, padding 12 top / 14 sides / 10 bottom; host 13 semibold, connection line 12.
  static let badge: CGFloat = 30
  static let badgeCorner: CGFloat = 8
  static let headerTop: CGFloat = 12
  static let headerBottom: CGFloat = 10
  static let sideInset: CGFloat = 14
  static let headerTextGap: CGFloat = 10
  static let headerHeight: CGFloat = 54
  /// Rows: 32 pt, 16 pt glyph, a 22 pt pop-up with radius 6.
  static let rowHeight: CGFloat = 32
  /// A row with a note under its title ("Turned off in macOS", #786): the 17 pt title, 1 pt, the 14 pt note line.
  static let notedRowHeight: CGFloat = 44
  static let glyph: CGFloat = 16
  static let glyphGap: CGFloat = 12
  static let popUpHeight: CGFloat = 22
  static let popUpCorner: CGFloat = 6
  static let sectionPadding: CGFloat = 6
  static let sectionTitleHeight: CGFloat = 24
  static let footerHeight: CGFloat = 44
  /// The footer's quiet buttons sit this far in from the panel's edges.
  static let footerInset: CGFloat = 22
  static let readOnlyNoteHeight: CGFloat = 22
  static let noteBottom: CGFloat = 14
  /// The scrolling list's faded bottom edge.
  static let fade: CGFloat = 12
}

/// Motion: opacity 0 to 1, scale 0.97 to 1 and 4 pt down into place, 0.22 s on `firmFast`; Reduce Motion: the fade
/// alone, 0.15 s. Out: a 0.10 s fade, none from the keyboard or under Reduce Motion.
enum PageInfoMotion {
  static let appearDuration: CFTimeInterval = 0.22
  static let reducedAppearDuration: CFTimeInterval = 0.15
  static let exitDuration: CFTimeInterval = 0.10
  static let appearScale: CGFloat = 0.97
  static let appearOffset: CGFloat = -4
  static var firmFast: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.2, 1, 0.4, 1) }
  static var easeOut: CAMediaTimingFunction { MotionCurve.strongEaseOut.timingFunction }
}

/// What the page info panel shows for one page, as data (#582). Nil for a page of the browser itself: its address
/// pill is inert and nothing opens.
struct PageInfoModel: Equatable {
  enum State: Equatable {
    /// A site: the data row, the permissions and the footer.
    case site
    /// A local file: the header and one note.
    case localFile
  }

  /// One permission row: its glyph, the engine's title and a pop-up of the settings it offers. When macOS itself denies
  /// Arkt the permission, a note under the title says so (#786); the pop-up keeps the site's stored setting.
  struct Row: Equatable {
    struct Option: Equatable {
      var setting: PermissionSetting
      var title: String
    }
    var kind: SitePermissionKind
    var title: String
    var symbol: String
    var setting: PermissionSetting
    var options: [Option]
    /// Why macOS keeps the permission from every site: Arkt's own access denied (#786) or Location Services off for
    /// the whole Mac (#856). Nil otherwise, including while macOS has not decided (it still asks on first use).
    var systemBlock: SystemPermissionBlock?
    /// "Turned off in macOS" or "Location Services off", under the title; nil without a block.
    var systemNote: String? { systemBlock?.note }
    /// VoiceOver reads the pop-up as "Location, turned off in macOS, Allow, pop-up button".
    var accessibilityLabel: String {
      guard let systemBlock else { return title }
      return "\(title), \(systemBlock.spokenNote)"
    }
    var height: CGFloat { systemNote == nil ? PageInfoMetrics.rowHeight : PageInfoMetrics.notedRowHeight }

    init(_ permission: SitePermission, deniedInMacOS: SystemPermissionBlock? = nil) {
      kind = permission.kind
      title = permission.title
      symbol = PageInfoModel.symbol(for: permission.kind)
      setting = permission.setting
      options = permission.options.map { Option(setting: $0, title: PageInfoModel.title(of: $0)) }
      systemBlock = deniedInMacOS
    }
  }

  var tab: TabID
  var origin: String
  var host: String
  var state: State
  var connectionText: String
  var connectionSymbol: String
  /// The security state in a word or two, for VoiceOver on the address pill ("Not secure, example.com"). Nil for a
  /// secure page and a local file: VoiceOver then reads the address alone.
  var siteDescription: String?
  /// Anything but a secure connection: the line keeps the primary text color with a warning glyph (never red).
  var connectionIsWarning: Bool
  var note: String?
  var siteDataText: String
  var rows: [Row]
  var canResetPermissions: Bool
  /// A private window (Incognito, Blank): its settings are not the normal profile's and cannot be changed here yet
  /// (#557), so the pop-ups and Reset Permissions are off and `readOnlyNote` says why.
  var isReadOnly: Bool
  /// The page's favicon (PNG or ICO data) for the header badge; nil shows the site glyph.
  var favicon: Data?

  var accessibilityLabel: String { "Site controls for \(host)" }
  var readOnlyNote: String? { isReadOnly ? "Site settings can't be changed in this window." : nil }

  /// `deniedInMacOS`: the permissions macOS keeps from every site, and why (`SystemPermissions.blockedKinds()`); their
  /// rows get the note. Empty by default, so the address pill's reads never ask macOS.
  init?(_ info: PageInfo, locale: Locale = .current, isReadOnly: Bool = false, favicon: Data? = nil,
        deniedInMacOS: [SitePermissionKind: SystemPermissionBlock] = [:]) {
    tab = info.tab
    origin = info.origin
    // The engine's host in either form, written as the address bar writes it (#697); a local file's name as it is.
    host = info.connection == .localFile ? info.host : HostDisplay.text(forHost: info.host)
    connectionIsWarning = true
    note = nil
    siteDataText = ""
    rows = []
    canResetPermissions = false
    self.isReadOnly = isReadOnly
    self.favicon = favicon
    connectionSymbol = "exclamationmark.triangle"
    switch info.connection {
    case .internalPage:
      return nil
    case .localFile:
      state = .localFile
      connectionText = "Local file on this Mac"
      connectionSymbol = "doc"
      siteDescription = nil
      connectionIsWarning = false
      note = "Local files have no site settings."
      return
    case .secure:
      connectionText = "Connection is secure"
      connectionSymbol = "lock"
      siteDescription = nil
      connectionIsWarning = false
    case .notSecure:
      connectionText = "Not secure: this site has no encrypted connection"
      siteDescription = "Not secure"
    case .notFullySecure:
      connectionText = "Not fully secure: parts of this page are not encrypted"
      siteDescription = "Not fully secure"
    case .certificateError:
      connectionText = "Not secure: this site's connection is not private"
      siteDescription = "Not secure"
    case .flagged:
      connectionText = "Dangerous: this site may try to steal your information"
      siteDescription = "Dangerous"
    }
    state = .site
    siteDataText = info.siteData.map { Self.siteDataText($0, locale: locale) } ?? ""
    rows = info.permissions.map { Row($0, deniedInMacOS: deniedInMacOS[$0.kind]) }
    canResetPermissions = !isReadOnly && info.permissions.contains { !$0.isDefault }
  }

  /// The address pill's glyph and its spoken security state for a page: nil for a page of the browser itself, whose
  /// pill stays inert.
  static func pill(for info: PageInfo?) -> (symbol: String, description: String?)? {
    guard let info, let model = PageInfoModel(info) else { return nil }
    return (model.connectionSymbol, model.siteDescription)
  }

  // MARK: Words

  static func title(of setting: PermissionSetting) -> String {
    switch setting {
    case .allow: "Allow"
    case .ask: "Ask"
    case .block: "Block"
    }
  }

  /// "14 cookies, 2.4 MB"; either part alone when the other is zero; "None" when both are.
  static func siteDataText(_ data: SiteData, locale: Locale = .current) -> String {
    var parts: [String] = []
    if data.cookies > 0 {
      let count = data.cookies.formatted(.number.locale(locale))
      parts.append(data.cookies == 1 ? "1 cookie" : "\(count) cookies")
    }
    if data.bytes > 0 {
      parts.append(data.bytes.formatted(.byteCount(style: .file).locale(locale)))
    }
    return parts.isEmpty ? "None" : parts.joined(separator: ", ")
  }

  static func symbol(for kind: SitePermissionKind) -> String {
    switch kind {
    case .location: "location"
    case .camera: "video"
    case .microphone: "mic"
    case .notifications: "bell"
    case .popups: "macwindow"
    case .sound: "speaker.wave.2"
    case .javascript: "chevron.left.forwardslash.chevron.right"
    case .images: "photo"
    case .automaticDownloads: "arrow.down.to.line"
    case .clipboard: "clipboard"
    case .midiDevices: "pianokeys"
    case .motionSensors: "gyroscope"
    case .usbDevices: "cable.connector"
    case .serialPorts: "cable.connector.horizontal"
    case .hidDevices: "gamecontroller"
    case .bluetoothDevices: "antenna.radiowaves.left.and.right"
    case .fileEditing: "pencil"
    case .windowManagement: "macwindow.on.rectangle"
    case .localFonts: "textformat"
    case .idleDetection: "clock"
    case .backgroundSync: "arrow.triangle.2.circlepath"
    case .insecureContent: "exclamationmark.shield"
    }
  }

  // MARK: Size

  /// The design's 330 pt, narrower in a narrow window, never under 260.
  static func panelWidth(available: CGFloat) -> CGFloat {
    min(PageInfoMetrics.width, max(PageInfoMetrics.minWidth, available))
  }

  struct Height: Equatable {
    var height: CGFloat
    var scrolls: Bool
  }

  /// The content's height up to 552 pt and the room the window leaves, never under 120; past either the list scrolls.
  static func panelHeight(content: CGFloat, available: CGFloat) -> Height {
    let cap = max(PageInfoMetrics.minHeight, min(PageInfoMetrics.maxHeight, available))
    return Height(height: min(content, cap), scrolls: content > cap)
  }

  /// The content's height with a one-line connection; the view adds what a wrapped line takes.
  var contentHeight: CGFloat {
    let m = PageInfoMetrics.self
    switch state {
    case .localFile:
      return m.headerHeight + m.sectionPadding + 2 * 16 + m.noteBottom
    case .site:
      let dataSection = 1 + 2 * m.sectionPadding + m.rowHeight
      let list = rows.reduce(0) { $0 + $1.height }
      let readOnly = isReadOnly && !rows.isEmpty ? m.readOnlyNoteHeight : 0
      let permissions = rows.isEmpty ? 0 : 1 + m.sectionTitleHeight + readOnly + list + m.sectionPadding
      return m.headerHeight + dataSection + permissions + 1 + m.footerHeight
    }
  }
}
