import CoreGraphics
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
    SidebarSpaceInfo(
      id: space.id, title: space.title, profile: space.profile, theme: theme(space.theme),
      usesDefaultTheme: usesDefaultTheme(space.theme), icon: icon(space.icon))
  }

  /// `theme(_:)` draws `bridgeDefault` for these.
  static func usesDefaultTheme(_ theme: SidebarModel.SpaceTheme?) -> Bool {
    theme?.baseColors.isEmpty ?? true
  }

  static func icon(_ icon: SidebarModel.SpaceIcon?) -> SpaceIconInfo? {
    switch icon {
    case nil: nil
    case .symbol(let name)?: .symbol(name)
    case .emoji(let emoji)?: .emoji(emoji)
    }
  }

  static func modelIcon(_ icon: SpaceIconInfo?) -> SidebarModel.SpaceIcon? {
    switch icon {
    case nil: nil
    case .symbol(let name)?: .symbol(name)
    case .emoji(let emoji)?: .emoji(emoji)
    }
  }

  /// Colors are stored as sRGB components (`modelColor`). `theme(_:)` reads them back as sRGB, and `noiseFactor` is
  /// not stored: a theme with no texture and sRGB colors round-trips equal, which is what the header menu's checkmark
  /// compares.
  static func modelTheme(_ theme: SpaceThemeInfo) -> SidebarModel.SpaceTheme {
    SidebarModel.SpaceTheme(
      baseColors: theme.baseColors.map(modelColor), overlayColors: theme.overlayColors.map(modelColor),
      texture: theme.texture, isDark: theme.isDark)
  }

  /// The model stores sRGB components and `rgba(_:)` reads them back as sRGB, so a Display P3 color is converted, not
  /// copied: copying P3 components would read back as a different (less saturated) color. Extended sRGB keeps a P3
  /// color outside the sRGB gamut as components outside 0...1, which Arc's stored themes also use.
  static func modelColor(_ color: ShellUI.RGBA) -> SidebarModel.RGBA {
    switch color.space {
    case .sRGB:
      return SidebarModel.RGBA(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    case .displayP3:
      guard let extendedSRGB = CGColorSpace(name: CGColorSpace.extendedSRGB),
            let converted = color.cgColor.converted(to: extendedSRGB, intent: .relativeColorimetric, options: nil),
            let c = converted.components, c.count == 4
      else { preconditionFailure("Display P3 always converts to extended sRGB") }
      return SidebarModel.RGBA(red: Double(c[0]), green: Double(c[1]), blue: Double(c[2]), alpha: Double(c[3]))
    }
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
