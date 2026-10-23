import Archive
import CryptoKit
import Foundation
import SidebarModel

public struct ArchiveImportReport: Hashable, Sendable {
  /// Entries in the file, including undecodable ones.
  public var entries = 0
  public var imported = 0
  public var manual = 0
  public var auto = 0
  public var fromSpace = 0
  public var fromLittleArc = 0
  public var fromUnknown = 0
  public var skipped: [SkippedItem] = []
  public var warnings: [ImportWarning] = []

  public init(
    entries: Int = 0, imported: Int = 0, manual: Int = 0, auto: Int = 0, fromSpace: Int = 0, fromLittleArc: Int = 0,
    fromUnknown: Int = 0, skipped: [SkippedItem] = [], warnings: [ImportWarning] = []
  ) {
    self.entries = entries
    self.imported = imported
    self.manual = manual
    self.auto = auto
    self.fromSpace = fromSpace
    self.fromLittleArc = fromLittleArc
    self.fromUnknown = fromUnknown
    self.skipped = skipped
    self.warnings = warnings
  }
}

public struct ArcArchiveImportResult: Hashable, Sendable {
  /// Imported entries in file order.
  public var items: [ArchivedItem]
  public var report: ArchiveImportReport

  public init(items: [ArchivedItem], report: ArchiveImportReport) {
    self.items = items
    self.report = report
  }
}

/// Turns a decoded `StorableArchiveItems.json` into archive entries. Pure: reads nothing and writes nothing.
public enum ArcArchiveImporter {
  /// Accepts version 1 only (every Arc store is version 1).
  public static func checkVersion(_ file: ArcArchiveFile) throws {
    guard file.version == 1 else { throw ArcImportError.unsupportedVersion(file.version) }
  }

  /// Entries in file order. Ids reuse Arc's item UUIDs (a non-UUID key gets an id derived from it), so importing
  /// twice yields the same ids; store them with `ArchiveStore.add(_:onConflict: .keepExisting)` so a re-import
  /// leaves already stored entries unchanged. `spaceIDsByArcID` comes from `ArcImportResult`.
  /// Imported entries have no `section`: the archive file does not record it. Bad entries are skipped and reported.
  public static func makeItems(
    from file: ArcArchiveFile, spaceIDsByArcID: [String: SpaceID]
  ) -> ArcArchiveImportResult {
    var report = ArchiveImportReport()
    var items: [ArchivedItem] = []
    for pair in file.items.pairs {
      report.entries += 1
      let id = pair.key
      guard let entry = pair.value.value else {
        report.skipped.append(SkippedItem(itemID: id, reason: .decodeFailed(pair.value.failureReason ?? "unknown")))
        continue
      }
      let snapshot: NodeSnapshot
      do {
        guard let made = try makeSnapshot(entry, id: id, report: &report) else { continue }
        snapshot = made
      } catch {
        report.skipped.append(SkippedItem(itemID: id, reason: .decodeFailed(String(describing: error))))
        continue
      }

      let reason: ArchiveReason
      if let known = ArchiveReason(rawValue: entry.reason) {
        reason = known
      } else {
        reason = .manual
        report.warnings.append(.unsupportedValue(itemID: id, field: "reason"))
      }

      let source: ArchiveSource
      switch entry.source.caseName {
      case "space":
        if let arcSpace = try? entry.source.payload(String.self) {
          if let space = spaceIDsByArcID[arcSpace] {
            source = .space(space)
          } else {
            source = .unknown
            report.warnings.append(.archiveSpaceNotImported(itemID: id))
          }
        } else {
          source = .unknown  // no Space id to look up: a malformed payload, not a missing Space
          report.warnings.append(.unsupportedValue(itemID: id, field: "source"))
        }
      case "littleArc": source = .littleArc
      case "unknown": source = .unknown
      default:
        source = .unknown
        report.warnings.append(.unsupportedValue(itemID: id, field: "source"))
      }

      items.append(ArchivedItem(reason: reason, archivedAt: entry.archivedAt, source: source, snapshot: snapshot))
      report.imported += 1
      switch reason {
      case .manual: report.manual += 1
      case .auto: report.auto += 1
      }
      switch source {
      case .space: report.fromSpace += 1
      case .littleArc: report.fromLittleArc += 1
      case .unknown: report.fromUnknown += 1
      }
    }
    return ArcArchiveImportResult(items: items, report: report)
  }

  /// Tab -> tab; list -> folder (children are not in the archive file, so it is empty). Anything else is skipped.
  /// Returns nil when the entry was skipped (and reported); throws when its payload is malformed.
  static func makeSnapshot(
    _ entry: ArcArchivedItem, id: String, report: inout ArchiveImportReport
  ) throws -> NodeSnapshot? {
    let item = entry.sidebarItem
    let nodeID = nodeID(forArcID: id)
    let createdAt = item.createdAt ?? entry.archivedAt
    switch item.data.caseName {
    case "tab":
      guard let tab = try item.tabData else {
        // Unreachable while `tabData` keys off the same case name; reported rather than dropped silently.
        report.skipped.append(SkippedItem(itemID: id, reason: .unsupportedKind(item.data.caseName)))
        return nil
      }
      guard let url = URL(string: tab.savedURL), url.scheme != nil else {
        report.skipped.append(SkippedItem(itemID: id, reason: .invalidURL))
        return nil
      }
      let tabItem = TabItem(
        url: url, title: tab.savedTitle ?? "", customTitle: item.title, lastActiveAt: tab.timeLastActiveAt)
      return NodeSnapshot(id: nodeID, kind: .tab(tabItem), createdAt: createdAt)
    case "list":
      if !item.childrenIds.isEmpty {
        report.warnings.append(.archivedFolderChildrenDropped(itemID: id, count: item.childrenIds.count))
      }
      return NodeSnapshot(id: nodeID, kind: .folder(FolderItem(title: item.title ?? "Folder")), createdAt: createdAt)
    default:
      report.skipped.append(SkippedItem(itemID: id, reason: .unsupportedKind(item.data.caseName)))
      return nil
    }
  }

  /// Arc's UUID when the key is one; otherwise a UUID derived from the key's SHA-256, so it is stable across imports.
  static func nodeID(forArcID id: String) -> NodeID {
    if let uuid = UUID(uuidString: id) { return uuid }
    var bytes = Array(SHA256.hash(data: Data(id.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x80  // version 8: custom
    bytes[8] = (bytes[8] & 0x3F) | 0x80  // RFC 4122 variant
    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
  }
}
