import ArcImport
import Foundation

// Read-only check of the Arc importer against a real StorableSidebar.json and, next to it,
// StorableArchiveItems.json. Reads those files and the favicon cache, writes nothing, and prints only counts and
// enum case names.

let arcDirectory = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent("Library/Application Support/Arc", isDirectory: true)
let sidebarURL = CommandLine.arguments.count > 1
  ? URL(fileURLWithPath: CommandLine.arguments[1])
  : arcDirectory.appendingPathComponent("StorableSidebar.json")
let faviconDirectory = sidebarURL.deletingLastPathComponent()
  .appendingPathComponent("SidebarItemsFaviconCache", isDirectory: true)

do {
  let file = try ArcSidebarFile.decode(Data(contentsOf: sidebarURL))
  let result = try ArcSidebarImporter.makeSidebar(from: file)

  // Coverage over the tabs that were actually imported, looked up by their Arc item id.
  let cache = ArcFaviconCache(directory: faviconDirectory)
  var coverage = ImportCheckSummary.FaviconCoverage(found: 0, missing: 0)
  for (arcID, nodeID) in result.nodeIDsByArcID {
    guard case .tab? = result.sidebar.nodes[nodeID]?.kind else { continue }
    if cache.pngData(forItemID: arcID) != nil { coverage.found += 1 } else { coverage.missing += 1 }
  }

  for line in ImportCheckSummary.lines(sidebar: result.sidebar, report: result.report, favicons: coverage) {
    print(line)
  }

  // Archive: optional, read-only, counts only. Reads one file next to the sidebar file; writes nothing.
  let archiveURL = sidebarURL.deletingLastPathComponent().appendingPathComponent("StorableArchiveItems.json")
  if FileManager.default.isReadableFile(atPath: archiveURL.path) {
    do {
      let archive = try ArcArchiveFile.decode(Data(contentsOf: archiveURL))
      try ArcArchiveImporter.checkVersion(archive)
      let imported = ArcArchiveImporter.makeItems(from: archive, spaceIDsByArcID: result.spaceIDsByArcID)
      for line in ArchiveCheckSummary.lines(report: imported.report) { print(line) }
    } catch {
      // Only the error's type and code, as below.
      print("archive error: \(type(of: error)) code \((error as NSError).code)")
    }
  } else {
    print("archive: not found")
  }
} catch {
  // Only the error's type and code: error descriptions can quote stored values or paths.
  print("error: \(type(of: error)) code \((error as NSError).code)")
  exit(1)
}
