import Foundation

// MARK: - Identity

/// Identity of one download, issued by the engine. The Chromium engine uses the item's GUID
/// (`download::DownloadItem::GetGuid()`), which is stable across restarts; the in-process engines use a UUID string.
public struct DownloadID: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String
  public init(_ rawValue: String = UUID().uuidString) { self.rawValue = rawValue }
  public var description: String { rawValue }
}

// MARK: - Interrupt reasons

/// Why a download was interrupted. The raw value is Chromium's `download::DownloadInterruptReason`
/// (`components/download/public/common/download_interrupt_reason_values.h`), so the Chromium engine passes it through
/// unchanged and a value the shell does not name still round-trips. Every named constant is checked against the header
/// (EngineDownloadsTests).
public struct DownloadInterruptReason: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public var description: String { "DownloadInterruptReason(\(rawValue))" }

  /// `DOWNLOAD_INTERRUPT_REASON_FILE_FAILED`
  public static let fileFailed = DownloadInterruptReason(rawValue: 1)
  /// `DOWNLOAD_INTERRUPT_REASON_FILE_ACCESS_DENIED`
  public static let fileAccessDenied = DownloadInterruptReason(rawValue: 2)
  /// `DOWNLOAD_INTERRUPT_REASON_FILE_NO_SPACE`
  public static let fileNoSpace = DownloadInterruptReason(rawValue: 3)
  /// `DOWNLOAD_INTERRUPT_REASON_FILE_NAME_TOO_LONG`
  public static let fileNameTooLong = DownloadInterruptReason(rawValue: 5)
  /// `DOWNLOAD_INTERRUPT_REASON_FILE_TOO_LARGE`
  public static let fileTooLarge = DownloadInterruptReason(rawValue: 6)
  /// `DOWNLOAD_INTERRUPT_REASON_FILE_VIRUS_INFECTED`
  public static let fileVirusInfected = DownloadInterruptReason(rawValue: 7)
  /// `DOWNLOAD_INTERRUPT_REASON_FILE_TRANSIENT_ERROR`
  public static let fileTransientError = DownloadInterruptReason(rawValue: 10)
  /// `DOWNLOAD_INTERRUPT_REASON_FILE_BLOCKED`
  public static let fileBlocked = DownloadInterruptReason(rawValue: 11)
  /// `DOWNLOAD_INTERRUPT_REASON_FILE_SECURITY_CHECK_FAILED`
  public static let fileSecurityCheckFailed = DownloadInterruptReason(rawValue: 12)
  /// `DOWNLOAD_INTERRUPT_REASON_FILE_TOO_SHORT`
  public static let fileTooShort = DownloadInterruptReason(rawValue: 13)
  /// `DOWNLOAD_INTERRUPT_REASON_FILE_HASH_MISMATCH`
  public static let fileHashMismatch = DownloadInterruptReason(rawValue: 14)
  /// `DOWNLOAD_INTERRUPT_REASON_FILE_SAME_AS_SOURCE`
  public static let fileSameAsSource = DownloadInterruptReason(rawValue: 15)
  /// `DOWNLOAD_INTERRUPT_REASON_NETWORK_FAILED`
  public static let networkFailed = DownloadInterruptReason(rawValue: 20)
  /// `DOWNLOAD_INTERRUPT_REASON_NETWORK_TIMEOUT`
  public static let networkTimeout = DownloadInterruptReason(rawValue: 21)
  /// `DOWNLOAD_INTERRUPT_REASON_NETWORK_DISCONNECTED`
  public static let networkDisconnected = DownloadInterruptReason(rawValue: 22)
  /// `DOWNLOAD_INTERRUPT_REASON_NETWORK_SERVER_DOWN`
  public static let networkServerDown = DownloadInterruptReason(rawValue: 23)
  /// `DOWNLOAD_INTERRUPT_REASON_NETWORK_INVALID_REQUEST`
  public static let networkInvalidRequest = DownloadInterruptReason(rawValue: 24)
  /// `DOWNLOAD_INTERRUPT_REASON_SERVER_FAILED`
  public static let serverFailed = DownloadInterruptReason(rawValue: 30)
  /// `DOWNLOAD_INTERRUPT_REASON_SERVER_NO_RANGE`
  public static let serverNoRange = DownloadInterruptReason(rawValue: 31)
  /// `DOWNLOAD_INTERRUPT_REASON_SERVER_BAD_CONTENT`
  public static let serverBadContent = DownloadInterruptReason(rawValue: 33)
  /// `DOWNLOAD_INTERRUPT_REASON_SERVER_UNAUTHORIZED`
  public static let serverUnauthorized = DownloadInterruptReason(rawValue: 34)
  /// `DOWNLOAD_INTERRUPT_REASON_SERVER_CERT_PROBLEM`
  public static let serverCertProblem = DownloadInterruptReason(rawValue: 35)
  /// `DOWNLOAD_INTERRUPT_REASON_SERVER_FORBIDDEN`
  public static let serverForbidden = DownloadInterruptReason(rawValue: 36)
  /// `DOWNLOAD_INTERRUPT_REASON_SERVER_UNREACHABLE`
  public static let serverUnreachable = DownloadInterruptReason(rawValue: 37)
  /// `DOWNLOAD_INTERRUPT_REASON_SERVER_CONTENT_LENGTH_MISMATCH`
  public static let serverContentLengthMismatch = DownloadInterruptReason(rawValue: 38)
  /// `DOWNLOAD_INTERRUPT_REASON_SERVER_CROSS_ORIGIN_REDIRECT`
  public static let serverCrossOriginRedirect = DownloadInterruptReason(rawValue: 39)
  /// `DOWNLOAD_INTERRUPT_REASON_USER_CANCELED`
  public static let userCanceled = DownloadInterruptReason(rawValue: 40)
  /// `DOWNLOAD_INTERRUPT_REASON_USER_SHUTDOWN`
  public static let userShutdown = DownloadInterruptReason(rawValue: 41)
  /// `DOWNLOAD_INTERRUPT_REASON_CRASH`
  public static let crash = DownloadInterruptReason(rawValue: 50)
  /// `DOWNLOAD_INTERRUPT_REASON_LOCAL_DOWNLOAD_BLOCKED`
  public static let localDownloadBlocked = DownloadInterruptReason(rawValue: 51)

  /// Every named constant, for the id check.
  public static let all: [DownloadInterruptReason] = [
    .fileFailed, .fileAccessDenied, .fileNoSpace, .fileNameTooLong, .fileTooLarge, .fileVirusInfected,
    .fileTransientError, .fileBlocked, .fileSecurityCheckFailed, .fileTooShort, .fileHashMismatch, .fileSameAsSource,
    .networkFailed, .networkTimeout, .networkDisconnected, .networkServerDown, .networkInvalidRequest,
    .serverFailed, .serverNoRange, .serverBadContent, .serverUnauthorized, .serverCertProblem, .serverForbidden,
    .serverUnreachable, .serverContentLengthMismatch, .serverCrossOriginRedirect, .userCanceled, .userShutdown,
    .crash, .localDownloadBlocked,
  ]

  /// The words the Library and the popover show after "Failed", in the design's voice ("Failed, Connection lost").
  public var failureWords: String {
    switch self {
    case .networkFailed, .networkDisconnected, .networkTimeout: "Connection lost"
    case .networkServerDown, .serverUnreachable: "Server unreachable"
    case .fileNoSpace: "Not enough space"
    case .fileAccessDenied, .fileFailed, .fileTransientError, .fileNameTooLong: "Could not save the file"
    case .fileTooLarge: "File too large"
    case .fileBlocked, .fileSecurityCheckFailed, .fileVirusInfected, .localDownloadBlocked: "Blocked"
    case .serverUnauthorized, .serverForbidden: "Not allowed"
    case .serverCertProblem: "Certificate problem"
    case .userCanceled, .userShutdown: "Cancelled"
    default: "Interrupted"
    }
  }
}

// MARK: - Danger types

/// How dangerous the engine judged a download. The raw value is Chromium's `download::DownloadDangerType`
/// (`components/download/public/common/download_danger_type.h`); a value the shell does not name still round-trips.
public struct DownloadDangerType: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public var description: String { "DownloadDangerType(\(rawValue))" }

  /// `DOWNLOAD_DANGER_TYPE_NOT_DANGEROUS`
  public static let notDangerous = DownloadDangerType(rawValue: 0)
  /// `DOWNLOAD_DANGER_TYPE_DANGEROUS_FILE`
  public static let dangerousFile = DownloadDangerType(rawValue: 1)
  /// `DOWNLOAD_DANGER_TYPE_DANGEROUS_URL`
  public static let dangerousURL = DownloadDangerType(rawValue: 2)
  /// `DOWNLOAD_DANGER_TYPE_DANGEROUS_CONTENT`
  public static let dangerousContent = DownloadDangerType(rawValue: 3)
  /// `DOWNLOAD_DANGER_TYPE_MAYBE_DANGEROUS_CONTENT`
  public static let maybeDangerousContent = DownloadDangerType(rawValue: 4)
  /// `DOWNLOAD_DANGER_TYPE_UNCOMMON_CONTENT`
  public static let uncommonContent = DownloadDangerType(rawValue: 5)
  /// `DOWNLOAD_DANGER_TYPE_USER_VALIDATED`
  public static let userValidated = DownloadDangerType(rawValue: 6)
  /// `DOWNLOAD_DANGER_TYPE_DANGEROUS_HOST`
  public static let dangerousHost = DownloadDangerType(rawValue: 7)
  /// `DOWNLOAD_DANGER_TYPE_POTENTIALLY_UNWANTED`
  public static let potentiallyUnwanted = DownloadDangerType(rawValue: 8)
  /// `DOWNLOAD_DANGER_TYPE_ALLOWLISTED_BY_POLICY`
  public static let allowlistedByPolicy = DownloadDangerType(rawValue: 9)
  /// `DOWNLOAD_DANGER_TYPE_ASYNC_SCANNING`
  public static let asyncScanning = DownloadDangerType(rawValue: 10)
  /// `DOWNLOAD_DANGER_TYPE_BLOCKED_PASSWORD_PROTECTED`
  public static let blockedPasswordProtected = DownloadDangerType(rawValue: 11)
  /// `DOWNLOAD_DANGER_TYPE_BLOCKED_TOO_LARGE`
  public static let blockedTooLarge = DownloadDangerType(rawValue: 12)
  /// `DOWNLOAD_DANGER_TYPE_SENSITIVE_CONTENT_WARNING`
  public static let sensitiveContentWarning = DownloadDangerType(rawValue: 13)
  /// `DOWNLOAD_DANGER_TYPE_SENSITIVE_CONTENT_BLOCK`
  public static let sensitiveContentBlock = DownloadDangerType(rawValue: 14)
  /// `DOWNLOAD_DANGER_TYPE_DEEP_SCANNED_SAFE`
  public static let deepScannedSafe = DownloadDangerType(rawValue: 15)
  /// `DOWNLOAD_DANGER_TYPE_DEEP_SCANNED_OPENED_DANGEROUS`
  public static let deepScannedOpenedDangerous = DownloadDangerType(rawValue: 16)
  /// `DOWNLOAD_DANGER_TYPE_PROMPT_FOR_SCANNING`
  public static let promptForScanning = DownloadDangerType(rawValue: 17)
  /// `DOWNLOAD_DANGER_TYPE_DANGEROUS_ACCOUNT_COMPROMISE`
  public static let dangerousAccountCompromise = DownloadDangerType(rawValue: 19)
  /// `DOWNLOAD_DANGER_TYPE_PROMPT_FOR_LOCAL_PASSWORD_SCANNING`
  public static let promptForLocalPasswordScanning = DownloadDangerType(rawValue: 21)
  /// `DOWNLOAD_DANGER_TYPE_ASYNC_LOCAL_PASSWORD_SCANNING`
  public static let asyncLocalPasswordScanning = DownloadDangerType(rawValue: 22)
  /// `DOWNLOAD_DANGER_TYPE_DEEP_SCANNED_FAILED`
  public static let deepScannedFailed = DownloadDangerType(rawValue: 20)
  /// `DOWNLOAD_DANGER_TYPE_BLOCKED_SCAN_FAILED`
  public static let blockedScanFailed = DownloadDangerType(rawValue: 23)
  /// `DOWNLOAD_DANGER_TYPE_FORCE_SAVE_TO_GDRIVE`
  public static let forceSaveToGDrive = DownloadDangerType(rawValue: 24)
  /// `DOWNLOAD_DANGER_TYPE_FORCE_SAVE_TO_ONEDRIVE`
  public static let forceSaveToOneDrive = DownloadDangerType(rawValue: 25)

  /// Every named constant, for the id check.
  public static let all: [DownloadDangerType] = [
    .notDangerous, .dangerousFile, .dangerousURL, .dangerousContent, .maybeDangerousContent, .uncommonContent,
    .userValidated, .dangerousHost, .potentiallyUnwanted, .allowlistedByPolicy, .asyncScanning,
    .blockedPasswordProtected, .blockedTooLarge, .sensitiveContentWarning, .sensitiveContentBlock, .deepScannedSafe,
    .deepScannedOpenedDangerous, .promptForScanning, .dangerousAccountCompromise, .promptForLocalPasswordScanning,
    .asyncLocalPasswordScanning, .deepScannedFailed, .blockedScanFailed, .forceSaveToGDrive, .forceSaveToOneDrive,
  ]

  /// The file may be opened: only the types Chromium treats as safe or answered. Everything else, including a value
  /// this list does not name and a scan still running, is NOT openable (fail closed); an engine's Open gate is this
  /// allow-list, never "not held".
  public var canOpen: Bool {
    switch self {
    case .notDangerous, .userValidated, .allowlistedByPolicy, .deepScannedSafe: true
    default: false
    }
  }

  /// A verdict is still pending (an async scan): not safe, not yet a decision for the user.
  public var isScanning: Bool { self == .asyncScanning || self == .asyncLocalPasswordScanning }

  /// The file is held and never opened until the user answers (`DownloadItem::IsDangerous()`): Keep or Delete. Every
  /// type that is neither openable nor a pending scan, including a value this list does not name.
  public var isHeldForDecision: Bool { !canOpen && !isScanning }

  /// The engine refuses the file: the only answer is Delete (a policy, a failed scan or a forced upload), never Keep.
  public var isBlocked: Bool {
    switch self {
    case .blockedPasswordProtected, .blockedTooLarge, .sensitiveContentBlock, .blockedScanFailed,
         .forceSaveToGDrive, .forceSaveToOneDrive:
      true
    default:
      false
    }
  }

  /// Uncommon but not dangerous: a plain row note and Keep or Delete in the Library, with no sheet (design, Behavior).
  public var isUncommon: Bool { self == .uncommonContent }

  /// The dangerous-file sheet is shown (a held type that is not merely uncommon, or a blocked one).
  public var needsSheet: Bool { (isHeldForDecision && !isUncommon) || isBlocked }

  /// The user may answer Keep Anyway (`keepDangerous`).
  public var canKeep: Bool { isHeldForDecision && !isBlocked }
}

// MARK: - State

/// A download's state, mapping 1:1 to `download::DownloadItem`: `inProgress` is `IN_PROGRESS` and not `IsPaused()`,
/// `paused` is `IN_PROGRESS` with `IsPaused()`, `complete` is `COMPLETE`, `cancelled` is `CANCELLED`, and
/// `interrupted` is `INTERRUPTED` with `GetLastReason()`.
public enum DownloadState: Equatable, Sendable {
  case inProgress
  case paused
  case complete
  case cancelled
  case interrupted(DownloadInterruptReason)

  /// Bytes may still arrive.
  public var isActive: Bool { self == .inProgress || self == .paused }
  /// Nothing more happens to the file on its own (`DownloadItem::IsDone()`, plus an interruption).
  public var isFinished: Bool {
    switch self {
    case .complete, .cancelled, .interrupted: true
    case .inProgress, .paused: false
    }
  }
}

// MARK: - Item

/// One download as plain values (`download::DownloadItem`). Safe to hand to any layer.
public struct DownloadItem: Equatable, Sendable, Identifiable {
  public var id: DownloadID
  /// The final URL of the request (`GetURL()`).
  public var url: URL
  /// The name to show (`GetFileNameToReportUser()`).
  public var filename: String
  /// Where the file is or will be (`GetTargetFilePath()`); nil until the engine has chosen the target.
  public var targetPath: URL?
  /// The size when the server said (`GetTotalBytes()`); nil when unknown (Chromium reports 0).
  public var totalBytes: Int64?
  /// Bytes on disk so far (`GetReceivedBytes()`).
  public var receivedBytes: Int64
  public var state: DownloadState
  public var dangerType: DownloadDangerType
  public var mimeType: String
  /// `GetStartTime()`.
  public var startTime: Date
  /// `GetEndTime()`; nil while the download is active.
  public var endTime: Date?
  /// Bytes per second now (`CurrentSpeed()`); 0 when not moving.
  public var bytesPerSecond: Int64
  /// An interrupted download can continue where it stopped (`CanResume()`).
  public var canResume: Bool

  public init(id: DownloadID = DownloadID(), url: URL, filename: String, targetPath: URL? = nil,
              totalBytes: Int64? = nil, receivedBytes: Int64 = 0, state: DownloadState = .inProgress,
              dangerType: DownloadDangerType = .notDangerous, mimeType: String = "application/octet-stream",
              startTime: Date = Date(), endTime: Date? = nil, bytesPerSecond: Int64 = 0, canResume: Bool = false) {
    self.id = id; self.url = url; self.filename = filename; self.targetPath = targetPath
    self.totalBytes = totalBytes; self.receivedBytes = receivedBytes; self.state = state
    self.dangerType = dangerType; self.mimeType = mimeType; self.startTime = startTime; self.endTime = endTime
    self.bytesPerSecond = bytesPerSecond; self.canResume = canResume
  }

  /// 0 to 1, or nil when the total is unknown. Complete is 1 whatever the bytes say.
  public var fraction: Double? {
    if state == .complete { return 1 }
    guard let totalBytes, totalBytes > 0 else { return nil }
    return min(1, max(0, Double(receivedBytes) / Double(totalBytes)))
  }

  /// Whole seconds left at the current speed; nil when not moving, unknown or not in progress
  /// (`TimeRemaining()`).
  public var secondsRemaining: Int? {
    guard state == .inProgress, bytesPerSecond > 0, let totalBytes, totalBytes > receivedBytes else { return nil }
    let left = totalBytes - receivedBytes
    return Int((Double(left) / Double(bytesPerSecond)).rounded(.up))
  }

  /// The file is held for the user's decision.
  public var isHeldForDecision: Bool { dangerType.isHeldForDecision || dangerType.isBlocked }

  /// Open is allowed: complete, and a danger type that is safe or answered. The one gate every engine and the model use.
  public var canBeOpened: Bool { state == .complete && dangerType.canOpen }
}

// MARK: - Events and commands

/// A change to the download list, delivered on its own stream (`EngineDownloads.observeDownloads(_:)` ) in order, through
/// the same FIFO as tab and window events (contract rule 24).
public enum DownloadEvent: Equatable, Sendable {
  /// A download started or was found at launch (`DownloadManager::Observer::OnDownloadCreated`).
  case downloadCreated(DownloadItem)
  /// Any change to the item: bytes, speed, state, target, danger (`DownloadItem::Observer::OnDownloadUpdated`). Updates
  /// of a moving download may be coalesced; the received bytes never go backwards, and nothing follows a final state
  /// except the commands' own changes.
  case downloadUpdated(DownloadItem)
  /// The item left the list (`OnDownloadRemoved`); its file stays on disk unless it was discarded or cancelled.
  case downloadRemoved(DownloadID)

  public var downloadID: DownloadID {
    switch self {
    case .downloadCreated(let item), .downloadUpdated(let item): item.id
    case .downloadRemoved(let id): id
    }
  }
}

/// What the shell asks of a download. Each command is a no-op for an unknown id or a state it does not apply to.
public enum DownloadCommand: Equatable, Sendable {
  /// `DownloadItem::Cancel(true)`: an active download becomes `.cancelled`; its partial file is deleted.
  case cancel
  /// `DownloadItem::Pause()`: `.inProgress` becomes `.paused`.
  case pause
  /// `DownloadItem::Resume(true)`: `.paused` becomes `.inProgress`; an interrupted item with `canResume` continues.
  case resume
  /// `DownloadItem::OpenDownload()`: opens a complete file with its default app. Never opens a held file.
  case open
  /// `DownloadItem::ShowDownloadInShell()`: reveals the file in Finder.
  case showInFinder
  /// Starts the same URL again (`DownloadManager::DownloadUrl`; there is no `DownloadItem` counterpart). An item that
  /// `canResume` is resumed in place; for any other cancelled or interrupted item the engine starts a new download of
  /// the URL and removes the old item (`.downloadRemoved` for it, `.downloadCreated` for the new one), so a retry
  /// replaces its row.
  case retry
  /// `DownloadItem::ValidateDangerousDownload()`: the held file may proceed; `dangerType` becomes `.userValidated`.
  case keepDangerous
  /// Deletes the held file and removes the item (`DownloadItem::Remove()` after deleting the file).
  case discardDangerous
  /// `DownloadItem::Remove()`: drops the item from the list and keeps its file. An active download is cancelled first.
  case remove
}

// MARK: - Location

/// Where downloads go (BH-182): Chromium's `download.prompt_for_download` and `download.default_directory`.
public enum DownloadSavePreference: Equatable, Sendable {
  /// A save panel for each download (`prompt_for_download` true).
  case ask
  /// The folder, with no panel (`prompt_for_download` false, `default_directory`).
  case folder(URL)
}

/// A request for the user to choose where a file goes, raised in `.ask` mode.
public struct DownloadDestinationRequest: Equatable, Sendable {
  public var suggestedFilename: String
  /// The folder the panel opens in.
  public var directory: URL
  public init(suggestedFilename: String, directory: URL) {
    self.suggestedFilename = suggestedFilename; self.directory = directory
  }
}

/// Shows the save panel for `.ask` mode and answers the chosen file URL, or nil when the user cancels (the download is
/// then cancelled). Set by the shell; without one an `.ask` engine saves to the default folder.
public typealias DownloadDestinationChooser = @MainActor (DownloadDestinationRequest) async -> URL?

// MARK: - Protocol

/// Downloads, for engines that have them. A separate protocol, like `EngineExtensions`: the shell shows the Library
/// button's ring only when `engine is EngineDownloads`. Downloads belong to no tab, so their events have their own
/// stream, through the same FIFO as `EngineEvent` (contract rule 24).
///
/// Implementations: InMemoryEngine (scripted), FakeEngine (WKDownload; no pause, no danger judgement), ChromiumEngine
/// (wired to the profile's DownloadManager through the facade, #132).
@MainActor
public protocol EngineDownloads: AnyObject {
  /// The list in creation order; the newest is last.
  var downloads: [DownloadItem] { get }
  /// The item, nil once removed or for an unknown id.
  func download(_ id: DownloadID) -> DownloadItem?
  /// Ordered, main-thread delivery of every download event, with the same delivery rules as `observe`.
  func observeDownloads(_ handler: @escaping @MainActor (DownloadEvent) -> Void) -> EngineObservation
  /// Runs `command` on the download; a no-op when it does not apply (see `DownloadCommand`).
  func perform(_ command: DownloadCommand, on id: DownloadID)
  /// Starts a download of `url` (`DownloadManager::DownloadUrl`), as Save Link As does.
  func startDownload(from url: URL)
  /// Where files go. Setting it applies to downloads that start afterwards.
  var downloadSavePreference: DownloadSavePreference { get set }
  /// The save panel for `.ask` mode; nil: the engine saves to the default folder.
  var downloadDestinationChooser: DownloadDestinationChooser? { get set }
  /// The system Downloads folder (Chromium's `DownloadPrefs::DefaultDownloadDirectory`): where a download goes when
  /// the preferred folder is missing or not writable, and what the Settings pop-up calls "Downloads".
  var downloadDefaultFolder: URL { get }
}

extension EngineDownloads {
  public func download(_ id: DownloadID) -> DownloadItem? { downloads.first { $0.id == id } }
}

// MARK: - File names

/// A server-suggested file name reduced to one safe name for the download folder. Engines that choose the target
/// themselves (not from a save panel) run every suggestion through this.
public enum DownloadFilename {
  /// The last path component (either separator), without NULs or leading dots, never empty, ".", or "..": "download"
  /// stands in. The result never contains a separator, so `folder.appending(path:)` stays inside `folder`.
  public static func sanitized(_ suggested: String) -> String {
    let cleaned = suggested.replacingOccurrences(of: "\u{0}", with: "")
    let last = cleaned.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
    var name = last.trimmingCharacters(in: .whitespaces)
    while name.hasPrefix(".") { name.removeFirst() }
    name = name.trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? "download" : name
  }

  /// `file` is a direct child of `folder` (paths compared without trailing slashes).
  public static func isDirectChild(_ file: URL, of folder: URL) -> Bool {
    func normalized(_ url: URL) -> String {
      var path = url.standardizedFileURL.path(percentEncoded: false)
      while path.count > 1, path.hasSuffix("/") { path.removeLast() }
      return path
    }
    return normalized(file.deletingLastPathComponent()) == normalized(folder)
  }
}
