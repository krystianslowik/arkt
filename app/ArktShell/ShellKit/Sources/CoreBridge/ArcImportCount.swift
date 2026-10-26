import ArcImport
import Foundation
import SidebarModel

/// What the first run's count pass found: counts only, never a name, title, URL or path (decision 6d).
public struct ArcImportCounts: Equatable, Sendable {
  public var spaces: Int
  /// Tabs in the Spaces' pinned sections, nested folders and splits included.
  public var pinnedTabs: Int
  /// Top-level Favorites (tabs, folders and splits).
  public var favorites: Int
  /// Folders anywhere: pinned, Today and Favorites.
  public var folders: Int

  public init(spaces: Int = 0, pinnedTabs: Int = 0, favorites: Int = 0, folders: Int = 0) {
    self.spaces = spaces; self.pinnedTabs = pinnedTabs; self.favorites = favorites; self.folders = folders
  }
}

/// The read-only count pass of the first run (onboarding spec, section 15, item 1; decision 1): reads Arc's sidebar
/// file off the main actor the way the import does, builds the sidebar value and counts it. Nothing is written and
/// nothing is merged; the stream rises one Space at a time, then adds the Favorites, so the Import step's numbers
/// climb as the pass goes.
public enum ArcImportCounter {
  /// Cumulative counts, one per Space and a last one with the Favorites; throws when the sidebar file cannot be read
  /// or decoded. Cancelling the consumer cancels the read.
  public static func counts(_ files: ArcSourceFiles) -> AsyncThrowingStream<ArcImportCounts, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for update in try await read(files) {
            try Task.checkCancellation()
            continuation.yield(update)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  @concurrent
  static func read(_ files: ArcSourceFiles) async throws -> [ArcImportCounts] {
    let file = try ArcSidebarFile.decode(Data(contentsOf: files.sidebarFile))
    return count(try ArcSidebarImporter.makeSidebar(from: file).sidebar)
  }

  /// Cumulative counts over `sidebar`: after each Space in `spaceOrder`, then with the Favorites.
  public static func count(_ sidebar: SidebarModel.Sidebar) -> [ArcImportCounts] {
    var pinnedBySpace: [SpaceID: Int] = [:]
    var foldersBySpace: [SpaceID: Int] = [:]
    var favorites = 0
    var favoriteFolders = 0
    for node in sidebar.nodes.values {
      let section = Self.section(of: node.parent, in: sidebar)
      let isFolder: Bool
      if case .folder = node.kind { isFolder = true } else { isFolder = false }
      switch section {
      case .pinned(let space)?:
        if case .tab = node.kind { pinnedBySpace[space, default: 0] += 1 }
        if isFolder { foldersBySpace[space, default: 0] += 1 }
      case .today(let space)?:
        if isFolder { foldersBySpace[space, default: 0] += 1 }
      case .favorites?:
        if case .favorites = node.parent { favorites += 1 }
        if isFolder { favoriteFolders += 1 }
      default:
        break
      }
    }
    var running = ArcImportCounts()
    var updates: [ArcImportCounts] = []
    for space in sidebar.spaceOrder {
      running.spaces += 1
      running.pinnedTabs += pinnedBySpace[space] ?? 0
      running.folders += foldersBySpace[space] ?? 0
      updates.append(running)
    }
    running.favorites = favorites
    running.folders += favoriteFolders
    updates.append(running)
    return updates
  }

  /// The top-level section holding a node whose parent is `location`, through folders and splits.
  private static func section(of location: Location, in sidebar: SidebarModel.Sidebar) -> Location? {
    var current = location
    for _ in 0..<64 {                       // depth guard against a malformed file
      guard let container = current.containerNode else { return current }
      guard let parent = sidebar.nodes[container]?.parent else { return nil }
      current = parent
    }
    return nil
  }
}
