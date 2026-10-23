import CoreBridge
import Foundation
import Persistence

/// Where Arkt keeps its data and where Arc's data would be. Debug and Profile builds (`ARKT_SMOKE_BUILD`) accept
/// overrides so development and smoke runs never touch the real folders.
enum AppEnvironment {
  /// Arkt's data folder. `@concurrent`: `applicationSupport()` may create the folder, and the main thread never
  /// waits on disk.
  @concurrent
  static func databaseLocation() async throws -> DatabaseLocation {
    #if DEBUG || ARKT_SMOKE_BUILD
    if let path = ProcessInfo.processInfo.environment["ARKT_DATA_DIR"] {
      return DatabaseLocation(directory: URL(fileURLWithPath: path, isDirectory: true))
    }
    #endif
    return try .applicationSupport()
  }

  /// `<data folder>/Favicons` (decision 8). `@concurrent`: the store resolves symlinks on the disk. nil only if the
  /// folder were inside Arc's (never for Arkt's own data folder); favicons are then not persisted.
  @concurrent
  static func faviconStore(in location: DatabaseLocation) async -> FaviconStore? {
    try? FaviconStore(directory: location.directory.appendingPathComponent("Favicons", isDirectory: true))
  }

  /// Arc's data folder; read only after the user asks for an import. Debug and Profile builds may point it at a
  /// fixture copy.
  static var arcDirectory: URL {
    #if DEBUG || ARKT_SMOKE_BUILD
    if let path = ProcessInfo.processInfo.environment["ARKT_ARC_DIR"] {
      return URL(fileURLWithPath: path, isDirectory: true)
    }
    #endif
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Arc", isDirectory: true)
  }
}
