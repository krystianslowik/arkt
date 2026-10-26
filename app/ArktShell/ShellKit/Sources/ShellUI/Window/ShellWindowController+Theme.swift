import AppKit
import Motion

/// Space themes as the window draws them (#410): the automatic contrast rule in the window's appearance, the theme
/// creator's live preview, and its `firm` crossfade while it is open.
extension ShellWindowController {
  func wireThemeDrawing() {
    let observer = ThemeContextObserver(window: window) { [weak self] context in
      self?.sidebarController.themeContext = context
    }
    themeContextObserver = observer
    sidebarController.themeContext = observer.context
    sidebarController.onThemePreview = { [weak self] index, theme in
      self?.rootView.themeBackground.previewTheme(theme, at: index)
    }
    sidebarController.onThemeCreatorChange = { [weak self] open in
      self?.rootView.themeBackground.crossfadeSpring = open ? SpringPreset.firm.parameters : nil
    }
  }

  /// One drawn theme per paged Space, so theme index == page index even if a Space lookup fails.
  func drawnThemes() -> [SpaceThemeInfo] {
    sidebarController.spaces.map {
      sidebarController.drawnSpace($0)?.theme ?? SpaceThemeInfo(baseColors: [.white(1)], isDark: false)
    }
  }

  /// The open theme creator's popover, if any (#410).
  public var themeCreatorView: NSView? { sidebarController.themeCreator?.view }
}
