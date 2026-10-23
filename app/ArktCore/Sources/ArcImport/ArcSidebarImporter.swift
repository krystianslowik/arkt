import Foundation
import SidebarModel

public enum ArcImportError: Error, Hashable, Sendable {
  /// The file has no `{"global": {}}` container, so there is nothing to import.
  case noGlobalContainer
  /// The file's `version` is not one this importer reads.
  case unsupportedVersion(Int)
}

/// Why an Arc item (or space) was not imported.
public enum SkipReason: Hashable, Sendable {
  /// The item's `data` case has no Arkt equivalent (for example `easel`, `arcDocument`).
  case unsupportedKind(String)
  /// The item or space failed to decode; the payload is the decoder's description.
  case decodeFailed(String)
  /// A tab whose `savedURL` is not an absolute URL.
  case invalidURL
  /// The item sits under a container that was itself skipped.
  case parentSkipped(parentID: String)
  /// A `childrenIds` (or root container) entry names an item that does not exist.
  case missingItem
  /// The Arkt model rejected the placement, for example a folder inside a split view.
  case notAllowedHere
  /// The item was already imported elsewhere in the tree (a repeated or cyclic reference).
  case duplicateReference
  /// The item is not reachable from any space or favorites root.
  case unreachable
}

public struct SkippedItem: Hashable, Sendable {
  public let itemID: String
  public let reason: SkipReason

  public init(itemID: String, reason: SkipReason) {
    self.itemID = itemID
    self.reason = reason
  }
}

/// Things that were imported, but not exactly as stored in Arc.
public enum ImportWarning: Hashable, Sendable {
  /// A profile other than `{"default": true}`; its spaces and favorites use this generated name.
  case unrecognizedProfile(String)
  /// The space's theme has a shape the importer does not know; the space was imported without a theme.
  case unsupportedTheme(spaceID: String)
  /// An item field had an unknown value and a default was used, for example an unknown split `layoutOrientation`.
  case unsupportedValue(itemID: String, field: String)
  /// An archived item's source Space was not imported; its source became unknown.
  case archiveSpaceNotImported(itemID: String)
  /// An archived folder (Arc `list`) named `count` children; the archive file holds no child items, so the folder
  /// was imported empty.
  case archivedFolderChildrenDropped(itemID: String, count: Int)
}

public struct ImportReport: Hashable, Sendable {
  public var spaces = 0
  public var tabs = 0
  public var folders = 0
  public var splits = 0
  public var skipped: [SkippedItem] = []
  public var warnings: [ImportWarning] = []

  public init() {}
}

public struct ArcImportResult: Hashable, Sendable {
  public var sidebar: Sidebar
  public var report: ImportReport
  /// The Arkt node created for each imported Arc item id. Root containers and skipped items have no entry.
  public var nodeIDsByArcID: [String: NodeID]
  /// The Arkt Space created for each imported Arc space id.
  public var spaceIDsByArcID: [String: SpaceID]

  public init(
    sidebar: Sidebar, report: ImportReport, nodeIDsByArcID: [String: NodeID], spaceIDsByArcID: [String: SpaceID] = [:]
  ) {
    self.sidebar = sidebar
    self.report = report
    self.nodeIDsByArcID = nodeIDsByArcID
    self.spaceIDsByArcID = spaceIDsByArcID
  }
}

/// Turns a decoded `StorableSidebar.json` into an Arkt `Sidebar`. Pure: reads nothing and writes nothing.
public enum ArcSidebarImporter {
  /// The creation date used for items that have none. Fixed, so imports are deterministic.
  public static let defaultFallbackCreatedAt = Date(timeIntervalSinceReferenceDate: 0)

  /// Builds the sidebar. Bad or unsupported items are skipped and listed in the report; only a file without a
  /// global container throws.
  public static func makeSidebar(
    from file: ArcSidebarFile,
    fallbackCreatedAt: Date = defaultFallbackCreatedAt
  ) throws -> ArcImportResult {
    guard let container = file.globalContainer else { throw ArcImportError.noGlobalContainer }
    var builder = Builder(container: container, fallbackCreatedAt: fallbackCreatedAt)
    builder.run()
    return ArcImportResult(
      sidebar: builder.sidebar, report: builder.report, nodeIDsByArcID: builder.nodeIDsByArcID,
      spaceIDsByArcID: builder.spaceIDsByArcID)
  }
}

private struct Builder {
  let container: ArcContainer
  let fallbackCreatedAt: Date
  var sidebar = Sidebar()
  var report = ImportReport()
  var nodeIDsByArcID: [String: NodeID] = [:]
  var spaceIDsByArcID: [String: SpaceID] = [:]
  /// Ids already placed or reported, so a repeated reference cannot import an item twice or loop.
  var visited: Set<String> = []
  var reportedProfiles: Set<String> = []

  init(container: ArcContainer, fallbackCreatedAt: Date) {
    self.container = container
    self.fallbackCreatedAt = fallbackCreatedAt
  }

  mutating func run() {
    for failure in container.itemFailures {
      skip(failure.id, .decodeFailed(failure.reason))
    }
    for pair in container.spaces.pairs {
      guard let space = pair.value.value else {
        skip(pair.key, .decodeFailed(pair.value.failureReason ?? "unknown"))
        continue
      }
      importSpace(space)
    }
    for pair in container.topAppsContainerIDs.pairs {
      importRoot(pair.value, into: .favorites(profile: profileName(pair.key)))
    }
    for id in container.items.pairs.map(\.key) where !visited.contains(id) {
      skip(id, .unreachable)
    }
  }

  // MARK: Spaces

  mutating func importSpace(_ space: ArcSpace) {
    let theme = Self.theme(from: space.customInfo)
    if theme == nil, Self.hasWindowTheme(space.customInfo) {
      report.warnings.append(.unsupportedTheme(spaceID: space.id))
    }
    let spaceID = sidebar.addSpace(title: space.title, profile: profileName(space.profile), theme: theme)
    spaceIDsByArcID[space.id] = spaceID
    report.spaces += 1
    let roots = Self.rootIDs(of: space)
    if let pinned = roots.pinned { importRoot(pinned, into: .pinned(spaceID)) }
    if let unpinned = roots.unpinned { importRoot(unpinned, into: .today(spaceID)) }
  }

  /// Pinned and unpinned root ids, per key from `newContainerIDs`, falling back to the legacy `containerIDs`.
  /// Among several unpinned keys the `shared` one wins. Nothing on the container items themselves is consulted.
  static func rootIDs(of space: ArcSpace) -> (pinned: String?, unpinned: String?) {
    let pairs = space.newContainerIDs?.pairs ?? []
    let pinned = pairs.first { $0.key.caseName == "pinned" }?.value
    let unpinnedPairs = pairs.filter { $0.key.caseName == "unpinned" }
    let shared = unpinnedPairs.first { (try? $0.key.payload(TaggedEnum.self))?.caseName == "shared" }
    let unpinned = (shared ?? unpinnedPairs.first)?.value
    return (pinned ?? space.containerIDs?["pinned"], unpinned ?? space.containerIDs?["unpinned"])
  }

  mutating func profileName(_ profile: JSONValue) -> String {
    if profile == .object(["default": .bool(true)]) { return "default" }
    let caseName: String
    if case .object(let fields) = profile, fields.count == 1, let key = fields.keys.first {
      caseName = key
    } else {
      caseName = "unknown"
    }
    let name = "profile-\(caseName)"
    if reportedProfiles.insert(name).inserted {
      report.warnings.append(.unrecognizedProfile(name))
    }
    return name
  }

  // MARK: Items

  /// Imports the children of a root container. The root itself becomes the section, not a node.
  mutating func importRoot(_ rootID: String, into location: Location) {
    guard !visited.contains(rootID) else {
      // Decode failures were reported up front; a decoded root seen twice is a repeated reference.
      if container.item(rootID) != nil { report.skipped.append(SkippedItem(itemID: rootID, reason: .duplicateReference)) }
      return
    }
    guard let root = container.item(rootID) else {
      skip(rootID, .missingItem)
      return
    }
    do {
      guard try root.containerType != nil else { return skipTree(root, .notAllowedHere) }
    } catch {
      return skipTree(root, .decodeFailed(String(describing: error)))
    }
    visited.insert(rootID)
    for child in root.childrenIds { importItem(child, into: location) }
  }

  mutating func importItem(_ id: String, into location: Location) {
    guard !visited.contains(id) else {
      // Decode failures were reported up front; anything else seen twice is a repeated reference.
      if container.items[id]?.value != nil { report.skipped.append(SkippedItem(itemID: id, reason: .duplicateReference)) }
      return
    }
    guard let item = container.item(id) else {
      skip(id, .missingItem)
      return
    }
    visited.insert(id)
    let createdAt = item.createdAt ?? fallbackCreatedAt
    do {
      switch item.data.caseName {
      case "tab":
        guard let tab = try item.tabData else { return }
        guard let url = URL(string: tab.savedURL), url.scheme != nil else {
          return skipTree(item, .invalidURL)
        }
        nodeIDsByArcID[id] = try sidebar.addTab(
          url: url, title: tab.savedTitle ?? "", customTitle: item.title, lastActiveAt: tab.timeLastActiveAt,
          in: location, createdAt: createdAt)
        report.tabs += 1
      case "list":
        let node = try sidebar.addFolder(title: item.title ?? "Folder", in: location, createdAt: createdAt)
        nodeIDsByArcID[id] = node
        report.folders += 1
        for child in item.childrenIds { importItem(child, into: .folder(node)) }
      case "splitView":
        guard let split = try item.splitViewData else { return }
        let orientation: Orientation
        switch split.layoutOrientation {
        case "horizontal": orientation = .horizontal
        case "vertical": orientation = .vertical
        default:
          orientation = .vertical
          report.warnings.append(.unsupportedValue(itemID: id, field: "layoutOrientation"))
        }
        let node = try sidebar.addSplit(
          orientation: orientation, widthFactors: split.itemWidthFactors, in: location, createdAt: createdAt)
        nodeIDsByArcID[id] = node
        report.splits += 1
        for child in item.childrenIds { importItem(child, into: .split(node)) }
      default:
        skipTree(item, .unsupportedKind(item.data.caseName))
      }
    } catch is SidebarError {
      skipTree(item, .notAllowedHere)
    } catch {
      skipTree(item, .decodeFailed(String(describing: error)))
    }
  }

  /// Reports `item` with `reason` and every descendant as `parentSkipped`, so nothing is lost silently.
  mutating func skipTree(_ item: ArcItem, _ reason: SkipReason) {
    visited.insert(item.id)
    report.skipped.append(SkippedItem(itemID: item.id, reason: reason))
    for child in item.childrenIds where !visited.contains(child) {
      if let childItem = container.item(child) {
        skipTree(childItem, .parentSkipped(parentID: item.id))
      } else {
        // Undecodable children are already visited (reported up front), so this one does not exist.
        skip(child, .missingItem)
      }
    }
  }

  mutating func skip(_ id: String, _ reason: SkipReason) {
    visited.insert(id)
    report.skipped.append(SkippedItem(itemID: id, reason: reason))
  }

  // MARK: Theme

  static func hasWindowTheme(_ customInfo: JSONValue?) -> Bool {
    customInfo?["windowTheme"] != nil
  }

  /// Reads `windowTheme.background.single._0`. Returns nil for any other shape.
  static func theme(from customInfo: JSONValue?) -> SpaceTheme? {
    guard let background = customInfo?["windowTheme"]?["background"]?["single"]?["_0"],
          let color = background["style"]?["color"]?["_0"] else { return nil }
    let isDark = background["contentOverBackgroundAppearance"] == .string("dark")
    if let gradient = color["blendedGradient"]?["_0"] {
      guard case .array(let base)? = gradient["baseColors"] else { return nil }
      let baseColors = base.compactMap(rgba)
      guard !baseColors.isEmpty, baseColors.count == base.count else { return nil }
      let overlay: [JSONValue]
      switch gradient["overlayColors"] {
      case nil: overlay = []
      case .array(let values)?: overlay = values
      default: return nil
      }
      let overlayColors = overlay.compactMap(rgba)
      guard overlayColors.count == overlay.count else { return nil }
      return SpaceTheme(baseColors: baseColors, overlayColors: overlayColors, texture: texture(gradient), isDark: isDark)
    }
    if let single = color["blendedSingleColor"]?["_0"] {
      guard let base = single["color"].flatMap(rgba) else { return nil }
      return SpaceTheme(baseColors: [base], texture: texture(single), isDark: isDark)
    }
    return nil
  }

  static func texture(_ body: JSONValue) -> String? {
    if case .string(let name)? = body["modifiers"]?["overlay"] { return name }
    return nil
  }

  static func rgba(_ value: JSONValue) -> RGBA? {
    guard let red = value["red"]?.double, let green = value["green"]?.double, let blue = value["blue"]?.double
    else { return nil }
    return RGBA(red: red, green: green, blue: blue, alpha: value["alpha"]?.double ?? 1)
  }
}

extension JSONValue {
  fileprivate subscript(key: String) -> JSONValue? {
    if case .object(let fields) = self { return fields[key] }
    return nil
  }

  /// Numbers written as `1.0` decode as `.int`, so both cases count.
  fileprivate var double: Double? {
    switch self {
    case .int(let value): Double(value)
    case .number(let value): value
    default: nil
    }
  }
}
