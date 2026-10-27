import EngineAPI
import Foundation

/// Where downloads go (BH-182): ask for each file, or save straight to a folder. A nil folder is the engine's default
/// (Downloads).
public struct DownloadLocationSetting: Equatable, Sendable {
  public var asksWhereToSave: Bool
  public var folder: URL?

  public init(asksWhereToSave: Bool = false, folder: URL? = nil) {
    self.asksWhereToSave = asksWhereToSave
    self.folder = folder
  }

  /// The engine's preference for this setting.
  public func preference(defaultFolder: URL) -> DownloadSavePreference {
    asksWhereToSave ? .ask : .folder(folder ?? defaultFolder)
  }

  /// "Downloads", "Desktop" or the folder's own name: what the Library footer and the Settings pop-up call the place.
  public func placeName(defaultFolder: URL) -> String {
    asksWhereToSave ? "Ask Where to Save" : (folder ?? defaultFolder).lastPathComponent
  }
}

/// The two sections of the Library window's rail (KB-065): Downloads and History.
public enum LibrarySection: String, CaseIterable, Sendable {
  case downloads, history

  public var title: String {
    switch self {
    case .downloads: "Downloads"
    case .history: "History"
    }
  }

  public var symbolName: String {
    switch self {
    case .downloads: "arrow.down.to.line"
    case .history: "clock.arrow.circlepath"
    }
  }
}
