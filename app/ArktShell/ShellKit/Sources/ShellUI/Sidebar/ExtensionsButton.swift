import AppKit
import EngineAPI

/// The Extensions control in the sidebar's bottom bar, shown only for an engine that runs extensions
/// (`EngineExtensions`; week-3 Decision 10). A click opens a menu of the window's extension actions; choosing one
/// runs it, and the engine anchors the action's popup to this button. Disabled while the window has no actions.
///
/// A native menu, so no motion of its own: AppKit's menu appearance is the feedback, and nothing runs per frame.
@MainActor
public final class ExtensionsButton: NSButton {
  static let symbolName = "puzzlepiece.extension"
  /// Size of an action's icon in the menu: the toolbar icon's 16 pt.
  static let iconSize: CGFloat = 16

  /// The window's actions in toolbar order; set by the window controller.
  public var actions: [ExtensionAction] = [] {
    didSet {
      guard actions != oldValue else { return }
      isEnabled = !actions.isEmpty
      toolTip = actions.isEmpty ? "No Extensions" : "Extensions"   // [I] product wording
    }
  }
  /// Runs the action with this id (the window controller passes it to the engine with this button as anchor).
  public var onRun: (@MainActor (String) -> Void)?

  public init() {
    super.init(frame: .zero)
    isBordered = false
    bezelStyle = .regularSquare
    imagePosition = .imageOnly
    autoresizingMask = []
    isEnabled = false
    toolTip = "No Extensions"
    setAccessibilityLabel("Extensions")
    setAccessibilityIdentifierWithCell(AXID.Sidebar.extensions)
    target = self
    action = #selector(showActions(_:))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// One item per action, enabled as the engine reports it for the active tab.
  public func makeMenu() -> NSMenu {
    let menu = NSMenu(title: "Extensions")
    menu.autoenablesItems = false
    for action in actions {
      let item = NSMenuItem(title: action.name, action: #selector(runItem(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = action.id
      item.isEnabled = action.isEnabled
      item.image = action.iconPNG.flatMap(NSImage.init(data:)).map { image in
        image.size = NSSize(width: Self.iconSize, height: Self.iconSize)
        return image
      }
      menu.addItem(item)
    }
    return menu
  }

  /// The menu opens above the button, which sits at the bottom of the window.
  @objc private func showActions(_ sender: Any?) {
    guard !actions.isEmpty else { return }
    let menu = makeMenu()
    let gap: CGFloat = 4
    let top = isFlipped ? -menu.size.height - gap : bounds.height + menu.size.height + gap
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: top), in: self)
  }

  @objc func runItem(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    onRun?(id)
  }
}
