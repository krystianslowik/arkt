import Foundation
import ShellUI
import SidebarModel

/// Value mapping between Arkt's `SidebarModel` and the shell's `SidebarSource` vocabulary. Both modules declare
/// `SpaceID`, `NodeID` and `RGBA`; ids are plain `UUID`s here and colors are always module-qualified.
enum BridgeMapping {
  static func location(_ location: SidebarLocation) -> SidebarModel.Location {
    switch location {
    case .favorites(let profile): .favorites(profile: profile)
    case .pinned(let id): .pinned(id)
    case .today(let id): .today(id)
    case .folder(let id): .folder(id)
    case .split(let id): .split(id)
    }
  }

  static func location(_ location: SidebarModel.Location) -> SidebarLocation {
    switch location {
    case .favorites(let profile): .favorites(profile: profile)
    case .pinned(let id): .pinned(id)
    case .today(let id): .today(id)
    case .folder(let id): .folder(id)
    case .split(let id): .split(id)
    }
  }

  static func nodeInfo(_ node: SidebarModel.Node) -> SidebarNodeInfo {
    switch node.kind {
    case .tab(let tab): .tab(id: node.id, url: tab.url, title: tab.customTitle ?? tab.title)
    case .folder(let folder): .folder(id: node.id, title: folder.title)
    case .split(let split): .split(id: node.id, layout: layout(split))
    }
  }

  /// Factors pass through as stored, drift included; the split layout repairs them (decision 2).
  static func layout(_ split: SplitItem) -> SplitLayoutInfo {
    SplitLayoutInfo(orientation: orientation(split.orientation), widthFactors: split.widthFactors)
  }

  static func orientation(_ orientation: SidebarModel.Orientation) -> SplitOrientation {
    switch orientation {
    case .horizontal: .horizontal
    case .vertical: .vertical
    }
  }

  static func orientation(_ orientation: SplitOrientation) -> SidebarModel.Orientation {
    switch orientation {
    case .horizontal: .horizontal
    case .vertical: .vertical
    }
  }

  static func spaceInfo(_ space: SidebarModel.Space) -> SidebarSpaceInfo {
    SidebarSpaceInfo(id: space.id, title: space.title, profile: space.profile, theme: theme(space.theme))
  }

  static func theme(_ theme: SidebarModel.SpaceTheme?) -> SpaceThemeInfo {
    guard let theme, !theme.baseColors.isEmpty else { return .bridgeDefault }
    return SpaceThemeInfo(
      baseColors: theme.baseColors.map(rgba), overlayColors: theme.overlayColors.map(rgba), texture: theme.texture,
      // Arc's noiseFactor is not in the core model yet; a mid value until it is.
      noiseFactor: theme.texture == nil ? 0 : 0.5, isDark: theme.isDark)
  }

  /// Arc stores `extendedSRGB` components; values outside 0...1 are kept.
  static func rgba(_ color: SidebarModel.RGBA) -> ShellUI.RGBA {
    ShellUI.RGBA(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha, space: .sRGB)
  }
}

extension SpaceThemeInfo {
  /// Light neutral theme for Spaces without one (new Spaces, Arc Spaces with an unsupported theme).
  /// TODO(design): final colors.
  public static let bridgeDefault = SpaceThemeInfo(
    baseColors: [.p3(hex: 0xF2F0EE, alpha: 1), .p3(hex: 0xE4E1DD, alpha: 1)], isDark: false)
}
