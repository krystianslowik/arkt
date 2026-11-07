import Foundation

/// The neutral backdrop of a Blank or Incognito window (#766, design/private-pages, `prototype.html` `--theme-a` and
/// `--theme-b`). These windows show no Spaces, so they draw this in place of a Space theme, light or dark by the
/// window's appearance.
public enum PrivateBackdrop {
  /// The backdrop's stored colors for `appearance`. The window draws it through `ThemeContrast`, as a Space theme.
  public static func theme(for appearance: ThemeFlavor) -> SpaceThemeInfo {
    switch appearance {
    case .light: SpaceThemeInfo(baseColors: [.srgb(hex: 0xE7E6EA), .srgb(hex: 0xD6D5DB)], isDark: false)
    case .dark: SpaceThemeInfo(baseColors: [.srgb(hex: 0x34343B), .srgb(hex: 0x222227)], isDark: true)
    }
  }
}
