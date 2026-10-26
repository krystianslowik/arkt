import AppKit
import EngineAPI

/// Visually borderless shell window. A real `.borderless` window would lose the traffic lights, key-window
/// behavior and resizing, so this is a titled, full-size-content window with a hidden, transparent titlebar
/// whose standard buttons are moved into the sidebar.
@MainActor
public final class ShellWindow: NSWindow {
  public var metrics = ShellMetrics.standard

  public init(contentRect: NSRect) {
    super.init(contentRect: contentRect,
               styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
               backing: .buffered, defer: false)
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = false   // window drags come from WindowDragView (sidebar, theme gaps)
    tabbingMode = .disallowed
    isReleasedWhenClosed = false
    minSize = NSSize(width: 640, height: 420)
    collectionBehavior.insert(.fullScreenPrimary)
    setAccessibilityIdentifier(AXID.Shell.window)
  }

  /// Where the traffic lights sit (#102): in the docked sidebar's top strip, in the hover-revealed overlay's (at its
  /// origin, faded with the reveal), or nowhere while the sidebar is hidden, so no buttons float over the page.
  /// PARITY(NEEDS-RUNTIME-CHECK RT-10): that Arc hides them with the sidebar.
  public enum TrafficLightPlacement: Equatable, Sendable {
    case sidebar
    case overlay(origin: CGPoint, alpha: CGFloat)
    case hidden
  }

  /// Set by the root view; applied by `layoutTrafficLights(sidebarWidth:)`.
  public var trafficLightPlacement = TrafficLightPlacement.sidebar

  /// Moves close/minimize/zoom so the close button's top-left sits at `metrics.trafficLightOrigin` from the top-left
  /// of the sidebar (window coordinates; the overlay's origin when it is revealed). AppKit resets these frames on
  /// several events; ShellRootView.layout() and the window controller call this again each time.
  ///
  /// The titlebar container is narrowed to the sidebar so it never sits over (and steals clicks from) the
  /// content card; it is never narrower than the three buttons, so they stay hit-testable. With the sidebar hidden
  /// and no overlay out it is zero wide and the buttons are hidden.
  public func layoutTrafficLights(sidebarWidth: CGFloat) {
    guard !styleMask.contains(.fullScreen) else { return }
    let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    guard let close = standardWindowButton(.closeButton),
          let titlebar = close.superview,                    // NSTitlebarView
          let container = titlebar.superview else { return } // NSTitlebarContainerView
    let (offset, shown, alpha): (CGPoint, Bool, CGFloat) = switch trafficLightPlacement {
    case .sidebar: (.zero, true, 1)
    case .overlay(let origin, let alpha): (origin, true, alpha)
    case .hidden: (.zero, false, 0)
    }
    let origin = metrics.trafficLightOrigin
    // As tall as the sidebar's traffic-light strip, so the sidebar URL bar below it keeps its clicks, and never
    // shorter than the buttons' bottom edge, so they stay hit-testable.
    let height = max(metrics.sidebarTopBarHeight, origin.y + close.frame.height) + offset.y
    let buttonsExtent = origin.x * 2 + CGFloat(kinds.count - 1) * metrics.trafficLightSpacing + close.frame.width
    let width = shown ? min(frame.width, offset.x + max(sidebarWidth, buttonsExtent)) : 0
    let containerFrame = NSRect(x: 0, y: frame.height - height, width: width, height: height)
    if container.frame != containerFrame { container.frame = containerFrame }
    var unhid = false
    for (index, kind) in kinds.enumerated() {
      guard let button = standardWindowButton(kind) else { continue }
      if button.isHidden == shown {
        button.isHidden = !shown
        unhid = unhid || shown
      }
      if button.alphaValue != alpha, shown { button.alphaValue = alpha }
      let x = offset.x + origin.x + CGFloat(index) * metrics.trafficLightSpacing
      let y = titlebar.bounds.height - offset.y - origin.y - button.frame.height   // titlebar view is not flipped
      let target = NSPoint(x: x, y: y)
      if button.frame.origin != target { button.setFrameOrigin(target) }
    }
    // Showing the buttons again makes AppKit put them back at its own titlebar positions in a later pass of a key
    // window; place them once more after it.
    if unhid {
      DispatchQueue.main.async { [weak self] in self?.layoutTrafficLights(sidebarWidth: sidebarWidth) }
    }
  }

  /// Sees key-down, flags-changed and mouse-down events before anything else in the window and returns true for the
  /// ones that must go no further: the Ctrl-Tab switcher (#103), which a page must never take.
  public var eventInterceptor: (@MainActor (NSEvent) -> Bool)?

  /// Mouse buttons 3 and 4 switch to the previous / next Space anywhere in the window (GS-002, BH-035, #98).
  public override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown:
      if eventInterceptor?(event) == true { return }
    default:
      break
    }
    if event.type == .otherMouseDown, event.buttonNumber == 3 || event.buttonNumber == 4 {
      otherMouseDown(with: event)
      return
    }
    super.sendEvent(event)
  }

  // MARK: Reserved keys (W3-8 step 3)

  /// The keys Arkt handles before the focused view. A web page takes every key equivalent first
  /// (`RenderWidgetHostViewCocoa`), so without this a page could swallow Cmd-W or Cmd-Q.
  public var reservedKeys = ReservedKeys.arkt

  /// A reserved key goes to the main menu first, before the view hierarchy; when the menu has no item for it, it goes
  /// the usual way. This is where Chromium reserves its own keys on macOS (the window's command dispatcher runs before
  /// the first responder), and it covers the FakeEngine build too.
  public override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if reservedKeys.matches(event), NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return true }
    return super.performKeyEquivalent(with: event)
  }

  // MARK: Engine commands (Decision 9)

  /// Where the engine's command selectors go: the window's host. Set by `ShellWindowController`.
  weak var commandHost: ShellEngineHost?

  /// Chromium's menu items and Arkt's page-command items: the sender's tag is the `EngineCommand` id.
  @objc public func commandDispatch(_ sender: Any?) {
    guard let command = Self.command(of: sender) else { return }
    commandHost?.dispatch(command, disposition: .currentTab)
  }

  /// As `commandDispatch(_:)`, with the disposition the current event's modifiers ask for (Back with Cmd opens a
  /// background tab, as in Chrome).
  @objc public func commandDispatchUsingKeyModifiers(_ sender: Any?) {
    guard let command = Self.command(of: sender) else { return }
    commandHost?.dispatch(command, disposition: Self.disposition(for: NSApp.currentEvent?.modifierFlags ?? []))
  }

  public override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    switch item.action {
    case #selector(commandDispatch(_:)), #selector(commandDispatchUsingKeyModifiers(_:)):
      guard let host = commandHost else { return false }
      return host.validate(EngineCommand(rawValue: item.tag))
    default:
      return super.validateUserInterfaceItem(item)
    }
  }

  private static func command(of sender: Any?) -> EngineCommand? {
    guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag else { return nil }
    return EngineCommand(rawValue: tag)
  }

  /// Chromium's `ui::DispositionFromEventFlags` for the flags a menu or key event can carry: Cmd opens a background
  /// tab, Cmd-Shift a foreground tab, Shift a new window; anything else stays in the current tab.
  static func disposition(for flags: NSEvent.ModifierFlags) -> EngineDisposition {
    let flags = flags.intersection([.command, .shift])
    switch flags {
    case [.command, .shift]: return .newForegroundTab
    case [.command]: return .newBackgroundTab
    case [.shift]: return .newWindow
    default: return .currentTab
    }
  }
}
